import Foundation

/// Primo nodo eseguibile della formula di uno stile. Il destinatario è implicito
/// nel tipo dello stile; la proprietà determina se si opera sui caratteri o sul paragrafo.
public struct StyleFormula: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var binding: FormulaExpression?
    public var operation: StylePropertyOperation
    public var when: StyleCondition
    public var target: TextRule.Target

    public init(id: UUID = UUID(), operation: StylePropertyOperation, when: StyleCondition = StyleCondition(), target: TextRule.Target = .paragraph) {
        self.binding = nil
        self.when = when
        self.target = target
        self.id = id
        self.operation = operation
    }

    public func validate(for target: StyleTarget) throws {
        try StyleDeclaration(self).validate(for: target)
    }
}

/// Passaggi risolti dell'eredità. I valori storici vengono conservati come un
/// passaggio compatibile, seguito dalle formule esplicite dello stesso stile.
indirect enum StyleResolutionStep: Hashable, Sendable {
    case values(StyleValues)
    case formula(StyleFormula)
}

extension StyleValues {
    public func evaluatingFormulas(from input: StylePredicateState, resolver: FontRoleResolver = FontRoleResolver(), context: TextRule.ParagraphContext? = nil,
                                   facts: TextRule.NaturalFacts? = nil) throws -> StylePredicateState {
        try evaluate(from: input, resolver: resolver, context: context, facts: facts, observe: nil)
    }

    public func formulaTrace(from input: StylePredicateState, resolver: FontRoleResolver = FontRoleResolver(),
                             context: TextRule.ParagraphContext? = nil, facts: TextRule.NaturalFacts? = nil) throws -> [StyleFormulaTrace] {
        var trace: [StyleFormulaTrace] = []
        _ = try evaluate(from: input, resolver: resolver, context: context, facts: facts) { trace.append($0) }
        return trace
    }

    private func evaluate(from input: StylePredicateState, resolver: FontRoleResolver,
                          context: TextRule.ParagraphContext?, facts: TextRule.NaturalFacts?,
                          observe: ((StyleFormulaTrace) -> Void)?) throws -> StylePredicateState {
        guard !resolutionSteps.isEmpty else {
            var result = StylePredicateState(character: applied(to: input.character, resolver: resolver), paragraph: applied(to: input.paragraph))
            result.directives = directives(over: input.directives)
            return result
        }
        var active = self
        active.resolutionSteps = resolutionSteps.filter { step in
            guard case .formula(let formula) = step else { return true }
            return StyleDeclaration(formula).appliesToWholeParagraph(in: context, facts: facts)
        }
        let baseSteps = active.resolutionSteps.filter { step in
            if case .formula(let formula) = step { return !formula.isRuntimeRule }
            return true
        }
        let contextual = active.resolutionSteps.compactMap { step -> StyleResolutionStep? in
            if case .formula(let formula) = step, formula.isRuntimeRule { return step }
            return nil
        }.sorted { lhs, rhs in
            guard case .formula(let a) = lhs, case .formula(let b) = rhs else { return false }
            return a.phase < b.phase
        }
        active.resolutionSteps = baseSteps + contextual
        return try active.legacyFontSteps.reduce(input) { state, step in
            switch step {
            case .values(let values):
                var character = state.character
                if values.fontName != nil || values.family != nil || values.italic != nil || values.bold != nil { character.fontRole = nil }
                var result = StylePredicateState(character: values.applied(to: character, resolver: resolver), paragraph: values.applied(to: state.paragraph))
                result.directives = values.directives(over: state.directives)
                return result
            case .formula(let formula):
                let declaration = StyleDeclaration(formula)
                let result = try declaration.operation.applied(to: state, resolver: resolver)
                observe?(StyleFormulaTrace(id: declaration.id, input: state, output: result))
                return result
            }
        }
    }

    /// Quando si assegna uno stile, i suoi predicati sul font leggono il testo
    /// destinatario, comprese le scelte manuali. Le altre proprietà continuano
    /// a seguire la normale precedenza delle eccezioni locali.
    func fontFormulaResult(from input: CharacterStyle, resolver: FontRoleResolver) throws -> CharacterStyle? {
        let fontProperties: Set<StyleProperty> = [.font, .family, .face]
        guard resolutionSteps.contains(where: {
            if case .formula(let formula) = $0 { return formula.isStatic && fontProperties.contains(formula.operation.property) }
            return false
        }) else { return nil }
        var projection = self
        projection.resolutionSteps = resolutionSteps.filter {
            if case .formula(let formula) = $0 { return formula.isStatic && fontProperties.contains(formula.operation.property) }
            return true
        }
        return try projection.evaluatingFormulas(from: StylePredicateState(character: input), resolver: resolver).character
    }

    /// I campi storici del font si ereditano come un'unica dichiarazione anche
    /// quando fra due livelli compaiono formule per corpo o spazi. Un predicato
    /// esplicito Font/Famiglia interrompe questa fusione e mantiene il suo ordine.
    private var legacyFontSteps: [StyleResolutionStep] {
        var result: [StyleResolutionStep] = []
        var segment: [StyleResolutionStep] = []
        var font = StyleValues()
        func flush() {
            if font != StyleValues() { result.append(.values(font)) }
            result += segment
            segment = []
            font = StyleValues()
        }
        for step in resolutionSteps {
            switch step {
            case .formula(let formula) where [.font, .family, .face].contains(formula.operation.property):
                flush()
                result.append(step)
            case .values(var values):
                var fields = StyleValues()
                fields.fontName = values.fontName; values.fontName = nil
                fields.family = values.family; values.family = nil
                fields.italic = values.italic; values.italic = nil
                fields.bold = values.bold; values.bold = nil
                fields.features = values.features; values.features = nil
                fields.variations = values.variations; values.variations = nil
                fields.opticalSize = values.opticalSize; values.opticalSize = nil
                font = fields.over(font)
                segment.append(.values(values))
            default: segment.append(step)
            }
        }
        flush()
        return result
    }

    var withoutResolutionSteps: StyleValues {
        var copy = self
        copy.resolutionSteps = []
        return copy
    }
}

extension NamedStyle {
    public var declaredValues: StyleValues { declarations.withoutResolutionSteps }

    var declarations: StyleValues {
        var result = values
        for formula in formulas { formula.projectDirectives(into: &result) }
        if !formulas.isEmpty {
            var before = values.withoutResolutionSteps
            var details = StyleValues()
            // Assi, funzioni e corpo ottico dello stile valgono nel font che famiglia o faccia scelgono: vanno dopo quelle
            // formule, che altrimenti ricalcolerebbero il font e li cancellerebbero (il peso 600 portato nello stile).
            if formulas.contains(where: { [.face, .family].contains($0.operation.property) }) {
                details.features = before.features; before.features = nil
                details.variations = before.variations; before.variations = nil
                details.opticalSize = before.opticalSize; before.opticalSize = nil
            }
            result.resolutionSteps = [.values(before)] + formulas.map(StyleResolutionStep.formula)
            if details != StyleValues() { result.resolutionSteps.append(.values(details)) }
        }
        return result
    }

    func declares(_ property: InspectorProperty) -> Bool {
        property.isFixed(in: values.limited(to: target)) ||
            formulas.contains { !$0.isRuntimeRule && $0.operation.property.inspectorProperty == property }
    }
}
