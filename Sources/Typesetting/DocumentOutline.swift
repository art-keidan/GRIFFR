import Foundation

/// Un oggetto dell'albero degli oggetti: un titolo (che contiene ciò che lo segue fino al titolo successivo dello stesso
/// livello o di uno superiore), un paragrafo, una voce di elenco, una nota, una figura.
public struct OutlineItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case paragraph
        case listItem
        case note
        case figure
        case table
    }

    /// La posizione nel testo: del paragrafo, o del richiamo per una nota o una figura. È anche l'identità della riga
    /// (per una tabella, che comincia dove comincia la sua prima cella, un numero negativo).
    public var id: Int { kind == .table ? -range.location - 1 : range.location }
    public var kind: Kind
    /// Le prime parole (del paragrafo, o del testo della nota o della didascalia).
    public var title: String
    /// Ciò che sta davanti: ¶, il segno della voce, il segno della nota, ▣ per una figura.
    public var label: String
    /// Ciò che sta a destra: lo stile del paragrafo, la serie della nota, il numero della figura.
    public var detail: String
    /// I caratteri dell'oggetto: il paragrafo, o il richiamo con il testo della nota.
    public var range: NSRange
    /// Per un titolo, ciò che contiene; `nil` per gli altri (niente freccia per aprirli).
    public var children: [OutlineItem]?

    public var isFloating: Bool { kind == .note || kind == .figure }
}

public enum DocumentOutline {
    /// Le parole iniziali mostrate per un oggetto.
    static let titleLength = 48

