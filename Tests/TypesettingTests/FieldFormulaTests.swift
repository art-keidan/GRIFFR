import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Campi formula", .serialized)
struct FieldFormulaTests {
    private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    @Test("Ogni formula va e torna dall'attributo del testo; le forme storiche diventano formule")
    func encoding() {
        let all: [FieldFormula] = [.pageContainingNumber, .documentPageCount,
                                   .sectionContainingTitle(role: "chapter"), .sectionContainingNumber(role: "parte prima")]
        for formula in all {
            #expect(Field(encoded: Field.formula(formula).encoded) == .formula(formula))
            #expect(FieldFormula(expression: formula.expression, role: formula.role) == formula)
        }
        #expect(Field(encoded: "page")?.asFormula == .pageContainingNumber)
        #expect(Field(encoded: "pages")?.asFormula == .documentPageCount)
        #expect(Field(encoded: "section-title\ncapitolo")?.asFormula == .sectionContainingTitle(role: "capitolo"))
        #expect(Field.page == .formula(.pageContainingNumber), "un campo storico e la sua formula sono lo stesso campo")
        #expect(FieldFormula(expression: "position.section-containing.title.write-here") == nil, "senza ruolo")
        #expect(Field(encoded: "formula\nposition.ovunque") == nil)
    }

    @Test("Un documento di prima si apre con campi formula e si salva nel formato 13; la versione 12 non le accetta")
    func conversion() throws {
        // Un file di prima: quello che si scrive oggi, con i tipi storici al posto delle formule e la versione 8.
        func run(_ field: Field?, _ text: String = Field.placeholder) -> Inline { .text(TextRun(text, style: body, field: field)) }
        let modern = DocumentFormat.string(for: Document(blocks: [.paragraph(Paragraph(inlines: [
            run(nil, "Pagina "), run(.page), run(nil, " di "), run(.pageCount), run(nil, ", "), run(.sectionTitle(role: "chapter"))]))]))
        let old = modern
            .replacingOccurrences(of: "kind=\"formula\" expression=\"position.page-containing.number.write-here\"", with: "kind=\"page\"")
            .replacingOccurrences(of: "kind=\"formula\" expression=\"document.page-count.write-here\"", with: "kind=\"pages\"")
            .replacingOccurrences(of: "kind=\"formula\" expression=\"position.section-containing.title.write-here\"", with: "kind=\"section-title\"")
            .replacingOccurrences(of: "version=\"13\"", with: "version=\"8\"")
        #expect(old.contains("kind=\"page\"") && old.contains("kind=\"section-title\" role=\"chapter\"") && old.contains("version=\"8\""))
        let read = try DocumentFormat.document(from: old)
        let fields = read.flatParagraphs.flatMap { $0.paragraph.inlines.compactMap { if case .text(let run) = $0 { run.field } else { nil } } }
        #expect(fields.map(\.asFormula) == [.pageContainingNumber, .documentPageCount, .sectionContainingTitle(role: "chapter")])
        let written = DocumentFormat.string(for: read)
        #expect(written.contains("version=\"13\""))
        #expect(!written.contains("kind=\"page\"") && !written.contains("kind=\"pages\"") && !written.contains("kind=\"section-title\""))
        #expect(written.contains("expression=\"document.page-count.write-here\""))
        // Riaperto e riscritto: lo stesso file, nessun campo in più.
        let again = try DocumentFormat.document(from: written)
        #expect(DocumentFormat.string(for: again) == written)
        #expect(again.blocks == read.blocks)
        let older = written.replacingOccurrences(of: "version=\"13\"", with: "version=\"12\"")
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: older) }
        // Il solo numero di pagina basta il formato 9.
        let pageOnly = DocumentFormat.string(for: Document(blocks: [.paragraph(Paragraph(inlines: [run(.page)]))]))
        #expect(pageOnly.contains("version=\"9\""))
        #expect((try? DocumentFormat.document(from: pageOnly)) != nil)
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
}
