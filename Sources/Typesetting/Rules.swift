import AppKit

/// Selezione condivisa dalle regole del documento. La posizione parte da uno.
public struct WordSelection: Hashable, Identifiable, Sendable {
    public enum Source: String, CaseIterable, Sendable { case words, capitals, numbers }
    public let id: UUID
    public var name: String
    public var source: Source
    public var index: Int

    public init(id: UUID = UUID(), name: String, source: Source = .words, index: Int = 5) {
        self.id = id
        self.name = name
        self.source = source
        self.index = index
    }

    public func preview(in sample: String) -> String? {
        let text = NSAttributedString(string: sample)
        let body = BodyText(text, paragraph: NSRange(location: 0, length: text.length))
        return body.selectedWord(self).map { body.string.substring(with: $0) }
    }
}

// MARK: - Regole

/// Una regola: trova pezzi di testo che nessuno ha creato (la prima lettera di un paragrafo, le sue prime parole, le
/// parole tutte maiuscole…) e dà loro l'aspetto di uno stile di carattere o di parola.
///
/// Il testo non cambia: la regola si applica a ogni composizione, su una copia, e il suo effetto si sposta da solo
/// quando il testo cambia. Un valore dato a mano a quel testo vale sopra la regola, e la regola sopra gli stili.
public struct TextRule: Hashable, Sendable {
    /// Che cosa trova la regola, dentro ciascun paragrafo scelto.
    public enum Target: Hashable, Sendable {
        /// La prima lettera (o cifra), con la punteggiatura d'apertura che la precede («, (, ").
        case firstLetter
        /// Le prime N parole, con la punteggiatura che le accompagna.
        case firstWords(Int)
        case selection(UUID)
        /// La prima frase, come la delimita il sistema (dal principio al primo punto fermo, esclamativo, interrogativo).
        case firstSentence
        /// Ogni parola che corrisponde a un modello.
        case words(WordPattern)
        /// Le prime N righe, come cadono componendo: lo stile e gli a capo si decidono insieme.
        case firstLines(Int)
        /// L'ultima riga.
        case lastLine
        /// Il paragrafo intero: con uno stile di paragrafo cambia anche allineamento, rientri, spazi.
        case paragraph

        /// Vero per le regole che dipendono dagli a capo, e che quindi si applicano componendo il paragrafo.
        public var isLineTarget: Bool {
            switch self {
            case .firstLines, .lastLine: true
            default: false
            }
        }
    }

    /// I modelli di parola che una regola sa riconoscere.
    public enum WordPattern: Hashable, Sendable {
        /// Parole di almeno due lettere, tutte maiuscole (sigle: ONU, UNESCO).
        case capitals
        /// Numeri romani scritti in maiuscolo (IV, XIX, MCMLXXXIV).
        case romanNumerals
        /// Parole fatte di sole cifre.
        case numbers
        /// Le parole date, esattamente come sono scritte (maiuscole e minuscole contano).
        case listed([String])
    }

    /// Quali paragrafi, per posizione.
    public enum Position: Hashable, Sendable {
        /// Tutti.
        case any
        /// Il paragrafo che viene subito dopo un paragrafo di questo stile («il primo dopo un Titolo 1»).
        case firstAfter(String)
        /// Il primo paragrafo di una sequenza. Finché non ci sono le sezioni, il primo del documento.
        case sequenceStart
        /// Il paragrafo che comincia una pagina, nella composizione naturale (senza le regole che dipendono da lei).
        case firstOnPage
    }

    /// Una condizione su una proprietà dinamica del paragrafo. Si controlla sul paragrafo composto senza le regole che
    /// dipendono dalla composizione: il risultato è stabile, anche se dopo l'applicazione la condizione può non valere più
    /// (scelta di Artemij Keidan, 17 ottobre 2026).
    public struct Condition: Hashable, Sendable {
        public enum Property: String, CaseIterable, Sendable {
            /// Il numero di righe.
            case lines
            /// Il numero di parole.
            case words
            /// Quanto l'ultima riga riempie della riga, in percentuale.
            case lastLineFill = "last-line-fill"
            /// Quante righe finiscono con un trattino.
            case hyphens
        }

