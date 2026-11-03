import AppKit

/// Le operazioni sulle sezioni nel testo piatto dell'editor (il deposito o un testo qualsiasi): leggere la struttura,
/// aprire una sezione al cursore, toglierla. Le sezioni stanno nei segni `.sectionTitle` dei titoli (vedi `SectionMark`).
public enum SectionEditing {
    /// Un titolo nel testo: il suo paragrafo, il suo segno e la profondità che ha davvero nell'albero.
    public struct Title: Equatable {
        public var range: NSRange
        public var mark: SectionMark
        public var depth: Int
    }

    /// Dove aprire una sezione nuova rispetto a quella in cui cade il titolo.
    public enum Level: Sendable {
        case inside, same, outside
    }

    /// Dove comincia la sezione di cui il paragrafo che comincia in `location` è il titolo; `.continuous` se non è un titolo.
    public static func start(in text: NSAttributedString, atParagraph location: Int) -> SectionStart {
        guard location < text.length else { return .continuous }
        return (text.attribute(.sectionTitle, at: location, effectiveRange: nil) as? String).flatMap(SectionMark.init(encoded:))?.start ?? .continuous
    }

    /// Vero se il paragrafo che comincia in `location` apre una sequenza di pagine: è il primo del documento, o il titolo
    /// di una sezione che comincia su una pagina nuova.
    public static func opensSequence(in text: NSAttributedString, atParagraph location: Int) -> Bool {
        location == 0 || start(in: text, atParagraph: location) != .continuous
    }

    /// Un avvenimento della struttura, in ordine nel testo: un titolo che apre una sezione, o un paragrafo che dopo una
    /// sezione interna torna a quella che la contiene (`target`; vuoto per il primo livello).
    public enum StructureEvent: Equatable {
        case title(Title)
        case back(range: NSRange, target: String)

        public var location: Int {
            switch self {
            case .title(let title): title.range.location
            case .back(let range, _): range.location
            }
        }
    }

    /// La struttura del testo: titoli e ritorni che contano, in ordine; e i paragrafi con un segno di ritorno che non
    /// conta (verso una sezione che non è aperta, senza nulla da chiudere, o su un titolo), da togliere.
    public static func structure(in text: NSAttributedString) -> (events: [StructureEvent], staleReturns: [NSRange]) {
        // I titoli candidati (anche quelli con un segno ripetuto, che non contano) e i ritorni, ciascuno col suo paragrafo.
        var candidates: [(range: NSRange, mark: SectionMark?, target: String?)] = []
        func collect(_ key: NSAttributedString.Key, _ finalKey: NSAttributedString.Key, _ make: @escaping (Any) -> (SectionMark?, String?)?) {
            // Si guardano solo i tratti segnati, non tutti i paragrafi: si legge a ogni movimento del cursore.
            var lastParagraph = -1
            text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, run, _ in
                guard value != nil else { return }
                var location = run.location
                while location < NSMaxRange(run) {
                    let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
                    if paragraph.location != lastParagraph, paragraph.location >= run.location || location == run.location,
                       let value = text.attribute(key, at: paragraph.location, effectiveRange: nil), let made = make(value) {
                        lastParagraph = paragraph.location
                        candidates.append((paragraph, made.0, made.1))
                    }
                    location = max(NSMaxRange(paragraph), location + 1)
                }
            }
            if text.length > 0, let value = text.attribute(finalKey, at: text.length - 1, effectiveRange: nil), let made = make(value) {
                let last = TextStyling.bodyParagraph(in: text, at: text.length - 1)
                if NSMaxRange(last.range) > last.contentsEnd { candidates.append((NSRange(location: text.length, length: 0), made.0, made.1)) }
            }
        }
        collect(.sectionTitle, .finalParagraphSection) { value in (value as? String).flatMap(SectionMark.init(encoded:)).map { ($0, nil) } }
        collect(.sectionReturn, .finalParagraphSectionReturn) { value in (value as? String).map { (nil, $0) } }
        // In ordine; sullo stesso paragrafo il titolo prima del ritorno.
        candidates.sort { $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.mark != nil && $1.mark == nil }

