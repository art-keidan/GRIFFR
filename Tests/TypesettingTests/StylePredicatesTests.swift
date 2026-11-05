import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Predicati degli stili · Imposta, Aggiungi e Sottrai")
    struct StylePredicatesTests {
        private let resolver = FontRoleResolver()
        private var initial: StylePredicateState {
            StylePredicateState(character: CharacterStyle(fontName: "HoeflerText-Regular", size: 12))
        }

        @Test("Imposta sostituisce il ruolo completo, Aggiungi unisce e Sottrai rimuove i tratti")
        func roleMatrix() throws {
            for before in FontRole.allCases {
                let character = try #require(resolver.applying(role: before, to: initial.character))
                let input = StylePredicateState(character: character)
                for requested in FontRole.allCases {
                    let set = try StylePropertyOperation(.set, .font, .font(requested)).applied(to: input)
                    let add = try StylePropertyOperation(.add, .font, .font(requested)).applied(to: input)
                    let subtract = try StylePropertyOperation(.subtract, .font, .font(requested)).applied(to: input)
                    let difference = FontRole(italic: before.isItalic && !requested.isItalic,
                                              bold: before.isBold && !requested.isBold)
                    let union = FontRole(italic: before.isItalic || requested.isItalic,
                                         bold: before.isBold || requested.isBold)
                    #expect(resolver.role(of: set.character) == requested)
                    #expect(resolver.role(of: add.character) == union)
                    #expect(resolver.role(of: subtract.character) == difference)
                    #expect(subtract.character.size == 12 && subtract.paragraph == input.paragraph)
                    if difference == before { #expect(subtract == input) }
                    #expect(resolver.family(of: set.character) == "Hoefler Text")
                    #expect(set.character.size == 12 && add.character.size == 12)
                    #expect(set.paragraph == input.paragraph && add.paragraph == input.paragraph)
                }
            }
        }

        @Test("Il caso dell'autore cambia la faccia effettiva, mantenendo lingua e colore")
        func italicExampleAndDiscreteValues() throws {
            var input = initial
            input.character = try #require(resolver.applying(role: .italic, to: input.character))
            input.character.color = "#123456"
            input.character.language = "la"
            let set = try StylePropertyOperation(.set, .font, .font(.bold)).applied(to: input)
            let add = try StylePropertyOperation(.add, .font, .font(.bold)).applied(to: input)
            #expect(set.character.fontName == "HoeflerText-Black")
            #expect(add.character.fontName == "HoeflerText-BlackItalic")
            #expect(set.character.color == "#123456" && add.character.language == "la")
            let centered = try StylePropertyOperation(.set, .alignment, .alignment(.center)).applied(to: input)
            #expect(centered.character == input.character && centered.paragraph.alignment == .center)
            let restoredLanguage = try StylePropertyOperation(.set, .language, .language(nil)).applied(to: input)
            #expect(restoredLanguage.character.language == nil)
            #expect(restoredLanguage.character.fontName == input.character.fontName)
        }

        @Test("Il ruolo passa dalle equivalenze del documento e conserva gli assi estranei")
        func variableAndCustomization() throws {
            let custom = FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Hoefler Text", role: .bold,
                      equivalence: FontRoleEquivalence(staticFace: "HoeflerText-Regular"))
            ]))
            let set = try StylePropertyOperation(.set, .font, .font(.bold)).applied(to: initial, resolver: custom)
            #expect(set.character.fontName == "HoeflerText-Regular")
            #expect(set.character.fontRole == .bold)
            var variable = initial
            variable.character = CharacterStyle(fontName: "Skia-Regular", size: 17,
                variations: [AxisValue(tag: "wdth", value: 0.9)], prefersVariableFont: true)
            let updated = try StylePropertyOperation(.set, .font, .font(.bold)).applied(to: variable)
            #expect(updated.character.variations.contains { $0.tag == "wdth" && abs($0.value - 0.9) < 0.001 })
            #expect(updated.character.variations.contains { $0.tag == "wght" })
            #expect(updated.character.size == 17)
        }

        @Test("Unità, ordine delle formule e ricomposizioni ripetute")
        func lengthsAndEvaluation() throws {
            var input = initial
            input.paragraph.spaceBefore = 12
            let add = StylePropertyOperation(.add, .spaceBefore, .length(6, .points))
            let set = StylePropertyOperation(.set, .spaceBefore, .length(6, .points))
            #expect(try add.applied(to: input).paragraph.spaceBefore == 18)
            #expect(try set.applied(to: input).paragraph.spaceBefore == 6)
            #expect(try StylePropertyOperation.evaluate([set, add], from: input).paragraph.spaceBefore == 12)
            #expect(try StylePropertyOperation.evaluate([add, set], from: input).paragraph.spaceBefore == 6)
            for _ in 0..<100 {
                #expect(try StylePropertyOperation.evaluate([add], from: input).paragraph.spaceBefore == 18)
            }
            let inch = try StylePropertyOperation(.set, .leftIndent, .length(1, .inches)).applied(to: input)
            #expect(inch.paragraph.leftIndent == 72)
            let mixed = try StylePropertyOperation(.add, .leftIndent, .length(25.4, .millimetres)).applied(to: inch)
            #expect(abs(mixed.paragraph.leftIndent - 144) < 0.0001)
            #expect(try StylePropertyOperation(.add, .spaceBefore, .length(-6, .points)).applied(to: input).paragraph.spaceBefore == 6)
        }

        @Test("Sottrai applica unità, ordine e limiti delle misure")
        func subtractionLengths() throws {
            var input = initial
            input.paragraph.spaceBefore = 12
            input.paragraph.leftIndent = 24
            let operation = StylePropertyOperation(.subtract, .spaceBefore, .length(6, .points))
            #expect(try operation.applied(to: input).paragraph.spaceBefore == 6)
            #expect(try StylePropertyOperation(.subtract, .size, .length(2, .points)).applied(to: input).character.size == 10)
            #expect(try StylePropertyOperation(.subtract, .leftIndent, .length(1, .inches)).applied(to: input).paragraph.leftIndent == -48)
            let add = StylePropertyOperation(.add, .spaceBefore, .length(6, .points))
            #expect(try StylePropertyOperation.evaluate([add, operation], from: input) == input)
            for _ in 0..<100 { #expect(try operation.applied(to: input).paragraph.spaceBefore == 6) }
            #expect(throws: StylePredicateError.invalidLength(.spaceBefore)) {
                try StylePropertyOperation(.subtract, .spaceBefore, .length(13, .points)).applied(to: input)
            }
            #expect(throws: StylePredicateError.invalidLength(.size)) {
                try StylePropertyOperation(.subtract, .size, .length(12, .points)).applied(to: input)
            }
            #expect(throws: StylePredicateError.unsupportedPredicate(.subtract, .language)) {
                try StylePropertyOperation(.subtract, .language, .language("it")).applied(to: input)
            }
        }

        @Test("Una formula non valida fallisce senza cambiare l'ingresso")
        func invalidArguments() throws {
            let input = initial
            #expect(throws: StylePredicateError.incompatibleArgument(.font)) {
                try StylePropertyOperation(.set, .font, .length(12, .points)).applied(to: input)
            }
            #expect(throws: StylePredicateError.unsupportedPredicate(.add, .language)) {
                try StylePropertyOperation(.add, .language, .language("it")).applied(to: input)
            }
            for value in [Double.nan, .infinity, -.infinity, -1, 0] {
                #expect(throws: StylePredicateError.invalidLength(.size)) {
                    try StylePropertyOperation(.set, .size, .length(value, .points)).applied(to: input)
                }
            }
            #expect(throws: StylePredicateError.invalidLength(.spaceBefore)) {
                try StylePropertyOperation(.add, .spaceBefore, .length(-1, .points)).applied(to: input)
            }
            #expect(throws: StylePredicateError.invalidLength(.size)) {
                try StylePropertyOperation(.set, .size, .length(.greatestFiniteMagnitude, .inches)).applied(to: input)
            }
            let invalidResolver = FontRoleResolver(table: FontRoleTable(customizations: [
                .init(family: "Hoefler Text", role: .bold, equivalence: FontRoleEquivalence(staticFace: "NonEsiste"))
            ]))
            #expect(throws: StylePredicateError.unavailableFontRole(.bold)) {
                try StylePropertyOperation(.set, .font, .font(.bold)).applied(to: input, resolver: invalidResolver)
            }
            #expect(input == initial)
        }
    }
}
