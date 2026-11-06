import AppKit

// MARK: - Ispettore: proprietà, valori e provenienza

/// Una proprietà che l'ispettore mostra per un oggetto del testo. Ognuna appartiene all'oggetto più basso a cui
/// ha senso darla: il carattere (font, corpo), la parola (lingua, sillabazione), il paragrafo (il resto).
public enum InspectorProperty: String, CaseIterable, Sendable, Identifiable {
    case family, face, size, smallCaps, color, verticalPosition, decorations, shaping
    case language, hyphenates
    case alignment, leftIndent, rightIndent, firstLineIndent, spaceBefore, spaceAfter, lineHeightMultiple, lineSpacing, list, openingDistance
    case keepWithNext, keepTogether, orphanLines, widowLines

    public var id: String { rawValue }

    /// L'oggetto a cui appartiene.
    public var level: StyleTarget {
        switch self {
        case .family, .face, .size, .smallCaps, .color, .verticalPosition, .decorations, .shaping: .character
        case .language, .hyphenates: .word
        default: .paragraph
        }
    }

    public var title: String {
        switch self {
        case .family: "Family"
        case .face: "Face"
        case .size: "Size"
        case .color: "Color"
        case .smallCaps: "Small caps"
        case .verticalPosition: "Vertical position"
        case .decorations: "Lines"
        case .shaping: "Shaping"
        case .language: "Language"
        case .hyphenates: "Hyphenation"
        case .alignment: "Alignment"
        case .leftIndent: "Left indent"
        case .rightIndent: "Right indent"
        case .firstLineIndent: "First-line indent"
        case .spaceBefore: "Space before"
        case .spaceAfter: "Space after"
        case .lineHeightMultiple: "Line height"
        case .lineSpacing: "Line spacing"
        case .list: "List"
        case .openingDistance: "Opening distance"
        case .keepWithNext: "Keep with next"
        case .keepTogether: "Keep lines together"
        case .orphanLines: "Lines at the bottom"
        case .widowLines: "Lines at the top"
        }
    }

    public static func properties(of level: StyleTarget) -> [InspectorProperty] { allCases.filter { $0.level == level } }

    /// Solo i campi di `values` che esprimono questa proprietà.
    public func only(_ values: StyleValues) -> StyleValues {
        var result = StyleValues()
        switch self {
        case .family: result.family = values.family
        case .face: result.fontName = values.fontName
        case .size: result.size = values.size
        case .color: result.color = values.color
        case .smallCaps: result.smallCaps = values.smallCaps
        case .verticalPosition: result.verticalPosition = values.verticalPosition
        case .decorations: result.decorations = values.decorations
        case .shaping: result.graphite = values.graphite
        case .language: result.language = values.language
        case .hyphenates: result.hyphenates = values.hyphenates
        case .alignment: result.alignment = values.alignment
        case .leftIndent: result.leftIndent = values.leftIndent
        case .rightIndent: result.rightIndent = values.rightIndent
        case .firstLineIndent: result.firstLineIndent = values.firstLineIndent
        case .spaceBefore: result.spaceBefore = values.spaceBefore
        case .spaceAfter: result.spaceAfter = values.spaceAfter
        case .lineHeightMultiple: result.lineHeightMultiple = values.lineHeightMultiple
        case .lineSpacing: result.lineSpacing = values.lineSpacing
        case .list: result.listName = values.listName
        case .openingDistance: result.openingDistance = values.openingDistance
        case .keepWithNext: result.keeping.withNext = values.keeping.withNext
        case .keepTogether: result.keeping.together = values.keeping.together
        case .orphanLines: result.keeping.linesAtEnd = values.keeping.linesAtEnd
        case .widowLines: result.keeping.linesAtStart = values.keeping.linesAtStart
        }
        return result
    }

    /// Vero se i valori propri di uno stile (non quelli ereditati) fissano questa proprietà.
    public func isFixed(in values: StyleValues) -> Bool {
        switch self {
        case .family: values.family != nil || values.fontName != nil
        case .face: values.fontName != nil || values.italic != nil || values.bold != nil || values.family != nil
        default: only(values) != StyleValues()
        }
    }
}

extension StyleValues {
    /// Toglie i campi che esprimono la proprietà: chi li usa la eredita.
    public mutating func clear(_ property: InspectorProperty) {
        resolutionSteps = resolutionSteps.compactMap { step in
            switch step {
            case .formula(let formula):
                return formula.operation.property.inspectorProperty == property ? nil : step
            case .values(var values):
                values.clear(property)
                return .values(values)
            }
        }
        switch property {
        case .family, .face:
            family = nil
            fontName = nil
            italic = nil
            bold = nil
        case .size: size = nil
        case .color: color = nil
        case .smallCaps: smallCaps = nil
        case .verticalPosition: verticalPosition = nil
        case .decorations: decorations = nil
        case .shaping: graphite = nil
        case .language: language = nil
        case .hyphenates: hyphenates = nil
        case .alignment: alignment = nil
        case .leftIndent: leftIndent = nil
        case .rightIndent: rightIndent = nil
        case .firstLineIndent: firstLineIndent = nil
        case .spaceBefore: spaceBefore = nil
        case .spaceAfter: spaceAfter = nil
        case .lineHeightMultiple: lineHeightMultiple = nil
        case .lineSpacing: lineSpacing = nil
        case .list: listName = nil
        case .openingDistance: openingDistance = nil
        case .keepWithNext: keeping.withNext = nil
        case .keepTogether: keeping.together = nil
        case .orphanLines: keeping.linesAtEnd = nil
        case .widowLines: keeping.linesAtStart = nil
        }
    }

