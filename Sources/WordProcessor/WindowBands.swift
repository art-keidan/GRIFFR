import AppKit

/// Le due interfacce della finestra (tappa I.1): la semplice usa le definizioni già pronte, l'avanzata mostra anche
/// l'ispettore e gli strumenti per ritoccare ogni oggetto.
enum InterfaceMode: String {
    case simple, advanced

    private static let key = "InterfaceMode"

    /// L'ultima scelta fatta in una finestra: i documenti nuovi partono da lì.
    static var lastChoice: InterfaceMode {
        get { UserDefaults.standard.string(forKey: key).flatMap(InterfaceMode.init(rawValue:)) ?? .simple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - Colori

/// I colori del disegno approvato (la pagina dei modelli, 17 ottobre 2026), nell'aspetto chiaro e in quello scuro.
@MainActor
enum Theme {
    private static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
    }

    static let window = color(0xeaf3fb, 0x202a36)
    static let bar = color(0xf1f7fd, 0x263341)
    static let side = color(0xeff7fe, 0x24313e)
    static let line = color(0xc6dced, 0x465b6e)
    static let control = color(0xf7fbff, 0x354a5f)
    static let controlBottom = color(0xe7f2fc, 0x304357)
    static let controlLine = color(0x9ac4e9, 0x68849e)
    static let text = color(0x1d1d1f, 0xf2f2f7)
    static let secondary = color(0x5c5c62, 0xb0b0b6)
    static let accent = color(0x0a60d0, 0x4b93f7)
    static let glyph = color(0x1e4fb4, 0x8db3ff)
    static let accentInk = color(0xffffff, 0xffffff)
    static let activeTop = color(0x4c8bf0, 0x3f7de6)
    static let activeBottom = color(0x2463d1, 0x2457b8)
    static let activeHoverBottom = color(0x3474e0, 0x2f69cc)
    static let pressed = color(0xdce7f8, 0x24406a)
    static let pressedBottom = color(0xb7c9e8, 0x24324d)
    static let hoverBottom = color(0xd9e6fb, 0x3a4a68)
    static let hoverLine = color(0x4f80d8, 0x6f9bea)
    static let highlight = color(0xebebee, 0x46464a)
    static let desk = color(0xdcebf7, 0x192532)
    static let ruler = color(0xeaf4fc, 0x273747)
    static let rulerPage = color(0xffffff, 0x3b3b3f)
    static let tick = color(0x9a9aa0, 0x7a7a80)
    static let warn = color(0xa34a00, 0xffb35c)
    /// Le provenienze nell'ispettore: un valore dato qui (arancio) e uno imposto da una regola (verde). Lo stile usa
    /// `accent`, il documento `secondary`.
    static let ownSource = color(0xc25e00, 0xffa04d)
    static let ruleSource = color(0x1f8a78, 0x5fd3bd)
    /// Sulla pagina, che è bianca anche con l'aspetto scuro: il cursore e la selezione nell'azzurro del disegno, non nel
    /// colore d'accento del sistema (che può essere rosso, o rosa per la selezione).
    static let pageCaret = NSColor(srgbRed: 0x0a / 255, green: 0x60 / 255, blue: 0xd0 / 255, alpha: 1)
    static let pageSelection = NSColor(srgbRed: 0xc8 / 255, green: 0xda / 255, blue: 0xf3 / 255, alpha: 1)
    /// Le occorrenze della ricerca sulla pagina.
    static let pageSearchMatch = NSColor(srgbRed: 0xff / 255, green: 0xec / 255, blue: 0x9e / 255, alpha: 1)
    /// I segni della provenienza: il fondo del testo con qualcosa di dato a mano (arancio, come nell'ispettore) e di
    /// quello a cui dà l'aspetto una regola (verde azzurro: l'azzurro della selezione li confonderebbe).
    static let pageManualMark = NSColor(srgbRed: 0xff / 255, green: 0xd9 / 255, blue: 0xb8 / 255, alpha: 1)
    static let pageRuleMark = NSColor(srgbRed: 0xc4 / 255, green: 0xec / 255, blue: 0xe4 / 255, alpha: 1)

    static let font = NSFont.systemFont(ofSize: 12)
    static let smallFont = NSFont.systemFont(ofSize: 11)
    /// Il fondo e il bordo delle zone di una fascia.
    static let zone = color(0xf1f7fd, 0x263341)
    static let zoneLine = color(0xc6dced, 0x465b6e)
    /// La stanga del cursore del peso: acciaio, con le scanalature chiare nell'aspetto chiaro e scure in quello scuro.
    static let beam = color(0xb9c3cc, 0x5d6873)
    static let beamTop = color(0xdde3e8, 0x7d8893)
    static let beamBottom = color(0x8f9aa5, 0x3e4851)
    static let beamNotch = color(0xf3f6f8, 0x2c343c)

    /// I nomi delle zone e delle fasce: maiuscoletto vero del font di sistema, in corpo molto piccolo.
    static func smallCaps(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType, NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector],
            [NSFontDescriptor.FeatureKey.typeIdentifier: kUpperCaseType, NSFontDescriptor.FeatureKey.selectorIdentifier: kUpperCaseSmallCapsSelector],
        ]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static let zoneFont = smallCaps(size: 10)

    /// Un nome in maiuscoletto, un po' spaziato.
    static func smallCapsTitle(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text.lowercased(), attributes: [.font: zoneFont, .foregroundColor: color, .kern: 0.7])
    }
    static let height: CGFloat = 22

    /// La scatola compatta dei controlli: glifi blu, stato attivo pieno e risposte distinte a passaggio e pressione.
    static func drawBox(_ rect: NSRect, on: Bool = false, dashed: Bool = false, highlighted: Bool = false,
                        hovered: Bool = false, border: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        // Piatta: un colore solo, senza rilievo.
        let (fill, edge): (NSColor, NSColor) =
            if highlighted { (pressedBottom, hoverLine) }
            else if on { (hovered ? activeHoverBottom : activeBottom, accent) }
            else if hovered { (hoverBottom, hoverLine) }
            else { (controlBottom, controlLine) }
        fill.setFill()
        path.fill()
        (border ?? edge).setStroke()
        path.lineWidth = 1
        if dashed { path.setLineDash([3, 2], count: 2, phase: 0) }
        path.stroke()
    }

    /// Una piccola freccia verso il basso, per i menu.
    static func drawChevron(at point: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: point.x - 3.5, y: point.y - 1.8))
        path.line(to: NSPoint(x: point.x, y: point.y + 1.8))
        path.line(to: NSPoint(x: point.x + 3.5, y: point.y - 1.8))
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// Un simbolo di sistema nel colore dato.
    static func drawSymbol(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect)
    }

    /// Un'etichetta corta (G, BI, 1,5, Lorem) al centro ottico di `rect`: in verticale è centrata l'altezza delle
    /// maiuscole sulla linea di base, non la riga con lo spazio delle discendenti; in orizzontale il segno disegnato, non
    /// la larghezza tipografica con i suoi margini (che sposterebbe soprattutto le corsive). Con `x` comincia lì.
    static func drawLabel(_ string: String, font: NSFont, color: NSColor, in rect: NSRect, x: CGFloat? = nil) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let originX = x ?? (rect.midX - ink.width / 2 - ink.minX)
        let flipped = NSView.focusView?.isFlipped ?? false
        context.saveGState()
        context.textMatrix = flipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
        context.textPosition = CGPoint(x: originX, y: flipped ? rect.midY + font.capHeight / 2 : rect.midY - font.capHeight / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func symbol(_ name: String, _ help: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: help)?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    }
}

