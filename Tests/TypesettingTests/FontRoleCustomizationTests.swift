import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Personalizzazione delle equivalenze")
    struct FontRoleCustomizationTests {
        private func resolver(_ weight: Double) -> FontRoleResolver {
            FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Skia", role: .bold, equivalence: FontRoleEquivalence(
                    variableInstance: VariableFontInstance(fontName: "Skia-Regular", variations: [AxisValue(tag: "wght", value: weight)]))),
            ]))
        }

        @Test("Uno stile usa l'equivalenza personalizzata senza creare un ruolo diretto")
        func styledRole() throws {
            var body = StyleValues(); body.family = "Skia"; body.size = 12
            var strong = StyleValues(); strong.bold = true
            let sheet = StyleSheet(styles: [
                NamedStyle(name: "Body", target: .paragraph, values: body),
                NamedStyle(name: "Strong", target: .character, values: strong),
            ])
            let regular = CharacterStyle(fontName: "Skia-Regular", size: 12)
            let text = NSMutableAttributedString(string: "Una parola", attributes: TextStyling.characterAttributes(for: regular).attributes)
            text.addAttribute(.paragraphStyleName, value: "Body", range: NSRange(location: 0, length: text.length))
            let range = (text.string as NSString).range(of: "parola")
            TextStyling.restyle(text, range: range, from: sheet, to: sheet, resolver: resolver(2.2)) { $0.character = "Strong" }
            let font = try #require(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) as CTFont
            #expect(FontVariations.values(of: font) == [AxisValue(tag: "wght", value: 2.2)])
            #expect(text.attribute(.fontRole, at: range.location, effectiveRange: nil) == nil)
        }

        @Test("Riapplicare aggiorna ruoli diretti ed ereditati, ma solo i primi conservano il contrassegno")
        func reapplyDirectAndInherited() throws {
            let regular = CharacterStyle(fontName: "Skia-Regular", size: 12,
                                         variations: [AxisValue(tag: "wdth", value: 0.8)])
            let text = NSMutableAttributedString(string: "Diretto ereditato", attributes: TextStyling.characterAttributes(for: regular).attributes)
            let direct = NSRange(location: 0, length: 7)
            TextStyling.apply(role: .bold, in: text, range: direct, resolver: resolver(2.2))
            let inherited = NSRange(location: 8, length: 9)
            let inheritedBold = try #require(resolver(1.9499).applying(role: .bold, to: regular))
            var withoutIntention = inheritedBold; withoutIntention.fontRole = nil
            text.setAttributes(TextStyling.characterAttributes(for: withoutIntention).attributes, range: inherited)

            #expect(TextStyling.reapplyFontRoles(in: text, range: NSRange(location: 0, length: text.length), resolver: resolver(2.7)) == 2)
            for location in [0, 8] {
                let font = try #require(text.attribute(.font, at: location, effectiveRange: nil) as? NSFont) as CTFont
                #expect(FontVariations.values(of: font) == [AxisValue(tag: "wght", value: 2.7), AxisValue(tag: "wdth", value: 0.8)])
            }
            #expect(text.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "bold")
            #expect(text.attribute(.fontRole, at: 8, effectiveRange: nil) == nil)
        }
    }
}
