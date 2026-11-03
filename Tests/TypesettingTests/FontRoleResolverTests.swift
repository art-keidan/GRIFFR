import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Risoluzione dei ruoli tipografici")
    struct FontRoleResolverTests {
        @Test("Una famiglia statica produce la faccia del ruolo; una variabile produce base e assi")
        func staticAndVariableResolution() throws {
            let resolver = FontRoleResolver()
            let hoefler = try #require(resolver.resolve(family: "Hoefler Text", role: .bold))
            #expect(hoefler.installation == .staticFiles && hoefler.fontName == "HoeflerText-Black")
            #expect(hoefler.variations.isEmpty && !hoefler.prefersVariableFont)
            let skia = try #require(resolver.resolve(family: "Skia", role: .bold))
            #expect(skia.installation == .variableFont && skia.fontName == "Skia-Regular")
            #expect(skia.variations == [AxisValue(tag: "wght", value: 1.9499)])
        }

        @Test("La forma richiesta è vincolante; in automatico si ripiega su quella disponibile")
        func requestedInstallation() {
            let resolver = FontRoleResolver()
            #expect(resolver.resolve(family: "Skia", role: .bold, installation: .staticFiles) == nil)
            #expect(resolver.resolve(family: "Skia", role: .bold, installation: .variableFont)?.installation == .variableFont)
            #expect(resolver.resolve(family: "Hoefler Text", role: .bold, installation: .variableFont) == nil)
            #expect(resolver.resolve(family: "Skia", role: .bold)?.installation == .variableFont)
        }

        @Test("Gli assi del ruolo sostituiscono quelli correnti, conserva gli altri, ignora gli assenti e limita i valori")
        func preserveCompatibleAxes() throws {
            let instance = VariableFontInstance(fontName: "Skia-Regular", variations: [
                AxisValue(tag: "wght", value: 99), AxisValue(tag: "wdth", value: 0.9),
            ])
            let resolver = FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Skia", role: .bold, equivalence: FontRoleEquivalence(variableInstance: instance)),
            ]))
            let current = CharacterStyle(fontName: "Skia-Regular", size: 12, variations: [
                AxisValue(tag: "wght", value: 1.2), AxisValue(tag: "wdth", value: 0.8), AxisValue(tag: "opsz", value: 20),
            ], prefersVariableFont: true)
            let resolved = try #require(resolver.resolve(family: "Skia", role: .bold, current: current, preservingAxes: true))
            #expect(resolved.variations == [AxisValue(tag: "wght", value: 3.1999), AxisValue(tag: "wdth", value: 0.9)])
            let withoutCurrent = try #require(resolver.resolve(family: "Skia", role: .bold, current: current, preservingAxes: false))
            #expect(withoutCurrent.variations == resolved.variations, "qui entrambi gli assi sono sostituiti dal ruolo")
        }

        @Test("Una faccia o un'istanza inesistente non viene restituita come risultato valido")
        func invalidCustomization() {
            let resolver = FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Skia", role: .bold, equivalence: FontRoleEquivalence(staticFace: "NonEsiste")),
            ]))
            #expect(resolver.resolve(family: "Skia", role: .bold, installation: .staticFiles) == nil)
            #expect(resolver.resolve(family: "Skia", role: .bold, installation: .variableFont) == nil,
                    "la personalizzazione esclude il lato variabile automatico")
        }

        private static var notoSansInstalledTwice: Bool {
            guard let byName = NSFont(name: "NotoSans-Bold", size: 12), !FontVariations.isVariable(byName as CTFont),
                  let variable = FontVariations.font(named: "NotoSans-Bold", size: 12, preferringVariable: true) else { return false }
            return FontVariations.isVariable(variable)
        }

        @Test("Con due installazioni segue il corrente e la personalizzazione decide il grassetto", .enabled(if: notoSansInstalledTwice))
        func preserveInstallationAndCustomize() throws {
            let customized = FontRoleEquivalence(staticFace: "NotoSans-Medium",
                                                 variableInstance: VariableFontInstance(fontName: "NotoSans-Regular",
                                                                                        variations: [AxisValue(tag: "wght", value: 550)]))
            let resolver = FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Noto Sans", role: .bold, equivalence: customized),
            ]))
            let staticCurrent = CharacterStyle(fontName: "NotoSans-Regular", size: 12)
            let staticBold = try #require(resolver.resolve(family: "Noto Sans", role: .bold, current: staticCurrent))
            #expect(staticBold.installation == .staticFiles && staticBold.fontName == "NotoSans-Medium")
            let variableCurrent = CharacterStyle(fontName: "NotoSans-Regular", size: 12, prefersVariableFont: true)
            let variableBold = try #require(resolver.resolve(family: "Noto Sans", role: .bold, current: variableCurrent))
            #expect(variableBold.installation == .variableFont && variableBold.fontName == "NotoSans-Regular")
            #expect(variableBold.variations == [AxisValue(tag: "wght", value: 550)])
        }
    }
}
