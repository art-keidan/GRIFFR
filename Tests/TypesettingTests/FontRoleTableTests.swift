import AppKit
import Foundation
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Equivalenze dei ruoli tipografici")
    struct FontRoleTableTests {
        @Test("Le facce statiche seguono i quattro ruoli senza cambiare il comportamento attuale")
        func automaticStaticFaces() {
            let table = FontRoleTable()
            #expect(table.equivalence(family: "Hoefler Text", role: .regular).staticFace == "HoeflerText-Regular")
            #expect(table.equivalence(family: "Hoefler Text", role: .italic).staticFace == "HoeflerText-Italic")
            #expect(table.equivalence(family: "Hoefler Text", role: .bold).staticFace == "HoeflerText-Black")
            #expect(table.equivalence(family: "Hoefler Text", role: .boldItalic).staticFace == "HoeflerText-BlackItalic")
            #expect(table.equivalence(family: "Una famiglia che non esiste", role: .bold).isEmpty)
        }

        @Test("Skia trasforma le facce denominate in font di base e assi")
        func automaticVariableInstances() throws {
            let table = FontRoleTable()
            let regular = table.equivalence(family: "Skia", role: .regular)
            #expect(regular.variableInstance?.fontName == "Skia-Regular")
            #expect(regular.variableInstance?.variations.isEmpty == true)
            let bold = table.equivalence(family: "Skia", role: .bold)
            #expect(bold.staticFace == nil, "Skia è installato soltanto come font variabile")
            #expect(bold.variableInstance?.fontName == "Skia-Regular")
            #expect(bold.variableInstance?.variations == [AxisValue(tag: "wght", value: 1.9499)])
        }

        @Test("Una personalizzazione vale per un solo ruolo, si sostituisce e si ripristina")
        func customizationAndReset() {
            var table = FontRoleTable()
            let regular = table.equivalence(family: "Hoefler Text", role: .regular)
            let custom = FontRoleEquivalence(staticFace: "Famiglia-Medium",
                                             variableInstance: VariableFontInstance(fontName: "Famiglia-Regular",
                                                                                    variations: [AxisValue(tag: "wght", value: 550)]))
            table.customize(family: "Famiglia", role: .bold, to: custom)
            table.customize(family: "Famiglia", role: .bold, to: custom)
            #expect(table.customizations.count == 1, "la stessa riga viene sostituita, non duplicata")
            #expect(table.equivalence(family: "Famiglia", role: .bold) == custom)
            #expect(table.equivalence(family: "Famiglia", role: .regular).isEmpty)
            #expect(table.equivalence(family: "Hoefler Text", role: .regular) == regular, "le altre famiglie non cambiano")
            table.resetCustomization(family: "Famiglia", role: .bold)
            #expect(table.customizations.isEmpty && table.equivalence(family: "Famiglia", role: .bold).isEmpty)
        }

        @Test("Una personalizzazione può escludere una delle due forme")
        func customizationDoesNotInventTheOtherSide() {
            var table = FontRoleTable()
            table.customize(family: "Skia", role: .bold, to: FontRoleEquivalence(staticFace: "SoloStatico"))
            let chosen = table.equivalence(family: "Skia", role: .bold)
            #expect(chosen.staticFace == "SoloStatico")
            #expect(chosen.variableInstance == nil, "non si ricostruisce il lato variabile che l'utente ha escluso")
        }

        @Test("La tabella personalizzata si conserva con ruoli e assi")
        func persistence() throws {
            var table = FontRoleTable()
            let custom = FontRoleEquivalence(staticFace: "Famiglia-Medium",
                                             variableInstance: VariableFontInstance(fontName: "Famiglia-Regular",
                                                                                    variations: [AxisValue(tag: "wght", value: 550), AxisValue(tag: "wdth", value: 85)]))
            table.customize(family: "Famiglia", role: .bold, to: custom)
            let data = try JSONEncoder().encode(table)
            #expect(try JSONDecoder().decode(FontRoleTable.self, from: data) == table)
        }

        private static var notoSansInstalledTwice: Bool {
            guard let byName = NSFont(name: "NotoSans-Bold", size: 12), !FontVariations.isVariable(byName as CTFont),
                  let variable = FontVariations.font(named: "NotoSans-Bold", size: 12, preferringVariable: true) else { return false }
            return FontVariations.isVariable(variable)
        }

        @Test("Noto Sans collega automaticamente la stessa faccia statica e variabile", .enabled(if: notoSansInstalledTwice))
        func automaticBothInstallations() {
            let bold = FontRoleTable().equivalence(family: "Noto Sans", role: .bold)
            #expect(bold.staticFace == "NotoSans-Bold")
            #expect(bold.variableInstance?.fontName == "NotoSans-Regular")
            #expect(bold.variableInstance?.variations == [AxisValue(tag: "wght", value: 700)])
        }
    }
}
