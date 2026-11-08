import AppKit
import CoreText
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// I font a colori arrivano a colori sulla pagina disegnata (come sullo schermo) e nel PDF.
    @Suite("Font a colori: sbix, COLR v0 e v1, SVG")
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
            // Spazi e a capo possono venire da un font di ripiego (Twemoji non ha l'a capo): conta il resto.
            let text = layout.text.string as NSString
            let runs = (CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []).filter { run in
                let range = CTRunGetStringRange(run)
                return !text.substring(with: NSRange(location: range.location, length: range.length))
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
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

        /// Vero se il font è installato con quel nome PostScript (altrimenti Core Text ne darebbe un altro).
        private static func installed(_ name: String) -> Bool {
            CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name
        }

        /// Un font a colori per ogni formato: il nome PostScript, il formato e un testo che il font colora. Catrinity e
        /// Bungee colorano le lettere, gli altri font di emoji solo gli emoji.
        static let cases: [(font: String, format: String, sample: String)] = [
            ("AppleColorEmoji", "sbix", "👍🏽🌈🍎"),
            ("Catrinity", "COLR v0", "🌈🌍🎁🎃🎄🎅"),
            ("BungeeColor-Regular", "COLR v0", "GRIFFR Aa 123"),
            ("TwemojiMozilla", "COLR v0", "🌈🍎🎃"),
            ("Honk-Regular", "COLR v1", "GRIFFR Aa 123"),
            ("Nabla-Regular", "COLR v1 + SVG", "GRIFFR Aa 123"),
            ("BungeeSpice-Regular", "COLR v1 + SVG", "GRIFFR Aa 123"),
            ("NotoColorEmoji", "COLR v1 + SVG", "🌈🍎🎃👍🏽"),
            ("GilbertColorBoldPreview5", "SVG", "GRIFFR"),
            ("EmojiOneColor", "SVG", "🌈🍎🎃👍🏽"),
        ]

        @Test("A colori sulla pagina e nel PDF; si salta se il font non è installato", arguments: cases.map(\.font))
        func inColor(_ font: String) throws {
            guard Self.installed(font), let item = Self.cases.first(where: { $0.font == font }) else { return }
            let result = try colors(font, item.sample)
            #expect(result.drawn > 500, "\(font) (\(item.format)): a colori sulla pagina")
            #expect(result.pdf > 500, "\(font) (\(item.format)): a colori nel PDF")
        }
    }
}
