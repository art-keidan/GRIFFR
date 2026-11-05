import AppKit
import Testing
@testable import WordProcessor

@MainActor
@Suite("Stato della vista conservato nel file", .serialized)
struct ViewStateTests {
    @Test("Lo stato si scrive in un attributo esteso del file, che non cambia, e si rilegge")
    func extendedAttributeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stato-\(UUID().uuidString).grx")
        try Data("contenuto".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(DocumentViewState.read(from: url) == nil)
        let state = DocumentViewState(zoom: 1.25, anchor: 120, head: 130, scroll: [0, 840], frame: [100, 80, 1100, 800])
        state.write(to: url)
        #expect(DocumentViewState.read(from: url) == state)
        #expect(try Data(contentsOf: url) == Data("contenuto".utf8), "il contenuto del file non cambia")
        DocumentViewState(zoom: nil, anchor: 0, head: 0, scroll: [0, 0], frame: []).write(to: url)
        #expect(DocumentViewState.read(from: url)?.zoom == nil, "lo zoom automatico si conserva come tale")
    }

    @Test("Una finestra salvata troppo grande rientra nello schermo alla riapertura")
    func restoreOversizedWindow() throws {
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        let screen = try #require(window.screen ?? NSScreen.main).visibleFrame
        let state = DocumentViewState(zoom: nil, anchor: 0, head: 0, scroll: [0, 0],
            frame: [screen.midX - screen.width, screen.maxY - screen.height * 2, screen.width * 2, screen.height * 2])
        h.editor.restoreViewState(state)
        h.step()
        #expect(window.frame.width <= screen.width + 1)
        #expect(window.frame.height <= screen.height + 1)
        #expect(window.frame.minX >= screen.minX - 1 && window.frame.minY >= screen.minY - 1)
        #expect(window.frame.maxX <= screen.maxX + 1 && window.frame.maxY <= screen.maxY + 1)
    }

    @Test("Zoom, cursore, finestra e scorrimento si ripristinano")
    func restoreInEditor() throws {
        let h = EditorHarness(paragraphs: Array(repeating: "Un paragrafo abbastanza lungo da riempire più pagine di testo, ripetuto molte volte.", count: 120))
        defer { h.close() }
        let screen = try #require(NSScreen.main?.visibleFrame)
        let frame = NSRect(x: screen.minX + 40, y: screen.minY + 40, width: min(1250, screen.width - 80), height: min(700, screen.height - 80))
        let wanted = DocumentViewState(zoom: 0.75, anchor: 2_000, head: 2_010, scroll: [0, 900],
                                       frame: [frame.minX, frame.minY, frame.width, frame.height])
        h.editor.restoreViewState(wanted)
        for _ in 0..<200 where h.editor.currentViewState().scroll[1] < 899 { h.step() }
        let now = h.editor.currentViewState()
        #expect(now.zoom == 0.75)
        #expect(now.anchor == 2_000 && now.head == 2_010)
        #expect(abs(now.frame[2] - frame.width) < 1 && abs(now.frame[3] - frame.height) < 1)
        #expect(abs(now.scroll[1] - 900) < 1, "scorrimento: \(now.scroll), pagine alte \(h.editor.pagesHeightForTests)")
    }
}
