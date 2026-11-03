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

    public static let lineRange = 1...9

    public init(withNext: Bool? = nil, together: Bool? = nil, linesAtEnd: Int? = nil, linesAtStart: Int? = nil) {
        self.withNext = withNext
        self.together = together
        self.linesAtEnd = linesAtEnd
        self.linesAtStart = linesAtStart
    }

    public var isEmpty: Bool { withNext == nil && together == nil && linesAtEnd == nil && linesAtStart == nil }

    /// Questi valori sopra quelli di `parent`: vale il proprio dove è fissato.
    public func over(_ parent: LineKeeping) -> LineKeeping {
        LineKeeping(withNext: withNext ?? parent.withNext, together: together ?? parent.together,
                    linesAtEnd: linesAtEnd ?? parent.linesAtEnd, linesAtStart: linesAtStart ?? parent.linesAtStart)
    }

    /// I valori che contano davvero, con i ripieghi: spento, spento, 1, 1.
    public var resolved: Resolved {
        Resolved(withNext: withNext ?? false, together: together ?? false, linesAtEnd: linesAtEnd ?? 1, linesAtStart: linesAtStart ?? 1)
    }

    public struct Resolved: Hashable, Sendable {
        public var withNext: Bool
        public var together: Bool
        public var linesAtEnd: Int
        public var linesAtStart: Int
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
            default: return nil
            }
        }
    }

    static func flag(_ text: String) -> Bool? { text == "on" ? true : text == "off" ? false : nil }
    static func lines(_ text: String) -> Int? { Int(text).flatMap { lineRange.contains($0) ? $0 : nil } }

    /// Gli attributi XML, uguali per `style` e per `p`.
    static let attributeNames = ["keep-with-next", "keep-together", "orphan-lines", "widow-lines"]

    var xmlAttributes: String {
        var out = ""
        if let withNext { out += " keep-with-next=\"\(withNext ? "on" : "off")\"" }
        if let together { out += " keep-together=\"\(together ? "on" : "off")\"" }
        if let linesAtEnd { out += " orphan-lines=\"\(linesAtEnd)\"" }
        if let linesAtStart { out += " widow-lines=\"\(linesAtStart)\"" }
        return out
    }

    /// Legge gli attributi XML; `invalid` riceve il nome e il valore di quello sbagliato.
    init(xml attributes: [String: String], invalid: (String, String) throws -> Never) rethrows {
        self.init()
        if let text = attributes["keep-with-next"] { guard let value = Self.flag(text) else { try invalid("keep-with-next", text) }; withNext = value }
        if let text = attributes["keep-together"] { guard let value = Self.flag(text) else { try invalid("keep-together", text) }; together = value }
        if let text = attributes["orphan-lines"] { guard let value = Self.lines(text) else { try invalid("orphan-lines", text) }; linesAtEnd = value }
        if let text = attributes["widow-lines"] { guard let value = Self.lines(text) else { try invalid("widow-lines", text) }; linesAtStart = value }
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
