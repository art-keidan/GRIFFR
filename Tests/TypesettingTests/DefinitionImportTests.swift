import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Incollare da un altro documento: le definizioni che il testo porta con sé")
    struct DefinitionImportTests {
        private func document(lists: String = "", styles: String = "", floatStyles: String = "", body: String) throws -> Document {
            var source = "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\n"
            if !lists.isEmpty { source += "<lists>\n\(lists)\n</lists>\n" }
            if !styles.isEmpty { source += "<styles>\n\(styles)\n</styles>\n" }
            if !floatStyles.isEmpty { source += "<float-styles>\n\(floatStyles)\n</float-styles>\n" }
            return try DocumentFormat.document(from: source + body + "\n</document>")
        }

        private func size(_ text: NSAttributedString, at index: Int) -> CGFloat {
            CTFontGetSize(text.attribute(.font, at: index, effectiveRange: nil) as! CTFont)
        }

        @Test("Ciò che manca si copia, con le dipendenze: stile di base, Lista dello stile, Lista madre, serie di note e sue definizioni")
        func missingDefinitionsComeAlong() throws {
            let source = try document(
                lists: "<list name=\"Capitoli\" counter=\"I\"/>\n<list name=\"Esempi\" counter=\"1\" parent=\"Capitoli\"/>\n<list name=\"Postille\" counter=\"a\"/>",
                styles: """
                <style name="Base" target="character" size="14"/>
                <style name="Mio" target="character" based-on="Base" italic="on"/>
                <style name="Esempio" target="paragraph" in-list="Esempi"/>
                <style name="Piccolo" target="paragraph" left-indent="12"/>
                <style name="Inutile" target="character" size="30"/>
                """,
                floatStyles: "<float-style name=\"Postilla\" list=\"Postille\" content=\"Piccolo\"/>",
                body: "<p style=\"Esempio\">Uno <t char-style=\"Mio\">due</t><note style=\"Postilla\">tre</note>.</p>")
            let text = source.attributedString().text
            let destination = Document()
            #expect(DefinitionImport.conflicts(of: text, from: source, into: destination).isEmpty)
            let merged = DefinitionImport.merge(text, from: source, into: destination, policy: .keepDestination)
            #expect(Set(merged.styles.styles.map(\.name)) == ["Base", "Mio", "Esempio", "Piccolo"], "«Inutile» non è usato e non viene")
            #expect(Set(merged.lists.map(\.name)) == ["Capitoli", "Esempi", "Postille"])
            #expect(merged.floatStyles.contains { $0.name == "Postilla" && $0.listName == "Postille" && $0.contentStyle == "Piccolo" })
            #expect(merged.text.isEqual(to: text), "il testo non cambia: le definizioni sono le stesse")
        }

        @Test("Stesso nome, definizione diversa: o vince la destinazione, o entra «Enfasi (2)» e il testo la segue")
        func conflictingStyle() throws {
            let source = try document(styles: "<style name=\"Enfasi\" target=\"character\" size=\"14\"/>",
                                      body: "<p>Uno <t char-style=\"Enfasi\">due</t> <t char-style=\"Enfasi\" size=\"20\">tre</t></p>")
            let destination = try document(styles: "<style name=\"Enfasi\" target=\"character\" size=\"10\"/>\n<style name=\"Enfasi (2)\" target=\"character\"/>",
                                           body: "<p>x</p>")
            let text = source.attributedString().text
            #expect(size(text, at: 4) == 14)
            #expect(DefinitionImport.conflicts(of: text, from: source, into: destination) == [.init(kind: .style, name: "Enfasi")])

            let kept = DefinitionImport.merge(text, from: source, into: destination, policy: .keepDestination)
            #expect(kept.styles == destination.styles, "nessuno stile nuovo")
            #expect(size(kept.text, at: 4) == 10, "il testo prende l'Enfasi della destinazione")
            #expect(size(kept.text, at: 8) == 20, "ma ciò che era dato a mano resta")
            #expect(kept.text.attribute(.characterStyleName, at: 4, effectiveRange: nil) as? String == "Enfasi")

            let copied = DefinitionImport.merge(text, from: source, into: destination, policy: .renameCopies)
            #expect(copied.styles.style(named: "Enfasi (3)")?.values.size == 14, "«Enfasi (2)» c'è già: la copia è la (3)")
            #expect(copied.styles.style(named: "Enfasi")?.values.size == 10, "quello della destinazione non cambia")
            #expect(copied.text.attribute(.characterStyleName, at: 4, effectiveRange: nil) as? String == "Enfasi (3)")
            #expect(size(copied.text, at: 4) == 14, "il testo resta com'era")
        }

        @Test("Uno stile che nella destinazione è di un'altra specie entra sempre come copia")
        func otherTargetIsAlwaysCopied() throws {
            let source = try document(styles: "<style name=\"Citazione\" target=\"character\" italic=\"on\"/>",
                                      body: "<p><t char-style=\"Citazione\">uno</t></p>")
            let destination = try document(styles: "<style name=\"Citazione\" target=\"paragraph\" left-indent=\"20\"/>", body: "<p>x</p>")
            let text = source.attributedString().text
            let merged = DefinitionImport.merge(text, from: source, into: destination, policy: .keepDestination)
            #expect(merged.styles.style(named: "Citazione (2)")?.target == .character)
            #expect(merged.text.attribute(.characterStyleName, at: 0, effectiveRange: nil) as? String == "Citazione (2)")
        }

        @Test("Una Lista copiata con un nome nuovo: le voci la seguono senza perdere le loro misure")
        func renamedListKeepsMeasures() throws {
            let source = try document(lists: "<list name=\"Esempi\" counter=\"1\" prefix=\"(\" suffix=\")\"/>",
                                      styles: "<style name=\"Esempio\" target=\"paragraph\" in-list=\"Esempi\"/>",
                                      body: "<p in-list=\"Esempi\" list-indent=\"40\">uno</p>\n<p style=\"Esempio\">due</p>")
            let destination = try document(lists: "<list name=\"Esempi\" counter=\"a\"/>",
                                           styles: "<style name=\"Esempio\" target=\"paragraph\" in-list=\"Esempi\"/>", body: "<p>x</p>")
            let text = source.attributedString().text
            #expect(DefinitionImport.conflicts(of: text, from: source, into: destination) == [.init(kind: .list, name: "Esempi"), .init(kind: .style, name: "Esempio")],
                    "lo stile «Esempio» è scritto uguale nei due documenti, ma rimanda a una Lista diversa: è in conflitto anche lui")
            let merged = DefinitionImport.merge(text, from: source, into: destination, policy: .renameCopies)
            let first = try #require((merged.text.attribute(.listItem, at: 0, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:)))
            #expect(first.listName == "Esempi (2)" && first.textIndent == 40)
            let second = try #require((merged.text.attribute(.listItem, at: 4, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:)))
            #expect(second.listName == "Esempi (2)")
            #expect(merged.text.attribute(.paragraphStyleName, at: 4, effectiveRange: nil) as? String == "Esempio (2)")
            #expect(merged.styles.style(named: "Esempio (2)")?.values.listName == "Esempi (2)")
            #expect(merged.lists.first { $0.name == "Esempi (2)" }?.prefix == "(")

            let kept = DefinitionImport.merge(text, from: source, into: destination, policy: .keepDestination)
            #expect(kept.lists == destination.lists && kept.styles == destination.styles)
            let keptSecond = (kept.text.attribute(.listItem, at: 4, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
            #expect(keptSecond?.listName == "Esempi", "vincendo la destinazione, il paragrafo va nella sua Lista")
        }

        @Test("La serie delle note a piè di pagina non è mai in conflitto e non si copia: le note entrano in quella della destinazione")
        func footnotesJoinTheDestination() throws {
            var source = try document(lists: "<list name=\"Note\" counter=\"1\"/>", body: "<p>Uno<note>nota</note></p>")
            source.noteList = "Note"
            let text = source.attributedString().text
            let destination = Document()
            #expect(DefinitionImport.conflicts(of: text, from: source, into: destination).isEmpty)
            let merged = DefinitionImport.merge(text, from: source, into: destination, policy: .renameCopies)
            #expect(merged.floatStyles == destination.floatStyles)
            #expect(merged.lists.isEmpty)
        }
    }
}
