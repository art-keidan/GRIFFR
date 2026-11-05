import Foundation

/// Contratti dei predicati con effetto. Gli argomenti restano distinti dal predicato.
public enum StylePredicate: String, CaseIterable, Hashable, Sendable {
    case set, add, subtract
}

public enum StyleProperty: String, CaseIterable, Hashable, Sendable {
    case font, size, spaceBefore, spaceAfter, firstLineIndent, leftIndent, rightIndent, lineSpacing
    case alignment, language, family, face, color, smallCaps, hyphenates
    case pageStartSpacing, openingDistance, opensSection, nextStyle, outlineLevel, applyStyle
    case keepWithNext, keepTogether, orphanLines, widowLines

    public var predicates: [StylePredicate] {
        if isDirective || self == .applyStyle { return [.set] }
        return switch self {
        case .alignment, .language, .family, .face, .color, .smallCaps, .hyphenates: [.set]
        default: [.set, .add, .subtract]
        }
    }

    fileprivate var paragraphLength: WritableKeyPath<ParagraphStyle, Double>? {
        switch self {
        case .spaceBefore: \.spaceBefore
        case .spaceAfter: \.spaceAfter
        case .firstLineIndent: \.firstLineIndent
        case .leftIndent: \.leftIndent
        case .rightIndent: \.rightIndent
        case .lineSpacing: \.lineSpacing
        default: nil
        }
    }
}

public enum StyleArgument: Hashable, Sendable {
    case font(FontRole)
    case length(Double, LengthUnit)
    case alignment(ParagraphStyle.Alignment)
    case language(String?)
    case family(String)
    case face(String)
    case color(String?)
    case smallCaps(SmallCaps)
    case hyphenates(Bool)
    case pageStart(PageStartSpacing)
    case text(String)
    case styleName(String?)
    case boolean(Bool)
    case integer(Int)
}

/// Uno stato di valutazione risolto, distinto dalla definizione salvata dello stile.
public struct StylePredicateState: Equatable, Sendable {
    public var character: CharacterStyle
    public var paragraph: ParagraphStyle
    public var directives = StyleDirectives()

    public init(character: CharacterStyle, paragraph: ParagraphStyle = ParagraphStyle()) {
        self.character = character
        self.paragraph = paragraph
    }
}

public enum StylePredicateError: Error, Equatable, Sendable {
    case unsupportedPredicate(StylePredicate, StyleProperty)
    case incompatibleArgument(StyleProperty)
    case invalidLength(StyleProperty)
    case unknownFontRole(String)
    case unavailableFontRole(FontRole)
}

/// Una singola operazione. La sequenza riceve sempre un ingresso esplicito:
/// la ricomposizione valuta di nuovo la sequenza sullo stesso ingresso.
public struct StylePropertyOperation: Hashable, Sendable {
    public let predicate: StylePredicate
    public let property: StyleProperty
    public let argument: StyleArgument

    public init(_ predicate: StylePredicate, _ property: StyleProperty, _ argument: StyleArgument) {
        self.predicate = predicate
        self.property = property
        self.argument = argument
    }

