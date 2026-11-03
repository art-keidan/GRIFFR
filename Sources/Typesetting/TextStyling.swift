import AppKit
import CoreText

/// Operazioni sugli attributi di un testo: font, corpo, funzioni tipografiche.
public enum TextStyling {
    /// I tratti di testo con lo stesso font dentro un intervallo.
    public static func fontRuns(in text: NSAttributedString, range: NSRange) -> [(font: CTFont, range: NSRange)] {
        var runs: [(font: CTFont, range: NSRange)] = []
        text.enumerateAttribute(.font, in: range) { value, runRange, _ in
            // NSFont e CTFont sono lo stesso oggetto (toll-free bridging).
            if let font = value as? NSFont { runs.append((font as CTFont, runRange)) }
        }
        return runs
    }

    /// Modifica le impostazioni delle funzioni nei tratti che usano il font indicato; gli altri tratti restano intatti,
    /// perché tipi e selettori hanno senso solo dentro il font che li dichiara.
    /// - Parameter baseName: il nome del font di base (`FontVariations.baseName`): le facce di uno stesso font a
    ///   più assi hanno le stesse funzioni.
    /// - Returns: il numero di tratti modificati.
    @discardableResult
    public static func updateFeatures(
        in text: NSMutableAttributedString, range: NSRange, ofFontNamed baseName: String,
        _ transform: ([FeatureSetting]) -> [FeatureSetting]
    ) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) where FontVariations.baseName(of: run.font) == baseName {
            let current = FontFeatures.settings(of: run.font)
            let updated = transform(current)
            guard updated != current else { continue }
            // Il maiuscoletto acceso o spento qui diventa la scelta tipografica: le sue forme si chiedono tutte, e il
            // testo lo registra anche dove il font non ne ha una (il maiuscoletto delle sigle in Hoefler Text).
            let shown = SmallCaps.split(current).smallCaps, wanted = SmallCaps.split(updated)
            var pieces: [(NSRange, SmallCaps)] = []
            text.enumerateAttribute(.smallCaps, in: run.range) { value, piece, _ in
                let recorded = (value as? String).flatMap(SmallCaps.init(rawValue:)) ?? shown
                let lowercase = shown.hasLowercase != wanted.smallCaps.hasLowercase ? wanted.smallCaps.hasLowercase : recorded.hasLowercase
                let uppercase = shown.hasUppercase != wanted.smallCaps.hasUppercase ? wanted.smallCaps.hasUppercase : recorded.hasUppercase
                pieces.append((piece, SmallCaps(lowercase: lowercase, uppercase: uppercase)))
            }
            for (piece, smallCaps) in pieces {
                TextStyling.writeFont(FontFeatures.font(run.font, with: wanted.rest + smallCaps.forms), in: text, range: piece)
                if smallCaps == .off { text.removeAttribute(.smallCaps, range: piece) } else { text.addAttribute(.smallCaps, value: smallCaps.rawValue, range: piece) }
            }
            changed += 1
        }
        return changed
    }

    /// Sposta gli assi di variazione nei tratti che usano il font indicato (per nome del font di base); gli altri
    /// tratti restano intatti, perché gli assi hanno senso solo dentro il font che li dichiara.
    /// - Returns: il numero di tratti modificati.
    @discardableResult
    public static func updateVariations(
        in text: NSMutableAttributedString, range: NSRange, ofFontNamed baseName: String,
        _ transform: ([AxisValue]) -> [AxisValue]
    ) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) where FontVariations.baseName(of: run.font) == baseName {
            let current = FontVariations.values(of: run.font)
            let updated = transform(current)
            guard updated != current else { continue }
            TextStyling.writeFont(FontVariations.font(run.font, with: updated), in: text, range: run.range)
            changed += 1
        }
        return changed
    }

    /// Collega `opsz` al corpo oppure ne congela il valore attuale in ciascun tratto dello stesso font.
    /// I tratti di altre famiglie e gli altri assi restano invariati.
    @discardableResult
    public static func setOpticalSize(automatic: Bool, in text: NSMutableAttributedString, range: NSRange, ofFontNamed baseName: String) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) where FontVariations.baseName(of: run.font) == baseName {
            let updated = FontVariations.font(run.font, automaticOpticalSize: automatic)
            guard !sameFont(updated, run.font) else { continue }
            TextStyling.writeFont(updated, in: text, range: run.range)
            changed += 1
        }
        return changed
    }

    /// Fissa un corpo ottico statico, oppure con `nil` lo collega al corpo del testo. Gli altri font restano intatti.
    @discardableResult
    public static func setStaticOpticalSize(_ size: StaticOpticalSize?, in text: NSMutableAttributedString,
                                            range: NSRange, family: String) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) where OpticalFonts.family(of: run.font) == family {
            let updated = OpticalFonts.font(run.font, opticalSize: size)
            if !sameFont(updated, run.font) { TextStyling.writeFont(updated, in: text, range: run.range) }
            if let size { text.addAttribute(.fontOpticalSize, value: size.rawValue, range: run.range) }
            else { text.removeAttribute(.fontOpticalSize, range: run.range) }
            changed += 1
        }
        return changed
    }

    /// Il font che realizza un ruolo, conservando corpo e funzioni compatibili; con `keepingWeight` anche il peso esatto.
    /// Restituisce anche il ruolo da registrare (`nil` se la faccia ottenuta non realizza esattamente un ruolo).
    public static func applying(role: FontRole, to font: CTFont, currentRole: FontRole? = nil, keepingWeight: Bool = false,
                                resolver: FontRoleResolver = FontRoleResolver()) -> (font: CTFont, role: FontRole?)? {
        var current = CharacterStyle(font)
        current.fontRole = currentRole
        guard let updated = resolver.applying(role: role, to: current, keepingWeight: keepingWeight),
              let result = characterAttributes(for: updated).attributes[.font] as? NSFont else { return nil }
        return (result as CTFont, updated.fontRole)
    }

    /// Applica un ruolo a ogni tratto e registra l'intenzione, così non dipende più dal nome della faccia ottenuta.
    /// Con `keepingWeight` (il corsivo) ogni tratto conserva il suo peso esatto; il ruolo si registra solo dove la faccia
    /// ottenuta lo realizza davvero.
    /// - Returns: il numero di tratti modificati.
    @discardableResult
    public static func apply(role: FontRole, in text: NSMutableAttributedString, range: NSRange, keepingWeight: Bool = false,
                             resolver: FontRoleResolver = FontRoleResolver(), styles: StyleSheet? = nil) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) {
            var current = CharacterStyle(run.font)
            current.fontRole = (text.attribute(.fontRole, at: run.range.location, effectiveRange: nil) as? String).flatMap(FontRole.init(rawValue:))
            if let styles, let face = styleFace(for: role, current: current, in: text, at: run.range.location, styles: styles, resolver: resolver) {
                if let font = characterAttributes(for: face).attributes[.font] as? NSFont, !sameFont(font as CTFont, run.font) {
                    TextStyling.writeFont(font, in: text, range: run.range)
                }
                text.removeAttribute(.fontRole, range: run.range)
                changed += 1
                continue
            }
            guard let updated = resolver.applying(role: role, to: current, keepingWeight: keepingWeight),
                  let font = characterAttributes(for: updated).attributes[.font] as? NSFont else { continue }
            if !sameFont(font as CTFont, run.font) { TextStyling.writeFont(font, in: text, range: run.range) }
            if let recorded = updated.fontRole { text.addAttribute(.fontRole, value: recorded.rawValue, range: run.range) }
            else { text.removeAttribute(.fontRole, range: run.range) }
            changed += 1
        }
        return changed
    }

    /// Togliendo il nero si torna alla faccia dello stile, se è della stessa famiglia, non nera e con lo stesso corsivo
    /// chiesto: un testo a 300 (Adobe Kis VF) torna a 300, non al Regular del font. `nil` se il ruolo è nero, o se lo
    /// stile non dà una faccia così (un titolo nero: allora vale il Regular delle equivalenze).
    public static func styleFace(for role: FontRole, current: CharacterStyle, in text: NSAttributedString, at index: Int,
                                 styles: StyleSheet, resolver: FontRoleResolver) -> CharacterStyle? {
        guard !role.isBold, index < text.length else { return nil }
        let paragraph = text.attribute(.paragraphStyleName, at: index, effectiveRange: nil) as? String
        let word = text.attribute(.wordStyleName, at: index, effectiveRange: nil) as? String
        let character = text.attribute(.characterStyleName, at: index, effectiveRange: nil) as? String
        guard paragraph != nil || word != nil || character != nil else { return nil }
        let resolved = styles.resolveCharacter(paragraphStyle: paragraph, wordStyle: word, characterStyle: character,
                                               base: styleBase, resolver: resolver)
        guard let styleFont = characterAttributes(for: resolved).attributes[.font] as? NSFont,
              resolver.family(of: resolved) == resolver.family(of: current) else { return nil }
        let font = styleFont as CTFont
        let italic = CTFontGetSymbolicTraits(font).contains(.traitItalic)
        let bold = FontVariations.coordinates(of: font)["wght"].map { $0 >= 600 } ?? CTFontGetSymbolicTraits(font).contains(.traitBold)
        guard !bold, italic == role.isItalic else { return nil }
        var face = current
        face.fontName = resolved.fontName
        face.variations = resolved.variations
        face.prefersVariableFont = resolved.prefersVariableFont
        face.fontRole = nil
        if face.fontName != current.fontName { face.features = [] }
        return face
    }

    /// Riapplica le equivalenze ai ruoli già presenti. Un ruolo ereditato da uno stile resta ereditato: non diventa
    /// un'eccezione diretta. Le facce libere, che non corrispondono a un ruolo, restano invariate.
    /// - Returns: il numero di tratti modificati.
    @discardableResult
    public static func reapplyFontRoles(in text: NSMutableAttributedString, range: NSRange, styles: StyleSheet = StyleSheet(),
                                        resolver: FontRoleResolver = FontRoleResolver()) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) {
            var current = CharacterStyle(run.font)
            current.fontRole = (text.attribute(.fontRole, at: run.range.location, effectiveRange: nil) as? String).flatMap(FontRole.init(rawValue:))
            var inheritedRole: FontRole?
            if current.fontRole == nil {
                let paragraph = text.attribute(.paragraphStyleName, at: run.range.location, effectiveRange: nil) as? String
                let word = text.attribute(.wordStyleName, at: run.range.location, effectiveRange: nil) as? String
                let character = text.attribute(.characterStyleName, at: run.range.location, effectiveRange: nil) as? String
                if paragraph != nil || word != nil || character != nil {
                    let resolved = styles.resolveCharacter(paragraphStyle: paragraph, wordStyle: word, characterStyle: character,
                                                           base: styleBase, resolver: resolver)
                    inheritedRole = resolver.role(of: resolved)
                }
            }
            let traits = FontFaces.description(of: current.fontName)
            guard let role = current.fontRole ?? inheritedRole ?? FontRoleResolver().role(of: current)
                    ?? (traits.map { FontRole(italic: $0.italic, bold: $0.bold) }),
                  var updated = resolver.applying(role: role, to: current) else { continue }
            let recordsRole = current.fontRole != nil
            if !recordsRole { updated.fontRole = nil }
            guard let rendered = characterAttributes(for: updated).attributes[.font] as? NSFont else { continue }
            if !sameFont(rendered as CTFont, run.font) {
                TextStyling.writeFont(rendered, in: text, range: run.range)
                changed += 1
            }
            if recordsRole { text.addAttribute(.fontRole, value: role.rawValue, range: run.range) }
        }
        return changed
    }

    /// Sostituisce il font nell'intervallo, conservando il corpo di ciascun tratto. Le funzioni attive si azzerano.
    /// Dove il testo era in un font a più assi, anche la nuova faccia si prende dal font a più assi, se c'è.
    /// La scelta esplicita di una faccia toglie il ruolo precedente, che non la descriverebbe più necessariamente.
    public static func setFont(postScriptName: String, in text: NSMutableAttributedString, range: NSRange) {
        for run in fontRuns(in: text, range: range) {
            guard let base = FontVariations.font(named: postScriptName, size: run.font.pointSize, preferringVariable: FontVariations.isVariable(run.font)) else { continue }
            // Il popup delle facce mostra la famiglia ottica di riferimento: la faccia scelta resta nel corpo ottico attuale.
            let fixed = (text.attribute(.fontOpticalSize, at: run.range.location, effectiveRange: nil) as? String).flatMap(StaticOpticalSize.init(rawValue:))
            let optical = fixed ?? OpticalFonts.opticalSize(of: run.font)
            let font = OpticalFonts.font(base, opticalSize: optical)
            TextStyling.writeFont(font, in: text, range: run.range)
            text.removeAttribute(.fontRole, range: run.range)
            text.removeAttribute(.missingFont, range: run.range)
            if OpticalFonts.opticalSize(of: font) == nil { text.removeAttribute(.fontOpticalSize, range: run.range) }
        }
    }

    /// Nei tratti della famiglia indicata, passa dall'installazione in file statici a quella a più assi
    /// (`variable`) o viceversa, conservando faccia, corpo, funzioni e ruolo.
    /// - Returns: il numero di tratti modificati.
    @discardableResult
    public static func switchFontFile(in text: NSMutableAttributedString, range: NSRange, family: String, variable: Bool) -> Int {
        var changed = 0
        for run in fontRuns(in: text, range: range) where CTFontCopyFamilyName(run.font) as String == family && FontVariations.isVariable(run.font) != variable {
            guard let other = FontVariations.counterpart(of: run.font, variable: variable) else { continue }
            TextStyling.writeFont(other, in: text, range: run.range)
            changed += 1
        }
        return changed
    }

    /// Cambia il corpo nell'intervallo, conservando font e funzioni attive di ciascun tratto.
    public static func setSize(_ size: CGFloat, in text: NSMutableAttributedString, range: NSRange) {
        for run in fontRuns(in: text, range: range) {
            let fixed = (text.attribute(.fontOpticalSize, at: run.range.location, effectiveRange: nil) as? String).flatMap(StaticOpticalSize.init(rawValue:))
            let updated = fixed == nil ? resized(run.font, to: size) : OpticalFonts.resized(run.font, to: size, opticalSize: fixed)
            TextStyling.writeFont(updated, in: text, range: run.range)
        }
    }

    /// Allinea nell'intervallo la spaziatura derivata dalla tabella `trak` al font e al corpo di ciascun tratto.
    ///
    /// Nel testo che si modifica la spaziatura entra come attributo di kerning,
    /// accompagnato da un contrassegno con la quantità aggiunta. Il contrassegno permette di toglierla o
    /// ricalcolarla (cambio di corpo, di font, interruttore spento) senza toccare un eventuale kerning dell'utente,
    /// e al layout di pagina di non contarla due volte.
    public static func syncFontTracking(in text: NSMutableAttributedString, range: NSRange, enabled: Bool) {
        for run in fontRuns(in: text, range: range) {
            let wanted = enabled ? Tracking.normalTracking(for: run.font).map(Double.init) : nil
            text.enumerateAttributes(in: run.range) { attributes, subrange, _ in
                let applied = (attributes[.fontTracking] as? NSNumber)?.doubleValue
                guard applied != wanted else { return }
                let kern = ((attributes[.kern] as? NSNumber)?.doubleValue ?? 0) - (applied ?? 0) + (wanted ?? 0)
                // Un kerning esplicito pari a zero spegnerebbe il kerning del font: in quel caso l'attributo si toglie.
                if abs(kern) < 1e-9 { text.removeAttribute(.kern, range: subrange) } else { text.addAttribute(.kern, value: kern, range: subrange) }
                if let wanted { text.addAttribute(.fontTracking, value: wanted, range: subrange) } else { text.removeAttribute(.fontTracking, range: subrange) }
            }
        }
    }

    public static func resized(_ font: CTFont, to size: CGFloat) -> CTFont {
        OpticalFonts.resized(font, to: size, opticalSize: nil)
    }

    /// Il solo cambio di corpo, senza spostare un eventuale corpo ottico statico.
    static func resizedWithoutOpticalSize(_ font: CTFont, to size: CGFloat) -> CTFont {
        CTFontCreateCopyWithAttributes(font, size, nil, nil)
    }
}

