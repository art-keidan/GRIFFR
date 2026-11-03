import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tenuta delle righe: impaginazione (tappa A2)")
    struct LineKeepingLayoutTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)
        /// Una pagina piccola: entrano poche righe, così i casi si contano a mano.
        private let setup = PageSetup(paperSize: CGSize(width: 300, height: 260), top: 30, bottom: 30, left: 30, right: 30)

        /// Un paragrafo di `count` righe, con gli a capo interni; `note` mette una nota alla fine della riga di quell'indice.
        private func lines(_ count: Int, word: String, note: Int? = nil, keeping: LineKeeping = LineKeeping()) -> Block {
            var inlines: [Inline] = []
            for index in 0..<count {
                inlines.append(.text(TextRun("\(word) \(index + 1)" + (index < count - 1 && index != note ? "\u{2028}" : ""), style: body)))
                if index == note {
                    inlines.append(.floating(FloatingObject(runs: [TextRun("Nota.", style: small)])))
                    if index < count - 1 { inlines.append(.text(TextRun("\u{2028}", style: body))) }
                }
            }
            return .paragraph(Paragraph(inlines: inlines, keeping: keeping))
        }

        /// Quante righe del paragrafo che comincia con `word` stanno in ciascuna pagina (solo le pagine in cui ce n'è).
        private func distribution(_ blocks: [Block], of word: String) -> [Int] {
            let text = Document(blocks: blocks).attributedString().text
            let location = (text.string as NSString).range(of: word + " 1").location
            let layout = PageLayout.layout(text, setup: setup, options: options)
            return layout.pages.map { $0.lines.filter { !$0.isNote && $0.paragraphLocation == location }.count }.filter { $0 > 0 }
        }

        /// Quante righe entrano in una pagina.
        private var perPage: Int { distribution([lines(60, word: "Riempi")], of: "Riempi").first ?? 0 }

        private let standard = LineKeeping(linesAtEnd: 2, linesAtStart: 2)

        private func split(filler: Int, _ count: Int, _ keeping: LineKeeping, note: Int? = nil) -> [Int] {
            distribution([lines(filler, word: "Riempi"), lines(count, word: "Prova", note: note, keeping: keeping)], of: "Prova")
        }

        @Test("La pagina di prova contiene abbastanza righe")
        func pageSize() { #expect(perPage >= 8) }

        @Test("2+2 resta 2+2; senza tenuta 3+1 e 1+3 restano come sono")
        func unchanged() {
            let n = perPage
            #expect(split(filler: n - 2, 4, standard) == [2, 2])
            #expect(split(filler: n - 3, 4, LineKeeping()) == [3, 1])
            #expect(split(filler: n - 1, 4, LineKeeping()) == [1, 3])
            #expect(split(filler: n - 3, 4, LineKeeping(linesAtEnd: 1, linesAtStart: 1)) == [3, 1])
        }

        @Test("3+1 diventa 2+2: la riga sola in cima alla pagina dopo se ne porta dietro un'altra")
        func widow() { #expect(split(filler: perPage - 3, 4, standard) == [2, 2]) }

        @Test("1+3 diventa 0+4: la riga sola in fondo alla pagina passa alla seguente")
        func orphan() { #expect(split(filler: perPage - 1, 4, standard) == [4]) }

        @Test("Un paragrafo troppo corto per spezzarsi rispettando i minimi va tutto nella pagina dopo")
        func tooShort() {
            #expect(split(filler: perPage - 2, 3, standard) == [3])
            #expect(split(filler: perPage - 1, 2, standard) == [2])
        }

        @Test("Il paragrafo indivisibile va tutto nella pagina dopo")
        func together() {
            #expect(split(filler: perPage - 2, 4, LineKeeping(together: true)) == [4])
            #expect(split(filler: perPage - 2, 4, LineKeeping(together: false)) == [2, 2])
        }

        @Test("Più lungo di una pagina: indivisibile comincia su una pagina nuova e poi si spezza; le righe minime valgono a ogni pagina")
        func longerThanPage() {
            let n = perPage
            #expect(split(filler: n - 2, 2 * n + 1, LineKeeping(together: true)) == [n, n, 1])
            #expect(split(filler: n - 2, 2 * n + 1, LineKeeping(together: true, linesAtStart: 2)) == [n, n - 1, 2])
            // Senza la pagina avviata prima: solo le righe in cima alla seguente.
            #expect(distribution([lines(n + 1, word: "Prova", keeping: standard)], of: "Prova") == [n - 1, 2])
        }

        @Test("Minimi più alti: 3 in fondo e 3 in cima")
        func higherMinimums() {
            let three = LineKeeping(linesAtEnd: 3, linesAtStart: 3)
            #expect(split(filler: perPage - 2, 6, three) == [6])
            #expect(split(filler: perPage - 4, 6, three) == [3, 3])
            #expect(split(filler: perPage - 5, 6, three) == [3, 3])
        }

        @Test("Una nota segue la sua riga anche quando la tenuta sposta le righe")
        func notesFollow() throws {
            let n = perPage
            for filler in (n - 4)...(n - 1) {
                let blocks = [lines(filler, word: "Riempi"), lines(4, word: "Prova", note: 2, keeping: standard)]
                let counts = distribution(blocks, of: "Prova")
                #expect(counts.allSatisfy { $0 >= 2 }, "riempitivo \(filler): \(counts)")
                let text = Document(blocks: blocks).attributedString().text
                let layout = PageLayout.layout(text, setup: setup, options: options)
                let marked = (text.string as NSString).range(of: "Prova 3").location
                let linePage = try #require(layout.pages.firstIndex { $0.lines.contains { !$0.isNote && NSLocationInRange(marked, $0.range) } })
                let notePage = try #require(layout.pages.firstIndex { $0.lines.contains { $0.isNote } })
                #expect(linePage == notePage, "riempitivo \(filler)")
            }
        }

        @Test("Con le sezioni (capitolo su pagina nuova, ritorno fuori dal capitolo) nessuna pagina resta vuota")
        func sections() {
            let n = perPage
            var document = Document(blocks: [lines(n - 1, word: "Premessa")])
            let title = Paragraph(inlines: [.text(TextRun("Capitolo", style: body))])
            guard case .paragraph(let first) = lines(4, word: "Prova", keeping: LineKeeping(together: true, linesAtEnd: 2, linesAtStart: 2)),
                  case .paragraph(let after) = lines(4, word: "Dopo", keeping: standard) else { return }
            document.sections = [Section(id: "c1", role: "capitolo", title: title,
                                         blocks: [lines(n - 3, word: "Corpo"), .paragraph(first)], start: .newPage,
                                         afterward: [.paragraph(after)])]
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: setup, options: options)
            #expect(layout.pages.allSatisfy { !$0.lines.isEmpty })
            func pages(of word: String) -> [Int] {
                let location = (text.string as NSString).range(of: word + " 1").location
                return layout.pages.indices.filter { layout.pages[$0].lines.contains { $0.paragraphLocation == location } }
            }
            #expect(pages(of: "Corpo") == [1])
            #expect(pages(of: "Prova") == [2])
            #expect(pages(of: "Dopo") == [2])
        }

        @Test("Un documento senza tenuta si impagina esattamente come prima")
        func noKeepingNoChange() {
            let n = perPage
            let blocks = (0..<6).map { lines(n / 2 + $0, word: "Blocco\($0)") }
            let text = Document(blocks: blocks).attributedString().text
            let plain = PageLayout.layout(text, setup: setup, options: options)
            let tagged = NSMutableAttributedString(attributedString: text)
            TextStyling.setLineKeeping(LineKeeping(withNext: false, together: false, linesAtEnd: 1, linesAtStart: 1), in: tagged,
                                       paragraphs: NSRange(location: 0, length: tagged.length))
            let same = PageLayout.layout(tagged, setup: setup, options: options)
            #expect(plain.pages.map { $0.lines.map(\.range) } == same.pages.map { $0.lines.map(\.range) })
        }
    }
}
