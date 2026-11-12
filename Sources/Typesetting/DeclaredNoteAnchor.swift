import Foundation

/// La dichiarazione appartiene a uno stile di paragrafo. Il suo UUID è locale allo stile.
public struct DeclaredNote: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let word: Int
    /// La serie della nota: uno stile di flottante (nota a piè di pagina, a margine, di chiusura).
    public var style: String

    public init?(id: UUID = UUID(), word: Int, style: String = FloatStyle.footnoteName) {
        guard word > 0 else { return nil }
        self.id = id
        self.word = word
        self.style = style
    }
}

extension StyleSheet {
    /// Le dichiarazioni di nota che valgono per un paragrafo con lo stile `name`: quelle dello stile e delle sue basi,
    /// dalla base allo stile assegnato, ciascuna con lo stile che la dichiara.
    public func declaredNotes(ofParagraphStyle name: String?) -> [(declaringStyle: String, declaration: DeclaredNote)] {
        var current = name
        var chain: [NamedStyle] = []
        var visited: Set<String> = []
        while let styleName = current, visited.insert(styleName).inserted,
              let style = style(named: styleName), style.target == .paragraph {
            chain.append(style)
            current = style.basedOn
        }
        return chain.reversed().flatMap { style in style.declaredNotes.map { (style.name, $0) } }
    }
}

/// Identità logica dell'occorrenza, indipendente dalla posizione della parola: il capoverso, lo stile che dichiara la
/// nota e la dichiarazione. Rinominare lo stile riscrive la chiave (`Document.renamingStyle`).
public struct DeclaredNoteSlot: Hashable, Sendable {
    public let paragraph: UUID
    public var declaringStyle: String
    public let declaration: UUID

    public init(paragraph: UUID, declaringStyle: String, declaration: UUID) {
        self.paragraph = paragraph
        self.declaringStyle = declaringStyle
        self.declaration = declaration
    }
}

extension DocumentStore {
    /// Le dichiarazioni del capoverso, comprese quelle ereditate o prive di aggancio.
    /// I risultati mantengono l'ordine dalla base allo stile assegnato.
    public func declaredNotePositions(in paragraph: ParagraphID) -> [(slot: DeclaredNoteSlot, position: Int?)] {
        guard let range = range(of: paragraph), range.length > 0 else { return [] }
        let name = attribute(.paragraphStyleName, at: range.location, effectiveRange: nil) as? String
        return settings.styles.declaredNotes(ofParagraphStyle: name).map { declaringStyle, declaration in
            let slot = DeclaredNoteSlot(paragraph: paragraph.persistent, declaringStyle: declaringStyle, declaration: declaration.id)
            let word = WordSelection(name: "", index: declaration.word)
            return (slot, DeclaredNoteAnchor.position(in: self, paragraph: range, selection: word))
        }
    }
}

/// Resolves a relative anchor without changing the document. A missing word leaves
/// the declaration without a visible anchor; the caller owns any saved content.
enum DeclaredNoteAnchor {
    static func position(in text: NSAttributedString, paragraph: NSRange, selection: WordSelection) -> Int? {
        guard paragraph.location != NSNotFound, paragraph.location >= 0, paragraph.length >= 0,
              paragraph.location <= text.length, paragraph.length <= text.length - paragraph.location else { return nil }
        let body = BodyText(text, paragraph: paragraph)
        guard let word = body.selectedWord(selection),
              let last = body.documentRanges(for: word).last else { return nil }
        return NSMaxRange(last)
    }
}

extension TextStyling {
    /// Il testo di un capoverso senza il contenuto delle note scritte che contiene: quello in cui si contano le parole
    /// delle note dichiarate, e con cui l'editor riconosce il capoverso negli elenchi.
    public static func bodyText(in text: NSAttributedString, paragraph: NSRange) -> String {
        BodyText(text, paragraph: paragraph).string as String
    }
}

/// Il testo di una nota dichiarata: tratti formattati (corsivo, neretto, font, funzioni…), come il testo di una nota
/// scritta. Gli stili con un nome dei tratti non si conservano: resta il loro aspetto risolto.
public struct DeclaredNoteText: Equatable, Sendable {
    public var runs: [TextRun]

    public init(runs: [TextRun]) {
        self.runs = runs.filter { !$0.text.isEmpty }.map { run in
            var plain = run
            plain.wordStyleName = nil
            plain.characterStyleName = nil
            plain.ruleExceptions = []
            plain.field = nil
            return plain
        }
    }

    /// Un testo senza formattazione, tutto nello stile dato.
    public init(_ text: String, style: CharacterStyle) {
        self.init(runs: [TextRun(text, style: style)])
    }

    public var plainText: String { runs.map(\.text).joined() }
    /// Vero se non c'è niente da conservare: nessun carattere che non sia uno spazio.
    public var isBlank: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Il testo con i suoi attributi, per comporlo o per modificarlo.
    public var attributedString: NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: TextStyling.characterAttributes(for: run.style).attributes))
        }
        return result
    }

    /// Il testo dei tratti di un testo con attributi (il campo dell'editor): gli a capo diventano spazi, perché la nota
    /// è un capoverso solo.
    public init(attributedString text: NSAttributedString) {
        let flat = NSMutableAttributedString(attributedString: text)
        let newline = CharacterSet.newlines
        for index in (0..<flat.length).reversed() {
            guard let scalar = Unicode.Scalar((flat.string as NSString).character(at: index)), newline.contains(scalar) else { continue }
            flat.replaceCharacters(in: NSRange(location: index, length: 1), with: " ")
        }
        let document = Document(attributedString: flat)
        self.init(runs: document.flatParagraphs.first?.paragraph.inlines.compactMap { inline in
            if case .text(let run) = inline { run } else { nil }
        } ?? [])
    }

    /// Il testo come frammento del formato del documento: un documento minimo con un solo capoverso. Lo scrivono e lo
    /// leggono le stesse funzioni dei capoversi, quindi conserva font, funzioni, colore e il resto dell'aspetto.
    var fragment: String {
        DocumentFormat.string(for: Document(blocks: [.paragraph(Paragraph(inlines: runs.map { .text($0) }))]))
    }

    init?(fragment: String) {
        guard let document = try? DocumentFormat.document(from: fragment) else { return nil }
        let runs = document.flatParagraphs.first?.paragraph.inlines.compactMap { inline -> TextRun? in
            if case .text(let run) = inline { run } else { nil }
        } ?? []
        self.init(runs: runs)
    }
}