    /// I valori senza i campi delle proprietà date.
    func clearing(_ properties: Set<InspectorProperty>) -> StyleValues {
        var result = self
        for property in properties { result.clear(property) }
        return result
    }
}

/// Da dove viene il valore di una proprietà.
public enum ValueSource: Equatable, Sendable {
    /// Dato a mano a questo oggetto.
    case own
    /// Da uno stile: quello, nella catena degli stili, che lo fissa.
    case style(String)
    /// Da nessuno stile: è il valore di partenza del documento.
    case document
    /// Da una regola (la sua descrizione): la regola vale sopra gli stili, e questo valore lo dà lei.
    case rule(String)
}

/// Una proprietà come la vede l'ispettore in un punto del testo.
public struct InspectedValue: Equatable, Sendable {
    public var property: InspectorProperty
    /// Il valore, nei soli campi della proprietà. Per la lingua, la stringa vuota è la lingua del documento; per la
    /// Lista, la stringa vuota è «nessuna».
    public var value: StyleValues
    /// Il valore che ci sarebbe senza nulla di dato a mano: quello degli stili o del documento.
    public var inherited: StyleValues
    public var source: ValueSource
    /// Vero se nella selezione la proprietà non ha un valore solo.
    public var isMixed: Bool
    /// Che cosa fanno le regole a questa proprietà nel punto, se la toccano: per spiegarlo nell'ispettore.
    public var rules: RuleInfluence? = nil

    public init(property: InspectorProperty, value: StyleValues, inherited: StyleValues, source: ValueSource, isMixed: Bool,
                rules: RuleInfluence? = nil) {
        self.property = property
        self.value = value
        self.inherited = inherited
        self.source = source
        self.isMixed = isMixed
        self.rules = rules
    }
}

/// Le regole che toccano una proprietà in un punto, nell'ordine in cui si applicano: l'ultima è quella che conta.
public struct RuleInfluence: Equatable, Sendable {
    /// Le descrizioni delle regole che danno un valore alla proprietà: prima quelle scavalcate, ultima quella che
    /// conta (la prima, nell'ordine delle regole, che la cambia). Più di una è un conflitto.
    public var rules: [String]
    /// Lo stile di cui l'ultima regola è una formula contestuale, se lo è.
    public var owner: String?
    /// Il valore dato a mano che una regola attiva scavalca: resta nel testo, ma non si applica.
    public var suspended: StyleValues?
    /// Il valore che l'ultima regola darebbe, quando a vincere è il valore dato qui (un'eccezione o una regola storica).
    public var yielded: StyleValues?

    public init(rules: [String], owner: String? = nil, suspended: StyleValues? = nil, yielded: StyleValues? = nil) {
        self.rules = rules
        self.owner = owner
        self.suspended = suspended
        self.yielded = yielded
    }

    /// La regola che conta.
    public var winner: String? { rules.last }
    /// Le regole scavalcate dall'ultima.
    public var outranked: [String] { Array(rules.dropLast()) }
}

extension TextStyling {
    /// Tutti i valori di un punto del testo, espressi come valori di uno stile.
    static func fullValues(character: CharacterStyle, paragraph: ParagraphStyle, list: ListItem?, openingDistance: Double = 0,
                           keeping: LineKeeping.Resolved = LineKeeping().resolved, resolver: FontRoleResolver = FontRoleResolver()) -> StyleValues {
        var values = StyleValues()
        values.fontName = character.fontName
        values.family = FontFaces.description(of: character.fontName)?.family ?? character.fontName
        let traits = FontFaces.description(of: character.fontName)
        let role = character.fontRole ?? resolver.role(of: character)
        values.bold = role?.isBold ?? traits?.bold ?? false
        values.italic = role?.isItalic ?? traits?.italic ?? false
        values.size = character.size
        values.color = character.color ?? ""
        values.smallCaps = character.smallCaps
        values.verticalPosition = character.verticalPosition?.encoded ?? ""
        values.decorations = LineDecoration.encode(character.decorations)
        values.graphite = Graphite.encodedChoice(character.graphite)
        values.language = character.language ?? ""
        values.hyphenates = character.hyphenates
        values.alignment = paragraph.alignment
        values.leftIndent = paragraph.leftIndent
        values.rightIndent = paragraph.rightIndent
        values.firstLineIndent = paragraph.firstLineIndent
        values.spaceBefore = paragraph.spaceBefore
        values.spaceAfter = paragraph.spaceAfter
        values.lineHeightMultiple = paragraph.lineHeightMultiple
        values.lineSpacing = paragraph.lineSpacing
        values.outlineLevel = paragraph.outlineLevel ?? 0
        // Un elenco senza nome non è una Lista: per l'ispettore il paragrafo non ne ha.
        values.listName = list?.listName ?? ""
        values.openingDistance = openingDistance
        values.keeping = keeping.full
        return values
    }

