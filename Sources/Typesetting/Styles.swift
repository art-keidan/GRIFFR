import AppKit

// MARK: - Stili con un nome

/// A quale specie di oggetto si applica uno stile.
public enum StyleTarget: String, Sendable, CaseIterable {
    case paragraph, word, character
}

/// I valori che uno stile fissa. Un valore `nil` non è fissato: si eredita.
///
/// Le proprietà sono di tre livelli: del carattere (font, corpo, funzioni, assi), della parola (lingua,
/// sillabazione), del paragrafo (allineamento, rientri, spazi, interlinea). Uno stile di paragrafo può fissare
/// tutti e tre i livelli, uno stile di parola i primi due, uno stile di carattere solo il primo: i livelli alti
/// passano i valori in basso, non il contrario.
extension NSAttributedString.Key {
    /// La distanza d'apertura data a mano a un paragrafo (in punti, `NSNumber`), su tutto il paragrafo, a capo compreso.
    public static let openingDistance = NSAttributedString.Key("WordProcessorOpeningDistance")
}

public enum PageStartSpacing: Hashable, Sendable {
    case disabled
    case distance(Double)
}

public struct StyleValues: Hashable, Sendable {
    var resolutionSteps: [StyleResolutionStep] = []
    // Carattere. La faccia si indica in due modi: con il nome preciso (`fontName`), oppure con la famiglia e i
    // due segnali corsivo e nero; così «corsivo» vale in qualunque famiglia arrivi da sopra.
    public var fontName: String?
    public var family: String?
    public var italic: Bool?
    public var bold: Bool?
    public var size: Double?
    public var features: [FeatureSetting]?
    public var variations: [AxisValue]?
    /// Corpo ottico statico (`StaticOpticalSize.rawValue`); la stringa vuota ripristina l'automatico.
    public var opticalSize: String?
    /// Il colore, `#rrggbb`; la stringa vuota riporta al colore automatico.
    public var color: String?
    /// La posizione verticale, come la scrive `VerticalPosition.encoded`; la stringa vuota riporta alla linea di base.
    public var verticalPosition: String?
    /// I filetti, come li scrive `LineDecoration.encode`; la stringa vuota toglie quelli ereditati.
    public var decorations: String?
    /// La composizione, come la scrive `Graphite.encodedChoice`: `off` per Core Text, `on` o le funzioni per Graphite.
    public var graphite: String?
    /// Il maiuscoletto voluto; `.off` toglie quello ereditato.
    public var smallCaps: SmallCaps?
    // Parola. Per la lingua, la stringa vuota riporta alla lingua del documento.
    public var language: String?
    public var hyphenates: Bool?
    // Paragrafo.
    public var alignment: ParagraphStyle.Alignment?
    public var firstLineIndent: Double?
    public var leftIndent: Double?
    public var rightIndent: Double?
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    public var lineSpacing: Double?
    public var lineHeightMultiple: Double?
    /// La Lista con un nome in cui lo stile mette il paragrafo (lo stile «Esempio» numera da solo).
    public var listName: String?
    /// Il ruolo della sezione che lo stile apre quando lo si dà a un paragrafo («Titolo 1» apre un capitolo); la stringa
    /// vuota toglie quello ereditato. Serve solo ad aprire la sezione: poi la sezione non dipende più dallo stile.
    public var opensSection: String?
    public var nextStyle: String?
    /// Il livello di paragrafazione: 1, 2, 3…; 0 toglie esplicitamente quello ereditato, `nil` lo lascia ereditare.
    public var outlineLevel: Int?
    /// La distanza d'apertura, in punti: dove scende il paragrafo che apre una sequenza di pagine (il titolo di un capitolo
    /// che comincia su una pagina nuova, il primo paragrafo del documento), misurata dal margine superiore.
    public var openingDistance: Double?
    /// Distanza quando il capoverso apre il flusso principale. nil eredita.
    public var pageStartSpacing: PageStartSpacing?
    /// La tenuta delle righe fra le pagine; ciascun valore si eredita da solo.
    public var keeping = LineKeeping()

    public init() {}

