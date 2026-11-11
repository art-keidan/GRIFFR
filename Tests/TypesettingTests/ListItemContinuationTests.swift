import AppKit
import PDFKit
import Testing
@testable import Typesetting

/// Una voce di elenco di più capoversi: il primo ha il segno e il numero, gli altri continuano la voce e non ne
/// consumano un'altra. È il primo caso della tappa 4 del modello degli oggetti (Appunti/MODELLO-OGGETTI.md).
@Suite("Voci di più capoversi", .serialized)
struct ListItemContinuationTests {
    private let hoefler = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    private func paragraph(_ text: String, _ marker: String? = nil, level: Int = 1, continues: Bool = false) -> Block {
        .paragraph(Paragraph(list: marker.map { ListItem(marker: $0, level: level, continuesPreviousItem: continues) },
                             inlines: [.text(TextRun(text, style: hoefler))]))
    }

    private func named(_ text: String, _ name: String, continues: Bool = false) -> Block {
        .paragraph(Paragraph(list: ListItem(listName: name, continuesPreviousItem: continues),
                             inlines: [.text(TextRun(text, style: hoefler))]))
    }

    private func document(_ blocks: [Block], lists: [ListDefinition] = []) -> Document {
        Document(appliesFontTracking: false, usesOpticalMargins: false, lists: lists, blocks: blocks)
    }

    private func layout(_ document: Document) -> DocumentLayout {
        PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
    }

    private func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

    // MARK: Il valore della voce

    @Test("La continuazione si conserva nel valore di testo dell'elenco, con o senza misure")
    func encoding() throws {
        let plain = ListItem(marker: "1.")
        #expect(plain.encoded == "1 1.")
        #expect(ListItem(encoded: plain.encoded) == plain)

        var continuation = ListItem(marker: "1.")
        continuation.continuesPreviousItem = true
        #expect(continuation.encoded == "1 1.\t- - c")
        #expect(try #require(ListItem(encoded: continuation.encoded)) == continuation)

        var measured = ListItem(listName: "Examples", continuesPreviousItem: true)
        measured.textIndent = 24
        measured.markerPosition = 18
        #expect(try #require(ListItem(encoded: measured.encoded)) == measured)
        // Un terzo campo che non è «c» non è una voce.
        #expect(ListItem(encoded: "1 1.\t- - x") == nil)
    }

    @Test("Una voce continua quella prima solo se è della stessa Lista, o dello stesso segno allo stesso livello")
    func sameItem() {
        let examples = ListItem(listName: "Examples")
        #expect(ListItem(listName: "Examples", continuesPreviousItem: true).belongsToSameItem(as: examples))
        #expect(!ListItem(listName: "Subexamples").belongsToSameItem(as: examples))
        let numbered = ListItem(marker: "1.")
        #expect(numbered.belongsToSameItem(as: ListItem(marker: "1.", continuesPreviousItem: true)))
        #expect(!numbered.belongsToSameItem(as: ListItem(marker: "1.", level: 2)))
        #expect(!numbered.belongsToSameItem(as: ListItem(marker: "•")))
        #expect(!numbered.belongsToSameItem(as: examples))
    }

    // MARK: File

    @Test("Nel file la voce di più capoversi si scrive nella versione 20, e torna uguale")
    func fileFormat() throws {
        let withContinuation = document([paragraph("Prima."), paragraph("Uno", "1."), paragraph("Altro capoverso", "1.", continues: true),
                                         paragraph("Due", "1.")])
        let written = DocumentFormat.string(for: withContinuation)
        #expect(written.contains("<document version=\"20\""), "\(written)")
        #expect(written.contains("<p list=\"1.\">Uno</p>"))
        #expect(written.contains("<p list=\"1.\" continue-previous-item=\"on\">Altro capoverso</p>"))
        #expect(written.contains("<p list=\"1.\">Due</p>"))
        #expect(try DocumentFormat.document(from: written) == withContinuation)
        // Un documento senza voci che continuano resta al 18.
        let withoutContinuations = document([paragraph("Uno", "1."), paragraph("Due", "1.")])
        #expect(DocumentFormat.string(for: withoutContinuations).contains("<document version=\"18\""))
    }

