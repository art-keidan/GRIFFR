import Foundation
import Testing
@testable import Typesetting

@Suite("Formule riutilizzabili")
struct ReusableFormulaTests {
    @Test("Una chiamata passa un parametro e sopravvive alla rinomina")
    func callAndRename() throws {
        let parameter = FormulaParameter(name: "distanza", type: .length)
        var inner = ReusableFormula(name: "Rientro", parameters: [parameter], resultType: .length,
                                    expression: .add(.parameter(parameter.id), .constant(.length(6))))
        let outer = ReusableFormula(name: "Composta", resultType: .length,
                                    expression: .call(inner.id, arguments: [parameter.id: .constant(.length(12))]))
        inner.name = "Nuovo nome"
        inner.parameters[0].name = "misura"
        let library = ReusableFormulaLibrary(definitions: [outer, inner])
        #expect(try library.evaluate(outer.id) == .length(18))
    }

    @Test("Rifiuta cicli, argomenti mancanti e tipi incompatibili")
    func invalidGraphs() throws {
        let a = UUID(), b = UUID()
        let first = ReusableFormula(id: a, name: "A", resultType: .number, expression: .call(b, arguments: [:]))
        let second = ReusableFormula(id: b, name: "B", resultType: .number, expression: .call(a, arguments: [:]))
        #expect(throws: ReusableFormulaError.cycle([a, b, a])) { try ReusableFormulaLibrary(definitions: [first, second]).validate() }
        let parameter = FormulaParameter(name: "x", type: .length)
        let callee = ReusableFormula(name: "C", parameters: [parameter], resultType: .length, expression: .parameter(parameter.id))
        let missing = ReusableFormula(name: "D", resultType: .length, expression: .call(callee.id, arguments: [:]))
        #expect(throws: ReusableFormulaError.invalidArguments(callee.id)) { try ReusableFormulaLibrary(definitions: [callee, missing]).validate() }
        let bad = ReusableFormula(name: "E", resultType: .number, expression: .add(.constant(.number(1)), .constant(.length(1))))
        #expect(throws: ReusableFormulaError.incompatibleTypes) { try ReusableFormulaLibrary(definitions: [bad]).validate() }
    }

    @Test("Le definizioni e i riferimenti sopravvivono al salvataggio")
    func documentRoundTrip() throws {
        let parameter = FormulaParameter(name: "misura", type: .length)
        let base = ReusableFormula(name: "Base", parameters: [parameter], resultType: .length,
                                   expression: .add(.parameter(parameter.id), .constant(.length(6))))
        let caller = ReusableFormula(name: "Composta", resultType: .length,
                                     expression: .call(base.id, arguments: [parameter.id: .constant(.length(12))]))
        var styles = StyleSheet()
        styles.reusableFormulas = [base, caller]
        let document = Document(styles: styles)
        let xml = DocumentFormat.string(for: document)
        #expect(xml.contains("version=\"18\""))
        let reopened = try DocumentFormat.document(from: xml)
        #expect(reopened.styles.reusableFormulas == [base, caller])
        #expect(try ReusableFormulaLibrary(definitions: reopened.styles.reusableFormulas).evaluate(caller.id) == .length(18))
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"9\"")) }
    }
}

extension ReusableFormulaTests {
    private func boundSheet() -> (StyleSheet, UUID) {
        let parameter = FormulaParameter(name: "misura", type: .length)
        let definition = ReusableFormula(name: "Con margine", parameters: [parameter], resultType: .length,
            expression: .add(.parameter(parameter.id), .constant(.length(6))))
        var formula = StyleFormula(operation: StylePropertyOperation(.set, .leftIndent, .length(1, .points)))
        formula.binding = .call(definition.id, arguments: [parameter.id: .constant(.length(12))])
        var sheet = StyleSheet(styles: [NamedStyle(name: "Relativo", target: .paragraph, formulas: [formula])])
        sheet.reusableFormulas = [definition]
        return (sheet, definition.id)
    }
    @Test("Una formula collegata cambia la resa e conserva il collegamento nel file")
    func boundStyle() throws {
        var (sheet, _) = boundSheet()
        #expect(sheet.resolveParagraph(styleName: "Relativo").leftIndent == 18)
        sheet.reusableFormulas[0].expression = .add(.parameter(sheet.reusableFormulas[0].parameters[0].id), .constant(.length(10)))
        #expect(sheet.resolveParagraph(styleName: "Relativo").leftIndent == 22)
        let document = Document(styles: sheet)
        let xml = DocumentFormat.string(for: document)
        #expect(xml.contains("version=\"18\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.styles[0].formulas[0].binding == sheet.styles[0].formulas[0].binding)
        #expect(read.styles.resolveParagraph(styleName: "Relativo").leftIndent == 22)
        #expect(read.styles.formulaDefinition(for: .leftIndent, inStyle: "Relativo")?.isCalculated == true)
    }
    @Test("Incollare importa le dipendenze e separa le identità in conflitto")
    func importedBindings() throws {
        let (sheet, id) = boundSheet()
        var source = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Relativo", inlines: [.text(TextRun("Testo", style: TextStyling.styleBase))]))])
        let (text, _) = source.attributedString()
        var destination = source
        destination.styles.reusableFormulas[0].expression = .constant(.length(40))
        let result = DefinitionImport.merge(text, from: source, into: destination, policy: .renameCopies)
        #expect(result.styles.reusableFormulas.count == 2)
        #expect(result.styles.reusableFormulas.first { $0.name != "Con margine" }?.id != id)
        #expect(result.styles.resolveParagraph(styleName: "Relativo (2)").leftIndent == 18)
        #expect(result.styles.resolveParagraph(styleName: "Relativo").leftIndent == 40)
        source.styles = result.styles
        #expect(source.styles.formulaReferenceProblem() == nil)
    }
}

extension ReusableFormulaTests {
    @Test("Il campione distribuito si apre e risolve il rientro")
    func sample() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Appunti/prova-formule-riutilizzabili.grx"))
        let document = try DocumentFormat.document(from: data)
        #expect(document.styles.resolveParagraph(styleName: "Citazione calcolata").leftIndent == 18)
    }
}
