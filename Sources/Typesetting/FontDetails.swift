import AppKit
import CoreText

// MARK: - Dettagli del font: funzioni, assi, corpo ottico

/// Un dettaglio del font che l'ispettore tratta da solo, come una proprietà: una funzione tipografica, un asse di un
/// font a più assi, il corpo ottico statico. Ognuno ha la sua provenienza, si toglie e si porta nello stile da solo:
/// portare nello stile il maiuscoletto non porta con sé le legature, portare il peso non porta la larghezza.
public enum FontDetail: Hashable, Sendable {
    case feature(FeatureKey)
    /// Un asse, con il suo tag (`wght`, `wdth`…).
    case axis(String)
    case opticalSize
}

/// Che cosa conta come «una funzione»: un tipo AAT esclusivo (le sue voci si escludono: «Maiuscole e minuscole»), una
/// voce di un tipo AAT non esclusivo (si accende e si spegne da sola: «Legature comuni»), un tag OpenType.
public enum FeatureKey: Hashable, Sendable {
    case aatType(Int)
    case aatSwitch(type: Int, selector: Int)
    case openType(String)
}

/// Un dettaglio del font come lo vede l'ispettore in un punto del testo.
public struct InspectedDetail: Equatable, Sendable, Identifiable {
    public var detail: FontDetail
    /// Il nome da mostrare: quello che il font dà alla funzione o all'asse.
    public var title: String
    /// Il valore attuale e quello che darebbero gli stili, già in parole.
    public var value: String
    public var inherited: String
    public var source: ValueSource
    public var isMixed: Bool
    /// Per una funzione, le impostazioni che il testo ha (vuoto se ha quella predefinita).
    public var settings: [FeatureSetting] = []

    public var id: FontDetail { detail }
}

extension TextStyling {
    /// Il valore di un dettaglio in uno stile di carattere, confrontabile: le impostazioni della funzione (in ordine
    /// fisso), il valore dell'asse (`nil` se naturale), il corpo ottico (`nil` se automatico).
    enum DetailValue: Equatable {
        case features([FeatureSetting])
        case axis(Double?)
        case optical(StaticOpticalSize?)
    }

    static func featureTypes(of style: CharacterStyle) -> [FeatureType] {
        FontFeatures.types(of: CTFontCreateWithName(style.fontName as CFString, CGFloat(style.size), nil))
    }

    /// Le funzioni come le tiene davvero il font: Core Text scarta quelle che il font non dichiara. Uno stile può
    /// chiederne di più (lo stile «Maiuscoletto» chiede il maiuscoletto in tre forme, per servire ogni font), ma il
    /// testo ha soltanto quelle che il suo font conosce: si confronta questo, non la richiesta.
    static func effectiveFeatures(_ style: CharacterStyle) -> CharacterStyle {
        var result = style
        result.features = kept(style.features, by: style)
        return result
    }

    /// Le funzioni che il font di `style` terrebbe, fra quelle chieste.
    static func kept(_ features: [FeatureSetting], by style: CharacterStyle) -> [FeatureSetting] {
        guard !features.isEmpty else { return [] }
        let font = CTFontCreateWithName(style.fontName as CFString, CGFloat(style.size), nil)
        return FontFeatures.settings(of: FontFeatures.applying(features, toClean: font))
    }

    /// Vero se le due facce sono della stessa famiglia: il corsivo e il nero cambiano faccia, non famiglia, e funzioni e
    /// assi degli stili valgono anche per loro.
    static func sameFamily(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        func family(_ name: String) -> String {
            let raw = FontFaces.description(of: name)?.family ?? FontVariations.baseName(of: CTFontCreateWithName(name as CFString, 12, nil))
            return OpticalFonts.canonicalFamily(raw) ?? raw
        }
        return family(a) == family(b)
    }

