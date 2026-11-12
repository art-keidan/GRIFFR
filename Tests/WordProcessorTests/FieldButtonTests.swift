import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Il pulsante dei campi nel gruppo Insert della barra: le stesse voci di Inserisci › Campo, indirizzate al suo editor.
@Suite("Pulsante dei campi", .serialized) @MainActor
struct FieldButtonTests {
    @Test("Il pulsante dei campi sta dopo Table e il suo menu inserisce un campo in questo documento")
    func insertsField() throws {
        #expect(EditorWindowController.defaultToolbar.firstIndex(of: "campo") == EditorWindowController.defaultToolbar.firstIndex(of: "tabella").map { $0 + 1 })
        #expect(EditorWindowController.defaultSimpleToolbar.contains("campo"))
        #expect(EditorWindowController.zoneTitle(for: ["nota", "campo"]) == "insert")

        let h = EditorHarness(paragraphs: ["Pagina "])
        defer { h.close() }
        let button = try #require(h.editor.bandControls["campo"] as? BandPopUp)
        #expect(button.toolTip == "Insert a field")
        let menu = NSMenu()
        FieldMenuFiller.shared.fill(menu, editor: h.editor)
        let page = try #require(menu.items.first { $0.title == FieldFormula.pageContainingNumber.title })
        #expect(page.target === h.editor && menu.items.last?.title == "Other Field…" && menu.items.last?.target === h.editor)
        h.select(h.text.utf16.count)
        h.editor.perform(page.action, with: page)
        h.step()
        #expect(h.editor.editingText.attribute(.field, at: ("Pagina " as NSString).length, effectiveRange: nil) as? String
                == Field.formula(.pageContainingNumber).encoded)
    }

    @Test("Una barra già scelta riceve il pulsante una volta sola, dopo Table; tolto, resta tolto")
    func introducedOnce() {
        let defaults = UserDefaults.standard
        let key = EditorWindowController.toolbarKey
        let saved = (defaults.stringArray(forKey: key), defaults.stringArray(forKey: key + ".offered"))
        defer {
            defaults.set(saved.0, forKey: key)
            defaults.set(saved.1, forKey: key + ".offered")
        }
        defaults.set(["salva", "|", "nota", "tabella", "|", "nascosti"], forKey: key)
        defaults.removeObject(forKey: key + ".offered")
        #expect(EditorWindowController.toolbarItems(for: .advanced) == ["salva", "|", "nota", "tabella", "campo", "|", "nascosti"])
        // L'autore lo toglie: resta tolto.
        defaults.set(["salva", "|", "nota", "tabella", "|", "nascosti"], forKey: key)
        #expect(EditorWindowController.toolbarItems(for: .advanced) == ["salva", "|", "nota", "tabella", "|", "nascosti"])
        // Anche se lo toglie dalla personalizzazione di una barra mai scelta prima.
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + ".offered")
        defaults.set(["salva"], forKey: key)
        defaults.set(EditorWindowController.introducedToolbarCommands.map(\.id), forKey: key + ".offered")
        #expect(EditorWindowController.toolbarItems(for: .advanced) == ["salva"])
    }
}
