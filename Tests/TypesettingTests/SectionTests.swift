import AppKit
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Le sezioni: albero nel modello e nel file, segni nel testo dell'editor")
    struct SectionTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

        private func paragraph(_ text: String) -> Paragraph {
            Paragraph(inlines: [.text(TextRun(text, style: body))])
        }

        /// Un libro: una premessa fuori dalle sezioni, una parte con due capitoli (il primo con due sezioni, l'ultima col
        /// titolo vuoto), un'appendice.
        private func book() -> Document {
            let first = Section(id: "c1", role: Section.Role.chapter, title: paragraph("Capitolo primo"), blocks: [.paragraph(paragraph("Testo del capitolo."))],
                                sections: [Section(id: "s11", title: paragraph("1.1"), blocks: [.paragraph(paragraph("Testo di 1.1."))]),
                                           Section(id: "s12", title: paragraph(""), blocks: [.paragraph(paragraph("Testo di 1.2, senza titolo."))])])
            let second = Section(id: "c2", role: Section.Role.chapter, title: paragraph("Capitolo secondo"), blocks: [.paragraph(paragraph("Testo."))])
            let part = Section(id: "p1", role: Section.Role.part, title: paragraph("Parte prima"), sections: [first, second])
            let appendix = Section(id: "a1", role: Section.Role.appendix, title: paragraph("Appendice"), blocks: [.paragraph(paragraph("Tavole."))])
            var document = Document(blocks: [.paragraph(paragraph("Premessa."))])
            document.sections = [part, appendix]
            return document
        }

        @Test("In fila i titoli portano sezione, ruolo e profondità; dalla fila torna lo stesso albero")
        func flat() {
            let document = book()
            let flat = document.flatParagraphs
            #expect(flat.map(\.paragraph.plainText) == ["Premessa.", "Parte prima", "Capitolo primo", "Testo del capitolo.", "1.1", "Testo di 1.1.", "",
                                                        "Testo di 1.2, senza titolo.", "Capitolo secondo", "Testo.", "Appendice", "Tavole."])
            #expect(flat.map { $0.section?.depth ?? 0 } == [0, 1, 2, 0, 3, 0, 3, 0, 2, 0, 1, 0])
            #expect(flat[1].section?.role == "part" && flat[10].section?.role == "appendix")
            var rebuilt = Document()
            rebuilt.setFlatParagraphs(flat)
            #expect(rebuilt.blocks == document.blocks && rebuilt.sections == document.sections)
        }

        @Test("Dalla fila: un segno ripetuto è testo della sezione; una profondità che salta livelli si accorcia")
        func repairs() {
            var document = Document()
            let mark = SectionMark(id: "x", role: "chapter", depth: 1)
            document.setFlatParagraphs([FlatParagraph(paragraph("Tito"), section: mark), FlatParagraph(paragraph("lo"), section: mark),
                                        FlatParagraph(paragraph("Salta"), section: SectionMark(id: "y", role: "section", depth: 3))])
            #expect(document.blocks.isEmpty && document.sections.count == 1)
            #expect(document.sections[0].title.plainText == "Tito")
            #expect(document.sections[0].blocks == [.paragraph(paragraph("lo"))], "Invio in fondo al titolo fa un paragrafo del corpo")
            #expect(document.sections[0].sections.map(\.id) == ["y"], "profondità 3 sotto una di profondità 1 diventa 2")
        }

        @Test("Il segno nel testo si scrive e si rilegge; un segno guasto non si legge")
        func markEncoding() {
            let mark = SectionMark(id: "s1", role: "parte prima", depth: 2)
            #expect(SectionMark(encoded: mark.encoded) == mark)
            #expect(SectionMark(encoded: "s1\n0\nparte") == nil && SectionMark(encoded: "s1\n2") == nil && SectionMark(encoded: "\n1\nparte") == nil)
        }

        private let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document version="1" font="HoeflerText-Regular" size="12">
        <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
        <p>Premessa.</p>
        <section id="p1" role="part">
        <title><p>Parte prima</p></title>
        <section id="c1" role="chapter">
        <title><p>Capitolo primo</p></title>
        <p>Testo del capitolo.</p>
        <section id="s11" role="section">
        <title><p>1.1</p></title>
        <p>Testo di 1.1.</p>
        </section>
        <section id="s12" role="section">
        <title><p/></title>
        <p>Testo di 1.2, senza titolo.</p>
        </section>
        </section>
        <section id="c2" role="chapter">
        <title><p>Capitolo secondo</p></title>
        <p>Testo.</p>
        </section>
        </section>
        <section id="a1" role="appendix">
        <title><p>Appendice</p></title>
        <p>Tavole.</p>
        </section>
        </document>

        """

        @Test("Nel file le sezioni sono annidate; si scrivono e si rileggono identiche")
        func file() throws {
            #expect(DocumentFormat.string(for: book()) == source)
            let read = try DocumentFormat.document(from: source)
            #expect(read.blocks == book().blocks && read.sections == book().sections)
            #expect(DocumentFormat.string(for: read) == source)
        }

        @Test("Il percorso dell'app: file → modello → testo dell'editor → modello → file, senza perdere le sezioni")
        func throughEditorText() throws {
            let document = try DocumentFormat.document(from: source)
            let (text, _) = document.attributedString()
            let titles = (0..<text.length).compactMap { text.attribute(.sectionTitle, at: $0, effectiveRange: nil) as? String }
            #expect(Set(titles).count == 6, "sei titoli segnati, anche quello vuoto (sul suo a capo)")
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(back.sections == document.sections && back.blocks == document.blocks)
            #expect(DocumentFormat.string(for: back) == source)
        }

        @Test("Un ultimo paragrafo vuoto che è un titolo si dichiara sull'a capo che lo precede")
        func emptyFinalTitle() {
            var document = Document(blocks: [.paragraph(paragraph("Testo."))])
            document.sections = [Section(id: "fine", role: "chapter", title: paragraph(""))]
            let (text, _) = document.attributedString()
            #expect(text.string == "Testo.\n")
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(back.sections == document.sections && back.blocks == document.blocks)
        }

        @Test("Un file senza sezioni si apre come prima; senza id né ruolo valgono un identificativo nuovo e «sezione»")
        func defaults() throws {
            let plain = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><p>a</p><p>b</p></document>")
            #expect(plain.sections.isEmpty && plain.blocks.count == 2)
            let bare = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><section><title/><p>a</p></section></document>")
            #expect(bare.sections.count == 1 && bare.sections[0].role == "section" && bare.sections[0].id.hasPrefix("s"))
            #expect(bare.sections[0].title.plainText.isEmpty && bare.sections[0].blocks.count == 1)
        }

        @Test("Incollare: un titolo copiato apre una sezione nuova; un pezzo dentro un paragrafo perde il segno")
        func pasting() {
            let (original, _) = book().attributedString()
            let copy = NSMutableAttributedString(attributedString: original)
            copy.renewSectionIdentities()
            let pasted = Document(attributedString: copy, settings: book().settingsOnly)
            func ids(_ sections: [Section]) -> [String] { sections.flatMap { [$0.id] + ids($0.sections) } }
            #expect(ids(pasted.sections).count == 6 && Set(ids(pasted.sections)).isDisjoint(with: ids(book().sections)))
            #expect(pasted.flatParagraphs.map(\.paragraph) == book().flatParagraphs.map(\.paragraph), "cambia solo l'identità")
            #expect(pasted.flatParagraphs.map { $0.section?.depth } == book().flatParagraphs.map { $0.section?.depth })
            copy.removeSectionMarks()
            #expect(Document(attributedString: copy, settings: book().settingsOnly).sections.isEmpty)
        }

        // MARK: Nel testo dell'editor (tappa S.2a)

        private func editable() -> NSMutableAttributedString { NSMutableAttributedString(attributedString: book().attributedString().text) }
        private func tree(_ text: NSAttributedString) -> Document { Document(attributedString: text, settings: book().settingsOnly) }
        private func outline(_ sections: [Section], depth: Int = 1) -> [String] {
            sections.flatMap { ["\(depth) \($0.role) \($0.title.plainText)"] + outline($0.sections, depth: depth + 1) }
        }
        private func location(of string: String, in text: NSAttributedString) -> Int { (text.string as NSString).range(of: string).location }

        @Test("Struttura nel testo: i titoli con la loro profondità, le sezioni che contengono un punto")
        func structure() {
            let text = editable()
            #expect(SectionEditing.titles(in: text).map(\.depth) == [1, 2, 3, 3, 2, 1])
            #expect(SectionEditing.enclosing(in: text, at: location(of: "Testo di 1.1.", in: text)).map(\.mark.id) == ["p1", "c1", "s11"])
            #expect(SectionEditing.enclosing(in: text, at: 0).isEmpty, "la premessa sta fuori dalle sezioni")
            #expect(SectionEditing.title(in: text, atParagraphContaining: location(of: "apitolo secondo", in: text))?.mark.id == "c2")
        }

        @Test("Aprire una sezione al cursore: allo stesso livello spezza il paragrafo, e ciò che segue entra nella sezione nuova")
        func insertSameLevel() {
            let text = editable()
            let point = location(of: " del capitolo.", in: text)
            let title = SectionEditing.insertSection(in: text, at: point, level: .same, sheet: .builtIn)
            #expect(title == point + 1 && (text.string as NSString).substring(with: NSRange(location: point - 5, length: 8)) == "Testo\n\n ")
            let document = tree(text)
            #expect(outline(document.sections) == ["1 part Parte prima", "2 chapter Capitolo primo", "2 chapter ", "3 section 1.1", "3 section ",
                                                   "2 chapter Capitolo secondo", "1 appendix Appendice"])
            #expect(document.sections[0].sections[0].blocks.map { if case .paragraph(let p) = $0 { p.plainText } else { "" } } == ["Testo"])
            #expect(document.sections[0].sections[1].blocks.count == 1, "« del capitolo.» passa al capitolo nuovo, con le sue sezioni")
        }

        @Test("Dentro e più fuori; prima di un paragrafo e dopo; ruolo e stile del titolo presi dalle sezioni sorelle")
        func insertLevels() {
            let text = editable()
            SectionEditing.insertSection(in: text, at: location(of: "Testo.", in: text), level: .inside, sheet: .builtIn)
            #expect(outline(tree(text).sections).contains("3 section "), "dentro il capitolo secondo, prima del suo testo")
            let inner = location(of: "Testo di 1.1.", in: text)
            SectionEditing.insertSection(in: text, at: inner + ("Testo di 1.1." as NSString).length, level: .outside, sheet: .builtIn)
            let names = outline(tree(text).sections)
            #expect(names.prefix(5) == ["1 part Parte prima", "2 chapter Capitolo primo", "3 section 1.1", "2 chapter ", "3 section "],
                    "più fuori dopo «Testo di 1.1.»: un capitolo, che prende la sezione 1.2 che seguiva")
            var plain = NSMutableAttributedString(attributedString: Document(blocks: [.paragraph(paragraph("Uno")), .paragraph(paragraph("Due"))]).attributedString().text)
            let first = SectionEditing.insertSection(in: plain, at: 0, level: .same, sheet: .builtIn)
            #expect(first == 0 && plain.string == "\nUno\nDue")
            #expect(plain.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Heading 1", "primo livello: Titolo 1")
            #expect(tree(plain).sections.first?.role == "chapter" && tree(plain).blocks.isEmpty)
            plain = NSMutableAttributedString(attributedString: Document(blocks: [.paragraph(paragraph("Uno")), .paragraph(paragraph("Due"))]).attributedString().text)
            SectionEditing.insertSection(in: plain, at: 3, level: .same, sheet: .builtIn)
            #expect(plain.string == "Uno\n\nDue", "alla fine di un paragrafo: il titolo dopo")
            SectionEditing.insertSection(in: plain, at: plain.length, level: .inside, sheet: .builtIn)
            #expect(plain.string == "Uno\n\nDue\n\n", "alla fine del testo: un titolo e un paragrafo vuoto dopo")
            #expect(outline(tree(plain).sections) == ["1 chapter ", "2 section "])
            #expect(plain.attribute(.paragraphStyleName, at: 9, effectiveRange: nil) as? String == "Heading 2")
        }

        @Test("Il ruolo di una sezione nuova: dalle sorelle, poi da chi ha un genitore dello stesso ruolo, altrimenti dalla profondità")
        func roleOfNewSection() {
            let text = editable()
            SectionEditing.insertSection(in: text, at: location(of: "Tavole.", in: text), level: .inside, sheet: .builtIn)
            #expect(outline(tree(text).sections).last == "2 section ", "dentro l'appendice: non «capitolo» come i capitoli della parte")
            SectionEditing.insertSection(in: text, at: location(of: "Testo.", in: text), level: .inside, sheet: .builtIn)
            #expect(outline(tree(text).sections).contains("3 section "), "dentro il capitolo secondo: «sezione», come le sezioni del capitolo primo")
            SectionEditing.insertSection(in: text, at: location(of: "Testo del capitolo.", in: text), level: .same, sheet: .builtIn)
            #expect(outline(tree(text).sections)[2] == "2 chapter ", "accanto a un capitolo: un capitolo")
        }

        @Test("Togliere una sezione: il suo testo passa alla sezione prima, le interne salgono di un livello e restano sorelle")
        func remove() throws {
            let text = editable()
            let chapter = try #require(SectionEditing.titles(in: text).first { $0.mark.id == "c1" })
            SectionEditing.removeSection(chapter, in: text)
            #expect(outline(tree(text).sections) == ["1 part Parte prima", "2 section 1.1", "2 section ", "2 chapter Capitolo secondo", "1 appendix Appendice"])
            #expect(SectionEditing.titles(in: text).allSatisfy { $0.mark.depth == $0.depth }, "i segni dicono la profondità vera")
            #expect(tree(text).sections[0].blocks.count == 2, "titolo e testo del capitolo restano, come paragrafi della parte")
        }

        // MARK: Per l'ispettore (tappa S.2b)

        private func title(_ id: String, _ text: NSAttributedString) -> SectionEditing.Title? { SectionEditing.titles(in: text).first { $0.mark.id == id } }

        @Test("Estensione e contenuto di una sezione: paragrafi (anche delle interne) e sezioni interne dirette")
        func contents() throws {
            let text = editable()
            let part = try #require(title("p1", text)), chapter = try #require(title("c1", text)), last = try #require(title("a1", text))
            #expect((text.string as NSString).substring(with: SectionEditing.range(of: chapter, in: text)).hasSuffix("Testo di 1.2, senza titolo.\n"))
            #expect(SectionEditing.contents(of: chapter, in: text) == (paragraphs: 5, sections: 2), "testo, 1.1 col suo testo, titolo vuoto col suo testo")
            #expect(SectionEditing.contents(of: part, in: text) == (paragraphs: 8, sections: 2))
            #expect(SectionEditing.contents(of: last, in: text) == (paragraphs: 1, sections: 0))
        }

        @Test("Il ruolo si cambia; la sezione scende sotto la sorella che la precede o sale, con le sue interne")
        func roleAndMoves() throws {
            let text = editable()
            SectionEditing.setRole("lezione", of: try #require(title("c2", text)), in: text)
            #expect(outline(tree(text).sections).contains("2 lezione Capitolo secondo"))
            #expect(!SectionEditing.canMoveInside(try #require(title("c1", text)), in: text), "il primo capitolo non ha una sorella prima")
            #expect(SectionEditing.canMoveInside(try #require(title("c2", text)), in: text))
            #expect(SectionEditing.moveSection(try #require(title("c2", text)), by: 1, in: text))
            #expect(outline(tree(text).sections) == ["1 part Parte prima", "2 chapter Capitolo primo", "3 section 1.1", "3 section ", "3 lezione Capitolo secondo",
                                                     "1 appendix Appendice"], "dopo le sezioni del capitolo primo, come sua ultima interna")
            #expect(SectionEditing.moveSection(try #require(title("c1", text)), by: -1, in: text))
            #expect(outline(tree(text).sections) == ["1 part Parte prima", "1 chapter Capitolo primo", "2 section 1.1", "2 section ", "2 lezione Capitolo secondo",
                                                     "1 appendix Appendice"], "sale con le sue interne")
            #expect(!SectionEditing.moveSection(try #require(title("a1", text)), by: -1, in: text), "al primo livello non si sale")
            #expect(SectionEditing.titles(in: text).allSatisfy { $0.mark.depth == $0.depth })
        }

        // MARK: Lo stile che apre una sezione e l'albero (tappa S.2c)

        @Test("Uno stile che apre una sezione: il paragrafo diventa titolo; profondità dalle sezioni dello stesso ruolo, o dentro quella in cui cade")
        func opensFromStyle() {
            let text = NSMutableAttributedString(attributedString: Document(blocks: ["Uno", "Due", "Tre", "Quattro"].map { .paragraph(paragraph($0)) }).attributedString().text)
            func range(_ word: String) -> NSRange { (text.string as NSString).range(of: word) }
            SectionEditing.openSections(role: "chapter", inParagraphsOf: range("Due"), in: text)
            SectionEditing.openSections(role: "section", inParagraphsOf: range("Tre"), in: text)
            #expect(outline(tree(text).sections) == ["1 chapter Due", "2 section Tre"], "la sezione nasce dentro il capitolo in cui cade")
            SectionEditing.openSections(role: "chapter", inParagraphsOf: range("Quattro"), in: text)
            #expect(outline(tree(text).sections) == ["1 chapter Due", "2 section Tre", "1 chapter Quattro"], "un capitolo va dove sono gli altri capitoli")
            SectionEditing.openSections(role: "part", inParagraphsOf: range("Due"), in: text)
            #expect(outline(tree(text).sections).first == "1 chapter Due", "un titolo resta la sezione che era")
            SectionEditing.openSections(role: "chapter", inParagraphsOf: NSRange(location: 0, length: text.length), in: text)
            #expect(outline(tree(text).sections) == ["1 chapter Uno", "1 chapter Due", "2 section Tre", "1 chapter Quattro"], "più paragrafi in una volta")
        }

        @Test("Nel file: opens-section sugli stili di paragrafo; Titolo 1 e Titolo 2 già pronti aprono capitolo e sezione")
        func opensSectionInFile() throws {
            #expect(StyleSheet.builtIn.values(of: "Heading 1").opensSection == "chapter" && StyleSheet.builtIn.values(of: "Heading 2").opensSection == "section")
            #expect(StyleSheet.builtIn.values(of: "Body").opensSection == nil)
            let document = Document(styles: .builtIn, lists: ListDefinition.builtIn, blocks: [.paragraph(paragraph("a"))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("opens-section=\"chapter\"") && written.contains("opens-section=\"section\""))
            #expect(try DocumentFormat.document(from: written).styles == document.styles)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><styles><style name=\"L\" target=\"word\" opens-section=\"chapter\"/></styles></document>")) == nil,
                    "solo uno stile di paragrafo apre una sezione")
        }

        @Test("L'albero degli oggetti: con le sezioni i rami sono le sezioni, con il ruolo a destra; senza, i titoli per stile")
        func outlineBySections() {
            let items = DocumentOutline.build(text: book().attributedString().text, layout: nil, floatStyles: [])
            func names(_ items: [OutlineItem], depth: Int = 0) -> [String] {
                items.flatMap { ["\(String(repeating: "  ", count: depth))\($0.label) \($0.title) [\($0.detail)]"] + names($0.children ?? [], depth: depth + 1) }
            }
            #expect(names(items) == ["¶ Premessa. []", "§ Parte prima [part]", "  § Capitolo primo [chapter]", "    ¶ Testo del capitolo. []",
                                     "    § 1.1 [section]", "      ¶ Testo di 1.1. []", "    § (untitled) [section]", "      ¶ Testo di 1.2, senza titolo. []",
                                     "  § Capitolo secondo [chapter]", "    ¶ Testo. []", "§ Appendice [appendix]", "  ¶ Tavole. []"])
        }

        // MARK: Dove comincia una sezione (tappa S.3a)

        private func pagedBook() -> Document {
            var document = Document(blocks: [.paragraph(paragraph("Premessa."))])
            document.sections = [
                Section(id: "c1", role: "chapter", title: paragraph("Uno"), blocks: [.paragraph(paragraph("Testo uno."))], start: .newPage),
                Section(id: "c2", role: "chapter", title: paragraph("Due"), blocks: [.paragraph(paragraph("Testo due."))], start: .oddPage),
                Section(id: "c3", role: "chapter", title: paragraph("Tre"), blocks: [.paragraph(paragraph("Testo tre."))], start: .oddPage),
                Section(id: "c4", role: "chapter", title: paragraph("Quattro"), blocks: [.paragraph(paragraph("Testo quattro."))]),
            ]
            return document
        }

        @Test("Una sezione comincia su una pagina nuova o sulla prossima dispari; di seguito, resta sulla stessa pagina")
        func pageStarts() {
            let text = pagedBook().attributedString().text
            let layout = PageLayout.layout(text, appliesFontTracking: false)
            func page(of word: String) -> Int? {
                let location = (text.string as NSString).range(of: word).location
                return layout.pages.firstIndex { $0.lines.contains { $0.paragraphLocation == location } }.map { $0 + 1 }
            }
            #expect(page(of: "Premessa.") == 1 && page(of: "Uno") == 2 && page(of: "Testo uno.") == 2)
            #expect(page(of: "Due") == 3, "pagina 3: già dispari, nessuna pagina bianca")
            #expect(page(of: "Tre") == 5 && layout.pages[3].lines.isEmpty, "la 4 resta bianca")
            #expect(page(of: "Quattro") == 5, "di seguito")
            #expect(layout.pages.count == 5)
        }

        @Test("Nel file start=\"new-page\" e start=\"odd-page\"; una sezione nuova copia l'inizio dalla sorella")
        func startInFileAndCopy() throws {
            let written = DocumentFormat.string(for: pagedBook())
            #expect(written.contains("<section id=\"c1\" role=\"chapter\" start=\"new-page\">") && written.contains("<section id=\"c4\" role=\"chapter\">"))
            let read = try DocumentFormat.document(from: written)
            #expect(read.sections == pagedBook().sections)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><section start=\"altrove\"><title/></section></document>")) == nil)
            let text = NSMutableAttributedString(attributedString: pagedBook().attributedString().text)
            SectionEditing.insertSection(in: text, at: location(of: "Testo due.", in: text) + 10, level: .same, sheet: .builtIn)
            #expect(tree(text).sections.map(\.start) == [.newPage, .oddPage, .oddPage, .oddPage, .continuous], "la nuova, dopo «Due», copia la dispari")
            let due = try #require(title("c2", text))
            SectionEditing.setStart(.continuous, of: due, in: text)
            #expect(tree(text).sections[1].start == .continuous)
            #expect(SectionEditing.opensSequence(in: text, atParagraph: 0) && SectionEditing.opensSequence(in: text, atParagraph: location(of: "Uno", in: text)))
            #expect(!SectionEditing.opensSequence(in: text, atParagraph: location(of: "Due", in: text)))
        }

        // MARK: La distanza d'apertura (tappa S.3b)

        /// Un libro con i titoli in «Titolo 1» (distanza d'apertura `distance`): il primo capitolo su una pagina nuova, il
        /// secondo di seguito.
        private func openingBook(distance: Double?, own: Double? = nil) -> Document {
            var sheet = StyleSheet.builtIn
            if let index = sheet.styles.firstIndex(where: { $0.name == "Heading 1" }) { sheet.styles[index].values.openingDistance = distance }
            func titled(_ text: String) -> Paragraph {
                Paragraph(styleName: "Heading 1", style: sheet.resolveParagraph(styleName: "Heading 1"),
                          inlines: [.text(TextRun(text, style: sheet.resolveCharacter(paragraphStyle: "Heading 1", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)))])
            }
            var first = titled("Uno")
            first.openingDistance = own
            var document = Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [.paragraph(paragraph("Premessa."))])
            document.sections = [Section(id: "c1", role: "chapter", title: first, blocks: [.paragraph(paragraph("Testo uno."))], start: .newPage),
                                 Section(id: "c2", role: "chapter", title: titled("Due"), blocks: [.paragraph(paragraph("Testo due."))])]
            return document
        }

        private func titleTop(_ document: Document, _ word: String) -> CGFloat? {
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let location = (text.string as NSString).range(of: word).location
            return layout.pages.lazy.compactMap { $0.lines.first { $0.paragraphLocation == location } }.first.map { $0.origin.y + $0.ascent }
        }

        @Test("La distanza d'apertura: il titolo che apre una pagina scende, misurato dal margine superiore; di seguito no")
        func openingDistanceLayout() throws {
            let plain = try #require(titleTop(openingBook(distance: nil), "Uno")), lowered = try #require(titleTop(openingBook(distance: 50), "Uno"))
            #expect(abs((plain - lowered) - 50) < 0.01, "scende di 50 pt, senza lo spazio prima del titolo")
            let ownTop = try #require(titleTop(openingBook(distance: 50, own: 20), "Uno"))
            #expect(abs((plain - ownTop) - 20) < 0.01, "quella data a mano vince sullo stile")
            let gapPlain = try #require(titleTop(openingBook(distance: nil), "Due")) - plain
            let gapLowered = try #require(titleTop(openingBook(distance: 50), "Due")) - lowered
            #expect(abs(gapPlain - gapLowered) < 0.01, "un titolo di seguito non scende di suo: segue soltanto il testo prima")
        }

        @Test("Nel file opening-distance su paragrafi e stili; nell'ispettore la provenienza, dato qui, torna allo stile")
        func openingDistanceFileAndInspector() throws {
            let document = openingBook(distance: 50, own: 20)
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("opening-distance=\"50\"") && written.contains("opening-distance=\"20\""))
            let read = try DocumentFormat.document(from: written)
            #expect(read.sections == document.sections && read.styles == document.styles)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><p opening-distance=\"-3\">a</p></document>")) == nil)

            let text = NSMutableAttributedString(attributedString: openingBook(distance: 50).attributedString().text)
            let due = (text.string as NSString).range(of: "Due").location
            func value() -> InspectedValue? {
                TextStyling.inspect(.paragraph, in: text, range: NSRange(location: due, length: 0), sheet: openingBook(distance: 50).styles)
                    .first { $0.property == .openingDistance }
            }
            #expect(value()?.value.openingDistance == 50 && value()?.source == .style("Heading 1"))
            var values = StyleValues()
            values.openingDistance = 30
            TextStyling.setValue(values, of: .openingDistance, in: text, range: NSRange(location: due, length: 0))
            #expect(value()?.value.openingDistance == 30 && value()?.source == .own)
            TextStyling.resetValue(of: .openingDistance, in: text, range: NSRange(location: due, length: 0), sheet: openingBook(distance: 50).styles)
            #expect(value()?.value.openingDistance == 50 && value()?.source == .style("Heading 1"))
        }

        // MARK: Liste per sezione (tappa S.4)

        @Test("Il contatore: una Lista che riparte a ogni sezione di un ruolo riparte quando ne passa una")
        func numbererSections() {
            var numberer = ListNumberer(definitions: [ListDefinition(name: "Examples", counter: .decimal, parent: .section("chapter"), continues: true)])
            #expect(numberer.next("Examples")?.text == "1" && numberer.next("Examples")?.text == "2")
            numberer.passSection(role: "section")
            #expect(numberer.next("Examples")?.text == "3", "una sezione di un altro ruolo non conta")
            numberer.passSection(role: "chapter")
            #expect(numberer.next("Examples")?.text == "1")
        }

        private func numberedBook() -> Document {
            let lists = [
                ListDefinition(name: "Capitoli", counter: .decimal, suffix: ".", continues: true, numbersSections: "chapter"),
                ListDefinition(name: "Paragrafi", counter: .decimal, prefix: ".", parent: .list("Capitoli"), continues: true, showsParent: true, numbersSections: "section"),
                ListDefinition(name: "Examples", counter: .decimal, prefix: ".", parent: .section("chapter"), continues: true, showsParent: true),
                ListDefinition(name: "Notes", counter: .decimal, parent: .section("chapter"), continues: true),
            ]
            func example(_ text: String) -> Paragraph { Paragraph(list: ListItem(listName: "Examples"), inlines: [.text(TextRun(text, style: body))]) }
            func noted(_ text: String) -> Paragraph {
                Paragraph(inlines: [.text(TextRun(text, style: body)), .floating(FloatingObject(paragraphs: [[TextRun("Nota.", style: body)]]))])
            }
            var document = Document(lists: lists, noteList: "Notes", blocks: [.paragraph(paragraph("Premessa."))])
            document.sections = [
                Section(id: "c1", role: "chapter", title: paragraph("Primo"), blocks: [.paragraph(example("Es. a")), .paragraph(noted("Con nota"))],
                        sections: [Section(id: "s11", title: paragraph("Uno"), blocks: [.paragraph(example("Es. b"))]),
                                   Section(id: "s12", title: paragraph(""), blocks: [.paragraph(paragraph("Senza titolo."))])]),
                Section(id: "c2", role: "chapter", title: paragraph("Secondo"), blocks: [.paragraph(example("Es. c")), .paragraph(noted("Altra nota"))]),
            ]
            return document
        }

        @Test("Una Lista numera le sezioni di un ruolo; le altre ripartono a ogni capitolo e ne scrivono il numero; le note anche")
        func sectionNumbering() throws {
            let document = numberedBook()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            func mark(_ word: String) -> String? { layout.listMarks[(text.string as NSString).range(of: word).location] }
            #expect(mark("Primo") == "1." && mark("Secondo") == "2.")
            #expect(mark("Uno") == "1.1", "le sezioni del capitolo: «1.1», con il numero del capitolo davanti")
            let untitled = try #require(title("s12", text))
            #expect(layout.listMarks[untitled.range.location] == "1.2", "anche una sezione senza titolo ha il suo numero")
            #expect(mark("Es. a") == "1.1" && mark("Es. b") == "1.2" && mark("Es. c") == "2.1", "gli esempi ripartono a ogni capitolo")
            let notes = layout.noteMarks.sorted { $0.key < $1.key }.map(\.value)
            #expect(notes == ["1", "1"], "le note ripartono a ogni capitolo")
            #expect(mark("Premessa.") == nil)

            let items = DocumentOutline.build(text: text, layout: layout, floatStyles: document.floatStyles)
            #expect(items.dropFirst().map(\.label) == ["1.", "2."] && items[1].children?.compactMap { $0.kind == .heading(level: 2) ? $0.label : nil } == ["1.1", "1.2"])
        }

        @Test("Nel file parent-section e numbers-sections; parent e parent-section insieme non vanno")
        func sectionListsInFile() throws {
            let written = DocumentFormat.string(for: numberedBook())
            #expect(written.contains("numbers-sections=\"chapter\"") && written.contains("parent-section=\"chapter\""))
            #expect(try DocumentFormat.document(from: written).lists == numberedBook().lists)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><lists><list name=\"A\" counter=\"1\" parent=\"page\" parent-section=\"chapter\"/></lists></document>")) == nil)
        }

        // MARK: Tipi di pagina (tappa S.5a)

        private func mm(_ value: Double) -> CGFloat { PageSetup.points(fromMillimetres: value) }

        /// Un libro con tre tipi di pagina: l'apertura dei capitoli (margini larghi, specchio stretto), una pagina
        /// orizzontale, una per le pari.
        private func typedBook() -> Document {
            let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 90)
            var document = Document(blocks: [.paragraph(paragraph("Premessa."))])
            document.pageTypes = [
                PageType(name: "Apertura", setup: PageSetup(paperSize: PageSetup.a4.paperSize, top: mm(80), bottom: mm(25), left: mm(45), right: mm(45))),
                PageType(name: "Orizzontale", setup: PageSetup(paperSize: CGSize(width: mm(297), height: mm(210)), top: mm(20), bottom: mm(20), left: mm(25), right: mm(25))),
                PageType(name: "Pari", setup: PageSetup(paperSize: PageSetup.a4.paperSize, top: mm(25), bottom: mm(25), left: mm(35), right: mm(15))),
            ]
            document.sections = [
                Section(id: "c1", role: "chapter", title: paragraph("Uno"), blocks: [.paragraph(paragraph(long))], start: .newPage,
                        pageTypes: SectionPageTypes(firstPage: "Apertura")),
                Section(id: "c2", role: "chapter", title: paragraph("Due"), blocks: [.paragraph(paragraph("Tavola."))],
                        sections: [Section(id: "s21", title: paragraph("Due.1"), blocks: [.paragraph(paragraph(long))])],
                        start: .newPage, pageTypes: SectionPageTypes(pages: "Orizzontale")),
                Section(id: "c3", role: "chapter", title: paragraph("Tre"), blocks: [.paragraph(paragraph(long))], start: .newPage,
                        pageTypes: SectionPageTypes(pages: PageType.defaultName, evenPages: "Pari")),
            ]
            return document
        }

        @Test("Nel file <page-types> e i tipi delle sezioni; un tipo che non c'è, o col nome del predefinito, non si legge")
        func pageTypesInFile() throws {
            let written = DocumentFormat.string(for: typedBook())
            #expect(written.contains("<page-type name=\"Orizzontale\" width=\"297mm\" height=\"210mm\""))
            #expect(written.contains("first-page-type=\"Apertura\"") && written.contains("even-page-type=\"Pari\"") && written.contains("page-type=\"Default\""))
            let read = try DocumentFormat.document(from: written)
            #expect(read.pageTypes == typedBook().pageTypes && read.sections == typedBook().sections)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><section page-type=\"Nessuno\"><title/></section></document>")) == nil)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><page-types><page-type name=\"Default\"/></page-types></document>")) == nil)
        }

        @Test("Ogni pagina col suo tipo: prima pagina, tipo ereditato dalle interne, pari e dispari; il seguito di un paragrafo si ricompone")
        func pagesByType() throws {
            let document = typedBook()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let types = Dictionary(uniqueKeysWithValues: document.pageTypes.map { ($0.name, $0.setup) })
            func pages(of word: String) -> [Int] {
                let paragraph = TextStyling.bodyParagraph(in: text, at: (text.string as NSString).range(of: word).location).range
                return layout.pages.indices.filter { layout.pages[$0].lines.contains { $0.paragraphLocation == paragraph.location } }
            }
            let one = pages(of: "Uno")[0]
            #expect(layout.pages[one].setup == types["Apertura"], "la prima pagina del capitolo")
            let rest = pages(of: "Una frase")
            #expect(rest.first == one && rest.count >= 2 && layout.pages[rest[1]].setup == document.pageSetup, "poi il predefinito")
            // Il seguito ricomposto: nessun carattere perso o ripetuto, e le righe larghe quanto il loro specchio.
            let paragraph = TextStyling.bodyParagraph(in: text, at: (text.string as NSString).range(of: "Una frase").location).range
            let ranges = rest.flatMap { index in layout.pages[index].lines.filter { $0.paragraphLocation == paragraph.location }.map(\.range) }
            #expect(ranges.first?.location == paragraph.location)
            #expect(zip(ranges, ranges.dropFirst()).allSatisfy { NSMaxRange($0.0) == $0.1.location }, "le righe si susseguono senza buchi")
            let firstWidth = layout.pages[one].lines.filter { $0.paragraphLocation == paragraph.location }.map(\.availableWidth).max() ?? 0
            let nextWidth = layout.pages[rest[1]].lines.map(\.availableWidth).max() ?? 0
            #expect(abs(firstWidth - types["Apertura"]!.textRect.width) < 1 && abs(nextWidth - document.pageSetup.textRect.width) < 1)
            // Il capitolo due e la sua sezione interna: orizzontali.
            for index in pages(of: "Due") + pages(of: "Due.1") { #expect(layout.pages[index].setup == types["Orizzontale"]) }
            let inner = layout.pages.indices.filter { index in layout.pages[index].lines.contains { (text.string as NSString).substring(with: $0.range).contains("Una frase") } }
            #expect(inner.contains { layout.pages[$0].setup == types["Orizzontale"] && $0 != pages(of: "Due")[0] }, "la sezione interna eredita il tipo")
            // Il capitolo tre: predefinito nelle dispari, «Pari» nelle pari.
            let three = pages(of: "Tre")[0]
            let threePages = layout.pages.indices.filter { $0 >= three }
            #expect(threePages.count >= 2)
            for index in threePages { #expect(layout.pages[index].setup == ((index + 1) % 2 == 0 ? types["Pari"] : document.pageSetup)) }
        }

        @Test("Il testo che torna al capitolo continua sulla stessa pagina, e le pagine seguenti prendono il tipo del capitolo")
        func returnInLayout() throws {
            var document = typedBook()
            let long = String(repeating: "Una frase del sottocapitolo, abbastanza lunga da riempire le righe. ", count: 60)
            let back = String(repeating: "Il ritorno al capitolo continua per molte righe ancora. ", count: 160)
            document.blocks = []
            document.sections = [
                Section(id: "c", role: "chapter", title: paragraph("Capitolo"), blocks: [.paragraph(paragraph("Primo."))],
                        sections: [Section(id: "s", title: paragraph("Sotto"), blocks: [.paragraph(paragraph(long))], start: .newPage,
                                           pageTypes: SectionPageTypes(pages: "Orizzontale"),
                                           afterward: [.paragraph(paragraph(back))])]),
            ]
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let types = Dictionary(uniqueKeysWithValues: document.pageTypes.map { ($0.name, $0.setup) })
            func pages(of word: String) -> [Int] {
                let paragraph = TextStyling.bodyParagraph(in: text, at: (text.string as NSString).range(of: word).location).range
                return layout.pages.indices.filter { layout.pages[$0].lines.contains { $0.paragraphLocation == paragraph.location } }
            }
            let inner = pages(of: "Una frase del sottocapitolo")
            let returning = pages(of: "Il ritorno al capitolo")
            #expect(inner.allSatisfy { layout.pages[$0].setup == types["Orizzontale"] }, "il sottocapitolo è orizzontale")
            #expect(returning.first == inner.last, "il ritorno continua sulla stessa pagina")
            #expect(returning.count >= 2)
            for index in returning.dropFirst() { #expect(layout.pages[index].setup == document.pageSetup, "poi le pagine del capitolo") }

            // Senza il ritorno, lo stesso testo sarebbe del sottocapitolo: orizzontale.
            var without = document
            without.sections[0].sections[0].blocks.append(.paragraph(paragraph(back)))
            without.sections[0].sections[0].afterward = []
            let plain = without.attributedString().text
            let plainLayout = PageLayout.layout(plain, setup: without.pageSetup, options: without.layoutOptions)
            #expect(plainLayout.pages.last?.setup == types["Orizzontale"])
        }

        @Test("Nel PDF ogni pagina ha il suo formato; una sezione nuova copia i tipi di pagina dalla sorella")
        func pdfPageSizesAndCopy() throws {
            let document = typedBook()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let pdf = try #require(CGPDFDocument(CGDataProvider(data: PDFRenderer.pdfData(for: layout) as CFData)!))
            let sizes = (1...pdf.numberOfPages).compactMap { pdf.page(at: $0)?.getBoxRect(.mediaBox).size }
            #expect(sizes.count == layout.pages.count || sizes.count == layout.pages.count - 1)
            #expect(sizes.contains { abs($0.width - mm(297)) < 1 && abs($0.height - mm(210)) < 1 } && sizes.contains { abs($0.width - mm(210)) < 1 })
            let editable = NSMutableAttributedString(attributedString: text)
            SectionEditing.insertSection(in: editable, at: location(of: "Tavola.", in: editable) + 7, level: .same, sheet: .builtIn)
            #expect(tree(editable).sections[2].pageTypes == SectionPageTypes(pages: "Orizzontale"), "dopo «Due», come «Due»")
        }

        @Test("Rinominare o togliere un tipo di pagina: le sezioni seguono; ogni pagina sa il nome del suo tipo")
        func renamePageTypes() {
            let text = NSMutableAttributedString(attributedString: typedBook().attributedString().text)
            let renames: [String: String?] = ["Orizzontale": "Larga", "Apertura": nil]
            SectionEditing.renamePageTypes(renames, in: text)
            let sections = tree(text).sections
            #expect(sections[1].pageTypes.pages == "Larga" && sections[0].pageTypes.firstPage == nil)
            #expect(sections[2].pageTypes == SectionPageTypes(pages: PageType.defaultName, evenPages: "Pari"), "gli altri restano")
            let document = typedBook()
            let layout = PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
            #expect(layout.pages[0].typeName == nil && layout.pages[1].typeName == "Apertura" && layout.pages.contains { $0.typeName == "Orizzontale" })
        }

        // MARK: Campi e numeri di pagina (tappa H.1)

        private func field(_ field: Field) -> TextRun { TextRun(Field.placeholder, style: body, field: field) }

        /// Una premessa numerata in romani, poi un capitolo che riparte da 1 in cifre arabe, con i campi nel testo.
        private func numberedPages() -> Document {
            let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 160)
            var document = Document(lists: [ListDefinition(name: "Romani", counter: .lowerRoman, continues: true),
                                            ListDefinition(name: "Arabi", counter: .decimal, prefix: "— ", suffix: " —", continues: true)],
                                    blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Premessa, pagina ", style: body)), .text(field(.page)),
                                                                             .text(TextRun(" di ", style: body)), .text(field(.pageCount))])),
                                             .paragraph(paragraph(long))])
            document.pageNumbering = "Romani"
            document.sections = [Section(id: "c1", role: "chapter", title: paragraph("Il primo capitolo"),
                                         blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Qui: ", style: body)), .text(field(.sectionTitle(role: "chapter"))),
                                                                                  .text(TextRun(", pagina ", style: body)), .text(field(.page))])),
                                                  .paragraph(paragraph(long))],
                                         start: .newPage, pageNumbering: "Arabi")]
            return document
        }

        @Test("Il campo nel segno e nel file (anche dentro una nota); due campi vicini restano due")
        func fieldsInFileAndText() throws {
            #expect(Field(encoded: Field.sectionNumber(role: "part").encoded) == .sectionNumber(role: "part") && Field(encoded: "pagina") == nil)
            var document = numberedPages()
            document.blocks.append(.paragraph(Paragraph(inlines: [.text(field(.page)), .text(field(.page)),
                                                                  .floating(FloatingObject(paragraphs: [[TextRun("Nota a pagina ", style: body), field(.page)]]))])))
            let written = DocumentFormat.string(for: document)
            // I campi si scrivono come formule, anche quelli costruiti nella forma storica.
            let page = "<field kind=\"formula\" expression=\"position.page-containing.number.write-here\"/>"
            #expect(written.contains(page + page))
            #expect(written.contains("<field kind=\"formula\" expression=\"position.section-containing.title.write-here\" role=\"chapter\"/>"))
            #expect(written.contains("version=\"13\""), "la sezione contenente richiede il formato 13")
            #expect(written.contains("page-numbering=\"Romani\"") && written.contains("page-numbering=\"Arabi\""))
            let read = try DocumentFormat.document(from: written)
            #expect(read.blocks == document.blocks && read.sections == document.sections && read.pageNumbering == "Romani")
            let (text, _) = read.attributedString()
            let back = Document(attributedString: text, settings: read.settingsOnly)
            #expect(back.blocks == document.blocks, "dal testo dell'editor, i campi tornano uguali")
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><p><field kind=\"data\"/></p></document>")) == nil)
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><p><field kind=\"section-title\"/></p></document>")) == nil, "manca il ruolo")
            #expect((try? DocumentFormat.document(from: "<document version=\"1\" page-numbering=\"Nessuna\"><p>a</p></document>")) == nil)
        }

        @Test("Numeri di pagina da una Lista; una sezione li fa ripartire; i campi scrivono pagina, totale e titolo in corso")
        func pageNumbersAndFields() throws {
            let document = numberedPages()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let numbers = layout.pages.map(\.number)
            let chapter = try #require(numbers.firstIndex(of: "— 1 —"))
            #expect(Array(numbers[..<chapter]) == ["i", "ii", "iii"].prefix(chapter).map { $0 }, "la premessa in romani")
            #expect(numbers[(chapter + 1)...].first == "— 2 —", "il capitolo prosegue in arabi")
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
            let first = pdf.page(at: 0)?.string ?? ""
            #expect(first.contains("Premessa, pagina i di \(layout.pages.count)"))
            let opening = pdf.page(at: chapter)?.string ?? ""
            #expect(opening.contains("Qui: Il primo capitolo, pagina — 1 —"))
        }

        // MARK: Intestazioni e piè di pagina (tappa H.2)

        private func running(_ style: String, _ runs: [TextRun]) -> Inline { .floating(FloatingObject(paragraphs: [runs], style: style)) }

        /// Un libro con un'intestazione e un piè di pagina ancorati all'inizio, e un capitolo con l'intestazione delle pari e
        /// quella della sua prima pagina.
        private func headedBook() -> Document {
            let long = String(repeating: "Una frase abbastanza lunga da riempire molte righe di testo. ", count: 160)
            var pari = FloatStyle.running(name: "Intestazione pari", pages: .even)
            pari.showsRule = true
            var document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Premessa.", style: body)),
                                               running(FloatStyle.headName, [TextRun("Il mio libro", style: body)]),
                                               running(FloatStyle.bottomName, [TextRun("pagina ", style: body), field(.page)])])),
                .paragraph(paragraph(long)),
            ])
            document.floatStyles += [.running(name: FloatStyle.headName), .running(name: FloatStyle.bottomName, placement: .pageBottom), pari,
                                     .running(name: "Apertura", pages: .first)]
            document.sections = [Section(id: "c1", role: "chapter",
                                         title: Paragraph(inlines: [.text(TextRun("Primo", style: body)),
                                                                    running("Intestazione pari", [field(.sectionTitle(role: "chapter"))]),
                                                                    running("Apertura", [TextRun("Apertura del primo", style: body)])]),
                                         blocks: [.paragraph(paragraph(long))], start: .newPage)]
            return document
        }

        @Test("Intestazioni e piè di pagina: da dove sono ancorati in poi, pari e dispari, la prima pagina della sezione, i campi della loro pagina")
        func runningHeads() throws {
            let document = headedBook()
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
            func page(_ index: Int) -> String { pdf.page(at: index)?.string ?? "" }
            let opening = try #require(layout.pages.firstIndex { $0.lines.contains { $0.noteRange == nil && (text.string as NSString).substring(with: $0.range).hasPrefix("Primo") } })
            #expect(opening >= 2, "la premessa occupa almeno due pagine")
            #expect(page(0).contains("Il mio libro") && page(0).contains("pagina 1"), "ancorati nel primo paragrafo: valgono già dalla prima pagina")
            #expect(page(1).contains("Il mio libro") && page(1).contains("pagina 2"))
            #expect(page(opening).contains("Apertura del primo") && !page(opening).contains("Il mio libro"), "la prima pagina del capitolo: la sua intestazione")
            #expect(page(opening).contains("pagina \(opening + 1)"), "il piè di pagina sì")
            let next = opening + 1
            #expect(next < layout.pages.count)
            if (next + 1) % 2 == 0 {
                #expect(page(next).contains("Primo") && !page(next).contains("Il mio libro"), "una pari del capitolo: il titolo del capitolo")
                #expect(!layout.pages[next].rules.isEmpty, "con il suo filetto")
            } else {
                #expect(page(next).contains("Il mio libro"), "una dispari: l'intestazione di prima, che vale ancora")
            }
            // Nei margini: l'intestazione sopra lo specchio, il piè di pagina sotto.
            let setup = layout.pages[0].setup
            let headLine = try #require(layout.pages[0].lines.first { $0.noteRange != nil && $0.origin.y > setup.paperSize.height - setup.top })
            let footLine = try #require(layout.pages[0].lines.first { $0.noteRange != nil && $0.origin.y < setup.bottom })
            #expect(headLine.origin.y < setup.paperSize.height && footLine.origin.y > 0)
        }

        @Test("Nel file gli stili di intestazione e piè di pagina: placement, pages, edge")
        func runningStylesInFile() throws {
            var document = headedBook()
            document.floatStyles[document.floatStyles.count - 1].edgeDistance = 30
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("placement=\"head\"") && written.contains("placement=\"bottom\"") && written.contains("pages=\"even\"") && written.contains("edge=\"30\""))
            let read = try DocumentFormat.document(from: written)
            #expect(read.floatStyles == document.floatStyles && read.blocks == document.blocks && read.sections == document.sections)
            let bare = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><float-styles><float-style name=\"Testa\" placement=\"head\"/></float-styles><p>a</p></document>")
            #expect(bare.floatStyles.last == .running(name: "Testa"), "senza altro, un'intestazione non ha richiamo né filetto")
            #expect((try? DocumentFormat.document(from: "<document version=\"1\"><float-styles><float-style name=\"N\" pages=\"even\"/></float-styles></document>")) == nil,
                    "pages solo per intestazioni e piè di pagina")
        }

        // MARK: Tabelle (tappa T.1)

        private func cell(_ texts: String...) -> TableCell { TableCell(paragraphs: texts.map { paragraph($0) }) }

        private func tabled() -> Document {
            let table = Table(id: "t1", rows: [TableRow(cells: [cell("Nome"), cell("Valore")]),
                                               TableRow(cells: [cell("Alfa", "seconda riga della cella"), cell("1")]),
                                               TableRow(cells: [cell("Beta"), cell("")])], headerRows: 1)
            var document = Document(blocks: [.paragraph(paragraph("Prima.")), .table(table), .paragraph(paragraph("Dopo."))])
            document.sections = [Section(id: "c1", role: "chapter", title: paragraph("Capitolo"),
                                         blocks: [.table(Table(id: "t2", rows: [TableRow(cells: [cell("a"), cell("b")])]))])]
            return document
        }

        @Test("Tabelle: in fila ogni paragrafo ha il segno della sua cella; dalla fila torna la stessa tabella")
        func tablesFlat() {
            let document = tabled()
            let flat = document.flatParagraphs
            #expect(flat.map { $0.cell.map { "\($0.table) \($0.row),\($0.column)" } ?? "-" } ==
                    ["-", "t1 0,0", "t1 0,1", "t1 1,0", "t1 1,0", "t1 1,1", "t1 2,0", "t1 2,1", "-", "-", "t2 0,0", "t2 0,1"])
            #expect(flat[1].cell?.headerRows == 1)
            var rebuilt = Document()
            rebuilt.setFlatParagraphs(flat)
            #expect(rebuilt.blocks == document.blocks && rebuilt.sections == document.sections)
            // Righe corte completate; una tabella interrotta da altro testo diventa un'altra tabella.
            var broken = Document()
            broken.setFlatParagraphs([FlatParagraph(paragraph("a"), cell: CellMark(table: "x", row: 0, column: 0)),
                                      FlatParagraph(paragraph("b"), cell: CellMark(table: "x", row: 0, column: 1)),
                                      FlatParagraph(paragraph("c"), cell: CellMark(table: "x", row: 1, column: 0)),
                                      FlatParagraph(paragraph("in mezzo")),
                                      FlatParagraph(paragraph("d"), cell: CellMark(table: "x", row: 0, column: 0))])
            guard case .table(let first)? = broken.blocks.first, case .table(let second)? = broken.blocks.last else { Issue.record("due tabelle"); return }
            #expect(first.rows.map(\.cells.count) == [2, 2] && first.rows[1].cells[1].paragraphs.count == 1, "la riga corta ha la sua cella vuota")
            #expect(first.id == "x" && second.id != "x")
        }

        private let tableSource = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document version="1" font="HoeflerText-Regular" size="12">
        <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
        <p>Prima.</p>
        <table id="t1" header-rows="1">
        <row>
        <cell><p>Nome</p></cell>
        <cell><p>Valore</p></cell>
        </row>
        <row>
        <cell><p>Alfa</p>
        <p>seconda riga della cella</p></cell>
        <cell><p>1</p></cell>
        </row>
        <row>
        <cell><p>Beta</p></cell>
        <cell><p/></cell>
        </row>
        </table>
        <p>Dopo.</p>
        <section id="c1" role="chapter">
        <title><p>Capitolo</p></title>
        <table id="t2">
        <row>
        <cell><p>a</p></cell>
        <cell><p>b</p></cell>
        </row>
        </table>
        </section>
        </document>

        """

        @Test("Tabelle nel file: righe, celle, paragrafi; si scrivono e si rileggono identiche; lettura severa")
        func tablesInFile() throws {
            #expect(DocumentFormat.string(for: tabled()) == tableSource)
            let read = try DocumentFormat.document(from: tableSource)
            #expect(read.blocks == tabled().blocks && read.sections == tabled().sections)
            let empty = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><table><row><cell/></row></table></document>")
            guard case .table(let table)? = empty.blocks.first else { Issue.record("una tabella"); return }
            #expect(table.rows.first?.cells.first?.paragraphs.count == 1, "una cella vuota ha un paragrafo vuoto")
            func fails(_ content: String) -> Bool {
                (try? DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\(content)</document>")) == nil
            }
            #expect(fails("<table><row><p>fuori dalla cella</p></row></table>") && fails("<table><p>a</p></table>"))
            #expect(fails("<table id=\"a\"><row><cell/></row></table><table id=\"a\"><row><cell/></row></table>"), "due tabelle con la stessa identità")
            #expect(fails("<table header-rows=\"-1\"><row><cell/></row></table>") && fails("<cell/>"))
            #expect(fails("<table/>") && fails("<table><row/></table>"), "una tabella senza righe, una riga senza celle")
        }

        @Test("Tabelle nel testo dell'editor: file → testo → file identico; anche con l'ultima cella vuota in fondo al testo")
        func tablesThroughEditorText() throws {
            let document = try DocumentFormat.document(from: tableSource)
            let (text, _) = document.attributedString()
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(back.blocks == document.blocks && back.sections == document.sections)
            #expect(DocumentFormat.string(for: back) == tableSource)
            let ending = Document(blocks: [.paragraph(paragraph("Prima.")), .table(Table(id: "t", rows: [TableRow(cells: [cell("a"), cell("")])]))])
            let (endingText, _) = ending.attributedString()
            #expect(Document(attributedString: endingText, settings: ending.settingsOnly).blocks == ending.blocks)
        }

        // MARK: L'impaginazione delle tabelle (tappa T.2)

        @Test("Una tabella: celle una accanto all'altra, colonne secondo il contenuto, griglia, righe alte quanto la cella più alta")
        func tableLayout() throws {
            let long = "Una cella con un testo abbastanza lungo da andare a capo più di una volta nella sua colonna."
            let table = Table(id: "t", rows: [TableRow(cells: [cell("N."), cell(long)]), TableRow(cells: [cell("1"), cell("breve")])])
            let document = Document(blocks: [.paragraph(paragraph("Prima.")), .table(table), .paragraph(paragraph("Dopo."))])
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let page = layout.pages[0]
            func lines(of word: String) -> [PlacedLine] {
                let location = TextStyling.bodyParagraph(in: text, at: (text.string as NSString).range(of: word).location).range.location
                return page.lines.filter { $0.paragraphLocation == location }
            }
            let first = try #require(lines(of: "N.").first), longLines = lines(of: "Una cella"), one = try #require(lines(of: "1").first)
            #expect(longLines.count >= 2, "il testo lungo va a capo nella sua colonna")
            #expect(longLines.allSatisfy { $0.origin.x > first.origin.x + 10 }, "la seconda colonna sta a destra della prima")
            #expect(abs(one.origin.x - first.origin.x) < 0.5, "la stessa colonna, la stessa ascissa")
            #expect(one.origin.y < (longLines.last?.origin.y ?? 0), "la seconda riga comincia sotto la cella più alta della prima")
            let area = layout.pages[0].setup.textRect
            #expect(longLines.allSatisfy { $0.origin.x + $0.width <= area.maxX + 0.5 }, "dentro la giustezza")
            #expect(page.rules.count >= 6, "la griglia")
            let after = try #require(lines(of: "Dopo.").first)
            #expect(after.origin.y < one.origin.y, "il paragrafo dopo la tabella sta sotto")
            // La colonna stretta è stretta: «N.» non prende metà della giustezza.
            #expect((longLines.first!.origin.x - first.origin.x) < area.width / 3)
        }

        @Test("Un clic in una cella mette il cursore in quella cella, anche accanto a una riga di un'altra colonna o sotto il suo testo")
        func tableClick() throws {
            let long = "Una cella con un testo abbastanza lungo da andare a capo più di una volta nella sua colonna."
            let table = Table(id: "t", rows: [TableRow(cells: [cell(long), cell("uno")]), TableRow(cells: [cell("due"), cell("")])])
            let document = Document(blocks: [.table(table)])
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let string = text.string as NSString
            let one = try #require(layout.pages[0].lines.first { $0.paragraphLocation == string.range(of: "uno").location })
            let longLines = layout.pages[0].lines.filter { $0.paragraphLocation == 0 }
            let oneCell = try #require(one.cell)
            // A destra di «uno», alla sua altezza: nella cella di «uno», non alla fine della riga della prima colonna.
            let right = try #require(layout.position(at: CGPoint(x: oneCell.maxX - 2, y: one.origin.y), onPage: 0))
            #expect(right.index == string.range(of: "uno").location + 3)
            // Nella stessa cella, all'altezza dell'ultima riga del testo lungo: ancora «uno».
            let lastLong = try #require(longLines.last)
            let below = try #require(layout.position(at: CGPoint(x: oneCell.maxX - 2, y: lastLong.origin.y), onPage: 0))
            #expect(below.index == string.range(of: "uno").location + 3)
            // La cella vuota accanto a «due».
            let two = try #require(layout.pages[0].lines.first { $0.paragraphLocation == string.range(of: "due").location })
            let empty = try #require(layout.position(at: CGPoint(x: oneCell.midX, y: two.origin.y), onPage: 0))
            #expect(empty.index == string.range(of: "due").location + 4)
            // Quella cella vuota è l'ultimo paragrafo del documento: sta nella tabella, e non c'è un'altra riga dopo.
            #expect(layout.pages[0].lines.filter { $0.range.location == string.length }.count == 1)
            #expect(layout.pages[0].lines.last?.cell != nil)
            // Con un paragrafo dopo la tabella, il clic nella cella vuota resta nella cella (non va al paragrafo dopo).
            let followed = Document(blocks: [.table(table), .paragraph(paragraph("Dopo."))])
            let followedText = followed.attributedString().text
            let followedLayout = PageLayout.layout(followedText, setup: followed.pageSetup, options: followed.layoutOptions)
            let followedString = followedText.string as NSString
            let emptyCell = followedString.range(of: "due").location + 4
            let line = try #require(followedLayout.pages[0].lines.first { $0.paragraphLocation == emptyCell })
            let cellBox = try #require(line.cell)
            #expect(line.range.location == emptyCell)
            #expect(followedLayout.position(at: CGPoint(x: cellBox.midX, y: cellBox.midY), onPage: 0)?.index == emptyCell)
            #expect(followedLayout.caret(at: emptyCell).map { cellBox.contains(CGPoint(x: $0.rect.minX, y: $0.rect.midY)) } == true)
        }

        @Test("Inserisci › Tabella: 3 × 3 con una riga d'intestazione, dopo il paragrafo del cursore, che resta intero")
        func insertTable() throws {
            let sheet = StyleSheet.builtIn
            func blocks(_ text: NSAttributedString) -> [Block] { Document(attributedString: text).blocks }
            // A metà di un paragrafo, con un paragrafo dopo.
            let middle = NSMutableAttributedString(attributedString: Document(blocks: [.paragraph(paragraph("Prima.")), .paragraph(paragraph("Dopo."))]).attributedString().text)
            let first = try #require(TableEditing.insertTable(in: middle, after: 2, sheet: sheet))
            #expect(first == 7)
            #expect(middle.string == "Prima.\n" + String(repeating: "\n", count: 9) + "Dopo.")
            let parsed = blocks(middle)
            #expect(parsed.count == 3)
            guard case .table(let table) = parsed[1] else { Issue.record("niente tabella"); return }
            #expect(table.rows.count == 3 && table.columnCount == 3 && table.headerRows == 1)
            #expect(TableEditing.cell(at: first, in: middle) == CellMark(table: table.id, row: 0, column: 0, headerRows: 1))
            #expect(TableEditing.paragraphs(ofTableAt: first + 4, in: middle).count == 9)
            // Nella tabella non se ne inserisce un'altra.
            #expect(TableEditing.insertTable(in: middle, after: first + 1, sheet: sheet) == nil)
            // In fondo al testo, dopo un paragrafo senza a capo: lo si chiude, e dopo la tabella resta un paragrafo normale.
            let end = NSMutableAttributedString(attributedString: Document(blocks: [.paragraph(paragraph("Prima."))]).attributedString().text)
            let endFirst = try #require(TableEditing.insertTable(in: end, after: end.length, sheet: sheet))
            #expect(end.string == "Prima.\n" + String(repeating: "\n", count: 9))
            #expect(TableEditing.cell(at: endFirst, in: end) != nil)
            #expect(TableEditing.cell(at: end.length, in: end) == nil, "il paragrafo vuoto dopo la tabella non è una cella")
            #expect(blocks(end).count == 3)
            // In un documento vuoto.
            let empty = NSMutableAttributedString()
            #expect(TableEditing.insertTable(in: empty, after: 0, sheet: sheet) == 0)
            #expect(empty.length == 9)
            // Dopo il titolo di una sezione: le celle non sono titoli e hanno lo stile del testo.
            let titled = editable()
            let title = try #require(SectionEditing.titles(in: titled).first)
            TextStyling.restyle(titled, range: title.range, from: sheet, to: sheet) { $0.paragraph = "Heading 1" }
            let cellStart = try #require(TableEditing.insertTable(in: titled, after: title.range.location, sheet: sheet))
            #expect(titled.attribute(.sectionTitle, at: cellStart, effectiveRange: nil) == nil)
            #expect(SectionEditing.titles(in: titled).count == SectionEditing.titles(in: editable()).count)
            #expect(titled.attribute(.paragraphStyleName, at: title.range.location, effectiveRange: nil) as? String == "Heading 1")
            #expect(titled.attribute(.paragraphStyleName, at: cellStart, effectiveRange: nil) as? String == "Body")
        }

        /// «Prima.», una tabella 2 × 2 (a b / c d, una riga d'intestazione), «Dopo.»: Prima.\na\nb\nc\nd\nDopo.
        private func smallTable() -> NSMutableAttributedString {
            let table = Table(id: "t", rows: [TableRow(cells: [cell("a"), cell("b")]), TableRow(cells: [cell("c"), cell("d")])], headerRows: 1)
            return NSMutableAttributedString(attributedString: Document(blocks: [.paragraph(paragraph("Prima.")), .table(table), .paragraph(paragraph("Dopo."))]).attributedString().text)
        }

        @Test("Cancellare non unisce due celle né una cella al testo accanto; una tabella presa per intero si cancella tutta")
        func tableDeletion() throws {
            let text = smallTable()
            #expect(text.string == "Prima.\na\nb\nc\nd\nDopo.")
            // Indietro dall'inizio di «b», avanti dalla fine di «a», indietro dall'inizio di «Dopo.», avanti dalla fine di «Prima.»: niente.
            for range in [NSRange(location: 8, length: 1), NSRange(location: 14, length: 1), NSRange(location: 6, length: 1)] {
                #expect(TableEditing.deletablePieces(of: range, in: text).isEmpty)
            }
            // Da «ma.» di Prima a metà della tabella: si cancella il testo, gli a capo restano.
            #expect(TableEditing.deletablePieces(of: NSRange(location: 3, length: 8), in: text)
                    == [NSRange(location: 3, length: 3), NSRange(location: 7, length: 1), NSRange(location: 9, length: 1)])
            let partial = smallTable()
            TableEditing.delete(NSRange(location: 3, length: 8), in: partial)
            #expect(partial.string == "Pri\n\n\nc\nd\nDopo.")
            #expect(Document(attributedString: partial).blocks.count == 3, "la tabella resta, con due celle vuote")
            // Tutto il testo: la tabella va via con il resto.
            let all = smallTable()
            TableEditing.delete(NSRange(location: 0, length: all.length), in: all)
            #expect(all.length == 0)
            // La tabella intera e basta (da «a» all'a capo di «d»): resta Prima.\nDopo.
            let whole = smallTable()
            TableEditing.delete(NSRange(location: 7, length: 8), in: whole)
            #expect(whole.string == "Prima.\nDopo.")
            #expect(Document(attributedString: whole).blocks.count == 2)
        }

        @Test("Ciò che entra in una cella è della cella; una tabella incollata fuori ha un'identità nuova; la cella dopo e prima; una riga nuova")
        func tableInsertionAndRows() throws {
            let text = smallTable()
            // «x\ny» dentro «b»: due paragrafi della stessa cella.
            let fragment = NSAttributedString(string: "x\ny", attributes: text.attributes(at: 0, effectiveRange: nil))
            let at = TableEditing.replace(NSRange(location: 10, length: 0), in: text, with: fragment)
            #expect(at == 10 && text.string == "Prima.\na\nbx\ny\nc\nd\nDopo.")
            #expect(TableEditing.cell(at: 12, in: text)?.column == 1 && TableEditing.cell(at: 12, in: text)?.row == 0)
            // Scrivere su una selezione che attraversa due celle: la prima prende il testo, la seconda si svuota.
            let typed = smallTable()
            TableEditing.replace(NSRange(location: 7, length: 3), in: typed, with: NSAttributedString(string: "Z"))
            #expect(typed.string == "Prima.\nZ\n\nc\nd\nDopo.")
            // Una tabella incollata accanto a sé stessa: due tabelle.
            let copy = smallTable().attributedSubstring(from: NSRange(location: 7, length: 8))
            let doubled = smallTable()
            TableEditing.replace(NSRange(location: 15, length: 0), in: doubled, with: copy)
            #expect(Document(attributedString: doubled).blocks.filter { if case .table = $0 { true } else { false } }.count == 2)
            // La cella dopo e prima.
            let plain = smallTable()
            #expect(TableEditing.neighbourCell(of: 7, forward: true, in: plain).map { [$0.row, $0.column] } == [0, 1])
            #expect(TableEditing.neighbourCell(of: 11, forward: false, in: plain).map { [$0.row, $0.column] } == [0, 1])
            #expect(TableEditing.neighbourCell(of: 13, forward: true, in: plain) == nil)
            #expect(TableEditing.contentRange(of: CellMark(table: "t", row: 1, column: 0), in: plain, near: 7) == NSRange(location: 11, length: 1))
            // Una riga sotto la prima: le righe dopo scalano.
            let first = try #require(TableEditing.insertRow(below: 0, ofTableAt: 7, in: plain))
            #expect(first == 11 && plain.string == "Prima.\na\nb\n\n\nc\nd\nDopo.")
            #expect(TableEditing.cell(at: 15, in: plain)?.row == 2)
            guard case .table(let table) = Document(attributedString: plain).blocks[1] else { Issue.record("niente tabella"); return }
            #expect(table.rows.count == 3 && table.headerRows == 1)
            // In fondo al testo, con l'ultima cella vuota come paragrafo finale: la riga nuova finisce in fondo, nella tabella.
            let endTable = Table(id: "e", rows: [TableRow(cells: [cell("p"), cell("")])])
            let end = NSMutableAttributedString(attributedString: Document(blocks: [.table(endTable)]).attributedString().text)
            #expect(end.string == "p\n")
            let newRow = try #require(TableEditing.insertRow(below: 0, ofTableAt: 0, in: end))
            #expect(end.string == "p\n\n\n" && newRow == 3)
            #expect(TableEditing.cell(at: end.length, in: end).map { [$0.row, $0.column] } == [1, 1])
            guard case .table(let grown) = Document(attributedString: end).blocks.first else { Issue.record("niente tabella"); return }
            #expect(grown.rows.count == 2 && grown.columnCount == 2)
        }

        @Test("Righe e colonne: aggiungere sopra, sotto, a sinistra, a destra; togliere; togliere la tabella; righe d'intestazione")
        func tableRowsAndColumns() throws {
            func table(_ text: NSAttributedString) -> Table? {
                Document(attributedString: text).blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first
            }
            func words(_ text: NSAttributedString) -> [[String]] {
                (table(text)?.rows ?? []).map { $0.cells.map { $0.paragraphs.map { Document(blocks: [.paragraph($0)]).attributedString().text.string }.joined() } }
            }
            // Una riga sopra la prima (d'intestazione): è d'intestazione anche lei.
            var text = smallTable()
            #expect(TableEditing.insertRow(at: 0, ofTableAt: 7, in: text) == 7)
            #expect(words(text) == [["", ""], ["a", "b"], ["c", "d"]] && table(text)?.headerRows == 2)
            // Una colonna a sinistra e una a destra.
            text = smallTable()
            TableEditing.insertColumn(at: 0, ofTableAt: 7, in: text)
            #expect(words(text) == [["", "a", "b"], ["", "c", "d"]])
            TableEditing.insertColumn(at: 3, ofTableAt: 7, in: text)
            #expect(words(text) == [["", "a", "b", ""], ["", "c", "d", ""]])
            #expect(text.string.hasSuffix("d\n\nDopo."))
            // Togliere la prima riga, poi la seconda colonna.
            text = smallTable()
            TableEditing.removeRow(0, ofTableAt: 7, in: text)
            #expect(words(text) == [["c", "d"]] && table(text)?.headerRows == 0)
            TableEditing.removeColumn(1, ofTableAt: 7, in: text)
            #expect(words(text) == [["c"]] && text.string == "Prima.\nc\nDopo.")
            // L'ultima colonna rimasta: va via la tabella.
            TableEditing.removeColumn(0, ofTableAt: 7, in: text)
            #expect(text.string == "Prima.\nDopo." && table(text) == nil)
            // Togliere la tabella.
            text = smallTable()
            #expect(TableEditing.removeTable(at: 9, in: text) == 7 && text.string == "Prima.\nDopo.")
            // Righe d'intestazione: da 0 a tutte.
            text = smallTable()
            TableEditing.setHeaderRows(5, ofTableAt: 7, in: text)
            #expect(table(text)?.headerRows == 2)
            TableEditing.setHeaderRows(0, ofTableAt: 7, in: text)
            #expect(table(text)?.headerRows == 0)
            // In fondo al testo, con l'ultima cella vuota come paragrafo finale.
            func endTable() -> NSMutableAttributedString {
                NSMutableAttributedString(attributedString: Document(blocks: [.table(Table(id: "e", rows: [TableRow(cells: [cell("p"), cell("")])]))]).attributedString().text)
            }
            text = endTable()
            TableEditing.insertColumn(at: 2, ofTableAt: 0, in: text)
            #expect(words(text) == [["p", "", ""]] && text.string == "p\n\n")
            #expect(TableEditing.cell(at: text.length, in: text)?.column == 2)
            text = endTable()
            TableEditing.insertColumn(at: 1, ofTableAt: 0, in: text)
            #expect(words(text) == [["p", "", ""]] && TableEditing.cell(at: text.length, in: text)?.column == 2)
            text = endTable()
            TableEditing.removeColumn(1, ofTableAt: 0, in: text)
            #expect(words(text) == [["p"]] && TableEditing.cell(at: text.length, in: text) == nil, "il paragrafo in fondo torna normale")
            text = endTable()
            TableEditing.insertRow(at: 0, ofTableAt: 0, in: text)
            #expect(words(text) == [["", ""], ["p", ""]])
        }

        @Test("Una colonna vuota non si riduce ai margini: in una tabella appena fatta le colonne sono uguali")
        func emptyColumns() throws {
            let empty = Table(id: "v", rows: [TableRow(cells: [cell(""), cell(""), cell("")])])
            let filled = Table(id: "w", rows: [TableRow(cells: [cell("Nome"), cell("Valore"), cell("")])])
            for table in [empty, filled] {
                let document = Document(blocks: [.table(table), .paragraph(paragraph("Dopo."))])
                let text = document.attributedString().text
                let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
                let boxes = layout.pages[0].lines.compactMap(\.cell)
                let widths = boxes.map(\.width)
                #expect(widths.count == 3)
                let area = layout.pages[0].setup.textRect.width
                #expect(widths.allSatisfy { $0 > area / 6 }, "nessuna colonna stretta: \(widths)")
            }
        }

        @Test("L'aspetto delle tabelle nel file: stili di tabella, eccezioni della tabella e delle celle; si rileggono identici, anche passando dal testo dell'editor")
        func tableAppearanceFile() throws {
            let source = """
            <?xml version="1.0" encoding="UTF-8"?>
            <document version="1" font="HoeflerText-Regular" size="12">
            <table-styles>
            <table-style name="Griglia" rules="grid"/>
            <table-style name="Elegante" rules="three-rules" rule-width="0.75" padding="3 6 3 6" valign="middle" background="#f2f2f2"/>
            </table-styles>
            <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
            <table id="t1" header-rows="1" style="Elegante" padding="2" background="">
            <row>
            <cell top="1.5" left="none" background="#ffeecc" valign="bottom" padding="1 2 3 4"><p>a</p></cell>
            <cell><p>b</p></cell>
            </row>
            </table>
            </document>
            """
            let document = try DocumentFormat.document(from: source)
            #expect(document.tableStyles.count == 2 && document.tableStyles[1].values.rules == .threeRules)
            guard case .table(let table) = document.blocks.first else { Issue.record("niente tabella"); return }
            #expect(table.styleName == "Elegante" && table.values == TableValues(padding: CellInsets(all: 2), background: ""))
            #expect(table.rows[0].cells[0].values == CellValues(top: .rule(1.5), left: CellBorder.none, background: "#ffeecc", verticalAlignment: .bottom,
                                                                padding: CellInsets(top: 1, right: 2, bottom: 3, left: 4)))
            #expect(table.rows[0].cells[1].values.isEmpty)
            #expect(DocumentFormat.string(for: document) == source + "\n")
            // Dal testo dell'editor e ritorno.
            let back = Document(attributedString: document.attributedString().text, settings: document.settingsOnly)
            #expect(back.blocks == document.blocks)
            // L'aspetto risolto: eccezioni della tabella sopra lo stile, sopra i valori di partenza.
            let resolved = TableStyle.resolved(styleName: table.styleName, values: table.values, in: document.tableStyles)
            #expect(resolved == TableValues(rules: .threeRules, ruleWidth: 0.75, padding: CellInsets(all: 2), verticalAlignment: .middle, background: ""))
            #expect(TableStyle.resolved(styleName: nil, values: TableValues(), in: TableStyle.builtIn) == .initial)
            // Un documento senza <table-styles> ha quelli con cui nasce ogni documento, e non li scrive.
            let plain = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><p>a</p></document>")
            #expect(plain.tableStyles == TableStyle.builtIn && !DocumentFormat.string(for: plain).contains("table-styles"))
            // Errori: uno stile che non c'è, valori sbagliati.
            for (bad, attribute) in [("<table style=\"Nessuno\">", "style"), ("<table rules=\"tutte\">", "rules"), ("<table padding=\"1 2\">", "padding"),
                                     ("<table background=\"rosso\">", "background"), ("<table valign=\"alto\">", "valign")] {
                let text = "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\(bad)<row><cell/></row></table></document>"
                #expect(throws: DocumentFormatError.self, "\(attribute)") { try DocumentFormat.document(from: text) }
            }
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><table><row><cell top=\"spesso\"/></row></table></document>")
            }
            // Una tabella con uno stile che il documento non ha più si scrive senza (il file si riapre).
            var orphan = document
            orphan.tableStyles = TableStyle.builtIn
            let written = DocumentFormat.string(for: orphan)
            #expect(!written.contains("style=\"Elegante\""))
            #expect((try? DocumentFormat.document(from: written)) != nil)
            // Una riga o una colonna nuova ha lo stile e l'aspetto della tabella, non quello proprio delle celle vicine.
            let text = NSMutableAttributedString(attributedString: document.attributedString().text)
            TableEditing.insertRow(at: 1, ofTableAt: 0, in: text)
            TableEditing.insertColumn(at: 0, ofTableAt: 0, in: text)
            guard case .table(let grown) = Document(attributedString: text, settings: document.settingsOnly).blocks.first else { Issue.record("niente tabella"); return }
            #expect(grown.styleName == "Elegante" && grown.values == table.values)
            #expect(grown.rows[1].cells[1].values.isEmpty && grown.rows[0].cells[0].values.isEmpty)
            #expect(grown.rows[0].cells[1].values == table.rows[0].cells[0].values)
        }

        @Test("L'aspetto nella pagina: schemi di filetti, lati delle celle, fondi, margini interni, allineamento verticale")
        func tableAppearanceLayout() throws {
            func layout(_ table: Table) -> LaidOutPage {
                let document = Document(blocks: [.table(table), .paragraph(paragraph("Dopo."))])
                let text = document.attributedString().text
                return PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions).pages[0]
            }
            func grid(_ rows: Int, _ columns: Int, headerRows: Int = 0, style: String? = nil, values: TableValues = TableValues()) -> Table {
                Table(id: "a", rows: (0..<rows).map { r in TableRow(cells: (0..<columns).map { c in cell("r\(r)c\(c)") }) },
                      headerRows: headerRows, styleName: style, values: values)
            }
            func horizontal(_ page: LaidOutPage) -> [CGRect] { page.rules.filter { $0.width > $0.height } }
            func vertical(_ page: LaidOutPage) -> [CGRect] { page.rules.filter { $0.height > $0.width } }
            // Griglia: 4 linee orizzontali (sopra, tra le righe, sotto) per 2 colonne, 3 verticali per 3 righe.
            var page = layout(grid(3, 2))
            #expect(horizontal(page).count == 8 && vertical(page).count == 9)
            // Tre filetti: sopra, sotto l'intestazione, in fondo; nessun verticale; lo spessore dello stile.
            page = layout(grid(3, 2, headerRows: 1, style: "Three Rules"))
            #expect(vertical(page).isEmpty)
            #expect(Set(horizontal(page).map { ($0.midY * 100).rounded() }).count == 3)
            #expect(horizontal(page).allSatisfy { abs($0.height - 0.75) < 0.01 })
            // Solo il bordo, nessun filetto.
            page = layout(grid(3, 2, style: "Frame"))
            #expect(horizontal(page).count == 4 && vertical(page).count == 6)
            #expect(layout(grid(3, 2, style: "No Rules")).rules.isEmpty)
            // Un lato detto vince sullo schema: in griglia, niente filetto tra le due celle della prima riga.
            var sides = grid(2, 2)
            sides.rows[0].cells[0].values.right = CellBorder.none
            page = layout(sides)
            #expect(vertical(page).count == 5)
            // Senza filetti, un lato di 2 punti sopra una cella.
            var thick = grid(2, 2, style: "No Rules")
            thick.rows[1].cells[1].values.top = .rule(2)
            page = layout(thick)
            #expect(page.rules.count == 1 && abs(page.rules[0].height - 2) < 0.01)
            // Fondi: della tabella per tutte le celle, tranne quella che dice «senza fondo»; uno proprio.
            var colored = grid(2, 2, values: TableValues(background: "#eeeeee"))
            colored.rows[0].cells[1].values.background = ""
            colored.rows[1].cells[1].values.background = "#ff0000"
            page = layout(colored)
            #expect(page.fills.count == 3)
            let red = try #require(page.fills.first { $0.color.components?.first ?? 0 > 0.99 && ($0.color.components?[1] ?? 1) < 0.01 })
            let redCell = try #require(page.lines.first { $0.cell != nil && $0.cell!.intersects(red.rect.insetBy(dx: 1, dy: 1)) }?.cell)
            #expect(redCell == red.rect)
            // Margini interni: 10 punti dalla tabella; la cella con i suoi.
            var padded = grid(1, 2, values: TableValues(padding: CellInsets(all: 10)))
            padded.rows[0].cells[1].values.padding = CellInsets(top: 0, right: 0, bottom: 0, left: 20)
            page = layout(padded)
            let firstLine = try #require(page.lines.first { $0.cell != nil })
            #expect(abs(firstLine.origin.x - firstLine.cell!.minX - 10.25) < 0.01)
            let secondLine = try #require(page.lines.filter { $0.cell != nil }.dropFirst().first)
            #expect(abs(secondLine.origin.x - secondLine.cell!.minX - 20.25) < 0.01)
            // Allineamento: accanto a una cella di tre righe, «basso» mette la riga più in basso di «alto».
            let tall = TableCell(paragraphs: [paragraph("uno"), paragraph("due"), paragraph("tre")])
            func shortLine(_ alignment: CellVerticalAlignment) throws -> CGFloat {
                var table = Table(id: "v", rows: [TableRow(cells: [tall, cell("corta")])])
                table.rows[0].cells[1].values.verticalAlignment = alignment
                let page = layout(table)
                return try #require(page.lines.first { $0.cell != nil && $0.cell!.minX > page.lines.compactMap(\.cell).map(\.minX).min()! }).origin.y
            }
            let top = try shortLine(.top), middle = try shortLine(.middle), bottom = try shortLine(.bottom)
            #expect(top > middle && middle > bottom)
        }

        /// Uno stile di flottante «Tabella» (didascalia sopra, numerata con «Tabelle»), con le posizioni date.
        private func floatingDocument(_ blocks: [Block], positions: [FloatStyle.FigurePosition] = [.here, .top, .bottom, .page]) -> Document {
            var document = Document(lists: [ListDefinition(name: "Tables", counter: .decimal, prefix: "Tabella ", suffix: ".", continues: true)], blocks: blocks)
            document.floatStyles.append(FloatStyle(name: "Table", placement: .figure, listName: "Tables", reference: .none, showsRule: false,
                                                   positions: positions, caption: .above))
            return document
        }

        @Test("Una tabella flottante: nel file con la didascalia; composta con il numero della sua Lista davanti; collocata come una figura")
        func floatingTable() throws {
            func table(_ id: String, caption: String, rows: Int = 2) -> Table {
                Table(id: id, rows: (0..<rows).map { r in TableRow(cells: [cell("a\(r)"), cell("b\(r)")]) }, floatStyle: "Table", caption: [paragraph(caption)])
            }
            // Il file.
            let document = floatingDocument([.paragraph(paragraph("Prima.")), .table(table("t1", caption: "Popolazione")), .paragraph(paragraph("Dopo."))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<table id=\"t1\" float=\"Table\">\n<caption><p>Popolazione</p></caption>"))
            let read = try DocumentFormat.document(from: written)
            #expect(read.blocks == document.blocks)
            #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly).blocks == document.blocks)
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><table float=\"Nessuno\"><row><cell/></row></table></document>")
            }
            // Due tabelle: «Tabella 1. Popolazione» sopra la prima, «Tabella 2. Area» sopra la seconda.
            let two = floatingDocument([.table(table("t1", caption: "Popolazione")), .paragraph(paragraph("In mezzo.")), .table(table("t2", caption: "Area"))])
            let text = two.attributedString().text
            let layout = PageLayout.layout(text, setup: two.pageSetup, options: two.layoutOptions)
            let string = text.string as NSString
            for (caption, label) in [("Popolazione", "Tabella 1. "), ("Area", "Tabella 2. ")] {
                let location = string.range(of: caption).location
                let line = try #require(layout.pages[0].lines.first { $0.paragraphLocation == location })
                // Il numero, la didascalia e l'a capo.
                #expect(CTLineGetGlyphCount(line.line) == (label + caption).count + 1)
                let firstRow = try #require(layout.pages[0].lines.first { $0.paragraphLocation == location + caption.count + 1 })
                #expect(line.origin.y > firstRow.origin.y, "la didascalia sta sopra")
            }
            // Solo «in cima»: a metà pagina la tabella va in cima alla pagina dopo; il testo che segue resta qui, e il cursore
            // vi si trova.
            var filler: [Block] = (0..<25).map { _ in .paragraph(paragraph("Un paragrafo che riempie una parte della pagina, con un po' di testo.")) }
            filler.append(.table(table("t3", caption: "Solo in cima")))
            filler.append(.paragraph(paragraph("Subito dopo.")))
            let topOnly = floatingDocument(filler, positions: [.top])
            let topText = topOnly.attributedString().text
            let topLayout = PageLayout.layout(topText, setup: topOnly.pageSetup, options: topOnly.layoutOptions)
            let topString = topText.string as NSString
            let captionAt = topString.range(of: "Solo in cima").location, afterAt = topString.range(of: "Subito dopo.").location
            #expect(topLayout.pages.count >= 2)
            #expect(topLayout.pages[1].lines.contains { $0.paragraphLocation == captionAt })
            #expect(topLayout.pages[0].lines.contains { $0.paragraphLocation == afterAt })
            #expect(topLayout.caret(at: afterAt + 3)?.page == 0)
            #expect(topLayout.caret(at: captionAt + 3)?.page == 1)
            // Più alta di una pagina: resta nel testo e si spezza tra le righe.
            let tall = floatingDocument([.table(table("t4", caption: "Lunga", rows: 80))])
            let tallLayout = PageLayout.layout(tall.attributedString().text, setup: tall.pageSetup, options: tall.layoutOptions)
            #expect(tallLayout.pages.count >= 2)
            // Il comando: diventare flottante dà una didascalia vuota; smettere la toglie.
            let editable = NSMutableAttributedString(attributedString: Document(blocks: [.table(Table(id: "e", rows: [TableRow(cells: [cell("x")])]))]).attributedString().text)
            let captionStart = try #require(TableEditing.setFloat("Table", ofTableAt: 0, in: editable))
            #expect(captionStart == 0 && TableEditing.cell(at: 0, in: editable)?.isCaption == true && editable.string == "\nx")
            guard case .table(let floated) = Document(attributedString: editable).blocks.first else { Issue.record("niente tabella"); return }
            #expect(floated.floatStyle == "Table" && floated.caption.count == 1 && floated.rows.count == 1)
            TableEditing.setFloat(nil, ofTableAt: 1, in: editable)
            #expect(editable.string == "x")
            guard case .table(let plain) = Document(attributedString: editable).blocks.first else { Issue.record("niente tabella"); return }
            #expect(plain.floatStyle == nil && plain.caption.isEmpty)
        }

        @Test("Celle unite: nel file con colspan e rowspan, nella pagina su più colonne e righe senza filetti dentro; unire, dividere, righe e colonne che le attraversano")
        func mergedCells() throws {
            let source = """
            <?xml version="1.0" encoding="UTF-8"?>
            <document version="1" font="HoeflerText-Regular" size="12">
            <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
            <table id="m">
            <row>
            <cell colspan="2"><p>Titolo</p></cell>
            <cell rowspan="2"><p>Alta</p></cell>
            </row>
            <row>
            <cell><p>a</p></cell>
            <cell><p>b</p></cell>
            </row>
            </table>
            <p>Dopo.</p>
            </document>
            """
            let document = try DocumentFormat.document(from: source)
            guard case .table(let table) = document.blocks.first else { Issue.record("niente tabella"); return }
            #expect(table.rows[0].cells.map(\.isCovered) == [false, true, false] && table.rows[1].cells.map(\.isCovered) == [false, false, true])
            #expect(table.rows[0].cells[0].columnSpan == 2 && table.rows[0].cells[2].rowSpan == 2)
            #expect(DocumentFormat.string(for: document) == source + "\n")
            #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly).blocks == document.blocks)
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><table><row><cell/><cell rowspan=\"2\"/></row><row><cell colspan=\"2\"/></row></table></document>")
            }
            // Nella pagina: «Titolo» largo come «a» e «b», «Alta» alta come le due righe; nessun filetto dentro.
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            let page = layout.pages[0]
            let string = text.string as NSString
            func box(_ word: String) throws -> CGRect {
                let location = string.range(of: "\n" + word + "\n").location
                return try #require(page.lines.first { $0.paragraphLocation == (location == NSNotFound ? 0 : location + 1) }?.cell)
            }
            let titolo = try box("Titolo"), alta = try box("Alta"), a = try box("a"), b = try box("b")
            #expect(abs(titolo.width - (a.width + b.width)) < 0.01 && abs(titolo.minX - a.minX) < 0.01)
            #expect(abs(alta.maxY - titolo.maxY) < 0.01 && abs(alta.minY - a.minY) < 0.01)
            #expect(!page.rules.contains { $0.intersects(titolo.insetBy(dx: 2, dy: 2)) } && !page.rules.contains { $0.intersects(alta.insetBy(dx: 2, dy: 2)) })
            // Unire «a» e «b» di una 2 × 2: una cella con due paragrafi, che copre due colonne; dividerla la riporta a due celle.
            let merged = smallTable()
            let marks = [try #require(TableEditing.cell(at: 7, in: merged)), try #require(TableEditing.cell(at: 9, in: merged))]
            #expect(TableEditing.mergeCells(touching: marks, ofTableAt: 7, in: merged) == 7)
            guard case .table(let joined) = Document(attributedString: merged).blocks[1] else { Issue.record("niente tabella"); return }
            #expect(joined.rows[0].cells[0].columnSpan == 2 && joined.rows[0].cells[0].paragraphs.count == 2 && joined.rows[0].cells[1].isCovered)
            #expect(merged.string == "Prima.\na\nb\nc\nd\nDopo.")
            TableEditing.splitCell(row: 0, column: 0, ofTableAt: 7, in: merged)
            guard case .table(let split) = Document(attributedString: merged).blocks[1] else { Issue.record("niente tabella"); return }
            #expect(split.rows[0].cells.map(\.isCovered) == [false, false] && split.rows[0].cells[0].paragraphs.count == 2)
            #expect(merged.string == "Prima.\na\nb\n\nc\nd\nDopo.")
            // Una riga nuova che attraversa «Alta» la allunga; una colonna nuova che attraversa «Titolo» lo allarga.
            func grid(_ text: NSAttributedString) -> Table? { Document(attributedString: text, settings: document.settingsOnly).blocks.lazy.compactMap { if case .table(let t) = $0 { t } else { nil } }.first }
            let editable = NSMutableAttributedString(attributedString: text)
            TableEditing.insertRow(at: 1, ofTableAt: 0, in: editable)
            #expect(grid(editable)?.rows.count == 3 && grid(editable)?.rows[0].cells[2].rowSpan == 3 && grid(editable)?.rows[1].cells.map(\.isCovered) == [false, false, true])
            TableEditing.insertColumn(at: 1, ofTableAt: 0, in: editable)
            #expect(grid(editable)?.rows[0].cells[0].columnSpan == 3 && grid(editable)?.rows[1].cells.count == 4 && grid(editable)?.rows[1].cells[1].isCovered == false)
            // Togliere la prima riga: «Alta», che vi comincia, si divide prima.
            let removing = NSMutableAttributedString(attributedString: text)
            TableEditing.removeRow(0, ofTableAt: 0, in: removing)
            #expect(grid(removing)?.rows.count == 1 && grid(removing)?.rows[0].cells.map(\.isCovered) == [false, false, false])
        }

        @Test("Sulla virgola: nel file e nel testo dell'editor; in una colonna i segni decimali (della lingua) uno sotto l'altro; fuori dalle tabelle al centro della riga")
        func decimalAlignment() throws {
            func decimal(_ text: String) -> Paragraph {
                var result = paragraph(text)
                result.style.alignment = .decimal
                return result
            }
            func decimalCell(_ text: String) -> TableCell { TableCell(paragraphs: [decimal(text)]) }
            // Il file e il testo dell'editor.
            let simple = Document(blocks: [.paragraph(decimal("3,14"))])
            let written = DocumentFormat.string(for: simple)
            #expect(written.contains("align=\"decimal\""))
            #expect(try DocumentFormat.document(from: written).blocks == simple.blocks)
            #expect(Document(attributedString: simple.attributedString().text).blocks == simple.blocks)
            // In una colonna: la virgola per l'italiano, il punto per l'inglese; un intero si allinea sulla sua fine.
            for (language, values) in [("it", ["3,14", "12,5", "100", "0,125"]), ("en", ["3.14", "12.5", "100", "0.125"])] {
                var document = Document(language: language, blocks: [.table(Table(id: "d", rows: values.map { TableRow(cells: [cell("x"), decimalCell($0)]) })),
                                                                     .paragraph(paragraph("Dopo."))])
                document.hyphenates = false
                let text = document.attributedString().text
                let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
                let string = text.string as NSString
                var positions: [CGFloat] = []
                for value in values {
                    let location = string.range(of: "\n" + value + "\n").location + 1
                    let line = try #require(layout.pages[0].lines.first { $0.paragraphLocation == location })
                    let separator = (value as NSString).range(of: language == "it" ? "," : ".")
                    let index = separator.location == NSNotFound ? (value as NSString).length : separator.location
                    positions.append(line.origin.x + CTLineGetOffsetForStringIndex(line.line, index, nil))
                }
                #expect(positions.allSatisfy { abs($0 - positions[0]) < 0.01 }, "\(language): \(positions)")
            }
            // Fuori dalle tabelle: il segno al centro della riga.
            let alone = Document(language: "it", blocks: [.paragraph(decimal("1234,5"))])
            let aloneLayout = PageLayout.layout(alone.attributedString().text, setup: alone.pageSetup, options: alone.layoutOptions)
            let line = try #require(aloneLayout.pages[0].lines.first)
            let center = aloneLayout.pages[0].setup.textRect.midX
            #expect(abs(line.origin.x + CTLineGetOffsetForStringIndex(line.line, 4, nil) - center) < 0.01)
        }

        @Test("Una tabella lunga si spezza tra le righe e ripete l'intestazione in cima alla pagina nuova")
        func longTable() throws {
            var rows = [TableRow(cells: [cell("Voce"), cell("Descrizione")])]
            for index in 1...80 { rows.append(TableRow(cells: [cell("\(index)"), cell("La descrizione della voce \(index).")])) }
            let document = Document(blocks: [.table(Table(id: "t", rows: rows, headerRows: 1))])
            let text = document.attributedString().text
            let layout = PageLayout.layout(text, setup: document.pageSetup, options: document.layoutOptions)
            #expect(layout.pages.count >= 2)
            let header = (text.string as NSString).range(of: "Voce").location
            for page in layout.pages.prefix(2) {
                let top = try #require(page.lines.max { $0.origin.y < $1.origin.y })
                #expect(top.paragraphLocation == header, "in cima a ogni pagina, l'intestazione")
            }
            // Nessuna riga spezzata: ogni voce ha le sue due celle sulla stessa pagina.
            for index in [20, 40, 60] {
                let number = TextStyling.bodyParagraph(in: text, at: (text.string as NSString).range(of: "\n\(index)\n").location + 1).range.location
                let descr = (text.string as NSString).range(of: "voce \(index).").location
                let pageOf = { (location: Int) in layout.pages.firstIndex { $0.lines.contains { NSLocationInRange(location, $0.range) || $0.paragraphLocation == location } } }
                #expect(pageOf(number) == pageOf(TextStyling.bodyParagraph(in: text, at: descr).range.location))
            }
        }

        @Test("Ripulire i segni: un segno ripetuto su un paragrafo del corpo sparisce")
        func normalizeDuplicates() {
            let text = editable()
            let mark = text.attribute(.sectionTitle, at: location(of: "Capitolo primo", in: text), effectiveRange: nil)!
            let body = (text.string as NSString).range(of: "Testo del capitolo.")
            text.addAttribute(.sectionTitle, value: mark, range: body)
            SectionEditing.normalize(text)
            #expect(text.attribute(.sectionTitle, at: body.location, effectiveRange: nil) == nil)
            #expect(tree(text).sections == book().sections)
        }

        // MARK: La fine della sezione: il testo che torna alla sezione esterna (tappa 1)

        private let returning = """
        <document version="1" font="HoeflerText-Regular" size="12">
        <p>Premessa.</p>
        <section id="c" role="chapter">
        <title><p>Capitolo</p></title>
        <p>Primo.</p>
        <section id="s" role="section">
        <title><p>Sotto</p></title>
        <p>Testo di sotto.</p>
        </section>
        <p>Secondo.</p>
        <p>Terzo.</p>
        <section id="t" role="section">
        <title><p>Sotto due</p></title>
        <section id="u" role="section">
        <title><p>Sotto sotto</p></title>
        <p>Profondo.</p>
        </section>
        <p>Di nuovo in sotto due.</p>
        </section>
        <table><row><cell><p>Cella che torna al capitolo.</p></cell></row></table>
        </section>
        <p>Postfazione.</p>
        </document>
        """

        private func texts(_ blocks: [Block]) -> [String] {
            blocks.map {
                switch $0 {
                case .paragraph(let paragraph): paragraph.plainText
                case .table: "tabella"
                }
            }
        }

        @Test("Il testo dopo una sezione interna torna a quella esterna: nel modello sta in `afterward`")
        func returnsInModel() throws {
            let document = try DocumentFormat.document(from: returning)
            let chapter = try #require(document.sections.first)
            #expect(texts(chapter.blocks) == ["Primo."])
            #expect(chapter.sections.map(\.id) == ["s", "t"])
            #expect(texts(chapter.sections[0].afterward) == ["Secondo.", "Terzo."])
            #expect(texts(chapter.sections[1].sections[0].afterward) == ["Di nuovo in sotto due."])
            #expect(texts(chapter.sections[1].afterward) == ["tabella"], "anche una tabella torna")
            #expect(texts(chapter.afterward) == ["Postfazione."], "al primo livello: fuori da ogni sezione")
            #expect(texts(document.blocks) == ["Premessa."])
        }

        @Test("Il ritorno nel file e nel testo dell'editor: file → modello → testo → modello → file identici")
        func returnsRoundTrip() throws {
            let document = try DocumentFormat.document(from: returning)
            let written = DocumentFormat.string(for: document)
            let reread = try DocumentFormat.document(from: written)
            #expect(reread.blocks == document.blocks && reread.sections == document.sections)
            #expect(DocumentFormat.string(for: reread) == written)

            let (text, _) = document.attributedString()
            func mark(_ word: String) -> String? {
                let at = (text.string as NSString).range(of: word).location
                return text.attribute(.sectionReturn, at: at, effectiveRange: nil) as? String
            }
            #expect(mark("Secondo.") == "c" && mark("Terzo.") == nil, "solo il primo paragrafo che torna porta il segno")
            #expect(mark("Di nuovo") == "t" && mark("Cella che torna") == "c" && mark("Postfazione.") == "")
            #expect(mark("Primo.") == nil && mark("Profondo.") == nil)
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(back.blocks == document.blocks && back.sections == document.sections)
            #expect(DocumentFormat.string(for: back) == written)
        }

        @Test("Un ultimo paragrafo vuoto che torna, e un ritorno senza senso, che non conta")
        func returnEdgeCases() throws {
            var document = Document(blocks: [])
            document.sections = [Section(id: "a", role: Section.Role.chapter, title: paragraph("A"),
                                         sections: [Section(id: "b", title: paragraph("B"), blocks: [.paragraph(paragraph("b"))],
                                                            afterward: [.paragraph(paragraph(""))])])]
            let (text, _) = document.attributedString()
            let back = Document(attributedString: text, settings: document.settingsOnly)
            #expect(back.sections == document.sections, "l'ultimo paragrafo vuoto torna ad A")

            // Un ritorno a una sezione che non contiene il paragrafo, o senza sezioni interne da chiudere: ignorato.
            var flat = document.flatParagraphs
            flat[flat.count - 1].sectionReturn = "nessuna"
            var ignored = document
            ignored.setFlatParagraphs(flat)
            #expect(ignored.sections.first?.sections.first?.blocks.count == 2 && ignored.sections.first?.sections.first?.afterward == [])
            // «b» che torna ad A: B si chiude subito dopo il titolo, e «b» con il vuoto vanno dopo di lei.
            flat[2].sectionReturn = "a"
            flat[flat.count - 1].sectionReturn = nil
            ignored.setFlatParagraphs(flat)
            #expect(ignored.sections.first?.sections.first?.afterward.count == 2, "torna ad A: «b» e il vuoto vanno dopo B")
        }

        @Test("La lettura è severa sulla struttura delle sezioni")
        func strict() {
            func fails(_ content: String) -> Bool {
                (try? DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\(content)</document>")) == nil
            }
            #expect(fails("<section><p>senza titolo</p></section>"))
            #expect(fails("<section></section>"), "manca il titolo")
            #expect(fails("<section><title/><title/></section>"), "due titoli")
            #expect(fails("<section><title><p>a</p><p>b</p></title></section>"), "il titolo è un solo paragrafo")
            #expect(fails("<section id=\"a\"><title/></section><section id=\"a\"><title/></section>"), "due sezioni con la stessa identità")
            #expect(fails("<section role=\"\"><title/></section>") && fails("<section colore=\"blu\"><title/></section>"))
            #expect(fails("<p><section><title/></section></p>") && fails("<title/>"))
        }
    }
}
