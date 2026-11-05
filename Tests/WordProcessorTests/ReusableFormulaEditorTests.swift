import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Formule riutilizzabili nell'editor", .serialized) @MainActor
struct ReusableFormulaEditorTests {
    @Test("Bacheca, testo, Annulla e file conservano la definizione comune")
    func completePath() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        let index = try #require(board.sheet.styles.firstIndex { $0.name == "Body" })
        let definition = ReusableFormula(name: "Corpo comune", resultType: .length, expression: .constant(.length(18)))
        board.sheet.reusableFormulas = [definition]
        var formula = StyleFormula(operation: StylePropertyOperation(.set, .size, .length(12, .points)))
        formula.binding = .call(definition.id, arguments: [:])
        board.sheet.styles[index].values.size = nil
        board.sheet.styles[index].formulas.removeAll { $0.operation.property == .size }
        board.sheet.styles[index].formulas.append(formula)
        #expect(board.validationIssue == nil)
        board.apply(); h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        board.sheet.reusableFormulas[0].expression = .constant(.length(22))
        board.apply(); h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 22)
        h.undo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        h.redo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 22)
        let read = try DocumentFormat.document(from: h.document.data(ofType: TextDocument.typeName))
        #expect(read.styles.resolveCharacter(paragraphStyle: "Body", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase).size == 22)
        #expect(read.styles.style(named: "Body")?.formulas.contains { $0.binding != nil } == true)
        board.removeReusableFormula(definition.id)
        #expect(board.sheet.reusableFormulas.count == 1)
        #expect(board.problem != nil)
    }
}
