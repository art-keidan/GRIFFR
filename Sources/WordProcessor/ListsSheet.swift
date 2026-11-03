import AppKit
import SwiftUI
import Typesetting

/// Una Lista come la si modifica nella finestra delle Liste. La lista superiore è indicata dalla riga, non dal nome:
/// così rinominare una lista non stacca quelle che ne dipendono.
struct ListRow: Identifiable, Equatable {
    let id = UUID()
    /// Il nome che la Lista aveva quando si è aperta la finestra; `nil` per una lista nuova.
    var original: String?
    var definition: ListDefinition
    var parent: Parent

    enum Parent: Hashable {
        case none, page
        case list(UUID)
        case section(String)
    }
}

/// Lo stato della finestra delle Liste.
@MainActor
final class ListsSheetModel: ObservableObject {
    @Published var rows: [ListRow]
    @Published var selection: ListRow.ID?
    /// La riga della Lista che numera le note; `nil` per i numeri 1, 2, 3 senza una Lista.
    @Published var noteList: ListRow.ID?
    /// La riga della Lista che numera le pagine dall'inizio; `nil` per 1, 2, 3.
    @Published var pageList: ListRow.ID?
    /// I ruoli delle sezioni offerti: quelli pronti, quelli del documento, quelli già usati dalle Liste.
    @Published var documentRoles: [String] = []

    var roles: [String] {
        var result = Typesetting.Section.Role.builtIn
        let used = rows.flatMap { row -> [String] in
            var roles = row.definition.numbersSections.map { [$0] } ?? []
            if case .section(let role) = row.parent { roles.append(role) }
            return roles
        }
        for role in documentRoles + used where !result.contains(role) { result.append(role) }
        return result
    }

    struct Result {
        var lists: [ListDefinition]
        var noteList: String?
        var renames: ListRenames
        var pageNumbering: String?
    }


    init(lists: [ListDefinition], noteList: String?, pageNumbering: String? = nil) {
        var rows = lists.map { ListRow(original: $0.name, definition: $0, parent: .none) }
        for index in rows.indices {
            switch rows[index].definition.parent {
            case .page?: rows[index].parent = .page
            case .list(let name)?: rows[index].parent = rows.first { $0.definition.name == name }.map { .list($0.id) } ?? .none
            case .section(let role)?: rows[index].parent = .section(role)
            case nil: break
            }
        }
        self.rows = rows
        originalNames = lists.map(\.name)
        selection = rows.first?.id
        self.noteList = rows.first { $0.definition.name == noteList }?.id
        self.pageList = rows.first { $0.definition.name == pageNumbering }?.id
    }

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    /// Le definizioni come risultano ora, con le liste superiori scritte per nome.
    var definitions: [ListDefinition] {
        rows.map { row in
            var definition = row.definition
            switch row.parent {
            case .none: definition.parent = nil
            case .page: definition.parent = .page
            case .list(let id): definition.parent = rows.first { $0.id == id }.map { .list($0.definition.name) }
            case .section(let role): definition.parent = .section(role)
            }
            return definition
        }
    }

    func result() -> Result {
        var renames: ListRenames = [:]
        for row in rows { if let original = row.original, original != row.definition.name { renames[original] = row.definition.name } }
        let kept = Set(rows.compactMap(\.original))
        // Una lista tolta, il cui nome è ripreso da un'altra, non va tolta dal testo: le voci passano alla nuova.
        let names = Set(rows.map(\.definition.name))
        for name in Set(originalNames).subtracting(kept) where !names.contains(name) { renames[name] = .some(nil) }
        return Result(lists: definitions, noteList: rows.first { $0.id == noteList }?.definition.name, renames: renames,
                      pageNumbering: rows.first { $0.id == pageList }?.definition.name)
    }

    private var originalNames: [String]

    /// Nella scheda del pannello, dopo che le modifiche sono passate al documento: lo stato attuale diventa quello da
    /// cui si calcolano le rinomine seguenti. Le righe restano le stesse (un campo in cui si sta scrivendo non si perde).
    func markApplied() {
        for index in rows.indices { rows[index].original = rows[index].definition.name }
        originalNames = rows.map(\.definition.name)
    }