    /// La funzione a cui appartiene un'impostazione, secondo i tipi che il font dichiara.
    static func featureKey(of setting: FeatureSetting, types: [FeatureType]) -> FeatureKey {
        switch setting {
        case .openType(let tag, _):
            return .openType(tag)
        case .aat(let type, _):
            guard let owner = types.first(where: { $0.owns(setting) }), !owner.isExclusive,
                  let selector = owner.selectors.first(where: { $0.setting == setting || $0.offSetting == setting }),
                  case .aat(_, let on) = selector.setting else { return .aatType(type) }
            return .aatSwitch(type: type, selector: on)
        }
    }

    static func value(of detail: FontDetail, in style: CharacterStyle, types: [FeatureType]) -> DetailValue {
        switch detail {
        case .feature(let key):
            return .features(style.features.filter { featureKey(of: $0, types: types) == key }.sorted { $0.description < $1.description })
        case .axis(let tag):
            return .axis(style.variations.last { $0.tag == tag }?.value)
        case .opticalSize:
            return .optical(style.opticalSize)
        }
    }

    /// Lo stile `style` con il dettaglio preso da `source`; il resto non cambia.
    static func replacing(_ detail: FontDetail, in style: CharacterStyle, from source: CharacterStyle, types: [FeatureType]) -> CharacterStyle {
        var result = style
        switch detail {
        case .feature(let key):
            result.features = style.features.filter { featureKey(of: $0, types: types) != key }
                + source.features.filter { featureKey(of: $0, types: types) == key }
        case .axis(let tag):
            let wanted = source.variations.last { $0.tag == tag }
            if let index = style.variations.firstIndex(where: { $0.tag == tag }) {
                if let wanted { result.variations[index] = wanted } else { result.variations.remove(at: index) }
            } else if let wanted {
                result.variations.append(wanted)
            }
        case .opticalSize:
            result.opticalSize = source.opticalSize
        }
        return result
    }

    /// I dettagli presenti nell'uno o nell'altro stile, nell'ordine: funzioni, assi, corpo ottico.
    static func details(in styles: [CharacterStyle], types: [FeatureType]) -> [FontDetail] {
        var result: [FontDetail] = []
        func add(_ detail: FontDetail) { if !result.contains(detail) { result.append(detail) } }
        for style in styles { for setting in style.features { add(.feature(featureKey(of: setting, types: types))) } }
        for style in styles { for axis in style.variations { add(.axis(axis.tag)) } }
        if styles.contains(where: { $0.opticalSize != nil }) { add(.opticalSize) }
        return result
    }

    /// Ciò che gli stili danno per i dettagli in un punto. Se il testo ha un font diverso da quello degli stili, le
    /// funzioni e gli assi degli stili non valgono per lui (cambiare font li azzera): il riferimento è il font del testo
    /// senza funzioni, con gli assi naturali e il corpo ottico automatico.
    static func detailReference(actual: CharacterStyle, expected: CharacterStyle) -> CharacterStyle {
        var reference = actual
        if sameFamily(actual.fontName, expected.fontName) {
            // Stessa famiglia (anche un'altra faccia, come il corsivo): valgono le richieste degli stili, come le tiene
            // il font del testo.
            reference.features = kept(expected.features, by: actual)
            reference.variations = expected.variations
            reference.opticalSize = expected.opticalSize
        } else {
            reference.features = []
            reference.variations = []
            reference.opticalSize = nil
        }
        return reference
    }

    static func styleNames(in text: NSAttributedString, at index: Int) -> StyleNames {
        StyleNames(paragraph: text.attribute(.paragraphStyleName, at: index, effectiveRange: nil) as? String,
                   word: text.attribute(.wordStyleName, at: index, effectiveRange: nil) as? String,
                   character: text.attribute(.characterStyleName, at: index, effectiveRange: nil) as? String)
    }

