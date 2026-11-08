import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Filetti liberi dei paragrafi (formato 18)")
    struct ParagraphRulesTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)
        private let setup = PageSetup(paperSize: CGSize(width: 300, height: 400), top: 30, bottom: 30, left: 30, right: 30)

        @Test("Si posano sopra, sotto e ai lati del paragrafo, senza spostare il testo")
        func placement() {
            let rules = ParagraphRules([ParagraphRule(anchor: .top, offset: 4, thickness: 1),
                                        ParagraphRule(anchor: .left, offset: 6, start: 2, end: 2, thickness: 2),
                                        ParagraphRule(anchor: .bottom, offset: 3, start: -10, end: -20, thickness: 0.5)])
            let plain = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Uno\u{2028}Due", style: body))]))])
            var ruled = plain
            if case .paragraph(var paragraph) = ruled.blocks[0] { paragraph.rules = rules; ruled.blocks[0] = .paragraph(paragraph) }
            let before = PageLayout.layout(plain.attributedString().text, setup: setup, options: options)
            let after = PageLayout.layout(ruled.attributedString().text, setup: setup, options: options)
            #expect(before.pages[0].lines.map(\.origin) == after.pages[0].lines.map(\.origin), "il testo non si sposta")
            let placed = after.pages[0].paragraphRules
            #expect(placed.map(\.rule) == [0, 1, 2])
            let lines = after.pages[0].lines
            let top = lines.map { $0.origin.y + $0.ascent }.max()!, bottom = lines.map { $0.origin.y - $0.descent }.min()!
            #expect(abs(placed[0].rect.minY - (top + 4)) < 0.01 && abs(placed[0].rect.width - 240) < 0.01)
            #expect(abs(placed[1].rect.maxX - (30 - 6)) < 0.01 && abs(placed[1].rect.height - (top - bottom + 4)) < 0.01)
            #expect(abs(placed[2].rect.minX - 40) < 0.01 && abs(placed[2].rect.width - 210) < 0.01 && abs(placed[2].rect.maxY - (bottom - 3)) < 0.01)
            #expect(after.pages[0].rules.count == before.pages[0].rules.count + 3, "e si disegnano")
        }

        @Test("Stile e paragrafo li scrivono nel file, versione 18; il paragrafo vince sullo stile")
        func roundTrip() throws {
            var values = StyleValues()
            values.rules = ParagraphRules([ParagraphRule(anchor: .right, offset: 5, thickness: 1)])
            let sheet = StyleSheet(styles: [NamedStyle(name: "Riquadro", target: .paragraph, values: values)])
            let own = ParagraphRules([ParagraphRule(anchor: .top, offset: 2.5, start: 1, end: -3, thickness: 0.75)])
            let document = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Riquadro", inlines: [.text(TextRun("Uno", style: body))], rules: own))])
            let xml = DocumentFormat.string(for: document)
            #expect(xml.contains("version=\"18\"") && xml.contains("rules=\"right 5 0 0 1\"") && xml.contains("rules=\"top 2.5 1 -3 0.75\""))
            let reread = try DocumentFormat.document(from: Data(xml.utf8))
            #expect(reread.styles.values(of: "Riquadro").rules == values.rules)
            #expect(reread.flatParagraphs.first?.paragraph.rules == own)
            #expect(ParagraphRules(encoded: "top 1 0 0 0") == nil, "uno spessore nullo non si accetta")
        }
    }
}
