import AppKit
import SwiftUI
import Typesetting

/// I comandi sulle righe e le colonne di una tabella (menu Tabella e ispettore).
enum TableCommand: String, CaseIterable {
    case rowAbove, rowBelow, columnLeft, columnRight, removeRow, removeColumn, removeTable

    var title: String {
        switch self {
        case .rowAbove: "Row Above"
        case .rowBelow: "Row Below"
        case .columnLeft: "Column to the Left"
        case .columnRight: "Column to the Right"
        case .removeRow: "Remove Row"
        case .removeColumn: "Remove Column"
        case .removeTable: "Remove Table"
        }
    }

    /// Il nome del passo di «Annulla».
    var actionName: String {
        switch self {
        case .rowAbove, .rowBelow: "Row"
        case .columnLeft, .columnRight: "Column"
        default: title
        }
    }
}

/// Un cambiamento dell'aspetto di uno stile di tabella o di una tabella: `nil` toglie ciò che si era detto (si torna
/// allo stile, o al valore iniziale).
enum TableValueChange: Equatable {
    case rules(TableRuleScheme?)
    case ruleWidth(Double?)
    case padding(CellInsets?)
    case alignment(CellVerticalAlignment?)
    case background(String?)

    func apply(to values: inout TableValues) {
        switch self {
        case .rules(let value): values.rules = value
        case .ruleWidth(let value): values.ruleWidth = value
        case .padding(let value): values.padding = value
        case .alignment(let value): values.verticalAlignment = value
        case .background(let value): values.background = value
        }
    }
}

/// Un lato di una cella.
enum CellSide: String, CaseIterable {
    case top, right, bottom, left

    var title: String {
        switch self {
        case .top: "Above"
        case .right: "Right"
        case .bottom: "Below"
        case .left: "Left"
        }
    }

    var keyPath: WritableKeyPath<CellValues, CellBorder?> {
        switch self {
        case .top: \.top
        case .right: \.right
        case .bottom: \.bottom
        case .left: \.left
        }
    }
}

/// Un cambiamento dell'aspetto proprio di una cella: `nil` torna a quello della tabella.
enum CellValueChange: Equatable {
    case border(CellSide, CellBorder?)
    case background(String?)
    case alignment(CellVerticalAlignment?)
    case padding(CellInsets?)

    func apply(to values: inout CellValues) {
        switch self {
        case .border(let side, let border): values[keyPath: side.keyPath] = border
        case .background(let value): values.background = value
        case .alignment(let value): values.verticalAlignment = value
        case .padding(let value): values.padding = value
        }
    }
}

/// Una riga di modulo: il titolo a sinistra, largo come negli altri moduli dell'ispettore.
private func formLine<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title).frame(width: 118, alignment: .leading)
        content()
    }
}

/// Il colore di un «#rrggbb», e il ritorno.
private func swiftUIColor(_ hex: String) -> Color { Color(nsColor: TextStyling.color(hex: hex) ?? .white) }
private func hexString(_ color: Color) -> String? { TextStyling.hex(of: NSColor(color)) }

/// I quattro margini interni, in punti.
struct InsetsFields: View {
    let insets: CellInsets
    let commit: (CellInsets) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                field("Above", \.top)
                field("Below", \.bottom)
            }
            GridRow {
                field("Left", \.left)
                field("Right", \.right)
            }
        }
    }

    private func field(_ title: String, _ path: WritableKeyPath<CellInsets, Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LengthField(points: CGFloat(insets[keyPath: path]), unit: .points) { value in
                var new = insets
                new[keyPath: path] = Double(value)
                commit(new)
            }
        }
    }
}