        public enum Comparison: String, CaseIterable, Sendable {
            case equal = "eq", less = "lt", lessOrEqual = "le", greater = "gt", greaterOrEqual = "ge"

            public var symbol: String {
                switch self {
                case .equal: "="
                case .less: "<"
                case .lessOrEqual: "≤"
                case .greater: ">"
                case .greaterOrEqual: "≥"
                }
            }
        }

        public var property: Property
        public var comparison: Comparison
        public var value: Double

        public init(_ property: Property, _ comparison: Comparison, _ value: Double) {
            self.property = property
            self.comparison = comparison
            self.value = value
        }

        public func holds(for facts: NaturalFacts) -> Bool {
            let actual: Double = switch property {
            case .lines: Double(facts.lineCount)
            case .words: Double(facts.wordCount)
            case .lastLineFill: (facts.lastLineFill * 100).rounded()
            case .hyphens: Double(facts.hyphenatedLines)
            }
            return switch comparison {
            case .equal: actual == value
            case .less: actual < value
            case .lessOrEqual: actual <= value
            case .greater: actual > value
            case .greaterOrEqual: actual >= value
            }
        }

        public var summary: String {
            let name = switch property {
            case .lines: "righe"
            case .words: "parole"
            case .lastLineFill: "ultima riga %"
            case .hyphens: "trattini"
            }
            return "se \(name) \(comparison.symbol) \(value.formatted(.number.precision(.fractionLength(0...1))))"
        }
    }

    /// Le proprietà del paragrafo composto al naturale su cui si controllano le condizioni.
    public struct NaturalFacts: Equatable, Sendable {
        public var lineCount: Int
        public var wordCount: Int
        public var lastLineFill: Double
        public var hyphenatedLines: Int

        public init(lineCount: Int, wordCount: Int, lastLineFill: Double, hyphenatedLines: Int) {
            self.lineCount = lineCount
            self.wordCount = wordCount
            self.lastLineFill = lastLineFill
            self.hyphenatedLines = hyphenatedLines
        }
    }

    public var target: Target
    /// Lo stile dei paragrafi in cui cercare; `nil` per tutti.
    public var paragraphStyle: String?
    public var position: Position
    /// Lo stile di carattere o di parola da applicare.
    public var styleName: String
    /// Una regola spenta resta nel documento ma non si applica.
    public var isEnabled: Bool
    /// La condizione su una proprietà dinamica, se c'è.
    public var condition: Condition?
    /// Presente soltanto nelle regole derivate dalle formule, mai nel file.
    public var formulaOwner: String?

    public init(target: Target, paragraphStyle: String? = nil, position: Position = .any, condition: Condition? = nil, styleName: String,
                isEnabled: Bool = true) {
        self.formulaOwner = nil
        self.target = target
        self.paragraphStyle = paragraphStyle
        self.position = position
        self.condition = condition
        self.styleName = styleName
        self.isEnabled = isEnabled
    }

    /// Vero se la regola si può decidere solo componendo: ha una condizione, o guarda la pagina.
    public var dependsOnLayout: Bool { condition != nil || position == .firstOnPage }

    /// Il paragrafo, con ciò che serve per decidere se la regola lo riguarda.
    public struct ParagraphContext: Hashable, Sendable {
        public var styleName: String?
        /// Lo stile del paragrafo precedente; `nil` se non ne ha uno, o se è il primo.
        public var previousStyleName: String?
        public var isSequenceStart: Bool
        /// Se il paragrafo comincia una pagina; `nil` se non lo si sa ancora (prima di comporre).
        public var isFirstOnPage: Bool?

