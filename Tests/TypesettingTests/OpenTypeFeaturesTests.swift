import AppKit
import CoreText
import Foundation
import Testing
import Typesetting

private let brillURL = URL(fileURLWithPath: "/Users/artemio/Library/Fonts/Brill/Brill-Roman.ttf")

extension TypesettingSuite {
    @Suite("Funzioni OpenType viste attraverso Core Text")
    struct OpenTypeFeaturesTests {
        @Test("Arial (font di sistema, solo GSUB): le legature portano il tag OpenType")
        func arial() throws {
            // Da file e non per nome: la ricerca per nome passa dal servizio dei font di sistema, che in un test si è bloccato.
            let font = try FontLoader.font(at: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf"), size: 24)
            #expect(font.postScriptName == "ArialMT")
            #expect(!font.tableTags.contains("morx"))
            let ligatures = try #require(FontFeatures.types(of: font).first { $0.key == .aat(1) })
            #expect(ligatures.selectors.compactMap(\.openTypeTag) == ["liga", "dlig"])
            #expect(FontFeatures.openTypeTags(of: font).gsub.contains("liga"))
        }

        @Test("Brill: una funzione senza equivalente AAT (cv01) è elencata e ha effetto",
              .enabled(if: FileManager.default.fileExists(atPath: brillURL.path)))
        func brillCharacterVariant() throws {
            let base = try FontLoader.font(at: brillURL, size: 24)
            let cv01 = try #require(FontFeatures.types(of: base).first { $0.key == .openType("cv01") })
            #expect(cv01.isExclusive)
            #expect(cv01.selectors.map(\.setting) == [
                .openType(tag: "cv01", value: 0), .openType(tag: "cv01", value: 1), .openType(tag: "cv01", value: 2),
            ])
            let settings = cv01.selecting(cv01.selectors[2], in: [])
            let font = FontFeatures.font(base, with: settings)
            #expect(FontFeatures.settings(of: font) == [.openType(tag: "cv01", value: 2)])
            #expect(cv01.activeSelector(in: FontFeatures.settings(of: font)) == cv01.selectors[2])
            // Tornare alla voce predefinita toglie l'impostazione.
            #expect(FontFeatures.settings(of: FontFeatures.font(font, with: cv01.selecting(cv01.selectors[0], in: settings))).isEmpty)
        }

        @Test("Brill: maiuscoletto chiesto in forma AAT e in forma OpenType dà gli stessi glifi",
              .enabled(if: FileManager.default.fileExists(atPath: brillURL.path)))
        func brillSmallCapsBothForms() throws {
            let base = try FontLoader.font(at: brillURL, size: 24)
            let plain = Shaper.glyphIDs(for: "Agfi", font: base)
            let aat = Shaper.glyphIDs(for: "Agfi", font: FontFeatures.font(base, with: [.aat(type: 37, selector: 1)]))
            let openType = Shaper.glyphIDs(for: "Agfi", font: FontFeatures.font(base, with: [.openType(tag: "smcp", value: 1)]))
            #expect(aat == openType)
            #expect(aat != plain)
        }

        @Test("Dei tag non elencati si possono forzare solo quelli che Core Text accetta di ricordare")
        func forceableTags() throws {
            // Vulcanius: `salt` viene ricordato (anche se, avendo il font una tabella morx, non ha effetto); `aalt` no.
            let vulcanius = try TestFonts.vulcanius()
            #expect(FontFeatures.unlistedOpenTypeTags(of: vulcanius) == ["aalt", "ccmp", "salt", "ss01", "ss02", "kern"])
            #expect(FontFeatures.forceableOpenTypeTags(of: vulcanius) == ["salt"])
            #expect(FontFeatures.forceableOpenTypeTags(of: try TestFonts.hoefler()).isEmpty)
            // Times New Roman dichiara funzioni di composizione (ccmp, locl, mark, forme arabe): nessuna si può forzare.
            let times = try #require(NSFont(name: "TimesNewRomanPSMT", size: 24)) as CTFont
            #expect(FontFeatures.unlistedOpenTypeTags(of: times).contains("ccmp"))
            #expect(FontFeatures.forceableOpenTypeTags(of: times).isEmpty)
        }
    }
}
