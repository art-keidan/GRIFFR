import CoreText
import Foundation
import Testing
@testable import Typesetting

@Suite("Aggancio relativo per note dichiarate")
struct DeclaredNoteAnchorTests {
    @Test("La dichiarazione si salva e l'aggancio ereditato mantiene l'identità durante la scrittura")
    func inheritedDeclarationRoundTrip() throws {
        let id = UUID()
        let source = """
            <document version="22" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Base" target="paragraph"><declare-note id="\(id.uuidString)" word="5"/></style>
            <style name="Child" target="paragraph" based-on="Base"/>
            </styles>
            <p style="Child">uno due tre quattro</p>
            </document>
            """
        let original = try DocumentFormat.document(from: source)
        let xml = DocumentFormat.string(for: original)
        let restored = try DocumentFormat.document(from: xml)
        #expect(restored.styles == original.styles)
        #expect(xml.contains("version=\"22\""))
        #expect(throws: DocumentFormatError.self) {
            try DocumentFormat.document(from: source.replacingOccurrences(of: "version=\"22\"", with: "version=\"21\""))
        }
        #expect(throws: DocumentFormatError.self) {
            try DocumentFormat.document(from: source.replacingOccurrences(of: "word=\"5\"", with: "word=\"0\""))
        }
        let store = DocumentStore(document: restored)
        let paragraph = try #require(store.paragraphIDs.first)
        let before = try #require(store.declaredNotePositions(in: paragraph).first)
        #expect(before.slot.declaringStyle == "Base")
        #expect(before.slot.declaration == id)
        #expect(before.position == nil)
        let addition = NSAttributedString(string: " cinque", attributes: [.paragraphStyleName: "Child"])
        store.replaceCharacters(in: NSRange(location: store.length, length: 0), with: addition)
        let after = try #require(store.declaredNotePositions(in: paragraph).first)
        #expect(after.slot == before.slot)
        #expect(after.position == store.length)
    }

    @Test("La quinta parola scompare e riappare senza cambiare il testo")
    func relativeAnchor() {
        let selection = WordSelection(name: "Fifth", index: 5)
        let short = NSAttributedString(string: "uno due tre quattro\n")
        #expect(DeclaredNoteAnchor.position(in: short, paragraph: NSRange(location: 0, length: short.length), selection: selection) == nil)
        let full = NSAttributedString(string: "uno due tre quattro cinque sei\n")
        let before = full.string
        let expected = (full.string as NSString).range(of: "cinque")
        #expect(DeclaredNoteAnchor.position(in: full, paragraph: NSRange(location: 0, length: full.length), selection: selection) == NSMaxRange(expected))
        #expect(full.string == before)
    }

    @Test("La posizione è nel documento, anche con Unicode e un paragrafo precedente")
    func documentOffset() {
        let text = NSAttributedString(string: "altro\nuno due tre quattro 😀cinque, sei\n")
        let start = (text.string as NSString).range(of: "uno").location
        let paragraph = NSRange(location: start, length: text.length - start)
        let expected = (text.string as NSString).range(of: "cinque")
        #expect(DeclaredNoteAnchor.position(in: text, paragraph: paragraph, selection: WordSelection(name: "Fifth", index: 5)) == NSMaxRange(expected))
    }

    @Test("Il contenuto di una nota manuale non entra nel conteggio")
    func excludesNoteContent() {
        let text = NSMutableAttributedString(string: "uno due NOTA parole interne tre quattro cinque")
        let note = (text.string as NSString).range(of: "NOTA parole interne")
        text.addAttribute(.footnote, value: "manual", range: note)
        let expected = (text.string as NSString).range(of: "cinque")
        #expect(DeclaredNoteAnchor.position(in: text, paragraph: NSRange(location: 0, length: text.length), selection: WordSelection(name: "Fifth", index: 5)) == NSMaxRange(expected))
    }

    @Test("Intervalli e indici non validi non producono un aggancio")
    func invalidInputs() {
        let text = NSAttributedString(string: "uno due")
        let selection = WordSelection(name: "Invalid", index: 0)
        #expect(DeclaredNoteAnchor.position(in: text, paragraph: NSRange(location: 0, length: text.length), selection: selection) == nil)
        #expect(DeclaredNoteAnchor.position(in: text, paragraph: NSRange(location: text.length, length: 1), selection: selection) == nil)
    }

    /// Un documento con lo stile «Glossa», che dichiara una nota dopo la quinta parola, e i paragrafi dati.
    private func declaredDocument(_ paragraphs: [String], style: String? = nil, floatStyles: String = "") throws -> Document {
        let declaration = UUID()
        let styleAttribute = style.map { " style=\"\($0)\"" } ?? ""
        let body = paragraphs.map { "<p style=\"Glossa\">\($0)</p>" }.joined(separator: "\n")
        return try DocumentFormat.document(from: """
            <document version="22" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Glossa" target="paragraph"><declare-note id="\(declaration.uuidString)" word="5"\(styleAttribute)/></style>
            </styles>
            \(floatStyles)
            \(body)
            </document>
            """)
    }

    private func layout(_ document: Document) -> DocumentLayout {
        PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
    }

    @Test("La nota dichiarata si compone dopo la quinta parola; con quattro parole è sospesa e non consuma un numero")
    func composedProjection() throws {
        let present = layout(try declaredDocument(["uno due tre quattro cinque sei"]))
        let note = try #require(present.declaredNotes.first)
        #expect(present.declaredNotes.count == 1)
        #expect(note.mark == "1" && note.key < 0 && present.noteMarks[note.key] == "1")
        #expect(note.position == ("uno due tre quattro cinque" as NSString).length)
        #expect(note.declaringStyle == "Glossa")
        // Il richiamo e la nota sono composti, ma non sono testo: il cursore non entra in nessuna nota.
        #expect(present.notes.isEmpty)
        #expect(present.pages[0].lines.contains { $0.noteRange == NSRange(location: note.position, length: 0) })
        let withoutNote = layout(try declaredDocument(["uno due tre quattro"]))

        // Quattro parole: nessuna nota, nessun numero, nessuna riga di nota.
        #expect(withoutNote.declaredNotes.isEmpty)
        #expect(withoutNote.noteMarks.isEmpty)
        #expect(!withoutNote.pages[0].lines.contains { $0.noteRange != nil })
    }

    @Test("Le note dichiarate si numerano insieme a quelle scritte, nell'ordine dei richiami")
    func sharedNumbering() throws {
        let document = try declaredDocument([
            "uno<note>Scritta prima</note> due tre quattro cinque sei",
            "alfa beta gamma delta epsilon<note>Scritta dopo la quinta</note>",
        ])
        let result = layout(document)
        #expect(result.declaredNotes.map(\.mark) == ["2", "3"], "\(result.declaredNotes)")
        let written = result.noteMarks.filter { $0.key >= 0 }.sorted { $0.key < $1.key }.map(\.value)
        // La nota scritta subito dopo la quinta parola viene dopo quella dichiarata nello stesso punto.
        #expect(written == ["1", "4"], "\(result.noteMarks)")
        #expect(result.notes.count == 2, "solo le note scritte sono testo del documento")
    }

    @Test("Una serie a margine vale anche per le note dichiarate; una serie che non esiste non compone niente")
    func declaredSeries() throws {
        let margin = layout(try declaredDocument(["uno due tre quattro cinque sei"], style: "Glosse",
            floatStyles: "<float-styles>\n<float-style name=\"Glosse\" placement=\"margin\"/>\n</float-styles>"))
        #expect(margin.declaredNotes.count == 1)
        let unknown = layout(try declaredDocument(["uno due tre quattro cinque sei"], style: "Inesistente"))
        #expect(unknown.declaredNotes.isEmpty)
        // La serie si salva e torna.
        let document = try declaredDocument(["uno"], style: "Glosse",
            floatStyles: "<float-styles>\n<float-style name=\"Glosse\" placement=\"margin\"/>\n</float-styles>")
        let written = DocumentFormat.string(for: document)
        #expect(written.contains("style=\"Glosse\"/>"))
        #expect(try DocumentFormat.document(from: written).styles == document.styles)
    }

    @Test("Il testo di una nota dichiarata sta nel registro: si compone, resta quando la nota è sospesa, torna dal file e segue la rinomina dello stile")
    func registeredText() throws {
        var document = try declaredDocument(["uno due tre quattro cinque sei"])
        let declaration = try #require(document.styles.style(named: "Glossa")?.declaredNotes.first?.id)
        // Un capoverso del documento ha un'identità quando viene dall'editor; qui gliela si dà.
        let paragraphID = UUID()
        var paragraphs = document.flatParagraphs
        paragraphs[0].paragraph.id = paragraphID
        document.setFlatParagraphs(paragraphs)
        let slot = DeclaredNoteSlot(paragraph: paragraphID, declaringStyle: "Glossa", declaration: declaration)
        document.declaredNoteTexts[slot] = "Glossa dell'autore"

        let present = layout(document)
        let placed = try #require(present.declaredNotes.first)
        #expect(placed.paragraphID == paragraphID)
        let noteLine = try #require(present.pages[0].lines.first { $0.noteRange != nil })
        let shown = (CTLineGetGlyphRuns(noteLine.line) as? [CTRun] ?? []).reduce(0) { $0 + CTRunGetGlyphCount($1) }
        #expect(shown > "1 Glossa".count, "la riga della nota porta il numero e il testo")

        // Il file lo conserva, con il formato 22, e la riapertura lo ritrova.
        let written = DocumentFormat.string(for: document)
        #expect(written.contains("<declared-note paragraph=\"\(paragraphID.uuidString)\" style=\"Glossa\""))
        #expect(written.contains("text=\"Glossa dell&apos;autore\"") || written.contains("text=\"Glossa dell'autore\""))
        let reopened = try DocumentFormat.document(from: written)
        #expect(reopened.declaredNoteTexts == document.declaredNoteTexts)
        #expect(throws: DocumentFormatError.self) {
            try DocumentFormat.document(from: written.replacingOccurrences(of: "<document version=\"22\"", with: "<document version=\"21\""))
        }

        // Con quattro parole la nota è sospesa: niente richiamo, ma il testo resta nel registro.
        var shorter = document
        var short = shorter.flatParagraphs
        short[0].paragraph.inlines = [.text(TextRun("uno due tre quattro", style: TextStyling.styleBase))]
        shorter.setFlatParagraphs(short)
        #expect(layout(shorter).declaredNotes.isEmpty)
        #expect(shorter.declaredNoteTexts[slot] == "Glossa dell'autore")

        // Rinominare lo stile non stacca il testo dalla sua nota.
        let renamed = document.renamingStyle("Glossa", to: "Glossa marginale")
        let renamedSlot = DeclaredNoteSlot(paragraph: paragraphID, declaringStyle: "Glossa marginale", declaration: declaration)
        #expect(renamed.declaredNoteTexts == [renamedSlot: "Glossa dell'autore"])
    }

    @Test("Un rimando a una nota dichiarata legge il suo numero e la sua pagina, si salva e torna; con la nota sospesa legge (??)")
    func referenceToDeclaredNote() throws {
        let declaration = UUID(), paragraph = UUID()
        func source(_ first: String) -> String {
            """
            <document version="22" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Glossa" target="paragraph"><declare-note id="\(declaration.uuidString)" word="5"/></style>
            </styles>
            <p>Prima<note>Una nota scritta.</note> di tutto.</p>
            <p id="\(paragraph.uuidString)" style="Glossa">\(first)</p>
            <p>Vedi la nota <field kind="reference" target="\(declaration.uuidString)" read="number" paragraph="\(paragraph.uuidString)" declaring-style="Glossa"/>, a pagina <field kind="reference" target="\(declaration.uuidString)" read="page" paragraph="\(paragraph.uuidString)" declaring-style="Glossa"/>.</p>
            </document>
            """
        }
        let document = try DocumentFormat.document(from: source("uno due tre quattro cinque sei"))
        let slot = DeclaredNoteSlot(paragraph: paragraph, declaringStyle: "Glossa", declaration: declaration)
        let number = ObjectReference(declaredNote: slot), page = ObjectReference(declaredNote: slot, reading: .page)
        let result = layout(document)
        // La nota scritta prima è la 1: quella dichiarata è la 2.
        #expect(result.referenceValue(number) == "2")
        #expect(result.referenceValue(page) == "1")

        // Il campo come attributo del testo e nel file.
        #expect(Field(encoded: Field.reference(number).encoded) == .reference(number))
        #expect(Field(encoded: Field.reference(ObjectReference(target: declaration)).encoded) == .reference(ObjectReference(target: declaration)))
        let written = DocumentFormat.string(for: document)
        #expect(written.contains("declaring-style=\"Glossa\""))
        #expect(try DocumentFormat.document(from: written) == document)
        #expect(throws: DocumentFormatError.self) {
            try DocumentFormat.document(from: source("uno").replacingOccurrences(of: " declaring-style=\"Glossa\"", with: ""))
        }

        // Con quattro parole la nota è sospesa: il rimando non ha un numero da leggere.
        let suspended = layout(try DocumentFormat.document(from: source("uno due tre quattro")))
        #expect(suspended.referenceValue(number) == "(??)")

        // Rinominare lo stile nel testo: il rimando segue; uno stile tolto lascia il rimando com'è.
        let text = NSMutableAttributedString(string: Field.placeholder, attributes: [.field: Field.reference(number).encoded])
        ObjectReference.renameDeclaringStyles(in: text, ["Glossa": "Glossa marginale"])
        let renamed = DeclaredNoteSlot(paragraph: paragraph, declaringStyle: "Glossa marginale", declaration: declaration)
        #expect(text.attribute(.field, at: 0, effectiveRange: nil) as? String == Field.reference(ObjectReference(declaredNote: renamed)).encoded)
        ObjectReference.renameDeclaringStyles(in: text, ["Glossa marginale": nil])
        #expect(text.attribute(.field, at: 0, effectiveRange: nil) as? String == Field.reference(ObjectReference(declaredNote: renamed)).encoded)
    }
}

