import AppKit
import Typesetting

extension EditorWindowController {
    // MARK: Ciò che la selezione guarda e cambia

    /// La sezione su cui agiscono i comandi delle sezioni: quella del livello scelto (1 la più esterna), o la più
    /// interna in cui sta il cursore.
    func inspectedSection() -> SectionEditing.Title? {
        let enclosing = enclosingSections()
        guard let depth = inspectedSectionDepth, depth >= 1, depth <= enclosing.count else { return enclosing.last }
        return enclosing[depth - 1]
    }

    /// Il testo che i comandi guardano e modificano per un livello. Senza selezione, per carattere e parola conta ciò
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

    /// Cambia il testo della selezione (o, senza selezione, ciò che si scriverà) con `body`, come una modifica annullabile.
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

    /// Un valore dato al testo della selezione, come una modifica annullabile (la Lista passa dai comandi degli elenchi).
    func setSelectionValue(_ property: InspectorProperty, _ values: StyleValues) {
        if property == .list {
            let list = values.list
            changeList(actionName: property.title) { _ in list }
            refreshFromSelection()
            return
        }
        editInspected(property, actionName: property.title) { text, range in
            TextStyling.setValue(values, of: property, in: text, range: range, resolver: fontRoleResolver)
        }
    }

    /// I valori che il testo della selezione ha ora, con la loro provenienza (stile, mano, regola).
    func selectionValues(_ level: StyleTarget) -> [InspectedValue] {
        let target = inspectionTarget(level)
        return TextStyling.inspect(level, in: target.text, range: target.range, sheet: settings.styles, resolver: fontRoleResolver)
    }

    /// Mette un valore nello stile che lo riceve: tutto il testo che lo eredita cambia, e la selezione perde il suo
    /// valore dato a mano, se ne aveva uno, per prendere quello dello stile.
    func setInStyle(_ property: InspectorProperty, _ values: StyleValues, replacingFormula: Bool = false) {
        let target = inspectionTarget(property.level)
        let copy = NSMutableAttributedString(attributedString: target.text)
        TextStyling.setValue(values, of: property, in: copy, range: target.isProbe ? NSRange(location: 0, length: copy.length) : target.range)
        guard let receiver = TextStyling.receivingStyle(for: property, in: target.text, at: target.range.location)?.name,
              let sheet = TextStyling.sheet(settings.styles, takingValueOf: property, from: copy, at: target.range.location, replacingFormula: replacingFormula) else { return }
        let actionName = "Style “\(receiver)”: \(property.title.lowercased())"
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        changeStyles(to: sheet, restyle: true, actionName: actionName)
        let newSheet = settings.styles
        editInspected(property, actionName: actionName) { text, range in TextStyling.resetValue(of: property, in: text, range: range, sheet: newSheet, resolver: self.fontRoleResolver) }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(actionName)
    }

    /// Il tipo della pagina del cursore: il suo formato e, se ne ha uno, il nome.
    func caretPageSetup() -> (setup: PageSetup, typeName: String?) {
        if let layout = pagesView.layout, let page = layout.caret(at: selection.head, affinity: selection.affinity)?.page {
            return (layout.setup(forPage: page), layout.pages[page].typeName)
        }
        return (settings.pageSetup, nil)
    }

    /// Cambia il tipo della pagina del cursore (il predefinito, o quello con un nome).
    func setCaretPageSetup(_ setup: PageSetup) {
        if let name = caretPageSetup().typeName, let index = settings.pageTypes.firstIndex(where: { $0.name == name }) {
            var types = settings.pageTypes
            types[index].setup = setup
            change(\.pageTypes, to: types, actionName: "Page type “\(name)”")
        } else {
            change(\.pageSetup, to: setup, actionName: "Page Setup")
        }
    }

    // MARK: Sezioni, tabelle e celle (i comandi restano; i moduli torneranno in una forma nuova)

    /// La sezione su cui agiscono i comandi, descritta come la mostravano i moduli.
    func sectionInfo() -> InspectorModel.SectionInfo? {
        guard let title = inspectedSection() else { return nil }
        let contents = SectionEditing.contents(of: title, in: store)
        return InspectorModel.SectionInfo(role: title.mark.role, title: displayTitle(of: title), depth: title.depth, paragraphs: contents.paragraphs,
                                          sections: contents.sections, canMoveInside: SectionEditing.canMoveInside(title, in: store),
                                          canMoveOutside: title.depth > 1, start: title.mark.start,
                                          pageTypes: title.mark.pageTypes, typeNames: settings.pageTypes.map(\.name),
                                          pageNumbering: title.mark.pageNumbering, listNames: settings.lists.map(\.name))
    }

