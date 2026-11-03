import CoreText
import Testing
import Typesetting

extension TypesettingSuite {
    /// Valori di riferimento misurati dall'utente con Core Text. Se uno cambia, lo shaping è cambiato.
    @Suite("Regressione sugli ID di glifo")
    struct GlyphRegressionTests {
        @Test("Vulcanius: alternative con selettori personalizzati", arguments: [
            ([FeatureSetting](), [15, 25, 3, 8, 24]),
            ([.aat(type: 17, selector: 1)], [33, 25, 3, 8, 24]),
            ([.aat(type: 17, selector: 2)], [15, 34, 3, 8, 24]),
            ([.aat(type: 17, selector: 3)], [33, 34, 3, 8, 24]),
        ])
        func vulcanius(settings: [FeatureSetting], expected: [Int]) throws {
            let font = FontFeatures.font(try TestFonts.vulcanius(), with: settings)
            let glyphs = Shaper.glyphs(for: TestFonts.gothicSample, font: font)
            #expect(glyphs.map { Int($0.id) } == expected)
            #expect(glyphs.allSatisfy { $0.fontName == "Vulcanius" }, "nessun glifo deve venire da un font di ripiego")
        }

        @Test("Hoefler Text: predefinito, legature rare, maiuscoletto", arguments: [
            ([FeatureSetting](), [70, 87, 3, 86, 87, 3, 631, 3, 20, 21, 22, 23]),
            ([.aat(type: 1, selector: 4)], [643, 3, 644, 3, 631, 3, 20, 21, 22, 23]),
            ([.aat(type: 3, selector: 3)], [462, 479, 3, 478, 479, 3, 465, 465, 468, 3, 20, 21, 22, 23]),
        ])
        func hoefler(settings: [FeatureSetting], expected: [Int]) throws {
            let font = FontFeatures.font(try TestFonts.hoefler(), with: settings)
            let glyphs = Shaper.glyphs(for: TestFonts.latinSample, font: font)
            #expect(glyphs.map { Int($0.id) } == expected)
            #expect(glyphs.allSatisfy { $0.fontName == "HoeflerText-Regular" })
        }
    }
}
