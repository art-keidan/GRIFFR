import Foundation
import AppKit

/// La dichiarazione che alimenta un controllo, con il proprietario reale anche
/// quando la formula è ereditata. Più operazioni o un predicato relativo richiedono
/// una scelta esplicita prima di diventare un valore fisso.
public struct StyleFormulaDefinition: Equatable, Sendable {
    public var calculation: String? = nil
    public var owner: String
    public var formulas: [StyleFormula]
    public var isCalculated: Bool {
        formulas.count != 1 || formulas.first?.operation.predicate != .set || formulas.contains { $0.binding != nil || !$0.when.isAlways || $0.target != .paragraph }
    }
}

extension StyleSheet {
    public func formulaDefinition(for property: InspectorProperty, inStyle name: String) -> StyleFormulaDefinition? {
        var next: String? = name
        var seen: Set<String> = []
        while let name = next, seen.insert(name).inserted, let style = style(named: name) {
            let formulas = style.formulas.filter { $0.operation.property.inspectorProperty == property }
            if !formulas.isEmpty { return StyleFormulaDefinition(calculation: formulas.contains { $0.binding != nil } ? formulas.compactMap { $0.binding?.summary(in: reusableFormulas) }.joined(separator: "; ") : nil, owner: name, formulas: formulas) }
            if property.isFixed(in: style.values.limited(to: style.target)) { return nil }
            next = style.basedOn
        }
        return nil
    }
}

extension StylePropertyOperation {
    /// Traduce i controlli costanti nello stesso linguaggio della bacheca.
    static func constant(_ values: StyleValues, for property: InspectorProperty) -> StylePropertyOperation? {
        switch property {
        case .openingDistance: return values.openingDistance.map { Self(.set, .openingDistance, .length($0, .points)) }
        case .keepWithNext: return values.keeping.withNext.map { Self(.set, .keepWithNext, .boolean($0)) }
        case .keepTogether: return values.keeping.together.map { Self(.set, .keepTogether, .boolean($0)) }
        case .orphanLines: return values.keeping.linesAtEnd.map { Self(.set, .orphanLines, .integer($0)) }
        case .widowLines: return values.keeping.linesAtStart.map { Self(.set, .widowLines, .integer($0)) }
        case .family: return values.family.map { Self(.set, .family, .family($0)) }
        case .face: return values.fontName.map { Self(.set, .face, .face($0)) }
        case .size: return values.size.map { Self(.set, .size, .length($0, .points)) }
        case .color: return values.color.map { Self(.set, .color, .color($0.isEmpty ? nil : $0)) }
        case .smallCaps: return values.smallCaps.map { Self(.set, .smallCaps, .smallCaps($0)) }
        case .language: return values.language.map { Self(.set, .language, .language($0.isEmpty ? nil : $0)) }
        case .hyphenates: return values.hyphenates.map { Self(.set, .hyphenates, .hyphenates($0)) }
        case .alignment: return values.alignment.map { Self(.set, .alignment, .alignment($0)) }
        case .spaceBefore: return values.spaceBefore.map { Self(.set, .spaceBefore, .length($0, .points)) }
        case .spaceAfter: return values.spaceAfter.map { Self(.set, .spaceAfter, .length($0, .points)) }
        case .firstLineIndent: return values.firstLineIndent.map { Self(.set, .firstLineIndent, .length($0, .points)) }
        case .leftIndent: return values.leftIndent.map { Self(.set, .leftIndent, .length($0, .points)) }
        case .rightIndent: return values.rightIndent.map { Self(.set, .rightIndent, .length($0, .points)) }
        case .lineSpacing: return values.lineSpacing.map { Self(.set, .lineSpacing, .length($0, .points)) }
        default: return nil
        }
    }
}

extension TextStyling {
    /// Aggiorna solo le proprietà diverse dall'aspetto attuale dello stile:
    /// una formula che già produce il valore scelto conserva identità e struttura.
    public static func styleChanges(from text: NSAttributedString, at index: Int, style name: String,
                                    sheet: StyleSheet, base: CharacterStyle = TextStyling.styleBase,
                                    resolver: FontRoleResolver = FontRoleResolver()) -> [(property: InspectorProperty, value: StyleValues)] {
        guard let style = sheet.style(named: name), let point = actualAndInherited(in: text, at: index, sheet: sheet, resolver: resolver) else { return [] }
        let existing = sheet.inspect(style: name, base: base, resolver: resolver)
        let character = sheet.resolveCharacter(paragraphStyle: style.target == .paragraph ? name : nil,
            wordStyle: style.target == .word ? name : nil, characterStyle: style.target == .character ? name : nil, base: base, resolver: resolver)
        let effective = fullValues(character: character, paragraph: sheet.resolveParagraph(styleName: name),
            list: sheet.values(of: name).list, openingDistance: sheet.values(of: name).openingDistance ?? 0,
            keeping: sheet.lineKeeping(styleName: name), resolver: resolver)
        return existing.compactMap { inspected in
            guard differs(inspected.property, between: point.actual, and: effective) else { return nil }
            // Non porta proprietà di livelli superiori nello stile.
            guard StyleSheet.properties(for: style.target).contains(inspected.property) else { return nil }
            return (inspected.property, inspected.property.only(point.actual))
        }
    }
}

extension TextStyling {
    /// I dettagli avanzati mantengono il loro canale compatibile: cambiano solo
    /// quelli effettivamente diversi nella selezione e restano intatte le formule.
    public static func updatingStyleFontDetails(_ sheet: StyleSheet, style name: String, from text: NSAttributedString,
                                                at index: Int, base: CharacterStyle = TextStyling.styleBase,
                                                resolver: FontRoleResolver = FontRoleResolver()) -> StyleSheet {
        guard let i = sheet.styles.firstIndex(where: { $0.name == name }),
              let actual = characterStyle(in: text, at: index) else { return sheet }
        let style = sheet.styles[i]
        let expected = sheet.resolveCharacter(paragraphStyle: style.target == .paragraph ? name : nil,
            wordStyle: style.target == .word ? name : nil, characterStyle: style.target == .character ? name : nil, base: base, resolver: resolver)
        var result = sheet
        if actual.features != expected.features { result.styles[i].values.features = actual.features }
        if actual.variations != expected.variations { result.styles[i].values.variations = actual.variations }
        if actual.opticalSize != expected.opticalSize { result.styles[i].values.opticalSize = actual.opticalSize?.rawValue ?? "" }
        return result
    }
}
