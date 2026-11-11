import AppKit
import Testing
@testable import Typesetting

/// Il caso 3 della tappa 4 del modello degli oggetti: due elenchi indipendenti che usano la stessa Lista, e un terzo
/// che riprende il primo. A: 1, 2 · B: 1, 2 · ripresa di A: 3, 4. I numeri restano calcolati, non scritti.
@Suite("Tratti di una Lista: ripartenze e riprese", .serialized)
struct ListSequenceTests {
    private let hoefler = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    private func named(_ text: String, _ name: String = "Examples", id: UUID? = nil, start: Int? = nil,
                       resume: UUID? = nil) -> Block {
        var item = ListItem(listName: name)
        item.sequenceStart = start
        item.sequenceResume = resume
        return .paragraph(Paragraph(list: item, inlines: [.text(TextRun(text, style: hoefler))], id: id))
    }

    private func paragraph(_ text: String) -> Block {
        .paragraph(Paragraph(inlines: [.text(TextRun(text, style: hoefler))]))
    }

    private func document(_ blocks: [Block], ids: Bool = true) -> Document {
        Document(appliesFontTracking: false, usesOpticalMargins: false, lists: ListDefinition.builtIn, blocks: blocks)
    }

    private func layout(_ document: Document) -> DocumentLayout {
        PageLayout.layout(document.attributedString().text, setup: document.pageSetup, options: document.layoutOptions)
    }

    private func markerTexts(_ layout: DocumentLayout) -> [String] {
        let font = try! TestFonts.hoefler(size: 12)
        let byGlyphs = Dictionary(uniqueKeysWithValues: ["(1)", "(2)", "(3)", "(4)", "(5)"].map { ($0, Shaper.glyphIDs(for: $0, font: font)) })
        return layout.pages.flatMap(\.markers).map { marker in
            let glyphs = Shaper.glyphs(in: marker.line).map { Int($0.id) }
            return byGlyphs.first { $0.value == glyphs }?.key ?? "?"
        }
    }

    // MARK: Il valore della voce

    @Test("La ripartenza e la ripresa si conservano nel valore di testo dell'elenco")
    func encoding() throws {
        let first = UUID(), second = UUID()
        var restart = ListItem(listName: "Examples")
        restart.sequenceStart = 2
        #expect(restart.encoded == "@Examples\t- - s2")
        #expect(try #require(ListItem(encoded: restart.encoded)) == restart)

        var resume = ListItem(listName: "Examples")
        resume.sequenceResume = first
        #expect(resume.encoded == "@Examples\t- - r\(first.uuidString)")
        #expect(try #require(ListItem(encoded: resume.encoded)) == resume)

        // Le due scelte non convivono; niente ripartenze da zero o identità non valide; un capoverso che continua la
        // voce non apre né riprende un tratto.
        #expect(ListItem(encoded: "@Examples\t- - s2 r\(second.uuidString)") == nil)
        #expect(ListItem(encoded: "@Examples\t- - c s2") == nil)
        #expect(ListItem(encoded: "@Examples\t- - c r\(first.uuidString)") == nil)
        #expect(ListItem(encoded: "@Examples\t- - s0") == nil)
        #expect(ListItem(encoded: "@Examples\t- - rnonesiste") == nil)
        #expect(ListItem(encoded: "@Examples\t- - x") == nil)
    }

