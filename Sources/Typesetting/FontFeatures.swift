import CoreText
import Foundation

/// Un'impostazione non predefinita di una funzione tipografica, nella forma in cui la si passa a Core Text.
public enum FeatureSetting: Hashable, Sendable, CustomStringConvertible {
    /// Coppia tipo/selettore AAT (tabella `feat`), compresi i selettori definiti dal font.
    case aat(type: Int, selector: Int)
    /// Tag OpenType con il suo valore (0 = spenta, 1 = accesa, n = n-esima alternativa).
    case openType(tag: String, value: Int)

    public var description: String {
        switch self {
        case .aat(let type, let selector): "\(type)/\(selector)"
        case .openType(let tag, let value): "\(tag)=\(value)"
        }
    }

    var dictionary: CFDictionary {
        switch self {
        case .aat(let type, let selector):
            [kCTFontFeatureTypeIdentifierKey: type, kCTFontFeatureSelectorIdentifierKey: selector] as CFDictionary
        case .openType(let tag, let value):
            [kCTFontOpenTypeFeatureTag: tag, kCTFontOpenTypeFeatureValue: value] as CFDictionary
        }
    }

    init?(dictionary: [String: Any]) {
        // Per le funzioni OpenType che hanno un equivalente AAT Core Text restituisce entrambe le forme: teniamo quella AAT.
        if let type = dictionary[kCTFontFeatureTypeIdentifierKey as String] as? Int,
           let selector = dictionary[kCTFontFeatureSelectorIdentifierKey as String] as? Int {
            self = .aat(type: type, selector: selector)
        } else if let tag = dictionary[kCTFontOpenTypeFeatureTag as String] as? String,
                  let value = dictionary[kCTFontOpenTypeFeatureValue as String] as? Int {
            self = .openType(tag: tag, value: value)
        } else {
            return nil
        }
    }
}

/// Una voce selezionabile dentro un tipo di funzione.
public struct FeatureSelector: Hashable, Sendable, Identifiable {
    public var name: String
    public var isDefault: Bool
    /// Tag OpenType corrispondente, se il font lo dichiara.
    public var openTypeTag: String?
    /// Impostazione che attiva questa voce.
    public var setting: FeatureSetting
    /// Impostazione che la spegne esplicitamente (solo nei tipi non esclusivi).
    public var offSetting: FeatureSetting?

    public var id: FeatureSetting { setting }
}

/// Un tipo di funzione così come lo elenca il font: un gruppo di voci, esclusive tra loro oppure indipendenti.
public struct FeatureType: Hashable, Sendable, Identifiable {
    public enum Key: Hashable, Sendable {
        case aat(Int)
        case openType(String)
    }

    public var key: Key
    public var name: String
    public var isExclusive: Bool
    public var selectors: [FeatureSelector]

    public var id: Key { key }

    func owns(_ setting: FeatureSetting) -> Bool {
        switch (key, setting) {
        case (.aat(let type), .aat(let settingType, _)): type == settingType
        case (.openType(let tag), .openType(let settingTag, _)): tag == settingTag
        default: false
        }
    }
}

extension FeatureType {
    /// La voce attiva di un tipo esclusivo, date le impostazioni correnti.
    public func activeSelector(in settings: [FeatureSetting]) -> FeatureSelector? {
        selectors.first { settings.contains($0.setting) } ?? selectors.first(where: \.isDefault) ?? selectors.first
    }

    /// Stato di una voce di un tipo non esclusivo, date le impostazioni correnti.
    public func isOn(_ selector: FeatureSelector, in settings: [FeatureSetting]) -> Bool {
        if settings.contains(selector.setting) { return true }
        if let off = selector.offSetting, settings.contains(off) { return false }
        return selector.isDefault
    }

    /// Sceglie una voce di un tipo esclusivo. Scegliere la voce predefinita toglie l'impostazione.
    public func selecting(_ selector: FeatureSelector, in settings: [FeatureSetting]) -> [FeatureSetting] {
        var result = settings.filter { !owns($0) }
        if !selector.isDefault { result.append(selector.setting) }
        return result
    }

