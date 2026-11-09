import CoreGraphics
import CoreText
import Foundation

/// Ciò che nel PDF serve a muoversi: i segnalibri dei titoli, i collegamenti fra i richiami e le loro note (andata e
/// ritorno), e le etichette delle pagine con i numeri stampati (i, ii, iii…), così il lettore mostra lo stesso numero
/// della pagina. L'idea viene da `@LinkSource`, `@LinkDest` e `@PageLabel` di Lout (Appunti/IDEE-DA-LOUT.md, idea 6).
///
/// Le posizioni sono quelle della composizione: origine della pagina in basso a sinistra, come nel PDF.
public struct PDFNavigation {
    /// Un punto d'arrivo con il suo nome, nella pagina `page` della composizione.
    public struct Destination: Equatable {
        public var name: String
        public var page: Int
        public var point: CGPoint
    }

    /// Una zona che si clicca e porta al punto d'arrivo `destination`.
    public struct Link: Equatable {
        public var destination: String
        public var page: Int
        public var rect: CGRect
    }

    /// Un segnalibro: il titolo, la sua pagina, la zona del titolo, i segnalibri dei titoli che contiene.
    public struct Bookmark: Equatable {
        public var title: String
        public var page: Int
        public var rect: CGRect
        public var children: [Bookmark]
    }

    public var destinations: [Destination] = []
    public var links: [Link] = []
    public var bookmarks: [Bookmark] = []
    /// L'etichetta di ogni pagina, se almeno una non coincide con la sua posizione nel PDF (1, 2, 3…); altrimenti vuoto.
    public var pageLabels: [String] = []

    /// Raccoglie la navigazione delle prime `pageCount` pagine della composizione (quelle che vanno nel PDF).
    public init(layout: DocumentLayout, pageCount: Int? = nil) {
        let count = min(pageCount ?? layout.pages.count, layout.pages.count)
        let pages = Array(layout.pages.prefix(count))
        collectNotes(layout: layout, pages: pages)
        bookmarks = Self.bookmarks(layout: layout, pages: pages)
        let numbers = pages.map(\.number)
        if numbers.enumerated().contains(where: { $0.element != String($0.offset + 1) }) { pageLabels = numbers }
    }

    // MARK: Note

