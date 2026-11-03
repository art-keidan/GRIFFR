import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Font mancanti e corpi ottici nel documento")
    struct MissingFontTests {
        @Test("Un corpo ottico non installato si riduce alla faccia di base")
        func baseFaceNames() {
            #expect(TextStyling.baseFaceCandidates(forMissing: "Minion3Subhead-Bold") == ["Minion3-Bold"])
            #expect(TextStyling.baseFaceCandidates(forMissing: "WarnockPro-LightCapt") == ["WarnockPro-Light"])
            #expect(TextStyling.baseFaceCandidates(forMissing: "PTSans-Caption") == ["PTSans-Regular", "PTSans"])
            #expect(TextStyling.baseFaceCandidates(forMissing: "HoeflerText-Black").isEmpty)
        }

        @Test("Aprendo un file, un corpo ottico mancante con la faccia di base installata non è un font mancante")
        func rescueOnOpen() {
            let rendered = TextStyling.characterAttributes(for: CharacterStyle(fontName: "HoeflerTextSubhead-Black", size: 18))
            #expect(!rendered.isMissing)
            #expect((rendered.attributes[.font] as? NSFont)?.fontName == "HoeflerText-Black")
        }

        @Test("A un testo in un font mancante si può dare una famiglia: resta nero, e smette di essere mancante")
        func familyOnMissingFont() throws {
            let missing = CharacterStyle(fontName: "InesistenteSubhead-Bold", size: 18)
            let rendered = TextStyling.characterAttributes(for: missing)
            #expect(rendered.isMissing)
            let text = NSMutableAttributedString(string: "Titolo", attributes: rendered.attributes)
            var values = StyleValues()
            values.family = "Hoefler Text"
            TextStyling.setValue(values, of: .family, in: text, range: NSRange(location: 0, length: text.length))
            let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(font.familyName == "Hoefler Text")
            #expect(TextStyling.traits(ofFace: font.fontName)?.bold == true, "faccia: \(font.fontName)")
            #expect(text.attribute(.missingFont, at: 0, effectiveRange: nil) == nil)
        }

        private static let warnock = { FontLoader.registerAdobeFonts(); return NSFont(name: "WarnockPro-LightDisp", size: 12) != nil }()

        @Test("Nel documento va la faccia scelta, non il corpo ottico scelto in automatico", .enabled(if: warnock))
        func baseFaceInDocument() throws {
            let display = try #require(NSFont(name: "WarnockPro-LightDisp", size: 30))
            let text = NSAttributedString(string: "Titolo", attributes: [.font: display])
            let written = DocumentFormat.string(for: Document(attributedString: text))
            #expect(written.contains("font=\"WarnockPro-Light\""), "\(written)")
            #expect(!written.contains("LightDisp"))
        }
    }
}
