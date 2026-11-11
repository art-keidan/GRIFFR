import Foundation

/// Dichiarazione eseguibile del compositore. Il formato 18 e il backend TextRule
/// usano i rispettivi adattatori; il significato di percorso, condizione ed effetto è qui.
struct StyleDeclaration: Hashable, Sendable {
    let id: UUID
    let target: Target
    let condition: Condition
    let operation: StylePropertyOperation
    let binding: FormulaExpression?

    init(_ formula: StyleFormula) {
        id = formula.id
        target = Target(formula.target)
        condition = Condition(formula.when)
        operation = formula.operation
        binding = formula.binding
    }

    init(id: UUID, target: Target, condition: Condition, operation: StylePropertyOperation, binding: FormulaExpression?) {
        self.id = id
        self.target = target
        self.condition = condition
        self.operation = operation
        self.binding = binding
    }

    func appliesToWholeParagraph(in context: TextRule.ParagraphContext?, facts: TextRule.NaturalFacts?) -> Bool {
        target == .paragraph && operation.property != .applyStyle && condition.holds(in: context, facts: facts)
    }

    var format18: StyleFormula {
        var formula = StyleFormula(id: id, operation: operation, when: condition.format18, target: target.format18)
        formula.binding = binding
        return formula
    }

    var isStatic: Bool { condition.isAlways && target == .paragraph && operation.property != .applyStyle }
    var isRuntimeRule: Bool { !operation.property.isDirective && !isStatic }

    var phase: StyleFormulaPhase {
        switch operation.property.descriptor.effect {
        case .placement: .placement
        case .assignment: .assignment
        case .paragraphCreation: .paragraphCreation
        case .rendering, .treatment:
            if isStatic { .base }
            else if condition.dependsOnLayout || target.isLineTarget { .composition }
            else { .textContext }
        }
    }

    enum Target: Hashable, Sendable {
        case paragraph
        case openingLetter
        case firstWordRange(Int)
        case namedSelection(UUID)
        case firstSentence
        case matchingWords(TextRule.WordPattern)
        case firstLineRanges(Int)
        case lastLineRange

        init(_ target: TextRule.Target) {
            self = switch target {
            case .paragraph: .paragraph
            case .firstLetter: .openingLetter
            case .firstWords(let count): .firstWordRange(count)
            case .selection(let id): .namedSelection(id)
            case .firstSentence: .firstSentence
            case .words(let pattern): .matchingWords(pattern)
            case .firstLines(let count): .firstLineRanges(count)
            case .lastLine: .lastLineRange
            }
        }

        var format18: TextRule.Target {
            switch self {
            case .paragraph: .paragraph
            case .openingLetter: .firstLetter
            case .firstWordRange(let count): .firstWords(count)
            case .namedSelection(let id): .selection(id)
            case .firstSentence: .firstSentence
            case .matchingWords(let pattern): .words(pattern)
            case .firstLineRanges(let count): .firstLines(count)
            case .lastLineRange: .lastLine
            }
        }

        var isLineTarget: Bool {
            switch self {
            case .firstLineRanges, .lastLineRange: true
            default: false
            }
        }
    }

    struct Condition: Hashable, Sendable {
        enum Position: Hashable, Sendable {
            case anywhere
            case afterStyle(String)
            case opensSequence
            case opensNaturalPage

            init(_ position: TextRule.Position) {
                self = switch position {
                case .any: .anywhere
                case .firstAfter(let name): .afterStyle(name)
                case .sequenceStart: .opensSequence
                case .firstOnPage: .opensNaturalPage
                }
            }

            var format18: TextRule.Position {
                switch self {
                case .anywhere: .any
                case .afterStyle(let name): .firstAfter(name)
                case .opensSequence: .sequenceStart
                case .opensNaturalPage: .firstOnPage
                }
            }
        }

