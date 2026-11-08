import AppKit
import CoreText
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// I font a colori arrivano a colori sulla pagina disegnata (come sullo schermo) e nel PDF.
    @Suite("Font a colori: sbix e COLR")
    struct ColorFontTests {
        /// Quanti pixel colorati, cioè non grigi, ha l'immagine.
        private func colored(_ image: CGImage) -> Int {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return stride(from: 0, to: data.count, by: 4).filter { i in
                let channels = [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
                return channels.max()! - channels.min()! > 60
            }.count
        }

        /// I pixel colorati nel disegno della pagina e nel PDF riletto.
        private func colors(_ fontName: String, _ string: String) throws -> (drawn: Int, pdf: Int) {
            let font = CTFontCreateWithName(fontName as CFString, 48, nil)
            let layout = PageLayout.layout(NSAttributedString(string: string + "\n", attributes: [.font: font as NSFont]))
            let line = try #require(layout.pages.first?.lines.first)
            let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
            #expect(runs.allSatisfy { CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String == fontName },
                    "nessun glifo da un font di ripiego")
            let size = layout.pages[0].setup.paperSize
            let bitmap = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.setFillColor(.white)
            bitmap.fill(CGRect(origin: .zero, size: size))
            PDFRenderer.draw(layout.pages[0], in: bitmap)
            let page = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.page(at: 0))
            let image = page.thumbnail(of: NSSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
            let rendered = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            return (colored(try #require(bitmap.makeImage())), colored(rendered))
        }

        @Test("Apple Color Emoji (sbix): a colori sulla pagina e nel PDF")
        func sbix() throws {
            let result = try colors("AppleColorEmoji", "👍🏽🌈🍎")
            #expect(result.drawn > 500 && result.pdf > 500)
        }

        /// Catrinity colora i suoi emoji; le lettere le disegna in nero, per scelta del font.
        @Test("Catrinity (COLR): a colori sulla pagina e nel PDF", .enabled(if: CTFontCopyPostScriptName(CTFontCreateWithName("Catrinity" as CFString, 12, nil)) as String == "Catrinity"))
        func colr() throws {
            let result = try colors("Catrinity", "🌈🌍🎁🎃🎄🎅")
            #expect(result.drawn > 500 && result.pdf > 500)
        }
    }
}
