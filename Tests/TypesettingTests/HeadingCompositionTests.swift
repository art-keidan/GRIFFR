import AppKit
import PDFKit
import Testing
@testable import Typesetting

@Suite("Testate di capitolo", .serialized)
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
        values.opensSection = "chapter"
        values.openingDistance = opening
        sheet.styles.append(NamedStyle(name: "Titolo capitolo", target: .paragraph, basedOn: "Body", values: values, heading: heading))
        func paragraph(_ string: String, _ style: String) -> Paragraph {
            Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style),
                      inlines: [.text(TextRun(string, style: sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: body)))])
        }
        let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 60)
        var document = Document(styles: sheet, lists: ListDefinition.builtIn + [ListDefinition(name: "Capitoli", counter: .decimal, continues: true, numbersSections: "chapter")],
                                blocks: [])
        document.pageSetup = PageSetup(paperSize: PageSetup.a4.paperSize, top: 72, bottom: 72, left: 72, right: 90, facing: facing)
        document.sections = (1...chapters).map { n in
            Section(id: "c\(n)", role: "chapter", title: paragraph(title, "Titolo capitolo"),
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
        #expect(xml.contains("version=\"18\"") && xml.contains("<heading encoding=\"json-v1\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.style(named: "Titolo capitolo")?.heading == heading)
        #expect(DocumentFormat.string(for: read) == xml)
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"13\"")) }
        var bad = heading
        bad.parts.append(.plainTitle)
        #expect(bad.problem != nil)
    }

    // MARK: Numero accanto, sezioni senza numero, titolo con lato e altezza propri (formato 15)

    /// La prima riga del titolo e i segni del suo paragrafo, sulla pagina del capitolo `n`.
    private func titleLine(_ layout: DocumentLayout, chapter n: Int = 0, title: String = "Il mare") throws -> (page: Int, line: PlacedLine, markers: [PlacedMarker], column: CGRect) {
        let index = try bodyTop(layout, chapter: n).page
        let page = layout.pages[index]
        let text = layout.text.string as NSString
        let line = try #require(page.lines.first { text.substring(with: $0.range).hasPrefix(title) })
        return (index, line, page.markers.filter { $0.paragraphLocation == line.paragraphLocation }, page.setup.textRect(forPage: index))
    }

    private func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

    @Test("Il numero accanto al titolo: sulla sua prima riga, a sinistra; il titolo si scosta della larghezza del numero più 4 mm")
    func numberBesideLeft() throws {
        let heading = HeadingComposition(parts: [.numberBeside(prefix: "", style: nil, side: .left, gap: 4 * mm), .plainTitle, .space(8 * mm)])
        let composed = layout(book(title: "Il mare", heading: heading))
        let found = try titleLine(composed)
        #expect(found.markers.count == 1, "il numero una volta sola")
        let number = try #require(found.markers.first)
        #expect(abs(number.origin.x - found.column.minX) < 0.01)
        #expect(abs(number.origin.y - found.line.origin.y) < 0.01, "sulla linea di base del titolo")
        // Il titolo tiene i rientri del suo stile, dopo il numero.
        let indent = try titleLine(layout(book(title: "Il mare", heading: nil))).line.origin.x - found.column.minX
        #expect(abs(found.line.origin.x - (found.column.minX + width(number.line) + 4 * mm + indent)) < 0.01)
        // Accanto, non sopra: il corpo scende soltanto degli 8 mm dopo il titolo.
        let plain = try bodyTop(layout(book(title: "Il mare", heading: nil))).top
        #expect(abs(try bodyTop(composed).top - plain - 8 * mm) < 0.01)
    }

    @Test("Il numero accanto sul lato esterno: a destra sulle dispari, a sinistra sulle pari; le righe lunghe restano nella misura")
    func numberBesideOutside() throws {
        let long = String(repeating: "Un titolo molto lungo che va a capo ", count: 4)
        let heading = HeadingComposition(parts: [.numberBeside(prefix: "", style: nil, side: .outside, gap: 6 * mm), .plainTitle])
        let composed = layout(book(title: long, heading: heading, facing: true, chapters: 2))
        let text = composed.text.string as NSString
        for chapter in 0..<2 {
            let found = try titleLine(composed, chapter: chapter, title: "Un titolo")
            let number = try #require(found.markers.first)
            let reserve = width(number.line) + 6 * mm
            let titleLines = composed.pages[found.page].lines.filter { $0.paragraphLocation == found.line.paragraphLocation }
            #expect(titleLines.count > 1)
            if found.page % 2 == 1 {
                #expect(abs(number.origin.x - found.column.minX) < 0.01, "pagina pari: numero a sinistra")
                #expect(titleLines.allSatisfy { $0.origin.x >= found.column.minX + reserve - 0.01 })
            } else {
                #expect(abs(number.origin.x - (found.column.maxX - width(number.line))) < 0.01, "pagina dispari: numero a destra")
                #expect(titleLines.allSatisfy { $0.origin.x + $0.width <= found.column.maxX - reserve + 0.01 })
            }
            _ = text
        }
    }

    @Test("Una sezione senza numero: la parte «numero» sparisce con la sua fascia, il numero accanto lascia tutta la misura")
    func unnumberedSection() throws {
        var document = book(title: "Il mare", heading: .standard, chapters: 2)
        document.sections[0].role = "preface"
        let composed = layout(document)
        let numbered = try bodyTop(composed, chapter: 1).top
        let unnumbered = try bodyTop(composed, chapter: 0).top
        #expect(abs((numbered - unnumbered) - 12 * mm) < 0.01, "senza numero manca la fascia di 12 mm: \((numbered - unnumbered) / mm) mm")
        #expect(try titleLine(composed, chapter: 0).markers.isEmpty)

        var beside = book(title: "Il mare", heading: HeadingComposition(parts: [.numberBeside(prefix: "", style: nil, side: .left, gap: 4 * mm), .plainTitle]))
        beside.sections[0].role = "preface"
        let found = try titleLine(layout(beside))
        var alone = book(title: "Il mare", heading: HeadingComposition(parts: [.plainTitle]))
        alone.sections[0].role = "preface"
        #expect(found.markers.isEmpty)
        #expect(abs(found.line.origin.x - (try titleLine(layout(alone)).line.origin.x)) < 0.01, "come il titolo senza numero accanto")
    }

    @Test("Il titolo con lato e altezza propri: a destra, o all'esterno; in una fascia di 30 mm poggia sul fondo")
    func titleOptions() throws {
        let right = layout(book(title: "Il mare", heading: HeadingComposition(parts: [.title(alignment: .right, minHeight: nil)])))
        let found = try titleLine(right)
        #expect(abs(found.line.origin.x + found.line.width - found.column.maxX) < 0.5, "il titolo finisce al margine destro")

        let outside = layout(book(title: "Il mare", heading: HeadingComposition(parts: [.title(alignment: .outside, minHeight: nil)]), facing: true, chapters: 2))
        let styled = layout(book(title: "Il mare", heading: HeadingComposition(parts: [.plainTitle]), facing: true, chapters: 2))
        for chapter in 0..<2 {
            let found = try titleLine(outside, chapter: chapter)
            // A sinistra il titolo tiene i rientri del suo stile, come senza allineamento proprio.
            if found.page % 2 == 1 { #expect(abs(found.line.origin.x - (try titleLine(styled, chapter: chapter).line.origin.x)) < 0.01, "pari: a sinistra") }
            else { #expect(abs(found.line.origin.x + found.line.width - found.column.maxX) < 0.5, "dispari: a destra") }
        }

        let plain = layout(book(title: "Il mare", heading: HeadingComposition(parts: [.plainTitle])))
        let tall = layout(book(title: "Il mare", heading: HeadingComposition(parts: [.title(alignment: nil, minHeight: 30 * mm)])))
        let plainTitle = try titleLine(plain), tallTitle = try titleLine(tall)
        let titleHeight = plainTitle.line.ascent + plainTitle.line.descent
        #expect(titleHeight < 30 * mm)
        let drop = plainTitle.line.origin.y - tallTitle.line.origin.y
        let bodyDrop = try bodyTop(tall).top - bodyTop(plain).top
        #expect(drop > 0 && abs(drop - bodyDrop) < 0.01, "il titolo e il corpo scendono insieme: lo spazio in più è sopra")
    }

    @Test("Numero accanto e lato del titolo si salvano nel formato 15; le testate di prima restano nel 14")
    func version15() throws {
        let heading = HeadingComposition(parts: [.numberBeside(prefix: "§ ", style: "Body", side: .inside, gap: 5 * mm),
                                                 .title(alignment: .center, minHeight: 20 * mm), .space(8 * mm)])
        let xml = DocumentFormat.string(for: book(title: "Il mare", heading: heading))
        #expect(xml.contains("version=\"18\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.style(named: "Titolo capitolo")?.heading == heading)
        #expect(DocumentFormat.string(for: read) == xml)
        #expect(throws: (any Error).self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"13\"")) }
        #expect(DocumentFormat.string(for: book(title: "Il mare", heading: .standard)).contains("version=\"18\""))
        #expect(HeadingComposition(parts: [.numberBeside(prefix: "", style: nil, side: .center, gap: 0), .plainTitle]).problem != nil)
        #expect(HeadingComposition(parts: [.numberBeside(prefix: "", style: nil, side: .left, gap: 0),
                                           .numberBeside(prefix: "", style: nil, side: .right, gap: 0), .plainTitle]).problem != nil)
    }

    @Test("Scrivi risultato nella testata: la pagina e il titolo della sezione, calcolati nel punto del titolo; vuoto, la parte sparisce")
    func resultPart() throws {
        let heading = HeadingComposition(parts: [
            .result(formula: .pageContainingNumber, prefix: "p. ", style: nil, alignment: .left, minHeight: nil),
            .result(formula: .sectionContainingTitle(role: "chapter"), prefix: "» ", style: "Body", alignment: .right, minHeight: nil),
            .plainTitle,
        ])
        #expect(heading.problem == nil)
        let composed = layout(book(title: "Il mare", heading: heading, chapters: 2))
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: composed)))
        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
        let second = try titleLine(composed, chapter: 1)
        #expect(second.page > 0)
        #expect(pages[0].contains("p. 1\n» Il mare\n1 Il mare"), "sulla prima pagina, sopra il titolo con il segno della Lista")
        #expect(pages[second.page].contains("p. \(second.page + 1)\n» Il mare"), "il capitolo dopo legge la sua pagina")
        #expect(second.markers.count == 3, "due risultati e il segno della Lista: la testata non scrive il numero")

        // Nessuna parte (role «part») contiene il capitolo: il risultato è vuoto e la parte non occupa posto.
        let missing = HeadingComposition(parts: [.result(formula: .sectionContainingTitle(role: "part"), prefix: "Part ", style: nil, alignment: .left, minHeight: 20 * mm),
                                                 .plainTitle])
        let without = try bodyTop(layout(book(title: "Il mare", heading: HeadingComposition(parts: [.plainTitle]))))
        let with = try bodyTop(layout(book(title: "Il mare", heading: missing)))
        #expect(abs(with.top - without.top) < 0.01)

        // Il numero delle pagine si sa a composizione finita: anche la testata lo legge giusto.
        let count = layout(book(title: "Il mare", heading: HeadingComposition(parts: [
            .result(formula: .documentPageCount, prefix: "of ", style: nil, alignment: .left, minHeight: nil), .plainTitle]), chapters: 2))
        let countPDF = try #require(PDFDocument(data: PDFRenderer.pdfData(for: count)))
        #expect(countPDF.page(at: 0)?.string?.contains("of \(count.pages.count)\n") == true)
    }

    @Test("La parte «risultato» si salva nel formato 16 con la sua catena, e rilegge uguale; una catena rotta è un errore")
    func version16() throws {
        let heading = HeadingComposition(parts: [.result(formula: .sectionContainingNumber(role: "part"), prefix: "Part ", style: "Body", alignment: .outside, minHeight: 10 * mm),
                                                 .plainTitle])
        let xml = DocumentFormat.string(for: book(title: "Il mare", heading: heading))
        #expect(xml.contains("version=\"18\""))
        let read = try DocumentFormat.document(from: xml)
        #expect(read.styles.style(named: "Titolo capitolo")?.heading == heading)
        #expect(DocumentFormat.string(for: read) == xml)
        let json = String(decoding: try JSONEncoder().encode(heading), as: UTF8.self)
        #expect(json.contains("position.section-containing.number.write-here") && json.contains("\"role\":\"part\""))
        let broken = json.replacingOccurrences(of: "position.section-containing.number.write-here", with: "position.number.write-here")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(HeadingComposition.self, from: Data(broken.utf8)) }
        #expect(HeadingComposition(parts: [.result(formula: FieldFormula(origin: .position, reading: .number), prefix: "", style: nil, alignment: .left, minHeight: nil)]).problem != nil)
    }
}
