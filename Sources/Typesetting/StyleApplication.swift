import AppKit

extension NSAttributedString.Key {
    /// Il nome dello stile di paragrafo, uguale su tutto il paragrafo, a capo finale compreso.
    public static let paragraphStyleName = NSAttributedString.Key("WordProcessorParagraphStyleName")
    /// Il livello di paragrafazione risolto (`NSNumber`): 0 dichiara esplicitamente che il paragrafo non è un titolo.
    public static let outlineLevel = NSAttributedString.Key("WordProcessorOutlineLevel")
    /// Sull'ultimo a capo: il livello del paragrafo finale vuoto, quando serve distinguerlo dal precedente.
    public static let finalParagraphOutlineLevel = NSAttributedString.Key("WordProcessorFinalParagraphOutlineLevel")
    /// I nomi degli stili di parola e di carattere di un tratto.
    public static let wordStyleName = NSAttributedString.Key("WordProcessorWordStyleName")
    public static let characterStyleName = NSAttributedString.Key("WordProcessorCharacterStyleName")
    /// Presente, con valore falso, sul testo le cui parole non si devono dividere a fine riga.
    public static let hyphenates = NSAttributedString.Key("WordProcessorHyphenates")
    /// La posizione verticale del testo (`VerticalPosition.encoded`): la applica la composizione.
    public static let verticalPosition = NSAttributedString.Key("WordProcessorVerticalPosition")
    /// I filetti del testo (`LineDecoration.encode`): li disegna il disegno delle pagine.
    public static let lineDecorations = NSAttributedString.Key("WordProcessorLineDecorations")
    /// Le proprietà che le regole non toccano in questo testo (nomi di `InspectorProperty`, separati da spazi):
    /// date qui a mano, valgono anche quando coincidono con il valore dello stile.
    public static let ruleExceptions = NSAttributedString.Key("WordProcessorRuleExceptions")
}

// MARK: - Stili nel testo dell'editor

extension TextStyling {
    /// Da dove partono i tratti per le proprietà che nessuno stile fissa.
    public static let styleBase = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    /// Gli attributi di testo che rendono uno stile di carattere già risolto. `isMissing` è vero se il font non è
    /// installato: il testo è mostrato con un font di ripiego e lo stile originale resta in `.missingFont`.
    public static func characterAttributes(for style: CharacterStyle) -> (attributes: [NSAttributedString.Key: Any], isMissing: Bool) {
        var result: [NSAttributedString.Key: Any] = [:]
        var isMissing = false
        let wantsVariable = style.prefersVariableFont || !style.variations.isEmpty
        // Un corpo ottico non installato, ma con la faccia di base installata: si usa quella (il corpo lo sceglie poi
        // l'automatico), senza dichiarare il font mancante.
        let found = FontVariations.font(named: style.fontName, size: style.size, preferringVariable: wantsVariable)
            ?? baseFaceCandidates(forMissing: style.fontName).lazy.compactMap { FontVariations.font(named: $0, size: style.size, preferringVariable: wantsVariable) }.first
        if let base = found {
            // Nei gruppi ottici statici la stessa faccia cambia file secondo il corpo o la scelta fissa.
            let optical = OpticalFonts.font(base, opticalSize: style.opticalSize)
            // Prima gli assi, poi le funzioni: ciascun passaggio conserva l'altro.
            let varied = style.variations.isEmpty ? optical : FontVariations.font(optical, with: style.variations)
            // Il maiuscoletto si chiede in tutte le forme: il font tiene quelle che conosce.
            let font = FontFeatures.font(varied, with: style.features + style.smallCaps.forms)
            result[.font] = font as NSFont
            result[.fontAxes] = axesSignature(of: font)
        } else {
            isMissing = true
            let fallback = NSFont.userFont(ofSize: style.size) ?? NSFont.systemFont(ofSize: style.size)
            result[.font] = fallback
            result[.missingFont] = MissingFont(fontName: style.fontName, features: style.features, variations: style.variations, fallbackName: fallback.fontName).encoded
        }
        if let language = style.language { result[.language] = language }
        if !style.hyphenates { result[.hyphenates] = false }
        if let hex = style.color, let color = color(hex: hex) { result[.foregroundColor] = color }
        if let position = style.verticalPosition { result[.verticalPosition] = position.encoded }
        if !style.decorations.isEmpty { result[.lineDecorations] = LineDecoration.encode(style.decorations) }
        if let graphite = style.graphite { result[.graphite] = graphite }
        if let role = style.fontRole { result[.fontRole] = role.rawValue }
        if let opticalSize = style.opticalSize { result[.fontOpticalSize] = opticalSize.rawValue }
        if style.smallCaps != .off { result[.smallCaps] = style.smallCaps.rawValue }
        return (result, isMissing)
    }

