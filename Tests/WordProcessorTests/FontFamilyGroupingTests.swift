import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Il menu delle famiglie nella barra, con le famiglie raggruppate per prima parola (Impostazioni › Fonts).
@MainActor
@Suite("Menu delle famiglie raggruppato", .serialized)
struct FontFamilyGroupingTests {
    @Test("Acceso: «Arial Narrow» sta nel sottomenu «Arial», si sceglie da lì e il pulsante la mostra; spento, il menu torna piatto")
    func groupedMenu() throws {
        let saved = UserDefaults.standard.object(forKey: FontMenuPreferences.key)
        defer { UserDefaults.standard.set(saved, forKey: FontMenuPreferences.key) }
        FontMenuPreferences.groupsFamilies = true
        let h = EditorHarness(paragraphs: ["Una prova."])
        defer { h.close() }
        let popup = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        let arial = try #require(popup.itemArray.first { $0.title == "Arial" && $0.submenu != nil })
        let narrow = try #require(arial.submenu?.items.first { $0.title == "Arial Narrow" })
        #expect(!popup.itemArray.contains { !$0.isHidden && $0.submenu == nil && $0.title == "Arial Narrow" }, "nel menu principale non si vede")
        #expect(popup.itemArray.contains { !$0.isHidden && $0.title == "Hoefler Text" }, "una famiglia senza compagne resta sciolta")

        h.select(0, length: 3)
        #expect(narrow.target != nil)
        #expect(NSApp.sendAction(narrow.action!, to: narrow.target, from: narrow))
        h.step()
        let font = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.familyName == "Arial Narrow")
        #expect(popup.titleOfSelectedItem == "Arial Narrow")

        FontMenuPreferences.groupsFamilies = false
        h.step()
        #expect(popup.itemArray.allSatisfy { $0.submenu == nil && !$0.isHidden })
        #expect(popup.titleOfSelectedItem == "Arial Narrow")
    }
}
