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
    /// Chiamata alla chiusura: con la formula per «OK», con `nil` per «Annulla».
    var finish: ((FieldFormula?) -> Void)?

    init(formula: FieldFormula, roles: [String], editing: Bool, preview: @escaping (FieldFormula) -> String) {
        self.formula = formula
        self.roles = roles
        self.editing = editing
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
                block(number: 1, symbol: "scope", verb: "Start from") {
                    Menu {
                        ForEach(FieldFormula.Origin.allCases, id: \.self) { origin in
                            Button(origin.title) { model.setOrigin(origin) }
                        }
                    } label: { ComposerPill(title: model.formula.origin.title) }.fixedSize()
                }
                ForEach(Array(model.formula.steps.enumerated()), id: \.offset) { index, step in
                    block(number: index + 2, symbol: "arrow.turn.down.right", verb: "Go to", removable: index) {
                        stepControls(step, at: index)
                    }
                }
                if !model.lastSubject.steps.isEmpty {
                    Menu {
                        ForEach(model.stepChoices(at: model.formula.steps.count), id: \.token) { step in
                            Button(stepTitle(step)) { model.addStep(step) }
                        }
                    } label: { Label("Add Step", systemImage: "plus") }
                        .menuStyle(.borderlessButton).hoverable().menuIndicator(.hidden).fixedSize().padding(.leading, 10)
                }
                block(number: model.formula.steps.count + 2, symbol: "text.viewfinder", verb: "Read") {
                    if model.lastSubject.readings.isEmpty {
                        Text("Add a step: a \(model.lastSubject.title) gives no result.").foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(model.lastSubject.readings, id: \.self) { reading in
                                Button(reading.title) { model.setReading(reading) }
                            }
                        } label: { ComposerPill(title: model.formula.reading.title) }.fixedSize()
                    }
                }
                block(number: model.formula.steps.count + 3, symbol: "square.and.pencil", verb: "Write result") {
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
                    Text("Result here:").foregroundStyle(.secondary)
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

    @ViewBuilder private func stepControls(_ step: FieldFormula.Step, at index: Int) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.stepChoices(at: index), id: \.token) { choice in
                    Button(stepTitle(choice)) { model.replaceStep(at: index, with: choice) }
                }
            } label: { ComposerPill(title: stepTitle(step)) }.fixedSize()
            if case .containingSection(let role) = step {
                Text("of role").foregroundStyle(.secondary).fixedSize()
                if otherRoleIndex == index {
                    TextField("Role", text: $otherRole)
                        .frame(width: 110)
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

    private func block<Content: View>(number: Int, symbol: String, verb: String, removable: Int? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 14)
            Image(systemName: symbol).foregroundStyle(Color(nsColor: Theme.glyph)).frame(width: 18)
            Text(verb).fontWeight(.medium).frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 6)
            if let removable {
                Button { model.removeStep(at: removable) } label: { Image(systemName: "xmark") }
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