    /// Che cosa impedisce di confermare, se qualcosa lo impedisce.
    var problem: String? {
        var seen: Set<String> = []
        for row in rows {
            let name = row.definition.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return "Ogni Lista deve avere un nome." }
            if !seen.insert(name).inserted { return "Ci sono due Liste di nome «\(name)»." }
        }
        return nil
    }

    func add() {
        var name = "Lista nuova"
        var number = 2
        while rows.contains(where: { $0.definition.name == name }) {
            name = "Lista nuova \(number)"
            number += 1
        }
        let row = ListRow(original: nil, definition: ListDefinition(name: name, counter: .decimal, suffix: "."), parent: .none)
        rows.append(row)
        selection = row.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        let id = rows[index].id
        rows.remove(at: index)
        for other in rows.indices where rows[other].parent == .list(id) { rows[other].parent = .none }
        if noteList == id { noteList = nil }
        if pageList == id { pageList = nil }
        selection = rows.indices.contains(index) ? rows[index].id : rows.last?.id
    }

    /// Le righe che dipendono da una riga, direttamente o attraverso altre: non possono farle da superiore.
    func descendants(of id: ListRow.ID) -> Set<ListRow.ID> {
        var result: Set<ListRow.ID> = []
        var frontier: Set<ListRow.ID> = [id]
        while !frontier.isEmpty {
            let next = Set(rows.filter { if case .list(let parent) = $0.parent { frontier.contains(parent) } else { false } }.map(\.id))
            frontier = next.subtracting(result)
            result.formUnion(next)
        }
        return result
    }

    /// I primi segni di una lista, come appariranno.
    func preview(of id: ListRow.ID) -> String {
        guard let row = rows.first(where: { $0.id == id }) else { return "" }
        let marks = ListNumberer.sample(of: row.definition.name, in: definitions, count: 5)
        return marks.joined(separator: "   ") + "   …"
    }

    /// Un collegamento a un campo di una riga, che regge anche se la riga sparisce mentre la vista la mostra ancora.
    func binding<Value>(_ id: ListRow.ID, _ path: WritableKeyPath<ListRow, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.rows.first { $0.id == id }?[keyPath: path] ?? fallback },
            set: { value in
                guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index][keyPath: path] = value
            })
    }

    static func counterTitle(_ counter: ListCounter) -> String {
        switch counter {
        case .decimal: "1, 2, 3"
        case .lowerLetter: "a, b, c"
        case .upperLetter: "A, B, C"
        case .lowerRoman: "i, ii, iii"
        case .upperRoman: "I, II, III"
        case .asterisks: "*, **, ***"
        case .symbols: "*, †, ‡, §, ‖, ¶"
        case .none: "Nessun numero (solo il segno)"
        }
    }

    static func overflowTitle(_ overflow: ListOverflow, series: Bool) -> String {
        switch overflow {
        case .ask: "Chiedilo quando succede"
        case .restart: "Ricomincia dal primo"
        case .double: series ? "Raddoppia i segni (**, ††…)" : "Prosegue oltre"
        case .numbers: "Passa ai numeri"
        }
    }
}

struct ListsSheetView: View {
    @ObservedObject var model: ListsSheetModel

    /// Nella scheda del pannello: in colonna, senza OK e Annulla (le modifiche valgono subito).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.rows) { row in
                    Text(row.definition.name.isEmpty ? "(senza nome)" : row.definition.name).tag(row.id)
                }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("Una Lista nuova")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }.disabled(model.selection == nil).help("Togli la Lista scelta")
                Spacer()
                if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
            Picker("Note numerate con", selection: $model.noteList) {
                Text("1, 2, 3 (nessuna Lista)").tag(ListRow.ID?.none)
                ForEach(model.rows) { row in Text(row.definition.name).tag(Optional(row.id)) }
            }
            Picker("Pagine numerate con", selection: $model.pageList) {
                Text("1, 2, 3 (nessuna Lista)").tag(ListRow.ID?.none)
                ForEach(model.rows) { row in Text(row.definition.name).tag(Optional(row.id)) }
            }
            .help("Dall'inizio del documento; una sezione può farle ripartire con un'altra Lista (ispettore della Sezione)")
            if let id = model.selection, model.rows.contains(where: { $0.id == id }) {
                ListDetailView(model: model, id: id, embedded: true)
            } else {
                Text("Nessuna Lista scelta.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
    }

}

