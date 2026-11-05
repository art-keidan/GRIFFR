import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Stili (barra e menu Formato)

    /// I nomi degli stili del documento per una specie, nell'ordine in cui sono definiti.
    func styleNames(for target: StyleTarget) -> [String] {
        settings.styles.styles.filter { $0.target == target }.map(\.name)
    }

    static let noStyleTitle = "None"

    func reloadStylePopup() {
        stylePopup.removeAllItems()
        stylePopup.addItems(withTitles: styleNames(for: .paragraph))
        if stylePopup.numberOfItems > 0 { stylePopup.menu?.addItem(.separator()) }
        stylePopup.addItem(withTitle: Self.noStyleTitle)
        showParagraphStyleInBar()
    }

    /// Il nome dello stile di quella specie nel punto in cui comincia la selezione (o al cursore).
    func selectionStyleName(_ target: StyleTarget) -> String? {
        let key: NSAttributedString.Key = switch target {
        case .paragraph: .paragraphStyleName
        case .word: .wordStyleName
        case .character: .characterStyleName
        }
        guard let storage = textStorage else { return nil }
        let range = selection.range
        if range.length == 0 || storage.length == 0 { return typingAttributes[key] as? String }
        return storage.attribute(key, at: min(range.location, storage.length - 1), effectiveRange: nil) as? String
    }

    func showParagraphStyleInBar() {
        let title = selectionStyleName(.paragraph) ?? Self.noStyleTitle
        if stylePopup.item(withTitle: title) != nil { stylePopup.selectItem(withTitle: title) } else { stylePopup.selectItem(withTitle: Self.noStyleTitle) }
    }

    @objc func stylePopupChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem
        applyNamedStyle(.paragraph, name: title == Self.noStyleTitle ? nil : title)
        window?.makeFirstResponder(pagesView)
    }

    @objc func setWordStyle(_ sender: NSMenuItem) { applyNamedStyle(.word, name: sender.representedObject as? String) }
    @objc func setCharacterStyle(_ sender: NSMenuItem) { applyNamedStyle(.character, name: sender.representedObject as? String) }

    /// Dà (o toglie, con `nil`) uno stile alla selezione: a tutti i paragrafi che tocca, per uno stile di
    /// paragrafo; al solo testo selezionato, per gli altri. Senza selezione vale per ciò che si scriverà.
    func applyNamedStyle(_ target: StyleTarget, name: String?) {
        guard let storage = textStorage else { return }
        endUndoStep(next: .none)
        func rename(_ names: inout TextStyling.StyleNames) {
            switch target {
            case .paragraph: names.paragraph = name
            case .word: names.word = name
            case .character: names.character = name
            }
        }
        var range = selection.range
        let atFinalEmptyParagraph = range.location >= storage.length && TextStyling.hasEmptyFinalParagraph(storage)
        if target == .paragraph, !atFinalEmptyParagraph { range = TextStyling.paragraphRange(in: storage, for: range) }
        if range.length == 0 {
            // Si calcola su un carattere di prova con gli attributi di scrittura, e il risultato diventa quelli.
            let probe = NSMutableAttributedString(string: " ", attributes: typingAttributes)
            let currentList = selectionListItem()
            if let currentList { probe.addAttribute(.listItem, value: currentList.encoded, range: NSRange(location: 0, length: 1)) } else { probe.removeAttribute(.listItem, range: NSRange(location: 0, length: 1)) }
            TextStyling.restyle(probe, range: NSRange(location: 0, length: 1), from: settings.styles, to: settings.styles, resolver: fontRoleResolver, base: settings.formulaBase ?? TextStyling.styleBase, assigning: target, rename: rename)
            typingAttributes = probe.attributes(at: 0, effectiveRange: nil)
            // Lo stile di paragrafo può dare una Lista anche al paragrafo vuoto in fondo.
            let newList = (probe.attribute(.listItem, at: 0, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
            if target == .paragraph, newList != currentList { changeList(actionName: name == nil ? "Remove Style" : "Style “\(name!)”") { _ in newList } }
            refreshFromSelection()
            return
        }
        let sheet = settings.styles
        // Lo stile decide anche la sezione: uno di titolo (con un livello o un ruolo) la apre, e su un titolo che c'è già
        // lo porta al suo livello; uno del corpo la toglie dal titolo selezionato.
        let changesSection = target == .paragraph && noteAnchor == nil
        let level = changesSection ? sheet.resolveParagraph(styleName: name).outlineLevel ?? 0 : 0
        // «Apre una sezione: No» scelto nella scheda Stili vince sul livello; senza indicazione basta il livello.
        let opens: String? = switch sheet.values(of: name).opensSection {
        case _ where !changesSection: nil
        case .some(""): nil
        case .some(let role): role
        case .none: level > 0 ? SectionEditing.defaultRole(forLevel: level) : nil
        }
        writeStore(actionName: name == nil ? "Remove Style" : "Style “\(name!)”") {
            TextStyling.restyle($0, range: range, from: sheet, to: sheet, resolver: fontRoleResolver, base: settings.formulaBase ?? TextStyling.styleBase, assigning: target, rename: rename)
            if let opens {
                // Prima i paragrafi diventano titoli, poi i titoli vanno al loro livello: dopo uno spostamento
                // l'intervallo contiene altro testo.
                SectionEditing.openSections(role: opens, inParagraphsOf: range, in: $0)
                SectionEditing.moveTitles(inParagraphsOf: range, toLevel: level, in: $0)
            } else if changesSection {
                SectionEditing.removeSections(inParagraphsOf: range, in: $0)
            }
        }
        if changesSection { typingAttributes = Self.typingAttributes(in: store, at: selection) }
        refreshFromSelection()
    }

    /// Cambia le definizioni degli stili (annullabile). Con `restyle` tutto il testo segue le definizioni nuove,
    /// tranne i valori dati a mano.
    func changeStyles(to newSheet: StyleSheet, restyle: Bool, actionName: String) {
        let oldSheet = settings.styles
        guard newSheet != oldSheet else { return }
        // Annullando, il testo torna com'era per conto del deposito; qui si rimettono le sole definizioni.
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.changeStyles(to: oldSheet, restyle: false, actionName: actionName) }
        }
        settings.styles = newSheet
        if restyle, store.length > 0 {
            writeStore(actionName: nil) { TextStyling.restyle($0, range: NSRange(location: 0, length: $0.length), from: oldSheet, to: newSheet, resolver: fontRoleResolver, base: settings.formulaBase ?? TextStyling.styleBase) }
        }
        document?.undoManager?.setActionName(actionName)
        reloadStylePopup()
        refreshFromSelection()
        layoutPages()
        definitionsPanel?.documentChanged()
        refreshStylesTab()
        composerModel?.documentChanged(sheet: settings.styles, rules: settings.rules)
    }

    /// Crea uno stile con ciò che la selezione ha di diverso dallo stile su cui si basa, e lo dà alla selezione.
    @objc func newStyleFromSelection(_ sender: Any?) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let kind = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        kind.addItems(withTitles: ["Paragraph Style", "Word Style", "Character Style"])
        askStyleName(title: "New Style from Selection",
                     message: "The style takes the look of the selected text: for a paragraph, what sets it apart from its current style; for a word or character, what sets it apart from the surrounding text.",
                     suggestion: nil, extra: kind) { [weak self] styleName in
            self?.createStyleFromSelection(named: styleName, target: [.paragraph, .word, .character][max(kind.indexOfSelectedItem, 0)])
        }
    }

    /// Chiede il nome di uno stile nuovo in un foglio sulla finestra; `done` riceve un nome libero, mai vuoto.
    func askStyleName(title: String, message: String, suggestion: String?, extra: NSView? = nil, done: @escaping (String) -> Void) {
        if let answer = styleNameAnswerForTests {
            if settings.styles.style(named: answer) == nil { done(answer) }
            return
        }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        name.placeholderString = "Style name"
        // Nella pila la casella non ha una larghezza sua: senza questo vincolo si stringeva a due punti.
        name.widthAnchor.constraint(equalToConstant: 240).isActive = true
        if let suggestion { name.stringValue = settings.styles.freeName(suggestion) }
        let box = NSStackView(views: [name] + (extra.map { [$0] } ?? []))
        box.orientation = .vertical
        box.alignment = .leading
        box.frame = NSRect(x: 0, y: 0, width: 240, height: extra == nil ? 24 : 58)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let styleName = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !styleName.isEmpty, self.settings.styles.style(named: styleName) == nil else { NSSound.beep(); return }
            done(styleName)
        }
    }

    /// Crea uno stile con la sola aggiunta scelta e lo dà alla selezione. L'aggiunta locale viene tolta prima di
    /// rinominare lo stile, altrimenti resterebbe sopra il valore nuovo; tutto forma un solo passo di Annulla.
    func createStyleFromAddition(at index: Int, named styleName: String) {
        guard let storage = textStorage, storage.length > 0, styleAdditions.indices.contains(index),
              let property = styleAdditions[index].property, settings.styles.style(named: styleName) == nil else { return }
        let target = inspectionTarget(property.level)
        let basedOn = selectionStyleName(property.level)
        let at = min(target.range.location, max(target.text.length - 1, 0))
        let allValues = TextStyling.styleValues(from: target.text, at: at, target: property.level, sheet: settings.styles, basedOn: basedOn)
        var values = property.only(allValues)
        // La faccia può essere descritta da corsivo/nero invece che dal nome completo del font.
        if property == .face {
            values.family = allValues.family
            values.italic = allValues.italic
            values.bold = allValues.bold
        }
        var sheet = settings.styles
        sheet.styles.append(NamedStyle(name: styleName, target: property.level, basedOn: basedOn, values: values))
        sheet.styles[sheet.styles.count - 1] = sheet.materializingFormulas(of: styleName) ?? sheet.styles[sheet.styles.count - 1]
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        removeStyleAdditions([index])
        changeStyles(to: sheet, restyle: false, actionName: "New Style")
        applyNamedStyle(property.level, name: styleName)
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("New Style “\(styleName)”")
        window?.makeFirstResponder(pagesView)
    }

    /// Crea lo stile con l'aspetto della selezione e glielo dà, in un solo passo da annullare.
    func createStyleFromSelection(named styleName: String, target: StyleTarget) {
        guard let storage = textStorage, storage.length > 0, settings.styles.style(named: styleName) == nil else { return }
        let at = min(selection.range.location, storage.length - 1)
        let basedOn = target == .paragraph ? selectionStyleName(.paragraph) : nil
        let values = TextStyling.styleValues(from: storage, at: at, target: target, sheet: settings.styles, basedOn: basedOn)
        var sheet = settings.styles
        sheet.styles.append(NamedStyle(name: styleName, target: target, basedOn: basedOn, values: values))
        sheet.styles[sheet.styles.count - 1] = sheet.materializingFormulas(of: styleName) ?? sheet.styles[sheet.styles.count - 1]
        document?.undoManager?.beginUndoGrouping()
        changeStyles(to: sheet, restyle: false, actionName: "New Style")
        applyNamedStyle(target, name: styleName)
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("New Style “\(styleName)”")
        window?.makeFirstResponder(pagesView)
    }

    /// Ispettore › «Crea uno stile da qui…»: uno stile della specie dell'oggetto scelto.
    func createStyleFromInspector() {
        guard let level = inspector.object.level, store.length > 0 else { return }
        let kind = switch level {
        case .paragraph: "paragraph"
        case .word: "word"
        case .character: "character"
        }
        askStyleName(title: "New \(kind) style",
                     message: "The style takes the look this \(inspector.object.title.lowercased()) has here, and is applied to it at once.",
                     suggestion: nil) { [weak self] name in
            self?.createStyleFromSelection(named: name, target: level)
        }
    }

    /// Ispettore › «Crea una regola da qui…»: indovina che cosa è il pezzo selezionato nel suo paragrafo (la prima
    /// lettera, le prime parole, la prima frase, il paragrafo intero, o una parola che si ripete) e crea una regola che
    /// dia quell'aspetto allo stesso pezzo nei paragrafi dello stesso stile. Lo stile è quello che il pezzo ha già, o
    /// uno nuovo con il suo aspetto. Poi si apre la scheda Regole, per aggiustarla.
    func createRuleFromInspector() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let range = selection.range
        guard range.length > 0, let target = Rules.guessTarget(for: range, in: storage) else {
            explain("Select the piece of text the rule should find",
                    "The first letter, the first words, the first sentence or the whole paragraph; or a single word, which the rule will find everywhere.")
            return
        }
        let paragraphStyle = selectionStyleName(.paragraph)
        let at = range.location
        let existing = (storage.attribute(.characterStyleName, at: at, effectiveRange: nil) as? String)
            ?? (storage.attribute(.wordStyleName, at: at, effectiveRange: nil) as? String)
        if let existing {
            addRule(TextRule(target: target, paragraphStyle: paragraphStyle, styleName: existing), styles: settings.styles, clearing: nil)
            return
        }
        // Uno stile nuovo con l'aspetto del pezzo: di parola se ha una lingua o una sillabazione sue, se no di carattere.
        let wordValues = TextStyling.styleValues(from: storage, at: at, target: .word, sheet: settings.styles, basedOn: nil)
        let styleTarget: StyleTarget = wordValues.language != nil || wordValues.hyphenates != nil ? .word : .character
        let values = styleTarget == .word ? wordValues : TextStyling.styleValues(from: storage, at: at, target: .character, sheet: settings.styles, basedOn: nil)
        let rule = TextRule(target: target, paragraphStyle: paragraphStyle, styleName: "")
        let what = rule.summary.components(separatedBy: " → ").first ?? ""
        askStyleName(title: "New Rule",
                     message: "The rule will find: \(what). It will give it a new style, with the look the selected text has here. What is the style called?",
                     suggestion: nil) { [weak self] name in
            guard let self else { return }
            var sheet = self.settings.styles
            sheet.styles.append(NamedStyle(name: name, target: styleTarget, basedOn: nil, values: values))
            sheet.styles[sheet.styles.count - 1] = sheet.materializingFormulas(of: name) ?? sheet.styles[sheet.styles.count - 1]
            var named = rule
            named.styleName = name
            self.addRule(named, styles: sheet, clearing: range)
        }
    }

    /// Un avviso in un foglio sulla finestra, con il solo «OK».
    func explain(_ title: String, _ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    /// Aggiunge una regola (con gli stili nuovi) in un passo annullabile e la mostra nella scheda Regole. Con `clearing`,
    /// il pezzo da cui è nata perde i valori dati a mano che ora gli dà la regola.
    func addRule(_ rule: TextRule, styles: StyleSheet, clearing range: NSRange?) {
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        changeRules(settings.rules + [rule], styles: styles)
        if let range, let style = styles.style(named: rule.styleName), store.length > 0 {
            let fixed = StyleSheet.properties(for: style.target).filter {
                $0.isFixed(in: style.values) || styles.formulaDefinition(for: $0, inStyle: style.name) != nil
            }
            let sheet = settings.styles
            if !fixed.isEmpty {
                writeStore(actionName: nil) { text in
                    for property in fixed { TextStyling.resetValue(of: property, in: text, range: range, sheet: sheet, resolver: self.fontRoleResolver) }
                }
            }
        }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("New Rule")
        refreshFromSelection()
        if interfaceMode == .simple { setInterfaceMode(.advanced) }
        definitionsPanel.showRule(at: settings.rules.count - 1)
        window?.makeFirstResponder(nil)
    }

    /// Ridefinisce lo stile della selezione (di paragrafo, di parola o di carattere) con l'aspetto che ha lì:
    /// tutto il testo con quello stile si aggiorna, tranne i valori dati a mano.
    @objc func updateStyleFromSelection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = StyleTarget(rawValue: raw),
              let storage = textStorage, storage.length > 0, let name = selectionStyleName(target) else { return }
        flushStyleChanges()
        let base = settings.styles
        let at = min(selection.range.location, storage.length - 1)
        let changes = TextStyling.styleChanges(from: storage, at: at, style: name, sheet: base,
                                               base: settings.formulaBase ?? TextStyling.styleBase, resolver: fontRoleResolver)
        let calculated = changes.filter { base.formulaDefinition(for: $0.property, inStyle: name)?.isCalculated == true }
        let apply: () -> Void = { [weak self] in
            guard let self, self.settings.styles == base else { return }
            var updated = base
            for change in changes {
                updated = updated.setting(change.value, of: change.property, inStyle: name,
                    base: self.settings.formulaBase ?? TextStyling.styleBase, replacingFormula: true)
            }
            updated = TextStyling.updatingStyleFontDetails(updated, style: name, from: storage, at: at,
                base: self.settings.formulaBase ?? TextStyling.styleBase, resolver: self.fontRoleResolver)
            self.endUndoStep(next: .none)
            self.changeStyles(to: updated, restyle: true, actionName: "Update Style “" + name + "”")
        }
        if calculated.isEmpty { apply(); return }
        if let answer = replaceFormulaAnswerForTests { if answer { apply() }; return }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Replace the changed formulas with fixed values?"
        alert.informativeText = "In the style “" + name + "” these change: " + calculated.map { $0.property.title }.joined(separator: ", ") + ". The other formulas are kept."
        alert.addButton(withTitle: "Replace with Fixed Values")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { if response == .alertFirstButtonReturn { apply() } }
        }
    }

    // MARK: Elenchi (menu Formato)

    /// I segni proposti nel menu; qualsiasi altro si può scrivere con «Altro segno…».
    static let bulletMarkers = ["•", "–", "◦", "▪"]

    /// La voce di menu di un segno d'elenco: il segno e il suo nome (con il solo «Puntato» le voci erano uguali).
    static func bulletTitle(_ marker: String) -> String {
        let name = ["•": "bullet", "–": "dash", "◦": "circle", "▪": "square"][marker] ?? "marker"
        return "\(marker)   Bulleted, \(name)"
    }
    static let numberMarkers = ["1.", "1)", "(1)", "a)", "a.", "A.", "i.", "I."]
    static let lastListMarkerKey = "LastListMarker"
    var lastListMarker: String {
        get { UserDefaults.standard.string(forKey: Self.lastListMarkerKey) ?? "•" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastListMarkerKey) }
    }

    /// L'elenco del paragrafo in cui comincia la selezione.
    func selectionListItem() -> ListItem? {
        guard let storage = textStorage else { return nil }
        if storage.length == 0 { return (typingAttributes[.listItem] as? String).flatMap(ListItem.init(encoded:)) }
        return TextStyling.listItem(in: storage, at: selection.range.location)
    }

    /// Cambia l'elenco dei paragrafi toccati dalla selezione (annullabile).
    @discardableResult
    func changeList(actionName: String, _ transform: (ListItem?) -> ListItem?) -> Bool {
        guard let storage = textStorage else { return false }
        endUndoStep(next: .none)
        if storage.length == 0 {
            // In un documento vuoto non c'è un carattere a cui attaccare l'elenco: lo prenderà il testo che si scriverà.
            typingAttributes[.listItem] = transform(selectionListItem())?.encoded
            return true
        }
        let range = selection.range
        let affected = TextStyling.listEditRange(in: storage, for: range)
        guard affected.length > 0 else { return false }
        writeStore(actionName: actionName) { TextStyling.setList(in: $0, range: range, transform) }
        syncListTypingAttributes()
        return true
    }

    func applyListMarker(_ marker: String?) {
        if let marker { lastListMarker = marker }
        // Chi è già una voce conserva il suo livello.
        changeList(actionName: marker == nil ? "Remove List" : "List") { current in marker.map { ListItem(marker: $0, level: current?.level ?? 1) } }
    }

    @objc func setListMarker(_ sender: NSMenuItem) {
        applyListMarker(sender.representedObject as? String)
    }

    /// Fa dei paragrafi selezionati un elenco con l'ultimo segno usato, oppure lo toglie se lo sono già.
    @objc func toggleList(_ sender: Any?) {
        applyListMarker(selectionListItem() == nil ? lastListMarker : nil)
    }

    @objc func chooseListMarker(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "List Marker"
        alert.informativeText = "Type a symbol (for example → or *), or a numbering pattern: a counter — 1, a, A, i, I — with any punctuation, for example 1), (a), I., §1."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = selectionListItem()?.marker ?? lastListMarker
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            let marker = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard response == .alertFirstButtonReturn, !marker.isEmpty, let self else { return }
            self.applyListMarker(marker)
            self.window?.makeFirstResponder(self.pagesView)
        }
    }

    // MARK: Liste con un nome

    /// Le Liste del documento, ciascuna con i suoi primi segni, per il menu.
    func namedLists() -> [(name: String, sample: String)] {
        settings.lists.map { ($0.name, ListNumberer.sample(of: $0.name, in: settings.lists).joined(separator: "  ")) }
    }

    /// Fa dei paragrafi selezionati voci della Lista scelta nel menu.
    @objc func setNamedList(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        changeList(actionName: "List “\(name)”") { _ in ListItem(listName: name) }
    }

    /// Apre la finestra in cui si creano, modificano e tolgono le Liste, e si sceglie quella delle note.
    @objc func editLists(_ sender: Any?) { showDefinitions(.lists) }

    /// Il pulsante «Stili di flottante…»: le serie di note, il loro aspetto e la loro numerazione.
    @objc func editFloatStyles(_ sender: Any?) { showDefinitions(.floats) }

    /// Il pulsante «Regole…»: i pezzi di testo che prendono uno stile da soli (prima lettera, prime parole, sigle…).
    @objc func editRules(_ sender: Any?) { showDefinitions(.rules) }

    /// Le Liste, gli stili di flottante e le regole si modificano nelle schede del pannello: dall'interfaccia semplice
    /// si passa all'avanzata.
    func showDefinitions(_ tab: DefinitionsPanel.Tab) {
        if interfaceMode == .simple { setInterfaceMode(.advanced) }
        definitionsPanel.show(tab)
        window?.makeFirstResponder(nil)
    }

    func connectDefinitionsPanel() {
        definitionsPanel.stylesModel = stylesTab
        definitionsPanel.onFlush = { [unowned self] in self.flushStyleChanges() }
        definitionsPanel.refreshStyles = { [unowned self] in self.refreshStylesTab() }
        styleInspector.families = OpticalFonts.families(NSFontManager.shared.availableFontFamilies).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        styleInspector.groupsFamilies = FontMenuPreferences.groupsFamilies
        styleInspector.languages = Self.languages.map { InspectorModel.LanguageChoice(code: $0, name: Self.languageName($0)) }
        styleInspector.set = { [unowned self] property, values in self.setStyleValue(property, values) }
        styleInspector.reset = { [unowned self] property in self.resetStyleValue(property) }
        styleInspector.openFormula = { [unowned self] name in self.showStyleComposer(style: name) }
        styleInspector.replaceFormula = { [unowned self] property in self.replaceStyleFormula(property) }
        stylesTab.onSelect = { [unowned self] _ in self.refreshStylesTab() }
        stylesTab.onNew = { [unowned self] target in self.newStyle(target) }
        stylesTab.onDuplicate = { [unowned self] name in self.duplicateStyle(name) }
        stylesTab.onRemove = { [unowned self] name in self.removeStyle(name) }
        stylesTab.onRename = { [unowned self] old, new in self.renameStyle(old, to: new) }
        stylesTab.onParent = { [unowned self] name, parent in self.setStyleParent(name, parent) }
        stylesTab.onOpensSection = { [unowned self] name, role in self.setStyleOpensSection(name, role) }
        stylesTab.onPageStart = { [unowned self] name, value in
            self.flushStyleChanges()
            let sheet = self.settings.styles.settingDirective(.pageStartSpacing, argument: value.map(StyleArgument.pageStart), inStyle: name)
            self.endUndoStep(next: .none)
            self.changeStyles(to: sheet, restyle: false, actionName: "Page-Start Distance")
        }
        stylesTab.onOutlineLevel = { [unowned self] name, level in self.setStyleOutlineLevel(name, level) }
        definitionsPanel.settings = { [unowned self] in self.settings }
        definitionsPanel.sectionRoles = { [unowned self] in
            SectionEditing.titles(in: self.store).map(\.mark.role).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }
        definitionsPanel.applyLists = { [unowned self] result in self.applyListChanges(result) }
        definitionsPanel.applyFloats = { [unowned self] result in self.applyFloatStyleChanges(result) }
        definitionsPanel.applyRules = { [unowned self] result in self.applyRuleChanges(result) }
        definitionsPanel.applyPageTypes = { [unowned self] result in self.applyPageTypeChanges(result) }
        definitionsPanel.applyTableStyles = { [unowned self] result in self.applyTableStyleChanges(result) }
    }

    // MARK: La scheda Stili

    /// Porta la scheda Stili in pari con il documento: gli stili, quello scelto, i valori del suo modulo.
    func refreshStylesTab() {
        let sheet = settings.styles
        stylesTab.sheet = sheet
        if stylesTab.selection.flatMap(sheet.style(named:)) == nil {
            stylesTab.selection = sheet.styles.first { $0.target == .paragraph }?.name ?? sheet.styles.first?.name
            return  // la scelta nuova richiama questa funzione
        }
        guard let name = stylesTab.selection else {
            styleInspector.values = []
            styleInspector.formulaDefinitions = [:]
            return
        }
        let values = (pendingStyles?.sheet ?? sheet).inspect(style: name, base: settings.formulaBase ?? TextStyling.styleBase, resolver: fontRoleResolver)
        styleInspector.lists = settings.lists.map(\.name)
        if let family = values.first(where: { $0.property == .family })?.value.family {
            styleInspector.faces = OpticalFonts.members(ofFamily: family).compactMap { member in
                guard let name = member[0] as? String, let title = member[1] as? String else { return nil }
                return InspectorModel.FaceChoice(name: name, title: title)
            }
        }
        styleInspector.values = values
        refreshStyleFormulaDefinitions(pendingStyles?.sheet ?? sheet, name: name)
    }

    func refreshStyleFormulaDefinitions(_ sheet: StyleSheet, name: String) {
        styleInspector.formulaDefinitions = Dictionary(uniqueKeysWithValues: styleInspector.values.compactMap { value in
            sheet.formulaDefinition(for: value.property, inStyle: name).map { (value.property, $0) }
        })
    }

    /// Scelta esplicita dal menu del controllo: la formula viene sostituita con il risultato attuale.
    func replaceStyleFormula(_ property: InspectorProperty) {
        guard let name = stylesTab.selection, let value = styleInspector.values.first(where: { $0.property == property }) else { return }
        let sheet = pendingStyles?.sheet ?? settings.styles
        queueStyleChange(sheet.setting(value.value, of: property, inStyle: name,
            base: settings.formulaBase ?? TextStyling.styleBase, replacingFormula: true), name: name, property: property)
        flushStyleChanges()
    }

    static let stylePause: TimeInterval = 0.3

    /// Un valore fissato nello stile scelto: tutto il testo che lo usa cambia (tranne ciò che è dato a mano).
    func setStyleValue(_ property: InspectorProperty, _ values: StyleValues) {
        guard let name = stylesTab.selection else { return }
        let base = pendingStyles?.sheet ?? settings.styles
        queueStyleChange(base.setting(values, of: property, inStyle: name, base: settings.formulaBase ?? TextStyling.styleBase), name: name, property: property)
    }

    /// Un valore tolto dallo stile scelto, che torna a ereditarlo.
    func resetStyleValue(_ property: InspectorProperty) {
        guard let name = stylesTab.selection else { return }
        let base = pendingStyles?.sheet ?? settings.styles
        queueStyleChange(base.resetting(property, inStyle: name), name: name, property: property)
    }

    func queueStyleChange(_ sheet: StyleSheet, name: String, property: InspectorProperty) {
        pendingStyles = (sheet, name, property)
        styleInspector.values = sheet.inspect(style: name, base: settings.formulaBase ?? TextStyling.styleBase, resolver: fontRoleResolver)
        refreshStyleFormulaDefinitions(sheet, name: name)
        pendingStyleTimer?.invalidate()
        // Un timer del ciclo degli eventi: scatta anche durante un trascinamento nel pannello dei colori.
        let timer = Timer(timeInterval: Self.stylePause, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushStyleChanges() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingStyleTimer = timer
    }

    /// Butta via, senza applicarle, le modifiche in attesa della pausa (scheda Stili e schede del pannello): si usa quando il
    /// documento viene sostituito. Da non confondere con `flushStyleChanges`, che le applica.
    func discardPendingChanges() {
        pendingStyleTimer?.invalidate()
        pendingStyleTimer = nil
        pendingStyles = nil
        definitionsPanel?.discardPending()
    }

    /// Applica subito le modifiche agli stili in attesa (prima di ogni altra azione, del salvataggio, di «Annulla»).
    func flushStyleChanges() {
        pendingStyleTimer?.invalidate()
        pendingStyleTimer = nil
        guard let pending = pendingStyles else { return }
        pendingStyles = nil
        guard pending.sheet != settings.styles else { return }
        endUndoStep(next: .none)
        changeStyles(to: pending.sheet, restyle: true, actionName: "Style “\(pending.name)”: \(pending.property.title.lowercased())")
    }

    /// Uno stile nuovo, vuoto: basato su quello scelto se è della stessa specie.
    func newStyle(_ target: StyleTarget) {
        flushStyleChanges()
        var sheet = settings.styles
        let parent = stylesTab.selected?.target == target ? stylesTab.selection : nil
        let kind = switch target { case .paragraph: "paragraph"; case .word: "word"; case .character: "character" }
        let name = sheet.freeName("New \(kind) style")
        sheet.styles.append(NamedStyle(name: name, target: target, basedOn: parent))
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: false, actionName: "New Style")
        stylesTab.selection = name
    }

    /// Una copia dello stile, subito dopo di lui.
    func duplicateStyle(_ name: String) {
        flushStyleChanges()
        var sheet = settings.styles
        guard let index = sheet.styles.firstIndex(where: { $0.name == name }) else { return }
        var copy = sheet.styles[index]
        copy.name = sheet.freeName("\(name) copy")
        sheet.styles.insert(copy, at: index + 1)
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: false, actionName: "Duplicate Style")
        stylesTab.selection = copy.name
    }

    /// Un nome nuovo: il testo, gli stili che si basano su di lui, le regole e gli stili di flottante lo seguono.
    func renameStyle(_ old: String, to new: String) {
        flushStyleChanges()
        let updated = settings.renamingStyle(old, to: new)
        guard updated.styles != settings.styles else { return }
        changeDefinitions(updated, renames: [old: new], actionName: "Rename Style")
        stylesTab.selection = new
    }

    /// Toglie uno stile: il testo, gli stili, le regole e gli stili di flottante passano allo stile su cui si basava.
    func removeStyle(_ name: String) {
        flushStyleChanges()
        let (updated, replacement) = settings.removingStyle(name)
        guard updated.styles != settings.styles else { return }
        changeDefinitions(updated, renames: [name: replacement], actionName: "Remove Style “\(name)”")
        stylesTab.selection = replacement
    }

    /// Lo stile su cui si basa: il testo prende l'aspetto della catena nuova (tranne ciò che è dato a mano).
    /// Scheda Stili › Apre una sezione: il ruolo che lo stile apre (`nil` lo eredita, la stringa vuota: nessuno).
    func setStyleOpensSection(_ name: String, _ role: String?) {
        flushStyleChanges()
        let sheet = settings.styles.settingDirective(.opensSection, argument: role.map(StyleArgument.text), inStyle: name)
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: false, actionName: "Style “\(name)”: opens a section")
    }

    /// Il livello di uno stile di paragrafo (`nil`: come lo stile di base; 0: nessuno). Lo stile comanda: i titoli che lo
    /// usano vanno al livello nuovo con il loro contenuto, nello stesso passo di «Annulla».
    func setStyleOutlineLevel(_ name: String, _ level: Int?) {
        flushStyleChanges()
        let sheet = settings.styles.settingDirective(.outlineLevel, argument: level.map(StyleArgument.integer), inStyle: name)
        guard sheet != settings.styles else { return }
        endUndoStep(next: .none)
        writeStore(actionName: "Style “\(name)”: level") { store in
            store.replaceStyles(sheet)
            SectionEditing.moveTitlesToStyleLevels(in: store)
        }
        refreshFromSelection()
        refreshStylesTab()
        composerModel?.documentChanged(sheet: settings.styles, rules: settings.rules)
        layoutPages()
    }

    func setStyleParent(_ name: String, _ parent: String?) {
        flushStyleChanges()
        var sheet = settings.styles
        guard let index = sheet.styles.firstIndex(where: { $0.name == name }), sheet.styles[index].basedOn != parent,
              parent.map({ sheet.possibleParents(of: name).contains($0) }) ?? true else { return }
        sheet.styles[index].basedOn = parent
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: true, actionName: "Style “\(name)”: based on")
    }

    /// Cambia insieme stili, regole e stili di flottante, e porta il testo dai nomi vecchi ai nuovi (`nil`: nessuno
    /// stile), in un passo solo di «Annulla».
    func changeDefinitions(_ updated: Document, renames: [String: String?], actionName: String) {
        endUndoStep(next: .none)
        let oldSheet = settings.styles
        let newSheet = updated.styles
        document?.undoManager?.beginUndoGrouping()
        if store.length > 0 {
            writeStore(actionName: nil) { store in
                TextStyling.restyle(store, range: NSRange(location: 0, length: store.length), from: oldSheet, to: newSheet, resolver: fontRoleResolver) { names in
                    func renamed(_ name: String?) -> String? {
                        guard let name, let replacement = renames[name] else { return name }
                        return replacement
                    }
                    names.paragraph = renamed(names.paragraph)
                    names.word = renamed(names.word)
                    names.character = renamed(names.character)
                }
            }
        }
        changeStyles(to: newSheet, restyle: false, actionName: actionName)
        if updated.rules != settings.rules { changeRules(updated.rules, styles: settings.styles) }
        if updated.floatStyles != settings.floatStyles {
            changeListSettings(lists: settings.lists, noteList: nil, styles: settings.styles, floatStyles: updated.floatStyles, actionName: actionName)
        }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(actionName)
    }

    /// Applica le regole uscite dalla scheda; gli stili predefiniti che una regola usa entrano nel documento, una volta
    /// sola. Vero se il documento è cambiato.
    @discardableResult
    func applyRuleChanges(_ result: RulesSheetModel.Result) -> Bool {
        var styles = settings.styles
        styles.styles += result.addedStyles.filter { styles.style(named: $0.name) == nil }
        guard result.rules != settings.rules || styles != settings.styles else { return false }
        endUndoStep(next: .none)
        changeRules(result.rules, styles: styles)
        return true
    }


    /// Cambia le regole (e, se serve, gli stili) in un passo annullabile. Il testo non si tocca: le regole agiscono
    /// solo nella composizione.
    func changeRules(_ rules: [TextRule], styles: StyleSheet) {
        let old = (rules: settings.rules, styles: settings.styles)
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.changeRules(old.rules, styles: old.styles) }
        }
        document?.undoManager?.setActionName("Rules")
        settings.rules = rules
        if styles != settings.styles {
            settings.styles = styles
            reloadStylePopup()
            refreshFromSelection()
        }
        layoutPages()
        definitionsPanel?.documentChanged()
        refreshStylesTab()
        composerModel?.documentChanged(sheet: settings.styles, rules: settings.rules)
    }

    /// Applica gli stili di flottante usciti dalla finestra: le note seguono gli stili rinominati o tolti.
    @discardableResult
    func applyFloatStyleChanges(_ result: FloatStylesSheetModel.Result) -> Bool {
        guard result.floatStyles != settings.floatStyles || !result.renames.isEmpty else { return false }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if store.length > 0, !result.renames.isEmpty {
            writeStore(actionName: nil) { TextStyling.renameFloatStyles(in: $0, result.renames) }
        }
        changeListSettings(lists: settings.lists, noteList: nil, styles: settings.styles, floatStyles: result.floatStyles, actionName: "Float Styles")
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("Float Styles")
        return true
    }

    /// Applica le Liste uscite dalla finestra: le voci e gli stili seguono le Liste rinominate o tolte.
    @discardableResult
    func applyListChanges(_ result: ListsSheetModel.Result) -> Bool {
        let styles = settings.styles.renamingLists(result.renames)
        guard result.lists != settings.lists || result.noteList != settings.noteList || styles != settings.styles
                || result.pageNumbering != settings.pageNumbering else { return false }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if store.length > 0, !result.renames.isEmpty {
            writeStore(actionName: nil) {
                TextStyling.renameLists(in: $0, result.renames)
                SectionEditing.renameListsInSections(result.renames, in: $0)
            }
        }
        change(\.pageNumbering, to: result.pageNumbering, actionName: "Lists")
        // Le serie di note seguono le Liste rinominate o tolte; quella delle note a piè di pagina prende la scelta fatta.
        var floatStyles = settings.floatStyles
        for index in floatStyles.indices {
            if let list = floatStyles[index].listName, let new = result.renames[list] { floatStyles[index].listName = new }
            if floatStyles[index].name == FloatStyle.footnoteName { floatStyles[index].listName = result.noteList }
        }
        changeListSettings(lists: result.lists, noteList: result.noteList, styles: styles, floatStyles: floatStyles, actionName: "Lists")
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("Lists")
        return true
    }

    /// Cambia le Liste, la Lista delle note e gli stili insieme (annullabile). Il testo non si tocca.
    func changeListSettings(lists: [ListDefinition], noteList: String?, styles: StyleSheet, floatStyles: [FloatStyle]? = nil, actionName: String) {
        let old = (lists: settings.lists, floatStyles: settings.floatStyles, styles: settings.styles)
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                controller.changeListSettings(lists: old.lists, noteList: nil, styles: old.styles, floatStyles: old.floatStyles, actionName: actionName)
            }
        }
        document?.undoManager?.setActionName(actionName)
        settings.lists = lists
        if let floatStyles { settings.floatStyles = floatStyles } else { settings.noteList = noteList }
        settings.styles = styles
        reloadStylePopup()
        refreshFromSelection()
        layoutPages()
        definitionsPanel?.documentChanged()
    }


    /// Se una Lista ha finito i suoi segni e non si è ancora deciso che cosa fare, lo chiede: la risposta vale
    /// per la Lista, e si può cambiare nella finestra delle Liste.
    func askAboutListOverflow() {
        guard !isAskingAboutOverflow, let window, window.attachedSheet == nil,
              let name = pagesView.layout?.listsNeedingOverflowChoice.first,
              let index = settings.lists.firstIndex(where: { $0.name == name }),
              let last = settings.lists[index].lastValue else { return }
        isAskingAboutOverflow = true
        let definition = settings.lists[index]
        /// Il segno dell'elemento dopo l'ultimo, con la scelta data.
        func next(_ overflow: ListOverflow) -> String {
            var changed = definition
            changed.overflow = overflow
            changed.parent = nil
            changed.start = 1
            return ListNumberer.sample(of: name, in: [changed], count: last + 1).last ?? ""
        }
        let lastMark = ListNumberer.sample(of: name, in: [{ var d = definition; d.parent = nil; d.start = 1; return d }()], count: last).last ?? ""
        let series = definition.counter.seriesLength != nil
        let choices: [ListOverflow] = [.restart, .double, .numbers]
        // Si chiede al giro successivo: la composizione in corso deve finire prima che si apra la domanda.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.attachedSheet == nil else {
                self?.isAskingAboutOverflow = false
                return
            }
            let alert = NSAlert()
            alert.messageText = "The list “\(name)” has run out of markers"
            alert.informativeText = "After “\(lastMark)” there are no more markers. What should the next item use? "
                + "The choice applies to the whole list, and can be changed in the Lists tab of the detailed interface."
            for choice in choices {
                let title = switch choice {
                case .restart: "Restart: “\(next(.restart))”"
                case .double: series ? "Double: “\(next(.double))”" : "Continue: “\(next(.double))”"
                default: "Switch to numbers: “\(next(.numbers))”"
                }
                alert.addButton(withTitle: title)
            }
            alert.beginSheetModal(for: window) { response in
                self.isAskingAboutOverflow = false
                let picked = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                guard choices.indices.contains(picked), let index = self.settings.lists.firstIndex(where: { $0.name == name }) else { return }
                var lists = self.settings.lists
                lists[index].overflow = choices[picked]
                self.changeListSettings(lists: lists, noteList: self.settings.noteList, styles: self.settings.styles, actionName: "Past the Last Marker")
            }
        }
    }

    /// Sposta le voci selezionate di un livello più in dentro o più in fuori. Non fa nulla (e lo dice) se la
    /// selezione non contiene voci di elenco.
    @discardableResult
    func changeListLevel(by delta: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let affected = TextStyling.listEditRange(in: storage, for: selection.range)
        var hasItem = TextStyling.listItem(in: storage, at: selection.range.location) != nil
        storage.enumerateAttribute(.listItem, in: affected) { value, _, _ in if value != nil { hasItem = true } }
        guard hasItem else { return false }
        // Le voci di una Lista con un nome hanno il livello della Lista: non si spostano.
        return changeList(actionName: delta > 0 ? "Increase Level" : "Decrease Level") { $0.map { $0.listName != nil ? $0 : ListItem(marker: $0.marker, level: $0.level + delta) } }
    }

    /// Vero se la selezione tocca almeno una voce di un elenco semplice, l'unica che cambia livello.
    var selectionHasLevelledItems: Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        var found = TextStyling.listItem(in: storage, at: selection.range.location).map { $0.listName == nil } ?? false
        storage.enumerateAttribute(.listItem, in: TextStyling.listEditRange(in: storage, for: selection.range)) { value, _, stop in
            if let encoded = value as? String, ListItem(encoded: encoded)?.listName == nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    @objc func increaseListLevel(_ sender: Any?) { changeListLevel(by: 1) }
    @objc func decreaseListLevel(_ sender: Any?) { changeListLevel(by: -1) }

    /// Il cursore è in una voce di elenco, fuori da una nota, all'inizio della voce (`atStart`) o in una voce vuota.
    func caretInListItem(atStart: Bool) -> Bool {
        guard let storage = textStorage, noteAnchor == nil, selection.range.length == 0 else { return false }
        let head = selection.range.location
        guard TextStyling.listItem(in: storage, at: head) != nil else { return false }
        if head >= storage.length { return TextStyling.hasEmptyFinalParagraph(storage) }
        let paragraph = TextStyling.bodyParagraph(in: storage, at: head)
        return head == paragraph.range.location && (atStart || paragraph.contentsEnd == paragraph.range.location)
    }

    // MARK: Monitor degli stili: il menu dello stile

    /// Gli stili che riceverebbero le aggiunte scelte, se le si porta nello stile.
    func additionReceivers(_ indices: [Int]) -> [String] {
        var names: [String] = []
        for index in indices where styleAdditions.indices.contains(index) {
            let addition = styleAdditions[index]
            let target = inspectionTarget(addition.level)
            var name: String?
            if let property = addition.property {
                name = TextStyling.receivingStyle(for: property, in: target.text, at: target.range.location)?.name
            } else if let detail = addition.detail,
                      TextStyling.sheet(settings.styles, takingDetail: detail, from: target.text, at: target.range.location, resolver: fontRoleResolver) != nil {
                // Una funzione va nello stile solo se il testo ha il font dello stile.
                name = TextStyling.receivingStyle(for: .size, in: target.text, at: target.range.location)?.name
            }
            if let name, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Le tre azioni di una pastiglia arancione; la stessa vista le usa anche sotto «+N».
    func additionMonitorMenu(at index: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard styleAdditions.indices.contains(index) else { return menu }
        let remove = menu.addItem(withTitle: "Remove", action: #selector(removeAdditionFromMenu(_:)), keyEquivalent: "")
        remove.target = self
        remove.tag = index
        let replacesFormula = styleAdditions[index].property.map { property in
            additionReceivers([index]).contains { settings.styles.formulaDefinition(for: property, inStyle: $0)?.isCalculated == true }
        } ?? false
        let move = menu.addItem(withTitle: replacesFormula ? "Put into the Style, Replacing the Formula" : "Put into the Style", action: #selector(moveAdditionToStyle(_:)), keyEquivalent: "")
        move.target = self
        move.tag = index
        move.isEnabled = !additionReceivers([index]).isEmpty
        let create = menu.addItem(withTitle: "New Style…", action: #selector(newStyleFromAddition(_:)), keyEquivalent: "")
        create.target = self
        create.tag = index
        create.isEnabled = styleAdditions[index].property != nil && store.length > 0
        return menu
    }

    @objc func removeAdditionFromMenu(_ sender: NSMenuItem) { removeStyleAdditions([sender.tag]) }
    @objc func moveAdditionToStyle(_ sender: NSMenuItem) { moveStyleAdditions([sender.tag]) }

    @objc func newStyleFromAddition(_ sender: NSMenuItem) {
        guard styleAdditions.indices.contains(sender.tag), styleAdditions[sender.tag].property != nil else { return }
        let index = sender.tag
        askStyleName(title: "New Style", message: "It contains only this addition and is applied to the selection.", suggestion: nil) { [weak self] name in
            self?.createStyleFromAddition(at: index, named: name)
        }
    }

    /// Il menu della pastiglia dello stile.
    func styleMonitorMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let remove = menu.addItem(withTitle: "Remove All Additions", action: #selector(removeAllStyleAdditions(_:)), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = !styleAdditions.isEmpty
        let receivers = additionReceivers(Array(styleAdditions.indices))
        let quoted = receivers.map { "“\($0)”" }
        let title = switch quoted.count {
        case 0: "Move the Additions into the Style"
        case 1: "Move the Additions into the Style \(quoted[0])"
        default: "Move the Additions into the Styles " + quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
        }
        let replacesFormula = styleAdditions.contains { addition in
            guard let property = addition.property else { return false }
            return receivers.contains { settings.styles.formulaDefinition(for: property, inStyle: $0)?.isCalculated == true }
        }
        let move = menu.addItem(withTitle: title + (replacesFormula ? " (replaces the changed formulas)" : ""), action: #selector(moveStyleAdditionsToStyles(_:)), keyEquivalent: "")
        move.target = self
        move.isEnabled = !receivers.isEmpty
        menu.addItem(.separator())
        let create = menu.addItem(withTitle: "Create a Style from the Selection…", action: #selector(newStyleFromSelection(_:)), keyEquivalent: "")
        create.target = self
        create.isEnabled = store.length > 0
        return menu
    }

    @objc func removeAllStyleAdditions(_ sender: Any?) { removeStyleAdditions(Array(styleAdditions.indices)) }
    @objc func moveStyleAdditionsToStyles(_ sender: Any?) { moveStyleAdditions(Array(styleAdditions.indices)) }

    /// Porta nello stile che le riceve ciascuna aggiunta scelta: tutto il testo di quello stile cambia, e qui
    /// l'aggiunta non è più un'aggiunta. Funzioni e assi vanno nello stile uno per uno. Un passo.
    func moveStyleAdditions(_ indices: [Int]) {
        var sheet = settings.styles
        let receivers = additionReceivers(indices)
        for index in indices where styleAdditions.indices.contains(index) {
            let addition = styleAdditions[index]
            let target = inspectionTarget(addition.level)
            if let property = addition.property {
                if let next = TextStyling.sheet(sheet, takingValueOf: property, from: target.text, at: target.range.location, replacingFormula: true) { sheet = next }
            } else if let detail = addition.detail,
                      let next = TextStyling.sheet(sheet, takingDetail: detail, from: target.text, at: target.range.location, resolver: fontRoleResolver) {
                sheet = next
            }
        }
        guard sheet != settings.styles else { return NSSound.beep() }
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: true, actionName: receivers.count == 1 ? "Additions into the Style “\(receivers[0])”" : "Additions into the Styles")
    }

    @objc func pagesScrolled(_ notification: Notification) { refreshRuler() }

    func pinchForTests(by magnification: CGFloat) { pagesView.pinch(by: magnification, at: NSPoint(x: pagesView.bounds.midX, y: 40)) }

    /// Il righello: la colonna della pagina del cursore, alla scala dello schermo, con i rientri del paragrafo.
    func refreshRuler() {
        refreshZoomTitle()
        guard let layout = pagesView.layout, let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page,
              let pageFrame = pagesView.frameOfPage(page) else {
            rulerView.geometry = nil
            return
        }
        let frame = rulerView.convert(pageFrame, from: pagesView)
        let scale = pagesView.scale
        let setup = layout.setup(forPage: page)
        let style = currentParagraphStyle()
        let right = (style?.tailIndent ?? 0) <= 0 ? -(style?.tailIndent ?? 0) : setup.textRect.width - (style?.tailIndent ?? 0)
        var geometry = RulerView.Geometry(
            pageMinX: frame.minX, pageWidth: frame.width, columnMinX: frame.minX + setup.textRect(forPage: page).minX * scale, columnWidth: setup.textRect.width * scale,
            scale: scale, firstLine: style?.firstLineHeadIndent ?? 0, left: style?.headIndent ?? 0, right: right)
        // Una voce di elenco: in alto dove finisce il segno (i segni si allineano a destra), in basso dove comincia il testo.
        if let list = currentListGeometry(in: layout, page: page) {
            geometry.firstLine = list.markerEnd
            geometry.left = list.textStart
            geometry.markerWidth = list.markerWidth
        }
        rulerView.geometry = geometry
    }

    /// Il paragrafo del cursore: la sua posizione d'inizio, come la portano le righe composte.
    func currentParagraphLocation() -> Int {
        let text = documentText
        let index = min(selection.range.location, text.length)
        if index == text.length, index == 0 || TextStyling.isLineTerminator((text.string as NSString).character(at: index - 1)) { return index }
        return TextStyling.bodyParagraph(in: text, at: min(index, max(text.length - 1, 0))).range.location
    }

    /// Se il cursore sta in una voce di elenco: dove finisce il segno e dove comincia il testo (in punti dal bordo della
    /// colonna, come dicono le misure della voce), e quanto è largo il segno nella pagina composta.
    func currentListGeometry(in layout: DocumentLayout, page: Int) -> (markerEnd: CGFloat, markerWidth: CGFloat, textStart: CGFloat, item: ListItem)? {
        guard let item = selectionListItem() else { return nil }
        let location = currentParagraphLocation()
        let measures = item.resolvedMeasures(in: settings.lists)
        let headIndent = currentParagraphStyle()?.headIndent ?? 0
        let width = layout.pages.flatMap(\.markers).first { $0.paragraphLocation == location }.map { CGFloat(CTLineGetTypographicBounds($0.line, nil, nil, nil)) } ?? 0
        return (headIndent + CGFloat(measures.markerPosition), width, headIndent + CGFloat(measures.textIndent), item)
    }

    /// Per le prove: la cornice di una pagina nella vista delle pagine.
    func pageFrameForTests(_ index: Int) -> NSRect? { pagesView.frameOfPage(index) }
    func dragRulerForTests(_ handle: RulerView.Handle, to value: CGFloat, modifiers: NSEvent.ModifierFlags = []) {
        refreshRuler()
        rulerDragged(handle, value: value, finished: false, modifiers: modifiers)
        rulerDragged(handle, value: value, finished: true, modifiers: modifiers)
    }

    /// Un segno del righello trascinato: mentre si trascina la guida sulla pagina, alla fine la modifica (un passo solo).
    func rulerDragged(_ handle: RulerView.Handle, value: CGFloat, finished: Bool, modifiers: NSEvent.ModifierFlags) {
        guard let edit = rulerEdit(handle, value: value, modifiers: modifiers) else { return }
        guard finished else {
            pagesView.guideX = rulerView.screenX(for: handle, value: value).map { pagesView.convert(NSPoint(x: $0, y: 0), from: rulerView).x }
            // Il testo si ricompone mentre si trascina, solo come anteprima: il documento non cambia ancora. Il valore è
            // agganciato al millimetro, quindi si ricompone solo quando cambia davvero.
            if lastRulerPreview?.handle != handle || lastRulerPreview?.value != value {
                lastRulerPreview = (handle, value)
                preview(edit)
            }
            return
        }
        pagesView.guideX = nil
        lastRulerPreview = nil
        commit(edit)
    }


    /// Ciò che un trascinamento sul righello cambierebbe: la stessa descrizione serve all'anteprima e alla modifica vera.
    enum RulerEdit {
        /// Un valore di paragrafo per i paragrafi selezionati.
        case paragraph(InspectorProperty, StyleValues, actionName: String)
        /// Le voci di elenco di un intervallo (la selezione, o un blocco di voci consecutive).
        case listItems(NSRange, transform: (ListItem?) -> ListItem?, actionName: String)
        /// Le misure di una Lista con un nome.
        case lists([ListDefinition], name: String)
    }

    func rulerEdit(_ handle: RulerView.Handle, value: CGFloat, modifiers: NSEvent.ModifierFlags) -> RulerEdit? {
        guard let geometry = rulerView.geometry else { return nil }
        func paragraph(_ property: InspectorProperty, _ name: String, _ build: (inout StyleValues) -> Void) -> RulerEdit {
            var values = StyleValues()
            build(&values)
            return .paragraph(property, values, actionName: name)
        }
        let headIndent = currentParagraphStyle()?.headIndent ?? 0
        if geometry.markerWidth != nil, let layout = pagesView.layout,
           let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page, let list = currentListGeometry(in: layout, page: page) {
            // Ogni triangolo sposta solo la sua cosa: l'altra posizione si fissa dov'è, perché non la segua.
            let text = Double(list.textStart - headIndent), marker = Double(list.markerEnd - headIndent)
            switch handle {
            case .right: return paragraph(.rightIndent, "Right Indent") { $0.rightIndent = Double(value) }
            case .left: return listMeasureEdit(of: list.item, textIndent: Double(max(value - headIndent, 0)), markerPosition: marker, onlyThisItem: modifiers.contains(.option))
            case .firstLine: return listMeasureEdit(of: list.item, textIndent: text, markerPosition: Double(max(value - headIndent, 0)), onlyThisItem: modifiers.contains(.option))
            }
        }
        switch handle {
        case .left: return paragraph(.leftIndent, "Left Indent") { $0.leftIndent = Double(value) }
        case .firstLine: return paragraph(.firstLineIndent, "First-Line Indent") { $0.firstLineIndent = Double(value - geometry.left) }
        case .right: return paragraph(.rightIndent, "Right Indent") { $0.rightIndent = Double(value) }
        }
    }

    /// Le misure di un elenco cambiate dal righello: di tutta la Lista con un nome, del blocco di voci consecutive per un
    /// elenco semplice, o (con ⌥) solo delle voci selezionate.
    func listMeasureEdit(of item: ListItem, textIndent: Double?, markerPosition: Double?, onlyThisItem: Bool) -> RulerEdit? {
        func updated(_ current: ListItem) -> ListItem {
            var result = current
            if let textIndent { result.textIndent = textIndent }
            if let markerPosition { result.markerPosition = markerPosition }
            return result
        }
        if onlyThisItem { return .listItems(selection.range, transform: { $0.map(updated) }, actionName: "Item Indents") }
        if let name = item.listName, let index = settings.lists.firstIndex(where: { $0.name == name }) {
            var lists = settings.lists
            if let textIndent { lists[index].textIndent = textIndent }
            if let markerPosition { lists[index].markerPosition = markerPosition }
            return .lists(lists, name: name)
        }
        // Il blocco di voci consecutive di elenchi semplici attorno al cursore; cambia il livello della voce.
        let text = documentText
        guard text.length > 0 else { return nil }
        var start = currentParagraphLocation(), end = start
        func isSimpleItem(_ location: Int) -> Bool {
            guard location < text.length, let found = TextStyling.listItem(in: text, at: location) else { return false }
            return found.listName == nil
        }
        while start > 0, isSimpleItem(TextStyling.bodyParagraph(in: text, at: start - 1).range.location) {
            start = TextStyling.bodyParagraph(in: text, at: start - 1).range.location
        }
        while end < text.length, isSimpleItem(end) { end = NSMaxRange(TextStyling.bodyParagraph(in: text, at: end).range) }
        let level = item.level
        return .listItems(NSRange(location: start, length: max(end - start, 1)), transform: { current in
            guard let current, current.listName == nil, current.level == level else { return current }
            return updated(current)
        }, actionName: "List Indents")
    }

    /// L'anteprima: la modifica applicata a una copia del testo (o delle Liste), e le pagine ricomposte da lì.
    func preview(_ edit: RulerEdit) {
        let copy = NSMutableAttributedString(attributedString: documentText)
        var options = settings.layoutOptions
        switch edit {
        case .paragraph(let property, let values, _): TextStyling.setValue(values, of: property, in: copy, range: selection.range)
        case .listItems(let range, let transform, _): TextStyling.setList(in: copy, range: range, transform)
        case .lists(let lists, _): options.lists = lists
        }
        pagesView.layout = PageLayout.layout(copy, setup: settings.pageSetup, options: options)
    }

    /// La modifica vera, alla fine del trascinamento: un passo di annullamento.
    func commit(_ edit: RulerEdit) {
        switch edit {
        case .paragraph(let property, let values, let name):
            editInspected(property, actionName: name) { text, range in TextStyling.setValue(values, of: property, in: text, range: range) }
        case .listItems(let range, let transform, let name):
            endUndoStep(next: .none)
            writeStore(actionName: name) { TextStyling.setList(in: $0, range: range, transform) }
            syncListTypingAttributes()
        case .lists(let lists, let name):
            endUndoStep(next: .none)
            changeListSettings(lists: lists, noteList: nil, styles: settings.styles, floatStyles: settings.floatStyles, actionName: "Indents of the List “\(name)”")
        }
        // Le pagine tornano a essere quelle del documento, anche se il valore finale è quello di partenza.
        layoutPages()
        refreshFromSelection()
        window?.makeFirstResponder(pagesView)
    }

    /// Un documento nuovo è vuoto: il cursore scrive nello stile «Testo».
    func loadEmptyDocument() {
        let sheet = settings.styles
        let character = sheet.resolveCharacter(paragraphStyle: "Testo", wordStyle: nil, characterStyle: nil, base: settings.formulaBase ?? TextStyling.styleBase)
        let probe = Document(styles: sheet, lists: settings.lists, blocks: [
            .paragraph(Paragraph(styleName: "Testo", style: sheet.resolveParagraph(styleName: "Testo"), inlines: [.text(TextRun(" ", style: character))]))
        ]).attributedString().text
        show(NSAttributedString())
        if probe.length > 0 { typingAttributes = probe.attributes(at: 0, effectiveRange: nil) }
    }

    func show(_ text: NSAttributedString) {
        // Il testo caricato va nel deposito senza diventare un passo da annullare.
        resetStore(to: text)
        markedRange = nil
        selection = TextSelection(caret: 0)
        typingAttributes = Self.typingAttributes(in: text, at: selection)
        // Con un testo vuoto il cursore deve comunque avere un font con cui scrivere.
        if text.length == 0, let font = NSFont(name: "HoeflerText-Regular", size: 14) { typingAttributes[.font] = font }
    }

    /// Gli attributi con cui si scriverebbe in una selezione, come li sceglieva l'area di Apple: con una selezione,
    /// quelli del suo primo carattere; al cursore, quelli del carattere che precede, ma all'inizio di un paragrafo
    /// quelli del suo primo carattere (non dell'a capo del paragrafo prima).
    static func typingAttributes(in text: NSAttributedString, at selection: TextSelection) -> [NSAttributedString.Key: Any] {
        guard text.length > 0 else { return [:] }
        let range = selection.range
        var attributes = range.length > 0 ? text.attributes(at: range.location, effectiveRange: nil)
            : typingSource(in: text, at: range.location).map { text.attributes(at: $0, effectiveRange: nil) } ?? [:]
        // Ciò che si scrive accanto a un campo è testo, non un altro campo.
        attributes[.field] = nil
        // La cella è quella del cursore (accanto a una tabella il carattere vicino può essere di una cella, il cursore no).
        let cell = TableEditing.cell(at: range.location, in: text)?.encoded
        attributes[.tableCell] = cell
        attributes[.finalParagraphCell] = cell
        return attributes
    }

    /// Il carattere da cui si prendono gli attributi per scrivere al cursore: quello che precede, ma all'inizio di un
    /// paragrafo quello che segue (l'a capo prima è del paragrafo precedente).
    static func typingSource(in text: NSAttributedString, at location: Int) -> Int? {
        guard text.length > 0 else { return nil }
        let location = min(location, text.length)
        let string = text.string as NSString
        if location > 0, !TextStyling.isLineTerminator(string.character(at: location - 1)) || location == text.length { return location - 1 }
        return min(location, text.length - 1)
    }
}
