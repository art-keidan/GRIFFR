import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Regole nell'ispettore: da dove viene un valore, valori che vincono")
    struct RuleProvenanceTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let rule = TextRule(target: .firstWords(1), paragraphStyle: "Body", styleName: "Emphasis")

        private func document(_ texts: [String] = ["Roma, città aperta.", "Seconda frase qui."], rules: [TextRule]? = nil) -> Document {
            Document(styles: RuleTests.sheet(.builtIn, with: rules ?? [rule]), lists: ListDefinition.builtIn, blocks: texts.map { text in
                .paragraph(Paragraph(styleName: "Body", style: StyleSheet.builtIn.resolveParagraph(styleName: "Body"),
                                     inlines: [.text(TextRun(text, style: body))]))
            })
        }

        private func isItalic(_ text: NSAttributedString, at index: Int) -> Bool {
            guard let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont else { return false }
            return NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        }

        @Test("Un valore che dà una regola si dice «dalla regola», con il valore che lei gli dà")
        func ruleSource() throws {
            let document = document()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, options: document.layoutOptions)
            let rules = layout.touchingRules(at: 1, sheet: document.styles)
            #expect(rules.count == 1 && rules[0].target == rule.target && rules[0].formulaOwner == "Body")
            #expect(layout.touchingRules(at: 8, sheet: document.styles).isEmpty, "«città» non è la prima parola")
            let plain = TextStyling.inspect(.character, in: text, range: NSRange(location: 1, length: 0), sheet: document.styles)
            let face = try #require(plain.first { $0.property == .face })
            #expect(face.source != .own)
            let given = TextStyling.withRuleSources(plain, rules: rules, in: text, at: 1, sheet: document.styles)
            let ruled = try #require(given.first { $0.property == .face })
            #expect(ruled.source == .rule(rules[0].summary))
            #expect(ruled.value.fontName != face.value.fontName, "il valore è quello della regola: il corsivo")
            #expect(given.first { $0.property == .size }?.source == plain.first { $0.property == .size }?.source, "il corpo la regola non lo tocca")
        }

        @Test("Un valore dato qui contro la regola vince anche se coincide con lo stile; tornare all'ereditato lo rilascia")
        func exceptions() throws {
            let document = document()
            let text = NSMutableAttributedString(attributedString: document.attributedString().text)
            let roma = NSRange(location: 0, length: 4)
            #expect(isItalic(Rules.applied(to: text, sheet: document.styles), at: 1))
            TextStyling.setRuleException(.face, true, in: text, range: roma)
            #expect(TextStyling.ruleExceptions(in: text, at: 1) == [.family, .face], "famiglia e faccia vanno insieme")
            #expect(!isItalic(Rules.applied(to: text, sheet: document.styles), at: 1))
            #expect(TextStyling.inspect(.character, in: text, range: NSRange(location: 1, length: 0), sheet: document.styles)
                .first { $0.property == .face }?.source == .own, "per l'ispettore è un valore dato qui")
            // Si salva e si rilegge.
            let saved = DocumentFormat.string(for: Document(attributedString: text, settings: document))
            #expect(saved.contains("rules-off=\"family face\""))
            let reread = try DocumentFormat.document(from: saved).attributedString().text
            #expect(TextStyling.ruleExceptions(in: reread, at: 1) == [.family, .face])
            #expect(TextStyling.ruleExceptions(in: reread, at: 6).isEmpty)
            // Tornare al valore ereditato lascia di nuovo fare alla regola.
            TextStyling.resetValue(of: .face, in: text, range: roma, sheet: document.styles)
            #expect(TextStyling.ruleExceptions(in: text, at: 1).isEmpty)
            #expect(isItalic(Rules.applied(to: text, sheet: document.styles), at: 1))
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: saved.replacingOccurrences(of: "family face", with: "colore")) }
        }

        @Test("I segni della provenienza: i tratti dati a mano e quelli a cui dà l'aspetto una regola")
        func marks() throws {
            let document = document(["Roma, città aperta.", "Seconda frase qui."],
                                    rules: [rule, TextRule(target: .lastLine, paragraphStyle: "Body", styleName: "Emphasis")])
            let text = NSMutableAttributedString(attributedString: document.attributedString().text)
            let string = text.string as NSString
            let città = string.range(of: "città")
            TextStyling.setValue({ var v = StyleValues(); v.size = 15; return v }(), of: .size, in: text, range: città)
            #expect(TextStyling.manualRanges(in: text, sheet: document.styles) == [città])
            // Il maiuscoletto dato a mano è una funzione del font, non una proprietà: conta lo stesso.
            let qui = string.range(of: "qui")
            Rules.applyStyle("Small Caps", to: qui, in: text, sheet: document.styles)
            #expect(TextStyling.manualRanges(in: text, sheet: document.styles) == [città, qui])
            // Un paragrafo con una misura data a mano: tutto il suo testo, senza l'a capo.
            let second = NSRange(location: string.range(of: "Seconda").location, length: "Seconda frase qui.".utf16.count)
            TextStyling.setValue({ var v = StyleValues(); v.leftIndent = 20; return v }(), of: .leftIndent, in: text, range: second)
            #expect(TextStyling.manualRanges(in: text, sheet: document.styles) == [città, second])

            let layout = PageLayout.layout(text, options: document.layoutOptions)
            let ruled = layout.ruleRanges(sheet: document.styles)
            // L'ultima riga di ciascun paragrafo è qui l'unica: i due paragrafi interi, che si toccano e fanno un tratto solo.
            #expect(ruled == [NSRange(location: 0, length: string.length)])
            let firstWords = PageLayout.layout(text, options: self.document().layoutOptions)
            #expect(firstWords.ruleRanges(sheet: self.document().styles).map { string.substring(with: $0) } == ["Roma,", "Seconda"])
        }

        @Test("Le regole che toccano una proprietà: quella che conta, quelle scavalcate, il valore sospeso e quello che cede")
        func influence() throws {
            let document = document()
            let text = NSMutableAttributedString(attributedString: document.attributedString().text)
            let roma = NSRange(location: 0, length: 4)
            let at = NSRange(location: 1, length: 0)
            // Due regole sullo stesso corpo: conta la prima che lo cambia, l'altra è scavalcata.
            var sheet = document.styles
            sheet.styles.append(NamedStyle(name: "Big", target: .character, values: { var v = StyleValues(); v.size = 20; return v }()))
            sheet.styles.append(NamedStyle(name: "Small", target: .character, values: { var v = StyleValues(); v.size = 8; return v }()))
            let big = TextRule(target: .firstWords(1), paragraphStyle: "Body", styleName: "Big")
            let small = TextRule(target: .firstWords(1), paragraphStyle: "Body", styleName: "Small")
            let plain = TextStyling.inspect(.character, in: text, range: at, sheet: sheet)
            let both = TextStyling.withRuleSources(plain, rules: [big, small], in: text, at: 1, sheet: sheet)
            let size = try #require(both.first { $0.property == .size })
            #expect(size.source == .rule(big.summary) && size.value.size == 20)
            #expect(size.rules?.winner == big.summary && size.rules?.outranked == [small.summary])
            #expect(size.rules?.suspended == nil && size.rules?.yielded == nil && size.rules?.owner == nil)
            #expect(both.first { $0.property == .alignment }?.rules == nil, "l'allineamento nessuna regola lo tocca")
            // Una regola (viene sempre da una formula) vince sul valore dato a mano, che resta sospeso.
            TextStyling.setValue({ var v = StyleValues(); v.fontName = "HoeflerText-Black"; return v }(), of: .face, in: text, range: roma)
            let own = TextStyling.inspect(.character, in: text, range: at, sheet: document.styles)
            var contextual = rule
            contextual.formulaOwner = "Body"
            let over = try #require(TextStyling.withRuleSources(own, rules: [contextual], in: text, at: 1, sheet: document.styles).first { $0.property == .face })
            #expect(over.source == .rule(contextual.summary) && over.rules?.owner == "Body")
            #expect(over.rules?.suspended?.fontName == "HoeflerText-Black", "il valore dato qui resta, sospeso")
            // Con un'eccezione il valore dato qui vince anche sulla formula, come nell'impaginazione.
            TextStyling.setRuleException(.face, true, in: text, range: roma)
            let excepted = TextStyling.inspect(.character, in: text, range: at, sheet: document.styles)
            let kept = try #require(TextStyling.withRuleSources(excepted, rules: [contextual], in: text, at: 1, sheet: document.styles).first { $0.property == .face })
            #expect(kept.source == .own && kept.value.fontName == "HoeflerText-Black" && kept.rules?.yielded != nil)
        }

        @Test("Il valore di una proprietà in parole brevi")
        func valueText() {
            var values = StyleValues()
            values.firstLineIndent = 72 / 25.4 * 5
            values.alignment = .justified
            values.keeping.withNext = true
            values.lineHeightMultiple = 1.25
            #expect(InspectorProperty.firstLineIndent.text(of: values) == "5 mm")
            #expect(InspectorProperty.alignment.text(of: values) == "Justified")
            #expect(InspectorProperty.keepWithNext.text(of: values) == "On")
            #expect(InspectorProperty.lineHeightMultiple.text(of: values) == "1.25 ×" || InspectorProperty.lineHeightMultiple.text(of: values) == "1,25 ×")
            #expect(InspectorProperty.spaceBefore.text(of: StyleValues()) == "—")
        }
    }
}