        public init(styleName: String?, previousStyleName: String?, isSequenceStart: Bool, isFirstOnPage: Bool? = nil) {
            self.styleName = styleName
            self.previousStyleName = previousStyleName
            self.isSequenceStart = isSequenceStart
            self.isFirstOnPage = isFirstOnPage
        }
    }

    public func applies(to context: ParagraphContext) -> Bool {
        guard isEnabled else { return false }
        if let paragraphStyle, context.styleName != paragraphStyle { return false }
        return StyleCondition(position: position).holds(in: context)
    }

    /// Una descrizione di una riga, per gli elenchi: «Prime 2 parole · Testo, primo dopo Titolo 1 → Maiuscoletto».
    public var summary: String { summary(selections: []) }

    public func summary(selections: [WordSelection]) -> String {
        let what: String = switch target {
        case .firstLetter: "Prima lettera"
        case .selection(let id): selections.first { $0.id == id }?.name ?? "Selezione composta"
        case .firstWords(let count): count == 1 ? "Prima parola" : "Prime \(count) parole"
        case .firstSentence: "Prima frase"
        case .words(.capitals): "Parole maiuscole"
        case .words(.romanNumerals): "Numeri romani"
        case .words(.numbers): "Numeri"
        case .words(.listed(let words)): words.isEmpty ? "Parole date" : "Parole: " + words.joined(separator: " ")
        case .firstLines(let count): count == 1 ? "Prima riga" : "Prime \(count) righe"
        case .lastLine: "Ultima riga"
        case .paragraph: "Paragrafo intero"
        }
        var whereText = paragraphStyle.map { "paragrafi \($0)" } ?? "tutti i paragrafi"
        switch position {
        case .any: break
        case .firstAfter(let style): whereText = (paragraphStyle.map { "\($0), " } ?? "") + "primo dopo \(style)"
        case .sequenceStart: whereText = (paragraphStyle.map { "\($0), " } ?? "") + "primo del documento"
        case .firstOnPage: whereText = (paragraphStyle.map { "\($0), " } ?? "") + "primo della pagina"
        }
        if let condition { whereText += ", " + condition.summary }
        let treatment = formulaOwner.map { "formula di «" + $0 + "»" } ?? styleName
        return "\(what) · \(whereText) → \(treatment)"
    }
}

// MARK: - Applicazione

public enum Rules {
    /// Una copia del testo con le regole applicate, paragrafo per paragrafo. Il testo è quello dell'editor (o
    /// del documento), con i nomi degli stili negli attributi; i testi delle note non si toccano.
    public static func applied(_ sourceRules: [TextRule], to text: NSAttributedString, sheet sourceSheet: StyleSheet, resolver: FontRoleResolver = FontRoleResolver()) -> NSAttributedString {
        let compiled = sourceSheet.compilingStyleRules(sourceRules)
        let rules = compiled.rules, sheet = compiled.sheet
        // Le regole che dipendono dalla composizione le applica l'impaginazione, paragrafo per paragrafo.
        let active = usable(rules, sheet: sheet).filter { !$0.dependsOnLayout }
        guard !active.isEmpty, text.length > 0 else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        apply(active, to: result, sheet: sheet, resolver: resolver)
        return result
    }

    /// Le regole accese che applicano uno stile esistente adatto: di carattere o di parola; di paragrafo solo al
    /// paragrafo intero.
    static func usable(_ rules: [TextRule], sheet: StyleSheet) -> [TextRule] {
        rules.filter { rule in
            guard rule.isEnabled, let style = sheet.style(named: rule.styleName) else { return false }
            return style.target != .paragraph || rule.target == .paragraph
        }
    }

