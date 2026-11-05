import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tenuta delle righe: tieni col seguente (tappa A3)")
    struct KeepWithNextTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)
        private let setup = PageSetup(paperSize: CGSize(width: 300, height: 260), top: 30, bottom: 30, left: 30, right: 30)
        private let withNext = LineKeeping(withNext: true)

        /// Un paragrafo di `count` righe, con gli a capo interni.
        private func paragraph(_ count: Int, word: String, keeping: LineKeeping = LineKeeping()) -> Paragraph {
            let text = (1...count).map { "\(word) \($0)" }.joined(separator: "\u{2028}")
            return Paragraph(inlines: [.text(TextRun(text, style: body))], keeping: keeping)
        }

        private func lines(_ count: Int, word: String, keeping: LineKeeping = LineKeeping()) -> Block {
            .paragraph(paragraph(count, word: word, keeping: keeping))
        }

        private func layout(_ document: Document) -> (text: NSAttributedString, layout: DocumentLayout) {
            let text = document.attributedString().text
            return (text, PageLayout.layout(text, setup: setup, options: options))
        }

        /// Le pagine (indici) in cui stanno righe del paragrafo che comincia con `word`.
        private func pages(of word: String, in result: (text: NSAttributedString, layout: DocumentLayout)) -> [Int] {
            let location = (result.text.string as NSString).range(of: word + " 1").location
            return result.layout.pages.indices.filter { result.layout.pages[$0].lines.contains { !$0.isNote && $0.paragraphLocation == location } }
        }

        private func pages(of word: String, _ blocks: [Block]) -> [Int] { pages(of: word, in: layout(Document(blocks: blocks))) }

        /// Quante righe entrano in una pagina.
        private var perPage: Int {
            let result = layout(Document(blocks: [lines(60, word: "Riempi")]))
            return result.layout.pages.first?.lines.count ?? 0
        }

        @Test("Un titolo all'ultima riga della pagina passa alla pagina dopo, con il testo che lo segue")
        func titleAtBottom() {
            let n = perPage
            #expect(n >= 8)
            let plain = [lines(n - 1, word: "Riempi"), lines(1, word: "Titolo"), lines(3, word: "Testo")]
            #expect(pages(of: "Titolo", plain) == [0])
            #expect(pages(of: "Testo", plain) == [1])
            let kept = [lines(n - 1, word: "Riempi"), lines(1, word: "Titolo", keeping: withNext), lines(3, word: "Testo")]
            #expect(pages(of: "Titolo", kept) == [1])
            #expect(pages(of: "Testo", kept) == [1])
            #expect(pages(of: "Riempi", kept) == [0])
        }

        @Test("La variante segue la prima riga accettata dopo un salto naturale o la tenuta del titolo")
        func pageStartPlacement() throws {
            let n = perPage
            let gap = PageSetup.points(fromMillimetres: 30)
            var values = StyleValues()
            values.pageStartSpacing = .distance(gap)
            let sheet = StyleSheet(styles: [NamedStyle(name: "Titolo", target: .paragraph, values: values)])
            var opts = options
            opts.styles = sheet
            func result(_ fill: Int, keep: Bool) -> DocumentLayout {
                var title = paragraph(1, word: "Titolo", keeping: keep ? withNext : LineKeeping())
                title.styleName = "Titolo"
                let document = Document(styles: sheet, blocks: [lines(fill, word: "Prima"), .paragraph(title), lines(3, word: "Dopo")])
                return PageLayout.layout(document.attributedString().text, setup: setup, options: opts)
            }
            for (fill, keep) in [(n, false), (n - 1, true)] {
                let layout = result(fill, keep: keep)
                let (index, fact) = try #require(layout.pageStarts.first)
                let line = try #require(layout.pages[1].lines.first { $0.paragraphLocation == index })
                #expect(abs(fact.effective - gap) < 0.01)
                #expect(abs(setup.paperSize.height - line.origin.y - line.ascent - setup.top - gap) < 0.1)
            }
            #expect(result(n - 3, keep: true).pageStarts.isEmpty)
        }

        @Test("Nello specchio corto il distacco cede spazio alla prima riga successiva")
        func pageStartOnShortPage() throws {
            var values = StyleValues()
            values.pageStartSpacing = .distance(190)
            let sheet = StyleSheet(styles: [NamedStyle(name: "Apertura", target: .paragraph, values: values)])
            var title = paragraph(1, word: "Titolo", keeping: withNext)
            title.styleName = "Apertura"
            var opts = options
            opts.styles = sheet
            let doc = Document(styles: sheet, blocks: [.paragraph(title), lines(1, word: "Testo")])
            let layout = PageLayout.layout(doc.attributedString().text, setup: setup, options: opts)
            let opening = try #require(layout.pageStarts[0])
            #expect(layout.pages.count == 1)
            #expect(opening.requested == 190)
            #expect(opening.effective < 190 && opening.effective > 0)
        }

        @Test("Il testo che segue conta con le sue righe minime in fondo alla pagina")
        func followerMinimum() {
            let n = perPage
            let follower = LineKeeping(linesAtEnd: 2, linesAtStart: 2)
            // Una riga del testo entrerebbe, ma ne vuole due: titolo e testo vanno alla pagina dopo.
            let blocks = [lines(n - 2, word: "Riempi"), lines(1, word: "Titolo", keeping: withNext), lines(4, word: "Testo", keeping: follower)]
            #expect(pages(of: "Titolo", blocks) == [1])
            #expect(pages(of: "Testo", blocks) == [1])
            // Due righe entrano: tutto resta dov'è.
            let room = [lines(n - 3, word: "Riempi"), lines(1, word: "Titolo", keeping: withNext), lines(4, word: "Testo", keeping: follower)]
            #expect(pages(of: "Titolo", room) == [0])
            #expect(pages(of: "Testo", room) == [0, 1])
        }

        @Test("Una catena di titoli passa tutta insieme")
        func chain() {
            let n = perPage
            let blocks = [lines(n - 2, word: "Riempi"), lines(1, word: "Capitolo", keeping: withNext), lines(1, word: "Paragrafo", keeping: withNext),
                          lines(3, word: "Testo")]
            #expect(pages(of: "Capitolo", blocks) == [1])
            #expect(pages(of: "Paragrafo", blocks) == [1])
            #expect(pages(of: "Testo", blocks) == [1])
            // Il primo titolo della catena all'ultima riga, il secondo nella pagina dopo: anche il primo passa.
            let split = [lines(n - 1, word: "Riempi"), lines(1, word: "Capitolo", keeping: withNext), lines(1, word: "Paragrafo", keeping: withNext),
                         lines(3, word: "Testo")]
            #expect(pages(of: "Capitolo", split) == [1])
            #expect(pages(of: "Paragrafo", split) == [1])
        }

        @Test("Un titolo seguito da una tabella che non entra va con la tabella")
        func beforeTable() {
            let n = perPage
            func cell(_ word: String) -> TableCell { TableCell(paragraphs: [paragraph(1, word: word)]) }
            let table = Block.table(Table(id: "t", rows: [TableRow(cells: [cell("Cella"), cell("Altra")]), TableRow(cells: [cell("Sotto"), cell("Fine")])]))
            let blocks = [lines(n - 2, word: "Riempi"), lines(1, word: "Titolo", keeping: withNext), table]
            let result = layout(Document(blocks: blocks))
            let tablePages = pages(of: "Cella", in: result)
            #expect(tablePages.count == 1)
            #expect(pages(of: "Titolo", in: result) == tablePages)
        }

        @Test("Un titolo prima di un ritorno fuori dalla sezione resta con il testo del ritorno")
        func beforeReturn() {
            let n = perPage
            func document(corpo: Int, keeping: LineKeeping) -> Document {
                var document = Document(blocks: [lines(2, word: "Prima")])
                document.sections = [Section(id: "c1", role: "chapter", title: paragraph(1, word: "Capitolo"),
                                             blocks: [lines(corpo, word: "Corpo"), lines(1, word: "Coda", keeping: keeping)],
                                             afterward: [lines(3, word: "Dopo")])]
                return document
            }
            // Il caso in cui, senza tenuta, la coda del capitolo è l'ultima riga della pagina e il ritorno comincia nella seguente.
            let corpo = ((n - 6)...(n - 1)).first { corpo in
                let plain = layout(document(corpo: corpo, keeping: LineKeeping()))
                return pages(of: "Coda", in: plain) == [0] && pages(of: "Dopo", in: plain).first == 1
            }
            guard let corpo else { Issue.record("nessun caso con la coda in fondo alla pagina"); return }
            let kept = layout(document(corpo: corpo, keeping: withNext))
            #expect(pages(of: "Coda", in: kept) == [1])
            #expect(pages(of: "Dopo", in: kept).first == 1)
            #expect(pages(of: "Corpo", in: kept) == [0])
        }

        @Test("Una catena che non sta con il seguito neanche spostata si posa com'era, senza pagine vuote")
        func tooLong() {
            let n = perPage
            // In una pagina vuota non si sposta.
            let full = [lines(n, word: "Riempi"), lines(n, word: "Lungo", keeping: withNext), lines(3, word: "Testo")]
            let first = layout(Document(blocks: full))
            #expect(first.layout.pages.allSatisfy { !$0.lines.isEmpty })
            #expect(pages(of: "Lungo", in: first) == [1])
            #expect(pages(of: "Testo", in: first) == [2])
            // Spostata, non entrerebbe ancora con il seguito indivisibile: resta dov'era.
            let blocks = [lines(2, word: "Riempi"), lines(n - 2, word: "Lungo", keeping: withNext), lines(3, word: "Testo", keeping: LineKeeping(together: true))]
            let second = layout(Document(blocks: blocks))
            #expect(second.layout.pages.allSatisfy { !$0.lines.isEmpty })
            #expect(pages(of: "Lungo", in: second) == [0])
            #expect(pages(of: "Testo", in: second) == [1])
        }

        @Test("Un titolo seguito da un capitolo su pagina nuova non si sposta")
        func beforeNewPageSection() {
            let n = perPage
            var document = Document(blocks: [lines(n - 1, word: "Riempi"), lines(1, word: "Titolo", keeping: withNext)])
            document.sections = [Section(id: "c1", role: "chapter", title: paragraph(1, word: "Capitolo"),
                                         blocks: [lines(3, word: "Testo")], start: .newPage)]
            let result = layout(document)
            #expect(pages(of: "Titolo", in: result) == [0])
            #expect(pages(of: "Capitolo", in: result) == [1])
        }

        @Test("Un titolo in cima alla pagina non si sposta, e senza «tieni col seguente» nulla cambia")
        func noChange() {
            let n = perPage
            let top = [lines(n, word: "Riempi"), lines(n - 1, word: "Titolo", keeping: withNext), lines(3, word: "Testo")]
            let result = layout(Document(blocks: top))
            #expect(pages(of: "Titolo", in: result) == [1])
            #expect(result.layout.pages.allSatisfy { !$0.lines.isEmpty })
            let blocks = (0..<6).map { lines(n / 2 + $0, word: "Blocco\($0)") }
            let text = Document(blocks: blocks).attributedString().text
            let plain = PageLayout.layout(text, setup: setup, options: options)
            let tagged = NSMutableAttributedString(attributedString: text)
            TextStyling.setLineKeeping(LineKeeping(withNext: false), in: tagged, paragraphs: NSRange(location: 0, length: tagged.length))
            let same = PageLayout.layout(tagged, setup: setup, options: options)
            #expect(plain.pages.map { $0.lines.map(\.range) } == same.pages.map { $0.lines.map(\.range) })
        }
    }
}
