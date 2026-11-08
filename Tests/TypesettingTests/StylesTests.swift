import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Stili con un nome")
    struct StylesTests {
        private let sheet = StyleSheet.builtIn
        private let helvetica = CharacterStyle(fontName: "Helvetica", size: 9)

        // MARK: Facce

        @Test("Corsivo e nero ritrovano la faccia giusta in ogni famiglia; dove manca, il testo resta com'è")
        func faces() {
            #expect(FontFaces.face(family: "Hoefler Text", italic: true, bold: false) == "HoeflerText-Italic")
            #expect(FontFaces.face(family: "Hoefler Text", italic: false, bold: true) == "HoeflerText-Black")
            #expect(FontFaces.face(family: "Hoefler Text", italic: true, bold: true) == "HoeflerText-BlackItalic")
            #expect(FontFaces.face(family: "Hoefler Text", italic: false, bold: false) == "HoeflerText-Regular", "non la faccia Ornaments")
            // Baskerville ha un semigrassetto (peso 8) e un grassetto (peso 9): «nero» è il grassetto.
            #expect(FontFaces.face(family: "Baskerville", italic: false, bold: true) == "Baskerville-Bold")
            #expect(FontFaces.face(family: "Vulcanius", italic: true, bold: false) == nil)

            var enfasi = StyleValues()
            enfasi.italic = true
            #expect(enfasi.applied(to: CharacterStyle(fontName: "Baskerville", size: 12)).fontName == "Baskerville-Italic")
            #expect(enfasi.applied(to: CharacterStyle(fontName: "TimesNewRomanPS-BoldMT", size: 12)).fontName == "TimesNewRomanPS-BoldItalicMT", "il nero resta")
            let gothic = CharacterStyle(fontName: "Vulcanius", size: 20, features: [.aat(type: 17, selector: 3)])
            #expect(enfasi.applied(to: gothic) == gothic, "senza corsivo nulla cambia, nemmeno le funzioni")
        }

        // MARK: Eredità

        @Test("I valori passano dal paragrafo alla parola al carattere, e il più vicino vince")
        func cascade() {
            let run = sheet.resolveCharacter(paragraphStyle: "Heading 1", wordStyle: "Latin", characterStyle: "Emphasis", base: helvetica)
            // Titolo 1 (basato su Testo): Hoefler Text, nero, corpo 18; Latino: lingua latina; Enfasi: corsivo.
            #expect(run.fontName == "HoeflerText-BlackItalic")
            #expect(run.size == 18)
            #expect(run.language == "la")
            #expect(sheet.resolveCharacter(paragraphStyle: "Body", wordStyle: nil, characterStyle: nil, base: helvetica)
                    == CharacterStyle(fontName: "HoeflerText-Regular", size: 12))
            // Senza stili resta la base.
            #expect(sheet.resolveCharacter(paragraphStyle: nil, wordStyle: nil, characterStyle: nil, base: helvetica) == helvetica)

            let quote = sheet.resolveParagraph(styleName: "Quotation")
            #expect(quote.alignment == .justified, "ereditato da Testo")
            #expect(quote.leftIndent == 24 && quote.rightIndent == 24 && quote.spaceBefore == 6)

            // Il più vicino vince: un corpo nello stile di carattere batte quello del paragrafo.
            var big = StyleValues()
            big.size = 30
            big.alignment = .center  // uno stile di carattere non può fissare l'allineamento: viene ignorato
            var custom = sheet
            custom.styles.append(NamedStyle(name: "Grande", target: .character, values: big))
            #expect(custom.resolveCharacter(paragraphStyle: "Heading 1", wordStyle: nil, characterStyle: "Grande", base: helvetica).size == 30)
            #expect(custom.values(of: "Grande").alignment == nil)
        }

        @Test("Una catena di stili che torna su se stessa non blocca il calcolo")
        func cycle() {
            var a = StyleValues(); a.size = 10
            var b = StyleValues(); b.leftIndent = 5
            let loop = StyleSheet(styles: [NamedStyle(name: "A", target: .paragraph, basedOn: "B", values: a),
                                           NamedStyle(name: "B", target: .paragraph, basedOn: "A", values: b)])
            let values = loop.values(of: "A")
            #expect(values.size == 10 && values.leftIndent == 5)
        }

        // MARK: File

        private func run(_ text: String, paragraph: String, word: String? = nil, character: String? = nil, size: Double? = nil, hyphenates: Bool = true) -> Inline {
            var style = sheet.resolveCharacter(paragraphStyle: paragraph, wordStyle: word, characterStyle: character, base: helvetica)
            if let size { style.size = size }
            style.hyphenates = hyphenates
            return .text(TextRun(text, style: style, wordStyleName: word, characterStyleName: character))
        }

        private func sample() -> Document {
            var indented = sheet.resolveParagraph(styleName: "Body")
            indented.firstLineIndent = 12
            return Document(styles: sheet, lists: ListDefinition.builtIn, blocks: [
                .paragraph(Paragraph(styleName: "Heading 1", style: sheet.resolveParagraph(styleName: "Heading 1"), inlines: [run("Introduzione", paragraph: "Heading 1")])),
                .paragraph(Paragraph(styleName: "Body", style: indented, inlines: [
                    run("Un testo con ", paragraph: "Body"), run("enfasi", paragraph: "Body", character: "Emphasis"),
                    run(", una citazione ", paragraph: "Body"), run("veni vidi vici", paragraph: "Body", word: "Latin"),
                    run(" e una parola più grande", paragraph: "Body", size: 14), run(" indivisibile", paragraph: "Body", hyphenates: false),
                ])),
                .paragraph(Paragraph(styleName: "Quotation", style: sheet.resolveParagraph(styleName: "Quotation"), inlines: [run("Una citazione.", paragraph: "Quotation")])),
            ])
        }

        @Test("Nel file: la sezione degli stili, poi paragrafi e tratti che nominano il loro stile e scrivono solo le differenze")
        func file() throws {
            let written = DocumentFormat.string(for: sample())
            #expect(written.contains("""
            <styles>
            <style name="Body" target="paragraph" family="Hoefler Text" size="12" align="justified"/>
            <style name="Heading 1" target="paragraph" based-on="Body" bold="on" size="18" align="natural" space-before="18" space-after="6" opens-section="chapter" outline-level="1"/>
            """))
            #expect(written.contains("<style name=\"Latin\" target=\"word\" lang=\"la\"/>"))
            #expect(written.contains("<style name=\"Emphasis\" target=\"character\" italic=\"on\"/>"))
            #expect(written.contains("<p style=\"Heading 1\">Introduzione</p>"))
            #expect(written.contains("<p style=\"Body\" first-indent=\"12\">Un testo con <t char-style=\"Emphasis\">enfasi</t>, una citazione <t word-style=\"Latin\">veni vidi vici</t><t size=\"14\"> e una parola più grande</t><t hyphenation=\"off\"> indivisibile</t></p>"))
            #expect(written.contains("<p style=\"Quotation\">Una citazione.</p>"))
            #expect(try DocumentFormat.document(from: written) == sample())
        }

        @Test("Il livello di paragrafazione si salva sullo stile e sul paragrafo; zero toglie quello ereditato")
        func outlineLevelInFile() throws {
            let document = try DocumentFormat.document(from: """
            <document version="18" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Testo" target="paragraph"/>
            <style name="Titolo 1" target="paragraph" based-on="Testo" outline-level="1"/>
            <style name="Senza livello" target="paragraph" based-on="Titolo 1" outline-level="0"/>
            </styles>
            <p style="Titolo 1">Primo</p>
            <p style="Titolo 1" outline-level="3">Terzo</p>
            <p style="Senza livello">Testo normale</p>
            </document>
            """)
            #expect(document.styles.style(named: "Senza livello")?.values.outlineLevel == 0)
            #expect(document.styles.resolveParagraph(styleName: "Senza livello").outlineLevel == nil)
            #expect(document.flatParagraphs.map(\.paragraph.style.outlineLevel) == [1, 3, nil])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<style name=\"Senza livello\" target=\"paragraph\" based-on=\"Titolo 1\" outline-level=\"0\"/>"))
            #expect(written.contains("<p style=\"Titolo 1\" outline-level=\"3\">Terzo</p>"))
            #expect(try DocumentFormat.document(from: written) == document)
            for invalid in ["-1", "1.5", "molto"] {
                let wrong = written.replacingOccurrences(of: "outline-level=\"3\"", with: "outline-level=\"\(invalid)\"")
                #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: wrong) }
            }
            let characterStyle = written.replacingOccurrences(of: "target=\"paragraph\" based-on=\"Testo\" outline-level=\"1\"",
                                                              with: "target=\"character\" outline-level=\"1\"")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: characterStyle) }
        }

        @Test("In un file che conosce già il livello, il nome «Titolo N» non lo dà; salvato e riaperto, resta senza")
        func nameDoesNotGiveLevelInNewFiles() throws {
            let document = try DocumentFormat.document(from: """
            <document version="18" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Capitolo" target="paragraph" outline-level="1"/>
            <style name="Titolo 2" target="paragraph"/>
            </styles>
            <p style="Titolo 2">Secondo</p>
            </document>
            """)
            #expect(document.styles.style(named: "Titolo 2")?.values.outlineLevel == nil)
            #expect(document.styles.headingStyles(forLevel: 1) == ["Capitolo"] && document.styles.headingStyles(forLevel: 2).isEmpty)
            #expect(try DocumentFormat.document(from: DocumentFormat.string(for: document)) == document)
        }

        @Test("Un file senza stili si scrive come prima")
        func noStyles() {
            let plain = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: plain))]))])
            let written = DocumentFormat.string(for: document)
            #expect(!written.contains("<styles>") && !written.contains("style="))
            #expect(written.contains("<document version=\"18\" font=\"HoeflerText-Regular\" size=\"12\">"))
        }

        @Test("Errori nel file: stile inesistente, della specie sbagliata, catena circolare, stili dopo i paragrafi, nome ripetuto")
        func errors() {
            func error(_ body: String) -> DocumentFormatError? {
                do { _ = try DocumentFormat.document(from: "<document version=\"18\" font=\"HoeflerText-Regular\" size=\"12\">\n\(body)\n</document>"); return nil }
                catch { return error as? DocumentFormatError }
            }
            let styles = "<styles>\n<style name=\"Testo\" target=\"paragraph\"/>\n<style name=\"Enfasi\" target=\"character\" italic=\"on\"/>\n</styles>"
            #expect(error(styles + "\n<p style=\"Nessuno\">a</p>") == .invalidValue(line: 6, attribute: "style", value: "Nessuno"))
            #expect(error(styles + "\n<p style=\"Enfasi\">a</p>") == .invalidValue(line: 6, attribute: "style", value: "Enfasi"))
            #expect(error(styles + "\n<p><t char-style=\"Testo\">a</t></p>") == .invalidValue(line: 6, attribute: "char-style", value: "Testo"))
            #expect(error("<styles>\n<style name=\"A\" target=\"paragraph\" based-on=\"B\"/>\n<style name=\"B\" target=\"paragraph\" based-on=\"A\"/>\n</styles>")
                    == .invalidValue(line: 3, attribute: "based-on", value: "B"))
            if case .malformed(let line, _)? = error("<p>a</p>\n<styles>\n</styles>") { #expect(line == 3) } else { Issue.record("atteso un errore") }
            #expect(error("<styles>\n<style name=\"A\" target=\"paragraph\"/>\n<style name=\"A\" target=\"word\"/>\n</styles>") == .invalidValue(line: 4, attribute: "name", value: "A"))
            #expect(error("<styles>\n<style name=\"A\" target=\"pagina\"/>\n</styles>") == .invalidValue(line: 3, attribute: "target", value: "pagina"))
        }
    }
}

extension TypesettingSuite.StylesTests {
    // MARK: Testo dell'editor

    private static let sheet = StyleSheet.builtIn
    private static let base = CharacterStyle(fontName: "Helvetica", size: 9)

    private static func editorText(_ paragraphs: [(String, String?)]) -> NSMutableAttributedString {
        let blocks = paragraphs.map { text, style in
            Block.paragraph(Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style), inlines: [
                .text(TextRun(text, style: sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)))]))
        }
        return NSMutableAttributedString(attributedString: Document(styles: sheet, lists: ListDefinition.builtIn, blocks: blocks).attributedString().text)
    }

    private static func font(_ text: NSAttributedString, _ word: String) -> NSFont {
        text.attribute(.font, at: (text.string as NSString).range(of: word).location, effectiveRange: nil) as! NSFont
    }

    @Test("Nel testo dell'editor i nomi degli stili sono attributi, e il passaggio dal modello e ritorno non perde nulla")
    func editorRoundTrip() throws {
        let written = DocumentFormat.string(for: try DocumentFormat.document(from: Data(DocumentFormat.string(for: Document(styles: Self.sheet, lists: ListDefinition.builtIn, blocks: [])).utf8)))
        #expect(written.contains("<styles>"))
        let text = Self.editorText([("Titolo", "Heading 1"), ("Corpo del testo", "Body")])
        #expect(text.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Heading 1")
        #expect(Self.font(text, "Titolo").fontName == "HoeflerText-Black")
        let document = Document(attributedString: text, settings: Document(styles: Self.sheet, lists: ListDefinition.builtIn))
        #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly) == document)
        guard case .paragraph(let second) = document.blocks[1] else { return }
        #expect(second.styleName == "Body")
    }

    @Test("Cambiare lo stile di un paragrafo aggiorna ciò che era ereditato e lascia ciò che era dato a mano")
    func applyParagraphStyle() {
        let text = Self.editorText([("Un paragrafo con una parola grande dentro.", "Body")])
        let big = (text.string as NSString).range(of: "grande")
        text.addAttribute(.font, value: NSFont(name: "HoeflerText-Regular", size: 20)!, range: big)  // dato a mano
        TextStyling.restyle(text, range: TextStyling.paragraphRange(in: text, for: NSRange(location: 0, length: 0)), from: Self.sheet, to: Self.sheet) { $0.paragraph = "Heading 1" }
        #expect(text.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Heading 1")
        #expect(Self.font(text, "Un").fontName == "HoeflerText-Black" && Self.font(text, "Un").pointSize == 18)
        // Il corpo 20 era dato a mano e resta; il font era ereditato e diventa il nero.
        #expect(Self.font(text, "grande").pointSize == 20 && Self.font(text, "grande").fontName == "HoeflerText-Black")
        #expect((text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .natural)
    }

    @Test("Stile di carattere e di parola su un pezzo di testo, e la loro rimozione")
    func applyRunStyles() {
        let text = Self.editorText([("Testo con una citazione latina in mezzo.", "Body")])
        let latin = (text.string as NSString).range(of: "citazione latina")
        TextStyling.restyle(text, range: latin, from: Self.sheet, to: Self.sheet) { $0.character = "Emphasis"; $0.word = "Latin" }
        #expect(Self.font(text, "citazione").fontName == "HoeflerText-Italic")
        #expect(text.attribute(.language, at: latin.location, effectiveRange: nil) as? String == "la")
        #expect(text.attribute(.characterStyleName, at: latin.location, effectiveRange: nil) as? String == "Emphasis")
        #expect(Self.font(text, "Testo").fontName == "HoeflerText-Regular", "fuori dal pezzo nulla cambia")
        TextStyling.restyle(text, range: latin, from: Self.sheet, to: Self.sheet) { $0.character = nil; $0.word = nil }
        #expect(Self.font(text, "citazione").fontName == "HoeflerText-Regular")
        #expect(text.attribute(.language, at: latin.location, effectiveRange: nil) == nil)
    }

    @Test("Ridefinire uno stile aggiorna tutto il testo che lo usa, anche attraverso gli stili basati su di lui")
    func redefine() {
        let text = Self.editorText([("Primo paragrafo di testo.", "Body"), ("Una citazione.", "Quotation"), ("Un titolo", "Heading 1")])
        let mark = (text.string as NSString).range(of: "Primo")
        text.addAttribute(.font, value: NSFont(name: "HoeflerText-Regular", size: 16)!, range: mark)  // dato a mano
        var newSheet = Self.sheet
        let at = newSheet.styles.firstIndex { $0.name == "Body" }!
        newSheet.styles[at].values.size = 13
        newSheet.styles[at].values.family = "Baskerville"
        TextStyling.restyle(text, range: NSRange(location: 0, length: text.length), from: Self.sheet, to: newSheet)
        #expect(Self.font(text, "paragrafo").fontName == "Baskerville" && Self.font(text, "paragrafo").pointSize == 13)
        #expect(Self.font(text, "Primo").pointSize == 16 && Self.font(text, "Primo").fontName == "Baskerville", "il corpo dato a mano resta")
        // Citazione fissa il suo corpo (11) ma eredita la famiglia; Titolo 1 eredita la famiglia e resta nero.
        #expect(Self.font(text, "citazione").fontName == "Baskerville" && Self.font(text, "citazione").pointSize == 11)
        #expect(Self.font(text, "titolo").fontName == "Baskerville-Bold")
    }

    @Test("Uno stile nuovo preso dalla selezione registra solo ciò che differisce, con il font come famiglia e corsivo")
    func styleFromSelection() {
        let text = Self.editorText([("Testo normale e testo speciale.", "Body")])
        let special = (text.string as NSString).range(of: "speciale")
        text.addAttribute(.font, value: NSFont(name: "HoeflerText-Italic", size: 14)!, range: special)
        let values = TextStyling.styleValues(from: text, at: special.location, target: .character, sheet: Self.sheet, basedOn: nil)
        #expect(values.italic == true && values.size == 14 && values.family == nil && values.fontName == nil)
        let paragraph = TextStyling.styleValues(from: text, at: 0, target: .paragraph, sheet: Self.sheet, basedOn: "Body")
        #expect(paragraph == StyleValues(), "il paragrafo non differisce da Testo")
    }

    @Test("Le parole di un testo con la sillabazione spenta non si dividono")
    func hyphenationOff() {
        let long = String(repeating: "Considerazioni sull'organizzazione internazionale delle comunicazioni. ", count: 6)
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        let text = NSMutableAttributedString(string: long, attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 14)!, .paragraphStyle: style])
        var setup = PageSetup.a4
        setup.right = setup.paperSize.width - setup.left - 160
        func hyphens() -> Int { PageLayout.layout(text, setup: setup, options: LayoutOptions(hyphenationLanguage: "it")).pages.flatMap(\.lines).filter(\.endsWithHyphen).count }
        #expect(hyphens() > 0)
        text.addAttribute(.hyphenates, value: false, range: NSRange(location: 0, length: text.length))
        #expect(hyphens() == 0)
    }
}

// MARK: - Colore (tappa I.2a)

extension TypesettingSuite {
    @Suite("Colore del testo")
    struct ColorTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private var red: CharacterStyle {
            var style = body
            style.color = "#9b1c1c"
            return style
        }

        @Test("Il colore viaggia dal documento al testo e ritorno, e nel file; il nero è il colore automatico")
        func roundTrip() throws {
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("nero ", style: body)), .text(TextRun("rosso", style: red))]))])
            let text = document.attributedString().text
            let color = try #require(text.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor)
            #expect(TextStyling.hex(of: color) == "#9b1c1c")
            #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("color=\"#9b1c1c\""))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(TextStyling.hex(of: .black) == nil && TextStyling.hex(of: .labelColor) == nil, "nero e colori di sistema: automatico")
            let wrong = written.replacingOccurrences(of: "#9b1c1c", with: "rossiccio")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: wrong) }
        }

        @Test("Uno stile può dare il colore; «color=\"\"» torna al colore automatico")
        func colorInStyles() throws {
            var sheet = StyleSheet.builtIn
            var values = StyleValues()
            values.color = "#1f3f8f"
            sheet.styles.append(NamedStyle(name: "Blu", target: .character, values: values))
            var reset = StyleValues()
            reset.color = ""
            sheet.styles.append(NamedStyle(name: "Di nuovo nero", target: .character, basedOn: "Blu", values: reset))
            #expect(sheet.resolveCharacter(paragraphStyle: "Testo", wordStyle: nil, characterStyle: "Blu", base: TextStyling.styleBase).color == "#1f3f8f")
            #expect(sheet.resolveCharacter(paragraphStyle: "Testo", wordStyle: nil, characterStyle: "Di nuovo nero", base: TextStyling.styleBase).color == nil)
            let document = Document(styles: sheet, lists: ListDefinition.builtIn,
                                    blocks: [.paragraph(Paragraph(styleName: "Testo", inlines: [.text(TextRun("blu", style: body, characterStyleName: "Blu"))]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<style name=\"Blu\" target=\"character\" color=\"#1f3f8f\"/>"))
            #expect(written.contains("color=\"\""))
            #expect(try DocumentFormat.document(from: written).styles == sheet)
        }

        @Test("Nella pagina composta la riga ha il colore del testo")
        func colorReachesLayout() throws {
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("rosso", style: red))]))])
            let layout = PageLayout.layout(document.attributedString().text)
            let line = try #require(layout.pages.first?.lines.first?.line)
            let run = try #require((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let color = attributes[kCTForegroundColorAttributeName] ?? attributes[NSAttributedString.Key.foregroundColor]
            let cg: CGColor? = (color as? NSColor)?.cgColor ?? (color.map { $0 as! CGColor })
            let rgb = try #require(cg?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components)
            #expect(abs(rgb[0] - 0x9b / 255.0) < 0.01 && abs(rgb[1] - 0x1c / 255.0) < 0.01)
        }
    }
}

// MARK: - Posizione verticale (tappa I.2b)

extension TypesettingSuite {
    @Suite("Apice, pedice e posizione verticale")
    struct VerticalPositionTests {
        private func run(_ text: String, font: String, position: VerticalPosition?) -> TextRun {
            TextRun(text, style: CharacterStyle(fontName: font, size: 12, verticalPosition: position))
        }

        private func layout(_ runs: [TextRun]) -> DocumentLayout {
            PageLayout.layout(Document(blocks: [.paragraph(Paragraph(inlines: runs.map(Inline.text)))]).attributedString().text)
        }

        private func runs(of layout: DocumentLayout) -> [(font: CTFont, offset: CGFloat)] {
            (CTLineGetGlyphRuns(layout.pages[0].lines[0].line) as? [CTRun] ?? []).map { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                return (attributes[kCTFontAttributeName] as! CTFont, (attributes[kCTBaselineOffsetAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0)
            }
        }

        @Test("Nel file: i valori già pronti con il loro nome, una posizione propria con i suoi numeri; i refusi sono errori")
        func file() throws {
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(run("H", font: "HoeflerText-Regular", position: nil)), .text(run("2", font: "HoeflerText-Regular", position: .subscript)),
                .text(run("O", font: "HoeflerText-Regular", position: nil)), .text(run("x", font: "HoeflerText-Regular", position: .superscript)),
                .text(run("y", font: "HoeflerText-Regular", position: VerticalPosition(shift: 0.4, scale: 0.6, usesFontGlyphs: false))),
            ]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("vertical=\"subscript\"") && written.contains("vertical=\"superscript\"") && written.contains("vertical=\"0.4 0.6 synthetic\""))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly) == document)
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: written.replacingOccurrences(of: "\"superscript\"", with: "\"sopra\"")) }
        }

        @Test("Senza glifi in apice (Hoefler Text): testo rimpicciolito e alzato, e la riga non diventa più alta")
        func synthetic() {
            let plain = layout([run("x2", font: "HoeflerText-Regular", position: nil)])
            let raised = layout([run("x", font: "HoeflerText-Regular", position: nil), run("2", font: "HoeflerText-Regular", position: .superscript)])
            let lowered = layout([run("H", font: "HoeflerText-Regular", position: nil), run("2", font: "HoeflerText-Regular", position: .subscript)])
            let up = runs(of: raised).last!, down = runs(of: lowered).last!
            #expect(abs(CTFontGetSize(up.font) - 7.8) < 0.01 && up.offset > 0)
            #expect(abs(CTFontGetSize(down.font) - 7.8) < 0.01 && down.offset < 0)
            #expect(abs(raised.pages[0].lines[0].ascent - plain.pages[0].lines[0].ascent) < 0.01, "l'alzata resta nell'altezza delle lettere")
            #expect(abs(lowered.pages[0].lines[0].descent - plain.pages[0].lines[0].descent) < 0.01)
        }

        @Test("Con i glifi del font (Iowan Old Style): le cifre in apice e in pedice disegnate apposta, al corpo pieno")
        func fontGlyphs() {
            let raised = layout([run("x", font: "IowanOldStyle-Roman", position: nil), run("2", font: "IowanOldStyle-Roman", position: .superscript)])
            let up = runs(of: raised).last!
            #expect(CTFontGetSize(up.font) == 12 && up.offset == 0)
            #expect(FontFeatures.settings(of: up.font).contains(.aat(type: 10, selector: 1)))
            let lowered = layout([run("H", font: "IowanOldStyle-Roman", position: nil), run("2", font: "IowanOldStyle-Roman", position: .subscript)])
            // Iowan Old Style non ha un «2» in pedice affidabile: i pedici comuni (10/2) non lo cambiano, gli inferiori
            // scientifici (10/4) danno lo stesso glifo dell'apice. Si ripiega sul testo rimpicciolito e abbassato.
            let down = runs(of: lowered).last!
            #expect(CTFontGetSize(down.font) < 12 && down.offset < 0)
            let forced = layout([run("x", font: "IowanOldStyle-Roman", position: nil),
                                 run("2", font: "IowanOldStyle-Roman", position: VerticalPosition(shift: 0.33, scale: 0.65, usesFontGlyphs: false))])
            #expect(CTFontGetSize(runs(of: forced).last!.font) < 12, "chiedendo di non usare i glifi del font, si rimpicciolisce comunque")
        }
    }
}

// MARK: - Filetti (tappa I.2c)

extension TypesettingSuite {
    @Suite("Filetti: sottolineato, barrato e filetti propri")
    struct DecorationTests {
        private func style(_ decorations: [LineDecoration]) -> CharacterStyle {
            CharacterStyle(fontName: "HoeflerText-Regular", size: 36, decorations: decorations)
        }

        @Test("Scrittura: i valori già pronti con il loro nome, i filetti propri con i loro parametri; i refusi non passano")
        func encoding() throws {
            let custom = LineDecoration(position: .under, pattern: .dotted, offset: 1, thickness: 0.6, color: "#9b1c1c")
            #expect(LineDecoration.encode([.underline, .strikethrough, custom]) == "underline; strikethrough; under dotted 1 0.6 #9b1c1c noskip")
            #expect(LineDecoration.decode("underline; strikethrough; under dotted 1 0.6 #9b1c1c noskip") == [.underline, .strikethrough, custom])
            #expect(LineDecoration.decode("") == [])
            #expect(LineDecoration.decode("sotto") == nil && LineDecoration.decode("under dotted 1 0.6 rosso noskip") == nil)
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("parola", style: style([.underline, custom])))]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("lines=\"underline; under dotted 1 0.6 #9b1c1c noskip\""))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(Document(attributedString: document.attributedString().text, settings: document.settingsOnly) == document)
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: written.replacingOccurrences(of: "dotted", with: "a puntini")) }
        }

        @Test("Le interruzioni del filetto: le parti fra un'interruzione e l'altra")
        func pieces() {
            let parts = LineDecorations.pieces(from: 0, to: 100, gaps: [40...50, 10...20, 45...60])
            #expect(parts == [0...10, 20...40, 60...100])
        }

        /// La pagina disegnata in memoria, a 1 punto per pixel: per ogni riga di pixel, quanti sono scuri.
        private func ink(_ runs: [TextRun]) -> (rows: [Int: Int], baseline: CGFloat, columns: (Int, ClosedRange<Int>) -> Int) {
            let layout = PageLayout.layout(Document(blocks: [.paragraph(Paragraph(inlines: runs.map(Inline.text)))]).attributedString().text)
            let size = layout.setup.paperSize
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
            PDFRenderer.draw(layout.pages[0], in: context)
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            let width = context.bytesPerRow
            let height = Int(size.height)
            func dark(_ x: Int, _ y: Int) -> Bool { data[(height - 1 - y) * width + x] < 128 }  // y dal basso, come la pagina
            var rows: [Int: Int] = [:]
            for y in 0..<height { rows[y] = (0..<Int(size.width)).filter { dark($0, y) }.count }
            return (rows, layout.pages[0].lines[0].origin.y, { y, xs in xs.filter { dark($0, y) }.count })
        }

        @Test("Il sottolineato si disegna sotto la linea di base, e si interrompe sotto le discendenti")
        func underlineIsDrawn() {
            let font = CTFontCreateWithName("HoeflerText-Regular" as CFString, 36, nil)
            let plain = ink([TextRun("ggg", style: style([]))])
            let skipping = ink([TextRun("ggg", style: style([.underline]))])
            let solid = ink([TextRun("ggg", style: style([LineDecoration(position: .under)]))])
            let y = Int((plain.baseline + CTFontGetUnderlinePosition(font)).rounded())
            #expect(solid.rows[y]! > plain.rows[y]! + 30, "senza salto, una riga piena sotto le tre g")
            #expect(skipping.rows[y]! < solid.rows[y]! - 20, "con il salto, interrotta sotto le g")
        }

        @Test("Il barrato attraversa anche gli spazi fra le parole")
        func strikethroughIsDrawn() {
            let font = CTFontCreateWithName("HoeflerText-Regular" as CFString, 36, nil)
            let plain = ink([TextRun("a    a", style: style([]))])
            let struck = ink([TextRun("a    a", style: style([.strikethrough]))])
            let y = Int((plain.baseline + CTFontGetXHeight(font) * 0.55).rounded())
            #expect(struck.rows[y]! > plain.rows[y]! + 30)
        }
    }
}
