import AppKit
import CoreText

// MARK: - Proprietà dinamiche

/// Ciò che la composizione dice di un paragrafo. Nessuno lo decide: cambia mentre si scrive.
public struct ParagraphFacts: Equatable, Sendable {
    public var lineCount: Int
    /// Le pagine, contate da 1, in cui cadono la prima e l'ultima riga.
    public var firstPage: Int
    public var lastPage: Int
    /// Vero se la prima riga del paragrafo è la prima riga del corpo della sua pagina; l'ultima, l'ultima.
    public var isFirstOnPage: Bool
    public var isLastOnPage: Bool
    public var wordCount: Int
    public var hyphenatedLines: Int
    /// L'ultima riga: quanto è larga (senza gli spazi finali) e quanto riempie della larghezza a disposizione (0…1).
    public var lastLineWidth: Double
    public var lastLineFill: Double
    /// Che cosa lo precede: niente (è il primo del documento) o un paragrafo di questo stile (`nil` se senza stile).
    public var isDocumentStart: Bool
    public var previousStyle: String?
    /// Le regole che valgono per questo paragrafo, descritte.
    public var rules: [String]

    public var isSplit: Bool { firstPage != lastPage }
}

/// Ciò che la composizione dice della riga in cui sta il cursore.
public struct LineFacts: Equatable, Sendable {
    /// La sua posizione nel paragrafo (da 1) e quante righe ha il paragrafo.
    public var number: Int
    public var count: Int
    public var page: Int
    /// Larghezze senza gli spazi finali: del testo prima della giustificazione, del testo composto, a disposizione.
    public var naturalWidth: Double
    public var width: Double
    public var availableWidth: Double
    public var endsWithHyphen: Bool
    public var wordCount: Int
    public var isNote: Bool

    /// Di quanto la giustificazione ha allargato (positivo) o stretto (negativo) la riga.
    public var justification: Double { width - naturalWidth }
}

/// Ciò che la composizione dice di una pagina.
public struct PageFacts: Equatable, Sendable {
    public var number: Int
    public var lineCount: Int
    /// Lo spazio rimasto vuoto tra l'ultima riga del corpo e ciò che sta sotto (note, figure in fondo, margine).
    public var freeSpace: Double
    public var hasNotes: Bool
    public var hasFigures: Bool

    public var isEven: Bool { number % 2 == 0 }
}

/// Ciò che la composizione dice del documento intero.
public struct DocumentFacts: Equatable, Sendable {
    public var pageCount: Int
    public var paragraphCount: Int
    public var wordCount: Int
    public var noteCount: Int
}

extension DocumentLayout {
    /// Il paragrafo del corpo che contiene la posizione: la sua posizione d'inizio, come la portano le sue righe.
    private func paragraphLocation(at index: Int) -> (location: Int, range: NSRange) {
        let index = min(max(index, 0), text.length)
        let string = text.string as NSString
        if index == text.length, index == 0 || TextStyling.isLineTerminator(string.character(at: index - 1)) {
            return (index, NSRange(location: index, length: 0))
        }
        let range = TextStyling.bodyParagraph(in: text, at: min(index, text.length - 1)).range
        return (range.location, range)
    }

    private func context(ofParagraphAt location: Int) -> TextRule.ParagraphContext {
        let style = location < text.length ? text.attribute(.paragraphStyleName, at: location, effectiveRange: nil) as? String : nil
        var previous: String?
        if location > 0 {
            let before = TextStyling.bodyParagraph(in: text, at: location - 1).range
            previous = text.attribute(.paragraphStyleName, at: before.location, effectiveRange: nil) as? String
        }
        return TextRule.ParagraphContext(styleName: style, previousStyleName: previous, isSequenceStart: SectionEditing.opensSequence(in: text, atParagraph: location))
    }

    private func bodyLines(ofParagraphAt location: Int) -> [Located] {
        allLines.filter { !$0.line.isNote && $0.line.paragraphLocation == location }
    }

