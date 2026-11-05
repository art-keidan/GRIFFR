import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

/// La finestra del documento: barra del font, pagine in cui si scrive, pannello delle funzioni.
@MainActor
final class EditorWindowController: NSWindowController, NSComboBoxDelegate, NSMenuItemValidation {
    /// Gli attributi con cui si scrive al cursore: quelli del carattere che precede (all'inizio di un paragrafo, del
    /// suo primo carattere), poi corretti per note ed elenchi; un cambio di font senza selezione vale fino al prossimo
    /// spostamento del cursore. Prima della tappa 4.7 li teneva l'area di testo di Apple.
    var typingAttributes: [NSAttributedString.Key: Any] = [:] {
        didSet {
            // I valori degli assi accompagnano il font: senza, Cocoa confonderebbe due istanze dello stesso font variabile.
            let synced = TextStyling.withFontAxes(typingAttributes)
            if (synced[.fontAxes] as? String) != (typingAttributes[.fontAxes] as? String) { typingAttributes = synced }
            if !isApplyingSelection { refreshFromSelection() }
        }
    }
    /// Il testo provvisorio di un metodo di input (´ in attesa della vocale, i caratteri latini prima della scelta del
    /// cinese): `nil` se non ce n'è.
    var markedRange: NSRange?
    /// Il menu degli stili di parola e di carattere: si crea con la fascia del carattere, ma sta in quella del paragrafo.
    var characterStylesControl: NSView?
    private let panelModel = FeaturePanelModel()
    /// L'ispettore, nel pannello a destra: il pannello delle funzioni del font ne è il gruppo finale del carattere.
    lazy var inspector = InspectorModel(features: panelModel)
    /// La scheda Stili e il suo modulo: un secondo ispettore, sui valori dello stile scelto.
    lazy var styleInspector: InspectorModel = {
        let model = InspectorModel(features: panelModel)
        model.editsStyle = true
        return model
    }()
    var composerController: NSWindowController?
    var composerModel: ComposerBoardModel?
    private(set) lazy var stylesTab = StylesTabModel(inspector: styleInspector)
    /// L'albero degli oggetti, a sinistra della pagina nell'interfaccia avanzata.
    private(set) var objectTree = ObjectTreeModel()
    private var objectTreeView: NSView!
    private var pendingOutline: Timer?
    private static let showsObjectTreeKey = "ShowsObjectTree"
    /// Se l'albero degli oggetti si vede (nell'interfaccia avanzata); la scelta vale per tutte le finestre.
    static var showsObjectTree: Bool {
        get { UserDefaults.standard.object(forKey: showsObjectTreeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showsObjectTreeKey) }
    }
    /// Il percorso degli oggetti sotto la barra: Documento › Paragrafo › Parola › Carattere.
    let pathBar = NSStackView()
    /// Nel percorso, dopo «Documento»: un pulsante per ogni sezione che contiene il cursore.
    let sectionPath = NSStackView()
    /// I pulsanti mostrati ora nel percorso delle sezioni (per non ricostruirli a ogni movimento del cursore).
    var sectionPathTitles: [String] = []
    /// Quale delle sezioni che contengono il cursore guarda l'ispettore (1 la più esterna); `nil` la più interna.
    var inspectedSectionDepth: Int?
    var pathButtons: [InspectedObject: NSButton] = [:]
    /// Il «›» davanti a ogni pulsante del percorso (quello della Tabella si nasconde con lei).
    var pathSeparators: [InspectedObject: NSView] = [:]
    let pagesView = PagesView()
    var pendingLayout: DispatchWorkItem?
    var pendingSpellCheck: DispatchWorkItem?
    /// Identifica questo documento presso il correttore di sistema (parole ignorate, ecc.).
    let spellTag = NSSpellChecker.uniqueSpellDocumentTag()
    private static let checksSpellingKey = "ChecksSpellingWhileTyping"
    var checksSpelling: Bool {
        get { UserDefaults.standard.object(forKey: Self.checksSpellingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.checksSpellingKey) }
    }
    /// La selezione nei termini del nostro motore: àncora, testa e ascissa da mantenere salendo e scendendo.
    var selection = TextSelection(caret: 0)
    /// Vero mentre si imposta la selezione: gli attributi di scrittura che cambiano non ridisegnano ancora l'interfaccia.
    private var isApplyingSelection = false
    enum DragUnit { case character, word, paragraph }
    var dragUnit = DragUnit.character
    var dragOrigin = NSRange(location: 0, length: 0)
    /// La nota (richiamo e testo) in cui è cominciato il trascinamento, se è cominciato in una nota.
    var dragNote: NSRange?
    /// Il richiamo della nota in cui si trova il cursore, quando è dentro il testo di una nota.
    private(set) var noteAnchor: Int?
    /// Il deposito del documento: il testo vivo, per paragrafi con la loro identità (fase 4). Si legge e si scrive qui.
    private(set) var store = DocumentStore()
    /// Il deposito, dove il codice lo tratta come facoltativo (prima della tappa 4.7 era l'area di testo di Apple).
    var textStorage: DocumentStore? { store }
    /// Gli appunti usati da Taglia, Copia e Incolla: quelli del sistema, o uno privato nelle prove.
    var pasteboard = NSPasteboard.general
    /// Nelle prove: la scelta da fare quando il testo incollato porta definizioni diverse da quelle del documento.
    var choosePasteConflictPolicy: (([DefinitionImport.Conflict], @escaping (DefinitionImport.Policy?) -> Void) -> Void)?
    /// L'ultima specie di modifica fatta dalla tastiera: serve a decidere dove finisce un passo di «Annulla».
    enum EditKind { case insertion, deletion, none }
    private var lastEdit = EditKind.none

