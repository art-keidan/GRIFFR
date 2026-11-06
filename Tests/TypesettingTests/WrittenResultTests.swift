import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Scrivi risultato nel paragrafo", .serialized)
struct WrittenResultTests {
    private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    /// Un capitolo «Il mare» con due paragrafi nello stile «Rimando», che scrive ciò che `writes` chiede, e uno in «Body».
    private func document(_ writes: [WrittenResult], note: Bool = false, middle: String = "Il testo del rimando.") -> Document {
        var sheet = StyleSheet.builtIn
        sheet.styles.append(NamedStyle(name: "Rimando", target: .paragraph, basedOn: "Body", writes: writes))
        sheet.styles.append(NamedStyle(name: "Rimando derivato", target: .paragraph, basedOn: "Rimando"))
        func run(_ string: String, _ style: String) -> Inline {
            .text(TextRun(string, style: sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: body)))
        }
        func paragraph(_ string: String, _ style: String, note: Bool = false) -> Paragraph {
            var inlines = [run(string, style)]
            if note { inlines.append(.floating(FloatingObject(runs: [TextRun("Una nota.", style: body)]))) }
            return Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style), inlines: inlines)
        }
        var document = Document(styles: sheet, blocks: [])
        document.sections = [Section(id: "c1", role: "chapter", title: paragraph("Il mare", "Heading 1"),
                                     blocks: [.paragraph(paragraph(middle, "Rimando", note: note)), .paragraph(paragraph("Un altro.", "Rimando derivato")),
                                              .paragraph(paragraph("Normale.", "Body"))])]
        return document
    }

    private func layout(_ document: Document) -> DocumentLayout {
        PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
    }

    private func pdfText(_ layout: DocumentLayout) throws -> String {
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test("Prima e dopo il testo: il titolo della sezione e la pagina; lo stile derivato eredita; il documento non cambia")
    func beforeAndAfter() throws {
        let writes = [WrittenResult(formula: .sectionContainingTitle(role: "chapter"), place: .before, prefix: "[", suffix: "] "),
                      WrittenResult(formula: .pageContainingNumber, place: .after, prefix: " (p. ", suffix: ")")]
        let document = document(writes)
        let composed = layout(document)
        let text = try pdfText(composed)
        #expect(text.contains("[Il mare] Il testo del rimando. (p. 1)"), "\(text)")
        #expect(text.contains("[Il mare] Un altro. (p. 1)"), "lo stile derivato scrive come quello su cui si basa")
        #expect(text.contains("Normale.") && !text.contains("[Il mare] Normale."))
        #expect(!composed.text.string.contains("[Il mare]"), "il testo scritto non entra nel documento")
        // Il cursore non entra nel testo scritto: l'inizio del paragrafo sta dopo «[Il mare] », la fine prima di « (p. 1)».
        let start = (composed.text.string as NSString).range(of: "Il testo").location
        let line = try #require(composed.pages[0].lines.first { $0.range.location == start })
        #expect(line.documentIndex(forString: 0) == start)
        let caretStart = try #require(composed.caret(at: start)), caretAfterOne = try #require(composed.caret(at: start + 1))
        #expect(caretStart.rect.minX > line.origin.x + 10, "il cursore all'inizio del testo, dopo il risultato")
        #expect(caretAfterOne.rect.minX > caretStart.rect.minX)
        let end = start + ("Il testo del rimando." as NSString).length
        let caretEnd = try #require(composed.caret(at: end))
        #expect(caretEnd.rect.minX < line.origin.x + line.width - 10, "la fine del testo, prima di « (p. 1)»")
    }

    @Test("Un risultato vuoto non scrive niente, nemmeno il testo fisso; una nota dopo il risultato «prima» resta sulla sua riga")
    func emptyAndNotes() throws {
        let missing = layout(document([WrittenResult(formula: .sectionContainingTitle(role: "part"), place: .before, prefix: "Part ", suffix: ": ")]))
        #expect(!(try pdfText(missing)).contains("Part"))
        let noted = layout(document([WrittenResult(formula: .sectionContainingNumber(role: "chapter"), place: .before, prefix: "§ ", suffix: " ")], note: true))
        let text = try pdfText(noted)
        #expect(text.contains("Una nota."), "la nota a piè di pagina c'è ancora: \(text)")
        // Lo stesso numero di richiamo, prima e dopo che il risultato sposti il testo.
        let plain = layout(document([], note: true))
        #expect(noted.pages.count == plain.pages.count)
    }

    @Test("Un testo lungo dopo il risultato va a capo con lui: le righe tengono la misura")
    func wrapping() throws {
        let long = String(repeating: "Una frase abbastanza lunga da andare a capo. ", count: 8)
        let composed = layout(document([WrittenResult(formula: .sectionContainingTitle(role: "chapter"), place: .before, prefix: "Nel capitolo «", suffix: "»: ")],
                                       middle: long))
        let start = (composed.text.string as NSString).range(of: "Una frase").location
        let lines = composed.pages[0].lines.filter { NSLocationInRange($0.range.location, NSRange(location: start, length: (long as NSString).length)) }
        #expect(lines.count > 2)
        #expect(lines.allSatisfy { $0.width <= $0.availableWidth + 0.5 })
        #expect(lines.first?.range.location == start)
    }

    @Test("Le azioni si salvano nel formato 16 e rileggono uguali; le versioni di prima non le accettano")
    func format() throws {
        let writes = [WrittenResult(formula: .sectionContainingNumber(role: "chapter"), place: .before, prefix: "§ ", suffix: " ", style: "Emphasis"),
                      WrittenResult(formula: .documentPageCount, place: .after, prefix: " / ")]
        let xml = DocumentFormat.string(for: document(writes))
        #expect(xml.contains("version=\"16\"") && xml.contains("<writes encoding=\"json-v1\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.style(named: "Rimando")?.writes == writes)
        #expect(DocumentFormat.string(for: read) == xml)
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"16\"", with: "version=\"15\"")) }
        #expect(WrittenResult(formula: .pageContainingNumber, place: .after, prefix: "a\nb").problem != nil)
    }
}
