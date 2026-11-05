import AppKit
import Typesetting

/// Un peso offerto nella striscia del carattere, con l'eventuale corsivo dello stesso peso.
struct FontFaceChoice: Equatable {
    let name: String
    let title: String
    let italicName: String?
    let weight: Int

    init(name: String, title: String, italicName: String? = nil, weight: Int = 0) {
        self.name = name
        self.title = title
        self.italicName = italicName
        self.weight = weight
    }
}

/// Il peso di un font variabile: l'asse `wght`, il valore attuale e i punti di attrazione (le istanze con nome del font).
struct VariableWeightChoice: Equatable {
    var range: ClosedRange<Double>
    var value: Double
    var stops: [Double]
    var titles: [String]
}

/// Il cursore del peso di un font variabile, disegnato come la stanga di una bilancia da pavimento: una barra d'acciaio
/// con una scanalatura per ogni punto di attrazione, e il romano blu che vi appoggia la punta. Vicino a un punto si
/// aggancia. Avvisa all'inizio e alla fine del trascinamento, così un trascinamento intero è un solo passo di Annulla.
@MainActor
final class WeightSlider: NSSlider {
    var stops: [Double] = [] { didSet { needsDisplay = true } }
    var onDrag: ((Bool) -> Void)?

    override class var cellClass: AnyClass? {
        get { BeamCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if !(cell is BeamCell) { cell = BeamCell() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Theme.height) }

    /// Il valore agganciato al punto più vicino, se dista meno del 3% dell'asse; altrimenti arrotondato alla decina
    /// (430, 440…), o al centesimo per gli assi con una scala piccola (Skia, da 0,48 a 3,2).
    static func snapped(_ value: Double, to stops: [Double], in range: ClosedRange<Double>) -> Double {
        let width = range.upperBound - range.lowerBound
        if let nearest = stops.min(by: { abs($0 - value) < abs($1 - value) }), abs(nearest - value) <= width * 0.03 { return nearest }
        let step = width >= 100 ? 10.0 : 0.01
        return min(max((value / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    override func mouseDown(with event: NSEvent) {
        onDrag?(true)
        super.mouseDown(with: event)
        onDrag?(false)
    }

    /// Il punto di attrazione su cui il valore si aggancia, se è abbastanza vicino: lì il romano scende nella tacca.
    var notch: Double? {
        let snapped = Self.snapped(doubleValue, to: stops, in: minValue...max(maxValue, minValue))
        return stops.contains(snapped) ? snapped : nil
    }

    /// Quanto il romano è sollevato: zero nella tacca, `BeamCell.notchDepth` appoggiato sulla stanga fra una tacca e
    /// l'altra. Passa da un'altezza all'altra in un decimo di secondo: il saltino.
    private(set) var lift: CGFloat = 0
    private var liftTarget: CGFloat = 0
    private var liftTimer: Timer?

    /// Il romano scende se il valore cade su una tacca, risale se ne esce.
    func updateLift() {
        let target: CGFloat = notch == nil ? BeamCell.notchDepth : 0
        guard target != liftTarget else { return }
        liftTarget = target
        liftTimer?.invalidate()
        guard Motion.duration > 0, window?.isVisible == true else {
            lift = target
            needsDisplay = true
            return
        }
        let start = lift, began = CACurrentMediaTime(), duration = 0.1
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min((CACurrentMediaTime() - began) / duration, 1)
                let eased = t * t * (3 - 2 * t)
                self.lift = start + (target - start) * CGFloat(eased)
                self.needsDisplay = true
                if t >= 1 { self.liftTimer?.invalidate(); self.liftTimer = nil }
            }
        }
        // Anche durante il trascinamento, quando il ciclo degli eventi segue il mouse.
        RunLoop.main.add(timer, forMode: .common)
        liftTimer = timer
    }

    override var doubleValue: Double {
        didSet { updateLift() }
    }

    /// Dove cade un valore, al centro del romano: lo stesso calcolo per le scanalature e per il romano.
    func centerX(for value: Double, in bounds: NSRect) -> CGFloat {
        let knob = BeamCell.knobWidth
        let fraction = maxValue > minValue ? (value - minValue) / (maxValue - minValue) : 0
        return bounds.minX + knob / 2 + CGFloat(min(max(fraction, 0), 1)) * (bounds.width - knob)
    }

    /// La stanga e il romano. Le misure sono dall'alto, in un controllo alto 22 punti.
    final class BeamCell: NSSliderCell {
        static let knobWidth: CGFloat = 12
        static let notchDepth: CGFloat = 3
        private static let beamTop: CGFloat = 12, beamHeight: CGFloat = 7

        override var knobThickness: CGFloat { Self.knobWidth }

        private var slider: WeightSlider? { controlView as? WeightSlider }

        /// Un punto misurato dall'alto, nel verso del controllo.
        private func y(_ fromTop: CGFloat, height: CGFloat, in bounds: NSRect, flipped: Bool) -> CGFloat {
            flipped ? bounds.minY + fromTop : bounds.maxY - fromTop - height
        }

        override func knobRect(flipped: Bool) -> NSRect {
            guard let slider else { return super.knobRect(flipped: flipped) }
            let bounds = slider.bounds
            // Vicino a una tacca il romano ci sta già sopra: il saltino è anche di lato.
            let x = slider.centerX(for: slider.notch ?? doubleValue, in: bounds)
            return NSRect(x: x - Self.knobWidth / 2, y: bounds.minY, width: Self.knobWidth, height: bounds.height)
        }

        override func barRect(flipped: Bool) -> NSRect {
            guard let bounds = slider?.bounds else { return super.barRect(flipped: flipped) }
            return NSRect(x: bounds.minX, y: y(Self.beamTop, height: Self.beamHeight, in: bounds, flipped: flipped),
                          width: bounds.width, height: Self.beamHeight)
        }

        override func drawBar(inside rect: NSRect, flipped: Bool) {
            guard let slider else { return }
            let bounds = slider.bounds
            let beam = barRect(flipped: flipped)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: beam, xRadius: 1.5, yRadius: 1.5).addClip()
            Theme.beam.setFill()
            beam.fill()
            // Un filo chiaro sopra e uno scuro sotto: l'acciaio, senza sfumature.
            Theme.beamTop.setFill()
            NSRect(x: beam.minX, y: y(Self.beamTop, height: 2, in: bounds, flipped: flipped), width: beam.width, height: 2).fill()
            Theme.beamBottom.setFill()
            NSRect(x: beam.minX, y: y(Self.beamTop + Self.beamHeight - 2, height: 2, in: bounds, flipped: flipped), width: beam.width, height: 2).fill()
            // Le scanalature, un triangolino per punto, intagliate nel bordo di sopra.
            Theme.beamNotch.setFill()
            for stop in slider.stops {
                let x = slider.centerX(for: stop, in: bounds)
                let notch = NSBezierPath()
                let top = flipped ? bounds.minY + Self.beamTop : bounds.maxY - Self.beamTop
                let tip = flipped ? top + Self.notchDepth : top - Self.notchDepth
                notch.move(to: NSPoint(x: x - 2.5, y: top))
                notch.line(to: NSPoint(x: x + 2.5, y: top))
                notch.line(to: NSPoint(x: x, y: tip))
                notch.close()
                notch.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        override func drawKnob(_ knobRect: NSRect) {
            guard let slider else { return }
            let flipped = slider.isFlipped
            let bounds = slider.bounds
            let w = Self.knobWidth, x = knobRect.midX
            slider.updateLift()
            // Il romano: il corpo con gli angoli arrotondati in alto, poi la punta, in fondo alla scanalatura o, sollevato,
            // appoggiata sulla stanga.
            let tip = Self.beamTop + Self.notchDepth - slider.lift
            let bodyBottom = tip - 4.5, bodyTop = bodyBottom - 7
            func p(_ dx: CGFloat, _ fromTop: CGFloat) -> NSPoint {
                NSPoint(x: x + dx, y: flipped ? bounds.minY + fromTop : bounds.maxY - fromTop)
            }
            let path = NSBezierPath()
            path.move(to: p(-w / 2, bodyTop + 2))
            path.appendArc(from: p(-w / 2, bodyTop), to: p(0, bodyTop), radius: 2)
            path.appendArc(from: p(w / 2, bodyTop), to: p(w / 2, bodyTop + 2), radius: 2)
            path.line(to: p(w / 2, bodyBottom))
            path.line(to: p(0, tip))
            path.line(to: p(-w / 2, bodyBottom))
            path.close()
            let pressed = isHighlighted
            let color: NSColor = !slider.isEnabled ? Theme.secondary : (pressed ? Theme.activeHoverBottom : Theme.activeBottom)
            color.setFill()
            path.fill()
            if slider.isEnabled {
                Theme.activeTop.setFill()
                NSRect(x: x - w / 2 + 2, y: flipped ? bounds.minY + bodyTop + 1 : bounds.maxY - bodyTop - 1 - 2, width: w - 4, height: 2).fill()
            }
        }

        override func drawTickMarks() {}
    }
}

/// Il grassetto essenziale che, nell'interfaccia avanzata, si espande nei pesi offerti dalla famiglia.
/// Le istanze dei font variabili hanno gli stessi pulsanti; gli altri assi restano negli strumenti dedicati.
@MainActor
final class FontFaceStrip: NSStackView {
    let boldButton: BandButton
    let disclosureButton: BandButton
    /// Al posto dei pesi, per un font variabile con l'asse `wght`.
    let weightSlider = WeightSlider()
    private var variableWeight: VariableWeightChoice?
    private(set) var faceButtons: [BandButton] = []
    private(set) var isExpanded = false

    private let faceTarget: AnyObject
    private let faceAction: Selector
    private var faces: [FontFaceChoice] = []
    private var currentFace: String?
    private var currentIsItalic = false
    private var advanced = false

    init(target: AnyObject, boldAction: Selector, faceAction: Selector, weightAction: Selector? = nil) {
        faceTarget = target
        self.faceAction = faceAction
        boldButton = BandButton(label: "B", help: "Bold (⌘B)", target: target, action: boldAction)
        disclosureButton = BandButton(symbol: "chevron.right", help: "Show all faces", target: nil, action: nil)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 3
        translatesAutoresizingMaskIntoConstraints = false
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleExpansion)
        disclosureButton.minimumWidth = 20
        weightSlider.target = target
        weightSlider.action = weightAction
        weightSlider.isContinuous = true
        weightSlider.controlSize = .small
        weightSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        weightSlider.toolTip = "Variable font weight"
        weightSlider.setAccessibilityLabel("Weight")
        addArrangedSubview(boldButton)
        addArrangedSubview(disclosureButton)
        addArrangedSubview(weightSlider)
        updateVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Aggiorna pesi, stato e aspetto dei campioni senza cambiare la scelta di espansione fatta dall'utente.
    func update(faces newFaces: [FontFaceChoice], currentFace: String?, currentIsItalic: Bool,
                advanced: Bool, boldFont: NSFont?, variableWeight: VariableWeightChoice? = nil) {
        self.variableWeight = variableWeight
        if let variableWeight {
            weightSlider.minValue = variableWeight.range.lowerBound
            weightSlider.maxValue = variableWeight.range.upperBound
            weightSlider.stops = variableWeight.stops
            // Durante il trascinamento il valore lo decide il cursore stesso.
            if !isDraggingWeight { weightSlider.doubleValue = variableWeight.value }
            showWeight(variableWeight.value)
            let instances = zip(variableWeight.stops, variableWeight.titles).filter { !$0.1.isEmpty }
            weightSlider.toolTip = instances.isEmpty
                ? "Variable font weight (the font declares no instances: evenly spaced stops)"
                : "Variable font weight. Font instances: " + instances.map { "\($0.1) \(Self.number($0.0))" }.joined(separator: ", ")
        }
        self.currentFace = currentFace
        self.currentIsItalic = currentIsItalic
        self.advanced = advanced
        boldButton.labelFont = boldFont ?? .systemFont(ofSize: 13, weight: .bold)
        boldButton.invalidateIntrinsicContentSize()
        boldButton.needsDisplay = true
        if faces != newFaces {
            faces = newFaces
            rebuildFaceButtons()
        }
        for (button, face) in zip(faceButtons, faces) {
            let targetName = currentIsItalic ? face.italicName : face.name
            let name = targetName ?? face.name
            button.identifier = NSUserInterfaceItemIdentifier(name)
            button.labelFont = NSFont(name: name, size: 13) ?? .systemFont(ofSize: 13)
            button.isEnabled = targetName != nil
            button.state = targetName == currentFace ? .on : .off
            button.toolTip = "Weight \(face.title)" + (currentIsItalic ? " · italic" : "")
            button.invalidateIntrinsicContentSize()
            button.needsDisplay = true
        }
        updateVisibility()
    }

    private func rebuildFaceButtons() {
        for button in faceButtons {
            removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        faceButtons = faces.map { face in
            let button = BandButton(label: "B", help: "Face \(face.title)", target: faceTarget, action: faceAction)
            button.identifier = NSUserInterfaceItemIdentifier(face.name)
            button.labelFont = NSFont(name: face.name, size: 13) ?? .systemFont(ofSize: 13)
            button.minimumWidth = 24
            button.setAccessibilityIdentifier("faccia.\(face.name)")
            return button
        }
        for button in faceButtons { addArrangedSubview(button) }
    }

    var isDraggingWeight = false

    /// Un peso come si legge: intero se lo è, altrimenti con al più due decimali (0,48 in Skia).
    static func number(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.005 { return String(Int(value.rounded())) }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Il valore del cursore per VoiceOver: il nome dell'istanza, se il peso è proprio su una, altrimenti il numero.
    func showWeight(_ value: Double) {
        guard let variableWeight else { return }
        let title = zip(variableWeight.stops, variableWeight.titles).first { abs($0.0 - value) < 0.001 }?.1
        weightSlider.setAccessibilityValueDescription(title ?? Self.number(value))
    }

    private func updateVisibility() {
        if advanced, variableWeight != nil {
            // Un font variabile con l'asse del peso: il cursore sostituisce i pesi; G resta.
            boldButton.isHidden = false
            disclosureButton.isHidden = true
            for button in faceButtons { button.isHidden = true }
            weightSlider.isHidden = false
            return
        }
        weightSlider.isHidden = true
        let canExpand = advanced && faces.count > 1
        let showFaces = canExpand && isExpanded
        boldButton.isHidden = showFaces
        for button in faceButtons { button.isHidden = !showFaces }
        disclosureButton.isHidden = !canExpand
        disclosureButton.symbolImage = Theme.symbol(isExpanded ? "chevron.left" : "chevron.right",
                                                    isExpanded ? "Collapse faces" : "Show all faces")
        let help = isExpanded ? "Collapse faces" : "Show all faces"
        disclosureButton.toolTip = help
        disclosureButton.setAccessibilityLabel(help)
        disclosureButton.needsDisplay = true
    }

    @objc private func toggleExpansion() {
        isExpanded.toggle()
        // I pesi si aprono e si chiudono scivolando.
        Motion.animate(in: window) { updateVisibility() }
    }
}

/// La zona dei ruoli: quattro caselle (Regular, Italic, Bold, Bold Italic), ciascuna con il peso o la faccia che il ruolo
/// ha per la famiglia del punto. È evidenziata quella del ruolo che la faccia attuale realizza; un clic su una casella dà
/// a quel ruolo la faccia attuale.
@MainActor
final class FontRoleSlots: NSStackView {
    private(set) var slots: [RoleSlot] = []
    var onAssign: ((FontRole) -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 3
        translatesAutoresizingMaskIntoConstraints = false
        slots = FontRole.allCases.map { role in
            let slot = RoleSlot(role: role)
            slot.target = self
            slot.action = #selector(assign(_:))
            addArrangedSubview(slot)
            return slot
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// I valori sotto i nomi dei ruoli e il ruolo della faccia attuale.
    func update(values: [FontRole: String], current: FontRole?) {
        for slot in slots {
            slot.value = values[slot.role] ?? "—"
            slot.state = slot.role == current ? .on : .off
            slot.toolTip = "\(slot.role.displayName): \(slot.value). Click: use the current face as \(slot.role.displayName)"
            slot.invalidateIntrinsicContentSize()
            slot.needsDisplay = true
        }
    }

    @objc private func assign(_ sender: RoleSlot) { onAssign?(sender.role) }
}

/// Una casella della zona dei ruoli: solo la sigla del ruolo (R, I, B, BI), nel tondo, corsivo o nero del sistema. Il
/// peso o la faccia del ruolo sta nel suggerimento.
@MainActor
final class RoleSlot: NSButton {
    let role: FontRole
    var value = "—"
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    static func abbreviation(_ role: FontRole) -> String {
        switch role {
        case .regular: "R"
        case .italic: "I"
        case .bold: "B"
        case .boldItalic: "BI"
        }
    }

    private var slotFont: NSFont {
        let base = NSFont.systemFont(ofSize: 12, weight: role.isBold ? .bold : .regular)
        guard role.isItalic else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.italic)), size: 12) ?? base
    }

    init(role: FontRole) {
        self.role = role
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityLabel("Set as \(role.displayName)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let text = (Self.abbreviation(role) as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: max(ceil(text) + 12, 24), height: Theme.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        Theme.drawBox(bounds, on: on, highlighted: isHighlighted, hovered: isHovered)
        Theme.drawLabel(Self.abbreviation(role), font: slotFont, color: on ? Theme.accentInk : Theme.glyph, in: bounds)
    }
}
