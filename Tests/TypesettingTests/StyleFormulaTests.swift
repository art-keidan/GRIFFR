import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Formule interne degli stili")
    struct StyleFormulaTests {
        private let base = CharacterStyle(fontName: "HoeflerText-Italic", size: 12)
        private func formula(_ predicate: StylePredicate, _ property: StyleProperty, _ argument: StyleArgument) -> StyleFormula {
            StyleFormula(operation: StylePropertyOperation(predicate, property, argument))
        }

        @Test("Forte come formula cambia il font effettivo anche dopo il salvataggio e il deposito")
        func fontRoundTrip() throws {
            let add = NamedStyle(name: "Strong", target: .character, formulas: [formula(.add, .font, .font(.bold))])
            let set = NamedStyle(name: "Nero assoluto", target: .character, formulas: [formula(.set, .font, .font(.bold))])
            let sheet = StyleSheet(styles: [add, set])
            var doc = Document(styles: sheet, blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("Prova", style: base, characterStyleName: "Forte"))
            ]))])
            let serialized = DocumentFormat.data(for: doc)
            let loaded = try DocumentFormat.document(from: serialized)
            #expect(loaded.styles.styles == sheet.styles)
            #expect(loaded.styles.resolveCharacter(paragraphStyle: nil, wordStyle: nil, characterStyle: "Strong", base: base).fontName == "HoeflerText-BlackItalic")
            #expect(loaded.styles.resolveCharacter(paragraphStyle: nil, wordStyle: nil, characterStyle: "Nero assoluto", base: base).fontName == "HoeflerText-Black")
            let store = DocumentStore(document: loaded)
            let reopened = try DocumentFormat.document(from: DocumentFormat.data(for: store.document))
            #expect(reopened.styles.styles == sheet.styles)
            doc.styles.styles[0].formulas[0].operation = StylePropertyOperation(.set, .font, .font(.bold))
            #expect(doc.styles.resolveCharacter(paragraphStyle: nil, wordStyle: nil, characterStyle: "Strong", base: base).fontName == "HoeflerText-Black")
        }

        @Test("Eredità mista, unità, ordine e sostituzione dal controllo di rientro")
        func inheritanceAndControls() throws {
            var values = StyleValues()
            values.leftIndent = 12
            let parent = NamedStyle(name: "Base", target: .paragraph, values: values)
            let child = NamedStyle(name: "Quotation", target: .paragraph, basedOn: "Base",
                                   formulas: [formula(.add, .leftIndent, .length(6, .points))])
            var sheet = StyleSheet(styles: [parent, child])
            #expect(sheet.resolveParagraph(styleName: "Quotation").leftIndent == 18)
            #expect(sheet.inspect(style: "Quotation", base: base).first { $0.property == .leftIndent }?.source == .own)
            sheet.styles[0].values.leftIndent = 24
            #expect(sheet.resolveParagraph(styleName: "Quotation").leftIndent == 30)
            var replacement = StyleValues()
            replacement.leftIndent = 8
            let controlled = sheet.setting(replacement, of: .leftIndent, inStyle: "Quotation", base: base, replacingFormula: true)
            #expect(controlled.styles[1].formulas.first?.operation.predicate == .set)
            #expect(controlled.resolveParagraph(styleName: "Quotation").leftIndent == 8)
            let inherited = sheet.resetting(.leftIndent, inStyle: "Quotation")
            #expect(inherited.resolveParagraph(styleName: "Quotation").leftIndent == 24)

            sheet.styles.append(NamedStyle(name: "Dopo", target: .paragraph, basedOn: "Quotation", values: replacement))
            #expect(sheet.resolveParagraph(styleName: "Dopo").leftIndent == 8)
            let loaded = try DocumentFormat.document(from: DocumentFormat.data(for: Document(styles: sheet)))
            #expect(loaded.styles.styles == sheet.styles)
            #expect(loaded.styles.resolveParagraph(styleName: "Quotation").leftIndent == 30)
            let evaluated = try sheet.values(of: "Quotation").evaluatingFormulas(from: StylePredicateState(character: base))
            #expect(evaluated.paragraph.leftIndent == 30)
        }

        @Test("Importazione, rinomina e cache seguono la formula")
        func importAndComposition() throws {
            let f = formula(.add, .size, .length(2, .points))
            let style = NamedStyle(name: "Grande", target: .paragraph, formulas: [f])
            let source = Document(styles: StyleSheet(styles: [style]),
                blocks: [.paragraph(Paragraph(styleName: "Grande", inlines: [.text(TextRun("Testo", style: base))]))])
            let text = source.attributedString().text
            let merged = DefinitionImport.merge(text, from: source, into: Document(), policy: .keepDestination)
            #expect(merged.styles.style(named: "Grande")?.formulas == [f])
            let renamed = source.renamingStyle("Grande", to: "Titolo")
            #expect(renamed.styles.style(named: "Titolo")?.formulas == [f])
            let resolver = FontRoleResolver()
            #expect(merged.styles.resolveCharacter(paragraphStyle: "Grande", wordStyle: nil, characterStyle: nil, base: base, resolver: resolver).size == 14)
            let first = PageLayout.layout(text, setup: source.pageSetup, options: source.layoutOptions)
            let second = PageLayout.layout(text, setup: source.pageSetup, options: source.layoutOptions)
            #expect(first.pages.flatMap(\.lines).map(\.origin) == second.pages.flatMap(\.lines).map(\.origin))
        }

        @Test("Un corpo relativo mantiene il suo ingresso dopo ripetuti salvataggi e una modifica della formula")
        func additiveSizeRemainsRelative() throws {
            let id = UUID().uuidString
            let xml = """
            <document version="18" font="HoeflerText-Italic" size="12"><styles>
            <style name="A" target="paragraph">
            <formula id="\(id)" predicate="add" property="size" kind="length" value="2" unit="pt"/>
            </style></styles><p style="A">Prova</p></document>
            """
            var doc = try DocumentFormat.document(from: xml)
            func size(_ doc: Document) -> CGFloat {
                (doc.attributedString().text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            }
            #expect(size(doc) == 14)
            for _ in 0..<5 {
                doc = try DocumentFormat.document(from: DocumentFormat.data(for: DocumentStore(document: doc).document))
                #expect(size(doc) == 14)
            }
            doc.styles.styles[0].formulas[0].operation = StylePropertyOperation(.add, .size, .length(4, .points))
            // Il cambio della definizione richiede il restyle normale dell'editor:
            // qui si verifica direttamente il risolutore sul suo ingresso salvato.
            #expect(doc.styles.resolveCharacter(paragraphStyle: "A", wordStyle: nil, characterStyle: nil, base: try #require(doc.formulaBase)).size == 16)
        }

        @Test("I controlli conservano identità, valori fissi espliciti e proteggono le formule relative")
        func controlDefinitions() throws {
            var sheet = StyleSheet(styles: [NamedStyle(name: "Base", target: .paragraph), NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Base")])
            var value = StyleValues(); value.size = 12
            sheet = sheet.setting(value, of: .size, inStyle: "Figlio", base: base)
            let formula = try #require(sheet.style(named: "Figlio")?.formulas.first)
            value.size = 16
            sheet = sheet.setting(value, of: .size, inStyle: "Figlio", base: base)
            #expect(sheet.style(named: "Figlio")?.formulas.first?.id == formula.id)
            sheet.styles[1].formulas[0].operation = StylePropertyOperation(.add, .size, .length(2, .points))
            #expect(sheet.setting(value, of: .size, inStyle: "Figlio", base: base) == sheet)
            let replaced = sheet.setting(value, of: .size, inStyle: "Figlio", base: base, replacingFormula: true)
            #expect(replaced.style(named: "Figlio")?.formulas.first?.id == formula.id)
            #expect(replaced.resolveCharacter(paragraphStyle: "Figlio", wordStyle: nil, characterStyle: nil, base: base).size == 16)
            #expect(replaced.resetting(.size, inStyle: "Figlio").style(named: "Figlio")?.formulas.isEmpty == true)
        }

        @Test("La faccia precisa si salva come formula e conserva i dettagli esplicitamente dichiarati")
        func preciseFace() throws {
            var values = StyleValues(); values.features = [.aat(type: 6, selector: 1)]
            var sheet = StyleSheet(styles: [NamedStyle(name: "A", target: .character, values: values)])
            var face = StyleValues(); face.fontName = "HoeflerText-Italic"
            sheet = sheet.setting(face, of: .face, inStyle: "A", base: base)
            let resolved = sheet.resolveCharacter(paragraphStyle: nil, wordStyle: nil, characterStyle: "A", base: base)
            #expect(resolved.fontName == "HoeflerText-Italic" && resolved.features == values.features)
            let data = DocumentFormat.data(for: Document(styles: sheet))
            let loaded = try DocumentFormat.document(from: data)
            #expect(loaded.styles.styles == sheet.styles)
            let xml = try #require(String(data: data, encoding: .utf8))
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"6\""))
            }
        }

        @Test("Sottrai conserva formule, eredità e versione senza cambiare i file precedenti")
        func subtractionRoundTrip() throws {
            var values = StyleValues(); values.leftIndent = 24
            let operations = [formula(.subtract, .leftIndent, .length(6, .points)), formula(.subtract, .font, .font(.bold))]
            let sheet = StyleSheet(styles: [NamedStyle(name: "Base", target: .paragraph, values: values),
                NamedStyle(name: "Sottrazione", target: .paragraph, basedOn: "Base", formulas: operations)])
            let data = DocumentFormat.data(for: Document(styles: sheet))
            let loaded = try DocumentFormat.document(from: data)
            #expect(loaded.styles.styles == sheet.styles)
            #expect(loaded.styles.resolveParagraph(styleName: "Sottrazione").leftIndent == 18)
            let input = StylePredicateState(character: CharacterStyle(fontName: "HoeflerText-BlackItalic", size: 12))
            #expect(try loaded.styles.values(of: "Sottrazione").evaluatingFormulas(from: input).character.fontName == "HoeflerText-Italic")
            let xml = try #require(String(data: data, encoding: .utf8))
            for previous in [4, 5] {
                #expect(throws: DocumentFormatError.self) {
                    try DocumentFormat.document(from: xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"\(previous)\""))
                }
            }
        }

        @Test("Le formule malformate vengono rifiutate senza degradarle in valori costanti")
        func invalidFile() throws {
            let id = UUID().uuidString
            let xml = """
            <document version="18" font="HoeflerText-Regular" size="12"><styles>
            <style name="A" target="paragraph">
            <formula id="\(id)" predicate="add" property="spaceBefore" kind="length" value="6" unit="pt"/>
            </style></styles><p style="A">Prova</p></document>
            """
            #expect(try DocumentFormat.document(from: xml).styles.resolveParagraph(styleName: "A").spaceBefore == 6)
            for bad in [
                xml.replacingOccurrences(of: "version=\"18\"", with: "version=\"3\""),
                xml.replacingOccurrences(of: "predicate=\"add\"", with: "predicate=\"unknown\""),
                xml.replacingOccurrences(of: "target=\"paragraph\"", with: "target=\"character\""),
                xml.replacingOccurrences(of: "value=\"6\"", with: "value=\"nan\""),
                xml.replacingOccurrences(of: "kind=\"length\"", with: "kind=\"font\"")
            ] {
                #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: bad) }
            }
        }
    }
}