// MARK: - Pulsante

/// Un pulsante del disegno: scatola con il bordo, icona e, dove serve, il nome. Premuto (`state == .on`) in azzurro;
/// tratteggiato se la sua funzione non c'è ancora.
final class BandButton: NSButton {
    var symbolImage: NSImage?
    var label: String
    var labelFont = Theme.font
    var isPlaceholder = false
    var showsChevron = false
    var borderColor: NSColor?
    var labelColor: NSColor?
    var minimumWidth: CGFloat = 24
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    init(symbol: String? = nil, label: String = "", help: String, target: AnyObject?, action: Selector?) {
        self.symbolImage = symbol.flatMap { Theme.symbol($0, help) }
        self.label = label
        super.init(frame: .zero)
        self.title = ""
        self.isBordered = false
        self.target = target
        self.action = action
        self.toolTip = help
        setAccessibilityLabel(help)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// AppKit cambia lo stato di ogni pulsante a ogni clic, anche di quelli momentanei, e qui lo stato si disegna come
    /// «premuto»: un pulsante momentaneo (Regole…, Salva…) resterebbe acceso. La sua cella non lo cambia; quelli che
    /// mostrano uno stato (Grassetto) lo ricevono dal programma, e quelli a interruttore (`pushOnPushOff`) lo cambiano.
    final class Cell: NSButtonCell {
        override var nextState: Int { showsStateBy.isEmpty ? state.rawValue : super.nextState }
    }

    override class var cellClass: AnyClass? {
        get { Cell.self }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let text = label.isEmpty ? 0 : (label as NSString).size(withAttributes: [.font: labelFont]).width
        let icon: CGFloat = symbolImage == nil ? 0 : 15
        let gap: CGFloat = (icon > 0 && text > 0) ? 4 : 0
        let chevron: CGFloat = showsChevron ? 13 : 0
        return NSSize(width: max(minimumWidth, ceil(12 + icon + gap + text + chevron)), height: Theme.height)
    }

    override var isEnabled: Bool { didSet { if !isEnabled { isHovered = false }; needsDisplay = true } }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        Theme.drawBox(bounds, on: on, dashed: isPlaceholder, highlighted: isHighlighted, hovered: isHovered, border: borderColor)
        let ink: NSColor = !isEnabled || isPlaceholder ? Theme.secondary : (labelColor ?? (on ? Theme.accentInk : Theme.glyph))
        let text = label.isEmpty ? 0 : (label as NSString).size(withAttributes: [.font: labelFont]).width
        let icon: CGFloat = symbolImage == nil ? 0 : 15
        let gap: CGFloat = (icon > 0 && text > 0) ? 4 : 0
        let chevron: CGFloat = showsChevron ? 13 : 0
        var x = (bounds.width - (icon + gap + text + chevron)) / 2
        if let symbolImage {
            let size = symbolImage.size
            let ratio = min(15 / max(size.width, 1), 15 / max(size.height, 1))
            let drawn = NSSize(width: size.width * ratio, height: size.height * ratio)
            Theme.drawSymbol(symbolImage, in: NSRect(x: x + (15 - drawn.width) / 2, y: (bounds.height - drawn.height) / 2, width: drawn.width, height: drawn.height),
                             color: ink.withAlphaComponent(isEnabled ? 1 : 0.45))
            x += icon + gap
        }
        if text > 0 {
            // Da solo, il nome sta al centro del segno; accanto a un'icona o a una freccia comincia al suo posto.
            Theme.drawLabel(label, font: labelFont, color: ink.withAlphaComponent(isEnabled ? 1 : 0.45), in: bounds,
                            x: icon > 0 || showsChevron ? x : nil)
            x += text
        }
        if showsChevron { Theme.drawChevron(at: NSPoint(x: x + 8, y: bounds.midY), color: ink) }
    }

    override var isFlipped: Bool { false }

