import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// Funzioni, assi e corpo ottico dati a mano: ciascuno con la sua provenienza, e ciascuno si toglie o si porta nello
    /// stile da solo. Font di prova: Hoefler Text (funzioni AAT) e Skia (assi peso e larghezza).
    @Suite("Ispettore: funzioni e assi uno per uno")
    struct FontDetailsTests {
        /// Una funzione di Hoefler Text da accendere a mano: le legature rare.
        private let rare = FeatureSetting.aat(type: 1, selector: 4)

        /// Una funzione non esclusiva di Hoefler Text da spegnere a mano (le legature comuni, accese in partenza).
        private func ligaturesOff() throws -> FeatureSetting {
            let types = FontFeatures.types(of: CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil))
            let selector = try #require(types.filter { !$0.isExclusive }.flatMap(\.selectors).first { $0.isDefault && $0.offSetting != nil })
            return try #require(selector.offSetting)
        }

        /// Un paragrafo «Citazione» composto con gli stili dati.
        private func sample(_ sheet: StyleSheet) -> NSMutableAttributedString {
            let style = sheet.resolveCharacter(paragraphStyle: "Citazione", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            return NSMutableAttributedString(attributedString: Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(styleName: "Citazione", style: sheet.resolveParagraph(styleName: "Citazione"),
                                     inlines: [.text(TextRun("Una frase qualsiasi.", style: style))])),
            ]).attributedString().text)
        }

        /// Dà a mano funzioni e assi ai primi tre caratteri.
        private func give(_ text: NSMutableAttributedString, features: [FeatureSetting]? = nil, variations: [AxisValue]? = nil) {
            var style = TextStyling.characterStyle(in: text, at: 0)!
            if let features { style.features = features }
            if let variations { style.variations = variations }
            TextStyling.apply(style, to: text, range: NSRange(location: 0, length: 3))
        }

        private func detail(_ wanted: FontDetail, _ text: NSAttributedString, _ sheet: StyleSheet) -> InspectedDetail? {
            TextStyling.inspectDetails(in: text, range: NSRange(location: 0, length: 0), sheet: sheet).first { $0.detail == wanted }
        }

        private func key(_ setting: FeatureSetting) -> FontDetail {
            .feature(TextStyling.featureKey(of: setting, types: FontFeatures.types(of: CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil))))
        }

        @Test("Ogni funzione data a mano compare da sola, con la sua provenienza")
        func ownFeatures() throws {
            let sheet = StyleSheet.builtIn
            let text = sample(sheet)
            let off = try ligaturesOff()
            give(text, features: [rare, off])
            #expect(key(rare) != key(off), "legature rare e comuni sono due funzioni")
            #expect(detail(key(rare), text, sheet)?.source == .own)
            #expect(detail(key(off), text, sheet)?.source == .own)
            #expect(TextStyling.inspectDetails(in: text, range: NSRange(location: 5, length: 0), sheet: sheet).isEmpty, "il resto del testo non ne ha")
        }

        @Test("Togliere una funzione lascia le altre")
        func resetOne() throws {
            let sheet = StyleSheet.builtIn
            let text = sample(sheet)
            let off = try ligaturesOff()
            give(text, features: [rare, off])
            TextStyling.resetDetail(key(rare), in: text, range: NSRange(location: 0, length: 3), sheet: sheet)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.features == [off])
            #expect(detail(key(rare), text, sheet) == nil)
        }

        @Test("Portare nello stile una funzione non porta le altre")
        func moveOne() throws {
            let sheet = StyleSheet.builtIn
            let text = sample(sheet)
            let off = try ligaturesOff()
            give(text, features: [rare, off])
            let updated = try #require(TextStyling.sheet(sheet, takingDetail: key(rare), from: text, at: 0))
            #expect(updated.style(named: "Citazione")?.values.features == [rare])
            TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: sheet, to: updated)
            #expect(detail(key(rare), text, updated)?.source == .style("Citazione"))
            #expect(detail(key(off), text, updated)?.source == .own, "le legature restano date a mano")
            #expect(TextStyling.characterStyle(in: text, at: 0).map { Set($0.features) } == [rare, off])
            #expect(TextStyling.characterStyle(in: text, at: 5)?.features == [rare], "il resto del paragrafo prende le legature rare dallo stile")
        }

        @Test("Quando lo stile cambia, una funzione data a mano non impedisce alle altre di seguirlo")
        func restylePerFeature() throws {
            let sheet = StyleSheet.builtIn
            let text = sample(sheet)
            let off = try ligaturesOff()
            give(text, features: [rare])
            var updated = sheet
            let position = try #require(updated.styles.firstIndex { $0.name == "Citazione" })
            updated.styles[position].values.features = [off]
            TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: sheet, to: updated)
            #expect(TextStyling.characterStyle(in: text, at: 0).map { Set($0.features) } == [rare, off])
            #expect(detail(key(off), text, updated)?.source == .style("Citazione"))
            #expect(detail(key(rare), text, updated)?.source == .own)
        }

        @Test("Il maiuscoletto non è più una funzione: nello stile e nel testo è una proprietà, e il corsivo non lo tocca")
        func smallCapsIsAProperty() throws {
            var sheet = StyleSheet.builtIn
            let position = try #require(sheet.styles.firstIndex { $0.name == "Citazione" })
            sheet.styles[position].values.smallCaps = .lowercase
            let text = sample(sheet)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .lowercase)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.features == [], "le forme tecniche non stanno fra le funzioni")
            let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(FontFeatures.settings(of: font as CTFont) == [.aat(type: 3, selector: 3)], "Hoefler Text tiene la sua forma, 3/3")
            // Come il pulsante del corsivo: cambia la faccia e conserva il resto.
            var italic = try #require(TextStyling.characterStyle(in: text, at: 0))
            italic.fontName = "HoeflerText-Italic"
            TextStyling.apply(italic, to: text, range: NSRange(location: 0, length: 3))
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .lowercase)
            #expect(TextStyling.inspectDetails(in: text, range: NSRange(location: 0, length: 0), sheet: sheet).isEmpty,
                    "nessuna funzione data a mano")
            let inspected = TextStyling.inspect(.character, in: text, range: NSRange(location: 0, length: 0), sheet: sheet).first { $0.property == .smallCaps }
            #expect(inspected?.source == .style("Citazione"))
        }

        /// Gli stili con «Citazione» in Skia: il testo ha il font dello stile, e gli assi si possono portare nello stile.
        private func skiaSheet() throws -> StyleSheet {
            var sheet = StyleSheet.builtIn
            let position = try #require(sheet.styles.firstIndex { $0.name == "Citazione" })
            sheet.styles[position].values.family = "Skia"
            return sheet
        }

        @Test("Gli assi uno per uno: portare il peso non porta la larghezza; togliere la larghezza lascia il peso")
        func axes() throws {
            let sheet = try skiaSheet()
            let text = sample(sheet)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.fontName == "Skia-Regular")
            give(text, variations: [AxisValue(tag: "wght", value: 2), AxisValue(tag: "wdth", value: 0.8)])
            #expect(detail(.axis("wght"), text, sheet)?.source == .own)
            #expect(detail(.axis("wdth"), text, sheet)?.source == .own)

            let updated = try #require(TextStyling.sheet(sheet, takingDetail: .axis("wght"), from: text, at: 0))
            #expect(updated.style(named: "Citazione")?.values.variations == [AxisValue(tag: "wght", value: 2)])
            TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: sheet, to: updated)
            #expect(detail(.axis("wght"), text, updated)?.source == .style("Citazione"))
            #expect(detail(.axis("wdth"), text, updated)?.source == .own)

            TextStyling.resetDetail(.axis("wdth"), in: text, range: NSRange(location: 0, length: 3), sheet: updated)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.variations == [AxisValue(tag: "wght", value: 2)])
            #expect(detail(.axis("wdth"), text, updated) == nil)
        }

        @Test("Con un font diverso da quello dello stile, una funzione non si porta nello stile da sola")
        func otherFont() throws {
            let sheet = StyleSheet.builtIn
            let text = sample(sheet)
            var skia = StyleValues()
            skia.family = "Skia"
            TextStyling.setValue(skia, of: .family, in: text, range: NSRange(location: 0, length: 3))
            give(text, variations: [AxisValue(tag: "wght", value: 2)])
            #expect(detail(.axis("wght"), text, sheet)?.source == .own)
            #expect(TextStyling.sheet(sheet, takingDetail: .axis("wght"), from: text, at: 0) == nil)
            // Togliere il peso lascia la famiglia.
            TextStyling.resetDetail(.axis("wght"), in: text, range: NSRange(location: 0, length: 3), sheet: sheet)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.fontName == "Skia-Regular")
            #expect(TextStyling.characterStyle(in: text, at: 0)?.variations == [])
        }
    }
}