    /// Questi valori sopra quelli di `parent`: vale il proprio dove è fissato, altrimenti quello del genitore.
    func over(_ parent: StyleValues) -> StyleValues {
        var result = parent
        // Una faccia precisa annulla famiglia e segnali ereditati, e viceversa.
        if fontName != nil { result.family = nil; result.italic = nil; result.bold = nil }
        if family != nil || italic != nil || bold != nil, fontName == nil { result.fontName = nil }
        func take<T>(_ path: WritableKeyPath<StyleValues, T?>) { if let value = self[keyPath: path] { result[keyPath: path] = value } }
        take(\.fontName); take(\.family); take(\.italic); take(\.bold); take(\.size); take(\.features); take(\.variations); take(\.opticalSize)
        take(\.color); take(\.verticalPosition); take(\.decorations); take(\.graphite); take(\.smallCaps); take(\.language); take(\.hyphenates)
        take(\.alignment); take(\.firstLineIndent); take(\.leftIndent); take(\.rightIndent)
        take(\.spaceBefore); take(\.spaceAfter); take(\.lineSpacing); take(\.lineHeightMultiple); take(\.listName); take(\.opensSection)
        take(\.nextStyle); take(\.outlineLevel); take(\.openingDistance); take(\.pageStartSpacing)
        result.keeping = keeping.over(parent.keeping)
        if !parent.resolutionSteps.isEmpty || !resolutionSteps.isEmpty {
            let before = parent.resolutionSteps.isEmpty ? [.values(parent.withoutResolutionSteps)] : parent.resolutionSteps
            let after = resolutionSteps.isEmpty ? [.values(withoutResolutionSteps)] : resolutionSteps
            result.resolutionSteps = before + after
        }
        return result
    }

    /// Solo i valori che uno stile di quella specie può fissare.
    func limited(to target: StyleTarget) -> StyleValues {
        var result = self
        if target != .paragraph {
            result.alignment = nil; result.firstLineIndent = nil; result.leftIndent = nil; result.rightIndent = nil
            result.spaceBefore = nil; result.spaceAfter = nil; result.lineSpacing = nil; result.lineHeightMultiple = nil
            result.listName = nil
            result.opensSection = nil
            result.nextStyle = nil
            result.outlineLevel = nil
            result.openingDistance = nil
            result.pageStartSpacing = nil
            result.keeping = LineKeeping()
        }
        if target == .character { result.language = nil; result.hyphenates = nil }
        result.resolutionSteps = resolutionSteps.compactMap { step in
            switch step {
            case .values(let values): return .values(values.limited(to: target))
            case .formula(let formula): return (try? formula.validate(for: target)) != nil ? step : nil
            }
        }
        return result
    }

    /// Applica i valori di carattere e di parola a uno stile di carattere già risolto.
    public func applied(to style: CharacterStyle, resolver: FontRoleResolver = FontRoleResolver()) -> CharacterStyle {
        var fields = CharacterFields(style)
        apply(to: &fields, resolver: resolver)
        return fields.resolved(fallback: style)
    }

    /// Applica i valori di paragrafo a uno stile di paragrafo già risolto.
    public func applied(to style: ParagraphStyle) -> ParagraphStyle {
        if !resolutionSteps.isEmpty {
            let input = StylePredicateState(character: TextStyling.styleBase, paragraph: style)
            let steps = resolutionSteps.filter {
                if case .formula(let formula) = $0 { return formula.operation.property.isParagraphProperty }
                return true
            }
            var projection = self
            projection.resolutionSteps = steps
            return (try? projection.evaluatingFormulas(from: input).paragraph) ?? withoutResolutionSteps.applied(to: style)
        }
        var result = style
        if let alignment { result.alignment = alignment }
        if let firstLineIndent { result.firstLineIndent = firstLineIndent }
        if let leftIndent { result.leftIndent = leftIndent }
        if let rightIndent { result.rightIndent = rightIndent }
        if let spaceBefore { result.spaceBefore = spaceBefore }
        if let spaceAfter { result.spaceAfter = spaceAfter }
        if let lineSpacing { result.lineSpacing = lineSpacing }
        if let lineHeightMultiple { result.lineHeightMultiple = lineHeightMultiple }
        if let outlineLevel { result.outlineLevel = outlineLevel > 0 ? outlineLevel : nil }
        return result
    }