    /// Chiude il gruppo di battute che «Annulla» tratta come un passo solo. Il deposito raggruppa le battute
    /// consecutive finché non gli si dice di chiudere: quando si sposta il cursore, si passa dallo scrivere al
    /// cancellare, o si dà un comando.
    func endUndoStep(next: EditKind) {
        if lastEdit != next || next == .none { store.breakUndoCoalescing() }
        lastEdit = next
    }
    let familyPopup = BandPopUp(width: 190, help: "Font family")
    let facePopup = BandPopUp(width: 120, help: "Face")
    /// La famiglia le cui facce sono caricate ora nel menu; può cambiare prima che si aggiorni il font selezionato.
    private var facePopupFamily: String?
    /// Il grassetto e, nell'avanzata, le facce statiche offerte come pulsanti.
    /// La zona dei ruoli dell'interfaccia dettagliata.
    private(set) lazy var roleSlots: FontRoleSlots = {
        let slots = FontRoleSlots()
        slots.onAssign = { [weak self] role in self?.assignFontRole(role) }
        return slots
    }()
    private(set) lazy var faceStrip = FontFaceStrip(target: self, boldAction: #selector(toggleBold(_:)),
                                                    faceAction: #selector(faceButtonChanged(_:)),
                                                    weightAction: #selector(weightSliderChanged(_:)))
    let sizeBox = BandSizeBox()
    let opticalSizePopup = BandPopUp(width: 104, help: "Optical size")
    let zoomPopup = BandPopUp(width: 76, help: "Zoom")
    /// Le impostazioni del documento (pagina, lingua, sillabazione, `trak`, margini ottici), senza il contenuto.
    var settings: Document
    /// La tabella globale viene riletta a ogni comando, così le impostazioni valgono subito per tutte le finestre.
    /// Le facce dei ruoli: quelle del documento prevalgono su quelle delle impostazioni del programma.
    var fontRoleResolver: FontRoleResolver { FontRoleResolver(table: FontRolePreferences.table().overlaid(by: settings.fontRoles)) }
    var documentLayoutOptions: LayoutOptions {
        var options = settings.layoutOptions
        options.fontRoles = fontRoleResolver.table
        return options
    }
    /// Le lingue offerte: quelle che si sanno sillabare, con il dizionario del sistema o con i modelli di TeX
    /// (latino, greco antico, sanscrito).
    static let languages = LayoutOptions.hyphenationLanguages(among: [
        "it", "en", "de", "fr", "es", "pt", "ca", "ro", "nl", "sv", "da", "nb", "fi", "pl", "cs", "hr", "hu", "ru", "uk", "el",
        "la", "la-x-classic", "grc", "sa"])

    /// Il nome di una lingua come compare nei menu.
    static func languageName(_ code: String) -> String {
        if code == "la-x-classic" { return "Classical Latin" }
        guard let name = Locale(identifier: "en").localizedString(forLanguageCode: code), let first = name.first else { return code }
        return first.uppercased() + name.dropFirst()
    }

    /// La lingua da passare al correttore di sistema, o `nil` se per quella lingua non ha un dizionario
    /// (latino, greco antico, sanscrito): in quel caso il testo non si controlla.
    static func spellingLanguage(for code: String) -> String? {
        if let known = spellingLanguages[code] { return known }
        let checker = NSSpellChecker.shared
        func match(_ languages: [String]) -> String? {
            languages.first { $0 == code } ?? languages.first { $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
        }
        // Tra le varianti di una lingua (inglese britannico, americano…) vince quella scelta nelle preferenze del Mac.
        let found = match(checker.userPreferredLanguages) ?? match(checker.availableLanguages)
        spellingLanguages[code] = .some(found)
        return found
    }
    private static var spellingLanguages: [String: String?] = [:]
    static let zoomLevels: [CGFloat] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]
    private static var cascadePoint = NSPoint.zero
    let stylePopup = BandPopUp(width: 150, help: "Paragraph style")
    /// Nome dell'azione raccolta nel gruppo di annullamento durante il trascinamento di un cursore.
    private var undoGroupName: String?

    /// - Parameter content: il documento da mostrare; `nil` per un documento nuovo, che parte dal testo di prova.
    init(content: Document?) {
        var settings = content?.settingsOnly ?? Document()
        if content == nil {
            // Un documento nuovo nasce con gli stili e le Liste predefiniti; le note si numerano 1, 2, 3.
            settings.styles = .builtIn
            settings.lists = ListDefinition.builtIn + [ListDefinition.figures]
            settings.noteList = "Note"
            settings.floatStyles.append(.defaultFigure)
            // Un documento nuovo nasce nella lingua del sistema, se è tra quelle che si sanno sillabare.
            let system = Locale.current.language.languageCode?.identifier
            settings.language = system.flatMap { Self.languages.contains($0) ? $0 : nil }
        }
        self.settings = settings
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: min(1180, screen.width - 60), height: min(940, screen.height - 60)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 700, height: 400)
        super.init(window: window)
        buildContent(in: window)
        window.center()
        // Chiudendo la finestra, si ricorda nel file come lo si stava guardando (vedi `DocumentViewState`).
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillCloseForViewState(_:)),
                                               name: NSWindow.willCloseNotification, object: window)
        // La prima finestra sta al centro; ogni altra si apre un po' più in basso a destra della precedente.
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)
        var missingFonts: [String] = []
        if let content {
            let (text, missing) = content.attributedString()
            show(text)
            missingFonts = missing
        } else {
            loadEmptyDocument()
        }
        panelModel.apply = { [weak self] transform in self?.updateFeatures(transform) }
        panelModel.setAxis = { [weak self] tag, value in
            self?.updateVariations { current in current.filter { $0.tag != tag } + (value.map { [AxisValue(tag: tag, value: $0)] } ?? []) }
        }
        panelModel.axisDragging = { [weak self] dragging in self?.groupContinuousChanges(dragging, actionName: "Font axes") }
        faceStrip.weightSlider.onDrag = { [weak self] dragging in
            self?.faceStrip.isDraggingWeight = dragging
            self?.groupContinuousChanges(dragging, actionName: "Weight")
        }
        panelModel.setUsesVariableFont = { [weak self] variable in self?.switchFontFile(variable: variable) }
        panelModel.setFontTracking = { [weak self] enabled in self?.change(\.appliesFontTracking, to: enabled, actionName: "Size-specific tracking") }
        panelModel.setOpticalMargins = { [weak self] enabled in self?.change(\.usesOpticalMargins, to: enabled, actionName: "Optical margins") }
        panelModel.setGraphite = { [weak self] features in
            var values = StyleValues()
            values.graphite = Graphite.encodedChoice(features)
            self?.inspectorSet(.shaping, values)
        }
        connectInspector()
        connectStore()
        pagesView.showsInvisibles = UserDefaults.standard.bool(forKey: Self.showsInvisiblesKey)
        showSettingsInPanel()
        if !missingFonts.isEmpty { reportMissingFonts(missingFonts) }
        reportMissingImages()
        // Tornando alla finestra le pagine si ridisegnano: le immagini collegate cambiate nel frattempo in un altro
        // programma si rileggono, quelle sparite diventano il riquadro grigio.
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pagesView.needsDisplay = true }
        })
        connectFindBar()
        pagesView.editing = self
        pagesView.onZoomChange = { [weak self] zoom in self?.showZoomInBar(zoom) }
        pagesView.onScaleChange = { [weak self] in self?.refreshRuler() }
        pagesView.onZoomSet = { [weak self] in self?.adaptWindowToZoom() }
        rulerView.onDrag = { [weak self] handle, value, finished, modifiers in
            self?.rulerDragged(handle, value: value, finished: finished, modifiers: modifiers)
        }
        refreshFromSelection()
        layoutPages()
        updateCounts()
        window.initialFirstResponder = pagesView
        window.makeFirstResponder(pagesView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Costruzione dell'interfaccia

    private func buildContent(in window: NSWindow) {
        // Il pannello dell'avanzata: l'ispettore e, nelle altre schede, Liste, Flottanti e Regole.
        let definitions = DefinitionsPanel(inspector: inspector.makeHostingView())
        definitionsPanel = definitions
        connectDefinitionsPanel()
        let panel = definitions.view
        inspectorPanel = panel
        buildPathBar()
        configureFontControls()
        // La barra del titolo prende il colore delle fasce, come nel disegno.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.bar

        pagesScroll.hasVerticalScroller = true
        pagesScroll.hasHorizontalScroller = true
        pagesScroll.autohidesScrollers = true
        pagesScroll.borderType = .noBorder
        pagesScroll.drawsBackground = true
        pagesScroll.backgroundColor = Theme.desk
        pagesScroll.documentView = pagesView
        // Il righello segue lo scorrimento delle pagine.
        pagesScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(pagesScrolled(_:)), name: NSView.boundsDidChangeNotification,
                                               object: pagesScroll.contentView)

        split.isVertical = true
        split.dividerStyle = .thin
        objectTreeView = objectTree.makeView()
        objectTree.onChoose = { [weak self] item in self?.revealOutlineItem(item) }
        objectTree.onMoveItem = { [weak self] source, target, placement in self?.moveOutlineItem(source, to: target, placement: placement) }
        split.addArrangedSubview(objectTreeView)
        split.addArrangedSubview(pagesScroll)
        split.addArrangedSubview(panel)
        // Quando la finestra cambia larghezza, cambia la pagina: l'albero e il pannello restano come sono.
        // L'albero tiene la sua larghezza appena più della pagina: si lascia spostare dal divisore, ma quando la finestra
        // cambia cede prima la pagina.
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 2)
        objectTreeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        // Più stretto, nell'ispettore del carattere i menu (che non si stringono sotto la loro voce) uscirebbero dai bordi.
        panelMinimumWidth = panel.widthAnchor.constraint(greaterThanOrEqualToConstant: InspectorView.minimumWidth)
        pagesScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        // Dall'alto: gli strumenti, il carattere, il paragrafo con il righello, il percorso e i pannelli dettagliati,
        // il testo, la barra di stato.
        // Un percorso lungo scorre nella fascia: la sua larghezza non deve diventare
        // la larghezza minima della finestra (per esempio con sezioni molto annidate).
        let pathScroll = NSScrollView()
        pathScroll.drawsBackground = false
        pathScroll.borderType = .noBorder
        pathScroll.hasHorizontalScroller = true
        pathScroll.autohidesScrollers = true
        pathScroll.scrollerStyle = .overlay
        pathScroll.documentView = pathBar
        pathBar.translatesAutoresizingMaskIntoConstraints = false
        pathBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        pathScroll.heightAnchor.constraint(equalToConstant: 30).isActive = true
        pathBand = Bands.band([pathScroll], height: 30, spacing: 0)
        pathScroll.widthAnchor.constraint(equalTo: pathBand.widthAnchor, constant: -24).isActive = true
        rulerView.translatesAutoresizingMaskIntoConstraints = false
        rulerView.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let toolbar = buildToolbarBand()
        toolbar.lineOnTop = true
        characterBand = buildCharacterBand()
        paragraphBand = buildParagraphBand()
        paragraphBand.lineOnBottom = false
        statusBand = buildStatusBand()
        let column = NSStackView(views: [toolbar, characterBand, paragraphBand, rulerView, pathBand, findBar.view, split, statusBand])
        column.orientation = .vertical
        column.spacing = 0
        column.alignment = .leading
        for view in column.arrangedSubviews { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        // Tutto lo spazio verticale va al testo.
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        window.contentView = column
        applyInterfaceMode()
        watchUndo()
    }

    /// I controlli delle fasce, per nome: «salva», «annulla», «nota»… (servono alle prove e allo stato dei pulsanti).
    var bandControls: [String: NSControl] = [:]
    let pagesScroll = NSScrollView()
    private let split = NSSplitView()
    private(set) var inspectorPanel: NSView!
    /// Il pannello con le schede (la sua vista è `inspectorPanel`).
    private(set) var definitionsPanel: DefinitionsPanel!
    private var pathBand: NSView!
    var characterBand: BandView!
    var characterBandForTests: BandView? { characterBand }
    var paragraphBand: BandView!
    private var statusBand: BandView!
    private var panelMinimumWidth: NSLayoutConstraint?
    /// Un solo comando compatto: acceso mostra gli strumenti dettagliati, spento quelli essenziali.
    lazy var modeButton = BandButton(symbol: "slider.horizontal.3", help: "Show detailed tools (⌥⌘A)",
                                             target: self, action: #selector(toggleInterfaceMode(_:)))
    /// Il pulsante che accende la modalità di disposizione delle zone (nella zona «interfaccia» della dettagliata).
    lazy var layoutEditButton: BandButton = {
        let button = BandButton(symbol: "square.dashed", help: "Arrange the layout: drag zones and buttons",
                                target: self, action: #selector(toggleLayoutEditing(_:)))
        button.setButtonType(.pushOnPushOff)
        bandControls["disposizione"] = button
        return button
    }()
    /// I controlli delle fasce per nome, e il nome di ogni pulsante messo in una zona.
    var layoutItems: [String: NSView] = [:]
    var layoutItemIDs: [ObjectIdentifier: String] = [:]
    /// Durante il trascinamento di un pulsante fuori dalle zone: la fascia e il posto della zona che nascerà.
    var pendingZoneIndex: (BandView, Int)?
    /// Il problema delle formule dell'ultimo foglio di stili controllato (vedi `formulaProblem`).
    var formulaProblemCache: (sheet: StyleSheet, problem: String?)?
    lazy var layoutDropMarker: DropMarkerView = {
        let marker = DropMarkerView()
        marker.isHidden = true
        return marker
    }()
    let rulerView = RulerView()
    let countsLabel = ClickableLabel(labelWithString: "")
    let stylePills = StylePillsView()
    /// La barra di «Cerca e sostituisci», sopra la pagina; nascosta finché non la si chiede.
    let findBar = FindBar()
    /// Le occorrenze di ciò che si cerca, in ordine.
    var searchMatches: [NSRange] = []
    private var pendingCounts: DispatchWorkItem?
    private var lastCounts = ""
    /// L'interfaccia di questa finestra: parte dall'ultima scelta fatta in una finestra qualunque.
    private(set) var interfaceMode = InterfaceMode.lastChoice

    @discardableResult
    func named<Control: NSControl>(_ name: String, _ control: Control) -> Control {
        bandControls[name] = control
        return control
    }

    func button(_ name: String, _ symbol: String?, label: String = "", help: String, action: Selector?) -> BandButton {
        named(name, BandButton(symbol: symbol, label: label, help: help, target: self, action: action))
    }

    /// Un pulsante con un menu a discesa che si riempie ogni volta che lo si apre.
    func pullDown(_ name: String, symbol: String? = nil, title: String, width: CGFloat? = nil, help: String,
                          fill: @escaping (NSMenu) -> Void) -> BandPopUp {
        let popUp = BandPopUp(width: width, pullsDown: true, help: help)
        popUp.fixedTitle = title
        popUp.symbolImage = symbol.flatMap { Theme.symbol($0, help) }
        popUp.attachFiller(fill)
        return named(name, popUp)
    }

    private func later<Control: NSControl>(_ control: Control, _ what: String) -> Control {
        control.isEnabled = false
        control.toolTip = "\(what): coming in a later version"
        return control
    }

    // MARK: Barra degli strumenti personalizzabile (i metodi sono in EditorWindowController+Toolbar.swift)
    var toolbarBand: BandView!

    // MARK: Comandi delle fasce

    // I comandi della barra puntano al documento di questa finestra, anche quando la finestra non è in primo piano.
    @objc func bandNew(_ sender: Any?) { NSDocumentController.shared.newDocument(sender) }
    @objc func bandOpen(_ sender: Any?) { NSDocumentController.shared.openDocument(sender) }
    @objc func bandSave(_ sender: Any?) { (document as? NSDocument)?.save(sender) }
    @objc func bandSaveAs(_ sender: Any?) { (document as? NSDocument)?.saveAs(sender) }
    @objc func bandClose(_ sender: Any?) { window?.performClose(sender) }
    @objc func bandUndo(_ sender: Any?) { performUndo(redo: false) }
    @objc func bandRedo(_ sender: Any?) { performUndo(redo: true) }

    /// Annulla o Ripeti, dalla barra o dal menu: prima entrano nel documento le modifiche in attesa di una pausa (scheda
    /// Stili, schede del pannello), così Annulla toglie proprio quelle.
    func performUndo(redo: Bool) {
        definitionsPanel?.flushPending()
        flushStyleChanges()
        endUndoStep(next: .none)
        if redo { (document as? NSDocument)?.undoManager?.redo() } else { (document as? NSDocument)?.undoManager?.undo() }
    }

    /// Formato › Grassetto (⌘B): la faccia nera della stessa famiglia, o di nuovo quella normale.
    @objc func toggleBold(_ sender: Any?) { toggleFaceTrait(bold: true) }
    /// Formato › Corsivo (⌘I).
    @objc func toggleItalic(_ sender: Any?) { toggleFaceTrait(bold: false) }

    /// Il ruolo del testo di riferimento: prima l'intenzione salvata, poi l'equivalenza della faccia, infine i tratti
    /// di macOS per i documenti vecchi e per le facce scelte liberamente.
    private func fontRole(of reference: CTFont) -> FontRole {
        var current = CharacterStyle(reference)
        let attributes = selection.range.length > 0 && selection.range.location < documentText.length
            ? documentText.attributes(at: selection.range.location, effectiveRange: nil) : typingAttributes
        current.fontRole = (attributes[.fontRole] as? String).flatMap(FontRole.init(rawValue:))
        if let role = fontRoleResolver.role(of: current) { return role }
        let traits = TextStyling.traits(ofFace: CTFontCopyPostScriptName(reference) as String)
        return FontRole(italic: traits?.italic ?? false, bold: traits?.bold ?? false)
    }

    private func toggleFaceTrait(bold: Bool) {
        guard let reference = selectionFont().font else { return }
        let resolver = fontRoleResolver
        let role = fontRole(of: reference)
        let target = bold ? role.togglingBold() : role.togglingItalic()
        // Il corsivo non tocca il peso: Semibold resta Semibold, e un `wght` regolato a mano resta quello.
        let keepingWeight = !bold
        let storedRole = (typingAttributes[.fontRole] as? String).flatMap(FontRole.init(rawValue:))
        // Il nero tolto riporta alla faccia dello stile, se lo stile non è nero (vedi `TextStyling.styleFace`).
        let styles: StyleSheet? = bold ? settings.styles : nil
        var updatedTyping = selection.range.length == 0
            ? TextStyling.applying(role: target, to: reference, currentRole: storedRole, keepingWeight: keepingWeight, resolver: resolver) : nil
        if selection.range.length == 0, let styles, documentText.length > 0,
           let face = TextStyling.styleFace(for: target, current: CharacterStyle(reference), in: documentText,
                                            at: min(selection.range.location, documentText.length - 1), styles: styles, resolver: resolver),
           let font = TextStyling.characterAttributes(for: face).attributes[.font] as? NSFont {
            updatedTyping = (font as CTFont, nil)
        }
        edit(
            selection: { text, range in TextStyling.apply(role: target, in: text, range: range, keepingWeight: keepingWeight, resolver: resolver, styles: styles) },
            typing: { _ in updatedTyping?.font })
        if let updatedTyping {
            if let recorded = updatedTyping.role { typingAttributes[.fontRole] = recorded.rawValue }
            else { typingAttributes.removeValue(forKey: .fontRole) }
        }
        if selection.range.length > 0 { document?.undoManager?.setActionName(bold ? "Bold" : "Italic") }
        window?.makeFirstResponder(pagesView)
    }

    /// Dà alla faccia del testo selezionato (o di quello che si scriverà) il ruolo `role` nella sua famiglia, per
    /// questo documento: da qui il pulsante del nero, del corsivo… la usano, e il testo che ha quel ruolo la prende.
    func assignFontRole(_ role: FontRole) {
        guard let reference = selectionFont().font else { return }
        let family = OpticalFonts.family(of: reference)
        var equivalence = fontRoleResolver.table.equivalence(family: family, role: role)
        if FontVariations.isVariable(reference) {
            equivalence.variableInstance = VariableFontInstance(reference)
        } else {
            equivalence.staticFace = CTFontCopyPostScriptName(reference) as String
        }
        var table = settings.fontRoles
        table.customize(family: family, role: role, to: equivalence)
        guard table != settings.fontRoles else { return }
        let actionName = "Role \(role.displayName)"
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        changeDocumentFontRoles(table, actionName: actionName)
        changeStyles(to: Self.styles(settings.styles, following: role, of: family, as: equivalence), restyle: false, actionName: actionName)
        // Il testo scelto prende il ruolo, poi tutto il documento segue la nuova faccia.
        let resolver = fontRoleResolver
        if selection.range.length > 0 {
            writeStore(actionName: nil) { TextStyling.apply(role: role, in: $0, range: self.selection.range, keepingWeight: false, resolver: resolver) }
        } else {
            typingAttributes[.fontRole] = role.rawValue
        }
        reapplyFontRoles()
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(actionName)
    }

    /// Gli stili della famiglia che, in quel ruolo, fissano a numero proprio gli assi della faccia scelta (lo stile Testo
    /// a peso 300, quando il 300 diventa il Regular): quegli assi si tolgono, e lo stile segue il ruolo. Così, se poi il
    /// Regular passa a 400, lo stile e il suo testo vanno a 400 insieme, senza aggiunte.
    static func styles(_ sheet: StyleSheet, following role: FontRole, of family: String, as equivalence: FontRoleEquivalence) -> StyleSheet {
        guard let instance = equivalence.variableInstance, !instance.variations.isEmpty else { return sheet }
        let governed = Set(instance.variations.map(\.tag))
        func same(_ a: [AxisValue], _ b: [AxisValue]) -> Bool {
            a.count == b.count && a.allSatisfy { value in b.contains { $0.tag == value.tag && abs($0.value - value.value) < 0.001 } }
        }
        var result = sheet
        for index in result.styles.indices {
            guard let own = result.styles[index].values.variations else { continue }
            // Famiglia e ruolo come li dà lo stile risolto: con le formule non stanno più nei campi dei valori.
            let style = result.styles[index]
            let character = sheet.resolveCharacter(paragraphStyle: style.target == .paragraph ? style.name : nil,
                                                   wordStyle: style.target == .word ? style.name : nil,
                                                   characterStyle: style.target == .character ? style.name : nil, base: TextStyling.styleBase)
            let traits = TextStyling.traits(ofFace: character.fontName)
            let styleRole = character.fontRole ?? FontRole(italic: traits?.italic ?? false, bold: traits?.bold ?? false)
            guard FontRoleResolver().family(of: character) == family, styleRole == role,
                  same(own.filter { governed.contains($0.tag) }, instance.variations) else { continue }
            let rest = own.filter { !governed.contains($0.tag) }
            result.styles[index].values.variations = rest.isEmpty ? nil : rest
        }
        return result
    }

    /// Il ruolo che la faccia attuale realizza davvero, per la casella accesa nella zona dei ruoli.
    func currentFontRole() -> FontRole? {
        guard let reference = selectionFont().font else { return nil }
        var current = CharacterStyle(reference)
        current.fontRole = nil
        return fontRoleResolver.role(of: current)
    }

    /// Cambia le facce dei ruoli del documento (annullabile). Il testo si aggiorna a parte.
    func changeDocumentFontRoles(_ table: FontRoleTable, actionName: String) {
        let old = settings.fontRoles
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.changeDocumentFontRoles(old, actionName: actionName) }
        }
        document?.undoManager?.setActionName(actionName)
        settings.fontRoles = table
        refreshFromSelection()
    }

    /// Applica al documento attivo le equivalenze appena cambiate nelle impostazioni dell'applicazione.
    func reapplyFontRoles() {
        let resolver = fontRoleResolver
        if store.length > 0 {
            writeStore(actionName: "Typographic equivalences") {
                TextStyling.reapplyFontRoles(in: $0, range: NSRange(location: 0, length: $0.length), styles: settings.styles, resolver: resolver)
            }
        }
        if typingAttributes[.font] != nil {
            let probe = NSMutableAttributedString(string: " ", attributes: typingAttributes)
            TextStyling.reapplyFontRoles(in: probe, range: NSRange(location: 0, length: 1), styles: settings.styles, resolver: resolver)
            typingAttributes = probe.attributes(at: 0, effectiveRange: nil)
        }
        refreshFromSelection()
    }

    /// Il maiuscoletto voluto nella selezione (o nel testo che si scriverà): quello registrato nel testo, altrimenti
    /// quello che il font mostra.
    private func currentSmallCaps() -> SmallCaps {
        let attributes = selection.range.length > 0 && selection.range.location < documentText.length
            ? documentText.attributes(at: selection.range.location, effectiveRange: nil) : typingAttributes
        if let recorded = (attributes[.smallCaps] as? String).flatMap(SmallCaps.init(rawValue:)) { return recorded }
        guard let font = attributes[.font] as? NSFont else { return .off }
        return SmallCaps.split(FontFeatures.settings(of: font as CTFont)).smallCaps
    }

    /// Il maiuscoletto delle minuscole sì/no, come scelta tipografica: le forme le sceglie il font. Quello delle sigle,
    /// se c'è, resta com'è.
    @objc func toggleSmallCaps(_ sender: Any?) {
        var values = StyleValues()
        values.smallCaps = switch currentSmallCaps() {
        case .off: .lowercase
        case .lowercase: .off
        case .uppercase: .all
        case .all: .uppercase
        }
        editInspected(.smallCaps, actionName: "Small caps") { text, range in TextStyling.setValue(values, of: .smallCaps, in: text, range: range) }
        refreshBandState()
        window?.makeFirstResponder(pagesView)
    }

    /// La tavolozza del pulsante del colore: pochi colori sobri, il colore automatico, e il selettore di macOS.
    static let palette: [(name: String, hex: String)] = [
        ("Gray", "#6b6b6b"), ("Dark red", "#9b1c1c"), ("Dark orange", "#a65200"), ("Brown", "#6e4520"),
        ("Dark green", "#2e6b30"), ("Dark blue", "#1f3f8f"), ("Purple", "#6a2c8c"),
    ]

    /// Il nome di un colore per il monitor degli stili: quello della tavolozza, o il codice.
    static func colorName(_ hex: String?) -> String {
        guard let hex, !hex.isEmpty else { return "automatic" }
        return palette.first { $0.hex == hex }?.name.lowercased() ?? hex
    }

    func fillColorMenu(_ menu: NSMenu) {
        let current = currentTextColor()
        func swatch(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 16, height: 12), flipped: false) { rect in
                color.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
                return true
            }
        }
        let automatic = menu.addItem(withTitle: "Automatic", action: #selector(chooseColor(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.image = swatch(.black)
        automatic.state = current == nil ? .on : .off
        menu.addItem(.separator())
        for entry in Self.palette {
            let item = menu.addItem(withTitle: entry.name, action: #selector(chooseColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.hex
            item.image = TextStyling.color(hex: entry.hex).map(swatch)
            item.state = current == entry.hex ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Other Color…", action: #selector(showColorPanel(_:)), keyEquivalent: "").target = self
    }

    /// Il colore del testo selezionato (o di quello che si scriverà); `nil` se automatico.
    private func currentTextColor() -> String? {
        if selection.range.length > 0 { return TextStyling.textColor(in: documentText, at: selection.range.location) }
        return (typingAttributes[.foregroundColor] as? NSColor).flatMap(TextStyling.hex(of:))
    }

    @objc private func chooseColor(_ sender: NSMenuItem) { setTextColor(sender.representedObject as? String) }

    @objc private func showColorPanel(_ sender: Any?) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        // Un passo di annullamento per colore scelto, non uno per ogni movimento nel selettore.
        panel.isContinuous = false
        panel.color = currentTextColor().flatMap { TextStyling.color(hex: $0) } ?? .black
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) { setTextColor(TextStyling.hex(of: sender.color)) }

    /// Dà il colore al testo selezionato, o a quello che si scriverà; `nil` per il colore automatico.
    func setTextColor(_ hex: String?) {
        var values = StyleValues()
        values.color = hex ?? ""
        editInspected(.color, actionName: "Color") { text, range in TextStyling.setValue(values, of: .color, in: text, range: range) }
        refreshBandState()
        window?.makeFirstResponder(pagesView)
    }

    /// Formato › Sottolineato (⌘U) e Barrato: aggiungono il filetto già pronto, o tolgono i filetti in quella posizione.
    @objc func toggleUnderline(_ sender: Any?) { toggleDecoration(.underline, name: "Underline") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleDecoration(.strikethrough, name: "Strikethrough") }

    /// I filetti del testo selezionato (o di quello che si scriverà).
    private func currentDecorations() -> [LineDecoration] {
        let attributes = selection.range.length > 0 && selection.range.location < documentText.length
            ? documentText.attributes(at: selection.range.location, effectiveRange: nil) : typingAttributes
        return (attributes[.lineDecorations] as? String).flatMap(LineDecoration.decode) ?? []
    }

    private func toggleDecoration(_ preset: LineDecoration, name: String) {
        let current = currentDecorations()
        let others = current.filter { $0.position != preset.position }
        let new = others.count == current.count ? current + [preset] : others
        var values = StyleValues()
        values.decorations = LineDecoration.encode(new)
        editInspected(.decorations, actionName: name) { text, range in TextStyling.setValue(values, of: .decorations, in: text, range: range) }
        refreshBandState()
        window?.makeFirstResponder(pagesView)
    }

    /// Formato › Apice e Pedice: il valore già pronto, o di nuovo la linea di base se c'era già.
    @objc func toggleSuperscript(_ sender: Any?) { toggleVerticalPosition(.superscript, name: "Superscript") }
    @objc func toggleSubscript(_ sender: Any?) { toggleVerticalPosition(.subscript, name: "Subscript") }

    /// La posizione verticale del testo selezionato (o di quello che si scriverà).
    private func currentVerticalPosition() -> VerticalPosition? {
        let attributes = selection.range.length > 0 && selection.range.location < documentText.length
            ? documentText.attributes(at: selection.range.location, effectiveRange: nil) : typingAttributes
        return (attributes[.verticalPosition] as? String).flatMap(VerticalPosition.init(encoded:))
    }

    private func toggleVerticalPosition(_ preset: VerticalPosition, name: String) {
        var values = StyleValues()
        values.verticalPosition = currentVerticalPosition() == preset ? "" : preset.encoded
        editInspected(.verticalPosition, actionName: name) { text, range in TextStyling.setValue(values, of: .verticalPosition, in: text, range: range) }
        refreshBandState()
        window?.makeFirstResponder(pagesView)
    }

    /// Dà un valore di paragrafo ai paragrafi selezionati, come «solo qui» nell'ispettore.
    func setParagraphValue(_ property: InspectorProperty, actionName: String, _ build: (inout StyleValues) -> Void) {
        var values = StyleValues()
        build(&values)
        editInspected(property, actionName: actionName) { text, range in TextStyling.setValue(values, of: property, in: text, range: range) }
        window?.makeFirstResponder(pagesView)
    }

    /// Il paragrafo del cursore (o dell'inizio della selezione), come lo vede il testo.
    func currentParagraphStyle() -> NSParagraphStyle? {
        let text = documentText
        guard text.length > 0 else { return typingAttributes[.paragraphStyle] as? NSParagraphStyle }
        return text.attribute(.paragraphStyle, at: min(selection.range.location, text.length - 1), effectiveRange: nil) as? NSParagraphStyle
    }

    func fillSpacesMenu(_ menu: NSMenu) {
        let style = currentParagraphStyle()
        for (title, property, current) in [("Space before", InspectorProperty.spaceBefore, style?.paragraphSpacingBefore ?? 0),
                                           ("Space after", InspectorProperty.spaceAfter, style?.paragraphSpacing ?? 0)] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
            for value in [0.0, 3, 6, 12, 18, 24] {
                let item = menu.addItem(withTitle: "\(Int(value)) pt", action: #selector(chooseSpace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [property.rawValue, value] as [Any]
                item.indentationLevel = 1
                item.state = abs(Double(current) - value) < 0.01 ? .on : .off
            }
        }
    }

    @objc private func chooseSpace(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Any], let raw = pair.first as? String, let value = pair.last as? Double,
              let property = InspectorProperty(rawValue: raw) else { return }
        setParagraphValue(property, actionName: property.title) { values in
            if property == .spaceBefore { values.spaceBefore = value } else { values.spaceAfter = value }
        }
    }

    /// I caratteri tecnici del menu «Carattere», a gruppi; in fondo il Visualizzatore caratteri di macOS.
    static let specialCharacters: [(group: String, items: [(title: String, character: String, note: String)])] = [
        ("Spaces", [("No-break space", "\u{00A0}", "U+00A0"), ("Narrow no-break space", "\u{202F}", "U+202F"),
                   ("Thin space", "\u{2009}", "U+2009")]),
        ("Dashes", [("Em dash —", "\u{2014}", "U+2014"), ("En dash –", "\u{2013}", "U+2013"),
                      ("Non-breaking hyphen", "\u{2011}", "U+2011"), ("Soft hyphen (hyphenation)", "\u{00AD}", "U+00AD")]),
        ("Breaks and joins", [("Line break in the same paragraph", "\u{2028}", "⇧↩"), ("Zero-width break opportunity", "\u{200B}", "U+200B"),
                                   ("Word joiner: no break here", "\u{2060}", "U+2060"), ("Zero-width non-joiner (ligatures)", "\u{200C}", "U+200C"),
                                   ("Zero-width joiner (ligatures)", "\u{200D}", "U+200D")]),
    ]

    func fillSpecialCharacters(_ menu: NSMenu) {
        for group in Self.specialCharacters {
            menu.addItem(withTitle: group.group, action: nil, keyEquivalent: "").isEnabled = false
            for entry in group.items {
                let item = menu.addItem(withTitle: "\(entry.title)    \(entry.note)", action: #selector(insertSpecialCharacter(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.character
                item.indentationLevel = 1
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "More Characters…", action: #selector(showCharacterViewer(_:)), keyEquivalent: "").target = self
    }

    @objc func insertSpecialCharacter(_ sender: NSMenuItem) {
        guard let character = sender.representedObject as? String else { return }
        pagesInsert(character, replacementRange: pagesSelectedRange)
        window?.makeFirstResponder(pagesView)
    }

    @objc private func showCharacterViewer(_ sender: Any?) {
        window?.makeFirstResponder(pagesView)
        NSApp.orderFrontCharacterPalette(sender)
    }

    /// Gli avvisi della composizione: note a margine sovrapposte, Liste che hanno finito i segni.
    private func warnings() -> [(title: String, range: NSRange?)] {
        guard let layout = pagesView.layout else { return [] }
        var result: [(String, NSRange?)] = layout.marginConflicts.map { ("Overlapping margin note", $0) }
        result += layout.listsNeedingOverflowChoice.map { ("The list “\($0)” has run out of markers", nil) }
        // Un foglio con formule non risolvibili si compone senza di esse: lo si dice, invece di tacerlo.
        if let problem = formulaProblem() { result.append(("Style formulas: " + problem, nil)) }
        if layout.graphiteFallbacks > 0 {
            let count = layout.graphiteFallbacks == 1 ? "1 run" : "\(layout.graphiteFallbacks) runs"
            result.append((Graphite.isAvailable ? "Graphite requested for a font without Graphite tables: \(count) with Core Text"
                                                : "Graphite is not installed: \(count) with Core Text", nil))
        }
        return result
    }

    /// Il problema delle formule del foglio di stili, calcolato una volta per foglio (gli avvisi si contano a ogni
    /// movimento del cursore).
    private func formulaProblem() -> String? {
        let sheet = settings.styles
        if let cached = formulaProblemCache, cached.sheet == sheet { return cached.problem }
        let problem = sheet.formulaReferenceProblem()
        formulaProblemCache = (sheet, problem)
        return problem
    }

    /// Gli avvisi della barra di stato, come testo (per le prove).
    var warningTitles: [String] { warnings().map(\.title) }

    func fillWarnings(_ menu: NSMenu) {
        for (index, warning) in warnings().enumerated() {
            let item = menu.addItem(withTitle: warning.title, action: warning.range == nil ? nil : #selector(showWarning(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
    }

    @objc private func showWarning(_ sender: NSMenuItem) {
        let list = warnings()
        guard list.indices.contains(sender.tag), let range = list[sender.tag].range else { return }
        apply(TextSelection(anchor: range.location, head: NSMaxRange(range)))
        pagesView.scrollCaretToVisible()
        window?.makeFirstResponder(pagesView)
    }

    // MARK: Essenziale e dettagliata

    /// I due livelli condividono documento e selezione, ma non gli stessi strumenti: l'essenziale lascia soltanto le
    /// operazioni di scrittura più frequenti; la dettagliata rende accessibili tutti gli oggetti e le loro proprietà.
    private func applyInterfaceMode() {
        let advanced = interfaceMode == .advanced
        modeButton.state = advanced ? .on : .off
        modeButton.toolTip = advanced ? "Show essential tools (⌥⌘A)" : "Show detailed tools (⌥⌘A)"
        modeButton.setAccessibilityLabel(modeButton.toolTip)
        composeBands()

        pathBand.isHidden = !advanced
        inspectorPanel.isHidden = !advanced
        objectTreeView.isHidden = !advanced || !Self.showsObjectTree
        let detailedOnly = ["stileCarattere", "barrato", "apice", "pedice", "maiuscoletto", "lingua", "nascosti",
                            "provenienza", "spazi", "lista", "ortografia"]
        for name in detailedOnly { bandControls[name]?.isHidden = !advanced }
        if let font = selectionFont().font {
            updateFaceStrip(for: font, family: OpticalFonts.family(of: font))
        }
        stylePills.isHidden = !advanced
        roleSlots.isHidden = !advanced
        // La barra di stato non ha zone: la riga che separa i conteggi dallo stile c'è solo nella dettagliata.
        (statusBand?.subviews.first as? NSStackView)?.arrangedSubviews.forEach { view in
            if view is SeparatorView { view.isHidden = !advanced }
        }
        refreshBandState()
        refreshProvenanceMarks()
        updateCounts()
        panelMinimumWidth?.isActive = advanced
        updateMinimumWindowWidth()
        split.adjustSubviews()
        if advanced {
            // La posizione dei divisori vale solo dopo la disposizione della finestra: l'albero largo 232 punti, come nel
            // disegno, il pannello largo quanto basta.
            // Un rinvio del ciclo degli eventi (non della coda principale): parte anche dentro un altro blocco, come
            // nelle prove.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.window?.layoutIfNeeded()
                    if !self.objectTreeView.isHidden { self.split.setPosition(232, ofDividerAt: 0) }
                    self.split.setPosition(self.split.bounds.width - InspectorView.minimumWidth, ofDividerAt: 1)
                    self.refreshObjectTree()
                }
            }
        }
        DispatchQueue.main.async { [weak self] in self?.refreshRuler() }
    }

    /// La finestra non si stringe sotto quanto chiedono i pannelli aperti: nella dettagliata la pagina (360 punti),
    /// l'ispettore e, se c'è, l'albero degli oggetti, con i divisori. Se adesso è più stretta, si allarga.
    private func updateMinimumWindowWidth() {
        guard let window else { return }
        var width: CGFloat = 700
        if interfaceMode == .advanced {
            let tree: CGFloat = objectTreeView.isHidden ? 0 : 170 + split.dividerThickness
            width = max(width, tree + 360 + split.dividerThickness + InspectorView.minimumWidth)
        }
        window.minSize.width = width
        if window.frame.width < width {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
        }
    }

    /// Passa all'altra interfaccia in questa finestra; la scelta vale anche per i documenti che si apriranno.
    func setInterfaceMode(_ mode: InterfaceMode) {
        guard mode != interfaceMode else { return }
        interfaceMode = mode
        InterfaceMode.lastChoice = mode
        applyInterfaceMode()
        if mode == .advanced { refreshInspector() }
    }

    /// Vero se si vedono gli strumenti dettagliati (ispettore e percorso).
    var showsAdvancedTools: Bool { !inspectorPanel.isHidden && !pathBand.isHidden }
    var statusTextForTests: String { countsLabel.stringValue }

    /// Vista › Interfaccia dettagliata.
    /// Vista › Albero degli oggetti (⌥⌘O): lo mostra o lo nasconde nell'interfaccia avanzata.
    @objc func toggleObjectTree(_ sender: Any?) {
        Self.showsObjectTree.toggle()
        if interfaceMode == .simple { setInterfaceMode(.advanced) } else { applyInterfaceMode() }
    }

    var isObjectTreeVisible: Bool { objectTreeView?.isHidden == false }

    /// I segni della provenienza, accesi per questa finestra; si vedono solo nell'avanzata, mai in stampa né nel PDF.
    private(set) var showsProvenanceMarks = false

    /// Vista › Segni della provenienza (⌥⌘P), e il pulsante nel Ribbon dell'avanzata.
    @objc func toggleProvenanceMarks(_ sender: Any?) {
        showsProvenanceMarks.toggle()
        if showsProvenanceMarks, interfaceMode == .simple { setInterfaceMode(.advanced) }
        (bandControls["provenienza"] as? NSButton)?.state = showsProvenanceMarks ? .on : .off
        refreshProvenanceMarks()
    }

    private var pendingMarks: Timer?

    /// I segni si ricalcolano dopo una breve pausa: su un documento di 85 pagine costano circa 55 ms, troppo per ogni
    /// tasto. Nel frattempo restano quelli di prima.
    private func scheduleProvenanceMarks() {
        guard showsProvenanceMarks else { return }
        pendingMarks?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshProvenanceMarks() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingMarks = timer
    }

    /// Ricalcola i segni dall'ultima composizione (le regole agiscono solo lì).
    func refreshProvenanceMarks() {
        pendingMarks?.invalidate()
        pendingMarks = nil
        guard showsProvenanceMarks, interfaceMode == .advanced, let layout = pagesView.layout else {
            pagesView.manualRanges = []
            pagesView.ruleRanges = []
            return
        }
        pagesView.ruleRanges = layout.ruleRanges(rules: settings.rules, sheet: settings.styles)
        pagesView.manualRanges = TextStyling.manualRanges(in: documentText, sheet: settings.styles)
    }

    /// I segni della provenienza mostrati (per le prove).
    var provenanceMarks: (manual: [NSRange], rules: [NSRange]) { (pagesView.manualRanges, pagesView.ruleRanges) }
    /// L'oggetto che l'ispettore mostra (per le prove).
    var inspectedObject: InspectedObject { inspector.object }
    /// Per le prove: il pannello delle funzioni del font.
    var featurePanelForTests: FeaturePanelModel { panelModel }
    /// Per le prove: l'ispettore del testo.
    var inspectorForTests: InspectorModel { inspector }
    /// Per le prove: il nome che si scriverebbe nel foglio che chiede il nome di uno stile nuovo (il foglio non si apre).
    var styleNameAnswerForTests: String?
    var replaceFormulaAnswerForTests: Bool?

    /// L'albero si ricostruisce dopo una breve pausa: mentre si scrive, un tasto dopo l'altro, una volta sola.
    private func scheduleObjectTree() {
        guard isObjectTreeVisible else { return }
        pendingOutline?.invalidate()
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshObjectTree() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingOutline = timer
    }

    /// Ricostruisce l'albero dal testo e dalla composizione, e vi evidenzia l'oggetto del cursore.
    func refreshObjectTree() {
        pendingOutline?.invalidate()
        pendingOutline = nil
        guard isObjectTreeVisible else { return }
        let items = DocumentOutline.build(text: documentText, layout: pagesView.layout, floatStyles: settings.floatStyles)
        if items != objectTree.items { objectTree.items = items }
        followCaretInObjectTree()
    }

    /// L'oggetto in cui sta il cursore, evidenziato nell'albero (senza muovere il cursore).
    private func followCaretInObjectTree() {
        guard isObjectTreeVisible, store.length > 0 else { return }
        let index = min(selection.head, store.length - 1)
        let id = DocumentOutline.item(containing: index, in: objectTree.items)?.id
        if objectTree.selection != id { objectTree.selection = id }
    }

    /// Un clic su un oggetto dell'albero: il cursore va all'inizio del paragrafo, o nel testo della nota o della
    /// didascalia; per un paragrafo l'ispettore mostra il paragrafo.
    func revealOutlineItem(_ item: OutlineItem) {
        let caret = item.isFloating ? min(item.range.location + 1, NSMaxRange(item.range)) : item.range.location
        apply(TextSelection(caret: caret))
        // L'ispettore passa al paragrafo, e si mostra anche se il pannello era su un'altra scheda.
        if !item.isFloating, interfaceMode == .advanced {
            inspect(item.kind == .table ? .table : .paragraph)
            definitionsPanel.show(.inspector)
        }
        pagesView.scrollCaretToVisible()
        window?.makeFirstResponder(pagesView)
    }

    /// Un oggetto trascinato nella mappa: un capoverso prima o dopo un altro, oppure una sezione prima, dopo o dentro
    /// un'altra. Il deposito conserva le identità e il comando è un solo passo di Annulla; il cursore segue l'oggetto.
    func moveOutlineItem(_ source: OutlineItem, to target: OutlineItem, placement: OutlineDropPlacement) {
        guard source.id != target.id, objectTree.filter.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sourceID = store.paragraphID(at: source.range.location)
        let targetID = store.paragraphID(at: target.range.location)
        endUndoStep(next: .none)
        var moved: NSRange?
        switch (source.kind, target.kind) {
        case (.paragraph, .heading(_)) where placement == .afterSection:
            // Dopo la sezione: il capoverso torna a quella che la contiene.
            writeStore(actionName: "Move Paragraph") { moved = $0.moveParagraph(sourceID, afterSection: targetID) }
        case (.paragraph, .paragraph), (.paragraph, .listItem), (.paragraph, .heading(_)):
            // Accanto a un titolo il capoverso va subito prima del titolo o subito dopo (primo della sezione).
            guard placement == .before || placement == .after else { return }
            writeStore(actionName: "Move Paragraph") {
                moved = $0.moveParagraph(sourceID, placement == .before ? .before : .after, targetID)
            }
        case (.heading(_), .heading(_)):
            let position: DocumentStore.SectionMovePosition = switch placement {
            case .before: .before
            case .after, .afterSection: .after
            case .inside: .inside
            }
            writeStore(actionName: "Move Section") { moved = $0.moveSection(sourceID, position, targetID) }
        case (.heading(_), .paragraph), (.heading(_), .listItem):
            // Davanti a un capoverso: lui e quelli che lo seguono restano alla loro sezione.
            guard placement == .before else { return }
            writeStore(actionName: "Move Section") { moved = $0.moveSection(sourceID, beforeParagraph: targetID) }
        default:
            return
        }
        guard let moved else { return }
        apply(TextSelection(caret: moved.location), textChanged: true)
        refreshObjectTree()
    }

    @objc func toggleInterfaceMode(_ sender: Any?) {
        setInterfaceMode(interfaceMode == .simple ? .advanced : .simple)
    }

    // MARK: Stato dei controlli, righello, barra di stato

    private var undoObservers: [NSObjectProtocol] = []
    /// Gli altri ascolti del centro notifiche aperti con un blocco: il centro li tiene finché non si tolgono, anche
    /// dopo la chiusura della finestra.
    var notificationTokens: [NSObjectProtocol] = []

    /// Alla chiusura della finestra: smette di ascoltare le notifiche e ferma i temporizzatori ancora in attesa.
    func stopObserving() {
        for token in undoObservers + notificationTokens { NotificationCenter.default.removeObserver(token) }
        undoObservers = []
        notificationTokens = []
        for timer in [pendingMarks, pendingOutline, pendingStyleTimer] { timer?.invalidate() }
        pendingMarks = nil
        pendingOutline = nil
        pendingStyleTimer = nil
    }

    var notificationTokenCountForTests: Int { undoObservers.count + notificationTokens.count }

    /// Annulla e Ripeti si accendono e spengono con ciò che il documento ha da annullare.
    private func watchUndo() {
        let names: [Notification.Name] = [.NSUndoManagerCheckpoint, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                                          .NSUndoManagerDidCloseUndoGroup]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Solo l'identità del gestore attraversa il confine: si confronta con quello del documento.
                let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let manager = (self.document as? NSDocument)?.undoManager, sender == ObjectIdentifier(manager) else { return }
                    self.refreshUndoButtons()
                }
            }
        }
    }

    /// Annulla e Ripeti secondo ciò che il documento ha da annullare. Chiedere `canUndo` o `canRedo` al gestore fa
    /// partire una notifica di «checkpoint», che riporta qui: la seconda volta non si fa nulla.
    private func refreshUndoButtons() {
        guard !isRefreshingUndoButtons else { return }
        isRefreshingUndoButtons = true
        defer { isRefreshingUndoButtons = false }
        bandControls["annulla"]?.isEnabled = document?.undoManager?.canUndo ?? false
        bandControls["ripeti"]?.isEnabled = document?.undoManager?.canRedo ?? false
    }

    private var isRefreshingUndoButtons = false

    /// Accende, spegne e preme i controlli delle fasce secondo il documento e la selezione.
    func refreshBandState() {
        refreshUndoButtons()
        // Una nota o un'immagine dentro una nota non sono previste.
        bandControls["nota"]?.isEnabled = noteAnchor == nil
        bandControls["illustrazione"]?.isEnabled = noteAnchor == nil
        bandControls["tabella"]?.isEnabled = canInsertTable
        // I livelli esistono solo negli elenchi semplici: fuori di lì i due pulsanti non farebbero nulla.
        let levels = selectionHasLevelledItems
        bandControls["riduciLivello"]?.isEnabled = levels
        bandControls["aumentaLivello"]?.isEnabled = levels
        (bandControls["nascosti"] as? NSButton)?.state = pagesView.showsInvisibles ? .on : .off
        if let font = selectionFont().font {
            let role = fontRole(of: font)
            (bandControls["grassetto"] as? NSButton)?.state = role.isBold ? .on : .off
            (bandControls["corsivo"] as? NSButton)?.state = role.isItalic ? .on : .off
            (bandControls["maiuscoletto"] as? NSButton)?.state = [.lowercase, .all].contains(currentSmallCaps()) ? .on : .off
            if let optical = bandControls["corpoOttico"] as? NSButton {
                let hasOpticalAxis = FontVariations.axes(of: font).contains { $0.tag == "opsz" }
                let staticSize = OpticalFonts.opticalSize(of: font)
                optical.isHidden = !hasOpticalAxis && staticSize == nil
                optical.state = staticSize != nil ? (currentStaticOpticalSize() == nil ? .on : .off)
                    : (hasOpticalAxis && !FontVariations.values(of: font).contains { $0.tag == "opsz" } ? .on : .off)
                opticalSizePopup.isHidden = staticSize == nil || interfaceMode != .advanced
                let choices = [""] + OpticalFonts.availableSizes(of: font).map(\.rawValue)
                if opticalSizePopup.itemArray.compactMap({ $0.representedObject as? String }) != choices {
                    opticalSizePopup.removeAllItems()
                    opticalSizePopup.addItem(withTitle: "Automatic")
                    opticalSizePopup.lastItem?.representedObject = ""
                    for size in OpticalFonts.availableSizes(of: font) {
                        opticalSizePopup.addItem(withTitle: size.title)
                        opticalSizePopup.lastItem?.representedObject = size.rawValue
                    }
                }
                let selected = currentStaticOpticalSize()?.rawValue ?? ""
                opticalSizePopup.selectItem(at: opticalSizePopup.itemArray.firstIndex { $0.representedObject as? String == selected } ?? 0)
            }
            familyPopup.titleFont = NSFontManager.shared.font(withFamily: OpticalFonts.family(of: font), traits: [], weight: 5, size: 13)
            familyPopup.needsDisplay = true
        }
        if let language = bandControls["lingua"] as? BandPopUp {
            // Si mostra la lingua che vale davvero: quella del testo, o quella del documento; «—» se sono più d'una.
            if let current = selectionLanguage() {
                language.selectItem(at: language.itemArray.firstIndex { $0.representedObject as? String == current } ?? 0)
                language.fixedTitle = (current ?? settings.language).map(Self.languageName) ?? "None"
            } else {
                language.fixedTitle = "—"
            }
            language.needsDisplay = true
        }
        if let style = currentParagraphStyle() {
            let alignment: Int? = switch style.alignment {
            case .left, .natural: 0
            case .center: 1
            case .right: style.isDecimalAligned ? 4 : 2
            case .justified: 3
            @unknown default: nil
            }
            (bandControls["allineamento"] as? BandSegments)?.selectedSegment = alignment
            let multiple = style.lineHeightMultiple
            (bandControls["interlinea"] as? BandSegments)?.selectedSegment = multiple <= 1.01 ? 0 : (abs(multiple - 1.5) < 0.01 ? 1 : (abs(multiple - 2) < 0.01 ? 2 : nil))
            if let spaces = bandControls["spazi"] as? BandPopUp {
                func format(_ value: CGFloat) -> String { Double(value).formatted(.number.precision(.fractionLength(0...1))) }
                spaces.fixedTitle = "\(format(style.paragraphSpacingBefore)) · \(format(style.paragraphSpacing)) pt"
                spaces.needsDisplay = true
            }
        }
        let decorations = currentDecorations()
        (bandControls["sottolineato"] as? NSButton)?.state = decorations.contains { $0.position == .under } ? .on : .off
        (bandControls["barrato"] as? NSButton)?.state = decorations.contains { $0.position == .through } ? .on : .off
        let position = currentVerticalPosition()
        (bandControls["apice"] as? NSButton)?.state = position == .superscript ? .on : .off
        (bandControls["pedice"] as? NSButton)?.state = position == .subscript ? .on : .off
        if let runStyles = bandControls["stileCarattere"] as? BandPopUp {
            let names = [selectionStyleName(.word), selectionStyleName(.character)].compactMap { $0 }
            runStyles.fixedTitle = "Style: " + (names.isEmpty ? "—" : names.joined(separator: " › "))
            runStyles.needsDisplay = true
        }
        if let color = bandControls["colore"] as? BandPopUp {
            color.swatchColor = currentTextColor().flatMap { TextStyling.color(hex: $0) } ?? Theme.text
        }
        if let lists = bandControls["lista"] as? BandPopUp {
            let text = documentText
            let item = text.length > 0 ? TextStyling.listItem(in: text, at: min(selection.range.location, text.length - 1)) : nil
            lists.fixedTitle = "List: " + (item?.listName ?? "—")
            lists.needsDisplay = true
        }
        if let spelling = bandControls["ortografia"] as? BandPopUp {
            spelling.fixedTitle = (settings.language.map(Self.languageName) ?? "No language") + (checksSpelling ? " ✓" : "")
            spelling.invalidateIntrinsicContentSize()
            spelling.needsDisplay = true
        }
        refreshStyleMonitor()
        syncBandZones()
    }

    /// Le zone i cui controlli sono tutti nascosti (nell'essenziale, o per il font del punto) si nascondono.
    func syncBandZones() {
        let bands = [toolbarBand, characterBand, paragraphBand].compactMap { $0 }
        guard bands.contains(where: { $0.zones.contains(where: \.needsHiddenSync) }) else { return }
        // Una zona che compare o sparisce: le altre scivolano al loro posto.
        Motion.animate(in: window) { for band in bands { band.syncZones() } }
    }

    /// Ciò che mostra il monitor degli stili: lo stile e le aggiunte date a mano (per le prove).
    var styleMonitor: (style: String, additions: [String]) { (stylePills.styleName, stylePills.additions) }
    /// La vista del monitor (per le prove: i clic sulle pastiglie).
    var styleMonitorView: StylePillsView { stylePills }
    /// La vista pagina (per le prove della selezione dal margine).
    var pagesViewForTests: PagesView { pagesView }

    /// Un'aggiunta del monitor: ciò che dice e la proprietà da riportare al valore dello stile (`nil`: il maiuscoletto,
    /// che è una funzione del font e non una proprietà dell'ispettore).
    /// Un'aggiunta del monitor: una proprietà dell'ispettore, oppure una funzione, un asse o il corpo ottico.
    struct StyleAddition {
        /// Con il livello davanti («car.», «parola», «par.»): per il suggerimento e gli elenchi.
        let label: String
        let property: InspectorProperty?
        /// Solo il contenuto, come si legge sulla pastiglia.
        var title: String
        var detail: FontDetail? = nil
        var level: StyleTarget { property?.level ?? .character }
    }
    var styleAdditions: [StyleAddition] = []

    /// Lo stile del punto e ciò che vi è stato aggiunto a mano: le proprietà che l'ispettore segna «dato qui».
    private func refreshStyleMonitor() {
        let text = documentText
        guard text.length > 0 else {
            stylePills.styleName = ""
            stylePills.titles = []
            stylePills.additions = []
            return
        }
        let index = min(selection.range.location, text.length - 1)
        let paragraphName = text.attribute(.paragraphStyleName, at: TextStyling.bodyParagraph(in: text, at: index).range.location, effectiveRange: nil) as? String
        let runTarget = inspectionTarget(.character)
        let probeIndex = min(runTarget.range.location, max(runTarget.text.length - 1, 0))
        let runNames = runTarget.text.length > 0
            ? [runTarget.text.attribute(.wordStyleName, at: probeIndex, effectiveRange: nil) as? String,
               runTarget.text.attribute(.characterStyleName, at: probeIndex, effectiveRange: nil) as? String].compactMap { $0 }
            : []
        stylePills.styleName = ([paragraphName ?? "No style"] + runNames).joined(separator: " › ")
        var additions: [StyleAddition] = []
        for level in [StyleTarget.character, .word, .paragraph] {
            let target = inspectionTarget(level)
            let prefix = switch level { case .character: "char."; case .word: "word"; case .paragraph: "para." }
            let font = target.range.location < target.text.length
                ? (target.text.attribute(.font, at: target.range.location, effectiveRange: nil) as? NSFont).map { $0 as CTFont } : nil
            for value in TextStyling.inspect(level, in: target.text, range: target.range, sheet: settings.styles, resolver: fontRoleResolver) where value.source == .own {
                let text = Self.shortDescription(value, font: font)
                additions.append(StyleAddition(label: "\(prefix) \(text)", property: value.property, title: text))
            }
        }
        // Funzioni, assi e corpo ottico dati a mano: una pastiglia ciascuno, come le righe dell'ispettore.
        let characterTarget = inspectionTarget(.character)
        // Il peso lo dice già «nero» (o il suo contrario), quando la faccia è data a mano.
        let faceGiven = additions.contains { $0.property == .face }
        for detail in TextStyling.inspectDetails(in: characterTarget.text, range: characterTarget.range, sheet: settings.styles, resolver: fontRoleResolver)
        where detail.source == .own && !(faceGiven && detail.detail == .axis("wght")) {
            let text = Self.shortDescription(detail)
            additions.append(StyleAddition(label: "char. \(text)", property: nil, title: text, detail: detail.detail))
        }
        styleAdditions = additions
        stylePills.titles = additions.map(\.title)
        stylePills.additions = additions.map(\.label)
    }

    /// Toglie delle aggiunte del monitor (indici in `styleAdditions`): il testo torna ai valori dei suoi stili.
    /// Con una selezione vale per la selezione; senza, per il tratto continuo attorno al cursore che ha quel valore
    /// dato a mano (per il paragrafo, il paragrafo), e anche per ciò che si scriverà. Un passo solo di «Annulla».
    func removeStyleAdditions(_ indices: [Int]) {
        let chosen = indices.compactMap { styleAdditions.indices.contains($0) ? styleAdditions[$0] : nil }
        guard !chosen.isEmpty else { return }
        endUndoStep(next: .none)
        let sheet = settings.styles
        let caret = selection.range.length == 0
        let resolver = fontRoleResolver
        // Gli intervalli si decidono tutti prima di modificare il testo.
        var edits: [(StyleAddition, NSRange)] = []
        for addition in chosen {
            if !caret {
                edits.append((addition, selection.range))
            } else if addition.level == .paragraph {
                if store.length > 0, selection.range.location < store.length { edits.append((addition, NSRange(location: selection.range.location, length: 0))) }
            } else if let source = Self.typingSource(in: store, at: selection.range.location) {
                let run = additionRun(addition, around: source, sheet: sheet)
                if run.length > 0 { edits.append((addition, run)) }
            }
        }
        let name = chosen.count == 1 ? "Remove “\(chosen[0].label)”" : "Remove the Additions"
        if !edits.isEmpty {
            writeStore(actionName: name) { text in
                for (addition, range) in edits { Self.remove(addition, in: text, range: range, sheet: sheet, resolver: resolver) }
            }
        }
        // Al cursore anche ciò che si scriverà perde l'aggiunta.
        if caret {
            let probe = NSMutableAttributedString(string: " ", attributes: typingAttributes)
            for addition in chosen where addition.level != .paragraph {
                Self.remove(addition, in: probe, range: NSRange(location: 0, length: 1), sheet: sheet, resolver: resolver)
            }
            typingAttributes = probe.attributes(at: 0, effectiveRange: nil)
        }
        refreshFromSelection()
        window?.makeFirstResponder(pagesView)
    }

    /// Il tratto continuo attorno a `index` che ha l'aggiunta.
    private func additionRun(_ addition: StyleAddition, around index: Int, sheet: StyleSheet) -> NSRange {
        if let property = addition.property { return TextStyling.ownRun(of: property, in: store, around: index, sheet: sheet) }
        guard let detail = addition.detail else { return NSRange(location: index, length: 0) }
        let text = store, resolver = fontRoleResolver
        return TextStyling.continuousRun(in: text, around: index) { location in
            TextStyling.inspectDetails(in: text, range: NSRange(location: location, length: 0), sheet: sheet, resolver: resolver)
                .contains { $0.detail == detail && $0.source == .own }
        }
    }

    /// Riporta l'aggiunta al valore degli stili nell'intervallo.
    private static func remove(_ addition: StyleAddition, in text: NSMutableAttributedString, range: NSRange, sheet: StyleSheet, resolver: FontRoleResolver) {
        if let property = addition.property {
            TextStyling.resetValue(of: property, in: text, range: range, sheet: sheet, resolver: resolver)
        } else if let detail = addition.detail {
            TextStyling.resetDetail(detail, in: text, range: range, sheet: sheet)
        }
    }

    /// Una funzione, un asse o il corpo ottico dato a mano, in poche parole: «maiuscoletto», «Common Ligatures spenta»,
    /// «weight 2». I nomi sono quelli che dà il font.
    private static func shortDescription(_ detail: InspectedDetail) -> String {
        switch detail.detail {
        case .feature(let key):
            if case .aatType = key, !detail.settings.isEmpty { return detail.value }
            return "\(detail.title) \(detail.value.lowercased())"
        case .axis: return "\(detail.title.lowercased()) \(detail.value)"
        case .opticalSize: return "optical size \(detail.value.lowercased())"
        }
    }

    /// Una proprietà data a mano, in poche parole: «corpo 14», «corsivo», «allineamento centrato».
    private static func shortDescription(_ value: InspectedValue, font: CTFont? = nil) -> String {
        let v = value.value
        func points(_ number: Double?) -> String { (number ?? 0).formatted(.number.precision(.fractionLength(0...1))) + " pt" }
        switch value.property {
        case .family: return v.family ?? "family"
        case .face:
            guard let name = v.fontName, let traits = TextStyling.traits(ofFace: name) else { return "face" }
            // In un font variabile il nome è quello del font di base: il nero lo dice il peso del font del testo.
            let bold = font.flatMap { FontVariations.coordinates(of: $0)["wght"] }.map { $0 >= 600 } ?? traits.bold
            let italic = font.map { NSFontManager.shared.traits(of: $0 as NSFont).contains(.italicFontMask) } ?? traits.italic
            let words = [bold ? "bold" : nil, italic ? "italic" : nil].compactMap { $0 }
            return words.isEmpty ? "roman" : words.joined(separator: " ")
        case .size: return "size \((v.size ?? 0).formatted(.number.precision(.fractionLength(0...1))))"
        case .smallCaps:
            return switch v.smallCaps ?? .off {
            case .off: "no small caps"
            case .lowercase: "small caps"
            case .uppercase: "all small caps"
            case .all: "small caps and all small caps"
            }
        case .color: return "color " + colorName(v.color)
        case .decorations:
            let list = LineDecoration.decode(v.decorations ?? "") ?? []
            if list.isEmpty { return "no lines" }
            return list.map { decoration in
                if decoration == .underline { return "underline" }
                if decoration == .strikethrough { return "strikethrough" }
                let position = switch decoration.position { case .under: "under"; case .through: "through"; case .over: "over" }
                return "line \(position)"
            }.joined(separator: ", ")
        case .shaping: return (v.graphite ?? "off") == "off" ? "Core Text" : "Graphite"
        case .verticalPosition:
            guard let position = (v.verticalPosition).flatMap(VerticalPosition.init(encoded:)) else { return "on the baseline" }
            return position == .superscript ? "superscript" : (position == .subscript ? "subscript" : (position.isRaised ? "raised" : "lowered"))
        case .language: return "language " + ((v.language ?? "").isEmpty ? "of the document" : languageName(v.language!))
        case .hyphenates: return v.hyphenates == false ? "no hyphenation" : "hyphenation"
        case .alignment:
            let name = switch v.alignment ?? .natural { case .natural: "natural"; case .left: "left"; case .center: "centered"; case .right: "right"; case .justified: "justified"; case .decimal: "decimal" }
            return "alignment \(name)"
        case .leftIndent: return "left indent \(points(v.leftIndent))"
        case .rightIndent: return "right indent \(points(v.rightIndent))"
        case .firstLineIndent: return "first-line indent \(points(v.firstLineIndent))"
        case .spaceBefore: return "space before \(points(v.spaceBefore))"
        case .spaceAfter: return "space after \(points(v.spaceAfter))"
        case .lineHeightMultiple: return "line height \((v.lineHeightMultiple ?? 0).formatted(.number.precision(.fractionLength(0...2))))"
        case .lineSpacing: return "line spacing \(points(v.lineSpacing))"
        case .list: return "List \((v.listName ?? "").isEmpty ? "none" : v.listName!)"
        case .openingDistance: return "opening distance \(Length.text(CGFloat(v.openingDistance ?? 0)))"
        case .keepWithNext: return v.keeping.withNext == true ? "kept with next" : "not kept with next"
        case .keepTogether: return v.keeping.together == true ? "kept together" : "may split"
        case .orphanLines: return "lines at the bottom: \((v.keeping.linesAtEnd ?? 1) > 1 ? "\(v.keeping.linesAtEnd!)" : "no minimum")"
        case .widowLines: return "lines at the top: \((v.keeping.linesAtStart ?? 1) > 1 ? "\(v.keeping.linesAtStart!)" : "no minimum")"
        }
    }

    /// I conteggi della barra di stato: la pagina subito, il resto dopo una breve pausa (contare le parole costa).
    private func refreshStatus() {
        guard let layout = pagesView.layout else { return }
        let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page ?? 0
        countsLabel.stringValue = "Page \(page + 1) of \(layout.pages.count)" + lastCounts
        refreshRuler()
    }

    /// Lo zoom si legge come percentuale, anche in automatico e dopo un pizzico sul trackpad.
    func refreshZoomTitle() {
        zoomPopup.fixedTitle = "\(Int((pagesView.scale * 100).rounded()))%"
        zoomPopup.needsDisplay = true
    }

    private func scheduleCounts() {
        pendingCounts?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.updateCounts() }
        }
        pendingCounts = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Nell'essenziale soltanto le parole; nella dettagliata anche caratteri, paragrafi, note e figure.
    func updateCounts() {
        guard let layout = pagesView.layout else { return }
        let facts = layout.documentFacts()
        func format(_ value: Int) -> String { value.formatted(.number) }
        let words = "\(format(facts.wordCount)) " + (facts.wordCount == 1 ? "word" : "words")
        if interfaceMode == .simple {
            lastCounts = " · \(words)"
        } else {
            let text = documentText
            let figures = figureCount(in: text)
            let characters = TextCounts(in: text, range: NSRange(location: 0, length: text.length)).characters
            lastCounts = " · \(words) · \(format(characters)) chars · \(format(facts.paragraphCount)) paras · "
                + "\(format(facts.noteCount - figures)) notes · \(format(figures)) figs"
        }
        let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page ?? 0
        countsLabel.stringValue = "Page \(page + 1) of \(layout.pages.count)" + lastCounts
        let warningCount = warnings().count
        if let button = bandControls["avvisi"] as? BandPopUp {
            button.fixedTitle = "\(warningCount)"
            button.isHidden = warningCount == 0
            button.invalidateIntrinsicContentSize()
        }
    }

    /// Le figure del documento: le note degli stili di flottante che sono figure.
    private func figureCount(in text: NSAttributedString) -> Int {
        let figureStyles = Set(settings.floatStyles.filter { $0.placement == .figure }.map(\.name))
        var figures = 0
        text.enumerateAttribute(.footnote, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = value as? String, figureStyles.contains(style) else { return }
            for index in range.location..<NSMaxRange(range) where TextStyling.isNoteAnchor(in: text, at: index) { figures += 1 }
        }
        return figures
    }

    /// I conteggi del riquadro della barra di stato: il documento e, se c'è, la selezione.
    func countSections() -> [(title: String, rows: [(String, String)])] {
        guard let layout = currentLayout() else { return [] }
        let text = documentText
        let all = TextCounts(in: text, range: NSRange(location: 0, length: text.length))
        let figures = figureCount(in: text)
        let notes = layout.notes.count - figures
        let page = (layout.caret(at: selection.head, affinity: selection.affinity)?.page ?? 0) + 1
        func format(_ value: Int) -> String { value.formatted(.number) }
        var sections: [(title: String, rows: [(String, String)])] = [("Document", [
            ("Pages", "\(format(layout.pages.count)) (you are on \(page))"),
            ("Words", format(all.words)),
            ("Characters", format(all.characters)),
            ("Characters without spaces", format(all.charactersWithoutSpaces)),
            ("Paragraphs", format(all.paragraphs)),
            ("Notes", format(notes)),
            ("Figures", format(figures)),
        ])]
        if selection.range.length > 0 {
            let selected = TextCounts(in: text, range: selection.range)
            sections.append(("Selection", [
                ("Words", format(selected.words)),
                ("Characters", format(selected.characters)),
                ("Characters without spaces", format(selected.charactersWithoutSpaces)),
                ("Paragraphs", format(selected.paragraphs)),
            ]))
        }
        return sections
    }

    private var countsPopover: NSPopover?
    /// Il testo dei conteggi nella barra di stato (per le prove).
    var countsText: String { countsLabel.stringValue }

    /// Un clic sui conteggi della barra di stato: il riquadro con l'elenco completo.
    @objc func showCounts(_ sender: Any?) {
        if let open = countsPopover, open.isShown {
            open.close()
            return
        }
        let popover = CountsView.makePopover(sections: countSections())
        popover.show(relativeTo: countsLabel.bounds, of: countsLabel, preferredEdge: .maxY)
        countsPopover = popover
    }

    // MARK: Monitor degli stili: il menu dello stile (i metodi sono in EditorWindowController+Stili.swift)
    /// La percentuale dello zoom mostrata ora, e un pizzico sul trackpad (per le prove).
    var zoomTitle: String { zoomPopup.displayTitle }

    var pageScale: CGFloat { pagesView.scale }

    /// Il righello come lo vede chi lo guarda, e un trascinamento simulato (per le prove).
    var rulerGeometry: RulerView.Geometry? { rulerView.geometry }

    var lastRulerPreview: (handle: RulerView.Handle, value: CGFloat)?

    // MARK: Collegamento con il documento

    /// Il contenuto corrente nella forma del modello, per salvarlo.
    func currentDocument() -> Document {
        // Ciò che si è appena scritto in una scheda del pannello va nel documento prima di salvarlo.
        definitionsPanel?.flushPending()
        flushStyleChanges()
        return Document(attributedString: documentText, settings: settings)
    }

    /// Sostituisce tutto il contenuto (usato da «Ripristina versione salvata»).
    func replaceContent(_ content: Document) {
        // Ciò che aspettava la pausa nelle schede riguarda il documento di prima: non va applicato a quello nuovo.
        discardPendingChanges()
        settings = content.settingsOnly
        let (text, missingFonts) = content.attributedString()
        show(text)
        definitionsPanel?.documentChanged()
        showSettingsInPanel()
        refreshFromSelection()
        layoutPages()
        if !missingFonts.isEmpty { reportMissingFonts(missingFonts) }
        reportMissingImages()
    }

    private func showSettingsInPanel() {
        panelModel.appliesFontTracking = settings.appliesFontTracking
        panelModel.usesOpticalMargins = settings.usesOpticalMargins
        refreshInspector()
    }

    /// Cambia un'impostazione del documento. È una modifica annullabile, e il documento risulta modificato.
    func change<Value: Equatable>(_ keyPath: WritableKeyPath<Document, Value>, to value: Value, actionName: String) {
        let previous = settings[keyPath: keyPath]
        guard value != previous else { return }
        // Il percorso si porta attraverso l'annullamento come valore opaco: è immutabile, ma non è dichiarato trasferibile.
        nonisolated(unsafe) let keyPath = keyPath
        nonisolated(unsafe) let previousValue = previous
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.change(keyPath, to: previousValue, actionName: actionName) }
        }
        document?.undoManager?.setActionName(actionName)
        settings[keyPath: keyPath] = value
        showSettingsInPanel()
        // La spaziatura `trak` vive anche nel testo, come attributo derivato: si ricalcola senza diventare un passo
        // (il passo è il cambio d'impostazione, già registrato).
        let tracking = settings.appliesFontTracking
        writeStore(actionName: nil, recordsUndo: false) { TextStyling.syncFontTracking(in: $0, range: NSRange(location: 0, length: $0.length), enabled: tracking) }
        layoutPages()
    }

    // MARK: Pagine

    /// L'ispettore Pagina mostra il tipo della pagina in cui sta il cursore.
    func syncPageInspector() {
        var setup = settings.pageSetup
        var name: String?
        if let layout = pagesView.layout, let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page {
            setup = layout.setup(forPage: page)
            name = layout.pages[page].typeName
        }
        if inspector.pageSetup != setup { inspector.pageSetup = setup }
        if inspector.pageTypeName != name { inspector.pageTypeName = name }
    }

    /// Ispettore › Pagina: cambia il tipo della pagina del cursore (il predefinito, o quello con un nome).
    func setInspectedPageSetup(_ setup: PageSetup) {
        if let name = inspector.pageTypeName, let index = settings.pageTypes.firstIndex(where: { $0.name == name }) {
            var types = settings.pageTypes
            types[index].setup = setup
            change(\.pageTypes, to: types, actionName: "Page type “\(name)”")
        } else {
            change(\.pageSetup, to: setup, actionName: "Page Setup")
        }
    }

    /// Scheda Pagine: i tipi di pagina, con le sezioni che seguono le rinomine, in un passo di Annulla.
    func applyPageTypeChanges(_ result: PageTypesSheetModel.Result) -> Bool {
        guard result.types != settings.pageTypes else { return false }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if store.length > 0, !result.renames.isEmpty {
            writeStore(actionName: nil) { SectionEditing.renamePageTypes(result.renames, in: $0) }
        }
        change(\.pageTypes, to: result.types, actionName: "Page Types")
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("Page Types")
        return true
    }

    /// Ricompone tutto il documento e aggiorna le pagine mostrate.
    func layoutPages() {
        composerModel?.documentChanged(sheet: settings.styles, rules: settings.rules)
        pendingLayout = nil
        pagesView.layout = PageLayout.layout(documentText, setup: settings.pageSetup, options: documentLayoutOptions)
        // Il conto delle parole del documento intero si rifà solo a richiesta (scegliendo «Documento» nel percorso).
        // Ciò che danno le regole si sa solo componendo: con un oggetto che ha proprietà, si rilegge tutto l'ispettore.
        if inspector.object.level != nil { refreshInspector() } else if inspector.object != .document { refreshFacts() }
        // La pagina nell'ispettore segue il documento anche dopo Annulla, che non cambia la selezione.
        syncPageInspector()
        scheduleProvenanceMarks()
        showSelectionInPages(scrollToVisible: false)
        scheduleCounts()
        scheduleSpellCheck()
        askAboutListOverflow()
        scheduleObjectTree()
    }

    // MARK: Selezione → interfaccia

    /// Il font di riferimento della selezione: il primo tratto, oppure quello con cui si scriverebbe al cursore.
    private func selectionFont() -> (font: CTFont?, others: Int) {
        let range = selection.range
        if range.length > 0, let storage = textStorage {
            let runs = TextStyling.fontRuns(in: storage, range: range)
            guard let first = runs.first else { return (nil, 0) }
            // Le facce di uno stesso font a più assi contano come un font solo.
            let others = Set(runs.map { FontVariations.baseName(of: $0.font) }).subtracting([FontVariations.baseName(of: first.font)]).count
            return (first.font, others)
        }
        return ((typingAttributes[.font] as? NSFont).map { $0 as CTFont }, 0)
    }

    /// Le funzioni Graphite del testo scelto (o di ciò che si scriverà): `nil` se si compone con Core Text.
    private func selectionGraphite() -> String? {
        let target = inspectionTarget(.character)
        guard target.text.length > 0 else { return nil }
        return target.text.attribute(.graphite, at: min(target.range.location, target.text.length - 1), effectiveRange: nil) as? String
    }

    func refreshFromSelection() {
        refreshBandState()
        followCaretInObjectTree()
        let (font, others) = selectionFont()
        panelModel.show(font: font, otherFonts: others)
        panelModel.graphiteSettings = selectionGraphite()
        // Il pannello dei font di sistema mostra il font della selezione della finestra in primo piano.
        if let font, window?.isMainWindow == true { NSFontManager.shared.setSelectedFont(font as NSFont, isMultiple: others > 0) }
        guard let font else {
            refreshInspector()
            return
        }
        let family = OpticalFonts.family(of: font)
        if familyPopup.titleOfSelectedItem != family { familyPopup.selectItem(withTitle: family) }
        markFamily(family)
        // Il font scelto resta nel menu; quello che si vede davvero per i caratteri che gli mancano segue in grigio: «→ Helvetica».
        let fallbacks = FontFallback.fallbackFamilies(in: documentText, range: fallbackProbeRange())
        let note = fallbacks.isEmpty ? nil : "→ " + fallbacks.joined(separator: ", ")
        if familyPopup.trailingNote != note {
            familyPopup.trailingNote = note
            familyPopup.toolTip = note.map { _ in "Font family: \(family). Characters it lacks are shown in \(fallbacks.joined(separator: ", "))." }
                ?? "Font family"
        }
        if facePopupFamily != family { reloadFaces(for: family) }
        // Variabile o istanze: il pulsante solo se la famiglia ha tutte e due le forme; con il font variabile (e l'asse
        // del peso) il menu delle facce lascia il posto al cursore del peso.
        let isVariable = FontVariations.isVariable(font)
        let hasBothForms = FontVariations.counterpart(of: font, variable: !isVariable) != nil
        let variableButton = bandControls["variabile"] as? NSButton
        variableButton?.state = isVariable ? .on : .off
        let hidesFaces = isVariable && FontVariations.axes(of: font).contains { $0.tag == "wght" }
        if variableButton?.isHidden == hasBothForms || facePopup.isHidden != hidesFaces {
            // Il pulsante del font variabile e il menu delle facce compaiono e spariscono scivolando.
            Motion.animate(in: window) {
                variableButton?.isHidden = !hasBothForms
                facePopup.isHidden = hidesFaces
            }
        }
        let baseFace = OpticalFonts.baseFaceName(of: font)
        if let index = facePopup.itemArray.firstIndex(where: { $0.representedObject as? String == baseFace }) {
            facePopup.selectItem(at: index)
        }
        sizeBox.stringValue = Self.sizeFormatter.string(from: font.pointSize as NSNumber) ?? ""
        showParagraphStyleInBar()
        updateFaceStrip(for: font, family: family)
        syncBandZones()
        refreshInspector()
    }

    /// Un pulsante per peso, non per faccia: i corsivi restano al comando C e decorano gli stessi campioni.
    private func updateFaceStrip(for font: CTFont, family: String) {
        let members: [(name: String, title: String, weight: Int, traits: Int)] =
            OpticalFonts.members(ofFamily: family).compactMap { member in
                guard member.count >= 4, let name = member[0] as? String, let title = member[1] as? String,
                      let weight = member[2] as? Int, let traits = member[3] as? Int else { return nil }
                return (name, title, weight, traits)
            }
        func weightTitle(_ title: String) -> String {
            if title == "Italic" || title == "Oblique" { return "Regular" }
            for suffix in [" Italic", " Oblique"] where title.hasSuffix(suffix) {
                return String(title.dropLast(suffix.count))
            }
            return title
        }
        let italics = members.filter { $0.traits & 1 != 0 }
        let widthVariants = ["Condensed", "Extended", "Expanded", "Compressed", "Narrow"]
        // A parità di peso resta il primo stile tondo: ornamenti e altre varianti non diventano pesi distinti.
        var uprightByWeight: [Int: (name: String, title: String, weight: Int, traits: Int)] = [:]
        for member in members where member.traits & 1 == 0 && uprightByWeight[member.weight] == nil
            && !widthVariants.contains(where: { member.title.localizedCaseInsensitiveContains($0) }) {
            uprightByWeight[member.weight] = member
        }
        let faces = uprightByWeight.values.sorted { $0.weight < $1.weight }.map { base in
            FontFaceChoice(name: base.name, title: base.title,
                           italicName: italics.first { weightTitle($0.title) == weightTitle(base.title) }?.name
                            ?? italics.first { $0.weight == base.weight }?.name,
                           weight: base.weight)
        }
        let role = fontRole(of: font)
        let displayedBoldRole = role.isBold ? role : role.togglingBold()
        var boldFont: NSFont?
        if let resolution = fontRoleResolver.resolve(family: family, role: displayedBoldRole, current: CharacterStyle(font)) {
            switch resolution {
            case .staticFace(let name):
                boldFont = NSFont(name: name, size: 13)
            case .variableInstance(let instance):
                if let base = FontVariations.font(named: instance.fontName, size: 13, preferringVariable: true) {
                    boldFont = FontVariations.font(base, with: instance.variations) as NSFont
                }
            }
        }
        faceStrip.update(faces: faces, currentFace: OpticalFonts.baseFaceName(of: font),
                         currentIsItalic: TextStyling.traits(ofFace: font.postScriptName)?.italic ?? false,
                         advanced: interfaceMode == .advanced, boldFont: boldFont, variableWeight: variableWeight(of: font, family: family))
        roleSlots.update(values: fontRoleValues(family: family, current: font), current: currentFontRole())
    }

    /// Che cosa ciascun ruolo è, per la famiglia: il peso (per un font variabile) o il nome della faccia.
    func fontRoleValues(family: String, current font: CTFont) -> [FontRole: String] {
        var values: [FontRole: String] = [:]
        for role in FontRole.allCases {
            switch fontRoleResolver.resolve(family: family, role: role, current: CharacterStyle(font)) {
            case .staticFace(let name):
                if let face = NSFont(name: name, size: 12) { values[role] = CTFontCopyName(face, kCTFontStyleNameKey) as String? ?? name }
            case .variableInstance(let instance):
                if let base = FontVariations.font(named: instance.fontName, size: 12, preferringVariable: true) {
                    let resolved = FontVariations.font(base, with: instance.variations)
                    let axis = FontVariations.axes(of: resolved).first { $0.tag == "wght" }
                    if let weight = FontVariations.coordinates(of: resolved)["wght"] ?? axis?.defaultValue {
                        values[role] = FontFaceStrip.number(weight)
                    } else {
                        values[role] = CTFontCopyName(resolved, kCTFontStyleNameKey) as String?
                    }
                }
            case nil:
                break
            }
        }
        return values
    }

    /// Dove guardare i caratteri di ripiego: la selezione, o col solo cursore il carattere che lo precede (quello che
    /// segue, a inizio paragrafo).
    private func fallbackProbeRange() -> NSRange {
        let text = documentText as NSAttributedString
        let range = selection.range
        if range.length > 0 { return range }
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let string = text.string as NSString
        let location = min(range.location, text.length)
        if location > 0, !TextStyling.isLineTerminator(string.character(at: location - 1)) { return NSRange(location: location - 1, length: 1) }
        return location < text.length ? NSRange(location: location, length: 1) : NSRange(location: 0, length: 0)
    }

    /// Il peso di un font variabile con l'asse `wght`, con le istanze con nome della famiglia (dello stesso corsivo) come
    /// punti di attrazione; senza almeno due istanze, cinque punti equidistanti. `nil` per i font statici.
    private func variableWeight(of font: CTFont, family: String) -> VariableWeightChoice? {
        guard FontVariations.isVariable(font), let axis = FontVariations.axes(of: font).first(where: { $0.tag == "wght" }),
              axis.maximum > axis.minimum else { return nil }
        let value = FontVariations.coordinates(of: font)["wght"] ?? axis.defaultValue
        let italic = TextStyling.traits(ofFace: font.postScriptName)?.italic ?? false
        var stops: [(Double, String)] = []
        for member in OpticalFonts.members(ofFamily: family) {
            guard member.count >= 4, let name = member[0] as? String, let title = member[1] as? String, let traits = member[3] as? Int,
                  (traits & 1 != 0) == italic,
                  let instance = FontVariations.font(named: name, size: 12, preferringVariable: true), FontVariations.isVariable(instance),
                  let weight = FontVariations.coordinates(of: instance)["wght"], !stops.contains(where: { abs($0.0 - weight) < 0.001 })
            else { continue }
            var shown = title
            for suffix in [" Italic", " Oblique"] where shown.hasSuffix(suffix) { shown = String(shown.dropLast(suffix.count)) }
            if shown == "Italic" || shown == "Oblique" { shown = "Regular" }
            stops.append((weight, shown))
        }
        stops.sort { $0.0 < $1.0 }
        if stops.count < 2 {
            stops = (0...4).map { step in
                let weight = axis.minimum + (axis.maximum - axis.minimum) * Double(step) / 4
                return ((weight * 100).rounded() / 100, "")
            }
        }
        return VariableWeightChoice(range: axis.minimum...axis.maximum, value: value, stops: stops.map(\.0), titles: stops.map(\.1))
    }

    /// Il cursore del peso: agganciato alle istanze, cambia solo `wght`; un peso scelto così è una faccia libera.
    @objc private func weightSliderChanged(_ sender: WeightSlider) {
        let range = sender.minValue...sender.maxValue
        let value = WeightSlider.snapped(sender.doubleValue, to: sender.stops, in: range)
        if value != sender.doubleValue { sender.doubleValue = value }
        updateVariations { current in current.filter { $0.tag != "wght" } + [AxisValue(tag: "wght", value: value)] }
        if selection.range.length > 0 {
            writeStore(actionName: nil, breakingUndo: false) { $0.removeAttribute(.fontRole, range: self.selection.range) }
        } else {
            typingAttributes.removeValue(forKey: .fontRole)
        }
        faceStrip.showWeight(value)
    }

    private func reloadFaces(for family: String) {
        facePopupFamily = family
        facePopup.removeAllItems()
        for member in OpticalFonts.members(ofFamily: family) {
            guard let postScriptName = member[0] as? String, let style = member[1] as? String else { continue }
            facePopup.addItem(withTitle: style)
            facePopup.lastItem?.representedObject = postScriptName
        }
    }

    private static let sizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private func showSelectionInPages(scrollToVisible: Bool) {
        pagesView.setSelection(selection.range, head: selection.head, affinity: selection.affinity, scrollToVisible: scrollToVisible)
        refreshStatus()
    }

    /// Dopo ogni cambio di selezione: ricorda se il cursore è in una nota e prepara gli attributi con cui si scriverà.
    private func selectionDidSettle() {
        guard let storage = textStorage else { return }
        noteAnchor = selection.isEmpty ? TextStyling.footnoteSpan(in: storage, containing: selection.head, affinity: selection.affinity)?.location : nil
        guard selection.isEmpty else { return }
        defer { syncListTypingAttributes() }
        let head = selection.head
        if noteAnchor != nil, head > 0 {
            // Dentro una nota si scrive con gli attributi del carattere che precede il cursore (il testo della nota
            // o, se è ancora vuota, il suo richiamo). Vanno impostati qui: non si ricalcolano quando la posizione del
            // cursore non cambia, come subito dopo l'inserimento di una nota.
            var attributes = storage.attributes(at: head - 1, effectiveRange: nil)
            // Lo stile del flottante resta quello della nota in cui si scrive.
            attributes[.footnote] = attributes[.footnote] ?? FloatStyle.footnoteName
            typingAttributes = attributes
        } else if let source = Self.typingSource(in: storage, at: head), storage.attribute(.footnote, at: source, effectiveRange: nil) != nil {
            // Nel corpo, subito dopo una nota, o a inizio paragrafo subito prima del suo richiamo: la regola generale
            // darebbe gli attributi della nota. Si prendono quelli del testo del corpo più vicino, prima o dopo.
            let string = storage.string as NSString
            let paragraph = string.paragraphRange(for: NSRange(location: min(head, max(string.length - 1, 0)), length: 0))
            var source: Int?
            var probe = head - 1
            while probe >= paragraph.location {
                if storage.attribute(.footnote, at: probe, effectiveRange: nil) == nil { source = probe; break }
                probe -= 1
            }
            probe = head
            while source == nil, probe < NSMaxRange(paragraph) {
                if storage.attribute(.footnote, at: probe, effectiveRange: nil) == nil { source = probe }
                probe += 1
            }
            var attributes = source.map { storage.attributes(at: $0, effectiveRange: nil) } ?? typingAttributes
            attributes[.footnote] = nil
            typingAttributes = attributes
        }
    }

    /// Fa sì che il testo scritto al cursore appartenga all'elenco del paragrafo in cui si scrive (o a nessuno).
    /// La regola generale darebbe gli attributi del carattere precedente, che all'inizio di un paragrafo può essere
    /// l'a capo del paragrafo prima, e in fondo al testo è l'ultimo a capo.
    func syncListTypingAttributes() {
        guard let storage = textStorage, storage.length > 0, selection.range.length == 0 else { return }
        let wanted = TextStyling.listItem(in: storage, at: selection.range.location)?.encoded
        var attributes = typingAttributes
        guard attributes[.listItem] as? String != wanted || attributes[.finalParagraphList] != nil else { return }
        attributes[.listItem] = wanted
        attributes[.finalParagraphList] = nil
        typingAttributes = attributes
    }

    /// Imposta la selezione decisa dal nostro motore, quando la sposta chi scrive (clic, frecce, comandi).
    /// `textChanged`: il testo sotto il cursore è cambiato (uno spostamento dalla mappa), e gli attributi di
    /// scrittura vanno ricalcolati anche se il cursore resta allo stesso numero di carattere.
    func apply(_ newSelection: TextSelection, textChanged: Bool = false) {
        // Uno spostamento del cursore separa ciò che si è scritto prima da ciò che si scriverà dopo, e rende
        // definitivo il testo provvisorio di un metodo di input.
        endUndoStep(next: .none)
        if markedRange != nil {
            markedRange = nil
            pagesView.inputContext?.discardMarkedText()
        }
        setSelection(newSelection, textChanged: textChanged)
    }

    /// Imposta la selezione senza chiudere il passo di annullamento: dopo un tasto, il cursore va avanti ma il passo
    /// continua.
    func setSelection(_ newSelection: TextSelection, textChanged: Bool = false) {
        let moved = textChanged || newSelection.range != selection.range
        selection = newSelection
        isApplyingSelection = true
        // Gli attributi di scrittura si ricalcolano solo se il cursore si è spostato: un font scelto senza selezione
        // resta finché non ci si muove.
        if moved { typingAttributes = Self.typingAttributes(in: store, at: newSelection) }
        isApplyingSelection = false
        selectionDidSettle()
        refreshFromSelection()
        showSelectionInPages(scrollToVisible: true)
    }

    /// Il layout su cui calcolare i movimenti, aggiornato se una ricomposizione era ancora in attesa.
    func currentLayout() -> DocumentLayout? {
        if pendingLayout != nil { layoutPages() }
        return pagesView.layout
    }

    // MARK: Interfaccia → testo

    /// Applica una modifica agli attributi della selezione (annullabile) oppure, senza selezione, al testo che si scriverà.
    private func edit(selection: (NSMutableAttributedString, NSRange) -> Void, typing: (CTFont) -> CTFont?) {
        let range = self.selection.range
        if range.length == 0 {
            if let font = (typingAttributes[.font] as? NSFont).map({ $0 as CTFont }), let updated = typing(font) {
                typingAttributes[.font] = updated
            }
        } else {
            writeStore(actionName: nil) { selection($0, range) }
        }
        refreshFromSelection()
    }

    private func updateFeatures(_ transform: @escaping ([FeatureSetting]) -> [FeatureSetting]) {
        guard let reference = selectionFont().font else { return }
        edit(
            selection: { TextStyling.updateFeatures(in: $0, range: $1, ofFontNamed: FontVariations.baseName(of: reference), transform) },
            typing: { FontFeatures.font($0, with: transform(FontFeatures.settings(of: $0))) })
        // Per il testo che si scriverà, il maiuscoletto acceso o spento dal pannello diventa la scelta registrata.
        if selection.range.length == 0, let font = typingAttributes[.font] as? NSFont {
            let shown = SmallCaps.split(FontFeatures.settings(of: font as CTFont)).smallCaps
            typingAttributes[.smallCaps] = shown == .off ? nil : shown.rawValue
        }
    }

    /// Sposta gli assi del font nella selezione, o nel testo che si scriverà.
    private func updateVariations(_ transform: @escaping ([AxisValue]) -> [AxisValue]) {
        guard let reference = selectionFont().font else { return }
        edit(
            selection: { TextStyling.updateVariations(in: $0, range: $1, ofFontNamed: FontVariations.baseName(of: reference), transform) },
            typing: { FontVariations.font($0, with: transform(FontVariations.values(of: $0))) })
        if selection.range.length > 0 { document?.undoManager?.setActionName("Font axes") }
    }

    /// Il simbolo dei font variabili: una «A» sopra un piccolo cursore, la lettera il cui disegno si regola lungo un asse.
    /// È disegnato in nero: il pulsante lo colora secondo lo stato, come i simboli di sistema.
    static let variableFontSymbol: NSImage = {
        let image = NSImage(size: NSSize(width: 15, height: 14), flipped: false) { bounds in
            NSColor.black.set()
            let letter = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .heavy),
                                                                     .foregroundColor: NSColor.black])
            let size = letter.size()
            letter.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height + 1.5))
            let track = NSBezierPath()
            track.move(to: NSPoint(x: 1, y: 2))
            track.line(to: NSPoint(x: bounds.width - 1, y: 2))
            track.lineWidth = 1.2
            track.lineCapStyle = .round
            track.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.4, y: 0, width: 4, height: 4)).fill()
            return true
        }
        image.accessibilityDescription = "Variable font"
        return image
    }()

    /// Il pulsante Variabile: passa dal font variabile della famiglia alle istanze statiche e viceversa.
    @objc func toggleVariableFont(_ sender: Any?) {
        guard let reference = selectionFont().font else { return }
        switchFontFile(variable: !FontVariations.isVariable(reference))
        window?.makeFirstResponder(pagesView)
    }

    /// Per una famiglia installata sia come font a più assi sia in file statici, passa da un'installazione all'altra.
    private func switchFontFile(variable: Bool) {
        guard let reference = selectionFont().font else { return }
        let family = CTFontCopyFamilyName(reference) as String
        edit(
            selection: { TextStyling.switchFontFile(in: $0, range: $1, family: family, variable: variable) },
            typing: { CTFontCopyFamilyName($0) as String == family ? FontVariations.counterpart(of: $0, variable: variable) : nil })
        if selection.range.length > 0 { document?.undoManager?.setActionName(variable ? "Multi-axis font" : "Static font") }
    }

    /// Mentre si trascina un cursore del pannello ogni passo modifica il documento: li si raccoglie in un solo
    /// passo di annullamento, dall'inizio alla fine del trascinamento.
    func groupContinuousChanges(_ dragging: Bool, actionName: String) {
        guard dragging != (undoGroupName != nil), let undoManager = (document as? NSDocument)?.undoManager else { return }
        if dragging {
            endUndoStep(next: .none)
            undoGroupName = actionName
            undoManager.beginUndoGrouping()
        } else {
            let name = undoGroupName ?? actionName
            undoGroupName = nil
            undoManager.endUndoGrouping()
            undoManager.setActionName(name)
        }
    }

    /// Le famiglie installate, come le mostrano i menu: i corpi ottici riuniti, in ordine alfabetico.
    static func menuFamilies() -> [String] {
        OpticalFonts.families(NSFontManager.shared.availableFontFamilies).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Riempie il menu delle famiglie. Con il raggruppamento acceso (Impostazioni › Fonts), le famiglie che cominciano
    /// con la stessa parola stanno in un sottomenu; restano anche come voci nascoste in cima, perché il pulsante possa
    /// mostrare come scelta corrente una famiglia che sta in un sottomenu.
    func fillFamilyPopup() {
        let selected = familyPopup.titleOfSelectedItem
        let families = Self.menuFamilies()
        familyPopup.removeAllItems()
        if FontMenuPreferences.groupsFamilies, let menu = familyPopup.menu {
            let entries = FontFamilyMenu.entries(families)
            for case .group(_, let members) in entries {
                for family in members {
                    let hidden = NSMenuItem(title: family, action: nil, keyEquivalent: "")
                    hidden.isHidden = true
                    menu.addItem(hidden)
                }
            }
            for entry in entries {
                switch entry {
                case .family(let family):
                    let choice = NSMenuItem(title: family, action: #selector(familyMenuItemChosen(_:)), keyEquivalent: "")
                    choice.target = self
                    menu.addItem(choice)
                case .group(let word, let members):
                    let item = NSMenuItem(title: word, action: nil, keyEquivalent: "")
                    let submenu = NSMenu(title: word)
                    for family in members {
                        let choice = NSMenuItem(title: family, action: #selector(familyMenuItemChosen(_:)), keyEquivalent: "")
                        choice.target = self
                        submenu.addItem(choice)
                    }
                    item.submenu = submenu
                    menu.addItem(item)
                }
            }
        } else {
            familyPopup.addItems(withTitles: families)
            for item in familyPopup.itemArray {
                item.action = #selector(familyMenuItemChosen(_:))
                item.target = self
            }
        }
        if let selected { familyPopup.selectItem(withTitle: selected) }
        markFamily(selected)
    }

    /// La spunta sulla famiglia attiva: sulla sua voce e, se sta in un gruppo, anche sulla voce del gruppo.
    func markFamily(_ family: String?) {
        for item in familyPopup.itemArray where !item.isHidden {
            if let submenu = item.submenu {
                var contains = false
                for member in submenu.items {
                    member.state = member.title == family ? .on : .off
                    contains = contains || member.title == family
                }
                item.state = contains ? .on : .off
            } else {
                item.state = item.title == family ? .on : .off
            }
        }
    }

    /// La voce visibile su cui aprire il menu delle famiglie: la famiglia attiva, o il suo gruppo.
    func familyPositioningItem() -> NSMenuItem? {
        let family = familyPopup.titleOfSelectedItem
        return familyPopup.itemArray.first { !$0.isHidden && ($0.title == family || $0.submenu?.items.contains { $0.title == family } == true) }
            ?? familyPopup.itemArray.first { !$0.isHidden }
    }

    func fontMenuGroupingChanged() {
        fillFamilyPopup()
        inspector.groupsFamilies = FontMenuPreferences.groupsFamilies
        styleInspector.groupsFamilies = FontMenuPreferences.groupsFamilies
        refreshFromSelection()
    }

    /// Una famiglia scelta in un sottomenu: vale come sceglierla nel menu.
    @objc private func familyMenuItemChosen(_ sender: NSMenuItem) {
        familyPopup.selectItem(withTitle: sender.title)
        familyChanged(familyPopup)
    }

    @objc func familyChanged(_ sender: NSPopUpButton) {
        guard let family = sender.titleOfSelectedItem else { return }
        var values = StyleValues()
        values.family = family
        editInspected(.family, actionName: "Family") {
            TextStyling.setValue(values, of: .family, in: $0, range: $1, resolver: fontRoleResolver)
        }
        window?.makeFirstResponder(pagesView)
    }

    @objc func faceChanged(_ sender: NSPopUpButton) {
        guard let postScriptName = sender.selectedItem?.representedObject as? String else { return }
        applyFace(postScriptName)
    }

    @objc private func faceButtonChanged(_ sender: NSButton) {
        guard let postScriptName = sender.identifier?.rawValue else { return }
        applyFace(postScriptName)
    }

    private func applyFace(_ postScriptName: String) {
        edit(
            selection: { TextStyling.setFont(postScriptName: postScriptName, in: $0, range: $1) },
            typing: { current in
                guard let base = FontVariations.font(named: postScriptName, size: current.pointSize,
                                                     preferringVariable: FontVariations.isVariable(current)) else { return nil }
                return OpticalFonts.font(base, opticalSize: currentStaticOpticalSize() ?? OpticalFonts.opticalSize(of: current))
            })
        window?.makeFirstResponder(pagesView)
    }

    private func currentStaticOpticalSize() -> StaticOpticalSize? {
        let attributes = selection.range.length > 0 && selection.range.location < documentText.length
            ? documentText.attributes(at: selection.range.location, effectiveRange: nil) : typingAttributes
        return (attributes[.fontOpticalSize] as? String).flatMap(StaticOpticalSize.init(rawValue:))
    }

    private func applyStaticOpticalSize(_ size: StaticOpticalSize?) {
        guard let reference = selectionFont().font, OpticalFonts.opticalSize(of: reference) != nil else { return }
        let family = OpticalFonts.family(of: reference)
        edit(
            selection: { TextStyling.setStaticOpticalSize(size, in: $0, range: $1, family: family) },
            typing: { OpticalFonts.font($0, opticalSize: size) })
        if selection.range.length == 0 {
            if let size { typingAttributes[.fontOpticalSize] = size.rawValue }
            else { typingAttributes.removeValue(forKey: .fontOpticalSize) }
            refreshFromSelection()
        } else {
            document?.undoManager?.setActionName(size == nil ? "Automatic optical size" : "Fixed optical size")
        }
        window?.makeFirstResponder(pagesView)
    }

    /// Acceso: il disegno ottico segue il corpo. Spento: conserva quello attuale anche cambiando corpo.
    @objc func toggleOpticalSize(_ sender: NSButton) {
        guard let reference = selectionFont().font else { return }
        if let staticSize = OpticalFonts.opticalSize(of: reference) {
            applyStaticOpticalSize(currentStaticOpticalSize() == nil ? staticSize : nil)
            return
        }
        guard FontVariations.axes(of: reference).contains(where: { $0.tag == "opsz" }) else { return }
        let automatic = FontVariations.values(of: reference).contains { $0.tag == "opsz" }
        edit(
            selection: { TextStyling.setOpticalSize(automatic: automatic, in: $0, range: $1, ofFontNamed: FontVariations.baseName(of: reference)) },
            typing: { FontVariations.font($0, automaticOpticalSize: automatic) })
        if selection.range.length > 0 { document?.undoManager?.setActionName(automatic ? "Automatic optical size" : "Fixed optical size") }
        window?.makeFirstResponder(pagesView)
    }

    @objc func opticalSizeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        applyStaticOpticalSize(raw.isEmpty ? nil : StaticOpticalSize(rawValue: raw))
    }

    @objc func sizeChanged(_ sender: NSControl) {
        guard let size = Self.sizeFormatter.number(from: sender.stringValue)?.doubleValue, size >= 1, size <= 2000 else {
            refreshFromSelection()
            return
        }
        let fixed = currentStaticOpticalSize()
        edit(
            selection: { TextStyling.setSize(size, in: $0, range: $1) },
            typing: { fixed == nil ? TextStyling.resized($0, to: size) : OpticalFonts.resized($0, to: size, opticalSize: fixed) })
        window?.makeFirstResponder(pagesView)
    }

    // MARK: Esportazione

    /// Compone il documento con il nostro layout Core Text (A4, margini di 25 mm) e lo scrive come PDF.
    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let title = (document as? NSDocument)?.displayName ?? window.title
        panel.nameFieldStringValue = (title as NSString).deletingPathExtension + ".pdf"
        // Che si distingua da «Salva con nome…», che altrimenti ha lo stesso aspetto.
        panel.message = "Export the document as PDF"
        panel.prompt = "Export"
        panel.isExtensionHidden = false
        let text = NSAttributedString(attributedString: documentText)
        let setup = settings.pageSetup
        let options = documentLayoutOptions
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let data = PDFRenderer.pdfData(for: PageLayout.layout(text, setup: setup, options: options), title: title)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    // MARK: Stampa

    /// Il documento come lo si stampa: le stesse pagine del PDF esportato, e il formato del foglio.
    func printablePDF(title: String?) -> (data: Data, paperSize: CGSize) {
        let setup = settings.pageSetup
        let layout = PageLayout.layout(NSAttributedString(attributedString: documentText), setup: setup, options: documentLayoutOptions)
        return (PDFRenderer.pdfData(for: layout, title: title), setup.paperSize)
    }

    /// Il pulsante della barra: lo stesso comando di File › Stampa… (⌘P), che passa dal documento.
    @objc func printFromBar(_ sender: Any?) {
        (document as? NSDocument)?.printDocument(sender)
    }

    // MARK: Tabelle (menu Inserisci) (i metodi sono in EditorWindowController+Inserisci.swift)
    /// Vero se il cursore sta nel testo del documento e non in una tabella: lì si può inserire una tabella.
    var canInsertTable: Bool { noteAnchor == nil && TableEditing.cell(at: selection.range.location, in: store) == nil }

    /// Per le prove: la risposta alla domanda «Togliere la sezione…?» (la domanda non si mostra).
    var sectionRemovalAnswerForTests: Bool?

    // MARK: Deposito

    /// Il deposito registra i suoi passi nel gestore dell'annullamento del documento, che esiste solo quando la
    /// finestra è già legata al documento: lo si collega alla prima modifica.
    private func connectStoreUndo() {
        if store.undoManager == nil { store.undoManager = document?.undoManager }
    }

    private func connectStore() {
        store.onEdit = { [weak self] edit in self?.noteTouched(edit) }
        store.onRevert = { [weak self] range, selection in self?.storeDidRevert(range, restoring: selection) }
        store.currentSelection = { [weak self] in self?.selection.range ?? NSRange(location: 0, length: 0) }
    }

    /// Il testo è stato sostituito per intero (apertura, «Ripristina»): un deposito nuovo, con gli stessi collegamenti.
    /// I passi da annullare del deposito di prima si buttano: si riferivano a lui.
    func resetStore(to text: NSAttributedString) {
        let old = store
        old.onEdit = nil
        old.onRevert = nil
        old.currentSelection = nil
        old.undoManager?.removeAllActions(withTarget: old)
        old.undoManager = nil
        store = DocumentStore(text: text)
        connectStore()
    }

    /// Scrive nel deposito: `body` lo modifica con le sue operazioni. Poi si riparano note, elenchi, attributi e
    /// spaziatura `trak` nel tratto toccato, e si ricompone. Con `breakingUndo` la modifica è un passo a sé (un
    /// comando); senza, si accoda ai tasti di prima.
    @discardableResult
    func writeStore(actionName: String?, breakingUndo: Bool = true, recordsUndo: Bool = true, _ body: (DocumentStore) -> Void) -> NSRange? {
        connectStoreUndo()
        let store = store
        // Un comando sulle sezioni può creare uno stile di titolo («Titolo 4»): il deposito lavora sul foglio corrente.
        store.settings.styles = settings.styles
        if breakingUndo { store.breakUndoCoalescing() }
        let stepsBefore = store.registeredSteps
        let selectionBefore = selection.range
        touchedByStore = nil
        func run() {
            body(store)
            if let touched = touchedByStore {
                let range = NSIntersectionRange(NSRange(location: max(touched.location - 1, 0), length: touched.length + 2), NSRange(location: 0, length: store.length))
                TextStyling.repairFootnotes(in: store, range: range)
                TextStyling.repairLists(in: store, range: range)
                // Un titolo toccato (spezzato con Invio, unito al paragrafo prima): i segni tornano a dire l'albero esatto.
                if Self.touchesSectionMarks(store, range) { SectionEditing.normalize(store) }
                // Lo stile di paragrafo è uguale in tutto il paragrafo. Il font invece non si corregge: la sostituzione di
                // Apple (`fixAttributes`) scriverebbe nel documento un font di ripiego al posto di quello scelto (Muna, che
                // non ha lettere latine, diventava Helvetica). I caratteri che il font non ha li disegna comunque Core
                // Text con un font di ripiego, senza cambiare il testo.
                store.fixParagraphStyleAttribute(in: (store.string as NSString).paragraphRange(for: range))
                TextStyling.syncFontTracking(in: store, range: range, enabled: settings.appliesFontTracking)
            }
        }
        if recordsUndo { run() } else { store.withoutUndo(run) }
        if store.settings.styles != settings.styles { stylesChangedInStore() }
        // Un comando ricorda dove stava il cursore: Annulla ce lo rimette. La scrittura no (U6: il cursore va alla fine del
        // punto cambiato).
        if breakingUndo, recordsUndo { store.rememberSelection(selectionBefore, forStepsAfter: stepsBefore) }
        let touched = touchedByStore
        touchedByStore = nil
        if let actionName, recordsUndo, store.registeredSteps > stepsBefore { document?.undoManager?.setActionName(actionName) }
        textChanged()
        return touched
    }

    /// I caratteri toccati dalla scrittura in corso nel deposito (approssimati per eccesso).
    private var touchedByStore: NSRange?

    /// Vero se nel tratto c'è il segno di un titolo di sezione (o l'ultimo a capo porta quello del paragrafo finale).
    private static func touchesSectionMarks(_ text: NSAttributedString, _ range: NSRange) -> Bool {
        var found = false
        for key in [NSAttributedString.Key.sectionTitle, .sectionReturn] where !found {
            text.enumerateAttribute(key, in: range) { value, _, stop in
                if value != nil { found = true; stop.pointee = true }
            }
        }
        let atEnd = NSMaxRange(range) >= text.length && text.length > 0
        return found || atEnd && [NSAttributedString.Key.finalParagraphSection, .finalParagraphSectionReturn].contains {
            text.attribute($0, at: text.length - 1, effectiveRange: nil) != nil
        }
    }

    private func noteTouched(_ edit: DocumentStore.Edit) {
        let changed: NSRange = switch edit {
        case .replaced(let range, let text): NSRange(location: range.location, length: text.length)
        case .attributes(_, let range): range
        }
        touchedByStore = touchedByStore.map { NSUnionRange($0, changed) } ?? changed
    }

    /// Il deposito ha cambiato il foglio degli stili (un comando, o Annulla): l'editor riprende la sua copia.
    private func stylesChangedInStore() {
        settings.styles = store.settings.styles
        reloadStylePopup()
        definitionsPanel?.documentChanged()
    }

    /// Dopo un annullamento o un ripristino del deposito: il cursore va sui caratteri cambiati, e si ricompone.
    /// Dopo «Annulla» o «Ripeti»: se è stato aggiunto o tolto testo, il cursore va alla fine del punto cambiato, come
    /// dopo aver scritto; se è cambiato solo l'aspetto (uno stile, il grassetto), il testo toccato resta selezionato.
    private func storeDidRevert(_ range: NSRange, restoring remembered: NSRange?) {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: store.length))
        if store.lastRevertChangedStyles { stylesChangedInStore() }
        markedRange = nil
        if let remembered {
            // Un comando: il cursore torna dov'era prima (Annulla) o dopo (Ripeti).
            let location = min(remembered.location, store.length)
            setSelection(TextSelection(anchor: location, head: min(NSMaxRange(remembered), store.length)), textChanged: true)
        } else if store.lastRevertChangedLength {
            setSelection(TextSelection(caret: NSMaxRange(clamped)), textChanged: true)
        } else {
            setSelection(TextSelection(anchor: clamped.location, head: NSMaxRange(clamped)), textChanged: true)
        }
        textChanged()
    }

    // MARK: Cerca e sostituisci (i metodi sono in EditorWindowController+Cerca.swift)
    var findBarForTests: FindBar { findBar }

    var isFindBarVisible: Bool { !findBar.view.isHidden }

    // MARK: Ispettore e percorso degli oggetti (i metodi sono in EditorWindowController+Ispettore.swift)
    /// I pulsanti del percorso delle sezioni, per le prove.
    var sectionPathTitlesForTests: [String] { sectionPathTitles }

    /// Le proprietà dinamiche che l'ispettore mostra ora.
    var inspectorFacts: [InspectorModel.Fact] { inspector.facts }

    // MARK: La scheda Stili (i metodi sono in EditorWindowController+Stili.swift)
    /// Le modifiche ai valori di uno stile in attesa della pausa: un selettore dei colori ne manda una a ogni movimento,
    /// e ognuna ricomporrebbe tutto il testo che usa lo stile (circa 190 ms su 100 pagine). Si applicano insieme dopo
    /// `stylePause`, in un passo solo di «Annulla»; intanto il modulo mostra già lo stile nuovo.
    var pendingStyles: (sheet: StyleSheet, name: String, property: InspectorProperty)?

    var pendingStyleTimer: Timer?

    /// Le regole e gli stili del documento, e i nomi delle Liste (per le prove: senza passare dal salvataggio).
    var rules: [TextRule] { settings.rules }

    var listNames: [String] { settings.lists.map(\.name) }

    var styleSheet: StyleSheet { settings.styles }

    var isAskingAboutOverflow = false

    // MARK: Sillabazione e lingua (menu Formato)

    @objc func toggleHyphenation(_ sender: Any?) {
        change(\.hyphenates, to: !settings.hyphenates, actionName: "Hyphenation")
    }

    @objc func setDocumentLanguage(_ sender: NSMenuItem) {
        change(\.language, to: sender.representedObject as? String, actionName: "Document Language")
    }

    /// Assegna una lingua al testo selezionato (o, senza selezione, a quello che si scriverà); `nil` lo riporta
    /// alla lingua del documento.
    @objc func setSelectionLanguage(_ sender: NSMenuItem) {
        let language = sender.representedObject as? String
        let range = selection.range
        if range.length == 0 {
            typingAttributes[.language] = language
        } else {
            endUndoStep(next: .none)
            writeStore(actionName: "Text Language") { store in
                if let language { store.addAttribute(.language, value: language, range: range) } else { store.removeAttribute(.language, range: range) }
            }
        }
    }

    /// La lingua assegnata al testo selezionato: `.some(nil)` se è quella del documento, `nil` se la selezione ne mescola più d'una.
    func selectionLanguage() -> String?? {
        let range = selection.range
        guard let storage = textStorage, range.length > 0 else { return .some(typingAttributes[.language] as? String) }
        var effective = NSRange(location: 0, length: 0)
        let language = storage.attribute(.language, at: range.location, longestEffectiveRange: &effective, in: range) as? String
        return NSMaxRange(effective) >= NSMaxRange(range) ? .some(language) : nil
    }

    // MARK: Ingrandimento (menu Vista e barra) (i metodi sono in EditorWindowController+Vista.swift)
    /// La finestra com'era prima che lo zoom la allargasse; `nil` se lo zoom non l'ha allargata, o se poi la si è
    /// ridimensionata a mano.
    var frameBeforeZoom: NSRect?

    /// L'ultima cornice data alla finestra dallo zoom: se al prossimo cambio di zoom la finestra ne ha un'altra, la si è
    /// ridimensionata a mano. (Non si ascoltano gli avvisi di ridimensionamento: con il pizzico arrivano in ritardo, e un
    /// ridimensionamento dello zoom sembrava fatto a mano.)
    var frameSetByZoom: NSRect?

    // MARK: Stato della vista conservato nel file (i metodi sono in EditorWindowController+Vista.swift)
    var pagesHeightForTests: CGFloat { pagesView.frame.height }

}