    /// Accende o spegne una voce di un tipo non esclusivo. Tornare al valore predefinito toglie l'impostazione.
    public func setting(_ selector: FeatureSelector, on: Bool, in settings: [FeatureSetting]) -> [FeatureSetting] {
        var result = settings.filter { $0 != selector.setting && $0 != selector.offSetting }
        if on != selector.isDefault, let change = on ? selector.setting : selector.offSetting {
            result.append(change)
        }
        return result
    }
}

public enum FontFeatures {
    /// Le funzioni del font, lette dal font stesso attraverso `CTFontCopyFeatures`.
    ///
    /// Core Text elenca qui sia i tipi AAT della tabella `feat` (compresi quelli definiti dal font)
    /// sia le funzioni OpenType selezionabili dall'utente; quelle senza equivalente AAT (per esempio `cvNN`)
    /// compaiono come tipi identificati dal solo tag.
    public static func types(of font: CTFont) -> [FeatureType] {
        let raw = CTFontCopyFeatures(font) as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            let aatType = entry[kCTFontFeatureTypeIdentifierKey as String] as? Int
            let typeTag = entry[kCTFontOpenTypeFeatureTag as String] as? String
            let key: FeatureType.Key
            if let aatType { key = .aat(aatType) } else if let typeTag { key = .openType(typeTag) } else { return nil }
            let isExclusive = (entry[kCTFontFeatureTypeExclusiveKey as String] as? Bool) ?? false
            let rawSelectors = entry[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            let selectors: [FeatureSelector] = rawSelectors.compactMap { item in
                let tag = item[kCTFontOpenTypeFeatureTag as String] as? String
                let value = item[kCTFontOpenTypeFeatureValue as String] as? Int
                let selector = item[kCTFontFeatureSelectorIdentifierKey as String] as? Int
                let setting: FeatureSetting
                var off: FeatureSetting?
                if let aatType, let selector {
                    setting = .aat(type: aatType, selector: selector)
                    // Convenzione AAT per i tipi non esclusivi: selettore pari = acceso, il dispari successivo = spento.
                    if !isExclusive { off = .aat(type: aatType, selector: selector + 1) }
                } else if let tag, let value {
                    setting = .openType(tag: tag, value: value)
                    if !isExclusive { off = .openType(tag: tag, value: 0) }
                } else {
                    return nil
                }
                return FeatureSelector(
                    name: item[kCTFontFeatureSelectorNameKey as String] as? String ?? setting.description,
                    isDefault: (item[kCTFontFeatureSelectorDefaultKey as String] as? Bool) ?? false,
                    openTypeTag: tag, setting: setting, offSetting: off)
            }
            guard !selectors.isEmpty else { return nil }
            return FeatureType(key: key, name: entry[kCTFontFeatureTypeNameKey as String] as? String ?? "\(key)",
                               isExclusive: isExclusive, selectors: selectors)
        }
    }

    /// Le impostazioni non predefinite attive su un font.
    public static func settings(of font: CTFont) -> [FeatureSetting] {
        let raw = CTFontCopyFeatureSettings(font) as? [[String: Any]] ?? []
        return raw.compactMap(FeatureSetting.init(dictionary:))
    }

