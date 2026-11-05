import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Le pastiglie del monitor degli stili per funzioni e assi dati a mano: una ciascuno, e ciascuna si toglie o si porta
/// nello stile da sola, come le righe dell'ispettore. Font di prova: Hoefler Text.
@MainActor
@Suite("Pastiglie di funzioni e assi", .serialized)
struct FontDetailPillsTests {
    private func smallCaps(_ h: EditorHarness, at index: Int) -> Bool {
        let font = h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont
        return FontFeatures.settings(of: font as CTFont).contains(.aat(type: 3, selector: 3))
    }

    private func italic(_ h: EditorHarness, at index: Int) -> Bool {
        let font = h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont
        return TextStyling.traits(ofFace: font.fontName)?.italic == true
    }

    /// «Una» in corsivo e maiuscoletto, dati a mano col pulsante.
    private func sample() -> EditorHarness {
        let h = EditorHarness(paragraphs: ["Una prova.", "Altro testo."])
        h.select(0, length: 3)
        h.editor.toggleItalic(nil)
        h.step()
        (h.editor.bandControls["maiuscoletto"] as? NSButton)?.performClick(nil)
        h.step()
        return h
    }

    @Test("Il maiuscoletto dato col pulsante è una pastiglia sola, con le tre azioni tutte attive: è una proprietà")
    func onePill() throws {
        let h = sample()
        defer { h.close() }
        #expect(smallCaps(h, at: 1))
        #expect(h.editor.styleMonitor.additions == ["car. corsivo", "car. maiuscoletto"])
        let menu = h.editor.additionMonitorMenu(at: 1)
        #expect(menu.items.map(\.title) == ["Togli", "Metti nello stile", "Nuovo stile…"])
        #expect(menu.items.map(\.isEnabled) == [true, true, true], "come per il corsivo, anche «Nuovo stile…»")
    }

    @Test("Togliere il maiuscoletto lascia il corsivo, e torna con un Annulla")
    func removeOne() throws {
        let h = sample()
        defer { h.close() }
        h.select(1)
        h.editor.styleMonitorView.click(pill: 2)  // la 0 è lo stile
        h.step()
        #expect(!smallCaps(h, at: 0) && !smallCaps(h, at: 2), "tutta la parola")
        #expect(italic(h, at: 1), "il corsivo resta")
        #expect(h.editor.styleMonitor.additions == ["car. corsivo"])
        h.undo()
        #expect(smallCaps(h, at: 1))
    }

    @Test("Mettere nello stile il maiuscoletto non porta il corsivo")
    func moveOne() throws {
        let h = sample()
        defer { h.close() }
        h.select(0, length: 3)
        h.editor.additionMonitorMenu(at: 1).performActionForItem(at: 1)
        h.step()
        let testo = h.editor.currentDocument().styles.style(named: "Testo")?.values
        #expect(h.editor.currentDocument().styles.inspect(style: "Testo", base: TextStyling.styleBase).first { $0.property == .smallCaps }?.value.smallCaps == .lowercase, "nello stile va la scelta, non le forme tecniche")
        #expect(testo?.features == nil)
        #expect(testo?.italic == nil, "il corsivo non va nello stile")
        #expect(h.editor.styleMonitor.additions == ["car. corsivo"])
        #expect(smallCaps(h, at: 12) && !italic(h, at: 12), "l'altro paragrafo prende il maiuscoletto, non il corsivo")
        h.undo()
        #expect(!smallCaps(h, at: 12))
        #expect(h.editor.styleMonitor.additions == ["car. corsivo", "car. maiuscoletto"])
    }

    @Test("«Porta le aggiunte nello stile» porta anche le funzioni")
    func moveAll() throws {
        let h = sample()
        defer { h.close() }
        h.select(0, length: 3)
        let menu = h.editor.styleMonitorMenu()
        #expect(menu.items[1].title == "Porta le aggiunte nello stile «Testo»")
        menu.performActionForItem(at: 1)
        h.step()
        #expect(h.editor.styleMonitor.additions.isEmpty)
        #expect(smallCaps(h, at: 12) && italic(h, at: 12))
    }
}
