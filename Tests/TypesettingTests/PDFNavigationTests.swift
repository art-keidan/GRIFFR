import AppKit
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Navigazione nel PDF: collegamenti delle note, segnalibri, etichette delle pagine")
    struct PDFNavigationTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)

        private func paragraph(_ text: String) -> Paragraph { Paragraph(inlines: [.text(TextRun(text, style: body))]) }

        /// I collegamenti di una pagina del PDF: il riquadro e la pagina (da 0) con il punto a cui portano.
        private func links(on page: PDFPage, in document: PDFDocument) -> [(bounds: CGRect, page: Int, point: CGPoint)] {
            page.annotations.compactMap { annotation in
                guard annotation.type == "Link", let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination,
                      let target = destination.page else { return nil }
                return (annotation.bounds, document.index(for: target), destination.point)
            }
        }

        @Test("Ogni richiamo porta alla sua nota, e il segno della nota riporta al richiamo")
        func noteLinks() throws {
            // «Testo¹ che continua² fine.»: richiami alle posizioni 5 e 30.
            let text = Document(blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Testo", style: body)),
                    .floating(FloatingObject(runs: [TextRun("Prima nota.", style: small)])),
                    .text(TextRun(" che continua", style: body)),
                    .floating(FloatingObject(runs: [TextRun("Seconda.", style: small)])),
                    .text(TextRun(" fine.", style: body)),
                ])),
            ]).attributedString().text
            let layout = PageLayout.layout(text, options: options)
            let navigation = PDFNavigation(layout: layout)
            #expect(navigation.links.map(\.destination) == ["note-5", "ref-5", "note-30", "ref-30"])
            #expect(Set(navigation.destinations.map(\.name)) == ["note-5", "ref-5", "note-30", "ref-30"])
            let page = layout.pages[0]
            let notes = page.lines.filter(\.isNote), main = page.lines.filter { !$0.isNote }
            // Il richiamo sta nella riga del testo, il ritorno nella riga della nota; la prima nota è sopra la seconda.
            let toFirst = try #require(navigation.links.first { $0.destination == "note-5" })
            #expect(toFirst.rect.minY <= main[0].origin.y && toFirst.rect.maxY >= main[0].origin.y)
            #expect(toFirst.rect.width > 1 && toFirst.rect.width < 12)
            let back = try #require(navigation.links.first { $0.destination == "ref-5" })
            #expect(back.rect.minY <= notes[0].origin.y && back.rect.maxY >= notes[0].origin.y)
            #expect(abs(back.rect.minX - notes[0].origin.x) < 0.01)
            let arrival = try #require(navigation.destinations.first { $0.name == "note-5" })
            #expect(abs(arrival.point.y - (notes[0].origin.y + notes[0].ascent)) < 0.01)

            // Nel PDF: quattro collegamenti, che PDFKit risolve in punti della prima pagina.
            let data = PDFRenderer.pdfData(for: layout)
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("griffr-notes.pdf"))
            let pdf = try #require(PDFDocument(data: data))
            let found = links(on: try #require(pdf.page(at: 0)), in: pdf)
            #expect(found.count == 4)
            #expect(found.allSatisfy { $0.page == 0 })
            let toNote = try #require(found.first { abs($0.bounds.midY - toFirst.rect.midY) < 1 && abs($0.bounds.minX - toFirst.rect.minX) < 1 })
            #expect(abs(toNote.point.y - arrival.point.y) < 1)
            #expect(pdf.string?.contains("Testo") == true, "il testo resta estraibile")
        }

        @Test("I titoli diventano segnalibri annidati che portano alla loro pagina")
        func bookmarks() throws {
            let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 120)
            let document = try DocumentFormat.document(from: """
                <document version="18" font="HoeflerText-Regular" size="12">
                <styles>
                <style name="Titolo 1" target="paragraph" size="18" outline-level="1"/>
                <style name="Titolo 2" target="paragraph" size="14" outline-level="2"/>
                <style name="Testo" target="paragraph"/>
                </styles>
                <p style="Titolo 1">Capitolo primo</p>
                <p style="Testo">\(long)</p>
                <p style="Titolo 2">Una sezione</p>
                <p style="Testo">\(long)</p>
                <p style="Titolo 1">Capitolo secondo</p>
                <p style="Testo">Ultimo paragrafo.</p>
                </document>
                """)
            let layout = PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
            #expect(layout.pages.count >= 2)
            let navigation = PDFNavigation(layout: layout)
            #expect(navigation.bookmarks.map(\.title) == ["Capitolo primo", "Capitolo secondo"])
            #expect(navigation.bookmarks[0].children.map(\.title) == ["Una sezione"])
            #expect(navigation.bookmarks[0].page == 0)
            let second = navigation.bookmarks[1]
            // La pagina del segnalibro è quella in cui sta la riga del titolo.
            let location = (layout.text.string as NSString).range(of: "Capitolo secondo").location
            let expectedPage = try #require(layout.pages.firstIndex { $0.lines.contains { !$0.isNote && NSLocationInRange(location, $0.range) } })
            #expect(second.page == expectedPage)

            let data = PDFRenderer.pdfData(for: layout)
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("griffr-bookmarks.pdf"))
            // Ogni voce ha il suo /Parent (Core Graphics lo omette, il ritocco in coda al file lo aggiunge).
            let raw = String(data: data, encoding: .isoLatin1) ?? ""
            let update = try #require(raw.components(separatedBy: "%%EOF").dropLast().last)
            #expect(update.components(separatedBy: "/Parent ").count - 1 == 3)
            #expect(!update.contains("/Count -"), "la radice ha un numero di voci visibili, non negativo")
            let pdf = try #require(PDFDocument(data: data))
            let root = try #require(pdf.outlineRoot)
            #expect(root.numberOfChildren == 2)
            let first = try #require(root.child(at: 0)), last = try #require(root.child(at: 1))
            #expect(first.label == "Capitolo primo" && first.numberOfChildren == 1 && first.child(at: 0)?.label == "Una sezione")
            #expect(last.label == "Capitolo secondo")
            let target = try #require(last.destination?.page)
            #expect(pdf.index(for: target) == expectedPage)
        }

        @Test("Una premessa in romani e un capitolo in cifre arabe: le etichette delle pagine seguono i numeri stampati")
        func pageLabels() throws {
            let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 160)
            var document = Document(lists: [ListDefinition(name: "Romani", counter: .lowerRoman, continues: true),
                                            ListDefinition(name: "Arabi", counter: .decimal, continues: true)],
                                    blocks: [.paragraph(paragraph("Premessa.")), .paragraph(paragraph(long))])
            document.pageNumbering = "Romani"
            document.sections = [Section(id: "c1", role: "chapter", title: paragraph("Il primo capitolo"),
                                         blocks: [.paragraph(paragraph(long))], start: .newPage, pageNumbering: "Arabi")]
            let layout = PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
            let numbers = layout.pages.map(\.number)
            let chapter = try #require(numbers.firstIndex(of: "1"))
            #expect(chapter >= 2)
            #expect(numbers[0] == "i" && numbers[1] == "ii")

            let data = PDFRenderer.pdfData(for: layout)
            // Per guardarlo con altri lettori (pdfinfo, mutool).
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("griffr-navigation.pdf"))
            let pdf = try #require(PDFDocument(data: data))
            #expect(pdf.pageCount <= layout.pages.count)
            let labels = (0..<pdf.pageCount).map { pdf.page(at: $0)?.label }
            #expect(labels == Array(numbers.prefix(pdf.pageCount)).map(Optional.some))
            // Due tratti: romani da 1, poi cifre arabe da 1.
            let raw = String(data: data, encoding: .isoLatin1) ?? ""
            #expect(raw.contains("/PageLabels << /Nums [ 0 << /S /r /St 1 >> \(chapter) << /S /D /St 1 >> ] >>"))
            // Il capitolo è anche un segnalibro.
            #expect(pdf.outlineRoot?.child(at: 0)?.label == "Il primo capitolo")
        }

        @Test("Senza numeri diversi dalla posizione nel PDF non si scrivono etichette")
        func noLabelsWhenPlain() throws {
            let layout = PageLayout.layout(NSAttributedString(string: "Una pagina sola.\n"), options: options)
            #expect(PDFNavigation(layout: layout).pageLabels.isEmpty)
            let raw = String(data: PDFRenderer.pdfData(for: layout), encoding: .isoLatin1) ?? ""
            #expect(!raw.contains("/PageLabels"))
        }

        @Test("Le voci delle etichette: tratti continui, numeri romani, etichette qualsiasi")
        func numberTree() {
            #expect(PDFNavigation.romanNumeral(1994) == "MCMXCIV")
            #expect(PDFNavigation.numberTree(["i", "ii", "iii", "1", "2", "A-1", "A-2"], values: [1, 2, 3, 1, 2, 1, 2])
                    == "0 << /S /r /St 1 >> 3 << /S /D /St 1 >> 5 << /P (A-1) >> 6 << /P (A-2) >> ")
            #expect(PDFNavigation.numberTree(["5", "7"], values: [5, 7]) == "0 << /S /D /St 5 >> 1 << /S /D /St 7 >> ")
            #expect(PDFNavigation.pdfString("a(b)") == "(a\\(b\\))")
            #expect(PDFNavigation.pdfString("— 1 —") == "<FEFF2014002000310020" + "2014>")
        }
    }
}