    /// Restituisce lo stesso font con esattamente le impostazioni date.
    ///
    /// Core Text *fonde* le nuove impostazioni con quelle già presenti nel descrittore, quindi per poterne
    /// togliere una si riparte ogni volta dal descrittore ripulito.
    public static func font(_ font: CTFont, with settings: [FeatureSetting]) -> CTFont {
        // Un font a più assi può essere installato anche in file statici con gli stessi nomi: un descrittore
        // ricostruito dal solo nome porterebbe a quelli. Si riparte allora dalla stessa faccia senza funzioni,
        // ottenuta dallo stesso file, e le si aggiungono le impostazioni.
        if FontVariations.isVariable(font) {
            return applying(settings, toClean: FontVariations.instance(of: font, with: FontVariations.values(of: font)))
        }
        let attributes = NSMutableDictionary(dictionary: CTFontDescriptorCopyAttributes(CTFontCopyFontDescriptor(font)))
        attributes.removeObject(forKey: kCTFontFeatureSettingsAttribute)
        attributes.removeObject(forKey: kCTFontFeaturesAttribute)
        if !settings.isEmpty {
            attributes[kCTFontFeatureSettingsAttribute] = settings.map(\.dictionary)
        }
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes), CTFontGetSize(font), nil)
    }

    /// Aggiunge le impostazioni a un font che non ne ha: su un descrittore pulito la fusione dà esattamente quelle.
    static func applying(_ settings: [FeatureSetting], toClean font: CTFont) -> CTFont {
        guard !settings.isEmpty else { return font }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [kCTFontFeatureSettingsAttribute: settings.map(\.dictionary)] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }

    /// Tag delle funzioni dichiarate nelle tabelle GSUB e GPOS, letti direttamente dalle tabelle.
    public static func openTypeTags(of font: CTFont) -> (gsub: [String], gpos: [String]) {
        (featureListTags(font.tableBytes("GSUB")), featureListTags(font.tableBytes("GPOS")))
    }

    /// Tag GSUB/GPOS che `CTFontCopyFeatures` non elenca: in genere funzioni di composizione applicate
    /// automaticamente (`ccmp`, `locl`, `mark`…), oppure funzioni che Core Text non usa per quel font.
    public static func unlistedOpenTypeTags(of font: CTFont) -> [String] {
        let listed = Set(types(of: font).flatMap { type -> [String] in
            var tags = type.selectors.compactMap(\.openTypeTag)
            if case .openType(let tag) = type.key { tags.append(tag) }
            return tags
        })
        let all = openTypeTags(of: font)
        var seen: Set<String> = []
        return (all.gsub + all.gpos).filter { !listed.contains($0) && seen.insert($0).inserted }
    }

    /// Tra i tag non elencati, quelli che Core Text accetta di forzare: l'impostazione, una volta data, si
    /// rilegge dal font. Per gli altri (di norma `ccmp`, `locl`, `mark`, le forme arabe e indiane) Core Text
    /// scarta l'ordine: sono applicati dal motore di composizione e non si comandano (provato su Merriweather,
    /// Times New Roman, Kohinoor Devanagari).
    public static func forceableOpenTypeTags(of font: CTFont) -> [String] {
        let name = font.postScriptName
        forceableLock.lock()
        defer { forceableLock.unlock() }
        if let known = forceable[name] { return known }
        let clean = Self.font(font, with: [])
        let result = unlistedOpenTypeTags(of: font).filter { tag in
            settings(of: Self.font(clean, with: [.openType(tag: tag, value: 1)])).contains(.openType(tag: tag, value: 1))
        }
        forceable[name] = result
        return result
    }

    private static let forceableLock = NSLock()
    nonisolated(unsafe) private static var forceable: [String: [String]] = [:]

    private static func featureListTags(_ bytes: [UInt8]) -> [String] {
        // Intestazione GSUB/GPOS: versione (4 byte), poi gli offset di ScriptList, FeatureList, LookupList.
        guard bytes.count >= 10 else { return [] }
        let list = Int(bytes[6]) << 8 | Int(bytes[7])
        guard list + 2 <= bytes.count else { return [] }
        let count = Int(bytes[list]) << 8 | Int(bytes[list + 1])
        var tags: [String] = []
        for index in 0..<count {
            let offset = list + 2 + 6 * index
            guard offset + 4 <= bytes.count else { break }
            if let tag = String(bytes: bytes[offset..<offset + 4], encoding: .isoLatin1), !tags.contains(tag) { tags.append(tag) }
        }
        return tags
    }
}