        let position: Position
        /// Secondo operando della congiunzione. Legge esclusivamente i fatti naturali.
        let naturalComparison: TextRule.Condition?

        init(_ condition: StyleCondition) {
            position = Position(condition.position)
            naturalComparison = condition.measurement
        }

        var format18: StyleCondition { StyleCondition(position: position.format18, measurement: naturalComparison) }
        var isAlways: Bool { position == .anywhere && naturalComparison == nil }
        var dependsOnLayout: Bool { position == .opensNaturalPage || naturalComparison != nil }

        func holds(in context: TextRule.ParagraphContext?, facts: TextRule.NaturalFacts?) -> Bool {
            switch position {
            case .anywhere: break
            case .afterStyle(let name):
                guard let context, context.previousStyleName == name && !context.isSequenceStart else { return false }
            case .opensSequence: guard context?.isSequenceStart == true else { return false }
            case .opensNaturalPage: guard context?.isFirstOnPage == true else { return false }
            }
            guard let naturalComparison else { return true }
            guard let facts else { return false }
            return naturalComparison.holds(for: facts)
        }
    }
}

extension StyleDeclaration {
    func validate(for owner: StyleTarget) throws {
        let property = operation.property
        let descriptor = property.descriptor
        if !isStatic, owner != .paragraph {
            throw StylePredicateError.incompatibleArgument(property)
        }
        if property.isDirective {
            guard self.target == .paragraph,
                (property == .pageStartSpacing ? condition.naturalComparison == nil && (condition.position == .anywhere || condition.position == .opensNaturalPage) : condition.isAlways) else {
                throw StylePredicateError.incompatibleArgument(property)
            }
        }
        if let measurement = condition.naturalComparison, !measurement.value.isFinite || measurement.value < 0 { throw StylePredicateError.incompatibleArgument(property) }
        switch self.target {
        case .firstWordRange(let count), .firstLineRanges(let count): guard count > 0 else { throw StylePredicateError.incompatibleArgument(property) }
        case .matchingWords(.listed(let words)): guard !words.isEmpty && words.allSatisfy({ !$0.isEmpty }) else { throw StylePredicateError.incompatibleArgument(property) }
        default: break
        }
        if self.target != .paragraph, property.isParagraphProperty && property != .applyStyle { throw StylePredicateError.incompatibleArgument(property) }
        if !descriptor.accepts(owner: owner) {
            throw StylePredicateError.incompatibleArgument(property)
        }
        guard property.predicates.contains(operation.predicate) else {
            throw StylePredicateError.unsupportedPredicate(operation.predicate, property)
        }
        guard operation.argument.kind == descriptor.initialArgument.kind else {
            throw StylePredicateError.incompatibleArgument(property)
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
        case (.outlineLevel, .integer(let level)):
            guard (0...99).contains(level) else { throw StylePredicateError.incompatibleArgument(property) }
        case (.orphanLines, .integer(let count)), (.widowLines, .integer(let count)), (.nextLines, .integer(let count)):
            guard (1...9).contains(count) else { throw StylePredicateError.incompatibleArgument(property) }
        case (.previousLines, .integer(let count)):
            guard LineKeeping.previousRange.contains(count) else { throw StylePredicateError.incompatibleArgument(property) }
        case (.family, .family(let name)), (.face, .face(let name)):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StylePredicateError.incompatibleArgument(property) }
        case (.color, .color(let color)):
            if let color {
                guard color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw StylePredicateError.incompatibleArgument(property) }
            }
        case (_, .length(let amount, let unit)):
            guard amount.isFinite, (amount * unit.points).isFinite else { throw StylePredicateError.invalidLength(property) }
            if operation.predicate == .set {
                let positive = property == .size
                let signed = [.leftIndent, .rightIndent, .firstLineIndent].contains(property)
                guard signed || (positive ? amount > 0 : amount >= 0) else { throw StylePredicateError.invalidLength(property) }
            }
        default: break
        }
    }
}
