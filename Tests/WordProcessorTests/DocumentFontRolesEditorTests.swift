import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Ruoli delle facce dalla pulsantiera, e pastiglie del monitor", .serialized) @MainActor
struct DocumentFontRolesEditorTests {
    private func fontName(_ h: EditorHarness, at index: Int) -> String {
        (h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont).fontName
    }

    @Test("La faccia scelta diventa il Bold della famiglia nel documento: il nero la usa, Annulla la toglie")
    func assignBold() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        let semibold = try #require(NSFont(name: "Baskerville-SemiBold", size: 14))
        let regular = try #require(NSFont(name: "Baskerville", size: 14))
        e.writeStore(actionName: nil) {
            $0.addAttribute(.font, value: regular, range: NSRange(location: 0, length: $0.length))
            $0.removeAttribute(.fontRole, range: NSRange(location: 0, length: $0.length))
            $0.addAttribute(.font, value: semibold, range: NSRange(location: 0, length: 5))
        }
        h.step()
        h.select(0, length: 5)
        #expect(e.currentFontRole() == nil, "Semibold non è ancora un ruolo")
        e.assignFontRole(.bold)
        h.step()
        #expect(e.currentDocument().fontRoles.customization(family: "Baskerville", role: .bold)?.equivalence.staticFace == "Baskerville-SemiBold")
        #expect(e.currentFontRole() == .bold)
        // Il nero, altrove, dà la faccia scelta.
        h.select(28, length: 7)
        e.toggleBold(nil); h.step()
        #expect(fontName(h, at: 30) == "Baskerville-SemiBold")
        // Il file la conserva.
        let reread = try DocumentFormat.document(from: DocumentFormat.string(for: e.currentDocument()))
        #expect(reread.fontRoles == e.currentDocument().fontRoles)
        h.undo()
        h.undo()
        #expect(e.currentDocument().fontRoles.isEmpty)
    }

    @Test("La zona dei ruoli: quattro caselle con la faccia di ciascun ruolo; un clic dà alla faccia attuale quel ruolo")
    func roleSlots() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        let previous = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = previous }
        e.setInterfaceMode(.advanced)
        let semibold = try #require(NSFont(name: "Baskerville-SemiBold", size: 14))
        let regular = try #require(NSFont(name: "Baskerville", size: 14))
        e.writeStore(actionName: nil) {
            $0.addAttribute(.font, value: regular, range: NSRange(location: 0, length: $0.length))
            $0.removeAttribute(.fontRole, range: NSRange(location: 0, length: $0.length))
            $0.addAttribute(.font, value: semibold, range: NSRange(location: 0, length: 5))
        }
        h.step()
        h.select(30)
        h.step()
        let slots = e.roleSlots.slots
        #expect(slots.map(\.role) == [.regular, .italic, .bold, .boldItalic])
        #expect(slots.map(\.value) == ["Regular", "Italic", "Bold", "Bold Italic"])
        #expect(slots.map(\.state) == [.on, .off, .off, .off])
        #expect(!e.roleSlots.isHidden)
        h.select(0, length: 5)
        h.step()
        #expect(slots.allSatisfy { $0.state == .off }, "Semibold non è ancora un ruolo")
        slots[2].performClick(nil)
        h.step()
        #expect(e.currentDocument().fontRoles.customization(family: "Baskerville", role: .bold)?.equivalence.staticFace == "Baskerville-SemiBold")
        #expect(slots[2].value == "SemiBold" && slots[2].state == .on)
        e.setInterfaceMode(.simple)
        #expect(e.roleSlots.isHidden, "nell'essenziale la zona dei ruoli non c'è")
    }

    @Test("Le pastiglie dicono solo il contenuto; la freccia porta l'aggiunta nello stile")
    func pills() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 25)
        e.toggleItalic(nil); h.step()
        #expect(e.styleMonitor.additions == ["car. corsivo"])
        #expect(e.styleMonitorView.titles == ["corsivo"])
        e.styleMonitorView.moveToStyle(pill: 1)
        h.step()
        #expect(e.styleMonitor.additions.isEmpty)
        let italic = (h.attributed.attribute(.font, at: 30, effectiveRange: nil) as! NSFont).fontDescriptor.symbolicTraits.contains(.italic)
        #expect(italic, "l'altro capoverso dello stesso stile diventa corsivo")
    }
}
