import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Identità persistenti e rimandi", .serialized)
struct ObjectReferenceTests {
    private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    @Test("Dal formato 18 al deposito, salvataggio 19 e riapertura con gli stessi identificatori")
    func migrateAndReopen() throws {
        let legacy = try DocumentFormat.document(from: """
        <document version="18" font="HoeflerText-Regular" size="12">
          <p>Testo<note>Nota</note></p><p/>
        </document>
        """)
        let store = DocumentStore(document: legacy)
        let ids = store.paragraphIDs.map(\.persistent)
        #expect(ids.count == 2 && Set(ids).count == 2)
        let note = try #require(FloatingIdentity.occurrences(in: store).first)
        let xml = DocumentFormat.string(for: store.document)
        #expect(xml.contains("version=\"19\""))
        let reopened = DocumentStore(document: try DocumentFormat.document(from: xml))
        #expect(reopened.paragraphIDs.map(\.persistent) == ids)
        #expect(FloatingIdentity.occurrences(in: reopened).first?.identity == note.identity)
        #expect(DocumentFormat.string(for: reopened.document) == xml)
        let empty = DocumentStore()
        let savedEmpty = try DocumentFormat.document(from: DocumentFormat.data(for: empty.document))
        #expect(DocumentStore(document: savedEmpty).paragraphIDs.map(\.persistent) == empty.paragraphIDs.map(\.persistent))
    }

    @Test("Il segno del capoverso non divide il tratto tipografico")
    func paragraphIdentityDoesNotSplitGlyphs() throws {
        let text = "ffi e ct all’inizio del capoverso."
        let style = CharacterStyle(fontName: body.fontName, size: 24, features: [.aat(type: 1, selector: 2)])
        let plain = Paragraph(inlines: [.text(TextRun(text, style: style))])
        var tagged = plain
        tagged.id = UUID()
        func layout(_ paragraph: Paragraph) -> DocumentLayout {
            let document = Document(blocks: [.paragraph(paragraph)])
            return PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
        }
        let original = try #require(layout(plain).pages.first?.lines.first)
        let migrated = try #require(layout(tagged).pages.first?.lines.first)
        #expect(Shaper.glyphs(in: original.line).map(\.id) == Shaper.glyphs(in: migrated.line).map(\.id))
        #expect(original.width == migrated.width)
    }

    @Test("Il numero segue il flottante e il rimando irrisolto conserva il suo bersaglio")
    func resolvesAfterMoveAndDelete() throws {
        let identity = FloatingIdentity(label: "Mare")
        var figure = FloatingObject(runs: [TextRun("Didascalia", style: body)], style: FloatStyle.figureName)
        figure.identity = identity
        var other = figure
        other.identity = FloatingIdentity(label: "Riva")
        let reference = ObjectReference(target: identity.id)
        let field = TextRun(Field.placeholder, style: body, field: .reference(reference))
        let intro = Paragraph(inlines: [.text(TextRun("Rimando ", style: body)), .text(field)])
        var document = Document(lists: [.figures], blocks: [
            .paragraph(intro), .paragraph(Paragraph(inlines: [.floating(other)])),
            .paragraph(Paragraph(inlines: [.floating(figure)]))
        ])
        document.floatStyles.append(.defaultFigure)
        func check(_ document: Document, _ expected: String) throws {
            let reopened = try DocumentFormat.document(from: DocumentFormat.data(for: document))
            let layout = PageLayout.layout(reopened.attributedString().text, options: reopened.layoutOptions)
            #expect(layout.referenceValue(reference) == expected)
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
            #expect(pdf.page(at: 0)?.string?.contains("Rimando " + expected) == true)
        }
        let format = ListDefinition.figures
        try check(document, format.prefix + format.counter.text(for: 2) + format.suffix)
        document.blocks.swapAt(1, 2)
        figure.identity?.label = "Etichetta nuova"
        document.blocks[1] = .paragraph(Paragraph(inlines: [.floating(figure)]))
        try check(document, format.prefix + format.counter.text(for: 1) + format.suffix)
        document.blocks.remove(at: 1)
        try check(document, "(??)")
    }

