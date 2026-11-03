import AppKit
import CoreText

/// Passaggio tra il modello di documento e il testo attribuito che usano l'editor provvisorio e il layout.
extension Document {
    /// Costruisce il documento da un testo attribuito. Si conservano font, corpo, funzioni e stile di paragrafo;
    /// gli altri attributi (colori, sottolineature, allegati) non fanno ancora parte del modello.
    public init(attributedString text: NSAttributedString, pageSetup: PageSetup = .a4, appliesFontTracking: Bool = true) {
        var settings = Document(pageSetup: pageSetup, appliesFontTracking: appliesFontTracking)
        // Senza altre indicazioni non si presume una lingua.
        settings.language = nil
        self.init(attributedString: text, settings: settings)
    }

    /// Costruisce il documento da un testo attribuito, prendendo le impostazioni da un altro documento.
    public init(attributedString text: NSAttributedString, settings: Document) {
        let string = text.string as NSString
        let attributed = text
        var paragraphs: [FlatParagraph] = []
        var location = 0
        var endsWithTerminator = true  // un testo vuoto è un solo paragrafo vuoto

        func style(at index: Int) -> CharacterStyle {
            guard index < string.length, let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont else {
                // Il font che AppKit sottintende quando l'attributo manca.
                return CharacterStyle(fontName: "Helvetica", size: 12)
            }
            let language = text.attribute(.language, at: index, effectiveRange: nil) as? String
            let role = (text.attribute(.fontRole, at: index, effectiveRange: nil) as? String).flatMap(FontRole.init(rawValue:))
            // Testo che chiedeva un font non installato: finché è ancora nel font di ripiego, si salva lo stile originale.
            if let original = (text.attribute(.missingFont, at: index, effectiveRange: nil) as? String).flatMap(MissingFont.init(encoded:)),
               original.fallbackName == font.fontName {
                let split = SmallCaps.split(original.features)
                return CharacterStyle(fontName: original.fontName, size: Double(font.pointSize), features: split.rest, language: language,
                                      variations: original.variations, fontRole: role,
                                      hyphenates: text.attribute(.hyphenates, at: index, effectiveRange: nil) as? Bool ?? true,
                                      color: TextStyling.textColor(in: text, at: index),
                                      verticalPosition: (text.attribute(.verticalPosition, at: index, effectiveRange: nil) as? String).flatMap(VerticalPosition.init(encoded:)),
                                      decorations: (text.attribute(.lineDecorations, at: index, effectiveRange: nil) as? String).flatMap(LineDecoration.decode) ?? [],
                                      graphite: text.attribute(.graphite, at: index, effectiveRange: nil) as? String,
                                      smallCaps: TextStyling.smallCaps(in: text, at: index, font: split.smallCaps))
            }
            var style = CharacterStyle(font as CTFont)
            style.fontName = TextStyling.chosenFaceName(of: font as CTFont, fallback: style.fontName)
            style.language = language
            style.fontRole = role
            style.opticalSize = (text.attribute(.fontOpticalSize, at: index, effectiveRange: nil) as? String).flatMap(StaticOpticalSize.init(rawValue:))
            style.hyphenates = text.attribute(.hyphenates, at: index, effectiveRange: nil) as? Bool ?? true
            style.color = TextStyling.textColor(in: text, at: index)
            style.verticalPosition = (text.attribute(.verticalPosition, at: index, effectiveRange: nil) as? String).flatMap(VerticalPosition.init(encoded:))
            style.decorations = (text.attribute(.lineDecorations, at: index, effectiveRange: nil) as? String).flatMap(LineDecoration.decode) ?? []
            style.graphite = text.attribute(.graphite, at: index, effectiveRange: nil) as? String
            style.smallCaps = TextStyling.smallCaps(in: text, at: index, font: style.smallCaps)
            return style
        }
        func names(at index: Int) -> (word: String?, character: String?) {
            guard index < string.length else { return (nil, nil) }
            return (text.attribute(.wordStyleName, at: index, effectiveRange: nil) as? String,
                    text.attribute(.characterStyleName, at: index, effectiveRange: nil) as? String)
        }
        func run(_ text: String, at index: Int) -> TextRun {
            let named = names(at: index)
            return TextRun(text, style: style(at: index), wordStyleName: named.word, characterStyleName: named.character,
                           ruleExceptions: TextStyling.ruleExceptions(in: attributed, at: index),
                           field: (attributed.attribute(.field, at: index, effectiveRange: nil) as? String).flatMap(Field.init(encoded:)))
        }

        while location < string.length {
            // I paragrafi del corpo: gli a capo dentro una nota non li spezzano.
            let (paragraphRange, contentsEnd) = TextStyling.bodyParagraph(in: text, at: location)
            let start = paragraphRange.location, end = NSMaxRange(paragraphRange)
            let content = NSRange(location: start, length: contentsEnd - start)
            let paragraphStyle = text.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
            var runs: [Inline] = []
            // La nota che si sta leggendo, e lo stile del suo richiamo (vale per una nota ancora vuota).
            var note: FloatingObject?
            var anchorStyle = CharacterStyle(fontName: "Helvetica", size: 12)
            func closeNote() {
                guard var finished = note else { return }
                // Un paragrafo vuoto della nota conserva lo stile del paragrafo che lo precede, o del richiamo.
                var style = anchorStyle
                for position in finished.paragraphs.indices {
                    if let last = finished.paragraphs[position].last { style = last.style } else { finished.paragraphs[position] = [TextRun("", style: style)] }
                }
                runs.append(.floating(finished))
                note = nil
            }
            func appendMain(_ run: TextRun) {
                if case .text(var last)? = runs.last, last.continues(with: run) {
                    last.text += run.text
                    runs[runs.count - 1] = .text(last)
                } else {
                    runs.append(.text(run))
                }
            }
            text.enumerateAttributes(in: content) { attributes, range, _ in
                if attributes[.footnote] == nil, let image = attributes[.inlineImage] as? ImageAttachment {
                    // Un'immagine nella riga: ogni suo carattere è un'immagine.
                    closeNote()
                    for _ in 0..<range.length { runs.append(.image(image.image)) }
                    return
                }
                guard attributes[.footnote] != nil else {
                    closeNote()
                    if attributes[.field] != nil {
                        // Un campo per carattere: due campi uguali vicini restano due.
                        for index in range.location..<NSMaxRange(range) { appendMain(run(string.substring(with: NSRange(location: index, length: 1)), at: index)) }
                    } else {
                        appendMain(run(string.substring(with: range), at: range.location))
                    }
                    return
                }
                // Testo di nota: ogni carattere-richiamo apre una nota, e ciò che segue è il suo testo.
                var pieceStart = range.location
                func flushPiece(upTo end: Int) {
                    guard end > pieceStart else { return }
                    // Un campo nel testo di una nota: un carattere per volta.
                    if attributes[.field] != nil, end - pieceStart > 1 {
                        let stop = end
                        while pieceStart < stop {
                            let next = pieceStart + 1
                            flushPiece(upTo: next)
                            pieceStart = next
                        }
                        return
                    }
                    let run = run(string.substring(with: NSRange(location: pieceStart, length: end - pieceStart)), at: pieceStart)
                    if var current = note {
                        // Dentro la nota ogni a capo apre un paragrafo nuovo.
                        for (position, piece) in run.text.components(separatedBy: "\n").enumerated() {
                            if position > 0 { current.paragraphs.append([]) }
                            guard !piece.isEmpty else { continue }
                            let last = current.paragraphs.count - 1
                            if var previous = current.paragraphs[last].last, previous.continues(with: run) {
                                previous.text += piece
                                current.paragraphs[last][current.paragraphs[last].count - 1] = previous
                            } else {
                                current.paragraphs[last].append(run.with(text: piece))
                            }
                        }
                        note = current
                    } else {
                        // Testo marcato come nota ma senza richiamo davanti (il richiamo è stato cancellato): torna testo normale.
                        appendMain(run)
                    }
                }
                for index in range.location..<NSMaxRange(range) where TextStyling.isNoteAnchor(in: text, at: index) {
                    flushPiece(upTo: index)
                    closeNote()
                    note = FloatingObject(paragraphs: [[]], style: text.attribute(.footnote, at: index, effectiveRange: nil) as? String ?? FloatStyle.footnoteName)
                    note?.image = (text.attribute(.floatImage, at: index, effectiveRange: nil) as? ImageAttachment)?.image
                    anchorStyle = style(at: index)
                    pieceStart = index + 1
                }
                flushPiece(upTo: NSMaxRange(range))
            }
            closeNote()
            if runs.isEmpty { runs = [.text(TextRun("", style: style(at: start)))] }
            let list = (text.attribute(.listItem, at: start, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
            let styleName = text.attribute(.paragraphStyleName, at: start, effectiveRange: nil) as? String
            var resolvedParagraph = paragraphStyle.map(ParagraphStyle.init) ?? ParagraphStyle()
            let section = (text.attribute(.sectionTitle, at: start, effectiveRange: nil) as? String).flatMap(SectionMark.init(encoded:))
            if section != nil {
                // Il livello di un titolo è la profondità della sua sezione: nel modello sta nell'albero, e il paragrafo
                // conserva soltanto quello del suo stile.
                resolvedParagraph.outlineLevel = settings.styles.resolveParagraph(styleName: styleName).outlineLevel
            } else if let level = (text.attribute(.outlineLevel, at: start, effectiveRange: nil) as? NSNumber)?.intValue {
                resolvedParagraph.outlineLevel = level > 0 ? level : nil
            } else {
                // Testo attribuito vecchio o costruito a mano: la migrazione avviene una volta, qui.
                resolvedParagraph.outlineLevel = settings.styles.resolveParagraph(styleName: styleName).outlineLevel
                    ?? DocumentOutline.headingLevel(of: styleName)
            }
            paragraphs.append(FlatParagraph(Paragraph(styleName: styleName, style: resolvedParagraph, list: list, inlines: runs,
                                                      openingDistance: TextStyling.openingDistance(in: text, at: start),
                                                      keeping: TextStyling.lineKeeping(in: text, at: start)),
                                            section: section,
                                            cell: (text.attribute(.tableCell, at: start, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)),
                                            sectionReturn: text.attribute(.sectionReturn, at: start, effectiveRange: nil) as? String))
            endsWithTerminator = end > contentsEnd
            location = end
        }
        if endsWithTerminator {
            // Dopo l'ultimo a capo c'è un paragrafo vuoto, quello in cui si trova il cursore a fine testo.
            let last = string.length - 1
            let paragraphStyle = last >= 0 ? text.attribute(.paragraphStyle, at: last, effectiveRange: nil) as? NSParagraphStyle : nil
            let styleName = last >= 0 ? text.attribute(.paragraphStyleName, at: last, effectiveRange: nil) as? String : nil
            var resolvedParagraph = paragraphStyle.map(ParagraphStyle.init) ?? ParagraphStyle()
            let declared = last >= 0 ? (text.attribute(.finalParagraphOutlineLevel, at: last, effectiveRange: nil) as? NSNumber)?.intValue : nil
            let inherited = last >= 0 ? (text.attribute(.outlineLevel, at: last, effectiveRange: nil) as? NSNumber)?.intValue : nil
            let finalSection = last >= 0 ? (text.attribute(.finalParagraphSection, at: last, effectiveRange: nil) as? String).flatMap(SectionMark.init(encoded:)) : nil
            if finalSection != nil {
                resolvedParagraph.outlineLevel = settings.styles.resolveParagraph(styleName: styleName).outlineLevel
            } else if let level = declared ?? inherited {
                resolvedParagraph.outlineLevel = level > 0 ? level : nil
            } else {
                resolvedParagraph.outlineLevel = settings.styles.resolveParagraph(styleName: styleName).outlineLevel
                    ?? DocumentOutline.headingLevel(of: styleName)
            }
            paragraphs.append(FlatParagraph(Paragraph(styleName: styleName, style: resolvedParagraph,
                                                      list: TextStyling.finalParagraphListItem(in: text),
                                                      inlines: [.text(TextRun("", style: style(at: max(last, 0))))]),
                                            section: finalSection,
                                            cell: last >= 0 ? (text.attribute(.finalParagraphCell, at: last, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)) : nil,
                                            sectionReturn: last >= 0 ? text.attribute(.finalParagraphSectionReturn, at: last, effectiveRange: nil) as? String : nil))
        }
        self = settings
        setFlatParagraphs(paragraphs)
    }

    /// Il documento come testo attribuito, con un a capo tra un paragrafo e l'altro.
    /// - Returns: il testo e i nomi dei font che non sono installati (sostituiti da un font di ripiego).
    public func attributedString() -> (text: NSAttributedString, missingFonts: [String]) {
        let result = NSMutableAttributedString()
        var attributes: [CharacterStyle: [NSAttributedString.Key: Any]] = [:]
        var missing: [String] = []

        func textAttributes(for style: CharacterStyle) -> [NSAttributedString.Key: Any] {
            if let cached = attributes[style] { return cached }
            let (result, isMissing) = TextStyling.characterAttributes(for: style)
            if isMissing, !missing.contains(style.fontName) { missing.append(style.fontName) }
            attributes[style] = result
            return result
        }
        func textAttributes(for run: TextRun) -> [NSAttributedString.Key: Any] {
            var result = textAttributes(for: run.style)
            if let name = run.wordStyleName { result[.wordStyleName] = name }
            if let name = run.characterStyleName { result[.characterStyleName] = name }
            if let exceptions = TextStyling.encodedRuleExceptions(run.ruleExceptions) { result[.ruleExceptions] = exceptions }
            if let field = run.field { result[.field] = field.encoded }
            return result
        }

        let items = flatParagraphs
        for (index, item) in items.enumerated() {
            let paragraph = item.paragraph
            let paragraphStyle = paragraph.style.nsParagraphStyle
            let paragraphStart = result.length
            var last: [NSAttributedString.Key: Any] = [:]
            for inline in paragraph.inlines {
                switch inline {
                case .text(let run):
                    last = textAttributes(for: run)
                    last[.paragraphStyle] = paragraphStyle
                    result.append(NSAttributedString(string: run.text, attributes: last))
                case .image(let image):
                    // Il carattere dell'oggetto, con gli attributi del testo che lo precede (servono alla riga e al cursore).
                    var attributes = last.isEmpty ? textAttributes(for: paragraph.inlines.lazy.compactMap { if case .text(let run) = $0 { run } else { nil } }.first?.style
                                                                   ?? TextStyling.styleBase) : last
                    attributes[.paragraphStyle] = paragraphStyle
                    attributes[.inlineImage] = ImageAttachment(image)
                    result.append(NSAttributedString(string: String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1), attributes: attributes))
                case .floating(let note):
                    // Nel testo la nota è un carattere-richiamo seguito dal suo testo, tutti marcati come nota;
                    // tra un paragrafo e l'altro della nota c'è un a capo, marcato anche lui.
                    var pieces = [TextRun(String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1), style: note.runs.first?.style ?? CharacterStyle(fontName: "Helvetica", size: 12))]
                    for (position, paragraph) in note.paragraphs.enumerated() {
                        if position > 0 { pieces.append(TextRun("\n", style: pieces[pieces.count - 1].style)) }
                        pieces.append(contentsOf: paragraph.filter { !$0.text.isEmpty })
                        // Un paragrafo vuoto che ne segue un altro lascia il proprio stile al suo a capo.
                        if position > 0, paragraph.allSatisfy(\.text.isEmpty), let style = paragraph.first?.style { pieces[pieces.count - 1].style = style }
                    }
                    for (position, run) in pieces.enumerated() {
                        var attributes = textAttributes(for: run)
                        attributes[.paragraphStyle] = paragraphStyle
                        attributes[.footnote] = note.style
                        // L'immagine di una figura sta sul suo segnaposto.
                        if position == 0, let image = note.image { attributes[.floatImage] = ImageAttachment(image) }
                        result.append(NSAttributedString(string: run.text, attributes: attributes))
                    }
                    // L'a capo che chiude il paragrafo non deve risultare parte della nota.
                    if last.isEmpty, let style = note.runs.first?.style {
                        last = textAttributes(for: style)
                        last[.paragraphStyle] = paragraphStyle
                    }
                }
            }
            if index < items.count - 1 {
                last[.paragraphStyle] = paragraphStyle
                result.append(NSAttributedString(string: "\n", attributes: last))
            }
            // Lo stile di paragrafo con un nome vale per tutto il paragrafo, a capo finale compreso.
            if let name = paragraph.styleName, result.length > paragraphStart {
                result.addAttribute(.paragraphStyleName, value: name, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
            }
            // Il livello è esplicito anche quando è zero: il nome dello stile non lo decide più. Per un titolo è la
            // profondità della sua sezione.
            let level = item.section?.depth ?? paragraph.style.outlineLevel ?? 0
            if result.length > paragraphStart {
                result.addAttribute(.outlineLevel, value: NSNumber(value: level),
                                    range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
            } else if index == items.count - 1, index > 0 {
                result.addAttribute(.finalParagraphOutlineLevel, value: NSNumber(value: level),
                                    range: NSRange(location: result.length - 1, length: 1))
            }
            // La distanza d'apertura data a mano, su tutto il paragrafo.
            if let distance = paragraph.openingDistance, result.length > paragraphStart {
                result.addAttribute(.openingDistance, value: NSNumber(value: distance), range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
            }
            if !paragraph.keeping.isEmpty, result.length > paragraphStart {
                result.addAttribute(.lineKeeping, value: paragraph.keeping.encoded, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
            }
            // L'elenco è un attributo di tutto il paragrafo, a capo finale compreso.
            if let list = paragraph.list, result.length > paragraphStart {
                result.addAttribute(.listItem, value: list.encoded, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
            }
            // Un ultimo paragrafo vuoto non ha caratteri: se il suo elenco non è quello che erediterebbe dal
            // paragrafo precedente, lo si dichiara sull'a capo che lo precede.
            if index == items.count - 1, index > 0, result.length == paragraphStart, items[index - 1].paragraph.list != paragraph.list {
                result.addAttribute(.finalParagraphList, value: paragraph.list?.encoded ?? "", range: NSRange(location: result.length - 1, length: 1))
            }
            // Il titolo di una sezione è segnato su tutto il paragrafo, a capo finale compreso; un ultimo paragrafo vuoto
            // che è un titolo lo dichiara sull'a capo che lo precede.
            // Il paragrafo di una cella: segnato su tutto il paragrafo (o, se è l'ultimo e vuoto, sull'a capo prima).
            if let cell = item.cell {
                if result.length > paragraphStart {
                    result.addAttribute(.tableCell, value: cell.encoded, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
                } else if index == items.count - 1, index > 0 {
                    result.addAttribute(.finalParagraphCell, value: cell.encoded, range: NSRange(location: result.length - 1, length: 1))
                }
            }
            if let mark = item.section {
                if result.length > paragraphStart {
                    result.addAttribute(.sectionTitle, value: mark.encoded, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
                } else if index == items.count - 1, index > 0 {
                    result.addAttribute(.finalParagraphSection, value: mark.encoded, range: NSRange(location: result.length - 1, length: 1))
                }
            }
            // Il ritorno alla sezione esterna, come il titolo: su tutto il paragrafo, o sull'a capo prima dell'ultimo vuoto.
            if let target = item.sectionReturn {
                if result.length > paragraphStart {
                    result.addAttribute(.sectionReturn, value: target, range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
                } else if index == items.count - 1, index > 0 {
                    result.addAttribute(.finalParagraphSectionReturn, value: target, range: NSRange(location: result.length - 1, length: 1))
                }
            }
        }
        return (result, missing)
    }
}

extension NSMutableAttributedString {
    /// Dà un'identità nuova alle sezioni i cui titoli stanno in questo testo: un titolo incollato apre una sezione nuova,
    /// non una seconda copia della stessa.
    public func renewSectionIdentities() {
        var renamed: [String: String] = [:]
        let all = NSRange(location: 0, length: length)
        for key in [NSAttributedString.Key.sectionTitle, .finalParagraphSection] {
            var changes: [(NSRange, String)] = []
            enumerateAttribute(key, in: all) { value, range, _ in
                guard let encoded = value as? String, var mark = SectionMark(encoded: encoded) else { return }
                mark.id = renamed[mark.id] ?? { let fresh = Section.newID(); renamed[mark.id] = fresh; return fresh }()
                changes.append((range, mark.encoded))
            }
            for (range, encoded) in changes { addAttribute(key, value: encoded, range: range) }
        }
        // Un ritorno a una sezione del pezzo segue la sua identità nuova.
        for key in [NSAttributedString.Key.sectionReturn, .finalParagraphSectionReturn] {
            var changes: [(NSRange, String)] = []
            enumerateAttribute(key, in: all) { value, range, _ in
                guard let id = value as? String, let fresh = renamed[id] else { return }
                changes.append((range, fresh))
            }
            for (range, id) in changes { addAttribute(key, value: id, range: range) }
        }
    }

    /// Un pezzo da incollare dentro la sezione `owner` (vuota: fuori da ogni sezione), che sta a profondità `depth`: le sue
    /// sezioni diventano interne di lei (scendono di `depth` livelli), e il suo testo che tornava al primo livello del
    /// pezzo torna a lei.
    public func nestSections(under owner: String, depth: Int) {
        let all = NSRange(location: 0, length: length)
        if depth > 0 {
            for key in [NSAttributedString.Key.sectionTitle, .finalParagraphSection] {
                var changes: [(NSRange, String)] = []
                enumerateAttribute(key, in: all) { value, range, _ in
                    guard let encoded = value as? String, var mark = SectionMark(encoded: encoded) else { return }
                    mark.depth += depth
                    changes.append((range, mark.encoded))
                }
                for (range, encoded) in changes { addAttribute(key, value: encoded, range: range) }
            }
        }
        guard !owner.isEmpty else { return }
        for key in [NSAttributedString.Key.sectionReturn, .finalParagraphSectionReturn] {
            var changes: [NSRange] = []
            enumerateAttribute(key, in: all) { value, range, _ in
                if (value as? String)?.isEmpty == true { changes.append(range) }
            }
            for range in changes { addAttribute(key, value: owner, range: range) }
        }
    }

    /// Toglie i segni delle sezioni: un pezzo che entra in un paragrafo non ne fa un titolo.
    public func removeSectionMarks() {
        let all = NSRange(location: 0, length: length)
        removeAttribute(.sectionTitle, range: all)
        removeAttribute(.finalParagraphSection, range: all)
        removeAttribute(.sectionReturn, range: all)
        removeAttribute(.finalParagraphSectionReturn, range: all)
    }
}

extension FloatingObject {
    /// Il carattere che nel testo tiene il posto del richiamo di nota (U+FFFC, «oggetto sostitutivo»).
    public static let anchorCharacter: unichar = 0xFFFC
}

/// L'immagine di un carattere del testo (attributo `.inlineImage`): confrontabile per contenuto, come ogni valore di un
/// attributo.
public final class ImageAttachment: NSObject, @unchecked Sendable {
    public let image: ImageObject

    public init(_ image: ImageObject) { self.image = image }

    public override func isEqual(_ object: Any?) -> Bool { (object as? ImageAttachment)?.image == image }
    public override var hash: Int { image.hashValue }
}

extension NSAttributedString.Key {
    /// Sul segnaposto di una figura: la sua immagine (valore `ImageAttachment`).
    public static let floatImage = NSAttributedString.Key("WordProcessorFloatImage")

    /// Su un carattere U+FFFC: l'immagine che sta nella riga al suo posto (valore `ImageAttachment`).
    public static let inlineImage = NSAttributedString.Key("WordProcessorInlineImage")

    /// Segna il richiamo di un flottante (per ora, una nota a piè di pagina) e il suo contenuto, che lo segue. Il valore è
    /// il nome dello stile di flottante; un valore vero, senza nome, vale «Nota a piè di pagina».
    public static let footnote = NSAttributedString.Key("WordProcessorFootnote")

    /// La lingua di un tratto di testo, quando è diversa da quella del documento. Il valore è il codice della
    /// lingua (per esempio "la"); serve alla sillabazione e al controllo ortografico.
    public static let language = NSAttributedString.Key("WordProcessorLanguage")

    /// Su un carattere `Field.placeholder`: il campo che la composizione vi scrive (valore `Field.encoded`).
    public static let field = NSAttributedString.Key("WordProcessorField")

    /// Segna i paragrafi di una cella di tabella, a capo finale compreso. Il valore è `CellMark.encoded`.
    public static let tableCell = NSAttributedString.Key("WordProcessorTableCell")

    /// Sull'ultimo a capo del testo: l'ultimo paragrafo, vuoto, è in una cella (valore `CellMark.encoded`).
    public static let finalParagraphCell = NSAttributedString.Key("WordProcessorFinalParagraphCell")

    /// Segna il paragrafo che è il titolo di una sezione, a capo finale compreso. Il valore è `SectionMark.encoded`.
    public static let sectionTitle = NSAttributedString.Key("WordProcessorSectionTitle")

    /// Sull'ultimo a capo del testo: l'ultimo paragrafo, vuoto, è il titolo di una sezione (valore `SectionMark.encoded`).
    public static let finalParagraphSection = NSAttributedString.Key("WordProcessorFinalParagraphSection")

    /// Segna il primo paragrafo che, dopo una sezione interna, torna alla sezione che la contiene, a capo finale
    /// compreso. Il valore è l'identità di quella sezione; vuoto per il primo livello (fuori da ogni sezione).
    public static let sectionReturn = NSAttributedString.Key("WordProcessorSectionReturn")

    /// Sull'ultimo a capo del testo: l'ultimo paragrafo, vuoto, torna alla sezione esterna (valore come `sectionReturn`).
    public static let finalParagraphSectionReturn = NSAttributedString.Key("WordProcessorFinalParagraphSectionReturn")

    /// Segna il testo che chiedeva un font non installato. Il valore è lo stile originale, codificato da `MissingFont`.
    public static let missingFont = NSAttributedString.Key("WordProcessorMissingFont")
}

/// Lo stile che un tratto aveva nel file quando il suo font non è installato su questo Mac.
struct MissingFont: Equatable {
    var fontName: String
    var features: [FeatureSetting]
    var variations: [AxisValue]
    /// Il font di ripiego con cui il testo è mostrato: se l'utente lo cambia, lo stile originale non vale più.
    var fallbackName: String

    /// Quattro righe di testo, così il valore dell'attributo resta una stringa che copia e incolla conservano.
    var encoded: String {
        [fontName, features.map(\.description).joined(separator: " "), variations.map(\.description).joined(separator: " "), fallbackName].joined(separator: "\n")
    }

    init(fontName: String, features: [FeatureSetting], variations: [AxisValue] = [], fallbackName: String) {
        self.fontName = fontName
        self.features = features
        self.variations = variations
        self.fallbackName = fallbackName
    }

    init?(encoded: String) {
        let parts = encoded.components(separatedBy: "\n")
        guard parts.count == 4 else { return nil }
        let features = parts[1].split(separator: " ").map { DocumentFormat.parseFeature(String($0)) }
        let variations = parts[2].split(separator: " ").map { DocumentFormat.parseVariation(String($0)) }
        guard !features.contains(where: { $0 == nil }), !variations.contains(where: { $0 == nil }) else { return nil }
        self.init(fontName: parts[0], features: features.compactMap { $0 }, variations: variations.compactMap { $0 }, fallbackName: parts[3])
    }
}

extension CharacterStyle {
    public init(_ font: CTFont) {
        let variations = FontVariations.values(of: font)
        // Il maiuscoletto che il font mostra non è una funzione qualsiasi: diventa la scelta tipografica.
        let split = SmallCaps.split(FontFeatures.settings(of: font))
        self.init(fontName: FontVariations.baseName(of: font), size: Double(font.pointSize), features: split.rest,
                  variations: variations, prefersVariableFont: variations.isEmpty && FontVariations.isShadowed(font), smallCaps: split.smallCaps)
    }
}

extension NSParagraphStyle {
    /// La tabulazione che distingue l'allineamento sulla virgola: decimale (con i segni decimali come terminatori), a 0.
    static var decimalMarker: NSTextTab { NSTextTab(textAlignment: .right, location: 0, options: [.columnTerminators: CharacterSet(charactersIn: ".,")]) }

    /// Vero per un paragrafo allineato sulla virgola.
    public var isDecimalAligned: Bool {
        alignment == .right && tabStops.count == 1 && tabStops[0].location == 0 && tabStops[0].options[.columnTerminators] != nil
    }
}

extension ParagraphStyle {
    init(_ style: NSParagraphStyle) {
        self.init()
        alignment = switch style.alignment {
        case .left: .left
        case .right: style.isDecimalAligned ? .decimal : .right
        case .center: .center
        case .justified: .justified
        default: .natural
        }
        firstLineIndent = Double(style.firstLineHeadIndent - style.headIndent)
        leftIndent = Double(style.headIndent)
        // In NSParagraphStyle il rientro destro è negativo; uno positivo è una larghezza dal margine sinistro e qui non si conserva.
        rightIndent = Double(max(-style.tailIndent, 0))
        spaceBefore = Double(style.paragraphSpacingBefore)
        spaceAfter = Double(style.paragraphSpacing)
        lineSpacing = Double(style.lineSpacing)
        lineHeightMultiple = Double(style.lineHeightMultiple)
    }

    var nsParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = switch alignment {
        case .natural: .natural
        case .left: .left
        case .right: .right
        case .center: .center
        case .justified: .justified
        // Sulla virgola: per il sistema (e per le altre applicazioni) a destra, con una sola tabulazione decimale a 0 che
        // lo distingue.
        case .decimal: .right
        }
        if alignment == .decimal { style.tabStops = [NSParagraphStyle.decimalMarker] }
        style.headIndent = CGFloat(leftIndent)
        style.firstLineHeadIndent = CGFloat(leftIndent + firstLineIndent)
        style.tailIndent = CGFloat(-rightIndent)
        style.paragraphSpacingBefore = CGFloat(spaceBefore)
        style.paragraphSpacing = CGFloat(spaceAfter)
        style.lineSpacing = CGFloat(lineSpacing)
        style.lineHeightMultiple = CGFloat(lineHeightMultiple)
        return style
    }
}
