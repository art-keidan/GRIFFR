import AppKit
import CoreText

/// Un asse di variazione di un font (tabella `fvar`): peso, larghezza, corpo ottico, o un asse proprio del font.
public struct FontAxis: Hashable, Sendable, Identifiable {
    /// Il tag di quattro lettere dell'asse (`wght`, `wdth`, `opsz`…).
    public var tag: String
    /// Il nome dell'asse come lo dichiara il font, nella lingua del sistema se c'è.
    public var name: String
    public var minimum: Double
    public var maximum: Double
    public var defaultValue: Double
    /// Assi che il font chiede di non mostrare all'utente.
    public var isHidden: Bool

    public var id: String { tag }
}

/// Il valore scelto per un asse. Nel file si scrive `tag=valore`, per esempio `wght=650`.
public struct AxisValue: Codable, Hashable, Sendable, CustomStringConvertible {
    public var tag: String
    public var value: Double

    public init(tag: String, value: Double) {
        self.tag = tag
        self.value = value
    }

    public var description: String { "\(tag)=\(DocumentFormat.number(value))" }
}

/// Lettura e modifica degli assi di variazione attraverso Core Text.
///
/// Un font a più assi è un solo file da cui si ricavano infiniti disegni; le facce con un nome (Bold, Condensed…)
/// sono soltanto punti segnalati dal disegnatore. Qui una faccia è sempre descritta come il font di base più i
/// valori degli assi fissati esplicitamente.
///
/// Gli assi non fissati restano «naturali»: di norma al valore predefinito, ma per alcuni font Core Text regola
/// da sé l'asse della dimensione ottica (`opsz`) secondo il corpo (osservato su Merriweather: a corpo 60 l'asse
/// vale 60 senza che nessuno l'abbia chiesto, e torna a seguire il corpo quando questo cambia). Fissare
/// esplicitamente quell'asse, anche al valore predefinito, spegne la regolazione: per questo un asse si scrive
/// solo se il suo valore è diverso da quello naturale.
public enum FontVariations {
    /// Gli assi del font, nell'ordine in cui li dichiara. Vuoto per un font che non ne ha.
    public static func axes(of font: CTFont) -> [FontAxis] {
        // Core Text ricompone a ogni chiamata i nomi localizzati degli assi (0,2 ms per Adobe Kis VF), e l'interfaccia
        // lo chiede centinaia di volte a ogni clic. Gli assi dipendono solo dal file e dalla famiglia: si ricordano.
        let key = fileURL(of: font).map { "\($0.path)|\(CTFontCopyFamilyName(font) as String)" }
        if let key {
            axisLock.lock()
            let known = axisCache[key]
            axisLock.unlock()
            if let known { return known }
        }
        let result = readAxes(of: font)
        if let key {
            axisLock.lock()
            axisCache[key] = result
            axisLock.unlock()
        }
        return result
    }

    /// Se il peso di partenza del file è diverso da quello della sua istanza Regular (o Italic): in Adobe Kis VF si parte
    /// da 300 («Default Roman»), il Regular è 400. In Skia il Regular è proprio il punto di partenza.
    static func naturalWeightIsNotRegular(_ font: CTFont) -> Bool {
        guard let url = fileURL(of: font) else { return false }
        axisLock.lock()
        let known = regularWeightCache[url.path]
        axisLock.unlock()
        if let known { return known }
        var result = false
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        if let natural = axes(of: font).first(where: { $0.tag == "wght" })?.defaultValue,
           let regular = descriptors.first(where: { ["Regular", "Italic"].contains(CTFontDescriptorCopyAttribute($0, kCTFontStyleNameAttribute) as? String ?? "") }),
           let variation = CTFontDescriptorCopyAttribute(regular, kCTFontVariationAttribute) as? [NSNumber: NSNumber],
           let weight = variation[NSNumber(value: identifier("wght"))]?.doubleValue {
            result = !isSame(weight, natural)
        }
        axisLock.lock()
        regularWeightCache[url.path] = result
        axisLock.unlock()
        return result
    }
    nonisolated(unsafe) private static var regularWeightCache: [String: Bool] = [:]

