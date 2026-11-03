import AppKit
import Testing
@testable import WordProcessor

/// La finestra: non si stringe sotto quanto chiedono i pannelli aperti, e chiudendola smette di ascoltare le notifiche.
@MainActor
@Suite("Finestra: larghezza minima e chiusura", .serialized)
struct WindowHousekeepingTests {
    @Test("La larghezza minima segue i pannelli: 700 nell'essenziale; nella dettagliata pagina, ispettore e albero")
    func minimumWidth() throws {
        let savedMode = InterfaceMode.lastChoice
        let savedTree = EditorWindowController.showsObjectTree
        defer { InterfaceMode.lastChoice = savedMode; EditorWindowController.showsObjectTree = savedTree }
        InterfaceMode.lastChoice = .simple
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        #expect(window.minSize.width == 700)

        h.editor.setInterfaceMode(.advanced)
        h.step()
        #expect(window.minSize.width >= 170 + 360 + 360, "albero, pagina e ispettore: \(window.minSize.width)")
        #expect(window.frame.width >= window.minSize.width)
        let withTree = window.minSize.width

        h.editor.toggleObjectTree(nil)
        h.step()
        #expect(window.minSize.width >= 360 + 360 && window.minSize.width < withTree, "senza albero: \(window.minSize.width)")

        h.editor.setInterfaceMode(.simple)
        h.step()
        #expect(window.minSize.width == 700)
    }

    @Test("Chiudendo la finestra si tolgono gli ascolti delle notifiche")
    func observersRemovedOnClose() {
        let h = EditorHarness(paragraphs: ["Una prova."])
        #expect(h.editor.notificationTokenCountForTests > 0)
        h.close()
        #expect(h.editor.notificationTokenCountForTests == 0)
    }
}
