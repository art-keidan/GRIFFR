import AppKit
import SwiftUI
import Typesetting

/// A chi vanno le modifiche della progettazione: allo stile del capoverso (tutti i capoversi con quello stile) o al
/// solo capoverso evidenziato (come valori dati a mano).
enum ParagraphDesignScope: Hashable { case style, paragraph }

/// Le modifiche della progettazione non ancora salvate. Le pagine le mostrano dal vivo su una copia del testo; il
/// documento cambia solo con Salva, in un passo di Annulla. Annulla le scarta.
struct ParagraphDesignDraft: Equatable {
    /// I valori messi negli stili, stile per stile.
    var styleEdits: [String: [InspectorProperty: StyleValues]] = [:]
    /// Lo stile dopo Invio, stile per stile (`nil` = lo stesso stile).
    var nextStyles: [String: String?] = [:]
    /// I valori dati al solo capoverso, capoverso per capoverso (per identità: non cambia scrivendo).
    var paragraphEdits: [DocumentStore.ParagraphID: [InspectorProperty: StyleValues]] = [:]
    /// I valori dati a mano che un capoverso perde, perché ora li dà lo stile.
    var ownResets: [DocumentStore.ParagraphID: Set<InspectorProperty>] = [:]
    /// Formato e margini: per tipo di pagina ("" il tipo predefinito).
    var pageSetups: [String: PageSetup] = [:]

    var isEmpty: Bool { self == ParagraphDesignDraft() }
}

/// La progettazione del capoverso in corso: quale capoverso, il suo stile, i valori (della bozza), il gesto in atto.
@MainActor
final class ParagraphDesignSession {
    /// L'inizio del capoverso, come lo portano le righe composte.
    var paragraphLocation = 0
    var paragraphID: DocumentStore.ParagraphID?
    /// Lo stile che riceve le modifiche; `nil` se il capoverso non ne ha uno.
    var styleName: String?
    /// I valori di paragrafo del capoverso come sono nella bozza, e la loro provenienza nel documento.
    var values: [InspectorProperty: InspectedValue] = [:]
    var documentSources: [InspectorProperty: ValueSource] = [:]
    var scope = ParagraphDesignScope.style
    /// Aggiornamento dal vivo di tutti i capoversi dello stile; spento, l'anteprima tocca solo quello evidenziato.
    var livePreviewAll = true
    var draft = ParagraphDesignDraft()
    /// Annulla e Ripeti dentro la bozza.
    var undoStack: [ParagraphDesignDraft] = []
    var redoStack: [ParagraphDesignDraft] = []
    /// La maniglia trascinata: il valore all'inizio del gesto e quello mostrato ora.
    var drag: (handle: DesignHandle, start: CGFloat, value: CGFloat)?
    /// La tenuta trascinata: da che parte, quante righe all'inizio e ora.
    var keepDrag: (side: KeepSide, start: Int, value: Int)?
    /// Il margine trascinato: la pagina, il lato, il valore all'inizio e ora.
    var marginDrag: (page: Int, side: MarginSide, start: CGFloat, value: CGFloat)?
    /// Il testo della bozza (il documento con le modifiche), per leggerne i valori; `nil` senza bozza.
    var draftText: NSAttributedString?
    let bar = ParagraphDesignBarModel()

    func number(_ property: InspectorProperty) -> CGFloat {
        guard let value = values[property]?.value else { return 0 }
        let number: Double? = switch property {
        case .leftIndent: value.leftIndent
        case .rightIndent: value.rightIndent
        case .firstLineIndent: value.firstLineIndent
        case .spaceBefore: value.spaceBefore
        case .spaceAfter: value.spaceAfter
        case .lineSpacing: value.lineSpacing
        default: nil
        }
        return CGFloat(number ?? 0)
    }
}

extension EditorWindowController {
    // MARK: Progettazione del capoverso sulla pagina

    var isDesigningParagraph: Bool { paragraphDesign != nil }

    /// Fascia del paragrafo › Design, Vista › Design Paragraph (⌥⌘G): entra; uscendo così, la bozza si salva.
    @objc func toggleParagraphDesign(_ sender: Any?) {
        if paragraphDesign == nil { setParagraphDesign(true) } else { saveParagraphDesign() }
    }

