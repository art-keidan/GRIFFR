import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Editor della formula di un campo", .serialized) @MainActor
struct FieldFormulaEditorTests {
    private func field(_ h: EditorHarness, at index: Int) -> Field? {
        (h.attributed.attribute(.field, at: index, effectiveRange: nil) as? String).flatMap(Field.init(encoded:))
    }

    @Test("Doppio clic sul numero di pagina: la catena diventa «Documento → Numero delle pagine»; un passo di Annulla; il campo resta uno")
    func editThroughDoubleClick() throws {
        let h = EditorHarness(paragraphs: ["Pagina  di tutto."])
        defer { h.close() }
        h.select(7)
        h.editor.insert(field: .page)
        h.step()
        // Il doppio clic sul campo lo sceglie e ne apre la formula.
        h.editor.pagesMouseDown(at: 7, affinity: .downstream, clickCount: 2, extending: false)
        h.step()
        let model = try #require(h.editor.fieldEditor)
        #expect(h.selection == NSRange(location: 7, length: 1))
        #expect(model.editing && model.formula == .pageContainingNumber && model.result == "1")
        // Il documento non sta in una pagina: il passo cade, e il risultato diventa il solo che il documento dà.
        model.setOrigin(.document)
        #expect(model.formula == .documentPageCount && model.problem == nil && model.result == "1")
        model.finish?(model.formula)
        h.step()
        #expect(h.editor.fieldEditor == nil)
        #expect(field(h, at: 7) == .formula(.documentPageCount))
        #expect(h.text == "Pagina \(Field.placeholder) di tutto.", "lo stesso carattere, nessun campo in più")
        #expect(h.undoActionName == "Field Formula")
        h.undo()
        #expect(field(h, at: 7) == .formula(.pageContainingNumber))
        h.redo()
        #expect(field(h, at: 7) == .formula(.documentPageCount))
    }

    @Test("Nell'editor la catena resta valida: un passo, il ruolo, il risultato; Annulla non cambia il campo")
    func chainEditing() throws {
        let h = EditorHarness(paragraphs: ["Qui: ."])
        defer { h.close() }
        h.select(5)
        h.editor.insert(field: .page)
        h.step()
        h.select(5, length: 1)
        h.editor.editFieldFormula(nil)
        let model = try #require(h.editor.fieldEditor)
        // Dalla pagina alla sezione contenente: il ruolo è il primo offerto, e il numero resta, perché anche la sezione ne ha uno.
        model.replaceStep(at: 0, with: .containingSection(role: ""))
        #expect(model.formula == .sectionContainingNumber(role: model.roles.first ?? "chapter"))
        model.setRole("part", at: 0)
        model.setReading(.title)
        #expect(model.formula == .sectionContainingTitle(role: "part"))
        #expect(model.result == "", "fuori da ogni sezione la catena non scrive niente")
        // Senza passi la posizione non dà risultati: la diagnosi lo dice, e OK non si può dare.
        model.removeStep(at: 0)
        #expect(model.problem?.contains("add a step") == true)
        model.addStep(.containingPage)
        #expect(model.formula == .pageContainingNumber)
        model.finish?(nil)
        h.step()
        #expect(field(h, at: 5) == .formula(.pageContainingNumber), "Annulla lascia il campo com'era")
    }

    @Test("Inserisci › Campo › Altro campo…: la catena composta va al cursore")
    func insertCustom() throws {
        let h = EditorHarness(paragraphs: ["Totale: ."])
        defer { h.close() }
        let menu = NSMenu()
        FieldMenuFiller.shared.menuNeedsUpdate(menu)
        #expect(menu.items.last?.title == "Other Field…")
        h.select(8)
        h.editor.insertCustomField(nil)
        let model = try #require(h.editor.fieldEditor)
        #expect(!model.editing)
        model.setOrigin(.document)
        model.finish?(model.formula)
        h.step()
        #expect(field(h, at: 8) == .formula(.documentPageCount))
        #expect(h.undoActionName == "Field")
    }
}
