import AppKit
import SwiftUI
import Typesetting
import UniformTypeIdentifiers

/// Il compositore di stili ad azioni: la libreria a sinistra, la sequenza dello stile al centro, l'anteprima a destra.
/// Ogni blocco è una formula o una variabile dello stile nella bozza della bacheca; l'ordine mostrato è quello in cui il
/// motore valuta (per fase), e uno stile resta una definizione che si aggiorna da sé, non uno script da eseguire.
struct ActionComposer: View {
    @ObservedObject var model: ComposerBoardModel
    @State private var expanded: Set<UUID> = []
    @State private var selectedAction: UUID?
    @State private var search = ""

    var body: some View {
        HSplitView {
            ComposerLibrary(model: model, search: $search, selectedAction: selectedAction) { id in
                expanded.insert(id)
                selectedAction = id
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            ScrollView {
                if let style = model.currentStyle {
                    ComposerFlow(model: model, style: style, expanded: $expanded, selectedAction: $selectedAction)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No style").foregroundStyle(.secondary).padding(24)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
            .background(Color(nsColor: Theme.desk))
            ComposerPreview(model: model)
                .frame(minWidth: 220, idealWidth: 290, maxWidth: 420)
        }
        .onAppear { if let name = model.selectedStyle { model.selectStyle(name) } }
    }
}

// MARK: - Libreria

private struct ComposerLibrary: View {
    @ObservedObject var model: ComposerBoardModel
    @Binding var search: String
    let selectedAction: UUID?
    let added: (UUID) -> Void

    private func matches(_ title: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || title.localizedCaseInsensitiveContains(query)
    }

    private func properties(directive: Bool) -> [StyleProperty] {
        guard let style = model.currentStyle else { return [] }
        return StyleProperty.allCases.filter { property in
            property.isDirective == directive && matches(property.title) &&
                (try? StyleFormula(operation: StylePropertyOperation(.set, property, property.initialArgument),
                                   when: property == .pageStartSpacing ? StyleCondition(position: .firstOnPage) : StyleCondition())
                    .validate(for: style.target)) != nil
        }
    }

    private var paragraphStyles: [String] { model.sheet.styles.filter { $0.target == .paragraph }.map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(model.sheet.styles, id: \.name) { style in
                    Button(style.name) { model.selectStyle(style.name) }
                }
            } label: { ComposerPill(title: model.selectedStyle ?? "Choose a style") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("Style")
            TextField("Search actions", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Con la ricerca, un gruppo senza voci non compare.
                    let formatting = properties(directive: false), behaviours = properties(directive: true)
                    if !formatting.isEmpty { group("Formatting") }
                    ForEach(formatting, id: \.self) { property in
                        item(property.title, symbol: property.symbol) { if let id = model.addAction(property) { added(id) } }
                    }
                    if !behaviours.isEmpty { group("Behaviors") }
                    ForEach(behaviours, id: \.self) { property in
                        item(property.title, symbol: property.symbol) { if let id = model.addAction(property) { added(id) } }
                    }
                    conditions
                    headingItems
                    calculations
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: Theme.side))
    }

    @ViewBuilder private var conditions: some View {
        let titles = ["First on page", "Sequence start", "Always"]
        if titles.contains(where: matches) || matches("After style") {
            group("Conditions of the chosen action")
            if matches("First on page") { conditionItem("First on page", .firstOnPage) }
            if matches("Sequence start") { conditionItem("Sequence start", .sequenceStart) }
            if matches("After style") {
                Menu {
                    ForEach(paragraphStyles, id: \.self) { name in
                        Button(name) { if let id = selectedAction { model.applyCondition(.firstAfter(name), to: id) } }
                    }
                } label: { Label("After Style…", systemImage: "arrow.turn.down.right") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(selectedAction == nil).padding(.vertical, 3)
            }
            if matches("Always") { conditionItem("Always", .any) }
        }
    }

    @ViewBuilder private var headingItems: some View {
        let mm = 72 / 25.4
        if model.currentStyle?.target == .paragraph, matches("Heading") || matches("Rule") || matches("Label") || matches("Number") || matches("Space") {
            group("Heading")
            if matches("Heading") { item("Ready-made heading", symbol: "rectangle.split.1x2") { model.useStandardHeading() } }
            if matches("Label") { item("Label", symbol: "textformat") { model.addHeadingPart(.label(text: "Chapter", style: nil, alignment: .left, minHeight: nil)) } }
            if matches("Number") { item("Section number", symbol: "number") { model.addHeadingPart(.number(prefix: "", style: nil, alignment: .left, minHeight: nil)) } }
            if matches("Number") { item("Number beside title", symbol: "text.insert") { model.addHeadingPart(.numberBeside(prefix: "", style: nil, side: .left, gap: 4 * mm)) } }
            if matches("Rule") { item("Rule", symbol: "minus") { model.addHeadingPart(.rule(thickness: 0.5 * mm, length: nil, alignment: .left)) } }
            if matches("Space") { item("Space", symbol: "arrow.up.and.down") { model.addHeadingPart(.space(3 * mm)) } }
        }
    }

    @ViewBuilder private var calculations: some View {
        if matches("Named value") || matches("Sum") {
            group("Calculations")
            if matches("Named value") {
                item("Named value", symbol: "number") {
                    _ = model.addVariable(named: "Value", expression: .constant(.length(12)))
                }
            }
            if matches("Sum") {
                item("Sum of two values", symbol: "plus.forwardslash.minus") {
                    _ = model.addVariable(named: "Sum", expression: .add(.constant(.length(12)), .constant(.length(6))))
                }
            }
        }
        let formulas = model.sheet.reusableFormulas.filter { matches($0.name) }
        if !formulas.isEmpty || search.trimmingCharacters(in: .whitespaces).isEmpty { group("Document formulas") }
        ForEach(formulas) { definition in
            item(definition.name, symbol: "function") { _ = model.addVariable(calling: definition) }
        }
        Button { model.section = .reusable } label: { Label("Manage Formulas…", systemImage: "slider.horizontal.3") }
            .buttonStyle(.borderless).padding(.vertical, 4)
    }

    private func group(_ title: String) -> some View {
        Text(Theme.smallCapsTitle(title, color: Theme.secondary).string)
            .font(Font(Theme.zoneFont)).foregroundStyle(Color(nsColor: Theme.secondary))
            .padding(.top, 12).padding(.bottom, 2)
    }

    private func item(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(Color(nsColor: Theme.glyph))
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.secondary))
            }.contentShape(Rectangle()).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add " + title)
    }