    public func paragraphFacts(at index: Int, sheet: StyleSheet) -> ParagraphFacts? {
        let (location, range) = paragraphLocation(at: index)
        let lines = bodyLines(ofParagraphAt: location)
        guard let first = lines.first, let last = lines.last else { return nil }
        let context = context(ofParagraphAt: location)
        let firstOfPage = pages[first.page].lines.first { !$0.isNote }
        let lastOfPage = pages[last.page].lines.last { !$0.isNote }
        let body = BodyText(text, paragraph: range)
        return ParagraphFacts(
            lineCount: lines.count, firstPage: first.page + 1, lastPage: last.page + 1,
            isFirstOnPage: firstOfPage?.range == first.line.range, isLastOnPage: lastOfPage?.range == last.line.range,
            wordCount: body.wordCount, hyphenatedLines: lines.filter(\.line.endsWithHyphen).count,
            lastLineWidth: Double(last.line.naturalWidth),
            lastLineFill: last.line.availableWidth > 0 ? Double(min(last.line.width / last.line.availableWidth, 1)) : 0,
            isDocumentStart: location == 0, previousStyle: context.previousStyleName,
            rules: applicableRules(at: location, sheet: sheet).map { $0.summary(selections: sheet.selections) })
    }

    /// Le regole che valgono per il paragrafo: quelle decise dal testo, e quelle che la composizione gli ha applicato.
    func applicableRules(at location: Int, sheet: StyleSheet) -> [TextRule] {
        let compiled = sheet.compilingStyleRules()
        let applied = layoutRulesApplied[location] ?? []
        let context = context(ofParagraphAt: location)
        return Rules.usable(compiled.rules, sheet: compiled.sheet).filter { rule in
            rule.dependsOnLayout ? applied.contains(rule) : rule.applies(to: context)
        }
    }

    public func lineFacts(at index: Int, affinity: NSSelectionAffinity) -> LineFacts? {
        guard let located = locatedLine(for: index, affinity: affinity) else { return nil }
        let line = located.line
        let siblings = allLines.filter { $0.line.isNote == line.isNote && $0.line.paragraphLocation == line.paragraphLocation }
        let number = (siblings.firstIndex { $0.index == located.index } ?? 0) + 1
        return LineFacts(number: number, count: siblings.count, page: located.page + 1, naturalWidth: Double(line.naturalWidth),
                         width: Double(line.width), availableWidth: Double(line.availableWidth), endsWithHyphen: line.endsWithHyphen,
                         wordCount: line.range.length > 0 ? BodyText(text, paragraph: line.range).wordCount : 0, isNote: line.isNote)
    }

    public func pageFacts(at index: Int, affinity: NSSelectionAffinity) -> PageFacts? {
        guard let located = locatedLine(for: index, affinity: affinity) else { return nil }
        let page = pages[located.page]
        // Le righe del corpo stanno nella colonna; le note a margine fuori, e non contano.
        let setup = page.setup
        let column = setup.textRect(forPage: located.page)
        let columnLeft = column.minX - 1, columnRight = column.maxX + 1
        let body = page.lines.filter { !$0.isNote }
        let footNotes = page.lines.filter { $0.isNote && $0.origin.x >= columnLeft && $0.origin.x <= columnRight }
        let bodyBottom = body.map { $0.origin.y - $0.descent }.min() ?? (setup.paperSize.height - setup.top)
        var floor = setup.bottom
        for line in footNotes where line.origin.y < bodyBottom { floor = max(floor, line.origin.y + line.ascent) }
        for image in page.images where image.rect.maxY <= bodyBottom { floor = max(floor, image.rect.maxY) }
        return PageFacts(number: located.page + 1, lineCount: body.count, freeSpace: Double(max(bodyBottom - floor, 0)),
                         hasNotes: page.lines.contains(where: \.isNote), hasFigures: !page.images.isEmpty)
    }

    /// Le regole che toccano il carattere nella posizione, descritte.
    public func rules(touching index: Int, sheet: StyleSheet, affinity: NSSelectionAffinity = .downstream) -> [String] {
        touchingRules(at: index, sheet: sheet, affinity: affinity).map { $0.summary(selections: sheet.selections) }
    }

