import AppKit
import CoreText
import PDFKit
import Testing
import Typesetting

extension TypesettingSuite {
    @Suite("Impaginazione ed esportazione PDF")
    struct PDFExportTests {
        /// Le righe di prova: gotico con entrambe le alternative, poi Hoefler normale, con legature rare, in maiuscoletto.
        private func sample() throws -> NSAttributedString {
            let text = NSMutableAttributedString()
            func add(_ string: String, _ font: CTFont, _ settings: [FeatureSetting] = []) {
                text.append(NSAttributedString(string: string + "\n", attributes: [.font: FontFeatures.font(font, with: settings)]))
            }
            add(TestFonts.gothicSample, try TestFonts.vulcanius(size: 36))
            add(TestFonts.gothicSample, try TestFonts.vulcanius(size: 36), [.aat(type: 17, selector: 3)])
            add(TestFonts.latinSample, try TestFonts.hoefler())
            add(TestFonts.latinSample, try TestFonts.hoefler(), [.aat(type: 1, selector: 4)])
            add(TestFonts.latinSample, try TestFonts.hoefler(), [.aat(type: 3, selector: 3)])
            return text
        }

        @Test("Le funzioni attive arrivano nella pagina composta")
        func featuresSurviveLayout() throws {
            let layout = PageLayout.layout(try sample())
            #expect(layout.pages.count == 1)
            let lines = layout.pages[0].lines
            #expect(lines.count == 6, "cinque righe di testo e la riga vuota dopo l'ultimo a capo")
            #expect(lines[5].range == NSRange(location: layout.text.length, length: 0))
            // Ogni riga finisce con il glifo dell'a capo, che qui non interessa.
            func ids(_ index: Int) -> [Int] { Shaper.glyphs(in: lines[index].line).filter { $0.advance > 0 }.map { Int($0.id) } }
            #expect(ids(0) == [15, 25, 3, 8, 24])
            #expect(ids(1) == [33, 34, 3, 8, 24])
            #expect(ids(3) == [643, 3, 644, 3, 631, 3, 20, 21, 22, 23])
            #expect(ids(4) == [462, 479, 3, 478, 479, 3, 465, 465, 468, 3, 20, 21, 22, 23])
        }

        @Test("Il PDF incorpora i due font")
        func fontsAreEmbedded() throws {
            let data = PDFRenderer.pdfData(for: PageLayout.layout(try sample()))
            let raw = String(data: data, encoding: .isoLatin1) ?? ""
            #expect(raw.contains("+Vulcanius"))
            #expect(raw.contains("+HoeflerText-Regular"))
            // Un programma di font incorporato per ogni font usato; nessun font solo citato per nome.
            let embedded = raw.components(separatedBy: "/FontFile2").count - 1
            let descriptors = raw.components(separatedBy: "/Type /FontDescriptor").count - 1
            #expect(embedded >= 2)
            #expect(embedded == descriptors)
        }

        @Test("Legature e alternative portano nel PDF il loro testo effettivo (ActualText)")
        func actualText() throws {
            let data = PDFRenderer.pdfData(for: PageLayout.layout(try sample()))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("wordprocessor-test.pdf"))
            let texts = try PDFInspector.actualTexts(inFirstPageOf: data)
            // Le due alternative gotiche (glifi 33 e 34) e le legature di Hoefler Text.
            #expect(texts.contains("\u{10339}"))
            #expect(texts.contains("\u{10343}"))
            #expect(texts.filter { $0 == "ffi" }.count >= 2)
            #expect(texts.contains("ct"))
            #expect(texts.contains("st"))
        }

        @Test("Il testo estratto con PDFKit coincide dove non agiscono alternative o legature")
        func pdfKitPlainText() throws {
            let data = PDFRenderer.pdfData(for: PageLayout.layout(try sample()))
            let lines = (try #require(PDFDocument(data: data)).string ?? "").split(separator: "\n").map(String.init)
            #expect(lines.count == 5)
            #expect(lines.first == TestFonts.gothicSample)
            #expect(lines.last == TestFonts.latinSample, "il maiuscoletto torna alle lettere scritte")
            // PDFKit ignora ActualText: per le alternative di Vulcanius restituisce i codici del sottoinsieme («%&»).
            // poppler e MuPDF invece lo rispettano. Se questo controllo comincia a passare, il limite è caduto.
            withKnownIssue("PDFKit non usa ActualText") {
                #expect(lines[1] == TestFonts.gothicSample)
            }
        }

        @Test("Un testo lungo si distribuisce su più pagine, senza perdere caratteri e senza uscire dallo specchio")
        func pagination() throws {
            let paragraph = "The officiating minister affixed five stamps to the letter and went away. "
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let text = NSAttributedString(
                string: String(repeating: String(repeating: paragraph, count: 6) + "\n", count: 40),
                attributes: [.font: try TestFonts.hoefler(size: 12), .paragraphStyle: style])
            let setup = PageSetup.a4
            // Senza trak, che ha i suoi test: qui si controlla solo la distribuzione delle righe.
            let layout = PageLayout.layout(text, setup: setup, appliesFontTracking: false)
            #expect(layout.pages.count > 1)

            let lines = layout.pages.flatMap(\.lines)
            #expect(lines.map(\.range.length).reduce(0, +) == text.length)
            #expect(zip(lines, lines.dropFirst()).allSatisfy { NSMaxRange($0.range) == $1.range.location })

            let rect = setup.textRect
            for page in layout.pages {
                for placed in page.lines {
                    var ascent: CGFloat = 0, descent: CGFloat = 0
                    let width = CGFloat(CTLineGetTypographicBounds(placed.line, &ascent, &descent, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(placed.line))
                    #expect(placed.origin.y + ascent <= rect.maxY + 0.01)
                    #expect(placed.origin.y - descent >= rect.minY - 0.01)
                    #expect(placed.origin.x + width <= rect.maxX + 0.01)
                }
            }
            // Le righe giustificate (tutte tranne l'ultima di ogni paragrafo) arrivano esattamente al margine destro.
            let first = layout.pages[0].lines[0]
            let firstWidth = CGFloat(CTLineGetTypographicBounds(first.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(first.line))
            #expect(abs(first.origin.x + firstWidth - rect.maxX) < 0.01)
            #expect(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.pageCount == layout.pages.count)
        }
    }
}
