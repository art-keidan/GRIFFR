import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tenuta delle righe: ispettore e stili (tappa A4)")
    struct LineKeepingInspectorTests {
        private let file = """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles>
        <style name="Testo" target="paragraph"/>
        <style name="Tenuto" target="paragraph" based-on="Testo" orphan-lines="2" widow-lines="2"/>
        <style name="Titolo" target="paragraph" based-on="Testo" keep-with-next="on"/>
        </styles>
        <p style="Tenuto">Uno.</p>
        <p style="Tenuto" widow-lines="3">Due.</p>
        <p style="Titolo">Tre.</p>
        </document>
        """

        private func setup() throws -> (text: NSMutableAttributedString, sheet: StyleSheet) {
            let document = try DocumentFormat.document(from: file)
            return (NSMutableAttributedString(attributedString: document.attributedString().text), document.styles)
        }

        private func at(_ word: String, _ text: NSAttributedString) -> Int { (text.string as NSString).range(of: word).location }

        private func inspected(_ text: NSAttributedString, _ sheet: StyleSheet, _ word: String) -> [InspectorProperty: InspectedValue] {
            let values = TextStyling.inspect(.paragraph, in: text, range: NSRange(location: at(word, text), length: 0), sheet: sheet)
            return Dictionary(uniqueKeysWithValues: values.filter(\.property.isLineKeeping).map { ($0.property, $0) })
        }

        @Test("L'ispettore mostra le quattro voci con valore e provenienza")
        func inspect() throws {
            let (text, sheet) = try setup()
            let one = inspected(text, sheet, "Uno")
            #expect(one.count == 4)
            #expect(one[.orphanLines]?.value.keeping.linesAtEnd == 2)
            #expect(one[.orphanLines]?.source == .style("Tenuto"))
            #expect(one[.keepWithNext]?.value.keeping.withNext == false)
            #expect(one[.keepWithNext]?.source == .document)
            let two = inspected(text, sheet, "Due")
            #expect(two[.widowLines]?.value.keeping.linesAtStart == 3)
            #expect(two[.widowLines]?.source == .own)
            #expect(two[.orphanLines]?.source == .style("Tenuto"))
            #expect(inspected(text, sheet, "Tre")[.keepWithNext]?.source == .style("Titolo"))
        }

        @Test("Dare un valore qui e tornare a quello ereditato tocca solo quella voce")
        func setAndReset() throws {
            let (text, sheet) = try setup()
            let range = NSRange(location: at("Due", text), length: 0)
            var values = StyleValues()
            values.keeping.together = true
            TextStyling.setValue(values, of: .keepTogether, in: text, range: range)
            #expect(TextStyling.lineKeeping(in: text, at: range.location) == LineKeeping(together: true, linesAtStart: 3))
            #expect(inspected(text, sheet, "Due")[.keepTogether]?.source == .own)
            #expect(TextStyling.lineKeeping(in: text, at: at("Uno", text)).isEmpty)
            TextStyling.resetValue(of: .widowLines, in: text, range: range, sheet: sheet)
            #expect(TextStyling.lineKeeping(in: text, at: range.location) == LineKeeping(together: true))
            #expect(inspected(text, sheet, "Due")[.widowLines]?.value.keeping.linesAtStart == 2)
        }

        @Test("Portare nello stile il valore dato qui")
        func moveToStyle() throws {
            let (text, sheet) = try setup()
            let moved = try #require(TextStyling.sheet(sheet, takingValueOf: .widowLines, from: text, at: at("Due", text)))
            #expect(moved.values(of: "Tenuto").keeping == LineKeeping(linesAtEnd: 2, linesAtStart: 3))
            // Lo stesso valore dello stile su cui si basa: lo stile smette di fissarlo.
            let back = try #require(TextStyling.sheet(sheet, takingValueOf: .orphanLines, from: text, at: at("Tre", text)))
            #expect(back.styles.first { $0.name == "Titolo" }?.values.keeping == LineKeeping(withNext: true))
        }

        @Test("La scheda Stili: valori, provenienza, fissare e togliere")
        func styleForm() throws {
            let (_, sheet) = try setup()
            let base = TextStyling.styleBase
            let shown = Dictionary(uniqueKeysWithValues: sheet.inspect(style: "Tenuto", base: base).filter(\.property.isLineKeeping).map { ($0.property, $0) })
            #expect(shown.count == 4)
            #expect(shown[.orphanLines]?.source == .own)
            #expect(shown[.keepTogether]?.source == .document)
            var values = StyleValues()
            values.keeping.together = true
            let set = sheet.setting(values, of: .keepTogether, inStyle: "Tenuto", base: base)
            #expect(set.values(of: "Tenuto").keeping == LineKeeping(together: true, linesAtEnd: 2, linesAtStart: 2))
            let reset = set.resetting(.orphanLines, inStyle: "Tenuto")
            #expect(reset.values(of: "Tenuto").keeping == LineKeeping(together: true, linesAtStart: 2))
            // Un valore uguale a quello ereditato non si fissa.
            var off = StyleValues()
            off.keeping.withNext = false
            #expect(sheet.setting(off, of: .keepWithNext, inStyle: "Tenuto", base: base).values(of: "Tenuto").keeping.withNext == false)
            // Gli stili di carattere non hanno queste voci.
            #expect(!StyleSheet.properties(for: .character).contains { $0.isLineKeeping })
        }
    }
}
