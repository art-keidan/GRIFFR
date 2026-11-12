import AppKit
import SwiftUI
import Typesetting

/// L'editor della formula di un campo: la catena a blocchi, come nel compositore. Si parte da un oggetto, si passa a quelli
/// che lo contengono, se ne legge un risultato e lo si scrive nel punto del campo. Ogni scelta lascia solo i passi e i
/// risultati che vengono dopo l'oggetto raggiunto, così la catena resta valida mentre la si cambia.
@MainActor
final class FieldFormulaEditorModel: ObservableObject {
    @Published private(set) var formula: FieldFormula
    /// I ruoli delle sezioni offerti per il passo «sezione contenente»: quelli pronti e quelli del documento.
    let roles: [String]
    /// Il campo che si modifica, o `false` per uno nuovo da inserire.
    let editing: Bool
    /// Il risultato della catena nel punto del campo, nella composizione attuale.
    private let preview: (FieldFormula) -> String
    let previewLabel: String
    /// Chiamata alla chiusura: con la formula per «OK», con `nil` per «Annulla».
    var finish: ((FieldFormula?) -> Void)?

    init(formula: FieldFormula, roles: [String], editing: Bool, previewLabel: String = "Result here",
         preview: @escaping (FieldFormula) -> String) {
        self.formula = formula
        self.roles = roles
        self.editing = editing
        self.previewLabel = previewLabel
        self.preview = preview
    }

    var problem: String? { formula.problem }
    var result: String { preview(formula) }

    /// Gli oggetti raggiunti: dopo l'origine e dopo ogni passo.
    private var subjects: [FieldFormula.Subject] { formula.subjects ?? [formula.origin == .position ? .position : .document] }
    var lastSubject: FieldFormula.Subject { subjects.last ?? .position }

    /// I passi che si possono mettere al posto `index` (dopo l'oggetto raggiunto fin lì).
    func stepChoices(at index: Int) -> [FieldFormula.Step] {
        subjects.indices.contains(index) ? subjects[index].steps : []
    }

    var defaultRole: String { roles.first ?? "chapter" }

    func setOrigin(_ origin: FieldFormula.Origin) {
        var changed = formula
        changed.origin = origin
        commit(changed)
    }

    func addStep(_ step: FieldFormula.Step) {
        var changed = formula
        changed.steps.append(withRole(step, keeping: nil))
        commit(changed)
    }

    func replaceStep(at index: Int, with step: FieldFormula.Step) {
        guard formula.steps.indices.contains(index) else { return }
        var changed = formula
        changed.steps[index] = withRole(step, keeping: formula.steps[index])
        commit(changed)
    }

    func removeStep(at index: Int) {
        guard formula.steps.indices.contains(index) else { return }
        var changed = formula
        changed.steps.remove(at: index)
        commit(changed)
    }

    func setRole(_ role: String, at index: Int) {
        guard formula.steps.indices.contains(index), case .containingSection = formula.steps[index] else { return }
        var changed = formula
        changed.steps[index] = .containingSection(role: role)
        commit(changed)
    }

    func setReading(_ reading: FieldFormula.Reading) {
        var changed = formula
        changed.reading = reading
        commit(changed)
    }

    /// Un passo «sezione contenente» prende il ruolo del passo che sostituisce, o il primo offerto.
    private func withRole(_ step: FieldFormula.Step, keeping old: FieldFormula.Step?) -> FieldFormula.Step {
        guard case .containingSection(let role) = step, role.isEmpty else { return step }
        if case .containingSection(let previous)? = old { return .containingSection(role: previous) }
        return .containingSection(role: defaultRole)
    }

    /// Toglie i passi che non partono più dall'oggetto raggiunto e, se il risultato non c'è più, prende il primo che c'è.
    private func commit(_ changed: FieldFormula) {
        var formula = changed
        var current: FieldFormula.Subject = formula.origin == .position ? .position : .document
        var kept: [FieldFormula.Step] = []
        for step in formula.steps {
            guard current.steps.contains(where: { $0.token == step.token }) else { break }
            kept.append(step)
            current = FieldFormula(origin: formula.origin, steps: kept, reading: formula.reading).lastSubject ?? current
        }
        formula.steps = kept
        if !current.readings.contains(formula.reading), let first = current.readings.first { formula.reading = first }
        self.formula = formula
    }

    func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: FieldFormulaEditorView(model: self).themed())
        let window = NSWindow(contentViewController: controller)
        window.title = editing ? "Field Formula" : "New Field"
        window.setContentSize(controller.view.fittingSize)
        return window
    }
}

