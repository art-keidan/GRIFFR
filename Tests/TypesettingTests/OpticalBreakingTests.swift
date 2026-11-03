import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Sporgenza della punteggiatura nella scelta degli a capo (tappa B1.1)")
    struct OpticalBreakingTests {
        // Hoefler Text a corpo 24, dalla sua tabella opbd: la virgola sporge a destra di 0,96 pt, la virgoletta
        // alta di apertura a sinistra di 2,16. Palatino non ha la tabella.

        private func paragraph(_ text: String, font: CTFont) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font])
        }

        /// L'ascissa naturale di un indice del testo, sulla riga non spezzata.
        private func x(_ text: NSAttributedString, _ index: Int) -> CGFloat {
            CTLineGetOffsetForStringIndex(CTLineCreateWithAttributedString(text), index, nil)
        }

        private func breaks(_ text: NSAttributedString, firstWidth: CGFloat, protrusion: LineBreaker.Protrusion, hangsHyphens: Bool = false) -> [Int] {
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            return LineBreaker.optimalBreaks(paragraph: text, typesetter: typesetter, firstWidth: firstWidth, restWidth: 1000,
                                             justified: false, expansionLimit: 0, hyphenates: false, hyphenationLanguage: nil,
                                             hangsHyphens: hangsHyphens, protrusion: protrusion)?.map(\.end) ?? []
        }

        @Test("Una riga più larga della giustezza solo per la virgola finale ci sta, perché la virgola sporge")
        func commaAtEnd() throws {
            let text = paragraph("Ava lanche, avalanche", font: try TestFonts.hoefler(size: 24))
            // «Ava lanche,» supera la giustezza di mezzo punto.
            let width = x(text, 11) - 0.5
            #expect(breaks(text, firstWidth: width, protrusion: []) == [4, 21])
            #expect(breaks(text, firstWidth: width, protrusion: .right) == [12, 21])
            // Oltre la sporgenza della virgola non basta più.
            #expect(breaks(text, firstWidth: x(text, 11) - 1.0, protrusion: .right) == [4, 21])
        }

        @Test("A sinistra la virgoletta d'apertura sporge, e la riga che comincia con lei può essere più larga")
        func quoteAtStart() throws {
            let text = paragraph("\u{201C}Ava lanche avalanche", font: try TestFonts.hoefler(size: 24))
            let width = x(text, 11) - 1.5
            #expect(breaks(text, firstWidth: width, protrusion: []) == [5, 21])
            #expect(breaks(text, firstWidth: width, protrusion: .right) == [5, 21])
            #expect(breaks(text, firstWidth: width, protrusion: [.left, .right]) == [12, 21])
        }

        @Test("Con un font senza tabella opbd nulla cambia")
        func fontWithoutTable() throws {
            let palatino = CTFontCreateWithName("Palatino-Roman" as CFString, 24, nil)
            try #require(CTFontCopyPostScriptName(palatino) as String == "Palatino-Roman")
            let text = paragraph("Ava lanche, avalanche", font: palatino)
            let width = x(text, 11) - 0.1
            #expect(breaks(text, firstWidth: width, protrusion: [.left, .right]) == [4, 21])
        }

        @Test("Un trattino scritto a fine riga sporge di metà in ogni font, come nella composizione")
        func writtenHyphen() throws {
            let palatino = CTFontCreateWithName("Palatino-Roman" as CFString, 24, nil)
            let text = paragraph("Ava ben-noto avalanche", font: palatino)
            let width = x(text, 8) - 1.0
            #expect(breaks(text, firstWidth: width, protrusion: []) == [4, 22])
            #expect(breaks(text, firstWidth: width, protrusion: .right) == [8, 22])
        }

        @Test("I bordi che contano seguono l'allineamento, e nulla con i margini ottici spenti")
        func edgesByAlignment() {
            let on = LayoutOptions(usesOpticalMargins: true), off = LayoutOptions(usesOpticalMargins: false)
            #expect(PageLayout.protrusion(for: .justified, options: on) == [.left, .right])
            #expect(PageLayout.protrusion(for: .left, options: on) == [.left, .right])
            #expect(PageLayout.protrusion(for: .natural, options: on) == [.left, .right])
            #expect(PageLayout.protrusion(for: .right, options: on) == .right)
            #expect(PageLayout.protrusion(for: .center, options: on) == [])
            #expect(PageLayout.protrusion(for: .justified, options: off) == [])
        }

        @Test("Nell'impaginazione: la virgola sporge oltre il margine e la riga resta intera")
        func inLayout() throws {
            let font = try TestFonts.hoefler(size: 24)
            let text = paragraph("Ava lanche, avalanche", font: font)
            let width = x(text, 11) - 0.5
            let setup = PageSetup(paperSize: CGSize(width: width + 100, height: 400), top: 50, bottom: 50, left: 50, right: 50)
            func layout(_ optical: Bool) -> [PlacedLine] {
                PageLayout.layout(text, setup: setup, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: optical,
                                                                             lineBreaking: .optimal)).pages.flatMap(\.lines)
            }
            #expect(layout(false).first?.range.length == 4)
            let first = try #require(layout(true).first)
            #expect(first.range.length == 12)
            let end = first.origin.x + CGFloat(CTLineGetTypographicBounds(first.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(first.line))
            // Non giustificata: la riga resta alla sua larghezza naturale, mezzo punto oltre il margine.
            #expect(abs(end - (setup.textRect.maxX + 0.5)) < 0.02)
        }
    }
}
