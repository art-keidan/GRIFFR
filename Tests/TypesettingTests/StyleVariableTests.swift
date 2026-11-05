import Foundation
import Testing
@testable import Typesetting

@Suite("Variabili degli stili")
struct StyleVariableTests {
    /// «Distanza» = Rientro con margine(Base 12 pt), con margine 6 pt; il rientro sinistro e lo spazio prima la usano.
    private func sheet() -> (StyleSheet, StyleVariable) {
        let base = FormulaParameter(name: "Base", type: .length)
        let definition = ReusableFormula(name: "Rientro con margine", parameters: [base], resultType: .length,
                                         expression: .add(.parameter(base.id), .constant(.length(6))))
        let distance = StyleVariable(name: "Distanza", expression: .call(definition.id, arguments: [base.id: .constant(.length(12))]))
        var indent = StyleFormula(operation: StylePropertyOperation(.set, .leftIndent, .length(0, .points)))
        indent.binding = .variable(distance.id)
        var before = StyleFormula(operation: StylePropertyOperation(.set, .spaceBefore, .length(0, .points)))
        before.binding = .variable(distance.id)
        var sheet = StyleSheet(styles: [NamedStyle(name: "Citazione", target: .paragraph, formulas: [indent, before], variables: [distance])])
        sheet.reusableFormulas = [definition]
        return (sheet, distance)
    }

    @Test("Base 12 pt più margine 6 pt dà Distanza, 18 pt, a due proprietà; con margine 10 pt dà 22 pt")
    func distance() throws {
        var (sheet, _) = sheet()
        let paragraph = sheet.resolveParagraph(styleName: "Citazione")
        #expect(paragraph.leftIndent == 18 && paragraph.spaceBefore == 18)
        let parameter = sheet.reusableFormulas[0].parameters[0].id
        sheet.reusableFormulas[0].expression = .add(.parameter(parameter), .constant(.length(10)))
        #expect(sheet.resolveParagraph(styleName: "Citazione").leftIndent == 22)
        #expect(sheet.formulaReferenceProblem() == nil)
        #expect(sheet.formulaDefinition(for: .leftIndent, inStyle: "Citazione")?.calculation?.contains("Distanza") == true)
    }

    @Test("Rinominare la variabile non interrompe le formule; una variabile può usarne un'altra")
    func renameAndChain() throws {
        var (sheet, distance) = sheet()
        sheet.styles[0].variables[0].name = "Rientro"
        #expect(sheet.resolveParagraph(styleName: "Citazione").leftIndent == 18)
        let double = StyleVariable(name: "Doppia", expression: .add(.variable(distance.id), .variable(distance.id)))
        sheet.styles[0].variables.append(double)
        sheet.styles[0].formulas[1].binding = .variable(double.id)
        #expect(sheet.resolveParagraph(styleName: "Citazione").spaceBefore == 36)
    }

    @Test("Una variabile assente, un giro di variabili e nomi doppi sono diagnosi, non silenzi")
    func diagnostics() throws {
        var (sheet, distance) = sheet()
        var missing = sheet
        missing.styles[0].variables = []
        #expect(missing.formulaReferenceProblem()?.contains("variabile") == true)
        var cycle = sheet
        let other = UUID()
        cycle.styles[0].variables = [StyleVariable(id: distance.id, name: "Distanza", expression: .variable(other)),
                                     StyleVariable(id: other, name: "Altra", expression: .variable(distance.id))]
        #expect(cycle.formulaReferenceProblem()?.contains("circolare") == true)
        sheet.styles[0].variables.append(StyleVariable(name: "Distanza", expression: .constant(.length(1))))
        #expect(sheet.formulaReferenceProblem()?.contains("nomi") == true)
    }

    @Test("Il file conserva le variabili dalla versione 12; una versione precedente non le accetta")
    func roundTrip() throws {
        let (sheet, distance) = sheet()
        let xml = DocumentFormat.string(for: Document(styles: sheet))
        #expect(xml.contains("version=\"12\"") && xml.contains("<variable id=\"\(distance.id.uuidString)\" name=\"Distanza\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.styles[0].variables == sheet.styles[0].variables)
        #expect(read.styles.resolveParagraph(styleName: "Citazione").leftIndent == 18)
        #expect(DocumentFormat.string(for: read) == xml, "riscritto uguale, senza duplicati")
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"12\"", with: "version=\"11\"")) }
    }

    @Test("Incollare uno stile con variabili porta la formula che esse richiamano, con l'identità rinnovata nei conflitti")
    func importCarriesVariables() throws {
        let (sheet, _) = sheet()
        let source = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Citazione", inlines: [.text(TextRun("Testo", style: TextStyling.styleBase))]))])
        let (text, _) = source.attributedString()
        let empty = DefinitionImport.merge(text, from: source, into: Document(), policy: .renameCopies)
        #expect(empty.styles.reusableFormulas.count == 1)
        #expect(empty.styles.resolveParagraph(styleName: "Citazione").leftIndent == 18)
        var destination = source
        destination.styles.reusableFormulas[0].expression = .constant(.length(40))
        let merged = DefinitionImport.merge(text, from: source, into: destination, policy: .renameCopies)
        #expect(merged.styles.resolveParagraph(styleName: "Citazione (2)").leftIndent == 18)
        #expect(merged.styles.resolveParagraph(styleName: "Citazione").leftIndent == 40)
        #expect(merged.styles.formulaReferenceProblem() == nil)
    }
}
