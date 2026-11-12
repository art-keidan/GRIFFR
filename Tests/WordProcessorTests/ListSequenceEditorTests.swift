import AppKit
import PDFKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// I tratti di una Lista nell'editor: ripartenza e ripresa dal menu Formato › Elenco, il foglio delle riprese,
/// Annulla/Ripeti e il file.
@Suite("Tratti di una Lista nell'editor", .serialized) @MainActor
struct ListSequenceEditorTests {
    private func location(of text: String, in h: EditorHarness) -> Int {
        (h.text as NSString).range(of: text).location
    }

    /// Un editor con sei voci della Lista «Examples» e un paragrafo normale in cima.
    private func harness() -> (EditorHarness, [String: Int]) {
        let h = EditorHarness(paragraphs: ["Prima.", "A uno", "A due", "B uno", "B due", "Ripresa uno", "Ripresa due"])
        let start = 7
        h.select(start, length: h.text.utf16.count - start)
        let menu = NSMenuItem(title: "", action: #selector(EditorWindowController.setNamedList(_:)), keyEquivalent: "")
        menu.representedObject = "Examples"
        h.editor.setNamedList(menu)
        var spots: [String: Int] = [:]
        for text in ["A uno", "A due", "B uno", "B due", "Ripresa uno", "Ripresa due"] {
            spots[text] = location(of: text, in: h)
        }
        return (h, spots)
    }

    @Test("Restart Numbering apre un tratto nuovo: B riparte da (1), e Annulla lo toglie")
    func restart() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let b = try #require(spots["B uno"])
        h.select(b)
        #expect(h.editor.canStartSequence)
        let item = NSMenuItem(title: "", action: #selector(EditorWindowController.restartListNumbering(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item))

        #expect(h.editor.applyListSequenceStart())
        #expect(h.editor.selectionListItem()?.sequenceStart == 1)
        var marks = try #require(h.editor.currentLayout()).listMarks
        #expect(marks[b] == "(1)" && marks[try #require(spots["Ripresa uno"])] == "(3)")

        h.undo()
        #expect(h.editor.selectionListItem()?.sequenceStart == nil)
        marks = try #require(h.editor.currentLayout()).listMarks
        #expect(marks[b] == "(3)")

        h.redo()
        #expect(h.editor.selectionListItem()?.sequenceStart == 1)
        #expect(try #require(h.editor.currentLayout()).listMarks[b] == "(1)")
    }

    @Test("Resume Numbering riprende il tratto scelto: la ripresa di A continua (3) (4) dopo B")
    func resume() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let a = try #require(spots["A uno"])
        let b = try #require(spots["B uno"])
        let c = try #require(spots["Ripresa uno"])
        let identity = h.editor.store.paragraphID(at: a).persistent

        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        h.select(c)
        #expect(h.editor.applyListSequenceResume(from: identity))
        #expect(h.editor.selectionListItem()?.sequenceResume == identity)
        let marks = try #require(h.editor.currentLayout()).listMarks
        #expect(marks[a] == "(1)" && marks[spots["A due"]!] == "(2)")
        #expect(marks[b] == "(1)" && marks[spots["B due"]!] == "(2)")
        #expect(marks[c] == "(3)" && marks[spots["Ripresa due"]!] == "(4)")

        // Le stesse scelte nel PDF: le identità dei capoversi arrivano alla composizione anche sulla copia.
        let pdf = try #require(PDFDocument(data: h.editor.printablePDF(title: nil).data))
        let text = (pdf.string ?? "").replacingOccurrences(of: "\n", with: " ")
        #expect(text.contains("(1) A uno") && text.contains("(1) B uno") && text.contains("(3) Ripresa uno"), "\(text)")

        // Un'identità che non appartiene a nessun tratto della Lista non si accetta.
        h.select(spots["Ripresa due"]!)
        #expect(!h.editor.applyListSequenceResume(from: UUID()))
    }

