import AppKit
import CoreText

extension NSAttributedString.Key {
    /// Chiede la composizione con Graphite. Il valore sono le funzioni Graphite, `tag=valore` separate da spazi
    /// (`"lldt=1 cv07=2"`); la stringa vuota per nessuna.
    public static let graphite = NSAttributedString.Key("WordProcessorGraphite")
    /// Solo nel testo da comporre: i glifi Graphite di un gruppo, sul suo primo carattere.
    static let graphiteCluster = NSAttributedString.Key("WordProcessorGraphiteCluster")
    /// Solo nel testo da comporre: il colore del testo Graphite (per Core Text il suo spazio è trasparente).
    static let graphiteColor = NSAttributedString.Key("WordProcessorGraphiteColor")
}

/// Il testo composto con Graphite dentro le righe di Core Text. Come per le immagini nella riga, per Core Text ogni
/// gruppo (cluster) di Graphite è uno spazio delle sue misure: a capo, giustificazione, cursore e selezione restano di
/// Core Text, e i glifi di Graphite si disegnano dove Core Text ha lasciato quello spazio.
enum GraphiteLayout {
    /// I glifi di un gruppo, con le posizioni dall'origine del gruppo (y verso l'alto), e lo spazio che Core Text gli
    /// lascia.
    final class Cluster: NSObject {
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
        let delegate: CTRunDelegate
        /// Quanti caratteri (unità UTF-16) copre il gruppo.
        let length: Int
        /// Dove cominciano i grafemi dopo il primo, dall'inizio del gruppo: le posizioni del cursore al suo interno.
        let boundaries: [Int]
        /// I caratteri del gruppo, nell'ordine in cui si leggono: il testo che il PDF deve restituire.
        let text: String

        init(glyphs: [CGGlyph], positions: [CGPoint], delegate: CTRunDelegate, length: Int, boundaries: [Int], text: String = "") {
            self.glyphs = glyphs
            self.positions = positions
            self.delegate = delegate
            self.length = length
            self.boundaries = boundaries
            self.text = text
        }
    }

    /// Un tratto composto: per ogni gruppo, i caratteri (dall'inizio del tratto) e i suoi glifi.
    private struct Shaped {
        var clusters: [(characters: NSRange, cluster: Cluster)]
    }

    struct Key: Hashable {
        let text: String
        let fontName: String
        /// Il file del font e le coordinate degli assi: due font con lo stesso nome PostScript (due file, due istanze di un
        /// font variabile) non si scambiano i glifi.
        let fontFile: String
        let variation: String
        let size: CGFloat
        let settings: String
    }