// MARK: - Font variabili nel testo con attributi

extension TextStyling {
    /// I valori espliciti degli assi del font, come li scrive il formato («wght=600 wdth=80»); `nil` senza assi fissati.
    public static func axesSignature(of font: CTFont) -> String? {
        let values = FontVariations.values(of: font)
        return values.isEmpty ? nil : values.map(\.description).joined(separator: " ")
    }

    /// Vero se i due font sono davvero lo stesso. macOS giudica uguali (anche `CFEqual`) due istanze di uno stesso
    /// font variabile che differiscono solo nei valori degli assi: qui si confrontano anche quelli.
    public static func sameFont(_ a: CTFont, _ b: CTFont) -> Bool {
        a == b && FontVariations.values(of: a) == FontVariations.values(of: b)
    }

    /// Scrive il font nell'intervallo insieme a `.fontAxes`, in un solo passo per ciascun tratto di attributi.
    ///
    /// Un testo con attributi non sostituisce un valore che giudica uguale, e la memoria condivisa degli attributi di
    /// Cocoa può restituire un insieme «uguale» già visto: con `addAttribute` un font a `wght=600` resterebbe a 400.
    /// L'attributo `.fontAxes` rende diversi i due insiemi, e il font scritto è proprio quello dato.
    public static func writeFont(_ font: Any, in text: NSMutableAttributedString, range: NSRange) {
        let axes = (font as? NSFont).flatMap { axesSignature(of: $0 as CTFont) }
        var pieces: [([NSAttributedString.Key: Any], NSRange)] = []
        text.enumerateAttributes(in: range) { attributes, run, _ in pieces.append((attributes, run)) }
        for (attributes, run) in pieces {
            var updated = attributes
            updated[.font] = font
            updated[.fontAxes] = axes
            text.setAttributes(updated, range: run)
        }
    }

