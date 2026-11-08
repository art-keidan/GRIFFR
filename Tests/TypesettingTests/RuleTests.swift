import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// Le regole del motore, che nascono dalle formule contestuali degli stili: qui ogni prova scrive la regola che vuole
    /// e la mette, come formula, nello stile dei paragrafi che riguarda (in «Body», da cui derivano tutti, se non ne ha uno).
    @Suite("Regole: pezzi di testo che si trovano")
    struct RuleTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

        /// Lo stile «Centered»: fissa solo l'allineamento.
        static var centered: NamedStyle {
            var values = StyleValues()
            values.alignment = .center
            return NamedStyle(name: "Centered", target: .paragraph, values: values)
        }

        /// La formula che fa ciò che fa la regola.
        static func formula(_ rule: TextRule) -> StyleFormula {
            StyleFormula(operation: StylePropertyOperation(.set, .applyStyle, .styleName(rule.styleName)),
                         when: StyleCondition(position: rule.position, measurement: rule.condition), target: rule.target)
        }

        /// Il foglio con le regole messe come formule negli stili dei loro paragrafi; una regola spenta non c'è.
        static func sheet(_ base: StyleSheet, with rules: [TextRule]) -> StyleSheet {
            var sheet = base
            for rule in rules where rule.isEnabled {
                let owner = rule.paragraphStyle ?? StyleSheet.defaultParagraphStyle
                guard let index = sheet.styles.firstIndex(where: { $0.name == owner }) else { continue }
                sheet.styles[index].formulas.append(formula(rule))
            }
            return sheet
        }

        private func paragraph(_ text: String, style: String = "Body", runs: [TextRun]? = nil) -> Block {
            .paragraph(Paragraph(styleName: style, style: StyleSheet.builtIn.resolveParagraph(styleName: style),
                                 inlines: (runs ?? [TextRun(text, style: body)]).map(Inline.text)))
        }

        private func document(_ blocks: [Block], rules: [TextRule], extraStyles: [NamedStyle] = [centered]) -> Document {
            var base = StyleSheet.builtIn
            base.styles += extraStyles.filter { base.style(named: $0.name) == nil }
            return Document(styles: Self.sheet(base, with: rules), lists: ListDefinition.builtIn, blocks: blocks)
        }

        /// I tratti del testo con le regole applicate che hanno il maiuscoletto, come testo.
        private func smallCapsPieces(_ document: Document) -> [String] {
            let text = Rules.applied(to: document.attributedString().text, sheet: document.styles)
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

        @Test("Due formule condividono una selezione composta anche dopo la riapertura")
        func sharedSelection() throws {
            let selection = WordSelection(name: "Richiamo", source: .words, index: 2)
            var doc = document([paragraph("uno due tre"), paragraph("alfa beta gamma", style: "Heading 1")], rules: [
                TextRule(target: .selection(selection.id), paragraphStyle: "Body", styleName: "Small Caps"),
                TextRule(target: .selection(selection.id), paragraphStyle: "Heading 1", styleName: "Small Caps")
            ])
            doc.styles.selections = [selection]
            let xml = DocumentFormat.string(for: doc)
            var loaded = try DocumentFormat.document(from: xml)
            #expect(loaded.styles == doc.styles)
            #expect(loaded.styles.selections == [selection])
            #expect(smallCapsPieces(loaded) == ["due", "beta"])
            loaded.styles.selections[0].index = 3
            #expect(smallCapsPieces(loaded) == ["tre", "gamma"])
            loaded.styles.selections[0].index = 4
            #expect(smallCapsPieces(loaded).isEmpty)
            let sigla = WordSelection(name: "Seconda sigla", source: .capitals, index: 2)
            #expect(sigla.preview(in: "L'ONU e l'UNESCO") == "UNESCO")
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: xml.replacingOccurrences(of: "selection=\"" + selection.id.uuidString, with: "selection=\"bad"))
            }
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
            let doc = document([.paragraph(Paragraph(styleName: "Body", inlines: [
                .text(TextRun("Prima", style: body)), .floating(note), .text(TextRun(" seconda terza.", style: body)),
            ]))], rules: [TextRule(target: .firstWords(2), styleName: "Small Caps")])
            #expect(smallCapsPieces(doc) == ["Prima", " seconda"], "le due parole del corpo, senza la nota in mezzo")
        }

        @Test("Dentro quali paragrafi: di uno stile, primo dopo uno stile, primo del documento")
        func positions() {
            let blocks = [paragraph("Inizio del documento."), paragraph("Capitolo", style: "Heading 1"), paragraph("Dopo il titolo."),
                          paragraph("Il secondo dopo."), paragraph("Una citazione.", style: "Quotation")]
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstWords(1), paragraphStyle: "Body", position: .firstAfter("Heading 1"),
                                                                      styleName: "Small Caps")])) == ["Dopo"])
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstWords(1), position: .sequenceStart, styleName: "Small Caps")])) == ["Inizio"])
            #expect(smallCapsPieces(document(blocks, rules: [TextRule(target: .firstLetter, paragraphStyle: "Quotation", styleName: "Small Caps")])) == ["U"])
        }

        @Test("La regola vince sul valore dato a mano, che resta sospeso; un'eccezione lo protegge; il testo non cambia")
        func precedence() throws {
            var big = body
            big.size = 15
            var piccolo = NamedStyle(name: "Piccolo", target: .character)
            piccolo.values.size = 9
            piccolo.values.features = SmallCaps.lowercaseForms
            let doc = document([paragraph("", runs: [TextRun("Grande ", style: big), TextRun("normale e resto.", style: body)])],
                               rules: [TextRule(target: .firstWords(2), styleName: "Piccolo")], extraStyles: [piccolo])
            let source = doc.attributedString().text
            let text = Rules.applied(to: source, sheet: doc.styles)
            #expect(text.string == source.string)
            let first = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let second = try #require(text.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
            let rest = try #require(text.attribute(.font, at: 20, effectiveRange: nil) as? NSFont)
            #expect(first.pointSize == 9, "il corpo dato a mano è sospeso: vale quello della regola")
            #expect(FontFeatures.settings(of: first as CTFont).contains(.aat(type: 3, selector: 3)))
            #expect(second.pointSize == 9, "il corpo dello stile del paragrafo cede a quello della regola")
            #expect(rest.pointSize == 12)
            #expect(text.attribute(.characterStyleName, at: 7, effectiveRange: nil) == nil, "la regola non scrive nomi di stile nel testo")
            // «Keep … here»: un'eccezione sul corpo lascia vincere il valore dato a mano.
            let excepted = NSMutableAttributedString(attributedString: source)
            TextStyling.setRuleException(.size, true, in: excepted, range: NSRange(location: 0, length: 6))
            let kept = try #require(Rules.applied(to: excepted, sheet: doc.styles).attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(kept.pointSize == 15)
        }

        @Test("Il maiuscoletto di Hoefler Text cambia davvero i glifi, e la pagina composta li usa")
        func smallCapsReachTheLayout() throws {
            let font = CTFontCreateWithName("HoeflerText-Regular" as CFString, 12, nil)
            let small = FontFeatures.font(font, with: SmallCaps.lowercaseForms)
            #expect(Shaper.glyphIDs(for: "abc", font: small) != Shaper.glyphIDs(for: "abc", font: font))
            let doc = document([paragraph("Primo paragrafo del documento.")], rules: [TextRule(target: .firstWords(1), styleName: "Small Caps")])
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

        @Test("Nel file le regole sono formule degli stili; un elemento <rule> non si legge più")
        func fileRoundTrip() throws {
            let rules = [
                TextRule(target: .firstWords(2), paragraphStyle: "Body", position: .firstAfter("Heading 1"), styleName: "Small Caps"),
                TextRule(target: .firstLetter, position: .sequenceStart, styleName: "Strong"),
                TextRule(target: .firstSentence, styleName: "Emphasis"),
                TextRule(target: .words(.capitals), styleName: "Small Caps"),
                TextRule(target: .words(.romanNumerals), styleName: "Small Caps"),
                TextRule(target: .words(.numbers), styleName: "Latin"),
                TextRule(target: .words(.listed(["ibid.", "cit."])), paragraphStyle: "Quotation", styleName: "Emphasis"),
                TextRule(target: .firstLines(2), paragraphStyle: "Body", styleName: "Small Caps"),
                TextRule(target: .lastLine, styleName: "Emphasis"),
                TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centered"),
                TextRule(target: .firstLetter, paragraphStyle: "Body", position: .firstOnPage, condition: .init(.lastLineFill, .less, 20), styleName: "Strong"),
            ]
            let doc = document([paragraph("Testo.")], rules: rules)
            let written = DocumentFormat.string(for: doc)
            #expect(!written.contains("<rule "))
            #expect(try DocumentFormat.document(from: written).styles == doc.styles)
            let typo = written.replacingOccurrences(of: "find=\"first-sentence\"", with: "find=\"first-sentense\"")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: typo) }
            let old = written.replacingOccurrences(of: "<page ", with: "<rules>\n<rule find=\"first-letter\" style=\"Strong\"/>\n</rules>\n<page ")
            #expect(throws: DocumentFormatError.self, "le regole del documento non esistono più") { try DocumentFormat.document(from: old) }
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
            let ruled = lines([TextRule(target: .firstLines(1), styleName: "Small Caps")])
            #expect(plain.count >= 3)
            #expect(ruled[0].all, "la prima riga è tutta in maiuscoletto")
            #expect(noneStyled(ruled.dropFirst()), "le altre no")
            #expect(contiguous(ruled, length: Self.paragraphLength), "nessun carattere perso o ripetuto tra le righe")
            #expect(ruled[0].range.length < plain[0].range.length, "il maiuscoletto è più largo: nella prima riga entra meno testo")
        }

        @Test("Prime N righe; un paragrafo più corto di N righe è tutto nello stile")
        func firstLines() {
            let two = lines([TextRule(target: .firstLines(2), styleName: "Small Caps")])
            #expect(two[0].all && two[1].all && noneStyled(two.dropFirst(2)))
            #expect(contiguous(two, length: Self.paragraphLength))
            let short = lines([TextRule(target: .firstLines(3), styleName: "Small Caps")], text: "Breve.")
            #expect(short.count == 1 && short[0].all)
        }

        @Test("Ultima riga: solo lei nello stile; con la prima riga insieme")
        func lastLine() {
            let ruled = lines([TextRule(target: .lastLine, styleName: "Small Caps")])
            #expect(ruled.last?.all == true)
            #expect(noneStyled(ruled.dropLast()))
            #expect(contiguous(ruled, length: Self.paragraphLength))
            let both = lines([TextRule(target: .firstLines(1), styleName: "Small Caps"), TextRule(target: .lastLine, styleName: "Small Caps")])
            // Il testo dell'ultima riga naturale, in maiuscoletto, è più largo: può andare su due righe, tutte e due nello stile.
            let styledTail = both.reversed().prefix { $0.all }.count
            #expect(both.first?.all == true && styledTail >= 1 && noneStyled(both.dropFirst().dropLast(styledTail)))
            #expect(contiguous(both, length: Self.paragraphLength))
        }

        // MARK: Condizioni e pagina (tappa 7.4)

        private func layout(_ paragraphs: [String], rules: [TextRule], extraStyles: [NamedStyle] = [centered]) -> (DocumentLayout, Document) {
            let doc = document(paragraphs.map { paragraph($0) }, rules: rules, extraStyles: extraStyles)
            return (PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions), doc)
        }

        private func isCentered(_ line: PlacedLine, in layout: DocumentLayout) -> Bool {
            let column = layout.setup.textRect
            return abs((line.origin.x - column.minX) - (column.width - line.width) / 2) < 1.5
        }

        @Test("Paragrafi di una sola riga → centrati; gli altri no; senza regola nessuno")
        func oneLineParagraphsCentered() throws {
            let rule = TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centered")
            let texts = ["Una riga sola.", Self.long, "Un'altra riga sola."]
            let (ruled, doc) = layout(texts, rules: [rule])
            let placed = ruled.pages[0].lines
            let starts = [0, ("Una riga sola.\n" as NSString).length, ("Una riga sola.\n" as NSString).length + (Self.long as NSString).length + 1]
            func linesOf(_ start: Int) -> [PlacedLine] { placed.filter { $0.paragraphLocation == start } }
            #expect(isCentered(linesOf(starts[0])[0], in: ruled) && isCentered(linesOf(starts[2])[0], in: ruled))
            #expect(linesOf(starts[1]).count > 1 && !isCentered(linesOf(starts[1]).last!, in: ruled))
            let applied = try #require(ruled.layoutRulesApplied[starts[0]])
            #expect(applied.count == 1 && applied[0].formulaOwner == "Body" && ruled.layoutRulesApplied[starts[1]] == nil)
            let facts = try #require(ruled.paragraphFacts(at: 1, sheet: doc.styles))
            #expect(facts.rules.count == 1, "l'ispettore la elenca")
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
            let rule = TextRule(target: .paragraph, position: .firstOnPage, styleName: "Small Caps")
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
            let letter = TextRule(target: .firstLetter, condition: .init(.lines, .greaterOrEqual, 3), styleName: "Small Caps")
            let (ruled, _) = layout(["Breve.", Self.long], rules: [letter])
            #expect(ruled.layoutRulesApplied.keys.sorted() == [("Breve.\n" as NSString).length], "solo il paragrafo lungo")
            let line = TextRule(target: .firstLines(1), condition: .init(.words, .greater, 10), styleName: "Small Caps")
            let (lined, _) = layout(["Breve.", Self.long], rules: [line])
            let longLines = lined.pages[0].lines.filter { $0.paragraphLocation == ("Breve.\n" as NSString).length }
            let runs = CTLineGetGlyphRuns(longLines[0].line) as! [CTRun]
            #expect(runs.allSatisfy { FontFeatures.settings(of: (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont).contains(.aat(type: 3, selector: 3)) })
        }

        @Test("Una regola di paragrafo vince sull'allineamento dato a mano; con un'eccezione resta il suo")
        func ownAlignmentWins() throws {
            var right = StyleSheet.builtIn.resolveParagraph(styleName: "Body")
            right.alignment = .right
            let doc = document([.paragraph(Paragraph(styleName: "Body", style: right, inlines: [.text(TextRun("A destra.", style: body))]))],
                               rules: [TextRule(target: .paragraph, condition: .init(.lines, .equal, 1), styleName: "Centered")])
            let text = NSMutableAttributedString(attributedString: doc.attributedString().text)
            let layout = PageLayout.layout(text, setup: doc.pageSetup, options: doc.layoutOptions)
            let line = layout.pages[0].lines[0]
            let column = layout.setup.textRect
            #expect(abs((line.origin.x - column.minX) - (column.width - line.width) / 2) < 1.5, "centrata: la regola vince")
            TextStyling.setRuleException(.alignment, true, in: text, range: NSRange(location: 0, length: 1))
            PageLayout.clearCaches()
            let kept = PageLayout.layout(text, setup: doc.pageSetup, options: doc.layoutOptions).pages[0].lines[0]
            #expect(abs(kept.origin.x + kept.width - column.maxX) < 1.5, "con l'eccezione resta a destra")
        }
    }
}
