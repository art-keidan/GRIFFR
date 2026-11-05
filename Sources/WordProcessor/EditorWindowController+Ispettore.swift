import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Ispettore e percorso degli oggetti

    func buildPathBar() {
        pathBar.orientation = .horizontal
        pathBar.spacing = 2
        sectionPath.orientation = .horizontal
        sectionPath.spacing = 2
        for (index, object) in InspectedObject.allCases.enumerated() {
            // Le sezioni hanno i loro pulsanti, uno per livello, dopo «Documento».
            if object == .section {
                pathBar.addArrangedSubview(sectionPath)
                continue
            }
            if index > 0 {
                let separator = NSTextField(labelWithString: "›")
                pathBar.addArrangedSubview(separator)
                pathSeparators[object] = separator
            }
            let button = NSButton(title: object.title, target: self, action: #selector(choosePathObject(_:)))
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.showsBorderOnlyWhileMouseInside = true
            button.tag = index
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            pathBar.addArrangedSubview(button)
            pathButtons[object] = button
        }
    }

    @objc func choosePathObject(_ sender: NSButton) {
        inspect(InspectedObject.allCases[sender.tag])
    }

    @objc func choosePathSection(_ sender: NSButton) {
        inspectSection(depth: sender.tag)
    }

    /// Mostra nell'ispettore la sezione di quel livello tra quelle che contengono il cursore (1 la più esterna), come un
    /// clic nel percorso; `nil` la più interna.
    func inspectSection(depth: Int?) {
        inspectedSectionDepth = depth
        inspect(.section)
    }

    /// La sezione che l'ispettore guarda: quella scelta nel percorso, o la più interna in cui sta il cursore.
    func inspectedSection() -> SectionEditing.Title? {
        let enclosing = enclosingSections()
        guard let depth = inspectedSectionDepth, depth >= 1, depth <= enclosing.count else { return enclosing.last }
        return enclosing[depth - 1]
    }

    /// Le sezioni nel percorso: «› Capitolo «Capitolo primo»» per ogni sezione che contiene il cursore.
    func refreshSectionPath(_ enclosing: [SectionEditing.Title]) {
        let titles = enclosing.map { title -> String in
            let name = displayTitle(of: title)
            let role = title.mark.role.prefix(1).uppercased() + title.mark.role.dropFirst()
            return name == "senza titolo" ? role : "\(role) \(name.count > 26 ? String(name.prefix(25)) + "…»" : name)"
        }
        if titles != sectionPathTitles {
            sectionPathTitles = titles
            for view in sectionPath.arrangedSubviews { sectionPath.removeArrangedSubview(view); view.removeFromSuperview() }
            for (index, title) in titles.enumerated() {
                sectionPath.addArrangedSubview(NSTextField(labelWithString: "›"))
                let button = NSButton(title: title, target: self, action: #selector(choosePathSection(_:)))
                button.bezelStyle = .recessed
                button.setButtonType(.pushOnPushOff)
                button.showsBorderOnlyWhileMouseInside = true
                button.tag = index + 1
                button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                sectionPath.addArrangedSubview(button)
            }
        }
        let chosen = inspector.object == .section ? (inspectedSection().map { $0.depth } ?? 0) : 0
        for case let button as NSButton in sectionPath.arrangedSubviews { button.state = button.tag == chosen ? .on : .off }
    }


    /// Sceglie l'oggetto di cui l'ispettore mostra le proprietà, come un clic nel percorso.
    func inspect(_ object: InspectedObject) {
        inspector.object = object
        refreshInspector()
    }


    func connectInspector() {
        inspector.families = OpticalFonts.families(NSFontManager.shared.availableFontFamilies).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        inspector.groupsFamilies = FontMenuPreferences.groupsFamilies
        inspector.languages = Self.languages.map { InspectorModel.LanguageChoice(code: $0, name: Self.languageName($0)) }
        inspector.set = { [weak self] property, values in self?.inspectorSet(property, values) }
        inspector.reset = { [weak self] property in self?.inspectorReset(property) }
        inspector.moveToStyle = { [weak self] property in self?.inspectorMoveToStyle(property) }
        inspector.resetDetail = { [weak self] detail in self?.inspectorResetDetail(detail) }
        inspector.moveDetailToStyle = { [weak self] detail in self?.inspectorMoveDetailToStyle(detail) }
        inspector.createStyle = { [weak self] in self?.createStyleFromInspector() }
        inspector.openFormula = { [weak self] name in self?.showStyleComposer(style: name) }
        inspector.replaceFormula = { [weak self] property in
            guard let self, let value = self.inspector.values.first(where: { $0.property == property }) else { return }
            self.inspector.modes[property] = .style
            self.setInStyle(property, value.value, replacingFormula: true)
        }
        inspector.setPageSetup = { [weak self] setup in self?.setInspectedPageSetup(setup) }
        inspector.createRule = { [weak self] in self?.createRuleFromInspector() }
        inspector.setSectionRole = { [weak self] role in self?.changeInspectedSection(actionName: "Ruolo della sezione") { SectionEditing.setRole(role, of: $0, in: $1) } }
        inspector.setSectionPageTypes = { [weak self] types in
            self?.changeInspectedSection(actionName: "Tipi di pagina della sezione") { SectionEditing.setPageTypes(types, of: $0, in: $1) }
        }
        inspector.setSectionPageNumbering = { [weak self] list in
            self?.changeInspectedSection(actionName: "Numeri di pagina della sezione") { SectionEditing.setPageNumbering(list, of: $0, in: $1) }
        }
        inspector.setSectionStart = { [weak self] start in
            self?.changeInspectedSection(actionName: "Inizio della sezione") { SectionEditing.setStart(start, of: $0, in: $1) }
        }
        inspector.moveSection = { [weak self] delta in
            guard let self else { return }
            // L'ispettore segue la sezione spostata, anche se nel percorso era scelto un livello preciso.
            let chosen = self.inspectedSectionDepth
            self.changeInspectedSection(actionName: delta > 0 ? "Sezione più dentro" : "Sezione più fuori") { SectionEditing.moveSection($0, by: delta, in: $1) }
            if let chosen {
                self.inspectedSectionDepth = max(chosen + delta, 1)
                self.refreshInspector()
            }
        }
        inspector.removeSection = { [weak self] in
            guard let self else { return }
            self.changeInspectedSection(actionName: "Togli la sezione") { SectionEditing.removeSection($0, in: $1) }
            self.inspectedSectionDepth = nil
            self.refreshInspector()
        }
        inspector.setTableHeaderRows = { [weak self] count in self?.setTableHeaderRows(count) }
        inspector.tableCommand = { [weak self] command in self?.perform(command) }
        inspector.setTableStyle = { [weak self] name in
            self?.changeTable(actionName: "Stile della tabella") { TableEditing.setStyle(name, ofTableAt: $0, in: $1) }
        }
        inspector.setTableFloat = { [weak self] name in self?.setTableFloat(name) }
        inspector.splitCell = { [weak self] in self?.splitTableCell(nil) }
        inspector.changeTable = { [weak self] change in
            // Uno schema di filetti scelto per la tabella vale per tutte le celle: i lati detti per le celle si tolgono.
            var clearing = false
            if case .rules(let scheme) = change, scheme != nil { clearing = true }
            self?.changeTable(actionName: "Aspetto della tabella") { point, store in
                TableEditing.changeTableValues(ofTableAt: point, in: store, clearingCellBorders: clearing) { change.apply(to: &$0) }
            }
        }
        inspector.changeCell = { [weak self] change in
            guard let self, let mark = TableEditing.cell(at: self.selection.range.location, in: self.store) else { return }
            self.changeTable(actionName: "Aspetto della cella") { point, store in
                TableEditing.changeCellValues(row: mark.row, column: mark.column, ofTableAt: point, in: store) { change.apply(to: &$0) }
            }
        }
        inspector.setDocumentLanguage = { [weak self] language in self?.change(\.language, to: language, actionName: "Lingua del documento") }
        inspector.setHyphenates = { [weak self] on in self?.change(\.hyphenates, to: on, actionName: "Sillabazione") }
        inspector.setGlyphExpansionLimit = { [weak self] value in self?.change(\.glyphExpansionLimit, to: value, actionName: "Espansione glifi") }
        inspector.glyphExpansionDragging = { [weak self] dragging in self?.groupContinuousChanges(dragging, actionName: "Espansione glifi") }
        inspector.setNoteList = { [weak self] name in
            guard let self else { return }
            self.changeListSettings(lists: self.settings.lists, noteList: name, styles: self.settings.styles, actionName: "Lista delle note")
        }
    }

    /// Il testo che l'ispettore guarda e modifica per un livello. Senza selezione, per carattere e parola conta ciò
    /// che si scriverà (gli attributi di scrittura): lo rappresenta un carattere di prova. Lo stesso in fondo al
    /// testo e in un documento vuoto.
    func inspectionTarget(_ level: StyleTarget) -> (text: NSAttributedString, range: NSRange, isProbe: Bool) {
        let text = documentText
        let range = selection.range
        if text.length == 0 || range.length == 0 && (level != .paragraph || range.location >= text.length) {
            return (NSAttributedString(string: " ", attributes: typingAttributes), NSRange(location: 0, length: 0), true)
        }
        return (text, range, false)
    }

    func refreshInspector() {
        inspector.documentLanguage = settings.language
        syncPageInspector()
        inspector.hyphenates = settings.hyphenates
        inspector.usesOpticalMargins = settings.usesOpticalMargins
        inspector.appliesFontTracking = settings.appliesFontTracking
        inspector.glyphExpansionLimit = settings.glyphExpansionLimit
        inspector.noteList = settings.noteList
        inspector.lists = settings.lists.map(\.name)
        // Le sezioni: nel percorso, e nell'ispettore se è lei l'oggetto scelto.
        let enclosing = enclosingSections()
        refreshSectionPath(enclosing)
        var sectionInfo: InspectorModel.SectionInfo?
        if inspector.object == .section, let title = inspectedSection() {
            let contents = SectionEditing.contents(of: title, in: store)
            sectionInfo = InspectorModel.SectionInfo(role: title.mark.role, title: displayTitle(of: title), depth: title.depth, paragraphs: contents.paragraphs,
                                                     sections: contents.sections, canMoveInside: SectionEditing.canMoveInside(title, in: store),
                                                     canMoveOutside: title.depth > 1, start: title.mark.start,
                                                     pageTypes: title.mark.pageTypes, typeNames: settings.pageTypes.map(\.name),
                                                     pageNumbering: title.mark.pageNumbering, listNames: settings.lists.map(\.name))
        }
        if inspector.section != sectionInfo { inspector.section = sectionInfo }
        // La tabella: nel percorso solo quando il cursore ci sta.
        let point = selection.range.location
        let cell = noteAnchor == nil ? TableEditing.cell(at: point, in: store) : nil
        for object in [InspectedObject.table, .cell] {
            pathButtons[object]?.isHidden = cell == nil
            pathSeparators[object]?.isHidden = cell == nil
        }
        if cell == nil, inspector.object == .table || inspector.object == .cell { inspector.object = .paragraph }
        var tableInfo: InspectorModel.TableInfo?
        var cellInfo: InspectorModel.CellInfo?
        if let cell, let shape = TableEditing.shape(ofTableAt: point, in: store) {
            let resolved = TableStyle.resolved(styleName: cell.style, values: cell.tableValues, in: settings.tableStyles)
            var floatChoices = settings.floatStyles.filter { $0.placement == .figure }.map(\.name)
            if !floatChoices.contains(FloatStyle.tableName) { floatChoices.append(FloatStyle.tableName) }
            if let float = cell.floatStyle, !floatChoices.contains(float) { floatChoices.append(float) }
            tableInfo = InspectorModel.TableInfo(rows: shape.rows, columns: shape.columns, headerRows: shape.headerRows, row: cell.row + 1, column: cell.column + 1,
                                                 style: cell.style, styleNames: settings.tableStyles.map(\.name), values: cell.tableValues, resolved: resolved,
                                                 floatStyle: cell.floatStyle, floatChoices: floatChoices)
            cellInfo = InspectorModel.CellInfo(row: cell.row + 1, column: cell.column + 1, values: cell.cellValues, tableBackground: resolved.background ?? "",
                                               tableAlignment: resolved.verticalAlignment ?? .top, tablePadding: resolved.padding ?? CellInsets(all: 4),
                                               tableRuleWidth: resolved.ruleWidth ?? 0.5, columnSpan: cell.columnSpan, rowSpan: cell.rowSpan)
        }
        if inspector.table != tableInfo { inspector.table = tableInfo }
        if inspector.cell != cellInfo { inspector.cell = cellInfo }
        // Il percorso: ogni livello con il suo stile.
        let paragraphTarget = inspectionTarget(.paragraph), runTarget = inspectionTarget(.character)
        func name(_ key: NSAttributedString.Key, in target: (text: NSAttributedString, range: NSRange, isProbe: Bool)) -> String? {
            target.text.length > 0 ? target.text.attribute(key, at: min(target.range.location, target.text.length - 1), effectiveRange: nil) as? String : nil
        }
        let names: [InspectedObject: String?] = [.document: nil, .paragraph: name(.paragraphStyleName, in: paragraphTarget),
                                                 .word: name(.wordStyleName, in: runTarget), .character: name(.characterStyleName, in: runTarget)]
        for (object, button) in pathButtons {
            button.title = (names[object] ?? nil).map { "\(object.title) «\($0)»" } ?? object.title
            button.state = object == inspector.object ? .on : .off
        }
        inspector.styleName = names[inspector.object] ?? nil
        refreshFacts()
        guard let level = inspector.object.level else {
            inspector.values = []
            if !inspector.details.isEmpty { inspector.details = [] }
            return
        }
        let target = inspectionTarget(level)
        refreshInspectorDetails(level == .character ? target : nil)
        var values = TextStyling.inspect(level, in: target.text, range: target.range, sheet: settings.styles, resolver: fontRoleResolver)
        // Le regole agiscono solo componendo: ciò che danno lì si legge dall'ultima composizione.
        let at = selection.range.location
        let hasContextualStyles = settings.styles.styles.contains { $0.formulas.contains(where: \.isRuntimeRule) }
        if let layout = pagesView.layout, !settings.rules.isEmpty || hasContextualStyles, at < layout.text.length, at < store.length {
            let rules = layout.touchingRules(at: at, rules: settings.rules, sheet: settings.styles, affinity: selection.affinity)
            values = TextStyling.withRuleSources(values, rules: rules, in: target.text, at: target.isProbe ? 0 : target.range.location,
                                                 sheet: settings.styles, resolver: fontRoleResolver)
        }
        if inspector.values != values { inspector.values = values }
        var receivers: [InspectorProperty: String] = [:]
        for value in values {
            receivers[value.property] = TextStyling.receivingStyle(for: value.property, in: target.text, at: target.range.location)?.name
        }
        inspector.receivers = receivers
        inspector.formulaDefinitions = Dictionary(uniqueKeysWithValues: values.compactMap { value in
            if let name = receivers[value.property], let definition = settings.styles.formulaDefinition(for: value.property, inStyle: name) {
                return (value.property, definition)
            }
            if case .style(let name) = value.source, let definition = settings.styles.formulaDefinition(for: value.property, inStyle: name) {
                return (value.property, definition)
            }
            return nil
        })
        if let family = values.first(where: { $0.property == .family })?.value.family {
            inspector.faces = OpticalFonts.members(ofFamily: family).compactMap { member in
                guard let name = member[0] as? String, let title = member[1] as? String else { return nil }
                return InspectorModel.FaceChoice(name: name, title: title)
            }
        }
    }

    /// Le proprietà dinamiche dell'oggetto scelto nell'ispettore, lette dall'ultima composizione.
    func refreshFacts() {
        guard let layout = pagesView.layout else {
            inspector.facts = []
            return
        }
        typealias Fact = InspectorModel.Fact
        func points(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + " pt" }
        func yesNo(_ value: Bool) -> String { value ? "sì" : "no" }
        func rulesText(_ rules: [String]) -> String { rules.isEmpty ? "nessuna" : rules.joined(separator: "\n") }
        let index = selection.head
        var facts: [Fact] = []
        switch inspector.object {
        case .section:
            if let title = inspectedSection() {
                let span = SectionEditing.range(of: title, in: store)
                let first = layout.pageFacts(at: span.location, affinity: .downstream)?.number
                let last = layout.pageFacts(at: max(NSMaxRange(span) - 1, span.location), affinity: .downstream)?.number
                if let first, let last { facts = [Fact(title: "Pagine", value: first == last ? "\(first)" : "\(first)–\(last)")] }
            }
        case .cell:
            break
        case .table:
            let cells = TableEditing.paragraphs(ofTableAt: selection.range.location, in: store)
            if let first = cells.first, let last = cells.last,
               let firstPage = layout.pageFacts(at: first.range.location, affinity: .downstream)?.number,
               let lastPage = layout.pageFacts(at: last.range.location, affinity: .downstream)?.number {
                facts = [Fact(title: "Pagine", value: firstPage == lastPage ? "\(firstPage)" : "\(firstPage)–\(lastPage)")]
            }
        case .document:
            let d = layout.documentFacts()
            facts = [Fact(title: "Pagine", value: "\(d.pageCount)"), Fact(title: "Paragrafi", value: "\(d.paragraphCount)"),
                     Fact(title: "Parole", value: "\(d.wordCount)"), Fact(title: "Note", value: "\(d.noteCount)")]
        case .page:
            if let p = layout.pageFacts(at: index, affinity: selection.affinity) {
                facts = [Fact(title: "Numero", value: "\(p.number) (\(p.isEven ? "pari" : "dispari"))"),
                         Fact(title: "Righe del corpo", value: "\(p.lineCount)"),
                         Fact(title: "Spazio vuoto in fondo", value: points(p.freeSpace)),
                         Fact(title: "Ha note", value: yesNo(p.hasNotes)), Fact(title: "Ha figure", value: yesNo(p.hasFigures))]
            }
        case .paragraph:
            if let p = layout.paragraphFacts(at: index, rules: settings.rules, sheet: settings.styles) {
                let pages = p.isSplit ? "\(p.firstPage)–\(p.lastPage), si spezza tra le pagine" : "\(p.firstPage)"
                let position = switch (p.isFirstOnPage, p.isLastOnPage) {
                case (true, true): "il primo e l'ultimo della pagina"
                case (true, false): "il primo della pagina"
                case (false, true): "l'ultimo della pagina"
                case (false, false): "né il primo né l'ultimo"
                }
                let previous = p.isDocumentStart ? "niente: è il primo del documento" : p.previousStyle.map { "un paragrafo «\($0)»" } ?? "un paragrafo senza stile"
                facts = [Fact(title: "Righe", value: "\(p.lineCount)"), Fact(title: "Pagina", value: pages), Fact(title: "Posizione", value: position),
                         Fact(title: "Parole", value: "\(p.wordCount)"), Fact(title: "Righe con trattino", value: "\(p.hyphenatedLines)"),
                         Fact(title: "Ultima riga", value: "\(points(p.lastLineWidth)), \(Int((p.lastLineFill * 100).rounded()))% della riga"),
                         Fact(title: "Lo precede", value: previous), Fact(title: "Regole", value: rulesText(p.rules))]
                let start = TextStyling.bodyParagraph(in: store, at: index).range.location
                if let opening = layout.pageStarts[start] {
                    facts.append(Fact(title: "Apertura pagina", value: "Stile «\(opening.style)» · \(points(opening.effective)) (richiesti \(points(opening.requested)))"))
                }
            }
        case .line:
            if let l = layout.lineFacts(at: index, affinity: selection.affinity) {
                let change = abs(l.justification) < 0.05 ? "nessuna" : (l.justification > 0 ? "allargata di " : "stretta di ") + points(abs(l.justification))
                facts = [Fact(title: "Posizione", value: "riga \(l.number) di \(l.count) del\(l.isNote ? "la nota" : " paragrafo")"),
                         Fact(title: "Pagina", value: "\(l.page)"), Fact(title: "Larghezza naturale", value: points(l.naturalWidth)),
                         Fact(title: "Giustificazione", value: change), Fact(title: "A disposizione", value: points(l.availableWidth)),
                         Fact(title: "Finisce con un trattino", value: yesNo(l.endsWithHyphen)), Fact(title: "Parole", value: "\(l.wordCount)")]
            }
        case .word, .character:
            // Come i valori sopra: dove comincia la selezione (con una parola selezionata, la fine è lo spazio dopo).
            let start = selection.range.length > 0 ? selection.range.location : index
            facts = [Fact(title: "Regole qui", value: rulesText(layout.rules(touching: start, rules: settings.rules, sheet: settings.styles,
                                                                               affinity: selection.affinity)))]
        }
        if inspector.facts != facts { inspector.facts = facts }
    }

    /// Cambia il testo dell'ispettore (o, senza selezione, ciò che si scriverà) con `body`, come una modifica annullabile.
    func editInspected(_ property: InspectorProperty, actionName: String, _ body: (NSMutableAttributedString, NSRange) -> Void) {
        endUndoStep(next: .none)
        let target = inspectionTarget(property.level)
        if target.isProbe {
            let probe = NSMutableAttributedString(attributedString: target.text)
            body(probe, NSRange(location: 0, length: probe.length))
            typingAttributes = probe.attributes(at: 0, effectiveRange: nil)
        } else {
            let store = store
            let affected = property.level == .paragraph ? TextStyling.paragraphRange(in: store, for: target.range) : target.range
            guard affected.length > 0 else { return }
            writeStore(actionName: actionName) { body($0, target.range) }
        }
        refreshFromSelection()
    }

    func inspectorSet(_ property: InspectorProperty, _ values: StyleValues) {
        if inspector.mode(property) == .style, inspector.receivers[property] != nil {
            setInStyle(property, values)
            return
        }
        if property == .list {
            // La Lista passa dai comandi degli elenchi, che sanno trattare anche il paragrafo vuoto in fondo.
            let list = values.list
            changeList(actionName: property.title) { _ in list }
            refreshFromSelection()
            return
        }
        // Un valore che dà una regola, cambiato qui, vale solo qui: vince sulla regola anche se coincide con lo stile.
        let fromRule = if case .rule = inspector.values.first(where: { $0.property == property })?.source { true } else { false }
        editInspected(property, actionName: property.title) { text, range in
            TextStyling.setValue(values, of: property, in: text, range: range, resolver: fontRoleResolver)
            if fromRule { TextStyling.setRuleException(property, true, in: text, range: range) }
        }
    }

    func inspectorReset(_ property: InspectorProperty) {
        if property == .list {
            let target = inspectionTarget(.paragraph)
            let name = target.text.length > 0 ? target.text.attribute(.paragraphStyleName, at: min(target.range.location, target.text.length - 1), effectiveRange: nil) as? String : nil
            let list = settings.styles.values(of: name).list
            changeList(actionName: "Torna alla Lista dello stile") { _ in list }
            refreshFromSelection()
            return
        }
        let sheet = settings.styles
        editInspected(property, actionName: "Torna al valore ereditato") { text, range in TextStyling.resetValue(of: property, in: text, range: range, sheet: sheet, resolver: self.fontRoleResolver) }
    }

    /// Porta nello stile il valore che il testo ha ora.
    func inspectorMoveToStyle(_ property: InspectorProperty) {
        let target = inspectionTarget(property.level)
        guard let receiver = inspector.receivers[property],
              let sheet = TextStyling.sheet(settings.styles, takingValueOf: property, from: target.text, at: target.range.location, replacingFormula: true) else { return }
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: true, actionName: "Stile «\(receiver)»: \(property.title.lowercased())")
    }

    /// Le funzioni, gli assi e il corpo ottico del carattere scelto, per l'ispettore; nessuno per gli altri oggetti.
    func refreshInspectorDetails(_ target: (text: NSAttributedString, range: NSRange, isProbe: Bool)?) {
        guard let target else {
            if !inspector.details.isEmpty { inspector.details = [] }
            return
        }
        let details = TextStyling.inspectDetails(in: target.text, range: target.range, sheet: settings.styles, resolver: fontRoleResolver)
        if inspector.details != details { inspector.details = details }
        let receiver = TextStyling.receivingStyle(for: .size, in: target.text, at: target.range.location)?.name
        if inspector.detailReceiver != receiver { inspector.detailReceiver = receiver }
        // Si può portare nello stile solo se il testo ha il font che gli stili gli danno.
        let movable = details.isEmpty ? false : details.contains { detail in
            TextStyling.sheet(settings.styles, takingDetail: detail.detail, from: target.text, at: target.range.location, resolver: fontRoleResolver) != nil
        }
        if inspector.detailsMovable != movable { inspector.detailsMovable = movable }
    }

    func inspectorResetDetail(_ detail: FontDetail) {
        let sheet = settings.styles, resolver = fontRoleResolver
        let title = inspector.details.first { $0.detail == detail }?.title ?? "funzione"
        editInspected(.size, actionName: "Torna al valore ereditato: \(title.lowercased())") { text, range in
            TextStyling.resetDetail(detail, in: text, range: range, sheet: sheet, resolver: resolver)
        }
    }

    /// Porta nello stile la sola funzione (o il solo asse) che il testo ha ora; le altre restano come sono.
    func inspectorMoveDetailToStyle(_ detail: FontDetail) {
        let target = inspectionTarget(.character)
        guard let receiver = inspector.detailReceiver,
              let sheet = TextStyling.sheet(settings.styles, takingDetail: detail, from: target.text, at: target.range.location,
                                            resolver: fontRoleResolver) else { return }
        let title = inspector.details.first { $0.detail == detail }?.title ?? "funzione"
        endUndoStep(next: .none)
        changeStyles(to: sheet, restyle: true, actionName: "Stile «\(receiver)»: \(title.lowercased())")
    }

    /// Mette un valore nello stile: tutto il testo che lo eredita cambia, e la selezione perde il suo valore dato a
    /// mano, se ne aveva uno, per prendere quello dello stile.
    func setInStyle(_ property: InspectorProperty, _ values: StyleValues, replacingFormula: Bool = false) {
        let target = inspectionTarget(property.level)
        let copy = NSMutableAttributedString(attributedString: target.text)
        TextStyling.setValue(values, of: property, in: copy, range: target.isProbe ? NSRange(location: 0, length: copy.length) : target.range)
        guard let receiver = inspector.receivers[property],
              let sheet = TextStyling.sheet(settings.styles, takingValueOf: property, from: copy, at: target.range.location, replacingFormula: replacingFormula) else { return }
        let actionName = "Stile «\(receiver)»: \(property.title.lowercased())"
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        changeStyles(to: sheet, restyle: true, actionName: actionName)
        let newSheet = settings.styles
        editInspected(property, actionName: actionName) { text, range in TextStyling.resetValue(of: property, in: text, range: range, sheet: newSheet, resolver: self.fontRoleResolver) }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(actionName)
    }
}
