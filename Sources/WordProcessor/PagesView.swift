import AppKit
import Typesetting

/// Ciò che la vista delle pagine chiede a chi possiede il testo: il controller della finestra, che tiene il deposito.
@MainActor
protocol PagesViewEditing: AnyObject {
    var pagesTextLength: Int { get }
    var pagesSelectedRange: NSRange { get }
    var pagesMarkedRange: NSRange { get }
    func pagesAttributedSubstring(for range: NSRange) -> NSAttributedString?
    func pagesInsert(_ text: Any, replacementRange: NSRange)
    func pagesSetMarkedText(_ text: Any, selectedRange: NSRange, replacementRange: NSRange)
    func pagesUnmarkText()
    /// Esegue un comando di tastiera (`moveLeft:`, `deleteBackward:`, `insertNewline:`…).
    func pagesPerform(_ command: Selector)
    func pagesMouseDown(at index: Int, affinity: NSSelectionAffinity, clickCount: Int, extending: Bool)
    func pagesMouseDragged(to index: Int, affinity: NSSelectionAffinity)
    /// Seleziona una riga intera, o l'unione di più righe durante il trascinamento nel margine.
    func pagesSelectLineRange(_ range: NSRange)
    /// Comandi del menu Modifica e simili, da girare a chi sa eseguirli.
    func pagesForwardAction(_ action: Selector, sender: Any?) -> Bool
    func pagesValidate(_ item: NSValidatedUserInterfaceItem) -> Bool
    /// Il menu del tasto destro per una posizione del testo.
    func pagesContextMenu(at index: Int) -> NSMenu?
}

/// Mostra le pagine composte dal nostro layout, una sotto l'altra, adattate alla larghezza disponibile.
///
/// È la vista pagina: usa lo stesso codice che produce il PDF, quindi ciò che si vede qui (a capo,
/// giustificazione, spaziatura `trak`) è ciò che verrà esportato. Riceve mouse e tastiera e li traduce in
/// richieste a chi possiede il testo.
@MainActor
final class PagesView: NSView {
    /// Se mostrare i segni dei caratteri nascosti (Vista › Mostra caratteri nascosti).
    var showsInvisibles = false {
        didSet { needsDisplay = true }
    }

    var layout: DocumentLayout? {
        didSet {
            fitToEnclosingClipView()
            updateInsertionIndicator()
            if pendingScroll != nil { schedulePendingScroll() }
            positionDesignBar()
        }
    }

    // MARK: Progettazione del capoverso (il disegno e i gesti sono in PagesView+Progetta.swift)