    /// Gli attributi con `.fontAxes` coerente con il loro font: per gli attributi di battitura e per il testo nuovo.
    public static func withFontAxes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result[.fontAxes] = (attributes[.font] as? NSFont).flatMap { axesSignature(of: $0 as CTFont) }
        return result
    }
}

extension NSAttributedString.Key {
    /// I valori espliciti degli assi del font del tratto («wght=600»). Serve solo a far distinguere a Cocoa due istanze
    /// di uno stesso font variabile (vedi `TextStyling.writeFont`); il documento li legge dal font, non da qui.
    public static let fontAxes = NSAttributedString.Key("WordProcessorFontAxes")
    /// Quantità di spaziatura `trak`, in punti, già compresa nell'attributo di kerning di un tratto.
    public static let fontTracking = NSAttributedString.Key("WordProcessorFontTracking")
    /// Il ruolo tipografico richiesto (`FontRole.rawValue`), distinto dalla faccia che lo realizza.
    public static let fontRole = NSAttributedString.Key("WordProcessorFontRole")
    /// Corpo ottico statico fissato (`StaticOpticalSize.rawValue`); assente quando segue il corpo del testo.
    public static let fontOpticalSize = NSAttributedString.Key("WordProcessorFontOpticalSize")
}

// MARK: - Note a piè di pagina nel testo

