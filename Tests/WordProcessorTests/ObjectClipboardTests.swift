import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Taglio e identità degli oggetti", .serialized)
@MainActor
struct ObjectClipboardTests {
    @Test("Il primo incolla dopo Taglia conserva le identità. Il successivo crea una copia.")
    func cutThenCopy() throws {
        let h = EditorHarness(paragraphs: ["Qui", "Dopo"])
        defer { h.close() }
        h.select(3)
        h.editor.insertNote(style: FloatStyle.footnoteName)
        h.type("Nota")
        let object = try #require(FloatingIdentity.occurrences(in: h.attributed).first)
        let originalParagraph = h.editor.store.paragraphID(at: 0).persistent
        let length = NSMaxRange(TextStyling.bodyParagraph(in: h.attributed, at: 0).range)
        h.select(0, length: length)
        #expect(h.menu(#selector(NSText.cut(_:))))
        #expect(FloatingIdentity.occurrences(in: h.attributed).isEmpty)
        h.select(0)
        #expect(h.menu(#selector(NSText.paste(_:))))
        #expect(FloatingIdentity.occurrences(in: h.attributed).first?.identity.id == object.identity.id)
        #expect(h.editor.store.paragraphID(at: 0).persistent == originalParagraph)
        h.select(0)
        #expect(h.menu(#selector(NSText.paste(_:))))
        let all = FloatingIdentity.occurrences(in: h.attributed).map { $0.identity.id }
        #expect(all.count == 2 && Set(all).count == 2)
        #expect(all.last == object.identity.id)
        h.undo()
        #expect(FloatingIdentity.occurrences(in: h.attributed).map { $0.identity.id } == [object.identity.id])
    }

    @Test("Eliminare il bersaglio lascia il rimando irrisolto e Annulla ripristina il numero")
    func deleteReferencedObject() throws {
        let h = EditorHarness(paragraphs: ["Vedi ", "Nota qui."])
        defer { h.close() }
        h.select(h.attributed.length)
        h.editor.insertNote(style: FloatStyle.footnoteName)
        h.type("Contenuto.")
        let target = try #require(FloatingIdentity.occurrences(in: h.attributed).first?.identity.id)
        let reference = ObjectReference(target: target)
        h.select(5)
        h.editor.insert(field: .reference(reference))
        let object = try #require(FloatingIdentity.occurrences(in: h.attributed).first)
        let range = try #require(TextStyling.footnoteSpan(in: h.attributed, anchoredAt: object.location))
        h.select(range.location, length: range.length)
        #expect(h.menu(#selector(NSText.delete(_:))))
        h.editor.layoutPages()
        #expect(h.editor.currentLayout()?.referenceValue(reference) == "(??)")
        h.undo()
        h.editor.layoutPages()
        #expect(h.editor.currentLayout()?.referenceValue(reference) == "1")
        h.redo()
        h.editor.layoutPages()
        #expect(h.editor.currentLayout()?.referenceValue(reference) == "(??)")
    }

    @Test("Annulla Taglia revoca lo spostamento anche se poi si cancella l'oggetto")
    func undoCutThenDelete() throws {
        let h = EditorHarness(paragraphs: ["Qui."])
        defer { h.close() }
        h.select(3)
        h.editor.insertNote(style: FloatStyle.footnoteName)
        h.type("Nota")
        let object = try #require(FloatingIdentity.occurrences(in: h.attributed).first)
        let range = try #require(TextStyling.footnoteSpan(in: h.attributed, anchoredAt: object.location))
        h.select(range.location, length: range.length)
        #expect(h.menu(#selector(NSText.cut(_:))))
        h.undo()
        #expect(FloatingIdentity.occurrences(in: h.attributed).first?.identity.id == object.identity.id)
        h.select(range.location, length: range.length)
        #expect(h.menu(#selector(NSText.delete(_:))))
        h.select(range.location)
        #expect(h.menu(#selector(NSText.paste(_:))))
        let copied = try #require(FloatingIdentity.occurrences(in: h.attributed).first?.identity.id)
        #expect(copied != object.identity.id)
    }
}
