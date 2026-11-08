import AppKit
import PDFKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Distanza a inizio pagina", .serialized) @MainActor
struct PageStartSpacingTests {
    @Test("Stile, annullamento, riapertura e quota esportata in PDF")
    func editing() throws {
        let h = EditorHarness(paragraphs: ["Titolo", "Testo"])
        defer { h.close() }
        func pdfTop() throws -> CGFloat {
            let pdf = try #require(PDFDocument(data: h.editor.printablePDF(title: nil).data))
            let page = try #require(pdf.page(at: 0))
            let selection = try #require(pdf.findString("Titolo", withOptions: []).first)
            return selection.bounds(for: page).maxY
        }
        let top = try pdfTop()
        let gap = PageSetup.points(fromMillimetres: 30)
        h.editor.stylesTab.onPageStart?("Body", .distance(gap))
        h.step()
        #expect(try abs(pdfTop() - top + gap) < 0.1)
        h.undo()
        #expect(try abs(pdfTop() - top) < 0.1)
        h.redo()
        let saved = try h.document.data(ofType: TextDocument.typeName)
        try h.document.read(from: saved, ofType: TextDocument.typeName)
        #expect(try abs(pdfTop() - top + gap) < 0.1)
        let opening = try #require(h.editor.currentLayout()?.pageStarts[0])
        #expect(abs(opening.requested - gap) < 0.01)
    }

    @Test("Eredità, disattivazione, zero esplicito e versione XML")
    func format() throws {
        func xml(_ version: Int, _ spacing: String) -> String {
            """
            <document version="\(version)" font="HoeflerText-Regular" size="12"><styles>
            <style name="A" target="paragraph" page-start-spacing="\(spacing)"/>
            <style name="B" target="paragraph" based-on="A"/>
            <style name="C" target="paragraph" based-on="B" page-start-spacing="off"/>
            <style name="D" target="paragraph" based-on="C" page-start-spacing="0"/>
            </styles><p style="B">Titolo</p></document>
            """
        }
        for bad in [xml(17, "30mm"), xml(18, "-1"), xml(18, "nan")] {
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: bad) }
        }
        let first = try DocumentFormat.document(from: xml(18, "1in"))
        let reopened = try DocumentFormat.document(from: DocumentFormat.data(for: DocumentStore(document: first).document))
        #expect(reopened.styles.values(of: "B").pageStartSpacing == .distance(72))
        #expect(reopened.styles.values(of: "C").pageStartSpacing == .disabled)
        #expect(reopened.styles.values(of: "D").pageStartSpacing == .distance(0))
    }
}

@Suite("Bacheca delle formule", .serialized) @MainActor
struct ComposerBoardTests {
    @Test("Bacheca indipendente, applicazione in un passo, riuso e conflitto con il documento")
    func boardLifecycle() throws {
        let h = EditorHarness(paragraphs: ["uno due tre quattro cinque"])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerController?.window)
        #expect(board !== h.editor.window)
        #expect(h.editor.window?.attachedSheet == nil)
        h.editor.openStyleComposer(nil)
        #expect(h.editor.composerController?.window === board)
        let sheet = h.editor.settings.styles
        let model = ComposerBoardModel(sheet: sheet, owner: "Body", sample: h.text)
        model.showingStyles = false
        model.commit = { base, updated in
            guard h.editor.settings.styles == base else { return "Conflitto" }
            h.editor.endUndoStep(next: .none)
            h.editor.changeStyles(to: updated, restyle: false, actionName: "Style Formulas")
            return nil
        }
        model.reload = { h.editor.settings.styles }
        model.addSelection()
        let id = try #require(model.sheet.selections.first?.id)
        #expect(!model.valid)
        model.incomplete.remove(id)
        #expect(model.valid && model.dirty)
        model.apply()
        #expect(!model.dirty && model.problem == nil)
        #expect(h.editor.settings.styles.selections.first?.preview(in: h.text) == "cinque")
        h.undo()
        #expect(h.editor.settings.styles == sheet)
        model.sheet.selections[0].index = 3
        model.apply()
        #expect(model.problem == "Conflitto")
        #expect(h.editor.settings.styles.selections.isEmpty)
        model.discard()
        #expect(!model.dirty && model.problem == nil && model.sheet.selections.isEmpty)
        h.redo()
        #expect(h.editor.settings.styles.selections.count == 1)
        let read = try DocumentFormat.document(from: h.document.data(ofType: TextDocument.typeName))
        #expect(read.styles.selections.first?.id == id)
    }
}

@Suite("Formule salvate negli stili", .serialized) @MainActor
struct StyleFormulaEditorTests {
    @Test("Modificare una formula ridisegna il testo e resta relativo dopo riapertura e Annulla")
    func editFormula() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        let index = try #require(sheet.styles.firstIndex { $0.name == "Body" })
        sheet.styles[index].formulas = [StyleFormula(operation: StylePropertyOperation(.add, .size, .length(2, .points)))]
        h.editor.changeStyles(to: sheet, restyle: true, actionName: "Formula corpo")
        func size() -> CGFloat {
            (h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        }
        #expect(size() == 14)
        let data = try h.document.data(ofType: TextDocument.typeName)
        try h.document.read(from: data, ofType: TextDocument.typeName)
        #expect(size() == 14)
        h.document.undoManager?.removeAllActions()
        var next = h.editor.settings.styles
        next.styles[index].formulas[0].operation = StylePropertyOperation(.add, .size, .length(4, .points))
        h.editor.changeStyles(to: next, restyle: true, actionName: "Formula corpo")
        h.step()
        #expect(size() == 16)
        h.undo()
        #expect(size() == 14)
        h.redo()
        #expect(size() == 16)
        try h.document.read(from: h.document.data(ofType: TextDocument.typeName), ofType: TextDocument.typeName)
        #expect(size() == 16)
    }
}
