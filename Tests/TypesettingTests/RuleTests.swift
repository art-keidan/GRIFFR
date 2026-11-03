import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Regole: pezzi di testo che si trovano")
    struct RuleTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

        private func paragraph(_ text: String, style: String = "Testo", runs: [TextRun]? = nil) -> Block {
            .paragraph(Paragraph(styleName: style, style: StyleSheet.builtIn.resolveParagraph(styleName: style),
                                 inlines: (runs ?? [TextRun(text, style: body)]).map(Inline.text)))
        }

        private func document(_ blocks: [Block], rules: [TextRule]) -> Document {
            var document = Document(styles: .builtIn, lists: ListDefinition.builtIn, blocks: blocks)
            document.rules = rules
            return document
        }

        /// I tratti del testo con le regole applicate che hanno il maiuscoletto, come testo.
        private func smallCapsPieces(_ document: Document) -> [String] {
            let text = Rules.applied(document.rules, to: document.attributedString().text, sheet: document.styles)
            var pieces: [String] = []
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                guard let font = value as? NSFont, FontFeatures.settings(of: font as CTFont).contains(.aat(type: 3, selector: 3)) else { return }
                pieces.append((text.string as NSString).substring(with: range))
            }
            return pieces
        }

        private func found(_ target: TextRule.Target, in string: String) -> [String] {
            let text = NSAttributedString(string: string)
            let body = BodyText(text, paragraph: NSRange(location: 0, length: text.length))
            return body.ranges(of: target).map { (string as NSString).substring(with: $0) }
        }

        @Test("Che cosa trova ciascun tipo di regola")
        func targets() {
            #expect(found(.firstLetter, in: "«Nel mezzo del cammin»\n") == ["«N"])
            #expect(found(.firstWords(2), in: "Roma, città aperta.\n") == ["Roma, città"])
            #expect(found(.firstWords(1), in: "Roma, città aperta.\n") == ["Roma,"])
            #expect(found(.firstWords(9), in: "Due parole\n") == ["Due parole"], "se le parole sono meno, tutte")
            #expect(found(.firstSentence, in: "Prima frase. Seconda frase.\n") == ["Prima frase."])
            #expect(found(.words(.capitals), in: "L'ONU e l’UNESCO, non A né Roma né USA-UE.") == ["ONU", "UNESCO", "USA", "UE"],
                    "dopo l'apostrofo la sigla è una parola a sé")
            #expect(found(.words(.romanNumerals), in: "Nel libro IV, capitolo XIX, non in VIM né in IIII.") == ["IV", "XIX"])
            #expect(found(.words(.numbers), in: "Nel 1984, 2.000 o 3,5 a.C., non 12a.") == ["1984", "2.000", "3,5"])
            #expect(found(.words(.listed(["ibid", "cit", "uomo"])), in: "Ibid. e ibid., op. cit. dell'uomo") == ["ibid", "cit", "uomo"],
                    "maiuscole e minuscole contano")
            #expect(found(.firstLetter, in: "123 stelle") == ["1"])
            #expect(found(.firstLetter, in: "\u{FFFC} immagine").isEmpty, "un'immagine in testa non è una lettera")
        }

        @Test("Il testo delle note non conta e non si tocca")
        func notesAreSkipped() {
            let note = FloatingObject(runs: [TextRun("Una nota lunga.", style: body)])
            let doc = document([.paragraph(Paragraph(styleName: "Testo", inlines: [
                .text(TextRun("Prima", style: body)), .floating(note), .text(TextRun(" seconda terza.", style: body)),
            ]))], rules: [TextRule(target: .firstWords(2), styleName: "Maiuscoletto")])
            #expect(smallCapsPieces(doc) == ["Prima", " seconda"], "le due parole del corpo, senza la nota in mezzo")
        }

        @Test("Dentro quali paragrafi: di uno stile, primo dopo uno stile, primo del documento")
        func positions() {
            let blocks = [paragraph("Inizio del documento."), paragraph("Capitolo", style: "Titolo 1"), paragraph("Dopo il titolo."),
                          paragraph("Il secondo dopo."), paragraph("Una citazione.", style: "Citazione")]
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstWords(1), paragraphStyle: "Testo", position: .firstAfter("Titolo 1"),
                                                                      styleName: "Maiuscoletto")])) == ["Dopo"])
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstWords(1), position: .sequenceStart, styleName: "Maiuscoletto")])) == ["Inizio"])
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstLetter, paragraphStyle: "Citazione", styleName: "Maiuscoletto")])) == ["U"])
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstLetter, paragraphStyle: "Citazione", styleName: "Maiuscoletto",
                                                                      isEnabled: false)])).isEmpty, "una regola spenta non si applica")
        }

        @Test("Un valore dato a mano vale sopra la regola; la regola sopra lo stile; il testo non cambia")
        func precedence() throws {
            var big = body
            big.size = 15
            var styles = StyleSheet.builtIn
            var piccolo = NamedStyle(name: "Piccolo", target: .character)
            piccolo.values.size = 9
            piccolo.values.features = SmallCaps.lowercaseForms
            styles.styles.append(piccolo)
            var doc = document([paragraph("", runs: [TextRun("Grande ", style: big), TextRun("normale e resto.", style: body)])],
                               rules: [TextRule(target: .firstWords(2), styleName: "Piccolo")])
            doc.styles = styles
            let source = doc.attributedString().text
            let text = Rules.applied(doc.rules, to: source, sheet: doc.styles)
            #expect(text.string == source.string)
            let first = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let second = try #require(text.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
            let rest = try #require(text.attribute(.font, at: 20, effectiveRange: nil) as? NSFont)
            #expect(first.pointSize == 15, "il corpo dato a mano resta")
            #expect(FontFeatures.settings(of: first as CTFont).contains(.aat(type: 3, selector: 3)), "ma il maiuscoletto della regola si aggiunge")
            #expect(second.pointSize == 9, "il corpo dello stile del paragrafo cede a quello della regola")
            #expect(rest.pointSize == 12)
            #expect(text.attribute(.characterStyleName, at: 7, effectiveRange: nil) == nil, "la regola non scrive nomi di stile nel testo")
        }

        @Test("Il maiuscoletto di Hoefler Text cambia davvero i glifi, e la pagina composta li usa")
        func smallCapsReachTheLayout() throws {
            let font = CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil)
            let small = FontFeatures.font(font, with: SmallCaps.lowercaseForms)
            #expect(Shaper.glyphIDs(for: "abc", font: small) != Shaper.glyphIDs(for: "abc", font: font))
            let doc = document([paragraph("Primo paragrafo del documento.")], rules: [TextRule(target: .firstWords(1), styleName: "Maiuscoletto")])
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            let line = try #require(layout.pages.first?.lines.first?.line)
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            let fonts = runs.map { (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont }
            #expect(FontFeatures.settings(of: fonts[0]).contains(.aat(type: 3, selector: 3)))
            #expect(!FontFeatures.settings(of: try #require(fonts.last)).contains(.aat(type: 3, selector: 3)))
        }

        @Test("Il maiuscoletto delle sigle: dove il font ha la funzione cambia le maiuscole; Hoefler Text non l'ha")
        func smallCapsForAcronyms() throws {
            let hoefler = CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil)
            #expect(Shaper.glyphIDs(for: "ONU", font: FontFeatures.font(hoefler, with: SmallCaps.uppercaseForms)) == Shaper.glyphIDs(for: "ONU", font: hoefler))
            #expect(Shaper.glyphIDs(for: "abc", font: FontFeatures.font(hoefler, with: SmallCaps.lowercaseForms)) != Shaper.glyphIDs(for: "abc", font: hoefler))
            // Un font di sistema con la funzione (in OpenType, `c2sc`): Avenir Next.
            let avenir = CTFontCreateWithName("AvenirNext-Regular" as CFString, 12, nil)
            try #require(CTFontCopyPostScriptName(avenir) as String == "AvenirNext-Regular")
            #expect(Shaper.glyphIDs(for: "ONU", font: FontFeatures.font(avenir, with: SmallCaps.uppercaseForms)) != Shaper.glyphIDs(for: "ONU", font: avenir))
        }

        @Test("Nel file: la sezione delle regole; quelle senza stile non si scrivono; i refusi sono errori")
        func fileRoundTrip() throws {
            let rules = [
                TextRule(target: .firstWords(2), paragraphStyle: "Testo", position: .firstAfter("Titolo 1"), styleName: "Maiuscoletto"),
                TextRule(target: .firstLetter, position: .sequenceStart, styleName: "Forte", isEnabled: false),
                TextRule(target: .firstSentence, styleName: "Enfasi"),
                TextRule(target: .words(.capitals), styleName: "Maiuscoletto"),
                TextRule(target: .words(.romanNumerals), styleName: "Maiuscoletto"),
                TextRule(target: .words(.numbers), styleName: "Latino"),
                TextRule(target: .words(.listed(["ibid.", "cit."])), paragraphStyle: "Citazione", styleName: "Enfasi"),
            ]
            let doc = document([paragraph("Testo.")], rules: rules)
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<rule find=\"first-words\" count=\"2\" in=\"Testo\" after=\"Titolo 1\" style=\"Maiuscoletto\"/>"))
            #expect(written.contains("position=\"sequence-start\" style=\"Forte\" enabled=\"off\""))
            #expect(try DocumentFormat.document(from: written) == doc)

            let orphan = document([paragraph("Testo.")], rules: [TextRule(target: .firstLetter, styleName: "Inesistente")])
            #expect(!DocumentFormat.string(for: orphan).contains("<rules>"))
            #expect(!DocumentFormat.string(for: document([paragraph("Testo.")], rules: [])).contains("<rules>"), "un documento senza regole non cambia")

            let wrong = written.replacingOccurrences(of: "style=\"Forte\"", with: "style=\"Testo\"")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: wrong) }
            let typo = written.replacingOccurrences(of: "find=\"first-sentence\"", with: "find=\"first-sentense\"")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: typo) }
        }

        // MARK: Righe (tappa 7.2)

        private static let long = "Il primo paragrafo del capitolo è abbastanza lungo da occupare parecchie righe della pagina, così che si possa vedere bene dove finisce la prima riga, dove la seconda e dove comincia il resto del testo, che non deve prendere lo stile della regola in nessun caso."

        /// Il primo paragrafo con il suo a capo.
        private static var paragraphLength: Int { (long as NSString).length + 1 }

        /// Le righe del primo paragrafo e, per ciascuna, se tutti i suoi tratti hanno la funzione e se nessuno ce l'ha.
        private func lines(_ rules: [TextRule], text: String = Self.long, feature: FeatureSetting = .aat(type: 3, selector: 3)) -> [(range: NSRange, all: Bool, none: Bool)] {
            let doc = document([paragraph(text), paragraph("Un altro.")], rules: rules)
            let layout = PageLayout.layout(doc.attributedString().text, options: doc.layoutOptions)
            return layout.pages[0].lines.filter { $0.paragraphLocation == 0 }.map { placed in
                let flags = (CTLineGetGlyphRuns(placed.line) as? [CTRun] ?? []).map { run in
                    let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    return FontFeatures.settings(of: font).contains(feature)
                }
                return (placed.range, flags.allSatisfy { $0 }, !flags.contains(true))
            }
        }

        private func noneStyled(_ lines: some Collection<(range: NSRange, all: Bool, none: Bool)>) -> Bool {
            !lines.contains { !$0.none }
        }

        private func contiguous(_ lines: [(range: NSRange, all: Bool, none: Bool)], length: Int) -> Bool {
            var position = 0
            for line in lines {
                guard line.range.location == position else { return false }
                position = NSMaxRange(line.range)
            }
            return position == length
        }

        @Test("Prima riga: tutta nello stile, e la seconda comincia esattamente dove la prima finisce")
        func firstLine() {
            let plain = lines([])
            let ruled = lines([TextRule(target: .firstLines(1), styleName: "Maiuscoletto")])
            #expect(plain.count >= 3)
            #expect(ruled[0].all, "la prima riga è tutta in maiuscoletto")
            #expect(noneStyled(ruled.dropFirst()), "le altre no")
            #expect(contiguous(ruled, length: Self.paragraphLength), "nessun carattere perso o ripetuto tra le righe")
            #expect(ruled[0].range.length < plain[0].range.length, "il maiuscoletto è più largo: nella prima riga entra meno testo")
        }

        @Test("Prime N righe; un paragrafo più corto di N righe è tutto nello stile")
        func firstLines() {
            let two = lines([TextRule(target: .firstLines(2), styleName: "Maiuscoletto")])
            #expect(two[0].all && two[1].all && noneStyled(two.dropFirst(2)))
            #expect(contiguous(two, length: Self.paragraphLength))
            let short = lines([TextRule(target: .firstLines(3), styleName: "Maiuscoletto")], text: "Breve.")
            #expect(short.count == 1 && short[0].all)
        }

        @Test("Ultima riga: solo lei nello stile; con la prima riga insieme")
        func lastLine() {
            let ruled = lines([TextRule(target: .lastLine, styleName: "Maiuscoletto")])
            #expect(ruled.last?.all == true)
            #expect(noneStyled(ruled.dropLast()))
            #expect(contiguous(ruled, length: Self.paragraphLength))
            let both = lines([TextRule(target: .firstLines(1), styleName: "Maiuscoletto"), TextRule(target: .lastLine, styleName: "Maiuscoletto")])
            // Il testo dell'ultima riga naturale, in maiuscoletto, è più largo: può andare su due righe, tutte e due nello stile.
            let styledTail = both.reversed().prefix { $0.all }.count
            #expect(both.first?.all == true && styledTail >= 1 && noneStyled(both.dropFirst().dropLast(styledTail)))
            #expect(contiguous(both, length: Self.paragraphLength))
        }

        @Test("Le regole di riga nel file")
        func lineRulesInFile() throws {
            let doc = document([paragraph("Testo.")], rules: [TextRule(target: .firstLines(2), paragraphStyle: "Testo", styleName: "Maiuscoletto"),
                                                              TextRule(target: .lastLine, styleName: "Enfasi")])
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<rule find=\"first-lines\" count=\"2\" in=\"Testo\" style=\"Maiuscoletto\"/>"))
            #expect(written.contains("<rule find=\"last-line\" style=\"Enfasi\"/>"))
            #expect(try DocumentFormat.document(from: written) == doc)
        }

        // MARK: Condizioni e pagina (tappa 7.4)

        private func layout(_ paragraphs: [String], rules: [TextRule], extraStyles: [NamedStyle] = StyleSheet.ruleStyles) -> (DocumentLayout, Document) {
            var doc = document(paragraphs.map { paragraph($0) }, rules: rules)
            doc.styles.styles += extraStyles.filter { doc.styles.style(named: $0.name) == nil }
            return (PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions), doc)
        }

        private func isCentered(_ line: PlacedLine, in layout: DocumentLayout) -> Bool {
            let column = layout.setup.textRect
            return abs((line.origin.x - column.minX) - (column.width - line.width) / 2) < 1.5
        }

        @Test("Paragrafi di una sola riga → centrati; gli altri no; senza regola nessuno")
        func oneLineParagraphsCentered() throws {
            let rule = TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centrato")
            let texts = ["Una riga sola.", Self.long, "Un'altra riga sola."]
            let (ruled, doc) = layout(texts, rules: [rule])
            let placed = ruled.pages[0].lines
            let starts = [0, ("Una riga sola.\n" as NSString).length, ("Una riga sola.\n" as NSString).length + (Self.long as NSString).length + 1]
            func linesOf(_ start: Int) -> [PlacedLine] { placed.filter { $0.paragraphLocation == start } }
            #expect(isCentered(linesOf(starts[0])[0], in: ruled) && isCentered(linesOf(starts[2])[0], in: ruled))
            #expect(linesOf(starts[1]).count > 1 && !isCentered(linesOf(starts[1]).last!, in: ruled))
            #expect(ruled.layoutRulesApplied[starts[0]] == [rule] && ruled.layoutRulesApplied[starts[1]] == nil)
            let facts = try #require(ruled.paragraphFacts(at: 1, rules: doc.rules, sheet: doc.styles))
            #expect(facts.rules == [rule.summary], "l'ispettore la elenca")
            let (plain, _) = layout(texts, rules: [])
            #expect(!isCentered(plain.pages[0].lines[0], in: plain))
        }

        @Test("La condizione si controlla sul paragrafo naturale: il risultato è stabile anche se la smentisce")
        func naturalConditionIsStable() throws {
            var big = NamedStyle(name: "Grande", target: .character)
            big.values.size = 40
            let rule = TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Grande")
            let text = "Una riga che col corpo grande va a capo."
            let (ruled, doc) = layout([text], rules: [rule], extraStyles: [big])
            let lines = ruled.pages[0].lines.filter { $0.paragraphLocation == 0 }
            #expect(lines.count > 1, "ingrandito, il paragrafo non è più di una riga")
            let font = (CTRunGetAttributes((CTLineGetGlyphRuns(lines[0].line) as! [CTRun])[0]) as NSDictionary)[kCTFontAttributeName] as! CTFont
            #expect(CTFontGetSize(font) == 40, "ma la regola resta applicata: non si torna indietro")
            PageLayout.clearCaches()
            let again = PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions)
            #expect(again.pages[0].lines.count == ruled.pages[0].lines.count, "ricomponendo, lo stesso risultato")
        }

        @Test("Primo della pagina: solo i paragrafi con cui comincia una pagina")
        func firstOnPage() throws {
            let texts = (1...120).map { "Paragrafo numero \($0), di una riga." }
            let rule = TextRule(target: .paragraph, position: .firstOnPage, styleName: "Maiuscoletto")
            let (ruled, _) = layout(texts, rules: [rule])
            #expect(ruled.pages.count >= 2)
            let starts = Set(ruled.pages.compactMap { $0.lines.first?.paragraphLocation })
            #expect(Set(ruled.layoutRulesApplied.keys) == starts, "tutti e soli i paragrafi in testa a una pagina")
            let second = try #require(ruled.pages[1].lines.first)
            let font = (CTRunGetAttributes((CTLineGetGlyphRuns(second.line) as! [CTRun])[0]) as NSDictionary)[kCTFontAttributeName] as! CTFont
            #expect(FontFeatures.settings(of: font).contains(.aat(type: 3, selector: 3)))
        }

        @Test("Una condizione anche su una regola di contenuto; una regola di riga con condizione")
        func conditionOnContentAndLineRules() throws {
            let letter = TextRule(target: .firstLetter, condition: .init(.lines, .greaterOrEqual, 3), styleName: "Maiuscoletto")
            let (ruled, _) = layout(["Breve.", Self.long], rules: [letter])
            #expect(ruled.layoutRulesApplied.keys.sorted() == [("Breve.\n" as NSString).length], "solo il paragrafo lungo")
            let line = TextRule(target: .firstLines(1), condition: .init(.words, .greater, 10), styleName: "Maiuscoletto")
            let (lined, _) = layout(["Breve.", Self.long], rules: [line])
            let longLines = lined.pages[0].lines.filter { $0.paragraphLocation == ("Breve.\n" as NSString).length }
            let runs = CTLineGetGlyphRuns(longLines[0].line) as! [CTRun]
            #expect(runs.allSatisfy { FontFeatures.settings(of: (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont).contains(.aat(type: 3, selector: 3)) })
        }

        @Test("Nel file: paragrafo intero, primo della pagina, condizioni")
        func conditionsInFile() throws {
            var doc = document([paragraph("Testo.")], rules: [
                TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centrato"),
                TextRule(target: .firstLetter, paragraphStyle: "Testo", position: .firstOnPage, condition: .init(.lastLineFill, .less, 20), styleName: "Forte"),
            ])
            doc.styles.styles += StyleSheet.ruleStyles.filter { $0.name == "Centrato" }
            let written = DocumentFormat.string(for: doc)
            #expect(written.contains("<rule find=\"paragraph\" if=\"lines\" compare=\"eq\" value=\"1\" style=\"Centrato\"/>"))
            #expect(written.contains("position=\"page-start\" if=\"last-line-fill\" compare=\"lt\" value=\"20\""))
            #expect(try DocumentFormat.document(from: written) == doc)
            let wrong = written.replacingOccurrences(of: "find=\"paragraph\"", with: "find=\"first-letter\"")
            #expect(throws: DocumentFormatError.self, "uno stile di paragrafo solo al paragrafo intero") { try DocumentFormat.document(from: wrong) }
        }

        @Test("Un allineamento dato a mano vale sopra la regola di paragrafo")
        func ownAlignmentWins() throws {
            var right = StyleSheet.builtIn.resolveParagraph(styleName: "Testo")
            right.alignment = .right
            var doc = document([.paragraph(Paragraph(styleName: "Testo", style: right, inlines: [.text(TextRun("A destra.", style: body))]))],
                               rules: [TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centrato")])
            doc.styles.styles += StyleSheet.ruleStyles.filter { $0.name == "Centrato" }
            let layout = PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions)
            let line = layout.pages[0].lines[0]
            #expect(abs(line.origin.x + line.width - layout.setup.textRect.maxX) < 1.5, "resta a destra")
        }
    }
}
