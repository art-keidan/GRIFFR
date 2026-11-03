import AppKit
import CoreText
import Testing
import Typesetting

extension TypesettingSuite {
    @Suite("Funzioni applicate a una selezione di testo")
    struct TextStylingTests {
        /// «𐌹𐍃 𐌲𐍂» in Vulcanius seguito da «ct st ffi 1234» in Hoefler Text.
        private func sample() throws -> (text: NSMutableAttributedString, gothic: NSRange, latin: NSRange) {
            let text = NSMutableAttributedString(string: TestFonts.gothicSample, attributes: [.font: try TestFonts.vulcanius()])
            let gothic = NSRange(location: 0, length: text.length)
            text.append(NSAttributedString(string: TestFonts.latinSample, attributes: [.font: try TestFonts.hoefler()]))
            return (text, gothic, NSRange(location: gothic.length, length: text.length - gothic.length))
        }

        private func glyphIDs(_ text: NSAttributedString, _ range: NSRange) -> [Int] {
            Shaper.glyphs(for: text.attributedSubstring(from: range)).map { Int($0.id) }
        }

        @Test("La modifica tocca solo i tratti del font indicato")
        func onlyMatchingFont() throws {
            let (text, gothic, latin) = try sample()
            let all = NSRange(location: 0, length: text.length)
            let changed = TextStyling.updateFeatures(in: text, range: all, ofFontNamed: "Vulcanius") { _ in [.aat(type: 17, selector: 3)] }
            #expect(changed == 1)
            #expect(glyphIDs(text, gothic) == [33, 34, 3, 8, 24])
            #expect(glyphIDs(text, latin) == [70, 87, 3, 86, 87, 3, 631, 3, 20, 21, 22, 23])
        }

        @Test("Una selezione parziale divide il tratto e lascia il resto com'era")
        func partialSelection() throws {
            let (text, _, latin) = try sample()
            // Solo «ct» (i primi due caratteri del tratto latino) con le legature rare.
            let ct = NSRange(location: latin.location, length: 2)
            TextStyling.updateFeatures(in: text, range: ct, ofFontNamed: "HoeflerText-Regular") { $0 + [.aat(type: 1, selector: 4)] }
            #expect(glyphIDs(text, latin) == [643, 3, 86, 87, 3, 631, 3, 20, 21, 22, 23], "ct legato, st no")
            #expect(TextStyling.fontRuns(in: text, range: latin).count == 2)
        }

        @Test("Cambiare il corpo conserva le funzioni attive")
        func resizeKeepsFeatures() throws {
            let (text, _, latin) = try sample()
            TextStyling.updateFeatures(in: text, range: latin, ofFontNamed: "HoeflerText-Regular") { _ in [.aat(type: 3, selector: 3)] }
            TextStyling.setSize(11, in: text, range: latin)
            let run = try #require(TextStyling.fontRuns(in: text, range: latin).first)
            #expect(run.font.pointSize == 11)
            #expect(FontFeatures.settings(of: run.font) == [.aat(type: 3, selector: 3)])
            #expect(glyphIDs(text, latin) == [462, 479, 3, 478, 479, 3, 465, 465, 468, 3, 20, 21, 22, 23])
        }
    }
}
