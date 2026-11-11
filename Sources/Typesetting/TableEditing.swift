import AppKit

/// Le operazioni sulle tabelle nel testo piatto dell'editor, dove ogni paragrafo di una cella porta il segno della sua
/// cella (`.tableCell`, e `.finalParagraphCell` sull'ultimo a capo per il paragrafo vuoto in fondo al testo).
public enum TableEditing {
    /// Un paragrafo di una cella: il suo segno e i suoi caratteri (a capo compreso; vuoto per il paragrafo finale).
    public struct CellParagraph: Equatable {
        public var mark: CellMark
        public var range: NSRange
    }

    /// Il segno della cella in cui sta una posizione del testo, se sta in una tabella.
    public static func cell(at index: Int, in text: NSAttributedString) -> CellMark? {
        let string = text.string as NSString
        guard string.length > 0 else { return nil }
        let index = min(max(index, 0), string.length)
        if index == string.length, string.paragraphRange(for: NSRange(location: index, length: 0)).length == 0 {
            return (text.attribute(.finalParagraphCell, at: string.length - 1, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:))
        }
        let paragraph = TextStyling.bodyParagraph(in: text, at: index).range
        guard paragraph.location < string.length else { return nil }
        return (text.attribute(.tableCell, at: paragraph.location, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:))
    }

    /// I paragrafi della tabella a cui appartiene la posizione data, nell'ordine del testo.
    public static func paragraphs(ofTableAt index: Int, in text: NSAttributedString) -> [CellParagraph] {
        guard let mark = cell(at: index, in: text) else { return [] }
        let table = mark.table
        let string = text.string as NSString
        func markAt(_ location: Int) -> CellMark? {
            (text.attribute(.tableCell, at: location, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:))
        }
        // Indietro fino al primo paragrafo della tabella.
        var start = TextStyling.bodyParagraph(in: text, at: min(index, string.length - 1)).range.location
        while start > 0 {
            let previous = TextStyling.bodyParagraph(in: text, at: start - 1).range
            guard markAt(previous.location)?.table == table else { break }
            start = previous.location
        }
        var result: [CellParagraph] = []
        var location = start
        while location < string.length {
            let range = TextStyling.bodyParagraph(in: text, at: location).range
            guard let found = markAt(range.location), found.table == table else { break }
            result.append(CellParagraph(mark: found, range: range))
            location = max(NSMaxRange(range), location + 1)
        }
        if location >= string.length, string.paragraphRange(for: NSRange(location: string.length, length: 0)).length == 0,
           let final = (text.attribute(.finalParagraphCell, at: string.length - 1, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)),
           final.table == mark.table {
            result.append(CellParagraph(mark: final, range: NSRange(location: string.length, length: 0)))
        }
        return result
    }

