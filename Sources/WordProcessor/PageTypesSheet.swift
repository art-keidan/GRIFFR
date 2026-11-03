import AppKit
import SwiftUI
import Typesetting

/// Un tipo di pagina come lo si modifica nella scheda Pagine. Il nome di partenza serve a riconoscere le rinomine.
struct PageTypeRow: Identifiable, Equatable {
    let id = UUID()
    /// Il nome che il tipo aveva quando la scheda si è aperta; `nil` per un tipo nuovo.
    var original: String?
    var type: PageType
}

/// Lo stato della scheda Pagine: i tipi di pagina con un nome (il predefinito si cambia dall'ispettore Pagina e da File ›
/// Formato della pagina).
@MainActor
final class PageTypesSheetModel: ObservableObject {
    @Published var rows: [PageTypeRow]
    @Published var selection: PageTypeRow.ID?
    /// Il tipo predefinito, da cui parte un tipo nuovo.
    let defaultSetup: PageSetup

    struct Result {
        var types: [PageType]
        /// Nome vecchio → nome nuovo (`nil`: tolto).
        var renames: [String: String?]
    }

    init(types: [PageType], defaultSetup: PageSetup) {
        rows = types.map { PageTypeRow(original: $0.name, type: $0) }
        self.defaultSetup = defaultSetup
        originalNames = types.map(\.name)
        selection = rows.first?.id
    }

    private var originalNames: [String]

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    func result() -> Result {
        var renames: [String: String?] = [:]
        for row in rows { if let original = row.original, original != row.type.name { renames[original] = row.type.name } }
        let names = Set(rows.map(\.type.name))
        for name in Set(originalNames).subtracting(rows.compactMap(\.original)) where !names.contains(name) { renames[name] = .some(nil) }
        return Result(types: rows.map(\.type), renames: renames)
    }

    /// Dopo che le modifiche sono passate al documento: lo stato attuale diventa la base delle rinomine seguenti.
    func markApplied() {
        for index in rows.indices { rows[index].original = rows[index].type.name }
        originalNames = rows.map(\.type.name)
    }

    /// Che cosa impedisce di applicare, se qualcosa lo impedisce.
    var problem: String? {
        var seen: Set<String> = []
        for row in rows {
            let name = row.type.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return "Ogni tipo di pagina deve avere un nome." }
            if name == PageType.defaultName { return "«\(PageType.defaultName)» è il nome del tipo predefinito del documento." }
            if name.contains("\n") { return "Il nome di un tipo di pagina sta su una riga." }
            if !seen.insert(name).inserted { return "Ci sono due tipi di pagina di nome «\(name)»." }
        }
        return nil
    }

    private func freeName(_ base: String) -> String {
        var name = base
        var number = 2
        while rows.contains(where: { $0.type.name == name }) {
            name = "\(base) \(number)"
            number += 1
        }
        return name
    }

    func add() {
        let row = PageTypeRow(original: nil, type: PageType(name: freeName("Pagina nuova"), setup: defaultSetup))
        rows.append(row)
        selection = row.id
    }

    func duplicateSelected() {
        guard let index = selectedIndex else { return }
        let row = PageTypeRow(original: nil, type: PageType(name: freeName(rows[index].type.name), setup: rows[index].type.setup))
        rows.insert(row, at: index + 1)
        selection = row.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        rows.remove(at: index)
        selection = rows.indices.contains(index) ? rows[index].id : rows.last?.id
    }

    /// Cambia le misure del tipo scelto, se il risultato è una pagina possibile.
    func changeSelected(_ transform: (inout PageSetup) -> Void) {
        guard let index = selectedIndex else { return }
        var setup = rows[index].type.setup
        transform(&setup)
        if let setup = PageSetupForm.checked(setup) { rows[index].type.setup = setup }
    }

    func rename(_ name: String) {
        guard let index = selectedIndex, rows[index].type.name != name else { return }
        rows[index].type.name = name
    }
}

struct PageTypesSheetView: View {
    @ObservedObject var model: PageTypesSheetModel
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.rows) { row in Text(row.type.name).tag(row.id) }
            }
            .frame(height: 160)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("Un tipo di pagina nuovo, come il predefinito")
                Button { model.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selection == nil).help("Duplica il tipo scelto")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(model.selection == nil).help("Togli il tipo: le sezioni che lo usavano tornano a quello della sezione esterna, o al predefinito")
                Spacer()
            }
            .padding(.horizontal, 10)
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            if let index = model.selectedIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Nome").frame(width: 118, alignment: .leading)
                            TextField("", text: $nameDraft)
                                .focused($nameFocused)
                                .onSubmit { model.rename(nameDraft) }
                                .onChange(of: nameFocused) { _, focused in if !focused { model.rename(nameDraft) } }
                        }
                        PageSetupForm(setup: model.rows[index].type.setup) { transform in model.changeSelected(transform) }
                        Text("Le sezioni scelgono i tipi nell'ispettore della Sezione. Il tipo predefinito, delle pagine senza un tipo, si cambia in File › Formato della pagina.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { nameDraft = model.rows[index].type.name }
                .onChange(of: model.selection) { _, _ in nameDraft = model.selectedIndex.map { model.rows[$0].type.name } ?? "" }
            } else {
                Text("Nessun tipo di pagina: tutte le pagine hanno il formato predefinito. Con + se ne crea uno.")
                    .foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, 8)
    }
}