    func setParagraphDesign(_ on: Bool) {
        guard on != (paragraphDesign != nil) else { return }
        if on {
            let session = ParagraphDesignSession()
            connectDesignBar(session.bar)
            paragraphDesign = session
            pagesView.onDesignDrag = { [weak self] handle, delta, phase, modifiers in self?.designDragged(handle, by: delta, phase: phase, modifiers: modifiers) }
            pagesView.onMarginDrag = { [weak self] page, side, delta, phase, modifiers in self?.marginDragged(page: page, side: side, by: delta, phase: phase, modifiers: modifiers) }
            pagesView.onDesignLockedHandle = { [weak self] handle in self?.openDesignFormula(handle.property) }
            pagesView.onKeepDrag = { [weak self] side, count, phase in self?.keepDragged(side, count: count, phase: phase) }
            pagesView.onKeepLocked = { [weak self] _ in self?.openDesignFormula(.keepWithNext) }
            pagesView.designBar = NSHostingView(rootView: ParagraphDesignBar(model: session.bar).themed())
            pagesView.designActions = NSHostingView(rootView: ParagraphDesignActions(model: session.bar).themed())
        } else {
            let hadPreview = paragraphDesign?.draft.isEmpty == false || paragraphDesign?.drag != nil || paragraphDesign?.marginDrag != nil
            paragraphDesign = nil
            pagesView.designDrag = nil
            pagesView.hoveredDesignHandle = nil
            pagesView.design = nil
            pagesView.designBar = nil
            pagesView.designActions = nil
            // Le pagine tornano quelle del documento.
            if hadPreview { layoutPages() }
        }
        (bandControls["progetta"] as? NSButton)?.state = on ? .on : .off
        refreshParagraphDesign()
        if on { pagesView.scrollCaretToVisible() }
        window?.makeFirstResponder(pagesView)
    }

    /// Salva: tutta la bozza va nel documento in un passo di Annulla, e la progettazione finisce.
    func saveParagraphDesign() {
        guard let session = paragraphDesign else { return }
        let draft = session.draft
        setParagraphDesign(false)
        guard !draft.isEmpty else { return }
        let actionName = "Paragraph Design"
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        let sheet = draftSheet(draft)
        if sheet != settings.styles { changeStyles(to: sheet, restyle: true, actionName: actionName) }
        if !draft.ownResets.isEmpty || !draft.paragraphEdits.isEmpty {
            let current = settings.styles
            writeStore(actionName: actionName) { store in self.applyParagraphChanges(draft, to: store, store: store, sheet: current) }
            layoutPages()
        }
        if let setup = draft.pageSetups[""] { change(\.pageSetup, to: setup, actionName: actionName) }
        let named = draft.pageSetups.filter { !$0.key.isEmpty }
        if !named.isEmpty {
            var types = settings.pageTypes
            for (name, setup) in named { if let index = types.firstIndex(where: { $0.name == name }) { types[index].setup = setup } }
            change(\.pageTypes, to: types, actionName: actionName)
        }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(actionName)
        refreshFromSelection()
    }

    /// Annulla: la bozza si scarta, il documento resta com'era.
    func cancelParagraphDesign() { setParagraphDesign(false) }

    /// Rilegge il capoverso del cursore e le sue misure, dalla bozza. Mentre si trascina, valgono quelle dell'anteprima.
    func refreshParagraphDesign() {
        selectionPanelModel.isDesigning = paragraphDesign != nil
        guard let session = paragraphDesign, session.drag == nil, session.marginDrag == nil, session.keepDrag == nil else { return }
        let source = documentText
        guard source.length > 0 else {
            session.styleName = nil
            pagesView.design = nil
            selectionPanelModel.styleName = nil
            return
        }
        let location = currentParagraphLocation()
        let at = min(location, source.length - 1)
        let paragraphID = store.length > 0 ? store.paragraphID(at: at) : nil
        if session.paragraphID != paragraphID, !session.livePreviewAll, !session.draft.isEmpty {
            session.paragraphID = paragraphID
            showDraft(session.draft)
        }
        let text = session.draftText ?? source
        let name = TextStyling.receivingStyle(for: .leftIndent, in: source, at: at)?.name
        let sheet = draftSheet(session.draft)
        let inspected = TextStyling.inspect(.paragraph, in: text, range: NSRange(location: at, length: 0), sheet: sheet, resolver: fontRoleResolver)
        let original = TextStyling.inspect(.paragraph, in: source, range: NSRange(location: at, length: 0), sheet: settings.styles, resolver: fontRoleResolver)
        session.paragraphLocation = location
        session.paragraphID = paragraphID
        session.styleName = name
        session.values = Dictionary(inspected.map { ($0.property, $0) }, uniquingKeysWith: { first, _ in first })
        session.documentSources = Dictionary(original.map { ($0.property, $0.source) }, uniquingKeysWith: { first, _ in first })
        var overlay = ParagraphDesignOverlay(paragraphLocation: location,
                                             values: Dictionary(uniqueKeysWithValues: DesignHandle.allCases.map { ($0, session.number($0.property)) }),
                                             locked: Set(DesignHandle.allCases.filter { isDesignLocked($0.property) }))
        overlay.keep = [.next: keepCount(session, .next), .previous: keepCount(session, .previous)]
        overlay.keepLocked = Set([KeepSide.next, .previous].filter { side in Self.keepProperties(side).contains { isDesignLocked($0) } })
        pagesView.design = overlay
        selectionPanelModel.styleName = name
        refreshDesignBar(session, text: text, sheet: sheet, at: at)
    }