    /// Il capoverso che si progetta sulla pagina, con le sue misure: `nil` fuori dalla modalità.
    var design: ParagraphDesignOverlay? {
        didSet {
            guard design != oldValue else { return }
            needsDisplay = true
            positionDesignBar()
        }
    }
    /// Una maniglia trascinata: lo spostamento dall'inizio del gesto, in punti di pagina (in basso è positivo).
    var onDesignDrag: ((DesignHandle, CGSize, DesignDragPhase, NSEvent.ModifierFlags) -> Void)?
    /// Un clic su una maniglia bloccata da una formula.
    var onDesignLockedHandle: ((DesignHandle) -> Void)?
    /// I pulsanti intorno al capoverso: la vista la dà chi possiede il testo, qui la si colloca.
    var designBar: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let designBar { addSubview(designBar) }
            positionDesignBar()
        }
    }
    /// Il gesto su una maniglia: dove è cominciato e quanto conta lo spostamento verticale (per l'interlinea presa su
    /// una riga più in basso, meno di un punto per punto).
    var designDrag: (handle: DesignHandle, start: NSPoint, factor: CGFloat)?
    /// Salva e Annulla, fissi in alto a destra della zona visibile.
    var designActions: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let designActions { addSubview(designActions) }
            positionDesignBar()
        }
    }
    /// I margini della pagina: il gesto, la maniglia sotto il mouse e quella trascinata ora.
    var onMarginDrag: ((Int, MarginSide, CGSize, DesignDragPhase, NSEvent.ModifierFlags) -> Void)?
    var marginDrag: (page: Int, side: MarginSide, start: NSPoint)?
    var hoveredMargin: (page: Int, side: MarginSide)? {
        didSet { if hoveredMargin?.page != oldValue?.page || hoveredMargin?.side != oldValue?.side { needsDisplay = true } }
    }
    var activeMargin: (page: Int, side: MarginSide)? { didSet { needsDisplay = true } }
    /// La tenuta con le righe dei vicini: il gesto (con le righe del vicino com'erano all'inizio), la maniglia sotto il mouse.
    var onKeepDrag: ((KeepSide, Int, DesignDragPhase) -> Void)?
    var onKeepLocked: ((KeepSide) -> Void)?
    var keepDrag: (side: KeepSide, mids: [CGFloat])?
    var hoveredKeep: KeepSide? { didSet { if hoveredKeep != oldValue { needsDisplay = true } } }
    /// La testata del titolo progettato: una maniglia trascinata, la scelta di una parte con un clic.
    var onHeadingDrag: ((HeadingGripID, CGSize, DesignDragPhase) -> Void)?
    var onHeadingSelect: ((Int) -> Void)?
    var headingDrag: (id: HeadingGripID, start: NSPoint)?
    var hoveredHeadingGrip: HeadingGripID? { didSet { if hoveredHeadingGrip != oldValue { needsDisplay = true } } }
    var hoveredDesignHandle: DesignHandle? {
        didSet { if hoveredDesignHandle != oldValue { needsDisplay = true } }
    }

    /// Uno scorrimento da fare appena le pagine sono abbastanza lunghe da raggiungerlo: riaprendo un documento, le
    /// pagine si impaginano dopo che lo stato della vista è stato rimesso. Dopo qualche secondo si lascia perdere, per
    /// non far saltare la vista mentre si scrive (il documento può essere diventato più corto).
    var pendingScroll: NSPoint? {
        didSet {
            pendingScrollDeadline = pendingScroll == nil ? nil : Date().addingTimeInterval(5)
            if pendingScroll != nil { schedulePendingScroll() }
        }
    }
    private var pendingScrollDeadline: Date?

    /// Al prossimo giro del ciclo degli eventi (non con GCD: dentro un'attesa del ciclo, come nelle prove, la coda
    /// principale di GCD non esegue un blocco nuovo finché non finisce quello in corso).
    private func schedulePendingScroll() {
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { self?.applyPendingScroll() }
        }
    }

    private func applyPendingScroll() {
        guard let target = pendingScroll, let clip = superview as? NSClipView else { return }
        if let deadline = pendingScrollDeadline, Date() > deadline {
            pendingScroll = nil
            return
        }
        // Si scorre fin dove le pagine già impaginate permettono; se il punto non è ancora raggiungibile, si riprova alla
        // prossima impaginazione (un documento diventato più corto resta così in fondo).
        let x = min(max(target.x, 0), max(frame.width - clip.bounds.width, 0))
        let y = min(max(target.y, 0), max(frame.height - clip.bounds.height, 0))
        clip.scroll(to: NSPoint(x: x, y: y))
        enclosingScrollView?.reflectScrolledClipView(clip)
        if frame.height >= target.y + clip.bounds.height - 1 { pendingScroll = nil }
    }

    weak var editing: PagesViewEditing?

    /// Le occorrenze di «Cerca e sostituisci»: un fondo giallo chiaro (quella scelta è la selezione).
    var searchRanges: [NSRange] = [] {
        didSet { if searchRanges != oldValue { needsDisplay = true } }
    }

    /// Le parole che il controllo ortografico non riconosce: vengono sottolineate in rosso.
    var misspelledRanges: [NSRange] = [] {
        didSet { if misspelledRanges != oldValue { needsDisplay = true } }
    }
    /// I segni della provenienza: i tratti con qualcosa di dato a mano, e quelli a cui dà l'aspetto una regola.
    var manualRanges: [NSRange] = [] {
        didSet { if manualRanges != oldValue { needsDisplay = true } }
    }
    var ruleRanges: [NSRange] = [] {
        didSet { if ruleRanges != oldValue { needsDisplay = true } }
    }

    /// Ingrandimento scelto (1 = grandezza reale); `nil` per adattare la pagina alla larghezza disponibile.
    var zoom: CGFloat? {
        didSet {
            fitToEnclosingClipView()
            onZoomSet?()
        }
    }
    /// Chiamata dopo ogni cambio d'ingrandimento (pizzico, menu, barra): la finestra può allargarsi per contenere la pagina.
    var onZoomSet: (() -> Void)?

    /// La larghezza che servirebbe per vedere intera la pagina più larga all'ingrandimento scelto; `nil` in automatico, dove
    /// la pagina si adatta alla finestra.
    var widthNeededForZoom: CGFloat? {
        guard let zoom, let layout else { return nil }
        let widest = layout.pages.indices.map { layout.setup(forPage: $0).paperSize.width }.max() ?? layout.setup.paperSize.width
        return widest * zoom + 2 * margin
    }
    static let zoomRange: ClosedRange<CGFloat> = 0.25...5
    /// Chiamata quando l'ingrandimento cambia per un gesto sul trackpad, così la barra può mostrarlo.
    var onZoomChange: ((CGFloat?) -> Void)?
    /// Chiamata ogni volta che la scala cambia: per uno zoom, o perché in automatico la finestra si è allargata o stretta.
    var onScaleChange: (() -> Void)?
    /// Mentre si trascina un rientro sul righello: la linea verticale che mostra dove cadrà, in coordinate di questa vista.
    var guideX: CGFloat? { didSet { needsDisplay = true } }

    /// Porta in vista il cursore (dopo un cambio di ingrandimento dal menu o dalla barra).
    func scrollCaretToVisible() {
        guard let layout, let caret = layout.caret(at: selection.location, affinity: affinity) else { return }
        scrollToVisible(viewRect(for: caret.rect, onPage: caret.page).insetBy(dx: -40, dy: -80))
    }

    // MARK: Gesti sul trackpad

    /// Pizzico: ingrandisce o riduce tenendo fermo il punto della pagina che sta sotto il puntatore.
    override func magnify(with event: NSEvent) {
        pinch(by: event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// Il pizzico, separato dall'evento: lo usano anche le prove.
    func pinch(by magnification: CGFloat, at point: NSPoint) {
        let target = min(max(scale * (1 + magnification), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        setZoom(target, anchoredAt: point)
    }

    /// Doppio tocco con due dita: passa dalla vista automatica al 200% e ritorno.
    override func smartMagnify(with event: NSEvent) {
        setZoom(zoom == nil ? 2 : nil, anchoredAt: convert(event.locationInWindow, from: nil))
    }

    private func setZoom(_ newZoom: CGFloat?, anchoredAt point: NSPoint) {
        guard let layout, !layout.pages.isEmpty else { return }
        // Il punto sotto il puntatore, espresso nelle coordinate della sua pagina, che non dipendono dall'ingrandimento.
        let page = layout.pages.indices.min { first, second in
            verticalDistance(from: point.y, to: frame(ofPage: first)) < verticalDistance(from: point.y, to: frame(ofPage: second))
        } ?? 0
        let before = frame(ofPage: page)
        let onPage = CGPoint(x: (point.x - before.minX) / scale, y: (point.y - before.minY) / scale)
        let offset = CGPoint(x: point.x - visibleRect.minX, y: point.y - visibleRect.minY)

        zoom = newZoom
        // Dopo il ridimensionamento lo stesso punto della pagina torna sotto il puntatore.
        let after = frame(ofPage: page)
        scroll(NSPoint(x: after.minX + onPage.x * scale - offset.x, y: after.minY + onPage.y * scale - offset.y))
        onZoomChange?(zoom)
    }

    var selection = NSRange(location: 0, length: 0)
    private var affinity = NSSelectionAffinity.downstream
    /// Il cursore di sistema: stesso aspetto e stesso lampeggio delle altre app.
    private let insertionIndicator = NSTextInsertionIndicator(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        insertionIndicator.displayMode = .hidden
        insertionIndicator.color = Theme.pageCaret
        addSubview(insertionIndicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private let margin: CGFloat = 18
    private let labelHeight: CGFloat = 20
    private(set) var scale: CGFloat = 1

    override var isFlipped: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clipView = superview as? NSClipView else { return }
        clipView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: clipView)
    }

    @objc private func clipViewFrameChanged(_ notification: Notification) { fitToEnclosingClipView() }

    /// Ricalcola scala e altezza totale in base alla larghezza visibile.
    private func fitToEnclosingClipView() {
        let width = superview?.bounds.width ?? bounds.width
        guard let layout, width > 2 * margin else {
            needsDisplay = true
            return
        }
        // In automatico la pagina si adatta alla larghezza, ma non oltre un quarto in più della grandezza reale.
        // La scala viene dal tipo di pagina predefinito; ogni pagina ha poi il suo formato.
        scale = zoom ?? min(max((width - 2 * margin) / layout.setup.paperSize.width, 0.2), 1.25)
        computePageTops()
        let height = pageTops.last.map { $0 + layout.setup(forPage: layout.pages.count - 1).paperSize.height * scale + labelHeight + margin } ?? margin
        // Se una pagina ingrandita è più larga della finestra, la vista si allarga e si scorre in orizzontale.
        let widest = layout.pages.indices.map { layout.setup(forPage: $0).paperSize.width }.max() ?? layout.setup.paperSize.width
        let contentWidth = max(width, widest * scale + 2 * margin)
        setFrameSize(NSSize(width: contentWidth, height: max(height, superview?.bounds.height ?? 0)))
        updateInsertionIndicator()
        needsDisplay = true
        positionDesignBar()
        onScaleChange?()
    }

    // MARK: Selezione e cursore

    /// Mostra nelle pagine la selezione corrente: il cursore se è vuota, l'evidenziazione altrimenti.
    /// - Parameter head: l'estremo mobile della selezione, quello da tenere in vista.
    func setSelection(_ range: NSRange, head: Int, affinity: NSSelectionAffinity, scrollToVisible: Bool) {
        selection = range
        self.affinity = affinity
        updateInsertionIndicator()
        needsDisplay = true
        if scrollToVisible, let layout, let caret = layout.caret(at: head, affinity: affinity) {
            self.scrollToVisible(viewRect(for: caret.rect, onPage: caret.page).insetBy(dx: -20, dy: -30))
        }
    }

    private func updateInsertionIndicator() {
        guard let layout, selection.length == 0, let caret = layout.caret(at: selection.location, affinity: affinity) else {
            insertionIndicator.displayMode = .hidden
            return
        }
        var rect = viewRect(for: caret.rect, onPage: caret.page)
        rect.origin.x -= 1
        rect.size.width = 2
        insertionIndicator.frame = rect
        insertionIndicator.displayMode = .automatic
    }

    /// Da coordinate di pagina (origine in basso a sinistra, in punti) a coordinate di questa vista.
    func viewRect(for rect: CGRect, onPage page: Int) -> NSRect {
        let pageFrame = frame(ofPage: page)
        let height = layout?.setup(forPage: page).paperSize.height ?? 0
        return NSRect(x: pageFrame.minX + rect.minX * scale, y: pageFrame.minY + (height - rect.maxY) * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        updateInsertionIndicator()
        return true
    }

    override func resignFirstResponder() -> Bool {
        // Un testo in composizione (tasto morto, metodo di input) non resta in sospeso quando si esce.
        inputContext?.discardMarkedText()
        editing?.pagesUnmarkText()
        insertionIndicator.displayMode = .hidden
        return true
    }

    private var lineSelectionAnchor: NSRange?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    private static let lineSelectionCursor: NSCursor = {
        guard let image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Select Line") else { return .arrow }
        return NSCursor(image: image, hotSpot: NSPoint(x: 1, y: image.size.height / 2))
    }()

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if designMouseMoved(at: point) { return }
        if lineSelectionAnchor != nil || lineSelectionRange(at: point) != nil { Self.lineSelectionCursor.set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) {
        if lineSelectionAnchor == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Un clic vero cade sempre dentro la vista; gli eventi sintetici con coordinate esterne si ignorano.
        guard visibleRect.contains(point) else { return }
        window?.makeFirstResponder(self)
        inputContext?.discardMarkedText()
        editing?.pagesUnmarkText()
        if designMouseDown(at: point, modifiers: event.modifierFlags) { return }
        if let range = lineSelectionRange(at: point) {
            lineSelectionAnchor = range
            editing?.pagesSelectLineRange(range)
            return
        }
        lineSelectionAnchor = nil
        guard let hit = position(at: point) else { return }
        editing?.pagesMouseDown(at: hit.index, affinity: hit.affinity, clickCount: event.clickCount, extending: event.modifierFlags.contains(.shift))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = position(at: convert(event.locationInWindow, from: nil)) else { return nil }
        window?.makeFirstResponder(self)
        return editing?.pagesContextMenu(at: hit.index)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if designMouseDragged(to: point, modifiers: event.modifierFlags) { return }
        if let anchor = lineSelectionAnchor {
            // Cominciato nel margine, il trascinamento resta per righe anche se il puntatore entra nel testo.
            if let line = lineSelectionRange(at: point, inMarginOnly: false) {
                editing?.pagesSelectLineRange(NSUnionRange(anchor, line))
            }
        } else if let hit = position(at: point) {
            editing?.pagesMouseDragged(to: hit.index, affinity: hit.affinity)
        }
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        lineSelectionAnchor = nil
        _ = designMouseUp(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    /// La riga da selezionare con un clic nel margine sinistro. Il range è quello della riga composta, quindi include
    /// l'a capo quando la riga chiude il paragrafo. Durante il trascinamento si può uscire dal margine e dalla pagina.
    func lineSelectionRange(at point: NSPoint, inMarginOnly: Bool = true) -> NSRange? {
        guard let layout, !layout.pages.isEmpty else { return nil }
        let pageIndex = layout.pages.indices.min { first, second in
            verticalDistance(from: point.y, to: frame(ofPage: first)) < verticalDistance(from: point.y, to: frame(ofPage: second))
        } ?? 0
        let pageFrame = frame(ofPage: pageIndex)
        if inMarginOnly, !pageFrame.contains(point) { return nil }
        let page = layout.pages[pageIndex]
        let pageScale = scale
        guard let line = page.lines.min(by: { first, second in
            func distance(_ line: PlacedLine) -> CGFloat {
                let top = pageFrame.maxY - (line.origin.y + line.ascent) * pageScale
                let bottom = pageFrame.maxY - (line.origin.y - line.descent) * pageScale
                return point.y < top ? top - point.y : (point.y > bottom ? point.y - bottom : 0)
            }
            return distance(first) < distance(second)
        }) else { return nil }
        if inMarginOnly {
            let textX = min(line.origin.x, line.cell?.minX ?? line.origin.x)
            guard point.x < pageFrame.minX + textX * scale else { return nil }
        }
        return line.range
    }

    /// La posizione nel testo sotto un punto della vista.
    private func position(at point: NSPoint) -> (index: Int, affinity: NSSelectionAffinity)? {
        guard let layout, !layout.pages.isEmpty else { return nil }
        // La pagina sotto il puntatore, o la più vicina in verticale se il clic cade nello spazio tra due pagine.
        let page = layout.pages.indices.min { first, second in
            verticalDistance(from: point.y, to: frame(ofPage: first)) < verticalDistance(from: point.y, to: frame(ofPage: second))
        } ?? 0
        let pageFrame = frame(ofPage: page)
        let pagePoint = CGPoint(x: (point.x - pageFrame.minX) / scale, y: (pageFrame.maxY - point.y) / scale)
        return layout.position(at: pagePoint, onPage: page)
    }

    // MARK: Tastiera

    override func keyDown(with event: NSEvent) {
        // Il sistema traduce i tasti in testo, composizioni (tasti morti, metodi di input) o comandi,
        // e ce li restituisce attraverso i metodi di NSTextInputClient qui sotto.
        NSCursor.setHiddenUntilMouseMoves(true)
        interpretKeyEvents([event])
    }

    // I comandi del menu Modifica (copia, incolla, seleziona tutto…) arrivano qui e vanno a chi possiede il testo.
    @objc func cut(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSText.cut(_:)), sender: sender) }
    @objc func copy(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSText.copy(_:)), sender: sender) }
    @objc func paste(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSText.paste(_:)), sender: sender) }
    @objc func delete(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSText.delete(_:)), sender: sender) }
    @objc override func selectAll(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSText.selectAll(_:)), sender: sender) }
    @objc func changeFont(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(NSTextView.changeFont(_:)), sender: sender) }
    // Anche Annulla e Ripeti passano da chi possiede il testo: prima vanno nel documento le modifiche in attesa di una
    // pausa (scheda Stili, schede del pannello), così Annulla toglie proprio quelle.
    @objc func undo(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(undo(_:)), sender: sender) }
    @objc func redo(_ sender: Any?) { _ = editing?.pagesForwardAction(#selector(redo(_:)), sender: sender) }

    private func verticalDistance(from y: CGFloat, to rect: NSRect) -> CGFloat {
        y < rect.minY ? rect.minY - y : (y > rect.maxY ? y - rect.maxY : 0)
    }

    /// La cornice di una pagina in coordinate di questa vista (per il righello).
    func frameOfPage(_ index: Int) -> NSRect? {
        guard let layout, layout.pages.indices.contains(index) else { return nil }
        return frame(ofPage: index)
    }

    /// Il bordo superiore di ogni pagina nella vista: le pagine possono avere formati diversi.
    private var pageTops: [CGFloat] = []
    private var pageTopsScale: CGFloat = 0

    private func computePageTops() {
        guard let layout else {
            pageTops = []
            return
        }
        var y = margin
        pageTops = layout.pages.indices.map { index in
            defer { y += layout.setup(forPage: index).paperSize.height * scale + labelHeight + margin }
            return y
        }
        pageTopsScale = scale
    }

    func frame(ofPage index: Int) -> NSRect {
        guard let layout else { return .zero }
        if pageTops.count != layout.pages.count || pageTopsScale != scale { computePageTops() }
        let setup = layout.setup(forPage: index)
        let size = NSSize(width: setup.paperSize.width * scale, height: setup.paperSize.height * scale)
        let top = pageTops.indices.contains(index) ? pageTops[index] : margin
        return NSRect(x: (bounds.width - size.width) / 2, y: top, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.desk.setFill()
        dirtyRect.fill()
        guard let layout, let context = NSGraphicsContext.current?.cgContext else { return }

        for (index, page) in layout.pages.enumerated() {
            let pageFrame = frame(ofPage: index)
            guard pageFrame.insetBy(dx: -4, dy: -labelHeight - 4).intersects(dirtyRect) else { continue }

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            context.setFillColor(.white)
            context.fill(pageFrame)
            context.restoreGState()

            // Sotto tutto il resto: prima le regole, poi ciò che è dato a mano (che vince sulle regole).
            for (ranges, color) in [(ruleRanges, Theme.pageRuleMark), (manualRanges, Theme.pageManualMark)] {
                color.setFill()
                for range in ranges {
                    for part in layout.selectionRects(for: range) where part.page == index {
                        viewRect(for: part.rect, onPage: index).fill()
                    }
                }
            }
            for range in searchRanges {
                for found in layout.selectionRects(for: range) where found.page == index {
                    Theme.pageSearchMatch.setFill()
                    viewRect(for: found.rect, onPage: index).fill()
                }
            }
            for selected in layout.selectionRects(for: selection) where selected.page == index {
                Theme.pageSelection.setFill()
                viewRect(for: selected.rect, onPage: index).fill()
            }
            if !misspelledRanges.isEmpty {
                context.saveGState()
                context.setStrokeColor(NSColor.systemRed.cgColor)
                context.setLineWidth(max(1, 1.3 * scale))
                context.setLineCap(.round)
                context.setLineDash(phase: 0, lengths: [0.1, 2.6 * scale])
                for range in misspelledRanges {
                    for part in layout.selectionRects(for: range) where part.page == index {
                        let rect = viewRect(for: part.rect, onPage: index)
                        let y = rect.maxY - rect.height * 0.1
                        context.move(to: CGPoint(x: rect.minX, y: y))
                        context.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }
                context.strokePath()
                context.restoreGState()
            }
            // Il testo in composizione (tasto morto premuto, metodo di input) è sottolineato finché non è confermato.
            if let marked = editing?.pagesMarkedRange, marked.location != NSNotFound, marked.length > 0 {
                NSColor.black.withAlphaComponent(0.6).setFill()
                for part in layout.selectionRects(for: marked) where part.page == index {
                    let rect = viewRect(for: part.rect, onPage: index)
                    NSRect(x: rect.minX, y: rect.maxY - max(1, scale), width: rect.width, height: max(1, scale)).fill()
                }
            }

            // Il motore disegna con l'origine in basso a sinistra, come il PDF: qui si ribalta e si scala la pagina.
            context.saveGState()
            context.clip(to: pageFrame)
            context.translateBy(x: pageFrame.minX, y: pageFrame.maxY)
            context.scaleBy(x: scale, y: -scale)
            // I caratteri che il font scelto non ha, disegnati con un font di ripiego: evidenziati in ambra, solo a schermo.
            let fallback = page.fallbackRects
            if !fallback.isEmpty {
                context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.28).cgColor)
                for rect in fallback { context.fill(rect) }
            }
            PDFRenderer.draw(page, in: context)
            if showsInvisibles { drawInvisibles(layout.invisibleMarks(onPage: index), in: context) }
            drawFieldFrames(page.fieldRects, in: context)
            // Le note a margine che si sovrappongono o escono dallo specchio: un riquadro rosso, solo a schermo.
            let conflicts = layout.marginConflictRects(onPage: index)
            if !conflicts.isEmpty {
                context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.7).cgColor)
                context.setLineWidth(0.75)
                for rect in conflicts { context.stroke(rect.insetBy(dx: -2, dy: -2)) }
            }
            context.restoreGState()
            if design != nil { drawDesign(onPage: index, pageFrame: pageFrame, in: context) }

            if let guideX, guideX >= pageFrame.minX, guideX <= pageFrame.maxX {
                context.saveGState()
                context.setStrokeColor(Theme.accent.cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 3])
                context.move(to: CGPoint(x: guideX, y: pageFrame.minY))
                context.addLine(to: CGPoint(x: guideX, y: pageFrame.maxY))
                context.strokePath()
                context.restoreGState()
            }
            let label = NSAttributedString(string: "Page \(index + 1) of \(layout.pages.count)", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
            ])
            label.draw(at: NSPoint(x: pageFrame.midX - label.size().width / 2, y: pageFrame.maxY + 4))
        }
    }
}