    /// Due famiglie realizzano la stessa faccia ereditata se hanno lo stesso ruolo: i loro nomi PostScript,
    /// naturalmente diversi, non costituiscono una seconda aggiunta. Dentro una famiglia conta la faccia precisa.
    static func differs(_ property: InspectorProperty, between actual: StyleValues, and inherited: StyleValues) -> Bool {
        if property == .face, actual.family != inherited.family {
            return actual.bold != inherited.bold || actual.italic != inherited.italic
        }
        // Nei font variabili il Regular e il Bold possono essere lo stesso file, a pesi diversi: conta anche il ruolo.
        if property == .face, actual.bold != inherited.bold || actual.italic != inherited.italic { return true }
        return property.only(actual) != property.only(inherited)
    }

    /// I valori effettivi di un punto, quelli che darebbero gli stili, e i nomi degli stili.
    static func actualAndInherited(in text: NSAttributedString, at index: Int, sheet: StyleSheet,
                                   resolver: FontRoleResolver = FontRoleResolver()) -> (actual: StyleValues, inherited: StyleValues, names: StyleNames)? {
        guard let character = characterStyle(in: text, at: index) else { return nil }
        let names = StyleNames(paragraph: text.attribute(.paragraphStyleName, at: index, effectiveRange: nil) as? String,
                               word: text.attribute(.wordStyleName, at: index, effectiveRange: nil) as? String,
                               character: text.attribute(.characterStyleName, at: index, effectiveRange: nil) as? String)
        var paragraph = (text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle).map(ParagraphStyle.init) ?? ParagraphStyle()
        let list = listItem(in: text, at: index)
        let expectedCharacter = sheet.resolveCharacter(paragraphStyle: names.paragraph, wordStyle: names.word, characterStyle: names.character,
                                                       base: styleBase, resolver: resolver)
        let expectedParagraph = sheet.resolveParagraph(styleName: names.paragraph)
        let recordedLevel = (text.attribute(.outlineLevel, at: index, effectiveRange: nil) as? NSNumber)?.intValue
        paragraph.outlineLevel = recordedLevel.map { $0 > 0 ? $0 : nil }
            ?? (recordedLevel == nil ? expectedParagraph.outlineLevel ?? DocumentOutline.headingLevel(of: names.paragraph) : nil)
        let expectedList = sheet.values(of: names.paragraph).list
        let expectedOpening = sheet.values(of: names.paragraph).openingDistance ?? 0
        let opening = openingDistance(in: text, at: index) ?? expectedOpening
        let expectedKeeping = sheet.lineKeeping(styleName: names.paragraph)
        let keeping = sheet.lineKeeping(styleName: names.paragraph, own: lineKeeping(in: text, at: index))
        return (fullValues(character: character, paragraph: paragraph, list: list, openingDistance: opening, keeping: keeping, resolver: resolver),
                fullValues(character: expectedCharacter, paragraph: expectedParagraph, list: expectedList, openingDistance: expectedOpening,
                           keeping: expectedKeeping, resolver: resolver), names)
    }

