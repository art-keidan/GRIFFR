import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Zone delle fasce e modalità di disposizione", .serialized) @MainActor
struct BandZoneTests {
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { find(type, in: $0) }
    }

    /// Le preferenze toccate dalle prove tornano com'erano.
    private func preserving(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = (defaults.data(forKey: BandLayout.key), defaults.stringArray(forKey: "ToolbarItems"), InterfaceMode.lastChoice)
        BandZone.usesSystemDrag = false
        Motion.duration = 0
        defer {
            Motion.duration = 0.2
            BandZone.usesSystemDrag = true
            BandLayoutEditing.isOn = false
            defaults.set(saved.0, forKey: BandLayout.key)
            defaults.set(saved.1, forKey: "ToolbarItems")
            InterfaceMode.lastChoice = saved.2
        }
        defaults.removeObject(forKey: BandLayout.key)
        try body()
    }

    @MainActor private struct Window {
        let h: EditorHarness
        let window: NSWindow

        init(toolbar: [String]) throws {
            EditorWindowController.setToolbarItems(toolbar, for: .advanced)
            UserDefaults.standard.removeObject(forKey: BandLayout.key)
            h = EditorHarness(paragraphs: ["Una prova."])
            h.editor.setInterfaceMode(.advanced)
            window = try #require(h.editor.window)
            window.setContentSize(NSSize(width: 1800, height: 800))
            window.orderFront(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        }

        func event(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }

        func hit(_ point: NSPoint) -> NSView? { window.contentView?.superview?.hitTest(point) }

        /// Un trascinamento consegnato dalla finestra, da un punto a un altro.
        func drag(from start: NSPoint, to end: NSPoint) {
            window.sendEvent(event(.leftMouseDown, start))
            window.sendEvent(event(.leftMouseDragged, NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)))
            window.sendEvent(event(.leftMouseDragged, end))
            window.sendEvent(event(.leftMouseUp, end))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        }

        func zones(_ band: BandView) -> [BandZone] { band.zones.filter { $0.isLayoutZone } }
    }

    private func center(of view: NSView) -> NSPoint { view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) }
    private func caption(of zone: BandZone) -> NSPoint { zone.convert(NSPoint(x: zone.bounds.midX, y: zone.bounds.height - 5), to: nil) }

    @Test("Spenta la modalità di disposizione nulla si trascina; accesa, una zona si sposta per il nome e l'ordine vale per l'applicazione")
    func zonesMoveOnlyWhileEditing() throws {
        try preserving {
            let w = try Window(toolbar: ["salva", "|", "annulla", "ripeti"])
            defer { w.h.close() }
            let e = w.h.editor
            let band = try #require(e.characterBand)
            let standard = ["family", "weight", "roles", "size", "form", "marks", "language", "symbols"]
            #expect(w.zones(band).map(\.title) == standard)
            let forma = w.zones(band)[4]
            w.drag(from: caption(of: forma), to: w.zones(band)[0].convert(NSPoint(x: 3, y: 5), to: nil))
            #expect(w.zones(band).map(\.title) == standard)

            let editButton = try #require(e.bandControls["disposizione"] as? NSButton)
            #expect(!editButton.isHidden)
            e.toggleLayoutEditing(editButton)
            #expect(BandLayoutEditing.isOn && editButton.state == .on)
            let italic = try #require(e.bandControls["corsivo"])
            let takesClick = w.hit(center(of: italic)) === w.zones(band)[4]
            #expect(takesClick, "accesa, la zona prende il clic al posto del pulsante")
            w.drag(from: caption(of: w.zones(band)[4]), to: w.zones(band)[0].convert(NSPoint(x: 3, y: 5), to: nil))
            let moved = ["form", "family", "weight", "roles", "size", "marks", "language", "symbols"]
            #expect(w.zones(band).map(\.title) == moved)
            #expect(BandLayout.load().bands[BandLayout.Band.character.rawValue].map(\.title) == moved)

            // Una finestra nuova la trova così; l'essenziale tiene l'ordine di sempre.
            let other = EditorHarness(paragraphs: ["Altro."])
            defer { other.close() }
            other.editor.setInterfaceMode(.advanced)
            #expect(try #require(other.editor.characterBand).zones.map(\.title) == moved)
            e.setInterfaceMode(.simple)
            w.h.step()
            #expect(band.zones.map(\.title) == standard)
            #expect(!BandLayoutEditing.isOn, "nell'essenziale la modalità di disposizione si spegne")
            #expect(editButton.isHidden)
        }
    }

    @Test("Un pulsante va in una zona di un'altra fascia; la zona che resta vuota sparisce; la barra lo sa")
    func itemMovesAcrossBands() throws {
        try preserving {
            let w = try Window(toolbar: ["salva", "|", "lorem"])
            defer { w.h.close() }
            let e = w.h.editor
            BandLayoutEditing.isOn = true
            let lorem = try #require(e.bandControls["lorem"])
            let paragraph = try #require(e.paragraphBand)
            let rules = try #require(w.zones(paragraph).first { $0.title == "rules" })
            let target = rules.convert(NSPoint(x: rules.bounds.maxX - 8, y: rules.bounds.midY), to: nil)
            w.drag(from: center(of: lorem), to: target)
            let layout = BandLayout.load()
            #expect(layout.bands[BandLayout.Band.paragraph.rawValue].first { $0.title == "rules" }?.items == ["regoleBanda", "lorem"])
            #expect(layout.bands[BandLayout.Band.tools.rawValue].map(\.items) == [["salva"]], "la zona di Lorem, vuota, non c'è più")
            #expect(EditorWindowController.toolbarItems(for: .advanced) == ["salva"])
            #expect(w.zones(e.toolbarBand).map(\.title) == ["file"])
            // Spenta la modalità, il pulsante fa di nuovo il suo comando dal nuovo posto.
            BandLayoutEditing.isOn = false
            let loremClick = w.hit(center(of: lorem)) === lorem
            #expect(loremClick)
        }
    }

    @Test("Fuori dalle zone un pulsante fa una zona nuova col suo nome; il doppio clic sul nome lo cambia")
    func newZoneAndRename() throws {
        try preserving {
            let w = try Window(toolbar: ["salva", "|", "annulla", "ripeti"])
            defer { w.h.close() }
            let e = w.h.editor
            BandLayoutEditing.isOn = true
            let band = try #require(e.characterBand)
            let superscript = try #require(e.bandControls["apice"])
            // Fra «famiglia» e «peso».
            let famiglia = w.zones(band)[0], peso = w.zones(band)[1]
            let gap = famiglia.convert(NSPoint(x: famiglia.bounds.maxX + (peso.frame.minX - famiglia.frame.maxX) / 2, y: 10), to: nil)
            w.drag(from: center(of: superscript), to: gap)
            #expect(w.zones(band).map(\.title).prefix(3) == ["family", "superscript", "weight"])
            let fresh = w.zones(band)[1]
            #expect(BandLayout.load().bands[BandLayout.Band.character.rawValue][1].items == ["apice"])
            #expect(w.zones(band).first { $0.title == "form" }?.row.arrangedSubviews.count == 3)

            w.window.makeKeyAndOrderFront(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            w.window.sendEvent(w.event(.leftMouseDown, caption(of: fresh)))
            w.window.sendEvent(w.event(.leftMouseUp, caption(of: fresh)))
            w.window.sendEvent(w.event(.leftMouseDown, caption(of: fresh), clicks: 2))
            w.window.sendEvent(w.event(.leftMouseUp, caption(of: fresh), clicks: 2))
            let open = fresh.renameFieldForTests != nil
            #expect(open, "il doppio clic sul nome apre il campo")
            let field = try #require(fresh.renameFieldForTests)
            field.stringValue = "esponenti"
            w.window.makeFirstResponder(nil)
            w.h.step()
            #expect(fresh.renameFieldForTests == nil)
            #expect(fresh.title == "esponenti")
            #expect(BandLayout.load().bands[BandLayout.Band.character.rawValue][1].title == "esponenti")
        }
    }

    @Test("Le lineette stanno a metà fra i pulsanti di due zone, anche quando la zona del peso si allarga; l'ultima zona non ne ha")
    func separatorsFollowZones() throws {
        try preserving {
            let w = try Window(toolbar: ["salva"])
            defer { w.h.close() }
            let e = w.h.editor
            let band = try #require(e.characterBand)
            @MainActor func check(_ label: String) throws {
                band.layoutSubtreeIfNeeded()
                let zones = w.zones(band).filter { !$0.isHidden }
                let peso = try #require(zones.first { $0.title == "weight" })
                let next = try #require(zones.firstIndex { $0 === peso }.map { zones[$0 + 1] })
                let line = band.convert(peso.separator.frame, from: peso)
                // A metà fra i pulsanti, non fra i bordi delle zone.
                let lastButton = band.convert(peso.row.bounds, from: peso.row).maxX
                let firstButton = band.convert(next.row.bounds, from: next.row).minX
                let middle = (lastButton + firstButton) / 2
                #expect(!peso.separator.isHidden && abs(line.midX - middle) <= 0.5, "\(label): \(line.midX) invece di \(middle)")
                #expect(zones.last?.separator.isHidden == true, "\(label): l'ultima zona senza lineetta")
            }
            try check("chiusa")
            let strip = e.faceStrip
            #expect(!strip.disclosureButton.isHidden)
            // Non `performClick`: con la finestra in vista aprirebbe un ciclo degli eventi annidato.
            let disclosure = strip.disclosureButton
            _ = NSApp.sendAction(disclosure.action!, to: disclosure.target, from: disclosure)
            w.h.step()
            #expect(strip.isExpanded)
            try check("espansa")
        }
    }

    @Test("Il romano del cursore del peso cade sulle scanalature, ci scende vicino a una tacca e risale fra due tacche")
    func beamKnobOnNotches() throws {
        let slider = WeightSlider(frame: NSRect(x: 0, y: 0, width: 110, height: 22))
        slider.minValue = 300
        slider.maxValue = 900
        slider.stops = [300, 600, 900]
        for value in [300.0, 600, 900] {
            slider.doubleValue = value
            let cell = try #require(slider.cell as? WeightSlider.BeamCell)
            #expect(abs(cell.knobRect(flipped: slider.isFlipped).midX - slider.centerX(for: value, in: slider.bounds)) < 0.01)
        }
        #expect(slider.centerX(for: 300, in: slider.bounds) == 6 && slider.centerX(for: 900, in: slider.bounds) == 104)
        // Il saltino: vicino a una tacca il romano ci sta sopra ed è giù; fra due tacche è sollevato sulla stanga.
        let cell = try #require(slider.cell as? WeightSlider.BeamCell)
        slider.doubleValue = 612
        #expect(slider.notch == 600 && slider.lift == 0)
        #expect(abs(cell.knobRect(flipped: slider.isFlipped).midX - slider.centerX(for: 600, in: slider.bounds)) < 0.01)
        slider.doubleValue = 450
        #expect(slider.notch == nil && slider.lift == WeightSlider.BeamCell.notchDepth)
        #expect(abs(cell.knobRect(flipped: slider.isFlipped).midX - slider.centerX(for: 450, in: slider.bounds)) < 0.01)
        slider.doubleValue = 900
        #expect(slider.lift == 0)
    }

    @Test("Nell'essenziale niente zone col nome né modalità di disposizione; i gruppi della barra hanno la presa")
    func simpleModeUnchanged() throws {
        try preserving {
            let w = try Window(toolbar: ["salva"])
            defer { w.h.close() }
            w.h.editor.setInterfaceMode(.simple)
            w.h.step()
            let plain = w.h.editor.toolbarBand.zones.allSatisfy(\.isPlain)
            let grips = find(ToolbarGroupView.self, in: w.h.editor.toolbarBand).allSatisfy(\.showsGrip)
            #expect(plain)
            #expect(grips)
            #expect(w.h.editor.bandControls["disposizione"]?.isHidden == true)
        }
    }
}