extension TextStyling {
    /// Vero se nella posizione c'è il richiamo di una nota: il carattere U+FFFC marcato come nota, e non un'immagine
    /// (che usa lo stesso carattere).
    public static func isNoteAnchor(in text: NSAttributedString, at index: Int) -> Bool {
        let string = text.string as NSString
        return index >= 0 && index < string.length && string.character(at: index) == FloatingObject.anchorCharacter
            && text.attribute(.footnote, at: index, effectiveRange: nil) != nil && text.attribute(.inlineImage, at: index, effectiveRange: nil) == nil
            // Un campo nel testo di una nota usa lo stesso carattere, ma non apre una nota.
            && text.attribute(.field, at: index, effectiveRange: nil) == nil
    }

    /// La nota (richiamo e testo) che comincia con il richiamo alla posizione data.
    public static func footnoteSpan(in text: NSAttributedString, anchoredAt anchor: Int) -> NSRange? {
        let string = text.string as NSString
        guard isNoteAnchor(in: text, at: anchor) else { return nil }
        var end = anchor + 1
        // Il testo della nota dura finché è marcato come nota (a capo compresi: una nota può avere più paragrafi)
        // e si ferma al richiamo successivo.
        while end < string.length, text.attribute(.footnote, at: end, effectiveRange: nil) != nil, !isNoteAnchor(in: text, at: end) { end += 1 }
        return NSRange(location: anchor, length: end - anchor)
    }