    private func conditionItem(_ title: String, _ position: TextRule.Position) -> some View {
        Button { if let id = selectedAction { model.applyCondition(position, to: id) } } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease").frame(width: 16).foregroundStyle(Color(nsColor: Theme.glyph))
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
            }.contentShape(Rectangle()).padding(.vertical, 3)
        }
        .buttonStyle(.plain).disabled(selectedAction == nil)
        .accessibilityLabel("Condition " + title + " for the chosen action")
    }
}

// MARK: - Flusso

private struct ComposerFlow: View {
    @ObservedObject var model: ComposerBoardModel
    let style: NamedStyle
    @Binding var expanded: Set<UUID>
    @Binding var selectedAction: UUID?
    /// The action being dragged: it shows faded and takes the place of the action it passes over, within its phase.
    @State private var dragging: UUID?

    private var objectTitle: String {
        switch style.target {
        case .paragraph: "This paragraph"
        case .word: "This word"
        case .character: "These characters"
        }
    }

    var body: some View {
        let ordered = model.orderedActions(style)
        let states = (try? model.formulaStates(style)) ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(style.name).font(.title3.weight(.semibold))
                Spacer()
                Text("Based on").foregroundStyle(.secondary)
                Menu {
                    Button("None") { setParent(nil) }
                    ForEach(model.sheet.possibleParents(of: style.name), id: \.self) { name in Button(name) { setParent(name) } }
                } label: { ComposerPill(title: style.basedOn ?? "Document") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            HStack {
                Image(systemName: style.target == .paragraph ? "paragraphsign" : "textformat")
                Text(objectTitle)
                Spacer()
                Text("Starting object").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
            if let heading = style.heading {
                caption("Heading")
                HeadingBlock(model: model, heading: heading, expanded: binding(for: headingID))
            }
            if !style.variables.isEmpty {
                caption("Variables")
                ForEach(style.variables) { variable in
                    VariableBlock(model: model, variable: variable, expanded: binding(for: variable.id))
                }
            }
            ForEach(Array(phases(ordered).enumerated()), id: \.offset) { _, phase in
                caption(ComposerBoard(model: model).phaseTitle(phase))
                ForEach(ordered.filter { $0.formula.phase == phase }, id: \.formula.id) { entry in
                    ActionBlock(model: model, formula: entry.formula, target: style.target,
                                number: (ordered.firstIndex { $0.formula.id == entry.formula.id } ?? 0) + 1,
                                state: states.last { $0.id == entry.formula.id },
                                expanded: binding(for: entry.formula.id),
                                selected: Binding(get: { selectedAction == entry.formula.id }, set: { if $0 { selectedAction = entry.formula.id } }))
                        .opacity(dragging == entry.formula.id ? 0.4 : 1)
                        .onDrag {
                            dragging = entry.formula.id
                            return NSItemProvider(object: entry.formula.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ActionDrop(model: model, target: entry.formula.id, dragging: $dragging))
                }
            }
            if ordered.isEmpty && style.variables.isEmpty {
                Text("Add an action from the library.").foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ComposerBoard(model: model).compatibleProperties(style)
        }
    }

    /// L'identità con cui il blocco della testata ricorda se è aperto.
    private let headingID = UUID(uuidString: "00000000-0000-0000-0000-00000000AE57")!

    private func phases(_ ordered: [(index: Int, formula: StyleFormula)]) -> [StyleFormulaPhase] {
        var result: [StyleFormulaPhase] = []
        for entry in ordered where !result.contains(entry.formula.phase) { result.append(entry.formula.phase) }
        return result
    }

    private func caption(_ title: String) -> some View {
        Text(Theme.smallCapsTitle(title, color: Theme.secondary).string)
            .font(Font(Theme.zoneFont)).foregroundStyle(Color(nsColor: Theme.secondary)).padding(.top, 6)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) }, set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }

    private func setParent(_ parent: String?) {
        guard let i = model.sheet.styles.firstIndex(where: { $0.name == style.name }) else { return }
        model.sheet.styles[i].basedOn = parent
    }
}

/// Dragging an action over another of the same phase moves it there at once; across phases the drop is refused.
private struct ActionDrop: DropDelegate {
    let model: ComposerBoardModel
    let target: UUID
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return dragging == target || model.canMoveAction(dragging, to: target)
    }
    func dropEntered(info: DropInfo) {
        guard let dragging, model.canMoveAction(dragging, to: target) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { model.moveAction(dragging, to: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Dragging a heading part over another moves it there.
private struct HeadingPartDrop: DropDelegate {
    let model: ComposerBoardModel
    let target: Int
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { model.moveHeadingPart(from: from, to: target) }
        dragging = target
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// La superficie di un blocco: una sola per azione, con la testata e, aperta, il corpo.
private struct BlockSurface<Header: View, Content: View>: View {
    let selected: Bool
    let open: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header().padding(.horizontal, 10).padding(.vertical, 7)
            if open {
                Divider()
                content().padding(10)
            }
        }
        .background(Color(nsColor: Theme.control))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: selected ? Theme.accent : Theme.line)))
    }
}

