import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Le foto della guida (`docs/guide`): finestre vere dell'editor, disegnate in un'immagine a densità doppia, senza
/// puntatore. Si generano solo con la cartella di destinazione in `GRIFFR_GUIDE_OUT`:
///
///     GRIFFR_GUIDE_OUT="$PWD/docs/guide/images/full" swift test --filter GuideScreenshotTests
///
/// Le immagini intere si ritagliano poi con `Scripts/guide-crops.swift`.
@Suite("Foto della guida", .serialized, .enabled(if: ProcessInfo.processInfo.environment["GRIFFR_GUIDE_OUT"] != nil)) @MainActor
struct GuideScreenshotTests {
    private var out: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["GRIFFR_GUIDE_OUT"] ?? "") }

    /// La vista disegnata a densità doppia, in PNG.
    private func save(_ view: NSView, _ name: String) throws {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try #require(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name + ".png"))
    }

    /// Lascia lavorare l'interfaccia (composizione, pause delle schede, SwiftUI); poi i conteggi della barra di stato, che
    /// arrivano dopo una pausa, e niente riga scelta nell'albero (la sua evidenziazione non si disegna fuori dallo schermo).
    private func settle(_ h: EditorHarness, _ seconds: TimeInterval = 0.6) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        h.editor.updateCounts()
        h.editor.objectTree.selection = nil
        h.step()
    }

    /// Una finestra con il testo di Lorem, il cursore all'inizio di un paragrafo del corpo.
    private func window(_ mode: InterfaceMode) throws -> EditorHarness {
        _ = FontLoader.registerAdobeFonts()
        let h = EditorHarness()
        let window = try #require(h.editor.window)
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1180, height: 900))
        window.contentView?.wantsLayer = true
        window.orderFront(nil)
        h.editor.setInterfaceMode(mode)
        h.editor.insertLorem(nil)
        settle(h)
        let body = (h.text as NSString).range(of: "A line that is too long")
        h.select(body.location == NSNotFound ? 0 : body.location + 40)
        h.editor.scrollToTopForTests()
        settle(h)
        return h
    }

    /// Le schede delle definizioni no: i loro pannelli SwiftUI con lo scorrimento si disegnano solo sullo schermo, e qui
    /// verrebbero neri. Quelle foto si fanno dall'app.
    @Test("Le due interfacce, la progettazione del paragrafo, il compositore degli stili")
    func windows() throws {
        let simple = try window(.simple)
        try save(try #require(simple.editor.window?.contentView), "simple")
        simple.close()

        let h = try window(.advanced)
        let content = try #require(h.editor.window?.contentView)
        try save(content, "detailed")
        h.editor.toggleParagraphDesign(nil)
        settle(h)
        try save(content, "design")
        h.editor.toggleParagraphDesign(nil)
        settle(h)

        h.editor.openStyleComposer(nil)
        settle(h, 1)
        let composer = try #require(h.editor.composerController?.window)
        composer.appearance = NSAppearance(named: .aqua)
        composer.setContentSize(NSSize(width: 1100, height: 720))
        settle(h, 1)
        try save(try #require(composer.contentView), "composer")
        composer.close()
        h.close()
    }

    /// Una nota, una figura e una tabella sulla pagina, vista intera.
    @Test("Note, figure e tabelle")
    func objects() throws {
        let h = try window(.advanced)
        let string = h.text as NSString
        // Una nota a piè di pagina dopo «in front of them».
        let them = string.range(of: "in front of them")
        h.select(NSMaxRange(them))
        h.editor.insertFootnote(nil)
        h.type("A note stays on the page of its reference mark.")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        // Una figura nel primo paragrafo del capitolo, con il marchio di GRIFFR e la sua didascalia.
        let asks = (h.text as NSString).range(of: "the next line, and it easily")
        if asks.location != NSNotFound {
            h.select(asks.location)
            let mark = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Branding_GRIFFR/icona_trasparente.png")
            let data = try Data(contentsOf: mark)
            let figure = try #require(h.editor.settings.floatStyles.first { $0.placement == .figure }?.name)
            h.editor.insertNote(style: figure, image: ImageObject(source: .embedded(data), width: 90, height: 90))
            h.type("The GRIFFR mark: a figure with its caption.")
            h.press(#selector(NSResponder.cancelOperation(_:)))
        }
        // Una tabella dopo il primo paragrafo, con due righe scritte.
        h.select(NSMaxRange(them))
        h.editor.insertTable(nil)
        for (index, cell) in ["Text", "Size", "Leading", "Body", "12 pt", "14 pt", "Notes", "9 pt", "11 pt"].enumerated() {
            if index > 0 { h.press(#selector(NSResponder.insertTab(_:))) }
            h.type(cell)
        }
        h.editor.setZoom(0.62)
        h.editor.scrollToTopForTests()
        settle(h, 1)
        try save(try #require(h.editor.window?.contentView), "objects")
        h.close()
    }
}

extension EditorWindowController {
    /// Per le foto: le pagine dalla prima riga.
    func scrollToTopForTests() {
        pagesView.scroll(NSPoint(x: 0, y: 0))
    }
}