    /// La scatola occupa tutto il controllo: nessun margine invisibile, così gli spazi fra i controlli sono quelli veri.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

// MARK: - Menu a tendina

/// Un menu a tendina del disegno: la scatola con il titolo e la freccia. Per un menu a discesa (`pullsDown`) il titolo è
/// quello dato, o la prima voce del menu.
final class BandPopUp: NSPopUpButton {
    var fixedTitle: String?
    /// Una nota in coda al titolo, in grigio e nel carattere di sistema (per esempio «→ Helvetica»).
    /// Centra in altezza il disegno vero delle lettere del titolo, non le metriche dichiarate dal font: certi font
    /// (Farisi) hanno ascendenti e discendenti così sbilanciati che il nome finirebbe spostato in alto.
    var centersInk = false
    var trailingNote: String? { didSet { if trailingNote != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var titleFont: NSFont?
    var symbolImage: NSImage?
    var preferredWidth: CGFloat?
    var isPlaceholder = false
    /// Falso nella barra di stato: solo il testo e la freccia, senza scatola.
    var drawsBox = true
    var borderColor: NSColor?
    var inkColor: NSColor?
    /// Per il pulsante del colore: una barretta del colore corrente sotto il titolo.
    var swatchColor: NSColor? { didSet { needsDisplay = true } }
    private var filler: MenuFiller?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    /// Il menu (a discesa) si riempie ogni volta che lo si apre; la prima voce è il titolo, che non si vede.
    func attachFiller(_ fill: @escaping (NSMenu) -> Void) {
        let filler = MenuFiller(fill)
        self.filler = filler
        menu?.delegate = filler
        menu?.removeAllItems()
        menu?.addItem(withTitle: "", action: nil, keyEquivalent: "")
    }

    init(width: CGFloat? = nil, pullsDown: Bool = false, help: String) {
        super.init(frame: .zero, pullsDown: pullsDown)
        preferredWidth = width
        isBordered = false
        toolTip = help
        setAccessibilityLabel(help)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// La voce su cui aprire il menu, sotto il pulsante (la famiglia attiva, o il gruppo che la contiene): un menu con
    /// sottomenu non sa da sé dove stia la scelta. Senza, il menu si apre come sempre.
    var positioningItem: (() -> NSMenuItem?)?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let positioningItem, let menu, let item = positioningItem() else { return super.mouseDown(with: event) }
        menu.minimumWidth = bounds.width
        menu.font = font
        // La voce scelta si posa sul titolo del pulsante, come nei menu a comparsa del sistema.
        menu.popUp(positioning: item, at: NSPoint(x: 0, y: isFlipped ? bounds.height - 3 : 3), in: self)
    }

    var displayTitle: String {
        if let fixedTitle { return fixedTitle }
        return pullsDown ? (itemArray.first?.title ?? "") : (titleOfSelectedItem ?? "")
    }

    override var intrinsicContentSize: NSSize {
        if let preferredWidth { return NSSize(width: preferredWidth, height: Theme.height) }
        let text = shownTitle(ink: Theme.text).size().width
        return NSSize(width: ceil(8 + (symbolImage == nil ? 0 : 19) + text + 22), height: Theme.height)
    }

    override var isEnabled: Bool { didSet { if !isEnabled { isHovered = false }; needsDisplay = true } }

    /// Il titolo, con la nota in coda in grigio.
    private func shownTitle(ink: NSColor, paragraphStyle: NSParagraphStyle? = nil) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: titleFont ?? Theme.font, .foregroundColor: ink]
        if let paragraphStyle { attributes[.paragraphStyle] = paragraphStyle }
        let result = NSMutableAttributedString(string: displayTitle, attributes: attributes)
        if let trailingNote {
            attributes[.font] = Theme.font
            attributes[.foregroundColor] = Theme.secondary
            result.append(NSAttributedString(string: "  " + trailingNote, attributes: attributes))
        }
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if drawsBox {
            Theme.drawBox(bounds, dashed: isPlaceholder, highlighted: isHighlighted, hovered: isHovered, border: borderColor)
        } else if isHighlighted || isHovered {
            Theme.highlight.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        }
        let ink = isEnabled && !isPlaceholder ? (inkColor ?? Theme.text) : Theme.secondary
        var x: CGFloat = 8
        if let symbolImage {
            Theme.drawSymbol(symbolImage, in: NSRect(x: x, y: (bounds.height - 14) / 2, width: 15, height: 14),
                             color: isEnabled && !isPlaceholder ? (inkColor ?? Theme.glyph) : Theme.secondary)
            x += 19
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont ?? Theme.font, .foregroundColor: ink, .paragraphStyle: style]
        let title = shownTitle(ink: ink, paragraphStyle: style)
        let height = (displayTitle as NSString).size(withAttributes: attributes).height
        let titleRect = NSRect(x: x, y: (bounds.height - height) / 2 - (swatchColor == nil ? 0 : 2), width: bounds.width - x - 20, height: height)
        if centersInk, let context = NSGraphicsContext.current?.cgContext {
            // Core Text vuole il colore come CGColor: si aggiunge accanto a quello di AppKit.
            let coloured = NSMutableAttributedString(attributedString: title)
            coloured.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: coloured.length)) { value, range, _ in
                if let color = value as? NSColor {
                    coloured.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: color.cgColor, range: range)
                }
            }
            let line = CTLineCreateWithAttributedString(coloured)
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
                .font: Theme.font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cgColor]))
            let shown = CTLineCreateTruncatedLine(line, Double(titleRect.width), .end, ellipsis) ?? line
            let inkBounds = CTLineGetImageBounds(shown, context)
            context.saveGState()
            if isFlipped {
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
            }
            context.textMatrix = .identity
            let baseline = inkBounds.isEmpty || inkBounds.isNull ? bounds.height / 2 - 4 : (bounds.height - inkBounds.height) / 2 - inkBounds.minY
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(shown, context)
            context.restoreGState()
        } else {
            title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if let swatchColor {
            let width = (displayTitle as NSString).size(withAttributes: attributes).width
            swatchColor.setFill()
            NSRect(x: x - 2, y: titleRect.maxY - 2, width: max(width + 4, 12), height: 3).fill()
        }
        Theme.drawChevron(at: NSPoint(x: bounds.width - 11, y: bounds.midY), color: ink)
    }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func setTitle(_ string: String) {
        super.setTitle(string)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func select(_ item: NSMenuItem?) {
        super.select(item)
        needsDisplay = true
    }

    override func selectItem(at index: Int) {
        super.selectItem(at: index)
        needsDisplay = true
    }
}

/// Riempie un menu quando lo si apre, dopo la voce del titolo.
final class MenuFiller: NSObject, NSMenuDelegate {
    let fill: (NSMenu) -> Void

    init(_ fill: @escaping (NSMenu) -> Void) {
        self.fill = fill
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.removeAllItems()
            menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            fill(menu)
        }
    }
}

// MARK: - Pulsanti uniti

/// Un gruppo di pulsanti uniti (allineamento, interlinea, Semplice/Avanzata): al più uno premuto.
final class BandSegments: NSControl {
    struct Segment {
        var label: String?
        var image: NSImage?
        var help: String
    }

    var segments: [Segment] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var selectedSegment: Int? { didSet { needsDisplay = true } }
    var segmentPadding: CGFloat = 7
    /// Il segmento sotto il mouse.
    private var hoveredSegment: Int? { didSet { if hoveredSegment != oldValue { needsDisplay = true } } }
    /// Chiamata quando si preme un segmento: si riceve il suo indice.
    var onSelect: ((Int) -> Void)?

    init(_ segments: [Segment], help: String) {
        self.segments = segments
        super.init(frame: .zero)
        toolTip = help
        setAccessibilityLabel(help)
        setAccessibilityRole(.radioGroup)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredSegment = isEnabled ? frames().firstIndex { $0.contains(point) } : nil
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoveredSegment = nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func width(of segment: Segment) -> CGFloat {
        let text = segment.label.map { ($0 as NSString).size(withAttributes: [.font: Theme.font]).width } ?? 0
        let icon: CGFloat = segment.image == nil ? 0 : 14
        return max(28, ceil(icon + text + 2 * segmentPadding))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: segments.reduce(0) { $0 + width(of: $1) }, height: Theme.height)
    }

