import Foundation

/// La ricerca nel testo per «Cerca e sostituisci»: le occorrenze di ciò che si cerca e il testo che prende il posto
/// di ciascuna. Si cerca nel testo com'è nel deposito, note comprese; un'occorrenza non passa mai dal corpo a una nota
/// (né attraversa un richiamo).
public enum TextSearch {
    public struct Options: Equatable, Sendable {
        /// Maiuscole e minuscole contano.
        public var matchesCase = false
        /// Solo parole intere: prima e dopo l'occorrenza non ci sono lettere, cifre o trattini bassi.
        public var wholeWords = false
        /// Ciò che si cerca è un'espressione regolare; nella sostituzione $1, $2… sono i gruppi.
        public var isPattern = false
        /// «e» trova anche é, è, ē, ἐ… Vale solo senza modello: in un'espressione regolare non si saprebbe dove sono
        /// i segni da ignorare.
        public var ignoresDiacritics = false

        public init(matchesCase: Bool = false, wholeWords: Bool = false, isPattern: Bool = false, ignoresDiacritics: Bool = false) {
            self.matchesCase = matchesCase
            self.wholeWords = wholeWords
            self.isPattern = isPattern
            self.ignoresDiacritics = ignoresDiacritics
        }
    }

    public enum SearchError: Error, Equatable {
        /// Il modello non è un'espressione regolare valida.
        case invalidPattern
    }

    /// Le occorrenze, in ordine, senza sovrapposizioni e mai vuote.
    public static func matches(of query: String, in text: NSAttributedString, options: Options) throws -> [NSRange] {
        guard !query.isEmpty, text.length > 0 else { return [] }
        let string = text.string as NSString
        var found: [NSRange] = []
        if options.isPattern {
            let expression = try expression(for: query, options: options)
            expression.enumerateMatches(in: text.string, range: NSRange(location: 0, length: string.length)) { match, _, _ in
                if let range = match?.range, range.length > 0 { found.append(range) }
            }
        } else {
            var compare: NSString.CompareOptions = []
            if !options.matchesCase { compare.insert(.caseInsensitive) }
            if options.ignoresDiacritics { compare.insert(.diacriticInsensitive) }
            var location = 0
            while location < string.length {
                let range = string.range(of: query, options: compare, range: NSRange(location: location, length: string.length - location))
                guard range.location != NSNotFound, range.length > 0 else { break }
                if !options.wholeWords || isWholeWord(range, in: string) { found.append(range) }
                location = NSMaxRange(range)
            }
        }
        return found.filter { staysInOnePlace($0, in: text) }
    }

    /// Il testo che prende il posto dell'occorrenza: con un modello, la sostituzione con i gruppi ($1, $2…) riempiti;
    /// senza, la sostituzione così com'è.
    public static func replacement(for match: NSRange, in text: NSAttributedString, query: String, template: String, options: Options) throws -> String {
        guard options.isPattern else { return template }
        let expression = try expression(for: query, options: options)
        guard let result = expression.firstMatch(in: text.string, range: match) else { return template }
        return expression.replacementString(for: result, in: text.string, offset: 0, template: template)
    }

    private static func expression(for query: String, options: Options) throws -> NSRegularExpression {
        var pattern = query
        if options.wholeWords { pattern = "(?<![\\p{L}\\p{N}_])(?:" + pattern + ")(?![\\p{L}\\p{N}_])" }
        do {
            return try NSRegularExpression(pattern: pattern, options: options.matchesCase ? [] : [.caseInsensitive])
        } catch {
            throw SearchError.invalidPattern
        }
    }

    private static func isWholeWord(_ range: NSRange, in string: NSString) -> Bool {
        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < string.length else { return false }
            let character = string.substring(with: string.rangeOfComposedCharacterSequence(at: index))
            return character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        }
        return !isWordCharacter(range.location - 1) && !isWordCharacter(NSMaxRange(range))
    }

    /// Vero se l'occorrenza sta tutta nel corpo o tutta nel testo di una nota, senza richiami dentro.
    private static func staysInOnePlace(_ range: NSRange, in text: NSAttributedString) -> Bool {
        let string = text.string as NSString
        if string.range(of: String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1), options: .literal, range: range).location != NSNotFound {
            return false
        }
        let first = text.attribute(.footnote, at: range.location, effectiveRange: nil) != nil
        let last = text.attribute(.footnote, at: NSMaxRange(range) - 1, effectiveRange: nil) != nil
        return first == last
    }
}
