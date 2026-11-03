import Foundation

/// Quali filetti disegna uno stile di tabella, prima delle eccezioni delle singole celle.
public enum TableRuleScheme: String, CaseIterable, Sendable {
    /// Tutti i lati di tutte le celle.
    case grid
    /// Sopra la tabella, sotto l'ultima riga d'intestazione, in fondo alla tabella.
    case threeRules = "three-rules"
    /// I lati orizzontali di tutte le celle.
    case horizontal
    /// Solo il bordo esterno.
    case frame
    /// Nessuno.
    case none

    public var title: String {
        switch self {
        case .grid: "Griglia completa"
        case .threeRules: "Tre filetti"
        case .horizontal: "Solo orizzontali"
        case .frame: "Solo il bordo"
        case .none: "Nessun filetto"
        }
    }
}

/// Dove sta il testo di una cella più bassa della sua riga.
public enum CellVerticalAlignment: String, CaseIterable, Sendable {
    case top, middle, bottom

    public var title: String {
        switch self {
        case .top: "In alto"
        case .middle: "Al centro"
        case .bottom: "In basso"
        }
    }
}

/// I margini interni di una cella, in punti.
public struct CellInsets: Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(all: Double) { self.init(top: all, right: all, bottom: all, left: all) }

    /// «4» se i quattro lati sono uguali, altrimenti «sopra destra sotto sinistra» (come nei CSS).
    public var text: String {
        let values = [top, right, bottom, left].map(CellInsets.number)
        return Set(values).count == 1 ? values[0] : values.joined(separator: " ")
    }

    /// Da «4» o da quattro misure (unità facoltativa, punti se manca).
    public init?(text: String, length: (String) -> Double?) {
        let parts = text.split(separator: " ").map(String.init)
        let values = parts.compactMap(length)
        guard values.count == parts.count, values.allSatisfy({ $0 >= 0 }) else { return nil }
        switch values.count {
        case 1: self.init(all: values[0])
        case 4: self.init(top: values[0], right: values[1], bottom: values[2], left: values[3])
        default: return nil
        }
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}

/// Un lato di una cella: senza filetto, o con un filetto di quello spessore (in punti).
public enum CellBorder: Equatable, Sendable {
    case none
    case rule(Double)

    /// «none» o lo spessore.
    public var text: String {
        switch self {
        case .none: "none"
        case .rule(let width): CellInsets.number(width)
        }
    }

    public init?(text: String, length: (String) -> Double?) {
        if text == "none" {
            self = .none
        } else if let width = length(text), width > 0 {
            self = .rule(width)
        } else {
            return nil
        }
    }

    public var width: Double {
        if case .rule(let width) = self { width } else { 0 }
    }
}

/// L'aspetto che uno stile di tabella dà e che una tabella può cambiare solo per sé. `nil`: non detto (vale quello dello
/// stile, o il valore iniziale).
public struct TableValues: Equatable, Sendable {
    public var rules: TableRuleScheme?
    public var ruleWidth: Double?
    public var padding: CellInsets?
    public var verticalAlignment: CellVerticalAlignment?
    /// Il fondo delle celle, «#rrggbb»; la stringa vuota è «senza fondo».
    public var background: String?

    public init(rules: TableRuleScheme? = nil, ruleWidth: Double? = nil, padding: CellInsets? = nil,
                verticalAlignment: CellVerticalAlignment? = nil, background: String? = nil) {
        self.rules = rules
        self.ruleWidth = ruleWidth
        self.padding = padding
        self.verticalAlignment = verticalAlignment
        self.background = background
    }

    public var isEmpty: Bool { self == TableValues() }

    /// I valori di partenza: griglia di filetti da mezzo punto, margini di 4 punti, testo in alto, senza fondo.
    public static let initial = TableValues(rules: .grid, ruleWidth: 0.5, padding: CellInsets(all: 4), verticalAlignment: .top, background: "")

    /// Questi valori sopra quelli dati: ciò che qui non è detto viene da `base`.
    public func over(_ base: TableValues) -> TableValues {
        TableValues(rules: rules ?? base.rules, ruleWidth: ruleWidth ?? base.ruleWidth, padding: padding ?? base.padding,
                    verticalAlignment: verticalAlignment ?? base.verticalAlignment, background: background ?? base.background)
    }

