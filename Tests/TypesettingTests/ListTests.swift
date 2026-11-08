import AppKit
import CoreText
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Elenchi puntati e numerati")
    struct ListTests {
        private let hoefler = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

        private func paragraph(_ text: String, _ marker: String? = nil, level: Int = 1) -> Block {
            .paragraph(Paragraph(list: marker.map { ListItem(marker: $0, level: level) }, inlines: [.text(TextRun(text, style: hoefler))]))
        }

        // MARK: Segni e numeri

        @Test("Un segno è un modello di numerazione se contiene un solo contatore; altrimenti è un simbolo fisso")
        func markers() {
            #expect(ListItem(marker: "1.").numbering?.counter == .decimal)
            #expect(ListItem(marker: "(a)").numbering.map { [$0.prefix, $0.suffix] } == ["(", ")"])
            #expect(ListItem(marker: "I.").numbering?.counter == .upperRoman)
            #expect(ListItem(marker: "§ 1").numbering?.prefix == "§ ")
            for symbol in ["•", "–", "→", "*", "o", "Es."] { #expect(!ListItem(marker: symbol).isNumbered, "\(symbol)") }
            #expect(ListItem(marker: "(i)").text(number: 4) == "(iv)")
            #expect(ListItem(marker: "a)").text(number: 28) == "ab)")
            #expect(ListItem(marker: "•").text(number: 3) == "•")
        }

        @Test("I contatori: cifre, lettere, numeri romani", arguments: [
            (ListItem.Counter.decimal, 12, "12"), (.lowerLetter, 1, "a"), (.lowerLetter, 26, "z"), (.lowerLetter, 27, "aa"), (.upperLetter, 3, "C"),
            (.lowerRoman, 4, "iv"), (.lowerRoman, 9, "ix"), (.lowerRoman, 14, "xiv"), (.upperRoman, 1994, "MCMXCIV"),
        ])
        func counters(counter: ListItem.Counter, number: Int, expected: String) {
            #expect(counter.text(for: number) == expected)
        }

        @Test("La numerazione continua dentro lo stesso elenco e riparte dopo un'interruzione")
        func numbering() {
            func texts(_ items: [ListItem?]) -> [String?] {
                var numbering = ListNumbering()
                return items.map { numbering.next($0) }
            }
            let one = ListItem(marker: "1."), sub = ListItem(marker: "a)", level: 2), bullet = ListItem(marker: "•")
            // Le voci interne non interrompono la numerazione esterna, e ripartono a ogni voce esterna.
            #expect(texts([one, one, sub, sub, one, sub]) == ["1.", "2.", "a)", "b)", "3.", "a)"])
            // Un paragrafo normale chiude l'elenco.
            #expect(texts([one, one, nil, one]) == ["1.", "2.", nil, "1."])
            // Un segno diverso allo stesso livello è un altro elenco.
            #expect(texts([one, bullet, one, ListItem(marker: "1)"), ListItem(marker: "1)")]) == ["1.", "•", "1.", "1)", "2)"])
            // Un elenco può cominciare da un livello interno.
            #expect(texts([sub, sub, one]) == ["a)", "b)", "1."])
        }

        // MARK: File

        @Test("Nel file una voce è un paragrafo con il suo segno e, se non è 1, il suo livello")
        func fileFormat() throws {
            let document = Document(blocks: [
                paragraph("Prima."), paragraph("Uno", "1."), paragraph("Sotto", "a)", level: 2), paragraph("Due", "1."),
                paragraph("Punto", "•"), paragraph("", "•"),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("""
            <p>Prima.</p>
            <p list="1.">Uno</p>
            <p list="a)" level="2">Sotto</p>
            <p list="1.">Due</p>
            <p list="•">Punto</p>
            <p list="•"/>
            """))
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("Errori nel file: livello senza elenco, livello fuori misura, segno vuoto")
        func fileErrors() {
            func error(_ paragraph: String) -> DocumentFormatError? {
                do {
                    _ = try DocumentFormat.document(from: "<document version=\"18\" font=\"X\" size=\"12\">\n\(paragraph)\n</document>")
                    return nil
                } catch { return error as? DocumentFormatError }
            }
            #expect(error("<p level=\"2\">a</p>") == .missingAttribute(line: 2, attribute: "list"))
            #expect(error("<p list=\"1.\" level=\"12\">a</p>") == .invalidValue(line: 2, attribute: "level", value: "12"))
            #expect(error("<p list=\"\">a</p>") == .invalidValue(line: 2, attribute: "list", value: ""))
        }

        // MARK: Testo attribuito

        @Test("Nel testo l'elenco è un attributo di tutto il paragrafo, e torna identico nel modello")
        func attributedRoundTrip() {
            let document = Document(blocks: [paragraph("Prima."), paragraph("Uno", "1."), paragraph("Sotto", "a)", level: 2), paragraph("Fine.")])
            let text = document.attributedString().text
            let string = text.string as NSString
            #expect(text.attribute(.listItem, at: 0, effectiveRange: nil) == nil)
            var range = NSRange(location: 0, length: 0)
            #expect(text.attribute(.listItem, at: string.range(of: "Uno").location, effectiveRange: &range) as? String == "1 1.")
            #expect(range == NSRange(location: 7, length: 4), "le tre lettere e l'a capo")
            #expect(text.attribute(.listItem, at: string.range(of: "Sotto").location, effectiveRange: nil) as? String == "2 a)")
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
        }

        @Test("L'ultimo paragrafo, se vuoto, eredita l'elenco del precedente oppure dichiara il proprio")
        func finalEmptyParagraph() {
            // Voce vuota in fondo a un elenco: è ciò che resta andando a capo dopo l'ultima voce.
            let continuing = Document(blocks: [paragraph("Uno", "1."), paragraph("", "1.")])
            var text = continuing.attributedString().text
            #expect(text.string == "Uno\n")
            #expect(text.attribute(.finalParagraphList, at: 3, effectiveRange: nil) == nil)
            #expect(TextStyling.listItem(in: text, at: 4) == ListItem(marker: "1."))
            #expect(Document(attributedString: text, settings: Document()) == continuing)

            // Paragraph vuoto normale dopo un elenco, e voce vuota dopo un paragrafo normale: vanno dichiarati.
            for document in [Document(blocks: [paragraph("Uno", "1."), paragraph("")]), Document(blocks: [paragraph("Testo"), paragraph("", "•")]),
                             Document(blocks: [paragraph("Uno", "1."), paragraph("", "a)", level: 2)])] {
                text = document.attributedString().text
                #expect(text.attribute(.finalParagraphList, at: text.length - 1, effectiveRange: nil) != nil)
                #expect(Document(attributedString: text, settings: Document()) == document)
            }
        }

        @Test("Cambiare l'elenco dei paragrafi toccati dalla selezione")
        func setList() {
            let text = NSMutableAttributedString(attributedString: Document(blocks: [paragraph("Uno"), paragraph("Due"), paragraph("Tre"), paragraph("")]).attributedString().text)
            #expect(text.string == "Uno\nDue\nTre\n")
            func lists() -> [ListItem?] { [0, 4, 8, 12].map { TextStyling.listItem(in: text, at: $0) } }
            let bullet = ListItem(marker: "•")

            // Una selezione da metà del primo a metà del secondo paragrafo li prende entrambi per intero.
            #expect(TextStyling.listEditRange(in: text, for: NSRange(location: 1, length: 4)) == NSRange(location: 0, length: 8))
            TextStyling.setList(in: text, range: NSRange(location: 1, length: 4)) { _ in bullet }
            #expect(lists() == [bullet, bullet, nil, nil])
            // Una selezione che finisce all'inizio di un paragrafo non lo comprende.
            #expect(TextStyling.listEditRange(in: text, for: NSRange(location: 0, length: 4)) == NSRange(location: 0, length: 4))
            // Il cursore in un paragrafo: solo quello. Aumentare il livello conserva il segno.
            TextStyling.setList(in: text, range: NSRange(location: 5, length: 0)) { $0.map { ListItem(marker: $0.marker, level: $0.level + 1) } }
            #expect(lists() == [bullet, ListItem(marker: "•", level: 2), nil, nil])
            // Il cursore nel paragrafo vuoto finale: la modifica cade sull'ultimo a capo, e solo lì.
            #expect(TextStyling.listEditRange(in: text, for: NSRange(location: 12, length: 0)) == NSRange(location: 11, length: 1))
            TextStyling.setList(in: text, range: NSRange(location: 12, length: 0)) { _ in ListItem(marker: "1.") }
            #expect(lists() == [bullet, ListItem(marker: "•", level: 2), nil, ListItem(marker: "1.")])
            // Tutto il documento, paragrafo finale compreso: via gli elenchi.
            TextStyling.setList(in: text, range: NSRange(location: 0, length: 12)) { _ in nil }
            #expect(lists() == [nil, nil, nil, nil])
        }

        @Test("Dopo una modifica ogni paragrafo ha per intero l'elenco del suo primo carattere")
        func repair() {
            let text = NSMutableAttributedString(attributedString: Document(blocks: [paragraph("Uno", "1."), paragraph("Due"), paragraph("")]).attributedString().text)
            #expect(text.string == "Uno\nDue\n")
            // Si cancella l'a capo tra la voce e il paragrafo normale: il paragrafo unito è una voce sola.
            text.replaceCharacters(in: NSRange(location: 3, length: 1), with: "")
            TextStyling.repairLists(in: text, range: NSRange(location: 3, length: 0))
            var range = NSRange(location: 0, length: 0)
            #expect(text.attribute(.listItem, at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length)) as? String == "1 1.")
            #expect(range == NSRange(location: 0, length: 7))
            // Il paragrafo vuoto finale ne è ora la voce successiva; lo si dichiara normale, poi si scrive ancora:
            // la dichiarazione, rimasta su un a capo che non è più l'ultimo, sparisce.
            TextStyling.setList(in: text, range: NSRange(location: 7, length: 0)) { _ in nil }
            #expect(TextStyling.listItem(in: text, at: 7) == nil)
            text.append(NSAttributedString(string: "x\n", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 12)!]))
            TextStyling.repairLists(in: text, range: NSRange(location: 7, length: 2))
            #expect(text.attribute(.finalParagraphList, at: 6, effectiveRange: nil) == nil)
            #expect(TextStyling.listItem(in: text, at: 7) == nil)
            #expect(TextStyling.listItem(in: text, at: 0) == ListItem(marker: "1."))
        }

        @Test("Con il cursore dopo l'ultimo carattere, senza a capo finale, l'elenco va all'ultimo paragrafo")
        func listAtEnd() {
            let text = NSMutableAttributedString(string: "Uno\nVoce", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 12)!])
            TextStyling.setList(in: text, range: NSRange(location: 8, length: 0)) { _ in ListItem(marker: "1.") }
            #expect(TextStyling.listItem(in: text, at: 4) == ListItem(marker: "1."))
            #expect(TextStyling.listItem(in: text, at: 0) == nil)
        }

        // MARK: Pagina

        private func layout(_ blocks: [Block]) -> DocumentLayout {
            PageLayout.layout(Document(blocks: blocks).attributedString().text, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false))
        }

        private func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

        @Test("Il testo di una voce rientra di due corpi per livello; il segno gli sta davanti, staccato di mezzo corpo")
        func placement() {
            let long = String(repeating: "parole che riempiono la riga fino ad andare a capo ", count: 4)
            let page = layout([paragraph("Prima."), paragraph(long, "1."), paragraph("Interna", "a)", level: 2), paragraph("Seconda", "1."), paragraph("Punto", "•")]).pages[0]
            let margin = PageSetup.a4.textRect.minX
            let lines = page.lines, markers = page.markers
            #expect(markers.count == 4)
            #expect(markers.map { Shaper.glyphs(in: $0.line).count } == [2, 2, 2, 1], "«1.», «a)», «2.», «•»")
            #expect(Shaper.glyphs(in: markers[2].line).map { Int($0.id) } == Shaper.glyphIDs(for: "2.", font: try! TestFonts.hoefler(size: 12)))

            // Corpo 12: ogni livello rientra di 24 punti, e il segno finisce 6 punti prima del testo.
            #expect(abs(lines[0].origin.x - margin) < 0.01)
            let first = lines.first { $0.paragraphLocation == markers[0].paragraphLocation }!
            let wrapped = lines.filter { $0.paragraphLocation == markers[0].paragraphLocation }
            #expect(wrapped.count > 1)
            for line in wrapped { #expect(abs(line.origin.x - (margin + 24)) < 0.01, "anche le righe successive rientrano") }
            #expect(abs(markers[0].origin.x + width(markers[0].line) - (margin + 24 - 6)) < 0.01)
            #expect(markers[0].origin.y == first.origin.y, "il segno sta sulla linea di base della prima riga")
            // Secondo livello.
            let inner = lines.first { $0.paragraphLocation == markers[1].paragraphLocation }!
            #expect(abs(inner.origin.x - (margin + 48)) < 0.01)
            #expect(abs(markers[1].origin.x + width(markers[1].line) - (margin + 48 - 6)) < 0.01)
            // La riga di una voce è più stretta della colonna di quanto rientra.
            #expect(wrapped.allSatisfy { width($0.line) <= PageSetup.a4.textRect.width - 24 + 0.01 })
        }

        @Test("Un segno più largo del rientro comincia all'inizio del livello e sposta la prima riga")
        func wideMarker() {
            let long = String(repeating: "parole che riempiono la riga fino ad andare a capo ", count: 4)
            let page = layout([paragraph(long, "(Esempio 1)")]).pages[0]
            let margin = PageSetup.a4.textRect.minX
            let marker = page.markers[0]
            #expect(abs(marker.origin.x - margin) < 0.01)
            #expect(abs(page.lines[0].origin.x - (marker.origin.x + width(marker.line) + 6)) < 0.01)
            #expect(abs(page.lines[1].origin.x - (margin + 24)) < 0.01)
        }

        @Test("Anche una voce vuota, in mezzo o in fondo al testo, mostra il suo segno")
        func emptyItems() {
            let pages = layout([paragraph("Uno", "1."), paragraph("", "1."), paragraph("", "1.")]).pages
            #expect(pages[0].markers.count == 3)
            #expect(Shaper.glyphs(in: pages[0].markers[2].line).map { Int($0.id) } == Shaper.glyphIDs(for: "3.", font: try! TestFonts.hoefler(size: 12)))
            #expect(abs(pages[0].lines[2].origin.x - (PageSetup.a4.textRect.minX + 24)) < 0.01, "il cursore della voce vuota finale sta dove comincerà il testo")
            // Dopo l'elenco, un paragrafo finale vuoto e normale non ha segno.
            #expect(layout([paragraph("Uno", "1."), paragraph("")]).pages[0].markers.count == 1)
        }

        @Test("Nel PDF i segni precedono il testo delle voci")
        func pdf() throws {
            let layout = layout([paragraph("Alfa", "1."), paragraph("Beta", "1."), paragraph("Gamma", "•")])
            let document = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
            let text = (document.string ?? "").replacingOccurrences(of: "\n", with: " ")
            #expect(text.contains("1. Alfa") && text.contains("2. Beta") && text.contains("• Gamma"), "\(text)")
        }

        @Test("Il cursore e il clic ignorano i segni: le posizioni restano quelle del testo")
        func caret() throws {
            let layout = layout([paragraph("Uno", "1."), paragraph("Due", "1.")])
            let margin = PageSetup.a4.textRect.minX
            #expect(abs(try #require(layout.caret(at: 0)).rect.minX - (margin + 24)) < 0.01)
            // Un clic sul segno porta all'inizio della voce.
            let line = layout.pages[0].lines[1]
            #expect(layout.position(at: CGPoint(x: margin + 5, y: line.origin.y + 3), onPage: 0)?.index == 4)
        }
    }
}
