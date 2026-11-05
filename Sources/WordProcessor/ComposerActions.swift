import Foundation
import Typesetting

/// Le operazioni del compositore ad azioni sulla bozza: variabili dello stile, collegamenti fra azioni e variabili,
/// e le condizioni date a un'azione. Tutto cambia la stessa definizione autorevole (`sheet`), che Applica porta al
/// documento come prima; nessun secondo modello.
extension ComposerBoardModel {
    var currentStyleIndex: Int? { sheet.styles.firstIndex { $0.name == selectedStyle } }
    var currentStyle: NamedStyle? { currentStyleIndex.map { sheet.styles[$0] } }
    var library: ReusableFormulaLibrary { ReusableFormulaLibrary(definitions: sheet.reusableFormulas) }

    /// Il valore di una variabile dello stile scelto, o il motivo per cui non c'è.
    func value(of variable: StyleVariable) -> (value: FormulaValue?, problem: String?) {
        let variables = currentStyle?.variables ?? []
        do { return (try library.evaluate(variable.expression.substitutingVariables(variables)), nil) }
        catch { return (nil, sheet.reusableProblem(error)) }
    }

    /// Il tipo di una variabile, se si può calcolare.
    func type(of variable: StyleVariable) -> FormulaValueType? {
        value(of: variable).value?.type
    }

    /// Una variabile nuova nello stile scelto, con un nome libero («Valore», «Valore 2»…). Restituisce la sua identità.
    @discardableResult
    func addVariable(named base: String = "Valore", expression: FormulaExpression) -> UUID? {
        guard let name = selectedStyle else { return nil }
        selectStyle(name)
        guard let i = currentStyleIndex else { return nil }
        var label = base, n = 2
        while sheet.styles[i].variables.contains(where: { $0.name == label }) { label = "\(base) \(n)"; n += 1 }
        let variable = StyleVariable(name: label, expression: expression)
        sheet.styles[i].variables.append(variable)
        return variable.id
    }

    /// Una variabile che richiama una formula del documento, con gli argomenti al loro zero.
    @discardableResult
    func addVariable(calling definition: ReusableFormula) -> UUID? {
        let arguments = Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, FormulaExpression.constant($0.type.zero)) })
        return addVariable(named: definition.name, expression: .call(definition.id, arguments: arguments))
    }

    func renameVariable(_ id: UUID, to name: String) {
        guard let i = currentStyleIndex, let j = sheet.styles[i].variables.firstIndex(where: { $0.id == id }) else { return }
        sheet.styles[i].variables[j].name = name
    }

    func updateVariable(_ id: UUID, expression: FormulaExpression) {
        guard let i = currentStyleIndex, let j = sheet.styles[i].variables.firstIndex(where: { $0.id == id }) else { return }
        sheet.styles[i].variables[j].expression = expression
    }

    /// Le azioni e le altre variabili che usano una variabile.
    func users(of id: UUID) -> Int {
        guard let style = currentStyle else { return 0 }
        return style.formulas.filter { $0.binding?.variableReferences.contains(id) == true }.count
            + style.variables.filter { $0.id != id && $0.expression.variableReferences.contains(id) }.count
    }

    /// Toglie una variabile; se qualcosa la usa, lo dice invece di lasciare riferimenti rotti.
    func removeVariable(_ id: UUID) {
        guard let i = currentStyleIndex else { return }
        let count = users(of: id)
        guard count == 0 else {
            problem = count == 1 ? "La variabile è usata da un'azione: scegli prima un altro valore."
                : "La variabile è usata da \(count) azioni: scegli prima un altro valore."
            return
        }
        sheet.styles[i].variables.removeAll { $0.id == id }
        problem = nil
    }

    /// Un'azione nuova «Imposta» per una proprietà, con il suo valore iniziale; restituisce la sua identità.
    @discardableResult
    func addAction(_ property: StyleProperty) -> UUID? {
        guard let name = selectedStyle else { return nil }
        selectStyle(name)
        guard let i = currentStyleIndex else { return nil }
        let formula = StyleFormula(operation: StylePropertyOperation(.set, property, property.initialArgument),
                                   when: property == .pageStartSpacing ? StyleCondition(position: .firstOnPage) : StyleCondition())
        guard (try? formula.validate(for: sheet.styles[i].target)) != nil else { return nil }
        sheet.styles[i].formulas.append(formula)
        return formula.id
    }

    /// Le variabili che un'azione può ricevere: dello stesso tipo del suo valore.
    func compatibleVariables(for formula: StyleFormula) -> [StyleVariable] {
        guard let wanted = formula.bindingType else { return [] }
        return (currentStyle?.variables ?? []).filter { type(of: $0) == wanted }
    }

    /// Collega il valore di un'azione a una variabile, o lo riporta a un valore fisso (quello che la variabile dava).
    func bind(_ formulaID: UUID, to variable: UUID?) {
        guard let i = currentStyleIndex, let j = sheet.styles[i].formulas.firstIndex(where: { $0.id == formulaID }) else { return }
        var formula = sheet.styles[i].formulas[j]
        if let variable {
            formula.binding = .variable(variable)
        } else if formula.binding != nil {
            if let resolved = try? formula.resolved(in: library, variables: sheet.styles[i].variables) { formula.operation = resolved.operation }
            formula.binding = nil
        }
        sheet.styles[i].formulas[j] = formula
    }

    /// Il calcolo scritto direttamente in un'azione diventa una variabile con un nome, che l'azione poi richiama.
    func extractVariable(from formulaID: UUID) {
        guard let formula = currentStyle?.formulas.first(where: { $0.id == formulaID }), let binding = formula.binding else { return }
        if case .variable = binding { return }
        if let id = addVariable(named: "Calcolo", expression: binding) { bind(formulaID, to: id) }
    }

    /// Il valore attuale di un'azione come nuova variabile: «Distanza = 18 pt», che poi altre azioni possono usare.
    func makeVariable(fromValueOf formulaID: UUID) {
        guard let formula = currentStyle?.formulas.first(where: { $0.id == formulaID }), formula.bindingType != nil else { return }
        if formula.binding != nil { return extractVariable(from: formulaID) }
        if let id = addVariable(named: formula.operation.property.title, expression: .constant(formula.bindingSeed)) { bind(formulaID, to: id) }
    }

    /// Dà all'azione la condizione chiesta dalla libreria, se è ammessa per quella proprietà; altrimenti dice perché no.
    func applyCondition(_ position: TextRule.Position, to formulaID: UUID) {
        guard let style = currentStyle, let formula = style.formulas.first(where: { $0.id == formulaID }) else { return }
        var when = formula.when
        when.position = position
        let candidate = StyleFormula(id: formula.id, operation: formula.operation, when: when, target: formula.target)
        guard (try? candidate.validate(for: style.target)) != nil else {
            problem = "«\(formula.operation.property.title)» non accetta questa condizione: si valuta in un'altra fase."
            return
        }
        problem = nil
        updateQualifiers(formulaID, when: when)
    }

    /// Le azioni nell'ordine in cui il motore le valuta: per fase, e dentro la fase nell'ordine dello stile.
    func orderedActions(_ style: NamedStyle) -> [(index: Int, formula: StyleFormula)] {
        Array(style.formulas.enumerated()).map { (index: $0.offset, formula: $0.element) }
            .sorted { $0.formula.phase == $1.formula.phase ? $0.index < $1.index : $0.formula.phase < $1.formula.phase }
    }

    /// Si può spostare l'azione di un passo in quella direzione senza uscire dalla sua fase?
    func canMove(_ formulaID: UUID, by offset: Int) -> Bool {
        guard let style = currentStyle, let formula = style.formulas.first(where: { $0.id == formulaID }) else { return false }
        let peers = style.formulas.filter { $0.phase == formula.phase }.map(\.id)
        guard let position = peers.firstIndex(of: formulaID) else { return false }
        return peers.indices.contains(position + offset)
    }
}