    /// Per ogni richiamo di nota visibile: un collegamento dal richiamo all'inizio della nota e, dal segno davanti alla
    /// nota, uno che torna al richiamo.
    private mutating func collectNotes(layout: DocumentLayout, pages: [LaidOutPage]) {
        let text = layout.text
        let length = text.length
        // Il primo posto di ogni nota (le testate e i piedi correnti si ripetono: conta il primo).
        var noteStarts: [Int: (page: Int, line: PlacedLine)] = [:]
        var references: [Int: (page: Int, rect: CGRect)] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for line in page.lines {
                if let noteRange = line.noteRange {
                    let anchor = noteRange.location - 1
                    if noteStarts[anchor] == nil { noteStarts[anchor] = (pageIndex, line) }
                    continue
                }
                // I richiami: nel testo composto di una riga del corpo, il materiale aggiunto fra due tratti del
                // documento, subito prima del carattere che ancora la nota.
                let composedEnd = NSMaxRange(line.composedRange)
                for (previous, next) in zip(line.map.segments, line.map.segments.dropFirst()) {
                    let start = previous.composed + previous.length
                    let anchor = previous.document + previous.length
                    guard next.composed > start, start >= line.composedRange.location, next.composed <= composedEnd,
                          anchor < length, TextStyling.isNoteAnchor(in: text, at: anchor), references[anchor] == nil else { continue }
                    let left = line.origin.x + line.offset(forString: start - line.composedOffset)
                    let right = line.origin.x + line.offset(forString: next.composed - line.composedOffset)
                    guard right - left > 0.5 else { continue }
                    references[anchor] = (pageIndex, CGRect(x: left, y: line.origin.y - line.descent, width: right - left,
                                                            height: line.ascent + line.descent))
                }
            }
        }
        for anchor in references.keys.sorted() {
            guard let reference = references[anchor], let note = noteStarts[anchor], let noteRange = note.line.noteRange else { continue }
            let toNote = "note-\(anchor)", toReference = "ref-\(anchor)"
            destinations.append(Destination(name: toNote, page: note.page,
                                            point: CGPoint(x: note.line.origin.x, y: note.line.origin.y + note.line.ascent)))
            links.append(Link(destination: toNote, page: reference.page, rect: reference.rect))
            // Il ritorno: dal segno della nota, che sta davanti al suo testo nella prima riga.
            let line = note.line
            let markEnd = line.origin.x + line.offset(forString: line.stringIndex(forDocument: noteRange.location))
            if markEnd - line.origin.x > 0.5 {
                destinations.append(Destination(name: toReference, page: reference.page,
                                                point: CGPoint(x: reference.rect.minX, y: reference.rect.maxY)))
                links.append(Link(destination: toReference, page: note.page,
                                  rect: CGRect(x: line.origin.x, y: line.origin.y - line.descent, width: markEnd - line.origin.x,
                                               height: line.ascent + line.descent)))
            }
        }
    }

    // MARK: Segnalibri

    /// I segnalibri dei titoli, annidati come nell'albero degli oggetti; il titolo è preceduto dal suo numero.
    static func bookmarks(layout: DocumentLayout, pages: [LaidOutPage]) -> [Bookmark] {
        let text = layout.text
        func place(of location: Int) -> (page: Int, rect: CGRect)? {
            for (pageIndex, page) in pages.enumerated() {
                let lines = page.lines.filter { $0.noteRange == nil && $0.paragraphLocation == location }
                guard !lines.isEmpty else { continue }
                var rect = lines.reduce(CGRect.null) {
                    $0.union(CGRect(x: $1.origin.x, y: $1.origin.y - $1.descent, width: max($1.width, 1), height: $1.ascent + $1.descent))
                }
                // Con una testata (etichetta, numero, filetto) il segnalibro porta alla sua cima.
                for part in page.headingParts where part.paragraphLocation == location { rect = rect.union(part.rect) }
                return (pageIndex, rect)
            }
            return nil
        }
        func convert(_ items: [OutlineItem]) -> [Bookmark] {
            items.flatMap { item -> [Bookmark] in
                let children = convert(item.children ?? [])
                guard case .heading = item.kind, let place = place(of: item.range.location) else { return children }
                let words = BodyText(text, paragraph: item.range).string as String
                var title = words.replacingOccurrences(of: "\u{2028}", with: " ").replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces)
                if title.isEmpty { title = item.title }
                if !item.label.isEmpty, item.label != "§" { title = item.label.trimmingCharacters(in: .whitespaces) + " " + title }
                return [Bookmark(title: title, page: place.page, rect: place.rect, children: children)]
            }
        }
        return convert(DocumentOutline.build(text: text, layout: layout, floatStyles: []))
    }

    /// I segnalibri come li vuole `CGPDFContextSetOutline`: una radice con i soli figli, pagine contate da 1.
    var outline: CFDictionary? {
        guard !bookmarks.isEmpty else { return nil }
        func entry(_ bookmark: Bookmark) -> NSDictionary {
            let dictionary = NSMutableDictionary()
            dictionary[kCGPDFOutlineTitle] = bookmark.title
            dictionary[kCGPDFOutlineDestination] = bookmark.page + 1
            dictionary[kCGPDFOutlineDestinationRect] = bookmark.rect.dictionaryRepresentation
            if !bookmark.children.isEmpty { dictionary[kCGPDFOutlineChildren] = bookmark.children.map(entry) }
            return dictionary
        }
        return [kCGPDFOutlineChildren: bookmarks.map(entry)] as NSDictionary
    }

    // MARK: Scrittura nel contesto

    /// Scrive i punti d'arrivo e i collegamenti della pagina `index`; va chiamata fra l'inizio e la fine della pagina.
    func write(page index: Int, in context: CGContext) {
        for destination in destinations where destination.page == index {
            context.addDestination(destination.name as CFString, at: destination.point)
        }
        for link in links where link.page == index {
            context.setDestination(link.destination as CFString, for: link.rect)
        }
    }

    // MARK: Ritocchi del file

    /// Ritocca il PDF scritto da Core Graphics con un aggiornamento in coda al file, senza toccare ciò che c'è:
    ///
    /// - aggiunge le etichette delle pagine (`/PageLabels` nel catalogo), se `labels` non è vuoto;
    /// - completa i segnalibri, che Core Graphics scrive senza il `/Parent` di ogni voce e con un `/Count` negativo
    ///   nella radice (i lettori li riparano, ma un controllo severo li segnala).
    ///
    /// Se il file non ha la forma attesa (tabella dei riferimenti classica) lo restituisce com'è.
    static func finishing(_ data: Data, labels: [String], values: [Int]) -> Data {
        guard var file = IncrementalUpdate(data), let root = file.trailerReference("Root"),
              let catalog = file.object(root.number) else { return data }
        if let outlines = reference("Outlines", in: catalog.body), let outlineRoot = file.object(outlines.number) {
            // Le voci di un livello: dalla prima, seguendo /Next; ognuna con i suoi figli da /First.
            var visited: Set<Int> = []
            func visibleCount(firstOf parent: Int, parentBody: String) -> Int {
                var count = 0
                var next = reference("First", in: parentBody)?.number
                while let item = next, visited.insert(item).inserted, visited.count < 100_000, let object = file.object(item) {
                    var body = object.body
                    if reference("Parent", in: body) == nil { body = inserting("/Parent \(parent) 0 R", into: body) }
                    // Core Graphics porta al riquadro del titolo con /FitR, e il lettore ingrandisce fino a riempirne la
                    // finestra: meglio /XYZ, che va all'angolo in alto a sinistra del titolo e lascia l'ingrandimento com'è.
                    body = body.replacingOccurrences(of: #"/FitR\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)"#,
                                                     with: "/XYZ $1 $4 null", options: .regularExpression)
                    file.replace(item, generation: object.generation, body: body)
                    let children = visibleCount(firstOf: item, parentBody: body)
                    let open = (integer("Count", in: body) ?? 0) > 0
                    count += 1 + (open ? children : 0)
                    next = reference("Next", in: body)?.number
                }
                return count
            }
            let count = visibleCount(firstOf: outlines.number, parentBody: outlineRoot.body)
            var body = outlineRoot.body.replacingOccurrences(of: #"/Count\s+-?\d+"#, with: "", options: .regularExpression)
            body = inserting("/Count \(count)", into: body)
            file.replace(outlines.number, generation: outlineRoot.generation, body: body)
        }
        if !labels.isEmpty, labels.count == values.count, !catalog.body.contains("/PageLabels") {
            file.replace(root.number, generation: catalog.generation,
                         body: inserting("/PageLabels << /Nums [ " + numberTree(labels, values: values) + "] >>", into: catalog.body))
        }
        return file.data
    }

    /// Un dizionario con una voce in più, subito dopo il suo `<<`.
    private static func inserting(_ entry: String, into body: String) -> String {
        guard let open = body.range(of: "<<") else { return body }
        return String(body[..<open.upperBound]) + " " + entry + String(body[open.upperBound...])
    }

    /// Le voci di un dizionario lette senza le stringhe, che potrebbero contenere parole come `/Next`.
    private static func withoutStrings(_ body: String) -> String {
        body.replacingOccurrences(of: #"\((?:\\.|[^\\)])*\)"#, with: "()", options: .regularExpression)
    }

    private static func reference(_ key: String, in body: String) -> (number: Int, generation: Int)? {
        guard let match = firstMatch("/\(key)\\s+(\\d+)\\s+(\\d+)\\s+R", in: withoutStrings(body)),
              let number = Int(match[0]), let generation = Int(match[1]) else { return nil }
        return (number, generation)
    }

    private static func integer(_ key: String, in body: String) -> Int? {
        firstMatch("/\(key)\\s+(-?\\d+)", in: withoutStrings(body))?.first.flatMap(Int.init)
    }

    /// Un aggiornamento in coda a un PDF con la tabella dei riferimenti classica: oggetti riscritti con lo stesso
    /// numero, una nuova sezione della tabella e un nuovo trailer che rimanda al precedente.
    private struct IncrementalUpdate {
        let original: Data
        let raw: NSString
        let trailer: String
        let previousXref: String
        var replaced: [(number: Int, generation: Int, body: String)] = []
        var starts: [Int: (location: Int, generation: Int)] = [:]

        init?(_ data: Data) {
            guard let source = String(data: data, encoding: .isoLatin1) else { return nil }
            let raw = source as NSString
            let trailerStart = raw.range(of: "trailer", options: .backwards)
            let startxref = raw.range(of: "startxref", options: .backwards)
            guard trailerStart.location != NSNotFound, startxref.location != NSNotFound, trailerStart.location < startxref.location,
                  let previous = PDFNavigation.firstMatch(#"startxref\s+(\d+)"#, in: raw.substring(from: startxref.location))?.first
            else { return nil }
            original = data
            self.raw = raw
            trailer = raw.substring(with: NSRange(location: trailerStart.location, length: startxref.location - trailerStart.location))
            previousXref = previous
            // Dove comincia ogni oggetto: l'ultima definizione di ogni numero, cercata una volta sola.
            if let expression = try? NSRegularExpression(pattern: #"(?:^|[\r\n])(\d+)\s+(\d+)\s+obj"#) {
                for match in expression.matches(in: source, range: NSRange(location: 0, length: raw.length)) {
                    guard let number = Int(raw.substring(with: match.range(at: 1))),
                          let generation = Int(raw.substring(with: match.range(at: 2))) else { continue }
                    starts[number] = (NSMaxRange(match.range), generation)
                }
            }
        }

        func trailerReference(_ key: String) -> (number: Int, generation: Int)? { PDFNavigation.reference(key, in: trailer) }

        /// Il dizionario dell'oggetto (l'ultima definizione nel file, o quella già riscritta).
        func object(_ number: Int) -> (generation: Int, body: String)? {
            if let done = replaced.last(where: { $0.number == number }) { return (done.generation, done.body) }
            guard let (start, generation) = starts[number] else { return nil }
            let end = raw.range(of: "endobj", options: [], range: NSRange(location: start, length: raw.length - start))
            guard end.location != NSNotFound else { return nil }
            let body = raw.substring(with: NSRange(location: start, length: end.location - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Solo dizionari: un oggetto con un flusso non si riscrive così.
            guard body.hasPrefix("<<"), body.hasSuffix(">>") else { return nil }
            return (generation, body)
        }

        mutating func replace(_ number: Int, generation: Int, body: String) {
            replaced.removeAll { $0.number == number }
            replaced.append((number, generation, body))
        }

        var data: Data {
            guard !replaced.isEmpty, let open = trailer.range(of: "<<"), let close = trailer.range(of: ">>", options: .backwards) else { return original }
            var update = "\n"
            var offsets: [Int: (offset: Int, generation: Int)] = [:]
            for object in replaced {
                offsets[object.number] = (original.count + (update as NSString).length, object.generation)
                update += "\(object.number) \(object.generation) obj\n\(object.body)\nendobj\n"
            }
            let xref = original.count + (update as NSString).length
            update += "xref\n"
            for number in offsets.keys.sorted() {
                let entry = offsets[number]!
                update += "\(number) 1\n" + String(format: "%010d %05d n \n", entry.offset, entry.generation)
            }
            var dictionary = String(trailer[open.upperBound..<close.lowerBound])
            dictionary = dictionary.replacingOccurrences(of: #"/Prev\s+\d+"#, with: "", options: .regularExpression)
            update += "trailer\n<<" + dictionary + " /Prev \(previousXref) >>\nstartxref\n\(xref)\n%%EOF\n"
            guard let tail = update.data(using: .isoLatin1) else { return original }
            return original + tail
        }
    }

    /// Le voci di `/Nums`: una per ogni tratto di pagine numerate di seguito nello stesso stile.
    static func numberTree(_ labels: [String], values: [Int]) -> String {
        enum Style: Equatable { case decimal, lowerRoman, upperRoman, literal(String) }
        func style(_ label: String, _ value: Int) -> Style {
            guard value > 0 else { return .literal(label) }
            if label == String(value) { return .decimal }
            let roman = romanNumeral(value)
            if label == roman.lowercased() { return .lowerRoman }
            if label == roman { return .upperRoman }
            return .literal(label)
        }
        var result = ""
        var last: (style: Style, value: Int)?
        for (index, label) in labels.enumerated() {
            let current = style(label, values[index])
            // Un tratto continua con lo stesso stile e il numero seguente; un'etichetta qualsiasi ha un tratto suo.
            let continues: Bool = {
                guard let last, last.style == current else { return false }
                if case .literal = current { return false }
                return values[index] == last.value + 1
            }()
            if !continues {
                switch current {
                case .decimal: result += "\(index) << /S /D /St \(values[index]) >> "
                case .lowerRoman: result += "\(index) << /S /r /St \(values[index]) >> "
                case .upperRoman: result += "\(index) << /S /R /St \(values[index]) >> "
                case .literal(let text): result += "\(index) << /P \(pdfString(text)) >> "
                }
            }
            last = (current, values[index])
        }
        return result
    }

    /// Un numero romano maiuscolo.
    static func romanNumeral(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"),
                                      (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var rest = value, result = ""
        for (amount, letters) in table {
            while rest >= amount { result += letters; rest -= amount }
        }
        return result
    }

    /// Una stringa PDF: letterale per il solo ASCII stampabile, altrimenti esadecimale in UTF-16 con il segno d'ordine.
    static func pdfString(_ text: String) -> String {
        if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)")
            return "(" + escaped + ")"
        }
        return "<FEFF" + text.utf16.map { String(format: "%04X", $0) }.joined() + ">"
    }

    private static func firstMatch(_ pattern: String, in string: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length)) else { return nil }
        return (1..<match.numberOfRanges).map { (string as NSString).substring(with: match.range(at: $0)) }
    }
}
