import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// La voce di più capoversi nell'editor: il comando del menu «Continua la voce prima», i segni composti e Annulla.
@Suite("Voci di più capoversi nell'editor", .serialized) @MainActor
struct ListItemContinuationEditorTests {
    @Test("Continua la voce prima: un segno per due capoversi, e Annulla lo toglie")
    func continuePreviousItem() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Uno", "Due"])
        defer { h.close() }
        h.select(0, length: h.text.utf16.count)
        h.editor.applyListMarker("1.")
        #expect(try #require(h.editor.currentLayout()).pages[0].markers.count == 3)

        // Il cursore nel secondo paragrafo: il primo è la voce che continua.
        h.select(7)
        #expect(h.editor.canContinuePreviousItem())
        h.editor.toggleListContinuation(nil)
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == true)
        let layout = try #require(h.editor.currentLayout())
        #expect(layout.pages[0].markers.count == 2, "«1.» sulla voce, «2.» sulla terza: la continuazione non ha segno")
        #expect(h.text == "Prima.\nUno\nDue")

        h.undo()
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == false)
        #expect(try #require(h.editor.currentLayout()).pages[0].markers.count == 3)

        h.redo()
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == true)
        #expect(try #require(h.editor.currentLayout()).pages[0].markers.count == 2)
    }

    @Test("La continuazione si toglie, e al primo paragrafo non si può mettere")
    func newItemAndFirstParagraph() {
        let h = EditorHarness(paragraphs: ["Prima.", "Uno"])
        defer { h.close() }
        h.select(0, length: h.text.utf16.count)
        h.editor.applyListMarker("1.")

        // Il primo paragrafo non ha una voce prima da continuare.
        h.select(0)
        #expect(!h.editor.canContinuePreviousItem())
        let item = NSMenuItem(title: "", action: #selector(EditorWindowController.toggleListContinuation(_:)), keyEquivalent: "")
        #expect(!h.editor.validateMenuItem(item))

        h.select(7)
        h.editor.toggleListContinuation(nil)
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == true)
        #expect(h.editor.canContinuePreviousItem())
        #expect(h.editor.validateMenuItem(item) && item.state == .on)

        // Di nuovo voce intera.
        h.editor.toggleListContinuation(nil)
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == false)
    }

    @Test("Un altro capoverso della voce resta nel file e torna aprendolo")
    func fileRoundTrip() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Uno", "Due"])
        defer { h.close() }
        h.select(0, length: h.text.utf16.count)
        h.editor.applyListMarker("1.")
        h.select(7)
        h.editor.toggleListContinuation(nil)

        let written = DocumentFormat.string(for: h.editor.store.document)
        #expect(written.contains("<document version=\"20\""), "\(written)")
        #expect(written.contains("continue-previous-item=\"on\""))
        // Il deposito dell'editor non porta le Liste predefinite (le prende dalle preferenze), quindi non si confronta
        // il documento intero: la seconda scrittura di ciò che si è riletto deve essere la stessa.
        let reread = try DocumentFormat.document(from: written)
        #expect(DocumentFormat.string(for: reread) == written)
        #expect(reread.blocks.compactMap { block -> Bool? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.list?.continuesPreviousItem
        } == [false, true, false])
    }
}