    /// Una riga di testo «chiave=valore;…», per il segno delle celle nel testo dell'editor.
    var encoded: String {
        var parts: [String] = []
        if let rules { parts.append("rules=\(rules.rawValue)") }
        if let ruleWidth { parts.append("rule-width=\(CellInsets.number(ruleWidth))") }
        if let padding { parts.append("padding=\(padding.text)") }
        if let verticalAlignment { parts.append("valign=\(verticalAlignment.rawValue)") }
        if let background { parts.append("background=\(background)") }
        return parts.joined(separator: ";")
    }

    init?(encoded: String) {
        self.init()
        for part in encoded.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2 else { return nil }
            switch pair[0] {
            case "rules": guard let value = TableRuleScheme(rawValue: pair[1]) else { return nil }; rules = value
            case "rule-width": guard let value = Double(pair[1]), value > 0 else { return nil }; ruleWidth = value
            case "padding": guard let value = CellInsets(text: pair[1], length: { Double($0) }) else { return nil }; padding = value
            case "valign": guard let value = CellVerticalAlignment(rawValue: pair[1]) else { return nil }; verticalAlignment = value
            case "background": background = pair[1]
            default: return nil
            }
        }
    }
}

/// L'aspetto proprio di una cella: i quattro lati, il fondo, l'allineamento verticale, i margini interni. `nil`: come
/// la tabella.
public struct CellValues: Equatable, Sendable {
    public var top: CellBorder?
    public var right: CellBorder?
    public var bottom: CellBorder?
    public var left: CellBorder?
    /// «#rrggbb»; la stringa vuota è «senza fondo».
    public var background: String?
    public var verticalAlignment: CellVerticalAlignment?
    public var padding: CellInsets?

    public init(top: CellBorder? = nil, right: CellBorder? = nil, bottom: CellBorder? = nil, left: CellBorder? = nil,
                background: String? = nil, verticalAlignment: CellVerticalAlignment? = nil, padding: CellInsets? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.background = background
        self.verticalAlignment = verticalAlignment
        self.padding = padding
    }

    public var isEmpty: Bool { self == CellValues() }

    var encoded: String {
        var parts: [String] = []
        for (key, border) in [("top", top), ("right", right), ("bottom", bottom), ("left", left)] {
            if let border { parts.append("\(key)=\(border.text)") }
        }
        if let background { parts.append("background=\(background)") }
        if let verticalAlignment { parts.append("valign=\(verticalAlignment.rawValue)") }
        if let padding { parts.append("padding=\(padding.text)") }
        return parts.joined(separator: ";")
    }

    init?(encoded: String) {
        self.init()
        for part in encoded.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2 else { return nil }
            switch pair[0] {
            case "top", "right", "bottom", "left":
                guard let border = CellBorder(text: pair[1], length: { Double($0) }) else { return nil }
                switch pair[0] {
                case "top": top = border
                case "right": right = border
                case "bottom": bottom = border
                default: left = border
                }
            case "background": background = pair[1]
            case "valign": guard let value = CellVerticalAlignment(rawValue: pair[1]) else { return nil }; verticalAlignment = value
            case "padding": guard let value = CellInsets(text: pair[1], length: { Double($0) }) else { return nil }; padding = value
            default: return nil
            }
        }
    }
}

/// Uno stile di tabella: un nome e l'aspetto che dà alle tabelle che lo usano.
public struct TableStyle: Equatable, Sendable {
    public var name: String
    public var values: TableValues

    public init(name: String, values: TableValues) {
        self.name = name
        self.values = values
    }

    /// Lo stile delle tabelle che non ne indicano uno.
    public static let defaultName = "Griglia"

    /// Gli stili con cui nasce ogni documento.
    public static let builtIn: [TableStyle] = [
        TableStyle(name: defaultName, values: TableValues(rules: .grid)),
        TableStyle(name: "Tre filetti", values: TableValues(rules: .threeRules, ruleWidth: 0.75)),
        TableStyle(name: "Orizzontali", values: TableValues(rules: .horizontal)),
        TableStyle(name: "Bordo", values: TableValues(rules: .frame)),
        TableStyle(name: "Senza filetti", values: TableValues(rules: TableRuleScheme.none)),
    ]

    /// L'aspetto di una tabella: le sue eccezioni sopra il suo stile (o quello predefinito), sopra i valori di partenza.
    public static func resolved(styleName: String?, values: TableValues, in styles: [TableStyle]) -> TableValues {
        let style = styles.first { $0.name == (styleName ?? defaultName) } ?? styles.first { $0.name == defaultName }
        return values.over(style?.values ?? TableValues()).over(.initial)
    }
}
