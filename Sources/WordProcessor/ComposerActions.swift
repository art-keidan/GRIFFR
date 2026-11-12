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
    func addVariable(named base: String = "Value", expression: FormulaExpression) -> UUID? {
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
            problem = count == 1 ? "The variable is used by an action: choose another value first."
                : "The variable is used by \(count) actions: choose another value first."
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
        if let id = addVariable(named: "Calculation", expression: binding) { bind(formulaID, to: id) }
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
            problem = "“\(formula.operation.property.title)” does not accept this condition: it is evaluated in another phase."
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
    func addHeadingPart(_ part: HeadingPart) { changeHeading { $0 = HeadingComposition.adding(part, to: $0) } }

    /// I ruoli delle sezioni che una formula «risultato» può nominare: quelli pronti e quelli aperti dagli stili.
    var sectionRoles: [String] {
        var roles = Typesetting.Section.Role.builtIn
        for style in sheet.styles { if let role = style.values.opensSection, !role.isEmpty, !roles.contains(role) { roles.append(role) } }
        return roles
    }

    /// Il risultato di una formula nel campione del compositore: pagina 1, e ogni sezione con il titolo del campione.
    var sampleFieldContext: FieldContext {
        FieldContext(pageNumber: "1", pageCount: "1",
                     sections: sectionRoles.map { FieldContext.Section(role: $0, title: sample, number: "1") })
    }

    func sampleResult(_ formula: FieldFormula) -> String {
        formula.value(in: sampleFieldContext)
    }

    var previewFieldContext: FieldContext? {
        previewMode == .sample ? sampleFieldContext : documentPreview?.context
    }

    private func resultEditor(for formula: FieldFormula) -> FieldFormulaEditorModel {
        refreshDocumentPreview()
        let context = previewFieldContext
        let label = previewMode == .sample ? "Sample result" : "Result at selection"
        return FieldFormulaEditorModel(formula: formula, roles: sectionRoles, editing: true, previewLabel: label) { formula in
            context.map { formula.value(in: $0) } ?? ""
        }
    }

    /// OK scrive la catena nella parte della testata, Annulla la lascia com'era; `done` chiude.
    func resultEditor(at index: Int, done: @escaping () -> Void) -> FieldFormulaEditorModel? {
        guard let parts = currentHeading?.parts, parts.indices.contains(index),
              case .result(let formula, let prefix, let style, let alignment, let minHeight) = parts[index] else { return nil }
        let editor = resultEditor(for: formula)
        editor.finish = { [weak self] chosen in
            if let chosen, chosen.problem == nil {
                self?.updateHeadingPart(at: index, to: .result(formula: chosen, prefix: prefix, style: style, alignment: alignment, minHeight: minHeight))
            }
            done()
        }
        return editor
    }

    func updateHeadingPart(at index: Int, to part: HeadingPart) { changeHeading { $0 = HeadingComposition.updating($0, at: index, to: part) } }

    func moveHeadingPart(at index: Int, by offset: Int) { changeHeading { $0 = HeadingComposition.moving($0, at: index, by: offset) } }

    func removeHeadingPart(at index: Int) { changeHeading { $0 = HeadingComposition.removing($0, at: index) } }
}

/// Spostare trascinando: un'azione va al posto di un'altra della stessa fase (l'ordine fra fasi lo decide il motore), una
/// parte della testata al posto di un'altra.
extension ComposerBoardModel {
    /// Vero se l'azione `id` può andare al posto di `target`: stesso stile, stessa fase.
    func canMoveAction(_ id: UUID, to target: UUID) -> Bool {
        guard id != target, let style = currentStyle,
              let a = style.formulas.first(where: { $0.id == id }), let b = style.formulas.first(where: { $0.id == target }) else { return false }
        return a.phase == b.phase
    }

    /// Porta l'azione `id` al posto di `target`, spostando le altre di uno.
    func moveAction(_ id: UUID, to target: UUID) {
        guard canMoveAction(id, to: target), let i = currentStyleIndex,
              let from = sheet.styles[i].formulas.firstIndex(where: { $0.id == id }),
              let to = sheet.styles[i].formulas.firstIndex(where: { $0.id == target }) else { return }
        let formula = sheet.styles[i].formulas.remove(at: from)
        sheet.styles[i].formulas.insert(formula, at: to)
    }

