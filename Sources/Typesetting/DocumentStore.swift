import AppKit

/// Il deposito del documento vivo: il testo con i suoi attributi, tenuto per paragrafi del corpo, ciascuno con
/// un'identità che resta la stessa mentre lo si modifica.
///
/// Verso l'esterno è un testo con attributi come gli altri (una sottoclasse di `NSMutableAttributedString`), con
/// le stesse posizioni dei caratteri: la composizione, gli elenchi, gli stili e l'ispettore lo usano senza
/// cambiare. Ogni modifica passa dalle due operazioni elementari di un testo modificabile, sostituire caratteri
/// e fissare attributi, come in ogni testo modificabile di macOS.
///
/// Un paragrafo del corpo finisce a un a capo che non fa parte di una nota (vedi `TextStyling.bodyParagraph`);
/// dopo l'ultimo a capo (o in un testo vuoto) c'è sempre un paragrafo finale vuoto, anche lui con la sua identità.
public final class DocumentStore: NSMutableAttributedString {
    /// L'identità di un paragrafo: non cambia scrivendoci dentro, né spezzandolo (la conserva la parte che contiene
    /// più del testo di prima), né unendogli il paragrafo seguente.
    public struct ParagraphID: Hashable, Sendable, CustomStringConvertible {
        public let value: UInt64
        public let persistent: UUID
        public var description: String { "¶\(value)" }
    }

    private struct Paragraph {
        var id: ParagraphID
        var text: NSMutableAttributedString
    }

    private var paragraphs: [Paragraph] = []
    /// La posizione del primo carattere di ogni paragrafo.
    private var starts: [Int] = []
    /// Tutto il testo, tenuto aggiornato a ogni modifica.
    private let contents = NSMutableString()
    private var nextID: UInt64 = 1
    /// Le impostazioni del documento (pagina, lingua, stili, Liste…), senza il contenuto.
    public var settings = Document()

    /// Una modifica elementare, come la riceve chi osserva il deposito (l'editor, per sapere che cosa è cambiato).
    public enum Edit {
        case replaced(NSRange, NSAttributedString)
        case attributes([NSAttributedString.Key: Any]?, NSRange)
    }

    /// Chiamato dopo ogni modifica elementare, anche quelle fatte annullando o rifacendo.
    public var onEdit: ((Edit) -> Void)?
    /// Chiamato alla fine di un annullamento o di un ripristino: con i caratteri toccati, e la selezione da rimettere se il
    /// passo ne ricordava una (i passi dei comandi; quelli della scrittura no).
    public var onRevert: ((NSRange, NSRange?) -> Void)?
    /// La selezione in corso, che il passo inverso ricorda: Ripeti la rimette.
    public var currentSelection: (() -> NSRange)?

    public override init() {
        super.init()
        paragraphs = [Paragraph(id: makeID(), text: NSMutableAttributedString())]
        starts = [0]
    }

    /// Un deposito con il testo dato.
    public convenience init(text: NSAttributedString, emptyParagraphID: UUID? = nil, identifyFloats: Bool = false) {
        self.init()
        let source = NSMutableAttributedString(attributedString: text)
        if identifyFloats { FloatingIdentity.identifyMissing(in: source) }
        replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        for index in paragraphs.indices {
            let start = starts[index]
            let identity: UUID?
            if start < source.length {
                identity = (source.attribute(.paragraphIdentity, at: start, effectiveRange: nil) as? String).flatMap(UUID.init(uuidString:))
            } else if source.length > 0 {
                identity = (source.attribute(.finalParagraphIdentity, at: source.length - 1, effectiveRange: nil) as? String).flatMap(UUID.init(uuidString:))
            } else {
                identity = emptyParagraphID
            }
            if let identity { paragraphs[index].id = ParagraphID(value: paragraphs[index].id.value, persistent: identity) }
        }
    }

    /// Un deposito con il contenuto e le impostazioni di un documento.
    public convenience init(document: Document) {
        self.init(text: document.attributedString().text, emptyParagraphID: document.flatParagraphs.first?.paragraph.id, identifyFloats: true)
        settings = document.settingsOnly
    }

    /// Il contenuto nella forma del modello, per salvarlo.
    public var document: Document { Document(attributedString: self, settings: settings) }

