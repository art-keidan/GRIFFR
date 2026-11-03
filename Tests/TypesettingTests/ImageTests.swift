import AppKit
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Immagini nella riga")
    struct ImageTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

        /// Un'immagine PNG di prova: un quadrato rosso pieno (disegnato con Core Graphics: impostare i colori pixel per
        /// pixel in una NSBitmapImageRep vuota la lasciava trasparente).
        static func png(size: Int = 8) -> Data {
            let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        }

        /// Il colore al centro di un rettangolo di una pagina disegnata (su fondo bianco), per vedere se l'immagine c'è.
        static func color(at point: CGPoint, of page: LaidOutPage, size: CGSize) -> NSColor {
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            PDFRenderer.draw(page, in: context)
            // NSBitmapImageRep conta le righe dall'alto.
            return NSBitmapImageRep(cgImage: context.makeImage()!).colorAt(x: Int(point.x), y: Int(size.height - point.y))!
        }

        private func document(_ image: ImageObject) -> Document {
            Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Prima ", style: body)), .image(image), .text(TextRun(" dopo", style: body))]))])
        }

        @Test("Nel file: immagine inclusa (in base64) e collegata; tornano uguali")
        func fileFormat() throws {
            let embedded = document(ImageObject(source: .embedded(Self.png()), width: 40, height: 30))
            let written = DocumentFormat.string(for: embedded)
            #expect(written.contains("<img width=\"40\" height=\"30\">\(Self.png().base64EncodedString())</img>"))
            #expect(try DocumentFormat.document(from: written) == embedded)
            let linked = document(ImageObject(source: .linked("/percorso/foto.png"), width: 20, height: 20))
            #expect(DocumentFormat.string(for: linked).contains("<img src=\"/percorso/foto.png\" width=\"20\" height=\"20\"/>"))
            #expect(try DocumentFormat.document(from: DocumentFormat.string(for: linked)) == linked)
        }

        @Test("Nel testo l'immagine è un carattere con il suo attributo, e torna nel modello; non è un richiamo di nota")
        func attributedText() {
            let doc = document(ImageObject(source: .embedded(Self.png()), width: 40, height: 30))
            let text = doc.attributedString().text
            #expect((text.attribute(.inlineImage, at: 6, effectiveRange: nil) as? ImageAttachment)?.image.width == 40)
            #expect(Document(attributedString: text, settings: doc.settingsOnly) == doc)
            let marked = NSMutableAttributedString(attributedString: text)
            marked.addAttribute(.footnote, value: true, range: NSRange(location: 6, length: 1))
            #expect(!TextStyling.isNoteAnchor(in: marked, at: 6), "un'immagine dentro una nota non apre una nota nuova")
        }

        @Test("La riga si alza per un'immagine alta, che occupa la sua larghezza; nel PDF c'è l'immagine")
        func layoutAndPDF() throws {
            let tall = document(ImageObject(source: .embedded(Self.png()), width: 50, height: 60))
            let layout = PageLayout.layout(tall.attributedString().text, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false))
            let line = try #require(layout.pages[0].lines.first)
            #expect(line.ascent >= 60)
            let plain = PageLayout.layout(Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Prima  dopo", style: body))]))]).attributedString().text,
                                          options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false))
            let widthWith = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
            let widthWithout = CGFloat(CTLineGetTypographicBounds(plain.pages[0].lines[0].line, nil, nil, nil))
            #expect(abs(widthWith - widthWithout - 50) < 3, "lo spazio dell'immagine al posto di un carattere")
            let pdf = String(decoding: PDFRenderer.pdfData(for: layout), as: UTF8.self)
            #expect(pdf.contains("/Image"))
        }

        @Test("Un'immagine collegata che non si trova più: la pagina si compone e si disegna lo stesso")
        func missingLinkedImage() {
            let doc = document(ImageObject(source: .linked("/non/esiste/foto.png"), width: 30, height: 30))
            #expect(InlineImages.drawable(for: ImageObject(source: .linked("/non/esiste/foto.png"), width: 30, height: 30)) == nil)
            let layout = PageLayout.layout(doc.attributedString().text, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false))
            #expect(!PDFRenderer.pdfData(for: layout).isEmpty)
        }
        // MARK: Figure (tappa 5.5b)

        private func figureDocument(_ inlines: [Inline], style: FloatStyle = .defaultFigure) -> Document {
            var document = Document(lists: [ListDefinition.figures], blocks: [.paragraph(Paragraph(inlines: inlines))])
            document.floatStyles.append(style)
            return document
        }

        private func figure(_ caption: String, height: Double = 100, style: String = FloatStyle.figureName) -> Inline {
            var object = FloatingObject(runs: [TextRun(caption, style: CharacterStyle(fontName: "HoeflerText-Regular", size: 10))], style: style)
            object.image = ImageObject(source: .embedded(Self.png()), width: 200, height: height)
            return .floating(object)
        }

        private func layout(_ document: Document) -> DocumentLayout { PageLayout.layout(document.attributedString().text, options: document.layoutOptions) }

        @Test("Nel file: lo stile delle figure (posizioni alla LaTeX, didascalia) e la figura con la sua immagine")
        func figureFile() throws {
            var style = FloatStyle.defaultFigure
            style.positions = [.top, .bottom]
            style.ignoresLimits = true
            style.caption = .above
            let doc = figureDocument([.text(TextRun("Testo", style: body)), figure("Didascalia")], style: style)
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("placement=\"figure\" positions=\"!tb\" caption=\"above\""))
            #expect(written.contains("<note style=\"Figura\""))
            #expect(try DocumentFormat.document(from: written) == doc)
        }

        @Test("h: la figura sta subito dopo il paragrafo, con la didascalia numerata sotto l'immagine")
        func figureHere() throws {
            let result = layout(figureDocument([.text(TextRun("Testo prima della figura", style: body)), figure("Una didascalia")]))
            let page = result.pages[0]
            let image = try #require(page.images.first)
            let bodyLine = try #require(page.lines.first { !$0.isNote })
            let caption = try #require(page.lines.first { $0.isNote })
            #expect(image.rect.maxY < bodyLine.origin.y - bodyLine.descent, "sotto il paragrafo")
            #expect(caption.origin.y < image.rect.minY, "la didascalia sotto l'immagine")
            let red = Self.color(at: CGPoint(x: image.rect.midX, y: image.rect.midY), of: page, size: result.setup.paperSize)
            // Rosso (la conversione tra spazi di colore porta il verde a circa 0,15).
            #expect(red.redComponent > 0.9 && red.greenComponent < 0.3 && red.blueComponent < 0.1, "l'immagine è disegnata al suo posto")
            let text = try #require(PDFDocument(data: PDFRenderer.pdfData(for: result))?.string)
            #expect(text.contains("Figura 1. Una didascalia"))
        }

        @Test("t: in cima alla pagina dopo; b: in fondo alla pagina del richiamo")
        func figureTopAndBottom() throws {
            var top = FloatStyle.defaultFigure
            top.positions = [.top]
            let atTop = layout(figureDocument([.text(TextRun("Testo", style: body)), figure("in cima")], style: top))
            #expect(atTop.pages.count == 2)
            let image = try #require(atTop.pages[1].images.first)
            #expect(abs(image.rect.maxY - atTop.setup.textRect.maxY) < 0.5, "in cima allo specchio della pagina dopo")
            var bottom = FloatStyle.defaultFigure
            bottom.positions = [.bottom]
            let atBottom = layout(figureDocument([.text(TextRun("Testo", style: body)), figure("in fondo")], style: bottom))
            #expect(atBottom.pages.count == 1)
            let low = try #require(atBottom.pages[0].images.first)
            #expect(low.rect.minY < atBottom.setup.textRect.minY + 60, "in fondo allo specchio")
        }

        @Test("H: subito dopo il paragrafo anche se non entra (allora nella pagina dopo, e il testo la segue); l'ordine resta")
        func figureExactlyHereAndOrder() throws {
            var exactly = FloatStyle.defaultFigure
            exactly.exactlyHere = true
            let filler = String(repeating: "riempitivo ", count: 380)
            let result = layout(figureDocument([.text(TextRun(filler, style: body)), figure("alta", height: 300)], style: exactly))
            let figurePage = try #require(result.pages.firstIndex { !$0.images.isEmpty })
            #expect(figurePage == 1, "non entra nella prima pagina: va nella seconda")
            var topOnly = FloatStyle.defaultFigure
            topOnly.positions = [.top]
            let ordered = layout(figureDocument([.text(TextRun("Uno", style: body)), figure("prima", height: 400), .text(TextRun(" due", style: body)),
                                                 figure("seconda", height: 50)], style: topOnly))
            let text = ordered.text.string as NSString
            let captions = ordered.pages.flatMap { $0.lines.filter(\.isNote).map { text.substring(with: $0.noteRange!) } }
            #expect(captions == ["prima", "seconda"], "la seconda, più piccola, non passa davanti alla prima")
        }

        @Test("La didascalia sopra l'immagine")
        func captionAbove() throws {
            var style = FloatStyle.defaultFigure
            style.caption = .above
            let result = layout(figureDocument([.text(TextRun("Testo", style: body)), figure("sopra")], style: style))
            let image = try #require(result.pages[0].images.first)
            let caption = try #require(result.pages[0].lines.first { $0.isNote })
            #expect(caption.origin.y > image.rect.maxY)
        }

        @Test("Una pagina con la sola figura, senza didascalia, arriva nel PDF")
        func figureOnlyPageIsPrinted() throws {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            var figureStyle = FloatStyle.defaultFigure
            figureStyle.positions = [.top]
            figureStyle.caption = .none
            var figure = FloatingObject(runs: [TextRun("didascalia", style: body)], style: FloatStyle.figureName)
            figure.image = ImageObject(source: .embedded(Data()), width: 200, height: 100)
            var document = Document(lists: [ListDefinition.figures],
                                    blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: body)), .floating(figure)]))])
            document.floatStyles.append(figureStyle)
            let layout = PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
            try #require(layout.pages.count == 2)
            #expect(!layout.pages[1].images.isEmpty, "la figura va in cima alla pagina dopo")
            #expect(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.pageCount == 2)
        }

        @Test("Solo l'ultima pagina con la sola riga vuota del cursore resta fuori dal PDF; una vuota in mezzo no")
        func onlyFinalCaretPageIsDropped() throws {
            let text = NSAttributedString(string: "Una riga.", attributes: [.font: CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil)])
            let one = PageLayout.layout(text)
            let page = try #require(one.pages.first)
            func pdfPages(_ pages: [LaidOutPage]) -> Int? {
                PDFDocument(data: PDFRenderer.pdfData(for: DocumentLayout(setup: one.setup, text: one.text, pages: pages, notes: [])))?.pageCount
            }
            #expect(pdfPages([page, LaidOutPage()]) == 1, "la pagina finale del cursore non si stampa")
            #expect(pdfPages([page, LaidOutPage(), page]) == 3, "una pagina vuota in mezzo sì")
            #expect(pdfPages([LaidOutPage()]) == 1, "un documento vuoto ha comunque una pagina")
        }

        /// Un PNG di `side` × `side` punti.
        private func png(side: Int) -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            return bitmap.representation(using: .png, properties: [:])!
        }

        private func pixelWidth(_ drawable: InlineImages.Drawable?) -> Int? {
            if case .bitmap(let image)? = drawable { image.width } else { nil }
        }

        @Test("Un'immagine collegata segue il suo file: sostituito si rilegge, cancellato diventa il riquadro, rimesso torna")
        func linkedImageFollowsItsFile() throws {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: path) }
            try png(side: 2).write(to: path)
            let image = ImageObject(source: .linked(path.path), width: 20, height: 20)
            #expect(pixelWidth(InlineImages.drawable(for: image)) == 2)
            try png(side: 3).write(to: path)
            // La data di modifica cambia anche se il file si riscrive nello stesso istante.
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path.path)
            #expect(pixelWidth(InlineImages.drawable(for: image)) == 3, "sostituito: l'immagine nuova")
            try FileManager.default.removeItem(at: path)
            #expect(InlineImages.drawable(for: image) == nil, "cancellato: nessuna immagine, al suo posto il riquadro")
            try png(side: 4).write(to: path)
            #expect(pixelWidth(InlineImages.drawable(for: image)) == 4, "rimesso: torna")
        }

        @Test("Cambiare le misure non decodifica di nuovo; il delegato delle misure non dipende dai byte dell'immagine")
        func resizingReusesTheDecodedImage() throws {
            let data = png(side: 5)
            let small = ImageObject(source: .embedded(data), width: 10, height: 10)
            let large = ImageObject(source: .embedded(data), width: 80, height: 80)
            // La memoria è un NSCache, che può scartare un'immagine in qualunque momento: si controlla la chiave, che
            // è la stessa per le due misure, e quindi la stessa immagine decodificata finché resta in memoria.
            let smallKey = try #require(InlineImages.contentKey(for: small))
            let largeKey = try #require(InlineImages.contentKey(for: large))
            #expect(smallKey.isEqual(largeKey) && smallKey.hash == largeKey.hash, "la chiave è il contenuto, non le misure")
            #expect(InlineImages.drawable(for: large) != nil)
            let other = ImageObject(source: .embedded(png(side: 6)), width: 10, height: 10)
            #expect(InlineImages.runDelegate(for: small) === InlineImages.runDelegate(for: other), "stesse misure, stesso delegato")
            #expect(InlineImages.runDelegate(for: small) !== InlineImages.runDelegate(for: large))
        }
    }
}