    func setSectionRole(_ role: String) {
        changeInspectedSection(actionName: "Section Role") { SectionEditing.setRole(role, of: $0, in: $1) }
    }

    func setSectionPageTypes(_ types: SectionPageTypes) {
        changeInspectedSection(actionName: "Section Page Types") { SectionEditing.setPageTypes(types, of: $0, in: $1) }
    }

    func setSectionPageNumbering(_ list: String?) {
        changeInspectedSection(actionName: "Section Page Numbers") { SectionEditing.setPageNumbering(list, of: $0, in: $1) }
    }

    func setSectionStart(_ start: SectionStart) {
        changeInspectedSection(actionName: "Section Start") { SectionEditing.setStart(start, of: $0, in: $1) }
    }

    /// Sposta la sezione dentro o fuori di un livello; il livello scelto la segue.
    func moveInspectedSection(by delta: Int) {
        let chosen = inspectedSectionDepth
        changeInspectedSection(actionName: delta > 0 ? "Section In" : "Section Out") { SectionEditing.moveSection($0, by: delta, in: $1) }
        if let chosen { inspectedSectionDepth = max(chosen + delta, 1) }
    }

    func removeInspectedSection() {
        changeInspectedSection(actionName: "Remove Section") { SectionEditing.removeSection($0, in: $1) }
        inspectedSectionDepth = nil
    }

    /// La tabella e la cella del cursore, descritte come le mostravano i moduli; `nil` fuori da una tabella.
    func tableAndCellInfo() -> (table: InspectorModel.TableInfo, cell: InspectorModel.CellInfo)? {
        let point = selection.range.location
        guard noteAnchor == nil, let cell = TableEditing.cell(at: point, in: store), let shape = TableEditing.shape(ofTableAt: point, in: store) else { return nil }
        let resolved = TableStyle.resolved(styleName: cell.style, values: cell.tableValues, in: settings.tableStyles)
        var floatChoices = settings.floatStyles.filter { $0.placement == .figure }.map(\.name)
        if !floatChoices.contains(FloatStyle.tableName) { floatChoices.append(FloatStyle.tableName) }
        if let float = cell.floatStyle, !floatChoices.contains(float) { floatChoices.append(float) }
        let table = InspectorModel.TableInfo(rows: shape.rows, columns: shape.columns, headerRows: shape.headerRows, row: cell.row + 1, column: cell.column + 1,
                                             style: cell.style, styleNames: settings.tableStyles.map(\.name), values: cell.tableValues, resolved: resolved,
                                             floatStyle: cell.floatStyle, floatChoices: floatChoices)
        let info = InspectorModel.CellInfo(row: cell.row + 1, column: cell.column + 1, values: cell.cellValues, tableBackground: resolved.background ?? "",
                                           tableAlignment: resolved.verticalAlignment ?? .top, tablePadding: resolved.padding ?? CellInsets(all: 4),
                                           tableRuleWidth: resolved.ruleWidth ?? 0.5, columnSpan: cell.columnSpan, rowSpan: cell.rowSpan)
        return (table, info)
    }

    func setTableStyle(_ name: String?) {
        changeTable(actionName: "Table Style") { TableEditing.setStyle(name, ofTableAt: $0, in: $1) }
    }

    /// Un cambiamento dell'aspetto della tabella. Uno schema di filetti scelto vale per tutte le celle: i lati detti per
    /// le celle si tolgono.
    func changeTableAppearance(_ change: TableValueChange) {
        var clearing = false
        if case .rules(let scheme) = change, scheme != nil { clearing = true }
        changeTable(actionName: "Table Appearance") { point, store in
            TableEditing.changeTableValues(ofTableAt: point, in: store, clearingCellBorders: clearing) { change.apply(to: &$0) }
        }
    }

    func changeCellAppearance(_ change: CellValueChange) {
        guard let mark = TableEditing.cell(at: selection.range.location, in: store) else { return }
        changeTable(actionName: "Cell Appearance") { point, store in
            TableEditing.changeCellValues(row: mark.row, column: mark.column, ofTableAt: point, in: store) { change.apply(to: &$0) }
        }
    }
}