    /// Inserisci › Tabella: una tabella vuota di `rows` righe e `columns` colonne subito dopo il paragrafo della
    /// posizione data (il paragrafo resta intero). Restituisce l'inizio della prima cella, o `nil` se la posizione sta
    /// già in una tabella (le tabelle non si annidano).
    @discardableResult
    public static func insertTable(in text: NSMutableAttributedString, after index: Int, rows: Int = 3, columns: Int = 3,
                                   headerRows: Int = 1, sheet: StyleSheet) -> Int? {
        guard rows > 0, columns > 0, cell(at: index, in: text) == nil else { return nil }
        let string = text.string as NSString
        let length = string.length
        let paragraph = TextStyling.bodyParagraph(in: text, at: min(max(index, 0), length)).range
        var insertAt = NSMaxRange(paragraph)
        let finalKeys: [NSAttributedString.Key] = [.finalParagraphList, .finalParagraphSection, .finalParagraphCell, .finalParagraphOutlineLevel]
        // Gli a capo delle celle nascono con gli attributi del paragrafo, senza ciò che è solo suo.
        var attributes: [NSAttributedString.Key: Any] = length == 0
            ? TextStyling.characterAttributes(for: TextStyling.styleBase).attributes
            : text.attributes(at: min(paragraph.location, length - 1), effectiveRange: nil)
        let isTitle = attributes[.sectionTitle] != nil
        for key in [NSAttributedString.Key.footnote, .floatImage, .inlineImage, .field, .sectionTitle, .listItem, .tableCell] + finalKeys { attributes[key] = nil }
        // Le cose del paragrafo vuoto in fondo al testo (stanno sull'ultimo a capo) passano al nuovo ultimo a capo.
        var finalAttributes: [NSAttributedString.Key: Any] = [:]
        if insertAt >= length, length > 0 {
            for key in finalKeys { if let value = text.attribute(key, at: length - 1, effectiveRange: nil) { finalAttributes[key] = value } }
            for key in finalKeys { text.removeAttribute(key, range: NSRange(location: length - 1, length: 1)) }
        }
        // Un paragrafo con testo in fondo, senza a capo: prima lo si chiude, con i suoi attributi.
        if paragraph.length > 0, !TextStyling.isLineTerminator(string.character(at: NSMaxRange(paragraph) - 1)) {
            let closing = text.attributes(at: NSMaxRange(paragraph) - 1, effectiveRange: nil)
            text.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: NSAttributedString(string: "\n", attributes: closing))
            insertAt += 1
        }
        let id = Table.newID()
        let cells = NSMutableAttributedString()
        for row in 0..<rows {
            for column in 0..<columns {
                var cellAttributes = attributes
                cellAttributes[.tableCell] = CellMark(table: id, row: row, column: column, headerRows: min(headerRows, rows)).encoded
                cells.append(NSAttributedString(string: "\n", attributes: cellAttributes))
            }
        }
        text.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: cells)
        // Dentro le celle il testo del documento, anche se il paragrafo era un titolo.
        if isTitle {
            let name = sheet.style(named: StyleSheet.defaultParagraphStyle)?.target == .paragraph ? StyleSheet.defaultParagraphStyle : nil
            TextStyling.restyle(text, range: NSRange(location: insertAt, length: cells.length), from: sheet, to: sheet) { $0.paragraph = name }
        }
        for (key, value) in finalAttributes { text.addAttribute(key, value: value, range: NSRange(location: text.length - 1, length: 1)) }
        return insertAt
    }

    // MARK: Scrivere e cancellare senza rompere le tabelle

    /// Due posizioni stanno nella stessa cella (o entrambe fuori dalle tabelle).
    private static func sameCell(_ first: CellMark?, _ second: CellMark?) -> Bool {
        first?.table == second?.table && first?.row == second?.row && first?.column == second?.column
    }

    /// I pezzi di un intervallo che si possono cancellare: tutto, tranne gli a capo che chiudono una cella o che
    /// separano una tabella dal testo intorno (cancellarli unirebbe due celle, o una cella al paragrafo accanto). Una
    /// tabella presa per intero dall'intervallo si cancella tutta. In ordine, dal primo all'ultimo.
    public static func deletablePieces(of range: NSRange, in text: NSAttributedString) -> [NSRange] {
        let string = text.string as NSString
        let range = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard range.length > 0 else { return [] }
        // Le tabelle prese per intero: dal primo carattere della prima cella all'a capo dell'ultima.
        var whole: Set<String> = []
        func isWhole(_ table: String, at index: Int) -> Bool {
            if whole.contains(table) { return true }
            let paragraphs = paragraphs(ofTableAt: index, in: text)
            guard let first = paragraphs.first, let last = paragraphs.last else { return false }
            let end = NSMaxRange(last.range)
            if first.range.location >= range.location && end <= NSMaxRange(range) && (last.range.length > 0 || end == string.length) {
                whole.insert(table)
                return true
            }
            return false
        }
        var pieces: [NSRange] = []
        var start = range.location
        for index in range.location..<NSMaxRange(range) {
            let character = string.character(at: index)
            guard TextStyling.isLineTerminator(character), character != 0x2028 else { continue }
            let before = cell(at: index, in: text), after = cell(at: index + 1, in: text)
            guard !sameCell(before, after) else { continue }
            let free = [before.map { ($0.table, index) }, after.map { ($0.table, index + 1) }].compactMap { $0 }.allSatisfy { isWhole($0.0, at: $0.1) }
            guard !free else { continue }
            if index > start { pieces.append(NSRange(location: start, length: index - start)) }
            start = index + 1
        }
        if NSMaxRange(range) > start { pieces.append(NSRange(location: start, length: NSMaxRange(range) - start)) }
        return pieces
    }

    /// Cancella un intervallo rispettando le tabelle. Vero se ha cancellato qualcosa.
    @discardableResult
    public static func delete(_ range: NSRange, in text: NSMutableAttributedString) -> Bool {
        let pieces = deletablePieces(of: range, in: text)
        for piece in pieces.reversed() { text.deleteCharacters(in: piece) }
        return !pieces.isEmpty
    }

    public static func identities(in text: NSAttributedString) -> Set<String> {
        let whole = NSRange(location: 0, length: text.length)
        var ids: Set<String> = []
        for key in [NSAttributedString.Key.tableCell, .finalParagraphCell] {
            text.enumerateAttribute(key, in: whole) { value, _, _ in
                if let mark = (value as? String).flatMap(CellMark.init(encoded:)) { ids.insert(mark.table) }
            }
        }
        return ids
    }

    /// Prepara un pezzo di testo che entra in `location`: in una cella prende il segno di quella cella (una tabella
    /// che contenesse diventa testo della cella); fuori, le sue tabelle prendono identità nuove (una tabella incollata
    /// due volte fa due tabelle).
    public static func prepared(_ fragment: NSAttributedString, at location: Int, in text: NSAttributedString, keepingIdentities: Set<String> = []) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: fragment)
        let all = NSRange(location: 0, length: result.length)
        guard all.length > 0 else { return result }
        if let mark = cell(at: location, in: text) {
            result.addAttribute(.tableCell, value: mark.encoded, range: all)
            result.addAttribute(.finalParagraphCell, value: mark.encoded, range: all)
            result.removeAttribute(.sectionTitle, range: all)
            result.removeAttribute(.finalParagraphSection, range: all)
        } else {
            var renamed: [String: String] = [:]
            for key in [NSAttributedString.Key.tableCell, .finalParagraphCell] {
                var changes: [(NSRange, String)] = []
                result.enumerateAttribute(key, in: all) { value, range, _ in
                    guard let encoded = value as? String, var mark = CellMark(encoded: encoded),
                          !keepingIdentities.contains(mark.table) else { return }
                    mark.table = renamed[mark.table] ?? { let fresh = Table.newID(); renamed[mark.table] = fresh; return fresh }()
                    changes.append((range, mark.encoded))
                }
                for (range, encoded) in changes { result.addAttribute(key, value: encoded, range: range) }
            }
        }
        return result
    }

    /// Sostituisce un intervallo con un pezzo di testo rispettando le tabelle: cancella ciò che si può (le celle
    /// toccate si svuotano, la loro struttura resta) e mette il pezzo all'inizio. Restituisce dove il pezzo comincia.
    @discardableResult
    public static func replace(_ range: NSRange, in text: NSMutableAttributedString, with fragment: NSAttributedString, keepingTableIdentities: Set<String> = []) -> Int {
        delete(range, in: text)
        let location = min(range.location, text.length)
        text.replaceCharacters(in: NSRange(location: location, length: 0), with: prepared(fragment, at: location, in: text, keepingIdentities: keepingTableIdentities))
        return location
    }

    // MARK: Celle

    /// Il testo di una cella: dall'inizio del suo primo paragrafo a prima dell'a capo dell'ultimo.
    public static func contentRange(of mark: CellMark, in text: NSAttributedString, near index: Int) -> NSRange? {
        let paragraphs = paragraphs(ofTableAt: index, in: text).filter { $0.mark.row == mark.row && $0.mark.column == mark.column }
        guard let first = paragraphs.first, let last = paragraphs.last else { return nil }
        let string = text.string as NSString
        var end = NSMaxRange(last.range)
        if last.range.length > 0, TextStyling.isLineTerminator(string.character(at: end - 1)) { end -= 1 }
        return NSRange(location: first.range.location, length: end - first.range.location)
    }

    /// La cella dopo (o prima) di quella in cui sta la posizione, nell'ordine di lettura; `nil` oltre l'ultima o la prima.
    public static func neighbourCell(of index: Int, forward: Bool, in text: NSAttributedString) -> CellMark? {
        guard let mark = cell(at: index, in: text) else { return nil }
        var seen: [CellMark] = []
        for paragraph in paragraphs(ofTableAt: index, in: text) where !seen.contains(where: { sameCell($0, paragraph.mark) }) { seen.append(paragraph.mark) }
        seen.sort { ($0.row, $0.column) < ($1.row, $1.column) }
        guard let position = seen.firstIndex(where: { sameCell($0, mark) }) else { return nil }
        let next = position + (forward ? 1 : -1)
        return seen.indices.contains(next) ? seen[next] : nil
    }

    /// Cambia i segni di tutte le celle della tabella (anche quello del paragrafo finale vuoto, se è una sua cella).
    private static func remark(tableAt index: Int, in text: NSMutableAttributedString, _ change: (CellMark) -> CellMark) {
        let paragraphs = paragraphs(ofTableAt: index, in: text)
        for paragraph in paragraphs {
            let new = change(paragraph.mark).encoded
            if paragraph.range.length > 0 {
                text.addAttribute(.tableCell, value: new, range: paragraph.range)
            } else if text.length > 0 {
                text.addAttribute(.finalParagraphCell, value: new, range: NSRange(location: text.length - 1, length: 1))
            }
        }
    }

    // MARK: Righe e colonne

    /// Righe, colonne e righe d'intestazione della tabella in cui sta la posizione.
    public static func shape(ofTableAt index: Int, in text: NSAttributedString) -> (rows: Int, columns: Int, headerRows: Int)? {
        let paragraphs = paragraphs(ofTableAt: index, in: text)
        guard let first = paragraphs.first?.mark else { return nil }
        let cells = paragraphs.filter { !$0.mark.isCaption }.map(\.mark)
        return (cells.map { $0.row + $0.rowSpan }.max() ?? 0, cells.map { $0.column + $0.columnSpan }.max() ?? 0, first.headerRows)
    }

    /// Il segno di ogni cella della tabella (quello del suo primo paragrafo), didascalia esclusa, nell'ordine del testo.
    public static func cells(ofTableAt index: Int, in text: NSAttributedString) -> [CellMark] {
        var seen: Set<[Int]> = []
        return paragraphs(ofTableAt: index, in: text).map(\.mark).filter { !$0.isCaption && seen.insert([$0.row, $0.column]).inserted }
    }

    private static let finalKeys: [NSAttributedString.Key] = [.finalParagraphList, .finalParagraphSection, .finalParagraphCell, .finalParagraphOutlineLevel]

    /// Gli attributi di una cella nuova: quelli di un paragrafo vicino, senza ciò che è solo suo, con il segno dato.
    private static func cellAttributes(like location: Int, in text: NSAttributedString, mark: CellMark) -> [NSAttributedString.Key: Any] {
        var attributes = text.length == 0 ? TextStyling.characterAttributes(for: TextStyling.styleBase).attributes
            : text.attributes(at: min(max(location, 0), text.length - 1), effectiveRange: nil)
        for key in [NSAttributedString.Key.footnote, .floatImage, .inlineImage, .field, .sectionTitle, .listItem] + finalKeys { attributes[key] = nil }
        attributes[.tableCell] = mark.encoded
        return attributes
    }

    /// Una cella vuota (un paragrafo vuoto) con il segno dato: prima del paragrafo che comincia in `location`, oppure,
    /// con `afterFinal`, dopo il paragrafo vuoto in fondo al testo (che è una cella: riceve il suo a capo, e la cella
    /// nuova diventa il paragrafo in fondo).
    private static func insertEmptyCell(_ mark: CellMark, at location: Int, afterFinal: Bool, like model: Int, in text: NSMutableAttributedString) {
        var attributes = cellAttributes(like: model, in: text, mark: mark)
        let end = text.length
        // Ciò che sta sull'ultimo a capo per il paragrafo in fondo passa al nuovo ultimo a capo.
        var final: [NSAttributedString.Key: Any] = [:]
        if (afterFinal || location >= end), end > 0 {
            for key in finalKeys { if let value = text.attribute(key, at: end - 1, effectiveRange: nil) { final[key] = value } }
            for key in finalKeys { text.removeAttribute(key, range: NSRange(location: end - 1, length: 1)) }
        }
        if afterFinal {
            // L'a capo è della cella che era in fondo; la cella nuova è il nuovo paragrafo in fondo.
            if let old = final[.finalParagraphCell] { attributes[.tableCell] = old }
            final[.finalParagraphCell] = mark.encoded
            text.replaceCharacters(in: NSRange(location: end, length: 0), with: NSAttributedString(string: "\n", attributes: attributes))
        } else {
            text.replaceCharacters(in: NSRange(location: min(location, end), length: 0), with: NSAttributedString(string: "\n", attributes: attributes))
        }
        for (key, value) in final { text.addAttribute(key, value: value, range: NSRange(location: text.length - 1, length: 1)) }
    }

    /// Una riga vuota al posto `row` della tabella in cui sta la posizione (da 0 al numero delle righe): le righe da lì
    /// in poi scalano di uno. Una riga nuova dentro le righe d'intestazione è anche lei d'intestazione. Restituisce
    /// l'inizio della prima cella della riga nuova.
    @discardableResult
    public static func insertRow(at row: Int, ofTableAt index: Int, in text: NSMutableAttributedString) -> Int? {
        let paragraphs = paragraphs(ofTableAt: index, in: text)
        guard let shape = shape(ofTableAt: index, in: text), let any = paragraphs.first?.mark, row >= 0, row <= shape.rows else { return nil }
        let headerRows = row < shape.headerRows ? shape.headerRows + 1 : shape.headerRows
        // Dove va: prima del primo paragrafo della riga che c'era lì, o dopo l'ultimo paragrafo della tabella.
        let model = paragraphs.last { $0.mark.row == min(row, shape.rows - 1) } ?? paragraphs[0]
        let before = paragraphs.first { !$0.mark.isCaption && $0.mark.row >= row }
        let last = paragraphs[paragraphs.count - 1]
        // Le celle unite che la riga nuova attraversa si allungano, e lì la riga non ha celle sue.
        let crossing = cells(ofTableAt: index, in: text).filter { $0.row < row && $0.row + $0.rowSpan > row }
        let skipped = Set(crossing.flatMap { $0.column..<($0.column + $0.columnSpan) })
        let created = (0..<shape.columns).filter { !skipped.contains($0) }
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            if mark.row >= row {
                mark.row += 1
            } else if !mark.isCaption, crossing.contains(where: { $0.row == mark.row && $0.column == mark.column }) {
                mark.rowSpan += 1
            }
            mark.headerRows = headerRows
            return mark
        }
        func mark(_ column: Int) -> CellMark { any.cell(row: row, column: column, headerRows: headerRows) }
        if let before {
            for column in created.reversed() { insertEmptyCell(mark(column), at: before.range.location, afterFinal: false, like: model.range.location, in: text) }
            return before.range.location
        }
        if last.range.length == 0 {
            for column in created { insertEmptyCell(mark(column), at: text.length, afterFinal: true, like: model.range.location, in: text) }
            return text.length - created.count + 1
        }
        let at = NSMaxRange(last.range)
        for column in created.reversed() { insertEmptyCell(mark(column), at: at, afterFinal: false, like: model.range.location, in: text) }
        return at
    }

    /// Una riga vuota sotto la riga `row` (per Tab nell'ultima cella e Tabella › Riga sotto).
    @discardableResult
    public static func insertRow(below row: Int, ofTableAt index: Int, in text: NSMutableAttributedString) -> Int? {
        insertRow(at: row + 1, ofTableAt: index, in: text)
    }

    /// Una colonna vuota al posto `column` (da 0 al numero delle colonne): le colonne da lì in poi scalano di uno.
    public static func insertColumn(at column: Int, ofTableAt index: Int, in text: NSMutableAttributedString) {
        let paragraphs = paragraphs(ofTableAt: index, in: text)
        guard let shape = shape(ofTableAt: index, in: text), let any = paragraphs.first?.mark, column >= 0, column <= shape.columns else { return }
        // Per ogni riga, dove va la cella nuova: prima della cella che c'era al suo posto, o dopo l'ultima della riga.
        // Le celle unite che la colonna nuova attraversa si allargano, e nelle loro righe la colonna non ha celle sue.
        let crossing = cells(ofTableAt: index, in: text).filter { $0.column < column && $0.column + $0.columnSpan > column }
        let skipped = Set(crossing.flatMap { $0.row..<($0.row + $0.rowSpan) })
        let body = paragraphs.filter { !$0.mark.isCaption }
        var places: [(location: Int, afterFinal: Bool, model: Int, row: Int)] = []
        for row in 0..<shape.rows where !skipped.contains(row) {
            let cells = body.filter { $0.mark.row == row }
            if let before = cells.first(where: { $0.mark.column >= column }) {
                places.append((before.range.location, false, before.range.location, row))
            } else if let lastOfRow = cells.last {
                if lastOfRow.range.length == 0 {
                    places.append((text.length, true, max(text.length - 1, 0), row))
                } else {
                    places.append((NSMaxRange(lastOfRow.range), false, lastOfRow.range.location, row))
                }
            } else if let next = body.first(where: { $0.mark.row > row }) {
                // Una riga tutta coperta da celle unite: la cella nuova va prima della riga dopo.
                places.append((next.range.location, false, next.range.location, row))
            } else if let lastCell = body.last {
                places.append(lastCell.range.length == 0 ? (text.length, true, max(text.length - 1, 0), row)
                              : (NSMaxRange(lastCell.range), false, lastCell.range.location, row))
            }
        }
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            if mark.column >= column {
                mark.column += 1
            } else if !mark.isCaption, crossing.contains(where: { $0.row == mark.row && $0.column == mark.column }) {
                mark.columnSpan += 1
            }
            return mark
        }
        // Dall'ultima riga alla prima, perché le posizioni prima restino buone.
        for place in places.reversed() {
            insertEmptyCell(any.cell(row: place.row, column: column),
                            at: place.location, afterFinal: place.afterFinal, like: place.model, in: text)
        }
    }

    /// Toglie le celle date (con il loro testo) e sistema il paragrafo in fondo se era una di loro.
    private static func deleteCells(_ cells: [CellParagraph], in text: NSMutableAttributedString) {
        let includesFinal = cells.contains { $0.range.length == 0 }
        var final: [NSAttributedString.Key: Any] = [:]
        if let lastEnd = cells.map({ NSMaxRange($0.range) }).max(), lastEnd >= text.length, text.length > 0 {
            for key in finalKeys where key != .finalParagraphCell { if let value = text.attribute(key, at: text.length - 1, effectiveRange: nil) { final[key] = value } }
        }
        for cell in cells.reversed() where cell.range.length > 0 { text.deleteCharacters(in: cell.range) }
        guard text.length > 0 else { return }
        let last = NSRange(location: text.length - 1, length: 1)
        // Il paragrafo in fondo, se era una cella tolta, torna un paragrafo normale.
        if includesFinal { text.removeAttribute(.finalParagraphCell, range: last) }
        for (key, value) in final { text.addAttribute(key, value: value, range: last) }
    }

    /// Toglie la riga `row`; se è l'unica, la tabella.
    public static func removeRow(_ row: Int, ofTableAt index: Int, in text: NSMutableAttributedString) {
        guard let shape = shape(ofTableAt: index, in: text) else { return }
        guard shape.rows > 1 else { removeTable(at: index, in: text); return }
        // Una cella unita che comincia in questa riga e ne copre altre si divide prima; quelle che la attraversano si accorciano.
        for merged in cells(ofTableAt: index, in: text) where merged.row == row && merged.rowSpan > 1 {
            splitCell(row: merged.row, column: merged.column, ofTableAt: index, in: text)
        }
        let crossing = cells(ofTableAt: index, in: text).filter { $0.row < row && $0.row + $0.rowSpan > row }
        let cells = paragraphs(ofTableAt: index, in: text).filter { !$0.mark.isCaption && $0.mark.row == row }
        let headerRows = row < shape.headerRows ? shape.headerRows - 1 : shape.headerRows
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            if mark.row > row { mark.row -= 1 }
            if !mark.isCaption, crossing.contains(where: { $0.row == mark.row && $0.column == mark.column }) { mark.rowSpan -= 1 }
            mark.headerRows = headerRows
            return mark
        }
        deleteCells(cells, in: text)
    }

    /// Toglie la colonna `column`; se è l'unica, la tabella.
    public static func removeColumn(_ column: Int, ofTableAt index: Int, in text: NSMutableAttributedString) {
        guard let shape = shape(ofTableAt: index, in: text) else { return }
        guard shape.columns > 1 else { removeTable(at: index, in: text); return }
        for merged in cells(ofTableAt: index, in: text) where merged.column == column && merged.columnSpan > 1 {
            splitCell(row: merged.row, column: merged.column, ofTableAt: index, in: text)
        }
        let crossing = cells(ofTableAt: index, in: text).filter { $0.column < column && $0.column + $0.columnSpan > column }
        let cells = paragraphs(ofTableAt: index, in: text).filter { !$0.mark.isCaption && $0.mark.column == column }
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            if mark.column > column { mark.column -= 1 }
            if !mark.isCaption, crossing.contains(where: { $0.row == mark.row && $0.column == mark.column }) { mark.columnSpan -= 1 }
            return mark
        }
        deleteCells(cells, in: text)
    }

    /// Toglie la tabella, con il suo testo. Restituisce dove stava.
    @discardableResult
    public static func removeTable(at index: Int, in text: NSMutableAttributedString) -> Int {
        let cells = paragraphs(ofTableAt: index, in: text)
        guard let first = cells.first else { return index }
        deleteCells(cells, in: text)
        return min(first.range.location, text.length)
    }

    /// Quante righe sono d'intestazione (ripetute in cima a ogni pagina): da 0 a tutte.
    public static func setHeaderRows(_ count: Int, ofTableAt index: Int, in text: NSMutableAttributedString) {
        guard let shape = shape(ofTableAt: index, in: text) else { return }
        let count = min(max(count, 0), shape.rows)
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            mark.headerRows = count
            return mark
        }
    }

    // MARK: L'aspetto

    /// Lo stile della tabella (`nil`: quello predefinito).
    public static func setStyle(_ name: String?, ofTableAt index: Int, in text: NSMutableAttributedString) {
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            mark.style = name
            return mark
        }
    }

    /// Cambia ciò che la tabella dice del suo aspetto. Con `clearingCellBorders` le celle dimenticano i lati detti per
    /// sé (uno schema di filetti scelto per la tabella vale per tutte le celle).
    public static func changeTableValues(ofTableAt index: Int, in text: NSMutableAttributedString, clearingCellBorders: Bool = false,
                                         _ change: (inout TableValues) -> Void) {
        guard let first = paragraphs(ofTableAt: index, in: text).first?.mark else { return }
        var values = first.tableValues
        change(&values)
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            mark.tableValues = values
            if clearingCellBorders {
                mark.cellValues.top = nil
                mark.cellValues.right = nil
                mark.cellValues.bottom = nil
                mark.cellValues.left = nil
            }
            return mark
        }
    }

    /// Cambia l'aspetto proprio di una cella.
    public static func changeCellValues(row: Int, column: Int, ofTableAt index: Int, in text: NSMutableAttributedString,
                                        _ change: (inout CellValues) -> Void) {
        guard let current = paragraphs(ofTableAt: index, in: text).first(where: { $0.mark.row == row && $0.mark.column == column })?.mark else { return }
        var values = current.cellValues
        change(&values)
        remark(tableAt: index, in: text) { mark in
            guard mark.row == row, mark.column == column else { return mark }
            var mark = mark
            mark.cellValues = values
            return mark
        }
    }

    /// Dopo aver rinominato (o tolto, con `nil`) degli stili di tabella: le tabelle che li usavano seguono (una tabella
    /// il cui stile è tolto torna a quello predefinito).
    public static func renameTableStyles(_ renames: [String: String?], in text: NSMutableAttributedString) {
        guard !renames.isEmpty, text.length > 0 else { return }
        let all = NSRange(location: 0, length: text.length)
        for key in [NSAttributedString.Key.tableCell, .finalParagraphCell] {
            var changes: [(NSRange, String)] = []
            text.enumerateAttribute(key, in: all) { value, range, _ in
                guard let encoded = value as? String, var mark = CellMark(encoded: encoded), let style = mark.style, let new = renames[style] else { return }
                mark.style = new
                changes.append((range, mark.encoded))
            }
            for (range, encoded) in changes { text.addAttribute(key, value: encoded, range: range) }
        }
    }

    // MARK: Flottante e didascalia

    /// Lo stile di flottante della tabella (`nil`: sta nel testo, senza didascalia). Una tabella che diventa flottante
    /// riceve una didascalia vuota, se non ne ha; una che non lo è più perde la sua. Restituisce l'inizio della didascalia.
    @discardableResult
    public static func setFloat(_ style: String?, ofTableAt index: Int, in text: NSMutableAttributedString) -> Int? {
        let paragraphs = paragraphs(ofTableAt: index, in: text)
        guard let first = paragraphs.first else { return nil }
        remark(tableAt: index, in: text) { mark in
            var mark = mark
            mark.floatStyle = style
            return mark
        }
        let captions = paragraphs.filter(\.mark.isCaption)
        guard let style else {
            deleteCells(captions, in: text)
            return nil
        }
        if let caption = captions.first { return caption.range.location }
        var mark = first.mark.cell(row: -1, column: 0)
        mark.floatStyle = style
        insertEmptyCell(mark, at: first.range.location, afterFinal: false, like: first.range.location, in: text)
        return first.range.location
    }

    // MARK: Celle unite

    /// Il rettangolo di celle che contiene le celle date, allargato finché contiene per intero ogni cella unita che tocca.
    public static func mergeRectangle(touching marks: [CellMark], ofTableAt index: Int, in text: NSAttributedString) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        let marks = marks.filter { !$0.isCaption }
        guard !marks.isEmpty else { return nil }
        var top = marks.map(\.row).min()!, left = marks.map(\.column).min()!
        var bottom = marks.map { $0.row + $0.rowSpan - 1 }.max()!, right = marks.map { $0.column + $0.columnSpan - 1 }.max()!
        let all = cells(ofTableAt: index, in: text)
        var changed = true
        while changed {
            changed = false
            for cell in all {
                let cellBottom = cell.row + cell.rowSpan - 1, cellRight = cell.column + cell.columnSpan - 1
                let touches = cell.row <= bottom && cellBottom >= top && cell.column <= right && cellRight >= left
                guard touches else { continue }
                if cell.row < top { top = cell.row; changed = true }
                if cell.column < left { left = cell.column; changed = true }
                if cellBottom > bottom { bottom = cellBottom; changed = true }
                if cellRight > right { right = cellRight; changed = true }
            }
        }
        return (top...bottom, left...right)
    }

    /// Unisce le celle del rettangolo (allargato per contenere intere le celle unite che tocca) nella cella in alto a
    /// sinistra: i loro paragrafi con testo vanno in lei, uno dopo l'altro. Restituisce l'inizio della cella unita, o `nil`
    /// se il rettangolo è una cella sola.
    @discardableResult
    public static func mergeCells(touching marks: [CellMark], ofTableAt index: Int, in text: NSMutableAttributedString) -> Int? {
        guard let rect = mergeRectangle(touching: marks, ofTableAt: index, in: text), rect.rows.count * rect.columns.count > 1 else { return nil }
        let inside = paragraphs(ofTableAt: index, in: text).filter { !$0.mark.isCaption && rect.rows.contains($0.mark.row) && rect.columns.contains($0.mark.column) }
        guard let target = inside.first(where: { $0.mark.row == rect.rows.lowerBound && $0.mark.column == rect.columns.lowerBound }) else { return nil }
        var mark = target.mark.spanning(columns: rect.columns.count, rows: rect.rows.count)
        mark.cellValues = target.mark.cellValues
        // Il testo della cella unita: i paragrafi con testo, ciascuno con il suo a capo.
        let string = text.string as NSString
        let content = NSMutableAttributedString()
        for paragraph in inside where paragraph.range.length > 0 {
            var range = paragraph.range
            let ends = TextStyling.isLineTerminator(string.character(at: NSMaxRange(range) - 1))
            if ends { range.length -= 1 }
            guard range.length > 0 else { continue }
            content.append(text.attributedSubstring(from: range))
            content.append(NSAttributedString(string: "\n", attributes: text.attributes(at: NSMaxRange(paragraph.range) - 1, effectiveRange: nil)))
        }
        if content.length == 0 {
            content.append(NSAttributedString(string: "\n", attributes: cellAttributes(like: target.range.location, in: text, mark: mark)))
        }
        content.addAttribute(.tableCell, value: mark.encoded, range: NSRange(location: 0, length: content.length))
        content.removeAttribute(.finalParagraphCell, range: NSRange(location: 0, length: content.length))
        let location = target.range.location
        deleteCells(inside, in: text)
        text.replaceCharacters(in: NSRange(location: location, length: 0), with: content)
        return location
    }

    /// Divide una cella unita: torna a coprire una posizione sola, e ogni posizione che copriva riceve una cella vuota.
    public static func splitCell(row: Int, column: Int, ofTableAt index: Int, in text: NSMutableAttributedString) {
        guard let merged = cells(ofTableAt: index, in: text).first(where: { $0.row == row && $0.column == column }),
              merged.columnSpan > 1 || merged.rowSpan > 1 else { return }
        remark(tableAt: index, in: text) { mark in
            guard mark.row == row, mark.column == column else { return mark }
            return mark.spanning(columns: 1, rows: 1)
        }
        let anchor = paragraphs(ofTableAt: index, in: text).first { $0.mark.row == row && $0.mark.column == column }?.range.location ?? index
        for r in row..<(row + merged.rowSpan) {
            for c in column..<(column + merged.columnSpan) where r != row || c != column {
                // Prima della prima cella che viene dopo questa posizione, riga per riga; se non c'è, in fondo alla tabella.
                let body = paragraphs(ofTableAt: anchor, in: text).filter { !$0.mark.isCaption }
                let mark = merged.cell(row: r, column: c)
                if let next = body.first(where: { ($0.mark.row, $0.mark.column) > (r, c) }) {
                    insertEmptyCell(mark, at: next.range.location, afterFinal: false, like: next.range.location, in: text)
                } else if let last = body.last {
                    insertEmptyCell(mark, at: last.range.length == 0 ? text.length : NSMaxRange(last.range), afterFinal: last.range.length == 0,
                                    like: last.range.location, in: text)
                }
            }
        }
    }
}