    /// La nota (richiamo e testo) al cui testo appartiene una posizione. Alla fine della nota la posizione le
    /// appartiene solo con affinità `.upstream`: con `.downstream` è il punto del corpo dopo il richiamo.
    public static func footnoteSpan(in text: NSAttributedString, containing index: Int, affinity: NSSelectionAffinity) -> NSRange? {
        let string = text.string as NSString
        var probe = min(index, string.length) - 1
        while probe >= 0, text.attribute(.footnote, at: probe, effectiveRange: nil) != nil {
            if isNoteAnchor(in: text, at: probe) {
                guard let span = footnoteSpan(in: text, anchoredAt: probe) else { return nil }
                let end = NSMaxRange(span)
                return index < end || (index == end && affinity == .upstream) ? span : nil
            }
            probe -= 1
        }
        return nil
    }

    /// Toglie il contrassegno di nota al testo che non ha più un richiamo davanti, per esempio perché il richiamo
    /// è stato cancellato: torna testo del corpo.
    public static func repairFootnotes(in text: NSMutableAttributedString, range: NSRange) {
        let string = text.string as NSString
        guard string.length > 0 else { return }
        let all = NSRange(location: 0, length: string.length)
        var index = min(max(range.location, 0), string.length - 1)
        let limit = min(NSMaxRange(range), string.length)
        var orphans: [NSRange] = []
        repeat {
            // Il tratto marcato va guardato per intero, anche dove esce dall'intervallo modificato: il suo richiamo
            // può stare molto prima del punto toccato.
            var run = NSRange(location: 0, length: 0)
            if text.attribute(.footnote, at: index, longestEffectiveRange: &run, in: all) != nil {
                var first = run.location
                while first < NSMaxRange(run), !isNoteAnchor(in: text, at: first) { first += 1 }
                if first > run.location { orphans.append(NSRange(location: run.location, length: first - run.location)) }
            }
            index = max(NSMaxRange(run), index + 1)
        } while index < limit
        for orphan in orphans { text.removeAttribute(.footnote, range: orphan) }
    }

