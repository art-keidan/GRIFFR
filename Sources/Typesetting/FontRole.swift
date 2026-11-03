/// Un ruolo tipografico richiesto, indipendente dalla faccia che una famiglia userà per realizzarlo.
///
/// Il ruolo non contiene un nome di font né una soglia di peso: per esempio, la famiglia può associare `.bold`
/// a una faccia `Medium`, `Semibold` o `Bold`, oppure a un valore dell'asse `wght` di un font variabile.
/// I valori grezzi sono stabili perché potranno essere conservati nelle impostazioni delle equivalenze.
public enum FontRole: String, CaseIterable, Codable, Hashable, Sendable {
    case regular
    case italic
    case bold
    case boldItalic

    /// Il ruolo corrispondente alla combinazione di corsivo e nero richiesta.
    public init(italic: Bool, bold: Bool) {
        switch (italic, bold) {
        case (false, false): self = .regular
        case (true, false): self = .italic
        case (false, true): self = .bold
        case (true, true): self = .boldItalic
        }
    }

    public var isItalic: Bool { self == .italic || self == .boldItalic }
    public var isBold: Bool { self == .bold || self == .boldItalic }

    /// Cambia solo il corsivo, conservando la richiesta di nero.
    public func togglingItalic() -> FontRole { FontRole(italic: !isItalic, bold: isBold) }

    /// Cambia solo il nero, conservando la richiesta di corsivo.
    public func togglingBold() -> FontRole { FontRole(italic: isItalic, bold: !isBold) }
}
