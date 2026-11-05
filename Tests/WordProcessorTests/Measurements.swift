import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Misure di velocità su un documento lungo. Girano solo a richiesta: `WP_MISURE=1 swift test --filter Measurements`.
@Suite("Misure", .serialized, .enabled(if: ProcessInfo.processInfo.environment["WP_MISURE"] != nil)) @MainActor
struct Measurements {
    /// Circa 100 pagine: 700 paragrafi di circa 560 caratteri.
    static func longParagraphs() -> [String] {
        let sentence = "La composizione tipografica di un documento lungo mette alla prova il programma: ogni tasto deve rispondere subito, anche quando il testo occupa molte pagine e contiene parole lunghe come internazionalizzazione o precipitevolissimevolmente. "
        return (0..<700).map { index in "\(index + 1). " + String(repeating: sentence, count: 2) + sentence.prefix(80) }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    @Test("Documento di circa 100 pagine: cambiare uno stile dalla scheda Stili")
    func styleChangeOnLongDocument() {
        let clock = ContinuousClock()
        let h = EditorHarness(paragraphs: Self.longParagraphs())
        defer { h.close() }
        h.editor.showDefinitions(.styles)
        h.step()
        let tab = h.editor.stylesTab
        tab.selection = "Body"
        var totals: [Double] = [], layouts: [Double] = []
        for size in [13.0, 12.0, 13.0, 12.0, 13.0] {
            totals.append(milliseconds(clock.measure {
                tab.inspector.change(.size) { $0.size = size }
                h.editor.flushStyleChanges()
            }))
            layouts.append(milliseconds(clock.measure { h.editor.layoutPages() }))
            h.step()
        }
        // Una raffica (come trascinando nel pannello dei colori): ogni cambio va in attesa; poi una sola applicazione.
        var queued: [Double] = []
        for size in stride(from: 12.0, through: 16.0, by: 0.5) {
            queued.append(milliseconds(clock.measure { tab.inspector.change(.size) { $0.size = size } }))
        }
        let flush = milliseconds(clock.measure { h.editor.flushStyleChanges() })
        print("MISURA stile: pagine \(h.editor.currentLayout()?.pages.count ?? 0); cambio di corpo applicato subito (restyle + composizione) mediana \(median(totals)) ms \(totals.map { Int($0) }); sola composizione di nuovo \(median(layouts)) ms; raffica di \(queued.count) cambi: in attesa mediana \(median(queued)) ms ciascuno, poi un'applicazione \(Int(flush)) ms")
    }

    @Test("Documento di circa 100 pagine: composizione completa e tempo di un tasto")
    func longDocument() {
        let clock = ContinuousClock()
        var h: EditorHarness!
        let open = clock.measure { h = EditorHarness(paragraphs: Self.longParagraphs()) }
        defer { h.close() }
        let layout = h.editor.currentLayout()
        let characters = h.text.utf16.count

        // Il motore da solo: composizione a freddo (cache vuote) e di nuovo, a caldo.
        let text = h.editor.editingText
        let options = h.editor.currentDocument().layoutOptions
        let cold = clock.measure { _ = PageLayout.layout(text, options: options) }
        let warm = clock.measure { _ = PageLayout.layout(text, options: options) }

        // Un tasto a metà documento: l'inserimento (deposito, riparazioni, ricomposizione) e poi di nuovo la ricomposizione.
        var inserts: [Double] = [], layouts: [Double] = []
        h.select(characters / 2)
        for _ in 0..<9 {
            inserts.append(milliseconds(clock.measure { h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange) }))
            layouts.append(milliseconds(clock.measure { h.editor.layoutPages() }))
            h.step()
        }
        // Il deposito della fase 4: lo stesso testo, un tasto a metà, e la composizione letta da lui.
        let store = DocumentStore(text: text)
        let storeUndo = UndoManager()
        store.undoManager = storeUndo
        var storeInserts: [Double] = []
        for index in 0..<9 {
            store.breakUndoCoalescing()
            storeInserts.append(milliseconds(clock.measure { store.replaceCharacters(in: NSRange(location: characters / 2 + index, length: 0), with: "x") }))
        }
        let storeLayout = clock.measure { _ = PageLayout.layout(store, options: options) }
        // Con due regole: una sulle prime parole di ogni paragrafo, una su tutte le parole (sigle).
        h.editor.changeRules([TextRule(target: .firstWords(2), paragraphStyle: "Body", styleName: "Small Caps"),
                              TextRule(target: .words(.capitals), styleName: "Small Caps")], styles: h.editor.styleSheet)
        var ruleLayouts: [Double] = []
        for _ in 0..<5 {
            h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange)
            ruleLayouts.append(milliseconds(clock.measure { h.editor.layoutPages() }))
            h.step()
        }
        // Con la prima riga in maiuscoletto in ogni paragrafo: composta insieme agli a capo.
        // (Cambiare le regole ricompone già tutto: si misura quello.)
        let firstLineOpen = clock.measure {
            h.editor.changeRules([TextRule(target: .firstLines(1), paragraphStyle: "Body", styleName: "Small Caps")], styles: h.editor.styleSheet)
        }
        let styledFirstLines = h.editor.currentLayout()?.pages.flatMap(\.lines).filter { placed in
            guard let run = (CTLineGetGlyphRuns(placed.line) as? [CTRun])?.first else { return false }
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            return FontFeatures.settings(of: font).contains(.aat(type: 3, selector: 3))
        }.count ?? 0
        var lineLayouts: [Double] = []
        for _ in 0..<5 {
            h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange)
            lineLayouts.append(milliseconds(clock.measure { h.editor.layoutPages() }))
            h.step()
        }
        // Con una regola che dipende dalla composizione: i paragrafi di una riga centrati (ogni paragrafo si controlla).
        var centeredStyles = h.editor.styleSheet
        centeredStyles.styles += StyleSheet.ruleStyles.filter { $0.name == "Centered" && centeredStyles.style(named: $0.name) == nil }
        h.editor.changeRules([TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centered")], styles: centeredStyles)
        var conditionLayouts: [Double] = []
        for _ in 0..<5 {
            h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange)
            conditionLayouts.append(milliseconds(clock.measure { h.editor.layoutPages() }))
            h.step()
        }
        // Con i segni della provenienza accesi (e la regola della condizione): ricomposizione e segni dopo un tasto.
        h.editor.setInterfaceMode(.advanced)
        h.editor.toggleProvenanceMarks(nil)
        var markLayouts: [Double] = []
        for _ in 0..<5 {
            h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange)
            markLayouts.append(milliseconds(clock.measure {
                h.editor.layoutPages()
                h.editor.refreshProvenanceMarks()
            }))
            h.step()
        }
        h.editor.toggleProvenanceMarks(nil)
        let report = """
            MISURE · \(characters) caratteri, \(layout?.pages.count ?? 0) pagine
            apertura (testo nel deposito, prima composizione, ispettore): \(String(format: "%.0f", milliseconds(open))) ms
            composizione completa con le righe già in memoria: \(String(format: "%.0f", milliseconds(cold))) ms · di nuovo: \(String(format: "%.0f", milliseconds(warm))) ms
            un tasto, mediana di 9: inserimento \(String(format: "%.1f", median(inserts))) ms + ricomposizione \(String(format: "%.0f", median(layouts))) ms
            con due regole (prime parole, sigle): ricomposizione dopo un tasto \(String(format: "%.0f", median(ruleLayouts))) ms
            prima riga in maiuscoletto in ogni paragrafo (\(styledFirstLines) righe): cambio delle regole \(String(format: "%.0f", milliseconds(firstLineOpen))) ms · dopo un tasto \(String(format: "%.0f", median(lineLayouts))) ms
            con una condizione (una riga → centrato): ricomposizione dopo un tasto \(String(format: "%.0f", median(conditionLayouts))) ms
            con i segni della provenienza accesi: composizione e segni insieme \(String(format: "%.0f", median(markLayouts))) ms
            deposito, con annullamento: un tasto \(String(format: "%.2f", median(storeInserts))) ms · composizione letta dal deposito \(String(format: "%.0f", milliseconds(storeLayout))) ms
            """
        print(report)
        #expect((layout?.pages.count ?? 0) >= 80)
    }

    /// Circa 100 pagine con un titolo ogni dieci paragrafi e una nota ogni cinque; `keeping` accende la tenuta negli stili
    /// (righe minime 2 e 2 nel testo, titoli col seguente).
    static func keepingDocument(keeping: Bool) throws -> Typesetting.Document {
        let sentence = "La composizione tipografica di un documento lungo mette alla prova il programma, pagina dopo pagina, riga dopo riga. "
        var xml = """
            <document version="1" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Testo" target="paragraph" align="justified" first-indent="14"\(keeping ? " orphan-lines=\"2\" widow-lines=\"2\"" : "")/>
            <style name="Titolo" target="paragraph" based-on="Testo" size="14" align="left" first-indent="0" space-before="14" space-after="4"\(keeping ? " keep-with-next=\"on\"" : "")/>
            </styles>

            """
        for index in 0..<1000 {
            if index % 10 == 0 { xml += "<p style=\"Titolo\">Parte \(index / 10 + 1)</p>\n" }
            let note = index % 5 == 2 ? "<note>Una nota a piè di pagina, abbastanza lunga da occupare più di una riga in fondo alla pagina.</note>" : ""
            xml += "<p style=\"Body\">\(index + 1). " + String(repeating: sentence, count: 2 + index % 4) + note + "</p>\n"
        }
        return try DocumentFormat.document(from: xml + "</document>")
    }

    @Test("Documento di circa 100 pagine con titoli e note: composizione e tasto, senza e con la tenuta delle righe")
    func lineKeeping() throws {
        let clock = ContinuousClock()
        var lines: [String] = []
        for keeping in [false, true] {
            let h = EditorHarness(paragraphs: ["x"])
            defer { h.close() }
            h.editor.replaceContent(try Self.keepingDocument(keeping: keeping))
            h.step()
            let text = h.editor.editingText
            let options = h.editor.currentDocument().layoutOptions
            var engine: [Double] = []
            for _ in 0..<5 { engine.append(milliseconds(clock.measure { _ = PageLayout.layout(text, options: options) })) }
            let layout = PageLayout.layout(text, options: options)
            // Le pagine che finiscono con un titolo, e quelle che cominciano o finiscono con una sola riga di un paragrafo spezzato.
            let string = text.string as NSString
            let titleBottoms = layout.pages.filter { page in
                page.lines.last(where: { !$0.isNote }).map { string.substring(with: NSRange(location: $0.paragraphLocation, length: 5)) == "Parte" } ?? false
            }.count
            var single = 0
            for (index, page) in layout.pages.enumerated() where index + 1 < layout.pages.count {
                let body = page.lines.filter { !$0.isNote }, next = layout.pages[index + 1].lines.filter { !$0.isNote }
                guard let last = body.last, let first = next.first, last.paragraphLocation == first.paragraphLocation else { continue }
                if body.filter({ $0.paragraphLocation == last.paragraphLocation }).count == 1 { single += 1 }
                if next.filter({ $0.paragraphLocation == first.paragraphLocation }).count == 1 { single += 1 }
            }
            h.select(text.length / 2)
            var keys: [Double] = []
            for _ in 0..<9 {
                h.editor.pagesInsert("x", replacementRange: h.editor.pagesSelectedRange)
                keys.append(milliseconds(clock.measure { h.editor.layoutPages() }))
                h.step()
            }
            lines.append("\(keeping ? "con" : "senza") tenuta: \(layout.pages.count) pagine; composizione del motore mediana \(Int(median(engine))) ms \(engine.map { Int($0) }); ricomposizione dopo un tasto mediana \(Int(median(keys))) ms; pagine che finiscono con un titolo \(titleBottoms), righe sole in fondo o in cima \(single)")
        }
        print("MISURA tenuta delle righe:\n" + lines.joined(separator: "\n"))
    }

    @Test("Documento birmano composto con Graphite: prima composizione e di nuovo")
    func graphiteDocument() {
        let clock = ContinuousClock()
        let font = CTFontCreateWithName("Padauk-Regular" as CFString, 12, nil) as NSFont
        let sentence = "မြန်မာစာ သည် မြန်မာနိုင်ငံ ၏ ရုံးသုံး ဘာသာစကား ဖြစ်သည်။ "
        let text = NSMutableAttributedString()
        for _ in 0..<300 { text.append(NSAttributedString(string: String(repeating: sentence, count: 6) + "\n", attributes: [.font: font, .graphite: ""])) }
        let plain = NSMutableAttributedString(attributedString: text)
        plain.removeAttribute(.graphite, range: NSRange(location: 0, length: plain.length))
        var pages = 0
        let first = clock.measure { pages = PageLayout.layout(text).pages.count }
        let again = clock.measure { _ = PageLayout.layout(text) }
        let coreText = clock.measure { _ = PageLayout.layout(plain) }
        print("MISURA Graphite: \(text.length) caratteri, \(pages) pagine; prima composizione \(Int(milliseconds(first))) ms, di nuovo \(Int(milliseconds(again))) ms; lo stesso testo con Core Text \(Int(milliseconds(coreText))) ms")
    }
}
