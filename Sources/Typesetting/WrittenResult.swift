import Foundation

/// «Scrivi risultato» dentro il paragrafo: un'azione di uno stile di paragrafo che scrive il risultato di una formula
/// prima o dopo il testo, sulle sue righe («Capitolo 3 · » davanti, «— p. 12» dopo). Il testo calcolato si compone con
/// il paragrafo e va a capo con lui, ma non entra nel documento: il cursore non ci entra, e si aggiorna a ogni
/// composizione. La formula si calcola nel punto del paragrafo, come quella di un campo.
public struct WrittenResult: Hashable, Sendable, Codable {
    public enum Place: String, Hashable, Sendable, Codable, CaseIterable {
        case before, after

        public var title: String {
            switch self {
            case .before: "Before the text"
            case .after: "After the text"
            }
        }
    }

    public var formula: FieldFormula
    public var place: Place
    /// Il testo fisso davanti e dopo il risultato («p. », « · »).
    public var prefix: String
    public var suffix: String
    /// Lo stile che dà l'aspetto al testo scritto, sopra quello del paragrafo; `nil`: l'aspetto del testo vicino.
    public var style: String?

    public init(formula: FieldFormula, place: Place, prefix: String = "", suffix: String = "", style: String? = nil) {
        self.formula = formula
        self.place = place
        self.prefix = prefix
        self.suffix = suffix
        self.style = style
    }

    /// Il testo da scrivere, dato il risultato: vuoto se il risultato è vuoto (l'azione allora non scrive niente).
    public func text(for value: String) -> String {
        PresentationWrite.decorate(value, prefix: prefix, suffix: suffix) ?? ""
    }

    public func text(in context: FieldContext) -> String {
        formula.presentationWrite(prefix: prefix, suffix: suffix)?.text(in: context) ?? ""
    }

    public var problem: String? {
        if let problem = formula.problem { return problem }
        if (prefix + suffix).contains(where: \.isNewline) { return "The text written with a result cannot contain a line break." }
        return nil
    }
}

extension StyleSheet {
    /// Ciò che uno stile di paragrafo scrive nel suo paragrafo: le azioni sue, o quelle dello stile su cui si basa.
    public func writtenResults(ofParagraphStyle name: String?) -> [WrittenResult] {
        var next = name
        var seen: Set<String> = []
        while let current = next, seen.insert(current).inserted, let style = style(named: current) {
            if !style.writes.isEmpty { return style.writes }
            next = style.basedOn
        }
        return []
    }
}