struct FieldFormulaEditorView: View {
    @ObservedObject var model: FieldFormulaEditorModel
    @State private var otherRoleIndex: Int?
    @State private var otherRole = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.editing ? "Field Formula" : "New Field").font(.headline)
            Text("The field starts from an object, moves to the objects that contain it, reads a result and writes it here.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ComposerPathEditor(rows: pathRows, layout: .blocks)
                FieldFormulaBlock(number: model.formula.steps.count + 3, symbol: "square.and.pencil", verb: "Write result") {
                    Text("Here").foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            Divider()
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.previewLabel + ":").foregroundStyle(.secondary)
                    Text(model.result.isEmpty ? "(nothing)" : model.result).fontWeight(.medium)
                        .foregroundStyle(model.result.isEmpty ? .secondary : .primary)
                }
                Text(model.formula.chain).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.finish?(nil) }.keyboardShortcut(.cancelAction)
                Button(model.editing ? "OK" : "Insert") { model.finish?(model.formula) }
                    .keyboardShortcut(.defaultAction).disabled(model.problem != nil)
            }
        }
        .padding(20)
        .frame(width: 540)
        .background(Color(nsColor: Theme.window))
    }

    private func stepTitle(_ step: FieldFormula.Step) -> String {
        if case .containingSection = step { return "Containing section" }
        return step.title
    }

    var pathRows: [ComposerPathRow] {
        var rows: [ComposerPathRow] = [.node(ComposerPathNode(
            verb: "Start from", symbol: "scope", title: model.formula.origin.title,
            choices: ComposerPathChoice.choices(FieldFormula.Origin.allCases, title: { $0.title }, select: model.setOrigin)))]
        for (index, step) in model.formula.steps.enumerated() {
            rows.append(.node(ComposerPathNode(
                verb: "Go to", symbol: "arrow.turn.down.right", title: stepTitle(step),
                choices: ComposerPathChoice.choices(model.stepChoices(at: index), title: stepTitle, select: { model.replaceStep(at: index, with: $0) }),
                remove: { model.removeStep(at: index) }, detail: AnyView(stepDetails(step, at: index)))))
        }
        if !model.lastSubject.steps.isEmpty {
            rows.append(.insertion(AnyView(addStep)))
        }
        rows.append(.node(ComposerPathNode(
            verb: "Read", symbol: "text.viewfinder", title: model.formula.reading.title,
            choices: ComposerPathChoice.choices(model.lastSubject.readings, title: { $0.title }, select: model.setReading),
            emptyMessage: model.lastSubject.readings.isEmpty ? "Add a step: a \(model.lastSubject.title) gives no result." : nil)))
        return rows
    }

    private var addStep: some View {
        Menu {
            ForEach(model.stepChoices(at: model.formula.steps.count), id: \.token) { step in
                Button(stepTitle(step)) { model.addStep(step) }
            }
        } label: { Label("Add Step", systemImage: "plus") }
            .menuStyle(.borderlessButton).hoverable().menuIndicator(.hidden).fixedSize().padding(.leading, 10)
    }

    @ViewBuilder private func stepDetails(_ step: FieldFormula.Step, at index: Int) -> some View {
        HStack(spacing: 8) {
            if case .containingSection(let role) = step {
                Text("of role").foregroundStyle(.secondary).fixedSize()
                if otherRoleIndex == index {
                    ComposerValueEditor(input: .text(label: "Role", value: $otherRole, width: 110))
                        .onSubmit { commitOtherRole(at: index) }
                    Button("Use") { commitOtherRole(at: index) }
                } else {
                    Menu {
                        ForEach(model.roles, id: \.self) { candidate in
                            Button(candidate) { model.setRole(candidate, at: index) }
                        }
                        Divider()
                        Button("Other Role…") { otherRole = role; otherRoleIndex = index }
                    } label: { ComposerPill(title: role.isEmpty ? "Choose" : role, placeholder: role.isEmpty) }.fixedSize()
                }
            }
        }
    }

    private func commitOtherRole(at index: Int) {
        let role = otherRole.trimmingCharacters(in: .whitespacesAndNewlines)
        if !role.isEmpty { model.setRole(role, at: index) }
        otherRoleIndex = nil
    }
}

/// Una tappa della catena, condivisa dagli editor di campi e rimandi.
struct FieldFormulaBlock<Content: View>: View {
    let number: Int
    let symbol: String
    let verb: String
    let remove: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(number: Int, symbol: String, verb: String, remove: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.number = number
        self.symbol = symbol
        self.verb = verb
        self.remove = remove
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 14)
            Image(systemName: symbol).foregroundStyle(Color(nsColor: Theme.glyph)).frame(width: 18)
            Text(verb).fontWeight(.medium).frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 6)
            if let remove {
                Button(action: remove) { Image(systemName: "xmark") }
                    .buttonStyle(.hover(.borderless)).accessibilityLabel("Remove step")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: Theme.control))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: Theme.line)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(number): \(verb)")
    }
}