/// L'aspetto di uno stile di tabella o di una tabella: schema e spessore dei filetti, margini interni, allineamento,
/// fondo. Mostra i valori risolti; accanto a ciò che è detto qui, un pulsante lo toglie.
struct TableValuesForm: View {
    /// Ciò che è detto qui (lo stile, o le eccezioni della tabella).
    let values: TableValues
    /// Ciò che vale, con quello che viene da sopra.
    let resolved: TableValues
    /// Il suggerimento del pulsante che toglie un valore detto qui.
    let resetHelp: String
    let change: (TableValueChange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formLine("Rules") {
                HStack(spacing: 4) {
                    Picker("", selection: Binding(get: { resolved.rules ?? .grid }, set: { change(.rules($0)) })) {
                        ForEach(TableRuleScheme.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    reset(values.rules != nil) { change(.rules(nil)) }
                }
            }
            formLine("Thickness") {
                HStack(spacing: 4) {
                    LengthField(points: CGFloat(resolved.ruleWidth ?? 0.5), unit: .points) { value in
                        if value > 0 { change(.ruleWidth(Double(value))) } else { NSSound.beep() }
                    }
                    reset(values.ruleWidth != nil) { change(.ruleWidth(nil)) }
                }
            }
            formLine("Inner margins") {
                HStack(alignment: .top, spacing: 4) {
                    InsetsFields(insets: resolved.padding ?? CellInsets(all: 4)) { change(.padding($0)) }
                    reset(values.padding != nil) { change(.padding(nil)) }
                }
            }
            formLine("Alignment") {
                HStack(spacing: 4) {
                    Picker("", selection: Binding(get: { resolved.verticalAlignment ?? .top }, set: { change(.alignment($0)) })) {
                        ForEach(CellVerticalAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    reset(values.verticalAlignment != nil) { change(.alignment(nil)) }
                }
            }
            formLine("Background") {
                HStack(spacing: 6) {
                    let background = resolved.background ?? ""
                    Toggle("", isOn: Binding(get: { !background.isEmpty }, set: { change(.background($0 ? "#eeeeee" : "")) })).labelsHidden()
                    if !background.isEmpty {
                        ColorPicker("", selection: Binding(get: { swiftUIColor(background) },
                                                           set: { if let hex = hexString($0) { change(.background(hex)) } }), supportsOpacity: false)
                            .labelsHidden()
                    }
                    reset(values.background != nil) { change(.background(nil)) }
                }
            }
        }
    }

    @ViewBuilder private func reset(_ shown: Bool, _ action: @escaping () -> Void) -> some View {
        if shown {
            Button(action: action) { Image(systemName: "arrow.uturn.backward.circle") }
                .buttonStyle(.hover(.borderless)).help(resetHelp)
        }
    }
}

/// L'ispettore della Tabella: stile e aspetto, misure, righe d'intestazione, righe e colonne.
struct TableForm: View {
    let info: InspectorModel.TableInfo
    let setHeaderRows: (Int) -> Void
    let setStyle: (String?) -> Void
    let setFloat: (String?) -> Void
    let change: (TableValueChange) -> Void
    let command: (TableCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                formLine("Floating") {
                    Picker("", selection: Binding(get: { info.floatStyle }, set: { setFloat($0) })) {
                        Text("no, it stays in the text").tag(String?.none)
                        ForEach(info.floatChoices, id: \.self) { Text("yes, “\($0)”").tag(Optional($0)) }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("When floating, the table has a numbered caption and goes where its float style says (Floats tab): here, at the top, at the bottom, on a separate page.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            }
            formLine("Size") { Text("\(info.rows) \(info.rows == 1 ? "row" : "rows"), \(info.columns) \(info.columns == 1 ? "column" : "columns")") }
            formLine("Cursor") { Text("row \(info.row), column \(info.column)") }
            formLine("Style") {
                Picker("", selection: Binding(get: { info.style ?? Typesetting.TableStyle.defaultName }, set: { setStyle($0 == Typesetting.TableStyle.defaultName ? nil : $0) })) {
                    ForEach(info.styleNames, id: \.self) { Text($0).tag($0) }
                    if !info.styleNames.contains(info.style ?? Typesetting.TableStyle.defaultName) {
                        Text("\(info.style ?? Typesetting.TableStyle.defaultName) (no longer exists)").tag(info.style ?? Typesetting.TableStyle.defaultName)
                    }
                }
                .labelsHidden().fixedSize()
            }
            TableValuesForm(values: info.values, resolved: info.resolved, resetHelp: "Back to What the Style Says", change: change)
            Text("What you change here applies only to this table. Choosing the rules removes the sides set for single cells.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            VStack(alignment: .leading, spacing: 3) {
                formLine("Header") {
                    Stepper(value: Binding(get: { info.headerRows }, set: { setHeaderRows($0) }), in: 0...info.rows) {
                        Text(info.headerRows == 0 ? "no rows" : info.headerRows == 1 ? "the first row" : "the first \(info.headerRows) rows")
                    }
                    .fixedSize()
                }
                Text("Header rows repeat at the top of every page the table continues on.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            }
            formLine("Rows") {
                HStack(spacing: 6) {
                    Button("Above") { command(.rowAbove) }.help("An empty row above the cursor's")
                    Button("Below") { command(.rowBelow) }.help("An empty row below the cursor's")
                    Button("Remove") { command(.removeRow) }.help("Removes the cursor's row, with its text")
                }
                .controlSize(.small)
            }
            formLine("Columns") {
                HStack(spacing: 6) {
                    Button("Left") { command(.columnLeft) }.help("An empty column to the left of the cursor's")
                    Button("Right") { command(.columnRight) }.help("An empty column to the right of the cursor's")
                    Button("Remove") { command(.removeColumn) }.help("Removes the cursor's column, with its text")
                }
                .controlSize(.small)
            }
            Button("Remove Table") { command(.removeTable) }
                .controlSize(.small)
                .help("Removes the table with all its text (Undo brings it back)")
        }
    }
}

/// L'ispettore della Cella: i quattro lati, il fondo, l'allineamento verticale, i margini interni.
struct CellForm: View {
    let info: InspectorModel.CellInfo
    let change: (CellValueChange) -> Void
    let split: () -> Void

    private enum BorderChoice: Hashable { case table, none, rule }
    private enum BackgroundChoice: Hashable { case table, none, color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            formLine("Cell") { Text("row \(info.row), column \(info.column)") }
            if info.columnSpan > 1 || info.rowSpan > 1 {
                formLine("Merged") {
                    HStack(spacing: 8) {
                        Text("spans \(info.columnSpan) \(info.columnSpan == 1 ? "column" : "columns") and \(info.rowSpan) \(info.rowSpan == 1 ? "row" : "rows")")
                        Button("Split") { split() }.controlSize(.small).help("Back to a single position; the others get empty cells")
                    }
                }
            }
            Text("Sides").font(.headline)
            ForEach(CellSide.allCases, id: \.self) { side in borderLine(side) }
            Text("“From the table”: the side given by the rule pattern. Where two cells touch, a side that is set wins over the pattern, and the thicker over the other.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            formLine("Background") {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(get: { backgroundChoice }, set: { choice in
                        switch choice {
                        case .table: change(.background(nil))
                        case .none: change(.background(""))
                        case .color: change(.background(info.tableBackground.isEmpty ? "#eeeeee" : info.tableBackground))
                        }
                    })) {
                        Text("from the table").tag(BackgroundChoice.table)
                        Text("none").tag(BackgroundChoice.none)
                        Text("a color").tag(BackgroundChoice.color)
                    }
                    .labelsHidden().fixedSize()
                    if let background = info.values.background, !background.isEmpty {
                        ColorPicker("", selection: Binding(get: { swiftUIColor(background) },
                                                           set: { if let hex = hexString($0) { change(.background(hex)) } }), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
            formLine("Alignment") {
                Picker("", selection: Binding(get: { info.values.verticalAlignment }, set: { change(.alignment($0)) })) {
                    Text("from the table (\(info.tableAlignment.title.lowercased()))").tag(CellVerticalAlignment?.none)
                    ForEach(CellVerticalAlignment.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden().fixedSize()
            }
            formLine("Inner margins") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("The cell's own", isOn: Binding(get: { info.values.padding != nil },
                                                               set: { change(.padding($0 ? info.tablePadding : nil)) }))
                    if let padding = info.values.padding {
                        InsetsFields(insets: padding) { change(.padding($0)) }
                    }
                }
            }
        }
    }

    private var backgroundChoice: BackgroundChoice {
        switch info.values.background {
        case nil: .table
        case let value? where value.isEmpty: .none
        default: .color
        }
    }

    private func borderLine(_ side: CellSide) -> some View {
        let border = info.values[keyPath: side.keyPath]
        let choice: BorderChoice = switch border {
        case nil: .table
        case .none?: .none
        case .rule?: .rule
        }
        return formLine(side.title) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { choice }, set: { new in
                    switch new {
                    case .table: change(.border(side, nil))
                    case .none: change(.border(side, CellBorder.none))
                    case .rule: change(.border(side, .rule(info.tableRuleWidth)))
                    }
                })) {
                    Text("from the table").tag(BorderChoice.table)
                    Text("no rule").tag(BorderChoice.none)
                    Text("filetto").tag(BorderChoice.rule)
                }
                .labelsHidden().fixedSize()
                if case .rule(let width)? = border {
                    LengthField(points: CGFloat(width), unit: .points) { value in
                        if value > 0 { change(.border(side, .rule(Double(value)))) } else { NSSound.beep() }
                    }
                }
            }
        }
    }
}

// MARK: - La scheda Tabelle (stili di tabella)

/// Uno stile di tabella come lo si modifica nella scheda. Il nome di partenza serve a riconoscere le rinomine.
struct TableStyleRow: Identifiable, Equatable {
    let id = UUID()
    var original: String?
    var style: Typesetting.TableStyle
}

@MainActor
final class TableStylesSheetModel: ObservableObject {
    @Published var rows: [TableStyleRow]
    @Published var selection: TableStyleRow.ID?
    private var originalNames: [String]

    struct Result {
        var styles: [Typesetting.TableStyle]
        /// Nome vecchio → nome nuovo (`nil`: tolto).
        var renames: [String: String?]
    }

    init(styles: [Typesetting.TableStyle]) {
        rows = styles.map { TableStyleRow(original: $0.name, style: $0) }
        originalNames = styles.map(\.name)
        selection = rows.first?.id
    }

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    func result() -> Result {
        var renames: [String: String?] = [:]
        for row in rows { if let original = row.original, original != row.style.name { renames[original] = row.style.name } }
        let names = Set(rows.map(\.style.name))
        for name in Set(originalNames).subtracting(rows.compactMap(\.original)) where !names.contains(name) { renames[name] = .some(nil) }
        return Result(styles: rows.map(\.style), renames: renames)
    }

    func markApplied() {
        for index in rows.indices { rows[index].original = rows[index].style.name }
        originalNames = rows.map(\.style.name)
    }

    var problem: String? {
        var seen: Set<String> = []
        for row in rows {
            let name = row.style.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return "Every table style needs a name." }
            if name.contains("\n") { return "A style name fits on one line." }
            if !seen.insert(name).inserted { return "There are two table styles named “\(name)”." }
        }
        return nil
    }

    private func freeName(_ base: String) -> String {
        var name = base
        var number = 2
        while rows.contains(where: { $0.style.name == name }) {
            name = "\(base) \(number)"
            number += 1
        }
        return name
    }

    func add() {
        let row = TableStyleRow(original: nil, style: Typesetting.TableStyle(name: freeName("Table Style"), values: TableValues()))
        rows.append(row)
        selection = row.id
    }

    func duplicateSelected() {
        guard let index = selectedIndex else { return }
        let row = TableStyleRow(original: nil, style: Typesetting.TableStyle(name: freeName(rows[index].style.name), values: rows[index].style.values))
        rows.insert(row, at: index + 1)
        selection = row.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        rows.remove(at: index)
        selection = rows.indices.contains(index) ? rows[index].id : rows.last?.id
    }

    func rename(_ name: String) {
        guard let index = selectedIndex, rows[index].style.name != name else { return }
        rows[index].style.name = name
    }

    func changeSelected(_ change: TableValueChange) {
        guard let index = selectedIndex else { return }
        change.apply(to: &rows[index].style.values)
    }
}

struct TableStylesSheetView: View {
    @ObservedObject var model: TableStylesSheetModel
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.rows) { row in Text(row.style.name).tag(row.id) }
            }
            .frame(height: 140)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("A new table style")
                Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selection == nil).help("Duplicate the chosen style")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(model.selection == nil).help("Remove the style: the tables that used it go back to “\(Typesetting.TableStyle.defaultName)”")
                Spacer()
            }
            .padding(.horizontal, 10)
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            if let index = model.selectedIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        formLine("Name") {
                            TextField("", text: $nameDraft)
                                .focused($nameFocused)
                                .onSubmit { model.rename(nameDraft) }
                                .onChange(of: nameFocused) { _, focused in if !focused { model.rename(nameDraft) } }
                        }
                        let style = model.rows[index].style
                        TableValuesForm(values: style.values, resolved: style.values.over(.initial),
                                        resetHelp: "Back to the Initial Value") { model.changeSelected($0) }
                        Text("Tables choose their style in the Table inspector; there they can change something just for themselves. With no style, a table uses “\(Typesetting.TableStyle.defaultName)”.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { nameDraft = model.rows[index].style.name }
                .onChange(of: model.selection) { _, _ in nameDraft = model.selectedIndex.map { model.rows[$0].style.name } ?? "" }
            } else {
                Text("No table styles: tables have the initial look (a grid of rules). Create one with +.")
                    .foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, 8)
    }
}
