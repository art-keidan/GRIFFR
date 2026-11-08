import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Condizioni e comportamenti nella bacheca", .serialized) @MainActor
struct ContextStyleEditorTests {
    @Test("Invio sceglie lo stile successivo una volta sola, senza creare altre sezioni durante la composizione")
    func nextStyleOnReturn() throws {
        let h = EditorHarness(paragraphs: ["Capitolo"])
        defer { h.close() }
        let sheet = h.editor.settings.styles.settingDirective(.nextStyle, argument: .styleName("Body"), inStyle: "Heading 1")
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Stile successivo")
        h.select(0, length: 8)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        let titles = SectionEditing.titles(in: h.attributed).map(\.mark.id)
        #expect(titles.count == 1)
        h.select(8)
        h.document.undoManager?.removeAllActions()
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.editor.selectionStyleName(.paragraph) == "Body")
        h.type("Corpo")
        #expect(h.attributed.attribute(.paragraphStyleName, at: 9, effectiveRange: nil) as? String == "Body")
        #expect((h.attributed.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)?.pointSize == 12)
        h.editor.layoutPages(); h.editor.layoutPages()
        #expect(SectionEditing.titles(in: h.attributed).map(\.mark.id) == titles)
        let data = try h.document.data(ofType: TextDocument.typeName)
        #expect(try DocumentFormat.document(from: data).styles.values(of: "Heading 1").nextStyle == "Body")
        h.undo()
        h.undo()
        #expect(h.text == "Capitolo")
        #expect(SectionEditing.titles(in: h.attributed).map(\.mark.id) == titles)
    }

    @Test("La pill Quando conserva la condizione cambiando il valore e controlla il campione")
    func conditionPills() throws {
        let h = EditorHarness(paragraphs: ["Titolo", "Corpo"])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let model = try #require(h.editor.composerModel)
        model.selectStyle("Body")
        model.addStyleFormula()
        let id = try #require(model.sheet.style(named: "Body")?.formulas.last?.id)
        model.updateFormula(id, operation: StylePropertyOperation(.set, .pageStartSpacing, .pageStart(.distance(72))))
        #expect(model.sheet.style(named: "Body")?.formulas.last?.when.position == .firstOnPage)
        model.previewFirstOnPage = false
        #expect(try model.preview(try #require(model.sheet.style(named: "Body"))).directives.pageStartSpacing == nil)
        model.previewFirstOnPage = true
        #expect(try model.preview(try #require(model.sheet.style(named: "Body"))).directives.pageStartSpacing == .distance(72))
        model.updateFormula(id, operation: StylePropertyOperation(.set, .pageStartSpacing, .pageStart(.distance(36))))
        #expect(model.sheet.style(named: "Body")?.formulas.last?.when.position == .firstOnPage)
        model.apply(); h.step()
        #expect(h.editor.currentLayout()?.pageStarts[0]?.requested == 36)
        h.undo()
        #expect(h.editor.currentLayout()?.pageStarts[0] == nil)
        h.redo()
        #expect(h.editor.currentLayout()?.pageStarts[0]?.requested == 36)
        let loaded = try DocumentFormat.document(from: h.document.data(ofType: TextDocument.typeName))
        #expect(loaded.styles.style(named: "Body")?.formulas.contains { $0.id == id && $0.when.position == .firstOnPage } == true)
    }

}