    private func frames() -> [NSRect] {
        var x: CGFloat = 0
        return segments.map { segment in
            let w = width(of: segment)
            defer { x += w }
            return NSRect(x: x, y: 0, width: w, height: bounds.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        Theme.controlBottom.setFill()
        outline.fill()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        for (index, frame) in frames().enumerated() {
            let on = index == selectedSegment
            let hovered = index == hoveredSegment
            if on {
                (hovered ? Theme.activeHoverBottom : Theme.activeBottom).setFill()
                frame.fill()
            } else if hovered {
                Theme.hoverBottom.setFill()
                frame.fill()
            }
            if index > 0 {
                Theme.controlLine.setFill()
                NSRect(x: frame.minX, y: 0, width: 1, height: bounds.height).fill()
            }
            let ink = isEnabled ? (on ? Theme.accentInk : Theme.glyph) : Theme.secondary
            let segment = segments[index]
            if let image = segment.image {
                Theme.drawSymbol(image, in: NSRect(x: frame.midX - 7, y: frame.midY - 7, width: 14, height: 14), color: ink)
            } else if let label = segment.label {
                Theme.drawLabel(label, font: Theme.font, color: ink, in: frame)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        Theme.controlLine.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = frames().firstIndex(where: { $0.contains(point) }) else { return }
        press(index)
    }

    /// Preme un segmento, come un clic.
    func press(_ index: Int) {
        guard segments.indices.contains(index) else { return }
        selectedSegment = index
        onSelect?(index)
    }
}

// MARK: - Casella del corpo

/// Il corpo: un numero che si scrive, con la freccia che apre i corpi consueti.
final class BandSizeBox: NSControl, NSTextFieldDelegate {
    private let field = NSTextField()
    private let sizes = [9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.font
        field.textColor = Theme.text
        field.target = self
        field.action = #selector(fieldCommitted(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = "Size"
        setAccessibilityLabel("Size")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 58, height: Theme.height) }

    override var isFlipped: Bool { true }

    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
    }
    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        Theme.drawBox(bounds, hovered: isHovered)
        Theme.drawChevron(at: NSPoint(x: bounds.width - 10, y: bounds.midY), color: Theme.text)
    }

    @objc private func fieldCommitted(_ sender: Any?) { sendAction(action, to: target) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x > bounds.width - 18 else { return super.mouseDown(with: event) }
        let menu = NSMenu()
        for size in sizes {
            let item = menu.addItem(withTitle: "\(size)", action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.state = field.stringValue == "\(size)" ? .on : .off
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        field.stringValue = sender.title
        sendAction(action, to: target)
    }
}

// MARK: - Fasce

/// I mattoni delle fasce sopra il testo e della barra di stato.
@MainActor
enum Bands {
    /// Una fascia orizzontale: i controlli in fila, con il fondo e una riga sotto. Lo spazio fra due controlli è sempre
    /// lo stesso; quello che avanza va tutto nello spazio elastico (o, se non c'è, in fondo a destra).
    static func band(_ views: [NSView], height: CGFloat = 38, spacing: CGFloat = 6) -> BandView {
        var views = views
        if !views.contains(where: { $0 is SpacerView }) { views.append(spacer()) }
        let row = BandRow(views: views)
        row.orientation = .horizontal
        row.spacing = spacing
        row.alignment = .centerY
        row.distribution = .fill
        for view in views where !(view is SpacerView) {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        let band = BandView()
        band.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        // La fila è la prima sottovista: chi lavora sulla fascia la cerca lì.
        band.addSubview(row)
        band.plainHeight = height
        let heightConstraint = band.heightAnchor.constraint(equalToConstant: height)
        let center = row.centerYAnchor.constraint(equalTo: band.centerYAnchor)
        band.heightConstraint = heightConstraint
        band.rowCenter = center
        // La fila riempie la fascia ma non allarga la finestra: sotto la priorità con cui la finestra tiene la sua misura,
        // così un font con più facce (Lorem in Garamond) non la fa crescere da sola.
        let trailing = row.trailingAnchor.constraint(equalTo: band.trailingAnchor, constant: -12)
        trailing.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        NSLayoutConstraint.activate([
            heightConstraint,
            row.leadingAnchor.constraint(equalTo: band.leadingAnchor, constant: 12),
            trailing,
            center,
        ])
        return band
    }

    /// Una zona: controlli imparentati in un riquadro, con il nome sotto.
    static func zone(_ title: String, _ views: [NSView], spacing: CGFloat = 5) -> BandZone {
        BandZone(title: title, views: views, spacing: spacing)
    }

    /// Una sottile riga verticale tra gruppi di pulsanti.
    static func separator() -> NSView {
        let line = SeparatorView()
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 9), line.heightAnchor.constraint(equalToConstant: 22)])
        return line
    }

    /// Uno spazio elastico che spinge a destra ciò che segue.
    static func spacer() -> NSView {
        let view = SpacerView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    static func label(_ text: String) -> NSTextField {
        let label = BandLabel(labelWithString: text)
        label.textColor = Theme.secondary
        label.font = Theme.smallFont
        return label
    }
}

/// Un'etichetta di fascia, senza margini invisibili.
final class BandLabel: NSTextField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

/// Un'etichetta che risponde al clic: i conteggi della barra di stato, che aprono l'elenco completo.
final class ClickableLabel: NSTextField {
    var onClick: (() -> Void)?
    /// Il colore a riposo; al passaggio del mouse il testo prende l'azzurro dei glifi, come i pulsanti delle barre.
    private var restingColor: NSColor?
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        guard onClick != nil, restingColor == nil else { return }
        restingColor = textColor
        textColor = Theme.glyph
    }
    override func mouseExited(with event: NSEvent) {
        guard let restingColor else { return }
        textColor = restingColor
        self.restingColor = nil
    }
}

/// Lo spazio elastico di una fascia.
final class SpacerView: NSView {}

/// La fila di una fascia: a ogni disposizione dice alle zone dove mettere la loro lineetta, che c'è solo fra due zone
/// vicine (non dopo l'ultima, né accanto allo spazio vuoto): a metà fra l'ultimo pulsante di una e il primo dell'altra,
/// anche quando il nome di una zona, più largo dei suoi pulsanti, li fa rientrare.
final class BandRow: NSStackView {
    override func layout() {
        super.layout()
        let visible = arrangedSubviews.filter { !$0.isHidden }
        for (index, view) in visible.enumerated() {
            guard let zone = view as? BandZone else { continue }
            guard let next = index + 1 < visible.count ? visible[index + 1] as? BandZone : nil, !zone.isPlain, !next.isPlain else {
                zone.separatorX = nil
                continue
            }
            let lastButton = zone.frame.maxX - zone.contentInset, firstButton = next.frame.minX + next.contentInset
            zone.separatorX = (lastButton + firstButton) / 2 - zone.frame.minX
        }
    }
}

/// La lineetta di una zona: sta fuori dal suo bordo destro, a metà dello spazio che la separa dalla zona dopo, e si
/// sposta con lei (anche mentre scivola o si allarga).
final class ZoneSeparator: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.zoneLine.setFill()
        bounds.fill()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.line.setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Gruppi di strumenti spostabili

/// La presa zigrinata a sinistra di un gruppo, come nelle barre staccabili di Word 98.
private final class ToolbarGripView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.secondary.withAlphaComponent(0.65).setStroke()
        for x in [3.5, 6.5, 9.5] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 6))
            path.line(to: NSPoint(x: x, y: bounds.height - 6))
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.stroke()
        }
    }
}

/// Un gruppo della barra: i suoi comandi restano insieme e si spostano trascinando la presa a sinistra. La barra
/// conserva l'ordine quando il trascinamento finisce; il documento e il testo non partecipano all'operazione.
@MainActor
final class ToolbarGroupView: NSView {
    let commands: [String]
    /// Il gruppo trascinato è arrivato a questo punto (coordinate della finestra).
    var onDrag: ((ToolbarGroupView, NSPoint) -> Void)?
    var onFinish: ((ToolbarGroupView) -> Void)?
    private var dragging = false { didSet { needsDisplay = true } }
    private let grip = ToolbarGripView()
    private var gripWidth: NSLayoutConstraint?
    private var gripGap: NSLayoutConstraint?

    /// La presa serve solo nell'essenziale: nella dettagliata il gruppo si trascina per il nome della sua zona.
    var showsGrip = true {
        didSet {
            grip.isHidden = !showsGrip
            gripWidth?.constant = showsGrip ? 13 : 0
            gripGap?.constant = showsGrip ? 2 : 0
            toolTip = showsGrip ? "Drag the grip to move this group of tools" : nil
            window?.invalidateCursorRects(for: self)
        }
    }