private struct ActionBlock: View {
    @ObservedObject var model: ComposerBoardModel
    let formula: StyleFormula
    let target: StyleTarget
    let number: Int
    let state: StyleFormulaTrace?
    @Binding var expanded: Bool
    @Binding var selected: Bool

    private var operation: StylePropertyOperation { formula.operation }
    private var variables: [StyleVariable] { model.currentStyle?.variables ?? [] }

    private var valueTitle: String {
        if let binding = formula.binding { return binding.summary(in: model.sheet.reusableFormulas, variables: variables) }
        return FormulaArgumentPill(operation: operation, target: target) { _ in }.titleText
    }

    private var summary: String {
        var parts = ["to " + valueTitle]
        if !formula.when.isAlways { parts.append("if " + formula.when.summary.lowercased()) }
        if formula.target != .paragraph { parts.append("on " + FormulaQualifiers.title(of: formula.target, selections: model.sheet.selections).lowercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        BlockSurface(selected: selected, open: expanded) {
            HStack(spacing: 8) {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 14)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(.borderless).accessibilityLabel(expanded ? "Collapse action" : "Expand action")
                Image(systemName: operation.property.symbol).foregroundStyle(Color(nsColor: Theme.glyph))
                Text(operation.predicate.title + " " + operation.property.title.lowercased()).fontWeight(.medium).lineLimit(1)
                    .layoutPriority(1)
                if !expanded { Text(summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
                Spacer(minLength: 6)
                Button { model.removeStyleFormula(formula.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove action")
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = true }
            // Without arrows: the action is dragged; from the keyboard ⌥⌘↑ and ⌥⌘↓ move the chosen one within its phase.
            .background {
                if selected {
                    Button("") { model.moveStyleFormula(formula.id, by: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                    Button("") { model.moveStyleFormula(formula.id, by: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if operation.property.predicates.count > 1 {
                        Menu {
                            ForEach(operation.property.predicates, id: \.self) { predicate in
                                Button(predicate.title) { model.updateFormula(formula.id, operation: StylePropertyOperation(predicate, operation.property, operation.argument)) }
                            }
                        } label: { ComposerPill(title: operation.predicate.title) }.fixedSize()
                    }
                    Menu {
                        ForEach(StyleProperty.allCases.filter { property in
                            (try? StyleFormula(operation: StylePropertyOperation(.set, property, property.initialArgument),
                                               when: property == .pageStartSpacing ? StyleCondition(position: .firstOnPage) : StyleCondition())
                                .validate(for: target)) != nil && property.phaseFamily == operation.property.phaseFamily
                        }, id: \.self) { property in
                            Button(property.title) {
                                let predicate = property.predicates.contains(operation.predicate) ? operation.predicate : .set
                                model.updateFormula(formula.id, operation: StylePropertyOperation(predicate, property, property.initialArgument))
                            }
                        }
                    } label: { ComposerPill(title: operation.property.title) }.fixedSize()
                }
                // Il valore su una riga sua: un calcolo con argomenti può essere lungo.
                HStack(spacing: 8) {
                    Text("to").foregroundStyle(.secondary)
                    valueControl
                }
                if target == .paragraph {
                    FormulaQualifiers(condition: Binding(get: { formula.when }, set: { model.updateQualifiers(formula.id, when: $0) }),
                                      target: Binding(get: { formula.target }, set: { model.updateQualifiers(formula.id, target: $0) }),
                                      operation: operation, styleNames: model.sheet.styles.filter { $0.target == .paragraph }.map(\.name),
                                      selections: model.sheet.selections)
                }
                HStack {
                    if !formula.when.isAlways {
                        Text(formula.when.holds(in: model.previewContext, facts: model.previewFacts) ? "Condition met on the sample" : "Condition not met on the sample")
                    }
                    Spacer()
                    if let state {
                        let board = ComposerBoard(model: model)
                        Text(board.summary(state.input, property: operation.property) + " → " + board.summary(state.output, property: operation.property))
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action \(number): " + operation.predicate.title + " " + operation.property.title)
        .accessibilityAction(named: "Move up") { model.moveStyleFormula(formula.id, by: -1) }
        .accessibilityAction(named: "Move down") { model.moveStyleFormula(formula.id, by: 1) }
    }

    @ViewBuilder private var valueControl: some View {
        let compatible = model.compatibleVariables(for: formula)
        if let binding = formula.binding {
            Menu {
                Button("Fixed Value") { model.bind(formula.id, to: nil) }
                if !compatible.isEmpty { Divider() }
                ForEach(compatible) { variable in Button(variable.name) { model.bind(formula.id, to: variable.id) } }
                if case .variable = binding {} else {
                    Divider()
                    Button("Name This Calculation") { model.extractVariable(from: formula.id) }
                }
            } label: { VariablePill(title: valueTitle) }
        } else {
            FormulaArgumentPill(operation: operation, target: target, styleNames: model.sheet.styles.filter {
                operation.property == .nextStyle ? $0.target == .paragraph : (($0.target != .paragraph || formula.target == .paragraph) && !$0.formulas.contains(where: \.isRuntimeRule))
            }.map(\.name)) { value in
                model.updateFormula(formula.id, operation: StylePropertyOperation(operation.predicate, operation.property, value))
            }.fixedSize()
            if formula.bindingType != nil {
                Menu {
                    ForEach(compatible) { variable in Button(variable.name) { model.bind(formula.id, to: variable.id) } }
                    if !compatible.isEmpty { Divider() }
                    Button("New Variable from This Value") { model.makeVariable(fromValueOf: formula.id) }
                } label: { Image(systemName: "function") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Use a variable").accessibilityLabel("Use a variable")
            }
        }
    }
}

/// Il nome di una variabile dove un'azione la usa: riconoscibile dal simbolo, non solo dal colore.
private struct VariablePill: View {
    let title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "function").font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color(nsColor: Theme.accentInk))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color(nsColor: Theme.activeBottom))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct VariableBlock: View {
    @ObservedObject var model: ComposerBoardModel
    let variable: StyleVariable
    @Binding var expanded: Bool
    @State private var editingDefinition = false

    private var variables: [StyleVariable] { model.currentStyle?.variables ?? [] }

    var body: some View {
        let evaluated = model.value(of: variable)
        BlockSurface(selected: false, open: expanded) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(.borderless).accessibilityLabel(expanded ? "Collapse variable" : "Expand variable")
                Image(systemName: "function").foregroundStyle(Color(nsColor: Theme.glyph))
                TextField("Name", text: Binding(get: { variable.name }, set: { model.renameVariable(variable.id, to: $0) }))
                    .textFieldStyle(.plain).fontWeight(.medium).frame(minWidth: 70, maxWidth: 150)
                    .accessibilityLabel("Variable name")
                if !expanded {
                    Text("= " + variable.expression.summary(in: model.sheet.reusableFormulas, variables: variables))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let value = evaluated.value {
                    Text(value.description).monospacedDigit()
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(nsColor: Theme.warn)).help(evaluated.problem ?? "")
                }
                Button { model.removeVariable(variable.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove variable")
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ExpressionLine(model: model, expression: variable.expression, owner: variable.id) {
                    model.updateVariable(variable.id, expression: $0)
                }
                if let problem = evaluated.problem {
                    Text(problem).font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
                }
                Text("Used by \(model.users(of: variable.id))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Un'espressione su una riga: un valore, una somma di due operandi, una formula richiamata con i suoi argomenti, o
/// un'altra variabile. Ciò che è più annidato si apre a parte, con l'editor completo, solo quando serve.
private struct ExpressionLine: View {
    @ObservedObject var model: ComposerBoardModel
    let expression: FormulaExpression
    let owner: UUID
    let commit: (FormulaExpression) -> Void
    @State private var editing = false

    private var variables: [StyleVariable] { model.currentStyle?.variables ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                kindMenu
                switch expression {
                case .constant, .variable:
                    OperandControl(model: model, expression: expression, owner: owner, type: nil, commit: commit)
                case .add(let a, let b):
                    OperandControl(model: model, expression: a, owner: owner, type: nil) { commit(.add($0, b)) }
                    Text("+")
                    OperandControl(model: model, expression: b, owner: owner, type: nil) { commit(.add(a, $0)) }
                case .call(let id, _):
                    if model.sheet.reusableFormulas.contains(where: { $0.id == id }) {
                        Button("Open Definition") { model.section = .reusable }.buttonStyle(.link).font(.caption)
                    } else {
                        Text("Formula not found").foregroundStyle(Color(nsColor: Theme.warn))
                    }
                case .parameter:
                    Text("Parameter").foregroundStyle(.secondary)
                }
            }
            // Gli argomenti di una formula richiamata, uno per riga.
            if case .call(let id, let arguments) = expression, let definition = model.sheet.reusableFormulas.first(where: { $0.id == id }) {
                ForEach(definition.parameters) { parameter in
                    HStack(spacing: 8) {
                        Text(parameter.name).foregroundStyle(.secondary).fixedSize()
                        OperandControl(model: model, expression: arguments[parameter.id] ?? .constant(parameter.type.zero), owner: owner, type: parameter.type) { value in
                            var updated = arguments
                            updated[parameter.id] = value
                            commit(.call(id, arguments: updated))
                        }
                    }
                }
            }
        }
    }

    private var kindMenu: some View {
        Menu {
            Button("Value") { commit(.constant(.length(12))) }
            Button("Sum") { commit(.add(.constant(.length(12)), .constant(.length(6)))) }
            ForEach(model.sheet.reusableFormulas) { definition in
                Button("Call · " + definition.name) {
                    commit(.call(definition.id, arguments: Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, FormulaExpression.constant($0.type.zero)) })))
                }
            }
        } label: { ComposerPill(title: kindTitle) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var kindTitle: String {
        switch expression {
        case .constant: "Value"
        case .add: "Sum"
        case .call(let id, _): "Call · " + (model.sheet.reusableFormulas.first { $0.id == id }?.name ?? "assente")
        case .variable: "Variable"
        case .parameter: "Parameter"
        }
    }
}

/// Un operando: un valore scritto, o una variabile dello stile del tipo giusto. Un operando più complesso mostra il suo
/// riassunto e si modifica a parte.
private struct OperandControl: View {
    @ObservedObject var model: ComposerBoardModel
    let expression: FormulaExpression
    let owner: UUID
    let type: FormulaValueType?
    let commit: (FormulaExpression) -> Void
    @State private var editing = false

    private var variables: [StyleVariable] { model.currentStyle?.variables ?? [] }
    private var choices: [StyleVariable] {
        variables.filter { $0.id != owner && (type == nil || model.type(of: $0) == type) }
    }

    var body: some View {
        HStack(spacing: 4) {
            switch expression {
            case .constant(let value):
                FormulaValueEditor(value: Binding(get: { value }, set: { commit(.constant($0)) }))
                if value.type == .length { Text("pt").foregroundStyle(.secondary) }
            case .variable(let id):
                VariablePill(title: variables.first { $0.id == id }?.name ?? "Missing variable")
            default:
                Button(expression.summary(in: model.sheet.reusableFormulas, variables: variables)) { editing = true }
                    .popover(isPresented: $editing) {
                        FormulaExpressionEditor(expression: Binding(get: { expression }, set: { commit($0) }),
                                                type: type ?? .length, parameters: [], definitions: model.sheet.reusableFormulas)
                            .padding(16).frame(minWidth: 360)
                    }
            }
            if !choices.isEmpty || expression.isVariable {
                Menu {
                    Button("Typed Value") { commit(.constant((type ?? .length).zero)) }
                    ForEach(choices) { variable in Button(variable.name) { commit(.variable(variable.id)) } }
                } label: { Image(systemName: "function") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Use a variable").accessibilityLabel("Use a variable")
            }
        }
    }
}

// MARK: - Anteprima

private struct ComposerPreview: View {
    @ObservedObject var model: ComposerBoardModel
    @State private var trial = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                Button { trial += 1; model.objectWillChange.send() } label: { Label("Try", systemImage: "play") }
                    .help("Re-evaluate the style on the sample")
            }
            TextField("Sample text", text: $model.sample, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            if let style = model.currentStyle {
                context(style)
                sample(style)
            }
            Spacer(minLength: 0)
            Text(status).font(.caption)
                .foregroundStyle(Color(nsColor: model.problem == nil && model.validationIssue == nil ? Theme.secondary : Theme.warn))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Reload") { model.discard() }.help("Replaces the draft with the document's current definitions")
                Spacer()
                Button("Apply to Document") { model.apply() }.disabled(!model.dirty || !model.valid)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .background(Color(nsColor: Theme.bar))
        .id(trial)
    }

    private var status: String {
        model.problem ?? model.validationIssue ?? (model.dirty ? "Changes to apply to the document" : "Ready")
    }

    @ViewBuilder private func context(_ style: NamedStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("From the document") { model.previewRole = nil }
                ForEach(FontRole.allCases, id: \.self) { role in Button(roleTitle(role)) { model.previewRole = role } }
            } label: { ComposerPill(title: "Character · " + (model.previewRole.map(roleTitle) ?? "from the document")) }.fixedSize()
            if style.target == .paragraph {
                Toggle("First on page", isOn: $model.previewFirstOnPage)
                Toggle("Sequence start", isOn: $model.previewSequenceStart)
                Menu {
                    Button("No previous") { model.previewPreviousStyle = nil }
                    ForEach(model.sheet.styles.filter { $0.target == .paragraph }, id: \.name) { previous in
                        Button(previous.name) { model.previewPreviousStyle = previous.name }
                    }
                } label: { ComposerPill(title: model.previewPreviousStyle.map { "After · " + $0 } ?? "Previous paragraph") }.fixedSize()
                if style.formulas.contains(where: { $0.when.measurement != nil }) {
                    HStack {
                        Text("Lines")
                        FormulaNumberPill(value: Double(model.previewLineCount)) { model.previewLineCount = max(1, Int($0)) }
                        Text("Last %")
                        FormulaNumberPill(value: model.previewLastLineFill) { model.previewLastLineFill = min(100, $0) }
                    }.font(.caption)
                }
            }
        }
        .toggleStyle(.checkbox).menuStyle(.borderlessButton).menuIndicator(.hidden)
    }

    @ViewBuilder private func sample(_ style: NamedStyle) -> some View {
        if let result = try? model.preview(style) {
            let paragraph = result.paragraph
            Group {
                if let heading = style.heading {
                    HeadingPreview(model: model, heading: heading, titleCharacter: result.character)
                } else {
                    Text(AttributedString(NSAttributedString(string: model.sample, attributes: TextStyling.characterAttributes(for: result.character).attributes)))
                        .padding(.leading, min(CGFloat(max(paragraph.leftIndent, 0)), 120))
                        .padding(.top, min(CGFloat(max(paragraph.spaceBefore, 0)), 60))
                }
            }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: Theme.rulerPage))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: Theme.line)))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(touchedProperties(style), id: \.self) { property in
                    HStack {
                        Text(property.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(ComposerBoard(model: model).summary(result, property: property)).monospacedDigit()
                    }
                }
            }.font(.caption)
        } else {
            Text("The style produces no result on the sample: check the font role and measures.")
                .font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
        }
    }

    private func touchedProperties(_ style: NamedStyle) -> [StyleProperty] {
        var result: [StyleProperty] = [.size]
        for formula in style.formulas where !result.contains(formula.operation.property) { result.append(formula.operation.property) }
        return result
    }
}

// MARK: - Aiuti

extension FormulaExpression {
    var isVariable: Bool { if case .variable = self { true } else { false } }
}

extension StyleProperty {
    /// Il simbolo dell'azione nella libreria e nel flusso.
    var symbol: String {
        switch self {
        case .font, .family, .face: "textformat"
        case .size: "textformat.size"
        case .color: "paintpalette"
        case .smallCaps: "textformat.alt"
        case .hyphenates: "minus"
        case .language: "globe"
        case .alignment: "text.alignleft"
        case .spaceBefore, .spaceAfter, .lineSpacing: "arrow.up.and.down.text.horizontal"
        case .firstLineIndent, .leftIndent, .rightIndent: "increase.indent"
        case .pageStartSpacing, .openingDistance: "arrow.down.to.line"
        case .opensSection, .outlineLevel: "list.bullet.indent"
        case .nextStyle: "return"
        case .applyStyle: "paintbrush"
        case .keepWithNext, .keepTogether, .orphanLines, .widowLines: "link"
        }
    }

    /// Le proprietà fra cui un'azione può cambiare restando nella sua specie: formattazione con formattazione,
    /// comportamenti con comportamenti (un comportamento si valuta in un'altra fase).
    var phaseFamily: Bool { isDirective }
}

// MARK: - Testata

/// La testata di uno stile di titolo nel flusso: un blocco con le parti in ordine, una riga ciascuna.
struct HeadingBlock: View {
    @ObservedObject var model: ComposerBoardModel
    let heading: HeadingComposition
    @Binding var expanded: Bool
    @State private var draggingPart: Int?
    private let mm = 72 / 25.4

    private var paragraphStyles: [String] { model.sheet.styles.map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(.borderless).accessibilityLabel(expanded ? "Collapse heading" : "Expand heading")
                Image(systemName: "rectangle.split.1x2").foregroundStyle(Color(nsColor: Theme.glyph))
                Text("Heading").fontWeight(.medium)
                if !expanded {
                    Text(heading.parts.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button { model.removeHeading() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove heading")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(heading.parts.enumerated()), id: \.offset) { index, part in
                        partRow(index, part)
                            .opacity(draggingPart == index ? 0.4 : 1)
                            .onDrag {
                                draggingPart = index
                                return NSItemProvider(object: String(index) as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: HeadingPartDrop(model: model, target: index, dragging: $draggingPart))
                    }
                    if let problem = heading.problem {
                        Text(problem).font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
                    }
                }
                .padding(10)
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
            }
        }
        .background(Color(nsColor: Theme.control))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: Theme.line)))
    }

    @ViewBuilder private func partRow(_ index: Int, _ part: HeadingPart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(part.title).frame(width: 56, alignment: .leading).foregroundStyle(.secondary)
                switch part {
                case .label(let text, let style, let alignment, let minHeight):
                    TextField("Text", text: Binding(get: { text }, set: { model.updateHeadingPart(at: index, to: .label(text: $0, style: style, alignment: alignment, minHeight: minHeight)) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                case .number(let prefix, let style, let alignment, let minHeight):
                    TextField("Before the number", text: Binding(get: { prefix }, set: { model.updateHeadingPart(at: index, to: .number(prefix: $0, style: style, alignment: alignment, minHeight: minHeight)) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                case .title:
                    Text("the title lines").foregroundStyle(.secondary).lineLimit(1)
                case .numberBeside(let prefix, let style, let side, let gap):
                    TextField("Before the number", text: Binding(get: { prefix }, set: { model.updateHeadingPart(at: index, to: .numberBeside(prefix: $0, style: style, side: side, gap: gap)) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                case .rule(let thickness, let length, let alignment):
                    FormulaNumberPill(value: (thickness / mm * 100).rounded() / 100) { if $0 > 0 { model.updateHeadingPart(at: index, to: .rule(thickness: $0 * mm, length: length, alignment: alignment)) } }
                        .fixedSize()
                    Text("mm").foregroundStyle(.secondary)
                case .space(let length):
                    FormulaNumberPill(value: (length / mm * 100).rounded() / 100) { model.updateHeadingPart(at: index, to: .space($0 * mm)) }
                        .fixedSize()
                    Text("mm").foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { model.removeHeadingPart(at: index) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Remove part")
            }
            // I controlli dell'aspetto su una seconda riga, sotto il valore.
            HStack(spacing: 6) {
                switch part {
                case .label(let text, let style, let alignment, let minHeight):
                    styleMenu(style) { model.updateHeadingPart(at: index, to: .label(text: text, style: $0, alignment: alignment, minHeight: minHeight)) }
                    alignmentMenu(alignment) { model.updateHeadingPart(at: index, to: .label(text: text, style: style, alignment: $0, minHeight: minHeight)) }
                    heightPill(minHeight) { model.updateHeadingPart(at: index, to: .label(text: text, style: style, alignment: alignment, minHeight: $0)) }
                case .number(let prefix, let style, let alignment, let minHeight):
                    styleMenu(style) { model.updateHeadingPart(at: index, to: .number(prefix: prefix, style: $0, alignment: alignment, minHeight: minHeight)) }
                    alignmentMenu(alignment) { model.updateHeadingPart(at: index, to: .number(prefix: prefix, style: style, alignment: $0, minHeight: minHeight)) }
                    heightPill(minHeight) { model.updateHeadingPart(at: index, to: .number(prefix: prefix, style: style, alignment: alignment, minHeight: $0)) }
                case .title(let alignment, let minHeight):
                    Menu {
                        Button("Style's alignment") { model.updateHeadingPart(at: index, to: .title(alignment: nil, minHeight: minHeight)) }
                        Divider()
                        ForEach(HeadingAlignment.allCases, id: \.self) { value in
                            Button(value.title) { model.updateHeadingPart(at: index, to: .title(alignment: value, minHeight: minHeight)) }
                        }
                    } label: { ComposerPill(title: alignment?.title ?? "Style's alignment") }.fixedSize()
                    heightPill(minHeight) { model.updateHeadingPart(at: index, to: .title(alignment: alignment, minHeight: $0)) }
                case .numberBeside(let prefix, let style, let side, let gap):
                    styleMenu(style) { model.updateHeadingPart(at: index, to: .numberBeside(prefix: prefix, style: $0, side: side, gap: gap)) }
                    Menu {
                        ForEach(HeadingAlignment.sides, id: \.self) { value in
                            Button(value.title) { model.updateHeadingPart(at: index, to: .numberBeside(prefix: prefix, style: style, side: value, gap: gap)) }
                        }
                    } label: { ComposerPill(title: side.title) }.fixedSize()
                    Text("gap").foregroundStyle(.secondary)
                    FormulaNumberPill(value: (gap / mm * 100).rounded() / 100) { if $0 >= 0 { model.updateHeadingPart(at: index, to: .numberBeside(prefix: prefix, style: style, side: side, gap: $0 * mm)) } }
                        .fixedSize()
                    Text("mm").foregroundStyle(.secondary)
                case .rule(let thickness, let length, let alignment):
                    Menu {
                        Button("Full measure") { model.updateHeadingPart(at: index, to: .rule(thickness: thickness, length: nil, alignment: alignment)) }
                        ForEach([20, 40, 60, 80], id: \.self) { n in
                            Button("\(n) mm") { model.updateHeadingPart(at: index, to: .rule(thickness: thickness, length: Double(n) * mm, alignment: alignment)) }
                        }
                    } label: { ComposerPill(title: length.map { "\(Int(($0 / mm).rounded())) mm long" } ?? "Full measure") }.fixedSize()
                    if length != nil {
                        alignmentMenu(alignment) { model.updateHeadingPart(at: index, to: .rule(thickness: thickness, length: length, alignment: $0)) }
                    }
                default: EmptyView()
                }
            }
            .padding(.leading, 12)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Part \(index + 1): " + part.title)
        .accessibilityAction(named: "Move up") { model.moveHeadingPart(at: index, by: -1) }
        .accessibilityAction(named: "Move down") { model.moveHeadingPart(at: index, by: 1) }
    }

    private func styleMenu(_ current: String?, _ commit: @escaping (String?) -> Void) -> some View {
        Menu {
            Button("Title style") { commit(nil) }
            ForEach(paragraphStyles, id: \.self) { name in Button(name) { commit(name) } }
        } label: { ComposerPill(title: current ?? "Title style") }.fixedSize()
    }

    private func alignmentMenu(_ current: HeadingAlignment, _ commit: @escaping (HeadingAlignment) -> Void) -> some View {
        Menu {
            ForEach(HeadingAlignment.allCases, id: \.self) { alignment in Button(alignment.title) { commit(alignment) } }
        } label: { ComposerPill(title: current.title) }.fixedSize()
    }

    private func heightPill(_ current: Double?, _ commit: @escaping (Double?) -> Void) -> some View {
        Menu {
            Button("Natural") { commit(nil) }
            ForEach([6, 8, 10, 12, 16, 20], id: \.self) { n in Button("\(n) mm") { commit(Double(n) * mm) } }
        } label: { ComposerPill(title: current.map { "\(Int(($0 / mm).rounded())) mm tall" } ?? "Natural") }.fixedSize()
            .help("Minimum band height")
    }
}

/// La testata nell'anteprima: le parti una sotto l'altra, alla loro misura, con il campione al posto del titolo.
struct HeadingPreview: View {
    @ObservedObject var model: ComposerBoardModel
    let heading: HeadingComposition
    let titleCharacter: CharacterStyle

    private func character(_ style: String?) -> CharacterStyle {
        guard let style, let target = model.sheet.style(named: style)?.target else { return titleCharacter }
        return model.sheet.resolveCharacter(paragraphStyle: target == .paragraph ? style : model.selectedStyle,
                                            wordStyle: target == .word ? style : nil, characterStyle: target == .character ? style : nil,
                                            base: TextStyling.styleBase, resolver: model.resolver)
    }

    private func alignment(_ value: HeadingAlignment) -> Alignment {
        switch value.resolved(onLeftPage: false) {
        case .right: .trailing
        case .center: .center
        default: .leading
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(heading.parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .label(let text, let style, let value, let minHeight):
                    line(text, character(style), value, minHeight)
                case .number(let prefix, let style, let value, let minHeight):
                    line(prefix + "1", character(style), value, minHeight)
                case .numberBeside:
                    EmptyView()
                case .title(let value, let minHeight):
                    // Il numero accanto al titolo, dal suo lato, sulla prima riga.
                    if let beside = heading.numberBeside {
                        let number = text(beside.prefix + "1", character(beside.style)).fixedSize()
                        let right = beside.side.resolved(onLeftPage: false) == .right
                        HStack(alignment: .firstTextBaseline, spacing: min(CGFloat(beside.gap), 40)) {
                            if !right { number }
                            line(model.sample, titleCharacter, value ?? .left, minHeight)
                            if right { number }
                        }
                    } else {
                        line(model.sample, titleCharacter, value ?? .left, minHeight)
                    }
                case .rule(let thickness, let length, let value):
                    Rectangle().fill(Color(nsColor: Theme.text))
                        .frame(width: length.map { CGFloat($0) }, height: max(CGFloat(thickness), 0.5))
                        .frame(maxWidth: .infinity, alignment: alignment(value))
                case .space(let length):
                    Color.clear.frame(height: min(CGFloat(length), 80))
                }
            }
        }
    }

    private func text(_ string: String, _ character: CharacterStyle) -> Text {
        Text(AttributedString(NSAttributedString(string: string, attributes: TextStyling.characterAttributes(for: character).attributes)))
    }

    private func line(_ string: String, _ character: CharacterStyle, _ value: HeadingAlignment, _ minHeight: Double?) -> some View {
        text(string, character)
            .lineLimit(3)
            .frame(maxWidth: .infinity, minHeight: minHeight.map { min(CGFloat($0), 80) }, alignment: Alignment(horizontal: alignment(value).horizontal, vertical: .bottom))
    }
}
