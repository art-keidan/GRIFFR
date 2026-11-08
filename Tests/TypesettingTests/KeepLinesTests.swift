import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tenuta delle righe: n righe del seguente e del precedente (formato 17)")
    struct KeepLinesTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)
        private let setup = PageSetup(paperSize: CGSize(width: 300, height: 260), top: 30, bottom: 30, left: 30, right: 30)

        private func lines(_ count: Int, word: String, keeping: LineKeeping = LineKeeping()) -> Block {
            let text = (1...count).map { "\(word) \($0)" }.joined(separator: "\u{2028}")
            return .paragraph(Paragraph(inlines: [.text(TextRun(text, style: body))], keeping: keeping))
        }

        private func layout(_ blocks: [Block]) -> (text: NSAttributedString, layout: DocumentLayout) {
            let text = Document(blocks: blocks).attributedString().text
            return (text, PageLayout.layout(text, setup: setup, options: options))
        }

        /// Quante righe del paragrafo che comincia con `word` stanno in ogni pagina.
        private func spread(of word: String, _ blocks: [Block]) -> [Int] {
            let result = layout(blocks)
            let location = (result.text.string as NSString).range(of: word + " 1").location
            return result.layout.pages.map { page in page.lines.filter { !$0.isNote && $0.paragraphLocation == location }.count }.filter { $0 > 0 }
        }

        private var perPage: Int { layout([lines(60, word: "Riempi")]).layout.pages.first?.lines.count ?? 0 }

        @Test("Tieni con n righe del seguente: se in fondo alla pagina non ne stanno n, il paragrafo passa con il seguito")
        func nextLines() {
            let n = perPage
            #expect(n >= 8)
            // Il titolo sta all'antipenultima riga: con «tieni col seguente» (1 riga) restano due righe di testo con lui.
            let one = [lines(n - 3, word: "Riempi"), lines(1, word: "Titolo", keeping: LineKeeping(withNext: true)), lines(5, word: "Testo")]
            #expect(spread(of: "Titolo", one) == [1] && spread(of: "Testo", one) == [2, 3])
            #expect(layout(one).layout.pages[0].lines.count == n, "il titolo resta in fondo alla prima pagina")
            // Con tre righe del seguente non bastano: il titolo passa alla pagina dopo.
            let three = [lines(n - 3, word: "Riempi"), lines(1, word: "Titolo", keeping: LineKeeping(withNext: true, nextLines: 3)), lines(5, word: "Testo")]
            #expect(spread(of: "Testo", three) == [5])
            #expect(layout(three).layout.pages[0].lines.count == n - 3, "il titolo e il testo vanno insieme alla pagina dopo")
        }

        @Test("Tieni con n righe del precedente: le ultime righe del precedente passano alla pagina di questo")
        func previousLines() {
            let n = perPage
            // Il paragrafo «Lungo» riempie esattamente la pagina: «Dopo» comincia in cima alla seconda.
            let plain = [lines(n - 4, word: "Riempi"), lines(4, word: "Lungo"), lines(2, word: "Dopo")]
            #expect(spread(of: "Lungo", plain) == [4])
            let kept = [lines(n - 4, word: "Riempi"), lines(4, word: "Lungo"), lines(2, word: "Dopo", keeping: LineKeeping(previousLines: 2))]
            #expect(spread(of: "Lungo", kept) == [2, 2], "due righe di «Lungo» vanno con «Dopo»")
            let result = layout(kept)
            let after = (result.text.string as NSString).range(of: "Dopo 1").location
            #expect(result.layout.pages[1].lines.contains { $0.paragraphLocation == after })
            // Il precedente è già spezzato, ma con una riga sola nella pagina di «Dopo»: ne arriva un'altra.
            let split = [lines(n - 3, word: "Riempi"), lines(4, word: "Lungo"), lines(2, word: "Dopo", keeping: LineKeeping(previousLines: 2))]
            #expect(spread(of: "Lungo", [lines(n - 3, word: "Riempi"), lines(4, word: "Lungo"), lines(2, word: "Dopo")]) == [3, 1])
            #expect(spread(of: "Lungo", split) == [2, 2])
            // Se il precedente è troppo corto per spezzarsi, passa tutto.
            let short = [lines(n - 2, word: "Riempi"), lines(2, word: "Corto"), lines(2, word: "Dopo", keeping: LineKeeping(previousLines: 2))]
            #expect(spread(of: "Corto", short) == [2] && layout(short).layout.pages[0].lines.count == n - 2)
            // Nella stessa pagina non cambia nulla.
            let room = [lines(3, word: "Riempi"), lines(4, word: "Lungo"), lines(2, word: "Dopo", keeping: LineKeeping(previousLines: 2))]
            #expect(spread(of: "Lungo", room) == [4] && layout(room).layout.pages.count == 1)
        }

        @Test("I due valori si leggono e si scrivono: nel testo, nei paragrafi e negli stili del file (versione 17)")
        func roundTrip() throws {
            let keeping = LineKeeping(withNext: true, nextLines: 3, previousLines: 2)
            #expect(LineKeeping(encoded: keeping.encoded) == keeping)
            var values = StyleValues()
            values.keeping = LineKeeping(previousLines: 1)
            let sheet = StyleSheet(styles: [NamedStyle(name: "Tenuto", target: .paragraph, values: values)])
            var document = Document(styles: sheet, blocks: [lines(2, word: "Uno", keeping: keeping)])
            document.styles = sheet
            let xml = DocumentFormat.string(for: document)
            #expect(xml.contains("version=\"18\"") && xml.contains("keep-next-lines=\"3\"") && xml.contains("keep-with-previous=\"2\""))
            let reread = try DocumentFormat.document(from: Data(xml.utf8))
            #expect(reread.flatParagraphs.first?.paragraph.keeping == keeping)
            #expect(reread.styles.lineKeeping(styleName: "Tenuto").previousLines == 1)
        }
    }
}
