import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Pulsanti delle facce del font", .serialized) @MainActor
struct FontFaceStripTests {
    @Test("La semplice ha solo Grassetto; l'avanzata espande le facce e ogni pulsante applica la sua")
    func expansionAndFaceApplication() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .simple
        let h = EditorHarness(paragraphs: ["Facce"])
        defer { h.close() }
        h.select(0, length: 5)
        let strip = h.editor.faceStrip
        #expect(!strip.boldButton.isHidden)
        #expect(strip.disclosureButton.isHidden)
        #expect(strip.faceButtons.allSatisfy { $0.isHidden })

        h.editor.setInterfaceMode(.advanced)
        h.step()
        #expect(!strip.disclosureButton.isHidden)
        strip.disclosureButton.performClick(nil)
        h.step()
        #expect(strip.isExpanded)
        #expect(strip.boldButton.isHidden)
        #expect(strip.faceButtons.count == 2, "solo i due pesi, non corsivi e ornamenti")
        #expect(Set(strip.faceButtons.compactMap { $0.identifier?.rawValue }) == Set(["HoeflerText-Regular", "HoeflerText-Black"]))
        #expect(strip.faceButtons.allSatisfy { !$0.isHidden })
        for button in strip.faceButtons {
            #expect(button.labelFont.fontName == button.identifier?.rawValue, "il campione usa davvero la sua faccia")
        }

        let bold = try #require(strip.faceButtons.first { $0.identifier?.rawValue == "HoeflerText-Black" })
        bold.performClick(nil)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
        #expect(bold.state == .on)

