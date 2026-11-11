import Foundation

/// Contratti delle dichiarazioni esprimibili nel formato 18.
public enum StyleDeclarationCatalog {
    public static func properties(for owner: StyleTarget) -> [StyleProperty] {
        StyleProperty.allCases.filter { $0.descriptor.accepts(owner: owner) }
    }

    /// Bersagli proposti quando si apre il menu. Le selezioni salvate si aggiungono dal foglio.
    public static let offeredTargets: [TextRule.Target] = [
        .paragraph, .firstLetter, .firstWords(2), .firstSentence, .firstLines(1), .lastLine,
        .words(.capitals), .words(.romanNumerals), .words(.numbers)
    ]

    public static let naturalMetrics = TextRule.Condition.Property.allCases
}

extension StyleProperty {
    struct Descriptor {
        enum Effect {
            case rendering, treatment, placement, assignment, paragraphCreation

            var isDirective: Bool {
                switch self {
                case .rendering, .treatment: false
                case .placement, .assignment, .paragraphCreation: true
                }
            }
        }

        let scope: StyleTarget
        let effect: Effect
        let initialArgument: StyleArgument
        let inspectorProperty: InspectorProperty?
        let permitsArithmetic: Bool

        init(_ scope: StyleTarget, _ argument: StyleArgument, _ inspector: InspectorProperty? = nil,
             effect: Effect = .rendering, permitsArithmetic: Bool = false) {
            self.scope = scope
            self.effect = effect
            self.initialArgument = argument
            self.inspectorProperty = inspector
            self.permitsArithmetic = permitsArithmetic
        }

        func accepts(owner: StyleTarget) -> Bool {
            switch scope {
            case .paragraph: owner == .paragraph
            case .word: owner != .character
            case .character: true
            }
        }
    }

    var descriptor: Descriptor {
        switch self {
        case .font: .init(.character, .font(.bold), .face, permitsArithmetic: true)
        case .size: .init(.character, .length(12, .points), .size, permitsArithmetic: true)
        case .spaceBefore: .init(.paragraph, .length(0, .points), .spaceBefore, permitsArithmetic: true)
        case .spaceAfter: .init(.paragraph, .length(0, .points), .spaceAfter, permitsArithmetic: true)
        case .firstLineIndent: .init(.paragraph, .length(0, .points), .firstLineIndent, permitsArithmetic: true)
        case .leftIndent: .init(.paragraph, .length(0, .points), .leftIndent, permitsArithmetic: true)
        case .rightIndent: .init(.paragraph, .length(0, .points), .rightIndent, permitsArithmetic: true)
        case .lineSpacing: .init(.paragraph, .length(0, .points), .lineSpacing, permitsArithmetic: true)
        case .alignment: .init(.paragraph, .alignment(.natural), .alignment)
        case .language: .init(.word, .language("it"), .language)
        case .family: .init(.character, .family("Hoefler Text"), .family)
        case .face: .init(.character, .face("HoeflerText-Regular"), .face)
        case .color: .init(.character, .color(nil), .color)
        case .smallCaps: .init(.character, .smallCaps(.lowercase), .smallCaps)
        case .hyphenates: .init(.word, .hyphenates(true), .hyphenates)
        case .pageStartSpacing: .init(.paragraph, .pageStart(.distance(72)), effect: .placement)
        case .openingDistance: .init(.paragraph, .length(0, .points), .openingDistance, effect: .placement)
        case .opensSection: .init(.paragraph, .text(Section.Role.chapter), effect: .assignment)
        case .nextStyle: .init(.paragraph, .styleName(nil), effect: .paragraphCreation)
        case .outlineLevel: .init(.paragraph, .integer(1), effect: .assignment)
        case .applyStyle: .init(.paragraph, .styleName("Strong"), effect: .treatment)
        case .keepWithNext: .init(.paragraph, .boolean(true), .keepWithNext, effect: .placement)
        case .keepTogether: .init(.paragraph, .boolean(true), .keepTogether, effect: .placement)
        case .orphanLines: .init(.paragraph, .integer(2), .orphanLines, effect: .placement)
        case .widowLines: .init(.paragraph, .integer(2), .widowLines, effect: .placement)
        case .nextLines: .init(.paragraph, .integer(2), .nextLines, effect: .placement)
        case .previousLines: .init(.paragraph, .integer(1), .previousLines, effect: .placement)
        }
    }

    public var initialArgument: StyleArgument { descriptor.initialArgument }
    public var isDirective: Bool { descriptor.effect.isDirective }
    public var predicates: [StylePredicate] { descriptor.permitsArithmetic ? [.set, .add, .subtract] : [.set] }

    var isParagraphProperty: Bool { descriptor.scope == .paragraph }
    var inspectorProperty: InspectorProperty? { descriptor.inspectorProperty }
}

extension StyleArgument {
    enum Kind {
        case font, length, alignment, language, family, face, color, smallCaps, hyphenates
        case pageStart, text, styleName, boolean, integer
    }

    var kind: Kind {
        switch self {
        case .font: .font
        case .length: .length
        case .alignment: .alignment
        case .language: .language
        case .family: .family
        case .face: .face
        case .color: .color
        case .smallCaps: .smallCaps
        case .hyphenates: .hyphenates
        case .pageStart: .pageStart
        case .text: .text
        case .styleName: .styleName
        case .boolean: .boolean
        case .integer: .integer
        }
    }

    var bindingType: FormulaValueType? {
        switch kind {
        case .length, .pageStart: .length
        case .integer: .number
        case .boolean, .hyphenates: .boolean
        default: nil
        }
    }
}