    /// Il tratto continuo attorno a `index` in cui `matches` resta vero, misurato a tratti di attributi uguali (dentro
    /// un tratto `matches` vale come al suo inizio). Vuoto se non vale in `index`. Non passa dal corpo a una nota né da
    /// una nota al corpo.
    public static func continuousRun(in text: NSAttributedString, around index: Int, where matches: (Int) -> Bool) -> NSRange {
        guard index >= 0, index < text.length, matches(index) else { return NSRange(location: max(index, 0), length: 0) }
        let inNote = text.attribute(.footnote, at: index, effectiveRange: nil) != nil
        func belongs(_ location: Int) -> Bool {
            (text.attribute(.footnote, at: location, effectiveRange: nil) != nil) == inNote && matches(location)
        }
        var run = NSRange(location: 0, length: 0)
        _ = text.attributes(at: index, effectiveRange: &run)
        var start = run.location
        var end = NSMaxRange(run)
        while start > 0 {
            var previous = NSRange(location: 0, length: 0)
            _ = text.attributes(at: start - 1, effectiveRange: &previous)
            guard belongs(previous.location) else { break }
            start = previous.location
        }
        while end < text.length {
            var next = NSRange(location: 0, length: 0)
            _ = text.attributes(at: end, effectiveRange: &next)
            guard belongs(end) else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    /// Il tratto continuo attorno a `index` in cui la proprietà ha il valore dato a mano che ha in `index` (diverso da
    /// quello che darebbero gli stili). Vuoto se in `index` il valore non è dato a mano.
    public static func ownRun(of property: InspectorProperty, in text: NSAttributedString, around index: Int, sheet: StyleSheet) -> NSRange {
        guard index >= 0, index < text.length, let here = actualAndInherited(in: text, at: index, sheet: sheet) else {
            return NSRange(location: max(index, 0), length: 0)
        }
        let value = property.only(here.actual)
        guard differs(property, between: here.actual, and: here.inherited) else { return NSRange(location: index, length: 0) }
        return continuousRun(in: text, around: index) { location in
            guard let values = actualAndInherited(in: text, at: location, sheet: sheet) else { return false }
            return property.only(values.actual) == value && differs(property, between: values.inherited, and: values.actual)
        }
    }

    /// Le proprietà di un oggetto nel punto in cui comincia la selezione, con valore e provenienza. Una selezione
    /// che attraversa valori diversi lo segnala.
    public static func inspect(_ level: StyleTarget, in text: NSAttributedString, range: NSRange, sheet: StyleSheet,
                               resolver: FontRoleResolver = FontRoleResolver()) -> [InspectedValue] {
        guard text.length > 0 else { return [] }
        let start = min(range.location, text.length - 1)
        guard let here = actualAndInherited(in: text, at: start, sheet: sheet, resolver: resolver) else { return [] }
        // Gli altri punti in cui la selezione cambia attributi: bastano gli inizi dei tratti.
        var others: [StyleValues] = []
        if range.length > 1 {
            text.enumerateAttributes(in: NSRange(location: start, length: min(range.length, text.length - start))) { _, run, _ in
                if run.location != start, let values = actualAndInherited(in: text, at: run.location, sheet: sheet, resolver: resolver) { others.append(values.actual) }
            }
        }
        let exceptions = ruleExceptions(in: text, at: start)
        return InspectorProperty.properties(of: level).map { property in
            let value = property.only(here.actual), inherited = property.only(here.inherited)
            let source: ValueSource = differs(property, between: here.actual, and: here.inherited) || exceptions.contains(property)
                ? .own : definer(of: property, names: here.names, sheet: sheet).map(ValueSource.style) ?? .document
            return InspectedValue(property: property, value: value, inherited: inherited, source: source,
                                  isMixed: others.contains { property.only($0) != value })
        }
    }

    /// Lo stile che dà il valore di una proprietà: si cercano, dal più vicino, lo stile di carattere, quello di
    /// parola e quello di paragrafo, ciascuno con gli stili su cui si basa.
    static func definer(of property: InspectorProperty, names: StyleNames, sheet: StyleSheet) -> String? {
        let candidates: [(String?, StyleTarget)] = [(names.character, .character), (names.word, .word), (names.paragraph, .paragraph)]
        for (name, target) in candidates {
            var next = name
            var seen: Set<String> = []
            while let current = next, !seen.contains(current), let style = sheet.style(named: current) {
                seen.insert(current)
                if style.declares(property) { return current }
                next = style.basedOn
            }
        }
        return nil
    }

    /// Lo stile che riceve una proprietà quando la si porta «nello stile»: il più vicino al testo tra quelli che
    /// la possono fissare (carattere, poi parola, poi paragrafo).
    public static func receivingStyle(for property: InspectorProperty, in text: NSAttributedString, at index: Int) -> (name: String, target: StyleTarget)? {
        guard text.length > 0 else { return nil }
        let index = min(index, text.length - 1)
        let order: [(NSAttributedString.Key, StyleTarget)] = switch property.level {
        case .character: [(.characterStyleName, .character), (.wordStyleName, .word), (.paragraphStyleName, .paragraph)]
        case .word: [(.wordStyleName, .word), (.paragraphStyleName, .paragraph)]
        case .paragraph: [(.paragraphStyleName, .paragraph)]
        }
        for (key, target) in order {
            if let name = text.attribute(key, at: index, effectiveRange: nil) as? String { return (name, target) }
        }
        return nil
    }

    // MARK: Modifiche

    /// Dà a mano un valore (i campi della proprietà in `values`) al testo dell'intervallo: ai caratteri per le
    /// proprietà di carattere e di parola, ai paragrafi interi per quelle di paragrafo.
    public static func setValue(_ values: StyleValues, of property: InspectorProperty, in text: NSMutableAttributedString, range: NSRange,
                                resolver: FontRoleResolver = FontRoleResolver()) {
        guard text.length > 0 else { return }
        let values = property.only(values)
        switch property.level {
        case .character, .word:
            let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
            guard range.length > 0 else { return }
            var pieces: [(NSRange, CharacterStyle)] = []
            text.enumerateAttributes(in: range) { attributes, run, _ in
                // Il testo in un font non installato conserva il suo stile originale: non lo si tocca, salvo quando gli si
                // dà proprio una famiglia o una faccia (allora riceve un font vero e smette di essere «mancante»).
                if let encoded = attributes[.missingFont] as? String {
                    guard property == .family || property == .face, var style = characterStyle(in: text, at: run.location),
                          let original = MissingFont(encoded: encoded) else { return }
                    // Nero e corsivo dal nome del font mancante: «Minion3Subhead-Bold» resta nero nella famiglia nuova.
                    let name = original.fontName
                    let bold = ["Bold", "Black", "Heavy", "Semibold", "SemiBold", "Demi"].contains { name.contains($0) }
                    let italic = name.contains("Italic") || name.range(of: "It(?=[A-Z]|$)", options: .regularExpression) != nil
                    style.fontRole = FontRole(italic: italic, bold: bold)
                    pieces.append((run, style))
                } else if let style = characterStyle(in: text, at: run.location) {
                    pieces.append((run, style))
                }
            }
            for (run, style) in pieces {
                var fields = CharacterFields(style)
                values.apply(to: &fields, resolver: resolver)
                let result = fields.resolved(fallback: style)
                if result != style { apply(result, to: text, range: run) }
            }
        case .paragraph:
            if property == .list {
                let list = values.list
                setList(in: text, range: range) { _ in list }
                return
            }
            if property == .openingDistance {
                setOpeningDistance(values.openingDistance, in: text, range: range)
                return
            }
            if property.isLineKeeping {
                changeLineKeeping(in: text, range: range) { values.keeping.over($0) }
                return
            }
            let paragraphs = paragraphRange(in: text, for: range)
            var location = paragraphs.location
            while location < NSMaxRange(paragraphs) {
                let paragraph = bodyParagraph(in: text, at: location).range
                let current = (text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle).map(ParagraphStyle.init) ?? ParagraphStyle()
                let result = values.applied(to: current)
                if result != current { text.addAttribute(.paragraphStyle, value: result.nsParagraphStyle, range: paragraph) }
                location = max(NSMaxRange(paragraph), location + 1)
            }
        }
    }

    /// Mette nel testo uno stile di carattere risolto, toccando solo gli attributi che ne dipendono.
    static func apply(_ style: CharacterStyle, to text: NSMutableAttributedString, range: NSRange) {
        let rendered = characterAttributes(for: style).attributes
        TextStyling.writeFont(rendered[.font]!, in: text, range: range)
        writeDerivedAttributes(rendered, in: text, range: range)
    }

    /// La distanza d'apertura data a mano al paragrafo che contiene `index`, se ne ha una.
    public static func openingDistance(in text: NSAttributedString, at index: Int) -> Double? {
        guard index >= 0, index < text.length else { return nil }
        return (text.attribute(.openingDistance, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue
    }

    /// Dà a mano la distanza d'apertura ai paragrafi interi dell'intervallo (`nil` la toglie: torna quella dello stile).
    public static func setOpeningDistance(_ value: Double?, in text: NSMutableAttributedString, range: NSRange) {
        guard text.length > 0 else { return }
        let paragraphs = paragraphRange(in: text, for: range)
        guard paragraphs.length > 0 else { return }
        if let value { text.addAttribute(.openingDistance, value: NSNumber(value: value), range: paragraphs) } else { text.removeAttribute(.openingDistance, range: paragraphs) }
    }

    /// La distanza d'apertura che vale per il paragrafo che comincia in `location`: quella data a mano, o quella del suo
    /// stile, o nessuna.
    public static func effectiveOpeningDistance(in text: NSAttributedString, atParagraph location: Int, sheet: StyleSheet) -> Double {
        guard location < text.length else { return 0 }
        if let own = openingDistance(in: text, at: location) { return own }
        return sheet.values(of: text.attribute(.paragraphStyleName, at: location, effectiveRange: nil) as? String).openingDistance ?? 0
    }

    /// Toglie il valore dato a mano: ogni tratto (o paragrafo) dell'intervallo torna al valore dei suoi stili.
    public static func resetValue(of property: InspectorProperty, in text: NSMutableAttributedString, range: NSRange, sheet: StyleSheet,
                                  resolver: FontRoleResolver = FontRoleResolver()) {
        guard text.length > 0 else { return }
        if property == .openingDistance {
            setOpeningDistance(nil, in: text, range: range)
            setRuleException(property, false, in: text, range: paragraphRange(in: text, for: range))
            return
        }
        if property.isLineKeeping {
            changeLineKeeping(in: text, range: range) { own in
                var values = StyleValues()
                values.keeping = own
                values.clear(property)
                return values.keeping
            }
            setRuleException(property, false, in: text, range: paragraphRange(in: text, for: range))
            return
        }
        let range = property.level == .paragraph ? paragraphRange(in: text, for: range) : NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        // Prima si raccolgono i valori ereditati di ogni pezzo, poi si applicano.
        var pieces: [(NSRange, StyleValues)] = []
        if property.level == .paragraph {
            var location = range.location
            while location < NSMaxRange(range) {
                let paragraph = bodyParagraph(in: text, at: location).range
                if let values = actualAndInherited(in: text, at: paragraph.location, sheet: sheet) { pieces.append((paragraph, values.inherited)) }
                location = max(NSMaxRange(paragraph), location + 1)
            }
        } else {
            text.enumerateAttributes(in: range) { _, run, _ in
                if let values = actualAndInherited(in: text, at: run.location, sheet: sheet), differs(property, between: values.actual, and: values.inherited) {
                    pieces.append((run, values.inherited))
                }
            }
        }
        for (piece, inherited) in pieces {
            if property == .family || property == .face {
                // La faccia ereditata intera: file, assi e forma, come la risolvono gli stili con le facce dei ruoli del
                // documento. Il solo nome del file non basta: in Adobe Kis VF Regular e Bold sono lo stesso file.
                text.enumerateAttributes(in: piece) { attributes, run, _ in
                    guard var style = characterStyle(in: text, at: run.location) else { return }
                    let resolved = sheet.resolveCharacter(paragraphStyle: attributes[.paragraphStyleName] as? String,
                                                          wordStyle: attributes[.wordStyleName] as? String,
                                                          characterStyle: attributes[.characterStyleName] as? String,
                                                          base: styleBase, resolver: resolver)
                    if style.fontName != resolved.fontName { style.features = [] }
                    style.fontName = resolved.fontName
                    style.variations = resolved.variations
                    style.prefersVariableFont = resolved.prefersVariableFont
                    style.fontRole = nil
                    apply(style, to: text, range: run)
                    text.removeAttribute(.fontRole, range: run)
                }
                continue
            }
            setValue(inherited, of: property, in: text, range: piece)
        }
        // Tornare al valore ereditato vuol dire anche lasciarlo di nuovo alle regole.
        setRuleException(property, false, in: text, range: range)
    }

    // MARK: Valori che vincono sulle regole

    /// Le proprietà che le regole non toccano nel punto.
    public static func ruleExceptions(in text: NSAttributedString, at index: Int) -> Set<InspectorProperty> {
        guard index < text.length else { return [] }
        return ruleExceptions(text.attribute(.ruleExceptions, at: index, effectiveRange: nil) as? String)
    }

    static func ruleExceptions(_ encoded: String?) -> Set<InspectorProperty> {
        Set((encoded ?? "").split(separator: " ").compactMap { InspectorProperty(rawValue: String($0)) })
    }

    /// Le proprietà scritte come valore dell'attributo (e del file): nell'ordine dell'ispettore; `nil` se nessuna.
    static func encodedRuleExceptions(_ properties: Set<InspectorProperty>) -> String? {
        properties.isEmpty ? nil : InspectorProperty.allCases.filter(properties.contains).map(\.rawValue).joined(separator: " ")
    }

    /// Fa sì che le regole non tocchino (`on`) o tornino a toccare la proprietà nell'intervallo: ai caratteri per le
    /// proprietà di carattere e di parola, ai paragrafi interi per quelle di paragrafo. Famiglia e faccia vanno insieme.
    public static func setRuleException(_ property: InspectorProperty, _ on: Bool, in text: NSMutableAttributedString, range: NSRange) {
        guard text.length > 0 else { return }
        let range = property.level == .paragraph ? paragraphRange(in: text, for: range) : NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard range.length > 0 else { return }
        let together: Set<InspectorProperty> = property == .family || property == .face ? [.family, .face] : [property]
        var pieces: [(NSRange, String?)] = []
        text.enumerateAttribute(.ruleExceptions, in: range) { value, run, _ in
            var set = ruleExceptions(value as? String)
            if on { set.formUnion(together) } else { set.subtract(together) }
            let encoded = encodedRuleExceptions(set)
            if encoded != value as? String { pieces.append((run, encoded)) }
        }
        for (run, encoded) in pieces {
            if let encoded { text.addAttribute(.ruleExceptions, value: encoded, range: run) } else { text.removeAttribute(.ruleExceptions, range: run) }
        }
    }

    /// I valori dell'ispettore con quelli che danno le regole che toccano il punto `index` (nell'ordine in cui si
    /// applicano): un valore non dato a mano che una regola cambia viene da lei, con il valore che lei gli dà.
    public static func withRuleSources(_ values: [InspectedValue], rules: [TextRule], in text: NSAttributedString, at index: Int,
                                       sheet originalSheet: StyleSheet, resolver: FontRoleResolver = FontRoleResolver()) -> [InspectedValue] {
        let sheet = originalSheet.compilingStyleRules([]).sheet
        guard !rules.isEmpty, text.length > 0 else { return values }
        let index = min(index, text.length - 1)
        let original = text.attributedSubstring(from: NSRange(location: index, length: 1))
        let all = NSRange(location: 0, length: 1)
        typealias Given = [InspectorProperty: [(value: StyleValues, rule: String, owner: String?)]]
        // Le regole una dopo l'altra su una copia del punto: per ogni proprietà, chi la cambia e in che valore.
        func simulate(_ piece: NSMutableAttributedString) -> Given? {
            guard var previous = actualAndInherited(in: piece, at: 0, sheet: sheet, resolver: resolver)?.actual else { return nil }
            var given: Given = [:]
            for rule in rules {
                if rule.target == .paragraph {
                    Rules.applyParagraphStyle(rule.styleName, in: piece, sheet: sheet, resolver: resolver)
                } else {
                    Rules.applyStyle(rule.styleName, to: all, in: piece, sheet: sheet, resolver: resolver)
                }
                guard let now = actualAndInherited(in: piece, at: 0, sheet: sheet, resolver: resolver)?.actual else { continue }
                for property in InspectorProperty.allCases where differs(property, between: now, and: previous) {
                    given[property, default: []].append((property.only(now), rule.summary, rule.formulaOwner))
                }
                previous = now
            }
            return given
        }
        // Ogni regola da sola: quali proprietà cambierebbe. Fra due regole sullo stesso punto conta la prima che
        // cambia la proprietà; le altre che la cambierebbero sono scavalcate.
        func alone(_ base: NSAttributedString) -> [InspectorProperty: [String]] {
            guard let before = actualAndInherited(in: base, at: 0, sheet: sheet, resolver: resolver)?.actual else { return [:] }
            var result: [InspectorProperty: [String]] = [:]
            for rule in rules {
                let piece = NSMutableAttributedString(attributedString: base)
                if rule.target == .paragraph {
                    Rules.applyParagraphStyle(rule.styleName, in: piece, sheet: sheet, resolver: resolver)
                } else {
                    Rules.applyStyle(rule.styleName, to: all, in: piece, sheet: sheet, resolver: resolver)
                }
                guard let now = actualAndInherited(in: piece, at: 0, sheet: sheet, resolver: resolver)?.actual else { continue }
                for property in InspectorProperty.allCases where differs(property, between: now, and: before) {
                    result[property, default: []].append(rule.summary)
                }
            }
            return result
        }
        guard var given = simulate(NSMutableAttributedString(attributedString: original)) else { return values }
        var candidates = alone(original)
        // Applicando una regola i valori dati a mano restano: per sapere che cosa le regole darebbero a uno di
        // questi, si rifà la prova senza di lui.
        for value in values where value.source == .own && !value.isMixed {
            let piece = NSMutableAttributedString(attributedString: original)
            resetValue(of: value.property, in: piece, range: all, sheet: sheet, resolver: resolver)
            if let list = simulate(piece)?[value.property] { given[value.property] = list }
            candidates[value.property] = alone(piece)[value.property]
        }
        // Un'eccezione segnata nel testo vince su ogni regola, come nell'impaginazione.
        let exceptions = ruleExceptions(in: text, at: index)
        return values.map { value in
            guard !value.isMixed, let list = given[value.property], let last = list.last else { return value }
            var copy = value
            // Le scavalcate prima, poi quella che conta.
            let names = (candidates[value.property] ?? []).filter { $0 != last.rule } + [last.rule]
            // Una regola storica non tocca un valore dato a mano; quella che viene da una formula sì, tranne dove
            // un'eccezione lo protegge.
            let active = last.owner != nil
            if value.source == .own && (!active || exceptions.contains(value.property)) {
                copy.rules = RuleInfluence(rules: names, owner: last.owner, yielded: last.value)
                return copy
            }
            copy.rules = RuleInfluence(rules: names, owner: last.owner, suspended: value.source == .own ? value.value : nil)
            copy.value = last.value
            copy.source = .rule(last.rule)
            return copy
        }
    }

    /// Gli stili con il valore del punto `index` portato nello stile che lo riceve (vedi `receivingStyle`); `nil` se
    /// nessuno stile lo può ricevere. Se il valore coincide con quello che lo stile erediterebbe comunque, lo stile
    /// smette di fissarlo.
    public static func sheet(_ sheet: StyleSheet, takingValueOf property: InspectorProperty, from text: NSAttributedString, at index: Int, replacingFormula: Bool = false) -> StyleSheet? {
        guard text.length > 0, let receiver = receivingStyle(for: property, in: text, at: index),
              let position = sheet.styles.firstIndex(where: { $0.name == receiver.name }) else { return nil }
        let index = min(index, text.length - 1)
        let style = sheet.styles[position]
        if !replacingFormula, sheet.formulaDefinition(for: property, inStyle: style.name)?.isCalculated == true { return sheet }
        if property != .face, let inspected = actualAndInherited(in: text, at: index, sheet: sheet),
           StylePropertyOperation.constant(property.only(inspected.actual), for: property) != nil {
            return sheet.setting(property.only(inspected.actual), of: property, inStyle: receiver.name,
                                 base: styleBase, replacingFormula: replacingFormula)
        }
        var values = style.values
        if property == .list {
            let list = listItem(in: text, at: index)?.listName ?? ""
            let parent = sheet.values(of: style.basedOn).listName ?? ""
            values.listName = list == parent ? nil : list
        } else if property == .openingDistance {
            let here = effectiveOpeningDistance(in: text, atParagraph: bodyParagraph(in: text, at: index).range.location, sheet: sheet)
            let parent = sheet.values(of: style.basedOn).openingDistance ?? 0
            values.openingDistance = here == parent ? nil : here
        } else if property.isLineKeeping {
            let paragraph = bodyParagraph(in: text, at: index).range.location
            func field(_ resolved: LineKeeping.Resolved) -> LineKeeping {
                var values = StyleValues()
                values.keeping = resolved.full
                return property.only(values).keeping
            }
            let here = field(sheet.lineKeeping(styleName: style.name, own: lineKeeping(in: text, at: paragraph)))
            let parent = field(sheet.lineKeeping(styleName: style.basedOn))
            values.clear(property)
            if here != parent { values.keeping = here.over(values.keeping) }
        } else {
            // Ciò che il testo ha di diverso da quanto darebbe lo stile senza i suoi valori propri.
            let difference = styleValues(from: text, at: index, target: receiver.target, sheet: sheet, basedOn: style.basedOn)
            switch property {
            case .family:
                // La famiglia scelta non porta con sé un corsivo o un nero dato a mano: quelli restano sul testo.
                // Si legge dal testo, non da `difference`: una faccia personalizzata può non coincidere con quella
                // automatica, ma ciò non deve far perdere la famiglia durante il trasferimento.
                values.fontName = nil
                values.family = characterStyle(in: text, at: index).flatMap { FontRoleResolver().family(of: $0) }
            case .face:
                // Analogamente, una faccia non incorpora nello stile un'eventuale famiglia data a mano.
                values.fontName = difference.fontName
                values.italic = difference.italic
                values.bold = difference.bold
            case .size: values.size = difference.size
            case .color: values.color = difference.color
            case .smallCaps: values.smallCaps = difference.smallCaps
            case .verticalPosition: values.verticalPosition = difference.verticalPosition
            case .decorations: values.decorations = difference.decorations
            case .shaping: values.graphite = difference.graphite
            case .language: values.language = difference.language
            case .hyphenates: values.hyphenates = difference.hyphenates
            case .alignment: values.alignment = difference.alignment
            case .leftIndent: values.leftIndent = difference.leftIndent
            case .rightIndent: values.rightIndent = difference.rightIndent
            case .firstLineIndent: values.firstLineIndent = difference.firstLineIndent
            case .spaceBefore: values.spaceBefore = difference.spaceBefore
            case .spaceAfter: values.spaceAfter = difference.spaceAfter
            case .lineHeightMultiple: values.lineHeightMultiple = difference.lineHeightMultiple
            case .lineSpacing: values.lineSpacing = difference.lineSpacing
            case .list, .openingDistance, .keepWithNext, .keepTogether, .orphanLines, .widowLines: break
            }
        }
        var result = sheet
        result.styles[position].values = values
        result.styles[position].formulas.removeAll { $0.operation.property.inspectorProperty == property }
        result.styles[position] = result.materializingFormulas(of: receiver.name) ?? result.styles[position]
        return result
    }
}

extension StyleValues {
    /// La Lista in cui questi valori mettono il paragrafo: nessuna se non è fissata o se è la stringa vuota.
    public var list: ListItem? { listName.flatMap { $0.isEmpty ? nil : ListItem(listName: $0) } }
}

extension InspectorProperty {
    /// Una delle voci della tenuta delle righe fra le pagine.
    public var isLineKeeping: Bool { [.keepWithNext, .keepTogether, .orphanLines, .widowLines].contains(self) }
}

extension LineKeeping.Resolved {
    /// Tutti e quattro i valori, fissati.
    var full: LineKeeping { LineKeeping(withNext: withNext, together: together, linesAtEnd: linesAtEnd, linesAtStart: linesAtStart) }
}

extension TextStyling {
    /// Cambia la tenuta data a mano a ciascun paragrafo dell'intervallo, partendo dalla sua.
    static func changeLineKeeping(in text: NSMutableAttributedString, range: NSRange, _ change: (LineKeeping) -> LineKeeping) {
        guard text.length > 0 else { return }
        let paragraphs = paragraphRange(in: text, for: range)
        var location = paragraphs.location
        var pieces: [(NSRange, LineKeeping)] = []
        while location < NSMaxRange(paragraphs) {
            let paragraph = bodyParagraph(in: text, at: location).range
            pieces.append((paragraph, change(lineKeeping(in: text, at: paragraph.location))))
            location = max(NSMaxRange(paragraph), location + 1)
        }
        for (paragraph, keeping) in pieces where paragraph.length > 0 { setLineKeeping(keeping, in: text, paragraphs: paragraph) }
    }
}

extension InspectorProperty {
    /// Il valore della proprietà in parole brevi, per le spiegazioni dell'ispettore («5 mm», «Justified», «On»).
    public func text(of values: StyleValues) -> String {
        func points(_ value: Double?) -> String {
            guard let value else { return "—" }
            let millimetres = value / 72 * 25.4
            return value == 0 ? "0 pt" : millimetres.formatted(.number.precision(.fractionLength(0...1))) + " mm"
        }
        func onOff(_ value: Bool?) -> String { value.map { $0 ? "On" : "Off" } ?? "—" }
        switch self {
        case .family: return values.family ?? values.fontName ?? "—"
        case .face: return values.fontName ?? "—"
        case .size: return values.size.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " pt" } ?? "—"
        case .smallCaps: return values.smallCaps?.rawValue ?? "—"
        case .color: return (values.color ?? "").isEmpty ? "Automatic" : values.color!
        case .verticalPosition: return values.verticalPosition ?? "—"
        case .decorations: return (values.decorations ?? "").isEmpty ? "None" : values.decorations!
        case .shaping: return values.graphite == nil ? "Core Text" : "Graphite"
        case .language: return (values.language ?? "").isEmpty ? "Document language" : values.language!
        case .hyphenates: return onOff(values.hyphenates)
        case .alignment: return values.alignment.map { $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst() } ?? "—"
        case .leftIndent: return points(values.leftIndent)
        case .rightIndent: return points(values.rightIndent)
        case .firstLineIndent: return points(values.firstLineIndent)
        case .spaceBefore: return points(values.spaceBefore)
        case .spaceAfter: return points(values.spaceAfter)
        case .lineSpacing: return points(values.lineSpacing)
        case .openingDistance: return points(values.openingDistance)
        case .lineHeightMultiple: return values.lineHeightMultiple.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " ×" } ?? "—"
        case .list: return (values.listName ?? "").isEmpty ? "None" : values.listName!
        case .keepWithNext: return onOff(values.keeping.withNext)
        case .keepTogether: return onOff(values.keeping.together)
        case .orphanLines: return values.keeping.linesAtEnd.map(String.init) ?? "—"
        case .widowLines: return values.keeping.linesAtStart.map(String.init) ?? "—"
        }
    }
}
