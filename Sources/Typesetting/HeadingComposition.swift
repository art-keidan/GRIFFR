import Foundation

/// La testata di uno stile di titolo, nello spirito dei `chapterstyle` di `memoir`: una sequenza verticale di parti
/// (un'etichetta come «Capitolo», il numero della sezione, il titolo, filetti e spazi). Il titolo resta il solo paragrafo
/// del documento: le altre parti si compongono accanto a lui e si posano con lui, senza entrare nel testo.
public struct HeadingComposition: Hashable, Sendable, Codable {
    public var parts: [HeadingPart]

    public init(parts: [HeadingPart]) { self.parts = parts }

    /// La testata del caso guida: numero sul lato esterno in una fascia di 12 mm, 3 mm, filetto di 0,5 mm, 2,5 mm,
    /// titolo, 8 mm prima del corpo.
    public static var standard: HeadingComposition {
        HeadingComposition(parts: [
            .number(prefix: "", style: nil, alignment: .outside, minHeight: 12 * 72 / 25.4),
            .space(3 * 72 / 25.4),
            .rule(thickness: 0.5 * 72 / 25.4, length: nil, alignment: .left),
            .space(2.5 * 72 / 25.4),
            .plainTitle,
            .space(8 * 72 / 25.4),
        ])
    }

    /// Vero se la testata scrive il numero: allora il segno dell'elenco del titolo non si disegna, e il numero compare
    /// una volta sola.
    public var showsNumber: Bool { parts.contains(where: \.isNumber) }

    /// Le parti prima del titolo e quelle dopo, senza il numero accanto al titolo, che si posa con la sua prima riga.
    /// Senza una parte «titolo», il titolo viene dopo tutte le parti.
    public var split: (before: [HeadingPart], after: [HeadingPart]) {
        let stacked = parts.filter { if case .numberBeside = $0 { false } else { true } }
        guard let index = stacked.firstIndex(where: \.isTitle) else { return (stacked, []) }
        return (Array(stacked[..<index]), Array(stacked[(index + 1)...]))
    }

    /// L'allineamento e l'altezza minima propri del titolo, se la parte «titolo» li dà.
    public var titleOptions: (alignment: HeadingAlignment?, minHeight: Double?) {
        for part in parts { if case .title(let alignment, let minHeight) = part { return (alignment, minHeight) } }
        return (nil, nil)
    }

    /// Il numero accanto al titolo, se c'è: sulla prima riga del titolo, dal lato `side`, a `gap` dal titolo.
    public var numberBeside: (prefix: String, style: String?, side: HeadingAlignment, gap: Double)? {
        for part in parts { if case .numberBeside(let prefix, let style, let side, let gap) = part { return (prefix, style, side, gap) } }
        return nil
    }

    /// Vero se la testata usa ciò che il formato 14 non sapeva scrivere: il numero accanto al titolo, o allineamento e
    /// altezza propri del titolo (formato 15).
    public var needsVersion15: Bool {
        parts.contains { part in
            switch part {
            case .numberBeside: true
            case .title(let alignment, let minHeight): alignment != nil || minHeight != nil
            default: false
            }
        }
    }

    /// Un problema della testata, se c'è: più di un titolo, misure non valide.
    public var problem: String? {
        if parts.filter(\.isTitle).count > 1 { return "The heading has more than one “title” part." }
        if parts.filter({ if case .numberBeside = $0 { true } else { false } }).count > 1 {
            return "The heading has more than one number beside the title."
        }
        for part in parts {
            switch part {
            case .space(let length) where !length.isFinite || length < 0: return "A space in the heading is not a valid measure."
            case .rule(let thickness, let length, _) where !thickness.isFinite || thickness <= 0 || (length.map { !$0.isFinite || $0 <= 0 } ?? false):
                return "A rule in the heading has no valid measures."
            case .label(_, _, _, let height?), .number(_, _, _, let height?) where !height.isFinite || height < 0:
                return "A minimum height in the heading is not valid."
            case .title(_, let height?) where !height.isFinite || height < 0:
                return "A minimum height in the heading is not valid."
            case .numberBeside(_, _, let side, let gap) where !gap.isFinite || gap < 0 || side == .center:
                return "The number beside the title needs a side (left, right, outside or inside) and a valid distance."
            default: continue
            }
        }
        return nil
    }
}

/// Una parte della testata. Le misure sono in punti.
public enum HeadingPart: Hashable, Sendable, Codable {
    /// Un testo fisso («Capitolo»), con lo stile che gli dà l'aspetto (uno stile di paragrafo o di carattere).
    case label(text: String, style: String?, alignment: HeadingAlignment, minHeight: Double?)
    /// Il numero della sezione che il titolo apre, come lo scrive la sua Lista, con un testo davanti («Capitolo »).
    /// Se la sezione non ha numero, la parte sparisce con la sua fascia.
    case number(prefix: String, style: String?, alignment: HeadingAlignment, minHeight: Double?)
    /// Il posto del titolo: le sue righe, con il suo stile. Un allineamento proprio sostituisce quello dello stile (anche
    /// esterno o interno); un'altezza minima fa una fascia in cui il titolo poggia sul fondo.
    case title(alignment: HeadingAlignment?, minHeight: Double?)
    /// Il numero della sezione sulla prima riga del titolo, da un lato: le righe del titolo si scostano della sua
    /// larghezza più `gap`. Se la sezione non ha numero, il titolo occupa tutta la misura.
    case numberBeside(prefix: String, style: String?, side: HeadingAlignment, gap: Double)
    /// Un filetto; senza lunghezza, largo quanto lo specchio.
    case rule(thickness: Double, length: Double?, alignment: HeadingAlignment)
    /// Uno spazio verticale.
    case space(Double)

    public var title: String {
        switch self {
        case .label: "Label"
        case .number: "Number"
        case .title: "Title"
        case .numberBeside: "Number beside"
        case .rule: "Rule"
        case .space: "Space"
        }
    }

    /// Il titolo con l'allineamento e l'altezza del suo stile.
    public static var plainTitle: HeadingPart { .title(alignment: nil, minHeight: nil) }

    public var isTitle: Bool { if case .title = self { true } else { false } }

    /// Vero per le parti che scrivono il numero della sezione.
    public var isNumber: Bool {
        switch self {
        case .number, .numberBeside: true
        default: false
        }
    }
}

/// Dove sta una parte nella larghezza dello specchio. Esterno e interno guardano le pagine affacciate: l'esterno di una
/// pagina pari è a sinistra, di una dispari a destra; senza pagine affacciate l'esterno è a destra.
public enum HeadingAlignment: String, Hashable, Sendable, Codable, CaseIterable {
    case left, center, right, outside, inside

    public var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .outside: "Outside"
        case .inside: "Inside"
        }
    }

    /// I lati possibili per il numero accanto al titolo: tutti tranne il centro.
    public static var sides: [HeadingAlignment] { [.left, .right, .outside, .inside] }

    /// Il lato effettivo su una pagina: sinistra, centro o destra.
    public func resolved(onLeftPage: Bool) -> HeadingAlignment {
        switch self {
        case .outside: onLeftPage ? .left : .right
        case .inside: onLeftPage ? .right : .left
        default: self
        }
    }
}

extension StyleSheet {
    /// La testata di uno stile di paragrafo: la sua, o quella dello stile su cui si basa.
    public func heading(ofParagraphStyle name: String?) -> HeadingComposition? {
        var next = name
        var seen: Set<String> = []
        while let current = next, seen.insert(current).inserted, let style = style(named: current) {
            if let heading = style.heading { return heading }
            next = style.basedOn
        }
        return nil
    }
}
