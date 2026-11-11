import Foundation

extension StyleSheet {
    /// Compila le formule contestuali degli stili nelle regole del motore. La definizione resta nello stile; le regole e
    /// gli stili tecnici prodotti qui vivono solo nella composizione.
    public func compilingStyleRules() -> (sheet: StyleSheet, rules: [TextRule]) {
        // A ogni modifica la compilazione si chiede da più parti (impaginazione, regole, ispettore, fatti) con lo stesso
        // foglio: l'ultima si ricorda. Il confronto costa meno di un microsecondo, la compilazione millisecondi.
        CompilationCache.lock.lock()
        if let cached = CompilationCache.last {
            // Il foglio di partenza, o quello già compilato che l'impaginazione passa alle regole: compilarlo di nuovo
            // darebbe lo stesso risultato.
            if cached.sheet == self || cached.result.sheet == self {
                CompilationCache.lock.unlock()
                return cached.result
            }
        }
        CompilationCache.lock.unlock()
        let result = compilingStyleRulesUncached()
        CompilationCache.lock.lock()
        CompilationCache.last = (self, result)
        CompilationCache.lock.unlock()
        return result
    }

    private func compilingStyleRulesUncached() -> (sheet: StyleSheet, rules: [TextRule]) {
        // Le formule riutilizzabili si espandono prima. Se non si possono risolvere (un riferimento rotto: il file e il
        // compositore non lo lasciano entrare, ma un foglio costruito altrove sì), si compone senza espanderle; l'editor
        // lo segnala fra gli avvisi con `formulaReferenceProblem`.
        do {
            let resolved = try resolvingReusable()
            if resolved != self { return resolved.compilingStyleRulesUncached() }
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
                for formula in ancestor.formulas {
                    let declaration = StyleDeclaration(formula)
                    guard declaration.isRuntimeRule else { continue }
                    let rule = declaration.textRule(owner: style.name, declaredBy: ancestor.name)
                    if compiled.style(named: rule.styleName) == nil {
                        compiled.styles.append(declaration.treatment(named: rule.styleName, in: self))
                    }
                    generated.append(rule)
                }
            }
        }
        return (compiled, generated)
    }

    /// Riferimenti che il file e il compositore possono verificare dopo avere letto tutti gli stili.
    public func formulaReferenceProblem() -> String? {
        do { _ = try resolvingReusable() } catch { return reusableProblem(error) }
        let library = ReusableFormulaLibrary(definitions: reusableFormulas)
        for owner in styles {
            if let problem = owner.heading?.problem { return "“\(owner.name)”: " + problem }
            let names = owner.variables.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            if names.contains("") || Set(names).count != names.count {
                return "The variables of “\(owner.name)” need names that are not empty and all different."
            }
            for variable in owner.variables {
                do { _ = try library.evaluate(variable.expression.substitutingVariables(owner.variables)) }
                catch { return "The variable “\(variable.name)” of “\(owner.name)”: " + reusableProblem(error) }
            }
            if let next = owner.values.nextStyle, !next.isEmpty, style(named: next)?.target != .paragraph { return "The style after Return of “\(owner.name)” does not exist or is not a paragraph style." }
            for formula in owner.formulas {
                let declaration = StyleDeclaration(formula)
                if case .afterStyle(let name) = declaration.condition.position, style(named: name)?.target != .paragraph {
                    return "The condition of “\(owner.name)” refers to an unknown paragraph style: “\(name)”."
                }
                if case .namedSelection(let id) = declaration.target, !selections.contains(where: { $0.id == id }) {
                    return "The formula of “\(owner.name)” refers to a selection that does not exist."
                }
                if case .styleName(let name) = declaration.operation.argument, let name, !name.isEmpty {
                    guard let target = style(named: name) else { return "The style “\(name)” referred to by “\(owner.name)” does not exist." }
                    if declaration.operation.property == .nextStyle, target.target != .paragraph {
                        return "The style after Return must be a paragraph style."
                    }
                    if declaration.operation.property == .applyStyle {
                        if target.target == .paragraph && declaration.target != .paragraph { return "A paragraph style needs the whole paragraph." }
                        var next: String? = target.name; var seen: Set<String> = []
                        while let current = next, seen.insert(current).inserted, let inherited = style(named: current) {
                            if inherited.formulas.contains(where: \.isRuntimeRule) {
                                return "The treatment “\(name)” contains other contextual rules: choose a rendering-only style."
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

extension StyleDeclaration {
    /// Conserva separatamente il proprietario a cui si applica la formula e lo stile che la dichiara.
    func textRule(owner: String, declaredBy: String) -> TextRule {
        let ownerKey = Data(owner.utf8).base64EncodedString()
        let declarationKey = Data(declaredBy.utf8).base64EncodedString()
        let name = FormulaTreatment.name(owner: ownerKey, declaration: declarationKey, formula: id)
        var rule = TextRule(target: target.format18, paragraphStyle: owner, position: condition.position.format18,
                            condition: condition.naturalComparison, styleName: name)
        rule.formulaOwner = owner
        return rule
    }

    func treatment(named name: String, in sheet: StyleSheet) -> NamedStyle {
        if operation.property == .applyStyle, case .styleName(let reference) = operation.argument,
           let reference, let appearance = sheet.style(named: reference) {
            return NamedStyle(name: name, target: appearance.target, values: sheet.values(of: reference))
        }
        return NamedStyle(name: name, target: operation.property.descriptor.scope,
                          formulas: [StyleFormula(id: id, operation: operation)])
    }
}

/// L'ultima compilazione delle formule (vedi `compilingStyleRules`).
private enum CompilationCache {
    static let lock = NSLock()
    nonisolated(unsafe) static var last: (sheet: StyleSheet, result: (sheet: StyleSheet, rules: [TextRule]))?
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
