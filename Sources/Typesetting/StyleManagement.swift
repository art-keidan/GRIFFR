import Foundation

// MARK: - Il gestore degli stili

extension StyleSheet {
    /// Le proprietà che uno stile di quella specie può fissare: lo stile di paragrafo tutte, quello di parola anche
    /// lingua e sillabazione, quello di carattere solo le proprietà del carattere.
    public static func properties(for target: StyleTarget) -> [InspectorProperty] {
        switch target {
        case .paragraph: InspectorProperty.allCases
        case .word: InspectorProperty.allCases.filter { $0.level != .paragraph }
        case .character: InspectorProperty.properties(of: .character)
        }
    }

    /// I valori che uno stile dà, con quelli degli stili su cui si basa e del documento (`base`).
    private func resolvedValues(of name: String?, target: StyleTarget, base: CharacterStyle, resolver: FontRoleResolver = FontRoleResolver()) -> StyleValues {
        let character = resolveCharacter(paragraphStyle: target == .paragraph ? name : nil, wordStyle: target == .word ? name : nil,
                                         characterStyle: target == .character ? name : nil, base: base, resolver: resolver)
        let paragraph = resolveParagraph(styleName: target == .paragraph ? name : nil)
        return TextStyling.fullValues(character: character, paragraph: paragraph, list: values(of: name).list,
                                      openingDistance: target == .paragraph ? values(of: name).openingDistance ?? 0 : 0,
                                      keeping: target == .paragraph ? lineKeeping(styleName: name) : LineKeeping().resolved, resolver: resolver)
    }

    /// Le proprietà di uno stile come le mostra il gestore: il valore che dà e da dove viene (`.own` se lo fissa lui,
    /// `.style(nome)` se lo fissa uno stile su cui si basa, `.document` se nessuno); `inherited` è ciò che darebbe
    /// senza i suoi valori propri.
    public func inspect(style name: String, base: CharacterStyle, resolver: FontRoleResolver = FontRoleResolver()) -> [InspectedValue] {
        guard let style = style(named: name) else { return [] }
        let actual = resolvedValues(of: name, target: style.target, base: base, resolver: resolver)
        let inherited = resolvedValues(of: style.basedOn, target: style.target, base: base, resolver: resolver)
        return Self.properties(for: style.target).map { property in
            InspectedValue(property: property, value: property.only(actual), inherited: property.only(inherited),
                           source: source(of: property, in: style), isMixed: false)
        }
    }

    /// Da dove viene il valore di una proprietà in uno stile.
    private func source(of property: InspectorProperty, in style: NamedStyle) -> ValueSource {
        if style.declares(property) { return .own }
        var next = style.basedOn
        var seen: Set<String> = [style.name]
        while let name = next, !seen.contains(name), let parent = self.style(named: name) {
            if parent.declares(property) { return .style(parent.name) }
            seen.insert(name)
            next = parent.basedOn
        }
        return .document
    }

