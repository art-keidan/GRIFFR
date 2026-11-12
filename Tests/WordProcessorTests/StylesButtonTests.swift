import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Il pulsante «Styles» accanto a «Design»: apre il compositore degli stili, sullo stile del capoverso, senza il menu.
@Suite("Pulsante Styles", .serialized) @MainActor
struct StylesButtonTests {
    @Test("«Styles» sta accanto a «Design» nella fascia del paragrafo e apre il compositore sullo stile del capoverso")
    func opensComposer() throws {
        let h = EditorHarness(paragraphs: ["Un capoverso."])
        defer { h.close() }
        let zone = try #require(BandLayout.defaultParagraph.first { $0.title == "design" })
        #expect(zone.items == ["progetta", "compositore"])
        #expect(BandLayout.standard.normalized().allItems.contains("compositore"))
        // Una disposizione salvata prima del pulsante lo riceve nella zona «design».
        var old = BandLayout.standard
        for index in old.bands[BandLayout.Band.paragraph.rawValue].indices {
            old.bands[BandLayout.Band.paragraph.rawValue][index].items.removeAll { $0 == "compositore" }
        }
        let restored = old.normalized().bands[BandLayout.Band.paragraph.rawValue].first { $0.title == "design" }
        #expect(restored?.items == ["progetta", "compositore"])

        let button = try #require(h.editor.bandControls["compositore"] as? BandButton)
        #expect(button.label == "Styles" && button.toolTip == "Open the Style Composer")
        #expect(h.editor.composerController == nil)
        h.select(0)
        #expect(button.action == #selector(EditorWindowController.openStyleComposer(_:)) && button.target === h.editor)
        h.editor.perform(button.action, with: button)
        let model = try #require(h.editor.composerModel)
        #expect(model.selectedStyle == "Body")
        #expect(h.editor.composerController?.window?.isVisible == true)
        h.editor.composerController?.close()
    }
}
