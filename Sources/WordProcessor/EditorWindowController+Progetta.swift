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
    /// La testata, stile per stile (`nil` = nessuna testata propria).
    var headings: [String: HeadingComposition?] = [:]
    /// I filetti liberi: dello stile, del solo capoverso, e i capoversi che perdono i loro filetti dati a mano.
    var styleRules: [String: ParagraphRules] = [:]
    var paragraphRules: [DocumentStore.ParagraphID: ParagraphRules] = [:]
    var ruleResets: Set<DocumentStore.ParagraphID> = []

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
    /// La parte della testata scelta, e la maniglia della testata trascinata (con il valore all'inizio del gesto).
    var selectedHeadingPart: Int?
    var headingDrag: (id: HeadingGripID, start: CGFloat)?
    /// Il filetto scelto, e quello trascinato (con il filetto com'era all'inizio del gesto).
    var selectedRule: Int?
    var ruleDrag: (id: RuleGripID, start: ParagraphRule, space: CGFloat)?
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
            pagesView.onHeadingDrag = { [weak self] id, delta, phase in self?.headingDragged(id, by: delta, phase: phase) }
            pagesView.onHeadingSelect = { [weak self] part in self?.selectHeadingPart(part) }
            pagesView.onRuleDrag = { [weak self] id, delta, phase, modifiers in self?.ruleDragged(id, by: delta, phase: phase, modifiers: modifiers) }
            pagesView.onRuleSelect = { [weak self] rule in self?.selectRule(rule) }
            pagesView.onDesignBarWidth = { [weak self] width in
                guard let self, let bar = self.paragraphDesign?.bar, abs(bar.maxWidth - width) > 1 else { return }
                bar.maxWidth = width
                // SwiftUI rimisura al prossimo giro: allora si ricolloca la barra.
                RunLoop.main.perform(inModes: [.common]) { [weak self] in MainActor.assumeIsolated { self?.pagesView.positionDesignBar() } }
            }
            // La barra sta in una fascia sua, sopra le pagine: così non copre mai il testo.
            designBand.show(NSHostingView(rootView: ParagraphDesignBand(model: session.bar).themed()))
            designBand.onWidth = { [weak session] width in
                guard let bar = session?.bar, abs(bar.maxWidth - width) > 1 else { return }
                bar.maxWidth = width
            }
        } else {
            let hadPreview = paragraphDesign?.draft.isEmpty == false || paragraphDesign?.drag != nil || paragraphDesign?.marginDrag != nil
            paragraphDesign = nil
            pagesView.designDrag = nil
            pagesView.hoveredDesignHandle = nil
            pagesView.design = nil
            designBand.show(nil)
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
        if !draft.ownResets.isEmpty || !draft.paragraphEdits.isEmpty || !draft.paragraphRules.isEmpty || !draft.ruleResets.isEmpty {
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
        guard let session = paragraphDesign, session.drag == nil, session.marginDrag == nil, session.keepDrag == nil, session.headingDrag == nil,
              session.ruleDrag == nil else { return }
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
        let heading = sheet.heading(ofParagraphStyle: name)
        if let part = session.selectedHeadingPart, !(heading?.parts.indices.contains(part) ?? false) { session.selectedHeadingPart = nil }
        overlay.heading = heading
        overlay.selectedHeadingPart = session.selectedHeadingPart
        overlay.headingEditable = isHeadingEditable
        let rules = designRules()
        if let rule = session.selectedRule, !rules.indices.contains(rule) { session.selectedRule = nil }
        overlay.rules = rules
        overlay.selectedRule = session.selectedRule
        pagesView.design = overlay
        selectionPanelModel.styleName = name
        refreshDesignBar(session, text: text, sheet: sheet, at: at)
        refreshRuler()
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
        bar.headingParts = sheet.heading(ofParagraphStyle: session.styleName)?.parts ?? []
        bar.selectedHeadingPart = session.selectedHeadingPart
        bar.headingEditable = isHeadingEditable
        bar.rules = designRules()
        bar.selectedRule = session.selectedRule
        bar.partStyles = sheet.styles.filter { $0.target != .paragraph || $0.name != session.styleName }.map(\.name)
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
        bar.useStandardHeading = { [weak self] in self?.changeDesignHeading { _ in .standard } }
        bar.removeHeading = { [weak self] in
            self?.paragraphDesign?.selectedHeadingPart = nil
            self?.changeDesignHeading { _ in nil }
        }
        bar.addHeadingPart = { [weak self] part in self?.changeDesignHeading { HeadingComposition.adding(part, to: $0) } }
        bar.updateHeadingPart = { [weak self] index, part in self?.changeDesignHeading { HeadingComposition.updating($0, at: index, to: part) } }
        bar.moveHeadingPart = { [weak self] index, offset in
            self?.paragraphDesign?.selectedHeadingPart = index + offset
            self?.changeDesignHeading { HeadingComposition.moving($0, at: index, by: offset) }
        }
        bar.removeHeadingPart = { [weak self] index in
            self?.paragraphDesign?.selectedHeadingPart = nil
            self?.changeDesignHeading { HeadingComposition.removing($0, at: index) }
        }
        bar.selectHeadingPart = { [weak self] index in self?.selectHeadingPart(index) }
        bar.addRule = { [weak self] anchor in self?.addDesignRule(anchor) }
        bar.selectRule = { [weak self] index in self?.selectRule(index) }
        bar.updateRule = { [weak self] index, rule in self?.changeDesignRules { rules in
            var rules = rules
            if rules.indices.contains(index) { rules[index] = rule }
            return rules
        } }
        bar.removeRule = { [weak self] index in
            self?.paragraphDesign?.selectedRule = nil
            self?.changeDesignRules { rules in rules.enumerated().filter { $0.offset != index }.map(\.element) }
        }
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
        for (name, rules) in draft.styleRules {
            if let index = sheet.styles.firstIndex(where: { $0.name == name }) { sheet.styles[index].values.rules = rules }
        }
        return Self.applyingHeadings(draft, to: sheet)
    }

    /// Gli stili con le testate della bozza.
    static func applyingHeadings(_ draft: ParagraphDesignDraft, to sheet: StyleSheet) -> StyleSheet {
        var sheet = sheet
        for (name, heading) in draft.headings {
            if let index = sheet.styles.firstIndex(where: { $0.name == name }) { sheet.styles[index].heading = heading }
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
        for id in draft.ruleResets where draft.paragraphRules[id] == nil {
            guard let range = store.range(of: id), range.length > 0 else { continue }
            TextStyling.setParagraphRules(nil, in: text, paragraphs: range)
        }
        for (id, rules) in draft.paragraphRules {
            guard let range = store.range(of: id), range.length > 0 else { continue }
            TextStyling.setParagraphRules(rules, in: text, paragraphs: range)
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
        // La copia porta le identità dei capoversi: senza, le riprese dei tratti delle Liste non troverebbero il tratto.
        let copy = NSMutableAttributedString(attributedString: store.identifiedCopy)
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
            // La testata vive solo nello stile: si vede sempre su tutti i titoli, anche con l'occhio barrato.
            document.styles = paragraphDesign?.livePreviewAll != false ? sheet : Self.applyingHeadings(draft, to: settings.styles)
        }
        // Con l'occhio barrato un capoverso progettato prima resta com'è nel documento: il valore dato a mano che
        // perderebbe salvando lo perde, nell'anteprima, solo il capoverso evidenziato.
        var shown = draft
        if paragraphDesign?.livePreviewAll == false {
            let current = paragraphDesign?.paragraphID
            shown.ownResets = shown.ownResets.filter { $0.key == current }
        }
        applyParagraphChanges(shown, to: copy, store: store, sheet: sheet)
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
            // I filetti dello stile nella bozza, sul solo capoverso evidenziato (se non ne ha di suoi).
            if !draft.styleRules.filter({ styleNames.contains($0.key) }).isEmpty, TextStyling.paragraphRules(in: copy, at: range.location) == nil {
                let name = copy.attribute(.paragraphStyleName, at: range.location, effectiveRange: nil) as? String
                TextStyling.setParagraphRules(sheet.values(of: name).rules ?? ParagraphRules(), in: copy, paragraphs: range)
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
        refreshRuler()
    }

    /// Dopo ogni ricomposizione del documento (si è scritto, si è annullato altro): la bozza torna sulle pagine.
    func showParagraphDesignDraftIfNeeded() {
        guard let session = paragraphDesign, !session.draft.isEmpty else { return }
        showDraft(session.draft)
    }

    /// Una modifica alla bozza: un passo dell'Annulla interno.
    func changeDraft(_ change: (inout ParagraphDesignDraft) -> Void) {
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
    func draft(_ draft: ParagraphDesignDraft, setting property: InspectorProperty, _ values: StyleValues) -> ParagraphDesignDraft {
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

    // MARK: La testata del titolo

    /// La testata si cambia solo nello stile, con l'occhio pieno: vale per tutti i titoli dello stile.
    var isHeadingEditable: Bool {
        guard let session = paragraphDesign else { return false }
        return session.scope == .style && session.livePreviewAll && session.styleName != nil
    }

    /// La testata del capoverso progettato, come è nella bozza.
    func designHeading() -> HeadingComposition? {
        guard let session = paragraphDesign else { return nil }
        return draftSheet(session.draft).heading(ofParagraphStyle: session.styleName)
    }

    /// Cambia la testata nella bozza: nello stile del capoverso, che ne prende una copia sua se la ereditava.
    func changeDesignHeading(_ change: (HeadingComposition?) -> HeadingComposition?) {
        guard isHeadingEditable, let name = paragraphDesign?.styleName else { return }
        let changed = change(designHeading())
        guard changed != designHeading() else { return }
        changeDraft { $0.headings[name] = .some(changed) }
    }

    func selectHeadingPart(_ part: Int?) {
        guard let session = paragraphDesign else { return }
        session.selectedHeadingPart = part
        refreshParagraphDesign()
    }

    func headingDragged(_ id: HeadingGripID, by delta: CGSize, phase: DesignDragPhase) {
        guard let session = paragraphDesign, isHeadingEditable, let name = session.styleName,
              let heading = designHeading(), heading.parts.indices.contains(id.part) else { return }
        let part = heading.parts[id.part]
        let shown = pagesView.designHeadingParts().first { $0.part == id.part }
        let shownRect = shown.map { NSRect(x: 0, y: 0, width: $0.rect.width / pagesView.scale, height: $0.rect.height / pagesView.scale) } ?? .zero
        let right: Bool = {
            let leftPage = shown.map { (pagesView.layout?.setup(forPage: $0.page).facing ?? false) && $0.page % 2 == 1 } ?? false
            switch part {
            case .rule(_, _, let alignment): return alignment.resolved(onLeftPage: leftPage) == .right
            case .numberBeside(_, _, let side, _): return side.resolved(onLeftPage: leftPage) == .right
            default: return false
            }
        }()
        switch phase {
        case .began:
            session.selectedHeadingPart = id.part
            session.headingDrag = (id, part.value(of: id.grip, shown: shownRect))
            pagesView.design?.activeHeadingGrip = id
            pagesView.design?.selectedHeadingPart = id.part
        case .changed, .ended:
            guard let drag = session.headingDrag, drag.id == id else { return }
            // Al mezzo millimetro, come i margini.
            let step = PageSetup.points(fromMillimetres: 0.5)
            let value = (part.value(of: id.grip, from: drag.start, moved: delta, onRightSide: right) / step).rounded() * step
            let changed = HeadingComposition.updating(heading, at: id.part, to: part.setting(id.grip, to: value))
            if phase == .changed {
                var preview = session.draft
                preview.headings[name] = .some(changed)
                pagesView.design?.heading = changed
                showDraft(preview)
                return
            }
            session.headingDrag = nil
            pagesView.design?.activeHeadingGrip = nil
            if abs(value - drag.start) > 0.001 {
                changeDraft { $0.headings[name] = .some(changed) }
            } else {
                showDraft(session.draft)
                refreshParagraphDesign()
            }
        }
    }

    func dragHeadingForTests(_ id: HeadingGripID, by delta: CGSize) {
        headingDragged(id, by: .zero, phase: .began)
        headingDragged(id, by: delta, phase: .changed)
        headingDragged(id, by: delta, phase: .ended)
    }

    // MARK: I filetti liberi

    /// I filetti del capoverso progettato, come sono nella bozza: i suoi, o quelli dello stile.
    func designRules() -> [ParagraphRule] {
        guard let session = paragraphDesign, documentText.length > 0 else { return [] }
        let at = min(session.paragraphLocation, documentText.length - 1)
        if let id = session.paragraphID, let own = session.draft.paragraphRules[id] { return own.rules }
        if let id = session.paragraphID, !session.draft.ruleResets.contains(id), let own = TextStyling.paragraphRules(in: documentText, at: at) { return own.rules }
        return draftSheet(session.draft).values(of: session.styleName).rules?.rules ?? []
    }

    /// Cambia i filetti nella bozza: nello stile (il capoverso perde i suoi dati a mano), o con ¶ nel solo capoverso.
    func changeDesignRules(_ change: ([ParagraphRule]) -> [ParagraphRule]) {
        guard let session = paragraphDesign, let id = session.paragraphID else { return }
        let changed = ParagraphRules(change(designRules()))
        guard changed.rules != designRules() else { return }
        switch session.scope {
        case .style:
            guard let name = session.styleName else { return }
            let at = min(session.paragraphLocation, max(documentText.length - 1, 0))
            changeDraft { draft in
                draft.styleRules[name] = changed
                draft.paragraphRules[id] = nil
                if TextStyling.paragraphRules(in: self.documentText, at: at) != nil { draft.ruleResets.insert(id) }
            }
        case .paragraph:
            changeDraft { $0.paragraphRules[id] = changed }
        }
    }

    func selectRule(_ rule: Int?) {
        guard let session = paragraphDesign else { return }
        session.selectedRule = rule
        refreshParagraphDesign()
    }

    func addDesignRule(_ anchor: ParagraphRule.Anchor) {
        let count = designRules().count
        changeDesignRules { $0 + [.fresh(anchor)] }
        paragraphDesign?.selectedRule = count
        refreshParagraphDesign()
    }

    /// Lo spazio che un filetto comanda con Maiuscole: quello sopra lo spazio prima, quello sotto lo spazio dopo, quelli
    /// ai lati i rientri.
    static func spaceProperty(of anchor: ParagraphRule.Anchor) -> InspectorProperty {
        switch anchor {
        case .top: .spaceBefore
        case .bottom: .spaceAfter
        case .left: .leftIndent
        case .right: .rightIndent
        }
    }

    /// La bozza con i filetti del capoverso cambiati (nello stile, o con ¶ nel solo capoverso).
    func draft(_ draft: ParagraphDesignDraft, settingRules rules: [ParagraphRule]) -> ParagraphDesignDraft {
        guard let session = paragraphDesign, let id = session.paragraphID else { return draft }
        var result = draft
        switch session.scope {
        case .style:
            guard let name = session.styleName else { return draft }
            result.styleRules[name] = ParagraphRules(rules)
            result.paragraphRules[id] = nil
            let at = min(session.paragraphLocation, max(documentText.length - 1, 0))
            if TextStyling.paragraphRules(in: documentText, at: at) != nil { result.ruleResets.insert(id) }
        case .paragraph:
            result.paragraphRules[id] = ParagraphRules(rules)
        }
        return result
    }

    /// Un filetto trascinato. Senza Maiuscole si muove da solo, fino al bordo del testo dal suo lato (mai dentro). Con
    /// Maiuscole trascina il suo spazio: segue il mouse, e lo spazio dal suo lato (prima, dopo, rientro) cambia della
    /// stessa misura, così il testo si sposta con lui; arrivato a zero, lo spazio si ferma e il filetto prosegue da solo.
    func ruleDragged(_ id: RuleGripID, by delta: CGSize, phase: DesignDragPhase, modifiers: NSEvent.ModifierFlags = []) {
        guard let session = paragraphDesign else { return }
        let rules = designRules()
        guard rules.indices.contains(id.rule) else { return }
        let property = Self.spaceProperty(of: rules[id.rule].anchor)
        switch phase {
        case .began:
            session.selectedRule = id.rule
            session.ruleDrag = (id, rules[id.rule], session.number(property))
            pagesView.design?.selectedRule = id.rule
            pagesView.design?.activeRuleGrip = id
        case .changed, .ended:
            guard let drag = session.ruleDrag, drag.id == id else { return }
            func snap(_ value: Double) -> Double { (value * 2).rounded() / 2 }
            let dx = Double(delta.width), dy = Double(delta.height)
            var moved = drag.start
            var space: Double?
            if modifiers.contains(.shift), id.grip == .body {
                let start = Double(drag.space), offset = drag.start.offset
                switch drag.start.anchor {
                case .top:
                    let value = max(snap(start + dy), 0)
                    space = value
                    moved.offset = offset + (value - start - dy)
                case .bottom:
                    space = max(snap(start + dy), 0)
                    moved.offset = offset + dy
                case .left:
                    space = max(snap(start + dx), 0)
                    moved.offset = offset - dx
                case .right:
                    space = max(snap(start - dx), 0)
                    moved.offset = offset + dx
                }
            } else {
                moved = drag.start.moved(id.grip, by: delta)
            }
            moved.offset = snap(moved.offset); moved.start = snap(moved.start); moved.end = snap(moved.end)
            // Mai dentro il testo: sopra e sotto fino al bordo delle righe, ai lati fino al rientro.
            switch moved.anchor {
            case .top, .bottom: moved.offset = max(moved.offset, 0)
            case .left, .right: moved.offset = max(moved.offset, -(space ?? Double(session.number(property))))
            }
            var changed = rules
            changed[id.rule] = moved
            func applied(to base: ParagraphDesignDraft) -> ParagraphDesignDraft {
                var result = draft(base, settingRules: changed)
                if let space { result = draft(result, setting: property, Self.designValues(property, CGFloat(space))) }
                return result
            }
            if phase == .changed {
                pagesView.design?.rules = changed
                if let space { pagesView.design?.values[DesignHandle.allCases.first { $0.property == property } ?? .spaceBefore] = CGFloat(space) }
                showDraft(applied(to: session.draft))
                return
            }
            session.ruleDrag = nil
            pagesView.design?.activeRuleGrip = nil
            if moved != drag.start || (space.map { abs($0 - Double(drag.space)) > 0.001 } ?? false) {
                changeDraft { $0 = applied(to: $0) }
            } else {
                showDraft(session.draft)
                refreshParagraphDesign()
            }
        }
    }

    func dragRuleForTests(_ id: RuleGripID, by delta: CGSize, modifiers: NSEvent.ModifierFlags = []) {
        ruleDragged(id, by: .zero, phase: .began, modifiers: modifiers)
        ruleDragged(id, by: delta, phase: .changed, modifiers: modifiers)
        ruleDragged(id, by: delta, phase: .ended, modifiers: modifiers)
    }

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
    var designHeadingGripsForTests: [HeadingGripID] { Array(pagesView.headingGripRects().keys) }
}