    /// Una misura calcolata da una formula dello stile non si cambia nello stile (si cambia nel compositore); per il
    /// solo capoverso sì, come valore dato a mano.
    func isDesignLocked(_ property: InspectorProperty) -> Bool {
        guard let session = paragraphDesign else { return true }
        guard session.scope == .style else { return false }
        guard let name = session.styleName else { return true }
        return settings.styles.formulaDefinition(for: property, inStyle: name)?.isCalculated == true
    }

    /// I valori dei pulsanti intorno al capoverso.
    private func refreshDesignBar(_ session: ParagraphDesignSession, text: NSAttributedString, sheet: StyleSheet, at: Int) {
        let bar = session.bar
        let values = session.values
        func value(_ property: InspectorProperty) -> StyleValues { values[property]?.value ?? StyleValues() }
        bar.styleName = session.styleName
        bar.scope = session.scope
        bar.livePreviewAll = session.livePreviewAll
        bar.hasChanges = !session.draft.isEmpty
        bar.alignment = value(.alignment).alignment ?? .left
        bar.lineHeightMultiple = value(.lineHeightMultiple).lineHeightMultiple ?? 0
        bar.keepTogether = value(.keepTogether).keeping.together ?? false
        bar.keepWithNext = value(.keepWithNext).keeping.withNext ?? false
        bar.linesAtEnd = value(.orphanLines).keeping.linesAtEnd ?? 1
        bar.linesAtStart = value(.widowLines).keeping.linesAtStart ?? 1
        bar.listName = value(.list).listName ?? ""
        bar.lists = settings.lists.map(\.name)
        bar.openingDistance = value(.openingDistance).openingDistance ?? 0
        let word = TextStyling.inspect(.word, in: text, range: NSRange(location: at, length: 0), sheet: sheet, resolver: fontRoleResolver)
        bar.hyphenates = word.first { $0.property == .hyphenates }?.value.hyphenates ?? settings.hyphenates
        bar.language = word.first { $0.property == .language }?.value.language ?? ""
        bar.languages = Self.languages.map { ($0, Self.languageName($0)) }
        let character = TextStyling.inspect(.character, in: text, range: NSRange(location: at, length: 0), sheet: sheet, resolver: fontRoleResolver)
        bar.family = character.first { $0.property == .family }?.value.family ?? ""
        bar.size = character.first { $0.property == .size }?.value.size ?? 12
        bar.families = Self.menuFamilies()
        bar.paragraphStyles = sheet.styles.filter { $0.target == .paragraph }.map(\.name)
        bar.nextStyle = session.styleName.flatMap { sheet.style(named: $0)?.values.nextStyle }
        bar.locked = Set(InspectorProperty.allCases.filter { isDesignLocked($0) })
    }

