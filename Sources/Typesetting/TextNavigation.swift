import AppKit

/// La selezione: un'àncora che resta ferma e una testa che si muove. Se coincidono è il solo cursore.
public struct TextSelection: Equatable, Sendable {
    public var anchor: Int
    public var head: Int
    /// A quale riga appartiene la testa quando cade su un a capo automatico.
    public var affinity: NSSelectionAffinity
    /// L'ascissa da mantenere mentre si sale o si scende di riga più volte di seguito.
    public var goalX: CGFloat?

    public init(anchor: Int, head: Int, affinity: NSSelectionAffinity = .downstream, goalX: CGFloat? = nil) {
        self.anchor = anchor
        self.head = head
        self.affinity = affinity
        self.goalX = goalX
    }

    public init(caret index: Int, affinity: NSSelectionAffinity = .downstream) {
        self.init(anchor: index, head: index, affinity: affinity)
    }

    public var range: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
    public var isEmpty: Bool { anchor == head }
}

/// I movimenti del cursore, nei termini dei comandi di tastiera standard.
public enum TextMovement: Sendable, CaseIterable {
    case left, right, wordLeft, wordRight
    case lineStart, lineEnd, up, down
    case paragraphStart, paragraphEnd, documentStart, documentEnd
}

extension DocumentLayout {
    /// Applica un movimento alla selezione. Con `extending` l'àncora resta ferma (movimento con Maiuscole).
    ///
    /// Sinistra e destra seguono l'ordine logico dei caratteri: nel testo da destra a sinistra non corrispondono
    /// ancora al verso visivo.
    public func selection(_ selection: TextSelection, moving movement: TextMovement, extending: Bool) -> TextSelection {
        let string = text.string as NSString
        let length = string.length
        var head = min(max(selection.head, 0), length)
        var affinity = selection.affinity
        var goalX: CGFloat?
        // La nota in cui si trova il cursore, se è in una nota: i movimenti di testo non ne escono.
        let originNote = noteTextRange(containing: head, affinity: affinity)
        /// Alla fine di una nota la posizione appartiene alla nota solo con affinità `.upstream`.
        func caret(_ index: Int) -> TextSelection {
            TextSelection(caret: index, affinity: originNote.map { NSMaxRange($0) == index } == true ? .upstream : .downstream)
        }

        // Senza Maiuscole, una selezione non vuota prima si chiude: verso l'inizio o verso la fine secondo il movimento.
        if !extending, !selection.isEmpty {
            let range = selection.range
            switch movement {
            case .left: return caret(range.location)
            case .right: return caret(NSMaxRange(range))
            case .up, .wordLeft, .lineStart, .paragraphStart: head = range.location; affinity = .downstream
            case .down, .wordRight, .lineEnd, .paragraphEnd: head = NSMaxRange(range); affinity = .downstream
            case .documentStart, .documentEnd: break
            }
        }

        switch movement {
        case .left:
            head = head > 0 ? string.rangeOfComposedCharacterSequence(at: head - 1).location : 0
            affinity = .downstream
        case .right:
            head = head < length ? NSMaxRange(string.rangeOfComposedCharacterSequence(at: head)) : length
            affinity = .downstream
        case .wordLeft:
            head = text.nextWord(from: head, forward: false)
            affinity = .downstream
        case .wordRight:
            head = text.nextWord(from: head, forward: true)
            affinity = .downstream
        case .lineStart:
            head = lineStart(for: head, affinity: affinity)
            affinity = .downstream
        case .lineEnd:
            (head, affinity) = lineEnd(for: head, affinity: affinity)
        case .up, .down:
            let moved = position(movingVerticallyFrom: head, affinity: affinity, lines: movement == .up ? -1 : 1, goalX: selection.goalX)
            (head, affinity, goalX) = (moved.index, moved.affinity, moved.goalX)
        case .paragraphStart:
            // Nel corpo i paragrafi non si spezzano agli a capo interni a una nota; dentro una nota valgono i suoi.
            head = originNote == nil ? TextStyling.bodyParagraph(in: text, at: head).range.location
                                     : string.paragraphRange(for: NSRange(location: head, length: 0)).location
            affinity = .downstream
        case .paragraphEnd:
            if originNote == nil {
                head = TextStyling.bodyParagraph(in: text, at: head).contentsEnd
            } else {
                var contentsEnd = 0
                string.getParagraphStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: head, length: 0))
                head = contentsEnd
            }
            affinity = .downstream
        case .documentStart:
            head = 0
            affinity = .downstream
        case .documentEnd:
            head = length
            affinity = .downstream
        }
        // Corpo e note sono due testi distinti che nel documento stanno uno dentro l'altro. Salire e scendere
        // seguono ciò che si vede sulla pagina; gli altri movimenti restano nel testo da cui partono.
        if movement != .up, movement != .down {
            if let note = originNote {
                head = min(max(head, note.location), NSMaxRange(note))
                if head == NSMaxRange(note) { affinity = .upstream }
            } else {
                // Nel corpo una nota si scavalca in un passo solo, richiamo e testo insieme.
                let start = min(max(selection.head, 0), length)
                if let crossed = note(strictlyContaining: head) {
                    head = head >= start ? NSMaxRange(crossed) : crossed.location
                }
                if note(endingAt: head) != nil { affinity = .downstream }
            }
        }
        return TextSelection(anchor: extending ? selection.anchor : head, head: head, affinity: affinity, goalX: goalX)
    }

    /// L'intervallo che un comando di cancellazione toglie: la selezione, se c'è, altrimenti dal cursore
    /// fin dove lo porterebbe il movimento dato.
    public func deletionRange(for selection: TextSelection, toward movement: TextMovement) -> NSRange {
        guard selection.isEmpty else { return selection.range }
        let range = self.selection(selection, moving: movement, extending: true).range
        // Cancellando all'indietro una lettera di una scrittura indiana o del Sud-Est asiatico si toglie solo il
        // carattere prima del cursore: da «मे» la vocale «े», poi la consonante (richiesta di Artemij Keidan, 20 ottobre
        // 2026). Vale anche col cursore in mezzo a una lettera, dove lo lascia la cancellazione precedente.
        let string = text.string as NSString
        let head = selection.head
        guard movement == .left, range.length > 1, NSMaxRange(range) == head, head > 0,
              Self.deletesByCharacter(string.substring(with: string.rangeOfComposedCharacterSequence(at: head - 1))) else { return range }
        // Il carattere intero: due unità UTF-16 se è fuori dal piano di base.
        let length = head >= 2 && UTF16.isTrailSurrogate(string.character(at: head - 1)) && UTF16.isLeadSurrogate(string.character(at: head - 2)) ? 2 : 1
        return NSRange(location: head - length, length: length)
    }

    /// Vero per le lettere delle scritture in cui la cancellazione all'indietro va carattere per carattere (vedi
    /// `ReorderingScripts`). Nelle altre (lettere latine con accenti, emoji, bandiere) si toglie la lettera intera.
    static func deletesByCharacter(_ grapheme: String) -> Bool { ReorderingScripts.contains(grapheme) }
}

/// Le scritture dell'India (dal devanagari al malayalam), singalese, thai, lao, tibetano, birmano, khmer e le loro
/// estensioni: quelle in cui i segni di una lettera si scrivono e si leggono in un ordine e si disegnano in un altro
/// (la matra «ि» prima della consonante), e una lettera è fatta di più caratteri. Valgono per loro la cancellazione un
/// carattere per volta e, nel PDF, il testo invisibile in ordine di lettura.
enum ReorderingScripts {
    static let blocks: [ClosedRange<UInt32>] = [0x0900...0x0DFF, 0x0E00...0x0EFF, 0x0F00...0x0FFF, 0x1000...0x109F, 0x1780...0x17FF,
                                                0xA8E0...0xA8FF, 0xA9E0...0xA9FF, 0xAA60...0xAA7F, 0x11000...0x111FF]

    static func contains(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in blocks.contains { $0.contains(scalar.value) } }
    }
}