    public required init?(coder: NSCoder) { fatalError("init(coder:) non è usato") }

    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("il deposito non si legge dagli appunti")
    }

    private func makeID(persistent: UUID = UUID()) -> ParagraphID {
        defer { nextID += 1 }
        return ParagraphID(value: nextID, persistent: persistent)
    }

    // MARK: Paragrafi

    /// Le identità dei paragrafi, nell'ordine del testo.
    public var paragraphIDs: [ParagraphID] { paragraphs.map(\.id) }

    /// Gli intervalli dei paragrafi con la loro identità, nell'ordine del testo (compreso il paragrafo finale vuoto):
    /// serve a chi compone senza leggere il deposito, per riconoscere i tratti delle Liste.
    public var paragraphSpans: [(range: NSRange, id: ParagraphID)] {
        paragraphs.indices.map { index in (NSRange(location: starts[index], length: paragraphs[index].text.length), paragraphs[index].id) }
    }

    /// Una copia indipendente del testo con le identità dei paragrafi, per comporre il PDF o stampare senza leggere il
    /// deposito (che può cambiare mentre il pannello di salvataggio è aperto).
    public var identifiedCopy: NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: self)
        for span in paragraphSpans {
            if span.range.length > 0 {
                copy.addAttribute(.paragraphIdentity, value: span.id.persistent.uuidString, range: NSRange(location: span.range.location, length: 1))
            } else if span.range.location > 0 {
                copy.addAttribute(.finalParagraphIdentity, value: span.id.persistent.uuidString, range: NSRange(location: span.range.location - 1, length: 1))
            }
        }
        return copy
    }

    /// Il frammento degli appunti porta le identità dei soli capoversi interamente selezionati.
    public func identifiedFragment(in range: NSRange) -> NSAttributedString {
        let fragment = NSMutableAttributedString(attributedString: attributedSubstring(from: range))
        let end = NSMaxRange(range)
        for index in paragraphIndex(at: range.location)..<paragraphs.count {
            let start = starts[index], length = paragraphs[index].text.length
            if start >= end { break }
            if length > 0, start >= range.location, start + length <= end {
                fragment.addAttribute(.paragraphIdentity, value: paragraphs[index].id.persistent.uuidString,
                                      range: NSRange(location: start - range.location, length: 1))
            }
        }
        return fragment
    }

    /// I caratteri di un paragrafo, a capo finale compreso; `nil` se non c'è più.
    public func range(of id: ParagraphID) -> NSRange? {
        guard let index = paragraphs.firstIndex(where: { $0.id == id }) else { return nil }
        return NSRange(location: starts[index], length: paragraphs[index].text.length)
    }

    /// Il paragrafo che contiene una posizione (dopo l'ultimo carattere: il paragrafo finale).
    public func paragraphID(at location: Int) -> ParagraphID { paragraphs[paragraphIndex(at: location)].id }

    /// Dove mettere un capoverso rispetto a un altro.
    public enum ParagraphMovePosition { case before, after }

    /// Sposta un capoverso intero prima o dopo un altro, conservando testo, attributi e identità. Restituisce la sua nuova
    /// posizione, o `nil` se il movimento non è possibile o non cambia nulla. I capoversi vuoti finali non si trascinano.
    /// Con i ritorni: un capoverso messo davanti al primo che torna a una sezione esterna torna lui al suo posto; uno che
    /// tornava, portato via, lascia il ritorno a quello che lo seguiva (il resto del testo resta alla sezione esterna).
    @discardableResult
    public func moveParagraph(_ source: ParagraphID, _ position: ParagraphMovePosition, _ target: ParagraphID) -> NSRange? {
        guard source != target, let sourceIndex = paragraphs.firstIndex(where: { $0.id == source }),
              let targetIndex = paragraphs.firstIndex(where: { $0.id == target }),
              paragraphs[sourceIndex].text.length > 0, paragraphs[targetIndex].text.length > 0 else { return nil }
        let destination = position == .before ? targetIndex : targetIndex + 1
        let inherits = position == .before ? effectiveReturn(of: target) : nil
        let stays = destination == sourceIndex || destination == sourceIndex + 1
        if stays {
            // Già lì nel testo: cambia solo a che sezione appartiene. Davanti al primo che torna, torna lui; subito dopo
            // l'ultimo capoverso di una sezione interna, entra in lei (il ritorno passa al capoverso seguente).
            if let inherits, effectiveReturn(of: source) == nil {
                setReturn(inherits, on: source)
            } else if position == .after, effectiveReturn(of: source) != nil {
                handOverReturn(from: source)
            } else {
                return nil
            }
            SectionEditing.normalize(self)
            return range(of: source)
        }
        handOverReturn(from: source)
        guard moveBlock(sourceIndex..<(sourceIndex + 1), to: destination) != nil else { return nil }
        if let inherits { setReturn(inherits, on: source) }
        SectionEditing.normalize(self)
        return range(of: source)
    }

    /// Sposta un capoverso subito dopo la sezione del titolo dato, al livello della sezione che la contiene (o fuori da
    /// ogni sezione): il capoverso torna lì.
    @discardableResult
    public func moveParagraph(_ source: ParagraphID, afterSection title: ParagraphID) -> NSRange? {
        let all = SectionEditing.titles(in: self)
        guard source != title, let section = all.first(where: { $0.range.length > 0 && paragraphID(at: $0.range.location) == title }),
              let sourceIndex = paragraphs.firstIndex(where: { $0.id == source }), paragraphs[sourceIndex].text.length > 0,
              !all.contains(where: { $0.range.length > 0 && paragraphID(at: $0.range.location) == source }) else { return nil }
        let span = SectionEditing.range(of: section, in: self)
        let owner = SectionEditing.enclosing(in: self, at: section.range.location).dropLast().last?.mark.id ?? ""
        let end = NSMaxRange(span) == length && paragraphs.last?.text.length ?? 0 > 0 ? paragraphs.count : paragraphIndex(at: NSMaxRange(span))
        if end != sourceIndex + 1 && end != sourceIndex {
            handOverReturn(from: source)
            guard moveBlock(sourceIndex..<(sourceIndex + 1), to: end) != nil else { return nil }
        } else if effectiveReturn(of: source) == owner {
            return nil
        }
        setReturn(owner, on: source)
        SectionEditing.normalize(self)
        return range(of: source)
    }

    /// Il ritorno che conta sul capoverso dato: la sezione a cui torna (vuoto: fuori da ogni sezione), o `nil`.
    private func effectiveReturn(of id: ParagraphID) -> String? {
        guard let range = range(of: id) else { return nil }
        for case .back(let back, let target) in SectionEditing.structure(in: self).events where back.location == range.location && back.length > 0 {
            return target
        }
        return nil
    }

    private func setReturn(_ target: String?, on id: ParagraphID) {
        guard let range = range(of: id), range.length > 0 else { return }
        if let target { addAttribute(.sectionReturn, value: target, range: range) } else { removeAttribute(.sectionReturn, range: range) }
    }

    /// Prima di portare via un capoverso che torna: il ritorno passa al capoverso che lo seguiva, se non è un titolo.
    private func handOverReturn(from id: ParagraphID) {
        guard let range = range(of: id), range.length > 0, let mark = attribute(.sectionReturn, at: range.location, effectiveRange: nil) as? String,
              let index = paragraphs.firstIndex(where: { $0.id == id }) else { return }
        setReturn(nil, on: id)
        guard index + 1 < paragraphs.count, let next = self.range(of: paragraphs[index + 1].id), next.length > 0,
              attribute(.sectionTitle, at: next.location, effectiveRange: nil) == nil,
              attribute(.sectionReturn, at: next.location, effectiveRange: nil) == nil else { return }
        addAttribute(.sectionReturn, value: mark, range: next)
    }

    /// Dove mettere una sezione rispetto a un'altra: come sorella, prima o dopo, oppure come ultima sezione interna.
    public enum SectionMovePosition { case before, after, inside }

    /// Sposta una sezione con tutto il suo contenuto, conservando testo, attributi e identità dei capoversi. Prima o dopo
    /// diventa sorella della destinazione; dentro ne diventa l'ultima sezione interna. Non può finire dentro sé stessa.
    @discardableResult
    public func moveSection(_ source: ParagraphID, _ position: SectionMovePosition, _ target: ParagraphID) -> NSRange? {
        let all = SectionEditing.titles(in: self)
        guard source != target, let sourceTitle = all.first(where: { $0.range.length > 0 && paragraphID(at: $0.range.location) == source }),
              let targetTitle = all.first(where: { $0.range.length > 0 && paragraphID(at: $0.range.location) == target }) else { return nil }
        let sourceSpan = SectionEditing.range(of: sourceTitle, in: self)
        guard !NSLocationInRange(targetTitle.range.location, sourceSpan) else { return nil }
        // Alla fine del testo, se non c'è un paragrafo finale vuoto, il confine è dopo l'ultimo paragrafo, non prima.
        func boundary(at end: Int) -> Int {
            end == length && paragraphs.last?.text.length ?? 0 > 0 ? paragraphs.count : paragraphIndex(at: end)
        }
        let sourceStart = paragraphIndex(at: sourceSpan.location)
        let sourceEnd = boundary(at: NSMaxRange(sourceSpan))
        let targetSpan = SectionEditing.range(of: targetTitle, in: self)
        let destination = switch position {
        case .before: paragraphIndex(at: targetSpan.location)
        case .after, .inside: boundary(at: NSMaxRange(targetSpan))
        }
        let newDepth = targetTitle.depth + (position == .inside ? 1 : 0)
        let delta = newDepth - sourceTitle.depth
        var depths: [ParagraphID: Int] = [:]
        if delta != 0 {
            for title in all where title.range.length > 0 && NSLocationInRange(title.range.location, sourceSpan) {
                depths[paragraphID(at: title.range.location)] = title.depth + delta
            }
        }
        guard moveBlock(sourceStart..<sourceEnd, to: destination, sectionDepths: depths) != nil else { return nil }
        // Profondità, livello di paragrafazione e stile dei titoli si allineano nello stesso passo di Annulla.
        SectionEditing.normalize(self)
        return range(of: source)
    }

    /// Sposta una sezione con tutto il suo contenuto subito prima di un capoverso del corpo: diventa sezione interna di
    /// quella in cui cade il capoverso, e il capoverso, con quelli che lo seguono, resta lì (torna alla sua sezione dopo
    /// quella spostata).
    @discardableResult
    public func moveSection(_ source: ParagraphID, beforeParagraph target: ParagraphID) -> NSRange? {
        let all = SectionEditing.titles(in: self)
        guard source != target, let sourceTitle = all.first(where: { $0.range.length > 0 && paragraphID(at: $0.range.location) == source }),
              let targetRange = range(of: target), targetRange.length > 0,
              !all.contains(where: { $0.range.location == targetRange.location && $0.range.length > 0 }) else { return nil }
        let sourceSpan = SectionEditing.range(of: sourceTitle, in: self)
        guard !NSLocationInRange(targetRange.location, sourceSpan) else { return nil }
        let owners = SectionEditing.enclosing(in: self, at: targetRange.location)
        let newDepth = owners.count + 1
        let delta = newDepth - sourceTitle.depth
        var depths: [ParagraphID: Int] = [:]
        if delta != 0 {
            for title in all where title.range.length > 0 && NSLocationInRange(title.range.location, sourceSpan) {
                depths[paragraphID(at: title.range.location)] = title.depth + delta
            }
        }
        let start = paragraphIndex(at: sourceSpan.location)
        let end = NSMaxRange(sourceSpan) == length && paragraphs.last?.text.length ?? 0 > 0 ? paragraphs.count : paragraphIndex(at: NSMaxRange(sourceSpan))
        guard moveBlock(start..<end, to: paragraphIndex(at: targetRange.location), sectionDepths: depths) != nil else { return nil }
        setReturn(owners.last?.mark.id ?? "", on: target)
        SectionEditing.normalize(self)
        return range(of: source)
    }

    /// Cambia il foglio degli stili come parte della modifica in corso: Annulla lo rimette com'era insieme al testo.
    public func replaceStyles(_ sheet: StyleSheet) {
        guard sheet != settings.styles else { return }
        let old = settings.styles
        settings.styles = sheet
        record(Change(first: 0, count: 0, paragraphs: [], styles: old))
    }

    /// Riordina una sequenza intera di paragrafi. `destination` è un indice nel testo di prima; se `sectionDepths` contiene
    /// dei titoli spostati, il loro segno riceve la nuova profondità. Livello e stile li allinea poi `SectionEditing.normalize`.
    private func moveBlock(_ source: Range<Int>, to insertion: Int, sectionDepths: [ParagraphID: Int] = [:]) -> NSRange? {
        guard !source.isEmpty, source.lowerBound >= 0, source.upperBound <= paragraphs.count,
              insertion >= 0, insertion <= paragraphs.count,
              insertion <= source.lowerBound || insertion >= source.upperBound else { return nil }
        var destination = insertion
        if source.upperBound <= insertion { destination -= source.count }
        guard destination != source.lowerBound || !sectionDepths.isEmpty else { return nil }

        let window = min(source.lowerBound, destination)..<max(source.upperBound, destination + source.count)
        let before = snapshot(window)
        let characterStart = starts[window.lowerBound]
        let oldLength = paragraphs[window].reduce(0) { $0 + $1.text.length }
        let sourceID = paragraphs[source.lowerBound].id
        let moved = Array(paragraphs[source])
        paragraphs.removeSubrange(source)
        paragraphs.insert(contentsOf: moved, at: destination)
        for index in paragraphs.indices {
            guard let depth = sectionDepths[paragraphs[index].id], paragraphs[index].text.length > 0,
                  let encoded = paragraphs[index].text.attribute(.sectionTitle, at: 0, effectiveRange: nil) as? String,
                  var mark = SectionMark(encoded: encoded) else { continue }
            mark.depth = depth
            paragraphs[index].text.addAttribute(.sectionTitle, value: mark.encoded, range: NSRange(location: 0, length: paragraphs[index].text.length))
        }

        // Un capoverso che lascia l'ultimo posto acquista l'a capo; quello che lo raggiunge lo cede. Gli attributi del
        // nuovo a capo sono quelli del capoverso, ma non fanno entrare la riga in una nota o in un campo.
        for index in paragraphs.indices {
            let paragraph = paragraphs[index]
            guard paragraph.text.length > 0 else { continue }
            let last = paragraph.text.length - 1
            let endsWithTerminator = TextStyling.isLineTerminator((paragraph.text.string as NSString).character(at: last))
                && paragraph.text.attribute(.footnote, at: last, effectiveRange: nil) == nil
            if index < paragraphs.count - 1, !endsWithTerminator {
                var attributes = paragraph.text.attributes(at: last, effectiveRange: nil)
                for key in [NSAttributedString.Key.footnote, .floatImage, .inlineImage, .field] { attributes[key] = nil }
                paragraph.text.append(NSAttributedString(string: "\n", attributes: attributes))
            } else if index == paragraphs.count - 1, endsWithTerminator {
                paragraph.text.deleteCharacters(in: NSRange(location: last, length: 1))
            }
        }
        let replacement = NSMutableAttributedString()
        for paragraph in paragraphs[window] { replacement.append(paragraph.text) }
        contents.replaceCharacters(in: NSRange(location: characterStart, length: oldLength), with: replacement.string)
        cachedString = nil
        recomputeStarts(from: window.lowerBound)
        record(Change(first: window.lowerBound, count: window.count, paragraphs: before))
        onEdit?(.replaced(NSRange(location: characterStart, length: oldLength), replacement))
        return range(of: sourceID)
    }

    /// L'indice del paragrafo che contiene `location`. Una posizione all'inizio di un paragrafo appartiene a quel
    /// paragrafo; la posizione dopo l'ultimo carattere appartiene all'ultimo.
    private func paragraphIndex(at location: Int) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= location { low = middle } else { high = middle - 1 }
        }
        return low
    }

    // MARK: Le primitive di un testo con attributi

    /// Il testo come stringa Swift. La conversione da `NSMutableString` copia tutto il testo: la si fa una volta sola e la
    /// si tiene finché il testo non cambia (molte funzioni chiedono `.string` per ogni paragrafo o oggetto, e con un
    /// documento di qualche decina di migliaia di caratteri la copia ripetuta rallentava ogni comando).
    public override var string: String {
        if let cachedString { return cachedString }
        let copy = contents as String
        cachedString = copy
        return copy
    }
    private var cachedString: String?

    public override var length: Int { contents.length }

    public override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        let index = paragraphIndex(at: location)
        let paragraph = paragraphs[index]
        var local = NSRange(location: 0, length: 0)
        let result = paragraph.text.attributes(at: location - starts[index], effectiveRange: &local)
        // Il tratto si ferma al confine del paragrafo: è permesso (il tratto «effettivo» non è per forza il più lungo).
        range?.pointee = NSRange(location: local.location + starts[index], length: local.length)
        return result
    }

    public override func replaceCharacters(in range: NSRange, with string: String) {
        // I caratteri nuovi prendono gli attributi del primo carattere sostituito; se non se ne sostituisce nessuno,
        // del carattere che precede, o altrimenti di quello che segue (come un testo con attributi di Apple).
        let source = range.length > 0 ? range.location : (range.location > 0 ? range.location - 1 : range.location)
        let attributes = source < length ? self.attributes(at: source, effectiveRange: nil) : [:]
        replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: attributes))
    }

    public override func replaceCharacters(in range: NSRange, with text: NSAttributedString) {
        precondition(NSMaxRange(range) <= length, "intervallo fuori dal testo")
        let window = window(for: range)
        let before = snapshot(window)
        let windowStart = starts[window.lowerBound]
        let combined = NSMutableAttributedString()
        for index in window { combined.append(paragraphs[index].text) }
        let local = NSRange(location: range.location - windowStart, length: range.length)
        combined.replaceCharacters(in: local, with: text)
        // Da dove viene ogni carattere nuovo della finestra: prima della modifica, dallo stesso posto; dopo, spostato;
        // il testo inserito da nessun paragrafo.
        let delta = text.length - range.length
        let count = resegment(window: window, combined: combined, origin: { position in
            if position < local.location { return position }
            if position >= local.location + text.length { return position - delta }
            return nil
        }, destination: { position in
            if position < local.location { return position }
            if position >= NSMaxRange(local) { return position + delta }
            return nil
        })
        contents.replaceCharacters(in: range, with: text.string)
        cachedString = nil
        record(Change(first: window.lowerBound, count: count, paragraphs: before))
        onEdit?(.replaced(range, text))
    }

    public override func setAttributes(_ attributes: [NSAttributedString.Key: Any]?, range: NSRange) {
        precondition(NSMaxRange(range) <= length, "intervallo fuori dal testo")
        guard range.length > 0 else { return }
        let first = paragraphIndex(at: range.location), last = paragraphIndex(at: NSMaxRange(range) - 1)
        let window = first..<min(last + 2, paragraphs.count)
        let before = snapshot(window)
        var count = window.count
        for index in first...last {
            let start = starts[index]
            let slice = NSIntersectionRange(range, NSRange(location: start, length: paragraphs[index].text.length))
            paragraphs[index].text.setAttributes(attributes, range: NSRange(location: slice.location - start, length: slice.length))
        }
        // Un a capo che entra in una nota o ne esce cambia i confini dei paragrafi.
        let string = contents
        if (range.location..<NSMaxRange(range)).contains(where: { TextStyling.isLineTerminator(string.character(at: $0)) }) {
            let combined = NSMutableAttributedString()
            for index in window { combined.append(paragraphs[index].text) }
            count = resegment(window: window, combined: combined, origin: { $0 }, destination: { $0 })
        }
        record(Change(first: window.lowerBound, count: count, paragraphs: before))
        onEdit?(.attributes(attributes, range))
    }

    // MARK: Confini dei paragrafi

    /// I paragrafi toccati da una modifica, più quello che segue: togliendo un a capo, i due si uniscono.
    private func window(for range: NSRange) -> Range<Int> {
        let first = paragraphIndex(at: range.location)
        let last = range.length > 0 ? paragraphIndex(at: NSMaxRange(range) - 1) : first
        return first..<min(last + 2, paragraphs.count)
    }

    /// Divide il testo della finestra in paragrafi del corpo e li mette al posto di quelli della finestra.
    ///
    /// Le identità: un paragrafo vecchio la passa al paragrafo nuovo in cui è finito il suo primo carattere (così,
    /// spezzando, la tiene la parte con l'inizio; unendo, il primo dei due). Se il primo carattere è stato cancellato,
    /// la passa al paragrafo nuovo che ha preso più caratteri suoi. `origin` dà, per ogni posizione nuova nella
    /// finestra, quella vecchia (`nil` per il testo inserito); `destination` fa il contrario (`nil` se cancellato).
    /// - Returns: quanti paragrafi occupano ora il posto della finestra.
    private func resegment(window: Range<Int>, combined: NSMutableAttributedString, origin: (Int) -> Int?, destination: (Int) -> Int?) -> Int {
        let windowStart = starts[window.lowerBound]
        let reachesEnd = window.upperBound == paragraphs.count
        // I confini vecchi, nella finestra: servono a sapere da quale paragrafo veniva un carattere.
        let oldBounds = window.map { starts[$0] - windowStart }
        func oldParagraph(_ position: Int) -> Int {
            var result = 0
            while result + 1 < oldBounds.count, oldBounds[result + 1] <= position { result += 1 }
            return result
        }

        // I paragrafi nuovi: ciascuno finisce dopo un a capo del corpo («\r\n» conta come uno).
        let string = combined.string as NSString
        var segments: [NSRange] = []
        var start = 0, position = 0
        while position < string.length {
            let character = string.character(at: position)
            if TextStyling.isLineTerminator(character), combined.attribute(.footnote, at: position, effectiveRange: nil) == nil {
                var end = position + 1
                if character == 0x0D, end < string.length, string.character(at: end) == 0x0A { end += 1 }
                segments.append(NSRange(location: start, length: end - start))
                start = end
                position = end
            } else {
                position += 1
            }
        }
        // Il resto: se la finestra arriva in fondo al testo è il paragrafo finale, anche se vuoto; altrimenti non
        // dovrebbe esserci (la finestra finisce con un a capo del corpo), ma se ci fosse resta un paragrafo.
        if start < string.length || reachesEnd { segments.append(NSRange(location: start, length: string.length - start)) }

        func segment(containing position: Int) -> Int? {
            segments.firstIndex { NSLocationInRange(position, $0) }
        }
        var ids: [ParagraphID?] = Array(repeating: nil, count: segments.count)
        var placed = Array(repeating: false, count: oldBounds.count)
        // Prima l'inizio di ogni paragrafo vecchio, nell'ordine.
        for (old, bound) in oldBounds.enumerated() where paragraphs[window.lowerBound + old].text.length > 0 {
            if let position = destination(bound), let target = segment(containing: position), ids[target] == nil {
                ids[target] = paragraphs[window.lowerBound + old].id
                placed[old] = true
            }
        }
        // Poi, per i paragrafi vecchi senza più l'inizio, la maggioranza dei caratteri.
        for (index, range) in segments.enumerated() where ids[index] == nil {
            var count: [Int: Int] = [:]
            for position in range.location..<NSMaxRange(range) {
                if let old = origin(position) { count[oldParagraph(old), default: 0] += 1 }
            }
            if let best = count.filter({ !placed[$0.key] }).max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
                ids[index] = paragraphs[window.lowerBound + best.key].id
                placed[best.key] = true
            }
        }
        // Il paragrafo finale di prima, se era vuoto, non ha caratteri: la sua identità va all'ultimo paragrafo nuovo
        // rimasto senza (scrivendo nel paragrafo finale, è lui).
        if reachesEnd, paragraphs[window.upperBound - 1].text.length == 0, !placed[window.count - 1],
           let lastWithout = ids.lastIndex(where: { $0 == nil }) {
            let segment = segments[lastWithout]
            if segment.length == 0 || combined.attribute(.paragraphIdentity, at: segment.location, effectiveRange: nil) == nil {
                ids[lastWithout] = paragraphs[window.upperBound - 1].id
            }
        }

        let replacements = segments.enumerated().map { index, segment in
            let text = NSMutableAttributedString(attributedString: combined.attributedSubstring(from: segment))
            var incoming: UUID?
            if text.length > 0, origin(segment.location) == nil {
                incoming = (text.attribute(.paragraphIdentity, at: 0, effectiveRange: nil) as? String).flatMap(UUID.init(uuidString:))
            }
            for key in [NSAttributedString.Key.paragraphIdentity, .finalParagraphIdentity] {
                text.removeAttribute(key, range: NSRange(location: 0, length: text.length))
            }
            return Paragraph(id: ids[index] ?? incoming.map { makeID(persistent: $0) } ?? makeID(), text: text)
        }
        paragraphs.replaceSubrange(window, with: replacements)
        recomputeStarts(from: window.lowerBound)
        return replacements.count
    }

    /// Le posizioni d'inizio, dal paragrafo `first` in poi.
    private func recomputeStarts(from first: Int) {
        var offset = first < starts.count ? starts[first] : contents.length
        if first == 0 { offset = 0 }
        starts.removeSubrange(first...)
        for index in first..<paragraphs.count {
            starts.append(offset)
            offset += paragraphs[index].text.length
        }
    }

    // MARK: Annullamento

    /// Come tornare indietro da una modifica elementare: i paragrafi che ora occupano le posizioni da `first` (sono
    /// `count`) vanno sostituiti con `paragraphs`, copie di quelli di prima, con le loro identità.
    private struct Change {
        var first: Int
        var count: Int
        var paragraphs: [Paragraph]
        /// Il foglio degli stili prima del comando, quando questo lo ha cambiato; da annullare con il testo.
        var styles: StyleSheet? = nil
    }

    /// Un passo di annullamento: le modifiche elementari, nell'ordine in cui sono state fatte.
    private final class Step {
        var changes: [Change] = []
        /// La selezione da rimettere quando il passo si annulla (o si rifà); `nil` per i passi della scrittura.
        var selection: NSRange?
    }

    /// Il gestore dell'annullamento a cui il deposito affida i suoi passi; senza, le modifiche non si registrano.
    public weak var undoManager: UndoManager?
    /// Il passo che sta crescendo: i tasti scritti di seguito vi si aggiungono finché non lo si chiude.
    private var openStep: Step?
    private var isReverting = false
    private var undoSuppressed = 0

    /// Vero mentre si annulla o si rifà un passo.
    public var isUndoingOrRedoing: Bool { isReverting }

    /// Modifiche che non diventano passi da annullare: il testo caricato, gli attributi che si ricalcolano da sé.
    public func withoutUndo(_ body: () -> Void) {
        undoSuppressed += 1
        defer { undoSuppressed -= 1 }
        body()
    }

    /// I caratteri toccati dall'ultimo annullamento o ripristino: l'editor ci mette il cursore.
    public private(set) var lastRevertedRange: NSRange?
    /// Vero se l'ultimo annullamento o ripristino ha aggiunto o tolto testo; falso se ha cambiato solo l'aspetto.
    public private(set) var lastRevertChangedLength = false
    /// Vero se ha anche ripristinato il foglio degli stili: l'editor deve sincronizzare la propria copia.
    public private(set) var lastRevertChangedStyles = false

    /// Chiude il passo che sta crescendo: la modifica seguente ne aprirà uno nuovo (come quando si sposta il cursore,
    /// si passa dallo scrivere al cancellare, o si dà un comando).
    public func breakUndoCoalescing() { openStep = nil }

    /// Il passo nato dopo che ne erano stati registrati `count` (un comando) ricorda la selezione che c'era prima: Annulla
    /// la rimette.
    public func rememberSelection(_ range: NSRange, forStepsAfter count: Int) {
        guard registeredSteps > count, let openStep, openStep.selection == nil else { return }
        openStep.selection = range
    }

    private func snapshot(_ window: Range<Int>) -> [Paragraph] {
        guard undoManager != nil, !isReverting, undoSuppressed == 0 else { return [] }
        return window.map { Paragraph(id: paragraphs[$0].id, text: NSMutableAttributedString(attributedString: paragraphs[$0].text)) }
    }

    private func record(_ change: Change) {
        guard let undoManager, !isReverting, undoSuppressed == 0 else { return }
        // Una modifica che non ha cambiato nulla non diventa un passo da annullare.
        let current = paragraphs[change.first..<(change.first + change.count)]
        if change.styles == nil, current.count == change.paragraphs.count,
           zip(current, change.paragraphs).allSatisfy({ $0.id == $1.id && $0.text.isEqual(to: $1.text) }) { return }
        if let openStep {
            openStep.changes.append(change)
            return
        }
        let step = Step()
        step.changes = [change]
        openStep = step
        register(step, with: undoManager)
    }

    /// Il deposito si modifica dal thread principale, come l'editor che lo usa e il gestore dell'annullamento.
    /// Quanti passi il deposito ha registrato (annullamenti e ripristini compresi): l'editor dà un nome al passo solo
    /// se ne è nato uno, perché dare un nome apre un gruppo anche quando non c'è nulla da annullare.
    public private(set) var registeredSteps = 0

    private func register(_ step: Step, with undoManager: UndoManager) {
        registeredSteps += 1
        nonisolated(unsafe) let step = step
        nonisolated(unsafe) let store = self
        let manager = undoManager
        MainActor.assumeIsolated {
            manager.registerUndo(withTarget: store) { target in
                nonisolated(unsafe) let target = target
                target.revert(step)
            }
        }
    }

    /// Torna indietro di un passo (o lo rifà, se il passo viene da un annullamento) e registra il passo inverso.
    private func revert(_ step: Step) {
        openStep = nil
        isReverting = true
        defer { isReverting = false }
        let inverse = Step()
        // Il passo inverso di un comando ricorda la selezione di adesso, che Ripeti (o di nuovo Annulla) rimetterà.
        if step.selection != nil { inverse.selection = currentSelection?() }
        var changed: NSRange?
        var union: NSRange?
        let lengthBefore = length
        for change in step.changes.reversed() {
            let (undone, range) = apply(change)
            inverse.changes.append(undone)
            changed = range
            if range.length > 0 { union = union.map { NSUnionRange($0, range) } ?? range }
        }
        lastRevertChangedLength = length != lengthBefore
        lastRevertChangedStyles = step.changes.contains { $0.styles != nil }
        // Se è cambiato solo l'aspetto, le posizioni non si spostano: i caratteri toccati sono quelli di tutte le
        // modifiche del passo. Altrimenti conta l'ultima, dopo la quale va il cursore.
        if !lastRevertChangedLength, let union { changed = union }
        lastRevertedRange = changed
        if let undoManager { register(inverse, with: undoManager) }
        if let changed { onRevert?(changed, step.selection) }
    }

    /// Mette al loro posto i paragrafi di una modifica e restituisce la modifica che la disfa, con i caratteri toccati.
    private func apply(_ change: Change) -> (Change, NSRange) {
        let currentStyles = change.styles.map { _ in settings.styles }
        if let previous = change.styles { settings.styles = previous }
        let range = change.first..<(change.first + change.count)
        let characterStart = starts[change.first]
        let removed = Array(paragraphs[range])
        let removedLength = removed.reduce(0) { $0 + $1.text.length }
        paragraphs.replaceSubrange(range, with: change.paragraphs)
        recomputeStarts(from: change.first)
        let restoredText = NSMutableAttributedString()
        for paragraph in change.paragraphs { restoredText.append(paragraph.text) }
        let restored = restoredText.string as NSString
        let removedText = NSMutableAttributedString()
        for paragraph in removed { removedText.append(paragraph.text) }
        let removedString = removedText.string as NSString
        contents.replaceCharacters(in: NSRange(location: characterStart, length: removedLength), with: restored as String)
        cachedString = nil
        onEdit?(.replaced(NSRange(location: characterStart, length: removedLength), restoredText))
        // I caratteri cambiati davvero: senza la parte uguale all'inizio e alla fine dei paragrafi rimessi. Uguale vuol
        // dire anche con lo stesso aspetto: se è cambiato solo quello (uno stile, un corsivo), restano i caratteri che
        // l'hanno cambiato, e l'editor li seleziona.
        func same(_ restoredIndex: Int, _ removedIndex: Int) -> Bool {
            restored.character(at: restoredIndex) == removedString.character(at: removedIndex)
                && (restoredText.attributes(at: restoredIndex, effectiveRange: nil) as NSDictionary)
                    .isEqual(to: removedText.attributes(at: removedIndex, effectiveRange: nil))
        }
        var prefix = 0
        while prefix < restored.length, prefix < removedString.length, same(prefix, prefix) { prefix += 1 }
        var suffix = 0
        while suffix < restored.length - prefix, suffix < removedString.length - prefix,
              same(restored.length - 1 - suffix, removedString.length - 1 - suffix) { suffix += 1 }
        return (Change(first: change.first, count: change.paragraphs.count, paragraphs: removed, styles: currentStyles),
                NSRange(location: characterStart + prefix, length: restored.length - prefix - suffix))
    }

    // MARK: Controlli

    /// Verifica che la struttura interna sia coerente con il testo: paragrafi che finiscono agli a capo del corpo,
    /// posizioni giuste, identità diverse, paragrafo finale. Restituisce la descrizione del primo problema, o `nil`.
    public func structuralProblem() -> String? {
        var offset = 0
        var seen: Set<UUID> = []
        let joined = NSMutableString()
        for (index, paragraph) in paragraphs.enumerated() {
            if starts[index] != offset { return "il paragrafo \(index) comincia a \(starts[index]) invece che a \(offset)" }
            if !seen.insert(paragraph.id.persistent).inserted { return "identità ripetuta \(paragraph.id)" }
            let isLast = index == paragraphs.count - 1
            if paragraph.text.length == 0, !isLast { return "paragrafo vuoto in mezzo (\(index))" }
            if !isLast {
                let expected = TextStyling.bodyParagraph(in: self, at: offset).range
                if expected != NSRange(location: offset, length: paragraph.text.length) {
                    return "il paragrafo \(index) è \(NSRange(location: offset, length: paragraph.text.length)), il corpo dice \(expected)"
                }
            }
            joined.append(paragraph.text.string)
            offset += paragraph.text.length
        }
        if joined as String != contents as String { return "il testo dei paragrafi non coincide con il testo intero" }
        if TextStyling.hasEmptyFinalParagraph(self), paragraphs.last?.text.length != 0 { return "manca il paragrafo finale vuoto" }
        if !TextStyling.hasEmptyFinalParagraph(self), paragraphs.last?.text.length == 0, length > 0 { return "c'è un paragrafo finale vuoto di troppo" }
        return nil
    }
}