    /// Un lucchetto suo: `baseName` chiede gli assi tenendo già `lock`.
    private static let axisLock = NSLock()
    nonisolated(unsafe) private static var axisCache: [String: [FontAxis]] = [:]

    /// Gli assi registrati di OpenType, con il loro nome inglese.
    static let registeredAxisNames = ["wght": "Weight", "wdth": "Width", "ital": "Italic", "slnt": "Slant", "opsz": "Optical size", "GRAD": "Grade"]

    private static func readAxes(of font: CTFont) -> [FontAxis] {
        guard let raw = CTFontCopyVariationAxes(font) as? [[CFString: Any]] else { return [] }
        return raw.compactMap { axis in
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber,
                  let minimum = axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber,
                  let maximum = axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber,
                  let defaultValue = axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber else { return nil }
            let tag = tag(identifier.uint32Value)
            // I nomi degli assi registrati non dipendono dalla lingua del sistema (macOS li darebbe localizzati).
            let name = registeredAxisNames[tag] ?? axis[kCTFontVariationAxisNameKey] as? String ?? tag
            return FontAxis(tag: tag, name: name, minimum: minimum.doubleValue, maximum: maximum.doubleValue,
                            defaultValue: defaultValue.doubleValue, isHidden: (axis[kCTFontVariationAxisHiddenKey] as? NSNumber)?.boolValue ?? false)
        }
    }

    /// Il valore che ogni asse ha effettivamente in questo font, fissato o naturale che sia.
    public static func coordinates(of font: CTFont) -> [String: Double] {
        let current = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        var result: [String: Double] = [:]
        for axis in axes(of: font) { result[axis.tag] = current[NSNumber(value: identifier(axis.tag))]?.doubleValue ?? axis.defaultValue }
        return result
    }

    /// I valori degli assi fissati in questo font: quelli diversi dal valore naturale, nell'ordine degli assi.
    public static func values(of font: CTFont) -> [AxisValue] {
        let axes = axes(of: font)
        guard !axes.isEmpty else { return [] }
        let actual = coordinates(of: font), natural = coordinates(of: naturalFont(for: font))
        // La dimensione ottica automatica segue il corpo: non è un valore fissato.
        let automatic = hasAutomaticOpticalSize(font)
        return axes.compactMap { axis in
            guard !(automatic && axis.tag == "opsz") else { return nil }
            // Il peso di partenza conta come fissato se il tondo del font è a un altro peso: il 300 di Adobe Kis VF
            // altrimenti si confonderebbe con «nessun peso», e chi lo rilegge prenderebbe il Regular (400).
            guard let value = actual[axis.tag],
                  !isSame(value, natural[axis.tag] ?? axis.defaultValue) || (axis.tag == "wght" && naturalWeightIsNotRegular(font)) else { return nil }
            // Quattro decimali, come nel file: così il valore letto dal font e quello riletto dal file coincidono.
            return AxisValue(tag: axis.tag, value: (value * 10_000).rounded() / 10_000)
        }
    }

    /// Lo stesso font con esattamente i valori dati: gli assi non nominati tornano naturali, i valori fuori dai
    /// limiti dell'asse vengono riportati al limite. Corpo e funzioni tipografiche restano quelli del font.
    public static func font(_ font: CTFont, with variations: [AxisValue]) -> CTFont {
        guard isVariable(font) else { return font }
        return FontFeatures.applying(FontFeatures.settings(of: font), toClean: instance(of: font, with: variations))
    }

    /// Accende o spegne la regolazione ottica automatica. Spegnendola si congela il disegno ottico attuale,
    /// così il gesto non cambia l'aspetto del testo; i successivi cambi di corpo non sposteranno più `opsz`.
    public static func font(_ font: CTFont, automaticOpticalSize: Bool) -> CTFont {
        guard let axis = axes(of: font).first(where: { $0.tag == "opsz" }) else { return font }
        var updated = values(of: font).filter { $0.tag != "opsz" }
        // Si blocca il disegno che si vede: con la dimensione ottica automatica, quello del corpo.
        if !automaticOpticalSize, let current = coordinates(of: withAutomaticOpticalSize(font))["opsz"] {
            var frozen = current
            // Core Text scarta un valore `opsz` esplicito se coincide con quello naturale: al cambio di corpo
            // ricomincerebbe a seguirlo. Uno scarto di 1/10.000 pt, impercettibile, rende il blocco effettivo.
            if let natural = coordinates(of: naturalFont(for: font))["opsz"], isSame(current, natural) {
                let adjustment = 0.0001
                frozen = current + adjustment <= axis.maximum ? current + adjustment : current - adjustment
            }
            updated.append(AxisValue(tag: "opsz", value: frozen))
        }
        return self.font(font, with: updated)
    }

