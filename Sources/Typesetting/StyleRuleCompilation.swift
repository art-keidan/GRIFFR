import Foundation

extension StyleSheet {
    /// Compila le formule di resa nel motore di regole esistente. La definizione
    /// resta nello stile; gli stili tecnici prodotti qui vivono solo nella composizione.
    public func compilingStyleRules(_ historical: [TextRule]) -> (sheet: StyleSheet, rules: [TextRule]) {
        // A ogni modifica la compilazione si chiede da più parti (impaginazione, regole, ispettore, fatti) con lo stesso
        // foglio: l'ultima si ricorda. Il confronto costa meno di un microsecondo, la compilazione millisecondi.
        CompilationCache.lock.lock()
        if let cached = CompilationCache.last {
            // Il foglio di partenza, o quello già compilato che l'impaginazione passa alle regole: compilarlo di nuovo
            // darebbe lo stesso risultato.
            if (cached.sheet == self && cached.historical == historical) ||
                (cached.result.sheet == self && cached.result.rules == historical) {
                CompilationCache.lock.unlock()
                return cached.result
            }
        }
        CompilationCache.lock.unlock()
        let result = compilingStyleRulesUncached(historical)
        CompilationCache.lock.lock()
        CompilationCache.last = (self, historical, result)
        CompilationCache.lock.unlock()
        return result
    }

    private func compilingStyleRulesUncached(_ historical: [TextRule]) -> (sheet: StyleSheet, rules: [TextRule]) {
        // Le formule riutilizzabili si espandono prima. Se non si possono risolvere (un riferimento rotto: il file e il
        // compositore non lo lasciano entrare, ma un foglio costruito altrove sì), si compone senza espanderle; l'editor
        // lo segnala fra gli avvisi con `formulaReferenceProblem`.
        do {
            let resolved = try resolvingReusable()
            if resolved != self { return resolved.compilingStyleRulesUncached(historical) }
        } catch {}
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
                    let name = FormulaTreatment.name(owner: ownerKey, declaration: declarationKey, formula: formula.id)
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

/// L'ultima compilazione delle formule (vedi `compilingStyleRules`).
private enum CompilationCache {
    static let lock = NSLock()
    nonisolated(unsafe) static var last: (sheet: StyleSheet, historical: [TextRule], result: (sheet: StyleSheet, rules: [TextRule]))?
}

/// Gli stili tecnici che la compilazione delle formule aggiunge al foglio: vivono solo nella composizione, mai nel file
/// né nei menu. Il nome comincia con un carattere dell'area privata, che nessuno stile dell'autore usa.
public enum FormulaTreatment {
    static let prefix = "\u{F000}formula:"

    static func name(owner: String, declaration: String, formula: UUID) -> String {
        prefix + owner + ":" + declaration + ":" + formula.uuidString
    }

    /// Vero per uno stile prodotto dalla compilazione: si applica sul testo così com'è, non come differenza dallo stile
    /// del paragrafo.
    public static func isTreatment(_ name: String) -> Bool { name.hasPrefix(prefix) }
}
