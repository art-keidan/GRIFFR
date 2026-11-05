import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Adobe Kis VF nell'editor: un font variabile con gli assi `opsz` e `wght` e istanze con un nome per i corpi ottici.
@Suite("Font variabili nell'editor (Adobe Kis VF)", .serialized,
       .enabled(if: NSFont(name: "AdobeKisVF-Regular", size: 12) != nil)) @MainActor
struct VariableFontEditorTests {
    private func send(_ control: NSControl, _ h: EditorHarness) {
        _ = NSApp.sendAction(control.action!, to: control.target, from: control)
        h.step()
    }

    private func font(_ h: EditorHarness, at index: Int = 0) -> CTFont {
        h.attributed.attribute(.font, at: index, effectiveRange: nil) as! NSFont as CTFont
    }

    private func axes(_ h: EditorHarness, at index: Int = 0) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: FontVariations.values(of: font(h, at: index)).map { ($0.tag, $0.value) })
    }

    @Test("Famiglia, corpo, nero e corsivo: istanze del testo, la dimensione ottica la regola l'asse")
    func faces() throws {
        let saved = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = saved }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 25)
        let family = try #require(e.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Adobe Kis VF")
        send(family, h)
        // Il tondo da testo, non l'istanza Caption.
        #expect(font(h).postScriptName == "AdobeKisVF-Regular")
        #expect(axes(h)["opsz"] == nil)
        // Il menu dei corpi ottici statici non c'è: la dimensione ottica la regola l'asse.
        #expect(e.bandControls["corpoOtticoScelta"]?.isHidden == true)
        let size = try #require(e.bandControls["corpo"])
        for points in ["20", "8", "36"] {
            size.stringValue = points
            send(size, h)
            #expect(font(h).postScriptName == "AdobeKisVF-Regular", "corpo \(points): nessuno scambio di faccia")
            #expect(axes(h)["opsz"] == nil)
        }
        size.stringValue = "12"
        send(size, h)
        e.toggleBold(nil); h.step()
        #expect(font(h).postScriptName == "AdobeKisVF-Bold")
        #expect(axes(h)["opsz"] == nil)
        e.toggleItalic(nil); h.step()
        #expect(font(h).postScriptName == "AdobeKisVF-BoldItalic")
        #expect(e.styleMonitor.additions.contains("char. bold italic"))
        e.toggleBold(nil); h.step()
        e.toggleItalic(nil); h.step()
        #expect(font(h).postScriptName == "AdobeKisVF-Regular")
    }

    @Test("Dimensione ottica bloccata sul corpo, poi di nuovo automatica")
    func freezeOpticalSize() throws {
        let h = EditorHarness(paragraphs: ["Titolo di prova."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 16)
        let family = try #require(e.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Adobe Kis VF")
        send(family, h)
        let size = try #require(e.bandControls["corpo"])
        size.stringValue = "24"
        send(size, h)
        let toggle = try #require(e.bandControls["corpoOttico"] as? NSButton)
        #expect(toggle.state == .on)
        send(toggle, h)
        #expect(toggle.state == .off)
        #expect(abs((axes(h)["opsz"] ?? 0) - 24) < 0.01)
        size.stringValue = "10"
        send(size, h)
        #expect(abs((axes(h)["opsz"] ?? 0) - 24) < 0.01, "bloccata, non segue il corpo")
        send(toggle, h)
        #expect(axes(h)["opsz"] == nil)
    }

    @Test("Portare le aggiunte nello stile: lo stile prende famiglia, corpo e peso, e il file resta pulito")
    func moveToStyle() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 25)
        let family = try #require(e.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Adobe Kis VF")
        send(family, h)
        let slider = e.faceStrip.weightSlider
        slider.doubleValue = 600
        send(slider, h)
        e.moveStyleAdditionsToStyles(nil); h.step()
        #expect(e.styleMonitor.additions.isEmpty)
        let sheet = e.currentDocument().styles
        let testo = sheet.values(of: "Body")
        // La famiglia ora sta in una formula dello stile, non nel campo storico: conta che lo stile la dichiari e la dia.
        #expect(sheet.style(named: "Body")?.declares(.family) == true)
        let resolved = sheet.resolveCharacter(paragraphStyle: "Body", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
        #expect(FontRoleResolver().family(of: resolved) == "Adobe Kis VF")
        #expect(testo.variations == [AxisValue(tag: "wght", value: 600)])
        // L'altro capoverso dello stesso stile: lo stesso font, senza corpo ottico fissato.
        #expect(font(h, at: 28).postScriptName == "AdobeKisVF-Semibold")
        #expect(axes(h, at: 28)["opsz"] == nil)
        let written = DocumentFormat.string(for: e.currentDocument())
        #expect(!written.contains("variable=\"off\""))
        #expect(!written.contains("opsz"))
    }

    @Test("Il peso 300 di Adobe Kis VF, il suo valore di partenza, va nello stile; il nero tolto torna a 300")
    func weight300() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 44)
        let family = try #require(e.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Adobe Kis VF")
        send(family, h)
        let slider = e.faceStrip.weightSlider
        slider.doubleValue = 300
        send(slider, h)
        #expect(e.styleMonitor.additions.contains("char. weight 300"))
        e.moveStyleAdditionsToStyles(nil); h.step()
        #expect(e.currentDocument().styles.values(of: "Body").variations == [AxisValue(tag: "wght", value: 300)])
        #expect(axes(h, at: 30)["wght"] == 300, "l'altro capoverso dello stile resta a 300")
        h.select(0, length: 5)
        e.toggleBold(nil); h.step()
        #expect(font(h).postScriptName == "AdobeKisVF-Bold")
        e.toggleBold(nil); h.step()
        #expect(axes(h)["wght"] == 300)
        #expect(e.styleMonitor.additions.isEmpty)
    }

    @Test("Regular a 300, poi a 400: lo stile segue il ruolo, il nero tolto torna a 400, il monitor dice «nero»")
    func regularMoves() throws {
        let h = EditorHarness(paragraphs: ["Primo capoverso-composto di prova.", "Secondo capoverso."])
        defer { h.close() }
        let e = h.editor
        h.select(0, length: 53)
        let family = try #require(e.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Adobe Kis VF")
        send(family, h)
        let slider = e.faceStrip.weightSlider
        slider.doubleValue = 300
        send(slider, h)
        e.moveStyleAdditionsToStyles(nil); h.step()
        h.select(0, length: 5)
        e.assignFontRole(.regular); h.step()
        // Lo stile non tiene più il 300 a numero: segue il Regular.
        #expect(e.currentDocument().styles.values(of: "Body").variations == nil)
        #expect(axes(h, at: 40)["wght"] == 300)
        h.select(6, length: 18)
        slider.doubleValue = 400
        send(slider, h)
        e.assignFontRole(.regular); h.step()
        #expect(axes(h, at: 40)["wght"] == 400, "anche l'altro capoverso dello stile")
        #expect(e.styleMonitor.additions.isEmpty)
        e.toggleBold(nil); h.step()
        #expect(e.styleMonitor.additions == ["char. bold"])
        e.toggleBold(nil); h.step()
        #expect(axes(h, at: 8)["wght"] == 400)
        #expect(e.styleMonitor.additions.isEmpty)
        // La × su «nero» riporta al Regular.
        e.toggleBold(nil); h.step()
        e.styleMonitorView.click(pill: 1); h.step()
        #expect(axes(h, at: 8)["wght"] == 400)
        #expect(e.styleMonitor.additions.isEmpty)
    }
}
