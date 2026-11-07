import Foundation

extension NSAttributedString.Key {
    /// La tenuta data a mano a un paragrafo (`LineKeeping.encoded`), su tutto il paragrafo, a capo compreso.
    public static let lineKeeping = NSAttributedString.Key("WordProcessorLineKeeping")
}

/// La tenuta delle righe fra le pagine: tieni col seguente, paragrafo indivisibile, righe minime in fondo alla pagina
/// (all'inizio del paragrafo) e in cima alla seguente (alla fine del paragrafo).
///
/// Ogni valore è facoltativo: assente vuol dire «come sopra» (lo stile di base, poi lo stile, poi niente); un valore
/// scritto vale anche se è uguale a quello che si erediterebbe. Tutto assente = nessuna tenuta, come prima.
public struct LineKeeping: Hashable, Sendable {
    /// Il paragrafo resta nella stessa pagina dell'inizio del successivo.
    public var withNext: Bool?
    /// Il paragrafo non si spezza fra due pagine.
    public var together: Bool?
    /// Righe minime del paragrafo in fondo alla pagina (le orfane); 1 = nessun controllo.
    public var linesAtEnd: Int?
    /// Righe minime del paragrafo in cima alla pagina seguente (le vedove); 1 = nessun controllo.
    public var linesAtStart: Int?
    /// Con «tieni col seguente»: quante righe del seguente stanno nella stessa pagina della fine di questo (formato 17).
    public var nextLines: Int?
    /// Tieni col precedente: quante righe del precedente stanno nella pagina in cui comincia questo; 0 = nessuna (17).
    public var previousLines: Int?

    public static let lineRange = 1...9
    public static let previousRange = 0...9

    public init(withNext: Bool? = nil, together: Bool? = nil, linesAtEnd: Int? = nil, linesAtStart: Int? = nil,
                nextLines: Int? = nil, previousLines: Int? = nil) {
        self.withNext = withNext
        self.together = together
        self.linesAtEnd = linesAtEnd
        self.linesAtStart = linesAtStart
        self.nextLines = nextLines
        self.previousLines = previousLines
    }

    public var isEmpty: Bool {
        withNext == nil && together == nil && linesAtEnd == nil && linesAtStart == nil && nextLines == nil && previousLines == nil
    }

    /// Questi valori sopra quelli di `parent`: vale il proprio dove è fissato.
    public func over(_ parent: LineKeeping) -> LineKeeping {
        LineKeeping(withNext: withNext ?? parent.withNext, together: together ?? parent.together,
                    linesAtEnd: linesAtEnd ?? parent.linesAtEnd, linesAtStart: linesAtStart ?? parent.linesAtStart,
                    nextLines: nextLines ?? parent.nextLines, previousLines: previousLines ?? parent.previousLines)
    }

    /// I valori che contano davvero, con i ripieghi: spento, spento, 1, 1, 1, 0.
    public var resolved: Resolved {
        Resolved(withNext: withNext ?? false, together: together ?? false, linesAtEnd: linesAtEnd ?? 1, linesAtStart: linesAtStart ?? 1,
                 nextLines: nextLines ?? 1, previousLines: previousLines ?? 0)
    }

    public struct Resolved: Hashable, Sendable {
        public var withNext: Bool
        public var together: Bool
        public var linesAtEnd: Int
        public var linesAtStart: Int
        /// Le righe del seguente che restano con questo (contano solo con `withNext`).
        public var nextLines: Int = 1
        /// Le righe del precedente che restano con questo; 0 = nessuna.
        public var previousLines: Int = 0

        public init(withNext: Bool, together: Bool, linesAtEnd: Int, linesAtStart: Int, nextLines: Int = 1, previousLines: Int = 0) {
            self.withNext = withNext
            self.together = together
            self.linesAtEnd = linesAtEnd
            self.linesAtStart = linesAtStart
            self.nextLines = nextLines
            self.previousLines = previousLines
        }

        /// Nessuna tenuta: il paragrafo si impagina come sempre.
        public var isNone: Bool { !withNext && !together && linesAtEnd <= 1 && linesAtStart <= 1 }
    }

    // MARK: - Testo e file