    /// Applica le regole al testo, sul posto. Il risultato di ogni paragrafo resta in memoria finché non cambiano
    /// le regole o gli stili: a ogni tasto si ricalcola solo il paragrafo toccato.
    static func apply(_ rules: [TextRule], to text: NSMutableAttributedString, sheet: StyleSheet, resolver: FontRoleResolver = FontRoleResolver()) {
        cacheLock.lock()
        if cachedRules != rules || cachedSheet != sheet || cachedFontRoles != resolver.table {
            cachedRules = rules
            cachedSheet = sheet
            cachedFontRoles = resolver.table
            paragraphCache.removeAll()
        }
        cacheLock.unlock()
        var location = 0
        var previousStyle: String?
        while location < text.length {
            let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
            let styleName = text.attribute(.paragraphStyleName, at: paragraph.location, effectiveRange: nil) as? String
            let context = TextRule.ParagraphContext(styleName: styleName, previousStyleName: previousStyle, isSequenceStart: SectionEditing.opensSequence(in: text, atParagraph: paragraph.location))
            let chosen = rules.filter { $0.applies(to: context) }
            if !chosen.isEmpty {
                // Le regole di riga non si applicano qui: si annotano sul paragrafo, e le applica la composizione.
                let lineRules = LineRuleSpec(chosen)
                let original = text.attributedSubstring(from: paragraph)
                let key = ParagraphKey(text: original, context: context)
                cacheLock.lock()
                let cached = paragraphCache[key]
                cacheLock.unlock()
                let styled: NSAttributedString?
                if let cached {
                    styled = cached.text
                } else {
                    let piece = NSMutableAttributedString(attributedString: original)
                    let body = BodyText(piece, paragraph: NSRange(location: 0, length: piece.length))
                    for rule in chosen where !rule.target.isLineTarget {
                        if rule.target == .paragraph {
                            applyParagraphStyle(rule.styleName, in: piece, sheet: sheet, resolver: resolver)
                            continue
                        }
                        for range in body.ranges(of: rule.target, selections: sheet.selections) { applyStyle(rule.styleName, to: range, in: piece, sheet: sheet, resolver: resolver) }
                    }
                    if let lineRules { piece.addAttribute(.lineRules, value: lineRules, range: NSRange(location: 0, length: piece.length)) }
                    styled = piece.isEqual(to: original) ? nil : piece
                    cacheLock.lock()
                    if paragraphCache.count > 20_000 { paragraphCache.removeAll() }
                    paragraphCache[key] = CachedParagraph(text: styled)
                    cacheLock.unlock()
                }
                if let styled { text.replaceCharacters(in: paragraph, with: styled) }
            }
            previousStyle = styleName
            location = max(NSMaxRange(paragraph), location + 1)
        }
    }

    private struct ParagraphKey: Hashable {
        let text: NSAttributedString
        let context: TextRule.ParagraphContext
    }

    private final class CachedParagraph {
        /// Il paragrafo con le regole applicate; `nil` se le regole non lo cambiano.
        let text: NSAttributedString?
        init(text: NSAttributedString?) { self.text = text }
    }

