import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Formato di file e modello di documento")
    struct DocumentFormatTests {
        private let hoefler = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let smallCaps = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, smallCaps: .lowercase)
        private let gothic = CharacterStyle(fontName: "Vulcanius", size: 36, features: [.aat(type: 17, selector: 3)])

        private func sample() -> Document {
            var justified = ParagraphStyle()
            justified.alignment = .justified
            justified.firstLineIndent = 14
            return Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun(TestFonts.gothicSample, style: gothic))])),
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Testo con ", style: hoefler)), .text(TextRun("maiuscoletto", style: smallCaps)), .text(TextRun(" e fine.", style: hoefler)),
                ])),
                .paragraph(Paragraph(style: justified, inlines: [.text(TextRun("Un paragrafo giustificato, con a < b & c.", style: hoefler))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("", style: hoefler))])),
            ])
        }

        @Test("Il file scritto è quello atteso, riga per riga")
        func written() {
            #expect(DocumentFormat.string(for: sample()) == """
            <?xml version="1.0" encoding="UTF-8"?>
            <document version="1" font="HoeflerText-Regular" size="12">
            <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
            <p font="Vulcanius" size="36" features="17/3">\u{10339}\u{10343} \u{10332}\u{10342}</p>
            <p>Testo con <t small-caps="lowercase">maiuscoletto</t> e fine.</p>
            <p align="justified" first-indent="14">Un paragrafo giustificato, con a &lt; b &amp; c.</p>
            <p/>
            </document>

            """)
        }

        @Test("Il testo liscio resta il predefinito anche quando è in minoranza")
        func plainStaysDefault() throws {
            // Il caso emerso dalla prova a schermo: una parola aggiunta in maiuscoletto non deve ribaltare il file.
            let plain = CharacterStyle(fontName: "HoeflerText-Regular", size: 24)
            let caps = CharacterStyle(fontName: "HoeflerText-Regular", size: 24, smallCaps: .lowercase)
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("ct st ", style: plain)), .text(TextRun("Small Caps", style: caps))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("asdf", style: caps))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<document version=\"1\" font=\"HoeflerText-Regular\" size=\"24\">"))
            #expect(written.contains("<p>ct st <t small-caps=\"lowercase\">Small Caps</t></p>"))
            #expect(written.contains("<p small-caps=\"lowercase\">asdf</p>"))
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("La lingua di un pezzo di testo: sul paragrafo se è di tutto il paragrafo, altrimenti sul tratto")
        func languages() throws {
            let latin = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, language: "la")
            let greek = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, language: "grc")
            let document = Document(language: "it", blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Disse: ", style: hoefler)), .text(TextRun("veni, vidi, vici", style: latin)), .text(TextRun(".", style: hoefler))])),
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Gallia est omnis divisa", style: latin)),
                    .floating(FloatingObject(runs: [TextRun("Nota in italiano con ", style: hoefler), TextRun("λόγος", style: greek)])),
                    .text(TextRun(" in partes tres.", style: latin)),
                ])),
                .paragraph(Paragraph(inlines: [.text(TextRun("", style: latin))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\" lang=\"it\">"))
            #expect(written.contains("<p>Disse: <t lang=\"la\">veni, vidi, vici</t>.</p>"))
            #expect(written.contains("<p lang=\"la\">Gallia est omnis divisa<note lang=\"\">Nota in italiano con <t lang=\"grc\">λόγος</t></note> in partes tres.</p>"))
            #expect(written.contains("<p lang=\"la\"/>"))
            #expect(try DocumentFormat.document(from: written) == document)

            // Nel testo attribuito la lingua è un attributo, che torna identico nel modello.
            let text = document.attributedString().text
            let string = text.string as NSString
            #expect(text.attribute(.language, at: string.range(of: "vidi").location, effectiveRange: nil) as? String == "la")
            #expect(text.attribute(.language, at: string.range(of: "Disse").location, effectiveRange: nil) == nil)
            #expect(text.attribute(.language, at: string.range(of: "λόγος").location, effectiveRange: nil) as? String == "grc")
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
        }

        @Test("Scrivere e rileggere restituisce lo stesso documento")
        func roundTrip() throws {
            let document = sample()
            #expect(try DocumentFormat.document(from: DocumentFormat.data(for: document)) == document)
        }

        @Test("Spazi, tabulazioni, a capo interni e caratteri speciali sopravvivono")
        func whitespace() throws {
            let text = "  due spazi davanti,\tuna tabulazione, un a capo\u{2028}interno, «&<>\"'» e spazio finale "
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun(text, style: hoefler))]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("un a capo<br/>interno"))
            let reread = try DocumentFormat.document(from: written)
            #expect(reread == document)
            guard case .paragraph(let paragraph) = reread.blocks[0] else { return }
            #expect(paragraph.plainText == text)
        }

        @Test("Chi cambia font non eredita le funzioni; features vuoto le azzera")
        func inheritance() throws {
            let document = try DocumentFormat.document(from: """
            <document version="1" font="HoeflerText-Regular" size="12" features="21/1">
            <p>a<t features="">b</t><t font="Vulcanius">c</t><t size="9">d</t></p>
            <p font="Brill-Roman" features="cv01=2 smcp=1">e</p>
            </document>
            """)
            guard case .paragraph(let first) = document.blocks[0], case .paragraph(let second) = document.blocks[1] else { return }
            let oldStyle = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, features: [.aat(type: 21, selector: 1)])
            #expect(first.inlines == [
                .text(TextRun("a", style: oldStyle)),
                .text(TextRun("b", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 12))),
                .text(TextRun("c", style: CharacterStyle(fontName: "Vulcanius", size: 12))),
                .text(TextRun("d", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 9, features: [.aat(type: 21, selector: 1)]))),
            ])
            // `smcp` fra le funzioni è il maiuscoletto dei file di prima: diventa la scelta tipografica.
            #expect(second.inlines == [.text(TextRun("e", style: CharacterStyle(
                fontName: "Brill-Roman", size: 12, features: [.openType(tag: "cv01", value: 2)], smallCaps: .lowercase)))])
        }

        @Test("L'interruttore di trak si salva solo quando è spento")
        func trackingSwitch() throws {
            var document = sample()
            #expect(!DocumentFormat.string(for: document).contains("trak="))
            document.appliesFontTracking = false
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\" trak=\"off\">"))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "trak", value: "forse")) {
                try DocumentFormat.document(from: "<document version=\"1\" trak=\"forse\"></document>")
            }
        }

        @Test("L'intensità dell'espansione si salva in percentuale; il predefinito resta implicito")
        func glyphExpansionSetting() throws {
            var document = sample()
            #expect(!DocumentFormat.string(for: document).contains("expansion="))
            document.glyphExpansionLimit = 0.025
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("expansion=\"2.5\""))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(document.layoutOptions.glyphExpansionLimit == 0.025)
            #expect(try DocumentFormat.document(from: "<document version=\"1\" expansion=\"0\"></document>").glyphExpansionLimit == 0)
            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "expansion", value: "4")) {
                try DocumentFormat.document(from: "<document version=\"1\" expansion=\"4\"></document>")
            }
            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "expansion", value: "molta")) {
                try DocumentFormat.document(from: "<document version=\"1\" expansion=\"molta\"></document>")
            }
        }

        @Test("Lingua, sillabazione e margini ottici si salvano nel documento")
        func typographySettings() throws {
            var document = sample()
            document.language = "it"
            document.hyphenates = false
            document.usesOpticalMargins = false
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\" lang=\"it\" hyphenation=\"off\" opbd=\"off\">"))
            #expect(try DocumentFormat.document(from: written) == document)
            #expect(document.layoutOptions == LayoutOptions(appliesFontTracking: true, usesOpticalMargins: false, hyphenationLanguage: "it", hyphenates: false, lineBreaking: .optimal))
            document.hyphenates = true
            #expect(document.layoutOptions.hyphenates && document.layoutOptions.hyphenationLanguage == "it")
            // Un file senza queste indicazioni: nessuna lingua, tutto il resto acceso.
            let bare = try DocumentFormat.document(from: "<document version=\"1\"></document>")
            #expect(bare.language == nil)
            #expect(bare.hyphenates && bare.usesOpticalMargins && bare.appliesFontTracking)
        }

        @Test("Le misure della pagina accettano mm, cm, in e pt")
        func pageUnits() throws {
            let document = try DocumentFormat.document(from: """
            <document version="1"><page width="21cm" height="11in" top="72" bottom="36pt" left="20mm" right="20mm"/></document>
            """)
            #expect(abs(document.pageSetup.paperSize.width - PageSetup.a4.paperSize.width) < 1e-9)
            #expect(document.pageSetup.paperSize.height == 792)
            #expect(document.pageSetup.top == 72)
            #expect(document.pageSetup.bottom == 36)
            #expect(document.blocks.isEmpty)
        }

        @Test("Gli errori indicano la riga", arguments: [
            ("<document version=\"1\" font=\"X\" size=\"12\">\n<p>a</p>\n<tabella/>\n</document>",
             DocumentFormatError.unexpectedElement(line: 3, element: "tabella", parent: "document")),
            ("<document version=\"1\" font=\"X\" size=\"12\">\n<p>a</p>\n<table/>\n</document>",
             .malformed(line: 3, detail: "a table has at least one row")),
            ("<document version=\"1\" font=\"X\" size=\"12\">\n<p colour=\"red\">a</p>\n</document>",
             .unknownAttribute(line: 2, element: "p", attribute: "colour")),
            ("<document version=\"1\" size=\"12\">\n<p>a</p>\n</document>", .missingAttribute(line: 2, attribute: "font")),
            ("<document version=\"1\" font=\"X\" size=\"12\">\n<p features=\"17-3\">a</p>\n</document>",
             .invalidValue(line: 2, attribute: "features", value: "17-3")),
            ("<document version=\"1\" font=\"X\" size=\"12\">\n<p align=\"middle\">a</p>\n</document>", .invalidValue(line: 2, attribute: "align", value: "middle")),
            ("<document version=\"99\"></document>", .newerVersion(99)),
        ])
        func errors(source: String, expected: DocumentFormatError) {
            #expect(throws: expected) { try DocumentFormat.document(from: source) }
        }

        @Test("XML mal formato e testo fuori dai paragrafi sono rifiutati")
        func malformed() {
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: "<document version=\"1\"><p>a</document>") }
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: "<document version=\"1\">testo sciolto</document>") }
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: "non è XML") }
        }

        @Test("Un file scritto a mano si apre, si impagina e si riscrive senza perdere nulla")
        func handWritten() throws {
            let source = """
            <?xml version="1.0" encoding="UTF-8"?>
            <document version="1" font="HoeflerText-Regular" size="14">
            <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
            <p font="Vulcanius" size="36" features="17/3">\u{10339}\u{10343} \u{10332}\u{10342}</p>
            <p size="24">ct st <t features="1/4">ct st</t> ffi <t small-caps="lowercase">Small Caps</t></p>
            <p align="justified" first-indent="14">Questo file è stato scritto a mano, e il paragrafo è giustificato.</p>
            </document>

            """
            let document = try DocumentFormat.document(from: source)
            #expect(DocumentFormat.string(for: document) == source, "la riscrittura è identica carattere per carattere")

            // Il percorso che fa l'app: file → modello → testo dell'editor → modello → file.
            let (text, missing) = document.attributedString()
            #expect(missing.isEmpty)
            #expect(DocumentFormat.string(for: Document(attributedString: text, pageSetup: document.pageSetup)) == source)

            let lines = PageLayout.layout(text, appliesFontTracking: false).pages[0].lines
            func ids(_ index: Int) -> [Int] { Shaper.glyphs(in: lines[index].line).filter { $0.advance > 0 }.map { Int($0.id) } }
            #expect(ids(0) == [33, 34, 3, 8, 24])
            #expect(Array(ids(1).prefix(9)) == [70, 87, 3, 86, 87, 3, 643, 3, 644], "ct st normali, poi ct e st legati")
        }

        // MARK: Ponte con il testo attribuito

        @Test("Dal testo attribuito al documento e ritorno: stesso testo, stessi glifi")
        func attributedRoundTrip() throws {
            let source = NSMutableAttributedString()
            source.append(NSAttributedString(string: TestFonts.gothicSample + "\n", attributes: [
                .font: FontFeatures.font(try #require(NSFont(name: "Vulcanius", size: 36)) as CTFont, with: [.aat(type: 17, selector: 3)]),
            ]))
            let hoeflerFont = try #require(NSFont(name: "HoeflerText-Regular", size: 24)) as CTFont
            source.append(NSAttributedString(string: "ct st ", attributes: [.font: FontFeatures.font(hoeflerFont, with: [.aat(type: 1, selector: 4)])]))
            source.append(NSAttributedString(string: "ffi 1234\n", attributes: [.font: hoeflerFont]))

            let document = Document(attributedString: source)
            #expect(document.blocks.count == 3, "due paragrafi e quello vuoto dopo l'ultimo a capo")
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("font=\"Vulcanius\" size=\"36\" features=\"17/3\""))
            #expect(written.contains("<t features=\"1/4\">ct st </t>ffi 1234</p>"))

            let (rebuilt, missing) = try DocumentFormat.document(from: written).attributedString()
            #expect(missing.isEmpty)
            #expect(rebuilt.string == source.string)
            let lines = PageLayout.layout(rebuilt, appliesFontTracking: false).pages[0].lines
            func ids(_ index: Int) -> [Int] { Shaper.glyphs(in: lines[index].line).filter { $0.advance > 0 }.map { Int($0.id) } }
            #expect(ids(0) == [33, 34, 3, 8, 24])
            #expect(ids(1) == [643, 3, 644, 3, 631, 3, 20, 21, 22, 23])
        }

        @Test("Lo stile di paragrafo passa nei due sensi")
        func paragraphStyleBridge() {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            style.headIndent = 20
            style.firstLineHeadIndent = 34
            style.tailIndent = -10
            style.paragraphSpacing = 6
            style.lineHeightMultiple = 1.2
            let source = NSAttributedString(string: "Testo", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 12) as Any, .paragraphStyle: style])
            let document = Document(attributedString: source)
            guard case .paragraph(let paragraph) = document.blocks[0] else { return }
            #expect(paragraph.style.alignment == .justified)
            #expect(paragraph.style.leftIndent == 20)
            #expect(paragraph.style.firstLineIndent == 14)
            #expect(paragraph.style.rightIndent == 10)
            #expect(paragraph.style.spaceAfter == 6)
            #expect(Document(attributedString: document.attributedString().text) == document)
        }

        @Test("Un font non installato viene segnalato, sostituito a schermo e conservato nel file")
        func missingFont() throws {
            let absent = CharacterStyle(fontName: "FontCheNonEsiste-Regular", size: 12, features: [.aat(type: 17, selector: 3), .openType(tag: "cv01", value: 2)])
            let present = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("manca", style: absent)), .text(TextRun(" c'è", style: present)),
            ]))])
            let (text, missing) = document.attributedString()
            #expect(missing == ["FontCheNonEsiste-Regular"])
            #expect(text.string == "manca c'è")
            // Salvare senza toccare nulla riscrive il nome e le funzioni originali, non il ripiego.
            #expect(Document(attributedString: text) == document)

            // Se però l'utente assegna un altro font a quel testo, vale la sua scelta.
            let edited = NSMutableAttributedString(attributedString: text)
            edited.addAttribute(.font, value: try #require(NSFont(name: "HoeflerText-Regular", size: 12)), range: NSRange(location: 0, length: 5))
            guard case .paragraph(let paragraph) = Document(attributedString: edited).blocks[0] else { return }
            #expect(paragraph.inlines == [.text(TextRun("manca c'è", style: present))])
        }

        @Test("Misure infinite o non numeriche e fogli senza specchio si rifiutano")
        func impossibleMeasuresAreRejected() {
            func read(_ inner: String) throws -> Document {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\">\(inner)<p>Testo</p></document>")
            }
            #expect(DocumentFormat.parseLength("inf") == nil)
            #expect(DocumentFormat.parseLength("nan mm") == nil)
            #expect(DocumentFormat.parseLength("1e308in") == nil, "finito come numero, infinito una volta in punti")
            #expect(DocumentFormat.parseLength("21cm") != nil)
            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "width", value: "inf")) { try read("<page width=\"inf\"/>") }
            #expect(throws: DocumentFormatError.self) { try read("<page width=\"0\"/>") }
            #expect(throws: DocumentFormatError.self) { try read("<page width=\"100mm\" left=\"60mm\" right=\"40mm\"/>") }
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"inf\"><p>Testo</p></document>")
            }
            #expect((try? read("<page width=\"100mm\" left=\"30mm\" right=\"30mm\"/>")) != nil)
        }

        @Test("Tabulazione, a capo e U+2028 nei nomi sopravvivono al salvataggio")
        func controlCharactersInAttributes() throws {
            for name in ["A\tB", "A\nB", "A\u{2028}B", "A \"B\" & <C>"] {
                var document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Testo", style: hoefler, characterStyleName: name))]))])
                document.styles.styles.append(NamedStyle(name: name, target: .character, values: StyleValues()))
                document.styles.styles.append(NamedStyle(name: "A B", target: .character, values: StyleValues()))
                let reread = try DocumentFormat.document(from: DocumentFormat.data(for: document))
                #expect(reread.styles.style(named: name) != nil, "\(name.debugDescription) resta com'era")
                #expect(reread.styles.styles.count == document.styles.styles.count, "e non si confonde con «A B»")
                guard case .paragraph(let paragraph) = reread.blocks.first, case .text(let run) = paragraph.inlines.first else {
                    Issue.record("manca il paragrafo")
                    continue
                }
                #expect(run.characterStyleName == name)
            }
        }
    }
}