    func apply(to fields: inout CharacterFields, resolver: FontRoleResolver = FontRoleResolver()) {
        if !resolutionSteps.isEmpty {
            var projection = self
            projection.resolutionSteps = resolutionSteps.filter {
                if case .formula(let formula) = $0 { return !formula.operation.property.isParagraphProperty }
                return true
            }
            let input = StylePredicateState(character: fields.resolved(fallback: TextStyling.styleBase))
            if let output = try? projection.evaluatingFormulas(from: input, resolver: resolver) {
                fields = CharacterFields(output.character)
            } else {
                withoutResolutionSteps.apply(to: &fields, resolver: resolver)
            }
            return
        }
        if let fontName {
            fields.fontName = fontName
            fields.features = []
            fields.variations = []
            fields.prefersVariableFont = false
            fields.fontRole = nil
            fields.opticalSize = nil
        } else if family != nil || italic != nil || bold != nil {
            let current = fields.resolved(fallback: TextStyling.styleBase)
            let description = fields.fontName.flatMap(FontFaces.description(of:))
            let wantedFamily = family ?? description?.family ?? resolver.family(of: current)
            let currentRole = resolver.role(of: current) ?? FontRole(italic: description?.italic ?? false, bold: description?.bold ?? false)
            let wantedRole = FontRole(italic: italic ?? currentRole.isItalic, bold: bold ?? currentRole.isBold)
            if let wantedFamily,
               let face = resolver.resolve(family: wantedFamily, role: wantedRole, current: current, preservingAxes: true) {
                if face.fontName != fields.fontName { fields.features = [] }
                fields.fontName = face.fontName
                fields.variations = face.variations
                fields.prefersVariableFont = face.prefersVariableFont
            }
            if family != nil { fields.opticalSize = nil }
        }
        if let size { fields.size = size }
        if let features { fields.features = features }
        if let variations { fields.variations = variations }
        if let opticalSize { fields.opticalSize = opticalSize.isEmpty ? nil : StaticOpticalSize(rawValue: opticalSize) }
        if let color { fields.color = color.isEmpty ? nil : color }
        if let verticalPosition { fields.verticalPosition = VerticalPosition(encoded: verticalPosition) }
        if let decorations { fields.decorations = LineDecoration.decode(decorations) ?? [] }
        if let graphite, let choice = Graphite.choice(fromEncoded: graphite) { fields.graphite = choice }
        if let smallCaps { fields.smallCaps = smallCaps }
        if let language { fields.language = language.isEmpty ? nil : language }
        if let hyphenates { fields.hyphenates = hyphenates }
    }
}

/// Uno stile con un nome, per una specie di oggetto. Può basarsi su un altro stile della stessa specie, e fissa
/// solo ciò che cambia rispetto a quello.
public struct NamedStyle: Hashable, Sendable {
    public var name: String
    public var target: StyleTarget
    public var basedOn: String?
    public var values: StyleValues
    public var formulas: [StyleFormula]
    /// I risultati con un nome che le formule dello stile richiamano (formato 12).
    public var variables: [StyleVariable]
    /// La testata, per uno stile di titolo (formato 14).
    public var heading: HeadingComposition?

    public init(name: String, target: StyleTarget, basedOn: String? = nil, values: StyleValues = StyleValues(), formulas: [StyleFormula] = [],
                variables: [StyleVariable] = [], heading: HeadingComposition? = nil) {
        self.formulas = formulas
        self.variables = variables
        self.heading = heading
        self.name = name
        self.target = target
        self.basedOn = basedOn
        self.values = values
    }
}

/// Gli stili di un documento.
public struct StyleSheet: Hashable, Sendable {
    public var selections: [WordSelection] = []
    /// Definizioni riutilizzabili conservate nel documento, con riferimenti per identità.
    public var reusableFormulas: [ReusableFormula] = []
    public var styles: [NamedStyle]

    public init(styles: [NamedStyle] = []) {
        self.styles = styles
    }

    public var isEmpty: Bool { styles.isEmpty }

    public func style(named name: String) -> NamedStyle? { styles.first { $0.name == name } }

    /// I valori di uno stile con quelli degli stili su cui è basato, limitati a ciò che la sua specie può fissare.
    public func values(of name: String?) -> StyleValues {
        guard let name, let style = style(named: name) else { return StyleValues() }
        var chain: [NamedStyle] = [style]
        var next = style.basedOn
        while let parentName = next, let parent = self.style(named: parentName), !chain.contains(where: { $0.name == parent.name }) {
            chain.append(parent)
            next = parent.basedOn
        }
        return chain.reversed().reduce(StyleValues()) { accumulated, item in
            let resolved = (try? resolvingReusableStyle(item)) ?? item
            return resolved.declarations.limited(to: style.target).over(accumulated)
        }
    }

