import AppKit
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Flottanti: stili e numerazione")
    struct FloatStyleTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)

        @Test("La Lista delle note è la Lista dello stile «Nota a piè di pagina»")
        func noteListIsTheFootnoteStyleList() {
            var document = Document(lists: ListDefinition.builtIn, noteList: "Symbol Notes")
            #expect(document.floatStyles == [FloatStyle.footnote(listName: "Symbol Notes")])
            document.noteList = "Notes"
            #expect(document.floatStyles.first?.listName == "Notes")
            #expect(document.layoutOptions.floatStyles == document.floatStyles)
        }

        @Test("Lo stile del flottante viaggia con il testo e torna nel modello; il file non cambia")
        func styleRoundTrip() throws {
            let note = FloatingObject(runs: [TextRun("Una nota.", style: small)])
            #expect(note.style == FloatStyle.footnoteName)
            let document = Document(lists: ListDefinition.builtIn, noteList: "Notes", blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: body)), .floating(note)])),
            ])
            let text = document.attributedString().text
            #expect(text.attribute(.footnote, at: 5, effectiveRange: nil) as? String == FloatStyle.footnoteName)
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("notes=\"Notes\"") && written.contains("<note"), "nel file resta <note>")
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("Ogni flottante si numera con la Lista del suo stile")
        func numberingByStyle() throws {
            let document = Document(lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Uno", style: body)), .floating(FloatingObject(runs: [TextRun("prima", style: small)])),
                    .text(TextRun(" due", style: body)), .floating(FloatingObject(runs: [TextRun("seconda", style: small)], style: "Altro")),
                ])),
            ])
            let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lists: ListDefinition.builtIn,
                                        floatStyles: [.footnote(listName: "Notes"), FloatStyle(name: "Altro", listName: "Symbol Notes")])
            let layout = PageLayout.layout(document.attributedString().text, options: options)
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.string)
            #expect(pdf.contains("\u{B9} prima") && pdf.contains("* seconda"), "la nota numera 1, l'altro stile con i simboli")
        }
        // MARK: Stili modificabili (tappa 5.2)

        private var curator: FloatStyle { FloatStyle(name: "Note del curatore", listName: "Notes", reference: .plain, showsRule: false, canSplit: false) }

        private func document(_ inlines: [Inline], styles: [FloatStyle]) -> Document {
            var document = Document(styles: .builtIn, lists: ListDefinition.builtIn, noteList: "Symbol Notes", blocks: [.paragraph(Paragraph(inlines: inlines))])
            for style in styles where style.name != FloatStyle.footnoteName { document.floatStyles.append(style) }
            return document
        }

        @Test("Nel file: la sezione degli stili di flottante e le note di un'altra serie; un documento normale non cambia")
        func fileFormat() throws {
            var authorStyle = FloatStyle.footnote(listName: "Symbol Notes")
            authorStyle.ruleLength = 100
            authorStyle.contentStyle = "Quotation"
            var doc = document([.text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun("dell'autore", style: small)])),
                                .text(TextRun(" altro", style: body)), .floating(FloatingObject(runs: [TextRun("del curatore", style: small)], style: "Note del curatore"))],
                               styles: [curator])
            doc.floatStyles[0] = authorStyle
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<float-style name=\"Footnote\" list=\"Symbol Notes\" rule-length=\"100\" content=\"Quotation\"/>"))
            #expect(written.contains("<float-style name=\"Note del curatore\" list=\"Notes\" reference=\"plain\" rule=\"off\" split=\"off\"/>"))
            #expect(written.contains("<note style=\"Note del curatore\""))
            #expect(try DocumentFormat.document(from: written) == doc)
            #expect(!DocumentFormat.string(for: Document(lists: ListDefinition.builtIn, noteList: "Notes")).contains("float-styles"))
        }

        @Test("Errori nel file: serie inesistente, stile del contenuto che non è di paragrafo, Lista inesistente")
        func fileErrors() {
            func error(_ body: String) -> DocumentFormatError? {
                do { _ = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\n\(body)\n</document>"); return nil }
                catch { return error as? DocumentFormatError }
            }
            #expect(error("<p>x<note style=\"Nessuna\">y</note></p>") == .invalidValue(line: 2, attribute: "style", value: "Nessuna"))
            #expect(error("<styles>\n<style name=\"Emphasis\" target=\"character\" italic=\"on\"/>\n</styles>\n<float-styles>\n<float-style name=\"A\" content=\"Emphasis\"/>\n</float-styles>")
                    == .invalidValue(line: 6, attribute: "content", value: "Emphasis"))
            #expect(error("<float-styles>\n<float-style name=\"A\" list=\"Z\"/>\n</float-styles>") == .invalidValue(line: 3, attribute: "list", value: "Z"))
        }

        @Test("Due serie sulla stessa pagina: un blocco per serie, nell'ordine degli stili, ciascuno con il suo filetto")
        func seriesBlocks() throws {
            var withRule = curator
            withRule.showsRule = true
            let doc = document([.text(TextRun("Prima", style: body)), .floating(FloatingObject(runs: [TextRun("curatore uno", style: small)], style: curator.name)),
                                .text(TextRun(" poi", style: body)), .floating(FloatingObject(runs: [TextRun("autore", style: small)])),
                                .text(TextRun(" infine", style: body)), .floating(FloatingObject(runs: [TextRun("curatore due", style: small)], style: curator.name))],
                               styles: [withRule])
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            let page = layout.pages[0]
            let notes = page.lines.filter(\.isNote)
            #expect(notes.count == 3)
            #expect(page.rules.count == 2, "un filetto per serie")
            // Prima la serie della nota a piè di pagina (primo stile), poi quella del curatore, anche se il curatore viene prima nel testo.
            let text = layout.text.string as NSString
            let order = notes.map { text.substring(with: $0.noteRange!) }
            #expect(order == ["autore", "curatore uno", "curatore due"])
            #expect(page.rules[1].maxY < notes[0].origin.y - notes[0].descent && page.rules[1].minY > notes[1].origin.y + notes[1].ascent,
                    "il secondo filetto sta tra i due blocchi")
        }

        @Test("Richiamo normale e richiamo assente")
        func references() throws {
            var none = curator
            none.reference = .none
            for (style, expectedBody, expectedNote) in [(curator, "Testo1 fine.", "1 nota"), (none, "Testo fine.", "nota")] {
                let doc = document([.text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun("nota", style: small)], style: style.name)),
                                    .text(TextRun(" fine.", style: body))], styles: [style])
                let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
                let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.string)
                #expect(pdf.replacingOccurrences(of: "\u{2060}", with: "").contains(expectedBody), "\(style.reference)")
                #expect(pdf.contains(expectedNote), "\(style.reference)")
            }
        }

        @Test("Una nota che non si spezza resta intera: passa nella pagina dopo con la riga che la richiama")
        func unbreakable() throws {
            let long = String(repeating: "Una nota lunga che occupa parecchie righe in fondo alla pagina. ", count: 10)
            func layout(filler words: Int, canSplit: Bool) -> DocumentLayout {
                var style = curator
                style.canSplit = canSplit
                let doc = document([.text(TextRun(String(repeating: "riempitivo ", count: words) + "fine", style: body)),
                                    .floating(FloatingObject(runs: [TextRun(long, style: small)], style: style.name))], styles: [style])
                return PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            }
            func notePages(_ layout: DocumentLayout) -> Set<Int> {
                Set(layout.pages.enumerated().filter { $0.element.lines.contains(where: \.isNote) }.map(\.offset))
            }
            // Si allunga il testo finché la nota spezzabile cade a cavallo di due pagine: la riga che la richiama è in fondo.
            let words = try #require((380...700).first { notePages(layout(filler: $0, canSplit: true)).count == 2 })
            let whole = layout(filler: words, canSplit: false)
            #expect(notePages(whole).count == 1, "non spezzabile: tutta in una pagina")
            let notePage = try #require(notePages(whole).first)
            #expect(whole.pages[notePage].lines.contains { !$0.isNote && $0.range.location <= ((whole.text.string as NSString).range(of: "fine").location) && NSMaxRange($0.range) > (whole.text.string as NSString).range(of: "fine").location },
                    "la riga che la richiama sta nella stessa pagina")
        }

        @Test("Lo stile del contenuto dà al testo della nota le misure di uno stile di paragrafo")
        func contentStyle() {
            var style = curator
            style.contentStyle = "Quotation"   // rientri di 24 pt a sinistra e a destra
            let doc = document([.text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun("nota rientrata", style: small)], style: style.name))],
                               styles: [style])
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            let note = layout.pages[0].lines.first(where: \.isNote)!
            #expect(abs(note.origin.x - (layout.setup.textRect.minX + 24)) < 0.5)
        }
        @Test("Uno stile di flottante rinominato o tolto: le sue note lo seguono, o tornano note a piè di pagina")
        func renaming() {
            let doc = document([.text(TextRun("a", style: body)), .floating(FloatingObject(runs: [TextRun("uno", style: small)], style: "A")),
                                .text(TextRun("b", style: body)), .floating(FloatingObject(runs: [TextRun("due", style: small)], style: "B"))],
                               styles: [FloatStyle(name: "A"), FloatStyle(name: "B")])
            let text = NSMutableAttributedString(attributedString: doc.attributedString().text)
            let renames: [String: String?] = ["A": "Autore", "B": nil]
            TextStyling.renameFloatStyles(in: text, renames)
            let notes = Document(attributedString: text, settings: doc.settingsOnly).blocks.flatMap { block -> [FloatingObject] in
                guard case .paragraph(let paragraph) = block else { return [] }
                return paragraph.inlines.compactMap { if case .floating(let note) = $0 { note } else { nil } }
            }
            #expect(notes.map(\.style) == ["Autore", FloatStyle.footnoteName])
        }
        // MARK: Note di chiusura (tappa 5.3)

        private var endnotes: FloatStyle { FloatStyle(name: "Note di chiusura", placement: .documentEnd, listName: "Notes", heading: "Note") }

        @Test("Le note di chiusura stanno dopo il testo, con titolo e filetto, nell'ordine dei richiami; il cursore ci va")
        func endnotesAfterText() throws {
            let doc = document([.text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun("prima di chiusura", style: small)], style: endnotes.name)),
                                .text(TextRun(" e", style: body)), .floating(FloatingObject(runs: [TextRun("a piè di pagina", style: small)])),
                                .text(TextRun(" fine", style: body)), .floating(FloatingObject(runs: [TextRun("seconda di chiusura", style: small)], style: endnotes.name))],
                               styles: [endnotes])
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            #expect(layout.pages.count == 1)
            let page = layout.pages[0]
            let text = layout.text.string as NSString
            let noteLines = page.lines.filter(\.isNote)
            let body = page.lines.filter { !$0.isNote }
            let endLines = noteLines.filter { text.substring(with: $0.noteRange!).contains("chiusura") }
            #expect(endLines.map { text.substring(with: $0.noteRange!) } == ["prima di chiusura", "seconda di chiusura"])
            #expect(endLines.allSatisfy { $0.origin.y < body.last!.origin.y }, "dopo il testo")
            let foot = try #require(noteLines.first { text.substring(with: $0.noteRange!) == "a piè di pagina" })
            #expect(endLines[0].origin.y > foot.origin.y + 100, "la nota a piè di pagina resta in fondo, quelle di chiusura subito dopo il testo")
            #expect(page.markers.count == 1, "il titolo «Note»")
            #expect(page.rules.count == 2, "il filetto delle note a piè di pagina e quello delle note di chiusura")
            let index = text.range(of: "seconda").location + 2
            let caret = try #require(layout.caret(at: index))
            #expect(abs(caret.rect.minY - (endLines[1].origin.y - endLines[1].descent)) < 0.5, "il cursore sta sulla riga della nota di chiusura")
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.string)
            #expect(pdf.contains("Note") && pdf.contains("\u{B9} prima di chiusura") && pdf.contains("\u{B2} seconda di chiusura"))
        }

        @Test("Note di chiusura su una pagina nuova; e nel file")
        func endnotesNewPageAndFile() throws {
            var style = endnotes
            style.startsOnNewPage = true
            style.showsRule = false
            let doc = document([.text(TextRun("Testo breve", style: body)), .floating(FloatingObject(runs: [TextRun("in fondo", style: small)], style: style.name))],
                               styles: [style])
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            #expect(layout.pages.count == 2)
            #expect(layout.pages[1].lines.contains(where: \.isNote) && !layout.pages[0].lines.contains(where: \.isNote))
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<float-style name=\"Note di chiusura\" placement=\"end\" heading=\"Note\" new-page=\"on\" list=\"Notes\" rule=\"off\"/>"))
            #expect(try DocumentFormat.document(from: written) == doc)
        }
        // MARK: Note a margine (tappa 5.4)

        private var marginal: FloatStyle { FloatStyle(name: "Postille", placement: .outerMargin, reference: .none, showsRule: false) }

        private func marginLayout(_ inlines: [Inline]) -> DocumentLayout {
            let doc = document(inlines, styles: [marginal])
            return PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
        }

        private func postil(_ text: String) -> Inline { .floating(FloatingObject(runs: [TextRun(text, style: small)], style: "Postille")) }

        @Test("La nota a margine sta nel margine esterno accanto alla sua riga: a destra a pagina 1, a sinistra a pagina 2")
        func marginSides() throws {
            let filler = String(repeating: "riempitivo ", count: 700)
            let layout = marginLayout([.text(TextRun("Inizio", style: body)), postil("a destra"), .text(TextRun(" " + filler + "dopo", style: body)), postil("a sinistra")])
            let column = layout.setup.textRect
            let text = layout.text.string as NSString
            let right = try #require(layout.pages[0].lines.first { $0.noteRange.map { text.substring(with: $0) } == "a destra" })
            #expect(right.origin.x > column.maxX)
            let anchor = try #require(layout.pages[0].lines.first { !$0.isNote })
            #expect(abs(right.origin.y - anchor.origin.y) < 0.01, "sulla stessa linea di base della riga del richiamo")
            let secondPage = try #require(layout.pages.firstIndex { $0.lines.contains { $0.noteRange.map { text.substring(with: $0) } == "a sinistra" } })
            #expect(secondPage % 2 == 1, "una pagina pari")
            let left = try #require(layout.pages[secondPage].lines.first { $0.noteRange.map { text.substring(with: $0) } == "a sinistra" })
            #expect(left.origin.x + CGFloat(CTLineGetTypographicBounds(left.line, nil, nil, nil)) < column.minX)
            #expect(layout.pages[0].rules.isEmpty, "niente filetto, niente note in fondo alla pagina")
            #expect(layout.marginConflicts.isEmpty)
        }

        @Test("Due note a margine che si sovrappongono restano al loro posto e sono segnalate entrambe; due lontane no")
        func marginOverlap() {
            let long = String(repeating: "una postilla lunga ", count: 12)
            let crowded = marginLayout([.text(TextRun("Uno", style: body)), postil(long), .text(TextRun(" due", style: body)), postil("seconda")])
            #expect(crowded.marginConflicts.count == 2)
            #expect(crowded.marginConflictRects(onPage: 0).count == 2)
            let filler = String(repeating: "testo ", count: 200)
            let apart = marginLayout([.text(TextRun("Uno", style: body)), postil("breve"), .text(TextRun(" " + filler, style: body)), postil("altra")])
            #expect(apart.marginConflicts.isEmpty)
        }

        @Test("Una nota a margine che esce dal fondo dello specchio è segnalata; e nel file")
        func marginOverflowAndFile() throws {
            let long = String(repeating: "una postilla molto lunga ", count: 20)
            // Si allunga il testo finché la riga del richiamo è l'ultima della prima pagina.
            func layout(_ words: Int) -> DocumentLayout { marginLayout([.text(TextRun(String(repeating: "riempitivo ", count: words) + "fine", style: body)), postil(long)]) }
            let words = try #require((300...700).first { words in
                let candidate = layout(words)
                guard candidate.pages.count == 1, let last = candidate.pages[0].lines.filter({ !$0.isNote }).last else { return false }
                return last.origin.y < candidate.setup.textRect.minY + 30
            })
            #expect(layout(words).marginConflicts.count == 1)
            let doc = document([.text(TextRun("Testo", style: body)), postil("nota")], styles: [marginal])
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<float-style name=\"Postille\" placement=\"margin\" reference=\"none\" rule=\"off\"/>"))
            #expect(try DocumentFormat.document(from: written) == doc)
        }
    }
}
