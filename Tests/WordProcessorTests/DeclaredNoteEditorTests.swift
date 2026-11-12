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
}

