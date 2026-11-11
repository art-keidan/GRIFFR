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
}