    /// Il testo in un punto e ciò che gli darebbero i suoi stili per i dettagli.
    static func actualAndExpectedCharacter(in text: NSAttributedString, at index: Int, sheet: StyleSheet,
                                           resolver: FontRoleResolver) -> (actual: CharacterStyle, expected: CharacterStyle, names: StyleNames)? {
        guard let actual = characterStyle(in: text, at: index) else { return nil }
        let names = styleNames(in: text, at: index)
        let expected = sheet.resolveCharacter(paragraphStyle: names.paragraph, wordStyle: names.word, characterStyle: names.character,
                                              base: styleBase, resolver: resolver)
        return (actual, detailReference(actual: actual, expected: expected), names)
    }

    /// Vero se i valori propri di uno stile decidono il dettaglio: lo fissano, o fissano il font (che lo azzera).
    static func decides(_ detail: FontDetail, _ values: StyleValues) -> Bool {
        // Cambiare famiglia o faccia precisa azzera le funzioni; corsivo e nero no, ma scelgono gli assi della faccia.
        let font = values.fontName != nil || values.family != nil
        return switch detail {
        case .feature: values.features != nil || font
        case .axis: values.variations != nil || font || values.italic != nil || values.bold != nil
        case .opticalSize: values.opticalSize != nil || values.fontName != nil || values.family != nil
        }
    }

    /// Lo stile che dà il dettaglio: come per le proprietà, dal più vicino al testo.
    static func definer(of detail: FontDetail, names: StyleNames, sheet: StyleSheet) -> String? {
        let candidates: [(String?, StyleTarget)] = [(names.character, .character), (names.word, .word), (names.paragraph, .paragraph)]
        for (name, target) in candidates {
            var next = name
            var seen: Set<String> = []
            while let current = next, !seen.contains(current), let style = sheet.style(named: current) {
                seen.insert(current)
                if decides(detail, style.values.limited(to: target)) { return current }
                next = style.basedOn
            }
        }
        return nil
    }

    /// Il valore di un dettaglio in parole: la voce scelta di una funzione, il numero di un asse.
    static func describe(_ value: DetailValue, of detail: FontDetail, types: [FeatureType], axes: [FontAxis]) -> String {
        switch value {
        case .features(let settings):
            guard case .feature(let key) = detail, let setting = settings.first else { return "Default" }
            switch key {
            case .aatSwitch(let type, _):
                let owner = types.first { $0.key == .aat(type) }
                if let selector = owner?.selectors.first(where: { $0.setting == setting }) { return selector.isDefault ? "Default" : "On" }
                if owner?.selectors.contains(where: { $0.offSetting == setting }) == true { return "Off" }
                return setting.description
            case .aatType(let type):
                return types.first { $0.key == .aat(type) }?.selectors.first { $0.setting == setting }?.name ?? setting.description
            case .openType(let tag):
                guard case .openType(_, let number) = setting else { return setting.description }
                let owner = types.first { $0.key == .openType(tag) }
                if owner?.isExclusive == true, let selector = owner?.selectors.first(where: { $0.setting == setting }) { return selector.name }
                return switch number { case 0: "Off"; case 1: "On"; default: "Variant \(number)" }
            }
        case .axis(let number):
            guard case .axis(let tag) = detail else { return "" }
            if let number { return DocumentFormat.number(number) }
            // Senza un valore fissato, la dimensione ottica segue il corpo.
            if tag == "opsz" { return "Automatic" }
            return axes.first { $0.tag == tag }.map { "Natural (\(DocumentFormat.number($0.defaultValue)))" } ?? "Natural"
        case .optical(let size):
            return size?.title ?? "Automatic"
        }
    }

    /// Il nome di un dettaglio: quello che gli dà il font.
    static func title(of detail: FontDetail, types: [FeatureType], axes: [FontAxis]) -> String {
        switch detail {
        case .feature(.aatSwitch(let type, let selector)):
            let owner = types.first { $0.key == .aat(type) }
            let name = owner?.selectors.first { $0.setting == .aat(type: type, selector: selector) }?.name
            return name ?? owner?.name ?? "Feature \(type)/\(selector)"
        case .feature(.aatType(let type)):
            return types.first { $0.key == .aat(type) }?.name ?? "Feature \(type)"
        case .feature(.openType(let tag)):
            return types.first { $0.key == .openType(tag) }?.name ?? tag
        case .axis(let tag):
            return axes.first { $0.tag == tag }?.name ?? tag
        case .opticalSize:
            return "Optical size"
        }
    }