    /// I controlli supportati scrivono Imposta, conservando l'identità del nodo.
    /// Un calcolo richiede replacingFormula; il valore fisso resta esplicito anche
    /// quando coincide con quello ereditato. Gli altri campi usano l'adattatore storico.
    public func setting(_ values: StyleValues, of property: InspectorProperty, inStyle name: String, base: CharacterStyle, replacingFormula: Bool = false) -> StyleSheet {
        guard let position = styles.firstIndex(where: { $0.name == name }) else { return self }
        if !replacingFormula, formulaDefinition(for: property, inStyle: name)?.isCalculated == true { return self }
        if let operation = StylePropertyOperation.constant(values, for: property) {
            let formula = StyleFormula(operation: operation)
            guard (try? formula.validate(for: styles[position].target)) != nil else { return self }
            var result = self
            var style = result.styles[position]
            if property == .family {
                style.values.family = nil
                style.values.fontName = nil
            } else { style.values.clear(property) }
            if property == .face {
                style.values.family = nil; style.values.fontName = nil; style.values.italic = nil; style.values.bold = nil
                style.formulas.removeAll { $0.operation.property == .family }
            } else if property == .family {
                style.values.fontName = nil
                style.formulas.removeAll { $0.operation.property == .face }
            }
            let matching = style.formulas.indices.filter { style.formulas[$0].operation.property.inspectorProperty == property }
            if let last = matching.last {
                let id = style.formulas[matching[0]].id
                style.formulas = style.formulas.enumerated().compactMap { index, item in
                    if index == last { return StyleFormula(id: id, operation: operation) }
                    return matching.contains(index) ? nil : item
                }
            } else { style.formulas.append(formula) }
            result.styles[position] = style
            return result
        }
        var result = self
        result.styles[position].formulas.removeAll { $0.operation.property.inspectorProperty == property }
        var own = styles[position].values
        switch property {
        case .family:
            // Una famiglia nuova: la faccia precisa cade, restano corsivo e nero se c'erano.
            own.family = values.family
            own.fontName = nil
        case .face:
            own.fontName = values.fontName
            own.family = nil
            own.italic = nil
            own.bold = nil
        case .size: own.size = values.size
        case .color: own.color = values.color
        case .smallCaps: own.smallCaps = values.smallCaps
        case .verticalPosition: own.verticalPosition = values.verticalPosition
        case .decorations: own.decorations = values.decorations
        case .shaping: own.graphite = values.graphite
        case .language: own.language = values.language
        case .hyphenates: own.hyphenates = values.hyphenates
        case .alignment: own.alignment = values.alignment
        case .leftIndent: own.leftIndent = values.leftIndent
        case .rightIndent: own.rightIndent = values.rightIndent
        case .firstLineIndent: own.firstLineIndent = values.firstLineIndent
        case .spaceBefore: own.spaceBefore = values.spaceBefore
        case .spaceAfter: own.spaceAfter = values.spaceAfter
        case .lineHeightMultiple: own.lineHeightMultiple = values.lineHeightMultiple
        case .lineSpacing: own.lineSpacing = values.lineSpacing
        case .list: own.listName = values.listName
        case .openingDistance: own.openingDistance = values.openingDistance
        case .keepWithNext, .keepTogether, .orphanLines, .widowLines, .nextLines, .previousLines:
            own.clear(property)
            own.keeping = property.only(values).keeping.over(own.keeping)
        }
        result.styles[position].values = own
        // Uguale a ciò che darebbe senza fissarlo: non lo fissa.
        let style = result.styles[position]
        if property.only(result.resolvedValues(of: name, target: style.target, base: base))
            == property.only(result.resolvedValues(of: style.basedOn, target: style.target, base: base)) {
            return result.resetting(property, inStyle: name)
        }
        return result
    }

    /// Lo stile senza il valore proprio della proprietà: torna a ereditarlo.
    public func resetting(_ property: InspectorProperty, inStyle name: String) -> StyleSheet {
        guard let position = styles.firstIndex(where: { $0.name == name }) else { return self }
        var result = self
        result.styles[position].formulas.removeAll { $0.operation.property.inspectorProperty == property }
        result.styles[position].values.clear(property)
        return result
    }

    /// Gli stili che si basano su questo, direttamente o attraverso altri.
    public func descendants(of name: String) -> Set<String> {
        var result: Set<String> = []
        var frontier: Set<String> = [name]
        while !frontier.isEmpty {
            let next = Set(styles.filter { $0.basedOn.map(frontier.contains) ?? false }.map(\.name))
            frontier = next.subtracting(result)
            result.formUnion(next)
        }
        return result
    }

    /// Gli stili su cui uno stile può basarsi: della stessa specie, né lui né uno che si basa su di lui (niente giri).
    public func possibleParents(of name: String) -> [String] {
        guard let style = style(named: name) else { return [] }
        let excluded = descendants(of: name).union([name])
        return styles.filter { $0.target == style.target && !excluded.contains($0.name) }.map(\.name)
    }

