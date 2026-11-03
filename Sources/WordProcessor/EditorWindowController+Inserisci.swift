import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Note a piè di pagina (menu Inserisci)

    /// Inserisce una nota nel punto del cursore e porta il cursore nel suo testo, in fondo alla pagina.
    @objc func insertFootnote(_ sender: Any?) {
        insertNote(style: FloatStyle.footnoteName)
    }

    /// Inserisci › Nota di un'altra serie: la serie è lo stile di flottante della voce di menu.
    @objc func insertNoteOfSeries(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        insertNote(style: style)
    }

    /// Gli stili di flottante diversi dalla nota a piè di pagina, per il menu.
    func otherFloatStyles() -> [String] {
        settings.floatStyles.filter { $0.name != FloatStyle.footnoteName && $0.placement != .figure }.map(\.name)
    }

    func insertNote(style: String, image: ImageObject? = nil) {
        guard noteAnchor == nil, textStorage != nil else {
            NSSound.beep()  // una nota dentro una nota non è prevista
            return
        }
        let point = NSMaxRange(selection.range)
        apply(TextSelection(caret: point))
        var attributes = typingAttributes
        let floatStyle = settings.floatStyles.first { $0.name == style }
        if let content = floatStyle?.contentStyle, settings.styles.style(named: content) != nil {
            // Con uno stile del contenuto, il testo della nota nasce con i suoi valori di carattere.
            let character = settings.styles.resolveCharacter(paragraphStyle: content, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            attributes.merge(TextStyling.characterAttributes(for: character).attributes) { $1 }
        } else if floatStyle?.placement.isRunning == true {
            // Intestazioni e piè di pagina: con l'aspetto del testo, non del titolo in cui sono ancorati; cinque sesti del corpo.
            let body = settings.styles.style(named: "Testo")?.target == .paragraph ? "Testo" : nil
            var character = settings.styles.resolveCharacter(paragraphStyle: body, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            character.size = max((character.size * 5 / 6 * 2).rounded() / 2, 4)
            attributes.merge(TextStyling.characterAttributes(for: character).attributes) { $1 }
            attributes[.wordStyleName] = nil
            attributes[.characterStyleName] = nil
        } else if let font = attributes[.font] as? NSFont {
            // Il testo della nota nasce con lo stesso font del corpo, cinque sesti del corpo (12 → 10), arrotondato al mezzo punto.
            attributes[.font] = TextStyling.resized(font as CTFont, to: max((font.pointSize * 5 / 6 * 2).rounded() / 2, 4))
        }
        attributes[.footnote] = style
        if let image { attributes[.floatImage] = ImageAttachment(image) }
        attributes[.kern] = nil
        attributes[.fontTracking] = nil
        insertFormatted(NSAttributedString(string: String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1), attributes: attributes),
                        replacing: NSRange(location: point, length: 0), actionName: style == FloatStyle.footnoteName ? "Nota a piè di pagina" : "Nota «\(style)»")
        // L'inserimento della nota è un passo a sé: ciò che si scrive dentro si annulla separatamente.
        apply(TextSelection(caret: point + 1, affinity: .upstream))
        window?.makeFirstResponder(pagesView)
    }

    /// Mette nel testo un pezzo già formattato, conservandone tutti gli attributi. Va fatto sostituendo
    /// direttamente i caratteri: il comando di inserimento dell'area di scrittura di Apple terrebbe il nostro
    /// contrassegno di nota ma darebbe al testo il corpo del punto in cui lo si inserisce (provato).
    func insertFormatted(_ text: NSAttributedString, replacing range: NSRange, actionName: String) {
        var start = range.location
        writeStore(actionName: actionName) { start = TableEditing.replace(range, in: $0, with: text) }
        setSelection(TextSelection(caret: start + text.length))
    }

    /// Dal testo di una nota torna al corpo, subito dopo il richiamo.
    func leaveNote() {
        guard let anchor = noteAnchor, let storage = textStorage, let span = TextStyling.footnoteSpan(in: storage, anchoredAt: anchor) else { return }
        apply(TextSelection(caret: NSMaxRange(span), affinity: .downstream))
    }

    // MARK: Intestazioni e piè di pagina (menu Inserisci)

    /// Il nome dello stile già pronto per un'intestazione o un piè di pagina di quelle pagine.
    static func runningStyleName(_ placement: FloatStyle.Placement, _ pages: FloatStyle.RunningPages) -> String {
        let base = placement == .pageHead ? FloatStyle.headName : FloatStyle.bottomName
        return switch pages {
        case .all: base
        case .odd: base + " dispari"
        case .even: base + " pari"
        case .first: base + " della prima pagina"
        }
    }

    /// Inserisci › Intestazione / Piè di pagina: la voce porta «head» o «bottom» e le pagine («all», «odd», «even», «first»).
    @objc func insertRunning(_ sender: NSMenuItem) {
        guard let parts = (sender.representedObject as? String)?.split(separator: " ").map(String.init), parts.count == 2,
              let pages = FloatStyle.RunningPages(rawValue: parts[1]) else { return }
        insertRunning(placement: parts[0] == "head" ? .pageHead : .pageBottom, pages: pages)
    }

    /// Àncora un'intestazione (o un piè di pagina) alla fine del titolo della sezione del cursore, o del primo paragrafo se il
    /// cursore non è in una sezione, e porta il cursore nel suo contenuto. Se lì ce n'è già uno dello stesso stile, porta il
    /// cursore in quello. Lo stile, se manca, nasce come quello già pronto; il piè di pagina nasce con il numero di pagina.
    func insertRunning(placement: FloatStyle.Placement, pages: FloatStyle.RunningPages) {
        guard noteAnchor == nil, store.length > 0 else {
            NSSound.beep()
            return
        }
        let name = Self.runningStyleName(placement, pages)
        let paragraph = TextStyling.bodyParagraph(in: store, at: enclosingSections().last?.range.location ?? 0)
        let content = NSRange(location: paragraph.range.location, length: paragraph.contentsEnd - paragraph.range.location)
        for index in content.location..<NSMaxRange(content) where TextStyling.isNoteAnchor(in: store, at: index)
            && store.attribute(.footnote, at: index, effectiveRange: nil) as? String == name {
            apply(TextSelection(caret: index + 1, affinity: .upstream))
            window?.makeFirstResponder(pagesView)
            return
        }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if !settings.floatStyles.contains(where: { $0.name == name }) {
            change(\.floatStyles, to: settings.floatStyles + [.running(name: name, placement: placement, pages: pages)], actionName: name)
        }
        apply(TextSelection(caret: paragraph.contentsEnd))
        insertNote(style: name)
        if placement == .pageBottom { insert(field: .page) }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(name)
    }

    // MARK: Campi (menu Inserisci)

    /// Inserisci › Campo: la voce porta il campo (`Field.encoded`).
    @objc func insertField(_ sender: NSMenuItem) {
        guard let encoded = sender.representedObject as? String, let field = Field(encoded: encoded) else { return }
        insert(field: field)
    }

    /// Mette un campo al cursore (anche nel testo di una nota): un carattere che la composizione sostituisce con il suo testo.
    func insert(field: Field) {
        guard textStorage != nil else { return }
        endUndoStep(next: .none)
        var attributes = typingAttributes
        for key in [NSAttributedString.Key.inlineImage, .floatImage, .sectionTitle, .finalParagraphSection] { attributes[key] = nil }
        attributes[.field] = field.encoded
        let range = selection.range
        insertFormatted(NSAttributedString(string: Field.placeholder, attributes: attributes), replacing: range, actionName: "Campo")
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        window?.makeFirstResponder(pagesView)
    }

    /// I ruoli offerti dai campi delle sezioni: quelli pronti e quelli del testo.
    func fieldRoles() -> [String] {
        var roles = Section.Role.builtIn
        for title in SectionEditing.titles(in: store) where !roles.contains(title.mark.role) { roles.append(title.mark.role) }
        return roles
    }

    // MARK: Sezioni (menu Inserisci)

    @objc func insertSectionSameLevel(_ sender: Any?) { insertSection(.same) }
    @objc func insertSectionInside(_ sender: Any?) { insertSection(.inside) }
    @objc func insertSectionOutside(_ sender: Any?) { insertSection(.outside) }

    /// Inserisci › Sezione: un titolo vuoto al cursore, e il cursore nel titolo. Il testo che segue entra nella sezione.
    func insertSection(_ level: SectionEditing.Level) {
        guard noteAnchor == nil else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        let point = selection.range.location
        let sheet = settings.styles
        var title = point
        writeStore(actionName: "Sezione") { store in title = SectionEditing.insertSection(in: store, at: point, level: level, sheet: sheet) }
        setSelection(TextSelection(caret: title))
        // Anche se il cursore non si è mosso, ora si scrive nel titolo, con i suoi attributi.
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        window?.makeFirstResponder(pagesView)
    }

    // MARK: Tabelle (menu Inserisci)

    /// Tab in una cella: il testo della cella dopo (o prima) è selezionato. Tab nell'ultima cella aggiunge una riga.
    func moveToNeighbourCell(forward: Bool) {
        let point = selection.range.location
        guard let mark = TableEditing.cell(at: point, in: store) else { return }
        var target = TableEditing.neighbourCell(of: point, forward: forward, in: store)
        if target == nil, forward {
            let lastRow = TableEditing.paragraphs(ofTableAt: point, in: store).map(\.mark.row).max() ?? mark.row
            endUndoStep(next: .none)
            var first: Int?
            writeStore(actionName: "Riga") { store in first = TableEditing.insertRow(below: lastRow, ofTableAt: point, in: store) }
            guard let first else { return }
            target = TableEditing.cell(at: first, in: store)
            setSelection(TextSelection(caret: first))
            typingAttributes = Self.typingAttributes(in: store, at: selection)
            return
        }
        guard let target, let range = TableEditing.contentRange(of: target, in: store, near: point) else {
            NSSound.beep()
            return
        }
        apply(TextSelection(anchor: range.location, head: NSMaxRange(range)))
    }


    /// Menu Tabella: la voce porta il comando.
    @objc func tableCommand(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? String).flatMap(TableCommand.init(rawValue:)) else { return }
        perform(command)
    }

    /// Un comando sulle righe e le colonne della tabella del cursore. Il cursore va nella cella nuova, o in quella che
    /// prende il posto della cella tolta.
    func perform(_ command: TableCommand) {
        let point = selection.range.location
        guard noteAnchor == nil, let mark = TableEditing.cell(at: point, in: store),
              let shape = TableEditing.shape(ofTableAt: point, in: store),
              let start = TableEditing.paragraphs(ofTableAt: point, in: store).first?.range.location else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        var target: (row: Int, column: Int)?
        var caret = start
        writeStore(actionName: command.actionName) { store in
            switch command {
            case .rowAbove:
                TableEditing.insertRow(at: mark.row, ofTableAt: start, in: store)
                target = (mark.row, mark.column)
            case .rowBelow:
                TableEditing.insertRow(at: mark.row + 1, ofTableAt: start, in: store)
                target = (mark.row + 1, mark.column)
            case .columnLeft:
                TableEditing.insertColumn(at: mark.column, ofTableAt: start, in: store)
                target = (mark.row, mark.column)
            case .columnRight:
                TableEditing.insertColumn(at: mark.column + 1, ofTableAt: start, in: store)
                target = (mark.row, mark.column + 1)
            case .removeRow:
                TableEditing.removeRow(mark.row, ofTableAt: start, in: store)
                if shape.rows > 1 { target = (min(mark.row, shape.rows - 2), mark.column) }
            case .removeColumn:
                TableEditing.removeColumn(mark.column, ofTableAt: start, in: store)
                if shape.columns > 1 { target = (mark.row, min(mark.column, shape.columns - 2)) }
            case .removeTable:
                caret = TableEditing.removeTable(at: start, in: store)
            }
        }
        if let target, let range = TableEditing.contentRange(of: CellMark(table: mark.table, row: target.row, column: target.column), in: store, near: start) {
            caret = range.location
        }
        setSelection(TextSelection(caret: min(caret, store.length)))
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        refreshInspector()
        window?.makeFirstResponder(pagesView)
    }

    /// Un cambiamento dell'aspetto della tabella del cursore, come un passo di Annulla; la selezione resta.
    func changeTable(actionName: String, _ body: (Int, NSMutableAttributedString) -> Void) {
        let point = selection.range.location
        guard noteAnchor == nil, TableEditing.cell(at: point, in: store) != nil else { return }
        endUndoStep(next: .none)
        let kept = selection
        writeStore(actionName: actionName) { body(point, $0) }
        setSelection(kept)
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        refreshInspector()
    }

    /// Le celle (della tabella dell'inizio della selezione) che la selezione tocca.
    func selectedCells() -> [CellMark] {
        let range = selection.range
        guard noteAnchor == nil, let first = TableEditing.cell(at: range.location, in: store) else { return [] }
        let end = NSMaxRange(range)
        // Una cella che finisce dove la selezione comincia (o comincia dove finisce) non è toccata; con il solo cursore,
        // la cella del cursore.
        return TableEditing.paragraphs(ofTableAt: range.location, in: store)
            .filter { paragraph in
                guard !paragraph.mark.isCaption, paragraph.mark.table == first.table else { return false }
                if range.length == 0 { return paragraph.mark.row == first.row && paragraph.mark.column == first.column }
                return paragraph.range.location < end && NSMaxRange(paragraph.range) > range.location
            }
            .map(\.mark)
    }

    /// Tabella › Unisci le celle: le celle toccate dalla selezione (con le celle unite che il rettangolo tocca) diventano
    /// una, con i loro testi uno dopo l'altro; il cursore va al suo inizio.
    @objc func mergeTableCells(_ sender: Any?) {
        let marks = selectedCells()
        let point = selection.range.location
        guard marks.count > 1 || marks.contains(where: { $0.columnSpan > 1 || $0.rowSpan > 1 }) else { return NSSound.beep() }
        endUndoStep(next: .none)
        var start: Int?
        writeStore(actionName: "Unisci le celle") { start = TableEditing.mergeCells(touching: marks, ofTableAt: point, in: $0) }
        guard let start else { return }
        setSelection(TextSelection(caret: start))
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        refreshInspector()
    }

    /// Tabella › Dividi la cella: la cella unita del cursore torna a coprire una sola posizione.
    @objc func splitTableCell(_ sender: Any?) {
        let point = selection.range.location
        guard noteAnchor == nil, let cell = TableEditing.cell(at: point, in: store), cell.columnSpan > 1 || cell.rowSpan > 1 else { return NSSound.beep() }
        changeTable(actionName: "Dividi la cella") { TableEditing.splitCell(row: cell.row, column: cell.column, ofTableAt: $0, in: $1) }
    }

    /// Menu Tabella › Tabella flottante, con didascalia: la accende con lo stile «Tabella», o la rimette nel testo.
    @objc func toggleTableFloat(_ sender: Any?) {
        guard let cell = TableEditing.cell(at: selection.range.location, in: store) else { return NSSound.beep() }
        setTableFloat(cell.floatStyle == nil ? FloatStyle.tableName : nil)
    }

    /// La tabella del cursore diventa flottante con lo stile dato (che nasce, con la Lista «Tabelle», se è «Tabella» e
    /// manca), con una didascalia in cui va il cursore; con `nil` torna nel testo e perde la didascalia. Un passo di Annulla.
    func setTableFloat(_ name: String?) {
        let point = selection.range.location
        guard noteAnchor == nil, let cell = TableEditing.cell(at: point, in: store), cell.floatStyle != name else { return }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if let name, name == FloatStyle.tableName, !settings.floatStyles.contains(where: { $0.name == name }) {
            var lists = settings.lists
            if !lists.contains(where: { $0.name == ListDefinition.tables.name }) { lists.append(ListDefinition.tables) }
            changeListSettings(lists: lists, noteList: nil, styles: settings.styles, floatStyles: settings.floatStyles + [.defaultTable], actionName: "Tabella flottante")
        }
        let kept = selection
        // Spegnendo, la didascalia va via: il cursore che stava dopo arretra di quanto era lunga, quello che stava dentro va
        // all'inizio della tabella.
        let captions = TableEditing.paragraphs(ofTableAt: point, in: store).filter(\.mark.isCaption).map(\.range)
        var keptLocation = kept.range.location
        if name == nil, let first = captions.first, let last = captions.last {
            let removed = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            if keptLocation >= NSMaxRange(removed) { keptLocation -= removed.length } else if keptLocation >= removed.location { keptLocation = removed.location }
        }
        var caption: Int?
        writeStore(actionName: "Tabella flottante") { caption = TableEditing.setFloat(name, ofTableAt: point, in: $0) }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(name == nil ? "Tabella nel testo" : "Tabella flottante")
        if let caption, name != nil {
            setSelection(TextSelection(caret: caption))
        } else {
            setSelection(TextSelection(caret: min(keptLocation, store.length)))
        }
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        refreshInspector()
    }

    /// Scheda Tabelle: gli stili di tabella, con le tabelle che seguono le rinomine, in un passo di Annulla.
    func applyTableStyleChanges(_ result: TableStylesSheetModel.Result) -> Bool {
        guard result.styles != settings.tableStyles else { return false }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if store.length > 0, !result.renames.isEmpty {
            writeStore(actionName: nil) { TableEditing.renameTableStyles(result.renames, in: $0) }
        }
        change(\.tableStyles, to: result.styles, actionName: "Stili di tabella")
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("Stili di tabella")
        return true
    }

    /// Ispettore della Tabella › Intestazione.
    func setTableHeaderRows(_ count: Int) {
        let point = selection.range.location
        guard TableEditing.cell(at: point, in: store) != nil else { return }
        endUndoStep(next: .none)
        writeStore(actionName: "Righe d'intestazione") { TableEditing.setHeaderRows(count, ofTableAt: point, in: $0) }
        refreshInspector()
    }

    /// Inserisci › Tabella: una tabella 3 × 3, con una riga d'intestazione, dopo il paragrafo del cursore; il cursore
    /// va nella prima cella.
    @objc func insertTable(_ sender: Any?) {
        guard canInsertTable else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        let point = selection.range.location
        let sheet = settings.styles
        var first: Int?
        writeStore(actionName: "Tabella") { store in first = TableEditing.insertTable(in: store, after: point, sheet: sheet) }
        guard let first else { return }
        setSelection(TextSelection(caret: first))
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        window?.makeFirstResponder(pagesView)
    }

    /// Inserisci › Togli la sezione: toglie la sezione più interna in cui sta il cursore (senza chiedere: Annulla la rimette).
    @objc func removeEnclosingSection(_ sender: Any?) {
        guard noteAnchor == nil, let title = enclosingSections().last else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        let point = selection
        writeStore(actionName: "Togli la sezione") { store in SectionEditing.removeSection(title, in: store) }
        setSelection(point)
        // Il segno della sezione tolta non deve tornare con ciò che si scrive.
        typingAttributes = Self.typingAttributes(in: store, at: selection)
    }

    /// Inserisci › Torna a «…»: il capoverso del cursore, e quelli che lo seguono nella sua sezione, tornano alla sezione
    /// che la contiene (o fuori da ogni sezione).
    @objc func returnToOuterSection(_ sender: Any?) {
        let point = selection
        guard noteAnchor == nil, SectionEditing.returnTarget(in: store, atParagraphContaining: point.range.location) != nil else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        writeStore(actionName: "Torna alla sezione esterna") { SectionEditing.returnParagraph(in: $0, containing: point.range.location) }
        setSelection(point, textChanged: true)
    }

    /// Inserisci › Entra in «…»: il capoverso del cursore, che tornava alla sezione esterna, entra in quella che lo precede.
    @objc func joinPreviousSection(_ sender: Any?) {
        let point = selection
        guard noteAnchor == nil, SectionEditing.joinTarget(in: store, atParagraphContaining: point.range.location) != nil else {
            NSSound.beep()
            return
        }
        endUndoStep(next: .none)
        writeStore(actionName: "Entra nella sezione precedente") { SectionEditing.removeReturn(in: $0, containing: point.range.location) }
        setSelection(point, textChanged: true)
    }

    /// Il titolo della voce «Torna a…», o `nil` se il comando non si può dare qui.
    func returnMenuTitle() -> String? {
        guard noteAnchor == nil, store.length > 0,
              let target = SectionEditing.returnTarget(in: store, atParagraphContaining: selection.range.location) else { return nil }
        guard !target.isEmpty, let title = SectionEditing.titles(in: store).first(where: { $0.mark.id == target }) else {
            return "Torna fuori dalle sezioni"
        }
        return "Torna a \(displayTitle(of: title))"
    }

    /// Il titolo della voce «Entra in…», o `nil` se il capoverso del cursore non torna a una sezione esterna.
    func joinMenuTitle() -> String? {
        guard noteAnchor == nil, store.length > 0,
              let title = SectionEditing.joinTarget(in: store, atParagraphContaining: selection.range.location) else { return nil }
        return "Entra in \(displayTitle(of: title))"
    }

    /// Le sezioni in cui sta il cursore, dalla più esterna.
    func enclosingSections() -> [SectionEditing.Title] {
        guard store.length > 0 else { return [] }
        return SectionEditing.enclosing(in: store, at: min(selection.range.location, store.length))
    }

    /// Il titolo che un tasto di cancellazione unirebbe al paragrafo prima: all'indietro dall'inizio del titolo, in avanti
    /// dalla fine del paragrafo che lo precede. Solo con il cursore nel corpo, senza selezione.
    func titleMergedByDeletion(forward: Bool) -> SectionEditing.Title? {
        guard noteAnchor == nil, markedRange == nil, selection.range.length == 0, store.length > 0 else { return nil }
        let caret = selection.range.location
        let start: Int
        if forward {
            guard caret < store.length else { return nil }
            let paragraph = TextStyling.bodyParagraph(in: store, at: caret)
            guard caret == paragraph.contentsEnd, NSMaxRange(paragraph.range) > paragraph.contentsEnd else { return nil }
            start = NSMaxRange(paragraph.range)
        } else {
            guard caret > 0 else { return nil }
            let paragraphStart = caret < store.length ? TextStyling.bodyParagraph(in: store, at: caret).range.location : caret
            guard paragraphStart == caret, TextStyling.isLineTerminator((store.string as NSString).character(at: caret - 1)) else { return nil }
            start = caret
        }
        // Il controllo veloce prima di leggere tutta la struttura.
        let marked = start < store.length ? store.attribute(.sectionTitle, at: start, effectiveRange: nil) != nil
            : store.attribute(.finalParagraphSection, at: store.length - 1, effectiveRange: nil) != nil
        guard marked else { return nil }
        return SectionEditing.title(in: store, atParagraphContaining: start).flatMap { $0.range.location == start ? $0 : nil }
    }

    /// Cambia la sezione guardata dall'ispettore con `body`, in un passo di Annulla; il cursore resta dov'era.
    func changeInspectedSection(actionName: String, _ body: (SectionEditing.Title, DocumentStore) -> Void) {
        guard let title = inspectedSection() else { return }
        endUndoStep(next: .none)
        let point = selection
        writeStore(actionName: actionName) { body(title, $0) }
        setSelection(point)
        typingAttributes = Self.typingAttributes(in: store, at: selection)
        refreshInspector()
    }


    /// Il testo del titolo di una sezione, per mostrarlo: le prime parole, o «senza titolo».
    func displayTitle(of title: SectionEditing.Title) -> String {
        let text = SectionEditing.titleText(of: title, in: store)
        guard !text.isEmpty else { return "senza titolo" }
        return "«" + (text.count > 40 ? String(text.prefix(40)) + "…" : text) + "»"
    }

    func confirmSectionRemoval(_ title: SectionEditing.Title, then remove: @escaping () -> Void) {
        if let answer = sectionRemovalAnswerForTests {
            if answer { remove() }
            return
        }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Togliere la sezione \(displayTitle(of: title)) (\(title.mark.role))?"
        alert.informativeText = "Il suo testo passa alla sezione che la precede e le sue sezioni interne salgono di un livello. Il titolo resta come paragrafo e si unisce a quello prima."
        alert.addButton(withTitle: "Togli la sezione")
        alert.addButton(withTitle: "Annulla")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            remove()
        }
    }

    // MARK: Immagini (menu Inserisci e Formato)

    /// Inserisci › Immagine…: un'immagine nella riga, al cursore, inclusa nel documento o collegata al suo file.
    @objc func insertImage(_ sender: Any?) {
        guard noteAnchor == nil, let window else {
            NSSound.beep()  // le immagini nelle note non sono previste
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        let link = NSButton(checkboxWithTitle: "Collega al file invece di includerlo nel documento", target: nil, action: nil)
        panel.accessoryView = link
        panel.isAccessoryViewDisclosed = true
        let range = selection.range
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            // Le misure naturali dell'immagine, in punti; se è più larga della colonna, la si riduce.
            let natural = NSImage(data: data)?.size ?? CGSize(width: 100, height: 100)
            let column = self.settings.pageSetup.textRect.width
            let scale = natural.width > column ? column / natural.width : 1
            let image = ImageObject(source: link.state == .on ? .linked(url.path) : .embedded(data),
                                    width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
            var attributes = self.typingAttributes
            attributes[.footnote] = nil
            attributes[.inlineImage] = ImageAttachment(image)
            self.insertFormatted(NSAttributedString(string: "\u{FFFC}", attributes: attributes), replacing: range, actionName: "Immagine")
            self.window?.makeFirstResponder(self.pagesView)
        }
    }

    /// Inserisci › Figura…: un'immagine con la sua didascalia, che si colloca come in LaTeX; il cursore va nella didascalia.
    /// Se il documento non ha uno stile di figura, nasce lo stile «Figura» con la Lista «Figure».
    @objc func insertFigure(_ sender: Any?) {
        guard noteAnchor == nil, let window else {
            NSSound.beep()
            return
        }
        let chosen = (sender as? NSMenuItem)?.representedObject as? String
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        let link = NSButton(checkboxWithTitle: "Collega al file invece di includerlo nel documento", target: nil, action: nil)
        panel.accessoryView = link
        panel.isAccessoryViewDisclosed = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            if !self.settings.floatStyles.contains(where: { $0.placement == .figure }) {
                var lists = self.settings.lists
                if !lists.contains(where: { $0.name == ListDefinition.figures.name }) { lists.append(ListDefinition.figures) }
                self.changeListSettings(lists: lists, noteList: nil, styles: self.settings.styles,
                                        floatStyles: self.settings.floatStyles + [.defaultFigure], actionName: "Figura")
            }
            // Lo stile di figura scelto nel menu, se è uno stile di figura del documento; altrimenti il primo.
            let figures = self.settings.floatStyles.filter { $0.placement == .figure }.map(\.name)
            guard let style = figures.first(where: { $0 == chosen }) ?? figures.first else { return }
            let natural = NSImage(data: data)?.size ?? CGSize(width: 200, height: 150)
            let column = self.settings.pageSetup.textRect.width
            let scale = natural.width > column ? column / natural.width : 1
            let image = ImageObject(source: link.state == .on ? .linked(url.path) : .embedded(data),
                                    width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
            self.insertNote(style: style, image: image)
        }
    }

    /// L'immagine selezionata, se la selezione è proprio un'immagine.
    var selectedImage: ImageObject? {
        let range = selection.range
        guard range.length == 1, NSMaxRange(range) <= store.length else { return nil }
        return (store.attribute(.inlineImage, at: range.location, effectiveRange: nil) as? ImageAttachment)?.image
    }

    /// Le misure dell'immagine scelta (doppio clic su di lei, o il menu del tasto destro): larghezza e altezza in punti,
    /// con le proporzioni bloccate se si vuole.
    @objc func editImageSize(_ sender: Any?) {
        guard let window, let image = selectedImage else { return }
        let range = selection.range
        let alert = NSAlert()
        alert.messageText = "Misure dell'immagine"
        alert.informativeText = "In punti. Con le proporzioni bloccate conta la larghezza."
        let width = NSTextField(string: String(format: "%g", image.width))
        let height = NSTextField(string: String(format: "%g", image.height))
        let keep = NSButton(checkboxWithTitle: "Mantieni le proporzioni", target: nil, action: nil)
        keep.state = .on
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Larghezza:"), width], [NSTextField(labelWithString: "Altezza:"), height], [NSView(), keep]])
        grid.frame = NSRect(x: 0, y: 0, width: 260, height: 80)
        alert.accessoryView = grid
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annulla")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, let newWidth = Double(width.stringValue.replacingOccurrences(of: ",", with: ".")), newWidth > 0 else { return }
            var newHeight = Double(height.stringValue.replacingOccurrences(of: ",", with: ".")) ?? image.height
            if keep.state == .on { newHeight = image.height * newWidth / image.width }
            guard newHeight > 0 else { return }
            var resized = image
            resized.width = newWidth.rounded()
            resized.height = newHeight.rounded()
            self.endUndoStep(next: .none)
            self.writeStore(actionName: "Misure dell'immagine") { $0.addAttribute(.inlineImage, value: ImageAttachment(resized), range: range) }
        }
    }

    func reportMissingFonts(_ names: [String]) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = names.count == 1 ? "Un font del documento non è installato" : "\(names.count) font del documento non sono installati"
        alert.informativeText = names.joined(separator: "\n")
            + "\n\nIl testo è mostrato con un font di ripiego. Nel file resta il nome del font originale, finché non assegni tu un altro font a quel testo."
        // La finestra non è ancora a schermo quando il documento viene aperto.
        DispatchQueue.main.async { alert.beginSheetModal(for: window) }
    }
}
