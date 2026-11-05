import Foundation

extension StyleSheet {
    /// Compila le formule di resa nel motore di regole esistente. La definizione
    /// resta nello stile; gli stili tecnici prodotti qui vivono solo nella composizione.
    public func compilingStyleRules(_ historical: [TextRule]) -> (sheet: StyleSheet, rules: [TextRule]) {
        if let resolved = try? resolvingReusable(), resolved != self { return resolved.compilingStyleRules(historical) }
        var compiled = self
        var generated: [TextRule] = []
        for style in styles where style.target == .paragraph {
            // L'eredità mantiene l'ordine della catena, poi l'ordine delle formule.
            var chain: [NamedStyle] = []; var next: String? = style.name; var seen: Set<String> = []
            while let name = next, seen.insert(name).inserted, let item = self.style(named: name) {
                chain.append(item); next = item.basedOn
            }
            for ancestor in chain.reversed() {
                for formula in ancestor.formulas where formula.isRuntimeRule {
                    let ownerKey = Data(style.name.utf8).base64EncodedString()
                    let declarationKey = Data(ancestor.name.utf8).base64EncodedString()
                    let name = "\u{F000}formula:" + ownerKey + ":" + declarationKey + ":" + formula.id.uuidString
                    if compiled.style(named: name) == nil {
                        if formula.operation.property == .applyStyle, case .styleName(let reference) = formula.operation.argument,
                           let reference, let appearance = self.style(named: reference) {
                            compiled.styles.append(NamedStyle(name: name, target: appearance.target, values: values(of: reference)))
                        } else {
                            let operation = StyleFormula(id: formula.id, operation: formula.operation)
                            compiled.styles.append(NamedStyle(name: name, target: formula.operation.property.isParagraphProperty ? .paragraph : ([StyleProperty.language, .hyphenates].contains(formula.operation.property) ? .word : .character), formulas: [operation]))
                        }
                    }
                    var rule = TextRule(target: formula.target, paragraphStyle: style.name, position: formula.when.position,
                        condition: formula.when.measurement, styleName: name)
                    rule.formulaOwner = style.name
                    generated.append(rule)
                }
            }
        }
        return (compiled, historical.filter { $0.formulaOwner == nil } + generated)
    }

    /// Riferimenti che il file e il compositore possono verificare dopo avere letto tutti gli stili.
    public func formulaReferenceProblem() -> String? {
        do { _ = try resolvingReusable() } catch { return reusableProblem(error) }
        for owner in styles {
            if let next = owner.values.nextStyle, !next.isEmpty, style(named: next)?.target != .paragraph { return "Lo stile dopo Invio di «\(owner.name)» non esiste o non è di paragrafo." }
            for formula in owner.formulas {
                if case .firstAfter(let name) = formula.when.position, style(named: name)?.target != .paragraph {
                    return "La condizione di «\(owner.name)» richiama un paragrafo sconosciuto: «\(name)»."
                }
                if case .selection(let id) = formula.target, !selections.contains(where: { $0.id == id }) {
                    return "La formula di «\(owner.name)» richiama una selezione inesistente."
                }
                if case .styleName(let name) = formula.operation.argument, let name, !name.isEmpty {
                    guard let target = style(named: name) else { return "Lo stile «\(name)» richiamato da «\(owner.name)» non esiste." }
                    if formula.operation.property == .nextStyle, target.target != .paragraph {
                        return "Lo stile dopo Invio deve essere uno stile di paragrafo."
                    }
                    if formula.operation.property == .applyStyle {
                        if target.target == .paragraph && formula.target != .paragraph { return "Uno stile di paragrafo richiede il paragrafo intero." }
                        var next: String? = target.name; var seen: Set<String> = []
                        while let current = next, seen.insert(current).inserted, let inherited = style(named: current) {
                            if inherited.formulas.contains(where: \.isRuntimeRule) {
                                return "Il trattamento «\(name)» contiene altre regole contestuali: scegli uno stile di sola resa."
                            }
                            next = inherited.basedOn
                        }
                    }
                }
            }
        }
        return nil
    }
}