    @Test("La rinomina della Lista conserva ripartenza e ripresa")
    func renaming() {
        let first = UUID()
        var item = ListItem(listName: "Examples")
        item.sequenceResume = first
        item.textIndent = 24
        let text = NSMutableAttributedString(string: "Uno", attributes: [.listItem: item.encoded])
        TextStyling.renameLists(in: text, ["Examples": "Esempi"])
        let renamed = (text.attribute(.listItem, at: 0, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
        #expect(renamed?.listName == "Esempi")
        #expect(renamed?.sequenceResume == first)
        #expect(renamed?.textIndent == 24)
    }

    // MARK: Numerazione

    @Test("A: 1, 2 · B: 1, 2 · ripresa di A: 3, 4; la ripartenza di B non tocca A")
    func restartAndResume() {
        let a = UUID(), b = UUID(), c = UUID()
        var n = ListNumberer(definitions: ListDefinition.builtIn)
        #expect(n.next("Examples", id: a)?.text == "(1)")
        #expect(n.next("Examples")?.text == "(2)")
        #expect(n.next("Examples", id: b, start: 1)?.text == "(1)")
        #expect(n.next("Examples")?.text == "(2)")
        #expect(n.next("Examples", id: c, resume: a)?.text == "(3)")
        #expect(n.next("Examples")?.text == "(4)")
        // Il tratto ripreso è lo stesso: le voci dopo restano sue.
        #expect(n.next("Examples")?.text == "(5)")
        // Una nuova ripartenza di B non cambia A.
        #expect(n.next("Examples", id: UUID(), start: 1)?.text == "(1)")
        #expect(n.next("Examples", id: UUID(), resume: a)?.text == "(6)")
    }

    @Test("La ripartenza può cominciare da un numero scelto; la ripresa senza tratto riparte dalla definizione")
    func startAndOrphan() {
        var n = ListNumberer(definitions: ListDefinition.builtIn)
        #expect(n.next("Examples", id: UUID(), start: 3)?.text == "(3)")
        #expect(n.next("Examples")?.text == "(4)")
        // Un'identità che non ha aperto nessun tratto: la ripresa non trova niente e il capoverso riparte da capo.
        #expect(n.next("Examples", id: UUID(), resume: UUID())?.text == "(1)")
        // Riprendere il tratto di un'altra Lista non vale.
        #expect(n.next("Numbered List", id: UUID())?.text == "1.")
        #expect(n.next("Examples", id: UUID(), resume: UUID())?.text == "(1)")
    }

    @Test("Dopo un'interruzione il numero della Lista superiore non compare: il suo tratto non è più aperto")
    func parentAfterInterruption() {
        var n = ListNumberer(definitions: ListDefinition.builtIn + [
            ListDefinition(name: "Paragrafi", counter: .decimal, prefix: ".", parent: .list("Numbered List"), showsParent: true),
        ])
        #expect(n.next("Numbered List")?.text == "1.")
        #expect(n.next("Paragrafi")?.text == "1.1")
        n.interrupt()
        // Una voce del figlio prima che la superiore riapra un tratto: senza il numero davanti.
        #expect(n.next("Paragrafi")?.text == ".1")
        #expect(n.next("Numbered List")?.text == "1.")
        #expect(n.next("Paragrafi")?.text == "1.1")
    }

    @Test("Una ripresa esplicita continua il tratto anche dopo un'interruzione: la politica ordinaria invece riparte")
    func resumeAfterInterruption() {
        let a = UUID()
        var n = ListNumberer(definitions: ListDefinition.builtIn + [ListDefinition(name: "Comune", counter: .decimal, suffix: ".")])
        #expect(n.next("Comune", id: a)?.text == "1.")
        #expect(n.next("Comune")?.text == "2.")
        n.interrupt()
        // La voce senza scelte riparte, come un elenco comune.
        #expect(n.next("Comune")?.text == "1.")
        // La ripresa esplicita invece continua il tratto di prima.
        #expect(n.next("Comune", id: UUID(), resume: a)?.text == "3.")
        #expect(n.next("Comune")?.text == "4.")
    }

    @Test("Il tratto sa chi lo ha aperto e se è nuovo")
    func segments() throws {
        let a = UUID()
        var n = ListNumberer(definitions: ListDefinition.builtIn)
        let firstCall = n.advance("Examples", id: a)
        let first = try #require(firstCall)
        #expect(first.segment == a && first.isNewSegment)
        let secondCall = n.advance("Examples", id: UUID())
        let second = try #require(secondCall)
        #expect(second.segment == a && !second.isNewSegment)
        let restartCall = n.advance("Examples", id: UUID(), start: 1)
        let restart = try #require(restartCall)
        #expect(restart.segment != a && restart.isNewSegment)
        let resumedCall = n.advance("Examples", id: UUID(), resume: a)
        let resumed = try #require(resumedCall)
        #expect(resumed.segment == a && !resumed.isNewSegment && resumed.mark.text == "(3)")
    }

    // MARK: File

    @Test("Nel file la ripartenza e la ripresa si scrivono nella versione 21, e tornano uguali")
    func fileFormat() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let edited = document([named("A uno", id: a), named("A due"), named("B uno", id: b, start: 1), named("B due"),
                               named("Ripresa uno", id: c, resume: a), named("Ripresa due")])
        let written = DocumentFormat.string(for: edited)
        #expect(written.contains("<document version=\"21\""), "\(written)")
        #expect(written.contains("in-list=\"Examples\" sequence-start=\"1\""), "\(written)")
        #expect(written.contains("id=\"\(b.uuidString)\" in-list=\"Examples\" sequence-start=\"1\""), "\(written)")
        #expect(written.contains("sequence-resume=\"\(a.uuidString)\""), "\(written)")
        #expect(try DocumentFormat.document(from: written) == edited)
        // Senza tratti scelti dall'autore il documento resta alle versioni di prima.
        #expect(DocumentFormat.string(for: document([named("A uno"), named("A due")])).contains("<document version=\"18\""))
    }

    @Test("Errori del file: senza Lista, entrambi gli attributi, numero non valido, identità non valida, versione 20")
    func fileErrors() {
        let lists = "<lists>\n<list name=\"Examples\" counter=\"1\" prefix=\"(\" suffix=\")\" continues=\"on\"/>\n</lists>"
        func error(_ paragraph: String, version: Int = 21) -> DocumentFormatError? {
            do {
                _ = try DocumentFormat.document(from: "<document version=\"\(version)\" font=\"X\" size=\"12\">\n\(lists)\n\(paragraph)\n</document>")
                return nil
            } catch { return error as? DocumentFormatError }
        }
        #expect(error("<p list=\"1.\" sequence-start=\"1\">a</p>") == .missingAttribute(line: 5, attribute: "in-list"))
        #expect(error("<p in-list=\"Examples\" sequence-start=\"2\" sequence-resume=\"\(UUID().uuidString)\">a</p>")
                == .malformed(line: 5, detail: "a paragraph cannot both start and resume a sequence"))
        #expect(error("<p in-list=\"Examples\" continue-previous-item=\"on\" sequence-start=\"1\">a</p>")
                == .malformed(line: 5, detail: "a paragraph that continues the previous item cannot start or resume a sequence"))
        #expect(error("<p in-list=\"Examples\" sequence-start=\"0\">a</p>") == .invalidValue(line: 5, attribute: "sequence-start", value: "0"))
        #expect(error("<p in-list=\"Examples\" sequence-resume=\"nonesiste\">a</p>") == .invalidValue(line: 5, attribute: "sequence-resume", value: "nonesiste"))
        #expect(error("<p in-list=\"Examples\" sequence-start=\"1\">a</p>", version: 20) == .unknownAttribute(line: 5, element: "p", attribute: "sequence-start"))
    }

    @Test("Una scelta di tratto su un elenco senza nome non si scrive nel file: la Lista deve avere un nome")
    func unnamedNotWritten() throws {
        var item = ListItem(marker: "1.")
        item.sequenceStart = 2
        let edited = document([.paragraph(Paragraph(list: item, inlines: [.text(TextRun("Uno", style: hoefler))]))])
        let written = DocumentFormat.string(for: edited)
        #expect(!written.contains("sequence-"), "\(written)")
        #expect(written.contains("<document version=\"18\""))
        let reread = try DocumentFormat.document(from: written)
        let list = try #require(reread.blocks.first.flatMap { block -> ListItem? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.list
        })
        #expect(list.sequenceStart == nil)
    }

    @Test("La ripartenza e la ripresa passano dal testo attribuito e tornano al modello")
    func attributedRoundTrip() {
        let a = UUID(), c = UUID()
        let edited = document([named("A uno", id: a), named("B uno", start: 2), named("Ripresa", id: c, resume: a)])
        let text = edited.attributedString().text
        let start = (text.string as NSString).range(of: "Ripresa").location
        let item = (text.attribute(.listItem, at: start, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
        #expect(item?.sequenceResume == a)
        #expect(Document(attributedString: text, settings: edited.settingsOnly) == edited)
    }

    // MARK: Pagina

    @Test("Nella pagina A è (1) (2), B riparte da (1) e la ripresa di A continua (3) (4)")
    func sequenceLayout() {
        let a = UUID(), b = UUID(), c = UUID()
        let edited = document([paragraph("Prima."), named("A uno", id: a), named("A due"),
                               named("B uno", id: b, start: 1), named("B due"),
                               named("Ripresa uno", id: c, resume: a), named("Ripresa due"), named("A tre")])
        let page = layout(edited).pages[0]
        #expect(markerTexts(layout(edited)) == ["(1)", "(2)", "(1)", "(2)", "(3)", "(4)", "(5)"])
        #expect(page.markers.count == 7)
    }

    @Test("Il tratto ripreso resta lo stesso: il suo numero arriva all'ultima voce, anche dopo la ripresa")
    func sequencesInLayout() throws {
        let a = UUID(), b = UUID()
        let edited = document([named("A uno", id: a), named("A due"), named("B uno", id: b, start: 1),
                               named("Ripresa uno", resume: a), named("A tre")])
        let sequences = layout(edited).sequences
        #expect(sequences.count == 2)
        let first = try #require(sequences.first { $0.identity == a })
        #expect(first.listName == "Examples" && first.firstNumber == 1 && first.lastNumber == 4 && first.items == 4)
        let second = try #require(sequences.first { $0.identity == b })
        #expect(second.firstNumber == 1 && second.lastNumber == 1 && second.items == 1)
    }

    @Test("La ripartenza in cima al testo è utile: la prima voce di un elenco non ha ancora un tratto da riprendere")
    func restartAtStart() {
        let a = UUID()
        let edited = document([named("Uno", id: a, start: 3), named("Due"), paragraph("Testo."), named("Altro")])
        #expect(markerTexts(layout(edited)) == ["(3)", "(4)", "(5)"], "«Examples» prosegue dopo il testo, dal tratto ripreso")
    }
}
