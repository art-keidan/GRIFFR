import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Note a piè di pagina: modello, file e testo")
    struct FootnoteModelTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
        private let smallCaps = CharacterStyle(fontName: "HoeflerText-Regular", size: 10, smallCaps: .lowercase)

        private func sample() -> Document {
            Document(blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Testo", style: body)),
                    .floating(FloatingObject(runs: [TextRun("Una nota con ", style: small), TextRun("maiuscoletto", style: smallCaps), TextRun(".", style: small)])),
                    .text(TextRun(" che continua", style: body)),
                    .floating(FloatingObject(runs: [TextRun("", style: small)])),
                    .text(TextRun(".", style: body)),
                ])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Secondo paragrafo.", style: body))])),
            ])
        }

        @Test("Nel file la nota sta nel punto del richiamo, senza numero")
        func written() throws {
            let text = DocumentFormat.string(for: sample())
            #expect(text.contains("<p>Testo<note size=\"10\">Una nota con <t small-caps=\"lowercase\">maiuscoletto</t>.</note> che continua<note size=\"10\"/>.</p>"))
            #expect(try DocumentFormat.document(from: text) == sample())
        }

        @Test("Una nota di più paragrafi: nel file ciascuno ha il suo p, nel testo sono separati da a capo marcati")
        func multipleParagraphs() throws {
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Prima", style: body)),
                    .floating(FloatingObject(paragraphs: [[TextRun("Uno.", style: small)], [TextRun("", style: small)], [TextRun("Tre ", style: small), TextRun("maiuscoletto", style: smallCaps)]])),
                    .text(TextRun(" dopo.", style: body)),
                ])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Secondo.", style: body))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<p>Prima<note size=\"10\"><p>Uno.</p><p/><p>Tre <t small-caps=\"lowercase\">maiuscoletto</t></p></note> dopo.</p>"))
            #expect(try DocumentFormat.document(from: written) == document)

            let text = document.attributedString().text
            #expect(text.string == "Prima\u{FFFC}Uno.\n\nTre maiuscoletto dopo.\nSecondo.")
            // Gli a capo dentro la nota sono marcati come nota; quello che chiude il paragrafo no.
            #expect(text.attribute(.footnote, at: 10, effectiveRange: nil) != nil)
            #expect(text.attribute(.footnote, at: 11, effectiveRange: nil) != nil)
            #expect(text.attribute(.footnote, at: 34, effectiveRange: nil) == nil)
            #expect(TextStyling.footnoteSpan(in: text, anchoredAt: 5) == NSRange(location: 5, length: 23))
            #expect(TextStyling.footnoteSpan(in: text, containing: 12, affinity: .downstream) == NSRange(location: 5, length: 23), "nel terzo paragrafo della nota")
            // Il paragrafo del corpo abbraccia tutta la nota, a capo compresi.
            #expect(TextStyling.bodyParagraph(in: text, at: 12).range == NSRange(location: 0, length: 35))
            #expect(TextStyling.bodyParagraph(in: text, at: 12).contentsEnd == 34)
            #expect(TextStyling.bodyParagraph(in: text, at: 36).range == NSRange(location: 35, length: 8))
            #expect(Document(attributedString: text) == document)
        }

        @Test("Nel file, tra i paragrafi di una nota si possono mettere spazi e a capo; del testo sciolto no")
        func noteParagraphsInFile() throws {
            let document = try DocumentFormat.document(from: """
            <document version="1" font="HoeflerText-Regular" size="12">
            <p>a<note size="10">
              <p>uno</p>
              <p>due</p>
            </note>b</p>
            </document>
            """)
            guard case .paragraph(let paragraph) = document.blocks[0], case .floating(let note) = paragraph.inlines[1] else {
                Issue.record("nota non trovata")
                return
            }
            #expect(note.paragraphs.map { $0.map(\.text).joined() } == ["uno", "due"])
            #expect(throws: DocumentFormatError.self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"X\" size=\"12\"><p>a<note><p>uno</p>sciolto<p>due</p></note></p></document>")
            }
        }

        @Test("La riparazione non tocca una nota di più paragrafi, anche se la modifica cade nel suo ultimo paragrafo")
        func repairKeepsMultiParagraphNotes() {
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("Prima", style: body)), .floating(FloatingObject(paragraphs: [[TextRun("Uno.", style: small)], [TextRun("Due.", style: small)]])), .text(TextRun(" dopo.", style: body)),
            ]))])
            let text = NSMutableAttributedString(attributedString: document.attributedString().text)
            TextStyling.repairFootnotes(in: text, range: NSRange(location: 13, length: 1))
            #expect(Document(attributedString: text) == document)
        }

        @Test("Una nota fuori da un paragrafo o dentro un'altra nota è un errore")
        func misplaced() {
            #expect(throws: DocumentFormatError.unexpectedElement(line: 2, element: "note", parent: "document")) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"X\" size=\"12\">\n<note>a</note>\n</document>")
            }
            #expect(throws: DocumentFormatError.unexpectedElement(line: 2, element: "note", parent: "note")) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"X\" size=\"12\">\n<p>a<note>b<note>c</note></note></p>\n</document>")
            }
        }

        @Test("Nel testo la nota è un carattere-richiamo seguito dal suo testo, marcati come nota")
        func asAttributedText() throws {
            let (text, missing) = sample().attributedString()
            #expect(missing.isEmpty)
            let anchor = "\u{FFFC}"
            #expect(text.string == "Testo\(anchor)Una nota con maiuscoletto. che continua\(anchor).\nSecondo paragrafo.")
            func isNote(_ index: Int) -> Bool { text.attribute(.footnote, at: index, effectiveRange: nil) != nil }
            #expect(!isNote(4))
            #expect(isNote(5), "il richiamo")
            #expect(isNote(6) && isNote(31), "il testo della nota")
            #expect(!isNote(32), "dopo la nota si torna al testo")
            let second = (text.string as NSString).range(of: anchor, options: [], range: NSRange(location: 6, length: text.length - 6)).location
            #expect(isNote(second))
            #expect(!isNote(second + 1), "la nota vuota è il solo richiamo")
            #expect(!isNote((text.string as NSString).range(of: "\n").location), "l'a capo del paragrafo non fa parte di una nota")
            // E ritorno: lo stesso documento.
            #expect(Document(attributedString: text) == sample())
        }

        @Test("Due note di seguito restano due note")
        func adjacentNotes() {
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("a", style: body)),
                .floating(FloatingObject(runs: [TextRun("prima", style: small)])),
                .floating(FloatingObject(runs: [TextRun("seconda", style: small)])),
                .text(TextRun("b", style: body)),
            ]))])
            #expect(Document(attributedString: document.attributedString().text) == document)
            #expect(DocumentFormat.string(for: document).contains("a<note size=\"10\">prima</note><note size=\"10\">seconda</note>b"))
        }

        @Test("Nel testo si riconosce la nota a cui appartiene una posizione")
        func spans() {
            // «Testo» 0…4, richiamo 5, nota 6…31, « che continua» 32…44, richiamo 45 (nota vuota), «.» 46.
            let text = sample().attributedString().text
            #expect(TextStyling.footnoteSpan(in: text, anchoredAt: 5) == NSRange(location: 5, length: 27))
            #expect(TextStyling.footnoteSpan(in: text, anchoredAt: 4) == nil)
            #expect(TextStyling.footnoteSpan(in: text, containing: 5, affinity: .downstream) == nil, "prima del richiamo si è nel corpo")
            #expect(TextStyling.footnoteSpan(in: text, containing: 6, affinity: .downstream) == NSRange(location: 5, length: 27))
            #expect(TextStyling.footnoteSpan(in: text, containing: 20, affinity: .downstream) == NSRange(location: 5, length: 27))
            #expect(TextStyling.footnoteSpan(in: text, containing: 32, affinity: .upstream) == NSRange(location: 5, length: 27), "fine della nota")
            #expect(TextStyling.footnoteSpan(in: text, containing: 32, affinity: .downstream) == nil, "stesso punto, ma nel corpo dopo il richiamo")
            #expect(TextStyling.footnoteSpan(in: text, containing: 46, affinity: .upstream) == NSRange(location: 45, length: 1), "dentro la nota vuota")
            #expect(TextStyling.footnoteSpan(in: text, containing: 46, affinity: .downstream) == nil)
        }

        @Test("La riparazione toglie il contrassegno di nota al testo rimasto senza richiamo")
        func repair() {
            let text = NSMutableAttributedString(attributedString: sample().attributedString().text)
            text.deleteCharacters(in: NSRange(location: 5, length: 1))
            #expect(text.attribute(.footnote, at: 5, effectiveRange: nil) != nil)
            TextStyling.repairFootnotes(in: text, range: NSRange(location: 5, length: 0))
            #expect(text.attribute(.footnote, at: 5, effectiveRange: nil) == nil)
            #expect(text.attribute(.footnote, at: 20, effectiveRange: nil) == nil)
            // La seconda nota, che ha ancora il suo richiamo, resta.
            let second = (text.string as NSString).range(of: "\u{FFFC}").location
            #expect(text.attribute(.footnote, at: second, effectiveRange: nil) != nil)
            // Un testo senza note, o vuoto, non dà problemi.
            TextStyling.repairFootnotes(in: NSMutableAttributedString(), range: NSRange(location: 0, length: 0))
            let plain = NSMutableAttributedString(string: "abc")
            TextStyling.repairFootnotes(in: plain, range: NSRange(location: 3, length: 0))
            #expect(plain.string == "abc")
        }

        @Test("Per le altre applicazioni le note diventano rimandi tra parentesi quadre, con i testi in coda")
        func flattened() {
            let text = sample().attributedString().text
            let flat = TextStyling.flattenedForExport(text)
            #expect(flat.string == "Testo[1] che continua[2].\nSecondo paragrafo.\n\n[1] Una nota con maiuscoletto.\n[2] ")
            #expect(flat.attribute(.footnote, at: 5, effectiveRange: nil) == nil)
            // Un testo senza note resta com'è.
            #expect(TextStyling.flattenedForExport(NSAttributedString(string: "Semplice.")).string == "Semplice.")
        }

        @Test("Un frammento copiato nel nostro formato ritorna identico, note comprese")
        func fragmentRoundTrip() throws {
            let text = sample().attributedString().text
            // Da «to» fino a « che», con la prima nota in mezzo.
            let fragment = text.attributedSubstring(from: NSRange(location: 3, length: 33))
            let data = DocumentFormat.data(for: Document(attributedString: fragment))
            let pasted = try DocumentFormat.document(from: data).attributedString().text
            #expect(pasted.string == fragment.string)
            #expect(TextStyling.footnoteSpan(in: pasted, anchoredAt: 2) == NSRange(location: 2, length: 27))
            #expect(Document(attributedString: pasted) == Document(attributedString: fragment))
        }

        @Test("Se il richiamo viene cancellato, il testo della nota torna testo normale")
        func orphanedNoteText() throws {
            let text = NSMutableAttributedString(attributedString: sample().attributedString().text)
            text.deleteCharacters(in: NSRange(location: 5, length: 1))  // il primo richiamo
            guard case .paragraph(let paragraph) = Document(attributedString: text).blocks[0] else { return }
            let notes = paragraph.inlines.filter { if case .floating = $0 { true } else { false } }
            #expect(notes.count == 1, "resta solo la seconda nota")
            #expect(paragraph.plainText.hasPrefix("TestoUna nota con maiuscoletto. che continua"))
        }
    }
}
