import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Caratteri disegnati con un font di ripiego")
    struct FontFallbackTests {
        private func page(_ text: String, font: String) throws -> LaidOutPage {
            let attributed = NSAttributedString(string: text, attributes: [.font: try #require(NSFont(name: font, size: 14))])
            return try #require(PageLayout.layout(attributed, setup: .a4, options: LayoutOptions()).pages.first)
        }

        @Test("Le lettere latine in Muna si riconoscono come ripiego; il testo e il font scelto non cambiano",
              .enabled(if: NSFont(name: "Muna", size: 12) != nil))
        func latinInArabicFont() throws {
            #expect(!(try page("Testo latino", font: "Muna")).fallbackRects.isEmpty)
            #expect((try page("Testo latino", font: "HoeflerText-Regular")).fallbackRects.isEmpty)
            #expect((try page("بسم", font: "Muna")).fallbackRects.isEmpty, "l'arabo è di Muna")
            let text = NSAttributedString(string: "ab بسم", attributes: [.font: NSFont(name: "Muna", size: 12)!])
            let families = FontFallback.fallbackFamilies(in: text, range: NSRange(location: 0, length: text.length))
            #expect(families.count == 1 && families.first != "Muna")
            #expect(text.attribute(.chosenFontFamily, at: 0, effectiveRange: nil) == nil, "l'attributo resta nell'impaginazione")
        }
    }
}