    /// Un nome libero: `base`, o `base 2`, `base 3`…
    public func freeName(_ base: String) -> String {
        guard style(named: base) != nil else { return base }
        var number = 2
        while style(named: "\(base) \(number)") != nil { number += 1 }
        return "\(base) \(number)"
    }
}

extension Document {
    /// Le definizioni con uno stile rinominato: gli stili che si basano su di lui, le regole e gli stili di flottante
    /// che lo nominano seguono il nome nuovo. Il testo lo riscrive chi chiama, con la stessa corrispondenza.
    public func renamingStyle(_ old: String, to new: String) -> Document {
        guard old != new, !new.isEmpty, styles.style(named: old) != nil, styles.style(named: new) == nil else { return self }
        var result = self
        for index in result.styles.styles.indices {
            if result.styles.styles[index].name == old { result.styles.styles[index].name = new }
            if result.styles.styles[index].basedOn == old { result.styles.styles[index].basedOn = new }
            result.styles.styles[index].formulas = result.styles.styles[index].formulas.map { formula in
                var changed = formula
                if case .firstAfter(old) = changed.when.position { changed.when.position = .firstAfter(new) }
                if case .styleName(old) = changed.operation.argument {
                    changed.operation = StylePropertyOperation(changed.operation.predicate, changed.operation.property, .styleName(new))
                }
                return changed
            }
            if result.styles.styles[index].values.nextStyle == old { result.styles.styles[index].values.nextStyle = new }
        }
        result.rules = rules.map { rule in
            var rule = rule
            if rule.styleName == old { rule.styleName = new }
            if rule.paragraphStyle == old { rule.paragraphStyle = new }
            if case .firstAfter(old) = rule.position { rule.position = .firstAfter(new) }
            return rule
        }
        for index in result.floatStyles.indices where result.floatStyles[index].contentStyle == old {
            result.floatStyles[index].contentStyle = new
        }
        return result
    }

    /// Le definizioni senza uno stile; regole, stili di flottante e stili che lo usavano passano allo stile su cui si
    /// basava (`replacement`, `nil` se nessuno), e così deve fare il testo, che riscrive chi chiama. Una regola che
    /// applicava proprio quello stile, o valeva dopo un paragrafo di quello stile, passa allo stile di base; se non c'è,
    /// si toglie.
    public func removingStyle(_ name: String) -> (document: Document, replacement: String?) {
        guard let style = styles.style(named: name) else { return (self, nil) }
        let parent = style.basedOn
        var result = self
        result.styles.styles.removeAll { $0.name == name }
        for index in result.styles.styles.indices where result.styles.styles[index].basedOn == name {
            result.styles.styles[index].basedOn = parent
        }
        for index in result.styles.styles.indices {
            result.styles.styles[index].formulas = result.styles.styles[index].formulas.compactMap { formula in
                var changed = formula
                if case .firstAfter(name) = changed.when.position {
                    guard let parent else { return nil }; changed.when.position = .firstAfter(parent)
                }
                if case .styleName(name) = changed.operation.argument {
                    if changed.operation.property == .applyStyle && parent == nil { return nil }
                    changed.operation = StylePropertyOperation(changed.operation.predicate, changed.operation.property, .styleName(parent))
                }
                return changed
            }
            if result.styles.styles[index].values.nextStyle == name { result.styles.styles[index].values.nextStyle = parent ?? "" }
        }
        result.rules = rules.compactMap { rule in
            var rule = rule
            if rule.styleName == name {
                guard let parent else { return nil }
                rule.styleName = parent
            }
            if rule.paragraphStyle == name { rule.paragraphStyle = parent }
            if case .firstAfter(name) = rule.position {
                guard let parent else { return nil }
                rule.position = .firstAfter(parent)
            }
            return rule
        }
        for index in result.floatStyles.indices where result.floatStyles[index].contentStyle == name {
            result.floatStyles[index].contentStyle = parent
        }
        return (result, parent)
    }
}
