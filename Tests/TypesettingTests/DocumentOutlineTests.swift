import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("L'albero degli oggetti")
    struct DocumentOutlineTests {
        private func document() throws -> Document {
            try DocumentFormat.document(from: """
                <document version="18" font="HoeflerText-Regular" size="12">
                <lists>
                <list name="Esempi" counter="1" prefix="(" suffix=")"/>
                <list name="Figure" counter="1" prefix="Figura " suffix="." continues="on"/>
                </lists>
                <styles>
                <style name="Titolo 1" target="paragraph" size="18" outline-level="1"/>
                <style name="Titolo 2" target="paragraph" size="14" outline-level="2"/>
                <style name="Testo" target="paragraph"/>
                </styles>
                <float-styles>
                <float-style name="Figura" placement="figure" list="Figure" reference="none" rule="off"/>
                </float-styles>
                <p style="Titolo 1">Capitolo primo</p>
                <p style="Testo">Il primo paragrafo<note>Una nota a piè di pagina</note> del capitolo.</p>
                <p style="Titolo 2">Una sezione</p>
                <p in-list="Esempi">lat. rosa</p>
                <p style="Testo">Una figura<note style="Figura">Il gufo</note> qui.</p>
                <p style="Titolo 1">Capitolo secondo</p>
                <p style="Testo">Ultimo paragrafo.</p>
                </document>
                """)
        }

        @Test("I titoli fanno da rami secondo il livello; sotto, paragrafi, voci, note e figure con i loro segni")
        func tree() throws {
            let document = try document()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, options: document.layoutOptions)
            let tree = DocumentOutline.build(text: text, layout: layout, floatStyles: document.floatStyles)
            #expect(tree.map(\.title) == ["Capitolo primo", "Capitolo secondo"])
            let first = try #require(tree.first?.children)
            #expect(first.map(\.kind) == [.paragraph, .note, .heading(level: 2)])
            #expect(first[0].title == "Il primo paragrafo del capitolo.", "le prime parole senza il testo della nota")
            #expect(first[1].label == "1" && first[1].title == "Una nota a piè di pagina" && first[1].detail == "Nota")
            let section = try #require(first[2].children)
            #expect(section.map(\.kind) == [.listItem, .paragraph, .figure])
            #expect(section[0].label == "(1)" && section[0].title == "lat. rosa")
            #expect(section[2].label == "▣" && section[2].title == "Il gufo" && section[2].detail.hasPrefix("Figura 1"))
            #expect(tree[1].children?.map(\.title) == ["Ultimo paragrafo."])
        }

        @Test("Il filtro tiene ciò che trova e i titoli sopra; l'oggetto sotto il cursore preferisce la nota al paragrafo")
        func filterAndCaret() throws {
            let document = try document()
            let text = document.attributedString().text
            let tree = DocumentOutline.build(text: text, layout: PageLayout.layout(text, options: document.layoutOptions),
                                             floatStyles: document.floatStyles)
            let found = DocumentOutline.filtered(tree, by: "gufo")
            #expect(found.map(\.title) == ["Capitolo primo"])
            #expect(found.first?.children?.first?.children?.map(\.title) == ["Il gufo"])
            #expect(DocumentOutline.filtered(tree, by: "").count == 2)
            let string = text.string as NSString
            let inNote = string.range(of: "piè").location
            #expect(DocumentOutline.item(containing: inNote, in: tree)?.kind == .note)
            let inParagraph = string.range(of: "capitolo.").location
            #expect(DocumentOutline.item(containing: inParagraph, in: tree)?.title == "Il primo paragrafo del capitolo.")
            #expect(DocumentOutline.item(containing: 2, in: tree)?.title == "Capitolo primo")
        }

        @Test("Il livello registrato prevale sul nome dello stile; Testo resta un capoverso")
        func explicitLevel() {
            let text = NSMutableAttributedString(string: "Titolo\nTesto\n")
            let heading = NSRange(location: 0, length: 7)
            let body = NSRange(location: 7, length: 6)
            text.addAttribute(.paragraphStyleName, value: "Titolo 1", range: heading)
            text.addAttribute(.outlineLevel, value: NSNumber(value: 3), range: heading)
            text.addAttribute(.paragraphStyleName, value: "Testo", range: body)
            text.addAttribute(.outlineLevel, value: NSNumber(value: 0), range: body)
            var tree = DocumentOutline.build(text: text, layout: nil, floatStyles: [])
            #expect(tree.count == 1 && tree[0].kind == .heading(level: 3))
            #expect(tree[0].children?.map(\.kind) == [.paragraph])

            // Senza l'attributo il nome dello stile non dice niente: è un capoverso.
            text.removeAttribute(.outlineLevel, range: NSRange(location: 0, length: text.length))
            tree = DocumentOutline.build(text: text, layout: nil, floatStyles: [])
            #expect(tree.first?.kind == .paragraph)
        }
    }
}
