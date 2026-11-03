import AppKit
import CoreText

/// Corrispondenza tra posizioni nel testo e punti sulla pagina: è ciò che serve per cursore, clic e selezione.
///
/// Le coordinate sono quelle della pagina, in punti, con l'origine in basso a sinistra.
///
/// Il documento ha due specie di testo: il corpo e le note a piè di pagina. Nel testo una nota occupa i caratteri
/// subito dopo il suo richiamo, ma sulla pagina è composta in fondo. Una posizione appartiene alla nota se cade
/// dentro il suo testo; al confine (la fine della nota, che è anche il punto del corpo subito dopo il richiamo)
/// decide l'affinità: `.upstream` è la fine della nota, `.downstream` è il corpo.
extension DocumentLayout {
    /// Dove si disegna il cursore: una linea verticale alta quanto la riga.
    public struct Caret: Equatable {
        public var page: Int
        public var rect: CGRect
    }

    struct Located {
        var page: Int
        var index: Int  // posizione della riga nella sequenza di tutte le righe del documento, nell'ordine in cui si vedono
        var line: PlacedLine
    }

    var allLines: [Located] {
        var result: [Located] = []
        for (page, content) in pages.enumerated() {
            for line in content.lines { result.append(Located(page: page, index: result.count, line: line)) }
        }
        return result
    }

    // MARK: Corpo e note

    /// La nota al cui testo appartiene una posizione: i caratteri del testo della nota, senza il richiamo.
    /// `nil` se la posizione è nel corpo.
    public func noteTextRange(containing index: Int, affinity: NSSelectionAffinity) -> NSRange? {
        for note in notes {
            let textStart = note.location + 1, end = NSMaxRange(note)
            if index >= textStart && index < end { return NSRange(location: textStart, length: end - textStart) }
            if index == end && affinity == .upstream { return NSRange(location: textStart, length: end - textStart) }
        }
        return nil
    }

    /// La nota (richiamo compreso) che una posizione del corpo scavalcherebbe muovendosi di un passo.
    func note(startingAt index: Int) -> NSRange? { notes.first { $0.location == index } }
    func note(endingAt index: Int) -> NSRange? { notes.first { NSMaxRange($0) == index } }
    /// La nota (richiamo compreso) dentro cui cade strettamente una posizione.
    func note(strictlyContaining index: Int) -> NSRange? { notes.first { index > $0.location && index < NSMaxRange($0) } }

    // MARK: Cursore

    /// Il cursore per una posizione nel testo (un indice UTF-16 da 0 alla lunghezza del testo).
    ///
    /// Dove una riga va a capo senza un a capo scritto, la stessa posizione sta sia alla fine di una riga sia
    /// all'inizio della successiva: `affinity` dice quale delle due mostrare (`.upstream` è la fine della prima).
    public func caret(at index: Int, affinity: NSSelectionAffinity = .downstream) -> Caret? {
        guard let located = locatedLine(for: index, affinity: affinity) else { return nil }
        let line = located.line
        let index = min(max(index, 0), text.length)
        // Dentro una legatura Core Text usa le posizioni della tabella `lcar` del font, se c'è.
        let offset = line.composedRange.length == 0 && !line.isNote ? 0 : line.offset(forString: line.stringIndex(forDocument: index))
        return Caret(page: located.page, rect: CGRect(x: line.origin.x + offset, y: line.origin.y - line.descent, width: 0, height: line.ascent + line.descent))
    }

    /// La riga su cui si mostra una posizione del testo.
    func locatedLine(for index: Int, affinity: NSSelectionAffinity) -> Located? {
        let index = min(max(index, 0), text.length)
        // Si cerca solo tra le righe della stessa specie: quelle della nota, o quelle del corpo.
        let note = noteTextRange(containing: index, affinity: affinity)
        // Nell'ordine del testo: una tabella flottante rimandata a una pagina dopo ha le sue righe dopo il testo che la
        // segue. A pari posizione (le righe d'intestazione ripetute) vale la prima copia.
        let lines = allLines.filter { $0.line.noteRange == note }.sorted {
            $0.line.range.location != $1.line.range.location ? $0.line.range.location < $1.line.range.location : $0.index > $1.index
        }
        guard !lines.isEmpty else { return allLines.first }
        var position = lines.lastIndex { $0.line.range.location <= index } ?? 0
        if affinity == .upstream, lines[position].line.range.location == index, position > 0 {
            let previous = lines[position - 1]
            // Solo se la riga precedente continua nello stesso paragrafo: dopo un a capo scritto il cursore non risale.
            if previous.line.paragraphLocation == lines[position].line.paragraphLocation, !endsWithLineBreak(previous.line) { position -= 1 }
        }
        return lines[position]
    }

