import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Il gestore degli stili")
    struct StyleManagementTests {
        private let base = TextStyling.styleBase

        @Test("Le proprietà di uno stile dicono da dove vengono: da lui, da uno stile su cui si basa, dal documento")
        func sources() throws {
            let sheet = StyleSheet.builtIn
            let values = sheet.inspect(style: "Subexample", base: base)
            #expect(values.map(\.property) == InspectorProperty.allCases, "uno stile di paragrafo mostra tutto")
            #expect(sheet.inspect(style: "Emphasis", base: base).map(\.property) == InspectorProperty.properties(of: .character))
            #expect(sheet.inspect(style: "Latin", base: base).contains { $0.property == .language && $0.source == .own })
            // Sottoesempio si basa su Esempio, che si basa su Testo: un valore che Esempio fissa viene da Esempio.
            let esempio = try #require(sheet.style(named: "Example"))
            if let fixed = InspectorProperty.allCases.first(where: { $0.isFixed(in: esempio.values) }),
               sheet.style(named: "Subexample").map({ !fixed.isFixed(in: $0.values) }) == true {
                #expect(values.first { $0.property == fixed }?.source == .style("Example"))
            }
        }

        @Test("Un valore fisso resta esplicito anche quando coincide con quello ereditato")
        func settingAndResetting() throws {
            var sheet = StyleSheet.builtIn
            var size = StyleValues()
            size.size = 15
            sheet = sheet.setting(size, of: .size, inStyle: "Quotation", base: base)
            #expect(sheet.inspect(style: "Quotation", base: base).first { $0.property == .size }?.value.size == 15)
            #expect(sheet.style(named: "Quotation")?.values.size == nil)
            #expect(sheet.inspect(style: "Quotation", base: base).first { $0.property == .size }?.source == .own)
            let inherited = try #require(sheet.inspect(style: "Quotation", base: base).first { $0.property == .size }?.inherited.size)
            size.size = inherited
            let same = sheet.setting(size, of: .size, inStyle: "Quotation", base: base)
            #expect(same.inspect(style: "Quotation", base: base).first { $0.property == .size }?.source == .own, "Imposta rimane esplicito; Eredita è un altro comando")
            #expect(sheet.resetting(.size, inStyle: "Quotation").style(named: "Quotation")?.values.size == nil)
        }

        @Test("Su chi può basarsi uno stile: della stessa specie, né lui né i suoi discendenti")
        func parents() {
            let sheet = StyleSheet.builtIn
            let parents = sheet.possibleParents(of: "Example")
            #expect(!parents.contains("Example") && !parents.contains("Subexample"), "niente giri")
            #expect(parents.contains("Body") && !parents.contains("Emphasis"))
            #expect(sheet.freeName("Body") == "Body 2" && sheet.freeName("Nuovo") == "Nuovo")
        }

        @Test("Rinominare e togliere uno stile: gli stili che si basano su di lui, le regole e gli stili di flottante seguono")
        func renameAndRemove() throws {
            var document = Document(styles: StyleSheet.builtIn)
            document.rules = [TextRule(target: .firstWords(1), paragraphStyle: "Example", position: .firstAfter("Example"), styleName: "Small Caps")]
            var float = FloatStyle(name: "Postille", listName: nil)
            float.contentStyle = "Example"
            document.floatStyles.append(float)

            let renamed = document.renamingStyle("Example", to: "Esempio linguistico")
            #expect(renamed.styles.style(named: "Example") == nil && renamed.styles.style(named: "Esempio linguistico") != nil)
            #expect(renamed.styles.style(named: "Subexample")?.basedOn == "Esempio linguistico")
            #expect(renamed.rules.first?.paragraphStyle == "Esempio linguistico" && renamed.rules.first?.position == .firstAfter("Esempio linguistico"))
            #expect(renamed.floatStyles.last?.contentStyle == "Esempio linguistico")
            #expect(document.renamingStyle("Example", to: "Body").styles == document.styles, "un nome già usato non si prende")

            let (removed, replacement) = document.removingStyle("Example")
            #expect(replacement == "Body")
            #expect(removed.styles.style(named: "Example") == nil)
            #expect(removed.styles.style(named: "Subexample")?.basedOn == "Body", "chi si basava su di lui passa al suo stile di base")
            #expect(removed.rules.first?.paragraphStyle == "Body" && removed.rules.first?.position == .firstAfter("Body"))
            #expect(removed.floatStyles.last?.contentStyle == "Body")
            // Una regola che applica uno stile senza stile di base si toglie con lui.
            var withRule = document
            withRule.rules = [TextRule(target: .firstWords(1), paragraphStyle: nil, position: .any, styleName: "Emphasis")]
            #expect(withRule.removingStyle("Emphasis").document.rules.isEmpty)
        }
    }
}
