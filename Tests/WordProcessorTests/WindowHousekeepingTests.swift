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

    @Test("Lorem ripetuto dentro sezioni non allarga la finestra e permette di rimpicciolirla")
    func repeatedLoremDoesNotResizeWindow() throws {
        let savedMode = InterfaceMode.lastChoice
        let savedTree = EditorWindowController.showsObjectTree
        defer { InterfaceMode.lastChoice = savedMode; EditorWindowController.showsObjectTree = savedTree }
        InterfaceMode.lastChoice = .advanced
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness()
        defer { h.close() }
        let window = try #require(h.editor.window)
        window.orderFront(nil)
        let initial = window.frame
        let wanted = NSSize(width: window.minSize.width + 20, height: 500)
        window.setFrame(NSRect(origin: initial.origin, size: wanted), display: true)
        h.step()
        let compact = window.frame.size
        window.setFrame(initial, display: true)
        h.step()
        for _ in 0..<6 {
            h.select(h.text.utf16.count)
            h.editor.insertLorem(nil)
            h.step()
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(abs(window.frame.width - initial.width) < 1, "dimensioni dopo Lorem: \(window.frame.size)")
            #expect(abs(window.frame.height - initial.height) < 1)
        }
        #expect(h.editor.sectionPathTitles.count >= 5, "il percorso contiene sezioni annidate")
        window.setFrame(NSRect(origin: window.frame.origin, size: compact), display: true)
        h.step()
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(abs(window.frame.width - compact.width) < 1, "larghezza minima effettiva: \(window.frame.width)")
        #expect(abs(window.frame.height - compact.height) < 1)
        let scroll = try #require(h.editor.pathBar.enclosingScrollView)
        #expect(h.editor.pathBar.frame.width > scroll.contentSize.width)
        let last = try #require(h.editor.sectionPath.arrangedSubviews.last)
        let rect = last.convert(last.bounds, to: h.editor.pathBar)
        h.editor.pathBar.scrollToVisible(rect)
        #expect(scroll.contentView.bounds.minX > 0, "i pulsanti fuori dalla fascia restano raggiungibili")
        #expect(h.editor.pathBar.visibleRect.minX <= rect.minX + 1)
        #expect(h.editor.pathBar.visibleRect.maxX >= rect.maxX - 1)
    }

    @Test("Chiudendo la finestra si tolgono gli ascolti delle notifiche")
    func observersRemovedOnClose() {
        let h = EditorHarness(paragraphs: ["Una prova."])
        #expect(h.editor.notificationTokenCountForTests > 0)
        h.close()
        #expect(h.editor.notificationTokenCountForTests == 0)
    }
}