        h.editor.setInterfaceMode(.simple)
        h.step()
        #expect(!strip.boldButton.isHidden)
        #expect(strip.disclosureButton.isHidden)
        #expect(strip.faceButtons.allSatisfy { $0.isHidden })
    }

    @Test("Il campione di Grassetto usa la faccia assegnata al ruolo")
    func boldSampleUsesRoleEquivalence() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: FontRolePreferences.key)
        let savedMode = InterfaceMode.lastChoice
        defer {
            if let previous { defaults.set(previous, forKey: FontRolePreferences.key) }
            else { defaults.removeObject(forKey: FontRolePreferences.key) }
            InterfaceMode.lastChoice = savedMode
        }
        FontRolePreferences.save(FontRoleTable(customizations: [
            .init(family: "Baskerville", role: .bold, equivalence: FontRoleEquivalence(staticFace: "Baskerville-SemiBold")),
        ]))
        InterfaceMode.lastChoice = .simple
        let h = EditorHarness(paragraphs: ["Grassetto"])
        defer { h.close() }
        h.select(0, length: 9)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Baskerville")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        #expect(h.editor.faceStrip.boldButton.labelFont.fontName == "Baskerville-SemiBold")
        h.editor.faceStrip.boldButton.performClick(nil)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Baskerville-SemiBold")
    }

    @Test("A corsivo attivo le G sono corsive e cambiare peso conserva il corsivo")
    func italicStaysIndependentFromWeight() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Corsivo"])
        defer { h.close() }
        h.select(0, length: 7)
        h.editor.toggleItalic(nil)
        h.step()
        let strip = h.editor.faceStrip
        strip.disclosureButton.performClick(nil)
        h.step()
        #expect(Set(strip.faceButtons.compactMap { $0.identifier?.rawValue }) == Set(["HoeflerText-Italic", "HoeflerText-BlackItalic"]))
        for button in strip.faceButtons {
            #expect(button.labelFont.fontName == button.identifier?.rawValue)
            #expect(TextStyling.traits(ofFace: button.labelFont.fontName)?.italic == true, "ogni campione è corsivo")
        }
        let blackItalic = try #require(strip.faceButtons.first { $0.identifier?.rawValue == "HoeflerText-BlackItalic" })
        blackItalic.performClick(nil)
        h.step()
        let font = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == "HoeflerText-BlackItalic")
        #expect(TextStyling.traits(ofFace: font.fontName)?.italic == true, "il nuovo peso non spegne il corsivo")
        #expect(blackItalic.state == .on)
    }

    @Test("Il popup offre tutte le facce e Grassetto e Corsivo partono da quella scelta")
    func exactFaceChoiceDrivesTheOtherButtons() throws {
        let h = EditorHarness(paragraphs: ["Faccia libera"])
        defer { h.close() }
        h.select(0, length: 12)
        let popup = try #require(h.editor.bandControls["faccia"] as? NSPopUpButton)
        let installed = (NSFontManager.shared.availableMembers(ofFontFamily: "Hoefler Text") ?? []).compactMap { $0[0] as? String }
        #expect(popup.itemArray.compactMap { $0.representedObject as? String } == installed)
        #expect(installed.contains("HoeflerText-Ornaments"), "anche le varianti decorative restano selezionabili")
        let index = try #require(popup.itemArray.firstIndex { $0.representedObject as? String == "HoeflerText-BlackItalic" })
        popup.selectItem(at: index)
        _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-BlackItalic")
        let bold = try #require(h.editor.bandControls["grassetto"] as? NSButton)
        let italic = try #require(h.editor.bandControls["corsivo"] as? NSButton)
        #expect(bold.state == .on && italic.state == .on)

        italic.performClick(nil)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
        #expect(bold.state == .on && italic.state == .off)
        bold.performClick(nil)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Regular")
        #expect(bold.state == .off && italic.state == .off)
    }

    @Test("Il corpo ottico automatico si spegne congelando il disegno e si riaccende seguendo il corpo",
          .enabled(if: NSFont(name: "Merriweather-Regular", size: 12) != nil))
    func opticalSizeSwitch() throws {
        let h = EditorHarness(paragraphs: ["Ottico"])
        defer { h.close() }
        h.select(0, length: 6)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Merriweather")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        let optical = try #require(h.editor.bandControls["corpoOttico"] as? NSButton)
        #expect(!optical.isHidden && optical.state == .on)
        let before = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        let coordinate = try #require(FontVariations.coordinates(of: before)["opsz"])

        optical.performClick(nil)
        h.step()
        #expect(optical.state == .off)
        let frozen = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        let frozenCoordinate = try #require(FontVariations.coordinates(of: frozen)["opsz"])
        #expect(abs(frozenCoordinate - coordinate) < 0.001, "spegnerlo non cambia percettibilmente il disegno attuale")
        #expect(FontVariations.values(of: frozen).contains { $0.tag == "opsz" && abs($0.value - coordinate) < 0.001 })

        let size = try #require(h.editor.bandControls["corpo"])
        size.stringValue = "24"
        _ = NSApp.sendAction(size.action!, to: size.target, from: size)
        h.step()
        let resized = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(resized.pointSize == 24 && FontVariations.coordinates(of: resized)["opsz"] == frozenCoordinate)

        optical.performClick(nil)
        h.step()
        #expect(optical.state == .on)
        let automatic = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(!FontVariations.values(of: automatic).contains { $0.tag == "opsz" })
        #expect(FontVariations.coordinates(of: automatic)["opsz"] == 24)
    }

    @Test("Un font variabile in corsivo: il cursore usa le istanze corsive, e il corsivo conserva il peso",
          .enabled(if: NSFont(name: "Merriweather-Regular", size: 12) != nil))
    func variableFontOffersWeightButtons() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Pesi variabili"])
        defer { h.close() }
        h.select(0, length: 14)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Merriweather")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        let strip = h.editor.faceStrip
        // Il cursore sostituisce i pesi; G mostra il nero delle equivalenze.
        #expect(strip.disclosureButton.isHidden && !strip.weightSlider.isHidden)
        #expect(FontVariations.values(of: strip.boldButton.labelFont as CTFont).contains { $0.tag == "wght" && $0.value == 700 })

        h.editor.toggleItalic(nil)
        h.step()
        // In corsivo i punti sono le istanze corsive: anche Light Italic, malgrado il numero di peso diverso.
        #expect(strip.weightSlider.stops.contains(300) && strip.weightSlider.stops.contains(600) && strip.weightSlider.stops.contains(900))
        strip.weightSlider.doubleValue = 600
        _ = NSApp.sendAction(strip.weightSlider.action!, to: strip.weightSlider.target, from: strip.weightSlider)
        h.step()
        let font = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(FontVariations.values(of: font).contains { $0.tag == "wght" && $0.value == 600 })
        #expect(TextStyling.traits(ofFace: font.postScriptName)?.italic == true)

        // Togliere e rimettere il corsivo non tocca il peso scelto.
        h.editor.toggleItalic(nil)
        h.step()
        let upright = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(FontVariations.values(of: upright).contains { $0.tag == "wght" && $0.value == 600 }, "il peso resta 600")
        #expect(TextStyling.traits(ofFace: upright.postScriptName)?.italic == false)
        h.editor.toggleItalic(nil)
        h.step()
        let italicAgain = try #require(h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
        #expect(FontVariations.values(of: italicAgain).contains { $0.tag == "wght" && $0.value == 600 })
    }

    @Test("Un font senza lettere latine resta quello scelto: niente Helvetica nel documento",
          .enabled(if: NSFont(name: "Muna", size: 12) != nil))
    func fontWithoutLatinStaysChosen() throws {
        let h = EditorHarness(paragraphs: ["Testo latino"])
        defer { h.close() }
        h.select(0, length: 12)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Muna")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName == "Muna")
        #expect(family.titleOfSelectedItem == "Muna")
        // Il menu dice anche quale font si vede davvero per le lettere latine.
        let note = try #require((family as? BandPopUp)?.trailingNote)
        #expect(note.hasPrefix("→ ") && note.count > 2 && !note.contains("Muna"), "nota: \(note)")
        #expect((family as? BandPopUp)?.displayTitle == "Muna")
        // Anche scrivendo altro testo latino il font resta Muna.
        h.select(12, length: 0)
        h.type(" altro")
        #expect((h.attributed.attribute(.font, at: 14, effectiveRange: nil) as? NSFont)?.familyName == "Muna")
    }

    @Test("Il cursore del peso si aggancia ai punti solo da vicino")
    func weightSnapping() {
        let stops = [300.0, 400, 500, 600, 700, 800, 900]
        #expect(WeightSlider.snapped(610, to: stops, in: 300...900) == 600)
        #expect(WeightSlider.snapped(650, to: stops, in: 300...900) == 650)
        #expect(WeightSlider.snapped(895, to: stops, in: 300...900) == 900)
        #expect(WeightSlider.snapped(437.6, to: stops, in: 300...900) == 440, "fuori dagli agganci, la decina")
        #expect(WeightSlider.snapped(1.234, to: [0.48, 3.2], in: 0.48...3.2) == 1.23, "scala piccola: il centesimo")
        #expect(FontFaceStrip.number(440) == "440" && FontFaceStrip.number(0.48) == "0,48")
    }

    @Test("Un font variabile ha il cursore del peso al posto dei pesi; G e ⌘B vanno al nero e tornano al tondo",
          .enabled(if: NSFont(name: "Merriweather-Regular", size: 12) != nil))
    func variableWeightSlider() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Peso variabile"])
        defer { h.close() }
        h.select(0, length: 14)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Merriweather")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        let strip = h.editor.faceStrip
        let slider = strip.weightSlider
        #expect(!slider.isHidden && strip.disclosureButton.isHidden && strip.faceButtons.allSatisfy(\.isHidden))
        #expect(!strip.boldButton.isHidden)
        #expect(slider.stops.contains(600) && slider.stops.contains(900) && slider.stops.count >= 5, "punti: \(slider.stops)")
        func weight() -> Double? {
            (h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).flatMap { FontVariations.coordinates(of: $0 as CTFont)["wght"] }
        }
        slider.doubleValue = 610
        _ = NSApp.sendAction(slider.action!, to: slider.target, from: slider)
        h.step()
        #expect(weight() == 600, "agganciato all'istanza SemiBold")
        #expect(slider.accessibilityValueDescription() == "SemiBold")
        #expect(strip.arrangedSubviews.allSatisfy { $0 is BandButton || $0 === slider }, "accanto al cursore nessun nome")
        slider.doubleValue = 650
        _ = NSApp.sendAction(slider.action!, to: slider.target, from: slider)
        h.step()
        #expect(weight() == 650)
        #expect(h.attributed.attribute(.fontRole, at: 0, effectiveRange: nil) == nil, "un peso a mano è una faccia libera")
        h.editor.toggleBold(nil)
        h.step()
        #expect(weight() == 700, "⌘B porta al nero delle equivalenze")
        #expect(slider.doubleValue == 700)
        h.editor.toggleBold(nil)
        h.step()
        #expect(weight() == 400, "e un secondo ⌘B al tondo")
    }

    @Test("Variabile o istanze: il pulsante c'è solo per le famiglie con tutte e due le forme",
          .enabled(if: FontVariations.font(named: "NotoSans-Regular", size: 12, preferringVariable: true).map(FontVariations.isVariable) == true
                    && NSFont(name: "NotoSans-Regular", size: 12).map { !FontVariations.isVariable($0 as CTFont) } == true))
    func variableToggle() throws {
        let savedMode = InterfaceMode.lastChoice
        defer { InterfaceMode.lastChoice = savedMode }
        InterfaceMode.lastChoice = .advanced
        let h = EditorHarness(paragraphs: ["Due forme"])
        defer { h.close() }
        h.select(0, length: 9)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        let face = try #require(h.editor.bandControls["faccia"] as? NSPopUpButton)
        let variable = try #require(h.editor.bandControls["variabile"] as? NSButton)
        func font() -> CTFont? { (h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { $0 as CTFont } }
        family.selectItem(withTitle: "Noto Sans")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        #expect(family.itemTitles.filter { $0 == "Noto Sans" }.count == 1, "la famiglia compare una volta sola")
        #expect(!variable.isHidden && variable.state == .off && !face.isHidden)
        #expect(font().map(FontVariations.isVariable) == false)

        variable.performClick(nil)
        h.step()
        #expect(font().map(FontVariations.isVariable) == true)
        #expect(variable.state == .on && face.isHidden && !h.editor.faceStrip.weightSlider.isHidden)

        variable.performClick(nil)
        h.step()
        #expect(font().map(FontVariations.isVariable) == false)
        #expect(variable.state == .off && !face.isHidden)

        // Una famiglia solo variabile: niente pulsante, niente menu delle facce, il cursore.
        if NSFont(name: "Merriweather-Regular", size: 12) != nil {
            family.selectItem(withTitle: "Merriweather")
            _ = NSApp.sendAction(family.action!, to: family.target, from: family)
            h.step()
            #expect(variable.isHidden && face.isHidden && !h.editor.faceStrip.weightSlider.isHidden)
        }
    }

    @Test("Il corsivo conserva il peso di una faccia statica intermedia")
    func italicKeepsStaticWeight() throws {
        let h = EditorHarness(paragraphs: ["Semigrassetto"])
        defer { h.close() }
        h.select(0, length: 13)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        family.selectItem(withTitle: "Avenir Next")
        _ = NSApp.sendAction(family.action!, to: family.target, from: family)
        h.step()
        let face = try #require(h.editor.bandControls["faccia"] as? NSPopUpButton)
        let demiBold = try #require(face.itemArray.firstIndex { $0.representedObject as? String == "AvenirNext-DemiBold" })
        face.selectItem(at: demiBold)
        _ = NSApp.sendAction(face.action!, to: face.target, from: face)
        h.step()
        func fontName() -> String? { (h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName }
        #expect(fontName() == "AvenirNext-DemiBold")
        h.editor.toggleItalic(nil)
        h.step()
        #expect(fontName() == "AvenirNext-DemiBoldItalic", "non Bold Italic")
        h.editor.toggleItalic(nil)
        h.step()
        #expect(fontName() == "AvenirNext-DemiBold", "non Regular né Bold")
    }

    @Test("Il menu delle famiglie spunta la famiglia attiva (e il suo gruppo) e si apre su di essa")
    func familyMenuMarksCurrent() throws {
        let saved = FontMenuPreferences.groupsFamilies
        defer { FontMenuPreferences.groupsFamilies = saved }
        FontMenuPreferences.groupsFamilies = true
        let h = EditorHarness(paragraphs: ["Famiglie"])
        defer { h.close() }
        h.select(0, length: 8)
        let family = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        func choose(_ name: String) {
            family.selectItem(withTitle: name)
            _ = NSApp.sendAction(family.action!, to: family.target, from: family)
            h.step()
        }
        choose("Baskerville")
        let plain = try #require(h.editor.familyPositioningItem())
        #expect(plain.title == "Baskerville" && plain.state == .on && plain.submenu == nil)
        let others = family.itemArray.filter { !$0.isHidden && $0 !== plain && $0.state == .on }
        #expect(others.isEmpty, "una spunta sola")

        if NSFont(name: "NotoSans-Regular", size: 12) != nil {
            choose("Noto Sans")
            let group = try #require(h.editor.familyPositioningItem())
            let submenu = try #require(group.submenu, "Noto Sans sta nel gruppo «\(group.title)»")
            #expect(group.state == .on)
            #expect(submenu.items.filter { $0.state == .on }.map(\.title) == ["Noto Sans"])
            #expect(plain.state == .off)
        }
    }
}
