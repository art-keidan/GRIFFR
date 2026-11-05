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
        let property = operation.property
        if (!when.isAlways || self.target != .paragraph || property == .applyStyle), target != .paragraph {
            throw StylePredicateError.incompatibleArgument(property)
        }
        if property.isDirective {
            guard self.target == .paragraph,
                (property == .pageStartSpacing ? when.measurement == nil && (when.position == .any || when.position == .firstOnPage) : when.isAlways) else {
                throw StylePredicateError.incompatibleArgument(property)
            }
        }
        if let measurement = when.measurement, !measurement.value.isFinite || measurement.value < 0 { throw StylePredicateError.incompatibleArgument(property) }
        switch self.target {
        case .firstWords(let count), .firstLines(let count): guard count > 0 else { throw StylePredicateError.incompatibleArgument(property) }
        case .words(.listed(let words)): guard !words.isEmpty && words.allSatisfy({ !$0.isEmpty }) else { throw StylePredicateError.incompatibleArgument(property) }
        default: break
        }
        if self.target != .paragraph, property.isParagraphProperty && property != .applyStyle { throw StylePredicateError.incompatibleArgument(property) }
        if (target != .paragraph && property.isParagraphProperty) ||
            (target == .character && [.language, .hyphenates].contains(property)) {
            throw StylePredicateError.incompatibleArgument(property)
        }
        guard property.predicates.contains(operation.predicate) else {
            throw StylePredicateError.unsupportedPredicate(operation.predicate, property)
        }
        switch (property, operation.argument) {
        case (.pageStartSpacing, .pageStart(let value)):
            if case .distance(let distance) = value, !distance.isFinite || distance < 0 { throw StylePredicateError.invalidLength(property) }
        case (.opensSection, .text(let role)):
            guard !role.contains("\n") && !role.contains("\r") else { throw StylePredicateError.incompatibleArgument(property) }
        case (.nextStyle, .styleName(let name)):
            if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw StylePredicateError.incompatibleArgument(property) }
        case (.applyStyle, .styleName(let name)):
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StylePredicateError.incompatibleArgument(property) }
        case (.keepWithNext, .boolean), (.keepTogether, .boolean): break
        case (.outlineLevel, .integer(let level)):
            guard (0...99).contains(level) else { throw StylePredicateError.incompatibleArgument(property) }
        case (.orphanLines, .integer(let count)), (.widowLines, .integer(let count)):
            guard (1...9).contains(count) else { throw StylePredicateError.incompatibleArgument(property) }
        case (.font, .font), (.alignment, .alignment), (.language, .language), (.smallCaps, .smallCaps), (.hyphenates, .hyphenates): break
        case (.family, .family(let name)), (.face, .face(let name)):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StylePredicateError.incompatibleArgument(property) }
        case (.color, .color(let color)):
            if let color {
                guard color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw StylePredicateError.incompatibleArgument(property) }
            }
        case (_, .length(let amount, let unit)) where [.size, .spaceBefore, .spaceAfter, .firstLineIndent, .leftIndent, .rightIndent, .lineSpacing, .openingDistance].contains(property):
            guard amount.isFinite, (amount * unit.points).isFinite else { throw StylePredicateError.invalidLength(property) }
            if operation.predicate == .set {
                let positive = property == .size
                let signed = [.leftIndent, .rightIndent, .firstLineIndent].contains(property)
                guard signed || (positive ? amount > 0 : amount >= 0) else { throw StylePredicateError.invalidLength(property) }
            }
        default: throw StylePredicateError.incompatibleArgument(property)
        }
    }
}

extension StyleProperty {
    var isParagraphProperty: Bool {
        switch self {
        case .font, .size, .language, .family, .face, .color, .smallCaps, .hyphenates: false
        default: true
        }
    }

    var inspectorProperty: InspectorProperty? {
        switch self {
        case .pageStartSpacing, .opensSection, .nextStyle, .outlineLevel, .applyStyle: nil
        case .openingDistance: .openingDistance
        case .keepWithNext: .keepWithNext
        case .keepTogether: .keepTogether
        case .orphanLines: .orphanLines
        case .widowLines: .widowLines
        case .family: .family
        case .face: .face
        case .color: .color
        case .smallCaps: .smallCaps
        case .hyphenates: .hyphenates
        case .font: .face
        case .size: .size
        case .language: .language
        case .alignment: .alignment
        case .spaceBefore: .spaceBefore
        case .spaceAfter: .spaceAfter
        case .firstLineIndent: .firstLineIndent
        case .leftIndent: .leftIndent
        case .rightIndent: .rightIndent
        case .lineSpacing: .lineSpacing
        }
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
            return formula.target == .paragraph && formula.operation.property != .applyStyle && formula.when.holds(in: context, facts: facts)
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
                guard formula.target == .paragraph, formula.operation.property != .applyStyle,
                      formula.when.holds(in: context, facts: facts) else { return state }
                let result = try formula.operation.applied(to: state, resolver: resolver)
                observe?(StyleFormulaTrace(id: formula.id, input: state, output: result))
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
            if formulas.contains(where: { $0.operation.property == .face }) {
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
