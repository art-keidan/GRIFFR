import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Documento nuovo e pulsante Lorem", .serialized) @MainActor
struct LoremTests {
    @Test("Un documento nuovo è vuoto e scrive nello stile Testo")
    func emptyDocument() {
        let h = EditorHarness()
        defer { h.close() }
        #expect(h.text.isEmpty)
        h.type("Ciao")
        #expect(h.text == "Ciao")
        #expect(h.attributed.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String == "Body")
    }

    @Test("Lorem: circa due pagine in Garamond Premier Pro, con tre titoletti, in un passo di Annulla",
          .enabled(if: NSFont(name: "GaramondPremrPro", size: 12) != nil))
    func lorem() throws {
        let h = EditorHarness()
        defer { h.close() }
        h.editor.insertLorem(nil)
        h.step()
        let text = h.attributed
        #expect(text.length > 4000, "lunghezza: \(text.length), testo: \(text.string.prefix(300))")
        var families: Set<String> = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? NSFont { families.insert(font.familyName ?? "") }
        }
        #expect(families == ["Garamond Premier Pro"])
        let titles = h.editor.currentDocument().sections.map { $0.title.inlines.count }
        #expect(titles.count == 3)
        let pages = try #require(h.editor.pagesView.layout).pages.count
        #expect((2...3).contains(pages), "pagine: \(pages)")
        h.undo()
        #expect(h.text.isEmpty)
    }

    @Test("Il brano di Lorem è inglese corretto per il correttore del Mac",
          .enabled(if: NSSpellChecker.shared.availableLanguages.contains { $0.hasPrefix("en") }))
    func loremSpelling() {
        let language = NSSpellChecker.shared.availableLanguages.first { $0.hasPrefix("en") }
        let pieces = [LoremText.opening] + LoremText.parts.flatMap { [$0.title] + $0.paragraphs }
        for piece in pieces {
            let found = NSSpellChecker.shared.checkSpelling(of: piece, startingAt: 0, language: language, wrap: false,
                                                            inSpellDocumentWithTag: 0, wordCount: nil)
            #expect(found.location == NSNotFound, "\((piece as NSString).substring(with: found.location == NSNotFound ? NSRange() : found))")
        }
    }

    @Test("Il pulsante della correzione ortografica la accende e la spegne")
    func spellingButton() throws {
        let h = EditorHarness()
        defer { h.close() }
        let before = h.editor.checksSpelling
        defer { h.editor.checksSpelling = before }
        let button = try #require(h.editor.bandControls["correzione"] as? NSButton)
        #expect(button.state == (before ? .on : .off))
        h.editor.toggleSpellChecking(button)
        #expect(h.editor.checksSpelling == !before)
        #expect(button.state == (before ? .off : .on))
        h.editor.toggleSpellChecking(button)
        #expect(h.editor.checksSpelling == before)
    }

    /// Per ogni titolo: profondità della sezione, livello nel testo, stile.
    private func headings(_ h: EditorHarness) -> [(depth: Int, level: Int, style: String)] {
        let store = h.editor.store
        return SectionEditing.titles(in: store).filter { $0.range.length > 0 }.map { title in
            (title.depth, (store.attribute(.outlineLevel, at: title.range.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0,
             store.attribute(.paragraphStyleName, at: title.range.location, effectiveRange: nil) as? String ?? "")
        }
    }

    @Test("I titoletti di Lorem hanno lo stile del loro livello; spostati dentro un'altra sezione, lo stile li segue")
    func loremHeadingLevels() throws {
        let h = EditorHarness()
        defer { h.close() }
        h.editor.insertLorem(nil)
        h.step()
        let sheet = h.editor.settings.styles
        let first = try #require(sheet.headingStyles(forLevel: 1).first)
        let second = try #require(sheet.headingStyles(forLevel: 2).first)
        #expect(headings(h).map(\.depth) == [1, 1, 1])
        #expect(headings(h).map(\.level) == [1, 1, 1])
        #expect(headings(h).map(\.style) == [first, first, first])

        let store = h.editor.store
        let titles = SectionEditing.titles(in: store).filter { $0.range.length > 0 }
        let a = store.paragraphID(at: titles[0].range.location), b = store.paragraphID(at: titles[1].range.location)
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(b, .inside, a) }
        #expect(headings(h).map(\.depth) == [1, 2, 1])
        #expect(headings(h).map(\.style) == [first, second, first])
        h.undo()
        #expect(headings(h).map(\.style) == [first, first, first])

        // Inserito dentro una sezione, scende di un livello e prende lo stile del secondo.
        h.editor.apply(TextSelection(caret: h.editor.store.length))
        h.editor.insertLorem(nil)
        h.step()
        #expect(headings(h).map(\.depth) == [1, 1, 1, 2, 2, 2])
        #expect(headings(h).map(\.style) == [first, first, first, second, second, second])
    }
}
