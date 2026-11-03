import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("La pagina: misure in ogni unità, pagine affacciate")
    struct PageSetupTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private func mm(_ value: Double) -> CGFloat { PageSetup.points(fromMillimetres: value) }

        @Test("Una misura si scrive in qualsiasi unità; senza unità valgono i millimetri")
        func lengths() {
            func close(_ text: String, _ points: CGFloat) -> Bool { Length.points(from: text).map { abs($0 - points) < 0.001 } ?? false }
            #expect(close("25", mm(25)) && close("25 mm", mm(25)) && close("25mm", mm(25)) && close("25 millimetri", mm(25)))
            #expect(close("2,5 cm", mm(25)) && close("2.5cm", mm(25)))
            #expect(close("1 in", 72) && close("1\"", 72) && close("1″", 72) && close("1 pollice", 72))
            #expect(close("72 pt", 72) && close("72 punti", 72) && close("6 pc", 72) && close("6 pica", 72))
            #expect(close("1p6", 18) && close("p6", 6) && close("6p", 72), "pica e punti come in InDesign")
            #expect(Length.points(from: "abc") == nil && Length.points(from: "") == nil && Length.points(from: "2 cubiti") == nil)
            #expect(Length.points(from: "10", defaultUnit: .points) == 10)
            #expect(Length.text(mm(25)) == "25 mm" && Length.text(mm(25.4), unit: .centimetres) == "2,54 cm")
        }

        @Test("Un campo di misura fa anche i conti: + − × ÷ e parentesi, con unità diverse")
        func arithmetic() {
            func close(_ text: String, _ points: CGFloat) -> Bool { Length.points(from: text).map { abs($0 - points) < 0.001 } ?? false }
            #expect(close("3 pt + 5 cm", 3 + mm(50)) && close("3pt+5cm", 3 + mm(50)))
            #expect(close("210 mm − 2 × 25 mm", mm(160)) && close("210mm-2*25mm", mm(160)) && close("210 - 2x25", mm(160)))
            #expect(close("(297 − 20) / 2", mm(138.5)) && close("297 : 2", mm(148.5)) && close("1 in ÷ 4", 18))
            #expect(close("2 + 3 × 4", mm(14)), "la moltiplicazione prima della somma")
            #expect(close("10 mm + 5", mm(15)) && close("1 in + 1", 72 + mm(1)), "un numero puro sommato vale millimetri")
            #expect(close("1p6 + 6pt", 24) && close("2 × 1p6", 36) && close("p6 + p6", 12))
            #expect(close("1\" − 0,5 cm", 72 - mm(5)) && close("2,5 cm × 2", mm(50)))
            #expect(close("−5 mm + 30", mm(25)) && close("-(10 - 30)", mm(20)))
            #expect(close("(10 cm) / (2 cm) × 1 cm", mm(50)), "lunghezza diviso lunghezza è un numero puro")
            #expect(Length.points(from: "5 cm × 2 cm") == nil, "un'area non è una lunghezza")
            #expect(Length.points(from: "5 / 0") == nil && Length.points(from: "3 / 1 cm") == nil)
            #expect(Length.points(from: "3 +") == nil && Length.points(from: "(3") == nil && Length.points(from: "3)") == nil)
            #expect(Length.points(from: "3 # 4") == nil && Length.points(from: "1.2.3") == nil && Length.points(from: "cm") == nil)
            #expect(Length.points(from: "10 + 2", defaultUnit: .points) == 12)
        }

        private func document(facing: Bool, inlines: [Inline], floatStyles: [FloatStyle] = []) -> Document {
            var document = Document(styles: .builtIn, lists: ListDefinition.builtIn, blocks: [.paragraph(Paragraph(styleName: "Testo",
                                    style: StyleSheet.builtIn.resolveParagraph(styleName: "Testo"), inlines: inlines))])
            document.floatStyles += floatStyles
            document.pageSetup = PageSetup(paperSize: CGSize(width: mm(170), height: mm(240)), top: mm(20), bottom: mm(25),
                                           left: mm(15), right: mm(35), facing: facing)
            return document
        }

        @Test("Pagine affacciate: lo specchio delle pagine pari sta dall'altra parte; le note a margine nel margine esterno vero")
        func facingPages() throws {
            let filler = String(repeating: "riempitivo ", count: 900)
            let postil = FloatStyle(name: "Postille", placement: .outerMargin, reference: .none, showsRule: false)
            func note(_ text: String) -> Inline { .floating(FloatingObject(runs: [TextRun(text, style: body)], style: "Postille")) }
            let inlines: [Inline] = [.text(TextRun("Inizio", style: body)), note("prima"), .text(TextRun(" " + filler + "dopo", style: body)), note("seconda")]
            for facing in [false, true] {
                let document = document(facing: facing, inlines: inlines, floatStyles: [postil])
                let layout = PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
                #expect(layout.pages.count >= 2)
                let setup = layout.setup
                let text = layout.text.string as NSString
                for (index, page) in layout.pages.enumerated() {
                    let column = setup.textRect(forPage: index)
                    #expect(column.minX == (facing && index % 2 == 1 ? mm(35) : mm(15)), "pagina \(index + 1)")
                    let body = page.lines.filter { !$0.isNote }
                    #expect(body.allSatisfy { abs($0.origin.x - column.minX) < 0.5 }, "le righe partono dallo specchio della pagina \(index + 1)")
                }
                // La nota a margine della pagina pari: a sinistra, nel margine esterno (35 mm con le pagine affacciate).
                let even = try #require(layout.pages.firstIndex { $0.lines.contains { $0.noteRange.map { text.substring(with: $0) } == "seconda" } })
                #expect(even % 2 == 1)
                let line = try #require(layout.pages[even].lines.first { $0.noteRange.map { text.substring(with: $0) } == "seconda" })
                let column = setup.textRect(forPage: even)
                #expect(line.origin.x >= 0 && line.origin.x < column.minX, "a sinistra dello specchio")
                if facing {
                    // Nel margine esterno, largo 35 mm: ci sta intera, senza toccare lo specchio. (Senza pagine affacciate a
                    // sinistra c'è il margine di 15 mm, e una parola più larga sconfina: com'era già.)
                    #expect(line.origin.x + CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil)) < column.minX)
                    #expect(line.origin.x < mm(12), "nel margine esterno largo, non stretta contro lo specchio")
                }
            }
        }

        @Test("Nel file: facing=\"on\"; un valore diverso rende il file non valido")
        func format() throws {
            let document = document(facing: true, inlines: [.text(TextRun("Prova", style: body))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("facing=\"on\""))
            let reread = try DocumentFormat.document(from: written)
            #expect(reread.pageSetup.facing && abs(reread.pageSetup.right - mm(35)) < 0.01)
            #expect(!DocumentFormat.string(for: self.document(facing: false, inlines: [.text(TextRun("Prova", style: body))])).contains("facing"))
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: written.replacingOccurrences(of: "facing=\"on\"", with: "facing=\"forse\"")) }
        }
    }
}