    @Test("Nel file una Lista con un nome scrive la continuazione accanto al suo nome")
    func namedFileFormat() throws {
        let document = document([named("Uno", "Examples"), named("Continua", "Examples", continues: true), named("Due", "Examples")],
                                lists: ListDefinition.builtIn)
        let written = DocumentFormat.string(for: document)
        #expect(written.contains("<p in-list=\"Examples\" continue-previous-item=\"on\">Continua</p>"), "\(written)")
        #expect(try DocumentFormat.document(from: written) == document)
    }

    @Test("Errori del file: continuazione senza elenco, valore sbagliato, attributo di una versione che non lo conosce")
    func fileErrors() {
        func error(_ paragraph: String, version: Int = 20) -> DocumentFormatError? {
            do {
                _ = try DocumentFormat.document(from: "<document version=\"\(version)\" font=\"X\" size=\"12\">\n\(paragraph)\n</document>")
                return nil
            } catch { return error as? DocumentFormatError }
        }
        #expect(error("<p continue-previous-item=\"on\">a</p>") == .missingAttribute(line: 2, attribute: "list"))
        #expect(error("<p list=\"1.\" continue-previous-item=\"yes\">a</p>") == .invalidValue(line: 2, attribute: "continue-previous-item", value: "yes"))
        #expect(error("<p list=\"1.\" continue-previous-item=\"on\">a</p>", version: 19) == .unknownAttribute(line: 2, element: "p", attribute: "continue-previous-item"))
    }

    @Test("La continuazione passa dal testo attribuito e torna al modello")
    func attributedRoundTrip() {
        let document = document([paragraph("Prima."), paragraph("Uno", "1."), paragraph("Altro", "1.", continues: true)])
        let text = document.attributedString().text
        let start = (text.string as NSString).range(of: "Altro").location
        #expect(text.attribute(.listItem, at: start, effectiveRange: nil) as? String == "1 1.\t- - c")
        #expect(Document(attributedString: text, settings: document.settingsOnly) == document)
    }

    // MARK: Pagina

