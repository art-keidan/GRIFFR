import Foundation
import Typesetting

/// Le equivalenze sono preferenze dell'applicazione: i documenti conservano i ruoli, non una copia della tabella.
enum FontRolePreferences {
    static let key = "FontRoleEquivalences"

    static func table(from defaults: UserDefaults = .standard) -> FontRoleTable {
        guard let data = defaults.data(forKey: key),
              let table = try? JSONDecoder().decode(FontRoleTable.self, from: data) else { return FontRoleTable() }
        return table
    }

    static func save(_ table: FontRoleTable, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Impostazioni › Fonts: come si presentano le famiglie nei menu.
enum FontMenuPreferences {
    static let key = "groupsFontFamilies"

    /// Se le famiglie che cominciano con la stessa parola («Noto Sans», «Noto Serif»…) stanno in un sottomenu. Acceso
    /// finché non lo si spegne.
    static var groupsFamilies: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .fontMenuGroupingChanged, object: nil)
        }
    }
}

extension Notification.Name {
    /// L'impostazione del raggruppamento delle famiglie è cambiata: i menu delle famiglie si rifanno.
    static let fontMenuGroupingChanged = Notification.Name("WordProcessorFontMenuGroupingChanged")
}

extension FontRole {
    /// Il nome del ruolo nei menu.
    var displayName: String {
        switch self {
        case .regular: "Regular"
        case .italic: "Italic"
        case .bold: "Bold"
        case .boldItalic: "Bold Italic"
        }
    }
}
