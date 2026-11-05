import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Cursore, clic e selezione nella pagina")
    struct LayoutGeometryTests {
        /// «ffi ct\n» su una riga, «AVA» sulla seconda, in Hoefler Text 24 senza trak (misure note dalla fase 0).
        private func twoLines() throws -> DocumentLayout {
            PageLayout.layout(NSAttributedString(string: "ffi ct\nAVA", attributes: [.font: try TestFonts.hoefler(size: 24)]), appliesFontTracking: false)
        }

        @Test("Dentro la legatura ffi il cursore segue la tabella lcar del font")
        func caretInsideLigature() throws {
            let layout = try twoLines()
            let left = layout.setup.textRect.minX
            let xs = try (0...3).map { try #require(layout.caret(at: $0)).rect.minX - left }
            // Valori misurati nella fase 0: 7,31 e 14,26 con lcar (sarebbero 6,92 e 13,84 dividendo in tre).
            #expect(abs(xs[0]) < 0.01)
            #expect(abs(xs[1] - 7.31) < 0.01)
            #expect(abs(xs[2] - 14.26) < 0.01)
            #expect(abs(xs[3] - 20.76) < 0.01)
        }

        @Test("Il cursore è alto quanto la riga e scende di riga dopo l'a capo")
        func caretLines() throws {
            let layout = try twoLines()
            let first = try #require(layout.caret(at: 0)), afterBreak = try #require(layout.caret(at: 7)), end = try #require(layout.caret(at: 10))
            let line = layout.pages[0].lines[0]
            #expect(first.page == 0)
            #expect(abs(first.rect.height - (line.ascent + line.descent)) < 0.001)
            #expect(abs(first.rect.minY - (line.origin.y - line.descent)) < 0.001)
            #expect(afterBreak.rect.minY < first.rect.minY, "la seconda riga è più in basso")
            #expect(abs(afterBreak.rect.minX - layout.setup.textRect.minX) < 0.01)
            #expect(end.rect.minX > afterBreak.rect.minX)
            // Fuori dai limiti si ottiene la posizione estrema, non un errore.
            #expect(layout.caret(at: 999) == end)
            #expect(layout.caret(at: -5) == first)
        }

        @Test("Un clic restituisce il carattere più vicino; cliccare e ridisegnare il cursore tornano allo stesso punto")
        func hitTesting() throws {
            let layout = try twoLines()
            for index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
                let caret = try #require(layout.caret(at: index))
                let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: caret.page))
                #expect(hit.index == index, "posizione \(index)")
            }
            let firstLine = try #require(layout.caret(at: 0)).rect, secondLine = try #require(layout.caret(at: 7)).rect
            // Oltre la fine della prima riga: prima dell'a capo (6), non dopo.
            #expect(try #require(layout.position(at: CGPoint(x: 500, y: firstLine.midY), onPage: 0)).index == 6)
            // A sinistra del margine: inizio della riga. Sotto l'ultima riga: si resta sull'ultima.
            #expect(try #require(layout.position(at: CGPoint(x: 0, y: secondLine.midY), onPage: 0)).index == 7)
            #expect(try #require(layout.position(at: CGPoint(x: 500, y: 5), onPage: 0)).index == 10)
            #expect(try #require(layout.position(at: CGPoint(x: 0, y: 5000), onPage: 0)).index == 0)
            #expect(layout.position(at: .zero, onPage: 7) == nil)
        }

        @Test("Dove la riga va a capo da sola, la fine della riga e l'inizio della successiva si distinguono")
        func softWrapAffinity() throws {
            let text = NSAttributedString(string: String(repeating: "minister affixed stamps ", count: 12), attributes: [.font: try TestFonts.hoefler(size: 24)])
            let layout = PageLayout.layout(text, appliesFontTracking: false)
            let lines = layout.pages[0].lines
            #expect(lines.count > 2)
            let boundary = NSMaxRange(lines[0].range)
            let downstream = try #require(layout.caret(at: boundary)), upstream = try #require(layout.caret(at: boundary, affinity: .upstream))
            #expect(abs(downstream.rect.minY - (lines[1].origin.y - lines[1].descent)) < 0.001, "per difetto: inizio della seconda riga")
            #expect(abs(upstream.rect.minY - (lines[0].origin.y - lines[0].descent)) < 0.001, "upstream: fine della prima riga")
            #expect(upstream.rect.minX > downstream.rect.minX)
            // Un clic oltre la fine della prima riga chiede proprio la fine di quella riga.
            let hit = try #require(layout.position(at: CGPoint(x: 590, y: upstream.rect.midY), onPage: 0))
            #expect(hit.index == boundary)
            #expect(hit.affinity == .upstream)
        }

        @Test("Testo vuoto e testo che finisce con un a capo hanno una riga per il cursore")
        func emptyLines() throws {
            let empty = PageLayout.layout(NSAttributedString())
            #expect(empty.pages.count == 1)
            let caret = try #require(empty.caret(at: 0))
            #expect(caret.rect.height > 0)
            #expect(abs(caret.rect.minX - empty.setup.textRect.minX) < 0.01)
            #expect(try #require(empty.position(at: CGPoint(x: 300, y: 300), onPage: 0)).index == 0)

            let trailing = PageLayout.layout(NSAttributedString(string: "AVA\n", attributes: [.font: try TestFonts.hoefler(size: 24)]))
            let last = try #require(trailing.caret(at: 4)), beforeBreak = try #require(trailing.caret(at: 3))
            #expect(last.rect.minY < beforeBreak.rect.minY, "dopo l'a capo finale il cursore è su una riga nuova")
            #expect(abs(last.rect.height - beforeBreak.rect.height) < 0.5, "con le misure dello stesso font")
            #expect(try #require(trailing.position(at: CGPoint(x: 300, y: last.rect.midY), onPage: 0)).index == 4)
        }

        @Test("Una pagina finale con la sola riga vuota del cursore non finisce nel PDF")
        func noBlankLastPage() throws {
            // Abbastanza righe da riempire esattamente una pagina, poi l'a capo finale.
            let font = try TestFonts.hoefler(size: 24)
            var count = 1
            while PageLayout.layout(NSAttributedString(string: String(repeating: "A\n", count: count), attributes: [.font: font])).pages.count == 1 { count += 1 }
            let layout = PageLayout.layout(NSAttributedString(string: String(repeating: "A\n", count: count), attributes: [.font: font]))
            #expect(layout.pages.count == 2)
            #expect(layout.pages[1].lines.allSatisfy { $0.range.length == 0 })
            let data = PDFRenderer.pdfData(for: layout)
            #expect(CGPDFDocument(try #require(CGDataProvider(data: data as CFData)))?.numberOfPages == 1)
        }

        @Test("I rettangoli di selezione: uno per riga, larghi quanto il testo selezionato")
        func selection() throws {
            let layout = try twoLines()
            #expect(layout.selectionRects(for: NSRange(location: 2, length: 0)).isEmpty)
            let ffi = layout.selectionRects(for: NSRange(location: 0, length: 3))
            #expect(ffi.count == 1)
            #expect(abs(ffi[0].rect.width - 20.76) < 0.01)
            let both = layout.selectionRects(for: NSRange(location: 4, length: 5))
            #expect(both.count == 2, "«ct» con l'a capo sulla prima riga, «AV» sulla seconda")
            #expect(both[0].rect.minY > both[1].rect.minY)
        }
        @Test("I caratteri nascosti: spazi, tabulazioni, a capo, fine paragrafo e richiami, ciascuno al suo posto")
        func invisibleMarks() throws {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let text = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("a b\tc\u{2028}d\u{A0}e", style: body)),
                                               .floating(FloatingObject(runs: [TextRun("una nota", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 10))])),
                                               .text(TextRun(" f", style: body))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("g", style: body))])),
            ]).attributedString().text
            let layout = PageLayout.layout(text, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false))
            let marks = layout.invisibleMarks(onPage: 0)
            #expect(marks.map(\.kind) == [.space, .tab, .lineBreak, .nonBreakingSpace, .noteReference, .space, .paragraphEnd, .space],
                    "da sinistra a destra in ogni riga; lo spazio della nota (tra «una» e «nota») per ultimo, con la riga della nota")
            let space = marks[0], tab = marks[1], lineBreak = marks[2]
            #expect(space.rect.width > 0 && tab.rect.minX > space.rect.maxX - 0.01 && lineBreak.rect.minX > tab.rect.minX)
            #expect(marks[3].baseline < lineBreak.baseline, "dopo l'a capo interno si scende di una riga")
            #expect(marks[4].rect.width > 0, "il numero di richiamo occupa un tratto della riga")
            #expect(marks[7].baseline < marks[6].baseline - 100, "lo spazio nel testo della nota sta in fondo alla pagina")
        }

        // MARK: Proprietà dinamiche (tappa 7.3)

        private static let sentence = "Una frase di prova abbastanza lunga da riempire la riga e andare oltre, così che il paragrafo occupi più righe. "

        private func factsDocument(paragraphs: [(String, String)], rules: [TextRule] = []) -> (DocumentLayout, Document) {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            var document = Document(styles: .builtIn, lists: ListDefinition.builtIn, blocks: paragraphs.map { style, text in
                .paragraph(Paragraph(styleName: style, style: StyleSheet.builtIn.resolveParagraph(styleName: style), inlines: [.text(TextRun(text, style: body))]))
            })
            document.rules = rules
            return (PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions), document)
        }

        @Test("Il paragrafo: righe, pagine, parole, ultima riga, che cosa lo precede, regole")
        func paragraphFacts() throws {
            let long = String(repeating: Self.sentence, count: 4)
            let rule = TextRule(target: .firstLines(1), paragraphStyle: "Body", position: .firstAfter("Heading 1"), styleName: "Small Caps")
            let (layout, document) = factsDocument(paragraphs: [("Heading 1", "Capitolo"), ("Body", long), ("Body", "Breve.")], rules: [rule])
            let start = ("Capitolo\n" as NSString).length
            let facts = try #require(layout.paragraphFacts(at: start + 5, rules: document.rules, sheet: document.styles))
            #expect(facts.lineCount == layout.pages[0].lines.filter { $0.paragraphLocation == start }.count)
            #expect(facts.lineCount >= 4)
            #expect(facts.wordCount == 4 * 20, "venti parole per frase")
            #expect(facts.firstPage == 1 && !facts.isSplit)
            #expect(!facts.isDocumentStart && facts.previousStyle == "Heading 1")
            #expect(facts.rules == [rule.summary])
            #expect(facts.lastLineFill > 0 && facts.lastLineFill < 1)
            let title = try #require(layout.paragraphFacts(at: 0, rules: document.rules, sheet: document.styles))
            #expect(title.isDocumentStart && title.isFirstOnPage && title.lineCount == 1 && title.rules.isEmpty)
            let short = try #require(layout.paragraphFacts(at: start + (long as NSString).length + 2, rules: document.rules, sheet: document.styles))
            #expect(short.isLastOnPage && short.previousStyle == "Body" && short.rules.isEmpty, "non è il primo dopo il titolo")
        }

        @Test("Un paragrafo che si spezza tra due pagine; la pagina: numero, righe, spazio vuoto")
        func splitParagraphAndPage() throws {
            let paragraphs = (0..<40).map { _ in ("Body", String(repeating: Self.sentence, count: 3)) }
            let (layout, document) = factsDocument(paragraphs: paragraphs)
            #expect(layout.pages.count >= 2)
            // Il paragrafo dell'ultima riga della prima pagina continua nella seconda.
            let lastLine = try #require(layout.pages[0].lines.last)
            let split = try #require(layout.paragraphFacts(at: lastLine.range.location, rules: [], sheet: document.styles))
            #expect(split.isSplit == (layout.pages[1].lines.first?.paragraphLocation == lastLine.paragraphLocation))
            let page = try #require(layout.pageFacts(at: 0, affinity: .downstream))
            #expect(page.number == 1 && !page.isEven && page.lineCount == layout.pages[0].lines.count && !page.hasNotes)
            #expect(page.freeSpace < 20, "una pagina piena")
            let lastPage = try #require(layout.pageFacts(at: layout.text.length, affinity: .downstream))
            #expect(lastPage.number == layout.pages.count)
            let short = factsDocument(paragraphs: [("Body", "Breve.")]).0
            #expect(try #require(short.pageFacts(at: 0, affinity: .downstream)).freeSpace > 500, "una pagina quasi vuota")
        }

        @Test("La riga: posizione, larghezza naturale e giustificazione, trattino; le regole che toccano un punto")
        func lineFactsAndRulesHere() throws {
            let long = String(repeating: Self.sentence, count: 4)
            let rule = TextRule(target: .firstLines(1), styleName: "Small Caps")
            let (layout, document) = factsDocument(paragraphs: [("Body", long)], rules: [rule])
            let lines = layout.pages[0].lines
            let first = try #require(layout.lineFacts(at: 2, affinity: .downstream))
            #expect(first.number == 1 && first.count == lines.count && first.page == 1)
            #expect(abs(first.width - first.availableWidth) < 1.5, "giustificata: piena")
            #expect(first.justification > 0 && first.naturalWidth < first.width)
            let last = try #require(layout.lineFacts(at: (long as NSString).length - 2, affinity: .downstream))
            #expect(last.number == lines.count && abs(last.justification) < 0.01, "l'ultima riga non si giustifica")
            #expect(layout.rules(touching: 2, rules: document.rules, sheet: document.styles) == [rule.summary])
            let third = lines[2].range.location + 1
            #expect(layout.rules(touching: third, rules: document.rules, sheet: document.styles).isEmpty)
            #expect(layout.documentFacts() == DocumentFacts(pageCount: 1, paragraphCount: 1, wordCount: 80, noteCount: 0))
        }

        @Test("Conteggi di un tratto: parole, caratteri con e senza spazi, paragrafi; il testo delle note non conta")
        func textCounts() throws {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let note = FloatingObject(runs: [TextRun("una nota lunga", style: body)])
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Città di Como", style: body)), .floating(note), .text(TextRun(".", style: body))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Secondo e\u{301}", style: body))])),
            ])
            let text = document.attributedString().text
            let all = TextCounts(in: text, range: NSRange(location: 0, length: text.length))
            #expect(all.words == 5)
            #expect(all.paragraphs == 2)
            #expect(all.characters == "Città di Como.".count + "Secondo e\u{301}".count, "una e con l'accento a parte è un carattere")
            #expect(all.charactersWithoutSpaces == all.characters - 3)
            let selected = TextCounts(in: text, range: NSRange(location: 0, length: 5))
            #expect(selected == TextCounts(words: 1, characters: 5, charactersWithoutSpaces: 5, paragraphs: 1))
        }
    }
}