    @Test("Un capoverso che continua la voce non ha segno, non consuma un numero e rientra come la voce")
    func continuationLayout() {
        let long = String(repeating: "parole che riempiono la riga fino ad andare a capo ", count: 3)
        let document = document([paragraph("Prima."), paragraph("Uno", "1."), paragraph(long, "1.", continues: true), paragraph("Due", "1.")])
        let text = document.attributedString().text
        let start = (text.string as NSString).range(of: "parole").location
        let page = layout(document).pages[0]
        let margin = PageSetup.a4.textRect.minX
        #expect(page.markers.count == 2)
        #expect(page.markers.map { Shaper.glyphs(in: $0.line).count } == [2, 2], "«1.» e «2.»: la continuazione non ha segno")
        #expect(Shaper.glyphs(in: page.markers[1].line).map { Int($0.id) } == Shaper.glyphIDs(for: "2.", font: try! TestFonts.hoefler(size: 12)))
        let continued = page.lines.filter { $0.paragraphLocation == start }
        #expect(continued.count > 1, "il capoverso va a capo")
        for line in continued { #expect(abs(line.origin.x - (margin + 24)) < 0.01, "anche le righe dopo la prima") }
        #expect(abs(page.markers[0].origin.x + width(page.markers[0].line) - (margin + 24 - 6)) < 0.01)
    }

    @Test("La voce di una Lista con un nome continua senza consumare un numero")
    func namedContinuationLayout() {
        let document = document([named("Uno", "Examples"), named("Continua", "Examples", continues: true), named("Due", "Examples")],
                                lists: ListDefinition.builtIn)
        let page = layout(document).pages[0]
        #expect(page.markers.count == 2)
        #expect(Shaper.glyphs(in: page.markers[1].line).map { Int($0.id) } == Shaper.glyphIDs(for: "(2)", font: try! TestFonts.hoefler(size: 12)))
    }

    @Test("Una continuazione rimasta senza voce è un avviso con il suo capoverso, non un silenzio")
    func orphanWarning() {
        let orphan = document([paragraph("Prima."), paragraph("Uno", "1.", continues: true)])
        #expect(layout(orphan).listWarnings == [ListWarning(kind: .continuationWithoutItem, paragraph: 7, list: "1.")])
        // Con la sua voce, nessun avviso.
        #expect(layout(document([paragraph("Uno", "1."), paragraph("Continua", "1.", continues: true)])).listWarnings.isEmpty)
    }

    @Test("Una continuazione senza la voce prima, o dopo un paragrafo normale, è una voce intera")
    func orphanContinuations() {
        // In cima al testo non c'è niente da continuare: la voce prende il suo segno e il suo numero.
        #expect(layout(document([paragraph("Prima."), paragraph("Uno", "1.", continues: true), paragraph("Due", "1.")])).pages[0].markers.count == 2)
        // Dopo un paragrafo normale la voce di prima è finita: anche questa è una voce nuova.
        let afterText = document([paragraph("Uno", "1."), paragraph("Testo."), paragraph("Altro", "1.", continues: true)])
        #expect(layout(afterText).pages[0].markers.count == 2)
        // Una voce vuota che continua non mostra un segno; quella dopo sì.
        let empty = document([paragraph("Uno", "1."), paragraph("", "1.", continues: true), paragraph("", "1.")])
        #expect(layout(empty).pages[0].markers.count == 2)
    }

    @Test("Le voci interne contano come prima: la continuazione non chiude il livello esterno")
    func nestedContinuation() {
        let long = String(repeating: "parole che riempiono la riga fino ad andare a capo ", count: 2)
        let document = document([paragraph("Uno", "1."), paragraph("Interna", "a)", level: 2),
                                 paragraph(long, "a)", level: 2, continues: true), paragraph("Due", "1.")])
        let text = document.attributedString().text
        let start = (text.string as NSString).range(of: "parole").location
        let page = layout(document).pages[0]
        let margin = PageSetup.a4.textRect.minX
        #expect(page.markers.count == 3)
        let continued = page.lines.filter { $0.paragraphLocation == start }
        for line in continued { #expect(abs(line.origin.x - (margin + 48)) < 0.01, "rientro del secondo livello") }
        #expect(Shaper.glyphs(in: page.markers[2].line).map { Int($0.id) } == Shaper.glyphIDs(for: "2.", font: try! TestFonts.hoefler(size: 12)))
    }

    @Test("La voce che continua su un'altra pagina resta senza segno e rientrata come la voce")
    func continuationAcrossPages() throws {
        let long = String(repeating: "parole che riempiono la riga fino ad andare a capo ", count: 120)
        let document = document([paragraph("Uno", "1."), paragraph(long, "1.", continues: true), paragraph("Due", "1.")])
        let text = document.attributedString().text
        let start = (text.string as NSString).range(of: "parole").location
        let pages = layout(document).pages
        #expect(pages.count > 1, "la voce continua su un'altra pagina")
        let markers = pages.flatMap(\.markers)
        #expect(markers.count == 2, "«1.» sulla voce e «2.» su quella dopo")
        #expect(Shaper.glyphs(in: markers[1].line).map { Int($0.id) } == Shaper.glyphIDs(for: "2.", font: try! TestFonts.hoefler(size: 12)))
        let margin = PageSetup.a4.textRect.minX
        let continued = pages.flatMap(\.lines).filter { $0.paragraphLocation == start }
        #expect(continued.count > 4)
        for line in continued { #expect(abs(line.origin.x - (margin + 24)) < 0.01) }
    }

    @Test("Nel PDF la voce di più capoversi ha un solo segno")
    func pdfContinuation() throws {
        let document = document([paragraph("Uno", "1."), paragraph("Altro capoverso", "1.", continues: true), paragraph("Due", "1.")])
        let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout(document))))
        let text = (pdf.string ?? "").replacingOccurrences(of: "\n", with: " ")
        #expect(text.contains("1. Uno Altro capoverso 2. Due"), "\(text)")
    }
}
