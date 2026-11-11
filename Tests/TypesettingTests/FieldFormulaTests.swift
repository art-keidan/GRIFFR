import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Campi formula", .serialized)
struct FieldFormulaTests {
    private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    @Test("Ogni formula va e torna dall'attributo del testo; le forme storiche non si leggono più")
    func encoding() {
        let all: [FieldFormula] = [.pageContainingNumber, .documentPageCount,
                                   .sectionContainingTitle(role: "chapter"), .sectionContainingNumber(role: "parte prima")]
        for formula in all {
            #expect(Field(encoded: Field.formula(formula).encoded) == .formula(formula))
            #expect(FieldFormula(expression: formula.expression, role: formula.role) == formula)
        }
        #expect(Field(encoded: "page") == nil && Field(encoded: "pages") == nil && Field(encoded: "section-title\ncapitolo") == nil)
        #expect(Field.page == .formula(.pageContainingNumber), "«page» è solo un modo breve di scrivere la formula")
        #expect(FieldFormula(expression: "position.section-containing.title.write-here") == nil, "senza ruolo")
        #expect(Field(encoded: "formula\nposition.ovunque") == nil)
    }

    @Test("Nel file ogni campo è una formula; i tipi storici sono un errore")
    func fileForm() throws {
        func run(_ field: Field?, _ text: String = Field.placeholder) -> Inline { .text(TextRun(text, style: body, field: field)) }
        let document = Document(blocks: [.paragraph(Paragraph(inlines: [
            run(nil, "Pagina "), run(.page), run(nil, " di "), run(.pageCount), run(nil, ", "), run(.sectionTitle(role: "chapter"))]))])
        let written = DocumentFormat.string(for: document)
        #expect(written.contains("expression=\"document.page-count.write-here\"") && !written.contains("kind=\"page\""))
        let again = try DocumentFormat.document(from: written)
        #expect(DocumentFormat.string(for: again) == written)
        let old = written.replacingOccurrences(of: "kind=\"formula\" expression=\"position.page-containing.number.write-here\"", with: "kind=\"page\"")
        #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: old) }
    }