/// La testata dello stile scelto nella bozza (vedi `HeadingComposition`): si crea, si compone parte per parte, si toglie.
extension ComposerBoardModel {
    var currentHeading: HeadingComposition? { currentStyle?.heading }

    private func changeHeading(_ change: (inout HeadingComposition?) -> Void) {
        guard let name = selectedStyle else { return }
        selectStyle(name)
        guard let i = currentStyleIndex, sheet.styles[i].target == .paragraph else { return }
        var heading = sheet.styles[i].heading
        change(&heading)
        sheet.styles[i].heading = heading
    }

    /// La testata pronta del caso guida.
    func useStandardHeading() { changeHeading { $0 = .standard } }

    func removeHeading() { changeHeading { $0 = nil } }

    /// Una parte nuova in fondo alla testata (prima di quanto segue il titolo, se è un'etichetta o il numero). Senza
    /// testata, ne nasce una con il solo titolo.
    func addHeadingPart(_ part: HeadingPart) {
        changeHeading { heading in
            var parts = heading?.parts ?? [.title]
            if part == .title, parts.contains(.title) { return }
            switch part {
            case .label, .number:
                let title = parts.firstIndex(of: .title) ?? parts.count
                parts.insert(part, at: title)
            default:
                parts.append(part)
            }
            heading = HeadingComposition(parts: parts)
        }
    }

    func updateHeadingPart(at index: Int, to part: HeadingPart) {
        changeHeading { heading in
            guard var current = heading, current.parts.indices.contains(index) else { return }
            current.parts[index] = part
            heading = current
        }
    }

    func moveHeadingPart(at index: Int, by offset: Int) {
        changeHeading { heading in
            guard var current = heading, current.parts.indices.contains(index), current.parts.indices.contains(index + offset) else { return }
            current.parts.swapAt(index, index + offset)
            heading = current
        }
    }

    func removeHeadingPart(at index: Int) {
        changeHeading { heading in
            guard var current = heading, current.parts.indices.contains(index) else { return }
            current.parts.remove(at: index)
            heading = current.parts.isEmpty ? nil : current
        }
    }
}
