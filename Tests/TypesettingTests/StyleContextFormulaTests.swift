import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Formule condizionate e comportamenti degli stili")
    struct StyleContextFormulaTests {
        let base = TextStyling.styleBase
        func formula(_ property: StyleProperty, _ argument: StyleArgument, when: StyleCondition = StyleCondition(), target: TextRule.Target = .paragraph) -> StyleFormula {
            StyleFormula(operation: StylePropertyOperation(.set, property, argument), when: when, target: target)
        }

        @Test("La formula condizionata non cambia il testo sorgente e segue il paragrafo precedente")
        func contextualRendering() throws {
            let conditional = formula(.firstLineIndent, .length(0, .points), when: StyleCondition(position: .firstAfter("Titolo")))
            let words = formula(.applyStyle, .styleName("Forte"), target: .firstWords(2))
            var body = StyleValues(); body.firstLineIndent = 18
            var bold = StyleValues(); bold.bold = true
            let sheet = StyleSheet(styles: [NamedStyle(name: "Titolo", target: .paragraph),
                NamedStyle(name: "Testo", target: .paragraph, values: body, formulas: [conditional, words]),
                NamedStyle(name: "Forte", target: .character, values: bold)])
            let source = Document(styles: sheet, blocks: [
                .paragraph(Paragraph(styleName: "Titolo", inlines: [.text(TextRun("Titolo", style: base))])),
                .paragraph(Paragraph(styleName: "Testo", style: sheet.resolveParagraph(styleName: "Testo"), inlines: [.text(TextRun("Uno due tre", style: base))]))
            ]).attributedString().text
            let result = Rules.applied([], to: source, sheet: sheet)
            let at = (source.string as NSString).range(of: "Uno").location
            #expect((source.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent == 18)
            #expect((result.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?.firstLineHeadIndent == 0)
            #expect((result.attribute(.font, at: at, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
            #expect((result.attribute(.font, at: at + 8, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Regular")
            let compiled = sheet.compilingStyleRules([])
            #expect(compiled.rules.count == 2)
            #expect(sheet.styles.count == 3)
        }

        @Test("Le condizioni numeriche vengono decise sul paragrafo naturale e restano stabili")
        func numericalCondition() throws {
            let conditional = formula(.alignment, .alignment(.center), when: StyleCondition(measurement: .init(.words, .lessOrEqual, 3)))
            let sheet = StyleSheet(styles: [NamedStyle(name: "P", target: .paragraph, formulas: [conditional])])
            func layout(_ string: String) -> DocumentLayout {
                let doc = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "P", inlines: [.text(TextRun(string, style: base))]))])
                return PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions)
            }
            let short = layout("Uno due tre"), long = layout("Uno due tre quattro")
            #expect(short.layoutRulesApplied[0]?.count == 1)
            #expect(long.layoutRulesApplied[0] == nil)
            #expect(short.pages.flatMap(\.lines).map(\.origin) == layout("Uno due tre").pages.flatMap(\.lines).map(\.origin))
        }

        @Test("Direttive, condizione e destinatario fanno andata e ritorno nel formato 8")
        func roundTrip() throws {
            let selection = WordSelection(name: "Quinta", index: 5)
            var sheet = StyleSheet(styles: [NamedStyle(name: "Titolo", target: .paragraph), NamedStyle(name: "Testo", target: .paragraph), NamedStyle(name: "Forte", target: .character)])
            sheet.selections = [selection]
            sheet = sheet.settingDirective(.pageStartSpacing, argument: .pageStart(.distance(72)), inStyle: "Titolo")
            sheet = sheet.settingDirective(.nextStyle, argument: .styleName("Testo"), inStyle: "Titolo")
            sheet = sheet.settingDirective(.opensSection, argument: .text(Section.Role.chapter), inStyle: "Titolo")
            sheet.styles[0].formulas.append(formula(.applyStyle, .styleName("Forte"), when: StyleCondition(position: .firstAfter("Testo"), measurement: .init(.lines, .greaterOrEqual, 2)), target: .selection(selection.id)))
            let data = DocumentFormat.data(for: Document(styles: sheet))
            let loaded = try DocumentFormat.document(from: data)
            #expect(loaded.sourceVersion == 8)
            for (a, b) in zip(loaded.styles.styles, sheet.styles) {
                #expect(a.values == b.values)
                #expect(a.formulas == b.formulas)
            }
            #expect(loaded.styles.selections == sheet.selections)
            #expect(loaded.styles.values(of: "Titolo").pageStartSpacing == .distance(72))
            #expect(loaded.styles.values(of: "Titolo").nextStyle == "Testo")
            let xml = try #require(String(data: data, encoding: .utf8))
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"8\"", with: "version=\"7\"")) }
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "threshold=\"2\"", with: "threshold=\"nan\"")) }
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: xml.replacingOccurrences(of: "value=\"Testo\"", with: "value=\"Assente\"")) }
        }

        @Test("La conversione della variante di inizio pagina conserva la quota e la tenuta")
        func pageDirective() throws {
            var values = StyleValues(); values.pageStartSpacing = .distance(72); values.keeping.withNext = true
            let old = StyleSheet(styles: [NamedStyle(name: "P", target: .paragraph, values: values)])
            let converted = StyleSheet(styles: old.styles.map { $0.materializingFormulas() })
            let doc = Document(styles: converted, blocks: [.paragraph(Paragraph(styleName: "P", inlines: [.text(TextRun("Titolo", style: base))]))])
            let layout = PageLayout.layout(doc.attributedString().text, setup: doc.pageSetup, options: doc.layoutOptions)
            #expect(layout.pageStarts[0]?.requested == 72)
            #expect(converted.lineKeeping(styleName: "P").withNext)
            #expect(converted.styles[0].values.pageStartSpacing == nil)
            #expect(converted.styles[0].formulas.contains { $0.operation.property == .pageStartSpacing && $0.when.position == .firstOnPage })
        }

        @Test("Incollare importa e rinomina anche stili e selezioni richiamati dalle formule")
        func importingReferences() throws {
            let selection = WordSelection(name: "Quinta", index: 5)
            let formulas = [formula(.nextStyle, .styleName("Body")),
                formula(.applyStyle, .styleName("Strong"), when: StyleCondition(position: .firstAfter("Titolo")), target: .selection(selection.id))]
            var sourceSheet = StyleSheet.builtIn
            sourceSheet.selections = [selection]
            sourceSheet.styles.append(NamedStyle(name: "Titolo", target: .paragraph, formulas: formulas))
            let source = Document(styles: sourceSheet, blocks: [.paragraph(Paragraph(styleName: "Titolo", inlines: [.text(TextRun("Uno due tre quattro cinque", style: base))]))])
            var destination = Document(styles: sourceSheet)
            destination.styles.selections[0].index = 1
            let merged = DefinitionImport.merge(source.attributedString().text, from: source, into: destination, policy: .renameCopies)
            let name = try #require(merged.text.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String)
            #expect(name != "Titolo")
            let imported = try #require(merged.styles.style(named: name))
            let reference = try #require(imported.formulas.last)
            #expect(reference.when.position == .firstAfter(name))
            guard case .selection(let id) = reference.target else { Issue.record("Manca il destinatario condiviso"); return }
            #expect(id != selection.id)
            #expect(merged.styles.selections.first { $0.id == id }?.index == 5)
            #expect(merged.styles.formulaReferenceProblem() == nil)
            let renamed = source.renamingStyle("Body", to: "Corpo")
            #expect(renamed.styles.values(of: "Titolo").nextStyle == "Corpo")
        }


        @Test("Due effetti contestuali si compongono sul risultato corrente nella stessa fase")
        func orderedContextEffects() throws {
            var values = StyleValues(); values.leftIndent = 12
            let condition = StyleCondition(position: .firstAfter("Titolo"))
            let add = StyleFormula(operation: StylePropertyOperation(.add, .leftIndent, .length(6, .points)), when: condition)
            let subtract = StyleFormula(operation: StylePropertyOperation(.subtract, .leftIndent, .length(2, .points)), when: condition)
            let sheet = StyleSheet(styles: [NamedStyle(name: "Titolo", target: .paragraph),
                NamedStyle(name: "P", target: .paragraph, values: values, formulas: [add, subtract])])
            let source = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Titolo", inlines: [.text(TextRun("Titolo", style: base))])),
                .paragraph(Paragraph(styleName: "P", style: sheet.resolveParagraph(styleName: "P"), inlines: [.text(TextRun("Corpo", style: base))]))]).attributedString().text
            let styled = Rules.applied([], to: source, sheet: sheet)
            let at = (styled.string as NSString).range(of: "Corpo").location
            #expect((styled.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?.headIndent == 16)
            let evaluated = try sheet.values(of: "P").evaluatingFormulas(from: StylePredicateState(character: base), context: .init(styleName: "P", previousStyleName: "Titolo", isSequenceStart: false))
            #expect(evaluated.paragraph.leftIndent == 16)
        }


        @Test("I trattamenti contestuali rispettano le equivalenze del documento e invalidano la cache")
        func contextualFontRoles() throws {
            let effect = formula(.font, .font(.bold), when: StyleCondition(position: .sequenceStart))
            let sheet = StyleSheet(styles: [NamedStyle(name: "P", target: .paragraph, formulas: [effect])])
            var doc = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "P", inlines: [.text(TextRun("Prova", style: base))]))])
            let source = doc.attributedString().text
            let normal = Rules.applied([], to: source, sheet: sheet)
            let table = FontRoleTable(customizations: [.init(family: "Hoefler Text", role: .bold,
                equivalence: FontRoleEquivalence(staticFace: "HoeflerText-Italic"))])
            let customized = Rules.applied([], to: source, sheet: sheet, resolver: FontRoleResolver(table: table))
            #expect((normal.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
            #expect((customized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
            doc.fontRoles = table
            let layout = PageLayout.layout(source, setup: doc.pageSetup, options: doc.layoutOptions)
            #expect((layout.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
        }


        @Test("Identità locali uguali in due stili ereditati conservano operazioni distinte")
        func scopedFormulaIdentities() throws {
            let condition = StyleCondition(position: .firstAfter("Titolo"))
            let first = StyleFormula(operation: StylePropertyOperation(.add, .leftIndent, .length(6, .points)), when: condition)
            let second = StyleFormula(id: first.id, operation: StylePropertyOperation(.set, .leftIndent, .length(20, .points)), when: condition)
            let sheet = StyleSheet(styles: [NamedStyle(name: "Titolo", target: .paragraph),
                NamedStyle(name: "Base", target: .paragraph, formulas: [first]),
                NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Base", formulas: [second])])
            let source = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Titolo", inlines: [.text(TextRun("Titolo", style: base))])),
                .paragraph(Paragraph(styleName: "Figlio", inlines: [.text(TextRun("Corpo", style: base))]))]).attributedString().text
            let result = Rules.applied([], to: source, sheet: sheet)
            let at = (result.string as NSString).range(of: "Corpo").location
            #expect((result.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?.headIndent == 20)
        }

    }
}
