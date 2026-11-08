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
            if name.isEmpty { return "Every style needs a name." }
            if !seen.insert(name).inserted { return "There are two styles named “\(name)”." }
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
        var name = "New Notes"
        var number = 2
        while rows.contains(where: { $0.style.name == name }) {
            name = "New Notes \(number)"
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
        case .superscript: "Superscript number"
        case .plain: "Normal number"
        case .none: "No reference mark"
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
                    Text(row.style.name.isEmpty ? "(untitled)" : row.style.name).tag(row.id)
                }
                .onMove { model.rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("A new float style")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(model.selectedIndex.map { model.rows[$0].isFootnote } ?? true)
                    .help("Remove the chosen style")
                Spacer()
                if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
            if let id = model.selection, let row = model.rows.first(where: { $0.id == id }) {
                FloatStyleDetailView(model: model, id: id, isFootnote: row.isFootnote, embedded: true)
            } else {
                Text("No style chosen.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .here: "h here"
        case .top: "t top"
        case .bottom: "b bottom"
        case .page: "p page"
        }
    }

    var body: some View {
        let style = model.rows.first { $0.id == id }?.style ?? FloatStyle(name: "")
        Form {
            TextField("Name:", text: field(\.name, "")).disabled(isFootnote)
            if isFootnote {
                Text("The footnote style (⌥⌘F): it always exists, and its name cannot change.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Numbered with:", selection: field(\.listName, nil)) {
                Text("1, 2, 3 (no list)").tag(String?.none)
                ForEach(model.lists, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Reference mark:", selection: field(\.reference, .superscript)) {
                ForEach(FloatStyle.Reference.allCases, id: \.self) { Text(FloatStylesSheetModel.referenceTitle($0)).tag($0) }
            }
            Toggle("Rule above the notes of this series", isOn: field(\.showsRule, true))
                .disabled(style.placement == .outerMargin)
            HStack {
                TextField("Rule length:", text: Binding(
                    get: { style.ruleLength.map { String(format: "%g", $0) } ?? "" },
                    set: { field(\.ruleLength, nil).wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }),
                    prompt: Text("automatic"))
                    .fieldWidth(230, embedded: embedded)
                Text("pt").foregroundStyle(.secondary)
            }
            .disabled(!style.showsRule)
            HStack {
                TextField("Space above:", value: field(\.spaceAbove, 7), format: .number).fieldWidth(160, embedded: embedded)
                TextField("Space below:", value: field(\.spaceBelow, 4), format: .number).fieldWidth(160, embedded: embedded)
                Text("pt").foregroundStyle(.secondary)
            }
            Toggle("A long note can continue on the next page", isOn: field(\.canSplit, true))
                .disabled(style.placement != .pageFoot)
            Picker("Content style:", selection: field(\.contentStyle, nil)) {
                Text("None (alignment of the paragraph that refers to it)").tag(String?.none)
                ForEach(model.paragraphStyles, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Placement:", selection: Binding(
                get: { style.placement },
                set: { placement in
                    field(\.placement, .pageFoot).wrappedValue = placement
                    // Le note di chiusura nascono con il titolo «Note»; quelle a margine senza richiamo e senza filetto.
                    if placement == .documentEnd, style.heading == nil { field(\.heading, nil).wrappedValue = "Notes" }
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
                Text("At the bottom of the referencing page").tag(FloatStyle.Placement.pageFoot)
                Text("At the end of the document (endnotes)").tag(FloatStyle.Placement.documentEnd)
                Text("In the outer margin, beside the line").tag(FloatStyle.Placement.outerMargin)
                Text("Figure: an image with its caption").tag(FloatStyle.Placement.figure)
                Text("At the top of pages (header)").tag(FloatStyle.Placement.pageHead)
                Text("At the bottom of pages (footer)").tag(FloatStyle.Placement.pageBottom)
            }
            .disabled(isFootnote)
            if style.placement.isRunning {
                Picker("For pages:", selection: field(\.pages, .all)) {
                    Text("All").tag(FloatStyle.RunningPages.all)
                    Text("Odd").tag(FloatStyle.RunningPages.odd)
                    Text("Even").tag(FloatStyle.RunningPages.even)
                    Text("Only the first of the section").tag(FloatStyle.RunningPages.first)
                }
                Toggle("Middle of the margin", isOn: Binding(get: { style.edgeDistance == nil },
                                                          set: { centered in field(\.edgeDistance, nil).wrappedValue = centered ? nil : 12 }))
                if let distance = style.edgeDistance {
                    LabeledContent("From the paper edge:") {
                        LengthField(points: CGFloat(distance)) { field(\.edgeDistance, nil).wrappedValue = Double($0) }
                    }
                }
                Text("It applies from where it is anchored (a section title, or the first paragraph) until another of the same style takes its place. The first page of a section that starts on a new page has no header, except one set to “only the first of the section”. The rule sits below the header and above the footer.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .outerMargin {
                Text("On the right on odd pages, on the left on even ones. Overlapping notes stay where they are: on screen a red box marks them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .figure {
                HStack {
                    Text("Can go:")
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
                Toggle("Exactly here, right after the paragraph (H)", isOn: field(\.exactlyHere, false))
                Toggle("Without the per-page limits (!)", isOn: field(\.ignoresLimits, false))
                Picker("Caption:", selection: field(\.caption, .below)) {
                    Text("Below the image").tag(FloatStyle.CaptionPosition.below)
                    Text("Above the image").tag(FloatStyle.CaptionPosition.above)
                    Text("None").tag(FloatStyle.CaptionPosition.none)
                }
                Text("As in LaTeX: h right after the paragraph, t at the top of a page, b at the bottom, p on a page of figures only; the figures of a series keep their order. Limits: at most 2 at the top, 1 at the bottom, 3 per page.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if style.placement == .documentEnd {
                TextField("Title:", text: Binding(get: { style.heading ?? "" }, set: { field(\.heading, nil).wrappedValue = $0.isEmpty ? nil : $0 }),
                          prompt: Text("none"))
                Toggle("Starts on a new page", isOn: field(\.startsOnNewPage, false))
            }
        }
        .definitionForm(embedded: embedded, width: 560)
    }
}
