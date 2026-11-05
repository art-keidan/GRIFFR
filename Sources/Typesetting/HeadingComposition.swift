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
            .title,
            .space(8 * 72 / 25.4),
        ])
    }

    /// Vero se la testata scrive il numero: allora il segno dell'elenco del titolo non si disegna, e il numero compare
    /// una volta sola.
    public var showsNumber: Bool { parts.contains { if case .number = $0 { true } else { false } } }

    /// Le parti prima del titolo e quelle dopo. Senza una parte «titolo», il titolo viene dopo tutte le parti.
    public var split: (before: [HeadingPart], after: [HeadingPart]) {
        guard let index = parts.firstIndex(of: .title) else { return (parts, []) }
        return (Array(parts[..<index]), Array(parts[(index + 1)...]))
    }

    /// Un problema della testata, se c'è: più di un titolo, misure non valide.
    public var problem: String? {
        if parts.filter({ $0 == .title }).count > 1 { return "La testata ha più di una parte «titolo»." }
        for part in parts {
            switch part {
            case .space(let length) where !length.isFinite || length < 0: return "Uno spazio della testata non è una misura valida."
            case .rule(let thickness, let length, _) where !thickness.isFinite || thickness <= 0 || (length.map { !$0.isFinite || $0 <= 0 } ?? false):
                return "Un filetto della testata non ha misure valide."
            case .label(_, _, _, let height?), .number(_, _, _, let height?) where !height.isFinite || height < 0:
                return "Un'altezza minima della testata non è valida."
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
    case number(prefix: String, style: String?, alignment: HeadingAlignment, minHeight: Double?)
    /// Il posto del titolo: le sue righe, con il suo stile.
    case title
    /// Un filetto; senza lunghezza, largo quanto lo specchio.
    case rule(thickness: Double, length: Double?, alignment: HeadingAlignment)
    /// Uno spazio verticale.
    case space(Double)

    public var title: String {
        switch self {
        case .label: "Etichetta"
        case .number: "Numero"
        case .title: "Titolo"
        case .rule: "Filetto"
        case .space: "Spazio"
        }
    }
}

/// Dove sta una parte nella larghezza dello specchio. Esterno e interno guardano le pagine affacciate: l'esterno di una
/// pagina pari è a sinistra, di una dispari a destra; senza pagine affacciate l'esterno è a destra.
public enum HeadingAlignment: String, Hashable, Sendable, Codable, CaseIterable {
    case left, center, right, outside, inside

    public var title: String {
        switch self {
        case .left: "A sinistra"
        case .center: "Al centro"
        case .right: "A destra"
        case .outside: "Lato esterno"
        case .inside: "Lato interno"
        }
    }

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
