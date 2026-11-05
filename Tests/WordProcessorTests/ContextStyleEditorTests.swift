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
        let sheet = h.editor.settings.styles.settingDirective(.nextStyle, argument: .styleName("Testo"), inStyle: "Titolo 1")
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Stile successivo")
        h.select(0, length: 8)
        h.editor.applyNamedStyle(.paragraph, name: "Titolo 1")
        h.step()
        let titles = SectionEditing.titles(in: h.attributed).map(\.mark.id)
        #expect(titles.count == 1)
        h.select(8)
        h.document.undoManager?.removeAllActions()
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.editor.selectionStyleName(.paragraph) == "Testo")
        h.type("Corpo")
        #expect(h.attributed.attribute(.paragraphStyleName, at: 9, effectiveRange: nil) as? String == "Testo")
        #expect((h.attributed.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)?.pointSize == 12)
        h.editor.layoutPages(); h.editor.layoutPages()
        #expect(SectionEditing.titles(in: h.attributed).map(\.mark.id) == titles)
        let data = try h.document.data(ofType: TextDocument.typeName)
        #expect(try DocumentFormat.document(from: data).styles.values(of: "Titolo 1").nextStyle == "Testo")
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
        model.selectStyle("Testo")
        model.addStyleFormula()
        let id = try #require(model.sheet.style(named: "Testo")?.formulas.last?.id)
        model.updateFormula(id, operation: StylePropertyOperation(.set, .pageStartSpacing, .pageStart(.distance(72))))
        #expect(model.sheet.style(named: "Testo")?.formulas.last?.when.position == .firstOnPage)
        model.previewFirstOnPage = false
        #expect(try model.preview(try #require(model.sheet.style(named: "Testo"))).directives.pageStartSpacing == nil)
        model.previewFirstOnPage = true
        #expect(try model.preview(try #require(model.sheet.style(named: "Testo"))).directives.pageStartSpacing == .distance(72))
        model.updateFormula(id, operation: StylePropertyOperation(.set, .pageStartSpacing, .pageStart(.distance(36))))
        #expect(model.sheet.style(named: "Testo")?.formulas.last?.when.position == .firstOnPage)
        model.apply(); h.step()
        #expect(h.editor.currentLayout()?.pageStarts[0]?.requested == 36)
        h.undo()
        #expect(h.editor.currentLayout()?.pageStarts[0] == nil)
        h.redo()
        #expect(h.editor.currentLayout()?.pageStarts[0]?.requested == 36)
        let loaded = try DocumentFormat.document(from: h.document.data(ofType: TextDocument.typeName))
        #expect(loaded.sourceVersion == 8)
        #expect(loaded.styles.style(named: "Testo")?.formulas.contains { $0.id == id && $0.when.position == .firstOnPage } == true)
    }

    @Test("Le regole storiche si modificano dalla bacheca mantenendo posizione e condizione")
    func historicalRules() throws {
        let h = EditorHarness(paragraphs: ["Uno due tre"])
        defer { h.close() }
        let rule = TextRule(target: .firstWords(1), paragraphStyle: "Testo", condition: .init(.words, .lessOrEqual, 3), styleName: "Forte")
        h.editor.changeRules([rule], styles: h.editor.settings.styles)
        h.step()
        h.editor.openStyleComposer(nil)
        let model = try #require(h.editor.composerModel)
        model.section = .rules
        model.rules[0].target = .firstWords(2)
        model.apply(); h.step()
        #expect(h.editor.settings.rules[0].condition == rule.condition)
        #expect(h.editor.settings.rules[0].target == .firstWords(2))
        h.undo()
        #expect(h.editor.settings.rules == [rule])
    }

    @Test("L'ispettore mostra la formula contestuale attiva e conserva un'eccezione esplicita")
    func inspectorSeesContext() throws {
        let h = EditorHarness(paragraphs: ["Uno due tre"])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        let i = try #require(sheet.styles.firstIndex { $0.name == "Testo" })
        sheet.styles[i].formulas.append(StyleFormula(operation: StylePropertyOperation(.set, .size, .length(18, .points)),
            when: StyleCondition(measurement: .init(.words, .lessOrEqual, 3))))
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Formula contestuale")
        h.select(0, length: 3)
        h.editor.inspect(.character)
        let inspector = h.editor.inspectorForTests
        let value = try #require(inspector.values.first { $0.property == .size })
        #expect(value.value.size == 18)
        if case .rule = value.source {} else { Issue.record("Manca la provenienza dalla formula contestuale") }
        inspector.change(.size) { $0.size = 20 }
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20)
        #expect(TextStyling.ruleExceptions(in: h.attributed, at: 0).contains(.size))
        #expect(inspector.values.first { $0.property == .size }?.value.size == 20)
    }

}