    /// Il paragrafo del corpo che contiene una posizione. I paragrafi del corpo finiscono agli a capo che non
    /// fanno parte di una nota: il testo di una nota, con i suoi a capo, sta dentro il paragrafo che la richiama.
    /// - Returns: l'intervallo del paragrafo con il suo a capo finale, e la posizione in cui finisce il contenuto.
    public static func bodyParagraph(in text: NSAttributedString, at index: Int) -> (range: NSRange, contentsEnd: Int) {
        let string = text.string as NSString
        let length = string.length
        func endsBodyParagraph(_ position: Int) -> Bool {
            isLineTerminator(string.character(at: position)) && text.attribute(.footnote, at: position, effectiveRange: nil) == nil
        }
        var start = min(max(index, 0), length)
        while start > 0, !endsBodyParagraph(start - 1) { start -= 1 }
        var contentsEnd = start
        while contentsEnd < length, !endsBodyParagraph(contentsEnd) { contentsEnd += 1 }
        var end = contentsEnd
        if end < length {
            // «\r\n» conta come un solo a capo.
            end += string.character(at: end) == 0x0D && end + 1 < length && string.character(at: end + 1) == 0x0A ? 2 : 1
        }
        return (NSRange(location: start, length: end - start), contentsEnd)
    }

    public static func isLineTerminator(_ character: unichar) -> Bool {
        // Senza un array: questa funzione gira su ogni carattere di lunghi tratti di testo.
        character == 0x0A || character == 0x0D || character == 0x85 || character == 0x2029
    }
}

