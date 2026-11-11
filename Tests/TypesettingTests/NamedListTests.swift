import AppKit
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Liste con un nome")
    struct NamedListTests {
        private func numberer(_ extra: [ListDefinition] = []) -> ListNumberer { ListNumberer(definitions: ListDefinition.builtIn + extra) }

        @Test("Le serie finite: asterischi e segni tipografici")
        func series() {
            #expect((1...3).map { ListCounter.asterisks.text(for: $0) } == ["*", "**", "***"])
            #expect((1...7).map { ListCounter.symbols.text(for: $0) } == ["*", "†", "‡", "§", "‖", "¶", "**"])
            #expect(ListCounter.asterisks.seriesLength == 3 && ListCounter.decimal.seriesLength == nil)
        }

        @Test("Gli esempi proseguono dopo il testo normale; gli elenchi comuni ripartono")
        func continuation() {
            var n = numberer()
            #expect(n.next("Examples")?.text == "(1)")
            n.interrupt()
            #expect(n.next("Examples")?.text == "(2)")
            #expect(n.next("Numbered List")?.text == "1.")
            #expect(n.next("Numbered List")?.text == "2.")
            n.interrupt()
            #expect(n.next("Numbered List")?.text == "1.")
            // Un esempio in mezzo interrompe l'elenco comune.
            #expect(n.next("Examples")?.text == "(3)")
            #expect(n.next("Numbered List")?.text == "1.")
            #expect(n.next("Inesistente") == nil)
        }

        @Test("Una lista riparte a ogni passo della sua lista superiore, e le voci interne non interrompono la superiore")
        func parent() {
            var n = numberer([ListDefinition(name: "Sottoelenco", counter: .lowerLetter, suffix: ")", parent: .list("Numbered List"))])
            #expect(n.next("Examples")?.text == "(1)")
            #expect(n.next("Subexamples")?.text == "a.")
            #expect(n.next("Subexamples")?.text == "b.")
            #expect(n.next("Examples")?.text == "(2)")
            #expect(n.next("Subexamples")?.text == "a.")
            #expect(n.next("Numbered List")?.text == "1.")
            #expect(n.next("Sottoelenco")?.text == "a)")
            #expect(n.next("Sottoelenco")?.text == "b)")
            #expect(n.next("Numbered List")?.text == "2.")
            #expect(n.next("Sottoelenco")?.text == "a)")
            // Dopo un'interruzione l'elenco riparte da 1, e il sottoelenco riconosce il passo nuovo.
            n.interrupt()
            #expect(n.next("Numbered List")?.text == "1.")
            #expect(n.next("Sottoelenco")?.text == "a)")
            #expect(n.depth(of: "Subexamples") == 1 && n.depth(of: "Examples") == 0)
        }

        @Test("Le note a simboli ripartono a ogni pagina")
        func page() {
            var n = numberer()
            n.setPage(1)
            #expect(n.next("Symbol Notes")?.text == "*")
            #expect(n.next("Symbol Notes")?.text == "†")
            n.setPage(2)
            #expect(n.next("Symbol Notes")?.text == "*")
        }

        @Test("Oltre l'ultimo simbolo: finché non è deciso il segno è provvisorio; poi vale la scelta fatta")
        func overflow() {
            func fourth(_ overflow: ListOverflow) -> ListMark? {
                var n = numberer([ListDefinition(name: "Asterischi", counter: .asterisks, continues: true, overflow: overflow)])
                for _ in 1...3 { _ = n.next("Asterischi") }
                return n.next("Asterischi")
            }
            #expect(fourth(.ask) == ListMark(text: "4", needsOverflowChoice: true, value: 4))
            #expect(fourth(.restart)?.text == "*")
            #expect(fourth(.double)?.text == "****")
            #expect(fourth(.numbers)?.text == "4")
            var n = numberer([ListDefinition(name: "Segni", counter: .symbols, continues: true, overflow: .double)])
            #expect((1...8).compactMap { _ in n.next("Segni")?.text } == ["*", "†", "‡", "§", "‖", "¶", "**", "††"])
        }

        @Test("Il numero della lista superiore davanti al proprio")
        func showsParent() {
            var n = numberer([ListDefinition(name: "Paragrafi", counter: .decimal, prefix: ".", parent: .list("Numbered List"), showsParent: true)])
            _ = n.next("Numbered List")
            _ = n.next("Numbered List")
            #expect(n.next("Paragrafi")?.text == "2.1")
            #expect(n.next("Paragrafi")?.text == "2.2")
        }

        // MARK: File

        @Test("Nel file: la sezione delle Liste, la Lista delle note, gli stili che danno una Lista e i paragrafi che la cambiano")
        func file() throws {
            let sheet = StyleSheet.builtIn
            let plain = sheet.resolveCharacter(paragraphStyle: "Example", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            func paragraph(_ text: String, style: String, list: ListItem?) -> Block {
                .paragraph(Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style), list: list, inlines: [.text(TextRun(text, style: plain))]))
            }
            let document = Document(styles: sheet, lists: ListDefinition.builtIn, noteList: "Symbol Notes", blocks: [
                paragraph("Primo esempio", style: "Example", list: ListItem(listName: "Examples")),
                paragraph("Esempio fuori lista", style: "Example", list: nil),
                paragraph("Esempio in un'altra lista", style: "Example", list: ListItem(listName: "Numbered List")),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains(" notes=\"Symbol Notes\">"))
            #expect(written.contains("""
            <lists>
            <list name="Numbered List" counter="1" suffix="."/>
            <list name="Examples" counter="1" prefix="(" suffix=")" continues="on"/>
            <list name="Subexamples" counter="a" suffix="." parent="Examples" continues="on"/>
            <list name="Notes" counter="1" continues="on"/>
            <list name="Symbol Notes" counter="†" parent="page" continues="on"/>
            </lists>
            """))
            #expect(written.contains("<style name=\"Example\" target=\"paragraph\" based-on=\"Body\" align=\"natural\" space-before=\"6\" space-after=\"6\" in-list=\"Examples\"/>"))
            #expect(written.contains("<p style=\"Example\">Primo esempio</p>"), "la Lista data dallo stile non si ripete")
            #expect(written.contains("<p style=\"Example\" in-list=\"\">Esempio fuori lista</p>"))
            #expect(written.contains("<p style=\"Example\" in-list=\"Numbered List\">"))
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("Errori nel file: Lista inesistente, superiore inesistente o circolare, note senza Lista")
        func errors() {
            func error(_ document: String, _ body: String) -> DocumentFormatError? {
                do { _ = try DocumentFormat.document(from: "<document version=\"18\" font=\"HoeflerText-Regular\" size=\"12\"\(document)>\n\(body)\n</document>"); return nil }
                catch { return error as? DocumentFormatError }
            }
            let lists = "<lists>\n<list name=\"A\" counter=\"1\"/>\n</lists>"
            #expect(error("", lists + "\n<p in-list=\"B\">x</p>") == .invalidValue(line: 5, attribute: "in-list", value: "B"))
            #expect(error("", "<lists>\n<list name=\"A\" counter=\"1\" parent=\"Z\"/>\n</lists>") == .invalidValue(line: 3, attribute: "parent", value: "Z"))
            #expect(error("", "<lists>\n<list name=\"A\" counter=\"1\" parent=\"B\"/>\n<list name=\"B\" counter=\"1\" parent=\"A\"/>\n</lists>") == .invalidValue(line: 3, attribute: "parent", value: "B"))
            #expect(error(" notes=\"Nessuna\"", lists) == .invalidValue(line: 1, attribute: "notes", value: "Nessuna"))
            #expect(error("", "<lists>\n<list name=\"A\" counter=\"x\"/>\n</lists>") == .invalidValue(line: 3, attribute: "counter", value: "x"))
        }
        // MARK: Pagina

        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit, lists: ListDefinition.builtIn)

        private func item(_ text: String, _ list: String?) -> Block {
            .paragraph(Paragraph(list: list.map { ListItem(listName: $0) }, inlines: [.text(TextRun(text, style: body))]))
        }

        @Test("Nella pagina, voci ed esempi prendono segno e rientro dalla loro Lista")
        func pageMarkers() throws {
            let blocks = [item("Uno", "Examples"), item("Due", "Examples"), item("Testo", nil), item("Tre", "Examples"), item("Primo", "Subexamples"),
                          item("Secondo", "Subexamples"), item("Voce", "Numbered List"), item("Voce", "Numbered List"), item("Ignota", "Nessuna")]
            let layout = PageLayout.layout(Document(lists: ListDefinition.builtIn, blocks: blocks).attributedString().text, options: options)
            let markers = layout.pages[0].markers
            let font = try TestFonts.hoefler(size: 12)
            #expect(markers.map { Shaper.glyphs(in: $0.line).map { Int($0.id) } } == ["(1)", "(2)", "(3)", "a.", "b.", "1.", "2."].map { Shaper.glyphIDs(for: $0, font: font) },
                    "gli esempi proseguono dopo il testo; una Lista che non c'è non dà segno")
            #expect(markers[3].origin.x > markers[2].origin.x + 20, "i sottoesempi rientrano di un livello")
            #expect(layout.listsNeedingOverflowChoice.isEmpty)
        }

        /// Un paragrafo con una nota, poi uno lungo più di una pagina con una nota in fondo.
        private func notesAcrossPages(noteList: String, lists: [ListDefinition] = ListDefinition.builtIn) -> DocumentLayout {
            let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
            let long = String(repeating: "parole che riempiono le righe ", count: 300)
            let document = Document(lists: lists, noteList: noteList, blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Inizio", style: body)), .floating(FloatingObject(runs: [TextRun("Prima.", style: small)])), .text(TextRun(".", style: body))])),
                .paragraph(Paragraph(inlines: [.text(TextRun(long + "ancora", style: body)), .floating(FloatingObject(runs: [TextRun("Seconda.", style: small)])), .text(TextRun(" fine.", style: body))])),
            ])
            var options = options
            options.lists = lists
            options.noteList = noteList
            return PageLayout.layout(document.attributedString().text, options: options)
        }

        @Test("Le note prendono il segno dalla Lista delle note; a simboli ripartono nella pagina dove sta il richiamo")
        func noteMarks() throws {
            let symbols = notesAcrossPages(noteList: "Symbol Notes")
            #expect(symbols.pages.count == 2)
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: symbols)))
            let first = try #require(pdf.page(at: 0)?.string), second = try #require(pdf.page(at: 1)?.string)
            #expect(first.contains("Inizio*.") && first.contains("* Prima."), "i simboli restano a corpo pieno")
            // Il secondo paragrafo comincia nella prima pagina, ma la sua nota sta nella seconda: riparte da «*».
            #expect(second.contains("ancora* fine.") && second.contains("* Seconda."))
            #expect(!second.contains("\u{2020}"))

            let decimal = notesAcrossPages(noteList: "Notes")
            let text = try #require(PDFDocument(data: PDFRenderer.pdfData(for: decimal))?.string)
            #expect(text.contains("\u{B9} Prima.") && text.contains("\u{B2} Seconda."), "le note numerate proseguono da una pagina all'altra")
        }

        @Test("Una Lista delle note che va oltre l'ultimo simbolo senza una scelta lo segnala")
        func overflowReported() {
            func layout(_ overflow: ListOverflow) -> DocumentLayout {
                let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
                let inlines: [Inline] = (1...4).flatMap { n in [.text(TextRun("Testo \(n)", style: body)), .floating(FloatingObject(runs: [TextRun("Nota.", style: small)]))] }
                let lists = [ListDefinition(name: "Asterischi", counter: .asterisks, continues: true, overflow: overflow)]
                var options = options
                options.lists = lists
                options.noteList = "Asterischi"
                return PageLayout.layout(Document(lists: lists, noteList: "Asterischi", blocks: [.paragraph(Paragraph(inlines: inlines))]).attributedString().text, options: options)
            }
            #expect(layout(.ask).listsNeedingOverflowChoice == ["Asterischi"])
            #expect(layout(.restart).listsNeedingOverflowChoice.isEmpty)
        }

        @Test("Un segno tipografico come richiamo resta com'è; una lettera va in apice")
        func symbolReference() throws {
            let font = try TestFonts.hoefler(size: 12)
            let mark = PageLayout.referenceMark("\u{2020}", attributes: [.font: font])
            #expect(mark.string == "\u{2020}" && (mark.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font)
            let letter = PageLayout.referenceMark("a", attributes: [.font: font])
            #expect(letter.string == "a" && ((letter.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) != font || letter.attribute(NSAttributedString.Key(kCTBaselineOffsetAttributeName as String), at: 0, effectiveRange: nil) != nil))
        }

        @Test("Cambiando lo stile di un paragrafo cambia anche la Lista che lo stile dà, ma non una scelta a mano")
        func restyleList() {
            let sheet = StyleSheet.builtIn
            let text = NSMutableAttributedString(attributedString: Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(styleName: "Body", inlines: [.text(TextRun("Uno", style: body))])),
                .paragraph(Paragraph(styleName: "Body", list: ListItem(listName: "Numbered List"), inlines: [.text(TextRun("Due", style: body))])),
            ]).attributedString().text)
            func list(at index: Int) -> String? { text.attribute(.listItem, at: index, effectiveRange: nil) as? String }
            TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: sheet, to: sheet) { $0.paragraph = "Example" }
            #expect(list(at: 0) == "@Examples" && list(at: 3) == "@Examples")
            #expect(list(at: 4) == "@Numbered List")
            TextStyling.restyle(text, range: NSRange(location: 0, length: 4), from: sheet, to: sheet) { $0.paragraph = "Body" }
            #expect(list(at: 0) == nil)
        }
        @Test("Una Lista rinominata o tolta: le voci e gli stili la seguono")
        func renaming() {
            let text = NSMutableAttributedString(attributedString: Document(lists: ListDefinition.builtIn, blocks: [
                item("Uno", "Examples"), item("Due", "Numbered List"), item("Tre", nil),
            ]).attributedString().text)
            TextStyling.renameLists(in: text, ["Examples": "Frasi", "Numbered List": nil])
            #expect(text.attribute(.listItem, at: 0, effectiveRange: nil) as? String == "@Frasi")
            #expect(text.attribute(.listItem, at: 4, effectiveRange: nil) == nil)
            let sheet = StyleSheet.builtIn.renamingLists(["Examples": "Frasi", "Subexamples": nil])
            #expect(sheet.style(named: "Example")?.values.listName == "Frasi")
            #expect(sheet.style(named: "Subexample")?.values.listName == nil)
        }
        @Test("Aggiornare uno stile dalla selezione conserva la sua Lista (errore segnalato il 16 ottobre)")
        func updateKeepsList() throws {
            let sheet = StyleSheet.builtIn
            let plain = sheet.resolveCharacter(paragraphStyle: "Example", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            let text = NSMutableAttributedString(attributedString: Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(styleName: "Example", style: sheet.resolveParagraph(styleName: "Example"), list: ListItem(listName: "Examples"),
                                     inlines: [.text(TextRun("Esempio 1234", style: plain))])),
            ]).attributedString().text)
            // Le cifre alte al posto di quelle basse, solo in questo paragrafo, come nella segnalazione.
            TextStyling.updateFeatures(in: text, range: NSRange(location: 0, length: text.length), ofFontNamed: "HoeflerText-Regular") { _ in [.aat(type: 21, selector: 1)] }
            let values = TextStyling.styleValues(from: text, at: 0, target: .paragraph, sheet: sheet, basedOn: "Body")
            #expect(values.listName == "Examples")
            var updated = sheet
            let index = try #require(updated.styles.firstIndex { $0.name == "Example" })
            updated.styles[index].values = values
            TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: sheet, to: updated)
            #expect(text.attribute(.listItem, at: 0, effectiveRange: nil) as? String == "@Examples", "la numerazione resta")
            // «Nessuna Lista» in uno stile si salva e si rilegge.
            var none = updated
            none.styles[index].values.listName = ""
            let document = Document(styles: none, lists: ListDefinition.builtIn, blocks: [])
            #expect(try DocumentFormat.document(from: DocumentFormat.string(for: document)).styles.style(named: "Example")?.values.listName == "")
        }
    }
}

// MARK: - Misure delle voci (tappa I.3a)

extension TypesettingSuite {
    @Suite("Misure delle voci di elenco")
    struct ListMeasureTests {
        private func run(_ text: String, size: Double = 12) -> Inline { .text(TextRun(text, style: CharacterStyle(fontName: "HoeflerText-Regular", size: size))) }

        /// Dove comincia il testo della prima riga di ogni paragrafo, e dove finisce il segno, dal bordo della colonna.
        private func geometry(_ document: Document) -> [(text: CGFloat, markerEnd: CGFloat?)] {
            let layout = PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
            let page = layout.pages[0]
            let left = layout.setup.textRect.minX
            var seen: Set<Int> = []
            return page.lines.compactMap { line -> (CGFloat, CGFloat?)? in
                guard seen.insert(line.paragraphLocation).inserted else { return nil }
                let marker = page.markers.first { $0.paragraphLocation == line.paragraphLocation }
                let end = marker.map { $0.origin.x - left + CGFloat(CTLineGetTypographicBounds($0.line, nil, nil, nil)) }
                return (line.origin.x - left, end)
            }
        }

        @Test("Valori iniziali: 24 pt per livello, il segno 6 pt prima del testo; fissi anche in un corpo diverso")
        func defaults() throws {
            let document = Document(blocks: [
                .paragraph(Paragraph(list: ListItem(marker: "1."), inlines: [run("Primo livello.")])),
                .paragraph(Paragraph(list: ListItem(marker: "a)", level: 2), inlines: [run("Secondo livello.")])),
                .paragraph(Paragraph(list: ListItem(marker: "1."), inlines: [run("Corpo grande.", size: 20)])),
            ])
            let g = geometry(document)
            #expect(abs(g[0].text - 24) < 0.5 && abs(g[0].markerEnd! - 18) < 0.5)
            #expect(abs(g[1].text - 48) < 0.5)
            #expect(abs(g[2].text - 24) < 0.5, "non più proporzionale al corpo")
        }

        @Test("Le misure della Lista valgono per tutte le sue voci; quelle della voce valgono sopra; segno e testo sono indipendenti")
        func listAndItemMeasures() throws {
            var lists = ListDefinition.builtIn
            let index = try #require(lists.firstIndex { $0.name == "Examples" })
            lists[index].textIndent = 40
            lists[index].markerPosition = 30
            var own = ListItem(listName: "Examples")
            own.textIndent = 60
            let document = Document(lists: lists, blocks: [
                .paragraph(Paragraph(list: ListItem(listName: "Examples"), inlines: [run("Primo esempio.")])),
                .paragraph(Paragraph(list: own, inlines: [run("Secondo, spostato a mano.")])),
            ])
            let g = geometry(document)
            #expect(abs(g[0].text - 40) < 0.5 && abs(g[0].markerEnd! - 30) < 0.5)
            #expect(abs(g[1].text - 60) < 0.5 && abs(g[1].markerEnd! - 30) < 0.5, "spostando il testo della voce, il segno resta alla posizione della Lista")
        }

        @Test("Nel file e nel testo: list-indent e list-marker sulla voce, indent e marker sulla Lista")
        func file() throws {
            var lists = ListDefinition.builtIn
            lists[0].textIndent = 30
            lists[0].markerPosition = 22
            var item = ListItem(marker: "•", level: 2)
            item.textIndent = 36
            item.markerPosition = 30
            let document = Document(lists: lists, blocks: [.paragraph(Paragraph(list: item, inlines: [run("Voce.")]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("list=\"•\" level=\"2\" list-indent=\"36\" list-marker=\"30\""))
            #expect(written.contains("indent=\"30\" marker=\"22\""))
            // La forma di un giorno solo, con la distanza fra segno e testo: si legge convertendola.
            let legacy = written.replacingOccurrences(of: "indent=\"30\" marker=\"22\"", with: "indent=\"30\" gap=\"8\"")
            #expect(try DocumentFormat.document(from: legacy).lists[0].markerPosition == 22)
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(ListItem(encoded: item.encoded) == item)
            #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly) == document)
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: written.replacingOccurrences(of: "list-indent=\"36\"", with: "list-indent=\"tanto\"")) }
        }
    }
}