/// I campi di una Lista.
private struct ListDetailView: View {
    @ObservedObject var model: ListsSheetModel
    let id: ListRow.ID
    var embedded = false

    private var row: ListRow? { model.rows.first { $0.id == id } }
    private func field<Value>(_ path: WritableKeyPath<ListDefinition, Value>, _ fallback: Value) -> Binding<Value> {
        let base: WritableKeyPath<ListRow, ListDefinition> = \.definition
        return model.binding(id, base.appending(path: path), fallback: fallback)
    }

    var body: some View {
        let definition = row?.definition ?? ListDefinition(name: "", counter: .decimal)
        let excluded = model.descendants(of: id).union([id])
        Form {
            TextField("Nome:", text: field(\.name, ""))
            Picker("Numero:", selection: field(\.counter, .decimal)) {
                ForEach(ListCounter.allCases, id: \.self) { Text(ListsSheetModel.counterTitle($0)).tag($0) }
            }
            HStack {
                TextField("Prima:", text: field(\.prefix, "")).fieldWidth(130, embedded: embedded)
                TextField("Dopo:", text: field(\.suffix, "")).fieldWidth(110, embedded: embedded)
            }
            HStack {
                TextField("Comincia da:", value: field(\.start, 1), format: .number).fieldWidth(150, embedded: embedded)
                TextField("Ultimo valore:", text: Binding(
                    get: { definition.end.map(String.init) ?? "" },
                    set: { field(\.end, nil).wrappedValue = Int($0.trimmingCharacters(in: .whitespaces)) }),
                    prompt: Text(definition.counter.seriesLength.map { "\($0)" } ?? "nessuno"))
                .fieldWidth(170, embedded: embedded)
            }
            Picker("Riparte:", selection: model.binding(id, \.parent, fallback: .none)) {
                Text("Solo come dice la riga sotto").tag(ListRow.Parent.none)
                Text("A ogni pagina").tag(ListRow.Parent.page)
                ForEach(model.rows.filter { !excluded.contains($0.id) }) { other in
                    Text("A ogni voce di «\(other.definition.name)»").tag(ListRow.Parent.list(other.id))
                }
                ForEach(model.roles, id: \.self) { role in
                    Text("A ogni sezione di ruolo «\(role)»").tag(ListRow.Parent.section(role))
                }
            }
            Picker("Numera le sezioni:", selection: field(\.numbersSections, nil)) {
                Text("Nessuna").tag(String?.none)
                ForEach(model.roles, id: \.self) { role in Text("Di ruolo «\(role)»: il numero davanti al titolo").tag(Optional(role)) }
            }
            Toggle("Prosegue dopo un paragrafo che non ne fa parte", isOn: field(\.continues, false))
            Toggle("Scrive davanti il numero della lista superiore (1.2, 3a)", isOn: field(\.showsParent, false))
                .disabled({ switch row?.parent { case .list?, .section?: false; default: true } }())
            if definition.lastValue != nil {
                Picker("Oltre l'ultimo valore:", selection: field(\.overflow, .ask)) {
                    ForEach(ListOverflow.allCases, id: \.self) {
                        Text(ListsSheetModel.overflowTitle($0, series: definition.counter.seriesLength != nil)).tag($0)
                    }
                }
            }
            LabeledContent("Anteprima:") { Text(model.preview(of: id)).font(.body.monospacedDigit()) }
        }
        .definitionForm(embedded: embedded, width: 590)
    }
}