    /// Porta la parte `from` della testata al posto `to`.
    func moveHeadingPart(from: Int, to: Int) {
        guard from != to else { return }
        guard let name = selectedStyle else { return }
        selectStyle(name)
        guard let i = currentStyleIndex, var heading = sheet.styles[i].heading,
              heading.parts.indices.contains(from), heading.parts.indices.contains(to) else { return }
        let part = heading.parts.remove(at: from)
        heading.parts.insert(part, at: to)
        sheet.styles[i].heading = heading
    }
}

/// «Scrivi risultato» dentro il paragrafo (vedi `WrittenResult`): le azioni dello stile scelto che scrivono un risultato
/// prima o dopo il testo.
extension ComposerBoardModel {
    var currentWrites: [WrittenResult] { currentStyle?.writes ?? [] }

    private func changeWrites(_ change: (inout [WrittenResult]) -> Void) {
        guard let name = selectedStyle else { return }
        selectStyle(name)
        guard let i = currentStyleIndex, sheet.styles[i].target == .paragraph else { return }
        change(&sheet.styles[i].writes)
    }

    /// Un'azione nuova: davanti, il numero del capitolo con uno spazio; dopo, la pagina fra parentesi.
    func addWrite(_ place: WrittenResult.Place) {
        changeWrites { writes in
            writes.append(place == .before
                ? WrittenResult(formula: .sectionContainingNumber(role: Typesetting.Section.Role.chapter), place: .before, suffix: " ")
                : WrittenResult(formula: .pageContainingNumber, place: .after, prefix: " (p. ", suffix: ")"))
        }
    }

    func updateWrite(at index: Int, to written: WrittenResult) {
        changeWrites { writes in if writes.indices.contains(index) { writes[index] = written } }
    }

    func removeWrite(at index: Int) {
        changeWrites { writes in if writes.indices.contains(index) { writes.remove(at: index) } }
    }

    /// Il campione con ciò che lo stile scrive prima e dopo il testo, come nel documento.
    func writtenSample(_ style: String) -> String {
        let writes = sheet.writtenResults(ofParagraphStyle: style)
        let context = sampleFieldContext
        func text(_ place: WrittenResult.Place) -> String {
            writes.filter { $0.place == place }.map { $0.text(in: context) }.joined()
        }
        return text(.before) + sample + text(.after)
    }

    /// L'editor della catena di un'azione «Scrivi risultato», come per le parti della testata.
    func writeEditor(at index: Int, done: @escaping () -> Void) -> FieldFormulaEditorModel? {
        let writes = currentWrites
        guard writes.indices.contains(index) else { return nil }
        let written = writes[index]
        let editor = resultEditor(for: written.formula)
        editor.finish = { [weak self] chosen in
            if let chosen, chosen.problem == nil {
                var changed = written
                changed.formula = chosen
                self?.updateWrite(at: index, to: changed)
            }
            done()
        }
        return editor
    }
}

/// Le note che lo stile scelto dichiara dopo una parola (vedi `DeclaredNote`): il compositore le aggiunge, cambia la
/// parola e la serie, le toglie. Il testo di ciascuna nota non sta qui: si scrive nel documento (Insert › Declared Note
/// Text…), occorrenza per occorrenza.
extension ComposerBoardModel {
    private func changeDeclaredNotes(_ change: (inout [DeclaredNote]) -> Void) {
        guard let name = selectedStyle else { return }
        selectStyle(name)
        guard let i = currentStyleIndex, sheet.styles[i].target == .paragraph else { return }
        change(&sheet.styles[i].declaredNotes)
    }

    /// Una nota a piè di pagina dopo la quinta parola, il caso guida.
    @discardableResult
    func addDeclaredNote() -> UUID? {
        guard let note = DeclaredNote(word: 5) else { return nil }
        var added: UUID?
        changeDeclaredNotes { notes in notes.append(note); added = note.id }
        return added
    }

    /// Cambia la parola o la serie di una nota dichiarata; la sua identità resta, e con lei il testo delle sue occorrenze.
    func updateDeclaredNote(_ id: UUID, word: Int? = nil, style: String? = nil) {
        changeDeclaredNotes { notes in
            guard let index = notes.firstIndex(where: { $0.id == id }),
                  let changed = DeclaredNote(id: id, word: word ?? notes[index].word, style: style ?? notes[index].style) else { return }
            notes[index] = changed
        }
    }

    func removeDeclaredNote(_ id: UUID) {
        changeDeclaredNotes { notes in notes.removeAll { $0.id == id } }
    }
}
