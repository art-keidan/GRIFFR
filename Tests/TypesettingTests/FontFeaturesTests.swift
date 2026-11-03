import CoreText
import Testing
import Typesetting

extension TypesettingSuite {
    @Suite("Lettura e modifica delle funzioni del font")
    struct FontFeaturesTests {
        @Test("Vulcanius dichiara il tipo 17 con i selettori 1–3")
        func vulcaniusTypes() throws {
            let types = FontFeatures.types(of: try TestFonts.vulcanius())
            let alternates = try #require(types.first { $0.key == .aat(17) })
            #expect(alternates.isExclusive)
            #expect(alternates.selectors.map(\.setting) == [
                .aat(type: 17, selector: 0), .aat(type: 17, selector: 1),
                .aat(type: 17, selector: 2), .aat(type: 17, selector: 3),
            ])
            #expect(alternates.selectors.map(\.name) == ["No Change", "Alternate Eis", "Alternate Sauil", "Both"])
            #expect(alternates.selectors.first?.isDefault == true)
        }

        @Test("Vulcanius ha morx e GSUB; i tag GSUB non sono elencati da Core Text")
        func vulcaniusOpenType() throws {
            let font = try TestFonts.vulcanius()
            #expect(font.tableTags.isSuperset(of: ["morx", "feat", "GSUB"]))
            #expect(FontFeatures.unlistedOpenTypeTags(of: font) == ["aalt", "ccmp", "salt", "ss01", "ss02", "kern"])
        }

        @Test("Hoefler Text: legature comuni accese per difetto, rare spente")
        func hoeflerLigatures() throws {
            let types = FontFeatures.types(of: try TestFonts.hoefler())
            let ligatures = try #require(types.first { $0.key == .aat(1) })
            #expect(!ligatures.isExclusive)
            let common = try #require(ligatures.selectors.first { $0.setting == .aat(type: 1, selector: 2) })
            let rare = try #require(ligatures.selectors.first { $0.setting == .aat(type: 1, selector: 4) })
            #expect(ligatures.isOn(common, in: []))
            #expect(!ligatures.isOn(rare, in: []))
            #expect(common.offSetting == .aat(type: 1, selector: 3))
        }

        @Test("Accendere e poi spegnere una funzione riporta al font di partenza")
        func roundTrip() throws {
            let base = try TestFonts.hoefler()
            let ligatures = try #require(FontFeatures.types(of: base).first { $0.key == .aat(1) })
            let rare = try #require(ligatures.selectors.first { $0.setting == .aat(type: 1, selector: 4) })

            let on = ligatures.setting(rare, on: true, in: [])
            #expect(on == [.aat(type: 1, selector: 4)])
            let withRare = FontFeatures.font(base, with: on)
            #expect(FontFeatures.settings(of: withRare) == on)
            #expect(Shaper.glyphIDs(for: "ct st", font: withRare) == [643, 3, 644])

            let off = ligatures.setting(rare, on: false, in: FontFeatures.settings(of: withRare))
            #expect(off.isEmpty)
            let restored = FontFeatures.font(withRare, with: off)
            #expect(FontFeatures.settings(of: restored).isEmpty)
            #expect(Shaper.glyphIDs(for: "ct st", font: restored) == [70, 87, 3, 86, 87])
            #expect(restored.postScriptName == base.postScriptName)
        }

        @Test("Spegnere una funzione accesa per difetto: legature comuni di Hoefler Text")
        func turnOffDefault() throws {
            let base = try TestFonts.hoefler()
            let ligatures = try #require(FontFeatures.types(of: base).first { $0.key == .aat(1) })
            let common = try #require(ligatures.selectors.first { $0.setting == .aat(type: 1, selector: 2) })
            let settings = ligatures.setting(common, on: false, in: [])
            #expect(settings == [.aat(type: 1, selector: 3)])
            let font = FontFeatures.font(base, with: settings)
            #expect(Shaper.glyphIDs(for: "ffi", font: font).count == 3, "senza legature comuni ffi resta di tre glifi")
            #expect(!ligatures.isOn(common, in: FontFeatures.settings(of: font)))
        }

        @Test("In un tipo esclusivo una scelta sostituisce la precedente")
        func exclusiveSelection() throws {
            let base = try TestFonts.vulcanius()
            let alternates = try #require(FontFeatures.types(of: base).first { $0.key == .aat(17) })
            let eis = alternates.selectors[1], both = alternates.selectors[3], none = alternates.selectors[0]

            var settings = alternates.selecting(eis, in: [])
            settings = alternates.selecting(both, in: settings)
            #expect(settings == [.aat(type: 17, selector: 3)])
            let font = FontFeatures.font(FontFeatures.font(base, with: [.aat(type: 17, selector: 1)]), with: settings)
            #expect(Shaper.glyphIDs(for: TestFonts.gothicSample, font: font) == [33, 34, 3, 8, 24])
            #expect(alternates.activeSelector(in: FontFeatures.settings(of: font)) == both)

            #expect(alternates.selecting(none, in: settings).isEmpty)
        }
    }
}
