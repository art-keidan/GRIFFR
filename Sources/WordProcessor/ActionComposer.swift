import AppKit
import SwiftUI
import Typesetting

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
                    Text("Nessuno stile").foregroundStyle(.secondary).padding(24)
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
            } label: { ComposerPill(title: model.selectedStyle ?? "Scegli uno stile") }
                .menuStyle(.borderlessButton).accessibilityLabel("Stile")
            TextField("Cerca un'azione", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Con la ricerca, un gruppo senza voci non compare.
                    let formatting = properties(directive: false), behaviours = properties(directive: true)
                    if !formatting.isEmpty { group("Formattazione") }
                    ForEach(formatting, id: \.self) { property in
                        item(property.title, symbol: property.symbol) { if let id = model.addAction(property) { added(id) } }
                    }
                    if !behaviours.isEmpty { group("Comportamenti") }
                    ForEach(behaviours, id: \.self) { property in
                        item(property.title, symbol: property.symbol) { if let id = model.addAction(property) { added(id) } }
                    }
                    conditions
                    calculations
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: Theme.side))
    }

    @ViewBuilder private var conditions: some View {
        let titles = ["Primo della pagina", "Inizio sequenza", "Sempre"]
        if titles.contains(where: matches) || matches("Dopo lo stile") {
            group("Condizioni dell'azione scelta")
            if matches("Primo della pagina") { conditionItem("Primo della pagina", .firstOnPage) }
            if matches("Inizio sequenza") { conditionItem("Inizio sequenza", .sequenceStart) }
            if matches("Dopo lo stile") {
                Menu {
                    ForEach(paragraphStyles, id: \.self) { name in
                        Button(name) { if let id = selectedAction { model.applyCondition(.firstAfter(name), to: id) } }
                    }
                } label: { Label("Dopo lo stile…", systemImage: "arrow.turn.down.right") }
                    .menuStyle(.borderlessButton).disabled(selectedAction == nil).padding(.vertical, 3)
            }
            if matches("Sempre") { conditionItem("Sempre", .any) }
        }
    }

    @ViewBuilder private var calculations: some View {
        if matches("Valore con nome") || matches("Somma") {
            group("Calcoli")
            if matches("Valore con nome") {
                item("Valore con nome", symbol: "number") {
                    _ = model.addVariable(named: "Valore", expression: .constant(.length(12)))
                }
            }
            if matches("Somma") {
                item("Somma di due valori", symbol: "plus.forwardslash.minus") {
                    _ = model.addVariable(named: "Somma", expression: .add(.constant(.length(12)), .constant(.length(6))))
                }
            }
        }
        let formulas = model.sheet.reusableFormulas.filter { matches($0.name) }
        if !formulas.isEmpty || search.trimmingCharacters(in: .whitespaces).isEmpty { group("Formule del documento") }
        ForEach(formulas) { definition in
            item(definition.name, symbol: "function") { _ = model.addVariable(calling: definition) }
        }
        Button { model.section = .reusable } label: { Label("Gestisci le formule…", systemImage: "slider.horizontal.3") }
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
        .accessibilityLabel("Aggiungi " + title)
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
        .accessibilityLabel("Condizione " + title + " per l'azione scelta")
    }
}

// MARK: - Flusso

private struct ComposerFlow: View {
    @ObservedObject var model: ComposerBoardModel
    let style: NamedStyle
    @Binding var expanded: Set<UUID>
    @Binding var selectedAction: UUID?

    private var objectTitle: String {
        switch style.target {
        case .paragraph: "Questo paragrafo"
        case .word: "Questa parola"
        case .character: "Questi caratteri"
        }
    }