    /// Le regole che toccano il carattere nella posizione, nell'ordine in cui si applicano.
    public func touchingRules(at index: Int, sheet: StyleSheet, affinity: NSSelectionAffinity = .downstream) -> [TextRule] {
        let (location, range) = paragraphLocation(at: index)
        guard range.length > 0 else { return [] }
        let chosen = applicableRules(at: location, sheet: sheet)
        guard !chosen.isEmpty else { return [] }
        let body = BodyText(text, paragraph: range)
        let line = lineFacts(at: index, affinity: affinity)
        return chosen.filter { rule in
            switch rule.target {
            case .firstLines(let count): (line?.number ?? .max) <= count
            case .lastLine: line.map { $0.number == $0.count } ?? false
            case .paragraph: true
            default: body.ranges(of: rule.target, selections: sheet.selections).contains { NSLocationInRange(index, $0) }
            }
        }
    }

    /// I tratti del corpo a cui le regole danno l'aspetto, in tutto il documento: ciò che trovano, le righe per le regole
    /// di riga, il corpo intero per quelle di paragrafo. Per i segni della provenienza.
    public func ruleRanges(sheet: StyleSheet) -> [NSRange] {
        guard !sheet.compilingStyleRules().rules.isEmpty, text.length > 0 else { return [] }
        var linesByParagraph: [Int: [PlacedLine]] = [:]
        for page in pages {
            for line in page.lines where !line.isNote { linesByParagraph[line.paragraphLocation, default: []].append(line) }
        }
        var result: [NSRange] = []
        var location = 0
        while location < text.length {
            let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
            location = max(NSMaxRange(paragraph), location + 1)
            let chosen = applicableRules(at: paragraph.location, sheet: sheet)
            guard !chosen.isEmpty else { continue }
            let body = BodyText(text, paragraph: paragraph)
            let lines = linesByParagraph[paragraph.location] ?? []
            for rule in chosen {
                switch rule.target {
                case .paragraph: result += body.documentRanges(for: NSRange(location: 0, length: body.string.length))
                case .firstLines(let count): result += lines.prefix(count).map(\.range)
                case .lastLine: result += lines.last.map { [$0.range] } ?? []
                default: result += body.ranges(of: rule.target, selections: sheet.selections)
                }
            }
        }
        return TextStyling.merged(result)
    }

    /// Conta paragrafi e parole di tutto il documento: da chiedere solo quando serve, costa.
    public func documentFacts() -> DocumentFacts {
        var paragraphs = 0, words = 0
        var location = 0
        while location < text.length {
            let range = TextStyling.bodyParagraph(in: text, at: location).range
            paragraphs += 1
            words += BodyText(text, paragraph: range).wordCount
            location = max(NSMaxRange(range), location + 1)
        }
        return DocumentFacts(pageCount: pages.count, paragraphCount: paragraphs, wordCount: words, noteCount: notes.count)
    }
}

// MARK: - Conteggi

/// Quanto testo c'è in un tratto: parole, caratteri (con e senza gli spazi) e paragrafi toccati. Conta il corpo, non
/// il testo delle note; i caratteri sono quelli che si vedono (una lettera con il suo accento è uno), senza gli a capo.
public struct TextCounts: Equatable, Sendable {
    public var words = 0
    public var characters = 0
    public var charactersWithoutSpaces = 0
    public var paragraphs = 0

    public init(words: Int = 0, characters: Int = 0, charactersWithoutSpaces: Int = 0, paragraphs: Int = 0) {
        self.words = words
        self.characters = characters
        self.charactersWithoutSpaces = charactersWithoutSpaces
        self.paragraphs = paragraphs
    }

    public init(in text: NSAttributedString, range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard text.length > 0 else { return }
        var location = range.location
        let end = max(NSMaxRange(range), range.location + 1)
        while location < min(end, text.length) {
            let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
            let piece = NSIntersectionRange(paragraph, range.length == 0 ? paragraph : range)
            paragraphs += 1
            let body = BodyText(text, paragraph: piece)
            words += body.wordCount
            let visible = (body.string as String).replacingOccurrences(of: "\u{2028}", with: " ")
                .filter { $0 != Character(Unicode.Scalar(FloatingObject.anchorCharacter)!) }
            characters += visible.count
            charactersWithoutSpaces += visible.filter { !$0.isWhitespace }.count
            location = max(NSMaxRange(paragraph), location + 1)
        }
    }
}