// MARK: - Caratteri nascosti

extension PagesView {
    /// Il colore dei segni dei caratteri nascosti: un grigio azzurro, che si distingue dal testo.
    private static let invisibleColor = NSColor(calibratedRed: 0.33, green: 0.52, blue: 0.82, alpha: 0.85).cgColor

    /// La cornice dei campi, solo a schermo: di tutti con i caratteri nascosti in vista, altrimenti di quelli scelti.
    /// Nel PDF e nella stampa non va. Con l'origine della pagina in basso a sinistra, come il motore.
    func drawFieldFrames(_ fields: [(location: Int, rect: CGRect)], in context: CGContext) {
        let chosen = fields.filter { showsInvisibles || NSLocationInRange($0.location, selection) }
        guard !chosen.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(0.6)
        for field in chosen {
            let selected = NSLocationInRange(field.location, selection)
            context.setStrokeColor(selected ? Theme.accent.cgColor : Self.invisibleColor)
            let rect = field.rect.insetBy(dx: -1, dy: 0.5)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            context.strokePath()
        }
    }

    /// Disegna i segni dei caratteri nascosti di una pagina, con l'origine della pagina in basso a sinistra (come il
    /// motore). Solo a schermo: nel PDF non vanno.
    func drawInvisibles(_ marks: [InvisibleMark], in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        for mark in marks {
            let size = min(max(mark.rect.height * 0.55, 5), 14)
            func draw(_ symbol: String, centered: Bool) {
                let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): Self.invisibleColor]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: symbol, attributes: attributes))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                // Un po' sopra la linea di base: i segni stanno meglio a metà del rigo che appoggiati in basso.
                context.textPosition = CGPoint(x: centered ? mark.rect.midX - width / 2 : mark.rect.minX + 0.5, y: mark.baseline + size * 0.2)
                CTLineDraw(line, context)
            }
            switch mark.kind {
            case .space:
                // Un cerchietto pieno invece del punto tipografico, che a corpo piccolo è troppo esile.
                let radius = max(size * 0.13, 0.8)
                context.setFillColor(Self.invisibleColor)
                context.fillEllipse(in: CGRect(x: mark.rect.midX - radius, y: mark.baseline + size * 0.55 - radius, width: radius * 2, height: radius * 2))
            case .nonBreakingSpace: draw("°", centered: true)
            case .tab: draw("→", centered: true)
            case .lineBreak: draw("↵", centered: false)
            case .paragraphEnd: draw("¶", centered: false)
            case .noteReference:
                context.setStrokeColor(Self.invisibleColor)
                context.setLineWidth(0.5)
                context.stroke(mark.rect.insetBy(dx: -0.5, dy: 0.5))
            }
        }
    }
}

