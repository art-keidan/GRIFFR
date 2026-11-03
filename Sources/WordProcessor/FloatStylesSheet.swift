import AppKit
import SwiftUI
import Typesetting

/// Uno stile di flottante come lo si modifica nella finestra degli stili di flottante.
struct FloatStyleRow: Identifiable, Equatable {
    let id = UUID()
    /// Il nome che lo stile aveva quando si è aperta la finestra; `nil` per uno stile nuovo.
    var original: String?
    var style: FloatStyle

    /// Lo stile delle note a piè di pagina: c'è sempre, e il suo nome non cambia.
    var isFootnote: Bool { original == FloatStyle.footnoteName }
}

/// Lo stato della finestra degli stili di flottante.
@MainActor
final class FloatStylesSheetModel: ObservableObject {
    @Published var rows: [FloatStyleRow]
    @Published var selection: FloatStyleRow.ID?
    /// Le Liste e gli stili di paragrafo del documento, da proporre.
    let lists: [String]
    let paragraphStyles: [String]

    struct Result {
        var floatStyles: [FloatStyle]
        /// Il nome nuovo di ogni stile rinominato, `nil` per quelli tolti.
        var renames: [String: String?]
    }


    init(styles: [FloatStyle], lists: [String], paragraphStyles: [String]) {
        let rows = styles.map { FloatStyleRow(original: $0.name, style: $0) }
        self.rows = rows
        self.lists = lists
        self.paragraphStyles = paragraphStyles
        originalNames = styles.map(\.name)
        selection = rows.first?.id
    }

    private var originalNames: [String]

    /// Nella scheda del pannello, dopo che le modifiche sono passate al documento: lo stato attuale diventa quello da
    /// cui si calcolano le rinomine seguenti. Le righe restano le stesse (un campo in cui si sta scrivendo non si perde).
    func markApplied() {
        for index in rows.indices where !rows[index].isFootnote { rows[index].original = rows[index].style.name }
        originalNames = rows.map(\.style.name)
    }

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    /// Che cosa impedisce di confermare, se qualcosa lo impedisce.
    var problem: String? {
        var seen: Set<String> = []
        for row in rows {
            let name = row.style.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return "Ogni stile deve avere un nome." }
            if !seen.insert(name).inserted { return "Ci sono due stili di nome «\(name)»." }
        }
        return nil
    }

    func result() -> Result {
        var renames: [String: String?] = [:]
        for row in rows { if let original = row.original, original != row.style.name { renames[original] = row.style.name } }
        let names = Set(rows.map(\.style.name))
        for name in Set(originalNames).subtracting(rows.compactMap(\.original)) where !names.contains(name) { renames[name] = .some(nil) }
        return Result(floatStyles: rows.map(\.style), renames: renames)
    }

    func add() {
        var name = "Note nuove"
        var number = 2
        while rows.contains(where: { $0.style.name == name }) {
            name = "Note nuove \(number)"
            number += 1
        }
        let row = FloatStyleRow(original: nil, style: FloatStyle(name: name))
        rows.append(row)
        selection = row.id
    }

    func removeSelected() {
        guard let index = selectedIndex, !rows[index].isFootnote else { return }
        rows.remove(at: index)
        selection = rows.indices.contains(index) ? rows[index].id : rows.last?.id
    }

    /// Un collegamento a un campo di una riga, che regge anche se la riga sparisce mentre la vista la mostra ancora.
    func binding<Value>(_ id: FloatStyleRow.ID, _ path: WritableKeyPath<FloatStyle, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.rows.first { $0.id == id }?.style[keyPath: path] ?? fallback },
            set: { value in
                guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index].style[keyPath: path] = value
            })
    }

    static func referenceTitle(_ reference: FloatStyle.Reference) -> String {
        switch reference {
        case .superscript: "Numero in apice"
        case .plain: "Numero normale"
        case .none: "Nessun richiamo"
        }
    }
}

struct FloatStylesSheetView: View {
    @ObservedObject var model: FloatStylesSheetModel