    /// Scrive nel testo gli attributi che derivano dallo stile di carattere oltre al font (lingua, sillabazione, colore,
    /// font mancante): li mette o li toglie, secondo `rendered`.
    static func writeDerivedAttributes(_ rendered: [NSAttributedString.Key: Any], in text: NSMutableAttributedString, range: NSRange) {
        if let language = rendered[.language] { text.addAttribute(.language, value: language, range: range) } else { text.removeAttribute(.language, range: range) }
        if rendered[.hyphenates] != nil { text.addAttribute(.hyphenates, value: false, range: range) } else { text.removeAttribute(.hyphenates, range: range) }
        if let color = rendered[.foregroundColor] { text.addAttribute(.foregroundColor, value: color, range: range) } else { text.removeAttribute(.foregroundColor, range: range) }
        if let position = rendered[.verticalPosition] { text.addAttribute(.verticalPosition, value: position, range: range) } else { text.removeAttribute(.verticalPosition, range: range) }
        if let lines = rendered[.lineDecorations] { text.addAttribute(.lineDecorations, value: lines, range: range) } else { text.removeAttribute(.lineDecorations, range: range) }
        if let graphite = rendered[.graphite] { text.addAttribute(.graphite, value: graphite, range: range) } else { text.removeAttribute(.graphite, range: range) }
        if let role = rendered[.fontRole] { text.addAttribute(.fontRole, value: role, range: range) } else { text.removeAttribute(.fontRole, range: range) }
        if let optical = rendered[.fontOpticalSize] { text.addAttribute(.fontOpticalSize, value: optical, range: range) } else { text.removeAttribute(.fontOpticalSize, range: range) }
        if let smallCaps = rendered[.smallCaps] { text.addAttribute(.smallCaps, value: smallCaps, range: range) } else { text.removeAttribute(.smallCaps, range: range) }
        // Un testo che riceve un font installato non è più «in un font mancante».
        if let missing = rendered[.missingFont] { text.addAttribute(.missingFont, value: missing, range: range) } else { text.removeAttribute(.missingFont, range: range) }
    }

    /// Un colore da `#rrggbb`.
    public static func color(hex: String) -> NSColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    /// `#rrggbb` di un colore; `nil` per il nero e per i colori di sistema che cambiano con l'aspetto (sono «automatici»).
    public static func hex(of color: NSColor) -> String? {
        guard color.type != .catalog, let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        if components == [0, 0, 0] { return nil }
        return String(format: "#%02x%02x%02x", components[0], components[1], components[2])
    }

    /// Il colore del testo in un punto, come lo vede il modello.
    public static func textColor(in text: NSAttributedString, at index: Int) -> String? {
        guard index < text.length, let color = text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor else { return nil }
        return hex(of: color)
    }

    /// Lo stile di carattere di un punto del testo, come lo vede il modello.
    static func characterStyle(in text: NSAttributedString, at index: Int) -> CharacterStyle? {
        guard index < text.length, let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont else { return nil }
        var style = CharacterStyle(font as CTFont)
        style.fontName = chosenFaceName(of: font as CTFont, fallback: style.fontName)
        style.language = text.attribute(.language, at: index, effectiveRange: nil) as? String
        style.hyphenates = text.attribute(.hyphenates, at: index, effectiveRange: nil) as? Bool ?? true
        style.color = textColor(in: text, at: index)
        style.verticalPosition = (text.attribute(.verticalPosition, at: index, effectiveRange: nil) as? String).flatMap(VerticalPosition.init(encoded:))
        style.decorations = (text.attribute(.lineDecorations, at: index, effectiveRange: nil) as? String).flatMap(LineDecoration.decode) ?? []
        style.graphite = text.attribute(.graphite, at: index, effectiveRange: nil) as? String
        style.fontRole = (text.attribute(.fontRole, at: index, effectiveRange: nil) as? String).flatMap(FontRole.init(rawValue:))
        style.opticalSize = (text.attribute(.fontOpticalSize, at: index, effectiveRange: nil) as? String).flatMap(StaticOpticalSize.init(rawValue:))
        style.smallCaps = smallCaps(in: text, at: index, font: style.smallCaps)
        return style
    }