    /// La chiave della memoria dei tratti composti.
    static func cacheKey(_ text: String, font: CTFont, settings encoded: String, language: String?) -> Key {
        let file = (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path ?? ""
        let axes = (CTFontCopyVariation(font) as? [NSNumber: NSNumber]) ?? [:]
        let variation = axes.sorted { $0.key.uint32Value < $1.key.uint32Value }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return Key(text: text, fontName: CTFontCopyPostScriptName(font) as String, fontFile: file, variation: variation,
                   size: CTFontGetSize(font), settings: encoded + "|" + (language ?? ""))
    }

    private final class Metrics {
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        init(width: CGFloat, ascent: CGFloat, descent: CGFloat) {
            self.width = width
            self.ascent = ascent
            self.descent = descent
        }
    }

    private static let lock = NSLock()
    /// I tratti già composti, con i loro delegati: gli stessi oggetti a ogni composizione, così il testo di un paragrafo
    /// resta uguale e la memoria delle righe lo ritrova.
    nonisolated(unsafe) private static var shapedRuns: [Key: Shaped] = [:]
    nonisolated(unsafe) private static var zeroWidth: CTRunDelegate?

    private static func delegate(width: CGFloat, ascent: CGFloat, descent: CGFloat) -> CTRunDelegate {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).release() },
            getAscent: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().ascent },
            getDescent: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().descent },
            getWidth: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().width })
        let metrics = Unmanaged.passRetained(Metrics(width: width, ascent: ascent, descent: descent)).toOpaque()
        return CTRunDelegateCreate(&callbacks, metrics)!
    }

    /// Lo spazio nullo dei caratteri di un gruppo dopo il primo (da chiedere con il lucchetto preso).
    private static var zeroWidthDelegate: CTRunDelegate {
        if let zeroWidth { return zeroWidth }
        let made = delegate(width: 0, ascent: 0, descent: 0)
        zeroWidth = made
        return made
    }

    /// Le funzioni scritte nell'attributo: `tag=valore`, il tag di quattro lettere al più o un numero.
    static func settings(from encoded: String) -> [GraphiteSetting] {
        encoded.split(separator: " ").compactMap { item in
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = UInt16(parts[1]) else { return nil }
            let tag = String(parts[0])
            if let number = UInt32(tag) { return GraphiteSetting(id: number, value: value) }
            guard (1...4).contains(tag.utf8.count), tag.allSatisfy(\.isASCII) else { return nil }
            return GraphiteSetting(id: Graphite.fourCC(tag.padding(toLength: 4, withPad: " ", startingAt: 0)), value: value)
        }
    }

    private static func shaped(_ text: String, font: CTFont, settings encoded: String, language: String?) -> Shaped? {
        let key = cacheKey(text, font: font, settings: encoded, language: language)
        lock.lock()
        if let cached = shapedRuns[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard let run = Graphite.shape(text, font: font, settings: settings(from: encoded), language: language) else { return nil }
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let string = text as NSString
        let clusters = run.clusters.map { cluster in
            var boundaries: [Int] = []
            var next = NSMaxRange(string.rangeOfComposedCharacterSequence(at: cluster.characters.location))
            while next < NSMaxRange(cluster.characters) {
                boundaries.append(next - cluster.characters.location)
                next = NSMaxRange(string.rangeOfComposedCharacterSequence(at: next))
            }
            let origin = cluster.glyphs.location < run.positions.count ? run.positions[cluster.glyphs.location].x : run.advance
            let glyphs = Array(run.glyphs[cluster.glyphs.location..<NSMaxRange(cluster.glyphs)])
            let positions = run.positions[cluster.glyphs.location..<NSMaxRange(cluster.glyphs)].map { CGPoint(x: $0.x - origin, y: $0.y) }
            return (cluster.characters, Cluster(glyphs: glyphs, positions: positions,
                                                delegate: delegate(width: cluster.advance, ascent: ascent, descent: descent),
                                                length: cluster.characters.length, boundaries: boundaries,
                                                text: string.substring(with: cluster.characters)))
        }
        let result = Shaped(clusters: clusters)
        lock.lock()
        defer { lock.unlock() }
        if let cached = shapedRuns[key] { return cached }
        if shapedRuns.count > 20_000 { shapedRuns.removeAll() }
        shapedRuns[key] = result
        return result
    }

    /// Il risultato di un paragrafo: il testo con gli spazi di Graphite (`nil` se non cambia) e i tratti contati.
    private final class Prepared {
        let text: NSAttributedString?
        let graphite: Int
        let coreText: Int
        init(text: NSAttributedString?, graphite: Int, coreText: Int) {
            self.text = text
            self.graphite = graphite
            self.coreText = coreText
        }
    }

    /// I paragrafi già preparati, per testo con i suoi attributi: a ogni tasto si rifà solo quello toccato.
    nonisolated(unsafe) private static var preparedParagraphs: [NSAttributedString: Prepared] = [:]
    /// I testi con i segnaposto già fatti, per paragrafo.
    nonisolated(unsafe) private static var placeholderTexts: [NSAttributedString: NSAttributedString] = [:]

    /// Nel testo da comporre, i tratti che chiedono Graphite diventano spazi delle misure dei loro gruppi, con i glifi
    /// da disegnare. Restano a Core Text i tratti di un font senza tabelle Graphite, o tutti se manca la libreria: il
    /// risultato dice quanti tratti vanno all'uno e all'altro.
    @discardableResult
    static func apply(in text: NSMutableAttributedString) -> (graphite: Int, coreText: Int) {
        let all = NSRange(location: 0, length: text.length)
        var asked = false
        text.enumerateAttribute(.graphite, in: all) { value, _, stop in
            if value != nil {
                asked = true
                stop.pointee = true
            }
        }
        guard asked else { return (0, 0) }
        let string = text.string as NSString
        var counts = (graphite: 0, coreText: 0)
        var location = 0
        while location < text.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = max(NSMaxRange(paragraph), location + 1)
            var hasGraphite = false
            text.enumerateAttribute(.graphite, in: paragraph) { value, _, stop in
                if value != nil {
                    hasGraphite = true
                    stop.pointee = true
                }
            }
            guard hasGraphite else { continue }
            let original = text.attributedSubstring(from: paragraph)
            lock.lock()
            var prepared = preparedParagraphs[original]
            lock.unlock()
            if prepared == nil {
                let piece = NSMutableAttributedString(attributedString: original)
                let pieceCounts = applyToParagraph(piece)
                prepared = Prepared(text: piece.isEqual(to: original) ? nil : piece, graphite: pieceCounts.graphite, coreText: pieceCounts.coreText)
                lock.lock()
                if preparedParagraphs.count > 20_000 { preparedParagraphs.removeAll() }
                preparedParagraphs[original] = prepared
                lock.unlock()
            }
            if let styled = prepared?.text { text.replaceCharacters(in: paragraph, with: styled) }
            counts.graphite += prepared?.graphite ?? 0
            counts.coreText += prepared?.coreText ?? 0
        }
        return counts
    }

    /// Il lavoro su un paragrafo solo.
    private static func applyToParagraph(_ text: NSMutableAttributedString) -> (graphite: Int, coreText: Int) {
        let all = NSRange(location: 0, length: text.length)
        var pieces: [NSRange] = []
        // Un tratto per volta: con gli stessi attributi (font, funzioni, nota o corpo).
        text.enumerateAttribute(.graphite, in: all) { value, range, _ in
            guard value is String else { return }
            text.enumerateAttributes(in: range) { _, piece, _ in pieces.append(piece) }
        }
        let string = text.string as NSString
        var counts = (graphite: 0, coreText: 0)
        let delegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        lock.lock()
        let zero = zeroWidthDelegate
        lock.unlock()
        for piece in pieces {
            let attributes = text.attributes(at: piece.location, effectiveRange: nil)
            guard attributes[.inlineImage] == nil, let font = attributes[.font] as? NSFont,
                  let encoded = attributes[.graphite] as? String else { continue }
            // Gli a capo restano caratteri di Core Text: dividono il tratto.
            var start = piece.location
            while start < NSMaxRange(piece) {
                var end = start
                while end < NSMaxRange(piece), !TextStyling.isLineTerminator(string.character(at: end)) { end += 1 }
                if end > start {
                    let range = NSRange(location: start, length: end - start)
                    if let shaped = shaped(string.substring(with: range), font: font as CTFont, settings: encoded,
                                           language: (attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] as? String)
                                               ?? attributes[.language] as? String) {
                        let color = attributes[colorKey] ?? CGColor(gray: 0, alpha: 1)
                        text.removeAttribute(.kern, range: range)
                        text.addAttributes([colorKey: CGColor.clear, .graphiteColor: color], range: range)
                        for (characters, cluster) in shaped.clusters where characters.length > 0 {
                            let first = NSRange(location: range.location + characters.location, length: 1)
                            text.addAttributes([delegateKey: cluster.delegate, .graphiteCluster: cluster], range: first)
                            if characters.length > 1 {
                                text.addAttribute(delegateKey, value: zero, range: NSRange(location: first.location + 1, length: characters.length - 1))
                            }
                        }
                        counts.graphite += 1
                    } else {
                        counts.coreText += 1
                    }
                }
                start = end + 1
            }
        }
        return counts
    }

    /// Un gruppo fatto a mano, con il suo spazio: per le prove della geometria.
    static func cluster(width: CGFloat, length: Int, boundaries: [Int]) -> Cluster {
        Cluster(glyphs: [], positions: [], delegate: delegate(width: width, ascent: 10, descent: 3), length: length, boundaries: boundaries)
    }

    /// Lo spazio nullo, per le prove della geometria.
    static var zeroWidthForTests: CTRunDelegate {
        lock.lock()
        defer { lock.unlock() }
        return zeroWidthDelegate
    }

    // MARK: Cursore dentro i gruppi

    /// I gruppi Graphite di una riga di Core Text: dove comincia ciascuno nella riga, la sua ascissa e la sua larghezza.
    private static func clusters(in line: CTLine) -> [(start: Int, x: CGFloat, width: CGFloat, cluster: Cluster)] {
        (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).compactMap { run in
            guard let cluster = (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.graphiteCluster] as? Cluster else { return nil }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
            return (CTRunGetStringRange(run).location, position.x, width, cluster)
        }
    }

    /// L'ascissa, dall'inizio della riga, di un indice della riga che cade dentro un gruppo Graphite; `nil` fuori dai
    /// gruppi. Il gruppo si divide in parti uguali fra i suoi grafemi: Graphite non dà le posizioni del cursore dentro un
    /// gruppo, e questa è una convenzione nostra. Un indice in mezzo a un grafemo vale come il suo inizio.
    static func offset(in line: CTLine, stringIndex index: Int) -> CGFloat? {
        for group in clusters(in: line) where index > group.start && index < group.start + group.cluster.length {
            let inside = index - group.start
            let part = group.cluster.boundaries.filter { $0 <= inside }.count
            return group.x + group.width * CGFloat(part) / CGFloat(group.cluster.boundaries.count + 1)
        }
        return nil
    }

    /// L'indice della riga più vicino a un'ascissa che cade su un gruppo Graphite: il suo inizio, la sua fine o
    /// l'inizio di uno dei suoi grafemi, mai in mezzo a un grafemo. `nil` fuori dai gruppi.
    static func stringIndex(in line: CTLine, offset x: CGFloat) -> Int? {
        for group in clusters(in: line) where group.width > 0 && x >= group.x && x < group.x + group.width {
            let stops = [0] + group.cluster.boundaries + [group.cluster.length]
            let part = Int(((x - group.x) / group.width * CGFloat(stops.count - 1)).rounded())
            return group.start + stops[min(max(part, 0), stops.count - 1)]
        }
        return nil
    }

    /// Il testo di un tratto Graphite, invisibile, per il PDF: un glifo per carattere (quello della `cmap` del font), uno
    /// dopo l'altro con le loro larghezze, ridotte se serve perché stiano nel tratto. Un vuoto fra due glifi chi legge il
    /// PDF lo prende per uno spazio: con posizioni a distanze uguali un segno largo zero (il virāma) lo lasciava. I
    /// caratteri che il font non ha restano fuori.
    private static func drawInvisibleText(_ text: String, font: CTFont, from x: CGFloat, width: CGFloat, baseline: CGFloat, in context: CGContext) {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
        let drawn = glyphs.filter { $0 != 0 }
        guard !drawn.isEmpty else { return }
        var advances = [CGSize](repeating: .zero, count: drawn.count)
        let total = CTFontGetAdvancesForGlyphs(font, .horizontal, drawn, &advances, drawn.count)
        // Si stringe, non si allarga: allargando, fra un glifo e il seguente resterebbe un vuoto, letto come spazio.
        let scale = total > 0 ? min(width / CGFloat(total), 1) : 0
        var positions: [CGPoint] = []
        var cursor = x
        for (index, advance) in advances.enumerated() {
            positions.append(CGPoint(x: total > 0 ? cursor : x + width * CGFloat(index) / CGFloat(drawn.count), y: baseline))
            cursor += advance.width * scale
        }
        context.setTextDrawingMode(.invisible)
        CTFontDrawGlyphs(font, drawn, positions, drawn.count, context)
        context.setTextDrawingMode(.fill)
    }

    /// L'ultimo punto, fra `start` (escluso) e `end` (compreso), in cui il testo vero può andare a capo; `nil` se
    /// nessuno (una parola più lunga della riga). Per Core Text, che vede i segnaposto, ogni gruppo sarebbe un punto buono.
    static func lastLineBreak(in string: NSString, after start: Int, notBeyond end: Int) -> Int? {
        let tokenizer = CFStringTokenizerCreate(nil, string, CFRange(location: start, length: string.length - start), kCFStringTokenizerUnitLineBreak, nil)
        var best: Int?
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let tokenEnd = token.location + token.length
            if tokenEnd > end { break }
            if tokenEnd > start { best = tokenEnd }
        }
        return best
    }

    /// Il testo da dare a Core Text: i caratteri composti da Graphite diventano segnaposto (U+FFFC, come le immagini),
    /// con gli stessi attributi. Con i caratteri veri Core Text li riordinerebbe secondo la loro scrittura (il segno
    /// birmano «ြ» davanti alla consonante) e cursore e larghezze andrebbero fuori posto. Gli a capo e la sillabazione
    /// si cercano invece nel testo vero.
    static func placeholders(_ text: NSAttributedString) -> NSAttributedString {
        let all = NSRange(location: 0, length: text.length)
        var ranges: [NSRange] = []
        text.enumerateAttribute(.graphiteColor, in: all) { value, range, _ in if value != nil { ranges.append(range) } }
        guard !ranges.isEmpty else { return text }
        lock.lock()
        if let cached = placeholderTexts[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        // Il testo nuovo in un colpo solo, poi gli attributi ricopiati tratto per tratto (sostituire i caratteri a pezzi
        // costava un millisecondo a paragrafo).
        var units = Array((text.string as NSString).utf16Units)
        for range in ranges { for index in range.location..<NSMaxRange(range) { units[index] = 0xFFFC } }
        let copy = NSMutableAttributedString(string: String(utf16CodeUnits: units, count: units.count))
        copy.beginEditing()
        text.enumerateAttributes(in: all) { attributes, range, _ in copy.setAttributes(attributes, range: range) }
        copy.endEditing()
        lock.lock()
        if placeholderTexts.count > 20_000 { placeholderTexts.removeAll() }
        placeholderTexts[NSAttributedString(attributedString: text)] = copy
        lock.unlock()
        return copy
    }

    /// Disegna sullo schermo i glifi Graphite di una riga già collocata, nello spazio dei loro gruppi.
    static func draw(line: CTLine, at origin: CGPoint, in context: CGContext) {
        // `CTLineDraw` lascia la posizione del testo in fondo alla riga, e la matrice del testo non fa parte dello stato
        // grafico: senza rimetterla a posto i glifi andrebbero spostati di tanto.
        let textMatrix = context.textMatrix
        context.textMatrix = .identity
        defer { context.textMatrix = textMatrix }
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            guard let placed = placedCluster(run, origin: origin) else { continue }
            context.saveGState()
            if let color = placed.color { context.setFillColor(color) }
            CTFontDrawGlyphs(placed.font, placed.cluster.glyphs, placed.positions, placed.cluster.glyphs.count, context)
            context.restoreGState()
        }
    }

    /// Un gruppo Graphite della riga, al suo posto: font, colore, posizione e larghezza del suo spazio, posizioni dei glifi.
    private static func placedCluster(_ run: CTRun, origin: CGPoint)
        -> (cluster: Cluster, font: CTFont, color: CGColor?, base: CGPoint, width: CGFloat, positions: [CGPoint])? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let cluster = attributes[NSAttributedString.Key.graphiteCluster] as? Cluster else { return nil }
        let font = attributes[kCTFontAttributeName] as! CTFont
        var position = CGPoint.zero
        CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
        let shift = (attributes[kCTBaselineOffsetAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
        let base = CGPoint(x: origin.x + position.x, y: origin.y + position.y + shift)
        let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
        let color = attributes[NSAttributedString.Key.graphiteColor].map { $0 as! CGColor }
        return (cluster, font, color, base, width, cluster.positions.map { CGPoint(x: base.x + $0.x, y: base.y + $0.y) })
    }

    /// Il testo che il PDF deve dare per un tratto di Core Text della riga, se è in una scrittura che riordina i segni
    /// (`ReorderingScripts`): i caratteri del documento che il tratto copre. `nil` per gli altri tratti, che restano
    /// testo vero.
    private static func reorderingText(of run: CTRun, in placed: PlacedLine, text: NSString?) -> String? {
        guard let text, (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] == nil else { return nil }
        let range = CTRunGetStringRange(run)
        let start = placed.documentIndex(forString: range.location), end = placed.documentIndex(forString: range.location + range.length)
        guard end > start, end <= text.length else { return nil }
        let string = text.substring(with: NSRange(location: start, length: end - start))
        return ReorderingScripts.contains(string) ? string : nil
    }

    /// Vero se nel PDF la riga va disegnata da `drawLineForPDF`: ha testo Graphite, o testo di Core Text in una scrittura
    /// che riordina i segni.
    static func needsPDFText(_ placed: PlacedLine, text: NSString?) -> Bool {
        (CTLineGetGlyphRuns(placed.line) as? [CTRun] ?? []).contains { run in
            (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.graphiteColor] != nil || reorderingText(of: run, in: placed, text: text) != nil
        }
    }

    /// Nel PDF, una riga con testo Graphite o in una scrittura che riordina i segni, tratto per tratto nell'ordine della
    /// riga (chi legge il PDF segue quello). I glifi di quei tratti diventano contorni vettoriali, che non sono testo; sotto
    /// ogni tratto continuo si scrive, invisibile, il suo testo: un glifo per carattere, quello che il font dà al carattere,
    /// nell'ordine in cui si legge. Così il testo si copia e si cerca giusto anche dove i segni sono riordinati o fusi (la
    /// matra «ि» disegnata prima della consonante, il reph, i congiunti): Core Text, da solo, scrive nel PDF i glifi
    /// nell'ordine in cui li disegna, e «किताब» si estraeva come «िकताब». Gli altri tratti di Core Text si disegnano interi,
    /// senza i segnaposto del testo Graphite (si estrarrebbero come U+FFFC).
    static func drawLineForPDF(_ placed: PlacedLine, text: NSString?, in context: CGContext) {
        let origin = placed.origin
        let textMatrix = context.textMatrix
        defer { context.textMatrix = textMatrix }
        var segment: (text: String, font: CTFont, x: CGFloat, width: CGFloat, baseline: CGFloat)?
        func flush() {
            if let open = segment {
                context.textMatrix = .identity
                drawInvisibleText(open.text, font: open.font, from: open.x, width: open.width, baseline: open.baseline, in: context)
            }
            segment = nil
        }
        /// I glifi come contorni, nel loro colore; poi il loro testo nel tratto invisibile, che prosegue finché i pezzi si
        /// toccano, sulla stessa linea di base e con lo stesso font.
        func outline(_ glyphs: [CGGlyph], at positions: [CGPoint], font: CTFont, color: CGColor?, text piece: String, x: CGFloat, width: CGFloat, baseline: CGFloat) {
            context.saveGState()
            if let color { context.setFillColor(color) }
            for (glyph, position) in zip(glyphs, positions) {
                var place = CGAffineTransform(translationX: position.x, y: position.y)
                if let path = CTFontCreatePathForGlyph(font, glyph, &place) { context.addPath(path) }
            }
            context.fillPath()
            context.restoreGState()
            if let open = segment, CFEqual(open.font, font), abs(open.baseline - baseline) < 0.01, abs(open.x + open.width - x) < 0.5 {
                segment = (open.text + piece, open.font, open.x, open.width + width, open.baseline)
            } else {
                flush()
                segment = (piece, font, x, width, baseline)
            }
        }
        for run in CTLineGetGlyphRuns(placed.line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            if let cluster = placedCluster(run, origin: origin) {
                outline(cluster.cluster.glyphs, at: cluster.positions, font: cluster.font, color: cluster.color, text: cluster.cluster.text,
                        x: cluster.base.x, width: cluster.width, baseline: cluster.base.y)
            } else if attributes[NSAttributedString.Key.graphiteColor] != nil {
                continue  // i caratteri di un gruppo dopo il primo: spazio nullo, niente da disegnare
            } else if let piece = reorderingText(of: run, in: placed, text: text) {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let font = attributes[kCTFontAttributeName] as! CTFont
                let shift = (attributes[kCTBaselineOffsetAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
                let placedPositions = positions.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y + shift) }
                let color = attributes[kCTForegroundColorAttributeName].map { $0 as! CGColor } ?? CGColor(gray: 0, alpha: 1)
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
                outline(glyphs, at: placedPositions, font: font, color: color, text: piece,
                        x: placedPositions.first?.x ?? origin.x, width: width, baseline: origin.y + shift)
            } else {
                flush()
                context.textMatrix = textMatrix
                context.textPosition = origin
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
            }
        }
        flush()
    }
}

private extension NSString {
    /// Le unità UTF-16 della stringa.
    var utf16Units: [unichar] {
        var units = [unichar](repeating: 0, count: length)
        getCharacters(&units, range: NSRange(location: 0, length: length))
        return units
    }
}
