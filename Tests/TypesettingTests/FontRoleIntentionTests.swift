import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Intenzioni dei ruoli tipografici")
    struct FontRoleIntentionTests {
        @Test("Il ruolo applicato resta nel testo, nel documento e nel file")
        func roleRoundTrip() throws {
            let regular = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let bold = try #require(FontRoleResolver().applying(role: .bold, to: regular))
            #expect(bold.fontName == "HoeflerText-Black" && bold.fontRole == .bold)
            #expect(FontRoleResolver().role(of: bold) == .bold)

            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: bold))]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("font-role=\"bold\""))
            #expect(try DocumentFormat.document(from: written) == document)

            let text = document.attributedString().text
            #expect(text.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "bold")
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
        }

        @Test("Il corsivo conserva il peso esatto, statico o variabile; il ruolo resta solo se la faccia lo realizza")
        func italicKeepsWeight() throws {
            let resolver = FontRoleResolver()
            let demiBold = CharacterStyle(fontName: "AvenirNext-DemiBold", size: 12)
            let italic = try #require(resolver.applying(role: .boldItalic, to: demiBold, keepingWeight: true))
            #expect(italic.fontName == "AvenirNext-DemiBoldItalic" && italic.fontRole == nil, "faccia libera, non Bold Italic")
            let back = try #require(resolver.applying(role: .bold, to: italic, keepingWeight: true))
            #expect(back.fontName == "AvenirNext-DemiBold")

            let regular = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let hoeflerItalic = try #require(resolver.applying(role: .italic, to: regular, keepingWeight: true))
            #expect(hoeflerItalic.fontName == "HoeflerText-Italic" && hoeflerItalic.fontRole == .italic, "una faccia di ruolo resta di ruolo")

            if FontVariations.font(named: "Merriweather-LightItalic", size: 12, preferringVariable: true).map(FontVariations.isVariable) == true {
                let semi = CharacterStyle(fontName: "Merriweather-LightItalic", size: 12, variations: [AxisValue(tag: "wght", value: 600)])
                let upright = try #require(resolver.applying(role: .bold, to: semi, keepingWeight: true))
                #expect(upright.variations.contains(AxisValue(tag: "wght", value: 600)))
                #expect(TextStyling.traits(ofFace: upright.fontName)?.italic == false)
            }
        }

        @Test("Il corsivo segue le equivalenze dei ruoli: da R va alla faccia di I, da B a quella di BI, e ritorno")
        func italicFollowsRoleTable() throws {
            var table = FontRoleTable()
            table.customize(family: "Baskerville", role: .regular, to: FontRoleEquivalence(staticFace: "Baskerville-SemiBold"))
            table.customize(family: "Baskerville", role: .italic, to: FontRoleEquivalence(staticFace: "Baskerville-Italic"))
            table.customize(family: "Baskerville", role: .bold, to: FontRoleEquivalence(staticFace: "Baskerville-Bold"))
            table.customize(family: "Baskerville", role: .boldItalic, to: FontRoleEquivalence(staticFace: "Baskerville-SemiBoldItalic"))
            let resolver = FontRoleResolver(table: table)
            let regular = try #require(resolver.applying(role: .regular, to: CharacterStyle(fontName: "Baskerville", size: 12)))
            #expect(regular.fontName == "Baskerville-SemiBold")
            let italic = try #require(resolver.applying(role: .italic, to: regular, keepingWeight: true))
            #expect(italic.fontName == "Baskerville-Italic" && italic.fontRole == .italic, "\(italic.fontName)")
            let back = try #require(resolver.applying(role: .regular, to: italic, keepingWeight: true))
            #expect(back.fontName == "Baskerville-SemiBold" && back.fontRole == .regular, "\(back.fontName)")
            let bold = try #require(resolver.applying(role: .bold, to: regular))
            let boldItalic = try #require(resolver.applying(role: .boldItalic, to: bold, keepingWeight: true))
            #expect(boldItalic.fontName == "Baskerville-SemiBoldItalic" && boldItalic.fontRole == .boldItalic, "\(boldItalic.fontName)")
            // Senza ruolo registrato, ma con la faccia della tabella: vale lo stesso.
            let bare = CharacterStyle(fontName: "Baskerville-SemiBold", size: 12)
            #expect(resolver.applying(role: .italic, to: bare, keepingWeight: true)?.fontName == "Baskerville-Italic")
        }

        @Test("Un'istanza variabile che cambia solo negli assi entra davvero nel testo",
              .enabled(if: FontVariations.font(named: "Merriweather-Light", size: 12, preferringVariable: true).map(FontVariations.isVariable) == true))
        func variableInstanceReallyChanges() throws {
            let base = try #require(FontVariations.font(named: "Merriweather-Light", size: 12, preferringVariable: true))
            let light = FontVariations.font(base, with: [AxisValue(tag: "wght", value: 400)])
            let semi = FontVariations.font(base, with: [AxisValue(tag: "wght", value: 600)])
            // Per macOS i due font sono uguali: per questo serve `writeFont`.
            #expect(light == semi && !TextStyling.sameFont(light, semi))
            let text = NSMutableAttributedString(string: "Peso", attributes: TextStyling.withFontAxes([.font: light as NSFont]))
            let all = NSRange(location: 0, length: text.length)
            TextStyling.writeFont(semi as NSFont, in: text, range: all)
            func weight() -> [AxisValue] { FontVariations.values(of: (text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont) as CTFont) }
            #expect(weight() == [AxisValue(tag: "wght", value: 600)])
            // Lo stesso per il cursore degli assi.
            TextStyling.updateVariations(in: text, range: all, ofFontNamed: FontVariations.baseName(of: semi)) { _ in [AxisValue(tag: "wght", value: 650)] }
            #expect(weight() == [AxisValue(tag: "wght", value: 650)])
            #expect(text.attribute(.fontAxes, at: 0, effectiveRange: nil) as? String == "wght=650")
        }

        @Test("Cambiare ruolo conserva gli altri assi; scegliere una faccia cancella l'intenzione")
        func attributedTextAndAxes() throws {
            let regular = CharacterStyle(fontName: "Skia-Regular", size: 12,
                                         variations: [AxisValue(tag: "wdth", value: 0.8)], fontRole: .regular)
            let text = NSMutableAttributedString(string: "Testo", attributes: TextStyling.characterAttributes(for: regular).attributes)
            let all = NSRange(location: 0, length: text.length)
            #expect(TextStyling.apply(role: .bold, in: text, range: all) == 1)
            let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
            #expect(FontVariations.values(of: font) == [AxisValue(tag: "wght", value: 1.9499), AxisValue(tag: "wdth", value: 0.8)])
            #expect(text.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "bold")

            TextStyling.setFont(postScriptName: "HoeflerText-Regular", in: text, range: all)
            #expect(text.attribute(.fontRole, at: 0, effectiveRange: nil) == nil)
        }

        @Test("Un documento precedente con un'istanza variabile rivela il ruolo dagli assi")
        func legacyVariableRole() {
            let bold = CharacterStyle(fontName: "Skia-Regular", size: 12,
                                      variations: [AxisValue(tag: "wght", value: 1.9499)])
            #expect(FontRoleResolver().role(of: bold) == .bold)
        }

        @Test("L'intenzione salvata prevale sul nome e segue una nuova equivalenza")
        func intentionFollowsCustomization() throws {
            func resolver(_ weight: Double) -> FontRoleResolver {
                FontRoleResolver(table: FontRoleTable(customizations: [
                    .init(family: "Skia", role: .bold, equivalence: FontRoleEquivalence(
                        variableInstance: VariableFontInstance(fontName: "Skia-Regular", variations: [AxisValue(tag: "wght", value: weight)]))),
                ]))
            }
            let regular = CharacterStyle(fontName: "Skia-Regular", size: 12, fontRole: .regular)
            let bold = try #require(resolver(2.2).applying(role: .bold, to: regular))
            #expect(bold.fontRole == .bold && bold.variations == [AxisValue(tag: "wght", value: 2.2)])
            let changed = try #require(resolver(2.7).applying(role: .bold, to: bold))
            #expect(changed.variations == [AxisValue(tag: "wght", value: 2.7)])
        }
    }
}
