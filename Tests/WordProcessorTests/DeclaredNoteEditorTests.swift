import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Le note dichiarate nell'editor: lo stile «Body» dichiara una nota dopo la quinta parola; il testo si scrive con
/// Insert › Declared Note Text…, si annulla, si salva, e resta quando la nota è sospesa.
@Suite("Note dichiarate nell'editor", .serialized) @MainActor
struct DeclaredNoteEditorTests {
    private func harness() throws -> EditorHarness {
        let h = EditorHarness(paragraphs: ["uno due tre quattro cinque sei", "Altro."])
        var sheet = h.editor.settings.styles
        let index = try #require(sheet.styles.firstIndex { $0.name == "Body" })
        sheet.styles[index].declaredNotes = [try #require(DeclaredNote(word: 5))]
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Declare Note")
        h.document.undoManager?.removeAllActions()
        h.step()
        return h
    }

    @Test("Il testo si scrive dal menu, si annulla e si ripete, si salva; la nota è sospesa senza la quinta parola e torna con lei")
    func writeAndSuspend() throws {
        let h = try harness()
        defer { h.close() }
        h.select(0)
        let entries = h.editor.declaredNotesAtSelection()
        #expect(entries.count == 1 && entries.first?.mark == "1" && entries.first?.word == 5)
        let item = NSMenuItem(title: "", action: #selector(EditorWindowController.editDeclaredNoteText(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item))
        // Il secondo capoverso ha una parola sola: la sua nota c'è, ma è sospesa.
        h.select(("uno due tre quattro cinque sei\n" as NSString).length + 1)
        #expect(h.editor.declaredNotesAtSelection().first?.mark == nil)

        h.select(0)
        h.editor.declaredNoteTextAnswerForTests = ["Glossa dell'autore"]
        h.editor.editDeclaredNoteText(nil)
        let slot = try #require(entries.first?.slot)
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa dell'autore"])
        #expect(DocumentFormat.string(for: h.editor.currentDocument()).contains("text=\"Glossa dell"))

        h.undo()
        #expect(h.editor.settings.declaredNoteTexts.isEmpty)
        h.redo()
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa dell'autore"])

        // Via «cinque sei»: la nota non si presenta più, ma il suo testo resta; Annulla la riporta.
        let words = ("uno due tre quattro" as NSString).length
        h.select(words, length: (" cinque sei" as NSString).length)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.text.hasPrefix("uno due tre quattro\n"))
        #expect(h.editor.currentLayout()?.declaredNotes.isEmpty == true)
        h.select(0)
        #expect(h.editor.declaredNotesAtSelection().first?.mark == nil)
        #expect(h.editor.settings.declaredNoteTexts[slot] == "Glossa dell'autore")
        h.undo()
        #expect(h.editor.currentLayout()?.declaredNotes.first?.mark == "1")

        // Un testo vuoto toglie la voce: la nota resta, senza testo.
        h.select(0)
        h.editor.declaredNoteTextAnswerForTests = ["  "]
        h.editor.editDeclaredNoteText(nil)
        #expect(h.editor.settings.declaredNoteTexts.isEmpty)
        #expect(h.editor.currentLayout()?.declaredNotes.count == 1)
    }

    @Test("Dal compositore: una nota dopo la quinta parola, la parola cambiata, Applica, Annulla e il file")
    func declareFromComposer() throws {
        let h = EditorHarness(paragraphs: ["uno due tre quattro cinque sei"])
        defer { h.close() }
        h.editor.showStyleComposer(style: "Body")
        let model = try #require(h.editor.composerModel)
        defer { h.editor.composerController?.close() }
        let id = try #require(model.addDeclaredNote())
        #expect(model.currentStyle?.declaredNotes.map(\.word) == [5])
        model.updateDeclaredNote(id, word: 3)
        model.updateDeclaredNote(id, word: 0)  // una parola che non c'è non si accetta
        #expect(model.currentStyle?.declaredNotes.first?.word == 3)
        #expect(model.valid && model.dirty)
        model.apply()
        #expect(model.problem == nil)
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.map(\.id) == [id])
        let placed = try #require(h.editor.currentLayout()?.declaredNotes.first)
        #expect(placed.position == ("uno due tre" as NSString).length && placed.mark == "1")
        #expect(DocumentFormat.string(for: h.editor.currentDocument()).contains("<declare-note id=\"\(id.uuidString)\" word=\"3\"/>"))
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.isEmpty == true)
        #expect(h.editor.currentLayout()?.declaredNotes.isEmpty == true)
        // Togliere la dichiarazione dalla bozza.
        model.discard()
        let again = try #require(model.addDeclaredNote())
        model.removeDeclaredNote(again)
        #expect(model.currentStyle?.declaredNotes.isEmpty == true)
    }

    /// Un editor in cui «Body» dichiara la nota e il primo capoverso ne ha già il testo.
    private func harnessWithText() throws -> (EditorHarness, DeclaredNoteSlot) {
        let h = try harness()
        h.select(0)
        h.editor.declaredNoteTextAnswerForTests = ["Glossa"]
        h.editor.editDeclaredNoteText(nil)
        let slot = try #require(h.editor.settings.declaredNoteTexts.keys.first)
        h.document.undoManager?.removeAllActions()
        h.step()
        return (h, slot)
    }

    @Test("Rinominare lo stile dalla scheda Stili non stacca il testo dalla sua nota; Annulla torna al nome di prima")
    func renameKeepsText() throws {
        let (h, slot) = try harnessWithText()
        defer { h.close() }
        h.editor.renameStyle("Body", to: "Corpo")
        let renamed = DeclaredNoteSlot(paragraph: slot.paragraph, declaringStyle: "Corpo", declaration: slot.declaration)
        #expect(h.editor.settings.declaredNoteTexts == [renamed: "Glossa"])
        #expect(h.editor.inactiveDeclaredNotes().isEmpty)
        #expect(h.editor.currentLayout()?.declaredNotes.count == 1)
        h.undo()
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa"])
    }

    @Test("Togliere la dichiarazione dal compositore chiede che cosa fare del testo: conservarlo come nota inattiva, eliminarlo, o non applicare")
    func removalFromComposer() throws {
        let (h, slot) = try harnessWithText()
        defer { h.close() }
        h.editor.showStyleComposer(style: "Body")
        let model = try #require(h.editor.composerModel)
        defer { h.editor.composerController?.close() }
        let declaration = slot.declaration

        // Annulla la domanda: niente si applica.
        h.editor.declaredTextChoiceForTests = .cancel
        model.removeDeclaredNote(declaration)
        model.apply()
        #expect(model.problem != nil)
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.count == 1)

        // Conserva: la dichiarazione va via, il testo resta come nota inattiva, e gli avvisi lo dicono.
        h.editor.declaredTextChoiceForTests = .keep
        model.problem = nil
        model.apply()
        #expect(model.problem == nil)
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.isEmpty == true)
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa"])
        #expect(h.editor.inactiveDeclaredNotes() == [slot])
        #expect(h.editor.warningTitles.contains { $0.contains("inactive") })
        let item = NSMenuItem(title: "", action: #selector(EditorWindowController.editInactiveDeclaredNotes(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item))
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.count == 1)
        #expect(h.editor.inactiveDeclaredNotes().isEmpty)

        // Elimina: il testo va via con la dichiarazione, e un solo Annulla riporta l'una e l'altro.
        h.editor.declaredTextChoiceForTests = .delete
        model.discard()
        model.removeDeclaredNote(declaration)
        model.apply()
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.isEmpty == true)
        #expect(h.editor.settings.declaredNoteTexts.isEmpty)
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Body")?.declaredNotes.count == 1)
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa"])
    }

    @Test("Togliere lo stile che dichiara la nota chiede del testo; le note inattive si ritrovano e si modificano")
    func removalOfStyleAndInactiveSheet() throws {
        let h = EditorHarness(paragraphs: ["uno due tre quattro cinque sei", "Altro."])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        var glossa = NamedStyle(name: "Glossa", target: .paragraph, basedOn: "Body")
        glossa.declaredNotes = [try #require(DeclaredNote(word: 5))]
        sheet.styles.append(glossa)
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "New Style")
        h.select(0)
        h.editor.applyNamedStyle(.paragraph, name: "Glossa")
        h.editor.declaredNoteTextAnswerForTests = ["Glossa"]
        h.editor.editDeclaredNoteText(nil)
        let slot = try #require(h.editor.settings.declaredNoteTexts.keys.first)
        #expect(slot.declaringStyle == "Glossa")
        // Un evento dopo l'altro, come nell'uso: la scrittura del testo e la rimozione sono due passi di Annulla.
        h.step()

        h.editor.declaredTextChoiceForTests = .delete
        h.editor.removeStyle("Glossa")
        #expect(h.editor.settings.styles.style(named: "Glossa") == nil)
        #expect(h.editor.settings.declaredNoteTexts.isEmpty)
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Glossa") != nil)
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa"])

        // Il capoverso cambia stile: la nota non ha più dichiarazione, senza domanda; il testo resta, inattivo.
        h.select(0)
        h.editor.applyNamedStyle(.paragraph, name: "Body")
        #expect(h.editor.inactiveDeclaredNotes() == [slot])
        // Dal foglio delle note inattive il testo si cambia, e un campo vuoto lo elimina.
        h.editor.declaredNoteTextAnswerForTests = ["Glossa rivista"]
        h.editor.editInactiveDeclaredNotes(nil)
        #expect(h.editor.settings.declaredNoteTexts == [slot: "Glossa rivista"])
        h.editor.declaredNoteTextAnswerForTests = [""]
        h.editor.editInactiveDeclaredNotes(nil)
        #expect(h.editor.settings.declaredNoteTexts.isEmpty)
        #expect(h.editor.inactiveDeclaredNotes().isEmpty)
    }

    @Test("Un rimando a una nota dichiarata nel testo: legge il numero, segue la rinomina dello stile, e senza lo stile legge (??)")
    func referenceInEditor() throws {
        let h = EditorHarness(paragraphs: ["uno due tre quattro cinque sei", "Vedi "])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        var glossa = NamedStyle(name: "Glossa", target: .paragraph, basedOn: "Body")
        glossa.declaredNotes = [try #require(DeclaredNote(word: 5))]
        sheet.styles.append(glossa)
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "New Style")
        h.select(0)
        h.editor.applyNamedStyle(.paragraph, name: "Glossa")
        h.step()
        let placed = try #require(h.editor.currentLayout()?.declaredNotes.first)
        let slot = DeclaredNoteSlot(paragraph: try #require(placed.paragraphID), declaringStyle: "Glossa", declaration: placed.declaration)

        h.select(h.text.utf16.count)
        h.editor.insert(field: .reference(ObjectReference(declaredNote: slot)))
        h.step()
        func reference() -> ObjectReference? {
            let text = h.editor.editingText
            var found: ObjectReference?
            text.enumerateAttribute(.field, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if let encoded = value as? String, case .reference(let reference)? = Field(encoded: encoded) { found = reference }
            }
            return found
        }
        let inserted = try #require(reference())
        #expect(inserted.declaredNote == slot)
        #expect(h.editor.currentLayout()?.referenceValue(inserted) == "1")

        h.editor.renameStyle("Glossa", to: "Glossa marginale")
        h.step()
        let renamed = try #require(reference())
        #expect(renamed.declaredNote?.declaringStyle == "Glossa marginale")
        #expect(h.editor.currentLayout()?.referenceValue(renamed) == "1")
        h.undo()
        #expect(reference()?.declaredNote?.declaringStyle == "Glossa")

        // Lo stile tolto: il capoverso passa a «Body», che non dichiara la nota; il rimando resta, e legge (??).
        h.editor.removeStyle("Glossa")
        h.step()
        let after = try #require(reference())
        #expect(after.declaredNote?.declaringStyle == "Glossa")
        #expect(h.editor.currentLayout()?.referenceValue(after) == "(??)")
    }

    @Test("Nel foglio dei rimandi una riga di nota dichiarata costruisce il rimando alla sua occorrenza, e si riconosce scelta")
    func referencePickerRows() {
        let slot = DeclaredNoteSlot(paragraph: UUID(), declaringStyle: "Glossa", declaration: UUID())
        let declared = ObjectReferenceEditor.Target(id: UUID(), title: "1", kind: "Declared note · Glossa", number: "1", excerpt: "", declaredNote: slot)
        let floating = ObjectReferenceEditor.Target(id: UUID(), title: "2", kind: "Footnote", number: "2", excerpt: "")
        let reference = declared.reference(reading: .page)
        #expect(reference.declaredNote == slot && reference.target == slot.declaration && reference.reading == .page)
        #expect(declared.isTarget(of: reference) && !floating.isTarget(of: reference))
        let toFloating = floating.reference()
        #expect(floating.isTarget(of: toFloating) && !declared.isTarget(of: toFloating))
        // Un rimando a un flottante con lo stesso UUID della dichiarazione non è un rimando alla nota dichiarata.
        #expect(!declared.isTarget(of: ObjectReference(target: slot.declaration)))
    }
}