    // MARK: Clic

    /// La posizione nel testo più vicina a un punto della pagina.
    public func position(at point: CGPoint, onPage page: Int) -> (index: Int, affinity: NSSelectionAffinity)? {
        guard pages.indices.contains(page) else { return nil }
        var lines = pages[page].lines
        // Dentro la cella di una tabella contano solo le sue righe.
        if let cell = lines.first(where: { $0.cell?.contains(point) == true })?.cell { lines = lines.filter { $0.cell == cell } }
        // La riga la cui fascia verticale contiene il punto, o altrimenti la più vicina; a pari distanza (le celle di
        // una stessa riga di tabella) la più vicina in orizzontale.
        guard let line = lines.min(by: {
            (distance(from: point.y, to: $0), horizontalDistance(from: point.x, to: $0)) < (distance(from: point.y, to: $1), horizontalDistance(from: point.x, to: $1))
        }) else { return nil }
        return position(atX: point.x, in: line)
    }

    private func horizontalDistance(from x: CGFloat, to line: PlacedLine) -> CGFloat {
        let left = line.cell?.minX ?? line.origin.x, right = line.cell?.maxX ?? line.origin.x + line.width
        return x > right ? x - right : (x < left ? left - x : 0)
    }

    /// La posizione più vicina a un'ascissa data, dentro una riga.
    private func position(atX x: CGFloat, in line: PlacedLine) -> (index: Int, affinity: NSSelectionAffinity) {
        let end = NSMaxRange(line.range)
        if let note = line.noteRange {
            // Riga di una nota: la posizione resta dentro il testo della nota, e alla sua fine appartiene alla nota.
            let found = line.stringIndex(forOffset: x - line.origin.x)
            var index = found == kCFNotFound ? line.range.location : line.documentIndex(forString: found)
            index = min(max(index, note.location), NSMaxRange(note))
            let contentEnd = end - trailingLineBreakLength(line)
            if contentEnd < end { index = min(index, contentEnd) }
            return (index, index >= end || index == NSMaxRange(note) ? .upstream : .downstream)
        }
        guard line.composedRange.length > 0 else { return (line.range.location, .downstream) }
        let found = line.stringIndex(forOffset: x - line.origin.x)
        guard found != kCFNotFound else { return (line.range.location, .downstream) }
        let index = line.documentIndex(forString: found)
        let contentEnd = end - trailingLineBreakLength(line)
        if contentEnd < end {
            // La riga finisce con un a capo scritto: oltre la fine, il cursore va prima dell'a capo.
            return (min(index, contentEnd), .downstream)
        }
        // La riga continua sulla successiva: la sua fine è anche l'inizio dell'altra, e qui si vuole la fine di questa.
        return index >= end ? (end, .upstream) : (index, .downstream)
    }

    // MARK: Movimenti che dipendono dalle righe

    /// Inizio della riga su cui si trova una posizione.
    public func lineStart(for index: Int, affinity: NSSelectionAffinity) -> Int {
        locatedLine(for: index, affinity: affinity)?.line.range.location ?? 0
    }

    /// Fine della riga su cui si trova una posizione: prima dell'a capo scritto, se c'è.
    public func lineEnd(for index: Int, affinity: NSSelectionAffinity) -> (index: Int, affinity: NSSelectionAffinity) {
        guard let line = locatedLine(for: index, affinity: affinity)?.line else { return (text.length, .downstream) }
        let breakLength = trailingLineBreakLength(line)
        if line.isNote { return (NSMaxRange(line.range) - breakLength, breakLength > 0 ? .downstream : .upstream) }
        return (NSMaxRange(line.range) - breakLength, breakLength > 0 || line.range.length == 0 ? .downstream : .upstream)
    }