    /// Che cosa dovrebbe cercare una regola per trovare, nel suo paragrafo, il pezzo `selection` del testo: la prima
    /// lettera, il paragrafo intero, le prime N parole, la prima frase; se il pezzo è una parola sola in un altro punto,
    /// quella parola ovunque. Spazi e punteggiatura agli estremi non contano. `nil` se il pezzo non è nessuna di queste.
    public static func guessTarget(for selection: NSRange, in text: NSAttributedString) -> TextRule.Target? {
        guard selection.length > 0, NSMaxRange(selection) <= text.length else { return nil }
        let string = text.string as NSString
        let paragraph = TextStyling.bodyParagraph(in: text, at: selection.location).range
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(CharacterSet(charactersIn: "\u{FFFC}\u{2028}"))
        func core(_ range: NSRange) -> NSRange? {
            var start = range.location, end = NSMaxRange(range)
            while start < end, let scalar = UnicodeScalar(string.character(at: start)), ignored.contains(scalar) { start += 1 }
            while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)), ignored.contains(scalar) { end -= 1 }
            return end > start ? NSRange(location: start, length: end - start) : nil
        }
        guard let wanted = core(selection), NSMaxRange(wanted) <= NSMaxRange(paragraph) else { return nil }
        let body = BodyText(text, paragraph: paragraph)
        // Il tratto che va dal primo all'ultimo pezzo trovato (più pezzi se in mezzo c'è una nota).
        func span(_ ranges: [NSRange]) -> NSRange? {
            guard let first = ranges.first, let last = ranges.last else { return nil }
            return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        }
        let whole = body.positions.first.map { NSRange(location: $0, length: body.positions.last! + 1 - $0) }
        var candidates: [(TextRule.Target, NSRange?)] = [(.firstLetter, span(body.ranges(of: .firstLetter))), (.paragraph, whole)]
        // Una selezione che finisce con il punto è più probabilmente una frase che un numero di parole.
        let selected = string.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "»”’\")")))
        let sentence: (TextRule.Target, NSRange?) = (.firstSentence, span(body.ranges(of: .firstSentence)))
        if selected.last.map(".!?…".contains) == true { candidates.append(sentence) }
        for count in 1...max(1, min(body.wordCount, 60)) {
            candidates.append((.firstWords(count), span(body.ranges(of: .firstWords(count)))))
        }
        candidates.append(sentence)
        for (target, range) in candidates where range.flatMap(core) == wanted { return target }
        let word = string.substring(with: wanted)
        guard word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, !word.contains("\u{FFFC}") else { return nil }
        return .words(.listed([word]))
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedRules: [TextRule] = []
    nonisolated(unsafe) private static var cachedSheet = StyleSheet()
    nonisolated(unsafe) private static var cachedFontRoles = FontRoleTable()
    nonisolated(unsafe) private static var paragraphCache: [ParagraphKey: CachedParagraph] = [:]

    /// Dà a tutto un paragrafo l'aspetto di uno stile: le misure di paragrafo (allineamento, rientri, spazi) e, sul
    /// testo del corpo, i valori di carattere e di parola. Anche qui i valori dati a mano restano.
    static func applyParagraphStyle(_ name: String, in paragraph: NSMutableAttributedString, sheet: StyleSheet, retracks: Bool = false, resolver: FontRoleResolver = FontRoleResolver()) {
        guard paragraph.length > 0 else { return }
        let all = NSRange(location: 0, length: paragraph.length)
        if let current = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            let restyled = restyledParagraph(current, styleName: paragraph.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String,
                                             with: name, sheet: sheet, except: TextStyling.ruleExceptions(in: paragraph, at: 0))
            if restyled !== current { paragraph.addAttribute(.paragraphStyle, value: restyled, range: all) }
        }
        applyStyle(name, to: all, in: paragraph, sheet: sheet, retracks: retracks, resolver: resolver)
    }

    /// Lo stile di paragrafo con le misure dello stile della regola, dove valevano quelle dello stile del paragrafo.
    static func restyledParagraph(_ current: NSParagraphStyle, styleName: String?, with name: String, sheet: StyleSheet,
                                  except exceptions: Set<InspectorProperty> = []) -> NSParagraphStyle {
        if name.hasPrefix("\u{F000}formula:") {
            let before = ParagraphStyle(current)
            return sheet.values(of: name).clearing(exceptions).applied(to: before).nsParagraphStyle
        }
        let before = sheet.resolveParagraph(styleName: styleName)
        let after = sheet.values(of: name).clearing(exceptions).applied(to: before)
        let value = ParagraphStyle(current)
        let result = TextStyling.restyled(value, from: before, to: after)
        return result == value ? current : result.nsParagraphStyle
    }

    /// Dà al testo dell'intervallo l'aspetto dello stile, tratto per tratto: ogni proprietà che vale quanto le
    /// danno i suoi stili prende il valore dello stile della regola; quelle date a mano restano. Le funzioni
    /// tipografiche si aggiungono a quelle che il tratto ha già.
    ///
    /// Con `retracks` il testo ha già la spaziatura `trak` nel kerning (è passato dalla preparazione alla composizione):
    /// se la regola cambia il font, la spaziatura si corregge per il font nuovo.
    static func applyStyle(_ name: String, to range: NSRange, in text: NSMutableAttributedString, sheet: StyleSheet, retracks: Bool = false, resolver: FontRoleResolver = FontRoleResolver()) {
        let values = sheet.values(of: name)
        var pieces: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        text.enumerateAttributes(in: range) { attributes, subrange, _ in pieces.append((subrange, attributes)) }
        for piece in pieces {
            let attributes = piece.attributes
            // I testi delle note, le immagini e il testo in un font che manca restano come sono.
            guard attributes[.footnote] == nil, attributes[.inlineImage] == nil, attributes[.missingFont] == nil,
                  let current = TextStyling.characterStyle(in: text, at: piece.range.location) else { continue }
            let before = sheet.resolveCharacter(paragraphStyle: attributes[.paragraphStyleName] as? String, wordStyle: attributes[.wordStyleName] as? String,
                                                characterStyle: attributes[.characterStyleName] as? String, base: TextStyling.styleBase, resolver: resolver)
            // Ciò che è stato dato qui a mano contro le regole resta com'è.
            let exceptions = TextStyling.ruleExceptions(attributes[.ruleExceptions] as? String)
            let after = (exceptions.isEmpty ? values : values.clearing(exceptions)).applied(to: before, resolver: resolver)
            var result = name.hasPrefix("\u{F000}formula:")
                ? (exceptions.isEmpty ? values : values.clearing(exceptions)).applied(to: current, resolver: resolver)
                : TextStyling.restyled(current, from: before, to: after)
            if let features = values.features, result.fontName == current.fontName {
                result.features = merged(current.features, with: features)
            }
            guard result != current else { continue }
            let rendered = TextStyling.characterAttributes(for: result).attributes
            TextStyling.writeFont(rendered[.font]!, in: text, range: piece.range)
            // Il testo già preparato per la composizione ha la dimensione ottica automatica: anche il font nuovo.
            if retracks { PageLayout.applyAutomaticOpticalSizes(in: text, range: piece.range) }
            if retracks, let old = attributes[.font] as? NSFont, let new = rendered[.font] as? NSFont {
                let change = (Tracking.normalTracking(for: new as CTFont) ?? 0) - (Tracking.normalTracking(for: old as CTFont) ?? 0)
                if abs(change) > 1e-9 {
                    let kern = ((attributes[.kern] as? NSNumber)?.doubleValue ?? 0) + Double(change)
                    if abs(kern) < 1e-9 { text.removeAttribute(.kern, range: piece.range) } else { text.addAttribute(.kern, value: kern, range: piece.range) }
                }
            }
            TextStyling.writeDerivedAttributes(rendered, in: text, range: piece.range)
        }
    }

    /// Le funzioni del tratto con quelle aggiunte: un'impostazione aggiunta sostituisce quella dello stesso tipo AAT
    /// (o dello stesso tag OpenType) che il tratto aveva.
    static func merged(_ current: [FeatureSetting], with added: [FeatureSetting]) -> [FeatureSetting] {
        func key(_ setting: FeatureSetting) -> String {
            switch setting {
            case .aat(let type, _): "aat\(type)"
            case .openType(let tag, _): tag
            }
        }
        let replaced = Set(added.map(key))
        return current.filter { !replaced.contains(key($0)) } + added
    }
}

