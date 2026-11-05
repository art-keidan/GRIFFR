import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Testate di capitolo")
struct HeadingCompositionTests {
    private let mm = 72 / 25.4
    private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    /// Un capitolo con il titolo nello stile «Titolo capitolo» e un corpo; la Lista «Capitoli» numera i capitoli.
    private func book(title: String, heading: HeadingComposition?, facing: Bool = false, chapters: Int = 1, opening: Double? = nil) -> Document {
        var sheet = StyleSheet.builtIn
        var values = StyleValues()
        values.size = 20
        values.spaceBefore = 0
        values.spaceAfter = 0
        values.opensSection = "capitolo"
        values.openingDistance = opening
        sheet.styles.append(NamedStyle(name: "Titolo capitolo", target: .paragraph, basedOn: "Testo", values: values, heading: heading))
        func paragraph(_ string: String, _ style: String) -> Paragraph {
            Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style),
                      inlines: [.text(TextRun(string, style: sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: body)))])
        }
        let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 60)
        var document = Document(styles: sheet, lists: ListDefinition.builtIn + [ListDefinition(name: "Capitoli", counter: .decimal, continues: true, numbersSections: "capitolo")],
                                blocks: [])
        document.pageSetup = PageSetup(paperSize: PageSetup.a4.paperSize, top: 72, bottom: 72, left: 72, right: 90, facing: facing)
        document.sections = (1...chapters).map { n in
            Section(id: "c\(n)", role: "capitolo", title: paragraph(title, "Titolo capitolo"),
                    blocks: [.paragraph(paragraph(long, "Testo"))], start: .newPage)
        }
        return document
    }

    private func layout(_ document: Document) -> DocumentLayout {
        PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
    }

    /// Dal margine superiore alla linea di base della prima riga del corpo del capitolo `n` (da 0), sulla sua pagina.
    private func bodyTop(_ layout: DocumentLayout, chapter n: Int = 0) throws -> (page: Int, top: CGFloat) {
        let marker = "Una frase"
        var seen = 0
        for (index, page) in layout.pages.enumerated() {
            for line in page.lines where (layout.text.string as NSString).substring(with: line.range).hasPrefix(marker) {
                if seen == n { return (index, page.setup.paperSize.height - page.setup.top - line.origin.y) }
                seen += 1
                break
            }
        }
        throw CancellationError()
    }

    @Test("Numero in una fascia di 12 mm, 3 mm, filetto 0,5 mm, 2,5 mm, titolo, 8 mm: il corpo scende di 26 mm, il filetto sta al suo posto")
    func guideCase() throws {
        let plain = try bodyTop(layout(book(title: "Il mare", heading: nil)))
        let composed = layout(book(title: "Il mare", heading: .standard))
        let headed = try bodyTop(composed)
        #expect(abs((headed.top - plain.top) - 26 * mm) < 0.01, "\(headed.top - plain.top) invece di \(26 * mm)")
        // Il filetto: dopo 12 + 3 mm dal sommo della testata, spesso 0,5 mm, largo quanto lo specchio.
        let page = composed.pages[headed.page]
        let column = page.setup.textRect(forPage: headed.page)
        let rule = try #require(page.rules.first { abs($0.height - 0.5 * mm) < 0.001 })
        #expect(abs((column.maxY - rule.maxY) - 15 * mm) < 0.01)
        #expect(abs(rule.width - column.width) < 0.01)
    }

    @Test("Un titolo di tre righe abbassa il corpo quanto le due righe in più, come senza testata; il titolo resta uno")
    func longTitle() throws {
        let longTitle = String(repeating: "Un titolo molto lungo che va a capo ", count: 4)
        let plainShift = try bodyTop(layout(book(title: longTitle, heading: nil))).top - bodyTop(layout(book(title: "Il mare", heading: nil))).top
        let headedShift = try bodyTop(layout(book(title: longTitle, heading: .standard))).top - bodyTop(layout(book(title: "Il mare", heading: .standard))).top
        #expect(plainShift > 0)
        #expect(abs(headedShift - plainShift) < 0.01)
        let document = book(title: longTitle, heading: .standard)
        #expect(document.flatParagraphs.filter { $0.paragraph.styleName == "Titolo capitolo" }.count == 1)
    }

    @Test("Il numero compare una volta sola, sul lato esterno: a destra sulle dispari, a sinistra sulle pari")
    func numberOnceOutside() throws {
        let composed = layout(book(title: "Il mare", heading: .standard, facing: true, chapters: 2))
        let text = composed.text.string as NSString
        for chapter in 0..<2 {
            let (index, _) = try bodyTop(composed, chapter: chapter)
            let page = composed.pages[index]
            let titleLine = try #require(page.lines.first { text.substring(with: $0.range).hasPrefix("Il mare") })
            let markers = page.markers.filter { $0.paragraphLocation == titleLine.paragraphLocation }
            #expect(markers.count == 1, "solo il numero della testata, non anche il segno della Lista")
            let column = page.setup.textRect(forPage: index)
            let width = CGFloat(CTLineGetTypographicBounds(try #require(markers.first).line, nil, nil, nil))
            let left = page.setup.facing && index % 2 == 1
            if left { #expect(abs(markers[0].origin.x - column.minX) < 0.01, "pagina pari: a sinistra") }
            else { #expect(abs(markers[0].origin.x - (column.maxX - width)) < 0.01, "pagina dispari: a destra") }
        }
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: composed)))
        let all = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        #expect(all.contains("1\nIl mare") && all.contains("2\nIl mare"), "il numero, poi il titolo")
    }

    @Test("Con la distanza d'apertura di 30 mm la testata comincia a 30 mm, il suo filetto a 45 mm: conta il blocco intero")
    func openingDistance() throws {
        let composed = layout(book(title: "Il mare", heading: .standard, opening: 30 * mm))
        let plain = layout(book(title: "Il mare", heading: .standard))
        let shift = try bodyTop(composed).top - bodyTop(plain).top
        #expect(abs(shift - 30 * mm) < 0.01, "il blocco scende di 30 mm: \(shift / mm) mm")
        let index = try bodyTop(composed).page
        let page = composed.pages[index]
        let column = page.setup.textRect(forPage: index)
        let rule = try #require(page.rules.first { abs($0.height - 0.5 * mm) < 0.001 })
        #expect(abs((column.maxY - rule.maxY) - 45 * mm) < 0.01, "30 + 12 + 3 mm")
    }

    @Test("La testata si salva nel formato 14 e torna uguale; una versione precedente non la accetta")
    func roundTrip() throws {
        var heading = HeadingComposition.standard
        heading.parts.insert(.label(text: "Capitolo", style: nil, alignment: .center, minHeight: nil), at: 0)
        let document = book(title: "Il mare", heading: heading)
        let xml = DocumentFormat.string(for: document)
        #expect(xml.contains("version=\"14\"") && xml.contains("<heading encoding=\"json-v1\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.style(named: "Titolo capitolo")?.heading == heading)
        #expect(DocumentFormat.string(for: read) == xml)
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"14\"", with: "version=\"13\"")) }
        var bad = heading
        bad.parts.append(.title)
        #expect(bad.problem != nil)
    }
}
