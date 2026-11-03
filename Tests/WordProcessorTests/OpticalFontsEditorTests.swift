import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Corpi ottici nell'editor", .serialized) @MainActor
struct OpticalFontsEditorTests {
    // Servono anche i corpi ottici: in Adobe Fonts si possono attivare separatamente dalla famiglia di base.
    nonisolated private static let installed = ["Minion3-Regular", "Minion3Caption-Regular", "Minion3Subhead-Regular", "Minion3Display-Regular"]
        .allSatisfy { NSFont(name: $0, size: 12) != nil }

    private func send(_ control: NSControl, _ h: EditorHarness) {
        _ = NSApp.sendAction(control.action!, to: control.target, from: control)
        h.step()
    }

    private func setSize(_ size: Int, _ h: EditorHarness) throws {
        let box = try #require(h.editor.bandControls["corpo"])
        box.stringValue = String(size)
        send(box, h)
    }

    private func fontName(_ h: EditorHarness) -> String? {
        (h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName
    }

    @Test("Minion 3 appare una volta; il corpo muove la variante e la scelta manuale resta nel file", .enabled(if: installed))
    func opticalSizesInControls() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Minion"])
        defer { h.close() }
        h.select(0, length: 6)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        #expect(family.itemTitles.filter { $0 == "Minion 3" }.count == 1)
        #expect(!family.itemTitles.contains("Minion 3 Caption"))
        #expect(!family.itemTitles.contains("Minion 3 Subhead"))
        #expect(!family.itemTitles.contains("Minion 3 Display"))
        family.selectItem(withTitle: "Minion 3")
        send(family, h)
        let face = try #require(h.editor.bandControls["faccia"] as? NSPopUpButton)
        #expect(face.itemTitles.count == 8)
        let bold = try #require(face.itemArray.firstIndex { $0.representedObject as? String == "Minion3-Bold" })
        face.selectItem(at: bold)
        send(face, h)
        #expect(fontName(h) == "Minion3-Bold")

        try setSize(7, h)
        #expect(fontName(h) == "Minion3Caption-Bold")
        #expect(face.selectedItem?.representedObject as? String == "Minion3-Bold")
        try setSize(16, h)
        #expect(fontName(h) == "Minion3Subhead-Bold")
        try setSize(36, h)
        #expect(fontName(h) == "Minion3Display-Bold")

        let optical = try #require(h.editor.bandControls["corpoOtticoScelta"] as? NSPopUpButton)
        #expect(!optical.isHidden)
        let caption = try #require(optical.itemArray.firstIndex { $0.representedObject as? String == "caption" })
        optical.selectItem(at: caption)
        send(optical, h)
        #expect(fontName(h) == "Minion3Caption-Bold")
        try setSize(7, h)
        try setSize(36, h)
        #expect(fontName(h) == "Minion3Caption-Bold", "la variante fissa non segue più il corpo")
        let written = DocumentFormat.string(for: Document(attributedString: h.attributed))
        #expect(written.contains("optical=\"caption\""))

        let automatic = try #require(optical.itemArray.firstIndex { $0.representedObject as? String == "" })
        optical.selectItem(at: automatic)
        send(optical, h)
        try setSize(36, h)
        #expect(fontName(h) == "Minion3Display-Bold")
        let toggle = try #require(h.editor.bandControls["corpoOttico"] as? NSButton)
        #expect(toggle.state == .on)
    }
}
