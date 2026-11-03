import AppKit
import SwiftUI
import Typesetting

/// I comandi sulle righe e le colonne di una tabella (menu Tabella e ispettore).
enum TableCommand: String, CaseIterable {
    case rowAbove, rowBelow, columnLeft, columnRight, removeRow, removeColumn, removeTable

    var title: String {
        switch self {
        case .rowAbove: "Riga sopra"
        case .rowBelow: "Riga sotto"
        case .columnLeft: "Colonna a sinistra"
        case .columnRight: "Colonna a destra"
        case .removeRow: "Togli la riga"
        case .removeColumn: "Togli la colonna"
        case .removeTable: "Togli la tabella"
        }
    }

    /// Il nome del passo di «Annulla».
    var actionName: String {
        switch self {
        case .rowAbove, .rowBelow: "Riga"
        case .columnLeft, .columnRight: "Colonna"
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
        case .top: "Sopra"
        case .right: "A destra"
        case .bottom: "Sotto"
        case .left: "A sinistra"
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
                field("Sopra", \.top)
                field("Sotto", \.bottom)
            }
            GridRow {
                field("Sinistra", \.left)
                field("Destra", \.right)
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
            formLine("Filetti") {
                HStack(spacing: 4) {
                    Picker("", selection: Binding(get: { resolved.rules ?? .grid }, set: { change(.rules($0)) })) {
                        ForEach(TableRuleScheme.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    reset(values.rules != nil) { change(.rules(nil)) }
                }
            }
            formLine("Spessore") {
                HStack(spacing: 4) {
                    LengthField(points: CGFloat(resolved.ruleWidth ?? 0.5), unit: .points) { value in
                        if value > 0 { change(.ruleWidth(Double(value))) } else { NSSound.beep() }
                    }
                    reset(values.ruleWidth != nil) { change(.ruleWidth(nil)) }
                }
            }
            formLine("Margini interni") {
                HStack(alignment: .top, spacing: 4) {
                    InsetsFields(insets: resolved.padding ?? CellInsets(all: 4)) { change(.padding($0)) }
                    reset(values.padding != nil) { change(.padding(nil)) }
                }
            }
            formLine("Allineamento") {
                HStack(spacing: 4) {
                    Picker("", selection: Binding(get: { resolved.verticalAlignment ?? .top }, set: { change(.alignment($0)) })) {
                        ForEach(CellVerticalAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    reset(values.verticalAlignment != nil) { change(.alignment(nil)) }
                }
            }
            formLine("Fondo") {
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
                .buttonStyle(.borderless).help(resetHelp)
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
                formLine("Flottante") {
                    Picker("", selection: Binding(get: { info.floatStyle }, set: { setFloat($0) })) {
                        Text("no, sta nel testo").tag(String?.none)
                        ForEach(info.floatChoices, id: \.self) { Text("sì, «\($0)»").tag(Optional($0)) }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Flottante, la tabella ha una didascalia numerata e va dove dice il suo stile di flottante (scheda Flottanti): qui, in cima, in fondo, in una pagina a parte.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            }
            formLine("Misure") { Text("\(info.rows) \(info.rows == 1 ? "riga" : "righe"), \(info.columns) \(info.columns == 1 ? "colonna" : "colonne")") }
            formLine("Cursore") { Text("riga \(info.row), colonna \(info.column)") }
            formLine("Stile") {
                Picker("", selection: Binding(get: { info.style ?? Typesetting.TableStyle.defaultName }, set: { setStyle($0 == Typesetting.TableStyle.defaultName ? nil : $0) })) {
                    ForEach(info.styleNames, id: \.self) { Text($0).tag($0) }
                    if !info.styleNames.contains(info.style ?? Typesetting.TableStyle.defaultName) {
                        Text("\(info.style ?? Typesetting.TableStyle.defaultName) (non c'è più)").tag(info.style ?? Typesetting.TableStyle.defaultName)
                    }
                }
                .labelsHidden().fixedSize()
            }
            TableValuesForm(values: info.values, resolved: info.resolved, resetHelp: "Torna a ciò che dice lo stile", change: change)
            Text("Ciò che si cambia qui vale solo per questa tabella. Scegliere i filetti toglie i lati detti per le singole celle.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            VStack(alignment: .leading, spacing: 3) {
                formLine("Intestazione") {
                    Stepper(value: Binding(get: { info.headerRows }, set: { setHeaderRows($0) }), in: 0...info.rows) {
                        Text(info.headerRows == 0 ? "nessuna riga" : info.headerRows == 1 ? "la prima riga" : "le prime \(info.headerRows) righe")
                    }
                    .fixedSize()
                }
                Text("Le righe d'intestazione si ripetono in cima a ogni pagina in cui la tabella continua.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            }
            formLine("Righe") {
                HStack(spacing: 6) {
                    Button("Sopra") { command(.rowAbove) }.help("Una riga vuota sopra quella del cursore")
                    Button("Sotto") { command(.rowBelow) }.help("Una riga vuota sotto quella del cursore")
                    Button("Togli") { command(.removeRow) }.help("Toglie la riga del cursore, con il suo testo")
                }
                .controlSize(.small)
            }
            formLine("Colonne") {
                HStack(spacing: 6) {
                    Button("A sinistra") { command(.columnLeft) }.help("Una colonna vuota a sinistra di quella del cursore")
                    Button("A destra") { command(.columnRight) }.help("Una colonna vuota a destra di quella del cursore")
                    Button("Togli") { command(.removeColumn) }.help("Toglie la colonna del cursore, con il suo testo")
                }
                .controlSize(.small)
            }
            Button("Togli la tabella") { command(.removeTable) }
                .controlSize(.small)
                .help("Toglie la tabella con tutto il suo testo (Annulla la rimette)")
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
            formLine("Cella") { Text("riga \(info.row), colonna \(info.column)") }
            if info.columnSpan > 1 || info.rowSpan > 1 {
                formLine("Unita") {
                    HStack(spacing: 8) {
                        Text("copre \(info.columnSpan) \(info.columnSpan == 1 ? "colonna" : "colonne") e \(info.rowSpan) \(info.rowSpan == 1 ? "riga" : "righe")")
                        Button("Dividi") { split() }.controlSize(.small).help("Torna a coprire una sola posizione; le altre ricevono celle vuote")
                    }
                }
            }
            Text("Lati").font(.headline)
            ForEach(CellSide.allCases, id: \.self) { side in borderLine(side) }
            Text("«Dalla tabella»: il lato che dà lo schema dei filetti. Dove due celle si toccano, un lato detto vince sullo schema, e il più spesso sull'altro.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.leading, 122)
            formLine("Fondo") {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(get: { backgroundChoice }, set: { choice in
                        switch choice {
                        case .table: change(.background(nil))
                        case .none: change(.background(""))
                        case .color: change(.background(info.tableBackground.isEmpty ? "#eeeeee" : info.tableBackground))
                        }
                    })) {
                        Text("dalla tabella").tag(BackgroundChoice.table)
                        Text("nessuno").tag(BackgroundChoice.none)
                        Text("un colore").tag(BackgroundChoice.color)
                    }
                    .labelsHidden().fixedSize()
                    if let background = info.values.background, !background.isEmpty {
                        ColorPicker("", selection: Binding(get: { swiftUIColor(background) },
                                                           set: { if let hex = hexString($0) { change(.background(hex)) } }), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
            formLine("Allineamento") {
                Picker("", selection: Binding(get: { info.values.verticalAlignment }, set: { change(.alignment($0)) })) {
                    Text("dalla tabella (\(info.tableAlignment.title.lowercased()))").tag(CellVerticalAlignment?.none)
                    ForEach(CellVerticalAlignment.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden().fixedSize()
            }
            formLine("Margini interni") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Propri della cella", isOn: Binding(get: { info.values.padding != nil },
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
                    Text("dalla tabella").tag(BorderChoice.table)
                    Text("nessun filetto").tag(BorderChoice.none)
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
            if name.isEmpty { return "Ogni stile di tabella deve avere un nome." }
            if name.contains("\n") { return "Il nome di uno stile sta su una riga." }
            if !seen.insert(name).inserted { return "Ci sono due stili di tabella di nome «\(name)»." }
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
        let row = TableStyleRow(original: nil, style: Typesetting.TableStyle(name: freeName("Stile di tabella"), values: TableValues()))
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
                Button { model.add() } label: { Image(systemName: "plus") }.help("Uno stile di tabella nuovo")
                Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selection == nil).help("Duplica lo stile scelto")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(model.selection == nil).help("Togli lo stile: le tabelle che lo usavano tornano a «\(Typesetting.TableStyle.defaultName)»")
                Spacer()
            }
            .padding(.horizontal, 10)
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            if let index = model.selectedIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        formLine("Nome") {
                            TextField("", text: $nameDraft)
                                .focused($nameFocused)
                                .onSubmit { model.rename(nameDraft) }
                                .onChange(of: nameFocused) { _, focused in if !focused { model.rename(nameDraft) } }
                        }
                        let style = model.rows[index].style
                        TableValuesForm(values: style.values, resolved: style.values.over(.initial),
                                        resetHelp: "Torna al valore iniziale") { model.changeSelected($0) }
                        Text("Le tabelle scelgono lo stile nell'ispettore della Tabella; lì possono cambiare qualcosa solo per sé. Senza stile, una tabella usa «\(Typesetting.TableStyle.defaultName)».")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { nameDraft = model.rows[index].style.name }
                .onChange(of: model.selection) { _, _ in nameDraft = model.selectedIndex.map { model.rows[$0].style.name } ?? "" }
            } else {
                Text("Nessuno stile di tabella: le tabelle hanno l'aspetto iniziale (griglia di filetti). Con + se ne crea uno.")
                    .foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, 8)
    }
}