    var body: some View {
        let ordered = model.orderedActions(style)
        let states = (try? model.formulaStates(style)) ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(style.name).font(.title3.weight(.semibold))
                Spacer()
                Text("Eredita da").foregroundStyle(.secondary)
                Menu {
                    Button("Nessuno") { setParent(nil) }
                    ForEach(model.sheet.possibleParents(of: style.name), id: \.self) { name in Button(name) { setParent(name) } }
                } label: { ComposerPill(title: style.basedOn ?? "Documento") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            HStack {
                Image(systemName: style.target == .paragraph ? "paragraphsign" : "textformat")
                Text(objectTitle)
                Spacer()
                Text("Oggetto iniziale").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
            if !style.variables.isEmpty {
                caption("Variabili")
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
                }
            }
            if ordered.isEmpty && style.variables.isEmpty {
                Text("Aggiungi un'azione dalla libreria.").foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ComposerBoard(model: model).compatibleProperties(style)
        }
    }

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
        var parts = ["a " + valueTitle]
        if !formula.when.isAlways { parts.append("se " + formula.when.summary.lowercased()) }
        if formula.target != .paragraph { parts.append("su " + FormulaQualifiers.title(of: formula.target, selections: model.sheet.selections).lowercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        BlockSurface(selected: selected, open: expanded) {
            HStack(spacing: 8) {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 14)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                    .buttonStyle(.borderless).accessibilityLabel(expanded ? "Richiudi l'azione" : "Apri l'azione")
                Image(systemName: operation.property.symbol).foregroundStyle(Color(nsColor: Theme.glyph))
                Text(operation.predicate.title + " " + operation.property.title.lowercased()).fontWeight(.medium).lineLimit(1)
                    .layoutPriority(1)
                if !expanded { Text(summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
                Spacer(minLength: 6)
                moveButton("arrow.up", -1, "Sposta prima", .upArrow)
                moveButton("arrow.down", 1, "Sposta dopo", .downArrow)
                Button { model.removeStyleFormula(formula.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Togli l'azione")
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = true }
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
                    Text("a").foregroundStyle(.secondary)
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
                        Text(formula.when.holds(in: model.previewContext, facts: model.previewFacts) ? "Condizione soddisfatta nel campione" : "Condizione non soddisfatta nel campione")
                    }
                    Spacer()
                    if let state {
                        let board = ComposerBoard(model: model)
                        Text(board.summary(state.input, property: operation.property) + " → " + board.summary(state.output, property: operation.property))
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Azione \(number): " + operation.predicate.title + " " + operation.property.title)
    }

    @ViewBuilder private var valueControl: some View {
        let compatible = model.compatibleVariables(for: formula)
        if let binding = formula.binding {
            Menu {
                Button("Valore fisso") { model.bind(formula.id, to: nil) }
                if !compatible.isEmpty { Divider() }
                ForEach(compatible) { variable in Button(variable.name) { model.bind(formula.id, to: variable.id) } }
                if case .variable = binding {} else {
                    Divider()
                    Button("Dai un nome a questo calcolo") { model.extractVariable(from: formula.id) }
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
                    Button("Nuova variabile da questo valore") { model.makeVariable(fromValueOf: formula.id) }
                } label: { Image(systemName: "function") }
                    .menuStyle(.borderlessButton).fixedSize().help("Usa una variabile").accessibilityLabel("Usa una variabile")
            }
        }
    }

    @ViewBuilder private func moveButton(_ symbol: String, _ offset: Int, _ label: String, _ key: KeyEquivalent) -> some View {
        let button = Button { model.moveStyleFormula(formula.id, by: offset) } label: { Image(systemName: symbol) }
            .buttonStyle(.borderless).disabled(!model.canMove(formula.id, by: offset))
            .help(model.canMove(formula.id, by: offset) ? label : label + ": non oltre la sua fase")
            .accessibilityLabel(label)
        if selected { button.keyboardShortcut(key, modifiers: [.command, .option]) } else { button }
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
                    .buttonStyle(.borderless).accessibilityLabel(expanded ? "Richiudi la variabile" : "Apri la variabile")
                Image(systemName: "function").foregroundStyle(Color(nsColor: Theme.glyph))
                TextField("Nome", text: Binding(get: { variable.name }, set: { model.renameVariable(variable.id, to: $0) }))
                    .textFieldStyle(.plain).fontWeight(.medium).frame(minWidth: 70, maxWidth: 150)
                    .accessibilityLabel("Nome della variabile")
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
                    .buttonStyle(.borderless).accessibilityLabel("Togli la variabile")
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ExpressionLine(model: model, expression: variable.expression, owner: variable.id) {
                    model.updateVariable(variable.id, expression: $0)
                }
                if let problem = evaluated.problem {
                    Text(problem).font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
                }
                Text("Usata da \(model.users(of: variable.id))").font(.caption).foregroundStyle(.secondary)
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
                        Button("Apri la definizione") { model.section = .reusable }.buttonStyle(.link).font(.caption)
                    } else {
                        Text("Formula non trovata").foregroundStyle(Color(nsColor: Theme.warn))
                    }
                case .parameter:
                    Text("Parametro").foregroundStyle(.secondary)
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
            Button("Valore") { commit(.constant(.length(12))) }
            Button("Somma") { commit(.add(.constant(.length(12)), .constant(.length(6)))) }
            ForEach(model.sheet.reusableFormulas) { definition in
                Button("Richiama · " + definition.name) {
                    commit(.call(definition.id, arguments: Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, FormulaExpression.constant($0.type.zero)) })))
                }
            }
        } label: { ComposerPill(title: kindTitle) }.menuStyle(.borderlessButton).fixedSize()
    }

    private var kindTitle: String {
        switch expression {
        case .constant: "Valore"
        case .add: "Somma"
        case .call(let id, _): "Richiama · " + (model.sheet.reusableFormulas.first { $0.id == id }?.name ?? "assente")
        case .variable: "Variabile"
        case .parameter: "Parametro"
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
                VariablePill(title: variables.first { $0.id == id }?.name ?? "Variabile assente")
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
                    Button("Valore scritto") { commit(.constant((type ?? .length).zero)) }
                    ForEach(choices) { variable in Button(variable.name) { commit(.variable(variable.id)) } }
                } label: { Image(systemName: "function") }
                    .menuStyle(.borderlessButton).fixedSize().help("Usa una variabile").accessibilityLabel("Usa una variabile")
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
                Text("Anteprima").font(.headline)
                Spacer()
                Button { trial += 1; model.objectWillChange.send() } label: { Label("Prova", systemImage: "play") }
                    .help("Rivaluta lo stile sul campione")
            }
            TextField("Testo di prova", text: $model.sample, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            if let style = model.currentStyle {
                context(style)
                sample(style)
            }
            Spacer(minLength: 0)
            Text(status).font(.caption)
                .foregroundStyle(Color(nsColor: model.problem == nil && model.validationIssue == nil ? Theme.secondary : Theme.warn))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Ricarica") { model.discard() }.help("Sostituisce la bozza con le definizioni attuali del documento")
                Spacer()
                Button("Applica al documento") { model.apply() }.disabled(!model.dirty || !model.valid)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .background(Color(nsColor: Theme.bar))
        .id(trial)
    }

    private var status: String {
        model.problem ?? model.validationIssue ?? (model.dirty ? "Modifiche da applicare al documento" : "Pronto")
    }

    @ViewBuilder private func context(_ style: NamedStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button("Dal documento") { model.previewRole = nil }
                ForEach(FontRole.allCases, id: \.self) { role in Button(roleTitle(role)) { model.previewRole = role } }
            } label: { ComposerPill(title: "Carattere · " + (model.previewRole.map(roleTitle) ?? "dal documento")) }.fixedSize()
            if style.target == .paragraph {
                Toggle("Primo della pagina", isOn: $model.previewFirstOnPage)
                Toggle("Inizio sequenza", isOn: $model.previewSequenceStart)
                Menu {
                    Button("Nessun precedente") { model.previewPreviousStyle = nil }
                    ForEach(model.sheet.styles.filter { $0.target == .paragraph }, id: \.name) { previous in
                        Button(previous.name) { model.previewPreviousStyle = previous.name }
                    }
                } label: { ComposerPill(title: model.previewPreviousStyle.map { "Dopo · " + $0 } ?? "Paragrafo precedente") }.fixedSize()
                if style.formulas.contains(where: { $0.when.measurement != nil }) {
                    HStack {
                        Text("Righe")
                        FormulaNumberPill(value: Double(model.previewLineCount)) { model.previewLineCount = max(1, Int($0)) }
                        Text("Ultima %")
                        FormulaNumberPill(value: model.previewLastLineFill) { model.previewLastLineFill = min(100, $0) }
                    }.font(.caption)
                }
            }
        }
        .toggleStyle(.checkbox).menuStyle(.borderlessButton)
    }

    @ViewBuilder private func sample(_ style: NamedStyle) -> some View {
        if let result = try? model.preview(style) {
            let paragraph = result.paragraph
            Text(AttributedString(NSAttributedString(string: model.sample, attributes: TextStyling.characterAttributes(for: result.character).attributes)))
                .padding(.leading, min(CGFloat(max(paragraph.leftIndent, 0)), 120))
                .padding(.top, min(CGFloat(max(paragraph.spaceBefore, 0)), 60))
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
            Text("Lo stile non produce un risultato sul campione: controlla ruolo del font e misure.")
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