extension NSAttributedString.Key {
    /// Le regole di riga che valgono per un paragrafo (`LineRuleSpec`): le applica la composizione.
    static let lineRules = NSAttributedString.Key("WordProcessorLineRules")
}

/// Le regole di riga di un paragrafo: al più una per le prime righe e una per l'ultima (se ne valgono di più, la più
/// in basso nell'elenco).
final class LineRuleSpec: NSObject {
    let firstLines: (count: Int, style: String)?
    let lastLine: String?

    init?(_ rules: [TextRule], over base: LineRuleSpec? = nil) {
        var first: (Int, String)? = base?.firstLines
        var last: String? = base?.lastLine
        for rule in rules {
            switch rule.target {
            case .firstLines(let count): first = (max(count, 1), rule.styleName)
            case .lastLine: last = rule.styleName
            default: break
            }
        }
        guard first != nil || last != nil else { return nil }
        firstLines = first
        lastLine = last
    }

    override var hash: Int { (firstLines?.count ?? 0) ^ (firstLines?.style.hashValue ?? 0) ^ (lastLine?.hashValue ?? 0) }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? LineRuleSpec else { return false }
        return firstLines?.count == other.firstLines?.count && firstLines?.style == other.firstLines?.style && lastLine == other.lastLine
    }
}

