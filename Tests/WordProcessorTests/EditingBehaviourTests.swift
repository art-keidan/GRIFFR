import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// La rete di sicurezza della fase 4: ciò che la scrittura sa fare oggi, provato attraverso l'editor intero.
/// Ogni prova porta il numero della voce nell'elenco `Appunti/comportamenti-scrittura.md`.
@Suite("Comportamenti della scrittura", .serialized) @MainActor
struct EditingBehaviourTests {
    private let backward = #selector(NSResponder.deleteBackward(_:))

    // MARK: Scrittura e cancellazione

    @Test("S1 · I caratteri entrano al cursore, che avanza; una selezione viene sostituita")
    func typing() {
        let h = EditorHarness(paragraphs: ["Prima riga", "Seconda"])
        defer { h.close() }
        h.select(5)
        h.type("XY")
        #expect(h.text == "PrimaXY riga\nSeconda")
        #expect(h.selection == NSRange(location: 7, length: 0))
        h.select(0, length: 5)
        h.type("Z")
        #expect(h.text == "ZXY riga\nSeconda")
    }

    @Test("S2 · Cancellare indietro, avanti, una parola indietro; con una selezione si cancella la selezione")
    func deleting() {
        let h = EditorHarness(paragraphs: ["uno due tre"])
        defer { h.close() }
        h.select(7)
        h.press(backward)
        #expect(h.text == "uno du tre")
        h.press(#selector(NSResponder.deleteForward(_:)))
        #expect(h.text == "uno dutre")
        h.select(3)
        h.press(#selector(NSResponder.deleteWordBackward(_:)))
        #expect(h.text == " dutre")
        h.select(1, length: 2)
        h.press(backward)
        #expect(h.text == " tre")
    }

    @Test("S3 · A capo spezza il paragrafo; cancellare all'inizio di un paragrafo lo unisce al precedente")
    func paragraphs() {
        let h = EditorHarness(paragraphs: ["abcdef"])
        defer { h.close() }
        h.select(3)
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.text == "abc\ndef")
        #expect(h.selection.location == 4)
        h.press(backward)
        #expect(h.text == "abcdef")
    }

    @Test("S4 · Le frecce muovono il cursore; con Maiuscole estendono la selezione")
    func movement() {
        let h = EditorHarness(paragraphs: ["abc", "def"])
        defer { h.close() }
        h.select(0)
        h.press(#selector(NSResponder.moveRight(_:)), times: 2)
        #expect(h.selection == NSRange(location: 2, length: 0))
        h.press(#selector(NSResponder.moveRightAndModifySelection(_:)), times: 3)
        #expect(h.selection == NSRange(location: 2, length: 3))
        h.press(#selector(NSResponder.moveToEndOfDocument(_:)))
        #expect(h.selection == NSRange(location: 7, length: 0))
        h.press(#selector(NSResponder.moveWordLeft(_:)))
        #expect(h.selection == NSRange(location: 4, length: 0))
    }

    @Test("S5 · Si scrive con gli attributi del carattere che precede il cursore")
    func typingAttributes() {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.select(1, length: 1)
        h.editor.applyNamedStyle(.character, name: "Emphasis")
        h.step()
        h.select(2)
        h.type("c")
        let font = h.attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(font?.fontName == "HoeflerText-Italic")
        #expect(h.attributed.attribute(.characterStyleName, at: 2, effectiveRange: nil) as? String == "Emphasis")
    }

    @Test("S6 · Maiuscole+Invio diventa l'a capo nello stesso paragrafo; Invio da solo, o con anche Comando, no")
    func shiftReturn() {
        let newline = #selector(NSResponder.insertNewline(_:)), lineBreak = #selector(NSResponder.insertLineBreak(_:))
        #expect(PagesView.command(for: newline, modifiers: .shift) == lineBreak)
        #expect(PagesView.command(for: newline, modifiers: []) == newline)
        #expect(PagesView.command(for: newline, modifiers: [.shift, .command]) == newline)
        #expect(PagesView.command(for: #selector(NSResponder.insertTab(_:)), modifiers: .shift) == #selector(NSResponder.insertTab(_:)))
    }

    @Test("S6 · Fuori da un elenco Tab scrive una tabulazione; l'a capo nel paragrafo non spezza il paragrafo")
    func tabAndLineBreak() {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.select(1)
        h.press(#selector(NSResponder.insertTab(_:)))
        h.press(#selector(NSResponder.insertLineBreak(_:)))
        #expect(h.text == "a\t\u{2028}b")
        #expect(h.editor.currentLayout()?.pages.first?.lines.count == 2, "due righe, un paragrafo")
    }

    @Test("S7 · Seleziona tutto")
    func selectAll() {
        let h = EditorHarness(paragraphs: ["uno", "due"])
        defer { h.close() }
        h.select(1)
        h.menu(#selector(NSResponder.selectAll(_:)))
        #expect(h.selection == NSRange(location: 0, length: 7))
    }

    // MARK: Annullamento

    @Test("U1 · Una parola scritta di seguito si annulla in un passo; spostare il cursore apre un passo nuovo")
    func undoGrouping() {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        h.select(1)
        h.type(" uno")
        h.select(0)
        h.type("due ")
        #expect(h.text == "due x uno")
        h.undo()
        #expect(h.text == "x uno")
        h.undo()
        #expect(h.text == "x")
        h.redo()
        #expect(h.text == "x uno")
    }

    @Test("U2 · Scrivere e poi cancellare sono passi diversi")
    func undoTypingThenDeleting() {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        h.select(1)
        h.type("abc")
        h.press(backward, times: 2)
        #expect(h.text == "xa")
        h.undo()
        #expect(h.text == "xabc")
        h.undo()
        #expect(h.text == "x")
    }

    @Test("Il trascinamento dell'espansione si annulla in un solo passo")
    func undoGlyphExpansionDrag() {
        let h = EditorHarness(paragraphs: ["Testo giustificato di prova."])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests
        #expect(inspector.glyphExpansionLimit == LayoutOptions.defaultGlyphExpansionLimit)
        inspector.glyphExpansionDragging?(true)
        inspector.setGlyphExpansionLimit?(0.01)
        inspector.setGlyphExpansionLimit?(0.03)
        inspector.glyphExpansionDragging?(false)
        h.step()
        #expect(inspector.glyphExpansionLimit == 0.03)
        h.undo()
        #expect(inspector.glyphExpansionLimit == LayoutOptions.defaultGlyphExpansionLimit)
    }

    // MARK: Note

    @Test("N1 · Inserire una nota porta il cursore nel suo testo; Esc torna al corpo, dopo il richiamo")
    func footnoteInsert() {
        let h = EditorHarness(paragraphs: ["Testo qui"])
        defer { h.close() }
        h.select(5)
        h.editor.insertFootnote(nil)
        h.step()
        #expect(h.editor.noteAnchor == 5)
        h.type("Nota")
        #expect(h.text == "Testo\u{FFFC}Nota qui".replacingOccurrences(of: "\u{FFFC}", with: String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1)))
        #expect(h.attributed.attribute(.footnote, at: 7, effectiveRange: nil) != nil, "il testo scritto appartiene alla nota")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.editor.noteAnchor == nil)
        #expect(h.selection.location == 10)
        h.type("!")
        #expect(h.attributed.attribute(.footnote, at: 10, effectiveRange: nil) == nil, "dopo Esc si scrive nel corpo")
        let layout = h.editor.currentLayout()
        #expect(layout?.notes.count == 1)
    }

    @Test("N2 · Cancellare indietro dopo un richiamo toglie tutta la nota; all'inizio della nota non toglie nulla")
    func footnoteDelete() {
        let h = EditorHarness(paragraphs: ["Testo"])
        defer { h.close() }
        h.select(5)
        h.editor.insertFootnote(nil)
        h.step()
        h.press(backward)
        #expect(h.text.count == 6, "all'inizio del testo della nota non si cancella il richiamo")
        h.type("abc")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.press(backward)
        #expect(h.text == "Testo")
        h.undo()
        #expect(h.text.count == 9, "annullando la nota torna intera")
    }

    @Test("N3 · In una nota si incolla solo il testo, anche se negli appunti c'è un'altra nota")
    func pasteInNote() {
        let h = EditorHarness(paragraphs: ["Testo"])
        defer { h.close() }
        h.select(5)
        h.editor.insertFootnote(nil)
        h.step()
        h.type("Nota")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.select(0, length: 10)
        h.menu(#selector(NSText.copy(_:)))
        h.select(5)
        h.editor.insertFootnote(nil)
        h.step()
        h.menu(#selector(NSText.paste(_:)))
        #expect(h.editor.currentLayout()?.notes.count == 2, "nessuna nota dentro la nota")
        #expect(h.text.contains("Testo") && h.text.filter { $0 == Character(Unicode.Scalar(FloatingObject.anchorCharacter)!) }.count == 2)
    }

    @Test("N5 · Una nota di un'altra serie (stile di flottante) si inserisce dal menu e sta nel blocco della sua serie")
    func noteOfSeries() throws {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        var document = h.editor.currentDocument()
        document.floatStyles.append(FloatStyle(name: "Note del curatore", reference: .plain))
        let style = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: style))]))]
        h.editor.replaceContent(document)
        h.step()
        #expect(h.editor.otherFloatStyles() == ["Note del curatore"])
        h.select(5)
        let item = NSMenuItem(title: "Note del curatore", action: nil, keyEquivalent: "")
        item.representedObject = "Note del curatore"
        h.editor.insertNoteOfSeries(item)
        h.step()
        h.type("del curatore")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.editor.insertFootnote(nil)
        h.step()
        h.type("normale")
        #expect(h.attributed.attribute(.footnote, at: 7, effectiveRange: nil) as? String == "Note del curatore")
        let layout = try #require(h.editor.currentLayout())
        #expect(layout.pages[0].rules.count == 2, "due serie, due filetti")
        let text = layout.text.string as NSString
        #expect(layout.pages[0].lines.filter(\.isNote).map { text.substring(with: $0.noteRange!) } == ["normale", "del curatore"],
                "prima la serie delle note a piè di pagina, poi quella del curatore")
        h.undo()
        h.undo()
        #expect(h.text.contains("del curatore") && !h.text.contains("normale"))
    }

    @Test("N6 · Una nota di chiusura si inserisce, ci si scrive alla fine del documento, ed Esc torna al testo")
    func endnote() throws {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        var document = h.editor.currentDocument()
        document.floatStyles.append(FloatStyle(name: "Note di chiusura", placement: .documentEnd, heading: "Note"))
        document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: EditorHarness.body))]))]
        h.editor.replaceContent(document)
        h.step()
        h.select(5)
        let item = NSMenuItem(title: "Note di chiusura", action: nil, keyEquivalent: "")
        item.representedObject = "Note di chiusura"
        h.editor.insertNoteOfSeries(item)
        h.step()
        h.type("in fondo")
        #expect(h.attributed.attribute(.footnote, at: 8, effectiveRange: nil) as? String == "Note di chiusura")
        let layout = try #require(h.editor.currentLayout())
        let noteLines = layout.pages[0].lines.filter { $0.isNote }
        let bodyLines = layout.pages[0].lines.filter { !$0.isNote }
        let line = try #require(noteLines.first)
        let body = try #require(bodyLines.first)
        #expect(line.origin.y < body.origin.y && line.origin.y > body.origin.y - 100, "subito dopo il testo, non in fondo alla pagina")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.editor.noteAnchor == nil && h.selection.location == 14)
        h.undo()
        h.undo()
        #expect(h.text == "Testo")
    }

    @Test("N7 · Una nota a margine si inserisce e ci si scrive: sta nel margine destro, accanto alla riga")
    func marginNote() throws {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        var document = h.editor.currentDocument()
        document.floatStyles.append(FloatStyle(name: "Postille", placement: .outerMargin, reference: .none, showsRule: false))
        document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: EditorHarness.body))]))]
        h.editor.replaceContent(document)
        h.step()
        h.select(5)
        let item = NSMenuItem(title: "Postille", action: nil, keyEquivalent: "")
        item.representedObject = "Postille"
        h.editor.insertNoteOfSeries(item)
        h.step()
        h.type("a margine")
        let layout = try #require(h.editor.currentLayout())
        let noteLines = layout.pages[0].lines.filter { $0.isNote }
        let note = try #require(noteLines.first)
        #expect(note.origin.x > layout.setup.textRect.maxX)
        let caret = try #require(layout.caret(at: h.selection.location, affinity: .upstream))
        #expect(caret.rect.minX > layout.setup.textRect.maxX, "il cursore è nella nota, nel margine")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.editor.noteAnchor == nil)
    }

    @Test("I1 · Un'immagine nella riga si cancella con un tasto, si annulla, si copia e si incolla come immagine")
    func inlineImage() throws {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        var document = h.editor.currentDocument()
        document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("ab", style: EditorHarness.body)),
                                                         .image(ImageObject(source: .embedded(png), width: 30, height: 20)),
                                                         .text(TextRun("cd", style: EditorHarness.body))]))]
        h.editor.replaceContent(document)
        h.step()
        func images() -> Int {
            var count = 0
            h.attributed.enumerateAttribute(.inlineImage, in: NSRange(location: 0, length: h.attributed.length)) { value, range, _ in if value != nil { count += range.length } }
            return count
        }
        #expect(images() == 1)
        h.select(3)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.text == "abcd" && images() == 0)
        h.undo()
        #expect(images() == 1)
        h.select(2, length: 1)
        h.menu(#selector(NSText.copy(_:)))
        h.select(5)
        h.menu(#selector(NSText.paste(_:)))
        #expect(images() == 2, "l'immagine incollata è un'immagine")
        #expect(try #require(h.editor.currentLayout()).pages[0].lines[0].ascent >= 20)
    }

    // MARK: Elenchi e Liste

    @Test("L1 · Elenco: a capo crea una voce; a capo in una voce vuota chiude l'elenco; cancellare all'inizio toglie il segno")
    func listEditing() {
        let h = EditorHarness(paragraphs: ["Voce"])
        defer { h.close() }
        h.select(4)
        _ = h.editor.changeList(actionName: "Elenco") { _ in ListItem(marker: "1.") }
        h.step()
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("Due")
        #expect(h.list(at: 5) == ListItem(marker: "1."))
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.text == "Voce\nDue\n")
        #expect(h.list(at: h.text.utf16.count) == nil, "la voce vuota non è più una voce")
        h.select(5)
        h.press(backward)
        #expect(h.list(at: 5) == nil && h.text == "Voce\nDue\n", "il primo cancella toglie il segno, non unisce")
    }

    @Test("L2 · Tab e Maiusc-Tab cambiano il livello di una voce; nelle Liste con un nome no")
    func listLevels() {
        let h = EditorHarness(paragraphs: ["Voce"])
        defer { h.close() }
        h.select(2)
        _ = h.editor.changeList(actionName: "Elenco") { _ in ListItem(marker: "1.") }
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.list(at: 0)?.level == 2)
        h.press(#selector(NSResponder.insertBacktab(_:)))
        #expect(h.list(at: 0)?.level == 1)
        _ = h.editor.changeList(actionName: "Lista") { _ in ListItem(listName: "Examples") }
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.list(at: 0) == ListItem(listName: "Examples"))
    }

    // MARK: Stili

    @Test("T1 · Lo stile di paragrafo «Esempio» dà anche la Lista; annullando tornano stile e Lista di prima")
    func paragraphStyle() {
        let h = EditorHarness(paragraphs: ["Frase"])
        defer { h.close() }
        h.select(2)
        h.editor.applyNamedStyle(.paragraph, name: "Example")
        h.step()
        #expect(h.attributed.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Example")
        #expect(h.list(at: 0) == ListItem(listName: "Examples"))
        #expect(h.editor.currentLayout()?.pages.first?.markers.count == 1)
        h.undo()
        #expect(h.attributed.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Body")
        #expect(h.list(at: 0) == nil)
    }

    // MARK: Appunti

    @Test("C1 · Copia e incolla nel documento conservano la nota; Taglia toglie e si annulla")
    func clipboard() {
        let h = EditorHarness(paragraphs: ["Testo", "Fine"])
        defer { h.close() }
        h.select(5)
        h.editor.insertFootnote(nil)
        h.step()
        h.type("Nota")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.select(0, length: 10)
        #expect(h.menu(#selector(NSText.copy(_:))))
        h.select(h.text.utf16.count)
        #expect(h.menu(#selector(NSText.paste(_:))))
        #expect(h.editor.currentLayout()?.notes.count == 2, "la nota incollata è una nota")
        h.select(0, length: 6)
        #expect(h.menu(#selector(NSText.cut(_:))))
        #expect(!h.text.hasPrefix("Testo"))
        h.undo()
        #expect(h.text.hasPrefix("Testo"))
    }

    @Test("U5 · Il documento risulta modificato dopo un tasto, e torna pulito annullando")
    func changeCount() {
        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        h.document.updateChangeCount(.changeCleared)
        h.select(1)
        h.type("ab")
        #expect(h.document.isDocumentEdited)
        h.undo()
        #expect(!h.document.isDocumentEdited)
    }

    @Test("S9 · Un comando raro della tastiera (scambia due lettere) e il suo annullamento")
    func rareCommand() {
        let h = EditorHarness(paragraphs: ["abc"])
        defer { h.close() }
        h.select(2)
        h.press(#selector(NSResponder.transpose(_:)))
        #expect(h.text == "acb")
        h.undo()
        #expect(h.text == "abc")
    }

    @Test("C3 · Incollare testo semplice da un'altra applicazione")
    func pasteFromOtherApplication() {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.editor.pasteboard.clearContents()
        h.editor.pasteboard.setString("XYZ", forType: .string)
        h.select(1)
        #expect(h.menu(#selector(NSText.paste(_:))))
        #expect(h.text == "aXYZb")
        h.undo()
        #expect(h.text == "ab")
    }

    // MARK: Metodi di input

    @Test("M1 · Lettere composte: il testo provvisorio del metodo di input è sostituito da quello definitivo")
    func markedText() {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.select(1)
        h.editor.pagesSetMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        h.step()
        #expect(h.editor.pagesMarkedRange == NSRange(location: 1, length: 1))
        h.editor.pagesInsert("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        h.step()
        #expect(h.text == "aéb")
        #expect(h.editor.pagesMarkedRange.location == NSNotFound || h.editor.pagesMarkedRange.length == 0)
    }

    // MARK: Regole (fase 7)

    /// Il testo dei tratti in maiuscoletto nelle righe composte della prima pagina.
    private func smallCapsText(_ h: EditorHarness) -> [String] {
        guard let page = h.editor.currentLayout()?.pages.first else { return [] }
        var pieces: [String] = []
        for placed in page.lines {
            for run in CTLineGetGlyphRuns(placed.line) as? [CTRun] ?? [] {
                let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                guard FontFeatures.settings(of: font).contains(.aat(type: 3, selector: 3)) else { continue }
                let range = CTRunGetStringRange(run)
                let start = placed.documentIndex(forString: range.location)
                pieces.append((h.text as NSString).substring(with: NSRange(location: start, length: range.length)))
            }
        }
        return pieces
    }

    @Test("R1 · Una regola segue il testo mentre si scrive, senza toccarlo; cambiare le regole si annulla")
    func ruleFollowsTyping() {
        let h = EditorHarness(paragraphs: ["Capitolo", "Primo paragrafo del capitolo.", "Secondo paragrafo."])
        defer { h.close() }
        h.select(0)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        h.editor.changeRules([TextRule(target: .firstWords(1), paragraphStyle: "Body", position: .firstAfter("Heading 1"), styleName: "Small Caps")],
                             styles: h.editor.styleSheet)
        h.step()
        #expect(smallCapsText(h) == ["Primo"])
        #expect(h.undoActionName == "Rules")
        // Scrivendo in testa al paragrafo, la regola passa alla parola nuova; il testo resta senza attributi della regola.
        h.select(9)
        h.type("Il ")
        #expect(smallCapsText(h) == ["Il"])
        #expect(!FontFeatures.settings(of: (h.attributed.attribute(.font, at: 9, effectiveRange: nil) as! NSFont) as CTFont).contains(.aat(type: 3, selector: 3)))
        h.undo()
        #expect(h.text == "Capitolo\nPrimo paragrafo del capitolo.\nSecondo paragrafo.")
        h.undo()
        #expect(h.editor.rules.isEmpty)
        #expect(smallCapsText(h).isEmpty)
    }

    @Test("R2 · Prima riga in maiuscoletto: scrivendo, lo stile resta esattamente sulla prima riga; il cursore va dove si scrive")
    func firstLineRuleWhileTyping() {
        let long = "Un paragrafo abbastanza lungo da occupare più righe della pagina, per vedere che il maiuscoletto copre sempre e solo la prima riga, qualunque cosa si scriva in testa."
        let h = EditorHarness(paragraphs: [long, "Breve."])
        defer { h.close() }
        h.editor.changeRules([TextRule(target: .firstLines(1), paragraphStyle: "Body", styleName: "Small Caps")], styles: h.editor.styleSheet)
        h.step()
        func firstLineText() -> String {
            guard let line = h.editor.currentLayout()?.pages.first?.lines.first else { return "" }
            return (h.text as NSString).substring(with: line.range)
        }
        #expect(smallCapsText(h) == [firstLineText(), "Breve."], "la prima riga di ogni paragrafo Testo, e nient'altro")
        h.select(0)
        h.type("Ecco: ")
        #expect(h.selection == NSRange(location: 6, length: 0))
        #expect(smallCapsText(h) == [firstLineText(), "Breve."], "dopo aver scritto, ancora tutta e sola la prima riga")
        #expect(firstLineText().hasPrefix("Ecco: "))
    }

    @Test("I1b · L'ispettore mostra le proprietà dinamiche, e le aggiorna mentre si scrive")
    func dynamicFactsInInspector() {
        let h = EditorHarness(paragraphs: ["Breve.", "Altro."])
        defer { h.close() }
        func fact(_ title: String) -> String? { h.editor.inspectorFacts.first { $0.title == title }?.value }
        h.select(2)
        h.editor.inspect(.paragraph)
        #expect(fact("Lines") == "1")
        #expect(fact("Preceded by") == "nothing: it is the first of the document")
        h.select(6)
        h.type(String(repeating: " ancora parole", count: 20))
        #expect(Int(fact("Lines") ?? "") ?? 0 >= 3, "scrivendo, il numero di righe cresce")
        h.editor.inspect(.line)
        #expect(fact("Position")?.hasPrefix("line ") == true)
        h.editor.inspect(.page)
        #expect(fact("Number") == "1 (odd)")
        h.editor.inspect(.document)
        #expect(fact("Paragraphs") == "2")
    }

    @Test("R3 · Una regola con condizione segue il paragrafo mentre si scrive: una riga centrata, più righe no")
    func conditionalRuleWhileTyping() {
        let h = EditorHarness(paragraphs: ["Breve.", "Altro."])
        defer { h.close() }
        var styles = h.editor.styleSheet
        styles.styles += StyleSheet.ruleStyles.filter { $0.name == "Centered" }
        h.editor.changeRules([TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centered")], styles: styles)
        h.step()
        func centered() -> Bool {
            // L'ultima riga del primo paragrafo: una riga piena e giustificata sembrerebbe centrata anche senza esserlo.
            guard let layout = h.editor.currentLayout(), let line = layout.pages[0].lines.last(where: { $0.paragraphLocation == 0 }) else { return false }
            let column = layout.setup.textRect
            return abs((line.origin.x - column.minX) - (column.width - line.width) / 2) < 1.5
        }
        #expect(centered())
        h.select(6)
        h.type(String(repeating: " ancora", count: 15))
        #expect(!centered(), "diventato di più righe, non è più centrato")
        h.undo()
        #expect(centered())
        h.undo()
        #expect(!centered() && h.editor.rules.isEmpty)
    }

    // MARK: Interfaccia (tappa I.1)

    @Test("G1 · Semplice e avanzata: ispettore e percorso solo nell'avanzata; la scelta vale per le finestre nuove")
    func interfaceModes() {
        let saved = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = saved }
        InterfaceMode.lastChoice = .simple
        let h = EditorHarness(paragraphs: ["Uno."])
        defer { h.close() }
        #expect(h.editor.interfaceMode == .simple && !h.editor.showsAdvancedTools)
        #expect(h.editor.bandControls["grassetto"]?.isHidden == false)
        #expect(h.editor.bandControls["stileCarattere"]?.isHidden == true)
        #expect(h.editor.bandControls["spazi"]?.isHidden == true)
        #expect(h.editor.styleMonitorView.isHidden)
        h.editor.updateCounts()
        #expect(h.editor.statusTextForTests.contains("1 word") && !h.editor.statusTextForTests.contains("chars"))
        h.editor.setInterfaceMode(.advanced)
        h.step()
        #expect(h.editor.showsAdvancedTools)
        #expect(h.editor.bandControls["stileCarattere"]?.isHidden == false)
        #expect(h.editor.bandControls["spazi"]?.isHidden == false)
        #expect(!h.editor.styleMonitorView.isHidden)
        #expect(InterfaceMode.lastChoice == .advanced)
        let other = EditorHarness(paragraphs: ["Due."])
        defer { other.close() }
        #expect(other.editor.interfaceMode == .advanced && other.editor.showsAdvancedTools, "una finestra nuova parte dall'ultima scelta")
        h.editor.toggleInterfaceMode(nil)
        #expect(!h.editor.showsAdvancedTools && other.editor.showsAdvancedTools, "ogni finestra ha il suo interruttore")
    }

    @Test("G2 · La barra: Annulla e Ripeti si accendono e funzionano; Nota inserisce una nota; ¶ mostra i nascosti")
    func toolbarCommands() throws {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        let undo = try #require(h.editor.bandControls["annulla"] as? NSButton)
        let redo = try #require(h.editor.bandControls["ripeti"] as? NSButton)
        h.editor.refreshBandState()
        #expect(!undo.isEnabled && !redo.isEnabled)
        h.select(1)
        h.type("X")
        #expect(undo.isEnabled)
        undo.performClick(nil)
        h.step()
        #expect(h.text == "ab" && redo.isEnabled)
        redo.performClick(nil)
        h.step()
        #expect(h.text == "aXb")

        let note = try #require(h.editor.bandControls["nota"] as? NSPopUpButton)
        let menu = try #require(note.menu)
        menu.delegate?.menuNeedsUpdate?(menu)
        let footnote = try #require(menu.items.first { $0.title == "Footnote" })
        h.select(3)
        NSApp.sendAction(try #require(footnote.action), to: footnote.target, from: footnote)
        h.step()
        #expect(h.text.contains("\u{FFFC}"), "il richiamo della nota è nel testo")
        let illustration = try #require(h.editor.bandControls["illustrazione"]?.menu)
        illustration.delegate?.menuNeedsUpdate?(illustration)
        #expect(illustration.items.map(\.title).contains("Figure with Caption…"))
        #expect(!(h.editor.bandControls["illustrazione"]?.isEnabled ?? true), "dentro la nota non si inserisce un'illustrazione")

        let invisibles = try #require(h.editor.bandControls["nascosti"] as? NSButton)
        let before = invisibles.state
        invisibles.performClick(nil)
        #expect(invisibles.state != before)
        invisibles.performClick(nil)
        #expect(invisibles.state == before)
        #expect(h.editor.bandControls["tabella"]?.isEnabled == false, "spento finché non arriva la sua tappa")
        #expect(h.editor.bandControls["cerca"]?.isEnabled == true, "Cerca e sostituisci c'è")
        #expect(h.editor.bandControls["stampa"]?.isEnabled == true, "la Stampa c'è")
    }

    @Test("U6 · Dopo Ripeti il testo riscritto non resta selezionato: il cursore va dopo di lui")
    func redoPutsCaretAfterText() {
        let h = EditorHarness(paragraphs: ["ab"])
        defer { h.close() }
        h.select(1)
        h.type("XYZ")
        h.undo()
        #expect(h.text == "ab" && h.selection == NSRange(location: 1, length: 0), "annullando, il cursore dove si era cominciato")
        h.redo()
        #expect(h.text == "aXYZb")
        #expect(h.selection == NSRange(location: 4, length: 0), "ripetendo, il cursore dopo il testo, senza selezione")
        h.select(4)
        h.press(#selector(NSResponder.deleteBackward(_:)), times: 2)
        h.undo()
        h.redo()
        #expect(h.text == "aXb" && h.selection == NSRange(location: 2, length: 0), "anche dopo una cancellazione ripetuta")
    }

    @Test("G3 · Ribbon e righello: grassetto, corsivo, maiuscoletto, allineamento, interlinea, carattere speciale; il monitor degli stili")
    func characterAndParagraphControls() throws {
        let h = EditorHarness(paragraphs: ["Una prova.", "Altro."])
        defer { h.close() }
        func font(at index: Int) -> NSFont { h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont }
        h.select(0, length: 3)
        let bold = try #require(h.editor.bandControls["grassetto"] as? NSButton)
        bold.performClick(nil)
        h.step()
        #expect(TextStyling.traits(ofFace: font(at: 1).fontName)?.bold == true && bold.state == .on)
        #expect(h.editor.styleMonitor.style == "Body" && h.editor.styleMonitor.additions.contains("char. bold"))
        h.undo()
        #expect(TextStyling.traits(ofFace: font(at: 1).fontName)?.bold == false)
        h.select(0, length: 3)
        (h.editor.bandControls["corsivo"] as? NSButton)?.performClick(nil)
        h.step()
        #expect(TextStyling.traits(ofFace: font(at: 1).fontName)?.italic == true)
        (h.editor.bandControls["maiuscoletto"] as? NSButton)?.performClick(nil)
        h.step()
        #expect(FontFeatures.settings(of: font(at: 1) as CTFont).contains(.aat(type: 3, selector: 3)))
        #expect(TextStyling.traits(ofFace: font(at: 1).fontName)?.italic == true, "il maiuscoletto non toglie il corsivo")

        let alignment = try #require(h.editor.bandControls["allineamento"] as? BandSegments)
        alignment.press(1)
        h.step()
        let style = h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
        #expect(h.editor.styleMonitor.additions.contains("para. alignment centered"))
        let spacing = try #require(h.editor.bandControls["interlinea"] as? BandSegments)
        spacing.press(1)
        h.step()
        #expect((h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineHeightMultiple == 1.5)
        #expect(spacing.selectedSegment == 1)

        h.select(3)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.representedObject = "\u{00A0}"
        h.editor.insertSpecialCharacter(item)
        h.step()
        #expect(h.text.hasPrefix("Una\u{00A0} prova."))
    }

    @Test("G3b · Grassetto dal Ribbon conserva gli altri assi e il ruolo nel testo che segue")
    func roleCommandPreservesIntentions() throws {
        let h = EditorHarness(paragraphs: ["Testo"])
        defer { h.close() }
        let regular = CharacterStyle(fontName: "Skia-Regular", size: 12,
                                     variations: [AxisValue(tag: "wdth", value: 0.8)], fontRole: .regular)
        h.editor.replaceContent(Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: regular))]))]))
        h.select(0, length: 4)
        let bold = try #require(h.editor.bandControls["grassetto"] as? NSButton)
        bold.performClick(nil)
        h.step()
        let font = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(FontVariations.values(of: font) == [AxisValue(tag: "wght", value: 1.9499), AxisValue(tag: "wdth", value: 0.8)])
        #expect(h.attributed.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "bold" && bold.state == .on)
        h.select(4)
        h.type("X")
        #expect(h.attributed.attribute(.fontRole, at: 4, effectiveRange: nil) as? String == "bold")
        h.undo()
        h.undo()
        #expect(h.attributed.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "regular")
    }

    @Test("G4 · In ogni fascia lo spazio fra due controlli è sempre lo stesso, anche cambiando la larghezza della finestra")
    func equalSpacing() throws {
        let h = EditorHarness(paragraphs: ["Uno."])
        defer { h.close() }
        h.editor.setInterfaceMode(.simple)
        h.editor.showFindBar(nil)
        for width in [700.0, 900.0, 1180.0, 1500.0, 1900.0] {
            if let window = h.editor.window {
                var frame = window.frame
                frame.size.width = CGFloat(width)
                frame.size.height = 800
                window.setFrame(frame, display: true)
            }
            h.editor.window?.layoutIfNeeded()
            h.step()
            #expect(h.editor.window?.contentView?.frame.width == CGFloat(width))
            let rows = h.editor.bandRows
            #expect(rows.count >= 4)
            for row in rows {
                let views = row.arrangedSubviews.filter { !$0.isHidden && !($0 is SpacerView) }
                for view in views {
                    #expect(view.frame.minX >= -0.5 && view.frame.maxX <= row.bounds.width + 0.5,
                            "a \(Int(width)) pt \(type(of: view)) esce dalla fascia")
                }
                for (left, right) in zip(views, views.dropFirst()) where row.arrangedSubviews.firstIndex(of: right)! == row.arrangedSubviews.firstIndex(of: left)! + 1 {
                    let gap = right.frame.minX - left.frame.maxX
                    #expect(abs(gap - row.spacing) < 0.5, "a \(Int(width)) pt: \(gap) fra \(type(of: left)) e \(type(of: right))")
                }
            }
        }
    }

    @Test("G5 · Dopo un pizzico sul trackpad la percentuale dello zoom è quella vera")
    func zoomTitleFollowsPinch() {
        let h = EditorHarness(paragraphs: ["Uno."])
        defer { h.close() }
        h.editor.window?.setContentSize(NSSize(width: 1180, height: 800))
        h.step()
        h.editor.pinchForTests(by: 0.4)
        h.step()
        #expect(h.editor.zoomTitle == "\(Int((h.editor.pageScale * 100).rounded()))%")
        let before = h.editor.zoomTitle
        h.editor.pinchForTests(by: -0.3)
        h.step()
        #expect(h.editor.zoomTitle != before && h.editor.zoomTitle == "\(Int((h.editor.pageScale * 100).rounded()))%")
    }

    @Test("C4 · Il colore: sulla selezione e sul testo che si scrive; si annulla; il monitor degli stili lo dice")
    func textColor() {
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        func hex(at index: Int) -> String? { TextStyling.textColor(in: h.attributed, at: index) }
        h.select(0, length: 3)
        h.editor.setTextColor("#9b1c1c")
        h.step()
        #expect(hex(at: 1) == "#9b1c1c" && hex(at: 4) == nil)
        #expect(h.editor.styleMonitor.additions.contains("char. color dark red"))
        h.undo()
        #expect(hex(at: 1) == nil)
        h.select(10)
        h.editor.setTextColor("#1f3f8f")
        h.type(" blu")
        #expect(hex(at: 12) == "#1f3f8f", "il testo scritto dopo prende il colore scelto")
        h.select(11, length: 3)
        h.editor.setTextColor(nil)
        h.step()
        #expect(hex(at: 12) == nil, "di nuovo automatico")
    }

    @Test("C5 · Apice e pedice dal Ribbon: si accendono, si spengono, valgono per il testo che si scrive")
    func superscriptButtons() throws {
        let h = EditorHarness(paragraphs: ["H2O"])
        defer { h.close() }
        func position(at index: Int) -> String? { h.attributed.attribute(.verticalPosition, at: index, effectiveRange: nil) as? String }
        let subscriptButton = try #require(h.editor.bandControls["pedice"] as? NSButton)
        h.select(1, length: 1)
        subscriptButton.performClick(nil)
        h.step()
        #expect(position(at: 1) == "subscript" && position(at: 0) == nil && subscriptButton.state == .on)
        #expect(h.editor.styleMonitor.additions.contains("char. subscript"))
        subscriptButton.performClick(nil)
        h.step()
        #expect(position(at: 1) == nil, "premuto di nuovo, torna sulla linea di base")
        h.select(3)
        (h.editor.bandControls["apice"] as? NSButton)?.performClick(nil)
        h.type("2")
        #expect(position(at: 3) == "superscript")
    }

    @Test("C6 · Sottolineato e barrato dal Ribbon: valori già pronti del filetto, che si accendono e si spengono")
    func underlineButtons() throws {
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        func lines(at index: Int) -> String? { h.attributed.attribute(.lineDecorations, at: index, effectiveRange: nil) as? String }
        h.select(0, length: 3)
        let underline = try #require(h.editor.bandControls["sottolineato"] as? NSButton)
        let strike = try #require(h.editor.bandControls["barrato"] as? NSButton)
        underline.performClick(nil)
        h.step()
        #expect(lines(at: 1) == "underline" && underline.state == .on)
        strike.performClick(nil)
        h.step()
        #expect(lines(at: 1) == "underline; strikethrough" && strike.state == .on)
        #expect(h.editor.styleMonitor.additions.contains("char. underline, strikethrough"))
        underline.performClick(nil)
        h.step()
        #expect(lines(at: 1) == "strikethrough" && underline.state == .off)
        h.undo()
        #expect(lines(at: 1) == "underline; strikethrough")
    }

    // MARK: Righello (tappa I.3)

    private func style(_ h: EditorHarness, at index: Int) -> NSParagraphStyle {
        h.attributed.attribute(.paragraphStyle, at: index, effectiveRange: nil) as! NSParagraphStyle
    }

    @Test("P1 · Righello, paragrafo comune: rientro sinistro (si porta dietro la prima riga), prima riga, destro; un passo solo")
    func rulerParagraph() throws {
        let h = EditorHarness(paragraphs: ["Uno.", "Due."])
        defer { h.close() }
        h.select(1)
        h.editor.dragRulerForTests(.left, to: 36)
        h.step()
        #expect(style(h, at: 0).headIndent == 36 && style(h, at: 0).firstLineHeadIndent == 36)
        #expect(style(h, at: 5).headIndent == 0, "l'altro paragrafo non cambia")
        h.editor.dragRulerForTests(.firstLine, to: 50)
        h.step()
        #expect(style(h, at: 0).firstLineHeadIndent == 50 && style(h, at: 0).headIndent == 36)
        h.editor.dragRulerForTests(.right, to: 20)
        h.step()
        #expect(style(h, at: 0).tailIndent == -20)
        h.undo()
        #expect(style(h, at: 0).tailIndent == 0 && style(h, at: 0).firstLineHeadIndent == 50, "un trascinamento, un passo")
        let ruler = try #require(h.editor.rulerGeometry)
        #expect(ruler.markerWidth == nil && ruler.left == 36)
    }

    @Test("P2 · Righello, Lista con un nome: si sposta tutta la Lista; con ⌥ solo la voce; segno e testo si spostano ciascuno per conto suo")
    func rulerNamedList() throws {
        let h = EditorHarness(paragraphs: ["Primo esempio.", "Testo.", "Secondo esempio."])
        defer { h.close() }
        for location in [0, 22] {
            h.select(location)
            h.editor.applyNamedStyle(.paragraph, name: "Example")
        }
        h.select(2)
        let ruler = try #require(h.editor.rulerGeometry)
        #expect(ruler.markerWidth != nil && abs(ruler.left - 24) < 0.01, "una voce: il testo comincia a 24 pt")
        h.editor.dragRulerForTests(.left, to: 40)
        #expect(h.editor.currentDocument().lists.first { $0.name == "Examples" }?.textIndent == 40)
        #expect(TextStyling.listItem(in: h.attributed, at: 2)?.textIndent == nil, "la misura è della Lista, non della voce")
        h.editor.dragRulerForTests(.left, to: 60, modifiers: .option)
        #expect(TextStyling.listItem(in: h.attributed, at: 2)?.textIndent == 60)
        #expect(TextStyling.listItem(in: h.attributed, at: 25)?.textIndent == nil, "l'altra voce resta alla misura della Lista")
        h.select(25)
        let marker = try #require(h.editor.rulerGeometry)
        #expect(abs(marker.firstLine - 18) < 0.01 && abs(marker.left - 40) < 0.01, "il segno finisce a 18 pt, il testo comincia a 40")
        h.editor.dragRulerForTests(.firstLine, to: 30)
        let esempi = h.editor.currentDocument().lists.first { $0.name == "Examples" }
        #expect(esempi?.markerPosition == 30 && esempi?.textIndent == 40, "il segno si sposta, il testo resta")
        h.editor.dragRulerForTests(.left, to: 50)
        let after = h.editor.currentDocument().lists.first { $0.name == "Examples" }
        #expect(after?.textIndent == 50 && after?.markerPosition == 30, "il testo si sposta, il segno resta")
    }

    @Test("P3 · Righello, elenco semplice: cambia il blocco di voci consecutive, non un altro elenco più avanti")
    func rulerSimpleList() {
        let h = EditorHarness(paragraphs: ["Uno", "Due", "Testo", "Tre"])
        defer { h.close() }
        for location in [0, 4, 14] {
            h.select(location)
            h.editor.toggleList(nil)
        }
        h.select(5)
        h.editor.dragRulerForTests(.left, to: 50)
        #expect(TextStyling.listItem(in: h.attributed, at: 0)?.textIndent == 50 && TextStyling.listItem(in: h.attributed, at: 4)?.textIndent == 50)
        #expect(TextStyling.listItem(in: h.attributed, at: 14)?.textIndent == nil, "il secondo elenco non cambia")
    }

    @Test("P4 · Righello con il mouse: clic e trascinamento consegnati dalla finestra, come da macOS")
    func rulerThroughWindowEvents() throws {
        let h = EditorHarness(paragraphs: ["Un paragrafo normale.", "Secondo."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1280, height: 800))
        // Una finestra mai mostrata non riceve i clic: va portata davanti, come quella vera.
        window.orderFront(nil)
        h.select(3)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            for sub in view.subviews { if let found = find(type, in: sub) { return found } }
            return nil
        }
        let content = try #require(window.contentView)
        let ruler = try #require(find(RulerView.self, in: content))
        let g = try #require(ruler.geometry)
        let start = ruler.convert(NSPoint(x: g.columnMinX + g.left * g.scale, y: ruler.bounds.height - 5), to: nil)
        #expect(window.contentView?.superview?.hitTest(start) === ruler, "il clic sul segno arriva al righello")
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let end = NSPoint(x: start.x + 2 * 72 / 2.54 * g.scale, y: start.y)
        window.sendEvent(event(.leftMouseDown, start))
        window.sendEvent(event(.leftMouseDragged, end))
        window.sendEvent(event(.leftMouseUp, end))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        let headIndent = (h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).headIndent
        #expect(abs(headIndent - 72 / 2.54 * 2) < 1, "2 cm, agganciati al millimetro")
    }

    @Test("P5 · Mentre si trascina un rientro il testo si ricompone dal vivo; il documento cambia solo al rilascio, in un passo")
    func rulerLivePreview() throws {
        let h = EditorHarness(paragraphs: ["Un paragrafo normale.", "Secondo."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.orderFront(nil)
        h.select(3)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let match = view as? T { return match }
            for sub in view.subviews { if let found = find(type, in: sub) { return found } }
            return nil
        }
        let content = try #require(window.contentView)
        let ruler = try #require(find(RulerView.self, in: content))
        let g = try #require(ruler.geometry)
        let start = ruler.convert(NSPoint(x: g.columnMinX + g.left * g.scale, y: ruler.bounds.height - 5), to: nil)
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func firstLineX() -> CGFloat { h.editor.currentLayout()?.pages[0].lines[0].origin.x ?? 0 }
        func headIndent() -> CGFloat { (h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).headIndent }
        let before = firstLineX()
        let middle = NSPoint(x: start.x + 72 / 2.54 * g.scale, y: start.y)
        window.sendEvent(event(.leftMouseDown, start))
        window.sendEvent(event(.leftMouseDragged, middle))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(abs(firstLineX() - before - 72 / 2.54) < 1, "a metà trascinamento la pagina mostra già il paragrafo rientrato di 1 cm")
        #expect(headIndent() == 0, "ma il documento non è ancora cambiato")
        window.sendEvent(event(.leftMouseUp, middle))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        #expect(abs(headIndent() - 72 / 2.54) < 1)
        h.undo()
        #expect(headIndent() == 0 && abs(firstLineX() - before) < 0.01, "un trascinamento, un passo")
    }

    @Test("C7 · Da un altro documento arrivano gli stili e le serie che mancano; per un nome con un'altra definizione si sceglie; un passo solo")
    func pasteBetweenDocuments() throws {
        let a = EditorHarness(paragraphs: ["x"])
        defer { a.close() }
        let b = EditorHarness(paragraphs: ["x"])
        defer { b.close() }
        b.editor.pasteboard = a.editor.pasteboard
        let head = "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\n"
        a.editor.replaceContent(try DocumentFormat.document(from: head + """
            <lists>
            <list name="Postille" counter="a"/>
            </lists>
            <styles>
            <style name="Enfasi" target="character" size="14"/>
            </styles>
            <float-styles>
            <float-style name="Postilla" list="Postille"/>
            </float-styles>
            <p>Uno <t char-style="Enfasi">due</t><note style="Postilla">tre</note>.</p>
            </document>
            """))
        b.editor.replaceContent(try DocumentFormat.document(from: head + """
            <styles>
            <style name="Enfasi" target="character" size="10"/>
            </styles>
            <p>Fine.</p>
            </document>
            """))
        a.document.undoManager?.removeAllActions()
        b.document.undoManager?.removeAllActions()
        a.step()
        a.select(0, length: a.attributed.length)
        a.menu(#selector(NSText.copy(_:)))
        let original = b.text
        func size(at index: Int) -> CGFloat { (b.attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 }
        func paste(answer: DefinitionImport.Policy?) -> [DefinitionImport.Conflict] {
            var asked: [DefinitionImport.Conflict] = []
            b.editor.choosePasteConflictPolicy = { conflicts, finish in
                asked = conflicts
                finish(answer)
            }
            b.select(0)
            b.menu(#selector(NSText.paste(_:)))
            return asked
        }

        // Vince la destinazione: «Enfasi» è quella di B; la serie «Postilla», che B non ha, arriva con la sua Lista.
        #expect(paste(answer: .keepDestination) == [.init(kind: .style, name: "Enfasi")])
        var settings = b.editor.currentDocument()
        #expect(settings.floatStyles.contains { $0.name == "Postilla" && $0.listName == "Postille" })
        #expect(settings.lists.contains { $0.name == "Postille" })
        #expect(settings.styles.style(named: "Enfasi")?.values.size == 10)
        #expect(size(at: 4) == 10, "il testo prende l'Enfasi di B")
        #expect(b.editor.currentLayout()?.notes.count == 1)
        // Salvato e riaperto, il testo conserva lo stile e la nota la sua serie.
        let reread = try DocumentFormat.document(from: DocumentFormat.data(for: settings))
        guard case .paragraph(let paragraph) = reread.blocks.first else { Issue.record("manca il paragrafo"); return }
        #expect(paragraph.inlines.contains { if case .text(let run) = $0 { run.characterStyleName == "Enfasi" } else { false } })
        #expect(paragraph.inlines.contains { if case .floating(let note) = $0 { note.style == "Postilla" } else { false } })

        // Un passo solo: annullando spariscono testo e definizioni; ripetendo tornano.
        #expect(b.undoActionName == "Paste")
        b.undo()
        #expect(b.text == original)
        #expect(!b.editor.currentDocument().floatStyles.contains { $0.name == "Postilla" })
        b.redo()
        #expect(b.editor.currentDocument().floatStyles.contains { $0.name == "Postilla" })
        #expect(b.text != original)
        b.undo()

        // Copie rinominate: entra «Enfasi (2)» e il testo resta com'era in A.
        _ = paste(answer: .renameCopies)
        settings = b.editor.currentDocument()
        #expect(settings.styles.style(named: "Enfasi (2)")?.values.size == 14)
        #expect(b.attributed.attribute(.characterStyleName, at: 4, effectiveRange: nil) as? String == "Enfasi (2)")
        #expect(size(at: 4) == 14)
        b.undo()
        #expect(b.editor.currentDocument().styles.style(named: "Enfasi (2)") == nil)

        // Annulla: non succede niente.
        _ = paste(answer: nil)
        #expect(b.text == original && !b.editor.currentDocument().floatStyles.contains { $0.name == "Postilla" })
    }

    @Test("I2 · Scegliendo un oggetto nel percorso l'altezza delle pagine non cambia, e l'ispettore resta largo quanto serve")
    func inspectorDoesNotResizeWindow() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1180, height: 900))
        h.editor.setInterfaceMode(.advanced)
        h.select(3)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        var heights: Set<CGFloat> = []
        for object in InspectedObject.allCases {
            h.editor.inspect(object)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            let panel = try #require(h.editor.inspectorPanel)
            heights.insert(try #require(panel.superview).frame.height)
            #expect(panel.frame.width >= InspectorView.minimumWidth, "\(object): ispettore largo almeno \(InspectorView.minimumWidth)")
        }
        #expect(heights.count == 1, "con «Parola» la finestra restava vuota per metà: \(heights)")
    }

    @Test("U7 · Annullando o ripetendo un comando (uno stile) torna la selezione di prima e di dopo, non un cursore altrove")
    func undoAttributeChangeSelectsText() {
        let h = EditorHarness(paragraphs: ["Primo paragrafo di prova.", "Secondo paragrafo.", "Terzo."])
        defer { h.close() }
        h.select(5, length: 4)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        h.undo()
        #expect(h.selection == NSRange(location: 5, length: 4), "prima il cursore andava nel terzo paragrafo: \(h.selection)")
        h.redo()
        #expect(h.selection == NSRange(location: 5, length: 4), "\(h.selection)")
    }

    @Test("U8 · Dopo Annulla di un comando sulla tabella il cursore torna nella cella dov'era; Ripeti lo rimette dove l'aveva lasciato il comando; la scrittura segue ancora U6")
    func undoCommandRestoresCaret() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("Nome")
        h.press(#selector(NSResponder.insertTab(_:)))
        h.type("Valore")
        h.press(#selector(NSResponder.insertTab(_:)))
        h.type("x")
        // Il cursore dopo «x», nella terza colonna; togliere la seconda colonna lo sposta.
        let before = h.selection
        h.editor.perform(.removeColumn)
        h.step()
        // (il cursore resta nella colonna che ha preso il posto: la terza, ora seconda)
        let after = h.selection
        h.undo()
        #expect(h.selection == before, "prima il cursore andava alla fine di «Valore»: \(h.selection)")
        h.redo()
        #expect(h.selection == after)
        // Scrivere e annullare: il cursore alla fine del punto cambiato (U6), come prima.
        h.undo()
        h.select(7)
        h.type("abc")
        h.select(0)
        h.step()
        h.undo()
        #expect(h.selection == NSRange(location: 7, length: 0))
    }

    @Test("N9 · All'inizio di un paragrafo, davanti al richiamo di una nota, si scrive con l'aspetto del corpo")
    func typingBeforeNoteAnchor() throws {
        let h = EditorHarness(paragraphs: ["Primo paragrafo."])
        defer { h.close() }
        h.select(0)
        h.editor.insertFootnote(nil)
        h.step()
        h.type("Nota")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        h.select(0)
        h.type("X")
        let font = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 12, "prendeva il corpo 10 della nota")
        #expect(h.attributed.attribute(.footnote, at: 0, effectiveRange: nil) == nil)
    }

    @Test("M1 · Un clic su un'aggiunta del monitor la toglie: dal tratto attorno al cursore, dalla selezione, dal paragrafo; «+N» toglie tutte; un passo")
    func removeAdditionsFromMonitor() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo.", "Altro."])
        defer { h.close() }
        func font(at index: Int) -> NSFont { h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont }
        func italic(_ index: Int) -> Bool { TextStyling.traits(ofFace: font(at: index).fontName)?.italic == true }
        func underlined(_ index: Int) -> Bool { (h.attributed.attribute(.lineDecorations, at: index, effectiveRange: nil) as? String).map { !$0.isEmpty } ?? false }
        // «prova» (4…8) in corsivo e sottolineata.
        h.select(4, length: 5)
        h.editor.toggleItalic(nil)
        h.step()
        h.editor.toggleUnderline(nil)
        h.step()

        // Al cursore, dentro la parola: il clic sulla prima aggiunta toglie il corsivo da tutta la parola, e basta.
        h.select(6)
        #expect(h.editor.styleMonitor.additions == ["char. italic", "char. underline"])
        h.editor.styleMonitorView.click(pill: 1)
        h.step()
        #expect(!italic(4) && !italic(8), "tutta la parola, non solo il carattere del cursore")
        #expect(underlined(4) && underlined(8), "il sottolineato resta")
        #expect(h.editor.styleMonitor.additions == ["char. underline"])
        h.type("x")
        #expect(!italic(6), "anche ciò che si scrive dopo non è più in corsivo")
        h.undo()
        h.undo()
        #expect(italic(4) && italic(8), "un passo solo di Annulla")

        // Con una selezione: solo la selezione.
        h.select(4, length: 2)
        h.editor.styleMonitorView.click(pill: 2)
        h.step()
        #expect(!underlined(4) && !underlined(5) && underlined(6))

        // Un'aggiunta di paragrafo: il paragrafo torna allo stile.
        h.select(1)
        let alignment = try #require(h.editor.bandControls["allineamento"] as? BandSegments)
        alignment.press(1)
        h.step()
        #expect(h.editor.styleMonitor.additions.contains("para. alignment centered"))
        let index = try #require(h.editor.styleMonitor.additions.firstIndex(of: "para. alignment centered"))
        // Le prime due aggiunte hanno una pastiglia; le altre stanno sotto «+N».
        if index < 2 {
            h.editor.styleMonitorView.click(pill: index + 1)
        } else {
            h.editor.removeStyleAdditions([index])
        }
        h.step()
        #expect((h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment != .center)

        // Tre aggiunte: la terza va sotto «+1», e il suo elenco ha «Togli tutte le aggiunte».
        h.select(10, length: 2)
        h.editor.toggleItalic(nil)
        h.step()
        h.editor.toggleUnderline(nil)
        h.step()
        h.editor.toggleSuperscript(nil)
        h.step()
        #expect(h.editor.styleMonitor.additions.count == 3)
        let menu = h.editor.styleMonitorView.moreMenu()
        let all = try #require(menu.items.last)
        #expect(all.title == "Remove All Additions")
        menu.performActionForItem(at: menu.items.count - 1)
        h.step()
        #expect(h.editor.styleMonitor.additions.isEmpty)
        #expect(!italic(10) && !underlined(10))
        h.undo()
        #expect(h.editor.styleMonitor.additions.count == 3, "tutte tornano con un solo Annulla")
    }

    @Test("M2 · Il menu di un'addizione ha tre azioni brevi; «Metti nello stile» trasferisce solo quella; anche «+N» ha il menu")
    func singleAdditionMenu() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo.", "Altro."])
        defer { h.close() }
        h.select(4, length: 5)
        h.editor.toggleItalic(nil)
        h.step()
        h.editor.toggleUnderline(nil)
        h.step()
        h.editor.toggleSuperscript(nil)
        h.step()

        let menu = h.editor.additionMonitorMenu(at: 0)
        #expect(menu.items.map(\.title) == ["Remove", "Put into the Style", "New Style…"])
        let hidden = try #require(h.editor.styleMonitorView.moreMenu().items.first?.submenu)
        #expect(hidden.items.map(\.title) == ["Remove", "Put into the Style", "New Style…"])
        menu.performActionForItem(at: 1)
        h.step()
        #expect(h.editor.currentDocument().styles.style(named: "Body")?.formulas.contains { $0.operation == StylePropertyOperation(.add, .font, .font(.italic)) } == true)
        #expect(h.editor.currentDocument().styles.style(named: "Body")?.values.decorations == nil)
        #expect(h.editor.styleMonitor.additions.count == 2, "restano sottolineato e apice, dati qui")
        #expect(h.editor.styleMonitor.additions.contains("char. underline"))
        let elsewhere = try #require(h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)
        #expect(TextStyling.traits(ofFace: elsewhere.fontName)?.italic == true, "lo stile cambia anche altrove")
        #expect((h.attributed.attribute(.lineDecorations, at: 21, effectiveRange: nil) as? String) == nil)
        h.undo()
        #expect(h.editor.currentDocument().styles.style(named: "Body")?.values.italic != true)
        #expect(h.editor.styleMonitor.additions.count == 3, "un solo Annulla ripristina tutte le aggiunte")
    }

    @Test("M2b · Mettere la famiglia nello stile non trasferisce il corsivo né le altre aggiunte")
    func familyAdditionMovesAlone() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo.", "Altro."])
        defer { h.close() }
        h.select(4, length: 5)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Times New Roman")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        h.editor.toggleItalic(nil)
        h.step()
        h.editor.toggleUnderline(nil)
        h.step()
        #expect(h.editor.styleMonitor.additions == ["char. Times New Roman", "char. italic", "char. underline"])

        h.editor.additionMonitorMenu(at: 0).performActionForItem(at: 1)
        h.step()
        let textStyle = try #require(h.editor.currentDocument().styles.style(named: "Body"))
        #expect(textStyle.formulas.contains { $0.operation == StylePropertyOperation(.set, .family, .family("Times New Roman")) })
        #expect(textStyle.values.italic == nil)
        #expect(textStyle.values.decorations == nil)
        #expect(h.editor.styleMonitor.additions == ["char. italic", "char. underline"])
        let elsewhere = try #require(h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)
        #expect(elsewhere.familyName == "Times New Roman")
        #expect(TextStyling.traits(ofFace: elsewhere.fontName)?.italic == false)
        h.undo()
        #expect(h.editor.styleMonitor.additions == ["char. Times New Roman", "char. italic", "char. underline"])
    }

    @Test("M2c · La famiglia con una faccia nera personalizzata entra nello stile dalla pill")
    func customBoldFamilyAdditionMovesIntoStyle() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: FontRolePreferences.key)
        defer {
            if let previous { defaults.set(previous, forKey: FontRolePreferences.key) }
            else { defaults.removeObject(forKey: FontRolePreferences.key) }
        }
        FontRolePreferences.save(FontRoleTable(customizations: [
            .init(family: "Baskerville", role: .bold, equivalence: FontRoleEquivalence(staticFace: "Baskerville-SemiBold")),
        ]))
        let h = EditorHarness()
        defer { h.close() }
        var document = h.editor.currentDocument()
        let position = try #require(document.styles.styles.firstIndex { $0.name == "Body" })
        document.styles.styles[position].values.family = "Hoefler Text"
        document.styles.styles[position].values.bold = true
        let character = document.styles.resolveCharacter(paragraphStyle: "Body", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
        let paragraph = document.styles.resolveParagraph(styleName: "Body")
        document.blocks = [
            .paragraph(Paragraph(styleName: "Body", style: paragraph, inlines: [.text(TextRun("Una prova di testo.", style: character))])),
            .paragraph(Paragraph(styleName: "Body", style: paragraph, inlines: [.text(TextRun("Altro.", style: character))])),
        ]
        h.editor.replaceContent(document)
        h.select(4, length: 5)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Baskerville")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        #expect((h.attributed.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")
        #expect(h.editor.styleMonitor.additions == ["char. Baskerville"])

        h.editor.additionMonitorMenu(at: 0).performActionForItem(at: 1)
        h.step()
        let values = try #require(h.editor.currentDocument().styles.style(named: "Body")?.values)
        #expect(h.editor.currentDocument().styles.style(named: "Body")?.formulas.contains { $0.operation == StylePropertyOperation(.set, .family, .family("Baskerville")) } == true)
        #expect(values.bold == true && values.fontName == nil)
        #expect(h.editor.styleMonitor.additions.isEmpty)
        #expect((h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")
        h.undo()
        #expect(h.editor.styleMonitor.additions == ["char. Baskerville"])
    }

    @Test("M3 · «Nuovo stile…» incorpora solo l'addizione scelta, la toglie dal testo e conserva le altre; un solo Annulla")
    func newStyleFromSingleAddition() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo.", "Altro."])
        defer { h.close() }
        let original = h.editor.currentDocument().styles.style(named: "Body")
        h.select(4, length: 5)
        h.editor.toggleItalic(nil)
        h.step()
        h.editor.toggleUnderline(nil)
        h.step()
        h.editor.styleNameAnswerForTests = "Corsivo speciale"
        let menu = h.editor.additionMonitorMenu(at: 0)
        menu.performActionForItem(at: 2)
        h.step()

        let created = try #require(h.editor.currentDocument().styles.style(named: "Corsivo speciale"))
        #expect(created.target == .character && created.basedOn == nil)
        #expect(created.formulas.contains { $0.operation == StylePropertyOperation(.add, .font, .font(.italic)) })
        #expect(created.values.decorations == nil && created.values.verticalPosition == nil)
        #expect(h.attributed.attribute(.characterStyleName, at: 4, effectiveRange: nil) as? String == "Corsivo speciale")
        #expect(h.attributed.attribute(.characterStyleName, at: 8, effectiveRange: nil) as? String == "Corsivo speciale")
        #expect(h.attributed.attribute(.characterStyleName, at: 9, effectiveRange: nil) as? String == nil)
        #expect(h.editor.styleMonitor.additions == ["char. underline"], "il corsivo è dello stile, il sottolineato resta manuale")
        #expect(h.editor.currentDocument().styles.style(named: "Body") == original, "lo stile di partenza non cambia")
        let elsewhere = try #require(h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)
        #expect(TextStyling.traits(ofFace: elsewhere.fontName)?.italic == false, "il resto del documento non cambia")
        #expect(h.undoActionName == "New Style “Corsivo speciale”")
        h.undo()
        #expect(h.editor.currentDocument().styles.style(named: "Corsivo speciale") == nil)
        #expect(h.attributed.attribute(.characterStyleName, at: 4, effectiveRange: nil) as? String == nil)
        #expect(h.editor.styleMonitor.additions == ["char. italic", "char. underline"])
    }

    @Test("M4 · Nel margine sinistro il clic seleziona la riga con l'a capo; il trascinamento unisce più righe")
    func lineSelectionFromMargin() throws {
        let h = EditorHarness(paragraphs: ["Prima riga", "Seconda riga", "Terza riga"])
        defer { h.close() }
        let view = h.editor.pagesViewForTests
        let layout = try #require(h.editor.currentLayout())
        let lines = layout.pages[0].lines
        let page = try #require(view.frameOfPage(0))
        #expect(lines.count == 3)
        func point(_ line: Int, inText: Bool = false) -> NSPoint {
            let x = inText ? lines[line].origin.x + 3 : 5
            return NSPoint(x: page.minX + x * view.scale, y: page.maxY - lines[line].origin.y * view.scale)
        }
        #expect(view.lineSelectionRange(at: point(0)) == lines[0].range)
        #expect(lines[0].range.length == 11, "dieci caratteri e l'a capo")
        #expect(view.lineSelectionRange(at: point(0, inText: true)) == nil, "nel testo resta il comportamento normale")

        let window = try #require(h.editor.window)
        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, point(0)))
        #expect(h.selection == lines[0].range)
        view.mouseDragged(with: event(.leftMouseDragged, point(2, inText: true)))
        #expect(h.selection == NSUnionRange(lines[0].range, lines[2].range))
        view.mouseUp(with: event(.leftMouseUp, point(2, inText: true)))
        view.mouseDown(with: event(.leftMouseDown, point(1)))
        #expect(h.selection == lines[1].range, "finito il trascinamento si riparte da una riga sola")
        view.mouseUp(with: event(.leftMouseUp, point(1)))
    }

    @Test("F1 · Cerca e sostituisci: conto, frecce che ricominciano, Sostituisci, Sostituisci tutto in un passo, opzioni, modello non valido")
    func findAndReplace() throws {
        let h = EditorHarness(paragraphs: ["Il lago di Como e il lago.", "Altro lago."])
        defer { h.close() }
        let bar = h.editor.findBarForTests
        func search(_ query: String) {
            bar.searchField.stringValue = query
            bar.onChange?()
            h.step()
        }
        h.select(0)
        h.editor.showFindBar(nil)
        h.step()
        #expect(h.editor.isFindBarVisible)
        search("lago")
        #expect(h.editor.searchMatches.count == 3)
        #expect(h.selection == NSRange(location: 3, length: 4), "mentre si scrive, la prima occorrenza dal cursore")
        #expect(bar.countLabel.stringValue == "1 of 3")
        h.editor.findNext(nil)
        h.editor.findNext(nil)
        #expect(bar.countLabel.stringValue == "3 of 3")
        h.editor.findNext(nil)
        #expect(bar.countLabel.stringValue == "1 of 3", "dall'ultima si ricomincia dalla prima")
        h.editor.findPrevious(nil)
        #expect(bar.countLabel.stringValue == "3 of 3")

        // Sostituisci: l'occorrenza scelta, poi la successiva.
        h.editor.findNext(nil)
        bar.replaceField.stringValue = "mare"
        bar.onReplace?()
        h.step()
        #expect(h.text.hasPrefix("Il mare di Como e il lago."))
        #expect(bar.countLabel.stringValue == "1 of 2")

        // Sostituisci tutto: un passo solo di Annulla.
        bar.onReplaceAll?()
        h.step()
        #expect(!h.text.contains("lago") && h.text.contains("Altro mare."))
        #expect(bar.countLabel.stringValue == "2 replaced")
        h.undo()
        #expect(h.text.components(separatedBy: "lago").count - 1 == 2)

        // Maiuscole e minuscole.
        search("il")
        #expect(h.editor.searchMatches.count == 2)
        bar.setOption(0, true)
        h.step()
        #expect(h.editor.searchMatches.count == 1)
        bar.setOption(0, false)

        // Un modello non valido lo dice, e non trova nulla.
        bar.setOption(2, true)
        search("(")
        #expect(bar.countLabel.stringValue == "Invalid pattern" && h.editor.searchMatches.isEmpty)
        search("l(a)go")
        bar.replaceField.stringValue = "$1"
        bar.onReplaceAll?()
        h.step()
        #expect(h.text.contains("Altro a."), "nel modello $1 è il gruppo")
        h.undo()
        bar.setOption(2, false)

        // Esc chiude e toglie le evidenziazioni.
        bar.onClose?()
        h.step()
        #expect(!h.editor.isFindBarVisible && h.editor.searchMatches.isEmpty)
    }

    @Test("S1 · La stampa ha le pagine del PDF, sul formato del foglio del documento, senza margini aggiunti")
    func printing() throws {
        let h = EditorHarness(paragraphs: Array(repeating: String(repeating: "Parole per riempire più pagine. ", count: 40), count: 12))
        defer { h.close() }
        let operation = try h.document.printOperation(withSettings: [:])
        let setup = h.editor.currentDocument().pageSetup
        // Il sistema porta il foglio al formato di carta più vicino della stampante (l'A4 a 595,2 × 841,68).
        #expect(abs(operation.printInfo.paperSize.width - setup.paperSize.width) < 1 && abs(operation.printInfo.paperSize.height - setup.paperSize.height) < 1)
        #expect(operation.printInfo.topMargin == 0 && operation.printInfo.leftMargin == 0)
        #expect(operation.jobTitle == h.document.displayName)
        let view = try #require(operation.view)
        var range = NSRange(location: 0, length: 0)
        #expect(view.knowsPageRange(&range))
        let pdf = h.editor.printablePDF(title: nil).data
        let pages = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)).numberOfPages
        #expect(pages > 1)
        #expect(range.length == pages, "le stesse pagine del PDF esportato")
    }

    @Test("B1 · Barra di stato: i conteggi completi (documento e selezione); il menu dello stile porta le aggiunte nello stile")
    func statusBarCountsAndStyleMenu() throws {
        let h = EditorHarness(paragraphs: ["Una prova di testo.", "Altro."])
        defer { h.close() }
        func row(_ section: Int, _ name: String) -> String? {
            let sections = h.editor.countSections()
            guard sections.indices.contains(section) else { return nil }
            return sections[section].rows.first { $0.0 == name }?.1
        }
        h.select(0)
        #expect(h.editor.countSections().count == 1, "senza selezione, solo il documento")
        #expect(row(0, "Words") == "5" && row(0, "Characters") == "25" && row(0, "Paragraphs") == "2")
        #expect(row(0, "Characters without spaces") == "22")
        h.editor.updateCounts()
        #expect(h.editor.countsText.contains("25 chars"), "la barra e il riquadro dicono lo stesso")
        h.select(0, length: 9)
        #expect(h.editor.countSections().last?.title == "Selection")
        #expect(row(1, "Words") == "2" && row(1, "Characters") == "9")
        h.editor.showCounts(nil)
        h.step()

        // Il menu dello stile: «prova» in corsivo, il cursore dentro.
        h.select(4, length: 5)
        h.editor.toggleItalic(nil)
        h.step()
        h.select(6)
        let menu = h.editor.styleMonitorMenu()
        #expect(menu.items[0].title == "Remove All Additions" && menu.items[0].isEnabled)
        #expect(menu.items[1].title == "Move the Additions into the Style “Body”" && menu.items[1].isEnabled)
        menu.performActionForItem(at: 1)
        h.step()
        #expect(h.editor.styleMonitor.additions.isEmpty, "il corsivo ora è dello stile")
        let other = try #require(h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)
        #expect(TextStyling.traits(ofFace: other.fontName)?.italic == true, "e tutto il testo dello stile è in corsivo")
        h.undo()
        let back = try #require(h.attributed.attribute(.font, at: 21, effectiveRange: nil) as? NSFont)
        #expect(TextStyling.traits(ofFace: back.fontName)?.italic == false, "un passo di Annulla")
    }

    @Test("D1 · Le schede del pannello: le modifiche passano al documento dopo una pausa, in un passo; Annulla ricarica la scheda")
    func definitionTabs() throws {
        let h = EditorHarness(paragraphs: ["Uno.", "Due."])
        defer { h.close() }
        h.editor.setInterfaceMode(.simple)
        h.editor.editLists(nil)
        h.step()
        #expect(h.editor.interfaceMode == .advanced, "dall'interfaccia semplice si passa all'avanzata")
        let panel = h.editor.definitionsPanel!
        #expect(panel.tab == .lists)
        let lists = try #require(panel.lists)
        let before = h.editor.currentDocument().lists
        let index = try #require(lists.rows.firstIndex { $0.definition.name == "Examples" })
        lists.rows[index].definition.prefix = "["
        lists.rows[index].definition.suffix = "]"
        #expect(h.editor.currentDocument().lists.first { $0.name == "Examples" }?.prefix == "[", "al salvataggio ciò che è in attesa va nel documento")
        // Una seconda modifica, applicata dalla pausa.
        lists.rows[index].definition.name = "Esempi numerati"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: DefinitionsPanel.pause + 0.3))
        #expect(h.editor.listNames.contains("Esempi numerati"), "applicata dalla pausa, senza bisogno di salvare")
        #expect(panel.lists?.rows[index].original == "Esempi numerati", "la scheda prende come base ciò che ha applicato")
        h.undo()
        h.undo()
        #expect(h.editor.currentDocument().lists == before)
        #expect(panel.lists?.rows.contains { $0.definition.name == "Examples" && $0.definition.prefix != "[" } == true, "Annulla ricarica la scheda")

        // Regole: uno stile predefinito usato da una regola entra una volta sola, anche applicando più volte.
        h.editor.editRules(nil)
        h.step()
        let rules = try #require(panel.rules)
        rules.add()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: DefinitionsPanel.pause + 0.3))
        let styleName = h.editor.rules.first?.styleName ?? ""
        #expect(h.editor.rules.count == 1 && !styleName.isEmpty)
        try #require(panel.rules).rows[0].isEnabled = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: DefinitionsPanel.pause + 0.3))
        #expect(h.editor.rules.first?.isEnabled == false)
        #expect(h.editor.styleSheet.styles.filter { $0.name == styleName }.count == 1, "lo stile non si duplica")
    }

    @Test("S2 · La scheda Stili: un valore nello stile cambia il testo; rinominare, togliere, nuovo, basato su; tutto annullabile")
    func stylesTab() throws {
        let h = EditorHarness(paragraphs: ["Uno.", "Due."])
        defer { h.close() }
        func size(at index: Int) -> CGFloat { (h.attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 }
        func paragraphStyle(at index: Int) -> String? { h.attributed.attribute(.paragraphStyleName, at: index, effectiveRange: nil) as? String }
        h.editor.showDefinitions(.styles)
        h.step()
        let tab = h.editor.stylesTab
        #expect(h.editor.definitionsPanel.tab == .styles)
        #expect(tab.selection == "Body", "si parte dal primo stile di paragrafo")
        #expect(tab.inspector.values.contains { $0.property == .size })
        let before = size(at: 0)

        func pause() { RunLoop.main.run(until: Date(timeIntervalSinceNow: EditorWindowController.stylePause + 0.2)) }
        // Un valore fissato nello stile: il modulo lo mostra subito, il testo cambia dopo la pausa; Annulla lo riporta.
        tab.inspector.change(.size) { $0.size = 20 }
        h.step()
        #expect(tab.inspector.values.first { $0.property == .size }?.value.size == 20, "il modulo mostra subito il valore nuovo")
        #expect(tab.inspector.values.first { $0.property == .size }?.source == .own)
        pause()
        #expect(size(at: 0) == 20 && size(at: 5) == 20)
        h.undo()
        #expect(size(at: 0) == before)

        // Più modifiche di seguito (come trascinando nel pannello dei colori): una composizione, un passo di Annulla.
        for value in [14.0, 15.0, 16.0] {
            tab.inspector.change(.size) { $0.size = value }
            h.step()
        }
        pause()
        #expect(size(at: 0) == 16)
        h.undo()
        #expect(size(at: 0) == before, "le tre modifiche sono un passo solo")

        // Annulla dal menu mentre una modifica aspetta: la modifica entra e Annulla toglie proprio lei.
        tab.inspector.change(.size) { $0.size = 18 }
        h.step()
        h.menu(#selector(PagesView.undo(_:)))
        pause()
        #expect(size(at: 0) == before)
        #expect(h.editor.styleSheet.style(named: "Body")?.values.size != 18)

        // Rinominare: il testo segue il nome nuovo.
        h.select(5)
        h.editor.applyNamedStyle(.paragraph, name: "Quotation")
        h.step()
        tab.selection = "Quotation"
        tab.nameDraft = "Citazione lunga"
        tab.commitName()
        h.step()
        #expect(paragraphStyle(at: 5) == "Citazione lunga" && h.editor.styleSheet.style(named: "Quotation") == nil)
        #expect(tab.selection == "Citazione lunga")

        // Togliere: il testo passa allo stile su cui si basava.
        tab.onRemove?("Citazione lunga")
        h.step()
        #expect(paragraphStyle(at: 5) == "Body" && h.editor.styleSheet.style(named: "Citazione lunga") == nil)
        h.undo()
        #expect(paragraphStyle(at: 5) == "Citazione lunga" && h.editor.styleSheet.style(named: "Citazione lunga") != nil, "un passo solo")

        // Nuovo: basato su quello scelto; basato su: niente giri.
        tab.selection = "Body"
        tab.onNew?(.paragraph)
        h.step()
        let created = try #require(tab.selection)
        #expect(h.editor.styleSheet.style(named: created)?.basedOn == "Body")
        tab.onParent?("Testo", created)
        h.step()
        #expect(h.editor.styleSheet.style(named: "Body")?.basedOn == nil, "Testo non può basarsi su chi si basa su di lui")
    }

    @Test("T1 · L'albero degli oggetti: i titoli fanno da rami; un clic porta il cursore; l'albero segue il cursore; si nasconde")
    func objectTree() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["Capitolo primo", "Il primo paragrafo.", "Capitolo secondo", "Ultimo paragrafo."])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        for start in [0, 35] {
            h.select(start)
            h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
            h.step()
        }
        h.editor.refreshObjectTree()
        #expect(h.editor.isObjectTreeVisible)
        // Larga come nel disegno, accanto alla pagina e al pannello.
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1180, height: 900))
        h.editor.setInterfaceMode(.simple)
        h.editor.setInterfaceMode(.advanced)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let split = try #require(h.editor.inspectorPanel.superview as? NSSplitView)
        #expect(Int(split.arrangedSubviews[0].frame.width) == 232, "albero largo 232 punti: \(split.arrangedSubviews.map { Int($0.frame.width) })")
        #expect(split.arrangedSubviews[2].frame.width >= InspectorView.minimumWidth)
        let tree = h.editor.objectTree
        #expect(tree.items.map(\.title) == ["Capitolo primo", "Capitolo secondo"])
        let paragraph = try #require(tree.items.last?.children?.first)
        #expect(paragraph.title == "Ultimo paragrafo." && paragraph.label == "¶")

        // Un clic: il cursore va all'inizio del paragrafo, l'ispettore mostra il paragrafo (anche dalla scheda Regole).
        h.editor.inspect(.character)
        h.editor.definitionsPanel.show(.rules)
        tree.choose(paragraph)
        h.step()
        #expect(h.selection == NSRange(location: paragraph.range.location, length: 0))
        #expect(tree.selection == paragraph.id)
        #expect(h.editor.inspectedObject == .paragraph)
        #expect(h.editor.definitionsPanel.tab == .inspector)

        // Il cursore altrove: l'albero evidenzia il suo oggetto.
        h.select(17)
        #expect(tree.selection == tree.items.first?.children?.first?.id)

        // Vista › Albero degli oggetti lo nasconde (e lo rimette).
        h.editor.toggleObjectTree(nil)
        #expect(!h.editor.isObjectTreeVisible)
        h.editor.toggleObjectTree(nil)
        #expect(h.editor.isObjectTreeVisible)
    }

    @Test("T1b · Trascinare un capoverso nella mappa lo sposta nel testo; il cursore lo segue e Annulla ripristina")
    func objectTreeMovesParagraph() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["uno", "due", "tre"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        h.editor.refreshObjectTree()
        let tree = h.editor.objectTree
        let source = try #require(tree.items.first)
        let target = try #require(tree.items.last)

        tree.onMoveItem?(source, target, .after)
        h.step()
        #expect(h.text == "due\ntre\nuno")
        #expect(h.selection == NSRange(location: 8, length: 0))
        #expect(tree.items.map(\.title) == ["due", "tre", "uno"])
        #expect(h.undoActionName == "Move Paragraph")
        h.undo()
        #expect(h.text == "uno\ndue\ntre")
        h.redo()
        #expect(h.text == "due\ntre\nuno")
    }

    @Test("T1d · La mappa traduce ogni rilascio proposto dalla lista in uno spostamento possibile, o lo rifiuta")
    func objectTreeResolvesDrops() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <p>Premessa.</p>
        <section id="a" role="capitolo"><title><p>Alfa</p></title><p>Testo di Alfa.</p>
        <section id="aa" role="sezione"><title><p>Alfa uno</p></title><p>Testo di Alfa uno.</p></section></section>
        <section id="b" role="capitolo"><title><p>Beta</p></title><p>Testo di Beta.</p><p>Secondo di Beta.</p></section>
        <section id="d" role="capitolo"><title><p>Delta</p></title></section>
        </document>
        """))
        h.editor.refreshObjectTree()
        let tree = h.editor.objectTree
        func id(_ title: String) throws -> OutlineItem.ID {
            func find(_ list: [OutlineItem]) -> OutlineItem? {
                for item in list {
                    if item.title == title { return item }
                    if let found = item.children.flatMap(find) { return found }
                }
                return nil
            }
            return try #require(find(tree.items)).id
        }
        func between(_ source: String, _ parent: String?, _ index: Int) throws -> String {
            guard let drop = tree.dropBetween(source: try id(source), parent: try parent.map(id), index: index) else { return "no" }
            return "\(drop.target.title) \(drop.placement) @\(drop.index.map(String.init) ?? "su")"
        }

        // Un titolo: fra le sezioni; proposto in mezzo al testo, la linea va dove la sezione può stare.
        #expect(try between("Alfa", "Beta", 2) == "Beta inside @2", "in fondo a Beta: ultima sezione interna")
        #expect(try between("Alfa", "Beta", 1) == "Secondo di Beta. before @1", "fra i capoversi di Beta: «Secondo» resta a Beta")
        #expect(try between("Alfa", nil, 3) == "Delta before @3")
        #expect(try between("Alfa uno", nil, 4) == "Delta after @4", "a sinistra, in fondo: torna capitolo")
        #expect(try between("Alfa uno", nil, 0) == "Premessa. before @0", "prima della Premessa, che resta fuori dai capitoli")
        #expect(try between("Alfa", "Alfa uno", 0) == "no", "non dentro sé stessa")
        #expect(try between("Alfa", nil, 1) == "no" && between("Alfa", nil, 2) == "no", "dov'è già: niente")
        #expect(tree.dropOnto(source: try id("Alfa"), item: try id("Beta"))?.placement == .inside)
        #expect(tree.dropOnto(source: try id("Alfa"), item: try id("Testo di Beta.")) == nil)

        // Un capoverso: fra il testo, prima delle sezioni interne; dopo il titolo, primo della sezione.
        #expect(try between("Premessa.", "Beta", 1) == "Secondo di Beta. before @1")
        #expect(try between("Premessa.", "Beta", 2) == "Secondo di Beta. after @2")
        #expect(try between("Premessa.", "Alfa", 2) == "Alfa uno afterSection @2", "dopo la sezione interna: torna ad Alfa")
        #expect(try between("Testo di Beta.", nil, 0) == "Premessa. before @0")
        #expect(try between("Testo di Beta.", nil, 2) == "Alfa afterSection @2", "fra due capitoli: fuori da ogni capitolo")
        #expect(try between("Testo di Beta.", "Delta", 0) == "Delta after @0", "nella sezione vuota, dopo il titolo")
        #expect(tree.dropOnto(source: try id("Premessa."), item: try id("Beta")) == nil)

        // Il capoverso entra davvero nella sezione vuota.
        let source = try #require(tree.item(try id("Testo di Beta.")))
        let drop = try #require(tree.dropBetween(source: source.id, parent: try id("Delta"), index: 0))
        tree.onMoveItem?(source, drop.target, drop.placement)
        h.step()
        #expect(tree.items.last?.title == "Delta")
        #expect(tree.items.last?.children?.map(\.title) == ["Testo di Beta."])
        #expect(h.undoActionName == "Move Paragraph")

        // Con il filtro non si trascina.
        tree.filter = "Beta"
        #expect(!tree.canDrag(try id("Beta")))
        #expect(tree.dropBetween(source: try id("Alfa"), parent: nil, index: 3) == nil)
    }

    @Test("T1c · Trascinare una sezione sposta tutto il ramo")
    func objectTreeMovesSection() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <section id="a" role="capitolo"><title><p>Alfa</p></title><p>Testo di Alfa.</p>
        <section id="aa" role="sezione"><title><p>Alfa interna</p></title></section></section>
        <section id="b" role="capitolo"><title><p>Beta</p></title><p>Testo di Beta.</p></section>
        </document>
        """))
        h.editor.refreshObjectTree()
        let tree = h.editor.objectTree
        var source = try #require(tree.items.first)
        var target = try #require(tree.items.last)
        let descendant = try #require(source.children?.last)
        #expect(tree.dropOnto(source: source.id, item: descendant.id) == nil, "una sezione non entra in sé stessa")
        #expect(tree.dropBetween(source: source.id, parent: descendant.id, index: 0) == nil)

        tree.onMoveItem?(source, target, .after)
        h.step()
        #expect(h.text == "Beta\nTesto di Beta.\nAlfa\nTesto di Alfa.\nAlfa interna")
        #expect(h.undoActionName == "Move Section")
        h.undo()
        h.editor.refreshObjectTree()
        source = try #require(tree.items.first)
        target = try #require(tree.items.last)
        tree.onMoveItem?(source, target, .inside)
        h.step()
        #expect(tree.items.map(\.title) == ["Beta"])
        #expect(tree.items.first?.children?.map(\.title) == ["Testo di Beta.", "Alfa"])
        let titles = SectionEditing.titles(in: h.editor.store)
        #expect(titles.map(\.depth) == [1, 2, 3])
        #expect(titles.map { h.attributed.attribute(.paragraphStyleName, at: $0.range.location, effectiveRange: nil) as? String }
                == [nil, "Heading 2", "Heading 3"], "Beta non cambia livello; Alfa e la sua interna scendono di uno")
        #expect(titles.map { (h.attributed.attribute(.outlineLevel, at: $0.range.location, effectiveRange: nil) as? NSNumber)?.intValue }
                == [1, 2, 3])
        let movedDocument = h.editor.currentDocument()
        #expect(movedDocument.styles.style(named: "Heading 3")?.values.outlineLevel == 3)
        #expect(movedDocument.flatParagraphs.map(\.paragraph.style.outlineLevel) == [nil, nil, 2, nil, 3],
                "nel modello un titolo porta il livello del suo stile; quello vero è la profondità")
        #expect(try DocumentFormat.document(from: DocumentFormat.data(for: movedDocument)) == movedDocument)
        h.undo()
        h.editor.refreshObjectTree()
        #expect(tree.items.map(\.title) == ["Alfa", "Beta"])
        #expect(h.editor.currentDocument().styles.style(named: "Heading 3") == nil, "Annulla toglie anche lo stile creato")
        h.redo()
        #expect(h.editor.currentDocument().styles.style(named: "Heading 3")?.values.outlineLevel == 3, "Ripeti lo ripristina")
    }

    @Test("I campi di misura dell'ispettore convertono le unità; i rientri possono essere negativi")
    func inspectorLengthFieldsConvertUnits() throws {
        let centimetre = CGFloat(720 / 25.4)
        let converted = try #require(LengthField.validatedPoints(from: "1cm", defaultUnit: .points, allowsNegative: true))
        #expect(abs(converted - centimetre) < 0.0001)
        #expect(LengthField.validatedPoints(from: "12", defaultUnit: .points) == 12, "senza unità il campo del rientro continua a usare i punti")
        #expect(LengthField.validatedPoints(from: "", defaultUnit: .points) == 0, "un campo vuoto vale zero")
        #expect(LengthField.validatedPoints(from: "   ", defaultUnit: .points) == 0, "anche un campo con soli spazi")
        #expect(LengthField.validatedPoints(from: "−0,5 cm", defaultUnit: .points, allowsNegative: true) == -centimetre / 2)
        #expect(LengthField.validatedPoints(from: "−1 cm", defaultUnit: .points) == nil, "gli spazi prima e dopo non diventano negativi")

        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        h.editor.inspectorForTests.change(.firstLineIndent) { $0.firstLineIndent = converted }
        h.step()
        let style = try #require(h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(style.firstLineHeadIndent - centimetre) < 0.0001, "1 cm arriva al rientro della prima riga come 28,35 pt")
    }

    @Test("Nell'ispettore Tab e Maiusc-Tab percorrono i campi e applicano il valore lasciato")
    func inspectorTabNavigation() throws {
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        h.editor.inspect(.paragraph)
        h.step()

        func host(in view: NSView) -> InspectorHostingView? {
            if let host = view as? InspectorHostingView { return host }
            for child in view.subviews { if let found = host(in: child) { return found } }
            return nil
        }
        let inspectorHost = try #require(host(in: h.editor.inspectorPanel))
        inspectorHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        func fieldsInVisualOrder() -> [NSTextField] {
            var fields: [NSTextField] = []
            func collect(_ view: NSView) {
                if let field = view as? NSTextField, field.isEditable, field.isEnabled, !field.isHiddenOrHasHiddenAncestor {
                    fields.append(field)
                }
                for child in view.subviews { collect(child) }
            }
            collect(inspectorHost)
            return fields.sorted { left, right in
                let a = left.convert(left.bounds, to: inspectorHost), b = right.convert(right.bounds, to: inspectorHost)
                if abs(a.midY - b.midY) > 6 { return a.midY > b.midY }
                return a.minX < b.minX
            }
        }
        let ordered = fieldsInVisualOrder()
        #expect(ordered.count > 2)

        let window = try #require(h.editor.window)
        #expect(window.makeFirstResponder(ordered[0]))
        ordered[0].selectText(nil)
        let fieldEditor = try #require(ordered[0].currentEditor() as? NSTextView)
        fieldEditor.insertText("1cm", replacementRange: NSRange(location: 0, length: (fieldEditor.string as NSString).length))
        func pressTab(shift: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: shift ? "\u{19}" : "\t",
                charactersIgnoringModifiers: shift ? "\u{19}" : "\t", isARepeat: false, keyCode: 48))
            NSApp.sendEvent(event)
        }
        func focusedField() -> NSTextField? {
            window.firstResponder as? NSTextField ?? (window.firstResponder as? NSTextView)?.delegate as? NSTextField
        }
        try pressTab()
        #expect(ordered.firstIndex { $0 === focusedField() } == 1, "Tab sposta davvero il focus")
        h.step()
        let leftIndent = try #require(h.editor.inspectorForTests.values.first { $0.property == .leftIndent }?.value.leftIndent)
        #expect(abs(leftIndent - 720 / 25.4) < 0.001, "lasciare il campo con Tab applica anche la conversione")
        try pressTab(shift: true)
        #expect(ordered.firstIndex { $0 === focusedField() } == 0, "Maiusc-Tab torna al campo precedente")

        // Cambiando oggetto cambiano i campi: la navigazione usa quelli nuovi, non una catena rimasta vecchia.
        h.editor.inspect(.page)
        h.step()
        inspectorHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let pageFields = fieldsInVisualOrder()
        #expect(pageFields.count > 2)
        window.makeFirstResponder(pageFields[0])
        try pressTab()
        #expect(pageFields.firstIndex { $0 === focusedField() } == 1, "Tab funziona anche dopo aver cambiato oggetto")
    }

    // MARK: Stili e regole dall'ispettore (tappa I.8)

    @Test("R1 · Dall'ispettore nasce una regola; ciò che dà si dice «dalla regola»; cambiarlo lì vale solo lì")
    func ruleFromInspector() throws {
        let h = EditorHarness(paragraphs: ["Roma, città aperta.", "Napoli, città bella."])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests
        h.select(0, length: 4)
        h.editor.inspect(.character)
        inspector.change(.size) { $0.size = 18 }
        h.step()

        // «Roma» è la prima parola: la regola la cerca nei paragrafi «Testo», con uno stile nuovo che ha il corpo 18.
        h.editor.styleNameAnswerForTests = "Prime parole"
        h.editor.createRuleFromInspector()
        h.step()
        #expect(h.editor.rules == [TextRule(target: .firstWords(1), paragraphStyle: "Body", styleName: "Prime parole")])
        let style = try #require(h.editor.styleSheet.style(named: "Prime parole"))
        #expect(style.target == .character && style.formulas.contains { $0.operation == StylePropertyOperation(.set, .size, .length(18, .points)) })
        #expect((h.attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize != 18,
                "il corpo dato a mano se ne va: ora lo dà la regola")
        #expect(h.editor.definitionsPanel.rules?.selectedIndex == 0, "si apre la scheda Regole, con la regola nuova scelta")

        // Nell'altro paragrafo il corpo viene dalla regola.
        h.editor.definitionsPanel.show(.inspector)
        h.select(20, length: 2)
        h.editor.inspect(.character)
        let size = try #require(inspector.values.first { $0.property == .size })
        #expect(size.source == .rule(h.editor.rules[0].summary) && size.value.size == 18)
        #expect(inspector.sourceText(size).hasPrefix("From the rule"))

        // Cambiato lì, anche al valore dello stile, vale solo lì: vince sulla regola.
        let inherited = try #require(size.inherited.size)
        inspector.change(.size) { $0.size = inherited }
        h.step()
        #expect(TextStyling.ruleExceptions(in: h.attributed, at: 20) == [.size])
        #expect(inspector.values.first { $0.property == .size }?.source == .own)
        #expect(inspector.values.first { $0.property == .size }?.value.size == inherited)

        // Annullando: prima l'eccezione, poi la regola con il suo stile, e «Roma» riprende il suo corpo.
        h.undo()
        #expect(TextStyling.ruleExceptions(in: h.attributed, at: 20).isEmpty)
        h.undo()
        #expect(h.editor.rules.isEmpty && h.editor.styleSheet.style(named: "Prime parole") == nil)
        #expect((h.attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize == 18)
    }

    @Test("R2 · «Crea uno stile da qui…» crea uno stile della specie dell'oggetto scelto e glielo dà")
    func styleFromInspector() throws {
        let h = EditorHarness(paragraphs: ["Roma, città aperta."])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests
        h.select(6, length: 5)
        h.editor.inspect(.word)
        inspector.change(.language) { $0.language = "la" }
        h.step()
        h.editor.styleNameAnswerForTests = "Parola latina"
        inspector.createStyle?()
        h.step()
        let style = try #require(h.editor.styleSheet.style(named: "Parola latina"))
        #expect(style.target == .word && style.formulas.contains { $0.operation == StylePropertyOperation(.set, .language, .language("la")) })
        #expect(h.attributed.attribute(.wordStyleName, at: 7, effectiveRange: nil) as? String == "Parola latina")
        #expect(inspector.styleName == "Parola latina")
    }

    @Test("R3 · Vista › Segni della provenienza: si accendono per la finestra, solo nell'avanzata, e seguono le modifiche")
    func provenanceMarks() throws {
        let saved = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = saved }
        let h = EditorHarness(paragraphs: ["Roma, città aperta.", "Napoli, città bella."])
        defer { h.close() }
        h.editor.changeRules([TextRule(target: .firstWords(1), paragraphStyle: "Body", styleName: "Emphasis")], styles: h.editor.styleSheet)
        h.step()
        #expect(h.editor.provenanceMarks.rules.isEmpty, "spenti all'inizio")
        h.editor.setInterfaceMode(.simple)
        h.editor.toggleProvenanceMarks(nil)
        h.step()
        #expect(h.editor.interfaceMode == .advanced, "accenderli porta all'avanzata")
        #expect(h.editor.provenanceMarks.rules == [NSRange(location: 0, length: 5), NSRange(location: 20, length: 7)])
        #expect(h.editor.provenanceMarks.manual.isEmpty)
        #expect((h.editor.bandControls["provenienza"] as? NSButton)?.state == .on)

        // Un grassetto dato a mano: un segno arancio, subito.
        h.select(6, length: 5)
        h.editor.toggleBold(nil)
        h.step()
        #expect(h.editor.provenanceMarks.manual.isEmpty, "dopo una pausa, non a ogni tasto")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        #expect(h.editor.provenanceMarks.manual == [NSRange(location: 6, length: 5)])

        // Nell'interfaccia semplice non si vedono; tornando all'avanzata, sì.
        h.editor.setInterfaceMode(.simple)
        #expect(h.editor.provenanceMarks.manual.isEmpty && h.editor.provenanceMarks.rules.isEmpty)
        h.editor.setInterfaceMode(.advanced)
        #expect(h.editor.provenanceMarks.manual == [NSRange(location: 6, length: 5)])
        h.editor.toggleProvenanceMarks(nil)
        #expect(h.editor.provenanceMarks.manual.isEmpty && h.editor.provenanceMarks.rules.isEmpty)
    }

    @Test("K1 · Cancella dopo «मे»: prima la vocale, poi la consonante; con Graphite come con Core Text")
    func indicBackspace() throws {
        for graphite in [false, true] {
            let h = EditorHarness(paragraphs: ["सत्यमेव"])
            defer { h.close() }
            h.select(0, length: 7)
            h.editor.inspect(.character)
            h.editor.inspectorForTests.change(.family) { $0.family = "Annapurna SIL" }
            if graphite { h.editor.inspectorForTests.change(.shaping) { $0.graphite = "on" } }
            h.step()
            h.select(6)
            h.press(#selector(NSResponder.deleteBackward(_:)))
            #expect(h.text.hasPrefix("सत्यमव"), "via la vocale «े»")
            #expect(h.selection == NSRange(location: 5, length: 0))
            h.press(#selector(NSResponder.deleteBackward(_:)))
            #expect(h.text.hasPrefix("सत्यव"), "poi la consonante")
            // Le cancellazioni di seguito sono un passo solo di Annulla, come le lettere scritte di seguito.
            h.undo()
            #expect(h.text.hasPrefix("सत्यमेव"))
        }
    }

    // MARK: La pagina (tappa P.2)

    @Test("F4 · Ispettore › Pagina: formato, margini, pagine affacciate; la composizione segue, Annulla torna indietro")
    func pageSetupFromInspector() throws {
        let h = EditorHarness(paragraphs: [String(repeating: "Una riga di prova che si ripete. ", count: 300)])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests
        h.editor.inspect(.page)
        #expect(inspector.pageSetup == h.editor.currentDocument().pageSetup)
        #expect(PageSetupForm.format(of: inspector.pageSetup.paperSize) == "A4")
        var setup = inspector.pageSetup
        setup.paperSize = CGSize(width: PageSetup.points(fromMillimetres: 148), height: PageSetup.points(fromMillimetres: 210))
        setup.left = try #require(Length.points(from: "2 cm"))
        setup.right = try #require(Length.points(from: "1 in"))
        setup.facing = true
        #expect(PageSetupForm.isValid(setup))
        inspector.setPageSetup?(setup)
        h.step()
        let layout = try #require(h.editor.currentLayout())
        #expect(layout.setup == setup && PageSetupForm.format(of: setup.paperSize) == "A5")
        #expect(layout.pages.count >= 2)
        #expect(abs(layout.pages[1].lines[0].origin.x - 72) < 0.5, "pagina 2: lo specchio comincia dopo il margine esterno di un pollice")
        #expect(DocumentFormat.string(for: h.editor.currentDocument()).contains("facing=\"on\""))
        h.undo()
        #expect(h.editor.currentDocument().pageSetup == PageSetup.a4 && inspector.pageSetup == PageSetup.a4, "Annulla torna all'A4, anche nell'ispettore")
        // Margini che non lasciano spazio al testo non si accettano.
        var crowded = setup
        crowded.left = PageSetup.points(fromMillimetres: 80)
        crowded.right = PageSetup.points(fromMillimetres: 80)
        #expect(!PageSetupForm.isValid(crowded))
    }

    // MARK: Graphite (tappa G.4)

    @Test("G4 · Ispettore › Composizione: Graphite sul testo scelto, nel file; su un font senza tabelle, un avviso")
    func graphiteChoice() throws {
        let h = EditorHarness(paragraphs: ["Prova မြန်မာ fine."])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests
        let burmese = (h.text as NSString).range(of: "မြန်မာ")
        h.select(burmese.location, length: burmese.length)
        h.editor.inspect(.character)
        inspector.change(.family) { $0.family = "Padauk" }
        h.step()
        #expect(inspector.values.first { $0.property == .shaping }?.value.graphite == "off", "si parte da Core Text")
        #expect(inspector.fontHasGraphite)
        inspector.change(.shaping) { $0.graphite = "on" }
        h.step()
        #expect(h.attributed.attribute(.graphite, at: burmese.location, effectiveRange: nil) as? String == "")
        #expect(h.attributed.attribute(.graphite, at: 0, effectiveRange: nil) == nil, "solo il testo scelto")
        let shaping = try #require(inspector.values.first { $0.property == .shaping })
        #expect(shaping.value.graphite == "on" && shaping.source == .own)
        #expect(inspector.graphiteProblem == nil)
        let layout = try #require(h.editor.currentLayout())
        #expect(layout.graphiteFallbacks == 0)
        let runs = layout.pages[0].lines.flatMap { CTLineGetGlyphRuns($0.line) as! [CTRun] }
        #expect(runs.contains { (CTRunGetAttributes($0) as NSDictionary)[NSAttributedString.Key.graphiteCluster] != nil }, "le righe hanno i gruppi di Graphite")
        #expect(DocumentFormat.string(for: h.editor.currentDocument()).contains("graphite=\"on\""))
        #expect(h.editor.styleMonitor.additions.contains("char. Graphite"), "il monitor degli stili lo segna come dato a mano")

        // Su «Prova», in Hoefler Text, Graphite non può comporre: avviso nell'ispettore e nella barra di stato.
        h.select(0, length: 5)
        h.editor.inspect(.character)
        inspector.change(.shaping) { $0.graphite = "on" }
        h.step()
        #expect(!inspector.fontHasGraphite && inspector.graphiteProblem?.contains("“Hoefler Text”") == true, "l'avviso nomina il font che c'è davvero")
        #expect(h.editor.currentLayout()?.graphiteFallbacks == 1)
        #expect(h.editor.warningTitles.contains { $0.contains("Graphite") })
        h.undo()
        #expect(h.editor.currentLayout()?.graphiteFallbacks == 0)
    }

    @Test("G6 · Scheda Stili: cambiato il font di uno stile, l'avviso su Graphite segue subito, senza aspettare la pausa")
    func graphiteInStylesTab() throws {
        let h = EditorHarness(paragraphs: nil)
        defer { h.close() }
        h.editor.showDefinitions(.styles)
        let tab = h.editor.stylesTab
        tab.selection = "Body"
        h.step()
        let form = tab.inspector
        form.change(.shaping) { $0.graphite = "on" }
        h.step()
        #expect(form.graphiteProblem != nil, "Testo è in Hoefler Text")
        form.change(.family) { $0.family = "Annapurna SIL" }
        h.step()
        #expect(form.fontHasGraphite && form.graphiteProblem == nil, "subito, durante la pausa prima di applicare")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        #expect(h.editor.currentLayout()?.graphiteFallbacks == 0)
    }

    @Test("G5 · Pannello delle funzioni › Funzioni Graphite: valgono con Graphite, vanno nel testo; il valore predefinito non si scrive")
    func graphiteFeatures() throws {
        let h = EditorHarness(paragraphs: ["Prova မြန်မာ fine."])
        defer { h.close() }
        let inspector = h.editor.inspectorForTests, panel = h.editor.featurePanelForTests
        let burmese = (h.text as NSString).range(of: "မြန်မာ")
        h.select(burmese.location, length: burmese.length)
        h.editor.inspect(.character)
        inspector.change(.family) { $0.family = "Padauk" }
        h.step()
        let lldt = try #require(panel.graphiteFeatures.first { $0.tag == "lldt" }, "le funzioni Graphite di Padauk")
        #expect(panel.graphiteSettings == nil, "con Core Text le funzioni Graphite non valgono")
        inspector.change(.shaping) { $0.graphite = "on" }
        h.step()
        #expect(panel.graphiteSettings == "")
        panel.setGraphiteValue(1, of: lldt)
        h.step()
        #expect(h.attributed.attribute(.graphite, at: burmese.location, effectiveRange: nil) as? String == "lldt=1")
        #expect(panel.graphiteValue(of: lldt) == 1)
        #expect(DocumentFormat.string(for: h.editor.currentDocument()).contains("graphite=\"lldt=1\""))
        panel.setGraphiteValue(lldt.defaultValue, of: lldt)
        h.step()
        #expect(h.attributed.attribute(.graphite, at: burmese.location, effectiveRange: nil) as? String == "", "resta Graphite, senza funzioni")
        // Sul testo in Hoefler Text il pannello non ha funzioni Graphite.
        h.select(0, length: 5)
        #expect(panel.graphiteFeatures.isEmpty)
    }

    // MARK: Menu ridotti (tappa I.10)

    @Test("M2 · I menu non ripetono ciò che ha un controllo; le misure dell'immagine con un doppio clic o il tasto destro")
    func reducedMenus() throws {
        let menu = MainMenu.build()
        func titles(_ menu: NSMenu) -> [String] { menu.items.flatMap { [$0.title] + ($0.submenu.map(titles) ?? []) } }
        let all = titles(menu)
        for gone in ["Lists…", "Float Styles…", "Rules…", "Image Size…", "Word Style", "Character Style", "Named List"] {
            #expect(!all.contains(gone), "«\(gone)» è uscito dai menu")
        }
        for kept in ["New Style from Selection…", "List On/Off", "Provenance Marks", "Footnote", "Document Language"] {
            #expect(all.contains(kept))
        }

        let h = EditorHarness(paragraphs: ["x"])
        defer { h.close() }
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        var document = h.editor.currentDocument()
        document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("ab ", style: EditorHarness.body)),
                                                         .image(ImageObject(source: .embedded(png), width: 30, height: 20)),
                                                         .text(TextRun(" cd", style: EditorHarness.body))]))]
        h.editor.replaceContent(document)
        h.step()
        // Doppio clic sulla metà destra dell'immagine (il punto più vicino è dopo di lei): l'immagine, e il foglio delle misure.
        h.editor.pagesMouseDown(at: 4, affinity: .downstream, clickCount: 2, extending: false)
        h.step()
        #expect(h.selection == NSRange(location: 3, length: 1))
        let sheet = try #require(h.editor.window?.attachedSheet, "si apre il foglio delle misure")
        h.editor.window?.endSheet(sheet)
        h.step()
        // Il tasto destro sull'immagine scelta offre le misure; su una parola no.
        #expect(h.editor.pagesContextMenu(at: 3)?.items.contains { $0.title == "Image Size…" } == true)
        h.select(0)
        #expect(h.editor.pagesContextMenu(at: 1)?.items.contains { $0.title == "Image Size…" } == false)
        // Un doppio clic su una parola non apre nulla.
        h.editor.pagesMouseDown(at: 1, affinity: .downstream, clickCount: 2, extending: false)
        h.step()
        #expect(h.editor.window?.attachedSheet == nil && h.selection == NSRange(location: 0, length: 2))
    }

    // MARK: Barra e comandi dalle definizioni (tappa I.4)

    @Test("G6 · La barra si personalizza (per tutte le finestre); i comandi nascono dalle definizioni del documento")
    func toolbarAndDefinitions() throws {
        let saved = UserDefaults.standard.stringArray(forKey: "ToolbarItems")
        defer { UserDefaults.standard.set(saved, forKey: "ToolbarItems") }
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        EditorWindowController.toolbarItems = ["salva", "|", "regole", "illustrazione"]
        h.step()
        #expect(h.editor.bandControls["salva"] != nil && h.editor.bandControls["regole"] != nil)
        #expect(h.editor.bandControls["nuovo"] == nil, "un comando tolto non c'è più")
        EditorWindowController.toolbarItems = EditorWindowController.defaultToolbar
        h.step()
        #expect(h.editor.bandControls["nuovo"] != nil && h.editor.bandControls["regole"] == nil)

        // Due stili di figura: due voci nel menu Illustrazione.
        var second = FloatStyle.defaultFigure
        second.name = "Tavola"
        h.editor.editFloatStylesForTests(h.editor.currentDocument().floatStyles + [.defaultFigure, second])
        let menu = try #require(h.editor.bandControls["illustrazione"]?.menu)
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(menu.items.map(\.title).contains("Figure…") && menu.items.map(\.title).contains("Tavola…"))

        // Gli stili di carattere come comandi del Ribbon.
        h.select(0, length: 3)
        let runStyles = try #require(h.editor.bandControls["stileCarattere"]?.menu)
        runStyles.delegate?.menuNeedsUpdate?(runStyles)
        let emphasis = try #require(runStyles.items.first { $0.title == "Emphasis" })
        NSApp.sendAction(try #require(emphasis.action), to: emphasis.target, from: emphasis)
        h.step()
        #expect(h.attributed.attribute(.characterStyleName, at: 1, effectiveRange: nil) as? String == "Emphasis")
    }

    @Test("G6b · Ogni livello ha i suoi gruppi; si spostano interi senza modificare il documento")
    func independentToolbarGroups() {
        let defaults = UserDefaults.standard
        let savedSimple = defaults.stringArray(forKey: "ToolbarItems.simple")
        let savedAdvanced = defaults.stringArray(forKey: "ToolbarItems")
        let savedMode = InterfaceMode.lastChoice
        defer {
            defaults.set(savedSimple, forKey: "ToolbarItems.simple")
            defaults.set(savedAdvanced, forKey: "ToolbarItems")
            InterfaceMode.lastChoice = savedMode
        }
        InterfaceMode.lastChoice = .simple
        EditorWindowController.setToolbarItems(EditorWindowController.defaultSimpleToolbar, for: .simple)
        EditorWindowController.setToolbarItems(["regole", "|", "salva"], for: .advanced)
        let h = EditorHarness(paragraphs: ["Il documento non cambia."])
        defer { h.close() }
        let before = h.text

        #expect(h.editor.toolbarGroupsForTests == [["salva"], ["annulla", "ripeti", "cerca"], ["nota", "illustrazione", "tabella"]])
        h.editor.setInterfaceMode(.advanced)
        h.step()
        #expect(h.editor.toolbarGroupsForTests == [["regole"], ["salva"]])
        h.editor.setInterfaceMode(.simple)
        h.step()
        h.editor.moveToolbarGroupForTests(from: 0, to: 2)
        h.step()
        #expect(h.editor.toolbarGroupsForTests == [["annulla", "ripeti", "cerca"], ["nota", "illustrazione", "tabella"], ["salva"]])
        #expect(h.text == before)
        h.editor.setInterfaceMode(.advanced)
        h.step()
        #expect(h.editor.toolbarGroupsForTests == [["regole"], ["salva"]], "il livello dettagliato non eredita lo spostamento")
    }

    @Test("G7 · Un pulsante che apre qualcosa non resta acceso dopo il clic; Grassetto sì, finché il testo è in grassetto")
    func momentaryButtonsStayOff() throws {
        let saved = UserDefaults.standard.stringArray(forKey: "ToolbarItems")
        defer { UserDefaults.standard.set(saved, forKey: "ToolbarItems") }
        EditorWindowController.toolbarItems = ["salva", "regole"]
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.orderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        func click(_ name: String) throws -> BandButton {
            let button = try #require(h.editor.bandControls[name] as? BandButton)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            return button
        }
        // Regole… apre la sua scheda nel pannello (dall'interfaccia semplice passa all'avanzata).
        let rules = try click("regole")
        #expect(h.editor.definitionsPanel.tab == .rules, "si apre la scheda Regole")
        #expect(rules.state == .off, "aperta la scheda, il pulsante non è acceso")
        h.select(0, length: 3)
        h.step()
        #expect(try click("grassetto").state == .on, "Grassetto si accende: il testo scelto ora è in grassetto")
        #expect(try click("grassetto").state == .off)
    }

    // MARK: Le sezioni (tappa S.2a)

    private func outline(_ sections: [Section], depth: Int = 1) -> [String] {
        sections.flatMap { ["\(depth) \($0.role) \($0.title.plainText)"] + outline($0.sections, depth: depth + 1) }
    }

    private func enabled(_ h: EditorHarness, _ action: Selector) -> Bool {
        h.editor.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }

    @Test("SZ4 · Inserisci › Sezione: titolo vuoto al cursore (il paragrafo si spezza), cursore nel titolo, un passo di Annulla")
    func insertSectionCommand() throws {
        let h = EditorHarness(paragraphs: ["Primo paragrafo.", "Secondo paragrafo."])
        defer { h.close() }
        #expect(enabled(h, #selector(EditorWindowController.insertSectionSameLevel(_:))))
        #expect(!enabled(h, #selector(EditorWindowController.insertSectionInside(_:))) && !enabled(h, #selector(EditorWindowController.removeEnclosingSection(_:))),
                "senza sezioni non c'è un «dentro» né una sezione da togliere")
        h.select(5)
        h.editor.insertSectionSameLevel(nil)
        h.step()
        #expect(h.text == "Primo\n\n paragrafo.\nSecondo paragrafo." && h.selection == NSRange(location: 6, length: 0))
        #expect(h.undoActionName == "Section")
        h.type("Capitolo uno")
        let document = h.editor.currentDocument()
        #expect(outline(document.sections) == ["1 chapter Capitolo uno"])
        #expect(document.sections[0].title.styleName == "Heading 1" && document.sections[0].blocks.count == 2)
        #expect(document.blocks.count == 1, "«Primo» resta prima della sezione")
        #expect(enabled(h, #selector(EditorWindowController.insertSectionInside(_:))) && !enabled(h, #selector(EditorWindowController.insertSectionOutside(_:))))
        h.undo()
        h.undo()
        #expect(h.text == "Primo paragrafo.\nSecondo paragrafo." && h.editor.currentDocument().sections.isEmpty)
    }

    @Test("SZ5 · Dentro e più fuori: la profondità e il ruolo seguono le sezioni attorno")
    func insertSectionLevels() throws {
        let h = EditorHarness(paragraphs: ["Testo del capitolo.", "Altro testo."])
        defer { h.close() }
        h.select(0)
        h.editor.insertSectionSameLevel(nil)
        h.type("Uno")
        h.select((h.text as NSString).range(of: "Altro").location)
        h.editor.insertSectionInside(nil)
        h.type("Uno.1")
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Uno", "2 section Uno.1"])
        #expect(enabled(h, #selector(EditorWindowController.insertSectionOutside(_:))))
        h.select(h.text.utf16.count)
        h.editor.insertSectionOutside(nil)
        h.type("Due")
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Uno", "2 section Uno.1", "1 chapter Due"])
    }

    @Test("SZ6 · Invio nel titolo: in fondo o in mezzo il seguito va nel corpo; all'inizio il titolo resta titolo")
    func returnInTitle() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Dopo."])
        defer { h.close() }
        h.select(7)
        h.editor.insertSectionSameLevel(nil)
        h.type("Capitolo")
        h.select(7 + 4)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("X")
        var document = h.editor.currentDocument()
        #expect(outline(document.sections) == ["1 chapter Capi"])
        #expect(document.sections[0].blocks.count == 2, "«Xtolo» e «Dopo.» sono testo del capitolo")
        let marks = (0..<h.attributed.length).filter { h.attributed.attribute(.sectionTitle, at: $0, effectiveRange: nil) != nil }
        #expect(marks == Array(7..<12), "il segno resta solo sul titolo")
        h.select(7)
        h.press(#selector(NSResponder.insertNewline(_:)))
        document = h.editor.currentDocument()
        #expect(outline(document.sections) == ["1 chapter Capi"], "il titolo scende di una riga e resta titolo")
        #expect(document.blocks.count == 2 && h.selection == NSRange(location: 8, length: 0))
    }

    @Test("SZ7 · Cancella che unirebbe un titolo al paragrafo prima chiede; togliendo, le interne salgono; Annulla rimette tutto")
    func deleteAtTitle() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Testo.", "Fine."])
        defer { h.close() }
        h.select(7)
        h.editor.insertSectionSameLevel(nil)
        h.type("Capitolo")
        h.select((h.text as NSString).range(of: "Fine.").location)
        h.editor.insertSectionInside(nil)
        h.type("Sezione")
        let before = h.text
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 section Sezione"])

        h.editor.sectionRemovalAnswerForTests = false
        h.select(7)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.text == before, "rispondendo Annulla non succede nulla")
        h.select(6)
        h.press(#selector(NSResponder.deleteForward(_:)))
        #expect(h.text == before, "anche Cancella verso destra dalla fine del paragrafo prima chiede")

        h.editor.sectionRemovalAnswerForTests = true
        h.select(7)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.text.hasPrefix("Prima.Capitolo\nTesto."), "il titolo si unisce al paragrafo prima")
        #expect(outline(h.editor.currentDocument().sections) == ["1 section Sezione"], "la sezione interna sale al primo livello")
        #expect(h.undoActionName == "Remove Section")
        h.undo()
        #expect(h.text == before && outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 section Sezione"])
    }

    @Test("SZ8 · Inserisci › Togli la sezione toglie la più interna in cui sta il cursore, senza chiedere")
    func removeSectionCommand() throws {
        let h = EditorHarness(paragraphs: ["Testo.", "Fine."])
        defer { h.close() }
        h.select(0)
        h.editor.insertSectionSameLevel(nil)
        h.type("Capitolo")
        h.select((h.text as NSString).range(of: "Fine.").location)
        h.editor.insertSectionInside(nil)
        h.type("Sezione")
        h.select(h.text.utf16.count)
        let item = NSMenuItem(title: "", action: #selector(EditorWindowController.removeEnclosingSection(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item) && item.title == "Remove the Section “Sezione”")
        h.editor.removeEnclosingSection(nil)
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo"])
        #expect(h.text.hasSuffix("Sezione\nFine."), "il titolo resta come paragrafo")
        h.undo()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 section Sezione"])
    }

    // MARK: La sezione nell'ispettore (tappa S.2b)

    @Test("SZ9 · Percorso e ispettore della Sezione: un pulsante per livello; ruolo, livello, contenuto, pagine; ogni cambio un passo di Annulla")
    func sectionInspector() throws {
        let h = EditorHarness(paragraphs: ["Testo.", "Fine."])
        defer { h.close() }
        h.select(0)
        h.editor.insertSectionSameLevel(nil)
        h.type("Capitolo")
        h.select((h.text as NSString).range(of: "Fine.").location)
        h.editor.insertSectionInside(nil)
        h.type("Sezione")
        #expect(h.editor.sectionPathTitlesForTests == ["Chapter “Capitolo”", "Section “Sezione”"])

        let inspector = h.editor.inspectorForTests
        h.editor.inspectSection(depth: nil)
        var info = try #require(inspector.section)
        #expect(info.role == "section" && info.title == "“Sezione”" && info.depth == 2 && info.paragraphs == 1 && info.sections == 0)
        #expect(!info.canMoveInside && info.canMoveOutside)
        #expect(h.editor.inspectorFacts == [InspectorModel.Fact(title: "Pages", value: "1")])

        h.editor.inspectSection(depth: 1)
        info = try #require(inspector.section)
        #expect(info.title == "“Capitolo”" && info.paragraphs == 3 && info.sections == 1, "Testo., e la sezione col suo titolo e Fine.")

        h.editor.inspectSection(depth: nil)
        inspector.setSectionRole?("paragrafo")
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 paragrafo Sezione"])
        #expect(h.undoActionName == "Section Role")
        inspector.moveSection?(-1)
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "1 paragrafo Sezione"])
        #expect(inspector.section?.depth == 1 && inspector.section?.canMoveInside == true)
        inspector.moveSection?(1)
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 paragrafo Sezione"])
        inspector.removeSection?()
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo"] && h.editor.sectionPathTitlesForTests == ["Chapter “Capitolo”"])
        h.undo()
        h.undo()
        h.undo()
        h.undo()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Capitolo", "2 section Sezione"], "quattro passi, all'indietro")
    }

    // MARK: Lo stile che apre una sezione (tappa S.2c)

    @Test("SZ10 · Dare Titolo 1 apre un capitolo, Titolo 2 una sezione dentro; dare Testo toglie la sezione; la scheda Stili lo cambia")
    func styleOpensSection() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Primo capitolo", "Testo.", "Una sezione", "Altro testo."])
        defer { h.close() }
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }
        h.select(at("Primo capitolo"))
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        h.select(at("Una sezione"))
        h.editor.applyNamedStyle(.paragraph, name: "Heading 2")
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Primo capitolo", "2 section Una sezione"])
        #expect(h.undoActionName == "Style “Heading 2”")
        h.type("X")
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Primo capitolo", "2 section XUna sezione"], "si scrive nel titolo")
        h.select(at("Primo capitolo"))
        h.editor.applyNamedStyle(.paragraph, name: "Body")
        h.step()
        #expect(outline(h.editor.currentDocument().sections) == ["1 section XUna sezione"], "lo stile del corpo toglie il capitolo; la sezione interna sale")
        let items = DocumentOutline.build(text: h.attributed, layout: nil, floatStyles: [])
        #expect(items.first { $0.title == "Primo capitolo" }?.kind == .paragraph)
        #expect(items.first { $0.title == "Primo capitolo" }?.detail == "Body")
        h.undo()
        h.undo()
        h.undo()
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Primo capitolo"], "Annulla toglie la sezione con lo stile")

        h.editor.stylesTab.onOpensSection?("Heading 2", "")
        h.step()
        #expect(h.editor.currentDocument().styles.values(of: "Heading 2").opensSection == "")
        h.select(at("Una sezione"))
        h.editor.applyNamedStyle(.paragraph, name: "Heading 2")
        #expect(outline(h.editor.currentDocument().sections) == ["1 chapter Primo capitolo"], "con «No» lo stile non apre più nulla")
    }

    // MARK: Dove comincia una sezione (tappa S.3a)

    @Test("SZ11 · Ispettore › Sezione › Comincia: su una pagina nuova o dispari la composizione segue; le sezioni aperte dopo lo copiano")
    func sectionStartFromInspector() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Testo uno.", "Testo due."])
        defer { h.close() }
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }
        h.select(at("Testo uno."))
        h.editor.insertSectionSameLevel(nil)
        h.step()
        h.type("Uno")
        h.editor.inspectSection(depth: nil)
        let inspector = h.editor.inspectorForTests
        #expect(inspector.section?.start == .continuous)
        #expect(try #require(h.editor.currentLayout()).pages.count == 1)
        inspector.setSectionStart?(.oddPage)
        h.step()
        #expect(h.undoActionName == "Section Start" && inspector.section?.start == .oddPage)
        #expect(try #require(h.editor.currentLayout()).pages.count == 3, "il capitolo va a pagina 3, la 2 resta bianca")
        h.select(at("Testo due."))
        h.editor.insertSectionSameLevel(nil)
        h.step()
        h.type("Due")
        #expect(h.editor.currentDocument().sections.map(\.start) == [.oddPage, .oddPage], "il capitolo nuovo copia la dispari")
        #expect(try #require(h.editor.currentLayout()).pages.count == 5)
        h.undo()
        h.undo()
        h.undo()
        #expect(h.editor.currentDocument().sections.map(\.start) == [.continuous])
    }

    // MARK: La distanza d'apertura (tappa S.3b)

    @Test("SZ12 · Ispettore › Paragrafo › Distanza d'apertura: il titolo di un capitolo su pagina nuova scende; dato qui, poi torna allo stile")
    func openingDistanceFromInspector() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Uno", "Testo."])
        defer { h.close() }
        let uno = (h.text as NSString).range(of: "Uno").location
        h.select(uno)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        h.editor.inspectSection(depth: nil)
        h.editor.inspectorForTests.setSectionStart?(.newPage)
        h.step()
        func top() throws -> CGFloat {
            let layout = try #require(h.editor.currentLayout())
            let line = try #require(layout.pages.lazy.compactMap { $0.lines.first { $0.paragraphLocation == uno } }.first)
            return line.origin.y + line.ascent
        }
        let before = try top()
        h.select(uno + 1)
        h.editor.inspect(.paragraph)
        let inspector = h.editor.inspectorForTests
        #expect(inspector.values.first { $0.property == .openingDistance }?.value.openingDistance == 0)
        inspector.change(.openingDistance) { $0.openingDistance = 100 }
        h.step()
        let value = try #require(inspector.values.first { $0.property == .openingDistance })
        #expect(value.value.openingDistance == 100 && value.source == .own)
        #expect(abs((before - (try top())) - 100) < 0.01, "il titolo scende di 100 pt")
        #expect(h.editor.currentDocument().sections.first?.title.openingDistance == 100)
        h.undo()
        #expect(abs(try top() - before) < 0.01 && h.editor.currentDocument().sections.first?.title.openingDistance == nil)
    }

    // MARK: Liste per sezione (tappa S.4)

    @Test("SZ13 · Scheda Liste: «riparte a ogni sezione di ruolo…» e «numera le sezioni» si leggono e si riscrivono; i ruoli offerti")
    func listsTabSections() throws {
        let lists = [ListDefinition(name: "Capitoli", counter: .decimal, suffix: ".", numbersSections: "chapter"),
                     ListDefinition(name: "Examples", counter: .decimal, parent: .section("lezione"), showsParent: true)]
        let model = ListsSheetModel(lists: lists, noteList: nil)
        model.documentRoles = ["chapter", "tavola"]
        #expect(model.rows[1].parent == .section("lezione"))
        #expect(model.roles == ["part", "chapter", "section", "appendix", "tavola", "lezione"], "pronti, del documento, già usati")
        #expect(model.definitions == lists, "riscritte uguali")
        model.rows[1].parent = .section("capitolo")
        model.rows[0].definition.numbersSections = nil
        #expect(model.result().lists[1].parent == .section("capitolo") && model.result().lists[0].numbersSections == nil)
    }

    // MARK: Tipi di pagina a schermo (tappa S.5b)

    @Test("SZ14 · A schermo ogni pagina col suo formato (una orizzontale tra verticali); il righello segue lo specchio della pagina del cursore")
    func pagesOfDifferentSizes() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Tavola", "Testo della tavola.", "Dopo", "Testo dopo."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        window.setContentSize(NSSize(width: 1280, height: 800))
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }
        var document = h.editor.currentDocument()
        let landscape = PageSetup(paperSize: CGSize(width: PageSetup.points(fromMillimetres: 297), height: PageSetup.points(fromMillimetres: 210)),
                                  top: 50, bottom: 50, left: 60, right: 60)
        document.pageTypes = [PageType(name: "Orizzontale", setup: landscape)]
        var flat = document.flatParagraphs
        flat[1].section = SectionMark(id: "t", role: "tavola", depth: 1, start: .newPage, pageTypes: SectionPageTypes(pages: "Orizzontale"))
        flat[3].section = SectionMark(id: "d", role: "chapter", depth: 1, start: .newPage, pageTypes: SectionPageTypes(pages: PageType.defaultName))
        document.setFlatParagraphs(flat)
        h.editor.replaceContent(document)
        h.step()
        let layout = try #require(h.editor.currentLayout())
        #expect(layout.pages.count == 3 && layout.setup(forPage: 1) == landscape)
        let first = try #require(h.editor.pageFrameForTests(0)), second = try #require(h.editor.pageFrameForTests(1)), third = try #require(h.editor.pageFrameForTests(2))
        #expect(second.width > second.height && first.height > first.width, "la seconda pagina è orizzontale")
        #expect(second.minY > first.maxY && third.minY > second.maxY, "le pagine non si sovrappongono")
        #expect(abs((third.minY - second.maxY) - (second.minY - first.maxY)) < 0.5, "la stessa distanza tra le pagine")
        h.select(at("Testo della tavola."))
        let ruler = try #require(h.editor.rulerGeometry)
        #expect(abs(ruler.columnWidth - landscape.textRect.width * ruler.scale) < 0.5, "il righello ha lo specchio della pagina orizzontale")
    }

    // MARK: Tipi di pagina nell'interfaccia (tappa S.5c)

    @Test("SZ15 · Ispettore Pagina sul tipo della pagina del cursore; scheda Pagine (rinominare segue nelle sezioni); tipi della sezione; Annulla")
    func pageTypesInterface() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Tavola", "Testo della tavola.", "Dopo", "Testo dopo."])
        defer { h.close() }
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }
        var document = h.editor.currentDocument()
        let landscape = PageSetup(paperSize: CGSize(width: PageSetup.points(fromMillimetres: 297), height: PageSetup.points(fromMillimetres: 210)),
                                  top: 50, bottom: 50, left: 60, right: 60)
        document.pageTypes = [PageType(name: "Orizzontale", setup: landscape)]
        var flat = document.flatParagraphs
        flat[1].section = SectionMark(id: "t", role: "tavola", depth: 1, start: .newPage, pageTypes: SectionPageTypes(pages: "Orizzontale"))
        flat[3].section = SectionMark(id: "d", role: "chapter", depth: 1, start: .newPage)
        document.setFlatParagraphs(flat)
        h.editor.replaceContent(document)
        h.step()
        let inspector = h.editor.inspectorForTests

        // L'ispettore Pagina: il tipo della pagina del cursore.
        h.select(at("Testo della tavola."))
        h.editor.inspect(.page)
        #expect(inspector.pageTypeName == "Orizzontale" && inspector.pageSetup == landscape)
        var taller = landscape
        taller.top = 80
        inspector.setPageSetup?(taller)
        h.step()
        #expect(h.editor.currentDocument().pageTypes.first?.setup.top == 80 && h.editor.currentDocument().pageSetup == document.pageSetup)
        #expect(h.undoActionName == "Page type “Orizzontale”")
        h.select(at("Premessa."))
        h.editor.inspect(.page)
        #expect(inspector.pageTypeName == nil, "la prima pagina ha il tipo predefinito")
        h.undo()
        #expect(h.editor.currentDocument().pageTypes.first?.setup.top == 50)

        // La scheda Pagine: rinominare il tipo, e la sezione lo segue.
        h.editor.definitionsPanel.show(.pages)
        let sheet = try #require(h.editor.definitionsPanel.pageTypes)
        #expect(sheet.rows.map(\.type.name) == ["Orizzontale"])
        sheet.rename("Larga")
        h.editor.definitionsPanel.flushPending()
        h.step()
        #expect(h.editor.currentDocument().pageTypes.map(\.name) == ["Larga"])
        #expect(h.editor.currentDocument().sections.first?.pageTypes.pages == "Larga", "la sezione segue la rinomina")
        #expect(h.undoActionName == "Page Types")
        h.undo()
        #expect(h.editor.currentDocument().pageTypes.map(\.name) == ["Orizzontale"] && h.editor.currentDocument().sections.first?.pageTypes.pages == "Orizzontale")

        // L'ispettore della sezione: senza tipo, la tavola torna al predefinito.
        h.select(at("Testo della tavola."))
        h.editor.inspectSection(depth: nil)
        #expect(inspector.section?.pageTypes.pages == "Orizzontale" && inspector.section?.typeNames == ["Orizzontale"])
        inspector.setSectionPageTypes?(SectionPageTypes())
        h.step()
        #expect(try #require(h.editor.currentLayout()).setup(forPage: 1) == document.pageSetup)
        h.undo()
        #expect(try #require(h.editor.currentLayout()).setup(forPage: 1) == landscape)
    }

    // MARK: Campi (tappa H.1)

    @Test("SZ16 · Inserisci › Campo: un carattere che la pagina sostituisce; dopo si scrive testo; anche in una nota; un passo di Annulla")
    func insertFieldCommand() throws {
        let h = EditorHarness(paragraphs: ["Pagina  di tutto."])
        defer { h.close() }
        let menu = NSMenu()
        FieldMenuFiller.shared.menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        #expect(titles.prefix(2) == ["Page number", "Number of pages"] && titles.contains("Title of the current section: chapter"))
        h.select(7)
        let item = try #require(menu.items.first)
        h.editor.insertField(item)
        h.step()
        #expect(h.undoActionName == "Field")
        // Il numero di pagina si inserisce come formula (Posizione → Pagina contenente → Numero).
        #expect(h.attributed.attribute(.field, at: 7, effectiveRange: nil) as? String == Field.formula(.pageContainingNumber).encoded)
        h.type("x")
        #expect(h.attributed.attribute(.field, at: 8, effectiveRange: nil) == nil, "ciò che si scrive dopo un campo è testo")
        let paragraph = try #require(h.editor.currentDocument().blocks.first.flatMap { if case .paragraph(let p) = $0 { p } else { nil } })
        #expect(paragraph.inlines.contains { if case .text(let run) = $0 { run.field == .page } else { false } })
        // In una nota.
        h.editor.insertFootnote(nil)
        h.step()
        h.type("Vedi pagina ")
        h.editor.insert(field: .page)
        h.step()
        let note = try #require(h.editor.currentDocument().blocks.first.flatMap { block -> FloatingObject? in
            guard case .paragraph(let p) = block else { return nil }
            return p.inlines.lazy.compactMap { if case .floating(let n) = $0 { n } else { nil } }.first
        })
        #expect(note.runs.contains { $0.field == .page } && note.runs.first?.text == "Vedi pagina ", "il campo sta nel testo della nota, che resta una")
        // Cinque passi: il campo, la «x», la nota, il suo testo, il campo nella nota.
        for _ in 0..<5 { h.undo() }
        #expect(h.text == "Pagina  di tutto.")
    }

    // MARK: Intestazioni nell'interfaccia (tappa H.3)

    private func floats(in paragraph: Paragraph) -> [FloatingObject] {
        paragraph.inlines.compactMap { if case .floating(let note) = $0 { note } else { nil } }
    }

    @Test("SZ17 · Inserisci › Intestazione e Piè di pagina: ancorati al titolo della sezione (o al primo paragrafo); lo stile nasce; un passo di Annulla")
    func insertRunningCommand() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Testo."])
        defer { h.close() }
        func first() throws -> Paragraph { try #require(h.editor.currentDocument().blocks.first.flatMap { if case .paragraph(let p) = $0 { p } else { nil } }) }
        h.select(h.text.utf16.count)
        h.editor.insertRunning(placement: .pageHead, pages: .all)
        h.step()
        #expect(h.editor.currentDocument().floatStyles.contains(.running(name: "Header")) && h.undoActionName == "Header")
        h.type("Il libro")
        // Il cursore, mentre si scrive nell'intestazione, sta sulla sua riga in testa alla pagina, non sulla prima del corpo.
        let caretLayout = try #require(h.editor.currentLayout())
        let caret = try #require(caretLayout.caret(at: h.selection.location, affinity: .upstream))
        #expect(caret.rect.minY > caretLayout.pages[caret.page].setup.paperSize.height - caretLayout.pages[caret.page].setup.top, "il cursore è nell'intestazione")
        var placed = floats(in: try first())
        #expect(placed.map(\.style) == ["Header"] && placed.first?.runs.first?.text == "Il libro", "senza sezioni, nel primo paragrafo")
        let layout = try #require(h.editor.currentLayout())
        let setup = layout.pages[0].setup
        #expect(layout.pages[0].lines.contains { $0.noteRange != nil && $0.origin.y > setup.paperSize.height - setup.top }, "in testa alla pagina")
        h.select(h.text.utf16.count)
        h.editor.insertRunning(placement: .pageHead, pages: .all)
        h.step()
        placed = floats(in: try first())
        #expect(placed.count == 1, "il secondo comando porta in quella che c'è")
        h.select(h.text.utf16.count)
        h.editor.insertRunning(placement: .pageBottom, pages: .all)
        h.step()
        placed = floats(in: try first())
        #expect(placed.last.map { $0.style == "Footer" && $0.runs.contains { $0.field == .page } } == true, "con il numero di pagina")
        h.undo()
        placed = floats(in: try first())
        #expect(placed.count == 1 && !h.editor.currentDocument().floatStyles.contains { $0.name == "Footer" }, "un passo: stile e ancora")

        // In una sezione: nel suo titolo.
        h.select((h.text as NSString).range(of: "Testo.").location)
        h.editor.insertSectionSameLevel(nil)
        h.step()
        h.type("Capitolo")
        h.select((h.text as NSString).range(of: "Testo.").location + 2)
        h.editor.insertRunning(placement: .pageHead, pages: .first)
        h.step()
        h.type("Apertura")
        let title = try #require(h.editor.currentDocument().sections.first?.title)
        #expect(floats(in: title).map(\.style) == ["Header (first page)"])
        // L'aspetto del testo, non quello del titolo (Titolo 1, 18 pt in nero): cinque sesti del corpo del testo.
        let run = try #require(floats(in: title).first?.runs.first)
        #expect(run.text == "Apertura" && run.style.size == 10 && run.style.fontName == "HoeflerText-Regular")
        #expect(h.editor.sectionPathTitlesForTests == ["Chapter “Capitolo”"], "il nome della sezione non comprende l'intestazione")
    }

    @Test("SZ18 · Scheda Liste › Pagine numerate con; ispettore della Sezione › Numeri di pagina ripartono")
    func pageNumberingInterface() throws {
        let h = EditorHarness(paragraphs: ["Premessa.", "Capitolo", String(repeating: "Testo che riempie la pagina. ", count: 400)])
        defer { h.close() }
        h.editor.definitionsPanel.show(.lists)
        let lists = try #require(h.editor.definitionsPanel.lists)
        lists.pageList = lists.rows.first { $0.definition.name == "Examples" }?.id
        h.editor.definitionsPanel.flushPending()
        h.step()
        #expect(h.editor.currentDocument().pageNumbering == "Examples")
        var number = try #require(h.editor.currentLayout()).pages.first?.number
        #expect(number == "(1)", "con la Lista degli esempi: (1)")
        h.select((h.text as NSString).range(of: "Capitolo").location)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        h.editor.inspectSection(depth: nil)
        let inspector = h.editor.inspectorForTests
        #expect(inspector.section?.listNames.contains("Numbered List") == true && inspector.section?.pageNumbering == nil)
        inspector.setSectionPageNumbering?("Numbered List")
        h.step()
        #expect(h.editor.currentDocument().sections.first?.pageNumbering == "Numbered List")
        number = try #require(h.editor.currentLayout()).pages.first?.number
        #expect(number == "1.", "il capitolo comincia nella prima pagina e la fa ripartire")
        h.undo()
        number = try #require(h.editor.currentLayout()).pages.first?.number
        #expect(number == "(1)")
    }

    // MARK: Tabelle

    @Test("TB1 · Inserisci › Tabella: 3 × 3 dopo il paragrafo del cursore, il cursore nella prima cella; nella tabella il comando è spento; Annulla la toglie")
    func insertTable() throws {
        let h = EditorHarness(paragraphs: ["Prima del punto.", "Dopo."])
        defer { h.close() }
        h.select(5)
        h.editor.insertTable(nil)
        h.step()
        #expect(h.text == "Prima del punto.\n" + String(repeating: "\n", count: 9) + "Dopo.")
        let document = h.editor.currentDocument()
        guard document.blocks.count == 3, case .table(let table) = document.blocks[1] else {
            Issue.record("niente tabella dopo il primo paragrafo")
            return
        }
        #expect(table.rows.count == 3 && table.columnCount == 3 && table.headerRows == 1)
        #expect(h.editor.pagesSelectedRange == NSRange(location: 17, length: 0))
        h.type("Nome")
        h.step()
        #expect(TableEditing.cell(at: 17, in: h.editor.editingText)?.column == 0)
        #expect(h.text.hasPrefix("Prima del punto.\nNome\n"))
        let item = NSMenuItem(title: "Tabella", action: #selector(EditorWindowController.insertTable(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item) == false, "dentro una tabella non se ne inserisce un'altra")
        h.undo()
        h.undo()
        #expect(h.text == "Prima del punto.\nDopo.")
    }

    @Test("TB2 · Nelle celle: Tab e Maiusc-Tab passano di cella (Tab nell'ultima aggiunge una riga), Opzione-Tab scrive un Tab, Invio resta nella cella, le cancellazioni non uniscono celle, scrivere dopo la tabella è fuori")
    func keysInCells() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        // Prima.\n + nove celle vuote + il paragrafo finale vuoto (fuori dalla tabella).
        h.type("a")
        h.press(#selector(NSResponder.insertTab(_:)))
        h.type("b")
        #expect(h.text.hasPrefix("Prima.\na\nb\n"))
        h.press(#selector(NSResponder.insertBacktab(_:)))
        #expect(h.selection == NSRange(location: 7, length: 1), "Maiusc-Tab seleziona il testo della cella prima")
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.selection == NSRange(location: 9, length: 1))
        // Opzione-Tab: un Tab vero, nella cella.
        h.press(#selector(NSResponder.moveRight(_:)))
        h.press(#selector(NSResponder.insertTabIgnoringFieldEditor(_:)))
        #expect(h.text.hasPrefix("Prima.\na\nb\t\n"))
        // Invio: un paragrafo nuovo nella stessa cella.
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("b2")
        #expect(TableEditing.cell(at: h.selection.location, in: h.attributed).map { [$0.row, $0.column] } == [0, 1])
        var table: Table? { h.editor.currentDocument().blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
        #expect(table?.rows.count == 3 && table?.rows.first?.cells[1].paragraphs.count == 2)
        // Indietro all'inizio della cella «b»: non fa nulla.
        let bStart = (h.text as NSString).range(of: "b\t").location
        h.select(bStart)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(h.text.hasPrefix("Prima.\na\nb\t\nb2\n"))
        // Avanti alla fine della cella «a»: non fa nulla.
        h.select(8)
        h.press(#selector(NSResponder.deleteForward(_:)))
        #expect(h.text.hasPrefix("Prima.\na\nb\t\nb2\n"))
        // Una selezione da «Prima» a «b2» cancellata: le celle si svuotano, la tabella resta.
        h.select(3, length: bStart + 5 - 3)
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(table?.rows.count == 3 && table?.columnCount == 3)
        #expect(h.text.hasPrefix("Pri\n\n"))
        // Tab nell'ultima cella aggiunge una riga, e il cursore ci va.
        let lastCell = (h.text as NSString).length - 1
        h.select(lastCell)
        #expect(TableEditing.cell(at: lastCell, in: h.attributed).map { [$0.row, $0.column] } == [2, 2])
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(table?.rows.count == 4)
        #expect(TableEditing.cell(at: h.selection.location, in: h.attributed).map { [$0.row, $0.column] } == [3, 0])
        // Scrivere nel paragrafo finale, dopo la tabella: è testo fuori dalla tabella.
        h.select((h.text as NSString).length)
        h.type("Dopo")
        #expect(TableEditing.cell(at: (h.text as NSString).length - 1, in: h.attributed) == nil)
        #expect(table?.rows.count == 4)
        if case .paragraph = h.editor.currentDocument().blocks.last {} else { Issue.record("«Dopo» non è un paragrafo dopo la tabella") }
        #expect(h.storeIsConsistent)
    }

    @Test("TB3 · Una tabella copiata e incollata fuori fa una seconda tabella; incollata in una cella diventa testo della cella")
    func pasteTable() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Dopo."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("a")
        // Tutta la tabella (nove celle) e l'a capo dopo: Prima.\na\n…
        h.select(7, length: 10)
        h.menu(#selector(NSText.copy(_:)))
        h.select((h.text as NSString).length)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.menu(#selector(NSText.paste(_:)))
        let tables = h.editor.currentDocument().blocks.filter { if case .table = $0 { true } else { false } }
        #expect(tables.count == 2)
        // In una cella: diventa testo di quella cella.
        h.select(9)
        h.menu(#selector(NSText.paste(_:)))
        let after = h.editor.currentDocument().blocks.filter { if case .table = $0 { true } else { false } }
        #expect(after.count == 2)
        if case .table(let first) = after.first { #expect(first.rows.count == 3 && first.columnCount == 3) }
    }

    @Test("TB4 · Menu Tabella e ispettore Tabella: righe e colonne, righe d'intestazione, togli la tabella; la tabella nell'albero degli oggetti")
    func tableCommands() throws {
        let h = EditorHarness(paragraphs: ["Prima.", "Dopo."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("a")
        var table: Table? { h.editor.currentDocument().blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
        func cellOfCaret() -> [Int]? { TableEditing.cell(at: h.selection.location, in: h.attributed).map { [$0.row, $0.column] } }
        let item = NSMenuItem(title: "Riga sotto", action: #selector(EditorWindowController.tableCommand(_:)), keyEquivalent: "")
        item.representedObject = TableCommand.rowBelow.rawValue
        #expect(h.editor.validateMenuItem(item))
        h.editor.tableCommand(item)
        h.step()
        #expect(table?.rows.count == 4 && cellOfCaret() == [1, 0])
        h.editor.perform(.columnRight)
        h.step()
        #expect(table?.columnCount == 4 && cellOfCaret() == [1, 1])
        // L'ispettore della tabella.
        h.editor.inspect(.table)
        let inspector = h.editor.inspectorForTests
        let info = try #require(inspector.table)
        let shape: [Int] = [info.rows, info.columns, info.headerRows, info.row, info.column]
        #expect(shape == [4, 4, 1, 2, 2])
        #expect(h.editor.inspectorFacts.contains { $0.title == "Pages" })
        inspector.setTableHeaderRows?(2)
        h.step()
        #expect(table?.headerRows == 2)
        inspector.tableCommand?(.removeColumn)
        h.step()
        h.editor.perform(.removeRow)
        h.step()
        #expect(table?.rows.count == 3 && table?.columnCount == 3 && table?.headerRows == 1, "la riga tolta era d'intestazione")
        #expect(table?.rows.first?.cells.first?.paragraphs.isEmpty == false && h.text.hasPrefix("Prima.\na\n"))
        // Nell'albero: la tabella, con le sue nove celle.
        let outline = DocumentOutline.build(text: h.attributed, layout: h.editor.currentLayout(), floatStyles: [])
        let tableItem = try #require(outline.first { $0.kind == .table })
        #expect(tableItem.children?.count == 9 && tableItem.detail == "3 × 3")
        #expect(Set(outline.map(\.id)).count == outline.count)
        // Togli la tabella: l'ispettore torna al paragrafo; Annulla la rimette.
        h.editor.perform(.removeTable)
        h.step()
        #expect(h.text == "Prima.\nDopo." && inspector.object == .paragraph)
        h.undo()
        #expect(table?.rows.count == 3)
        // Fuori dalla tabella i comandi sono spenti.
        h.select(0)
        #expect(!h.editor.validateMenuItem(item))
    }

    @Test("TB5 · Aspetto delle tabelle: stile ed eccezioni nell'ispettore Tabella, lati, fondo e allineamento nell'ispettore Cella, scheda Tabelle (rinominare e togliere uno stile), Annulla")
    func tableAppearanceInterface() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("a")
        var table: Table? { h.editor.currentDocument().blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
        var page: LaidOutPage? { h.editor.currentLayout()?.pages.first }
        let inspector = h.editor.inspectorForTests
        h.editor.inspect(.table)
        #expect(inspector.table?.style == nil && inspector.table?.styleNames.count == 5 && inspector.table?.resolved == .initial)
        // Lo stile «Tre filetti»: niente filetti verticali.
        inspector.setTableStyle?("Three Rules")
        h.step()
        #expect(table?.styleName == "Three Rules" && inspector.table?.style == "Three Rules")
        #expect(page?.rules.allSatisfy { $0.width > $0.height } == true)
        // Un fondo solo per questa tabella; la selezione resta dov'era.
        let caret = h.selection
        inspector.changeTable?(.background("#ff0000"))
        h.step()
        #expect(table?.values.background == "#ff0000" && page?.fills.count == 9 && h.selection == caret)
        // La cella: un filetto di 2 punti sopra, al centro, senza fondo.
        h.editor.inspect(.cell)
        #expect(inspector.cell?.row == 1 && inspector.cell?.column == 1)
        inspector.changeCell?(.border(.top, .rule(2)))
        h.step()
        inspector.changeCell?(.alignment(.middle))
        h.step()
        inspector.changeCell?(.background(""))
        h.step()
        #expect(table?.rows[0].cells[0].values == CellValues(top: .rule(2), background: "", verticalAlignment: .middle))
        #expect(page?.fills.count == 8)
        // Scegliere i filetti per la tabella toglie i lati detti per le celle (il resto resta).
        inspector.changeTable?(.rules(.grid))
        h.step()
        #expect(table?.values.rules == .grid && table?.rows[0].cells[0].values == CellValues(background: "", verticalAlignment: .middle))
        // Togliere l'eccezione torna allo stile; Annulla la rimette.
        inspector.changeTable?(.rules(nil))
        h.step()
        #expect(table?.values.rules == nil)
        h.undo()
        #expect(table?.values.rules == .grid)
        // La scheda Tabelle: rinominare lo stile che la tabella usa, poi toglierlo.
        h.editor.definitionsPanel.show(.tables)
        let sheet = try #require(h.editor.definitionsPanel.tableStyles)
        sheet.selection = sheet.rows.first { $0.style.name == "Three Rules" }?.id
        sheet.rename("Tre righe")
        h.editor.definitionsPanel.flushPending()
        h.step()
        #expect(h.editor.currentDocument().tableStyles.contains { $0.name == "Tre righe" } && table?.styleName == "Tre righe")
        sheet.removeSelected()
        h.editor.definitionsPanel.flushPending()
        h.step()
        #expect(table?.styleName == nil && !h.editor.currentDocument().tableStyles.contains { $0.name == "Tre righe" })
        h.undo()
        #expect(table?.styleName == "Tre righe")
        // Il file si scrive e si riapre con lo stesso aspetto.
        let written = DocumentFormat.string(for: h.editor.currentDocument())
        let reread = try DocumentFormat.document(from: written)
        #expect(reread.blocks == h.editor.currentDocument().blocks)
    }

    @Test("TB6 · Tabella › Tabella flottante, con didascalia: nasce lo stile «Tabella» con la Lista «Tabelle», il cursore va nella didascalia; spenta, la didascalia va via; Annulla la rimette")
    func floatingTableInterface() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        var table: Table? { h.editor.currentDocument().blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
        let item = NSMenuItem(title: "Tabella flottante, con didascalia", action: #selector(EditorWindowController.toggleTableFloat(_:)), keyEquivalent: "")
        #expect(h.editor.validateMenuItem(item) && item.state == .off)
        h.editor.toggleTableFloat(item)
        h.step()
        let document = h.editor.currentDocument()
        #expect(document.floatStyles.contains { $0.name == FloatStyle.tableName && $0.placement == .figure })
        #expect(document.lists.contains { $0.name == ListDefinition.tables.name })
        #expect(table?.floatStyle == FloatStyle.tableName)
        #expect(TableEditing.cell(at: h.selection.location, in: h.attributed)?.isCaption == true)
        h.type("Popolazione")
        #expect(table?.caption.count == 1 && table?.rows.count == 3)
        _ = h.editor.validateMenuItem(item)
        #expect(item.state == .on)
        h.editor.inspect(.table)
        #expect(h.editor.inspectorForTests.table?.floatStyle == FloatStyle.tableName)
        // Nella pagina: la didascalia con il numero, sopra la tabella.
        let captionAt = (h.text as NSString).range(of: "Popolazione").location
        let line = try #require(h.editor.currentLayout()?.pages.first?.lines.first { $0.paragraphLocation == captionAt })
        #expect(CTLineGetGlyphCount(line.line) == "Table 1. Popolazione".count + 1)
        // Spenta: torna nel testo e perde la didascalia; il cursore resta nella sua cella; Annulla la rimette.
        h.press(#selector(NSResponder.insertTab(_:)))
        h.type("Nome")
        let cellBefore = TableEditing.cell(at: h.selection.location, in: h.attributed).map { [$0.row, $0.column] }
        h.editor.toggleTableFloat(item)
        h.step()
        #expect(table?.floatStyle == nil && table?.caption.isEmpty == true && !h.text.contains("Popolazione"))
        #expect(TableEditing.cell(at: h.selection.location, in: h.attributed).map { [$0.row, $0.column] } == cellBefore)
        #expect((h.text as NSString).substring(to: h.selection.location).hasSuffix("Nome"))
        h.undo()
        #expect(table?.floatStyle == FloatStyle.tableName && h.text.contains("Popolazione"))
        let reread = try DocumentFormat.document(from: DocumentFormat.string(for: h.editor.currentDocument()))
        #expect(reread.blocks == h.editor.currentDocument().blocks)
    }

    @Test("TB7 · Tabella › Unisci le celle sulle celle selezionate, Dividi la cella (anche dall'ispettore Cella), Annulla")
    func mergeCellsInterface() throws {
        let h = EditorHarness(paragraphs: ["Prima."])
        defer { h.close() }
        h.select(0)
        h.editor.insertTable(nil)
        h.step()
        h.type("a")
        h.press(#selector(NSResponder.insertTab(_:)))
        h.type("b")
        var table: Table? { h.editor.currentDocument().blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
        let merge = NSMenuItem(title: "Unisci le celle", action: #selector(EditorWindowController.mergeTableCells(_:)), keyEquivalent: "")
        let split = NSMenuItem(title: "Dividi la cella", action: #selector(EditorWindowController.splitTableCell(_:)), keyEquivalent: "")
        // Il cursore in una cella sola: niente da unire.
        #expect(!h.editor.validateMenuItem(merge) && !h.editor.validateMenuItem(split))
        // Dall'inizio di «b» a una lettera della cella dopo: la cella «a», che finisce dove comincia la selezione, non c'entra.
        h.select(9, length: 3)
        h.editor.mergeTableCells(merge)
        h.step()
        #expect(table?.rows[0].cells[0].columnSpan == 1 && table?.rows[0].cells[1].columnSpan == 2 && table?.rows[0].cells[2].isCovered == true)
        h.undo()
        #expect(table?.rows[0].cells.map(\.columnSpan) == [1, 1, 1])
        // Da «a» a «b»: due celle della prima riga.
        h.select(7, length: 3)
        #expect(h.editor.validateMenuItem(merge))
        h.editor.mergeTableCells(merge)
        h.step()
        #expect(table?.rows[0].cells[0].columnSpan == 2 && table?.rows[0].cells[1].isCovered == true)
        #expect(table?.rows[0].cells[0].paragraphs.count == 2 && h.selection == NSRange(location: 7, length: 0))
        #expect(h.editor.validateMenuItem(split))
        h.editor.inspect(.cell)
        #expect(h.editor.inspectorForTests.cell?.columnSpan == 2)
        // Dividere dall'ispettore; Annulla la riunisce.
        h.editor.inspectorForTests.splitCell?()
        h.step()
        #expect(table?.rows[0].cells.map(\.isCovered) == [false, false, false] && table?.rows[0].cells[0].columnSpan == 1)
        h.undo()
        #expect(table?.rows[0].cells[0].columnSpan == 2)
        #expect(h.storeIsConsistent)
    }

    @Test("TB8 · Sulla virgola: il quinto pulsante dell'allineamento lo applica al paragrafo e si accende; l'ispettore lo mostra; il file lo conserva")
    func decimalAlignmentInterface() throws {
        let h = EditorHarness(paragraphs: ["3,14"])
        defer { h.close() }
        h.select(1)
        let alignment = try #require(h.editor.bandControls["allineamento"] as? BandSegments)
        alignment.press(4)
        h.step()
        let style = try #require(h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.isDecimalAligned)
        h.editor.refreshBandState()
        #expect(alignment.selectedSegment == 4)
        h.editor.inspect(.paragraph)
        #expect(h.editor.inspectorForTests.values.first { $0.property == .alignment }?.value.alignment == .decimal)
        guard case .paragraph(let paragraph) = h.editor.currentDocument().blocks.first else { Issue.record("niente paragrafo"); return }
        #expect(paragraph.style.alignment == .decimal)
        // A destra resta a destra.
        alignment.press(2)
        h.step()
        h.editor.refreshBandState()
        #expect(alignment.selectedSegment == 2)
        #expect((h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.isDecimalAligned == false)
    }

    @Test("R1 · Ripristina versione salvata butta via le modifiche in attesa della pausa (scheda Stili, scheda Liste): non arrivano al documento ripristinato")
    func revertDiscardsPendingChanges() throws {
        let h = EditorHarness(paragraphs: ["Uno.", "Due."])
        defer { h.close() }
        let saved = h.editor.currentDocument()
        func pause() { RunLoop.main.run(until: Date(timeIntervalSinceNow: max(EditorWindowController.stylePause, DefinitionsPanel.pause) + 0.3)) }
        // Scheda Stili: un corpo nuovo ancora in attesa, poi il ripristino.
        h.editor.showDefinitions(.styles)
        h.step()
        h.editor.stylesTab.inspector.change(.size) { $0.size = 30 }
        h.step()
        h.editor.replaceContent(saved)
        pause()
        #expect(h.editor.currentDocument().styles == saved.styles, "la modifica in attesa è arrivata dopo il ripristino")
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize != 30)
        // Scheda Liste: una Lista rinominata ancora in attesa, poi il ripristino.
        h.editor.definitionsPanel.show(.lists)
        let lists = try #require(h.editor.definitionsPanel.lists)
        let index = try #require(lists.rows.firstIndex { $0.definition.name == "Examples" })
        lists.rows[index].definition.name = "Esempi rinominati"
        h.step()
        h.editor.replaceContent(saved)
        pause()
        #expect(h.editor.currentDocument().lists == saved.lists, "la Lista rinominata è arrivata dopo il ripristino")
        // La scheda mostra il documento ripristinato.
        #expect(h.editor.definitionsPanel.lists?.rows.contains { $0.definition.name == "Examples" } == true)
    }

    // MARK: Lo zoom allarga la finestra

    @Test("Z1 · Ingrandendo, la finestra si allarga per contenere la pagina (fino ai bordi dello schermo); riducendo torna com'era; dopo un ridimensionamento a mano no")
    func zoomGrowsWindow() throws {
        let h = EditorHarness(paragraphs: ["Una pagina da ingrandire."])
        defer { h.close() }
        let window = try #require(h.editor.window)
        let screen = try #require((window.screen ?? NSScreen.main)?.visibleFrame)
        window.setFrame(NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 900, height: min(700, screen.height - 80)), display: true)
        window.orderFront(nil)
        h.step()
        let start = window.frame
        for _ in 0..<4 { h.editor.zoomIn(nil); h.step() }
        #expect(window.frame.width > start.width, "la finestra si è allargata")
        let area = EditorWindowController.zoomArea(screen: screen)
        #expect(area.contains(window.frame), "senza uscire dallo schermo")
        #expect(h.editor.frameBeforeZoom == start)
        h.editor.zoomToFit(nil)
        h.step()
        #expect(window.frame == start && h.editor.frameBeforeZoom == nil, "con «Adatta alla finestra» torna com'era")
        // Allargata dallo zoom, poi ridimensionata a mano: riducendo lo zoom resta com'è.
        for _ in 0..<4 { h.editor.zoomIn(nil); h.step() }
        var manual = window.frame
        manual.size.width -= 20
        window.setFrame(manual, display: true)
        h.step()
        h.editor.zoomToFit(nil)
        h.step()
        #expect(window.frame == manual && h.editor.frameBeforeZoom == nil, "ridimensionata a mano: resta com'è")
        // Molti ingrandimenti di seguito, senza pause (come il pizzico): la misura di partenza non si perde.
        window.setFrame(start, display: true)
        h.step()
        for _ in 0..<5 { h.editor.zoomIn(nil) }
        h.editor.zoomToFit(nil)
        h.step()
        #expect(window.frame == start, "di seguito, poi «Adatta alla finestra»: com'era")
        // Con il pizzico, da una finestra vicina al bordo destro o a quello sinistro: sempre dentro lo schermo.
        for start in [NSRect(x: screen.maxX - 800, y: screen.minY + 40, width: 760, height: 700),
                      NSRect(x: screen.minX + 2, y: screen.minY + 40, width: 900, height: 700)] {
            window.setFrame(start, display: true)
            h.editor.zoomToFit(nil)
            h.step()
            for _ in 0..<12 {
                h.editor.pinchForTests(by: 0.3)
                h.step()
                #expect(area.contains(window.frame), "pizzicando, la finestra resta nello schermo: \(window.frame)")
            }
        }
        // I conti della cornice: una finestra più larga dello spazio, o che ne esce, torna dentro.
        let space = NSRect(x: 0, y: 78, width: 2240, height: 1152)
        #expect(EditorWindowController.clamped(NSRect(x: 1800, y: 100, width: 900, height: 700), to: space) == NSRect(x: 1340, y: 100, width: 900, height: 700))
        #expect(EditorWindowController.clamped(NSRect(x: -50, y: 0, width: 3000, height: 2000), to: space) == space)
    }
}
