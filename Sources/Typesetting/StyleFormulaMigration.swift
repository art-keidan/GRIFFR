import Foundation

extension NamedStyle {
    /// Espone come formule i valori costanti già supportati. Le altre proprietà
    /// restano nella dichiarazione compatibile e vengono conservate integralmente.
    public func materializingFormulas(preservingFontDeclarations: Bool = false) -> NamedStyle {
        var result = self
        var constants: [StyleFormula] = []
        func add(_ property: StyleProperty, _ argument: StyleArgument, predicate: StylePredicate = .set) {
            constants.append(StyleFormula(operation: StylePropertyOperation(predicate, property, argument)))
        }
        let canExtractFont = !preservingFontDeclarations && result.values.fontName == nil && result.values.features == nil &&
            result.values.variations == nil && result.values.opticalSize == nil
        if canExtractFont, let family = result.values.family { add(.family, .family(family)); result.values.family = nil }
        if canExtractFont {
            let italic = result.values.italic, bold = result.values.bold
            if italic == true || bold == true {
                add(.font, .font(FontRole(italic: italic == true, bold: bold == true)), predicate: .add)
            }
            if italic == false || bold == false {
                add(.font, .font(FontRole(italic: italic == false, bold: bold == false)), predicate: .subtract)
            }
            result.values.bold = nil
            result.values.italic = nil
        }
        if let size = result.values.size { add(.size, .length(size, .points)); result.values.size = nil }
        if let color = result.values.color { add(.color, .color(color.isEmpty ? nil : color)); result.values.color = nil }
        if let mode = result.values.smallCaps { add(.smallCaps, .smallCaps(mode)); result.values.smallCaps = nil }
        if let language = result.values.language { add(.language, .language(language.isEmpty ? nil : language)); result.values.language = nil }
        if let hyphenates = result.values.hyphenates { add(.hyphenates, .hyphenates(hyphenates)); result.values.hyphenates = nil }
        if let alignment = result.values.alignment { add(.alignment, .alignment(alignment)); result.values.alignment = nil }
        let lengths: [(StyleProperty, WritableKeyPath<StyleValues, Double?>)] = [
            (.spaceBefore, \.spaceBefore), (.spaceAfter, \.spaceAfter), (.firstLineIndent, \.firstLineIndent),
            (.leftIndent, \.leftIndent), (.rightIndent, \.rightIndent), (.lineSpacing, \.lineSpacing)
        ]
        for (property, path) in lengths {
            if let value = result.values[keyPath: path] { add(property, .length(value, .points)); result.values[keyPath: path] = nil }
        }
        if let spacing = result.values.pageStartSpacing {
            constants.append(StyleFormula(operation: StylePropertyOperation(.set, .pageStartSpacing, .pageStart(spacing)), when: StyleCondition(position: .firstOnPage)))
            result.values.pageStartSpacing = nil
        }
        if let value = result.values.openingDistance { add(.openingDistance, .length(value, .points)); result.values.openingDistance = nil }
        if let role = result.values.opensSection { add(.opensSection, .text(role)); result.values.opensSection = nil }
        if let name = result.values.nextStyle { add(.nextStyle, .styleName(name.isEmpty ? nil : name)); result.values.nextStyle = nil }
        if let level = result.values.outlineLevel { add(.outlineLevel, .integer(level)); result.values.outlineLevel = nil }
        if let flag = result.values.keeping.withNext { add(.keepWithNext, .boolean(flag)); result.values.keeping.withNext = nil }
        if let flag = result.values.keeping.together { add(.keepTogether, .boolean(flag)); result.values.keeping.together = nil }
        if let count = result.values.keeping.linesAtEnd { add(.orphanLines, .integer(count)); result.values.keeping.linesAtEnd = nil }
        if let count = result.values.keeping.linesAtStart { add(.widowLines, .integer(count)); result.values.keeping.linesAtStart = nil }
        if let count = result.values.keeping.nextLines { add(.nextLines, .integer(count)); result.values.keeping.nextLines = nil }
        if let count = result.values.keeping.previousLines { add(.previousLines, .integer(count)); result.values.keeping.previousLines = nil }
        result.formulas = constants + result.formulas
        return result
    }
}

extension StyleSheet {
    /// Le vecchie scelte avanzate si fondono prima di risolvere il font. In una
    /// catena che le contiene si conservano quindi le dichiarazioni del font,
    /// evitando che la conversione sequenziale ne cambi la precedenza.
    public func materializingFormulas(of name: String) -> NamedStyle? {
        guard let style = style(named: name) else { return nil }
        var next: String? = name
        var seen: Set<String> = []
        var preserveFont = false
        while let current = next, seen.insert(current).inserted, let item = self.style(named: current) {
            let v = item.values
            preserveFont = preserveFont || v.fontName != nil || v.features != nil || v.variations != nil || v.opticalSize != nil
            next = item.basedOn
        }
        return style.materializingFormulas(preservingFontDeclarations: preserveFont)
    }
}
