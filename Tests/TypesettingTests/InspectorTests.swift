import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Ispettore: valori, provenienza e modifiche")
    struct InspectorTests {
        private let sheet = StyleSheet.builtIn

        private func run(_ text: String, _ paragraph: String?, word: String? = nil, character: String? = nil) -> Inline {
            .text(TextRun(text, style: sheet.resolveCharacter(paragraphStyle: paragraph, wordStyle: word, characterStyle: character, base: TextStyling.styleBase),
                          wordStyleName: word, characterStyleName: character))
        }

        /// «Citazione» con una parola latina in corsivo (0…10 «Una frase »; 10…15 «veni,»; poi « fine.»), e un esempio.
        private func sample() -> NSMutableAttributedString {
            NSMutableAttributedString(attributedString: Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(styleName: "Citazione", style: sheet.resolveParagraph(styleName: "Citazione"), inlines: [
                    run("Una frase ", "Citazione"), run("veni,", "Citazione", word: "Latino", character: "Enfasi"), run(" fine.", "Citazione"),
                ])),
                .paragraph(Paragraph(styleName: "Esempio", style: sheet.resolveParagraph(styleName: "Esempio"), list: ListItem(listName: "Esempi"),
                                     inlines: [run("Esempio", "Esempio")])),
            ]).attributedString().text)
        }

        private func value(_ property: InspectorProperty, _ text: NSAttributedString, at location: Int, length: Int = 0) -> InspectedValue {
            TextStyling.inspect(property.level, in: text, range: NSRange(location: location, length: length), sheet: sheet).first { $0.property == property }!
        }

        @Test("Ogni valore dice da quale stile viene, o dal documento")
        func sources() {
            let text = sample()
            #expect(value(.size, text, at: 0).value.size == 11)
            #expect(value(.size, text, at: 0).source == .style("Citazione"))
            #expect(value(.family, text, at: 0).source == .style("Testo"), "la famiglia la fissa lo stile su cui Citazione si basa")
            #expect(value(.face, text, at: 12).value.fontName == "HoeflerText-Italic")
            #expect(value(.face, text, at: 12).source == .style("Enfasi"))
            #expect(value(.language, text, at: 12).source == .style("Latino") && value(.language, text, at: 12).value.language == "la")
            #expect(value(.language, text, at: 0).source == .document && value(.language, text, at: 0).value.language == "")
            #expect(value(.leftIndent, text, at: 0).source == .style("Citazione"))
            #expect(value(.firstLineIndent, text, at: 0).source == .document)
            #expect(value(.list, text, at: 22).value.listName == "Esempi" && value(.list, text, at: 22).source == .style("Esempio"))
            #expect(value(.size, text, at: 5, length: 10).isMixed == false)
            #expect(value(.face, text, at: 5, length: 10).isMixed, "la selezione attraversa il tondo e il corsivo")
        }

        @Test("Un valore dato a mano risulta proprio; tolto, torna quello dello stile")
        func ownAndReset() {
            let text = sample()
            var big = StyleValues()
            big.size = 14
            TextStyling.setValue(big, of: .size, in: text, range: NSRange(location: 0, length: 3))
            #expect(value(.size, text, at: 0).source == .own && value(.size, text, at: 0).value.size == 14)
            #expect(value(.size, text, at: 0).inherited.size == 11)
            #expect(value(.size, text, at: 4).source == .style("Citazione"), "solo i caratteri scelti")
            var centered = StyleValues()
            centered.alignment = .center
            TextStyling.setValue(centered, of: .alignment, in: text, range: NSRange(location: 4, length: 0))
            #expect(value(.alignment, text, at: 18).source == .own, "una proprietà di paragrafo vale per tutto il paragrafo")
            TextStyling.resetValue(of: .size, in: text, range: NSRange(location: 0, length: text.length), sheet: sheet)
            TextStyling.resetValue(of: .alignment, in: text, range: NSRange(location: 0, length: 1), sheet: sheet)
            #expect(value(.size, text, at: 0).source == .style("Citazione") && value(.size, text, at: 0).value.size == 11)
            #expect(value(.alignment, text, at: 0).source == .style("Testo"))
            #expect(value(.face, text, at: 12).value.fontName == "HoeflerText-Italic", "togliere il corpo non tocca il corsivo")

            // Una famiglia data a mano si toglie insieme alla faccia.
            var times = StyleValues()
            times.family = "Times New Roman"
            TextStyling.setValue(times, of: .family, in: text, range: NSRange(location: 10, length: 5))
            #expect(value(.family, text, at: 12).source == .own && value(.face, text, at: 12).value.fontName == "TimesNewRomanPS-ItalicMT", "il corsivo resta")
            #expect(value(.face, text, at: 12).source == .style("Enfasi"), "il nome del font cambia, ma il corsivo resta ereditato")
            TextStyling.resetValue(of: .family, in: text, range: NSRange(location: 10, length: 5), sheet: sheet)
            #expect(value(.face, text, at: 12).value.fontName == "HoeflerText-Italic")

            // La Lista: togliere quella data a mano riporta a quella dello stile.
            var none = StyleValues()
            none.listName = ""
            TextStyling.setValue(none, of: .list, in: text, range: NSRange(location: 22, length: 0))
            #expect(value(.list, text, at: 22).source == .own && value(.list, text, at: 22).value.listName == "")
            TextStyling.resetValue(of: .list, in: text, range: NSRange(location: 22, length: 0), sheet: sheet)
            #expect(value(.list, text, at: 22).value.listName == "Esempi")
        }

        @Test("Portare un valore nello stile: lo riceve lo stile più vicino che lo può fissare")
        func intoStyle() throws {
            let text = sample()
            var big = StyleValues()
            big.size = 13
            TextStyling.setValue(big, of: .size, in: text, range: NSRange(location: 0, length: 3))
            let updated = try #require(TextStyling.sheet(sheet, takingValueOf: .size, from: text, at: 0))
            #expect(updated.style(named: "Citazione")?.values.size == 13)
            #expect(TextStyling.receivingStyle(for: .face, in: text, at: 12)?.name == "Enfasi")
            #expect(TextStyling.receivingStyle(for: .language, in: text, at: 12)?.name == "Latino", "la lingua non va in uno stile di carattere")
            #expect(TextStyling.receivingStyle(for: .alignment, in: text, at: 12)?.name == "Citazione")
            // Un valore uguale a quello ereditato: lo stile smette di fissarlo.
            var twelve = StyleValues()
            twelve.size = 12
            TextStyling.setValue(twelve, of: .size, in: text, range: NSRange(location: 0, length: 3))
            #expect(TextStyling.sheet(sheet, takingValueOf: .size, from: text, at: 0)?.style(named: "Citazione")?.values.size == nil)
            // Il testo senza stile non ha dove portare il valore.
            let plain = NSMutableAttributedString(string: "x", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 12)!])
            #expect(TextStyling.sheet(sheet, takingValueOf: .size, from: plain, at: 0) == nil)
        }

        @Test("La sola famiglia entra in uno stile nero anche con una faccia personalizzata")
        func familyIntoBoldStyleWithCustomFace() throws {
            var sheet = StyleSheet.builtIn
            let position = try #require(sheet.styles.firstIndex { $0.name == "Testo" })
            sheet.styles[position].values.family = "Hoefler Text"
            sheet.styles[position].values.bold = true
            let current = CharacterStyle(fontName: "Baskerville-SemiBold", size: 12, fontRole: .bold)
            let text = NSMutableAttributedString(string: "Parola", attributes: TextStyling.characterAttributes(for: current).attributes)
            text.addAttribute(.paragraphStyleName, value: "Testo", range: NSRange(location: 0, length: text.length))
            let updated = try #require(TextStyling.sheet(sheet, takingValueOf: .family, from: text, at: 0))
            let values = try #require(updated.style(named: "Testo")?.values)
            #expect(values.family == "Baskerville")
            #expect(values.bold == true)
            #expect(values.fontName == nil)
            #expect(values.italic == nil)
        }
    }
}