    /// Lo stile di carattere di un tratto: dalla base (il documento, o ciò che sta sopra), poi lo stile del
    /// paragrafo, lo stile di parola e lo stile di carattere, ciascuno sopra il precedente.
    public func resolveCharacter(paragraphStyle: String?, wordStyle: String?, characterStyle: String?, base: CharacterStyle,
                                 resolver: FontRoleResolver = FontRoleResolver()) -> CharacterStyle {
        var fields = CharacterFields(base)
        values(of: paragraphStyle).apply(to: &fields, resolver: resolver)
        values(of: wordStyle).apply(to: &fields, resolver: resolver)
        values(of: characterStyle).apply(to: &fields, resolver: resolver)
        return fields.resolved(fallback: base)
    }

    public func resolveParagraph(styleName: String?, base: ParagraphStyle = ParagraphStyle()) -> ParagraphStyle {
        values(of: styleName).applied(to: base)
    }

    /// Gli stili di paragrafo che dichiarano quel livello di paragrafazione, anche per eredità, nell'ordine del foglio.
    /// Il nome non conta: «Capitolo» con livello 1 è uno stile di livello 1, «Titolo 2» con livello 0 non lo è.
    public func headingStyles(forLevel level: Int) -> [String] {
        guard level > 0 else { return [] }
        return styles.filter { $0.target == .paragraph && resolveParagraph(styleName: $0.name).outlineLevel == level }.map(\.name)
    }

    /// Lo stile da dare a un titolo che passa al livello `level` e che aveva lo stile `current`. Fra gli stili di quel
    /// livello si preferisce uno basato sullo stesso stile di `current` (la stessa serie), poi il primo del foglio. Se il
    /// livello non ha stili, se ne aggiunge uno: basato sullo stile del livello più vicino sopra, di cui prende l'aspetto,
    /// con il solo livello cambiato; in un foglio senza titoli, la definizione predefinita. Restituisce il foglio
    /// (cambiato solo se lo stile è nuovo) e il nome.
    public func headingStyle(forLevel level: Int, replacing current: String?) -> (sheet: StyleSheet, name: String)? {
        guard level > 0 else { return nil }
        let candidates = headingStyles(forLevel: level)
        if let current, let family = style(named: current)?.basedOn,
           let sameFamily = candidates.first(where: { style(named: $0)?.basedOn == family }) {
            return (self, sameFamily)
        }
        if let first = candidates.first { return (self, first) }
        // Il nome: «Titolo N», se è libero; altrimenti «Livello N», «Livello N (2)»…
        var name = "Titolo \(level)"
        if style(named: name) != nil {
            name = "Livello \(level)"
            var counter = 2
            while style(named: name) != nil { name = "Livello \(level) (\(counter))"; counter += 1 }
        }
        var heading: NamedStyle
        if let above = (1..<level).reversed().lazy.compactMap({ self.headingStyles(forLevel: $0).first }).first {
            heading = NamedStyle(name: name, target: .paragraph, basedOn: above, values: StyleValues())
        } else if let model = Self.builtIn.style(named: "Titolo \(min(level, 3))") {
            heading = model
            heading.name = name
            // Un documento senza «Testo» (o senza lo stile di base) non lo riceve: il titolo si basa sul testo del documento.
            if let base = heading.basedOn, style(named: base) == nil { heading.basedOn = nil }
        } else {
            return nil
        }
        heading.values.outlineLevel = level
        var result = self
        result.styles.append(heading)
        return (result, name)
    }

    /// Gli stili predefiniti che le regole usano più spesso: la finestra delle regole li propone anche ai documenti che
    /// non li hanno ancora.
    public static var ruleStyles: [NamedStyle] {
        var centered = StyleValues()
        centered.alignment = .center
        // «Centrato» fissa solo l'allineamento: applicato da una regola a un paragrafo, il resto non cambia.
        return builtIn.styles.filter { $0.name.hasPrefix("Maiuscoletto") } + [NamedStyle(name: "Centrato", target: .paragraph, values: centered)]
    }