    init(commands: [String], views: [NSView]) {
        self.commands = commands
        super.init(frame: .zero)
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        for view in [grip, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: leadingAnchor),
            grip.topAnchor.constraint(equalTo: topAnchor),
            grip.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Theme.height),
        ])
        let width = grip.widthAnchor.constraint(equalToConstant: 13)
        let gap = row.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 2)
        NSLayoutConstraint.activate([width, gap])
        gripWidth = width
        gripGap = gap
        toolTip = "Drag the grip to move this group of tools"
    }

    /// Il trascinamento cominciato altrove (sul nome della zona): stessa presa e stesso rilascio della presa.
    private var pushedCursor = false

    func beginDrag(showingClosedHand: Bool = true) {
        dragging = true
        pushedCursor = showingClosedHand
        if showingClosedHand { NSCursor.closedHand.push() }
    }

    func continueDrag(at point: NSPoint) { if dragging { onDrag?(self, point) } }

    func endDrag() {
        guard dragging else { return }
        dragging = false
        if pushedCursor { NSCursor.pop() }
        pushedCursor = false
        onFinish?(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return showsGrip && local.x <= 15 && bounds.contains(local) ? self : super.hitTest(point)
    }

    override func resetCursorRects() {
        if showsGrip { addCursorRect(NSRect(x: 0, y: 0, width: 15, height: bounds.height), cursor: .openHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if dragging {
            Theme.highlight.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard showsGrip, point.x <= 15 else { return super.mouseDown(with: event) }
        beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(self, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return super.mouseUp(with: event) }
        endDrag()
    }
}

/// Una zona di una fascia: una fila di controlli imparentati (la famiglia, i pesi, il corpo…). Nell'interfaccia
/// dettagliata sta in un riquadro con il nome sotto, in maiuscoletto; nell'essenziale è una fila semplice, come prima.
final class BandZone: NSView, NSDraggingSource, NSTextFieldDelegate {
    static let zonedHeight: CGFloat = 42
    var title: String {
        didSet {
            caption.attributedStringValue = Theme.smallCapsTitle(title, color: Theme.secondary)
            setAccessibilityLabel(title)
        }
    }
    /// Una zona della disposizione dell'interfaccia dettagliata: nella modalità di disposizione si trascina, e i suoi
    /// pulsanti si portano altrove.
    var isLayoutZone = false
    weak var layoutDelegate: BandLayoutDragging?
    let row: NSStackView
    private let caption: BandLabel
    private var zonedConstraints: [NSLayoutConstraint] = []
    private var plainConstraints: [NSLayoutConstraint] = []

    var isPlain = true {
        didSet {
            guard isPlain != oldValue else { return }
            applyMode()
        }
    }

    /// Dove va il centro della lineetta, nelle coordinate della zona (oltre il suo bordo destro); `nil` senza lineetta.
    var separatorX: CGFloat? {
        didSet {
            guard separatorX != oldValue else { return }
            separator.isHidden = separatorX == nil
            needsLayout = true
        }
    }
    let separator = ZoneSeparator()

    /// Quanto rientrano i pulsanti dai bordi della zona: il margine, o di più se il nome è più largo della fila.
    var contentInset: CGFloat { max(6, (frame.width - row.fittingSize.width) / 2) }

    override func layout() {
        super.layout()
        if let x = separatorX {
            separator.frame = NSRect(x: x - 0.5, y: 6, width: 1, height: max(bounds.height - 12, 0))
        }
    }

    /// Il gruppo della barra, se la zona ne contiene uno (la sua presa vale nell'essenziale).
    var draggedGroup: ToolbarGroupView? { row.arrangedSubviews.first as? ToolbarGroupView }

    /// La zona trascinata per il nome è arrivata a questo punto (coordinate della finestra); e il rilascio. Senza,
    /// la zona sta ferma.
    var onMove: ((BandZone, NSPoint) -> Void)?
    var onDrop: ((BandZone) -> Void)?
    var isDraggable: Bool { onMove != nil }

    init(title: String, views: [NSView], spacing: CGFloat) {
        self.title = title
        row = NSStackView(views: views)
        caption = BandLabel(labelWithAttributedString: Theme.smallCapsTitle(title, color: Theme.secondary))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        separator.isHidden = true
        addSubview(separator)
        row.orientation = .horizontal
        row.spacing = spacing
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.alignment = .center
        caption.lineBreakMode = .byClipping
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in views {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        addSubview(row)
        addSubview(caption)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        plainConstraints = [
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        zonedConstraints = [
            // La fila al centro: se il nome è più largo dei pulsanti, lo spazio in più si divide ai due lati.
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            { let c = widthAnchor.constraint(equalToConstant: 0); c.priority = .defaultLow; return c }(),
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 3),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: Self.zonedHeight),
        ]
        applyMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private func applyMode() {
        caption.isHidden = isPlain
        NSLayoutConstraint.deactivate(isPlain ? zonedConstraints : plainConstraints)
        NSLayoutConstraint.activate(isPlain ? plainConstraints : zonedConstraints)
        draggedGroup?.showsGrip = isPlain
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// La riga del nome, per tutta la larghezza del riquadro.
    private var captionArea: NSRect {
        NSRect(x: 0, y: caption.frame.minY - 1, width: bounds.width, height: bounds.height - caption.frame.minY + 1)
    }

    /// Nella modalità di disposizione la zona prende per sé i clic: i pulsanti si trascinano invece di fare il loro comando.
    var isEditing: Bool { isLayoutZone && !isPlain && BandLayoutEditing.isOn }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if renameField != nil { return super.hitTest(point) }
        if isEditing && bounds.contains(local) { return self }
        // Il nome non è un controllo: il clic resta alla zona, che non sposta la finestra.
        if !isPlain && captionArea.contains(local) { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        if isEditing { addCursorRect(bounds, cursor: .openHand) }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Il trascinamento di sistema mostra la sagoma sotto il mouse. Le prove, che mandano gli eventi da sé e non possono
    /// seguire il ciclo del trascinamento di macOS, spostano zone e pulsanti seguendo direttamente il mouse.
    static var usesSystemDrag = true
    private var pressEvent: NSEvent?
    private var subject: LayoutDragSubject?
    private var draggedView: NSView?
    private var isInSystemDrag = false
    private var isDirectDragging = false

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return super.mouseDown(with: event) }
        let local = convert(event.locationInWindow, from: nil)
        if captionArea.contains(local) {
            if event.clickCount == 2 { return beginRename() }
            subject = .zone(self)
            draggedView = self
        } else if let item = row.arrangedSubviews.first(where: { !$0.isHidden && convert($0.bounds, from: $0).contains(local) }) {
            subject = .item(item)
            draggedView = item
        } else {
            subject = .zone(self)
            draggedView = self
        }
        pressEvent = event
        if !Self.usesSystemDrag {
            isDirectDragging = true
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let subject, let view = draggedView, pressEvent != nil else { return }
        guard Self.usesSystemDrag else { return layoutDelegate?.layoutDragMoved(subject, to: event.locationInWindow) ?? () }
        guard !isInSystemDrag else { return }
        isInSystemDrag = true
        let item = NSPasteboardItem()
        item.setString(title, forType: Self.pasteboardType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(convert(view.bounds, from: view), contents: Self.snapshot(of: view))
        let session = beginDraggingSession(with: [dragging], event: pressEvent ?? event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        // Al suo posto resta l'originale sbiadito, che si sposta mentre la sagoma segue il mouse.
        view.alphaValue = 0.35
    }

    override func mouseUp(with event: NSEvent) {
        pressEvent = nil
        guard isDirectDragging else { subject = nil; draggedView = nil; return }
        isDirectDragging = false
        NSCursor.pop()
        finishDrag()
    }

    private func finishDrag() {
        draggedView?.alphaValue = 1
        if let subject { layoutDelegate?.layoutDragEnded(subject) }
        subject = nil
        draggedView = nil
    }

    static let pasteboardType = NSPasteboard.PasteboardType("local.wordprocessor.band-zone")

    /// L'immagine di una vista com'è ora, per la sagoma che segue il mouse.
    static func snapshot(of view: NSView) -> NSImage {
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    /// Nascosta se lo sono tutti i suoi controlli (una zona appena svuotata durante un trascinamento resta visibile).
    func syncHidden() {
        if needsHiddenSync { isHidden.toggle() }
    }

    var needsHiddenSync: Bool {
        let empty = !row.arrangedSubviews.isEmpty && row.arrangedSubviews.allSatisfy(\.isHidden)
        return isHidden != empty
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let window, let subject else { return }
        layoutDelegate?.layoutDragMoved(subject, to: window.convertPoint(fromScreen: screenPoint))
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isInSystemDrag = false
        pressEvent = nil
        finishDrag()
    }

    // MARK: Nome

    private var renameField: NSTextField?

    /// Il doppio clic sul nome lo rende modificabile; Invio o un clic altrove lo conferma, Esc lo lascia com'era.
    func beginRename() {
        guard renameField == nil else { return }
        let field = NSTextField(string: title)
        field.font = Theme.smallFont
        field.alignment = .center
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.centerXAnchor.constraint(equalTo: centerXAnchor),
            field.centerYAnchor.constraint(equalTo: caption.centerYAnchor),
            field.widthAnchor.constraint(equalTo: widthAnchor, constant: -6),
        ])
        caption.isHidden = true
        renameField = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endRename(commit: false)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) { endRename(commit: true) }

    private func endRename(commit: Bool) {
        guard let field = renameField else { return }
        renameField = nil
        let text = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        caption.isHidden = isPlain
        if commit { layoutDelegate?.renameZone(self, to: text) }
    }

    /// La zona col nome in modifica (per le prove).
    var renameFieldForTests: NSTextField? { renameField }

    override func draw(_ dirtyRect: NSRect) {
        guard !isPlain else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        // Nella modalità di disposizione il bordo è tratteggiato e blu: la zona si può prendere.
        if isEditing {
            Theme.accent.setStroke()
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// Il fondo di una fascia, con la riga che la separa da ciò che sta sotto (o sopra, per la barra di stato).
///
/// Nell'interfaccia dettagliata le fasce sono divise in zone, ciascuna nel suo riquadro con il nome sotto;
/// nell'essenziale riquadri e nomi spariscono e la fascia torna alta come prima.
final class BandView: NSView {
    var lineOnTop = false
    var lineOnBottom = true
    var fill: NSColor = Theme.bar
    var plainHeight: CGFloat = 38
    var heightConstraint: NSLayoutConstraint?
    var rowCenter: NSLayoutConstraint?
    private(set) var isZoned = false

    override var isFlipped: Bool { true }

    /// Le zone della fila, nell'ordine.
    var zones: [BandZone] {
        (subviews.first as? NSStackView)?.arrangedSubviews.compactMap { $0 as? BandZone } ?? []
    }

    /// Con le zone (dettagliata) o senza (essenziale).
    func setZoned(_ zoned: Bool) {
        isZoned = zoned
        for zone in zones { zone.isPlain = !zoned }
        heightConstraint?.constant = zoned ? BandZone.zonedHeight + 8 : plainHeight
        syncZones()
        needsDisplay = true
    }

    /// Dove va la zona trascinata, fra le zone che si trascinano: davanti alla prima il cui centro sta oltre il punto.
    /// Le zone si riordinano senza uscire dalla finestra: quella trascinata deve ricevere il rilascio del mouse.
    func move(_ zone: BandZone, toWindowPoint point: NSPoint) {
        guard let row = subviews.first as? NSStackView else { return }
        let movable = zones.filter(\.isDraggable)
        guard let source = movable.firstIndex(where: { $0 === zone }) else { return }
        let x = row.convert(point, from: nil).x
        let others = movable.filter { $0 !== zone }
        let destination = others.firstIndex { x < $0.frame.midX } ?? others.count
        guard source != destination else { return }
        var ordered = movable
        ordered.remove(at: source)
        ordered.insert(zone, at: destination)
        arrange(ordered)
    }

    /// Mette le zone in quest'ordine, al posto di quelle che si spostano (le altre restano dove sono).
    func arrange(_ ordered: [BandZone]) {
        guard let row = subviews.first as? NSStackView, let first = ordered.compactMap({ zone in row.arrangedSubviews.firstIndex { $0 === zone } }).min()
        else { return }
        for (offset, zone) in ordered.enumerated() { row.insertArrangedSubview(zone, at: first + offset) }
    }

    /// Una zona i cui controlli sono tutti nascosti si nasconde anche lei.
    func syncZones() {
        for zone in zones { zone.syncHidden() }
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
        Theme.line.setFill()
        if lineOnBottom { NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill() }
        if lineOnTop { NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill() }
    }
}

// MARK: - Monitor degli stili

/// Nella barra di stato: lo stile del punto in una pastiglia azzurra, e le aggiunte date a mano in pastiglie arancioni,
/// al più due, poi «+N». L'elenco intero sta nel suggerimento.
final class StylePillsView: NSView {
    var styleName = "" { didSet { refresh() } }
    /// Le aggiunte con il livello davanti: nel suggerimento e nell'elenco di «+N».
    var additions: [String] = [] { didSet { refresh() } }
    /// Ciò che si legge sulle pastiglie: solo il contenuto. Se manca, le aggiunte intere.
    var titles: [String] = [] { didSet { refresh() } }
    /// La freccia di una pastiglia: l'aggiunta va nello stile.
    var onMoveToStyle: ((Int) -> Void)?
    /// Chiamata quando si chiede di togliere delle aggiunte (gli indici in `additions`): con un clic su una pastiglia,
    /// o dall'elenco di «+N».
    var onRemove: (([Int]) -> Void)?
    /// Il menu di una singola aggiunta, con le azioni che la riguardano.
    var additionMenu: ((Int) -> NSMenu)?
    /// Il menu della pastiglia dello stile: togliere le aggiunte, portarle nello stile, crearne uno nuovo.
    var styleMenu: (() -> NSMenu)?
    private let maximumShown = 2
    /// La larghezza di ciascuno dei due pulsanti di un'aggiunta (freccia e ×), in fondo alla pastiglia.
    private let buttonWidth: CGFloat = 13
    private let pillFont = NSFont.systemFont(ofSize: 10.5)
    private let styleFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    /// La pastiglia sotto il mouse: un'aggiunta mostra la × e si colora.
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressedPill: Int?
    private var suppressClick = false

    private enum Kind: Equatable {
        case style
        case addition(Int)
        case more
    }

    private var pills: [(text: String, kind: Kind)] {
        var result: [(String, Kind)] = [(styleName.isEmpty ? "No style" : styleName, .style)]
        let shown = titles.count == additions.count ? titles : additions
        result += shown.prefix(maximumShown).enumerated().map { ($1, .addition($0)) }
        if additions.count > maximumShown { result.append(("+\(additions.count - maximumShown)", .more)) }
        return result
    }

    private func width(_ text: String, kind: Kind) -> CGFloat {
        let font = kind == .style ? styleFont : pillFont
        // Le aggiunte tengono lo spazio della freccia e della ×, così la pastiglia non si allarga quando la si sorvola.
        let extra: CGFloat = if case .addition = kind { 2 * buttonWidth } else { 0 }
        return min(ceil((text as NSString).size(withAttributes: [.font: font]).width) + 14 + extra, 182)
    }

    private var rects: [NSRect] {
        var x: CGFloat = 0
        return pills.map { pill in
            let w = width(pill.text, kind: pill.kind)
            defer { x += w + 4 }
            return NSRect(x: x, y: (bounds.height - 18) / 2, width: w, height: 18)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let press = NSPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.45
        press.allowableMovement = 6
        addGestureRecognizer(press)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        hovered = nil
        pressedPill = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
        toolTip = additions.isEmpty ? "Style “\(styleName)”, with no manual additions"
            : "Style “\(styleName)”, plus:\n" + additions.map { "· \($0)" }.joined(separator: "\n") + "\nArrow: into the style. ×: remove. Long or right click: more actions."
        setAccessibilityLabel(toolTip)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: pills.reduce(0) { $0 + width($1.text, kind: $1.kind) + 4 }, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    private func pill(at point: NSPoint) -> Int? { rects.firstIndex { $0.contains(point) } }

    override func mouseMoved(with event: NSEvent) {
        let index = pill(at: convert(event.locationInWindow, from: nil))
        hovered = index
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let index = pill(at: convert(event.locationInWindow, from: nil)) else { return }
        if case .addition = pills[index].kind {
            // Il clic breve si decide al rilascio: così il clic prolungato può aprire il menu senza togliere l'aggiunta.
            pressedPill = index
            suppressClick = false
        } else {
            click(pill: index, at: rects[index])
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedPill = nil; suppressClick = false }
        let point = convert(event.locationInWindow, from: nil)
        guard !suppressClick, let pressed = pressedPill, pill(at: point) == pressed else { return }
        if case .addition = pills[pressed].kind, point.x < rects[pressed].maxX - 4 - buttonWidth {
            // La freccia, o il resto della pastiglia: nello stile solo dalla freccia.
            if point.x >= rects[pressed].maxX - 4 - 2 * buttonWidth { moveToStyle(pill: pressed) }
            return
        }
        click(pill: pressed, at: rects[pressed])
    }

    /// La freccia di un'aggiunta (anche dalle prove): l'aggiunta va nello stile.
    func moveToStyle(pill index: Int) {
        guard pills.indices.contains(index), case .addition(let addition) = pills[index].kind else { return }
        onMoveToStyle?(addition)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = pill(at: convert(event.locationInWindow, from: nil)), case .addition(let addition) = pills[index].kind else { return }
        suppressClick = true
        if let menu = additionMenu?(addition) { popUpAbove(menu, rects[index]) }
    }

    @objc private func longPress(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began, let index = pill(at: gesture.location(in: self)),
              case .addition(let addition) = pills[index].kind else { return }
        suppressClick = true
        if let menu = additionMenu?(addition) { popUpAbove(menu, rects[index]) }
    }

    /// Il clic su una pastiglia (anche dalle prove): un'aggiunta si toglie, «+N» apre l'elenco delle altre.
    func click(pill index: Int, at rect: NSRect? = nil) {
        guard pills.indices.contains(index) else { return }
        switch pills[index].kind {
        case .style:
            if let menu = styleMenu?() { popUpAbove(menu, rect ?? rects[index]) }
        case .addition(let addition): onRemove?([addition])
        case .more: popUpAbove(moreMenu(), rect ?? rects[index])
        }
    }

    /// I menu si aprono sopra la pastiglia: la barra di stato sta in fondo alla finestra.
    private func popUpAbove(_ menu: NSMenu, _ rect: NSRect) {
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + menu.size.height + 4), in: self)
    }

    /// L'elenco di «+N»: ogni aggiunta nascosta ha lo stesso menu delle pastiglie visibili.
    func moreMenu() -> NSMenu {
        let menu = NSMenu()
        for index in maximumShown..<additions.count {
            let item = menu.addItem(withTitle: additions[index], action: nil, keyEquivalent: "")
            item.submenu = additionMenu?(index)
        }
        menu.addItem(.separator())
        let all = menu.addItem(withTitle: "Remove All Additions", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
        all.target = self
        all.tag = -1
        return menu
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        onRemove?(sender.tag < 0 ? Array(additions.indices) : [sender.tag])
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, (pill, rect)) in zip(pills, rects).enumerated() {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
            let isHovered = hovered == index
            if pill.kind == .style {
                (isHovered ? Theme.accent.withAlphaComponent(0.22) : Theme.pressed).setFill()
                path.fill()
            } else {
                if isHovered {
                    Theme.warn.withAlphaComponent(0.14).setFill()
                    path.fill()
                }
                Theme.warn.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: pill.kind == .style ? styleFont : pillFont,
                .foregroundColor: pill.kind == .style ? Theme.text : Theme.warn, .paragraphStyle: style]
            let height = (pill.text as NSString).size(withAttributes: attributes).height
            var textRect = NSRect(x: rect.minX + 5, y: rect.midY - height / 2, width: rect.width - 10, height: height)
            if case .addition = pill.kind {
                textRect.size.width -= 2 * buttonWidth
                if isHovered {
                    drawCross(centeredAt: NSPoint(x: rect.maxX - 4 - buttonWidth / 2, y: rect.midY))
                    drawUpArrow(centeredAt: NSPoint(x: rect.maxX - 4 - buttonWidth * 1.5, y: rect.midY))
                }
            }
            (pill.text as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }

    /// La freccia verso l'alto: l'aggiunta sale nello stile.
    private func drawUpArrow(centeredAt center: NSPoint) {
        let path = NSBezierPath()
        let r: CGFloat = 3.5
        path.move(to: NSPoint(x: center.x, y: center.y - r))
        path.line(to: NSPoint(x: center.x, y: center.y + r))
        path.move(to: NSPoint(x: center.x - r * 0.8, y: center.y + r * 0.2))
        path.line(to: NSPoint(x: center.x, y: center.y + r))
        path.line(to: NSPoint(x: center.x + r * 0.8, y: center.y + r * 0.2))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        Theme.warn.setStroke()
        path.stroke()
    }

    private func drawCross(centeredAt center: NSPoint) {
        let path = NSBezierPath()
        let r: CGFloat = 3
        path.move(to: NSPoint(x: center.x - r, y: center.y - r))
        path.line(to: NSPoint(x: center.x + r, y: center.y + r))
        path.move(to: NSPoint(x: center.x - r, y: center.y + r))
        path.line(to: NSPoint(x: center.x + r, y: center.y - r))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        Theme.warn.setStroke()
        path.stroke()
    }
}

// MARK: - Righello

/// La scala in centimetri sopra il testo, allineata alla colonna della pagina in cui sta il cursore, con i segni dei
/// rientri del paragrafo, che si trascinano. Per una voce di elenco il triangolo in alto è dove comincia il segno,
/// quello in basso dove comincia il testo, e il segno stesso si vede come una tacca fra i due.
final class RulerView: NSView {
    struct Geometry {
        /// La pagina e la colonna del testo, in coordinate di questa vista.
        var pageMinX: CGFloat
        var pageWidth: CGFloat
        var columnMinX: CGFloat
        var columnWidth: CGFloat
        /// Punti sullo schermo per punto di pagina.
        var scale: CGFloat
        /// In punti di pagina dal bordo sinistro della colonna: dove comincia la prima riga (per una voce, il segno) e
        /// dove cominciano le altre (per una voce, il testo); il destro dal bordo destro.
        var firstLine: CGFloat
        var left: CGFloat
        var right: CGFloat
        /// Per una voce di elenco, la larghezza del segno.
        var markerWidth: CGFloat?
    }

    enum Handle { case firstLine, left, right }

    var geometry: Geometry? { didSet { needsDisplay = true } }
    /// Durante il trascinamento (`finished` falso) e alla fine: quale segno, a quale valore in punti di pagina (dal bordo
    /// sinistro della colonna; per il destro, dal bordo destro), e i tasti premuti.
    var onDrag: ((Handle, CGFloat, Bool, NSEvent.ModifierFlags) -> Void)?
    private var dragging: (handle: Handle, value: CGFloat)?

    override var isFlipped: Bool { true }

    private static let millimetre = 72 / 25.4

    private func x(of handle: Handle, in g: Geometry) -> CGFloat {
        switch handle {
        case .firstLine: g.columnMinX + g.firstLine * g.scale
        case .left: g.columnMinX + g.left * g.scale
        case .right: g.columnMinX + g.columnWidth - g.right * g.scale
        }
    }

    /// La geometria con il segno trascinato al valore del momento.
    private var shown: Geometry? {
        guard var g = geometry, let dragging else { return geometry }
        switch dragging.handle {
        case .firstLine: g.firstLine = dragging.value
        case .left:
            // Il rientro sinistro di un paragrafo comune si porta dietro la prima riga; quello di una voce no (il
            // segno resta dov'è finché non lo si trascina).
            if g.markerWidth == nil { g.firstLine += dragging.value - g.left }
            g.left = dragging.value
        case .right: g.right = dragging.value
        }
        return g
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.ruler.setFill()
        bounds.fill()
        Theme.line.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        guard let g = shown else { return }
        let track = NSRect(x: g.pageMinX, y: 4, width: g.pageWidth, height: bounds.height - 9)
        Theme.rulerPage.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let centimetre = 10 * Self.millimetre * g.scale
        let count = Int(g.columnWidth / centimetre)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5), .foregroundColor: Theme.secondary]
        if count >= 0 {
            for index in 0...count {
                let x = g.columnMinX + CGFloat(index) * centimetre
                Theme.tick.setFill()
                NSRect(x: round(x), y: track.minY, width: 1, height: track.height).fill()
                ("\(index)" as NSString).draw(at: NSPoint(x: round(x) + 2, y: track.minY), withAttributes: attributes)
                let half = x + centimetre / 2
                if half < g.columnMinX + g.columnWidth { NSRect(x: round(half), y: track.maxY - 4, width: 1, height: 4).fill() }
            }
        }
        if let width = g.markerWidth {
            // Il segno dell'elenco: una tacca chiara che finisce dove sta il triangolo in alto (i segni si allineano a destra).
            let end = x(of: .firstLine, in: g)
            Theme.pressed.setFill()
            NSBezierPath(roundedRect: NSRect(x: end - max(width * g.scale, 3), y: track.maxY - 6, width: max(width * g.scale, 3), height: 5),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
        Theme.accent.setFill()
        let left = x(of: .left, in: g)
        triangle(at: x(of: .firstLine, in: g), pointingDown: true, top: 1)
        triangle(at: left, pointingDown: false, top: bounds.height - 13)
        NSRect(x: left - 5, y: bounds.height - 7, width: 10, height: 4).fill()
        triangle(at: x(of: .right, in: g), pointingDown: false, top: bounds.height - 11)
        if let dragging {
            // Il valore mentre si trascina, in centimetri.
            let centimetres = Double(dragging.value) / (10 * Self.millimetre)
            let text = centimetres.formatted(.number.precision(.fractionLength(1...2))) + " cm" as NSString
            let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: Theme.accentInk]
            let size = text.size(withAttributes: label)
            let anchor = x(of: dragging.handle, in: g)
            let box = NSRect(x: min(max(anchor + 8, 2), bounds.width - size.width - 10), y: 3, width: size.width + 8, height: size.height + 2)
            Theme.pressed.setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            text.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 1), withAttributes: label)
        }
    }

    private func triangle(at x: CGFloat, pointingDown: Bool, top: CGFloat) {
        let path = NSBezierPath()
        if pointingDown {
            path.move(to: NSPoint(x: x - 5, y: top))
            path.line(to: NSPoint(x: x + 5, y: top))
            path.line(to: NSPoint(x: x, y: top + 6))
        } else {
            path.move(to: NSPoint(x: x - 5, y: top + 6))
            path.line(to: NSPoint(x: x + 5, y: top + 6))
            path.line(to: NSPoint(x: x, y: top))
        }
        path.close()
        path.fill()
    }

    /// Il segno sotto il punto: il più vicino, contando anche l'altezza (il triangolo della prima riga sta in alto, gli
    /// altri due in basso), entro un raggio di presa.
    func handle(at point: NSPoint) -> Handle? {
        guard let g = geometry else { return nil }
        func center(_ handle: Handle) -> NSPoint {
            NSPoint(x: x(of: handle, in: g), y: handle == .firstLine ? 4 : bounds.height - 8)
        }
        func distance(_ handle: Handle) -> CGFloat { hypot(center(handle).x - point.x, center(handle).y - point.y) }
        let nearest = [Handle.firstLine, .left, .right].min { distance($0) < distance($1) }!
        return abs(center(nearest).x - point.x) <= 9 ? nearest : nil
    }

    /// Il valore in punti di pagina per un punto del righello, agganciato al millimetro (con ⌘, libero).
    func value(for handle: Handle, at x: CGFloat, modifiers: NSEvent.ModifierFlags) -> CGFloat {
        guard let g = geometry else { return 0 }
        var value = handle == .right ? (g.columnMinX + g.columnWidth - x) / g.scale : (x - g.columnMinX) / g.scale
        if !modifiers.contains(.command) { value = (value / Self.millimetre).rounded() * Self.millimetre }
        return min(max(value, 0), g.columnWidth / g.scale - 18)
    }

    // Il clic sul righello è suo: anche il primo, in una finestra non attiva, e mai per spostare la finestra (con la barra
    // del titolo trasparente macOS può usare i clic sulle viste non opache per trascinare la finestra).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let handle = handle(at: point) else { return }
        dragging = (handle, value(for: handle, at: point.x, modifiers: event.modifierFlags))
        onDrag?(handle, dragging!.value, false, event.modifierFlags)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let current = dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragging = (current.handle, value(for: current.handle, at: point.x, modifiers: event.modifierFlags))
        onDrag?(current.handle, dragging!.value, false, event.modifierFlags)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = dragging else { return }
        dragging = nil
        needsDisplay = true
        onDrag?(current.handle, current.value, true, event.modifierFlags)
    }

    /// La posizione sullo schermo (in coordinate di questa vista) di un valore, per la guida sulla pagina.
    func screenX(for handle: Handle, value: CGFloat) -> CGFloat? {
        guard let g = geometry else { return nil }
        return handle == .right ? g.columnMinX + g.columnWidth - value * g.scale : g.columnMinX + value * g.scale
    }
}
