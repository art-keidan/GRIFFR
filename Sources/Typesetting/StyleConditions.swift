import Foundation

/// La stessa condizione alimenta formule degli stili e regole storiche.
/// Le misure geometriche si leggono dalla composizione naturale, prima degli effetti.
public struct StyleCondition: Hashable, Sendable {
    public var position: TextRule.Position
    public var measurement: TextRule.Condition?

    public init(position: TextRule.Position = .any, measurement: TextRule.Condition? = nil) {
        self.position = position
        self.measurement = measurement
    }

    public var isAlways: Bool { StyleDeclaration.Condition(self).isAlways }
    public var dependsOnLayout: Bool { StyleDeclaration.Condition(self).dependsOnLayout }

    public func holds(in context: TextRule.ParagraphContext?, facts: TextRule.NaturalFacts? = nil) -> Bool {
        StyleDeclaration.Condition(self).holds(in: context, facts: facts)
    }
}

public struct StyleDirectives: Equatable, Sendable {
    public var pageStartSpacing: PageStartSpacing?
    public var openingDistance: Double?
    public var opensSection: String?
    public var nextStyle: String?
    public var applyingStyle: String?
    public var keeping = LineKeeping()
    public init() {}
}

extension StyleFormula {
    public var isStatic: Bool { StyleDeclaration(self).isStatic }
    public var isPageStartDirective: Bool { operation.property == .pageStartSpacing }
    public var isRuntimeRule: Bool { StyleDeclaration(self).isRuntimeRule }

    /// Solo le richieste dichiarative: l'impaginazione e gli eventi di scrittura
    /// continuano a risolverle nella fase appropriata.
    func projectDirectives(into values: inout StyleValues) {
        guard isStatic || isPageStartDirective else { return }
        switch (operation.property, operation.argument) {
        case (.pageStartSpacing, .pageStart(let spacing)): values.pageStartSpacing = spacing
        case (.openingDistance, .length(let number, let unit)): values.openingDistance = number * unit.points
        case (.opensSection, .text(let role)): values.opensSection = role
        case (.nextStyle, .styleName(let name)): values.nextStyle = name ?? ""
        case (.outlineLevel, .integer(let level)): values.outlineLevel = level
        case (.keepWithNext, .boolean(let enabled)): values.keeping.withNext = enabled
        case (.keepTogether, .boolean(let enabled)): values.keeping.together = enabled
        case (.orphanLines, .integer(let count)): values.keeping.linesAtEnd = count
        case (.widowLines, .integer(let count)): values.keeping.linesAtStart = count
        case (.nextLines, .integer(let count)): values.keeping.nextLines = count
        case (.previousLines, .integer(let count)): values.keeping.previousLines = count
        default: break
        }
    }
}

extension StyleValues {
    func directives(over input: StyleDirectives) -> StyleDirectives {
        var result = input
        if let pageStartSpacing { result.pageStartSpacing = pageStartSpacing }
        if let openingDistance { result.openingDistance = openingDistance }
        if let opensSection { result.opensSection = opensSection }
        if let nextStyle { result.nextStyle = nextStyle }
        result.keeping = keeping.over(input.keeping)
        return result
    }

    mutating func clearDirective(_ property: StyleProperty) {
        switch property {
        case .pageStartSpacing: pageStartSpacing = nil
        case .openingDistance: openingDistance = nil
        case .opensSection: opensSection = nil
        case .nextStyle: nextStyle = nil
        case .outlineLevel: outlineLevel = nil
        case .keepWithNext: keeping.withNext = nil
        case .keepTogether: keeping.together = nil
        case .orphanLines: keeping.linesAtEnd = nil
        case .widowLines: keeping.linesAtStart = nil
        case .nextLines: keeping.nextLines = nil
        case .previousLines: keeping.previousLines = nil
        default: break
        }
    }
}

extension StyleSheet {
    public func settingDirective(_ property: StyleProperty, argument: StyleArgument?, inStyle name: String) -> StyleSheet {
        guard property.isDirective, let i = styles.firstIndex(where: { $0.name == name }), styles[i].target == .paragraph else { return self }
        var result = self
        let old = styles[i].formulas.first { $0.operation.property == property }
        result.styles[i].values.clearDirective(property)
        result.styles[i].formulas.removeAll { $0.operation.property == property }
        if let argument {
            let formula = StyleFormula(id: old?.id ?? UUID(), operation: StylePropertyOperation(.set, property, argument),
                when: property == .pageStartSpacing ? StyleCondition(position: .firstOnPage) : StyleCondition())
            guard (try? formula.validate(for: .paragraph)) != nil else { return self }
            result.styles[i].formulas.append(formula)
        }
        return result
    }
}

extension StyleCondition {
    public var summary: String {
        var parts: [String] = []
        switch position {
        case .any: break
        case .sequenceStart: parts.append("sequence start")
        case .firstOnPage: parts.append("first on page")
        case .firstAfter(let name): parts.append("after “" + name + "”")
        }
        if let measurement { parts.append(measurement.summary) }
        return parts.isEmpty ? "Always" : parts.joined(separator: " and ")
    }

    public static func previewFacts(_ sample: String, lines: Int, lastLineFill: Double, hyphens: Int) -> TextRule.NaturalFacts {
        let text = NSAttributedString(string: sample)
        return TextRule.NaturalFacts(lineCount: lines, wordCount: BodyText(text, paragraph: NSRange(location: 0, length: text.length)).wordCount,
            lastLineFill: lastLineFill / 100, hyphenatedLines: hyphens)
    }
}

public enum StyleFormulaPhase: Int, Comparable, Sendable {
    case base, placement, textContext, composition, assignment, paragraphCreation
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension StyleFormula {
    public var phase: StyleFormulaPhase { StyleDeclaration(self).phase }
}

public struct StyleFormulaTrace: Sendable {
    public var id: UUID
    public var input: StylePredicateState
    public var output: StylePredicateState
}