        var events: [StructureEvent] = []
        var stale: [NSRange] = []
        var open: [(depth: Int, id: String)] = []  // le profondità scritte e le identità delle sezioni aperte
        var seen: Set<String> = []
        var lastTitleLocation = -1
        for candidate in candidates {
            if let mark = candidate.mark {
                guard seen.insert(mark.id).inserted else { continue }
                while let last = open.last, last.depth >= mark.depth { open.removeLast() }
                open.append((mark.depth, mark.id))
                lastTitleLocation = candidate.range.location
                events.append(.title(Title(range: candidate.range, mark: mark, depth: open.count)))
            } else if let target = candidate.target {
                let closes: Int? = target.isEmpty ? (open.isEmpty ? nil : 0)
                    : open.lastIndex(where: { $0.id == target }).flatMap { $0 < open.count - 1 ? $0 + 1 : nil }
                if let keep = closes, candidate.range.location != lastTitleLocation {
                    open.removeLast(open.count - keep)
                    events.append(.back(range: candidate.range, target: target))
                } else {
                    stale.append(candidate.range)
                }
            }
        }
        return (events, stale)
    }

    /// I titoli del testo, in ordine, con la profondità vera; come nella ricostruzione dell'albero, un segno ripetuto
    /// non conta (quel paragrafo è testo della sezione), e un ritorno chiude le sezioni interne.
    public static func titles(in text: NSAttributedString) -> [Title] {
        structure(in: text).events.compactMap { if case .title(let title) = $0 { title } else { nil } }
    }

    // MARK: Il ritorno alla sezione esterna, a mano

    /// Il paragrafo che contiene `index`: il suo intervallo (vuoto, in fondo al testo, per l'ultimo paragrafo vuoto).
    private static func paragraph(in text: NSAttributedString, containing index: Int) -> NSRange {
        let atEnd = index >= text.length && (text.length == 0 || TextStyling.isLineTerminator((text.string as NSString).character(at: text.length - 1)))
        return atEnd ? NSRange(location: text.length, length: 0) : TextStyling.bodyParagraph(in: text, at: min(index, max(text.length - 1, 0))).range
    }

    /// Dove tornerebbe il paragrafo che contiene `index` con «Torna alla sezione esterna»: l'identità della sezione che
    /// contiene quella in cui sta (vuota: fuori da ogni sezione). `nil` se non si può: è un titolo, non sta in una
    /// sezione, o dopo di lui la sua sezione ha sezioni interne (salirebbero di livello).
    public static func returnTarget(in text: NSAttributedString, atParagraphContaining index: Int) -> String? {
        let paragraph = paragraph(in: text, containing: index)
        let all = titles(in: text)
        guard !all.contains(where: { $0.range.location == paragraph.location }) else { return nil }
        let chain = enclosing(in: text, at: paragraph.location)
        guard let inner = chain.last else { return nil }
        let end = NSMaxRange(range(of: inner, in: text))
        guard !all.contains(where: { $0.range.location > paragraph.location && $0.range.location < end }) else { return nil }
        return chain.count >= 2 ? chain[chain.count - 2].mark.id : ""
    }

    /// «Torna alla sezione esterna»: il paragrafo che contiene `index`, e quelli che lo seguono nella sua sezione, tornano a
    /// quella che la contiene. Vero se è cambiato qualcosa.
    @discardableResult
    public static func returnParagraph(in text: NSMutableAttributedString, containing index: Int) -> Bool {
        guard let target = returnTarget(in: text, atParagraphContaining: index) else { return false }
        let paragraph = paragraph(in: text, containing: index)
        if paragraph.length > 0 {
            text.addAttribute(.sectionReturn, value: target, range: paragraph)
        } else if text.length > 0 {
            text.addAttribute(.finalParagraphSectionReturn, value: target, range: NSRange(location: text.length - 1, length: 1))
        }
        normalize(text)
        return true
    }

    /// La sezione in cui entrerebbe il paragrafo che contiene `index` togliendo il suo ritorno: la più interna aperta
    /// subito prima di lui. `nil` se il paragrafo non torna.
    public static func joinTarget(in text: NSAttributedString, atParagraphContaining index: Int) -> Title? {
        let paragraph = paragraph(in: text, containing: index)
        guard paragraph.location > 0, structure(in: text).events.contains(where: {
            if case .back(let range, _) = $0 { range.location == paragraph.location } else { false }
        }) else { return nil }
        return enclosing(in: text, at: paragraph.location - 1).last
    }

    /// «Entra nella sezione precedente»: toglie il ritorno del paragrafo che contiene `index`; lui e quelli che lo seguono
    /// fino al titolo seguente entrano nella sezione che li precede. Vero se è cambiato qualcosa.
    @discardableResult
    public static func removeReturn(in text: NSMutableAttributedString, containing index: Int) -> Bool {
        guard joinTarget(in: text, atParagraphContaining: index) != nil else { return false }
        let paragraph = paragraph(in: text, containing: index)
        if paragraph.length > 0 {
            text.removeAttribute(.sectionReturn, range: paragraph)
        } else if text.length > 0 {
            text.removeAttribute(.finalParagraphSectionReturn, range: NSRange(location: text.length - 1, length: 1))
        }
        normalize(text)
        return true
    }

    /// Il paragrafo che comincia in `location`, se una sezione appena inserita prima di lui lo ha preso, torna a `owner`
    /// (vuota: fuori da ogni sezione): una sezione incollata porta solo il suo contenuto.
    public static func keepParagraph(at location: Int, in owner: String, text: NSMutableAttributedString) {
        guard location > 0, location < text.length else { return }
        let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
        guard paragraph.location == location, paragraph.length > 0,
              !titles(in: text).contains(where: { $0.range.location == location }) else { return }
        let current = enclosing(in: text, at: location).last?.mark.id ?? ""
        guard current != owner else { return }
        text.addAttribute(.sectionReturn, value: owner, range: paragraph)
        normalize(text)
    }

    /// Prima di togliere una sezione: i paragrafi che tornavano a lei tornano a quella che la conteneva (o fuori da ogni
    /// sezione), così il testo che stava dopo le sue interne non finisce dentro l'ultima.
    static func retargetReturns(to title: Title, in text: NSMutableAttributedString) {
        let owner = enclosing(in: text, at: title.range.location).dropLast().last?.mark.id ?? ""
        let all = NSRange(location: 0, length: text.length)
        for key in [NSAttributedString.Key.sectionReturn, .finalParagraphSectionReturn] {
            var changes: [NSRange] = []
            text.enumerateAttribute(key, in: all) { value, range, _ in
                if (value as? String) == title.mark.id { changes.append(range) }
            }
            for range in changes { text.addAttribute(key, value: owner, range: range) }
        }
    }

    /// Il testo del titolo di una sezione, senza le note e le intestazioni che vi sono ancorate né i campi.
    public static func titleText(of title: Title, in text: NSAttributedString) -> String {
        guard title.range.length > 0 else { return "" }
        var result = ""
        text.enumerateAttributes(in: title.range) { attributes, range, _ in
            guard attributes[.footnote] == nil, attributes[.field] == nil, attributes[.inlineImage] == nil else { return }
            result += (text.string as NSString).substring(with: range)
        }
        return result.replacingOccurrences(of: "\u{2028}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Il titolo del paragrafo che contiene `index`, se è il titolo di una sezione.
    public static func title(in text: NSAttributedString, atParagraphContaining index: Int) -> Title? {
        let paragraph = index >= text.length ? NSRange(location: text.length, length: 0) : TextStyling.bodyParagraph(in: text, at: index).range
        return titles(in: text).first { $0.range.location == paragraph.location }
    }

    /// Le sezioni che contengono il carattere `index`, dalla più esterna alla più interna (il titolo appartiene alla sua
    /// sezione).
    public static func enclosing(in text: NSAttributedString, at index: Int) -> [Title] {
        var open: [Title] = []
        for event in structure(in: text).events where event.location <= index {
            switch event {
            case .title(let title):
                while let last = open.last, last.depth >= title.depth { open.removeLast() }
                open.append(title)
            case .back(_, let target):
                if let keep = open.lastIndex(where: { $0.mark.id == target }) { open.removeLast(open.count - keep - 1) } else { open.removeAll() }
            }
        }
        return open
    }

    /// Apre una sezione al punto `index`: un titolo vuoto, prima del paragrafo se il punto ne è l'inizio, dopo se ne è
    /// la fine, altrimenti spezzando il paragrafo. Il testo che segue entra nella sezione nuova. Il ruolo è quello delle
    /// sorelle, poi delle sezioni che stanno sotto un genitore dello stesso ruolo (altrimenti «capitolo» al primo livello e
    /// «sezione» più dentro), lo stile
    /// del titolo quello degli altri titoli dello stesso ruolo (altrimenti «Titolo N», se c'è). Restituisce la posizione
    /// del titolo, dove mettere il cursore.
    @discardableResult
    public static func insertSection(in text: NSMutableAttributedString, at index: Int, level: Level, sheet: StyleSheet) -> Int {
        let index = min(max(index, 0), text.length)
        let paragraph = index >= text.length && (text.length == 0 || TextStyling.isLineTerminator((text.string as NSString).character(at: text.length - 1)))
            ? (range: NSRange(location: text.length, length: 0), contentsEnd: text.length)
            : TextStyling.bodyParagraph(in: text, at: index)
        let start = paragraph.range.location
        let hasTerminator = NSMaxRange(paragraph.range) > paragraph.contentsEnd

        // Dove va il titolo, e quanti a capo servono.
        let insertAt: Int, newlines: Int, titleIndex: Int
        if index == start {
            (insertAt, newlines, titleIndex) = (start, 1, start)
        } else if index == paragraph.contentsEnd, hasTerminator {
            (insertAt, newlines, titleIndex) = (NSMaxRange(paragraph.range), 1, NSMaxRange(paragraph.range))
        } else {
            (insertAt, newlines, titleIndex) = (index, 2, index + 1)
        }

        // La sezione in cui cade il titolo: quella del testo che lo precede.
        let titles = titles(in: text)
        let context = insertAt > 0 ? enclosing(in: text, at: insertAt - 1) : []
        let depth = switch level {
        case .inside: context.count + 1
        case .same: max(context.count, 1)
        case .outside: max(context.count - 1, 1)
        }
        // Il ruolo: quello delle sorelle (stesso genitore), poi di chi sta sotto un genitore dello stesso ruolo.
        let parent = depth >= 2 ? context[depth - 2].mark : nil
        var parents: [String: SectionMark?] = [:]
        var open: [Title] = []
        for title in titles {
            while let last = open.last, last.depth >= title.depth { open.removeLast() }
            parents[title.mark.id] = open.last?.mark
            open.append(title)
        }
        let peers = titles.filter { $0.depth == depth }
        let siblings = peers.filter { parents[$0.mark.id]??.id == parent?.id }
        let cousins = peers.filter { parents[$0.mark.id]??.role == parent?.role }
        let model = (siblings.last { $0.range.location < insertAt } ?? siblings.first) ?? (cousins.last { $0.range.location < insertAt } ?? cousins.first)
        let role = model?.mark.role ?? (depth == 1 ? Section.Role.chapter : Section.Role.section)
        // Dove comincia: come la sezione da cui prende il ruolo (basta impostarlo sul primo capitolo).
        let pageStart = model?.mark.start ?? .continuous
        // Lo stile: quello dei titoli allo stesso livello, altrimenti quello che gli stili dichiarano per il livello.
        let samePeers = (siblings + cousins + peers).filter { $0.range.length > 0 }
        let styleName = samePeers.lazy.compactMap { text.attribute(.paragraphStyleName, at: $0.range.location, effectiveRange: nil) as? String }.first
            ?? sheet.headingStyles(forLevel: depth).first

        // Gli a capo nascono con gli attributi del testo accanto, poi il titolo prende i suoi.
        var attributes: [NSAttributedString.Key: Any]
        if text.length == 0 {
            attributes = TextStyling.characterAttributes(for: TextStyling.styleBase).attributes
        } else {
            attributes = text.attributes(at: min(max(insertAt - 1, 0), text.length - 1), effectiveRange: nil)
        }
        for key in [NSAttributedString.Key.footnote, .floatImage, .inlineImage, .finalParagraphList, .finalParagraphSection, .field] { attributes[key] = nil }
        text.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: NSAttributedString(string: String(repeating: "\n", count: newlines), attributes: attributes))

        let title = NSRange(location: titleIndex, length: 1)
        for key in [NSAttributedString.Key.sectionTitle, .listItem] { text.removeAttribute(key, range: title) }
        if let styleName {
            TextStyling.restyle(text, range: title, from: sheet, to: sheet) { $0.paragraph = styleName }
        }
        text.addAttribute(.sectionTitle, value: SectionMark(id: Section.newID(), role: role, depth: depth, start: pageStart,
                                                 pageTypes: model?.mark.pageTypes ?? SectionPageTypes()).encoded, range: title)
        if newlines == 2 {
            // La parte che segue il titolo è testo della sezione nuova, anche se veniva da un titolo.
            let rest = TextStyling.bodyParagraph(in: text, at: titleIndex + 1).range
            if rest.length > 0 { text.removeAttribute(.sectionTitle, range: rest) }
        }
        normalize(text)
        return titleIndex
    }

    /// I caratteri della sezione del titolo dato: dal titolo fino al titolo seguente della stessa profondità o di una
    /// minore, o al paragrafo che torna a una sezione che la contiene (o alla fine del testo), sezioni interne comprese.
    public static func range(of title: Title, in text: NSAttributedString) -> NSRange {
        var end = text.length
        var open: [String] = []  // la sezione e le sue interne aperte
        for event in structure(in: text).events where event.location >= title.range.location {
            if open.isEmpty {
                guard case .title(let first) = event, first.mark.id == title.mark.id else { continue }
                open = [first.mark.id]
                continue
            }
            switch event {
            case .title(let next):
                if next.depth <= title.depth { end = next.range.location; break }
                open.removeLast(max(open.count - (next.depth - title.depth), 0))
                open.append(next.mark.id)
                continue
            case .back(let range, let target):
                if let keep = open.lastIndex(of: target) { open.removeLast(open.count - keep - 1); continue }
                end = range.location
            }
            break
        }
        return NSRange(location: title.range.location, length: end - title.range.location)
    }

    /// Che cosa contiene una sezione: i paragrafi (titolo escluso, quelli delle sezioni interne compresi) e le sezioni
    /// interne dirette.
    public static func contents(of title: Title, in text: NSAttributedString) -> (paragraphs: Int, sections: Int) {
        let span = range(of: title, in: text)
        // Le interne: i titoli dentro l'intervallo, più un titolo finale vuoto se la sezione arriva in fondo al testo.
        let inner = titles(in: text).filter {
            $0.range.location > span.location && ($0.range.location < NSMaxRange(span) || $0.range.length == 0 && NSMaxRange(span) == text.length)
        }
        var paragraphs = 0
        var location = span.location
        while location < NSMaxRange(span) {
            location = max(NSMaxRange(TextStyling.bodyParagraph(in: text, at: location).range), location + 1)
            paragraphs += 1
        }
        // Un paragrafo finale vuoto (dopo l'ultimo a capo) appartiene all'ultima sezione.
        if NSMaxRange(span) == text.length, span.length > 0, TextStyling.isLineTerminator((text.string as NSString).character(at: text.length - 1)) { paragraphs += 1 }
        if title.range.length > 0 { paragraphs -= 1 }
        return (max(paragraphs, 0), inner.filter { $0.depth == title.depth + 1 }.count)
    }

    /// Cambia il ruolo della sezione del titolo dato.
    public static func setRole(_ role: String, of title: Title, in text: NSMutableAttributedString) {
        rewrite(title, in: text) { $0.role = role }
    }

    /// Cambia dove comincia la sezione del titolo dato.
    public static func setStart(_ start: SectionStart, of title: Title, in text: NSMutableAttributedString) {
        rewrite(title, in: text) { $0.start = start }
    }

    /// Cambia i tipi di pagina che la sezione del titolo dato indica.
    public static func setPageTypes(_ types: SectionPageTypes, of title: Title, in text: NSMutableAttributedString) {
        rewrite(title, in: text) { $0.pageTypes = types }
    }

    /// Dopo aver rinominato (o tolto, con `nil`) dei tipi di pagina: le sezioni che li indicavano seguono.
    public static func renamePageTypes(_ renames: [String: String?], in text: NSMutableAttributedString) {
        guard !renames.isEmpty else { return }
        func renamed(_ name: String?) -> String? {
            guard let name, let new = renames[name] else { return name }
            return new
        }
        for title in titles(in: text) {
            let old = title.mark.pageTypes
            let new = SectionPageTypes(pages: renamed(old.pages), evenPages: renamed(old.evenPages), firstPage: renamed(old.firstPage))
            if new != old { setPageTypes(new, of: title, in: text) }
        }
    }

    /// Cambia la Lista con cui la sezione fa ripartire i numeri di pagina (`nil`: proseguono).
    public static func setPageNumbering(_ list: String?, of title: Title, in text: NSMutableAttributedString) {
        rewrite(title, in: text) { $0.pageNumbering = list }
    }

    /// Dopo aver rinominato (o tolto, con `nil`) delle Liste: le sezioni che ne usavano una per i numeri di pagina seguono.
    public static func renameListsInSections(_ renames: [String: String?], in text: NSMutableAttributedString) {
        guard !renames.isEmpty else { return }
        for title in titles(in: text) {
            guard let list = title.mark.pageNumbering, let new = renames[list] else { continue }
            setPageNumbering(new, of: title, in: text)
        }
    }

    /// Riscrive il segno di un titolo.
    private static func rewrite(_ title: Title, in text: NSMutableAttributedString, _ change: (inout SectionMark) -> Void) {
        var mark = title.mark
        change(&mark)
        if title.range.length > 0 {
            text.addAttribute(.sectionTitle, value: mark.encoded, range: title.range)
        } else if text.length > 0 {
            text.addAttribute(.finalParagraphSection, value: mark.encoded, range: NSRange(location: text.length - 1, length: 1))
        }
    }

    /// Se la sezione può scendere di un livello: serve una sorella prima di lei, che la accolga come ultima sezione interna.
    public static func canMoveInside(_ title: Title, in text: NSAttributedString) -> Bool {
        let all = titles(in: text)
        guard let position = all.firstIndex(of: title) else { return false }
        for previous in all[..<position].reversed() {
            if previous.depth < title.depth { return false }
            if previous.depth == title.depth { return true }
        }
        return false
    }

    /// Sposta la sezione di un livello, con tutte le sue interne: più dentro diventa l'ultima sezione interna della sorella
    /// che la precede; più fuori diventa sorella di quella che la conteneva (e le sorelle che la seguivano diventano sue
    /// interne, perché nel testo vengono dopo di lei). Vero se lo spostamento c'è stato.
    @discardableResult
    public static func moveSection(_ title: Title, by delta: Int, in text: NSMutableAttributedString) -> Bool {
        guard delta == 1 && canMoveInside(title, in: text) || delta == -1 && title.depth > 1 else { return false }
        let all = titles(in: text)
        guard let position = all.firstIndex(of: title) else { return false }
        var moved = [title]
        for next in all[(position + 1)...] {
            if next.depth <= title.depth { break }
            moved.append(next)
        }
        for item in moved {
            var mark = item.mark
            mark.depth = item.depth + delta
            if item.range.length > 0 {
                text.addAttribute(.sectionTitle, value: mark.encoded, range: item.range)
            } else if text.length > 0 {
                text.addAttribute(.finalParagraphSection, value: mark.encoded, range: NSRange(location: text.length - 1, length: 1))
            }
        }
        normalize(text)
        return true
    }

    /// Dopo aver dato a dei paragrafi uno stile che apre una sezione: ogni paragrafo dell'intervallo che non è già un
    /// titolo diventa il titolo di una sezione nuova di quel ruolo. La profondità è il livello di paragrafazione che il
    /// paragrafo ha ricevuto dallo stile; se non ne ha, quella dell'ultima sezione dello stesso ruolo prima del paragrafo
    /// (o della prima dopo); se non ce n'è, la sezione nasce dentro quella in cui cade. Un livello che salterebbe un
    /// gradino (un «Titolo 3» subito dentro un capitolo) diventa quello possibile, e lo stile lo segue.
    public static func openSections(role: String, inParagraphsOf range: NSRange, in text: NSMutableAttributedString) {
        var location = range.location
        let end = NSMaxRange(range)
        while location < max(end, range.location + 1), location < text.length {
            let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
            location = max(NSMaxRange(paragraph), location + 1)
            let all = titles(in: text)
            guard paragraph.length > 0, !all.contains(where: { $0.range.location == paragraph.location }) else { continue }
            let sameRole = all.filter { $0.mark.role == role }
            let model = sameRole.last { $0.range.location < paragraph.location } ?? sameRole.first
            // La profondità è il livello che lo stile appena dato dichiara; senza, come le sezioni dello stesso ruolo.
            let declared = (text.attribute(.outlineLevel, at: paragraph.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let depth = declared > 0 ? declared
                : model?.depth ?? (paragraph.location > 0 ? enclosing(in: text, at: paragraph.location - 1).count + 1 : 1)
            text.addAttribute(.sectionTitle, value: SectionMark(id: Section.newID(), role: role, depth: depth, start: model?.mark.start ?? .continuous,
                                                          pageTypes: model?.mark.pageTypes ?? SectionPageTypes()).encoded,
                              range: paragraph)
        }
        normalize(text)
    }

    /// Il ruolo di una sezione che nasce da uno stile con un livello ma senza ruolo proprio.
    public static func defaultRole(forLevel level: Int) -> String {
        level <= 1 ? Section.Role.chapter : Section.Role.section
    }

    /// Dopo aver dato a dei titoli uno stile che dichiara il livello `level`: ogni sezione dell'intervallo che sta a
    /// un'altra profondità si sposta lì con tutto il suo contenuto, come trascinata nella mappa. Più fuori va subito dopo
    /// la sezione che la conteneva a quel livello (le sorelle che la seguivano restano dov'erano); più dentro diventa
    /// l'ultima sezione interna della sorella che la precede, un gradino alla volta. Lo stile dato resta; se il livello
    /// non si può raggiungere (più dentro senza una sorella prima), la sezione resta al livello possibile e lo stile segue
    /// quello.
    public static func moveTitles(inParagraphsOf range: NSRange, toLevel level: Int, in store: DocumentStore) {
        guard level > 0 else { return }
        let ids = titles(in: store)
            .filter { $0.range.length > 0 && $0.range.location >= range.location && $0.range.location < max(NSMaxRange(range), range.location + 1) }
            .map { store.paragraphID(at: $0.range.location) }
        for id in ids {
            func current() -> Title? {
                titles(in: store).first { $0.range.length > 0 && store.paragraphID(at: $0.range.location) == id }
            }
            guard let start = current(), start.depth != level else { continue }
            // Il livello registrato resta la profondità attuale: così, a ogni passo, lo stile appena dato è una scelta
            // fatta a mano e non viene rimesso a quello della profondità.
            store.addAttribute(.outlineLevel, value: NSNumber(value: start.depth), range: start.range)
            for _ in 0..<64 {
                guard let title = current(), title.depth != level else { break }
                let all = titles(in: store)
                guard let index = all.firstIndex(of: title) else { break }
                if title.depth > level {
                    guard let owner = all[..<index].last(where: { $0.depth <= level }), owner.depth == level, owner.range.length > 0,
                          store.moveSection(id, .after, store.paragraphID(at: owner.range.location)) != nil else { break }
                } else {
                    var sister: Title?
                    for previous in all[..<index].reversed() {
                        if previous.depth < title.depth { break }
                        if previous.depth == title.depth { sister = previous; break }
                    }
                    guard let sister, sister.range.length > 0,
                          store.moveSection(id, .inside, store.paragraphID(at: sister.range.location)) != nil else { break }
                }
            }
            if let title = current(), title.depth != level {
                store.addAttribute(.outlineLevel, value: NSNumber(value: level), range: title.range)
                normalize(store)
            }
        }
    }

    /// Dopo che è cambiato il livello di uno stile: ogni titolo il cui stile dichiara un livello diverso dalla sua
    /// profondità va a quel livello, come in `moveTitles`.
    public static func moveTitlesToStyleLevels(in store: DocumentStore) {
        let ids = titles(in: store).filter { $0.range.length > 0 }.map { store.paragraphID(at: $0.range.location) }
        for id in ids {
            guard let title = titles(in: store).first(where: { $0.range.length > 0 && store.paragraphID(at: $0.range.location) == id }) else { continue }
            let name = store.attribute(.paragraphStyleName, at: title.range.location, effectiveRange: nil) as? String
            let level = store.settings.styles.resolveParagraph(styleName: name).outlineLevel ?? 0
            if level > 0, level != title.depth { moveTitles(inParagraphsOf: title.range, toLevel: level, in: store) }
        }
    }

    /// Dopo aver dato ai paragrafi uno stile che non apre una sezione: quelli che erano titoli tornano paragrafi del corpo.
    /// Il loro testo passa alla sezione che li precede e le sezioni interne salgono di un livello.
    public static func removeSections(inParagraphsOf range: NSRange, in text: NSMutableAttributedString) {
        let selected = titles(in: text).filter { $0.range.length > 0 && NSLocationInRange($0.range.location, range) }
        guard !selected.isEmpty else { return }
        for title in selected {
            retargetReturns(to: title, in: text)
            text.removeAttribute(.sectionTitle, range: title.range)
            clearLevel(of: title, in: text)
        }
        normalize(text)
    }

    /// Toglie la sezione del titolo dato: il titolo resta come paragrafo, il suo testo passa alla sezione che lo precede,
    /// le sue sezioni interne salgono di un livello.
    public static func removeSection(_ title: Title, in text: NSMutableAttributedString) {
        retargetReturns(to: title, in: text)
        clearLevel(of: title, in: text)
        if title.range.length > 0 {
            text.removeAttribute(.sectionTitle, range: title.range)
        } else if text.length > 0 {
            text.removeAttribute(.finalParagraphSection, range: NSRange(location: text.length - 1, length: 1))
        }
        normalize(text)
    }

    /// Riscrive i segni con la profondità vera e toglie quelli ripetuti, così il testo dice esattamente l'albero.
    public static func normalize(_ text: NSMutableAttributedString) {
        // I ritorni che non contano si tolgono: dopo uno spostamento, o copiati da Invio nel paragrafo nuovo.
        for range in structure(in: text).staleReturns {
            if range.length > 0 {
                text.removeAttribute(.sectionReturn, range: range)
            } else if text.length > 0 {
                text.removeAttribute(.finalParagraphSectionReturn, range: NSRange(location: text.length - 1, length: 1))
            }
        }
        let real = titles(in: text)
        let realStarts = Set(real.map(\.range.location))
        for title in real where title.mark.depth != title.depth {
            var mark = title.mark
            mark.depth = title.depth
            if title.range.length > 0 {
                text.addAttribute(.sectionTitle, value: mark.encoded, range: title.range)
            } else {
                text.addAttribute(.finalParagraphSection, value: mark.encoded, range: NSRange(location: text.length - 1, length: 1))
            }
        }
        // I segni ripetuti (paragrafi del corpo che se li portano dietro).
        var stale: [NSRange] = []
        text.enumerateAttribute(.sectionTitle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value != nil else { return }
            var location = range.location
            while location < NSMaxRange(range) {
                let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
                if !realStarts.contains(paragraph.location) { stale.append(NSIntersectionRange(paragraph, range)) }
                location = max(NSMaxRange(paragraph), location + 1)
            }
        }
        for range in stale where range.length > 0 { text.removeAttribute(.sectionTitle, range: range) }
        alignLevels(of: real, in: text)
    }

    /// Il livello di paragrafazione di un titolo è la profondità della sua sezione: qui la si ricopia nel paragrafo.
    /// Se il livello registrato era un altro (la sezione è entrata in un'altra, ne è uscita, è salita perché quella che la
    /// conteneva è stata tolta), nel deposito cambia anche lo stile del titolo: quello del livello di prima (o nessuno
    /// stile) diventa quello del nuovo livello, secondo il livello che gli stili dichiarano e non il loro nome
    /// (`StyleSheet.headingStyle(forLevel:replacing:)`), creato se manca.
    /// Il cambio del foglio degli stili entra nello stesso passo di Annulla.
    static func alignLevels(of titles: [Title], in text: NSMutableAttributedString) {
        let store = text as? DocumentStore
        let oldSheet = store?.settings.styles
        var sheet = oldSheet
        for title in titles {
            let level = NSNumber(value: title.depth)
            guard title.range.length > 0 else {
                // Il titolo vuoto in fondo al testo: il livello sta sull'ultimo a capo, come il suo segno.
                if text.length > 0 {
                    text.addAttribute(.finalParagraphOutlineLevel, value: level, range: NSRange(location: text.length - 1, length: 1))
                }
                continue
            }
            let recorded = (text.attribute(.outlineLevel, at: title.range.location, effectiveRange: nil) as? NSNumber)?.intValue
            guard recorded != title.depth else { continue }
            // Solo un vero cambio di livello cambia lo stile; un titolo che non ne aveva uno riceve soltanto il numero. Lo
            // stile cambia se era quello del livello di prima (o se non c'era): uno stile che dichiara un altro livello è
            // una scelta fatta a mano, e resta.
            if let recorded, recorded > 0, let oldSheet, let current = sheet {
                let oldName = text.attribute(.paragraphStyleName, at: title.range.location, effectiveRange: nil) as? String
                let declared = oldName.map { current.resolveParagraph(styleName: $0).outlineLevel }
                if oldName == nil || declared == recorded,
                   let (newSheet, newName) = current.headingStyle(forLevel: title.depth, replacing: oldName), newName != oldName {
                    TextStyling.restyle(text, range: title.range, from: oldSheet, to: newSheet) { $0.paragraph = newName }
                    sheet = newSheet
                }
            }
            text.addAttribute(.outlineLevel, value: level, range: title.range)
        }
        if let store, let sheet { store.replaceStyles(sheet) }
    }

    /// Un paragrafo che smette di essere titolo non ha più un livello di paragrafazione.
    static func clearLevel(of title: Title, in text: NSMutableAttributedString) {
        if title.range.length > 0 {
            text.addAttribute(.outlineLevel, value: NSNumber(value: 0), range: title.range)
        } else if text.length > 0 {
            text.addAttribute(.finalParagraphOutlineLevel, value: NSNumber(value: 0), range: NSRange(location: text.length - 1, length: 1))
        }
    }
}
