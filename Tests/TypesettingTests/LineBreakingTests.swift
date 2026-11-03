import AppKit
import CoreText
import Testing
import Typesetting

extension TypesettingSuite {
    @Suite("A capo ottimali (Knuth–Plass)")
    struct LineBreakingTests {
        private let italian = "“Tipografia” è una parola che usiamo con leggerezza. La sillabazione automatica delle parole particolarmente lunghe migliora notevolmente la composizione dei paragrafi giustificati, soprattutto quando le colonne sono strette e le parole straordinariamente ingombranti. Il risultato è un grigio più uniforme, senza quei larghi fiumi di bianco che attraversano la pagina."
        /// La pagina del documento di prova usato a schermo: A5 con margini di 20 mm, giustezza di 108 mm.
        private let a5 = PageSetup(paperSize: CGSize(width: PageSetup.points(fromMillimetres: 148), height: PageSetup.points(fromMillimetres: 210)),
                                   top: 56.7, bottom: 56.7, left: 56.7, right: 56.7)

        private func lines(_ text: String, _ breaking: LayoutOptions.LineBreaking, alignment: NSTextAlignment = .justified,
                           language: String? = "it", size: CGFloat = 16, setup: PageSetup? = nil,
                           opticalMargins: Bool = false, tracking: Bool = false,
                           expansionLimit: Double = LayoutOptions.defaultGlyphExpansionLimit) throws -> [PlacedLine] {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            let attributed = NSAttributedString(string: text, attributes: [.font: try TestFonts.hoefler(size: size), .paragraphStyle: style])
            return PageLayout.layout(attributed, setup: setup ?? a5, options: LayoutOptions(
                appliesFontTracking: tracking, usesOpticalMargins: opticalMargins, glyphExpansionLimit: expansionLimit,
                hyphenationLanguage: language, lineBreaking: breaking)).pages.flatMap(\.lines)
        }

