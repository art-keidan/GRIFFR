import AppKit
import CoreText

/// Un'istanza di un font variabile: il font di base e gli assi fissati esplicitamente. Gli assi assenti restano
/// naturali; in particolare, la dimensione ottica può continuare a seguire il corpo.
public struct VariableFontInstance: Codable, Hashable, Sendable {
    public var fontName: String
    public var variations: [AxisValue]
    public var prefersVariableFont: Bool

    public init(fontName: String, variations: [AxisValue] = [], prefersVariableFont: Bool = true) {
        self.fontName = fontName
        self.variations = variations
        self.prefersVariableFont = prefersVariableFont
    }

    /// L'istanza rappresentata da un font risolto, con il nome di base invece del nome dell'istanza denominata.
    public init(_ font: CTFont) {
        self.init(fontName: FontVariations.baseName(of: font), variations: FontVariations.values(of: font),
                  prefersVariableFont: FontVariations.isShadowed(font))
    }
}

/// Come una famiglia realizza un ruolo. Può conoscere entrambe le forme, per passare da statico a variabile e
/// viceversa; un valore `nil` significa che quella forma non è disponibile o è stata esclusa dalla personalizzazione.
public struct FontRoleEquivalence: Codable, Hashable, Sendable {
    public var staticFace: String?
    public var variableInstance: VariableFontInstance?

    public init(staticFace: String? = nil, variableInstance: VariableFontInstance? = nil) {
        self.staticFace = staticFace
        self.variableInstance = variableInstance
    }

    public var isEmpty: Bool { staticFace == nil && variableInstance == nil }
}

/// Le equivalenze fra ruoli e facce. Quella automatica viene ricavata dalle facce installate; una personalizzazione
/// riguarda una sola coppia famiglia-ruolo e ha la precedenza, finché non viene ripristinata.
///
/// La tabella descrive soltanto le corrispondenze: non cambia il testo e non decide ancora quale forma usare.
public struct FontRoleTable: Codable, Hashable, Sendable {
    public struct Customization: Codable, Hashable, Sendable {
        public var family: String
        public var role: FontRole
        public var equivalence: FontRoleEquivalence

        public init(family: String, role: FontRole, equivalence: FontRoleEquivalence) {
            self.family = family
            self.role = role
            self.equivalence = equivalence
        }
    }

    public private(set) var customizations: [Customization]

    public init(customizations: [Customization] = []) {
        self.customizations = []
        for customization in customizations {
            customize(family: customization.family, role: customization.role, to: customization.equivalence)
        }
    }

    /// L'equivalenza effettiva: quella personalizzata, se esiste, altrimenti quella ricavata dai font installati.
    public func equivalence(family: String, role: FontRole) -> FontRoleEquivalence {
        customization(family: family, role: role)?.equivalence ?? automaticEquivalence(family: family, role: role)
    }

    public func customization(family: String, role: FontRole) -> Customization? {
        customizations.first { $0.family == family && $0.role == role }
    }

    /// Personalizza soltanto questo ruolo. Le altre righe della famiglia non cambiano.
    public mutating func customize(family: String, role: FontRole, to equivalence: FontRoleEquivalence) {
        let value = Customization(family: family, role: role, equivalence: equivalence)
        if let index = customizations.firstIndex(where: { $0.family == family && $0.role == role }) {
            customizations[index] = value
        } else {
            customizations.append(value)
        }
    }

    /// La tabella con le personalizzazioni di `other` sopra le proprie: dove entrambe ne hanno una, vince `other`.
    public func overlaid(by other: FontRoleTable) -> FontRoleTable {
        var result = self
        for customization in other.customizations {
            result.customize(family: customization.family, role: customization.role, to: customization.equivalence)
        }
        return result
    }

    public var isEmpty: Bool { customizations.isEmpty }

    /// Fa tornare questo ruolo all'equivalenza automatica.
    public mutating func resetCustomization(family: String, role: FontRole) {
        customizations.removeAll { $0.family == family && $0.role == role }
    }

    /// La corrispondenza ricavata dalle facce attualmente installate. Se la famiglia è presente sia in file statici
    /// sia come font variabile, riempie entrambi i lati usando la stessa faccia denominata come punto di partenza.
    public func automaticEquivalence(family: String, role: FontRole) -> FontRoleEquivalence {
        AutomaticEquivalences.shared.value(family: family, role: role) { Self.computeAutomaticEquivalence(family: family, role: role) }
    }

    private static func computeAutomaticEquivalence(family: String, role: FontRole) -> FontRoleEquivalence {
        guard let name = FontFaces.face(family: family, italic: role.isItalic, bold: role.isBold),
              let font = NSFont(name: name, size: 12) as CTFont? else { return FontRoleEquivalence() }
        if FontVariations.isVariable(font) {
            return FontRoleEquivalence(staticFace: FontVariations.counterpart(of: font, variable: false)?.postScriptName,
                                       variableInstance: VariableFontInstance(font))
        }
        return FontRoleEquivalence(staticFace: font.postScriptName,
                                   variableInstance: FontVariations.counterpart(of: font, variable: true).map(VariableFontInstance.init))
    }
}

/// Le equivalenze automatiche dipendono solo dai font installati, e trovarle costa (si cercano le facce per nome e
/// l'altra installazione della famiglia): l'interfaccia le chiede molte volte a ogni clic. Si ricordano finché
/// l'elenco dei font del sistema non cambia.
final class AutomaticEquivalences: @unchecked Sendable {
    static let shared = AutomaticEquivalences()
    private let lock = NSLock()
    private var values: [String: FontRoleEquivalence] = [:]

    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name(kCTFontManagerRegisteredFontsChangedNotification as String),
                                               object: nil, queue: nil) { [weak self] _ in self?.clear() }
    }

    func value(family: String, role: FontRole, compute: () -> FontRoleEquivalence) -> FontRoleEquivalence {
        let key = "\(family)|\(role.rawValue)"
        lock.lock()
        if let known = values[key] { lock.unlock(); return known }
        lock.unlock()
        let result = compute()
        lock.lock()
        values[key] = result
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        values = [:]
        lock.unlock()
    }
}