    @Test("Un rimando di pagina legge la pagina della figura, anche quando compare prima di essa")
    func pageOfFigure() throws {
        let identity = FloatingIdentity(label: "Mare")
        var figure = FloatingObject(runs: [TextRun("Didascalia", style: body)], style: FloatStyle.figureName)
        figure.identity = identity
        let field = ObjectReference(target: identity.id, reading: .page)
        var document = Document(lists: [.figures], blocks: [
            .paragraph(Paragraph(inlines: [.text(TextRun("A pagina ", style: body)),
                                           .text(TextRun(Field.placeholder, style: body, field: .reference(field)))]))
        ])
        document.floatStyles.append(.defaultFigure)
        document.sections = [Section(id: "chapter", role: "chapter",
                                     title: Paragraph(inlines: [.text(TextRun("Titolo", style: body))]),
                                     blocks: [.paragraph(Paragraph(inlines: [.floating(figure)]))], start: .newPage)]
        let layout = PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
        #expect(layout.referenceValue(field) == "2")
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        #expect(pdf.page(at: 0)?.string?.contains("A pagina 2") == true)
    }

    @Test("Il lettore separa le identità per tipo e rifiuta duplicati e attributi 19 nel formato 18")
    func strictFormat() throws {
        let id = UUID().uuidString
        let paragraph = "<p id=\"\(id)\"><note id=\"\(id)\" label=\"Mare\"/></p>"
        func read(_ version: Int, _ content: String) throws -> Document {
            try DocumentFormat.document(from: "<document version=\"\(version)\" font=\"HoeflerText-Regular\" size=\"12\">\(content)</document>")
        }
        #expect(try read(19, paragraph).flatParagraphs.first?.paragraph.id?.uuidString == id)
        #expect(throws: DocumentFormatError.self) { try read(18, paragraph) }
        #expect(throws: DocumentFormatError.self) { try read(19, paragraph + paragraph) }
        #expect(throws: DocumentFormatError.self) { try read(19, "<p><note id=\"\(id)\"/><note id=\"\(id)\"/></p>") }
        #expect(throws: DocumentFormatError.self) { try read(19, "<p><note label=\"Mare\"/></p>") }
        let target = UUID()
        let xml = "<p><field kind=\"reference\" target=\"\(target)\" read=\"page\"/></p>"
        let result = try read(19, xml).flatParagraphs.first?.paragraph.inlines.first
        guard case .text(let field)? = result else { Issue.record("Campo mancante"); return }
        #expect(field.field == .reference(ObjectReference(target: target, reading: .page)))
    }

    @Test("La copia rimappa il rimando interno e quello esterno resta locale al documento")
    func pasteMapping() throws {
        var note = FloatingObject(runs: [TextRun("Nota", style: body)])
        let identity = FloatingIdentity(label: "Mare")
        note.identity = identity
        let outside = UUID()
        let original = Document(blocks: [.paragraph(Paragraph(inlines: [.floating(note), .text(TextRun(" ", style: body))] +
            [identity.id, outside].map { .text(TextRun(Field.placeholder, style: body, field: .reference(ObjectReference(target: $0)))) }))])
        let source = original.attributedString().text
        for sameDocument in [true, false] {
            let copy = NSMutableAttributedString(attributedString: source)
            FloatingIdentity.preparePaste(copy, into: source, sameDocument: sameDocument)
            let pasted = try #require(FloatingIdentity.occurrences(in: copy).first?.identity)
            #expect(pasted.id != identity.id && pasted.label == "Mare (2)")
            var targets: [UUID] = []
            copy.enumerateAttribute(.field, in: NSRange(location: 0, length: copy.length)) { value, _, _ in
                if let value = value as? String, case .reference(let field)? = Field(encoded: value) { targets.append(field.target) }
            }
            #expect(targets.first == pasted.id)
            #expect((targets.last == outside) == sameDocument)
        }
    }
}
