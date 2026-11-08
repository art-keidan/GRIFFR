import Foundation

extension NSAttributedString.Key {
    /// I filetti dati a mano a un paragrafo (`ParagraphRules.encoded`), su tutto il paragrafo: sostituiscono quelli dello stile.
    public static let paragraphRules = NSAttributedString.Key("WordProcessorParagraphRules")
}

/// Un filetto libero di un paragrafo (formato 18): orizzontale sopra o sotto, verticale a sinistra o a destra. Non occupa
/// spazio: si posa sulla pagina e il testo non si sposta.
public struct ParagraphRule: Hashable, Sendable, Codable {
    public enum Anchor: String, CaseIterable, Sendable, Codable {
        case top, bottom, left, right

        public var isHorizontal: Bool { self == .top || self == .bottom }

        public var title: String {
            switch self {
            case .top: "Above"
            case .bottom: "Below"
            case .left: "Left"
            case .right: "Right"
            }
        }
    }

    /// Il bordo del paragrafo a cui il filetto si aggancia: l'alto della prima riga, il basso dell'ultima, i lati della
    /// colonna (o della cella).
    public var anchor: Anchor
    /// La distanza dal bordo agganciato, verso l'esterno (in punti; negativa verso il testo).
    public var offset: Double
    /// Di quanto il filetto si prolunga oltre il paragrafo al suo inizio (a sinistra o in alto) e alla sua fine (a destra
    /// o in basso); un valore negativo lo accorcia.
    public var start: Double
    public var end: Double
    public var thickness: Double

    public init(anchor: Anchor, offset: Double = 0, start: Double = 0, end: Double = 0, thickness: Double = 0.5) {
        self.anchor = anchor
        self.offset = offset
        self.start = start
        self.end = end
        self.thickness = thickness
    }

    /// Un filetto nuovo, a qualche punto dal testo.
    public static func fresh(_ anchor: Anchor) -> ParagraphRule {
        ParagraphRule(anchor: anchor, offset: anchor.isHorizontal ? 3 : 6, thickness: 0.5)
    }
}

/// I filetti di un paragrafo o di uno stile. Un elenco vuoto toglie quelli ereditati.
public struct ParagraphRules: Hashable, Sendable {
    public var rules: [ParagraphRule]

    public init(_ rules: [ParagraphRule] = []) { self.rules = rules }

    /// La forma scritta nel testo e nel file: `top 3 0 0 0.5; left 6 0 0 1` (aggancio, scarto, inizio, fine, spessore).
    public var encoded: String {
        rules.map { rule in
            ([rule.anchor.rawValue] + [rule.offset, rule.start, rule.end, rule.thickness].map { Self.number($0) }).joined(separator: " ")
        }.joined(separator: "; ")
    }

    public init?(encoded: String) {
        var rules: [ParagraphRule] = []
        for piece in encoded.split(separator: ";") {
            let parts = piece.split(separator: " ").map(String.init)
            guard parts.count == 5, let anchor = ParagraphRule.Anchor(rawValue: parts[0]) else { return nil }
            let numbers = parts.dropFirst().compactMap(Double.init)
            guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[3] > 0 else { return nil }
            rules.append(ParagraphRule(anchor: anchor, offset: numbers[0], start: numbers[1], end: numbers[2], thickness: numbers[3]))
        }
        self.rules = rules
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

extension TextStyling {
    /// I filetti dati a mano al paragrafo che contiene `index`; `nil` se valgono quelli dello stile.
    public static func paragraphRules(in text: NSAttributedString, at index: Int) -> ParagraphRules? {
        guard index >= 0, index < text.length else { return nil }
        return (text.attribute(.paragraphRules, at: index, effectiveRange: nil) as? String).flatMap(ParagraphRules.init(encoded:))
    }

    /// Fissa (o, con `nil`, toglie) i filetti dati a mano a un intervallo di paragrafi interi.
    public static func setParagraphRules(_ rules: ParagraphRules?, in text: NSMutableAttributedString, paragraphs range: NSRange) {
        if let rules { text.addAttribute(.paragraphRules, value: rules.encoded, range: range) } else { text.removeAttribute(.paragraphRules, range: range) }
    }
}

/// Dove un filetto di un paragrafo è stato posato, per la progettazione.
public struct PlacedParagraphRule: Sendable {
    public let paragraphLocation: Int
    /// Il posto del filetto nell'elenco dei filetti del paragrafo.
    public let rule: Int
    /// Con l'origine della pagina in basso a sinistra.
    public let rect: CGRect
}