    /// Lo stile di paragrafo predefinito dei documenti nuovi.
    public static let defaultParagraphStyle = "Testo"

    /// Gli stili con cui nasce un documento nuovo.
    public static let builtIn: StyleSheet = {
        func values(_ build: (inout StyleValues) -> Void) -> StyleValues { var v = StyleValues(); build(&v); return v }
        return StyleSheet(styles: [
            NamedStyle(name: "Testo", target: .paragraph, values: values {
                $0.family = "Hoefler Text"; $0.size = 12; $0.alignment = .justified
            }),
            NamedStyle(name: "Titolo 1", target: .paragraph, basedOn: "Testo", values: values {
                $0.size = 18; $0.bold = true; $0.alignment = .natural; $0.spaceBefore = 18; $0.spaceAfter = 6; $0.opensSection = Section.Role.chapter; $0.outlineLevel = 1
            }),
            NamedStyle(name: "Titolo 2", target: .paragraph, basedOn: "Testo", values: values {
                $0.size = 14; $0.bold = true; $0.alignment = .natural; $0.spaceBefore = 12; $0.spaceAfter = 4; $0.opensSection = Section.Role.section; $0.outlineLevel = 2
            }),
            NamedStyle(name: "Titolo 3", target: .paragraph, basedOn: "Testo", values: values {
                $0.size = 13; $0.bold = true; $0.alignment = .natural; $0.spaceBefore = 10; $0.spaceAfter = 3; $0.opensSection = Section.Role.section; $0.outlineLevel = 3
            }),
            NamedStyle(name: "Citazione", target: .paragraph, basedOn: "Testo", values: values {
                $0.size = 11; $0.leftIndent = 24; $0.rightIndent = 24; $0.spaceBefore = 6; $0.spaceAfter = 6
            }),
            NamedStyle(name: "Esempio", target: .paragraph, basedOn: "Testo", values: values {
                $0.alignment = .natural; $0.spaceBefore = 6; $0.spaceAfter = 6; $0.listName = "Esempi"
            }),
            NamedStyle(name: "Sottoesempio", target: .paragraph, basedOn: "Esempio", values: values {
                $0.spaceBefore = 0; $0.spaceAfter = 0; $0.listName = "Sottoesempi"
            }),
            NamedStyle(name: "Latino", target: .word, values: values { $0.language = "la" }),
            NamedStyle(name: "Greco antico", target: .word, values: values { $0.language = "grc" }),
            NamedStyle(name: "Enfasi", target: .character, values: values { $0.italic = true }),
            NamedStyle(name: "Forte", target: .character, values: values { $0.bold = true }),
            NamedStyle(name: "Maiuscoletto", target: .character, values: values { $0.smallCaps = .lowercase }),
            NamedStyle(name: "Maiuscoletto delle sigle", target: .character, values: values { $0.smallCaps = .uppercase }),
        ])
    }()
}

/// Le proprietà di carattere e di parola mentre si calcola un tratto: il font può non essere ancora noto.
struct CharacterFields {
    var fontName: String?
    var size: Double?
    var features: [FeatureSetting] = []
    var variations: [AxisValue] = []
    var prefersVariableFont = false
    var fontRole: FontRole?
    var opticalSize: StaticOpticalSize?
    var language: String?
    var hyphenates = true
    var color: String?
    var verticalPosition: VerticalPosition?
    var decorations: [LineDecoration] = []
    var graphite: String?
    var smallCaps: SmallCaps = .off

    init(fontName: String? = nil, size: Double? = nil) {
        self.fontName = fontName
        self.size = size
    }

    init(_ style: CharacterStyle) {
        fontName = style.fontName
        size = style.size
        features = style.features
        variations = style.variations
        prefersVariableFont = style.prefersVariableFont
        fontRole = style.fontRole
        opticalSize = style.opticalSize
        language = style.language
        hyphenates = style.hyphenates
        color = style.color
        verticalPosition = style.verticalPosition
        decorations = style.decorations
        graphite = style.graphite
        smallCaps = style.smallCaps
    }

    func resolved(fallback: CharacterStyle) -> CharacterStyle {
        CharacterStyle(fontName: fontName ?? fallback.fontName, size: size ?? fallback.size, features: features, language: language,
                       variations: variations, prefersVariableFont: prefersVariableFont, fontRole: fontRole,
                       opticalSize: opticalSize, hyphenates: hyphenates, color: color,
                       verticalPosition: verticalPosition, decorations: decorations, graphite: graphite, smallCaps: smallCaps)
    }
}

