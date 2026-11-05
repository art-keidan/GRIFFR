import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Impostazioni delle equivalenze", .serialized) @MainActor
struct FontRoleSettingsTests {
    @Test("La tabella si salva e si rilegge in JSON; i dati non validi tornano all'automatico")
    func persistence() throws {
        let name = "FontRoleSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let table = FontRoleTable(customizations: [
            .init(family: "Skia", role: .bold, equivalence: FontRoleEquivalence(
                variableInstance: VariableFontInstance(fontName: "Skia-Regular", variations: [AxisValue(tag: "wght", value: 2.4)]))),
        ])
        FontRolePreferences.save(table, to: defaults)
        #expect(defaults.data(forKey: FontRolePreferences.key) != nil)
        #expect(FontRolePreferences.table(from: defaults) == table)
        defaults.set(Data("non JSON".utf8), forKey: FontRolePreferences.key)
        #expect(FontRolePreferences.table(from: defaults) == FontRoleTable())
    }

    @Test("Il pannello modifica assi e ruoli separatamente; Automatico ripristina solo la riga scelta")
    func modelAndSelectiveReset() {
        let model = FontRoleSettingsModel(table: FontRoleTable(), families: ["Skia"], preferredFamily: "Skia")
        var saved = FontRoleTable()
        model.onChange = { saved = $0 }
        model.chooseVariableBase("Skia-Regular")
        model.setAxis("wght", value: 2.3)
        #expect(model.equivalence.variableInstance?.variations == [AxisValue(tag: "wght", value: 2.3)])
        #expect(saved.customization(family: "Skia", role: .bold)?.equivalence == model.equivalence)

        model.selectRole(.italic)
        model.chooseStatic(model.staticFaces.first)
        model.selectRole(.bold)
        model.reset()
        #expect(model.table.customization(family: "Skia", role: .bold) == nil)
        #expect(model.table.customization(family: "Skia", role: .italic) != nil)
        #expect(saved == model.table)
    }

    @Test("Il comando usa le preferenze e Riapplica si annulla in un solo passo")
    func commandReapplyAndUndo() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: FontRolePreferences.key)
        defer {
            if let previous { defaults.set(previous, forKey: FontRolePreferences.key) }
            else { defaults.removeObject(forKey: FontRolePreferences.key) }
        }
        func save(_ face: String) {
            FontRolePreferences.save(FontRoleTable(customizations: [
                .init(family: "Baskerville", role: .bold, equivalence: FontRoleEquivalence(staticFace: face)),
            ]))
        }
        save("Baskerville-SemiBold")
        let h = EditorHarness()
        defer { h.close() }
        let regular = CharacterStyle(fontName: "Baskerville", size: 12)
        h.editor.replaceContent(Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("Grassetto", style: regular))]))]))
        h.document.undoManager?.removeAllActions()
        h.select(0, length: 9)
        h.editor.toggleBold(nil)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")

        save("Baskerville-Bold")
        h.editor.reapplyFontRoles()
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-Bold")
        #expect(h.undoActionName == "Typographic equivalences")
        h.undo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")
    }

    @Test("Cambiare famiglia conserva il grassetto e aggiorna il menu delle facce")
    func familyChangeKeepsBold() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: FontRolePreferences.key)
        defer {
            if let previous { defaults.set(previous, forKey: FontRolePreferences.key) }
            else { defaults.removeObject(forKey: FontRolePreferences.key) }
        }
        FontRolePreferences.save(FontRoleTable(customizations: [
            .init(family: "Baskerville", role: .bold, equivalence: FontRoleEquivalence(staticFace: "Baskerville-SemiBold")),
        ]))
        let h = EditorHarness(paragraphs: ["Grassetto"])
        defer { h.close() }
        func expectBold() throws {
            #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")
            #expect(h.attributed.attribute(.fontRole, at: 0, effectiveRange: nil) as? String == "bold")
            let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
            let face = try #require(h.editor.bandControls["faccia"] as? NSPopUpButton)
            #expect(family.titleOfSelectedItem == "Baskerville")
            #expect(face.itemArray.contains { $0.representedObject as? String == "Baskerville-SemiBold" })
            #expect(face.selectedItem?.representedObject as? String == "Baskerville-SemiBold")
        }
        h.select(0, length: 9)
        h.editor.toggleBold(nil)
        h.step()
        h.editor.inspect(.character)
        h.editor.inspectorForTests.change(.family) { $0.family = "Baskerville" }
        h.step()
        try expectBold()

        h.undo()
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Baskerville")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        try expectBold()

        h.select(0)
        family.selectItem(withTitle: "Hoefler Text")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        family.selectItem(withTitle: "Baskerville")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        h.type("x")
        try expectBold()
    }

    @Test("Cambiare famiglia da tondo a tondo produce solo l'aggiunta della famiglia")
    func regularFamilyChangeDoesNotAddFaceOverride() throws {
        let h = EditorHarness(paragraphs: ["Una parola"])
        defer { h.close() }
        h.select(4, length: 6)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Times New Roman")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        let font = try #require(h.attributed.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == "TimesNewRomanPSMT")
        #expect(h.editor.styleMonitor.additions == ["char. Times New Roman"])
    }
}