// MARK: - Ingresso di testo dal sistema

extension PagesView: @preconcurrency NSTextInputClient, NSUserInterfaceValidations {
    func insertText(_ string: Any, replacementRange: NSRange) {
        editing?.pagesInsert(string, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector) {
        editing?.pagesPerform(Self.command(for: selector, modifiers: NSApp.currentEvent?.modifierFlags ?? []))
    }

    /// Il comando da eseguire per quello che manda il sistema. macOS non dà a Maiuscole+Invio un comando proprio, e lo
    /// tratta come Invio (paragrafo nuovo): qui diventa l'a capo dentro lo stesso paragrafo, come Ctrl+Invio.
    static func command(for selector: Selector, modifiers: NSEvent.ModifierFlags) -> Selector {
        if selector == #selector(NSResponder.insertNewline(_:)), modifiers.intersection(.deviceIndependentFlagsMask) == .shift {
            return #selector(NSResponder.insertLineBreak(_:))
        }
        return selector
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        editing?.pagesSetMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    func unmarkText() { editing?.pagesUnmarkText() }
    func selectedRange() -> NSRange { editing?.pagesSelectedRange ?? NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { editing?.pagesMarkedRange ?? NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { markedRange().location != NSNotFound && markedRange().length > 0 }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let length = editing?.pagesTextLength ?? 0
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        actualRange?.pointee = clamped
        return editing?.pagesAttributedSubstring(for: clamped)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// Dove si trova sullo schermo un tratto di testo: il sistema ci mette accanto il riquadro degli accenti
    /// o dei candidati di un metodo di input.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let layout, let caret = layout.caret(at: range.location), let window else { return .zero }
        var rect = viewRect(for: caret.rect, onPage: caret.page)
        if let last = layout.selectionRects(for: range).first(where: { $0.page == caret.page }) {
            rect = viewRect(for: last.rect, onPage: caret.page)
        }
        return window.convertToScreen(convert(rect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return position(at: local)?.index ?? NSNotFound
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        editing?.pagesValidate(item) ?? false
    }
}