// MARK: - Grassetto e corsivo

extension TextStyling {
    /// Il nero e il corsivo di una faccia installata, come li descrive macOS.
    public static func traits(ofFace postScriptName: String) -> (bold: Bool, italic: Bool)? {
        FontFaces.description(of: postScriptName).map { ($0.bold, $0.italic) }
    }

    /// La faccia della stessa famiglia con il nero e il corsivo chiesti (`nil`: come la faccia data); `nil` se la
    /// famiglia non ne ha una così.
    public static func face(of postScriptName: String, bold: Bool?, italic: Bool?) -> String? {
        guard let description = FontFaces.description(of: postScriptName) else { return nil }
        return FontFaces.face(family: description.family, italic: italic ?? description.italic, bold: bold ?? description.bold,
                              weightNear: description.weight)
    }
}

// MARK: - Facce di una famiglia

/// Ritrova le facce di una famiglia per corsivo, nero e peso, come le descrive macOS.
enum FontFaces {
    struct Description: Equatable {
        var family: String
        var italic: Bool
        var bold: Bool
        var weight: Int
    }

    private struct Member {
        var postScriptName: String
        var weight: Int
        var traits: Int
        /// La faccia nomina un corpo ottico (Caption, Display…) accanto a facce normali: si sceglie solo se manca
        /// la normale, perché il corpo ottico lo decide il corpo (con le varianti statiche o con l'asse `opsz`).
        var isOpticalVariant = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var members: [String: [Member]] = [:]
    nonisolated(unsafe) private static var descriptions: [String: Description?] = [:]

    private static func members(of family: String) -> [Member] {
        let optical = OpticalFonts.namesOpticalSizes(family: family)
        lock.lock()
        defer { lock.unlock() }
        if let known = members[family] { return known }
        let found = (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { entry -> Member? in
            guard entry.count >= 4, let name = entry[0] as? String, let weight = entry[2] as? Int, let traits = entry[3] as? Int else { return nil }
            let variant = optical && (entry[1] as? String).map { OpticalFonts.namesOpticalSize(style: $0) } == true
            return Member(postScriptName: name, weight: weight, traits: traits, isOpticalVariant: variant)
        }
        members[family] = found
        return found
    }

    /// Famiglia, corsivo, nero e peso di una faccia installata.
    static func description(of postScriptName: String) -> Description? {
        lock.lock()
        if let known = descriptions[postScriptName] { lock.unlock(); return known }
        lock.unlock()
        var result: Description?
        if let font = NSFont(name: postScriptName, size: 12), let family = font.familyName {
            let traits = NSFontManager.shared.traits(of: font).rawValue
            let weight = NSFontManager.shared.weight(of: font)
            result = Description(family: family, italic: traits & 1 != 0, bold: traits & 2 != 0, weight: weight)
        }
        lock.lock()
        descriptions[postScriptName] = .some(result)
        lock.unlock()
        return result
    }

    /// La faccia della famiglia con il corsivo e il nero chiesti. A parità, si preferisce il peso più vicino a
    /// `weightNear` (o al tondo e al nero consueti, 5 e 9) e una faccia senza altre particolarità (stretta,
    /// larga…); poi l'ordine in cui macOS elenca le facce. `nil` se la famiglia non ha una faccia così.
    static func face(family: String, italic: Bool, bold: Bool, weightNear: Int? = nil) -> String? {
        let target = weightNear.map { bold == ($0 >= 7) ? $0 : (bold ? 9 : 5) } ?? (bold ? 9 : 5)
        let candidates = members(of: family).enumerated().filter { _, member in
            (member.traits & 1 != 0) == italic && ((member.traits & 2 != 0) || member.weight >= 7) == bold
        }
        return candidates.min { a, b in
            func score(_ entry: (offset: Int, element: Member)) -> Int {
                (entry.element.isOpticalVariant ? 10_000 : 0) + abs(entry.element.weight - target) * 100
                    + (entry.element.traits & ~3 != 0 ? 50 : 0) + entry.offset
            }
            return score(a) < score(b)
        }?.element.postScriptName
    }
}
