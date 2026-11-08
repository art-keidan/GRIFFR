import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tenuta delle righe: modello e formato (tappa A1)")
    struct LineKeepingTests {
        private let file = """
        <document version="18" font="HoeflerText-Regular" size="12">
        <styles>
        <style name="Testo" target="paragraph"/>
        <style name="Tenuto" target="paragraph" based-on="Testo" orphan-lines="2" widow-lines="2"/>
        <style name="Titolo" target="paragraph" based-on="Testo" keep-with-next="on"/>
        <style name="Citazione" target="paragraph" based-on="Tenuto" keep-together="on" widow-lines="3"/>
        </styles>
        <p style="Testo">Uno.</p>
        <p style="Tenuto">Due.</p>
        <p style="Tenuto" orphan-lines="2">Tre, col valore dello stile scritto a mano.</p>
        <p style="Titolo" keep-with-next="off">Quattro, titolo staccato a mano.</p>
        <p style="Citazione">Cinque.</p>
        <p style="Testo" keep-together="on" widow-lines="4">Sei.</p>
        </document>
        """

        private func paragraphs(_ document: Document) -> [Paragraph] {
            document.blocks.compactMap { if case .paragraph(let paragraph) = $0 { paragraph } else { nil } }
        }

        private func effective(_ document: Document) -> [LineKeeping.Resolved] {
            paragraphs(document).map { document.styles.lineKeeping(styleName: $0.styleName, own: $0.keeping) }
        }

        @Test("Senza voci non c'è tenuta, e il file non cambia")
        func absentMeansNone() throws {
            let document = try DocumentFormat.document(from: """
            <document version="18" font="HoeflerText-Regular" size="12">
            <styles><style name="Testo" target="paragraph"/></styles>
            <p style="Testo">Uno.</p>
            </document>
            """)
            #expect(effective(document).allSatisfy { $0.isNone })
            let written = DocumentFormat.string(for: document)
            #expect(!LineKeeping.attributeNames.contains { written.contains($0) })
        }

        @Test("Eredità: stile di base, stile, paragrafo; i valori scritti a mano restano scritti")
        func inheritance() throws {
            let document = try DocumentFormat.document(from: file)
            let resolved = effective(document)
            #expect(resolved[0].isNone)
            #expect(resolved[1] == .init(withNext: false, together: false, linesAtEnd: 2, linesAtStart: 2))
            #expect(resolved[2] == resolved[1])
            #expect(resolved[3].isNone)
            #expect(resolved[4] == .init(withNext: false, together: true, linesAtEnd: 2, linesAtStart: 3))
            #expect(resolved[5] == .init(withNext: false, together: true, linesAtEnd: 1, linesAtStart: 4))
            let own = paragraphs(document).map { $0.keeping }
            #expect(own[1].isEmpty && own[4].isEmpty)
            #expect(own[2] == LineKeeping(linesAtEnd: 2))
            #expect(own[3] == LineKeeping(withNext: false))
        }

        @Test("Andata e ritorno: file, modello, testo dell'editor, modello, file")
        func roundTrip() throws {
            let document = try DocumentFormat.document(from: file)
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<style name=\"Citazione\" target=\"paragraph\" based-on=\"Tenuto\" keep-together=\"on\" widow-lines=\"3\"/>"))
            #expect(written.contains("orphan-lines=\"2\">Tre"))
            #expect(written.contains("keep-with-next=\"off\">Quattro"))
            #expect(try DocumentFormat.document(from: written) == document)
            let text = document.attributedString().text
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(paragraphs(back).map { $0.keeping } == paragraphs(document).map { $0.keeping })
            #expect(DocumentFormat.string(for: back) == written)
        }

        @Test("Cambiare lo stile dopo: segue chi eredita, non chi ha il valore scritto a mano")
        func laterStyleChange() throws {
            var document = try DocumentFormat.document(from: file)
            let index = try #require(document.styles.styles.firstIndex { $0.name == "Tenuto" })
            document.styles.styles[index].values.keeping.linesAtEnd = 3
            let titleIndex = try #require(document.styles.styles.firstIndex { $0.name == "Titolo" })
            document.styles.styles[titleIndex].values.keeping.withNext = nil
            let reread = try DocumentFormat.document(from: DocumentFormat.string(for: document))
            let resolved = effective(reread)
            #expect(resolved[1].linesAtEnd == 3)
            #expect(resolved[2].linesAtEnd == 2)
            #expect(resolved[4].linesAtEnd == 3)
            #expect(paragraphs(reread)[3].keeping == LineKeeping(withNext: false))
        }

        @Test("Uno stile ridefinito dal paragrafo ne prende la tenuta effettiva")
        func styleFromParagraph() throws {
            let document = try DocumentFormat.document(from: file)
            let text = document.attributedString().text
            let location = (text.string as NSString).range(of: "Sei.").location
            let values = TextStyling.styleValues(from: text, at: location, target: .paragraph, sheet: document.styles, basedOn: "Body")
            #expect(values.keeping == LineKeeping(together: true, linesAtStart: 4))
        }

        @Test("Valori sbagliati e voci negli stili di carattere sono rifiutati")
        func invalid() {
            for bad in ["<p widow-lines=\"0\">x</p>", "<p orphan-lines=\"10\">x</p>", "<p keep-together=\"yes\">x</p>",
                        "<styles><style name=\"C\" target=\"character\" keep-with-next=\"on\"/></styles><p>x</p>"] {
                #expect(throws: (any Error).self) {
                    try DocumentFormat.document(from: "<document version=\"18\" font=\"HoeflerText-Regular\" size=\"12\">\(bad)</document>")
                }
            }
        }

        @Test("La forma scritta nel testo dell'editor si rilegge")
        func encoding() {
            let keeping = LineKeeping(withNext: false, together: true, linesAtEnd: 2, linesAtStart: 9)
            #expect(LineKeeping(encoded: keeping.encoded) == keeping)
            #expect(LineKeeping(encoded: "") == LineKeeping())
            #expect(LineKeeping(encoded: "end=0") == nil)
            #expect(LineKeeping(encoded: "next=si") == nil)
        }
    }
}