/// Il testo di un paragrafo senza i testi delle note (e senza i loro richiami): ciò che il lettore legge nel corpo.
/// Gli intervalli trovati si riportano alle posizioni del testo intero.
struct BodyText {
    let string: NSString
    /// Per ogni carattere di `string`, la sua posizione nel testo intero.
    let positions: [Int]

    init(_ text: NSAttributedString, paragraph: NSRange) {
        let whole = text.string as NSString
        var characters: [unichar] = []
        var positions: [Int] = []
        var index = paragraph.location
        let end = NSMaxRange(paragraph)
        while index < end {
            var effective = NSRange(location: 0, length: 0)
            let isNote = text.attribute(.footnote, at: index, longestEffectiveRange: &effective, in: NSRange(location: index, length: end - index)) != nil
            let stop = min(NSMaxRange(effective), end)
            if !isNote {
                for position in index..<stop {
                    let character = whole.character(at: position)
                    // L'a capo che chiude il paragrafo non fa parte del testo in cui si cerca.
                    if position == end - 1, TextStyling.isLineTerminator(character) { continue }
                    characters.append(character)
                    positions.append(position)
                }
            }
            index = max(stop, index + 1)
        }
        string = NSString(characters: characters, length: characters.count)
        self.positions = positions
    }

    /// Gli intervalli del testo intero che corrispondono a un intervallo di `string` (più d'uno se in mezzo c'è una nota).
    func documentRanges(for range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        for index in range.location..<NSMaxRange(range) {
            let position = positions[index]
            if let last = result.last, NSMaxRange(last) == position {
                result[result.count - 1].length += 1
            } else {
                result.append(NSRange(location: position, length: 1))
            }
        }
        return result
    }

    func ranges(of target: TextRule.Target, selections: [WordSelection] = []) -> [NSRange] {
        guard string.length > 0 else { return [] }
        let found: [NSRange]
        switch target {
        case .selection(let id):
            found = selections.first { $0.id == id }.flatMap { selectedWord($0) }.map { [$0] } ?? []
        case .firstLetter: found = firstLetter().map { [$0] } ?? []
        case .firstWords(let count): found = firstWords(count).map { [$0] } ?? []
        case .firstSentence: found = firstSentence().map { [$0] } ?? []
        case .words(let pattern): found = words(matching: pattern)
        case .firstLines, .lastLine, .paragraph: found = []
        }
        return found.flatMap(documentRanges(for:))
    }

    private static let opening = CharacterSet(charactersIn: "«‹\"'“‘„‚([{¿¡—–-")