    /// Il maiuscoletto voluto in un punto: quello registrato nel testo, che vale anche dove il font non ha la forma.
    /// Senza registrazione, quello che il font mostra (`fromFont`): per esempio chiesto come funzione grezza.
    static func smallCaps(in text: NSAttributedString, at index: Int, font fromFont: SmallCaps) -> SmallCaps {
        guard let raw = text.attribute(.smallCaps, at: index, effectiveRange: nil) as? String, let recorded = SmallCaps(rawValue: raw) else { return fromFont }
        return recorded
    }

    /// Il nome della faccia scelta per un font disegnato. In un gruppo di corpi ottici il file usato dipende dal corpo
    /// (Minion 3 Subhead a 18 pt): nel documento va la faccia di base, perché il corpo ottico automatico è solo disegno e
    /// quel file può non essere installato altrove.
    static func chosenFaceName(of font: CTFont, fallback: String) -> String {
        OpticalFonts.opticalSize(of: font) == nil ? fallback : OpticalFonts.baseFaceName(of: font)
    }

    /// Il nome di un corpo ottico non installato ridotto alla sua faccia di base: «Minion3Subhead-Bold» → «Minion3-Bold»,
    /// «WarnockPro-LightCapt» → «WarnockPro-Light»; `nil` se il nome non nomina un corpo ottico.
    static func baseFaceCandidates(forMissing name: String) -> [String] {
        let words = "(Caption|Capt|Subhead|Subh|Display|Disp)"
        var result: [String] = []
        for pattern in ["\(words)(?=-)", "\(words)$"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let stripped = regex.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: (name as NSString).length), withTemplate: "")
            guard stripped != name else { continue }
            result.append(stripped.hasSuffix("-") ? stripped + "Regular" : stripped)
            if stripped.hasSuffix("-") { result.append(String(stripped.dropLast())) }
        }
        return result
    }

    /// Ogni proprietà che valeva quanto davano gli stili di prima prende il valore degli stili nuovi; le altre
    /// erano state date a mano e restano.
    static func restyled(_ current: CharacterStyle, from old: CharacterStyle, to new: CharacterStyle) -> CharacterStyle {
        var result = current
        if current.fontName == old.fontName { result.fontName = new.fontName }
        if current.size == old.size { result.size = new.size }
        // Funzioni e assi uno per uno: una funzione data a mano non impedisce alle altre di seguire lo stile.
        result.features = TextStyling.restyledFeatures(current, from: old, to: new)
        result.variations = TextStyling.restyledVariations(current, from: old, to: new)
        if current.prefersVariableFont == old.prefersVariableFont { result.prefersVariableFont = new.prefersVariableFont }
        if current.fontRole == old.fontRole { result.fontRole = new.fontRole }
        if current.opticalSize == old.opticalSize { result.opticalSize = new.opticalSize }
        if current.language == old.language { result.language = new.language }
        if current.hyphenates == old.hyphenates { result.hyphenates = new.hyphenates }
        if current.color == old.color { result.color = new.color }
        if current.verticalPosition == old.verticalPosition { result.verticalPosition = new.verticalPosition }
        if current.decorations == old.decorations { result.decorations = new.decorations }
        if current.graphite == old.graphite { result.graphite = new.graphite }
        if current.smallCaps == old.smallCaps { result.smallCaps = new.smallCaps }
        return result
    }

    static func restyled(_ current: ParagraphStyle, from old: ParagraphStyle, to new: ParagraphStyle) -> ParagraphStyle {
        var result = current
        func carry<T: Equatable>(_ path: WritableKeyPath<ParagraphStyle, T>) { if current[keyPath: path] == old[keyPath: path] { result[keyPath: path] = new[keyPath: path] } }
        carry(\.alignment); carry(\.firstLineIndent); carry(\.leftIndent); carry(\.rightIndent)
        carry(\.spaceBefore); carry(\.spaceAfter); carry(\.lineSpacing); carry(\.lineHeightMultiple); carry(\.outlineLevel)
        return result
    }

    /// I nomi degli stili di un tratto.
    public struct StyleNames: Equatable {
        public var paragraph: String?
        public var word: String?
        public var character: String?
    }

    /// Cambia i nomi degli stili (con `rename`) e, se serve, le loro definizioni (da `oldSheet` a `newSheet`)
    /// nell'intervallo. I valori ereditati seguono gli stili nuovi; quelli dati a mano restano.
    ///
    /// Per gli stili di paragrafo l'intervallo va dato già esteso ai paragrafi interi.
    public static func restyle(_ text: NSMutableAttributedString, range: NSRange, from oldSheet: StyleSheet, to newSheet: StyleSheet,
                               resolver: FontRoleResolver = FontRoleResolver(), base: CharacterStyle = TextStyling.styleBase,
                               assigning target: StyleTarget? = nil,
                               rename: (inout StyleNames) -> Void = { _ in }) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard range.length > 0 else { return }
        // Prima si raccoglie tutto, poi si modifica: i nomi vecchi vanno letti prima di cambiarli.
        struct Piece { var range: NSRange; var old: StyleNames; var new: StyleNames; var style: CharacterStyle?; var missing: Bool }
        var pieces: [Piece] = []
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            let old = StyleNames(paragraph: attributes[.paragraphStyleName] as? String, word: attributes[.wordStyleName] as? String,
                                 character: attributes[.characterStyleName] as? String)
            var new = old
            rename(&new)
            pieces.append(Piece(range: subrange, old: old, new: new, style: characterStyle(in: text, at: subrange.location),
                                missing: attributes[.missingFont] != nil))
        }
        var paragraphs: [(range: NSRange, old: String?, new: String?)] = []
        var location = range.location
        while location < NSMaxRange(range) {
            let paragraph = bodyParagraph(in: text, at: location).range
            let old = text.attribute(.paragraphStyleName, at: paragraph.location, effectiveRange: nil) as? String
            var names = StyleNames(paragraph: old)
            rename(&names)
            paragraphs.append((paragraph, old, names.paragraph))
            location = max(NSMaxRange(paragraph), location + 1)
        }

        for piece in pieces {
            func setName(_ key: NSAttributedString.Key, _ value: String?) {
                if let value { text.addAttribute(key, value: value, range: piece.range) } else { text.removeAttribute(key, range: piece.range) }
            }
            if piece.new.word != piece.old.word { setName(.wordStyleName, piece.new.word) }
            if piece.new.character != piece.old.character { setName(.characterStyleName, piece.new.character) }
            // Il testo in un font non installato conserva il suo stile originale: non lo si tocca.
            guard let current = piece.style, !piece.missing else { continue }
            let before = oldSheet.resolveCharacter(paragraphStyle: piece.old.paragraph, wordStyle: piece.old.word, characterStyle: piece.old.character, base: base, resolver: resolver)
            let after = newSheet.resolveCharacter(paragraphStyle: piece.new.paragraph, wordStyle: piece.new.word, characterStyle: piece.new.character, base: base, resolver: resolver)
            var result = restyled(current, from: before, to: after)
            let assignedName: String? = switch target {
            case .paragraph: piece.new.paragraph
            case .word: piece.new.word
            case .character: piece.new.character
            case .none: nil
            }
            if let assignedName,
               let font = try? newSheet.values(of: assignedName).fontFormulaResult(from: current, resolver: resolver) {
                result.fontName = font.fontName
                result.features = font.features
                result.variations = font.variations
                result.prefersVariableFont = font.prefersVariableFont
                result.fontRole = font.fontRole
                result.opticalSize = font.opticalSize
            }
            guard result != current else { continue }
            let rendered = characterAttributes(for: result).attributes
            TextStyling.writeFont(rendered[.font]!, in: text, range: piece.range)
            writeDerivedAttributes(rendered, in: text, range: piece.range)
        }
        for paragraph in paragraphs {
            if paragraph.new != paragraph.old {
                if let name = paragraph.new { text.addAttribute(.paragraphStyleName, value: name, range: paragraph.range) } else { text.removeAttribute(.paragraphStyleName, range: paragraph.range) }
            }
            let oldParagraph = oldSheet.resolveParagraph(styleName: paragraph.old)
            let newParagraph = newSheet.resolveParagraph(styleName: paragraph.new)
            var current = (text.attribute(.paragraphStyle, at: paragraph.range.location, effectiveRange: nil) as? NSParagraphStyle).map(ParagraphStyle.init) ?? ParagraphStyle()
            if let level = (text.attribute(.outlineLevel, at: paragraph.range.location, effectiveRange: nil) as? NSNumber)?.intValue {
                current.outlineLevel = level > 0 ? level : nil
            } else {
                current.outlineLevel = oldParagraph.outlineLevel ?? DocumentOutline.headingLevel(of: paragraph.old)
            }
            let result = restyled(current, from: oldParagraph, to: newParagraph)
            if result != current { text.addAttribute(.paragraphStyle, value: result.nsParagraphStyle, range: paragraph.range) }
            if result != current || paragraph.new != paragraph.old {
                text.addAttribute(.outlineLevel, value: NSNumber(value: result.outlineLevel ?? 0), range: paragraph.range)
            }
            // La Lista segue la stessa regola: se è quella che dava lo stile vecchio, diventa quella del nuovo.
            let currentList = (text.attribute(.listItem, at: paragraph.range.location, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
            let oldList = oldSheet.values(of: paragraph.old).list
            let newList = newSheet.values(of: paragraph.new).list
            if currentList == oldList, newList != oldList {
                if let newList { text.addAttribute(.listItem, value: newList.encoded, range: paragraph.range) } else { text.removeAttribute(.listItem, range: paragraph.range) }
            }
        }
    }

    /// L'intervallo esteso ai paragrafi interi che tocca.
    public static func paragraphRange(in text: NSAttributedString, for range: NSRange) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let first = bodyParagraph(in: text, at: min(range.location, text.length - 1)).range
        let lastIndex = range.length > 0 ? NSMaxRange(range) - 1 : range.location
        let last = bodyParagraph(in: text, at: min(lastIndex, text.length - 1)).range
        return NSUnionRange(first, last)
    }

    /// I valori per uno stile nuovo (o ridefinito) di quella specie, presi dal testo in `index`: ciò che lì
    /// differisce da quanto darebbe lo stile `basedOn` (o, per parola e carattere, gli stili sopra il tratto).
    /// Il font si registra come famiglia, corsivo e nero.
    public static func styleValues(from text: NSAttributedString, at index: Int, target: StyleTarget, sheet: StyleSheet, basedOn: String?) -> StyleValues {
        var values = StyleValues()
        guard let current = characterStyle(in: text, at: index) else { return values }
        let paragraphName = text.attribute(.paragraphStyleName, at: index, effectiveRange: nil) as? String
        let wordName = text.attribute(.wordStyleName, at: index, effectiveRange: nil) as? String
        // Il riferimento: ciò che il testo avrebbe senza lo stile che si sta definendo.
        let reference: CharacterStyle = switch target {
        case .paragraph: sheet.resolveCharacter(paragraphStyle: basedOn, wordStyle: nil, characterStyle: nil, base: styleBase)
        case .word: sheet.resolveCharacter(paragraphStyle: paragraphName, wordStyle: basedOn, characterStyle: nil, base: styleBase)
        case .character: sheet.resolveCharacter(paragraphStyle: paragraphName, wordStyle: wordName, characterStyle: basedOn, base: styleBase)
        }
        if target != .character {
            if current.language != reference.language { values.language = current.language ?? "" }
            if current.hyphenates != reference.hyphenates { values.hyphenates = current.hyphenates }
        }
        let face = FontFaces.description(of: current.fontName), referenceFace = FontFaces.description(of: reference.fontName)
        if let face, current.fontName != reference.fontName {
            let family = OpticalFonts.canonicalFamily(face.family) ?? face.family
            let referenceFamily = referenceFace.flatMap { OpticalFonts.canonicalFamily($0.family) ?? $0.family }
            if family != referenceFamily { values.family = family }
            if face.italic != referenceFace?.italic { values.italic = face.italic }
            if face.bold != referenceFace?.bold { values.bold = face.bold }
            // Una faccia che famiglia, corsivo e nero non bastano a ritrovare (un peso particolare) si fissa per nome.
            var check = CharacterFields(reference)
            values.apply(to: &check)
            if check.fontName != current.fontName, OpticalFonts.canonicalFamily(face.family) == nil {
                values = StyleValues(copyingWordFrom: values); values.fontName = current.fontName
            }
        } else if face == nil, current.fontName != reference.fontName {
            values.fontName = current.fontName
        }
        if current.size != reference.size { values.size = current.size }
        if current.opticalSize != reference.opticalSize { values.opticalSize = current.opticalSize?.rawValue ?? "" }
        if current.color != reference.color { values.color = current.color ?? "" }
        if current.verticalPosition != reference.verticalPosition { values.verticalPosition = current.verticalPosition?.encoded ?? "" }
        if current.decorations != reference.decorations { values.decorations = LineDecoration.encode(current.decorations) }
        if current.graphite != reference.graphite { values.graphite = Graphite.encodedChoice(current.graphite) }
        if current.smallCaps != reference.smallCaps { values.smallCaps = current.smallCaps }
        if current.features != reference.features && !current.features.isEmpty { values.features = current.features }
        if current.variations != reference.variations && !current.variations.isEmpty { values.variations = current.variations }
        if target == .paragraph, let style = (text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle).map(ParagraphStyle.init) {
            let base = sheet.resolveParagraph(styleName: basedOn)
            if style.alignment != base.alignment { values.alignment = style.alignment }
            if style.firstLineIndent != base.firstLineIndent { values.firstLineIndent = style.firstLineIndent }
            if style.leftIndent != base.leftIndent { values.leftIndent = style.leftIndent }
            if style.rightIndent != base.rightIndent { values.rightIndent = style.rightIndent }
            if style.spaceBefore != base.spaceBefore { values.spaceBefore = style.spaceBefore }
            if style.spaceAfter != base.spaceAfter { values.spaceAfter = style.spaceAfter }
            if style.lineSpacing != base.lineSpacing { values.lineSpacing = style.lineSpacing }
            if style.lineHeightMultiple != base.lineHeightMultiple { values.lineHeightMultiple = style.lineHeightMultiple }
        }
        // Anche la Lista del paragrafo fa parte dello stile: senza, ridefinire «Esempio» toglierebbe la numerazione.
        if target == .paragraph {
            let list = listItem(in: text, at: index)?.listName ?? ""
            if list != (sheet.values(of: basedOn).listName ?? "") { values.listName = list }
            // Il livello registrato vince sul nome dello stile; solo il testo vecchio senza attributo usa il ripiego.
            let level = (text.attribute(.outlineLevel, at: index, effectiveRange: nil) as? NSNumber)?.intValue
                ?? sheet.resolveParagraph(styleName: paragraphName).outlineLevel ?? DocumentOutline.headingLevel(of: paragraphName) ?? 0
            let inheritedLevel = sheet.resolveParagraph(styleName: basedOn).outlineLevel ?? 0
            if level != inheritedLevel { values.outlineLevel = level }
            // E la distanza d'apertura data a mano.
            if let own = openingDistance(in: text, at: index), own != (sheet.values(of: basedOn).openingDistance ?? 0) { values.openingDistance = own }
            // E la tenuta: quella effettiva del paragrafo, dove differisce da quella che darebbe lo stile di base.
            let here = sheet.lineKeeping(styleName: paragraphName, own: lineKeeping(in: text, at: index))
            let parent = sheet.lineKeeping(styleName: basedOn)
            if here.withNext != parent.withNext { values.keeping.withNext = here.withNext }
            if here.together != parent.together { values.keeping.together = here.together }
            if here.linesAtEnd != parent.linesAtEnd { values.keeping.linesAtEnd = here.linesAtEnd }
            if here.linesAtStart != parent.linesAtStart { values.keeping.linesAtStart = here.linesAtStart }
        }
        return values
    }
}

extension StyleValues {
    /// Solo lingua e sillabazione di un altro insieme di valori.
    init(copyingWordFrom other: StyleValues) {
        self.init()
        language = other.language
        hyphenates = other.hyphenates
    }
}