    /// Nella scheda del pannello: in colonna, senza OK e Annulla (le modifiche valgono subito).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.rows) { row in
                    Text(row.style.name.isEmpty ? "(senza nome)" : row.style.name).tag(row.id)
                }
                .onMove { model.rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("Uno stile di flottante nuovo")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(model.selectedIndex.map { model.rows[$0].isFootnote } ?? true)
                    .help("Togli lo stile scelto")
                Spacer()
                if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
            if let id = model.selection, let row = model.rows.first(where: { $0.id == id }) {
                FloatStyleDetailView(model: model, id: id, isFootnote: row.isFootnote, embedded: true)
            } else {
                Text("Nessuno stile scelto.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
    }

}

/// I campi di uno stile di flottante.
private struct FloatStyleDetailView: View {
    @ObservedObject var model: FloatStylesSheetModel
    let id: FloatStyleRow.ID
    let isFootnote: Bool
    var embedded = false

    private func field<Value>(_ path: WritableKeyPath<FloatStyle, Value>, _ fallback: Value) -> Binding<Value> {
        model.binding(id, path, fallback: fallback)
    }

    static func positionTitle(_ position: FloatStyle.FigurePosition) -> String {
        switch position {
        case .here: "h qui"
        case .top: "t in cima"
        case .bottom: "b in fondo"
        case .page: "p pagina"
        }
    }

    var body: some View {
        let style = model.rows.first { $0.id == id }?.style ?? FloatStyle(name: "")
        Form {
            TextField("Nome:", text: field(\.name, "")).disabled(isFootnote)
            if isFootnote {
                Text("Lo stile delle note a piè di pagina (⌥⌘F): c'è sempre, e il nome non si cambia.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Si numera con:", selection: field(\.listName, nil)) {
                Text("1, 2, 3 (nessuna Lista)").tag(String?.none)
                ForEach(model.lists, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Richiamo:", selection: field(\.reference, .superscript)) {
                ForEach(FloatStyle.Reference.allCases, id: \.self) { Text(FloatStylesSheetModel.referenceTitle($0)).tag($0) }
            }
            Toggle("Filetto sopra le note di questa serie", isOn: field(\.showsRule, true))
                .disabled(style.placement == .outerMargin)
            HStack {
                TextField("Lunghezza del filetto:", text: Binding(
                    get: { style.ruleLength.map { String(format: "%g", $0) } ?? "" },
                    set: { field(\.ruleLength, nil).wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }),
                    prompt: Text("automatica"))
                    .fieldWidth(230, embedded: embedded)
                Text("pt").foregroundStyle(.secondary)
            }
            .disabled(!style.showsRule)
            HStack {
                TextField("Spazio sopra:", value: field(\.spaceAbove, 7), format: .number).fieldWidth(160, embedded: embedded)
                TextField("Spazio sotto:", value: field(\.spaceBelow, 4), format: .number).fieldWidth(160, embedded: embedded)
                Text("pt").foregroundStyle(.secondary)
            }
            Toggle("Una nota lunga può continuare nella pagina dopo", isOn: field(\.canSplit, true))
                .disabled(style.placement != .pageFoot)
            Picker("Stile del contenuto:", selection: field(\.contentStyle, nil)) {
                Text("Nessuno (allineamento del paragrafo che la richiama)").tag(String?.none)
                ForEach(model.paragraphStyles, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Dove va:", selection: Binding(
                get: { style.placement },
                set: { placement in
                    field(\.placement, .pageFoot).wrappedValue = placement
                    // Le note di chiusura nascono con il titolo «Note»; quelle a margine senza richiamo e senza filetto.
                    if placement == .documentEnd, style.heading == nil { field(\.heading, nil).wrappedValue = "Note" }
                    if placement == .figure {
                        field(\.reference, .superscript).wrappedValue = .none
                        field(\.showsRule, true).wrappedValue = false
                    }
                    if placement == .outerMargin || placement.isRunning {
                        field(\.reference, .superscript).wrappedValue = .none
                        field(\.showsRule, true).wrappedValue = false
                    }
                    if placement.isRunning { field(\.canSplit, true).wrappedValue = false }
                })) {
                Text("In fondo alla pagina del richiamo").tag(FloatStyle.Placement.pageFoot)
                Text("Alla fine del documento (note di chiusura)").tag(FloatStyle.Placement.documentEnd)
                Text("Nel margine esterno, accanto alla riga").tag(FloatStyle.Placement.outerMargin)
                Text("Figura: un'immagine con la sua didascalia").tag(FloatStyle.Placement.figure)
                Text("In testa alle pagine (intestazione)").tag(FloatStyle.Placement.pageHead)
                Text("In fondo alle pagine (piè di pagina)").tag(FloatStyle.Placement.pageBottom)
            }
            .disabled(isFootnote)
            if style.placement.isRunning {
                Picker("Per le pagine:", selection: field(\.pages, .all)) {
                    Text("Tutte").tag(FloatStyle.RunningPages.all)
                    Text("Dispari").tag(FloatStyle.RunningPages.odd)
                    Text("Pari").tag(FloatStyle.RunningPages.even)
                    Text("Solo la prima della sezione").tag(FloatStyle.RunningPages.first)
                }
                Toggle("A metà del margine", isOn: Binding(get: { style.edgeDistance == nil },
                                                          set: { centered in field(\.edgeDistance, nil).wrappedValue = centered ? nil : 12 }))
                if let distance = style.edgeDistance {
                    LabeledContent("Dal bordo del foglio:") {
                        LengthField(points: CGFloat(distance)) { field(\.edgeDistance, nil).wrappedValue = Double($0) }
                    }
                }
                Text("Vale da dove è ancorato (il titolo di una sezione, o il primo paragrafo) finché un altro dello stesso stile non prende il suo posto. La prima pagina di una sezione che comincia su una pagina nuova non ha intestazione, salvo quella «solo la prima della sezione». Il filetto sta sotto l'intestazione e sopra il piè di pagina.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .outerMargin {
                Text("A destra nelle pagine dispari, a sinistra nelle pari. Le note che si sovrappongono restano dove sono: sullo schermo le segnala un riquadro rosso.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .figure {
                HStack {
                    Text("Può andare:")
                    ForEach(FloatStyle.FigurePosition.allCases, id: \.self) { position in
                        Toggle(Self.positionTitle(position), isOn: Binding(
                            get: { style.positions.contains(position) },
                            set: { on in
                                var positions = style.positions.filter { $0 != position }
                                if on { positions.append(position) }
                                // L'ordine di preferenza è quello di LaTeX: h, t, b, p.
                                let ordered = FloatStyle.FigurePosition.allCases.filter(positions.contains)
                                if !ordered.isEmpty { field(\.positions, []).wrappedValue = ordered }
                            }))
                    }
                }
                .disabled(style.exactlyHere)
                Toggle("Esattamente qui, subito dopo il paragrafo (H)", isOn: field(\.exactlyHere, false))
                Toggle("Senza i limiti per pagina (!)", isOn: field(\.ignoresLimits, false))
                Picker("Didascalia:", selection: field(\.caption, .below)) {
                    Text("Sotto l'immagine").tag(FloatStyle.CaptionPosition.below)
                    Text("Sopra l'immagine").tag(FloatStyle.CaptionPosition.above)
                    Text("Nessuna").tag(FloatStyle.CaptionPosition.none)
                }
                Text("Come in LaTeX: h subito dopo il paragrafo, t in cima a una pagina, b in fondo, p su una pagina di sole figure; le figure di una serie restano nel loro ordine. Limiti: al più 2 in cima, 1 in fondo, 3 per pagina.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .documentEnd {
                TextField("Titolo:", text: Binding(get: { style.heading ?? "" }, set: { field(\.heading, nil).wrappedValue = $0.isEmpty ? nil : $0 }),
                          prompt: Text("nessuno"))
                Toggle("Comincia su una pagina nuova", isOn: field(\.startsOnNewPage, false))
            }
        }
        .definitionForm(embedded: embedded, width: 560)
    }
}