    @Test("Il foglio delle riprese offre i tratti già cominciati, con il testo della prima voce")
    func chooser() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let a = try #require(spots["A uno"])
        let b = try #require(spots["B uno"])
        let c = try #require(spots["Ripresa uno"])
        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        h.select(c)
        var offered: [UUID] = []
        h.editor.chooseSequenceForTests = { offered = $0 }
        h.editor.resumeListNumbering(nil)
        #expect(offered.count == 2, "A e B, cominciati prima del capoverso")
        // La prima scelta è il tratto di A: riprenderla dà (3).
        #expect(h.editor.applyListSequenceResume(from: h.editor.store.paragraphID(at: a).persistent))
        #expect(try #require(h.editor.currentLayout()).listMarks[c] == "(3)")
    }

    @Test("Ripartenza e ripresa non valgono per un paragrafo normale né per una voce che continua quella prima")
    func onlyItems() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let first = location(of: "Prima.", in: h)
        h.select(first)
        #expect(!h.editor.canStartSequence)
        let restart = NSMenuItem(title: "", action: #selector(EditorWindowController.restartListNumbering(_:)), keyEquivalent: "")
        let resume = NSMenuItem(title: "", action: #selector(EditorWindowController.resumeListNumbering(_:)), keyEquivalent: "")
        #expect(!h.editor.validateMenuItem(restart))
        #expect(!h.editor.validateMenuItem(resume))

        // Il primo capoverso di un elenco: nessun tratto da riprendere, ma una ripartenza sì.
        h.select(spots["A uno"]!)
        #expect(h.editor.canStartSequence)
        #expect(h.editor.validateMenuItem(restart))
        #expect(!h.editor.validateMenuItem(resume))

        // Una voce che continua la voce prima non apre un tratto.
        h.select(spots["A due"]!)
        h.editor.toggleListContinuation(nil)
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == true)
        #expect(!h.editor.canStartSequence)
    }

    @Test("Una continuazione rimasta senza voce compare fra gli avvisi della composizione")
    func orphanWarning() throws {
        let (h, spots) = harness()
        defer { h.close() }
        h.select(spots["A due"]!)
        h.editor.toggleListContinuation(nil)
        #expect(h.editor.selectionListItem()?.continuesPreviousItem == true)
        #expect(!h.editor.warningTitles.contains { $0.contains("continues an item") })
        // Tolta la voce che la precede, la continuazione resta senza voce.
        h.select(location(of: "A uno", in: h))
        h.editor.applyListMarker(nil)
        _ = h.editor.currentLayout()
        #expect(h.editor.warningTitles.contains { $0.contains("A list item continues an item that isn't there") },
                "\(h.editor.warningTitles)")
    }

    @Test("Dentro una cella di tabella i comandi dei tratti sono spenti")
    func tableCells() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("Uno")
        h.step()
        #expect(h.editor.selectionInTableCell)
        h.editor.applyListMarker("1.")
        #expect(h.editor.selectionListItem() != nil)
        #expect(!h.editor.canContinuePreviousItem())
        #expect(!h.editor.canStartSequence)
        let continuation = NSMenuItem(title: "", action: #selector(EditorWindowController.toggleListContinuation(_:)), keyEquivalent: "")
        let restart = NSMenuItem(title: "", action: #selector(EditorWindowController.restartListNumbering(_:)), keyEquivalent: "")
        let resume = NSMenuItem(title: "", action: #selector(EditorWindowController.resumeListNumbering(_:)), keyEquivalent: "")
        #expect(!h.editor.validateMenuItem(continuation))
        #expect(!h.editor.validateMenuItem(restart))
        #expect(!h.editor.validateMenuItem(resume))
        #expect(!h.editor.applyListSequenceStart())
        #expect(h.editor.selectionListItem()?.sequenceStart == nil)
    }

    @Test("Una ripresa copiata senza il tratto che la apre diventa un avviso, non un numero silenzioso")
    func copiedResumeWithoutSequence() throws {
        let a = EditorHarness(paragraphs: ["A uno", "Ripresa"])
        defer { a.close() }
        let b = EditorHarness(paragraphs: ["Testo."])
        defer { b.close() }
        b.editor.pasteboard = a.editor.pasteboard
        a.select(0, length: a.text.utf16.count)
        let menu = NSMenuItem(title: "", action: #selector(EditorWindowController.setNamedList(_:)), keyEquivalent: "")
        menu.representedObject = "Examples"
        a.editor.setNamedList(menu)
        let aID = a.editor.store.paragraphID(at: 0).persistent
        let resume = (a.text as NSString).range(of: "Ripresa").location
        a.select(resume)
        #expect(a.editor.applyListSequenceResume(from: aID))
        #expect(a.editor.currentLayout()?.listMarks[resume] == "(2)")

        // Si copiano il capoverso che apre il tratto e quello che lo riprende: il frammento conserva l'elenco, ma
        // l'identità del capoverso copiato cambia, quindi la ripresa resta senza tratto.
        let start = (a.text as NSString).range(of: "A uno").location
        let end = NSMaxRange(TextStyling.bodyParagraph(in: a.editor.editingText, at: resume).range)
        a.select(start, length: end - start)
        #expect(a.menu(#selector(NSText.copy(_:))))
        b.select(b.text.utf16.count)
        b.press(#selector(NSResponder.insertNewline(_:)))
        #expect(b.menu(#selector(NSText.paste(_:))))
        _ = b.editor.currentLayout()
        #expect(b.editor.warningTitles.contains { $0.contains("resumes a sequence that isn't there") },
                "\(b.editor.warningTitles)")
        #expect(try #require(b.editor.currentLayout()).listMarks.values.contains("(1)"), "la voce copiata riparte dalla definizione")
    }

    @Test("La ripartenza e la ripresa restano nel file e tornano aprendolo")
    func fileRoundTrip() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let a = try #require(spots["A uno"])
        let b = try #require(spots["B uno"])
        let c = try #require(spots["Ripresa uno"])
        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        h.select(c)
        #expect(h.editor.applyListSequenceResume(from: h.editor.store.paragraphID(at: a).persistent))

        let saved = h.editor.currentDocument()
        let written = DocumentFormat.string(for: saved)
        #expect(written.contains("<document version=\"21\""), "\(written)")
        #expect(written.contains("sequence-start=\"1\""))
        #expect(written.contains("sequence-resume=\"\(h.editor.store.paragraphID(at: a).persistent.uuidString)\""))
        let reread = try DocumentFormat.document(from: written)
        #expect(DocumentFormat.string(for: reread) == written)
        #expect(reread == saved)
        // I paragrafi dei due tratti conservano le scelte.
        let items = reread.blocks.compactMap { block -> ListItem? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.list
        }
        #expect(items[2].sequenceStart == 1)
        #expect(items[4].sequenceResume == h.editor.store.paragraphID(at: a).persistent)
    }

    @Test("Invio dopo una voce che riparte: la voce nuova continua il tratto, la ripartenza resta sulla prima")
    func returnAfterRestart() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let b = try #require(spots["B uno"])
        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        let id = h.editor.store.paragraphID(at: b).persistent
        // A capo in fondo alla voce, poi una voce nuova.
        h.select(b + "B uno".utf16.count)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("B mezzo")
        let middle = location(of: "B mezzo", in: h)
        #expect(h.editor.selectionListItem()?.sequenceStart == nil)
        var marks = try #require(h.editor.currentLayout()).listMarks
        #expect(marks[b] == "(1)" && marks[middle] == "(2)" && marks[try #require(spots["B due"]) + "B mezzo\n".utf16.count] == "(3)", "\(marks)")
        #expect(h.editor.store.paragraphID(at: b).persistent == id, "la voce che riparte conserva la sua identità")
        #expect(TextStyling.listItem(in: h.editor.store, at: b)?.sequenceStart == 1)

        // Un capoverso diviso a metà: solo la prima parte riapre il tratto.
        h.select(b + 2)
        h.press(#selector(NSResponder.insertNewline(_:)))
        marks = try #require(h.editor.currentLayout()).listMarks
        #expect(marks[b] == "(1)" && marks[b + 3] == "(2)", "\(marks)")

        // Annulla toglie l'a capo e torna come prima.
        h.undo()
        #expect(try #require(h.editor.currentLayout()).listMarks[middle] == "(2)")
    }

    @Test("L'anteprima del righello conserva le riprese dei tratti")
    func rulerPreviewKeepsResume() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let a = try #require(spots["A uno"])
        let b = try #require(spots["B uno"])
        let c = try #require(spots["Ripresa uno"])
        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        h.select(c)
        #expect(h.editor.applyListSequenceResume(from: h.editor.store.paragraphID(at: a).persistent))
        #expect(h.editor.currentLayout()?.listMarks[c] == "(3)")

        h.editor.preview(.lists(h.editor.settings.lists, name: "Examples"))
        let layout = try #require(h.editor.pagesView.layout)
        #expect(layout.listMarks[c] == "(3)", "\(layout.listMarks)")
        #expect(layout.listWarnings.isEmpty, "\(layout.listWarnings)")
    }

    @Test("L'anteprima di Progetta il capoverso conserva le riprese dei tratti")
    func paragraphDesignPreviewKeepsResume() throws {
        let (h, spots) = harness()
        defer { h.close() }
        let a = try #require(spots["A uno"])
        let b = try #require(spots["B uno"])
        let c = try #require(spots["Ripresa uno"])
        h.select(b)
        #expect(h.editor.applyListSequenceStart())
        h.select(c)
        #expect(h.editor.applyListSequenceResume(from: h.editor.store.paragraphID(at: a).persistent))

        h.editor.setParagraphDesign(true)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        #expect(h.editor.paragraphDesignPreviewForTests != nil, "l'anteprima della bozza è in corso")
        let layout = try #require(h.editor.pagesView.layout)
        #expect(layout.listMarks[c] == "(3)", "\(layout.listMarks)")
        #expect(layout.listWarnings.isEmpty, "\(layout.listWarnings)")
        h.editor.setParagraphDesign(false)
    }
}