    /// I dettagli del font nel punto in cui comincia la selezione, con valore e provenienza: le funzioni, gli assi
    /// fissati e il corpo ottico che il testo o i suoi stili hanno.
    public static func inspectDetails(in text: NSAttributedString, range: NSRange, sheet: StyleSheet,
                                      resolver: FontRoleResolver = FontRoleResolver()) -> [InspectedDetail] {
        guard text.length > 0 else { return [] }
        let start = min(range.location, text.length - 1)
        guard let here = actualAndExpectedCharacter(in: text, at: start, sheet: sheet, resolver: resolver) else { return [] }
        let types = featureTypes(of: here.actual)
        let axes = FontVariations.axes(of: CTFontCreateWithName(here.actual.fontName as CFString, CGFloat(here.actual.size), nil))
        var others: [CharacterStyle] = []
        if range.length > 1 {
            text.enumerateAttributes(in: NSRange(location: start, length: min(range.length, text.length - start))) { _, run, _ in
                if run.location != start, let style = characterStyle(in: text, at: run.location) { others.append(style) }
            }
        }
        return details(in: [here.actual, here.expected], types: types).map { detail in
            let value = Self.value(of: detail, in: here.actual, types: types)
            let inherited = Self.value(of: detail, in: here.expected, types: types)
            let source: ValueSource = value != inherited ? .own : definer(of: detail, names: here.names, sheet: sheet).map(ValueSource.style) ?? .document
            let mixed = others.contains { $0.fontName != here.actual.fontName || Self.value(of: detail, in: $0, types: types) != value }
            let settings: [FeatureSetting] = if case .features(let list) = value { list } else { [] }
            return InspectedDetail(detail: detail, title: title(of: detail, types: types, axes: axes),
                                   value: describe(value, of: detail, types: types, axes: axes),
                                   inherited: describe(inherited, of: detail, types: types, axes: axes), source: source, isMixed: mixed,
                                   settings: settings)
        }
    }

