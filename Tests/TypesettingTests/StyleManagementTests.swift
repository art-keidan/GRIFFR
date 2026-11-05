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
            let values = sheet.inspect(style: "Sottoesempio", base: base)
            #expect(values.map(\.property) == InspectorProperty.allCases, "uno stile di paragrafo mostra tutto")
            #expect(sheet.inspect(style: "Enfasi", base: base).map(\.property) == InspectorProperty.properties(of: .character))
            #expect(sheet.inspect(style: "Latino", base: base).contains { $0.property == .language && $0.source == .own })
            // Sottoesempio si basa su Esempio, che si basa su Testo: un valore che Esempio fissa viene da Esempio.
            let esempio = try #require(sheet.style(named: "Esempio"))
            if let fixed = InspectorProperty.allCases.first(where: { $0.isFixed(in: esempio.values) }),
               sheet.style(named: "Sottoesempio").map({ !fixed.isFixed(in: $0.values) }) == true {
                #expect(values.first { $0.property == fixed }?.source == .style("Esempio"))
            }
        }

        @Test("Un valore fisso resta esplicito anche quando coincide con quello ereditato")
        func settingAndResetting() throws {
            var sheet = StyleSheet.builtIn
            var size = StyleValues()
            size.size = 15
            sheet = sheet.setting(size, of: .size, inStyle: "Citazione", base: base)
            #expect(sheet.inspect(style: "Citazione", base: base).first { $0.property == .size }?.value.size == 15)
            #expect(sheet.style(named: "Citazione")?.values.size == nil)
            #expect(sheet.inspect(style: "Citazione", base: base).first { $0.property == .size }?.source == .own)
            let inherited = try #require(sheet.inspect(style: "Citazione", base: base).first { $0.property == .size }?.inherited.size)
            size.size = inherited
            let same = sheet.setting(size, of: .size, inStyle: "Citazione", base: base)
            #expect(same.inspect(style: "Citazione", base: base).first { $0.property == .size }?.source == .own, "Imposta rimane esplicito; Eredita è un altro comando")
            #expect(sheet.resetting(.size, inStyle: "Citazione").style(named: "Citazione")?.values.size == nil)
        }

        @Test("Su chi può basarsi uno stile: della stessa specie, né lui né i suoi discendenti")
        func parents() {
            let sheet = StyleSheet.builtIn
            let parents = sheet.possibleParents(of: "Esempio")
            #expect(!parents.contains("Esempio") && !parents.contains("Sottoesempio"), "niente giri")
            #expect(parents.contains("Testo") && !parents.contains("Enfasi"))
            #expect(sheet.freeName("Testo") == "Testo 2" && sheet.freeName("Nuovo") == "Nuovo")
        }

        @Test("Rinominare e togliere uno stile: gli stili che si basano su di lui, le regole e gli stili di flottante seguono")
        func renameAndRemove() throws {
            var document = Document(styles: StyleSheet.builtIn)
            document.rules = [TextRule(target: .firstWords(1), paragraphStyle: "Esempio", position: .firstAfter("Esempio"), styleName: "Maiuscoletto")]
            var float = FloatStyle(name: "Postille", listName: nil)
            float.contentStyle = "Esempio"
            document.floatStyles.append(float)

            let renamed = document.renamingStyle("Esempio", to: "Esempio linguistico")
            #expect(renamed.styles.style(named: "Esempio") == nil && renamed.styles.style(named: "Esempio linguistico") != nil)
            #expect(renamed.styles.style(named: "Sottoesempio")?.basedOn == "Esempio linguistico")
            #expect(renamed.rules.first?.paragraphStyle == "Esempio linguistico" && renamed.rules.first?.position == .firstAfter("Esempio linguistico"))
            #expect(renamed.floatStyles.last?.contentStyle == "Esempio linguistico")
            #expect(document.renamingStyle("Esempio", to: "Testo").styles == document.styles, "un nome già usato non si prende")

            let (removed, replacement) = document.removingStyle("Esempio")
            #expect(replacement == "Testo")
            #expect(removed.styles.style(named: "Esempio") == nil)
            #expect(removed.styles.style(named: "Sottoesempio")?.basedOn == "Testo", "chi si basava su di lui passa al suo stile di base")
            #expect(removed.rules.first?.paragraphStyle == "Testo" && removed.rules.first?.position == .firstAfter("Testo"))
            #expect(removed.floatStyles.last?.contentStyle == "Testo")
            // Una regola che applica uno stile senza stile di base si toglie con lui.
            var withRule = document
            withRule.rules = [TextRule(target: .firstWords(1), paragraphStyle: nil, position: .any, styleName: "Enfasi")]
            #expect(withRule.removingStyle("Enfasi").document.rules.isEmpty)
        }
    }
}