    public func applied(to input: StylePredicateState, resolver: FontRoleResolver = FontRoleResolver()) throws -> StylePredicateState {
        guard property.predicates.contains(predicate) else {
            throw StylePredicateError.unsupportedPredicate(predicate, property)
        }
        var output = input
        switch (property, argument) {
        case (.pageStartSpacing, .pageStart(let spacing)):
            if case .distance(let points) = spacing, !points.isFinite || points < 0 { throw StylePredicateError.invalidLength(property) }
            output.directives.pageStartSpacing = spacing
        case (.openingDistance, .length(let value, let unit)):
            output.directives.openingDistance = try length(value, unit: unit, current: input.directives.openingDistance ?? 0)
        case (.opensSection, .text(let role)): output.directives.opensSection = role
        case (.nextStyle, .styleName(let name)): output.directives.nextStyle = name ?? ""
        case (.applyStyle, .styleName(let name)):
            guard let name, !name.isEmpty else { throw StylePredicateError.incompatibleArgument(property) }
            output.directives.applyingStyle = name
        case (.outlineLevel, .integer(let level)):
            guard level >= 0 else { throw StylePredicateError.incompatibleArgument(property) }
            output.paragraph.outlineLevel = level > 0 ? level : nil
        case (.keepWithNext, .boolean(let enabled)): output.directives.keeping.withNext = enabled
        case (.keepTogether, .boolean(let enabled)): output.directives.keeping.together = enabled
        case (.orphanLines, .integer(let count)), (.widowLines, .integer(let count)):
            guard (1...9).contains(count) else { throw StylePredicateError.incompatibleArgument(property) }
            if property == .orphanLines { output.directives.keeping.linesAtEnd = count } else { output.directives.keeping.linesAtStart = count }
        case (.font, .font(let requested)):
            var role = requested
            if predicate != .set {
                // Il tondo non contiene tratti da aggiungere o sottrarre.
                if requested == .regular { return input }
                let current: FontRole
                if let known = resolver.role(of: input.character) {
                    current = known
                } else if let face = FontFaces.description(of: input.character.fontName) {
                    current = FontRole(italic: face.italic, bold: face.bold)
                } else {
                    throw StylePredicateError.unknownFontRole(input.character.fontName)
                }
                if predicate == .add {
                    role = FontRole(italic: current.isItalic || requested.isItalic,
                                    bold: current.isBold || requested.isBold)
                } else {
                    role = FontRole(italic: current.isItalic && !requested.isItalic,
                                    bold: current.isBold && !requested.isBold)
                }
                if role == current { return input }
            }
            // Modificare soltanto il corsivo a una faccia libera ne conserva il peso.
            let keepingWeight = predicate != .set && requested == .italic
            guard let resolved = resolver.applying(role: role, to: input.character, keepingWeight: keepingWeight) else {
                throw StylePredicateError.unavailableFontRole(role)
            }
            output.character = resolved

        case (.size, .length(let value, let unit)):
            output.character.size = try length(value, unit: unit, current: input.character.size, positive: true)

        case (.face, .face(let name)):
            guard !name.isEmpty else { throw StylePredicateError.incompatibleArgument(.face) }
            var values = StyleValues(); values.fontName = name
            output.character = values.applied(to: input.character, resolver: resolver)
        case (.family, .family(let family)):
            guard !family.isEmpty else { throw StylePredicateError.incompatibleArgument(.family) }
            var values = StyleValues()
            values.family = family
            output.character = values.applied(to: input.character, resolver: resolver)
        case (.color, .color(let color)): output.character.color = color
        case (.smallCaps, .smallCaps(let mode)): output.character.smallCaps = mode
        case (.hyphenates, .hyphenates(let enabled)): output.character.hyphenates = enabled
        case (.alignment, .alignment(let alignment)):
            output.paragraph.alignment = alignment

        case (.language, .language(let language)):
            output.character.language = language

        case (_, .length(let value, let unit)):
            guard let path = property.paragraphLength else {
                throw StylePredicateError.incompatibleArgument(property)
            }
            // I rientri possono essere negativi. Spazi e interlinea seguono
            // il contratto delle misure non negative già offerto dall'editor.
            let isIndent = [.firstLineIndent, .leftIndent, .rightIndent].contains(property)
            output.paragraph[keyPath: path] = try length(value, unit: unit, current: input.paragraph[keyPath: path],
                                                         allowsNegative: isIndent)

        default:
            throw StylePredicateError.incompatibleArgument(property)
        }
        return output
    }

    private func length(_ value: Double, unit: LengthUnit, current: Double,
                        positive: Bool = false, allowsNegative: Bool = false) throws -> Double {
        let points = value * unit.points
        let result: Double
        switch predicate {
        case .set: result = points
        case .add: result = current + points
        case .subtract: result = current - points
        }
        guard value.isFinite, points.isFinite, result.isFinite,
              (allowsNegative || result >= 0), (!positive || result > 0) else {
            throw StylePredicateError.invalidLength(property)
        }
        return result
    }

    public static func evaluate(_ operations: [StylePropertyOperation], from input: StylePredicateState,
                                resolver: FontRoleResolver = FontRoleResolver()) throws -> StylePredicateState {
        try operations.reduce(input) { try $1.applied(to: $0, resolver: resolver) }
    }
}