    private func connectDesignBar(_ bar: ParagraphDesignBarModel) {
        bar.set = { [weak self] property, values in self?.designEdit(property, values) }
        bar.setNextStyle = { [weak self] name in self?.designSetNextStyle(name) }
        bar.setScope = { [weak self] scope in
            guard let self, let session = self.paragraphDesign else { return }
            session.scope = scope
            self.showDraft(session.draft)
            self.refreshParagraphDesign()
        }
        bar.setLivePreviewAll = { [weak self] on in
            guard let self, let session = self.paragraphDesign else { return }
            session.livePreviewAll = on
            self.showDraft(session.draft)
            self.refreshParagraphDesign()
        }
        bar.openFormula = { [weak self] property in self?.openDesignFormula(property) }
        bar.save = { [weak self] in self?.saveParagraphDesign() }
        bar.cancel = { [weak self] in self?.cancelParagraphDesign() }
    }

    // MARK: La bozza

    /// Gli stili con le modifiche della bozza.
    func draftSheet(_ draft: ParagraphDesignDraft) -> StyleSheet {
        var sheet = settings.styles
        let base = settings.formulaBase ?? TextStyling.styleBase
        for (name, edits) in draft.styleEdits.sorted(by: { $0.key < $1.key }) {
            for (property, values) in edits.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                sheet = sheet.setting(values, of: property, inStyle: name, base: base)
            }
        }
        for (name, next) in draft.nextStyles {
            if let index = sheet.styles.firstIndex(where: { $0.name == name }) { sheet.styles[index].values.nextStyle = next }
        }
        return sheet
    }

    /// I valori dati a mano tolti e quelli dati al solo capoverso, su un testo (la copia dell'anteprima o il deposito).
    private func applyParagraphChanges(_ draft: ParagraphDesignDraft, to text: NSMutableAttributedString, store: DocumentStore, sheet: StyleSheet) {
        for (id, properties) in draft.ownResets {
            guard let range = store.range(of: id), range.length > 0 else { continue }
            for property in properties.sorted(by: { $0.rawValue < $1.rawValue }) where draft.paragraphEdits[id]?[property] == nil {
                TextStyling.resetValue(of: property, in: text, range: range, sheet: sheet, resolver: fontRoleResolver)
            }
        }
        for (id, edits) in draft.paragraphEdits {
            guard let range = store.range(of: id), range.length > 0 else { continue }
            for (property, values) in edits.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                TextStyling.setValue(values, of: property, in: text, range: range, resolver: fontRoleResolver)
            }
        }
    }

    /// Il documento con la bozza: il testo, le opzioni e il formato con cui comporlo.
    private func draftDocument(_ draft: ParagraphDesignDraft) -> (text: NSMutableAttributedString, options: LayoutOptions, setup: PageSetup) {
        let copy = NSMutableAttributedString(attributedString: documentText)
        var document = settings
        let sheet = draftSheet(draft)
        var localPreviewRange: NSRange?
        if sheet != settings.styles {
            // Senza l'aggiornamento dal vivo di tutti, cambia solo il capoverso evidenziato; gli altri restano come sono.
            var range = NSRange(location: 0, length: copy.length)
            if paragraphDesign?.livePreviewAll == false {
                if let id = paragraphDesign?.paragraphID, let paragraph = store.range(of: id) {
                    range = paragraph
                    localPreviewRange = paragraph
                } else {
                    range = NSRange(location: 0, length: 0)
                }
            }
            TextStyling.restyle(copy, range: range, from: settings.styles, to: sheet,
                                resolver: fontRoleResolver, base: settings.formulaBase ?? TextStyling.styleBase)
            if paragraphDesign?.livePreviewAll != false { document.styles = sheet }
        }
        applyParagraphChanges(draft, to: copy, store: store, sheet: sheet)
        if let range = localPreviewRange, range.length > 0 {
            // Tenuta e distanza d'apertura vengono lette dallo stile durante la
            // composizione: fissiamo sulla copia il valore effettivo del solo
            // paragrafo, preservando eventuali valori locali non rimossi.
            var styleNames = Set<String>()
            var current = copy.attribute(.paragraphStyleName, at: range.location, effectiveRange: nil) as? String
            while let name = current, styleNames.insert(name).inserted {
                current = sheet.style(named: name)?.basedOn
            }
            let properties = Set(draft.styleEdits.filter { styleNames.contains($0.key) }.values.flatMap { $0.keys })
                .filter { $0.isLineKeeping || $0 == .openingDistance }
            let inspected = TextStyling.inspect(.paragraph, in: copy, range: range, sheet: sheet, resolver: fontRoleResolver)
            for value in inspected where properties.contains(value.property) {
                TextStyling.setValue(value.value, of: value.property, in: copy, range: range, resolver: fontRoleResolver)
            }
        }
        if let setup = draft.pageSetups[""] { document.pageSetup = setup }
        for (name, setup) in draft.pageSetups where !name.isEmpty {
            if let index = document.pageTypes.firstIndex(where: { $0.name == name }) { document.pageTypes[index].setup = setup }
        }
        var options = document.layoutOptions
        options.fontRoles = fontRoleResolver.table
        return (copy, options, document.pageSetup)
    }

    /// Le pagine composte dalla bozza (o da una bozza provvisoria, durante un gesto).
    func showDraft(_ draft: ParagraphDesignDraft) {
        guard let session = paragraphDesign else { return }
        if draft.isEmpty {
            session.draftText = nil
            pagesView.layout = PageLayout.layout(documentText, setup: settings.pageSetup, options: documentLayoutOptions)
            return
        }
        let composed = draftDocument(draft)
        session.draftText = composed.text
        pagesView.layout = PageLayout.layout(composed.text, setup: composed.setup, options: composed.options)
    }

    /// Dopo ogni ricomposizione del documento (si è scritto, si è annullato altro): la bozza torna sulle pagine.
    func showParagraphDesignDraftIfNeeded() {
        guard let session = paragraphDesign, !session.draft.isEmpty else { return }
        showDraft(session.draft)
    }

    /// Una modifica alla bozza: un passo dell'Annulla interno.
    private func changeDraft(_ change: (inout ParagraphDesignDraft) -> Void) {
        guard let session = paragraphDesign else { return }
        var draft = session.draft
        change(&draft)
        guard draft != session.draft else {
            showDraft(session.draft)
            return
        }
        session.undoStack.append(session.draft)
        session.redoStack = []
        session.draft = draft
        showDraft(draft)
        refreshParagraphDesign()
    }

    /// La bozza con un valore in più, secondo la portata scelta.
    private func draft(_ draft: ParagraphDesignDraft, setting property: InspectorProperty, _ values: StyleValues) -> ParagraphDesignDraft {
        guard let session = paragraphDesign else { return draft }
        var result = draft
        switch session.scope {
        case .style:
            guard let name = session.styleName else { return draft }
            result.styleEdits[name, default: [:]][property] = values
            if let id = session.paragraphID {
                result.paragraphEdits[id]?[property] = nil
                if result.paragraphEdits[id]?.isEmpty == true { result.paragraphEdits[id] = nil }
                // Un valore dato a mano coprirebbe quello dello stile: il capoverso lo perde.
                if session.documentSources[property] == .own { result.ownResets[id, default: []].insert(property) }
            }
        case .paragraph:
            guard let id = session.paragraphID else { return draft }
            result.paragraphEdits[id, default: [:]][property] = values
        }
        return result
    }

    /// Un valore scelto con un pulsante o alla fine di un gesto.
    func designEdit(_ property: InspectorProperty, _ values: StyleValues) {
        guard paragraphDesign != nil, !isDesignLocked(property) || paragraphDesign?.scope == .paragraph else { return }
        changeDraft { $0 = draft($0, setting: property, values) }
    }

    /// Lo stile che segue con Invio: è una proprietà dello stile, vale per tutti i suoi capoversi.
    func designSetNextStyle(_ next: String?) {
        guard let name = paragraphDesign?.styleName else { return }
        changeDraft { $0.nextStyles[name] = .some(next) }
    }

    /// Annulla e Ripeti durante la progettazione: tolgono e rimettono i passi della bozza. Vero se li ha presi lei.
    func undoParagraphDesign(redo: Bool) -> Bool {
        guard let session = paragraphDesign else { return false }
        if redo {
            guard let next = session.redoStack.popLast() else { return true }
            session.undoStack.append(session.draft)
            session.draft = next
        } else {
            guard let previous = session.undoStack.popLast() else { return true }
            session.redoStack.append(session.draft)
            session.draft = previous
        }
        showDraft(session.draft)
        refreshParagraphDesign()
        return true
    }

    var canUndoParagraphDesign: Bool { paragraphDesign?.undoStack.isEmpty == false }
    var canRedoParagraphDesign: Bool { paragraphDesign?.redoStack.isEmpty == false }

    // MARK: Tenere con le righe dei vicini

    /// Le proprietà che una tenuta cambia.
    static func keepProperties(_ side: KeepSide) -> [InspectorProperty] { side == .next ? [.keepWithNext, .nextLines] : [.previousLines] }

    /// Con quante righe del vicino il capoverso resta, nella bozza: 0 se non tiene.
    func keepCount(_ session: ParagraphDesignSession, _ side: KeepSide) -> Int {
        switch side {
        case .next:
            guard session.values[.keepWithNext]?.value.keeping.withNext == true else { return 0 }
            return session.values[.nextLines]?.value.keeping.nextLines ?? 1
        case .previous:
            return session.values[.previousLines]?.value.keeping.previousLines ?? 0
        }
    }

    /// I valori di una tenuta di `count` righe.
    static func keepEdits(_ side: KeepSide, _ count: Int) -> [(InspectorProperty, StyleValues)] {
        var flag = StyleValues(), lines = StyleValues()
        switch side {
        case .next:
            flag.keeping.withNext = count > 0
            guard count > 0 else { return [(.keepWithNext, flag)] }
            lines.keeping.nextLines = min(count, LineKeeping.lineRange.upperBound)
            return [(.keepWithNext, flag), (.nextLines, lines)]
        case .previous:
            lines.keeping.previousLines = min(count, LineKeeping.previousRange.upperBound)
            return [(.previousLines, lines)]
        }
    }

    func keepDragged(_ side: KeepSide, count: Int, phase: DesignDragPhase) {
        guard let session = paragraphDesign else { return }
        switch phase {
        case .began:
            let start = keepCount(session, side)
            session.keepDrag = (side, start, start)
            pagesView.design?.activeKeep = side
        case .changed, .ended:
            guard var drag = session.keepDrag, drag.side == side else { return }
            if phase == .changed {
                guard count != drag.value else { return }
                drag.value = count
                session.keepDrag = drag
                pagesView.design?.keep[side] = count
                var preview = session.draft
                for (property, values) in Self.keepEdits(side, count) { preview = draft(preview, setting: property, values) }
                showDraft(preview)
                return
            }
            session.keepDrag = nil
            pagesView.design?.activeKeep = nil
            if count != drag.start {
                designEdits(Self.keepEdits(side, count))
            } else {
                showDraft(session.draft)
                refreshParagraphDesign()
            }
        }
    }

    /// Più valori insieme, in un solo passo della bozza.
    func designEdits(_ edits: [(InspectorProperty, StyleValues)]) {
        guard paragraphDesign != nil, !edits.contains(where: { isDesignLocked($0.0) }) else { return }
        changeDraft { draft in for (property, values) in edits { draft = self.draft(draft, setting: property, values) } }
    }

    func dragKeepForTests(_ side: KeepSide, to count: Int) {
        keepDragged(side, count: 0, phase: .began)
        keepDragged(side, count: count, phase: .changed)
        keepDragged(side, count: count, phase: .ended)
    }

    // MARK: Il gesto sulle maniglie

    func designDragged(_ handle: DesignHandle, by delta: CGSize, phase: DesignDragPhase, modifiers: NSEvent.ModifierFlags) {
        guard let session = paragraphDesign, session.styleName != nil || session.scope == .paragraph else { return }
        switch phase {
        case .began:
            let start = session.number(handle.property)
            session.drag = (handle, start, start)
            pagesView.design?.active = handle
        case .changed, .ended:
            guard var drag = session.drag, drag.handle == handle else { return }
            // Al punto intero; con ⌥ al decimo di punto.
            let step: CGFloat = modifiers.contains(.option) ? 0.1 : 1
            let value = max((handle.value(from: drag.start, moved: delta) / step).rounded() * step, handle.minimum)
            if phase == .changed {
                guard value != drag.value else { return }
                drag.value = value
                session.drag = drag
                pagesView.design?.values[handle] = value
                showDraft(draft(session.draft, setting: handle.property, Self.designValues(handle.property, value)))
                return
            }
            session.drag = nil
            pagesView.design?.active = nil
            if value != drag.start {
                designEdit(handle.property, Self.designValues(handle.property, value))
            } else {
                showDraft(session.draft)
                refreshParagraphDesign()
            }
        }
    }

    /// Il valore di una maniglia come valori di stile.
    static func designValues(_ property: InspectorProperty, _ value: CGFloat) -> StyleValues {
        var values = StyleValues()
        let number = Double(value)
        switch property {
        case .leftIndent: values.leftIndent = number
        case .rightIndent: values.rightIndent = number
        case .firstLineIndent: values.firstLineIndent = number
        case .spaceBefore: values.spaceBefore = number
        case .spaceAfter: values.spaceAfter = number
        case .lineSpacing: values.lineSpacing = number
        default: break
        }
        return values
    }

    // MARK: I margini della pagina

    /// Il formato con cui la pagina mostrata ora è composta, e il tipo a cui appartiene ("" il predefinito).
    private func shownSetup(ofPage page: Int) -> (setup: PageSetup, type: String)? {
        guard let layout = pagesView.layout, layout.pages.indices.contains(page) else { return nil }
        let type = layout.pages[page].typeName ?? ""
        return (layout.setup(forPage: page), settings.pageTypes.contains { $0.name == type } ? type : "")
    }

    func marginDragged(page: Int, side: MarginSide, by delta: CGSize, phase: DesignDragPhase, modifiers: NSEvent.ModifierFlags) {
        guard let session = paragraphDesign, let shown = shownSetup(ofPage: page) else { return }
        let field = side.field(onPage: page, facing: shown.setup.facing)
        switch phase {
        case .began:
            let start = shown.setup[keyPath: field]
            session.marginDrag = (page, side, start, start)
            pagesView.activeMargin = (page, side)
        case .changed, .ended:
            guard var drag = session.marginDrag, drag.page == page, drag.side == side else { return }
            // Al mezzo millimetro; con ⌥ al punto.
            let step = modifiers.contains(.option) ? 1 : PageSetup.points(fromMillimetres: 0.5)
            var value = (side.value(from: drag.start, moved: delta) / step).rounded() * step
            // Lo specchio non sparisce: restano almeno 36 punti di testo.
            var setup = shown.setup
            let other: CGFloat = side.isHorizontal ? setup.paperSize.width - setup.left - setup.right + setup[keyPath: field]
                                                    : setup.paperSize.height - setup.top - setup.bottom + setup[keyPath: field]
            value = min(max(value, 0), other - 36)
            setup[keyPath: field] = value
            if phase == .changed {
                guard value != drag.value else { return }
                drag.value = value
                session.marginDrag = drag
                var draft = session.draft
                draft.pageSetups[shown.type] = setup
                showDraft(draft)
                return
            }
            session.marginDrag = nil
            pagesView.activeMargin = nil
            if value != drag.start {
                changeDraft { $0.pageSetups[shown.type] = setup }
            } else {
                showDraft(session.draft)
                refreshParagraphDesign()
            }
        }
    }

    /// Una misura calcolata da una formula: si apre lo stile nel compositore.
    func openDesignFormula(_ property: InspectorProperty) {
        guard let name = paragraphDesign?.styleName else { return }
        showStyleComposer(style: name)
    }

    // MARK: Per le prove

    /// Un trascinamento simulato di una maniglia: lo spostamento in punti di pagina, in basso positivo.
    func dragDesignHandleForTests(_ handle: DesignHandle, by delta: CGSize, modifiers: NSEvent.ModifierFlags = []) {
        designDragged(handle, by: .zero, phase: .began, modifiers: modifiers)
        designDragged(handle, by: CGSize(width: delta.width / 2, height: delta.height / 2), phase: .changed, modifiers: modifiers)
        designDragged(handle, by: delta, phase: .changed, modifiers: modifiers)
        designDragged(handle, by: delta, phase: .ended, modifiers: modifiers)
    }

    func dragMarginForTests(page: Int, side: MarginSide, by delta: CGSize) {
        marginDragged(page: page, side: side, by: .zero, phase: .began, modifiers: [])
        marginDragged(page: page, side: side, by: delta, phase: .changed, modifiers: [])
        marginDragged(page: page, side: side, by: delta, phase: .ended, modifiers: [])
    }

    var paragraphDesignOverlayForTests: ParagraphDesignOverlay? { pagesView.design }
    var paragraphDesignBarForTests: ParagraphDesignBarModel? { paragraphDesign?.bar }
    var paragraphDesignDraftForTests: ParagraphDesignDraft? { paragraphDesign?.draft }
    var paragraphDesignPreviewForTests: NSAttributedString? { paragraphDesign?.draftText }
    var designHandleRectsForTests: [DesignHandle: NSRect] { pagesView.designHandleRects() }
}