    /// La posizione una riga sopra (`lines` negativo) o sotto, mantenendo l'ascissa `goalX` se data.
    /// Oltre la prima o l'ultima riga si arriva all'inizio o alla fine del documento.
    public func position(movingVerticallyFrom index: Int, affinity: NSSelectionAffinity, lines offset: Int, goalX: CGFloat?)
        -> (index: Int, affinity: NSSelectionAffinity, goalX: CGFloat) {
        let lines = allLines
        guard let current = locatedLine(for: index, affinity: affinity), let caret = caret(at: index, affinity: affinity) else { return (0, .downstream, goalX ?? 0) }
        let x = goalX ?? caret.rect.minX
        let target = current.index + offset
        if target < 0 { return (0, .downstream, x) }
        if target >= lines.count { return (text.length, .downstream, x) }
        let found = position(atX: x, in: lines[target].line)
        return (found.index, found.affinity, x)
    }

    // MARK: Selezione

    /// I rettangoli che coprono un intervallo di testo, uno per riga: servono a evidenziare la selezione.
    public func selectionRects(for range: NSRange) -> [(page: Int, rect: CGRect)] {
        guard range.length > 0 else { return [] }
        var result: [(page: Int, rect: CGRect)] = []
        for located in allLines {
            let line = located.line
            let lineStart = line.composedRange.location, lineEnd = NSMaxRange(line.composedRange)
            func x(_ composed: Int) -> CGFloat {
                line.offset(forString: min(max(composed, lineStart), lineEnd) - line.composedOffset)
            }
            func add(from start: CGFloat, to end: CGFloat) {
                result.append((located.page, CGRect(x: line.origin.x + min(start, end), y: line.origin.y - line.descent,
                                                    width: abs(end - start), height: line.ascent + line.descent)))
            }
            for (position, segment) in line.map.segments.enumerated() {
                // La parte di questo tratto che sta nella riga e nella selezione.
                let composedStart = max(segment.composed, lineStart), composedEnd = min(segment.composed + segment.length, lineEnd)
                if composedEnd > composedStart {
                    let documentStart = segment.document + (composedStart - segment.composed)
                    let overlap = NSIntersectionRange(range, NSRange(location: documentStart, length: composedEnd - composedStart))
                    if overlap.length > 0 {
                        let start = x(segment.composed + (overlap.location - segment.document))
                        var end = x(segment.composed + (NSMaxRange(overlap) - segment.document))
                        // Se la selezione prosegue oltre l'a capo, l'evidenziazione include un po' di spazio a fine riga.
                        if NSMaxRange(overlap) == NSMaxRange(line.range), trailingLineBreakLength(line) > 0 { end += line.ascent * 0.3 }
                        add(from: start, to: end)
                    }
                }
                // Un richiamo di nota che sta in questa riga, tra questo tratto e il successivo: si evidenzia se la
                // selezione comprende tutta la nota.
                if position + 1 < line.map.segments.count {
                    let next = line.map.segments[position + 1]
                    let markerStart = segment.composed + segment.length, markerEnd = next.composed
                    let removed = NSRange(location: segment.document + segment.length, length: next.document - segment.document - segment.length)
                    if markerEnd > markerStart, markerStart >= lineStart, markerEnd <= lineEnd, removed.length > 0,
                       NSIntersectionRange(range, removed).length == removed.length {
                        add(from: x(markerStart), to: x(markerEnd))
                    }
                }
            }
        }
        return result
    }

    private func distance(from y: CGFloat, to line: PlacedLine) -> CGFloat {
        let bottom = line.origin.y - line.descent, top = line.origin.y + line.ascent
        return y > top ? y - top : (y < bottom ? bottom - y : 0)
    }

    private func endsWithLineBreak(_ line: PlacedLine) -> Bool { trailingLineBreakLength(line) > 0 }

    /// Numero di caratteri finali della riga che sono un a capo scritto (di paragrafo o interno al paragrafo).
    private func trailingLineBreakLength(_ line: PlacedLine) -> Int {
        guard line.range.length > 0 else { return 0 }
        let string = text.string as NSString
        let last = string.character(at: NSMaxRange(line.range) - 1)
        guard [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(Int(last)) else { return 0 }
        // «\r\n» conta come un solo a capo di due caratteri.
        if last == 0x0A, line.range.length > 1, string.character(at: NSMaxRange(line.range) - 2) == 0x0D { return 2 }
        return 1
    }
}

// MARK: - Caratteri nascosti

/// Un carattere che non si vede (spazio, tabulazione, a capo, fine paragrafo) o un richiamo di nota, con il posto che
/// occupa sulla pagina: la vista delle pagine ci disegna un segno, solo a schermo.
public struct InvisibleMark: Equatable, Sendable {
    public enum Kind: Sendable {
        case space, nonBreakingSpace, tab, lineBreak, paragraphEnd, noteReference
    }