extension TextStyling {
    /// Il primo punto, a partire dall'inizio di `range` (tutto il testo se `nil`), in cui due testi differiscono per un
    /// carattere o per gli attributi; `nil` se coincidono. Testi di lunghezza diversa differiscono almeno alla fine
    /// del più corto.
    public static func firstDifference(_ a: NSAttributedString, _ b: NSAttributedString, in range: NSRange? = nil) -> Int? {
        let range = range ?? NSRange(location: 0, length: max(a.length, b.length))
        let common = min(NSMaxRange(range), a.length, b.length)
        let left = a.string as NSString, right = b.string as NSString
        var position = range.location
        while position < common {
            if left.character(at: position) != right.character(at: position) { return position }
            var runA = NSRange(location: 0, length: 0), runB = NSRange(location: 0, length: 0)
            let attributesA = a.attributes(at: position, effectiveRange: &runA), attributesB = b.attributes(at: position, effectiveRange: &runB)
            if !NSDictionary(dictionary: attributesA).isEqual(to: attributesB) { return position }
            // Fino alla fine del più corto dei due tratti gli attributi restano uguali: si controllano solo i caratteri.
            let end = min(NSMaxRange(runA), NSMaxRange(runB), common)
            position += 1
            while position < end {
                if left.character(at: position) != right.character(at: position) { return position }
                position += 1
            }
        }
        return common < NSMaxRange(range) && a.length != b.length ? common : nil
    }
}
