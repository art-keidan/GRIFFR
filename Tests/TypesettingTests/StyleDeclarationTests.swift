import Foundation
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Catalogo e adattatore delle dichiarazioni di stile")
    struct StyleDeclarationTests {
        @Test("Ogni proprietà del formato 18 è disponibile negli stessi stili", arguments: StyleProperty.allCases)
        func catalog(property: StyleProperty) {
            let arithmetic: Set<StyleProperty> = [.font, .size, .spaceBefore, .spaceAfter, .firstLineIndent,
                                                   .leftIndent, .rightIndent, .lineSpacing]
            let character: Set<StyleProperty> = [.font, .size, .family, .face, .color, .smallCaps]
            let word = character.union([.language, .hyphenates])
            let predicates: [StylePredicate] = arithmetic.contains(property) ? [.set, .add, .subtract] : [.set]
            #expect(property.predicates == predicates)

            for owner in StyleTarget.allCases {
                let available = owner == .paragraph || (owner == .word ? word : character).contains(property)
                #expect(StyleDeclarationCatalog.properties(for: owner).contains(property) == available)
                for predicate in StylePredicate.allCases {
                    let formula = StyleFormula(operation: .init(predicate, property, property.initialArgument))
                    let declaration = StyleDeclaration(formula)
                    #expect(declaration.format18 == formula)
                    #expect(((try? declaration.validate(for: owner)) != nil) == (available && predicates.contains(predicate)))
                }
            }
        }

        @Test("Bersagli e confronti del formato 18 conservano gli argomenti nell’adattatore")
        func qualifiers() throws {
            let selection = UUID()
            let targets: [TextRule.Target] = [
                .paragraph, .firstLetter, .firstWords(3), .selection(selection), .firstSentence,
                .words(.capitals), .words(.romanNumerals), .words(.numbers), .words(.listed(["Roma", "Città"])),
                .firstLines(2), .lastLine
            ]
            let positions: [TextRule.Position] = [.any, .firstAfter("Titolo"), .sequenceStart, .firstOnPage]
            var measurements: [TextRule.Condition?] = [nil]
            for property in TextRule.Condition.Property.allCases {
                measurements += TextRule.Condition.Comparison.allCases.map { .init(property, $0, 2) }
            }

            for target in targets {
                for position in positions {
                    for measurement in measurements {
                        let formula = StyleFormula(operation: .init(.set, .applyStyle, .styleName("Strong")),
                                                   when: .init(position: position, measurement: measurement), target: target)
                        let declaration = StyleDeclaration(formula)
                        try declaration.validate(for: .paragraph)
                        #expect(declaration.format18 == formula)
                        let rule = declaration.textRule(owner: "Testo", declaredBy: "Base")
                        #expect(rule.paragraphStyle == "Testo")
                        #expect(rule.formulaOwner == "Testo")
                        #expect(rule.target == target)
                        #expect(rule.position == position)
                        #expect(rule.condition == measurement)
                        let composition = target.isLineTarget || position == .firstOnPage || measurement != nil
                        #expect(declaration.phase == (composition ? .composition : .textContext))
                    }
                }
            }
        }

        @Test("Binding, precedenza e identità dichiaranti sopravvivono alla compilazione")
        func inheritedTrace() throws {
            let condition = StyleCondition(position: .firstAfter("Titolo"), measurement: .init(.lastLineFill, .equal, 64))
            var first = StyleFormula(operation: .init(.add, .leftIndent, .length(1, .millimetres)), when: condition)
            first.binding = .constant(.length(6))
            let second = StyleFormula(id: first.id, operation: .init(.subtract, .leftIndent, .length(2, .points)), when: condition)
            let sheet = StyleSheet(styles: [
                NamedStyle(name: "Titolo", target: .paragraph),
                NamedStyle(name: "Base", target: .paragraph, formulas: [first]),
                NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Base", formulas: [second])
            ])
            #expect(StyleDeclaration(first).format18 == first)
            let compiled = sheet.compilingStyleRules()
            let rules = compiled.rules.filter { $0.paragraphStyle == "Figlio" }
            #expect(rules.count == 2)
            let inherited = try #require(rules.first)
            let local = try #require(rules.last)
            let owner = Data("Figlio".utf8).base64EncodedString()
            let base = Data("Base".utf8).base64EncodedString()
            #expect(inherited.styleName == FormulaTreatment.name(owner: owner, declaration: base, formula: first.id))
            #expect(local.styleName == FormulaTreatment.name(owner: owner, declaration: owner, formula: first.id))
            let values = sheet.values(of: "Figlio")
            let input = StylePredicateState(character: .init(fontName: "HoeflerText-Regular", size: 12))
            let context = TextRule.ParagraphContext(styleName: "Figlio", previousStyleName: "Titolo", isSequenceStart: false)
            let facts = TextRule.NaturalFacts(lineCount: 3, wordCount: 6, lastLineFill: 0.637, hyphenatedLines: 1)
            let trace = try values.formulaTrace(from: input, context: context, facts: facts)
            #expect(trace.map(\.id) == [first.id, second.id])
            #expect(trace.map(\.input.paragraph.leftIndent) == [0, 6])
            #expect(trace.map(\.output.paragraph.leftIndent) == [6, 4])
            let adapted = try rules.reduce(input) { state, rule in
                try compiled.sheet.values(of: rule.styleName).evaluatingFormulas(from: state)
            }
            #expect(adapted == trace.last?.output)
            #expect(try values.formulaTrace(from: input, context: context).isEmpty)
            var sequenceStart = context
            sequenceStart.isSequenceStart = true
            #expect(try values.formulaTrace(from: input, context: sequenceStart, facts: facts).isEmpty)
        }
    }
}