    /// La prima lettera o cifra, con la punteggiatura d'apertura e gli spazi che la precedono.
    func firstLetter() -> NSRange? {
        var index = 0
        while index < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: index)
            let piece = string.substring(with: range)
            if piece.unicodeScalars.first.map(CharacterSet.alphanumerics.contains) == true {
                return NSRange(location: 0, length: NSMaxRange(range))
            }
            guard piece.unicodeScalars.allSatisfy({ Self.opening.contains($0) || CharacterSet.whitespaces.contains($0) }) else { return nil }
            index = NSMaxRange(range)
        }
        return nil
    }

    func selectedWord(_ selection: WordSelection) -> NSRange? {
        guard selection.index > 0 else { return nil }
        let matches = switch selection.source {
        case .words: wordRanges(limit: selection.index)
        case .capitals: words(matching: .capitals)
        case .numbers: words(matching: .numbers)
        }
        return selection.index <= matches.count ? matches[selection.index - 1] : nil
    }

    /// Quante parole ha il testo.
    var wordCount: Int { wordRanges().count }

    /// Le parole del testo, come le divide il sistema.
    private func wordRanges(limit: Int = .max) -> [NSRange] {
        var result: [NSRange] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            result.append(range)
            if result.count >= limit { stop.pointee = true }
        }
        return result
    }

    /// Dal principio alla fine dell'ennesima parola, compresa la punteggiatura attaccata a lei («Roma,» «cit.»).
    func firstWords(_ count: Int) -> NSRange? {
        guard count > 0, let last = wordRanges(limit: count).last else { return nil }
        var end = NSMaxRange(last)
        while end < string.length, let scalar = Unicode.Scalar(string.character(at: end)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar), !CharacterSet.alphanumerics.contains(scalar) { end += 1 }
        return NSRange(location: 0, length: end)
    }

    /// La prima frase, senza gli spazi che la seguono.
    func firstSentence() -> NSRange? {
        var result: NSRange?
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            result = range
            stop.pointee = true
        }
        guard var range = result else { return nil }
        while range.length > 0, let scalar = Unicode.Scalar(string.character(at: NSMaxRange(range) - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { range.length -= 1 }
        return range.length > 0 ? range : nil
    }

    private static let romanNumeral = try! NSRegularExpression(pattern: "^M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$")
    private static let number = try! NSRegularExpression(pattern: "^[0-9]+([.,][0-9]+)*$")
    private static let apostrophes = CharacterSet(charactersIn: "'’")

    /// Le parole per i modelli: come le divide il sistema, ma staccando ciò che segue un apostrofo, così che in
    /// «dell'ONU» la sigla sia una parola a sé.
    private func patternWords() -> [NSRange] {
        wordRanges().flatMap { range -> [NSRange] in
            var pieces: [NSRange] = []
            var start = range.location
            for index in range.location..<NSMaxRange(range) {
                guard let scalar = Unicode.Scalar(string.character(at: index)), Self.apostrophes.contains(scalar) else { continue }
                if index > start { pieces.append(NSRange(location: start, length: index - start)) }
                start = index + 1
            }
            if NSMaxRange(range) > start { pieces.append(NSRange(location: start, length: NSMaxRange(range) - start)) }
            return pieces
        }
    }

    func words(matching pattern: TextRule.WordPattern) -> [NSRange] {
        let listed: Set<String> = if case .listed(let words) = pattern { Set(words) } else { [] }
        func matches(_ expression: NSRegularExpression, _ word: String) -> Bool {
            expression.firstMatch(in: word, range: NSRange(location: 0, length: (word as NSString).length)) != nil
        }
        return patternWords().filter { range in
            let word = string.substring(with: range)
            switch pattern {
            case .capitals:
                let letters = word.unicodeScalars.filter(CharacterSet.letters.contains)
                return letters.count >= 2 && word == word.uppercased() && word != word.lowercased()
            case .romanNumerals:
                return !word.isEmpty && matches(Self.romanNumeral, word)
            case .numbers:
                return matches(Self.number, word)
            case .listed:
                return listed.contains(word)
            }
        }
    }
}
