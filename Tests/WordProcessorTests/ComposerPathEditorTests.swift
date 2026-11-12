import Testing
import SwiftUI
@testable import Typesetting
@testable import WordProcessor

@Suite("Editor condiviso dei percorsi", .serialized) @MainActor
struct ComposerPathEditorTests {
    @Test("Le scelte del percorso modificano la bozza del campo e seguono il soggetto raggiunto")
    func fieldPathUsesDraftAndCatalog() throws {
        let model = FieldFormulaEditorModel(formula: .pageContainingNumber, roles: ["chapter"], editing: true) { _ in "" }
        let view = FieldFormulaEditorView(model: model)
        guard case .node(let root) = try #require(view.pathRows.first) else {
            Issue.record("Missing root"); return
        }
        try #require(root.choices.first { $0.title == "Document" }).select()
        #expect(model.formula == .documentPageCount)
        guard case .node(let read) = try #require(view.pathRows.last) else {
            Issue.record("Missing reading"); return
        }
        #expect(read.choices.map(\.title) == ["Number of pages"])
        #expect(model.problem == nil)
        try #require(root.choices.first { $0.title == "Position" }).select()
        #expect(model.problem != nil)
        #expect(model.stepChoices(at: 0).contains(.containingPage))
    }

    @Test("Le scelte tipizzate invocano l'operazione sulla fonte autorevole")
    func choicesWriteThrough() throws {
        var current = 1
        let choices = ComposerPathChoice.choices([2, 3], title: { String($0) }) { current = $0 }
        try #require(choices.last).select()
        #expect(current == 3)
    }

    @Test("I bersagli proposti dipendono dalla validazione della proprietà")
    func styleTargetsRespectValidator() {
        let character = FormulaQualifiers(condition: .constant(.init()), target: .constant(.paragraph),
                                          operation: StylePropertyOperation(.set, .size, .length(12, .points)),
                                          styleNames: [], selections: [])
        let paragraph = FormulaQualifiers(condition: .constant(.init()), target: .constant(.paragraph),
                                          operation: StylePropertyOperation(.set, .leftIndent, .length(12, .points)),
                                          styleNames: [], selections: [])
        #expect(character.targetChoices.contains(.firstWords(2)))
        #expect(!paragraph.targetChoices.contains(.firstWords(2)))
        #expect(paragraph.targetChoices.contains(.paragraph))
    }
}
