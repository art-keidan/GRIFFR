import AppKit

/// Il maiuscoletto come scelta tipografica: quali lettere vanno in maiuscoletto, qualunque sia il font. Nel documento
/// si registra questa scelta; le forme tecniche (AAT o OpenType) che la realizzano si scelgono solo quando si compone,
/// fra quelle che il font conosce. Un font che non ne ha nessuna lascia il testo com'è, ma la scelta resta.
public enum SmallCaps: String, CaseIterable, Hashable, Sendable {
    /// Nessun maiuscoletto.
    case off
    /// Le minuscole in maiuscoletto: il maiuscoletto consueto.
    case lowercase
    /// Le maiuscole in maiuscoletto: per le sigle (ONU), i numeri romani.
    case uppercase
    /// Tutte le lettere in maiuscoletto.
    case all

    public var title: String {
        switch self {
        case .off: "No"
        case .lowercase: "Minuscole"
        case .uppercase: "Sigle"
        case .all: "Minuscole e sigle"
        }
    }

    /// Le forme in cui i font offrono il maiuscoletto delle minuscole: AAT «Letter Case» (tipo 3, come in Hoefler Text),
    /// AAT «Lower Case» (tipo 37, come in Baskerville), OpenType `smcp`.
    public static let lowercaseForms: [FeatureSetting] = [.aat(type: 3, selector: 3), .aat(type: 37, selector: 1), .openType(tag: "smcp", value: 1)]

    /// Le forme del maiuscoletto delle maiuscole: AAT «Upper Case» (tipo 38) e OpenType `c2sc`. Molti font non l'hanno
    /// (Hoefler Text no).
    public static let uppercaseForms: [FeatureSetting] = [.aat(type: 38, selector: 1), .openType(tag: "c2sc", value: 1)]

    var hasLowercase: Bool { self == .lowercase || self == .all }
    var hasUppercase: Bool { self == .uppercase || self == .all }

    init(lowercase: Bool, uppercase: Bool) {
        switch (lowercase, uppercase) {
        case (false, false): self = .off
        case (true, false): self = .lowercase
        case (false, true): self = .uppercase
        case (true, true): self = .all
        }
    }

    /// Tutte le forme tecniche da chiedere al font: lui tiene quelle che conosce.
    public var forms: [FeatureSetting] {
        (hasLowercase ? Self.lowercaseForms : []) + (hasUppercase ? Self.uppercaseForms : [])
    }

    /// Divide un elenco di funzioni in quelle che non sono maiuscoletto e il maiuscoletto che le altre esprimono. Serve
    /// a leggere i documenti di prima, e i font in cui il maiuscoletto è arrivato come funzione grezza.
    public static func split(_ features: [FeatureSetting]) -> (rest: [FeatureSetting], smallCaps: SmallCaps) {
        let lowercase = features.contains { lowercaseForms.contains($0) }
        let uppercase = features.contains { uppercaseForms.contains($0) }
        let rest = features.filter { !lowercaseForms.contains($0) && !uppercaseForms.contains($0) }
        return (rest, SmallCaps(lowercase: lowercase, uppercase: uppercase))
    }
}

extension NSAttributedString.Key {
    /// Il maiuscoletto voluto (`SmallCaps.rawValue`), assente per nessuno: vale anche dove il font non ha la forma.
    public static let smallCaps = NSAttributedString.Key("WordProcessorSmallCaps")
}