    public var kind: Kind
    /// Dal bordo sinistro al bordo destro del carattere (o del numero di richiamo), alto quanto la riga; origine della
    /// pagina in basso a sinistra.
    public var rect: CGRect
    /// La linea di base della riga.
    public var baseline: CGFloat
}

extension DocumentLayout {
    /// I caratteri nascosti e i richiami di nota di una pagina, nell'ordine delle righe.
    public func invisibleMarks(onPage pageIndex: Int) -> [InvisibleMark] {
        guard pages.indices.contains(pageIndex) else { return [] }
        let string = text.string as NSString
        var marks: [InvisibleMark] = []
        for line in pages[pageIndex].lines where line.composedRange.length > 0 {
            let lineStart = marks.count
            defer { marks[lineStart...].sort { $0.rect.minX < $1.rect.minX } }
            func x(_ composed: Int) -> CGFloat { line.origin.x + line.offset(forString: composed - line.composedOffset) }
            func mark(_ kind: InvisibleMark.Kind, from start: Int, to end: Int) {
                let left = x(start), right = x(end)
                marks.append(InvisibleMark(kind: kind, rect: CGRect(x: left, y: line.origin.y - line.descent, width: max(right - left, 0),
                                                                    height: line.ascent + line.descent), baseline: line.origin.y))
            }
            let composedEnd = NSMaxRange(line.composedRange)
            for index in line.range.location..<min(NSMaxRange(line.range), string.length) {
                // Nelle righe del corpo il testo delle note non c'è (è composto in fondo alla pagina); in quelle di nota,
                // solo il testo della nota.
                if let noteRange = line.noteRange {
                    guard NSLocationInRange(index, noteRange) else { continue }
                } else if text.attribute(.footnote, at: index, effectiveRange: nil) != nil {
                    continue
                }
                let kind: InvisibleMark.Kind? = switch string.character(at: index) {
                case 0x20: .space
                case 0xA0, 0x202F: .nonBreakingSpace
                case 0x09: .tab
                case 0x2028: .lineBreak
                case 0x0A, 0x0D, 0x85, 0x2029: .paragraphEnd
                default: nil
                }
                guard let kind, let composed = line.map.composedIndex(forDocument: index),
                      composed >= line.composedRange.location, composed < composedEnd else { continue }
                mark(kind, from: composed, to: composed + 1)
            }
            // I richiami: nel testo composto di una riga del corpo, il materiale aggiunto tra due tratti del documento.
            guard line.noteRange == nil else { continue }
            for (previous, next) in zip(line.map.segments, line.map.segments.dropFirst()) {
                let start = previous.composed + previous.length
                guard next.composed > start, start >= line.composedRange.location, next.composed <= composedEnd else { continue }
                mark(.noteReference, from: start, to: next.composed)
            }
        }
        return marks
    }
}

// MARK: - Note a margine da sistemare

extension DocumentLayout {
    /// I riquadri delle note a margine segnalate (`marginConflicts`) in una pagina: uno per nota, intorno alle sue righe.
    public func marginConflictRects(onPage pageIndex: Int) -> [CGRect] {
        guard pages.indices.contains(pageIndex), !marginConflicts.isEmpty else { return [] }
        var boxes: [NSRange: CGRect] = [:]
        for line in pages[pageIndex].lines {
            guard let range = line.noteRange, marginConflicts.contains(range) else { continue }
            let width = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil))
            let box = CGRect(x: line.origin.x, y: line.origin.y - line.descent, width: max(width, 1), height: line.ascent + line.descent)
            boxes[range] = boxes[range].map { $0.union(box) } ?? box
        }
        return Array(boxes.values)
    }
}

extension PlacedLine {
    /// L'ascissa, dall'inizio della riga, di un indice della riga di Core Text; dentro un gruppo Graphite, quella dei
    /// suoi grafemi.
    func offset(forString index: Int) -> CGFloat {
        GraphiteLayout.offset(in: line, stringIndex: index) ?? CTLineGetOffsetForStringIndex(line, index, nil)
    }

    /// L'indice della riga di Core Text più vicino a un'ascissa (dall'inizio della riga); su un gruppo Graphite, mai in
    /// mezzo a un grafemo.
    func stringIndex(forOffset x: CGFloat) -> Int {
        GraphiteLayout.stringIndex(in: line, offset: x) ?? CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
    }
}