    @Test("Nel testo composto: pagine totali, titolo e numero della sezione contenente; ricomporre non duplica nulla")
    func composition() throws {
        func field(_ formula: FieldFormula) -> Inline { .text(TextRun(Field.placeholder, style: body, field: .formula(formula))) }
        func text(_ string: String) -> Inline { .text(TextRun(string, style: body)) }
        let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 120)
        var document = Document(lists: [ListDefinition(name: "Capitoli", counter: .decimal, numbersSections: "chapter")],
                                blocks: [.paragraph(Paragraph(inlines: [text("Premessa di "), field(.documentPageCount), text(" pagine.")]))])
        document.sections = [Section(id: "c1", role: "chapter", title: Paragraph(inlines: [text("Il mare")]),
                                     blocks: [.paragraph(Paragraph(inlines: [text("Qui: "), field(.sectionContainingTitle(role: "chapter")),
                                                                              text(", capitolo "), field(.sectionContainingNumber(role: "chapter")),
                                                                              text(", pagina "), field(.pageContainingNumber), text(".")])),
                                              .paragraph(Paragraph(inlines: [text(long)]))],
                                     start: .newPage)]
        let attributed = document.attributedString().text
        let fieldCount = { (text: NSAttributedString) -> Int in
            var n = 0
            text.enumerateAttribute(.field, in: NSRange(location: 0, length: text.length)) { value, _, _ in if value != nil { n += 1 } }
            return n
        }
        #expect(fieldCount(attributed) == 4)
        let layout = PageLayout.layout(attributed, setup: document.pageSetup, options: document.layoutOptions)
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        let all = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        #expect(all.contains("Premessa di \(layout.pages.count) pagine."), "\(all)")
        #expect(all.contains("Qui: Il mare, capitolo 1, pagina 2."), "\(all)")
        // Ricomporre, salvare e riaprire non cambia il numero dei campi.
        _ = PageLayout.layout(attributed, setup: document.pageSetup, options: document.layoutOptions)
        let reopened = try DocumentFormat.document(from: DocumentFormat.string(for: Document(attributedString: attributed, settings: document.settingsOnly)))
        #expect(fieldCount(reopened.attributedString().text) == 4)
    }

    @Test("La catena si legge passo per passo: le formule pronte sono catene, le altre si spiegano; il valore segue l'ultimo oggetto")
    func chain() throws {
        // Le formule pronte sono catene come le altre, e il file le scrive come prima.
        #expect(FieldFormula.pageContainingNumber == FieldFormula(origin: .position, steps: [.containingPage], reading: .number))
        #expect(FieldFormula.pageContainingNumber.expression == "position.page-containing.number.write-here")
        #expect(FieldFormula.documentPageCount.expression == "document.page-count.write-here")
        #expect(FieldFormula.sectionContainingNumber(role: "part").expression == "position.section-containing.number.write-here")
        #expect(FieldFormula.sectionContainingTitle(role: "chapter").chain == "Position → Containing section (chapter) → Title")
        #expect(FieldFormula.sectionContainingTitle(role: "chapter").title == "Title of the current section: chapter")
        // Ogni passo deve partire dall'oggetto raggiunto; il risultato deve essere dell'ultimo.
        #expect(FieldFormula(origin: .document, steps: [.containingPage], reading: .number).problem != nil, "il documento non sta in una pagina")
        #expect(FieldFormula(origin: .position, steps: [.containingPage], reading: .title).problem?.contains("page") == true)
        #expect(FieldFormula(origin: .position, reading: .number).problem?.contains("add a step") == true)
        #expect(FieldFormula(origin: .position, steps: [.containingSection(role: " ")], reading: .title).problem?.contains("role") == true)
        #expect(FieldFormula(origin: .position, steps: [.containingPage, .containingPage], reading: .number).problem != nil)
        // Il file: le catene sbagliate, i ruoli mancanti o in più non si leggono.
        #expect(FieldFormula(expression: "document.page-containing.number.write-here") == nil)
        #expect(FieldFormula(expression: "position.page-containing.number.write-here", role: "chapter") == nil, "un ruolo senza sezione")
        #expect(FieldFormula(expression: "position.page-containing.number") == nil, "senza «write-here»")
        // Il valore: dall'oggetto a cui la catena arriva.
        let context = FieldContext(pageNumber: "iv", pageCount: "12", sections: [
            .init(role: "part", title: "Prima parte", number: "I"), .init(role: "chapter", title: "Il mare", number: "3"),
            .init(role: "chapter", title: "Interno", number: nil)])
        #expect(FieldFormula.pageContainingNumber.value(in: context) == "iv")
        #expect(FieldFormula.documentPageCount.value(in: context) == "12")
        #expect(FieldFormula.sectionContainingTitle(role: "part").value(in: context) == "Prima parte")
        #expect(FieldFormula.sectionContainingTitle(role: "chapter").value(in: context) == "Interno", "la più interna del ruolo")
        #expect(FieldFormula.sectionContainingNumber(role: "chapter").value(in: context) == "", "una sezione senza numero")
        #expect(FieldFormula.sectionContainingTitle(role: "appendix").value(in: context) == "")
        #expect(FieldFormula(origin: .document, steps: [.containingPage], reading: .number).value(in: context) == "", "una catena sbagliata non scrive")
    }

    @Test("Ciò che un campo legge in un punto della composizione: pagina, pagine e sezioni che lo contengono")
    func contextAtPosition() throws {
        func text(_ string: String) -> Inline { .text(TextRun(string, style: body)) }
        let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 120)
        var document = Document(lists: [ListDefinition(name: "Capitoli", counter: .decimal, numbersSections: "chapter")],
                                blocks: [.paragraph(Paragraph(inlines: [text("Premessa.")]))])
        document.sections = [Section(id: "c1", role: "chapter", title: Paragraph(inlines: [text("Il mare")]),
                                     blocks: [.paragraph(Paragraph(inlines: [text(long)])), .paragraph(Paragraph(inlines: [text("Fine.")]))],
                                     start: .newPage)]
        let attributed = document.attributedString().text
        let layout = PageLayout.layout(attributed, setup: document.pageSetup, options: document.layoutOptions)
        let start = layout.fieldContext(at: 2)
        #expect(start.pageNumber == "1" && start.sections.isEmpty)
        let end = layout.fieldContext(at: attributed.length - 2)
        #expect(end.pageCount == String(layout.pages.count) && end.pageNumber == layout.pages.last?.number)
        #expect(end.sections == [FieldContext.Section(role: "chapter", title: "Il mare", number: "1")])
    }

    @Test("Il campo in un capoverso spezzato legge la pagina della propria riga")
    func fieldAfterPageBreak() throws {
        let field = Inline.text(TextRun(Field.placeholder, style: body, field: .page))
        var document = Document(blocks: [.paragraph(Paragraph(inlines: [
            .text(TextRun("Prima \u{2028}Seconda ", style: body)), field
        ]))])
        document.pageSetup = PageSetup(paperSize: CGSize(width: 280, height: 62), top: 20, bottom: 20, left: 20, right: 28, facing: true)
        let text = document.attributedString().text
        let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
        #expect(layout.pages.count == 2)
        let index = (text.string as NSString).range(of: Field.placeholder).location
        #expect(layout.pages.firstIndex { $0.fieldRects.contains { $0.location == index } } == 1)
        #expect(layout.fieldContext(at: index).pageNumber == "2")
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        #expect(pdf.page(at: 1)?.string?.contains("Seconda 2") == true)
    }

    @Test("Un campo alla fine del capoverso scrive il numero una sola volta")
    func fieldBeforeParagraphSeparator() throws {
        let document = Document(blocks: [
            .paragraph(Paragraph(inlines: [.text(TextRun("Pagina ", style: body)),
                                           .text(TextRun(Field.placeholder, style: body, field: .page))])),
            .paragraph(Paragraph(inlines: [.text(TextRun("Segue.", style: body))]))
        ])
        let source = document.attributedString().text
        let end = (source.string as NSString).range(of: "\n").location
        #expect(source.attribute(.field, at: end, effectiveRange: nil) == nil)
        let layout = PageLayout.layout(source, setup: document.pageSetup, options: document.layoutOptions)
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        #expect(pdf.page(at: 0)?.string?.contains("Pagina 1\nSegue.") == true)
    }

    @Test("Il segnaposto di un campo non è una sostituzione del font; il testo calcolato ha la sua cornice e non è un richiamo")
    func placeholderAndFrame() throws {
        func text(_ string: String) -> Inline { .text(TextRun(string, style: body)) }
        let document = Document(blocks: [.paragraph(Paragraph(inlines: [text("Pagina "), .text(TextRun(Field.placeholder, style: body, field: .page)),
                                                                        text(" di tutto.")]))])
        let attributed = document.attributedString().text
        let field = (attributed.string as NSString).range(of: Field.placeholder).location
        #expect(field == 7)
        // Il menu del font guarda il testo del documento: il segnaposto c'è, ma non conta.
        #expect(FontFallback.fallbackFamilies(in: attributed, range: NSRange(location: 0, length: attributed.length)).isEmpty)
        #expect(FontFallback.fallbackFamilies(in: attributed, range: NSRange(location: field, length: 1)).isEmpty)
        let bare = NSMutableAttributedString(attributedString: attributed)
        bare.removeAttribute(.field, range: NSRange(location: 0, length: bare.length))
        #expect(!FontFallback.fallbackFamilies(in: bare, range: NSRange(location: field, length: 1)).isEmpty,
                "senza il segno di campo, lo stesso carattere chiede un ripiego: è il caso segnalato prima")
        // Sulla pagina il campo scrive «1»: la sua cornice sta dove sta quel testo, fra «Pagina » e « di».
        let layout = PageLayout.layout(attributed, setup: document.pageSetup, options: document.layoutOptions)
        let frames = layout.pages[0].fieldRects
        #expect(frames.count == 1 && frames.first?.location == field)
        let frame = try #require(frames.first?.rect)
        let line = try #require(layout.pages[0].lines.first)
        #expect(frame.width > 1 && frame.minX > line.origin.x + 10 && frame.maxX < line.origin.x + line.width)
        #expect(!layout.invisibleMarks(onPage: 0).contains { $0.kind == .noteReference }, "il campo non si segna come un richiamo")
        // Nel PDF nessuna traccia: il testo è quello di sempre.
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        #expect(pdf.page(at: 0)?.string?.contains("Pagina 1 di tutto.") == true)
    }
}