    /// La forma scritta nel testo dell'editor: `next=on together=off end=2 start=2`, solo i valori fissati.
    public var encoded: String {
        var parts: [String] = []
        if let withNext { parts.append("next=\(withNext ? "on" : "off")") }
        if let together { parts.append("together=\(together ? "on" : "off")") }
        if let linesAtEnd { parts.append("end=\(linesAtEnd)") }
        if let linesAtStart { parts.append("start=\(linesAtStart)") }
        if let nextLines { parts.append("nextlines=\(nextLines)") }
        if let previousLines { parts.append("previous=\(previousLines)") }
        return parts.joined(separator: " ")
    }

    public init?(encoded: String) {
        self.init()
        for part in encoded.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            switch pair[0] {
            case "next": guard let value = Self.flag(pair[1]) else { return nil }; withNext = value
            case "together": guard let value = Self.flag(pair[1]) else { return nil }; together = value
            case "end": guard let value = Self.lines(pair[1]) else { return nil }; linesAtEnd = value
            case "start": guard let value = Self.lines(pair[1]) else { return nil }; linesAtStart = value
            case "nextlines": guard let value = Self.lines(pair[1]) else { return nil }; nextLines = value
            case "previous": guard let value = Self.previous(pair[1]) else { return nil }; previousLines = value
            default: return nil
            }
        }
    }

    static func flag(_ text: String) -> Bool? { text == "on" ? true : text == "off" ? false : nil }
    static func lines(_ text: String) -> Int? { Int(text).flatMap { lineRange.contains($0) ? $0 : nil } }
    static func previous(_ text: String) -> Int? { Int(text).flatMap { previousRange.contains($0) ? $0 : nil } }

    /// Gli attributi XML, uguali per `style` e per `p`.
    static let attributeNames = ["keep-with-next", "keep-together", "orphan-lines", "widow-lines", "keep-next-lines", "keep-with-previous"]

    var xmlAttributes: String {
        var out = ""
        if let withNext { out += " keep-with-next=\"\(withNext ? "on" : "off")\"" }
        if let together { out += " keep-together=\"\(together ? "on" : "off")\"" }
        if let linesAtEnd { out += " orphan-lines=\"\(linesAtEnd)\"" }
        if let linesAtStart { out += " widow-lines=\"\(linesAtStart)\"" }
        if let nextLines { out += " keep-next-lines=\"\(nextLines)\"" }
        if let previousLines { out += " keep-with-previous=\"\(previousLines)\"" }
        return out
    }

    /// Legge gli attributi XML; `invalid` riceve il nome e il valore di quello sbagliato.
    init(xml attributes: [String: String], invalid: (String, String) throws -> Never) rethrows {
        self.init()
        if let text = attributes["keep-with-next"] { guard let value = Self.flag(text) else { try invalid("keep-with-next", text) }; withNext = value }
        if let text = attributes["keep-together"] { guard let value = Self.flag(text) else { try invalid("keep-together", text) }; together = value }
        if let text = attributes["orphan-lines"] { guard let value = Self.lines(text) else { try invalid("orphan-lines", text) }; linesAtEnd = value }
        if let text = attributes["widow-lines"] { guard let value = Self.lines(text) else { try invalid("widow-lines", text) }; linesAtStart = value }
        if let text = attributes["keep-next-lines"] { guard let value = Self.lines(text) else { try invalid("keep-next-lines", text) }; nextLines = value }
        if let text = attributes["keep-with-previous"] { guard let value = Self.previous(text) else { try invalid("keep-with-previous", text) }; previousLines = value }
    }
}

extension TextStyling {
    /// La tenuta data a mano al paragrafo che contiene `index`.
    public static func lineKeeping(in text: NSAttributedString, at index: Int) -> LineKeeping {
        guard index >= 0, index < text.length else { return LineKeeping() }
        return (text.attribute(.lineKeeping, at: index, effectiveRange: nil) as? String).flatMap(LineKeeping.init(encoded:)) ?? LineKeeping()
    }

    /// Fissa (o toglie, se vuota) la tenuta data a mano a un intervallo di paragrafi interi.
    public static func setLineKeeping(_ keeping: LineKeeping, in text: NSMutableAttributedString, paragraphs range: NSRange) {
        if keeping.isEmpty { text.removeAttribute(.lineKeeping, range: range) } else { text.addAttribute(.lineKeeping, value: keeping.encoded, range: range) }
    }
}

extension StyleSheet {
    /// La tenuta effettiva di un paragrafo: la sua, sopra quella del suo stile.
    public func lineKeeping(styleName: String?, own: LineKeeping = LineKeeping()) -> LineKeeping.Resolved {
        own.over(values(of: styleName).keeping).resolved
    }
}