    /// Compatibilità con i documenti precedenti: il livello dal nome «Titolo N» si usa soltanto quando il testo non
    /// porta ancora la proprietà esplicita `.outlineLevel`.
    public static func headingLevel(of styleName: String?) -> Int? {
        guard let styleName, styleName.hasPrefix("Titolo") else { return nil }
        let rest = styleName.dropFirst("Titolo".count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? 1 : Int(rest)
    }

    /// L'albero del testo: i titoli fanno da rami, il resto sta sotto il titolo che lo precede. Con almeno una sezione i
    /// rami sono le sezioni, secondo la loro profondità; senza sezioni, si usa il livello di paragrafazione registrato.
    public static func build(text: NSAttributedString, layout: DocumentLayout?, floatStyles: [FloatStyle]) -> [OutlineItem] {
        var flat: [OutlineItem] = []
        let structure = SectionEditing.structure(in: text).events
        let sections = structure.compactMap { if case .title(let title) = $0 { title } else { nil } }
        // I paragrafi che tornano a una sezione esterna: la profondità a cui tornano (0, fuori da ogni sezione).
        let depthByID = Dictionary(sections.map { ($0.mark.id, $0.depth) }, uniquingKeysWith: { first, _ in first })
        var returns: [Int: Int] = [:]
        for case .back(let range, let target) in structure { returns[range.location] = depthByID[target] ?? 0 }
        let sectionAt = Dictionary(sections.map { ($0.range.location, $0) }, uniquingKeysWith: { first, _ in first })
        let string = text.string as NSString
        let figures = Set(floatStyles.filter { $0.placement == .figure }.map(\.name))
        var location = 0
        // I paragrafi delle celle della tabella in corso, e la tabella stessa.
        var tableItem: OutlineItem?
        var tableEnd = 0
        func closeTable() {
            if let item = tableItem { flat.append(item) }
            tableItem = nil
        }
        while location < text.length {
            let paragraph = TextStyling.bodyParagraph(in: text, at: location).range
            location = max(NSMaxRange(paragraph), location + 1)
            if paragraph.location >= tableEnd { closeTable() }
            if tableItem == nil, let mark = TableEditing.cell(at: paragraph.location, in: text),
               let shape = TableEditing.shape(ofTableAt: paragraph.location, in: text) {
                let cells = TableEditing.paragraphs(ofTableAt: paragraph.location, in: text)
                tableEnd = cells.last.map { NSMaxRange($0.range) } ?? paragraph.location
                _ = mark
                tableItem = OutlineItem(kind: .table, title: "Tabella", label: "▦", detail: "\(shape.rows) × \(shape.columns)",
                                        range: NSRange(location: paragraph.location, length: tableEnd - paragraph.location), children: [])
            }
            if tableItem != nil {
                let words = shortened(BodyText(text, paragraph: paragraph).string as String)
                let style = text.attribute(.paragraphStyleName, at: paragraph.location, effectiveRange: nil) as? String
                tableItem?.children?.append(OutlineItem(kind: .paragraph, title: words.isEmpty ? "(vuoto)" : words, label: "¶", detail: style ?? "",
                                                        range: paragraph, children: nil))
                continue
            }
            let words = shortened(BodyText(text, paragraph: paragraph).string as String)
            let style = text.attribute(.paragraphStyleName, at: paragraph.location, effectiveRange: nil) as? String
            let hasNotes = (0..<paragraph.length).contains { TextStyling.isNoteAnchor(in: text, at: paragraph.location + $0) }
            // Il paragrafo vuoto in fondo al testo non è un oggetto da mostrare.
            if words.isEmpty, !hasNotes, NSMaxRange(paragraph) >= text.length, sectionAt[paragraph.location] == nil { continue }
            let recordedLevel = (text.attribute(.outlineLevel, at: paragraph.location, effectiveRange: nil) as? NSNumber)?.intValue
            let level = recordedLevel.map { $0 > 0 ? $0 : nil } ?? (recordedLevel == nil ? headingLevel(of: style) : nil)
            if let section = sectionAt[paragraph.location], paragraph.length > 0 {
                flat.append(sectionItem(section, words: words, style: style, number: layout?.listMarks[paragraph.location]))
            } else if sections.isEmpty, let level {
                flat.append(OutlineItem(kind: .heading(level: level), title: words.isEmpty ? "(titolo vuoto)" : words, label: "",
                                        detail: style ?? "", range: paragraph, children: []))
            } else if let mark = layout?.listMarks[paragraph.location] {
                flat.append(OutlineItem(kind: .listItem, title: words, label: mark, detail: style ?? "", range: paragraph, children: nil))
            } else {
                flat.append(OutlineItem(kind: .paragraph, title: words.isEmpty ? "(vuoto)" : words, label: "¶", detail: style ?? "",
                                        range: paragraph, children: nil))
            }
            // Le note e le figure del paragrafo, subito dopo di lui.
            var index = paragraph.location
            while index < NSMaxRange(paragraph) {
                guard TextStyling.isNoteAnchor(in: text, at: index), let span = TextStyling.footnoteSpan(in: text, anchoredAt: index) else {
                    index += 1
                    continue
                }
                let series = text.attribute(.footnote, at: index, effectiveRange: nil) as? String ?? FloatStyle.footnoteName
                let content = string.substring(with: NSRange(location: span.location + 1, length: span.length - 1))
                let mark = layout?.noteMarks[index] ?? ""
                if figures.contains(series) {
                    flat.append(OutlineItem(kind: .figure, title: shortened(content), label: "▣", detail: mark.isEmpty ? series : mark,
                                            range: span, children: nil))
                } else {
                    flat.append(OutlineItem(kind: .note, title: shortened(content), label: mark.isEmpty ? "•" : mark,
                                            detail: series == FloatStyle.footnoteName ? "Nota" : series, range: span, children: nil))
                }
                index = NSMaxRange(span)
            }
        }
        closeTable()
        // Un titolo vuoto nel paragrafo finale, che non ha caratteri.
        if let last = sections.last, last.range.length == 0 { flat.append(sectionItem(last, words: "", style: nil, number: nil)) }
        return nest(flat, returns: returns)
    }

    /// Il ramo di una sezione: il suo numero (o «§»), le prime parole del titolo, il ruolo (e lo stile del titolo) a destra.
    private static func sectionItem(_ title: SectionEditing.Title, words: String, style: String?, number: String?) -> OutlineItem {
        OutlineItem(kind: .heading(level: title.depth), title: words.isEmpty ? "(senza titolo)" : words, label: number ?? "§",
                    detail: style.map { "\(title.mark.role) · \($0)" } ?? title.mark.role, range: title.range, children: [])
    }

    /// Mette ogni oggetto sotto l'ultimo titolo di livello più alto che lo precede; un oggetto che torna a una sezione
    /// esterna (`returns`: la posizione e la profondità a cui torna) va sotto di lei, dopo le sue interne.
    static func nest(_ flat: [OutlineItem], returns: [Int: Int] = [:]) -> [OutlineItem] {
        var root: [OutlineItem] = []
        // I titoli aperti, dal più esterno: il livello e il percorso fino a lui nell'albero.
        var open: [(level: Int, path: [Int])] = []
        func insert(_ item: OutlineItem, under path: [Int]) -> [Int] {
            func place(_ list: inout [OutlineItem], _ rest: ArraySlice<Int>) -> [Int] {
                guard let first = rest.first else {
                    list.append(item)
                    return [list.count - 1]
                }
                var children = list[first].children ?? []
                let inner = place(&children, rest.dropFirst())
                list[first].children = children
                return [first] + inner
            }
            return place(&root, path[...])
        }
        for item in flat {
            if case .heading(let level) = item.kind {
                while let last = open.last, last.level >= level { open.removeLast() }
                open.append((level, insert(item, under: open.last?.path ?? [])))
            } else {
                if let depth = returns[item.range.location] {
                    while let last = open.last, last.level > depth { open.removeLast() }
                }
                _ = insert(item, under: open.last?.path ?? [])
            }
        }
        return root
    }

    /// Le prime parole, su una riga sola.
    static func shortened(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\u{2028}", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces)
        guard line.count > titleLength else { return line }
        let cut = line.prefix(titleLength)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word + "…"
    }

    /// Gli oggetti che contengono `filter` nel titolo, nel segno o nello stile, con i titoli sopra di loro (un titolo
    /// resta se va bene lui o se resta qualcosa sotto di lui).
    public static func filtered(_ items: [OutlineItem], by filter: String) -> [OutlineItem] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        func matches(_ item: OutlineItem) -> Bool {
            [item.title, item.label, item.detail].contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return items.compactMap { item in
            if let children = item.children {
                let kept = filtered(children, by: needle)
                if kept.isEmpty, !matches(item) { return nil }
                var copy = item
                copy.children = kept
                return copy
            }
            return matches(item) ? item : nil
        }
    }

    /// L'oggetto più preciso che contiene la posizione `index`: una nota o una figura prima del paragrafo che la
    /// contiene (il testo di una nota sta dentro il paragrafo del suo richiamo).
    public static func item(containing index: Int, in items: [OutlineItem]) -> OutlineItem? {
        var paragraph: OutlineItem?
        for item in items {
            if let children = item.children, let inner = self.item(containing: index, in: children) { return inner }
            guard NSLocationInRange(index, item.range) else { continue }
            if item.isFloating { return item }
            if paragraph == nil { paragraph = item }
        }
        return paragraph
    }
}
