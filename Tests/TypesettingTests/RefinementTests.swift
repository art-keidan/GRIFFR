import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Margini ottici e sillabazione")
    struct RefinementTests {
        private func attributes(_ alignment: NSTextAlignment = .left, size: CGFloat = 24) throws -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            return [.font: try TestFonts.hoefler(size: size), .paragraphStyle: style]
        }

        private let optical = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: true, lineBreaking: .firstFit)
        private let plain = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)

        /// Il punto in cui finisce l'ultimo glifo visibile della riga.
        private func visibleEnd(_ line: PlacedLine) -> CGFloat {
            line.origin.x + CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line.line))
        }

        // I valori vengono dalla tabella opbd di Hoefler Text a corpo 24, misurati nella fase 0:
        // virgoletta aperta 2,16 a sinistra; punto 1,80 a destra. Il trattino segue una regola nostra.

        /// Di quanto sporge un trattino a fine riga perché il centro del suo inchiostro cada sul margine.
        private func hyphenOverhang(size: CGFloat) throws -> CGFloat {
            let font = try TestFonts.hoefler(size: size)
            var glyph = CGGlyph(Shaper.glyphIDs(for: "-", font: font)[0])
            var box = CGRect.zero, advance = CGSize.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &box, 1)
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            return advance.width - box.midX
        }

        @Test("A sinistra la virgoletta sporge nel margine di 2,16 pt; una lettera normale no")
        func leftEdge() throws {
            let text = NSAttributedString(string: "\u{201C}To be\u{201D}\nAvalanche", attributes: try attributes())
            let margin = PageSetup.a4.textRect.minX
            let lines = PageLayout.layout(text, options: optical).pages[0].lines
            #expect(abs(lines[0].origin.x - (margin - 2.16)) < 0.01)
            #expect(abs(lines[1].origin.x - margin) < 0.01)
            let untouched = PageLayout.layout(text, options: plain).pages[0].lines
            #expect(abs(untouched[0].origin.x - margin) < 0.01)
        }

        @Test("A destra il punto sporge di 1,80 pt, come dice il font")
        func rightEdge() throws {
            let text = NSAttributedString(string: "Avalanche.", attributes: try attributes(.right))
            let edge = PageSetup.a4.textRect.maxX
            #expect(abs(visibleEnd(PageLayout.layout(text, options: optical).pages[0].lines[0]) - (edge + 1.80)) < 0.01)
            #expect(abs(visibleEnd(PageLayout.layout(text, options: plain).pages[0].lines[0]) - edge) < 0.01)
        }

        @Test("Un trattino a fine riga sta a cavallo del margine: metà dentro, metà fuori")
        func hyphenStraddlesMargin() throws {
            let overhang = try hyphenOverhang(size: 24)
            // Circa metà dell'avanzamento del glifo (7,82 pt a corpo 24), contro l'1,80 della tabella del font.
            #expect(abs(overhang - 3.91) < 0.05)
            let edge = PageSetup.a4.textRect.maxX
            let line = PageLayout.layout(NSAttributedString(string: "Avalanche-", attributes: try attributes(.right)), options: optical).pages[0].lines[0]
            #expect(abs(visibleEnd(line) - (edge + overhang)) < 0.01)
            // Il centro dell'inchiostro del trattino cade esattamente sul margine.
            let glyphs = Shaper.glyphs(in: line.line)
            let font = try TestFonts.hoefler(size: 24)
            var glyph = try #require(glyphs.last).id, box = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &box, 1)
            let hyphenStart = visibleEnd(line) - (try #require(glyphs.last).advance)
            #expect(abs(hyphenStart + box.midX - edge) < 0.01)
        }

        @Test("Anche il trattino di sillabazione sta a cavallo del margine, nel giustificato")
        func hyphenationHyphenStraddlesMargin() throws {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let text = NSAttributedString(string: italian, attributes: [.font: try TestFonts.hoefler(size: 14), .paragraphStyle: style])
            let lines = PageLayout.layout(text, setup: narrow, options: LayoutOptions(
                appliesFontTracking: true, usesOpticalMargins: true, hyphenationLanguage: "it")).pages[0].lines
            let overhang = try hyphenOverhang(size: 14)
            // La larghezza della riga comprende la spaziatura trak dopo il trattino (negativa): il glifo finisce
            // quindi un po' oltre la fine misurata della riga.
            let tracking = try #require(Tracking.normalTracking(for: try TestFonts.hoefler(size: 14)))
            let hyphenated = lines.dropLast().filter { $0.endsWithHyphen }
            #expect(!hyphenated.isEmpty)
            for line in hyphenated {
                #expect(abs(visibleEnd(line) - tracking - (narrow.textRect.maxX + overhang)) < 0.02)
            }
        }

        @Test("Davanti al trattino di sillabazione non si applica la spaziatura trak")
        func noTrackingBeforeHyphen() throws {
            // «leg» a corpo 24 con la spaziatura trak di Hoefler Text (−0,36 pt dopo ogni glifo).
            let tracked = NSMutableAttributedString(string: "leg", attributes: [.font: try TestFonts.hoefler(size: 24)])
            TextStyling.syncFontTracking(in: tracked, range: NSRange(location: 0, length: 3), enabled: true)
            tracked.removeAttribute(.fontTracking, range: NSRange(location: 0, length: 3))
            let plainAdvances = Shaper.glyphs(for: "leg-", font: try TestFonts.hoefler(size: 24)).map(\.advance)

            let kept = Shaper.glyphs(in: PageLayout.hyphenatedLine(paragraph: tracked, start: 0, end: 3, hyphen: "-", tracked: false).line).map(\.advance)
            let removed = Shaper.glyphs(in: PageLayout.hyphenatedLine(paragraph: tracked, start: 0, end: 3, hyphen: "-", tracked: true).line).map(\.advance)
            // Le prime due lettere restano spaziate; la «g» davanti al trattino torna alla distanza del font.
            #expect(abs(removed[0] - (plainAdvances[0] - 0.36)) < 0.001)
            #expect(abs(removed[1] - (plainAdvances[1] - 0.36)) < 0.001)
            #expect(abs(removed[2] - plainAdvances[2]) < 0.001)
            #expect(abs(kept[2] - (plainAdvances[2] - 0.36)) < 0.001, "senza la correzione la g sarebbe più vicina al trattino")
        }

        @Test("Il trattino di sillabazione non si avvicina alla lettera: l'avvicinamento del font si annulla, l'allontanamento resta")
        func hyphenKeepsItsDistance() throws {
            let font = try TestFonts.hoefler(size: 24)
            func natural(_ letter: String) -> CGFloat { Shaper.glyphs(for: letter, font: font)[0].advance }
            // Hoefler Text avvicina il trattino dopo «r» (−1,46 pt a corpo 24) e «t», e lo allontana dopo «g» (+0,72).
            #expect(abs(Shaper.glyphs(for: "r-", font: font)[0].advance - (natural("r") - 1.464)) < 0.001)
            #expect(abs(Shaper.glyphs(for: "g-", font: font)[0].advance - (natural("g") + 0.72)) < 0.001)

            for tracked in [false, true] {
                func lastLetterAdvance(_ word: String) -> CGFloat {
                    let paragraph = NSMutableAttributedString(string: word, attributes: [.font: font])
                    if tracked {
                        TextStyling.syncFontTracking(in: paragraph, range: NSRange(location: 0, length: paragraph.length), enabled: true)
                        paragraph.removeAttribute(.fontTracking, range: NSRange(location: 0, length: paragraph.length))
                    }
                    let glyphs = Shaper.glyphs(in: PageLayout.hyphenatedLine(paragraph: paragraph, start: 0, end: paragraph.length, hyphen: "-", tracked: tracked).line)
                    return glyphs[glyphs.count - 2].advance
                }
                #expect(abs(lastLetterAdvance("mar") - natural("r")) < 0.001)
                #expect(abs(lastLetterAdvance("lat") - natural("t")) < 0.001)
                #expect(abs(lastLetterAdvance("leg") - (natural("g") + 0.72)) < 0.001)
                #expect(abs(lastLetterAdvance("ma") - natural("a")) < 0.001)
            }
        }

        @Test("Una legatura in fondo alla riga sillabata resta legatura, anche con la spaziatura trak")
        func ligatureBeforeHyphen() throws {
            let font = try TestFonts.hoefler(size: 24)
            let paragraph = NSMutableAttributedString(string: "affi", attributes: [.font: font])
            TextStyling.syncFontTracking(in: paragraph, range: NSRange(location: 0, length: 4), enabled: true)
            paragraph.removeAttribute(.fontTracking, range: NSRange(location: 0, length: 4))
            let glyphs = Shaper.glyphs(in: PageLayout.hyphenatedLine(paragraph: paragraph, start: 0, end: 4, hyphen: "-", tracked: true).line)
            // a, ffi (glifo 631), trattino
            #expect(glyphs.map { Int($0.id) } == Shaper.glyphIDs(for: "affi-", font: font))
            #expect(glyphs.count == 3 && glyphs[1].id == 631)
            #expect(PageLayout.hyphenJoin(paragraph: paragraph, end: 4, hyphen: "-", tracked: true).cluster == NSRange(location: 1, length: 3))
        }

        @Test("Nel giustificato le righe che finiscono con un trattino lo portano a cavallo del margine")
        func justifiedEdge() throws {
            // Ogni parola finisce con un trattino, quindi ogni riga piena finisce con un trattino.
            let text = NSAttributedString(string: String(repeating: "minister- ", count: 30), attributes: try attributes(.justified))
            let rect = PageSetup.a4.textRect
            let lines = PageLayout.layout(text, options: optical).pages[0].lines
            #expect(lines.count > 3)
            for line in lines.dropLast(2) {
                #expect(abs(line.origin.x - rect.minX) < 0.01, "la «m» non ha rientro ottico")
                #expect(abs(visibleEnd(line) - (rect.maxX + (try hyphenOverhang(size: 24)))) < 0.02)
            }
        }

        @Test("Il cursore segue la riga spostata dai margini ottici")
        func caretFollows() throws {
            let text = NSAttributedString(string: "\u{201C}To be\u{201D}", attributes: try attributes())
            let layout = PageLayout.layout(text, options: optical)
            #expect(abs(try #require(layout.caret(at: 0)).rect.minX - (PageSetup.a4.textRect.minX - 2.16)) < 0.01)
            for index in 0...text.length {
                let caret = try #require(layout.caret(at: index))
                #expect(try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: 0)).index == index)
            }
        }

        // MARK: Sillabazione

        private let italian = "La sillabazione automatica delle parole particolarmente lunghe migliora notevolmente la composizione tipografica dei paragrafi giustificati, soprattutto quando le colonne sono strette e le parole straordinariamente ingombranti."
        /// Una colonna stretta: 200 pt di larghezza utile.
        private let narrow = PageSetup(paperSize: CGSize(width: 240, height: 2000), top: 20, bottom: 20, left: 20, right: 20)

        private func italianLayout(language: String?, alignment: NSTextAlignment = .justified) throws -> DocumentLayout {
            PageLayout.layout(NSAttributedString(string: italian, attributes: try attributes(alignment, size: 14)), setup: narrow,
                              options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, hyphenationLanguage: language, lineBreaking: .firstFit))
        }

        @Test("Riga per riga: con la lingua indicata le parole lunghe si dividono; senza, no")
        func hyphenates() throws {
            let with = try italianLayout(language: "it").pages[0].lines
            let without = try italianLayout(language: nil).pages[0].lines
            #expect(without.allSatisfy { !$0.endsWithHyphen })
            let hyphenated = with.filter(\.endsWithHyphen)
            #expect(!hyphenated.isEmpty)
            #expect(with.count <= without.count, "sillabando non servono più righe")

            let string = italian as NSString
            for line in hyphenated {
                // La riga mostra un trattino che nel testo non c'è, e il taglio cade dentro una parola.
                let glyphs = Shaper.glyphs(in: line.line)
                #expect(glyphs.last.map { Int($0.id) } == Shaper.glyphIDs(for: "-", font: try TestFonts.hoefler(size: 14)).first)
                let cut = NSMaxRange(line.range)
                #expect(CharacterSet.letters.contains(try #require(Unicode.Scalar(string.character(at: cut - 1)))))
                #expect(CharacterSet.letters.contains(try #require(Unicode.Scalar(string.character(at: cut)))))
                // Il taglio è uno dei punti che il dizionario italiano del sistema ammette per quella parola.
                var wordStart = cut, wordEnd = cut
                while wordStart > 0, string.character(at: wordStart - 1) != 0x20 { wordStart -= 1 }
                while wordEnd < string.length, CharacterSet.letters.contains(Unicode.Scalar(string.character(at: wordEnd))!) { wordEnd += 1 }
                let allowed = CFStringGetHyphenationLocationBeforeIndex(string, cut + 1, CFRange(location: wordStart, length: wordEnd - wordStart), 0, Locale(identifier: "it") as CFLocale, nil)
                #expect(allowed == cut, "taglio in «\(string.substring(with: NSRange(location: wordStart, length: wordEnd - wordStart)))»")
            }
        }

        @Test("Mai più di due righe sillabate di seguito")
        func consecutiveHyphensAreLimited() throws {
            // Parole lunghissime in una colonna stretta: senza limite quasi ogni riga finirebbe con un trattino.
            let text = String(repeating: "straordinariamente particolarmente incomprensibilmente ", count: 12)
            let lines = PageLayout.layout(NSAttributedString(string: text, attributes: try attributes(.justified, size: 14)), setup: narrow,
                                          options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, hyphenationLanguage: "it", lineBreaking: .firstFit)).pages[0].lines
            #expect(lines.contains { $0.endsWithHyphen })
            var run = 0, longest = 0
            for line in lines {
                run = line.endsWithHyphen ? run + 1 : 0
                longest = max(longest, run)
            }
            #expect(longest <= 2)
        }

        @Test("Le righe sillabate non perdono caratteri, stanno nella colonna e restano giustificate")
        func hyphenatedLinesAreSound() throws {
            let layout = try italianLayout(language: "it")
            let lines = layout.pages[0].lines
            #expect(lines.map(\.range.length).reduce(0, +) == (italian as NSString).length)
            #expect(zip(lines, lines.dropFirst()).allSatisfy { NSMaxRange($0.range) == $1.range.location })
            let rect = narrow.textRect
            for line in lines.dropLast() {
                #expect(abs(visibleEnd(line) - rect.maxX) < 0.02, "riga giustificata fino al margine")
            }
        }

        @Test("Cursore e clic funzionano anche sulle righe sillabate")
        func caretOnHyphenatedLines() throws {
            let layout = try italianLayout(language: "it", alignment: .left)
            let lines = layout.pages[0].lines
            let hyphenated = try #require(lines.first { $0.endsWithHyphen })
            for index in 0...layout.text.length {
                let caret = try #require(layout.caret(at: index))
                let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: 0))
                #expect(hit.index == index, "posizione \(index)")
            }
            // Un clic oltre il trattino porta alla fine della riga, cioè al punto del taglio, restando su quella riga.
            let end = try #require(layout.position(at: CGPoint(x: narrow.textRect.maxX + 50, y: hyphenated.origin.y), onPage: 0))
            #expect(end.index == NSMaxRange(hyphenated.range))
            #expect(end.affinity == .upstream)
            // Il cursore a fine riga sta prima del trattino, non dopo.
            let caretAtEnd = try #require(layout.caret(at: end.index, affinity: .upstream))
            #expect(caretAtEnd.rect.minX < hyphenated.origin.x + CGFloat(CTLineGetTypographicBounds(hyphenated.line, nil, nil, nil)) - 1)
        }

        @Test("Una lingua che non si sa sillabare (gotico) non divide le parole e non dà errori")
        func unsupportedLanguage() throws {
            #expect(try italianLayout(language: "got").pages[0].lines.allSatisfy { !$0.endsWithHyphen })
            #expect(LayoutOptions.hyphenationLanguages(among: ["it", "en", "la", "grc", "got"]) == ["it", "en", "la", "grc"])
        }
    }
}