    /// Toglie il dettaglio dato a mano: ogni tratto dell'intervallo lo riprende dai suoi stili; il resto resta com'è.
    public static func resetDetail(_ detail: FontDetail, in text: NSMutableAttributedString, range: NSRange, sheet: StyleSheet,
                                   resolver: FontRoleResolver = FontRoleResolver()) {
        guard text.length > 0 else { return }
        let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        var pieces: [(NSRange, CharacterStyle)] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in
            guard attributes[.missingFont] == nil,
                  let here = actualAndExpectedCharacter(in: text, at: run.location, sheet: sheet, resolver: resolver) else { return }
            let result = replacing(detail, in: here.actual, from: here.expected, types: featureTypes(of: here.actual))
            if result != here.actual { pieces.append((run, result)) }
        }
        for (run, style) in pieces { apply(style, to: text, range: run) }
    }

    /// Gli stili con il dettaglio del punto `index` portato nello stile che riceve le proprietà del carattere (vedi
    /// `receivingStyle`). `nil` se nessuno stile lo può ricevere, o se il testo ha un font diverso da quello degli stili:
    /// una funzione vale solo nel suo font, e prima si porta nello stile la famiglia. Lo stile fissa il dettaglio solo se
    /// differisce da ciò che erediterebbe; le altre funzioni e gli altri assi restano come gli stili li danno.
    public static func sheet(_ sheet: StyleSheet, takingDetail detail: FontDetail, from text: NSAttributedString, at index: Int,
                             resolver: FontRoleResolver = FontRoleResolver()) -> StyleSheet? {
        guard text.length > 0 else { return nil }
        let index = min(index, text.length - 1)
        guard let receiver = receivingStyle(for: .size, in: text, at: index),
              let position = sheet.styles.firstIndex(where: { $0.name == receiver.name }),
              let actual = characterStyle(in: text, at: index) else { return nil }
        let names = styleNames(in: text, at: index)
        func resolved(_ sheet: StyleSheet) -> CharacterStyle {
            sheet.resolveCharacter(paragraphStyle: names.paragraph, wordStyle: names.word, characterStyle: names.character, base: styleBase, resolver: resolver)
        }
        let expected = resolved(sheet)
        guard sameFamily(expected.fontName, actual.fontName) else { return nil }
        let types = featureTypes(of: actual)
        // Ciò che si erediterebbe se lo stile non fissasse il campo, e ciò che gli stili devono dare ora.
        var without = sheet
        switch detail {
        case .feature: without.styles[position].values.features = nil
        case .axis: without.styles[position].values.variations = nil
        case .opticalSize: without.styles[position].values.opticalSize = nil
        }
        let inherited = resolved(without)
        // Lo stile riceve la richiesta degli stili con la sola funzione cambiata: le forme che questo font ignora
        // (ma un altro no) restano.
        let wanted = replacing(detail, in: expected, from: actual, types: types)
        let same = sameFamily(inherited.fontName, wanted.fontName)
        var result = sheet
        switch detail {
        case .feature:
            let unchanged = same && Set(kept(inherited.features, by: actual)) == Set(kept(wanted.features, by: actual))
            result.styles[position].values.features = unchanged ? nil : wanted.features
        case .axis:
            result.styles[position].values.variations = same && Set(inherited.variations) == Set(wanted.variations) ? nil : wanted.variations
        case .opticalSize:
            result.styles[position].values.opticalSize = inherited.opticalSize == wanted.opticalSize ? nil : (wanted.opticalSize?.rawValue ?? "")
        }
        return result
    }

    /// Le funzioni del testo dopo un cambio di stili, una per una: quella che valeva quanto davano gli stili di prima
    /// prende il valore nuovo, quella data a mano resta. Vale dentro uno stesso font; altrimenti conta l'elenco intero.
    static func restyledFeatures(_ current: CharacterStyle, from old: CharacterStyle, to new: CharacterStyle) -> [FeatureSetting] {
        // Il caso comune (nessuna funzione data a mano) non ha bisogno di chiedere al font i suoi tipi.
        if current.features == old.features { return new.features }
        guard sameFamily(current.fontName, old.fontName), sameFamily(old.fontName, new.fontName), old.features != new.features else { return current.features }
        let types = featureTypes(of: current)
        // Si confronta ciò che il font del testo tiene davvero; il testo prende poi la richiesta nuova degli stili.
        var oldKept = old
        oldKept.features = kept(old.features, by: current)
        var result = current
        for detail in details(in: [current, oldKept, new], types: types) {
            guard case .feature = detail else { continue }
            if value(of: detail, in: current, types: types) == value(of: detail, in: oldKept, types: types) {
                result = replacing(detail, in: result, from: new, types: types)
            }
        }
        return result.features
    }

    /// Gli assi del testo dopo un cambio di stili, uno per uno, come le funzioni.
    static func restyledVariations(_ current: CharacterStyle, from old: CharacterStyle, to new: CharacterStyle) -> [AxisValue] {
        if current.variations == old.variations { return new.variations }
        guard sameFamily(current.fontName, old.fontName), sameFamily(old.fontName, new.fontName), old.variations != new.variations else { return current.variations }
        var result = current
        let tags = (current.variations + old.variations + new.variations).map(\.tag).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for tag in tags where value(of: .axis(tag), in: current, types: []) == value(of: .axis(tag), in: old, types: []) {
            result = replacing(.axis(tag), in: result, from: new, types: [])
        }
        return result.variations
    }
}