    /// Il font come lo compone Core Text quando la dimensione ottica non è fissata: se ha l'asse `opsz`, segue il corpo.
    ///
    /// Core Text lo fa da sé solo per alcuni font (Merriweather); per altri (Adobe Kis VF) l'asse resta al valore
    /// predefinito a qualsiasi corpo, finché non gli si chiede la dimensione ottica automatica (provato il 2 novembre
    /// 2026: a 36 pt Adobe Kis VF senza richiesta è largo quanto con `opsz` 12, con la richiesta quanto con `opsz` 36).
    /// Un valore fissato vince sulla richiesta.
    public static func withAutomaticOpticalSize(_ font: CTFont) -> CTFont {
        guard !hasAutomaticOpticalSize(font), axes(of: font).contains(where: { $0.tag == "opsz" }) else { return font }
        let current = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        guard current[NSNumber(value: identifier("opsz"))] == nil else { return font }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [kCTFontOpticalSizeAttribute: "auto"] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }

    /// Vero se al font è stata chiesta la dimensione ottica automatica.
    public static func hasAutomaticOpticalSize(_ font: CTFont) -> Bool {
        (CTFontCopyAttribute(font, kCTFontOpticalSizeAttribute) as? String) == "auto"
    }

    /// La faccia con i valori dati, senza funzioni tipografiche: il font di base, letto dallo stesso file, a cui
    /// si fissano gli assi nominati.
    static func instance(of font: CTFont, with variations: [AxisValue]) -> CTFont {
        let axes = axes(of: font)
        var result = naturalFont(for: font)
        var coordinates: [NSNumber: NSNumber] = [:]
        for axis in axes {
            guard let wanted = variations.last(where: { $0.tag == axis.tag })?.value else { continue }
            coordinates[NSNumber(value: identifier(axis.tag))] = NSNumber(value: min(max(wanted, axis.minimum), axis.maximum))
        }
        if !coordinates.isEmpty {
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(result), [kCTFontVariationAttribute: coordinates] as CFDictionary)
            result = CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
        }
        return result
    }

    /// Il nome PostScript del font di base: quello con tutti gli assi al valore predefinito. Per un font senza
    /// assi è il suo nome. Le facce con un nome e quelle ottenute spostando gli assi hanno nomi PostScript
    /// diversi (Core Text vi scrive in coda i valori), ma lo stesso font di base.
    public static func baseName(of font: CTFont) -> String {
        let name = font.postScriptName
        guard let current = CTFontCopyVariation(font) as? [NSNumber: NSNumber], !current.isEmpty else { return name }
        lock.lock()
        defer { lock.unlock() }
        if let known = baseNames[name] { return known }
        let base = allDefaults(font).postScriptName
        baseNames[name] = base
        return base
    }

    /// Il font di base al corpo di `font`, senza alcun asse fissato: è ciò che si ottiene aprendolo per nome dallo
    /// stesso file, ed è il riferimento rispetto a cui un asse risulta fissato o no.
    static func naturalFont(for font: CTFont) -> CTFont {
        let base = baseName(of: font)
        let size = CTFontGetSize(font)
        var candidate = CTFontCreateWithName(base as CFString, size, nil)
        if candidate.postScriptName != base || !isVariable(candidate), let url = fileURL(of: font) {
            // Per nome si otterrebbe un altro file (la stessa famiglia installata anche in file statici): si chiede questo.
            candidate = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: base, kCTFontURLAttribute: url] as CFDictionary), size, nil)
        }
        // Un font caricato da un file e non installato non si ritrova per nome: si ripiega sui valori predefiniti.
        return candidate.postScriptName == base && isVariable(candidate) ? candidate : allDefaults(font)
    }

    /// Il font con tutti gli assi fissati al valore predefinito.
    private static func allDefaults(_ font: CTFont) -> CTFont {
        var coordinates: [NSNumber: NSNumber] = [:]
        for axis in axes(of: font) { coordinates[NSNumber(value: identifier(axis.tag))] = NSNumber(value: axis.defaultValue) }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [kCTFontVariationAttribute: coordinates] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var baseNames: [String: String] = [:]

    // MARK: Lo stesso font installato in due modi

    // Una famiglia può essere installata due volte: come font a più assi e come file statici separati, uno per
    // faccia, con gli stessi nomi. Aprendo un font per nome macOS dà allora il file statico (provato su Noto
    // Sans); il font a più assi si ottiene chiedendo espressamente il suo file.

    public static func isVariable(_ font: CTFont) -> Bool { !axes(of: font).isEmpty }

    /// Il file da cui il font è letto.
    public static func fileURL(of font: CTFont) -> URL? {
        CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
    }

    /// Apre un font per nome PostScript. Con `preferringVariable`, se il nome esiste sia in un file statico sia in
    /// un font a più assi, si prende quest'ultimo.
    public static func font(named name: String, size: CGFloat, preferringVariable: Bool) -> CTFont? {
        guard let found = NSFont(name: name, size: size) else { return nil }
        guard preferringVariable, !isVariable(found as CTFont) else { return found as CTFont }
        let query = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        for match in CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] ?? [] {
            guard let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL else { continue }
            let candidate = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name, kCTFontURLAttribute: url] as CFDictionary), size, nil)
            if isVariable(candidate) { return candidate }
        }
        return found as CTFont
    }

    /// Vero se il font è a più assi ma, aprendolo per nome, si otterrebbe un file statico: nel documento va
    /// allora detto espressamente che si vuole il font a più assi.
    public static func isShadowed(_ font: CTFont) -> Bool {
        guard isVariable(font) else { return false }
        let base = baseName(of: font)
        lock.lock()
        defer { lock.unlock() }
        if let known = shadowed[base] { return known }
        let result = !(NSFont(name: base, size: 12).map { isVariable($0 as CTFont) } ?? false)
        shadowed[base] = result
        return result
    }

    /// La stessa faccia (stessa famiglia e stesso stile) presa dall'altra installazione della famiglia: quella a
    /// più assi se `variable`, altrimenti quella in file statici. `nil` se la famiglia è installata in un modo solo.
    /// Corpo e funzioni restano quelli del font; passando ai file statici gli assi spostati a mano si perdono, e
    /// se la faccia non ha un file statico suo si prende il tondo.
    public static func counterpart(of font: CTFont, variable: Bool) -> CTFont? {
        guard isVariable(font) != variable else { return font }
        let family = CTFontCopyFamilyName(font) as String
        let style = CTFontCopyAttribute(font, kCTFontStyleNameAttribute) as? String ?? "Regular"
        let size = CTFontGetSize(font)
        for styleName in style == "Regular" ? [style] : [style, "Regular"] {
            let query = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family, kCTFontStyleNameAttribute: styleName] as CFDictionary)
            for match in CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] ?? [] {
                let candidate = CTFontCreateWithFontDescriptor(match, size, nil)
                guard isVariable(candidate) == variable, CTFontCopyFamilyName(candidate) as String == family else { continue }
                return FontFeatures.font(candidate, with: FontFeatures.settings(of: font))
            }
        }
        return nil
    }

    nonisolated(unsafe) private static var shadowed: [String: Bool] = [:]

    /// Due valori di un asse sono lo stesso se coincidono nella precisione con cui i font li conservano (1/65536).
    static func isSame(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1.0 / 32768 }

    private static func tag(_ identifier: UInt32) -> String {
        String(bytes: [UInt8(identifier >> 24), UInt8(identifier >> 16 & 0xFF), UInt8(identifier >> 8 & 0xFF), UInt8(identifier & 0xFF)], encoding: .isoLatin1) ?? ""
    }

    private static func identifier(_ tag: String) -> UInt32 {
        tag.unicodeScalars.prefix(4).reduce(UInt32(0)) { $0 << 8 | ($1.value & 0xFF) }
    }
}