// MARK: - Testo per le altre applicazioni

extension TextStyling {
    /// Il testo come lo riceve un'altra applicazione, che non conosce le nostre note: nel corpo ogni nota diventa
    /// un rimando «[n]», e i testi delle note seguono in coda, uno per riga, dopo una riga vuota.
    public static func flattenedForExport(_ text: NSAttributedString) -> NSAttributedString {
        let string = text.string as NSString
        let body = NSMutableAttributedString()
        let notes = NSMutableAttributedString()
        var number = 0
        var index = 0
        func clean(_ piece: NSAttributedString) -> NSAttributedString {
            let copy = NSMutableAttributedString(attributedString: piece)
            let all = NSRange(location: 0, length: copy.length)
            syncFontTracking(in: copy, range: all, enabled: false)
            for key in [NSAttributedString.Key.footnote, .fontTracking, .missingFont] { copy.removeAttribute(key, range: all) }
            return copy
        }
        while index < string.length {
            if let span = footnoteSpan(in: text, anchoredAt: index) {
                number += 1
                let anchorAttributes = text.attributes(at: index, effectiveRange: nil)
                // Il rimando prende l'aspetto del testo che lo precede, se c'è.
                let bodyAttributes = body.length > 0 ? body.attributes(at: body.length - 1, effectiveRange: nil) : anchorAttributes
                body.append(clean(NSAttributedString(string: "[\(number)]", attributes: bodyAttributes)))
                notes.append(clean(NSAttributedString(string: (notes.length == 0 ? "" : "\n") + "[\(number)] ", attributes: anchorAttributes)))
                notes.append(clean(text.attributedSubstring(from: NSRange(location: span.location + 1, length: span.length - 1))))
                index = NSMaxRange(span)
            } else {
                // Fino al prossimo richiamo, o alla fine.
                var end = index + 1
                while end < string.length, footnoteSpan(in: text, anchoredAt: end) == nil { end += 1 }
                body.append(clean(text.attributedSubstring(from: NSRange(location: index, length: end - index))))
                index = end
            }
        }
        guard notes.length > 0 else { return body }
        let separator = body.string.hasSuffix("\n") ? "\n" : "\n\n"
        body.append(NSAttributedString(string: separator, attributes: body.length > 0 ? body.attributes(at: body.length - 1, effectiveRange: nil) : [:]))
        body.append(notes)
        return body
    }
}
