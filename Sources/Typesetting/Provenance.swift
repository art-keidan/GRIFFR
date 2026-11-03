import AppKit

// MARK: - I segni della provenienza

extension TextStyling {
    /// I tratti del corpo con qualcosa di dato a mano: un valore di carattere o di parola diverso da quello dei suoi
    /// stili (anche le funzioni del font, come il maiuscoletto), un valore che vince sulle regole, o, per un paragrafo
    /// con una misura data a mano, tutto il suo testo. I testi delle note e le immagini non contano.
    public static func manualRanges(in text: NSAttributedString, sheet: StyleSheet) -> [NSRange] {
        guard text.length > 0 else { return [] }
        let string = text.string as NSString
        let characterProperties = InspectorProperty.allCases.filter { $0.level != .paragraph }
        let paragraphProperties = InspectorProperty.properties(of: .paragraph).filter { $0 != .list }
        var result: [NSRange] = []
        var location = 0
        while location < text.length {
            let paragraph = bodyParagraph(in: text, at: location).range
            location = max(NSMaxRange(paragraph), location + 1)
            // Il paragrafo: le sue misure (la Lista no: è un comando a sé, non un aspetto).
            if let values = actualAndInherited(in: text, at: paragraph.location, sheet: sheet),
               paragraphProperties.contains(where: { $0.only(values.actual) != $0.only(values.inherited) }) {
                let body = BodyText(text, paragraph: paragraph)
                result += body.documentRanges(for: NSRange(location: 0, length: body.string.length))
                continue
            }
            text.enumerateAttributes(in: paragraph) { attributes, run, _ in
                guard attributes[.footnote] == nil, attributes[.inlineImage] == nil, attributes[.missingFont] == nil else { return }
                var range = run
                // L'a capo non si segna.
                while range.length > 0, isLineTerminator(string.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
                guard range.length > 0 else { return }
                if attributes[.ruleExceptions] != nil { result.append(range); return }
                guard let values = actualAndInherited(in: text, at: run.location, sheet: sheet) else { return }
                if characterProperties.contains(where: { $0.only(values.actual) != $0.only(values.inherited) }) { result.append(range); return }
                // Le funzioni del font non sono proprietà dell'ispettore: si confrontano a parte.
                if let current = characterStyle(in: text, at: run.location) {
                    let expected = sheet.resolveCharacter(paragraphStyle: values.names.paragraph, wordStyle: values.names.word,
                                                          characterStyle: values.names.character, base: styleBase)
                    if current.fontName == expected.fontName, Set(current.features) != Set(expected.features) { result.append(range) }
                }
            }
        }
        return merged(result)
    }

    /// Gli intervalli ordinati, con quelli che si toccano o si sovrappongono fusi.
    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                result.append(range)
            }
        }
        return result
    }
}
