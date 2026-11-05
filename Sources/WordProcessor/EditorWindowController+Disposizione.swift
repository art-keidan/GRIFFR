import AppKit

/// I movimenti dell'interfaccia: zone e pulsanti che si spostano, compaiono o spariscono scivolano al loro posto
/// invece di saltarci.
@MainActor
enum Motion {
    /// Zero spegne i movimenti (le prove che misurano le posizioni subito dopo un cambio).
    static var duration: TimeInterval = 0.2

    static func animate(in window: NSWindow?, _ changes: () -> Void) {
        guard let window, duration > 0, window.isVisible else {
            changes()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            changes()
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}

/// Ciò che si trascina nella modalità di disposizione: una zona intera, o un pulsante.
enum LayoutDragSubject {
    case zone(BandZone)
    case item(NSView)
}

@MainActor
protocol BandLayoutDragging: AnyObject {
    func layoutDragMoved(_ subject: LayoutDragSubject, to windowPoint: NSPoint)
    func layoutDragEnded(_ subject: LayoutDragSubject)
    func renameZone(_ zone: BandZone, to title: String)
}

extension EditorWindowController: BandLayoutDragging {
    /// I controlli delle fasce del carattere e del paragrafo, per nome: la disposizione li mette nelle zone.
    func register(_ items: [String: NSView]) {
        for (id, view) in items { layoutItems[id] = view }
    }

    private var layoutBands: [BandView] { [toolbarBand, characterBand, paragraphBand].compactMap { $0 } }

    /// Il pulsante di un nome: un controllo delle fasce, o un comando della barra (fatto nuovo).
    private func layoutItemView(_ id: String) -> NSView? {
        guard let view = layoutItems[id] ?? toolbarControl(id) else { return nil }
        layoutItemIDs[ObjectIdentifier(view)] = id
        return view
    }

    /// Una zona della disposizione: si trascina e accoglie pulsanti nella modalità di disposizione.
    private func layoutZone(_ zone: BandLayout.Zone) -> BandZone {
        let view = Bands.zone(zone.title, zone.items.compactMap(layoutItemView), spacing: zone.items == ["ruoli"] ? 3 : 5)
        view.isLayoutZone = true
        view.layoutDelegate = self
        return view
    }

    private func interfaceZone() -> BandZone {
        layoutEditButton.isHidden = interfaceMode != .advanced
        return Bands.zone("interface", [layoutEditButton, modeButton])
    }

    private func setRow(of band: BandView, to views: [NSView]) {
        guard let row = band.subviews.first as? NSStackView else { return }
        for view in row.arrangedSubviews { row.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in views { row.addArrangedSubview(view) }
        for view in row.arrangedSubviews where !(view is SpacerView) {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
    }

    /// Rifà le tre fasce di sopra: nella dettagliata secondo la disposizione dell'applicazione, nell'essenziale come
    /// sempre (i gruppi della barra con la loro presa, il carattere e il paragrafo nell'ordine di sempre).
    func composeBands() {
        guard toolbarBand != nil, characterBand != nil, paragraphBand != nil else { return }
        for id in Self.toolbarCommands.map(\.id) { bandControls[id] = nil }
        layoutItemIDs = [:]
        let advanced = interfaceMode == .advanced
        if advanced {
            let layout = BandLayout.load()
            for (band, view) in zip(BandLayout.Band.allCases, layoutBands) {
                var views: [NSView] = layout.bands[band.rawValue].map(layoutZone)
                views.append(Bands.spacer())
                if band == .tools { views.append(interfaceZone()) }
                setRow(of: view, to: views)
            }
        } else {
            setRow(of: toolbarBand, to: toolbarViews() + [Bands.spacer(), interfaceZone()])
            for (view, zones) in [(characterBand!, BandLayout.defaultCharacter), (paragraphBand!, BandLayout.defaultParagraph)] {
                setRow(of: view, to: zones.map { zone in Bands.zone(zone.title, zone.items.compactMap(layoutItemView), spacing: zone.items == ["ruoli"] ? 3 : 5) } + [Bands.spacer()])
            }
        }
        if !advanced { BandLayoutEditing.isOn = false }
        for band in layoutBands { band.setZoned(advanced) }
        layoutEditingChanged()
        refreshBandState()
    }

    /// La disposizione delle fasce com'è ora sullo schermo.
    func currentBandLayout() -> BandLayout {
        BandLayout(bands: layoutBands.map { band in
            band.zones.filter(\.isLayoutZone).map { zone in
                BandLayout.Zone(title: zone.title, items: zone.row.arrangedSubviews.compactMap { layoutItemIDs[ObjectIdentifier($0)] })
            }
        })
    }

    /// Un'altra finestra (o questa) ha cambiato la disposizione.
    func bandLayoutChanged() {
        guard interfaceMode == .advanced, currentBandLayout().normalized() != BandLayout.load() else { return }
        composeBands()
    }

    func layoutEditingChanged() {
        let on = BandLayoutEditing.isOn && interfaceMode == .advanced
        layoutEditButton.state = on ? .on : .off
        for band in layoutBands {
            for zone in band.zones {
                zone.needsDisplay = true
                window?.invalidateCursorRects(for: zone)
            }
        }
    }

    /// Il pulsante della zona «interfaccia»: accende e spegne la modalità di disposizione, in tutte le finestre.
    @objc func toggleLayoutEditing(_ sender: Any?) {
        BandLayoutEditing.isOn.toggle()
    }

    // MARK: Trascinamento

    /// La fascia sotto un punto della finestra; fuori dalle fasce, la più vicina.
    private func band(at windowPoint: NSPoint) -> BandView? {
        layoutBands.min { a, b in
            func distance(_ band: BandView) -> CGFloat {
                let frame = band.convert(band.bounds, to: nil)
                return windowPoint.y < frame.minY ? frame.minY - windowPoint.y : windowPoint.y > frame.maxY ? windowPoint.y - frame.maxY : 0
            }
            return distance(a) < distance(b)
        }
    }

    func layoutDragMoved(_ subject: LayoutDragSubject, to windowPoint: NSPoint) {
        guard let band = band(at: windowPoint), let row = band.subviews.first as? NSStackView else { return }
        let x = row.convert(windowPoint, from: nil).x
        let zones = band.zones.filter(\.isLayoutZone)
        switch subject {
        case .zone(let zone):
            hideDropMarker()
            let others = zones.filter { $0 !== zone }
            let destination = others.firstIndex { x < $0.frame.midX } ?? others.count
            let index = destination < others.count ? row.arrangedSubviews.firstIndex(of: others[destination])!
                : (others.last.flatMap { row.arrangedSubviews.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
            let current = row.arrangedSubviews.firstIndex(of: zone)
            guard current != index, current.map({ $0 + 1 }) != index || zone.superview !== row else { return }
            Motion.animate(in: window) {
                if zone.superview === row, let current, current < index {
                    row.insertArrangedSubview(zone, at: index - 1)
                } else {
                    row.insertArrangedSubview(zone, at: index)
                }
                zone.isPlain = false
            }
        case .item(let item):
            // Dentro una zona (con mezzo spazio di tolleranza ai lati), il pulsante va fra i suoi; fra due zone, o oltre
            // l'ultima, nascerà una zona nuova.
            if let target = zones.first(where: { x >= $0.frame.minX - 2 && x <= $0.frame.maxX + 2 }) {
                hideDropMarker()
                pendingZoneIndex = nil
                let local = target.row.convert(windowPoint, from: nil).x
                let others = target.row.arrangedSubviews.filter { $0 !== item && !$0.isHidden }
                let before = others.first { local < $0.frame.midX }
                let index = before.flatMap { target.row.arrangedSubviews.firstIndex(of: $0) } ?? target.row.arrangedSubviews.count
                let current = target.row.arrangedSubviews.firstIndex(of: item)
                if item.superview === target.row, let current, current == index || current + 1 == index { return }
                Motion.animate(in: window) {
                    if item.superview === target.row, let current, current < index {
                        target.row.insertArrangedSubview(item, at: index - 1)
                    } else {
                        target.row.insertArrangedSubview(item, at: index)
                    }
                    for zone in layoutBands.flatMap(\.zones) { zone.syncHidden() }
                }
            } else {
                let gap = zones.filter { $0.frame.midX < x }.count
                pendingZoneIndex = (band, gap)
                let markerX: CGFloat = gap == 0 ? (zones.first?.frame.minX ?? 0) - row.spacing / 2
                    : gap < zones.count ? (zones[gap - 1].frame.maxX + zones[gap].frame.minX) / 2 : (zones.last?.frame.maxX ?? 0) + row.spacing / 2
                showDropMarker(in: band, atRowX: markerX)
            }
        }
    }

    func layoutDragEnded(_ subject: LayoutDragSubject) {
        hideDropMarker()
        Motion.animate(in: window) {
            if case .item(let item) = subject, let (band, gap) = pendingZoneIndex, let row = band.subviews.first as? NSStackView,
               let id = layoutItemIDs[ObjectIdentifier(item)] {
                let zone = layoutZone(BandLayout.Zone(title: BandLayout.name(of: id), items: []))
                zone.isPlain = false
                let zones = band.zones.filter(\.isLayoutZone)
                let index = gap < zones.count ? row.arrangedSubviews.firstIndex(of: zones[gap])! : (zones.last.flatMap { row.arrangedSubviews.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
                row.insertArrangedSubview(zone, at: index)
                zone.row.addArrangedSubview(item)
                item.setContentHuggingPriority(.required, for: .horizontal)
            }
            pendingZoneIndex = nil
            // Le zone rimaste senza pulsanti spariscono.
            for band in layoutBands {
                for zone in band.zones where zone.isLayoutZone && zone.row.arrangedSubviews.isEmpty {
                    zone.removeFromSuperview()
                }
                band.syncZones()
            }
        }
        currentBandLayout().save()
        refreshBandState()
    }

    func renameZone(_ zone: BandZone, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != zone.title else { return }
        zone.title = name
        currentBandLayout().save()
    }

    private func showDropMarker(in band: BandView, atRowX x: CGFloat) {
        guard let row = band.subviews.first as? NSStackView else { return }
        let marker = layoutDropMarker
        if marker.superview !== band {
            marker.removeFromSuperview()
            band.addSubview(marker)
        }
        let point = band.convert(NSPoint(x: x, y: 0), from: row)
        marker.frame = NSRect(x: point.x - 1.5, y: 4, width: 3, height: band.bounds.height - 8)
        marker.isHidden = false
    }

    private func hideDropMarker() {
        layoutDropMarker.isHidden = true
    }
}

/// Il segno blu dove nascerà una zona nuova.
final class DropMarkerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
