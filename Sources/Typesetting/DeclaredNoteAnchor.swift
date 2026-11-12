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
    func declaredNotes(ofParagraphStyle name: String?) -> [(declaringStyle: String, declaration: DeclaredNote)] {
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