        /// Di quanto la riga, alla sua larghezza naturale, è più corta (positivo) o più lunga della giustezza, in frazione.
        private func slack(_ line: PlacedLine, in text: String, width: CGFloat, font: CTFont) -> Double {
            var piece = (text as NSString).substring(with: line.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.endsWithHyphen { piece += "-" }
            let natural = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: piece, attributes: [.font: font])), nil, nil, nil)
            return (Double(width) - natural) / Double(width)
        }

        @Test("Sul paragrafo di prova: righe più uniformi della scelta riga per riga, e mai più di due trattini di seguito")
        func betterThanFirstFit() throws {
            let greedy = try lines(italian, .firstFit), optimal = try lines(italian, .optimal)
            let font = try TestFonts.hoefler(size: 16)
            let width = a5.textRect.width
            // La riga più larga (esclusa l'ultima, che non si giustifica): 19% riga per riga, 10% con la scelta ottimale.
            let worstGreedy = greedy.dropLast(2).map { slack($0, in: italian, width: width, font: font) }.max() ?? 0
            let worstOptimal = optimal.dropLast(2).map { slack($0, in: italian, width: width, font: font) }.max() ?? 0
            #expect(worstGreedy > 0.18)
            #expect(worstOptimal < 0.11)

            var run = 0, longest = 0
            for line in optimal {
                run = line.endsWithHyphen ? run + 1 : 0
                longest = max(longest, run)
            }
            #expect(longest <= 2)
            // In una colonna di 40 caratteri con parole italiane lunghe qualche trattino resta inevitabile.
            #expect(optimal.filter { $0.endsWithHyphen }.count <= 4)
        }

        @Test("Il limite di due trattini consecutivi vale anche dove il minimo matematico ne vorrebbe di più")
        func hyphenLadderIsCapped() throws {
            let text = String(repeating: "straordinariamente particolarmente incomprensibilmente ", count: 12)
            let narrow = PageSetup(paperSize: CGSize(width: 240, height: 2000), top: 20, bottom: 20, left: 20, right: 20)
            let all = try lines(text, .optimal, size: 14, setup: narrow)
            #expect(all.contains { $0.endsWithHyphen })
            var run = 0, longest = 0
            for line in all {
                run = line.endsWithHyphen ? run + 1 : 0
                longest = max(longest, run)
            }
            #expect(longest <= 2)
            #expect(all.map(\.range.length).reduce(0, +) == (text as NSString).length)
        }

        @Test("Le righe sillabate non vengono compresse")
        func hyphenatedLinesAreNotSqueezed() throws {
            let font = try TestFonts.hoefler(size: 16)
            for width in stride(from: 200.0, through: 400.0, by: 20.0) {
                let setup = PageSetup(paperSize: CGSize(width: width + 40, height: 3000), top: 20, bottom: 20, left: 20, right: 20)
                for line in try lines(italian, .optimal, setup: setup) where line.endsWithHyphen {
                    // Larghezza naturale non superiore alla giustezza: la riga può solo essere allargata.
                    #expect(slack(line, in: italian, width: width, font: font) > -0.001, "giustezza \(width)")
                }
            }
        }

        @Test("L'ultima parola del paragrafo non viene divisa")
        func lastWordStaysWhole() throws {
            // Larghezze diverse, per incontrare anche i casi in cui dividere l'ultima parola converrebbe.
            for width in stride(from: 180.0, through: 420.0, by: 12.0) {
                let setup = PageSetup(paperSize: CGSize(width: width + 40, height: 3000), top: 20, bottom: 20, left: 20, right: 20)
                let all = try lines(italian, .optimal, setup: setup)
                guard let last = all.last, let penultimate = all.dropLast().last, penultimate.endsWithHyphen else { continue }
                // Se la penultima riga finisce con un trattino, la parola divisa non è l'ultima: dopo ce ne sono altre.
                let ending = (italian as NSString).substring(with: last.range)
                #expect(ending.contains(" "), "giustezza \(width): ultima riga «\(ending)»")
            }
        }

        @Test("Nessun carattere perso; ogni riga giustificata arriva esattamente al margine")
        func soundness() throws {
            let all = try lines(italian, .optimal)
            #expect(all.map(\.range.length).reduce(0, +) == (italian as NSString).length)
            #expect(zip(all, all.dropFirst()).allSatisfy { NSMaxRange($0.range) == $1.range.location })
            for line in all.dropLast(2) {
                let end = line.origin.x + CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line.line))
                #expect(abs(end - a5.textRect.maxX) < 0.05)
            }
        }

        @Test("Senza giustificazione nessuna riga esce dalla giustezza")
        func raggedStaysInside() throws {
            for line in try lines(italian, .optimal, alignment: .left) {
                let end = line.origin.x + CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line.line))
                #expect(end <= a5.textRect.maxX + 0.05)
            }
        }

        @Test("Nel testo centrato i bianchi laterali sono uguali in ogni riga")
        func centeredVisibleBounds() throws {
            for opticalMargins in [false, true] {
                for line in try lines("T\nx\nHoefler\nfi", .optimal, alignment: .center, opticalMargins: opticalMargins) {
                    let bounds = CTLineGetImageBounds(line.line, nil)
                    #expect(!bounds.isNull && !bounds.isEmpty)
                    let left = line.origin.x + bounds.minX - a5.textRect.minX
                    let right = a5.textRect.maxX - line.origin.x - bounds.maxX
                    #expect(abs(left - right) < 0.01, "margini ottici \(opticalMargins), riga \(line.range): bianco sinistro \(left), destro \(right)")
                }
            }
        }

        @Test("La microtipografia espande i glifi entro il 2%, mai sull'ultima riga o senza giustificazione")
        func restrainedGlyphExpansion() throws {
            let text = "La costiera, formata dal deposito di tre grossi torrenti, scende appoggiata a due monti contigui, l’uno detto di san Martino, l’altro, con voce lombarda, il Resegone, dai molti suoi cocuzzoli in fila, che in vero lo fanno somigliare a una sega: talché non è chi, al primo vederlo, purché sia di fronte, come per esempio di su le mura di Milano che guardano a settentrione, non lo discerna tosto, a un tal contrassegno, in quella lunga e vasta giogaia, dagli altri monti di nome più oscuro e di forma più comune."
            func factors(_ line: PlacedLine) -> [Double] {
                (CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []).map { run in
                    let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    return Double(CTFontGetMatrix(font).a)
                }
            }

            let all = try lines(text, .optimal, size: 12, setup: .a4, opticalMargins: true, tracking: true)
            let expanded = all.dropLast().flatMap(factors)
            #expect(expanded.contains { abs($0 - 1) > 0.000_001 })
            #expect(expanded.allSatisfy { (0.979_999...1.020_001).contains($0) })
            #expect(all.last.map(factors)?.allSatisfy { abs($0 - 1) < 0.000_001 } == true)
            #expect(all.first?.endsWithHyphen == false, "l'espansione evita la divisione di «contigui»")

            let ragged = try lines(text, .optimal, alignment: .left, size: 12, setup: .a4, opticalMargins: true, tracking: true)
            #expect(ragged.flatMap(factors).allSatisfy { abs($0 - 1) < 0.000_001 })

            let off = try lines(text, .optimal, size: 12, setup: .a4, opticalMargins: true, tracking: true, expansionLimit: 0)
            #expect(off.flatMap(factors).allSatisfy { abs($0 - 1) < 0.000_001 }, "a zero la microtipografia è spenta")
            let strong = try lines(text, .optimal, size: 12, setup: .a4, opticalMargins: true, tracking: true, expansionLimit: 0.03)
            #expect(strong.dropLast().flatMap(factors) != expanded, "cambiare intensità cambia davvero la composizione")
            #expect(strong.dropLast().flatMap(factors).allSatisfy { (0.969_999...1.030_001).contains($0) })

            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let layout = PageLayout.layout(NSAttributedString(string: text, attributes: [.font: try TestFonts.hoefler(size: 12), .paragraphStyle: style]),
                                           setup: .a4, options: LayoutOptions(appliesFontTracking: true, usesOpticalMargins: true, hyphenationLanguage: "it"))
            #expect(PDFRenderer.pdfData(for: layout).count > 1_000)
        }

        @Test("L'ultima riga non resta troppo corta se esiste un'alternativa")
        func avoidsSingleWordLastLine() throws {
            let text = "Per un buon pezzo, la costa sale con un pendìo lento e continuo; poi si rompe in poggi e in valloncelli, in erte e in ispianate, secondo l’ossatura de’ due monti, e il lavoro dell’acque. Il lembo estremo, tagliato dalle foci de’ torrenti, è quasi tutto ghiaia e ciottoloni; il resto, campi e vigne, sparse di terre, di ville, di casali; in qualche parte boschi, che si prolungano su per la montagna."
            let all = try lines(text, .optimal, size: 12, setup: .a4, opticalMargins: true, tracking: true)
            let last = try #require(all.last)
            let ending = (text as NSString).substring(with: last.range).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(ending.split(whereSeparator: \.isWhitespace).count >= 3)
        }

        @Test("Senza lingua non si sillaba, e si resta nella giustezza")
        func noLanguage() throws {
            let all = try lines(italian, .optimal, language: nil)
            #expect(all.allSatisfy { !$0.endsWithHyphen })
            #expect(all.map(\.range.length).reduce(0, +) == (italian as NSString).length)
        }

        @Test("Casi limite: una riga sola, a capo scritto dentro il paragrafo, parola più larga della riga")
        func edgeCases() throws {
            #expect(try lines("Breve.", .optimal).filter { $0.range.length > 0 }.count == 1)

            // Un a capo scritto (U+2028) va rispettato, e la riga che lo precede non si allarga fino al margine.
            let forced = "Prima riga breve\u{2028}seconda riga dopo l'a capo scritto, abbastanza lunga da andare a capo almeno una volta nel paragrafo."
            let forcedLines = try lines(forced, .optimal)
            #expect(forcedLines[0].range == NSRange(location: 0, length: 17))
            let firstEnd = forcedLines[0].origin.x + CGFloat(CTLineGetTypographicBounds(forcedLines[0].line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(forcedLines[0].line))
            #expect(firstEnd < a5.textRect.maxX - 50)

            // Una «parola» senza punti di divisione, più larga della colonna: nessun errore e nessun carattere perso.
            let narrow = PageSetup(paperSize: CGSize(width: 160, height: 2000), top: 20, bottom: 20, left: 20, right: 20)
            let long = "prima 12345678901234567890123456789012345678901234567890 dopo"
            let longLines = try lines(long, .optimal, setup: narrow)
            #expect(longLines.map(\.range.length).reduce(0, +) == (long as NSString).length)
        }

        @Test("Cursore e clic restano coerenti con gli a capo ottimali e le righe sillabate")
        func caretRoundTrip() throws {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let layout = PageLayout.layout(
                NSAttributedString(string: italian, attributes: [.font: try TestFonts.hoefler(size: 16), .paragraphStyle: style]), setup: a5,
                options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: true, hyphenationLanguage: "it"))
            for index in 0...layout.text.length {
                let caret = try #require(layout.caret(at: index))
                let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: caret.page))
                #expect(hit.index == index, "posizione \(index)")
            }
        }

        @Test("Un documento lungo si compone in tempi compatibili con la scrittura")
        func speed() throws {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            // Circa 30 000 caratteri in 80 paragrafi tutti diversi, perché la memoria degli a capo non aiuti.
            let text = (0..<80).map { "Paragrafo \($0). " + italian }.joined(separator: "\n")
            let attributed = NSAttributedString(string: text, attributes: [.font: try TestFonts.hoefler(size: 12), .paragraphStyle: style])
            let options = LayoutOptions(appliesFontTracking: true, usesOpticalMargins: true, hyphenationLanguage: "it")
            let clock = ContinuousClock()
            let cold = clock.measure { _ = PageLayout.layout(attributed, options: options) }
            let warm = clock.measure { _ = PageLayout.layout(attributed, options: options) }
            print("TEMPI: \((text as NSString).length) caratteri, prima composizione \(cold), ricomposizione \(warm)")
            #expect(cold < .seconds(2))
            #expect(warm < .milliseconds(400))
        }
    }
}
