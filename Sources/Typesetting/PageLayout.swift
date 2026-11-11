import AppKit
import CoreText

/// Formato della pagina e margini, in punti tipografici.
public struct PageSetup: Sendable, Equatable {
    public var paperSize: CGSize
    public var top: CGFloat
    public var bottom: CGFloat
    /// Con le pagine affacciate, `left` è il margine interno (verso la cucitura) e `right` quello esterno.
    public var left: CGFloat
    public var right: CGFloat
    /// Pagine affacciate, come in un libro: lo specchio di stampa si scambia fra le pagine dispari (a destra della
    /// cucitura, margine interno a sinistra) e le pari (margine interno a destra).
    public var facing: Bool

    public init(paperSize: CGSize, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, facing: Bool = false) {
        self.paperSize = paperSize
        self.top = top; self.bottom = bottom; self.left = left; self.right = right
        self.facing = facing
    }

    /// Lo specchio di stampa della pagina `index` (da zero: la prima pagina è dispari).
    public func textRect(forPage index: Int) -> CGRect {
        var rect = textRect
        if facing, index % 2 == 1 { rect.origin.x = right }
        return rect
    }

    /// Di quanto lo specchio della pagina `index` sta a destra di quello della prima.
    func horizontalShift(forPage index: Int) -> CGFloat { facing && index % 2 == 1 ? right - left : 0 }

    /// A4 con margini di 25 mm.
    public static let a4: PageSetup = {
        let margin = points(fromMillimetres: 25)
        return PageSetup(paperSize: CGSize(width: points(fromMillimetres: 210), height: points(fromMillimetres: 297)),
                         top: margin, bottom: margin, left: margin, right: margin)
    }()

    public static func points(fromMillimetres millimetres: Double) -> CGFloat { CGFloat(millimetres * 72 / 25.4) }
    public static func millimetres(fromPoints points: CGFloat) -> Double { Double(points) * 25.4 / 72 }

    /// Lo specchio di stampa (delle pagine dispari, con le pagine affacciate), con l'origine della pagina in basso a
    /// sinistra come nel PDF.
    public var textRect: CGRect {
        CGRect(x: left, y: bottom, width: paperSize.width - left - right, height: paperSize.height - top - bottom)
    }
}

// MARK: - Misure in qualsiasi unità

/// Le unità di lunghezza che si possono scrivere in un campo di misura, come in InDesign.
public enum LengthUnit: String, CaseIterable, Sendable {
    case millimetres = "mm", centimetres = "cm", inches = "in", points = "pt", picas = "pc"

    /// Quanti punti tipografici (1/72 di pollice) vale un'unità.
    public var points: Double {
        switch self {
        case .millimetres: 72 / 25.4
        case .centimetres: 720 / 25.4
        case .inches: 72
        case .points: 1
        case .picas: 12
        }
    }
}

public enum Length {
    /// I nomi accettati per ogni unità, in minuscolo.
    private static let names: [(String, LengthUnit)] = [
        ("millimetri", .millimetres), ("millimetro", .millimetres), ("mm", .millimetres),
        ("centimetri", .centimetres), ("centimetro", .centimetres), ("cm", .centimetres),
        ("pollici", .inches), ("pollice", .inches), ("inches", .inches), ("inch", .inches), ("in", .inches),
        ("punti", .points), ("punto", .points), ("pt", .points), ("px", .points),
        ("pica", .picas), ("pc", .picas),
    ]

    /// I punti di una misura scritta, anche come conto. Una misura è un numero (con la virgola o il punto) seguito, o
    /// no, da un'unità («25», «25 mm», «2,5cm», «1 in», «1"», «72 pt», «6 pc»), oppure pica e punti alla maniera di
    /// InDesign («1p6» è una pica e sei punti, «p6» sei punti, «6p» sei pica). Le misure si combinano con + e −, × e ÷
    /// (anche * e /, «x») e le parentesi: «3 pt + 5 cm», «210 mm − 2 × 25 mm», «(297 − 20) / 2». Un numero senza unità
    /// vale `defaultUnit` quando si somma o resta da solo, ed è un semplice fattore quando moltiplica o divide.
    /// `nil` se non si legge o se il conto non ha senso (due misure moltiplicate, divisione per zero).
    public static func points(from text: String, defaultUnit: LengthUnit = .millimetres) -> CGFloat? {
        guard let tokens = tokens(of: text), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens, defaultUnit: defaultUnit)
        guard let value = parser.expression(), parser.position == tokens.count else { return nil }
        let points = value.isLength ? value.amount : value.amount * defaultUnit.points
        return points.isFinite ? CGFloat(points) : nil
    }

    private enum Token: Equatable {
        case number(Double)
        case word(String)
        case symbol(Character)
    }

    /// I pezzi di una scrittura: numeri, parole (unità, «p» delle pica, «x») e segni. `nil` per un carattere estraneo.
    private static func tokens(of text: String) -> [Token]? {
        var tokens: [Token] = []
        var characters = Array(text.lowercased())[...]
        while let character = characters.first {
            if character.isWhitespace {
                characters.removeFirst()
            } else if character.isNumber || character == "." || character == "," {
                var digits = ""
                while let next = characters.first, next.isNumber || next == "." || next == "," {
                    digits.append(next == "," ? "." : next)
                    characters.removeFirst()
                }
                guard let value = Double(digits), value.isFinite else { return nil }
                tokens.append(.number(value))
            } else if character.isLetter {
                var word = ""
                while let next = characters.first, next.isLetter {
                    word.append(next)
                    characters.removeFirst()
                }
                tokens.append(.word(word))
            } else if "+-−–*×/÷:()\"″".contains(character) {
                tokens.append(.symbol(character))
                characters.removeFirst()
            } else {
                return nil
            }
        }
        return tokens
    }

    /// Un valore del conto: una lunghezza in punti, o un numero puro.
    private struct Value {
        var amount: Double
        var isLength: Bool
    }

    /// Lettura per discesa ricorsiva: espressione = termine (± termine)*, termine = fattore (×÷ fattore)*,
    /// fattore = segno fattore | (espressione) | misura.
    private struct Parser {
        let tokens: [Token]
        let defaultUnit: LengthUnit
        var position = 0

        private var next: Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func take(_ symbols: String) -> Character? {
            if case .symbol(let symbol)? = next, symbols.contains(symbol) {
                position += 1
                return symbol
            }
            if symbols.contains("×"), case .word("x")? = next {
                position += 1
                return "×"
            }
            return nil
        }

        mutating func expression() -> Value? {
            guard var result = term() else { return nil }
            while let sign = take("+-−–") {
                guard let other = term() else { return nil }
                // Un numero puro sommato a una lunghezza si legge nell'unità predefinita.
                let isLength = result.isLength || other.isLength
                let left = result.isLength || !isLength ? result.amount : result.amount * defaultUnit.points
                let right = other.isLength || !isLength ? other.amount : other.amount * defaultUnit.points
                result = Value(amount: sign == "+" ? left + right : left - right, isLength: isLength)
            }
            return result
        }

        private mutating func term() -> Value? {
            guard var result = factor() else { return nil }
            while let sign = take("*×/÷:") {
                guard let other = factor() else { return nil }
                if sign == "*" || sign == "×" {
                    guard !(result.isLength && other.isLength) else { return nil }
                    result = Value(amount: result.amount * other.amount, isLength: result.isLength || other.isLength)
                } else {
                    guard other.amount != 0, !(other.isLength && !result.isLength) else { return nil }
                    // Lunghezza diviso lunghezza è un rapporto, un numero puro.
                    result = Value(amount: result.amount / other.amount, isLength: result.isLength && !other.isLength)
                }
            }
            return result
        }

        private mutating func factor() -> Value? {
            if let sign = take("+-−–") {
                guard let value = factor() else { return nil }
                return sign == "+" ? value : Value(amount: -value.amount, isLength: value.isLength)
            }
            if take("(") != nil {
                guard let value = expression(), take(")") != nil else { return nil }
                return value
            }
            return measure()
        }

        /// Un numero con la sua unità, o pica e punti («1p6», «p6», «6p»).
        private mutating func measure() -> Value? {
            if case .word("p")? = next {
                position += 1
                guard case .number(let points)? = next else { return nil }
                position += 1
                return Value(amount: points, isLength: true)
            }
            guard case .number(let number)? = next else { return nil }
            position += 1
            switch next {
            case .word("p")?:
                position += 1
                if case .number(let points)? = next {
                    position += 1
                    return Value(amount: number * 12 + points, isLength: true)
                }
                return Value(amount: number * 12, isLength: true)
            case .word(let word)? where word != "x":
                guard let unit = Length.names.first(where: { $0.0 == word })?.1 else { return nil }
                position += 1
                return Value(amount: number * unit.points, isLength: true)
            case .symbol(let symbol)? where symbol == "\"" || symbol == "″":
                position += 1
                return Value(amount: number * LengthUnit.inches.points, isLength: true)
            default:
                return Value(amount: number, isLength: false)
            }
        }
    }

    /// Una misura scritta nell'unità data, con al più due decimali e la virgola: «25 mm», «2,54 cm».
    public static func text(_ points: CGFloat, unit: LengthUnit = .millimetres) -> String {
        let value = Double(points) / unit.points
        // Con il punto decimale, come l'interfaccia in inglese; la lettura accetta anche la virgola.
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) + " " + unit.rawValue
    }
}

/// Corrispondenza tra gli indici di un paragrafo composto e quelli del documento.
///
/// Il testo che Core Text compone non coincide sempre con quello del documento: nel corpo il testo di una nota è
/// sostituito dal numero di richiamo, e in fondo alla pagina la nota è preceduta dal proprio numero. La mappa è
/// fatta di tratti che corrispondono carattere per carattere; ciò che sta tra un tratto e l'altro è materiale
/// aggiunto (nel testo composto) o tolto (dal documento).
public struct TextMap: Sendable {
    struct Segment: Sendable {
        var composed: Int
        var document: Int
        var length: Int
    }

    var segments: [Segment]

    static func identity(location: Int, length: Int) -> TextMap {
        TextMap(segments: [Segment(composed: 0, document: location, length: length)])
    }

    /// La posizione nel documento di una posizione del testo composto. Dentro il materiale aggiunto (un numero di
    /// richiamo) si prende il bordo più vicino: prima o dopo il richiamo.
    func documentIndex(forComposed index: Int) -> Int {
        guard let last = segments.last else { return 0 }
        for (position, segment) in segments.enumerated() {
            if index < segment.composed {
                guard position > 0 else { return segment.document }
                let previous = segments[position - 1]
                let previousEnd = previous.composed + previous.length
                return (index - previousEnd) * 2 < segment.composed - previousEnd ? previous.document + previous.length : segment.document
            }
            if index <= segment.composed + segment.length { return segment.document + (index - segment.composed) }
        }
        return last.document + last.length
    }

    /// La posizione nel testo composto di una posizione del documento, se cade in uno dei tratti.
    func composedIndex(forDocument index: Int) -> Int? {
        for segment in segments where index >= segment.document && index <= segment.document + segment.length {
            return segment.composed + (index - segment.document)
        }
        return nil
    }
}

/// Una riga composta e collocata sulla pagina.
public struct PlacedLine {
    public let line: CTLine
    /// Inizio della linea di base, con l'origine della pagina in basso a sinistra.
    public internal(set) var origin: CGPoint
    /// Caratteri (UTF-16) del documento tra l'inizio e la fine della riga. In una riga del corpo che contiene
    /// richiami di nota l'intervallo abbraccia anche il testo delle note, che però è composto in fondo alla pagina.
    public let range: NSRange
    /// Identifica il paragrafo a cui la riga appartiene: la sua posizione nel documento (per una nota, quella del
    /// suo testo).
    public let paragraphLocation: Int
    /// Vero se la riga finisce con un trattino di sillabazione, che non fa parte del testo del documento.
    public let endsWithHyphen: Bool
    /// Altezza sopra e sotto la linea di base: lo spazio verticale che la riga occupa, e l'altezza del cursore.
    public let ascent: CGFloat
    public let descent: CGFloat
    /// Per una riga di nota a piè di pagina: i caratteri del documento che formano il testo della nota, senza il richiamo.
    public let noteRange: NSRange?
    /// La parte del paragrafo composto che la riga contiene, e la posizione in esso dell'indice zero della riga di
    /// Core Text (diversa da zero per una riga sillabata, composta a parte con il trattino aggiunto).
    let composedRange: NSRange
    let composedOffset: Int
    let map: TextMap
    /// Larghezze, in punti, senza gli spazi finali: del testo prima di giustificarlo, del testo come è composto, e quella
    /// a disposizione della riga.
    public let naturalWidth: CGFloat
    public let width: CGFloat
    public let availableWidth: CGFloat
    /// Per una riga dentro la cella di una tabella: il riquadro della cella sulla pagina (decide a quale cella va un clic).
    public internal(set) var cell: CGRect? = nil

    public var isNote: Bool { noteRange != nil }

    /// L'indice, nella riga di Core Text, che corrisponde a una posizione del documento.
    func stringIndex(forDocument index: Int) -> Int {
        let composed = map.composedIndex(forDocument: index) ?? (index <= range.location ? composedRange.location : NSMaxRange(composedRange))
        return min(max(composed, composedRange.location), NSMaxRange(composedRange)) - composedOffset
    }

    /// La posizione del documento che corrisponde a un indice della riga di Core Text.
    func documentIndex(forString index: Int) -> Int {
        map.documentIndex(forComposed: min(max(index + composedOffset, composedRange.location), NSMaxRange(composedRange)))
    }
}

/// Il segno di una voce di elenco (un simbolo o un numero), collocato sulla pagina accanto alla prima riga della voce.
/// Non fa parte del testo del documento: il cursore non ci entra.
/// Una parte composta di una testata (vedi `HeadingComposition`), pronta da posare.
struct HeadingPiece {
    enum Kind {
        case text(CTLine, descent: CGFloat, leading: CGFloat, width: CGFloat)
        case rule(length: CGFloat?)
        case space
    }
    let kind: Kind
    let height: CGFloat
    let alignment: HeadingAlignment
    /// Il posto della parte nella testata dello stile (`HeadingComposition.parts`); -1 se non viene da lì.
    var part = -1
}

/// Dove una parte della testata di un titolo è stata posata: la sua fascia (larga quanto lo specchio) o, per il numero
/// accanto al titolo, il riquadro del numero. Serve alla progettazione, per prenderla con il mouse.
public struct PlacedHeadingPart: Sendable {
    /// Il titolo, come in `PlacedLine.paragraphLocation`.
    public let paragraphLocation: Int
    /// Il posto della parte in `HeadingComposition.parts`.
    public let part: Int
    /// Con l'origine della pagina in basso a sinistra.
    public let rect: CGRect
}

public struct PlacedMarker {
    public let line: CTLine
    /// Inizio della linea di base, con l'origine della pagina in basso a sinistra.
    public internal(set) var origin: CGPoint
    /// Il paragrafo a cui il segno appartiene, come in `PlacedLine.paragraphLocation`.
    public let paragraphLocation: Int
}

public struct LaidOutPage {
    /// Il formato e i margini di questa pagina (il suo tipo di pagina, già scelto tra dispari, pari e prima pagina).
    public internal(set) var setup: PageSetup = .a4
    /// Il nome del tipo di pagina; `nil` per il predefinito.
    public internal(set) var typeName: String?
    /// Il numero della pagina come si scrive (dalla Lista che numera le pagine), e il suo valore.
    public internal(set) var number = ""
    public internal(set) var numberValue = 0
    public var lines: [PlacedLine] = []
    /// I segni delle voci di elenco che cominciano in questa pagina.
    public var markers: [PlacedMarker] = []
    /// Le parti delle testate dei titoli posate in questa pagina.
    public var headingParts: [PlacedHeadingPart] = []
    /// I filetti liberi dei paragrafi posati in questa pagina (sono anche fra i `rules`, che li disegnano).
    public var paragraphRules: [PlacedParagraphRule] = []
    /// Filetti da disegnare sulla pagina (il separatore sopra le note, i filetti delle tabelle), come rettangoli pieni.
    public var rules: [CGRect] = []
    /// Fondi colorati (delle celle delle tabelle), da disegnare prima dei filetti e del testo.
    public var fills: [PlacedFill] = []
    /// Le immagini delle figure, con il loro posto (origine della pagina in basso a sinistra).
    public var images: [PlacedImage] = []
}

/// Un rettangolo pieno di un colore (il fondo di una cella).
public struct PlacedFill {
    public internal(set) var rect: CGRect
    public let color: CGColor
}

/// L'immagine di una figura collocata sulla pagina.
public struct PlacedImage {
    public let image: ImageObject
    public internal(set) var rect: CGRect
}

public struct PageStartPlacement {
    public let style: String
    public let requested: Double
    public let effective: Double
    let pageIndex: Int
}

public struct DocumentLayout {
    public internal(set) var pageStarts: [Int: PageStartPlacement] = [:]
    /// Il tipo di pagina predefinito del documento; ogni pagina ha il suo in `LaidOutPage.setup`.
    public let setup: PageSetup

    /// Il formato e i margini della pagina `index` (da 0).
    public func setup(forPage index: Int) -> PageSetup { pages.indices.contains(index) ? pages[index].setup : setup }
    public let text: NSAttributedString
    public let pages: [LaidOutPage]
    /// Le note a piè di pagina, in ordine: per ciascuna, i caratteri del documento dal richiamo alla fine del testo.
    public let notes: [NSRange]
    /// Le Liste che sono andate oltre il loro ultimo valore senza che sia stato deciso che cosa fare,
    /// nell'ordine in cui succede: i loro segni sono provvisori.
    public var listsNeedingOverflowChoice: [String] = []
    /// Le note a margine che si sovrappongono a un'altra o escono dal fondo dello specchio: i caratteri del loro testo.
    /// Restano dove sono; la vista delle pagine le segnala, da sistemare a mano.
    public var marginConflicts: [NSRange] = []
    /// I tratti che chiedono Graphite ma sono composti con Core Text: la libreria non c'è, o il loro font non ha le
    /// tabelle Graphite.
    public var graphiteFallbacks = 0
    /// Le regole che dipendono dalla composizione applicate a ciascun paragrafo (chiave: la sua posizione nel testo).
    public var layoutRulesApplied: [Int: [TextRule]] = [:]
    /// Il segno composto davanti a ogni voce di elenco o di Lista (chiave: la posizione del paragrafo), e quello di ogni
    /// nota o figura numerata (chiave: la posizione del richiamo). Per l'albero degli oggetti.
    public var listMarks: [Int: String] = [:]
    public var noteMarks: [Int: String] = [:]
}

/// Le scelte tipografiche che valgono per tutto il documento.
public struct LayoutOptions: Equatable, Sendable {
    /// Applica la spaziatura dipendente dal corpo della tabella `trak`.
    public var appliesFontTracking: Bool
    /// Allinea ai margini i bordi ottici dei glifi (tabella `opbd`, o `lfbd`/`rtbd` nei font OpenType):
    /// virgolette, trattini e punti sporgono leggermente, e il margine appare più diritto.
    public var usesOpticalMargins: Bool
    /// Quanto i glifi del testo giustificato possono allargarsi o stringersi, in frazione della loro larghezza.
    /// Zero spegne l'espansione microtipografica.
    public var glyphExpansionLimit: Double
    public static let defaultGlyphExpansionLimit = 0.02
    /// Lingua (per esempio "it") con cui sillabare il testo che non ne ha una propria (attributo `.language`);
    /// `nil` per sillabare solo il testo che dichiara la sua.
    public var hyphenationLanguage: String?
    /// Se dividere le parole a fine riga.
    public var hyphenates: Bool
    /// Come si scelgono gli a capo.
    public var lineBreaking: LineBreaking
    /// Le Liste del documento, a cui rimandano le voci con un nome.
    public var lists: [ListDefinition]
    /// Gli stili di flottante: ogni flottante si numera con la Lista del suo stile (`nil`, o una lista che non c'è, per
    /// i numeri 1, 2, 3…).
    public var floatStyles: [FloatStyle]
    /// Gli stili con un nome: servono a comporre il contenuto dei flottanti con il loro stile di paragrafo.
    public var styles: StyleSheet
    /// Le regole del motore, compilate dalle formule contestuali degli stili all'inizio di ogni composizione.
    var rules: [TextRule] = []
    public var fontRoles = FontRoleTable()
    /// I tipi di pagina con un nome, che le sezioni scelgono.
    public var pageTypes: [PageType] = []
    /// La Lista che numera le pagine dall'inizio; `nil` per 1, 2, 3.
    public var pageNumbering: String?
    /// Gli stili di tabella.
    public var tableStyles: [TableStyle] = TableStyle.builtIn

    /// Le sole scelte che contano per comporre in righe un paragrafo già pronto: le memorie delle righe e degli a capo
    /// le usano come chiave, così un cambio degli stili, delle liste o delle regole non le svuota (i paragrafi che lo
    /// stile cambia hanno già un testo diverso, e si ricompongono da sé).
    struct LineComposition: Hashable, Sendable {
        let appliesFontTracking: Bool
        let usesOpticalMargins: Bool
        let glyphExpansionLimit: Double
        let hyphenationLanguage: String?
        let hyphenates: Bool
        let lineBreaking: LineBreaking
    }

    var lineComposition: LineComposition {
        LineComposition(appliesFontTracking: appliesFontTracking, usesOpticalMargins: usesOpticalMargins, glyphExpansionLimit: glyphExpansionLimit,
                        hyphenationLanguage: hyphenationLanguage, hyphenates: hyphenates, lineBreaking: lineBreaking)
    }

    /// La Lista delle note a piè di pagina.
    public var noteList: String? {
        get { floatStyles.first { $0.name == FloatStyle.footnoteName }?.listName }
        set {
            if let index = floatStyles.firstIndex(where: { $0.name == FloatStyle.footnoteName }) { floatStyles[index].listName = newValue }
            else { floatStyles.append(.footnote(listName: newValue)) }
        }
    }

    public enum LineBreaking: Sendable {
        /// Sull'intero paragrafo, cercando gli spazi più uniformi (Knuth e Plass, come TeX).
        case optimal
        /// Una riga alla volta, riempiendola il più possibile.
        case firstFit
    }

    public init(appliesFontTracking: Bool = true, usesOpticalMargins: Bool = true, glyphExpansionLimit: Double = defaultGlyphExpansionLimit,
                hyphenationLanguage: String? = nil, hyphenates: Bool = true, lineBreaking: LineBreaking = .optimal, lists: [ListDefinition] = [],
                noteList: String? = nil, floatStyles: [FloatStyle]? = nil, styles: StyleSheet = StyleSheet()) {
        self.appliesFontTracking = appliesFontTracking
        self.styles = styles
        self.lists = lists
        self.floatStyles = floatStyles ?? [.footnote(listName: noteList)]
        self.usesOpticalMargins = usesOpticalMargins
        self.glyphExpansionLimit = glyphExpansionLimit
        self.hyphenationLanguage = hyphenationLanguage
        self.hyphenates = hyphenates
        self.lineBreaking = lineBreaking
    }

    /// Le lingue che si sanno sillabare, tra quelle date: con il dizionario del sistema o con i modelli di TeX.
    public static func hyphenationLanguages(among candidates: [String]) -> [String] {
        candidates.filter(Hyphenation.isAvailable)
    }
}

/// Impaginazione costruita direttamente su Core Text: `CTTypesetter` spezza le righe, noi le collochiamo.
///
/// Gestisce il flusso dei paragrafi (allineamento, rientri, spaziature), gli elenchi e le note a piè di pagina.
/// Le tabelle arriveranno qui.
public enum PageLayout {
    /// Composizione semplice: la sola scelta sulla spaziatura `trak`, senza margini ottici né sillabazione,
    /// con gli a capo riga per riga.
    public static func layout(_ source: NSAttributedString, setup: PageSetup = .a4, appliesFontTracking: Bool = true) -> DocumentLayout {
        layout(source, setup: setup, options: LayoutOptions(appliesFontTracking: appliesFontTracking, usesOpticalMargins: false, lineBreaking: .firstFit))
    }

    public static func layout(_ source: NSAttributedString, setup: PageSetup = .a4, options originalOptions: LayoutOptions) -> DocumentLayout {
        var options = originalOptions
        let compiled = options.styles.compilingStyleRules()
        options.styles = compiled.sheet
        options.rules = compiled.rules
        // Le regole danno il loro aspetto a una copia del testo, prima della spaziatura `trak`, che dipende dal corpo.
        var graphite = (graphite: 0, coreText: 0)
        let text = prepared(Rules.applied(to: source, sheet: options.styles, resolver: FontRoleResolver(table: options.fontRoles)), appliesFontTracking: options.appliesFontTracking,
                            documentLanguage: options.hyphenationLanguage, graphite: &graphite)
        // Le note numerate pagina per pagina: la prima composizione suppone che ogni nota stia nella pagina dove comincia
        // il suo paragrafo; se non è così, si ricompone con le pagine vere. Il numero cambia la larghezza del richiamo,
        // e quindi forse gli a capo: si ripete finché le pagine non cambiano più, ma non all'infinito.
        var pass = layoutPass(text, setup: setup, options: options, notePages: nil, pageCount: nil)
        let pageLists = options.floatStyles.compactMap(\.listName).filter { name in options.lists.first { $0.name == name }?.parent == .page }
        if !pageLists.isEmpty {
            for _ in 0..<3 where pass.assumedNotePages != pass.notePages {
                pass = layoutPass(text, setup: setup, options: options, notePages: pass.notePages, pageCount: nil)
            }
        }
        // Le presentazioni possono cambiare gli a capo. Le letture di pagina usano le posizioni
        // osservate nel passaggio precedente, anche quando il numero totale di pagine non cambia.
        let readsPageCount = usesPageCount(text) || options.styles.styles.contains {
            $0.heading?.readsPageCount == true || $0.writes.contains { $0.formula.presentationRead == .pageCount }
        }
        var count: Int?
        for _ in 0..<3 {
            let resolved = pass.pageNumbers.resolved(in: pass.layout)
            let total = readsPageCount ? pass.layout.pages.count : nil
            guard count != total || resolved != pass.pageNumbers else { break }
            count = total
            pass = layoutPass(text, setup: setup, options: options, notePages: pass.notePages, pageCount: count, pageNumbers: resolved)
        }
        var layout = pass.layout
        layout.graphiteFallbacks = graphite.coreText
        return layout
    }

    private struct PresentationPageNumbers: Equatable {
        var fields: [Int: String] = [:]
        var paragraphs: [Int: String] = [:]

        func resolved(in layout: DocumentLayout) -> Self {
            var result = self
            var remainingFields = Set(fields.keys)
            var remainingParagraphs = Set(paragraphs.keys)
            for page in layout.pages {
                if remainingFields.isEmpty && remainingParagraphs.isEmpty { break }
                if !remainingFields.isEmpty {
                    for field in page.fieldRects where remainingFields.remove(field.location) != nil {
                        result.fields[field.location] = page.number
                    }
                }
                if !remainingParagraphs.isEmpty {
                    for line in page.lines where !line.isNote && remainingParagraphs.remove(line.paragraphLocation) != nil {
                        result.paragraphs[line.paragraphLocation] = page.number
                    }
                }
            }
            // Una numerazione senza testo può lasciare un campo senza glifi.
            for location in remainingFields where fields[location] == "" {
                if let page = layout.locatedLine(for: location, affinity: .downstream)?.page {
                    result.fields[location] = layout.pages[page].number
                }
            }
            return result
        }
    }

    /// Vero se nel testo c'è un campo con il numero delle pagine.
    private static func usesPageCount(_ text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.field, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if (value as? String) == Field.pageCount.encoded { found = true; stop.pointee = true }
        }
        return found
    }

    /// `knownPages` indica la pagina supposta di ciascun richiamo di nota.
    private static func layoutPass(_ text: NSAttributedString, setup: PageSetup, options: LayoutOptions, notePages knownPages: [Int: Int]?,
                                   pageCount: Int?, pageNumbers assumedPageNumbers: PresentationPageNumbers = PresentationPageNumbers())
        -> (layout: DocumentLayout, assumedNotePages: [Int: Int], notePages: [Int: Int], pageNumbers: PresentationPageNumbers) {
        let string = text.string as NSString
        var column = setup.textRect
        var pages = [LaidOutPage()]
        // I tipi di pagina: ogni pagina prende quello indicato dalle sezioni aperte quando comincia (le più interne per prime;
        // dispari e pari si ereditano, la prima pagina vale solo per la sezione che la indica).
        let namedTypes = Dictionary(options.pageTypes.map { ($0.name, $0.setup) }, uniquingKeysWith: { first, _ in first })
        var openSections: [(declared: Int, mark: SectionMark, title: String, number: String?)] = []
        var pageNumbers = PresentationPageNumbers()
        func fieldContext() -> FieldContext {
            FieldContext(pageNumber: pages[pages.count - 1].number,
                         pageCount: pageCount.map(String.init) ?? "?",
                         sections: openSections.map { FieldContext.Section(role: $0.mark.role, title: $0.title, number: $0.number) })
        }
        // I paragrafi che dopo una sezione interna tornano a quella esterna (vuoto: fuori da ogni sezione), solo quelli che
        // contano: da lì valgono di nuovo il tipo di pagina, le testatine e i campi della sezione esterna. Il testo continua
        // sulla stessa pagina.
        var returns: [Int: String] = [:]
        for case .back(let range, let target) in SectionEditing.structure(in: text).events where range.length > 0 { returns[range.location] = target }
        // La numerazione delle pagine: la Lista in corso e il valore della pagina in corso.
        let listsByName = Dictionary(options.lists.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var pageNumbering = options.pageNumbering.flatMap { listsByName[$0] }
        var pageValue = (pageNumbering?.start ?? 1) - 1
        func pageNumberText(_ value: Int) -> String {
            guard let list = pageNumbering else { return String(value) }
            return list.counter == .none ? list.prefix + list.suffix : list.prefix + list.counter.text(for: value) + list.suffix
        }
        // Intestazioni e piè di pagina: quelli in corso (fino al prossimo dello stesso tipo), quelli per la prima pagina di una
        // sezione, e per ogni pagina ciò che era in corso al suo inizio (con le sezioni, per i campi).
        struct RunningEntry {
            var note: ComposedNote
            var paragraphStyle: NSParagraphStyle
        }
        struct RunningKey: Hashable {
            var placement: FloatStyle.Placement
            var pages: FloatStyle.RunningPages
        }
        struct FirstKey: Hashable {
            var placement: FloatStyle.Placement
            var section: String?
        }
        var runningActive: [RunningKey: RunningEntry] = [:]
        var runningFirst: [FirstKey: RunningEntry] = [:]
        var pageRunning: [[RunningKey: RunningEntry]] = []
        var pageSections: [[(role: String, title: String, number: String?)]] = []
        /// Le pagine aperte da una sezione che comincia su una pagina nuova, con l'identità della sezione.
        var openingPages: [Int: String] = [:]
        /// Ciò che vale per la pagina in corso: le intestazioni e le sezioni in corso adesso.
        func snapshotPage() {
            let index = pages.count - 1
            while pageRunning.count <= index {
                pageRunning.append([:])
                pageSections.append([])
            }
            pageRunning[index] = runningActive
            pageSections[index] = openSections.map { ($0.mark.role, $0.title, $0.number) }
        }
        /// Numera la pagina appena aperta.
        func numberNewPage() {
            pageValue += 1
            pages[pages.count - 1].numberValue = pageValue
            pages[pages.count - 1].number = pageNumberText(pageValue)
            snapshotPage()
        }
        /// Le parti di una testata, composte: le righe di testo con il loro stile, i filetti, gli spazi.
        func headingPieces(_ parts: [HeadingPart], number: String, titleStyle: String?, indices: [Int] = []) -> [HeadingPiece] {
            let resolver = FontRoleResolver(table: options.fontRoles)
            func text(_ string: String, _ style: String?, _ alignment: HeadingAlignment, _ minHeight: Double?) -> HeadingPiece {
                // Lo stile della parte: di paragrafo, al posto di quello del titolo; di carattere o di parola, sopra di esso.
                let target = style.flatMap { options.styles.style(named: $0)?.target }
                let character = options.styles.resolveCharacter(
                    paragraphStyle: target == .paragraph ? style : titleStyle, wordStyle: target == .word ? style : nil,
                    characterStyle: target == .character ? style : nil, base: TextStyling.styleBase, resolver: resolver)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: TextStyling.characterAttributes(for: character).attributes))
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                let natural = ascent + descent + leading
                return HeadingPiece(kind: .text(line, descent: descent, leading: leading, width: width),
                                    height: max(natural, CGFloat(minHeight ?? 0)), alignment: alignment)
            }
            let context = fieldContext()
            func composedPiece(_ part: HeadingPart) -> HeadingPiece? {
                switch part {
                case .label(_, let style, let alignment, let minHeight),
                     .number(_, let style, let alignment, let minHeight),
                     .result(_, _, let style, let alignment, let minHeight):
                    return part.presentationText(in: context, openedNumber: number).map { text($0, style, alignment, minHeight) }
                case .numberBeside(_, let style, let side, _):
                    return part.presentationText(in: context, openedNumber: number).map { text($0, style, side, nil) }
                case .title:
                    return nil
                case .rule(let thickness, let length, let alignment):
                    return HeadingPiece(kind: .rule(length: length.map { CGFloat($0) }), height: CGFloat(thickness), alignment: alignment)
                case .space(let length):
                    return HeadingPiece(kind: .space, height: CGFloat(length), alignment: .left)
                }
            }
            return parts.enumerated().compactMap { offset, part -> HeadingPiece? in
                var piece = composedPiece(part)
                piece?.part = indices.indices.contains(offset) ? indices[offset] : -1
                return piece
            }
        }
        /// Posa le parti di una testata dall'altezza in corso, una sotto l'altra. Il testo poggia sul fondo della sua
        /// fascia (un'altezza minima la allarga verso l'alto); esterno e interno seguono le pagine affacciate.
        func placeHeading(_ pieces: [HeadingPiece], paragraphLocation: Int) {
            guard !pieces.isEmpty else { return }
            let index = pages.count - 1
            let leftPage = pages[index].setup.facing && index % 2 == 1
            func x(_ alignment: HeadingAlignment, width: CGFloat) -> CGFloat {
                switch alignment.resolved(onLeftPage: leftPage) {
                case .right: column.maxX - width
                case .center: column.minX + (column.width - width) / 2
                default: column.minX
                }
            }
            for piece in pieces {
                if piece.part >= 0 {
                    // La fascia della parte; per un filetto, il filetto stesso (serve la sua lunghezza).
                    var rect = CGRect(x: column.minX, y: column.maxY - y - piece.height, width: column.width, height: piece.height)
                    if case .rule(let length) = piece.kind {
                        let width = min(length ?? column.width, column.width)
                        rect.origin.x = x(piece.alignment, width: width)
                        rect.size.width = width
                    }
                    pages[index].headingParts.append(PlacedHeadingPart(paragraphLocation: paragraphLocation, part: piece.part, rect: rect))
                }
                switch piece.kind {
                case .space: break
                case .rule(let length):
                    let width = min(length ?? column.width, column.width)
                    pages[index].rules.append(CGRect(x: x(piece.alignment, width: width), y: column.maxY - y - piece.height, width: width, height: piece.height))
                case .text(let line, let descent, let leading, let width):
                    let baseline = column.maxY - (y + piece.height - descent - leading)
                    pages[index].markers.append(PlacedMarker(line: line, origin: CGPoint(x: x(piece.alignment, width: width), y: baseline),
                                                             paragraphLocation: paragraphLocation))
                }
                y += piece.height
            }
        }
        /// I filetti liberi di un paragrafo già posato: quelli sopra sulla prima pagina, quelli sotto sull'ultima, quelli ai
        /// lati su ogni pagina, lungo le sue righe. Non occupano spazio.
        func placeParagraphRules(_ rules: [ParagraphRule], paragraph: Int, fromPage: Int) {
            let indices = (max(fromPage, 0)..<pages.count).filter { pages[$0].lines.contains { !$0.isNote && $0.paragraphLocation == paragraph } }
            for (position, index) in indices.enumerated() {
                let lines = pages[index].lines.filter { !$0.isNote && $0.paragraphLocation == paragraph }
                guard let top = lines.map({ $0.origin.y + $0.ascent }).max(), let bottom = lines.map({ $0.origin.y - $0.descent }).min() else { continue }
                let box = lines.first?.cell ?? pages[index].setup.textRect(forPage: index)
                for (number, rule) in rules.enumerated() {
                    let t = CGFloat(rule.thickness), offset = CGFloat(rule.offset), start = CGFloat(rule.start), end = CGFloat(rule.end)
                    let rect: CGRect? = switch rule.anchor {
                    case .top where position == 0: CGRect(x: box.minX - start, y: top + offset, width: box.width + start + end, height: t)
                    case .bottom where position == indices.count - 1: CGRect(x: box.minX - start, y: bottom - offset - t, width: box.width + start + end, height: t)
                    case .left: CGRect(x: box.minX - offset - t, y: bottom - end, width: t, height: top - bottom + start + end)
                    case .right: CGRect(x: box.maxX + offset, y: bottom - end, width: t, height: top - bottom + start + end)
                    default: nil
                    }
                    guard let rect, rect.width > 0, rect.height > 0 else { continue }
                    pages[index].rules.append(rect)
                    pages[index].paragraphRules.append(PlacedParagraphRule(paragraphLocation: paragraph, rule: number, rect: rect))
                }
            }
        }
        /// Il testo di un campo, nel punto della composizione in cui si è.
        func fieldText(_ field: Field, at location: Int) -> String {
            guard let write = field.asFormula.presentationWrite() else { return "" }
            var context = fieldContext()
            if case .read(.pageNumber) = write.expression {
                let style = text.attribute(.footnote, at: location, effectiveRange: nil) as? String
                // Le testatine ripetute vengono risolte di nuovo sulla pagina di ciascuna copia.
                if !options.floatStyles.contains(where: { $0.name == style && $0.placement.isRunning }) {
                    context.pageNumber = assumedPageNumbers.fields[location] ?? context.pageNumber
                    pageNumbers.fields[location] = context.pageNumber
                }
            }
            return write.text(in: context) ?? ""
        }
        /// Il tipo della pagina `number`: il nome (`nil` per il predefinito) e le misure.
        func pageType(number: Int, sectionFirst: Bool) -> (name: String?, setup: PageSetup) {
            func named(_ name: String?) -> (name: String?, setup: PageSetup)? {
                guard let name else { return nil }
                if name == PageType.defaultName { return (nil, setup) }
                return namedTypes[name].map { (name, $0) }
            }
            if sectionFirst, let first = named(openSections.last?.mark.pageTypes.firstPage) { return first }
            if number % 2 == 0, let even = openSections.reversed().lazy.compactMap({ named($0.mark.pageTypes.evenPages) }).first { return even }
            return openSections.reversed().lazy.compactMap { named($0.mark.pageTypes.pages) }.first ?? (nil, setup)
        }
        /// Dà alla pagina in corso il suo tipo, e lo specchio con cui comporla.
        func applyPageSetup(sectionFirst: Bool = false) {
            let chosen = pageType(number: pages.count, sectionFirst: sectionFirst)
            pages[pages.count - 1].setup = chosen.setup
            pages[pages.count - 1].typeName = chosen.name
            column = chosen.setup.textRect
        }
        applyPageSetup()
        numberNewPage()
        var y: CGFloat = 0  // distanza dal bordo superiore dello specchio
        var location = 0
        var noteNumber = 0
        var notes: [NSRange] = []
        var listMarks: [Int: String] = [:]
        var noteMarks: [Int: String] = [:]
        var numbering = ListNumbering()
        // Le Liste con un nome: una numerazione per il testo e una a parte per le note, perché una nota non
        // interrompe l'elenco in cui sta.
        var named = ListNumberer(definitions: options.lists)
        var noteNumberer = ListNumberer(definitions: options.lists)
        /// La Lista di ogni stile di flottante, se esiste.
        var floatLists: [String: String] = [:]
        for style in options.floatStyles {
            if let name = style.listName, options.lists.contains(where: { $0.name == name }) { floatLists[style.name] = name }
        }
        var overflowing: [String] = []
        func noticeOverflow(_ mark: ListMark, in name: String) {
            if mark.needsOverflowChoice, !overflowing.contains(name) { overflowing.append(name) }
        }
        var assumedNotePages: [Int: Int] = [:]
        var notePages: [Int: Int] = [:]
        /// Il segno della prossima nota, il cui richiamo sta alla posizione `anchor`.
        func noteMark(anchor: Int) -> String {
            let mark = computeNoteMark(anchor: anchor)
            noteMarks[anchor] = mark
            return mark
        }
        func computeNoteMark(anchor: Int) -> String {
            let style = text.attribute(.footnote, at: anchor, effectiveRange: nil) as? String ?? FloatStyle.footnoteName
            guard let noteList = floatLists[style] else {
                noteNumber += 1
                return String(noteNumber)
            }
            let page = knownPages?[anchor] ?? pages.count
            assumedNotePages[anchor] = page
            noteNumberer.setPage(page)
            guard let mark = noteNumberer.next(noteList) else { return "" }
            noticeOverflow(mark, in: noteList)
            return mark.text
        }
        /// Il segno da comporre davanti a un paragrafo, e la voce da usare per il rientro; `nil` se il paragrafo non
        /// è una voce. Fa avanzare le numerazioni.
        func listMarker(for item: ListItem?) -> (item: ListItem, text: String)? {
            if let item, let name = item.listName {
                _ = numbering.next(nil)
                guard let mark = named.next(name) else {
                    named.interrupt()
                    return nil
                }
                noticeOverflow(mark, in: name)
                // Le misure: quelle della voce, poi quelle della Lista; il livello è la profondità della Lista.
                var shown = ListItem(marker: mark.text, level: named.depth(of: name) + 1)
                let measures = item.resolvedMeasures(in: options.lists)
                shown.textIndent = measures.textIndent
                shown.markerPosition = measures.markerPosition
                return (shown, mark.text)
            }
            named.interrupt()
            guard let item, let text = numbering.next(item) else {
                _ = numbering.next(nil)
                return nil
            }
            return (item, text)
        }
        /// Una riga di nota in attesa di essere collocata in fondo alla pagina.
        struct NoteEntry {
            var line: ComposedLine
            var info: ComposedNote
        }
        // Le righe di nota della pagina in corso: vanno in fondo, quando la pagina si chiude.
        var pageNotes: [NoteEntry] = []
        // Le righe di nota che non sono entrate nella pagina del loro richiamo: continuano in fondo alla successiva.
        var carried: [NoteEntry] = []

        /// La posizione della serie di una nota: quella del suo stile di flottante (uno sconosciuto va in fondo).
        func seriesIndex(_ info: ComposedNote) -> Int { options.floatStyles.firstIndex { $0.name == info.style.name } ?? options.floatStyles.count }
        /// Le righe di nota raggruppate per serie, nell'ordine degli stili, e dentro ogni serie nell'ordine dei richiami.
        func ordered(_ entries: [NoteEntry]) -> [NoteEntry] {
            entries.enumerated().sorted { (seriesIndex($0.element.info), $0.offset) < (seriesIndex($1.element.info), $1.offset) }.map(\.element)
        }
        /// L'altezza del blocco delle note: ogni serie comincia con il suo separatore (gli spazi del filetto), tra una nota
        /// e l'altra c'è un piccolo distacco.
        func notesHeight(_ entries: [NoteEntry]) -> CGFloat {
            guard !entries.isEmpty else { return 0 }
            // Nell'ordine di `ordered`, ma ordinando solo le posizioni: copiare le note costa.
            let series = entries.map { seriesIndex($0.info) }
            let order = entries.indices.sorted { (series[$0], $0) < (series[$1], $1) }
            var total: CGFloat = 0
            var previous: Int?
            for index in order {
                let entry = entries[index]
                if let previous, series[previous] == series[index] {
                    if entries[previous].info.range != entry.info.range { total += noteGap }
                } else {
                    total += CGFloat(entry.info.style.spaceAbove + entry.info.style.spaceBelow)
                }
                total += entry.line.height + entry.line.spacingAfter
                previous = index
            }
            return total
        }
        var pageNotesHeight: CGFloat { notesHeight(pageNotes) }
        /// Di quanto cresce il blocco delle note aggiungendo queste righe.
        func addedHeight(_ entries: [NoteEntry]) -> CGFloat { notesHeight(pageNotes + entries) - pageNotesHeight }

        func addToPage(_ entry: NoteEntry) { pageNotes.append(entry) }

        /// Le righe del testo di una nota. Se la nota finisce con un a capo, dopo c'è un paragrafo vuoto: gli spetta una
        /// riga, per il cursore.
        func noteLines(_ note: ComposedNote, paragraphStyle: NSParagraphStyle, width: CGFloat? = nil, composedStyle: NSParagraphStyle? = nil) -> [ComposedLine] {
            let noteStyle = composedStyle ?? noteParagraphStyle(for: note.style, from: paragraphStyle, options: options)
            var lines = composedLines(note.text, style: noteStyle, width: width ?? column.width, options: options)
            if let last = lines.last, note.text.length > 0, TextStyling.isLineTerminator((note.text.string as NSString).character(at: note.text.length - 1)) {
                lines.append(ComposedLine(
                    line: CTLineCreateWithAttributedString(NSAttributedString()), composedRange: NSRange(location: note.text.length, length: 0),
                    composedOffset: note.text.length, endsWithHyphen: false, ascent: last.ascent, descent: last.descent, height: last.height,
                    baselineFromTop: last.baselineFromTop, x: 0, spacingAfter: last.spacingAfter))
            }
            return lines
        }
        // Le note a margine già collocate in ogni pagina, per accorgersi di quelle che si sovrappongono.
        var marginBoxes: [Int: [(box: CGRect, range: NSRange)]] = [:]
        var marginConflicts: [NSRange] = []
        /// Mette una nota a margine accanto alla riga che la richiama: nel margine esterno (a destra nelle pagine dispari,
        /// a sinistra nelle pari), con la prima riga sulla stessa linea di base. Non si sposta per far posto ad altre.
        func placeMarginNote(_ note: ComposedNote, beside anchorLine: PlacedLine, paragraphStyle: NSParagraphStyle) {
            let pageIndex = pages.count - 1
            let rightSide = pageIndex % 2 == 0  // la prima pagina è dispari
            let gap: CGFloat = 9
            // Con le pagine affacciate il margine esterno è sempre `right`: nelle pagine pari, che si spostano a comporre
        // finito, sta a sinistra.
        let page = pages[pageIndex].setup
        let margin = page.facing ? page.right : (rightSide ? page.paperSize.width - column.maxX : column.minX)
            let width = max(margin - 2 * gap, 24)
            let left = rightSide ? column.maxX + gap : column.minX - gap - width
            // In una colonna così stretta il testo giustificato verrebbe male: a bandiera, salvo uno stile del contenuto.
            var composedStyle: NSParagraphStyle?
            if note.style.contentStyle == nil {
                let ragged = NSMutableParagraphStyle()
                ragged.alignment = .natural
                ragged.lineHeightMultiple = paragraphStyle.lineHeightMultiple
                composedStyle = ragged
            }
            let lines = noteLines(note, paragraphStyle: paragraphStyle, width: width, composedStyle: composedStyle)
            guard let first = lines.first else { return }
            var top = column.maxY - anchorLine.origin.y - first.baselineFromTop
            var box = CGRect.null
            for line in lines {
                let placedLine = placed(line, top: top, map: note.map, paragraphLocation: note.textRange.location, noteRange: note.textRange, left: left)
                pages[pageIndex].lines.append(placedLine)
                box = box.union(CGRect(x: left, y: placedLine.origin.y - placedLine.descent, width: width, height: placedLine.ascent + placedLine.descent))
                top += line.height + line.spacingAfter
            }
            func flag(_ range: NSRange) { if !marginConflicts.contains(range) { marginConflicts.append(range) } }
            // Si sovrappone a un'altra (con mezzo punto di tolleranza), o esce dal fondo dello specchio: si segnalano.
            if box.minY < column.minY - 0.5 { flag(note.textRange) }
            for other in marginBoxes[pageIndex] ?? [] where other.box.insetBy(dx: 0, dy: 0.5).intersects(box) {
                flag(other.range)
                flag(note.textRange)
            }
            marginBoxes[pageIndex, default: []].append((box, note.textRange))
        }
        // Le note di chiusura, nell'ordine dei richiami, con lo stile del paragrafo che le richiama.
        var endNotes: [(info: ComposedNote, paragraphStyle: NSParagraphStyle)] = []

        func placed(_ line: ComposedLine, top: CGFloat, map: TextMap, paragraphLocation: Int, noteRange: NSRange?, left: CGFloat? = nil) -> PlacedLine {
            let start = map.documentIndex(forComposed: line.composedRange.location)
            let end = map.documentIndex(forComposed: NSMaxRange(line.composedRange))
            return PlacedLine(
                line: line.line, origin: CGPoint(x: (left ?? column.minX) + line.x, y: column.maxY - (top + line.baselineFromTop)),
                range: NSRange(location: start, length: max(end - start, 0)), paragraphLocation: paragraphLocation,
                endsWithHyphen: line.endsWithHyphen, ascent: line.ascent, descent: line.descent, noteRange: noteRange,
                composedRange: line.composedRange, composedOffset: line.composedOffset, map: map,
                naturalWidth: line.naturalWidth, width: line.width, availableWidth: line.availableWidth)
        }

        // MARK: Figure

        /// Un disegno già composto, con le posizioni dal suo bordo alto (`top` cresce verso il basso) e le ascisse della
        /// pagina: una tabella, che si colloca tutta insieme (come flottante) o riga per riga.
        struct BlockDrawing {
            struct Line {
                var line: ComposedLine
                var top: CGFloat
                var left: CGFloat
                var map: TextMap
                var paragraphLocation: Int
                /// Il riquadro della cella, con `y` come distanza dal bordo alto del disegno.
                var cell: CGRect?
            }
            var lines: [Line] = []
            /// Rettangoli con `y` come distanza dal bordo alto del disegno.
            var rules: [CGRect] = []
            var fills: [(rect: CGRect, color: CGColor)] = []
            var height: CGFloat = 0

            /// Aggiunge un altro disegno, spostato in basso di `offset`.
            mutating func append(_ other: BlockDrawing, at offset: CGFloat) {
                lines += other.lines.map { var line = $0; line.top += offset; line.cell?.origin.y += offset; return line }
                rules += other.rules.map { $0.offsetBy(dx: 0, dy: offset) }
                fills += other.fills.map { ($0.rect.offsetBy(dx: 0, dy: offset), $0.color) }
            }
        }

        /// Mette un disegno nella pagina in corso, con il bordo alto a `top` (dal bordo alto dello specchio).
        func emit(_ drawing: BlockDrawing, top: CGFloat) {
            func onPage(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: column.maxY - top - rect.minY - rect.height, width: rect.width, height: rect.height) }
            for fill in drawing.fills { pages[pages.count - 1].fills.append(PlacedFill(rect: onPage(fill.rect), color: fill.color)) }
            for rule in drawing.rules { pages[pages.count - 1].rules.append(onPage(rule)) }
            for item in drawing.lines {
                var line = placed(item.line, top: top + item.top, map: item.map, paragraphLocation: item.paragraphLocation, noteRange: nil, left: item.left)
                line.cell = item.cell.map(onPage)
                pages[pages.count - 1].lines.append(line)
            }
        }

        /// Una figura (o una tabella flottante) pronta da collocare: per una figura la didascalia composta e l'immagine con
        /// le misure ridotte alla colonna; per una tabella il suo disegno, didascalia compresa.
        struct FigureBlock {
            var style: FloatStyle
            var info: ComposedNote?
            var captionLines: [ComposedLine] = []
            var imageSize: CGSize = .zero
            var drawing: BlockDrawing?
            var height: CGFloat
        }
        let figureGap: CGFloat = 6, floatSeparation: CGFloat = 12
        // Le figure che aspettano una pagina (nel loro ordine), quelle da mettere a fine paragrafo, quelle in fondo alla
        // pagina in corso, e quante ne sono già state messe in questa pagina (in cima e in tutto).
        var deferredFigures: [FigureBlock] = []
        var hereFigures: [FigureBlock] = []
        var bottomFigures: [FigureBlock] = []
        var topFigureCount = 0, pageFigureCount = 0
        var bottomFiguresHeight: CGFloat { bottomFigures.reduce(0) { $0 + $1.height + floatSeparation } }

        func figureBlock(_ note: ComposedNote, paragraphStyle: NSParagraphStyle) -> FigureBlock {
            let natural = CGSize(width: note.image.map { CGFloat($0.width) } ?? 0, height: note.image.map { CGFloat($0.height) } ?? 0)
            let scale = natural.width > column.width ? column.width / natural.width : 1
            let size = CGSize(width: natural.width * scale, height: natural.height * scale)
            let caption = note.style.caption == .none ? [] : noteLines(note, paragraphStyle: paragraphStyle)
            let captionHeight = caption.reduce(0) { $0 + $1.height + $1.spacingAfter }
            let height = size.height + (caption.isEmpty ? 0 : figureGap + captionHeight)
            return FigureBlock(style: note.style, info: note, captionLines: caption, imageSize: size, height: height)
        }

        /// Mette una figura nella pagina in corso a partire da `top` (dal bordo alto dello specchio).
        func placeFigure(_ block: FigureBlock, top: CGFloat) {
            if let drawing = block.drawing {
                emit(drawing, top: top)
                pageFigureCount += 1
                return
            }
            guard let info = block.info else { return }
            var top = top
            func placeCaption() {
                for line in block.captionLines {
                    pages[pages.count - 1].lines.append(placed(line, top: top, map: info.map, paragraphLocation: info.textRange.location,
                                                               noteRange: info.textRange))
                    top += line.height + line.spacingAfter
                }
            }
            if block.style.caption == .above, !block.captionLines.isEmpty {
                placeCaption()
                top += figureGap
            }
            if let image = info.image {
                pages[pages.count - 1].images.append(PlacedImage(image: image, rect: CGRect(
                    x: column.minX + (column.width - block.imageSize.width) / 2, y: column.maxY - top - block.imageSize.height,
                    width: block.imageSize.width, height: block.imageSize.height)))
            }
            top += block.imageSize.height
            if block.style.caption == .below, !block.captionLines.isEmpty {
                top += figureGap
                placeCaption()
            }
            pageFigureCount += 1
        }

        /// In cima alla pagina in corso, se la figura lo ammette, c'è posto, e i limiti lo permettono (come in LaTeX: al più
        /// 2 figure in cima, 3 per pagina, la parte alta al più il 70% dello specchio).
        func tryTop(_ block: FigureBlock) -> Bool {
            let style = block.style
            guard style.positions.contains(.top) else { return false }
            let end = y + block.height
            guard end + floatSeparation + pageNotesHeight + bottomFiguresHeight <= column.height else { return false }
            if !style.ignoresLimits, topFigureCount >= 2 || pageFigureCount >= 3 || end > column.height * 0.7 { return false }
            placeFigure(block, top: y)
            y = end + floatSeparation
            topFigureCount += 1
            return true
        }

        /// In fondo alla pagina in corso, sopra le note: si riserva lo spazio e la si disegna chiudendo la pagina (al più 1
        /// figura in fondo, la parte bassa al più il 30% dello specchio).
        func tryBottom(_ block: FigureBlock) -> Bool {
            let style = block.style
            guard style.positions.contains(.bottom) else { return false }
            guard y + pageNotesHeight + bottomFiguresHeight + block.height + floatSeparation <= column.height else { return false }
            if !style.ignoresLimits, !bottomFigures.isEmpty || pageFigureCount >= 3 || bottomFiguresHeight + block.height > column.height * 0.3 { return false }
            bottomFigures.append(block)
            pageFigureCount += 1
            return true
        }

        /// Vero se prima di questa figura ne aspetta un'altra della stessa serie: l'ordine non cambia.
        func isBlocked(_ block: FigureBlock) -> Bool { deferredFigures.contains { $0.style.name == block.style.name } }

        /// Colloca in fondo alla pagina in corso le note che vi sono richiamate: una serie sotto l'altra, ciascuna con il
        /// suo filetto.
        func closePage() {
            // Prima le figure in fondo alla pagina, sopra le note.
            if !bottomFigures.isEmpty {
                var top = column.height - pageNotesHeight - bottomFiguresHeight
                for block in bottomFigures {
                    top += floatSeparation
                    placeFigure(block, top: top)
                    top += block.height
                }
                bottomFigures = []
            }
            guard !pageNotes.isEmpty else { return }
            var top = column.height - pageNotesHeight
            var previous: NoteEntry?
            for entry in ordered(pageNotes) {
                if let previous, seriesIndex(previous.info) == seriesIndex(entry.info) {
                    if previous.info.range != entry.info.range { top += noteGap }
                } else {
                    let style = entry.info.style
                    if style.showsRule {
                        pages[pages.count - 1].rules.append(CGRect(
                            x: column.minX, y: column.maxY - (top + CGFloat(style.spaceAbove)) - noteRuleThickness,
                            width: style.ruleLength.map { CGFloat($0) } ?? min(column.width / 3, 144), height: noteRuleThickness))
                    }
                    top += CGFloat(style.spaceAbove + style.spaceBelow)
                }
                pages[pages.count - 1].lines.append(placed(entry.line, top: top, map: entry.info.map, paragraphLocation: entry.info.textRange.location, noteRange: entry.info.textRange))
                top += entry.line.height + entry.line.spacingAfter
                previous = entry
            }
            pageNotes = []
        }

        /// Apre una pagina nuova e vi porta per prime le righe di nota rimaste dalla precedente. Se da sole
        /// riempiono la pagina, se ne aprono altre finché non sono finite.
        func startNewPage(sectionFirst: Bool = false) {
            closePage()
            pages.append(LaidOutPage())
            applyPageSetup(sectionFirst: sectionFirst)
            numberNewPage()
            y = 0
            while let next = carried.first {
                // Una nota che non si spezza passa tutta insieme; se non entra nemmeno in una pagina vuota, si spezza lo stesso.
                var group = [next]
                if !next.info.style.canSplit {
                    group = Array(carried.prefix { $0.info.range == next.info.range })
                    if pageNotes.isEmpty, notesHeight(group) > column.height { group = [next] }
                }
                // Almeno una riga per pagina, anche se fosse più alta dello specchio: altrimenti non si finirebbe mai.
                let fits = pageNotesHeight + addedHeight(group) <= column.height
                guard fits || pageNotes.isEmpty else {
                    closePage()
                    pages.append(LaidOutPage())
                    applyPageSetup()
                    numberNewPage()
                    continue
                }
                for entry in group { addToPage(entry) }
                carried.removeFirst(group.count)
            }
            topFigureCount = 0
            pageFigureCount = 0
            placeDeferredFigures()
        }
        /// All'inizio di una pagina, le figure che aspettano: in cima o in fondo, secondo ciò che ammettono e i limiti; una
        /// figura che ammette una pagina di sole figure e non trova posto la ottiene, se la pagina è ancora vuota.
        func placeDeferredFigures() {
            var waiting: [FigureBlock] = []
            var floatPage = false
            for block in deferredFigures {
                if waiting.contains(where: { $0.style.name == block.style.name }) {
                    waiting.append(block)
                    continue
                }
                if tryTop(block) || tryBottom(block) { continue }
                let empty = pages[pages.count - 1].lines.isEmpty && pages[pages.count - 1].images.isEmpty
                if block.style.positions.contains(.page) || floatPage, empty || floatPage, y + block.height <= column.height || y == 0 {
                    // Una pagina di sole figure.
                    placeFigure(block, top: y)
                    y += block.height + floatSeparation
                    floatPage = true
                    continue
                }
                waiting.append(block)
            }
            deferredFigures = waiting
            if floatPage { startNewPage() }
        }

        var pageIsEmpty: Bool { pages[pages.count - 1].lines.isEmpty && pageNotes.isEmpty && pages[pages.count - 1].images.isEmpty }

        // Le regole che si decidono solo componendo (con una condizione, o sulla pagina), e lo stile del paragrafo precedente.
        let layoutRules = Rules.usable(options.rules, sheet: options.styles).filter(\.dependsOnLayout)
        var previousParagraphStyle: String?

        /// Colloca una tabella intera, dai paragrafi della sua prima cella in poi; restituisce dove finisce nel testo.
        /// Colonne automatiche (come le tabelle HTML), griglia completa, righe che non si spezzano, intestazione ripetuta
        /// in cima a ogni pagina nuova.
        /// Vero se il paragrafo vuoto in fondo al documento è già stato messo, come cella di una tabella.
        var finalParagraphPlaced = false
        func placeTable(_ id: String, from start: Int) -> Int {
            // Le celle: per ognuna i suoi paragrafi, nell'ordine, e il suo aspetto (dal segno del suo primo paragrafo).
            struct CellParagraph { var range: NSRange; var body: NSAttributedString; var map: TextMap; var style: NSParagraphStyle }
            var cells: [[[CellParagraph]]] = []
            var cellValues: [[CellValues]] = []
            var captionParagraphs: [CellParagraph] = []
            /// Le colonne e righe coperte da ogni cella unita, per la sua posizione.
            var spans: [[Int]: (columns: Int, rows: Int)] = [:]
            var headerRows = 0
            var tableMark: CellMark?
            func add(_ paragraph: CellParagraph, mark: CellMark) {
                tableMark = tableMark ?? mark
                headerRows = mark.headerRows
                if mark.isCaption {
                    captionParagraphs.append(paragraph)
                    return
                }
                while cells.count <= mark.row { cells.append([]); cellValues.append([]) }
                while cells[mark.row].count <= mark.column { cells[mark.row].append([]); cellValues[mark.row].append(CellValues()) }
                if cells[mark.row][mark.column].isEmpty {
                    cellValues[mark.row][mark.column] = mark.cellValues
                    if mark.columnSpan > 1 || mark.rowSpan > 1 { spans[[mark.row, mark.column]] = (mark.columnSpan, mark.rowSpan) }
                }
                cells[mark.row][mark.column].append(paragraph)
            }
            var cursor = start
            while cursor < string.length {
                let range = TextStyling.bodyParagraph(in: text, at: cursor).range
                guard let mark = (text.attribute(.tableCell, at: range.location, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)),
                      mark.table == id else { break }
                let body = composedBody(of: text.attributedSubstring(from: range), location: range.location, field: fieldText,
                                        floatStyles: options.floatStyles, noteMark: noteMark)
                let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle ?? .default
                add(CellParagraph(range: range, body: body.text, map: body.map, style: style), mark: mark)
                cursor = max(NSMaxRange(range), cursor + 1)
            }
            // Il paragrafo vuoto dopo l'ultimo a capo, se è una cella di questa tabella (il suo segno sta sull'a capo).
            if cursor >= string.length, string.length > 0, string.paragraphRange(for: NSRange(location: string.length, length: 0)).length == 0,
               let mark = (text.attribute(.finalParagraphCell, at: string.length - 1, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)),
               mark.table == id {
                let style = text.attribute(.paragraphStyle, at: string.length - 1, effectiveRange: nil) as? NSParagraphStyle ?? .default
                add(CellParagraph(range: NSRange(location: string.length, length: 0), body: NSAttributedString(),
                                  map: .identity(location: string.length, length: 0), style: style), mark: mark)
                finalParagraphPlaced = true
            }
            // Le posizioni coperte da una cella unita, con la cella che le copre; righe e colonne contano anche quelle.
            var owners: [[Int]: [Int]] = [:]
            for (origin, span) in spans {
                for r in origin[0]..<(origin[0] + span.rows) { for c in origin[1]..<(origin[1] + span.columns) where [r, c] != origin { owners[[r, c]] = origin } }
            }
            let columns = max(cells.map(\.count).max() ?? 0, spans.map { $0.key[1] + $0.value.columns }.max() ?? 0)
            let rowCount = max(cells.count, spans.map { $0.key[0] + $0.value.rows }.max() ?? 0)
            guard columns > 0 else { return cursor }
            while cells.count < rowCount { cells.append([]); cellValues.append([]) }
            for r in 0..<rowCount {
                while cells[r].count < columns { cells[r].append([]); cellValues[r].append(CellValues()) }
            }
            func owner(_ r: Int, _ c: Int) -> [Int] { owners[[r, c]] ?? [r, c] }
            func isCovered(_ r: Int, _ c: Int) -> Bool { owners[[r, c]] != nil }
            func span(_ r: Int, _ c: Int) -> (columns: Int, rows: Int) { spans[[r, c]] ?? (1, 1) }

            // L'aspetto: le eccezioni della tabella sopra il suo stile; per ogni cella le sue eccezioni.
            let look = TableStyle.resolved(styleName: tableMark?.style, values: tableMark?.tableValues ?? TableValues(), in: options.tableStyles)
            let ruleWidth = CGFloat(look.ruleWidth ?? 0.5)
            func values(_ r: Int, _ c: Int) -> CellValues {
                let o = owner(r, c)
                return o[0] < cellValues.count && o[1] < cellValues[o[0]].count ? cellValues[o[0]][o[1]] : CellValues()
            }
            func padding(_ r: Int, _ c: Int) -> CellInsets { values(r, c).padding ?? look.padding ?? CellInsets(all: 4) }
            enum Side { case top, right, bottom, left }
            /// Lo spessore che lo schema dà a un lato di una cella (0: nessun filetto).
            func schemeBorder(_ r: Int, _ c: Int, _ side: Side) -> CGFloat {
                let on: Bool = switch look.rules ?? .grid {
                case .grid: true
                case .horizontal: side == .top || side == .bottom
                case .frame: (side == .top && r == 0) || (side == .bottom && r == rowCount - 1) || (side == .left && c == 0) || (side == .right && c == columns - 1)
                case .threeRules: (side == .top && r == 0) || (side == .bottom && (r == rowCount - 1 || (headerRows > 0 && r == headerRows - 1)))
                case .none: false
                }
                return on ? ruleWidth : 0
            }
            func explicitBorder(_ r: Int, _ c: Int, _ side: Side) -> CGFloat? {
                let value = values(r, c)
                let border = switch side {
                case .top: value.top
                case .right: value.right
                case .bottom: value.bottom
                case .left: value.left
                }
                return border.map { CGFloat($0.width) }
            }
            /// Il filetto dove due celle si toccano (o sul bordo, con una sola): se una delle due ne dice uno suo, valgono
            /// i lati detti; se no, lo schema. Dei due vince il più spesso.
            func edge(_ first: (Int, Int, Side)?, _ second: (Int, Int, Side)?) -> CGFloat {
                // Dentro una cella unita non ci sono filetti.
                if let first, let second, owner(first.0, first.1) == owner(second.0, second.1) { return 0 }
                let sides = [first, second].compactMap { $0 }
                let explicit = sides.compactMap { explicitBorder($0.0, $0.1, $0.2) }
                if !explicit.isEmpty { return explicit.max() ?? 0 }
                return sides.map { schemeBorder($0.0, $0.1, $0.2) }.max() ?? 0
            }
            // I filetti verticali di ogni riga (prima della prima colonna, tra le colonne, dopo l'ultima).
            let verticalEdges: [[CGFloat]] = (0..<rowCount).map { r in
                (0...columns).map { c in edge(c > 0 ? (r, c - 1, .right) : nil, c < columns ? (r, c, .left) : nil) }
            }
            /// Lo spazio orizzontale di una cella che non è testo: margini interni e metà dei filetti ai lati (per una cella
            /// unita, quelli ai lati di tutte le colonne che copre).
            func extraWidth(_ r: Int, _ c: Int) -> CGFloat {
                let insets = padding(r, c)
                return CGFloat(insets.left + insets.right) + verticalEdges[r][c] / 2 + verticalEdges[r][min(c + span(r, c).columns, columns)] / 2
            }

            // Larghezze minime (la parola più lunga) e naturali (il testo senza a capo) di ogni colonna; prima le celle di una
            // colonna sola.
            func measure(_ cell: [CellParagraph]) -> (minimum: CGFloat, natural: CGFloat) {
                var minimum: CGFloat = 0, natural: CGFloat = 0
                for paragraph in cell {
                    let text = paragraph.body
                    let full = CTLineCreateWithAttributedString(text)
                    natural = max(natural, CGFloat(CTLineGetTypographicBounds(full, nil, nil, nil)) + paragraph.style.headIndent + max(paragraph.style.firstLineHeadIndent - paragraph.style.headIndent, 0))
                    let words = (text.string as NSString)
                    var wordStart: Int?
                    for index in 0...words.length {
                        let isSpace = index == words.length || CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(words.character(at: index)) ?? " ")
                        if isSpace, let begin = wordStart {
                            let word = CTLineCreateWithAttributedString(text.attributedSubstring(from: NSRange(location: begin, length: index - begin)))
                            minimum = max(minimum, CGFloat(CTLineGetTypographicBounds(word, nil, nil, nil)))
                            wordStart = nil
                        } else if !isSpace, wordStart == nil {
                            wordStart = index
                        }
                    }
                }
                return (minimum, natural)
            }
            var minimum = [CGFloat](repeating: 0, count: columns), natural = [CGFloat](repeating: 0, count: columns)
            for (r, row) in cells.enumerated() {
                for (c, cell) in row.enumerated() where span(r, c).columns == 1 && !isCovered(r, c) {
                    let measured = measure(cell)
                    minimum[c] = max(minimum[c], measured.minimum)
                    natural[c] = max(natural[c], measured.natural)
                }
            }
            // Una colonna senza testo conta come la media delle altre (in una tabella appena fatta le colonne sono
            // uguali): altrimenti si ridurrebbe ai margini interni, e non ci si potrebbe cliccare dentro.
            let filled = natural.filter { $0 > 0 }
            let fallback = filled.isEmpty ? 1 : filled.reduce(0, +) / CGFloat(filled.count)
            for c in 0..<columns where natural[c] <= 0 { natural[c] = fallback }
            let extra = (0..<columns).map { c in (0..<rowCount).filter { span($0, c).columns == 1 && !isCovered($0, c) }.map { extraWidth($0, c) }.max() ?? 0 }
            // Una cella che copre più colonne: se il suo testo vuole più spazio di quelle colonne, la differenza si divide tra loro.
            for (origin, cellSpan) in spans where cellSpan.columns > 1 {
                let measured = measure(cells[origin[0]][origin[1]])
                let spanned = origin[1]..<min(origin[1] + cellSpan.columns, columns)
                let own = extraWidth(origin[0], origin[1])
                let extras = spanned.reduce(CGFloat(0)) { $0 + extra[$1] }
                let naturalDeficit = measured.natural + own - spanned.reduce(CGFloat(0)) { $0 + natural[$1] } - extras
                if naturalDeficit > 0 { for c in spanned { natural[c] += naturalDeficit / CGFloat(spanned.count) } }
                let minimumDeficit = measured.minimum + own - spanned.reduce(CGFloat(0)) { $0 + minimum[$1] } - extras
                if minimumDeficit > 0 { for c in spanned { minimum[c] += minimumDeficit / CGFloat(spanned.count) } }
            }
            let available = column.width
            let minTotal = zip(minimum, extra).reduce(0) { $0 + $1.0 + $1.1 }
            let naturalTotal = zip(natural, extra).reduce(0) { $0 + $1.0 + $1.1 }
            var widths: [CGFloat]
            if naturalTotal <= available {
                // Tutto sta senza a capo: lo spazio in più si divide in proporzione alle larghezze naturali.
                let weight = max(natural.reduce(0, +), 1)
                widths = (0..<columns).map { natural[$0] + extra[$0] + (available - naturalTotal) * (natural[$0] / weight) }
            } else if minTotal <= available {
                let span = max(naturalTotal - minTotal, 1)
                widths = (0..<columns).map { minimum[$0] + extra[$0] + (natural[$0] - minimum[$0]) * (available - minTotal) / span }
            } else {
                // Nemmeno le parole più lunghe ci stanno: le colonne si stringono in proporzione.
                widths = (0..<columns).map { (minimum[$0] + extra[$0]) * available / max(minTotal, 1) }
            }
            let lefts = widths.indices.map { c in column.minX + widths.prefix(c).reduce(0, +) }
            /// Un paragrafo vuoto (una cella vuota, una didascalia vuota): una riga vuota con le misure del font, per il
            /// cursore, all'inizio del paragrafo.
            func emptyLine(_ paragraph: CellParagraph) -> ComposedLine {
                let font = text.attribute(.font, at: max(min(paragraph.range.location, string.length) - (paragraph.range.length > 0 ? 0 : 1), 0), effectiveRange: nil) as? NSFont
                    ?? NSFont.userFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
                let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
                return ComposedLine(line: CTLineCreateWithAttributedString(NSAttributedString()), composedRange: NSRange(location: 0, length: 0),
                                    composedOffset: 0, endsWithHyphen: false, ascent: ascent, descent: descent,
                                    height: ascent + descent + CTFontGetLeading(font), baselineFromTop: ascent, x: paragraph.style.firstLineHeadIndent, spacingAfter: 0)
            }

            // Le righe composte: per ogni cella le sue righe e l'altezza del suo testo; per la riga, quanto dei filetti
            // sopra e sotto le spetta (metà di ciascuno).
            typealias CellLine = (line: ComposedLine, top: CGFloat, paragraph: CellParagraph)
            struct ComposedRow { var index: Int; var cells: [[CellLine]]; var contentHeights: [CGFloat]; var topEdge: CGFloat; var bottomEdge: CGFloat; var height: CGFloat }
            var rows: [ComposedRow] = []
            for (r, row) in cells.enumerated() {
                var composed: [[CellLine]] = []
                var contentHeights: [CGFloat] = []
                var height: CGFloat = 0
                for c in 0..<columns {
                    var top: CGFloat = 0
                    var placedLines: [CellLine] = []
                    let cell = c < row.count ? row[c] : []
                    for (index, cellParagraph) in cell.enumerated() {
                        var paragraph = cellParagraph
                        if index > 0 { top += paragraph.style.paragraphSpacingBefore }
                        let cellWidth = widths[c..<min(c + span(r, c).columns, columns)].reduce(0, +)
                        var lines = composedLines(paragraph.body, style: paragraph.style, width: max(cellWidth - extraWidth(r, c), 1), options: options)
                        if lines.isEmpty {
                            paragraph.map = .identity(location: paragraph.range.location, length: 0)
                            lines = [emptyLine(paragraph)]
                        }
                        for line in lines {
                            placedLines.append((line, top, paragraph))
                            top += line.height + line.spacingAfter
                        }
                        if index < cell.count - 1 { top += paragraph.style.paragraphSpacing }
                    }
                    composed.append(placedLines)
                    contentHeights.append(top)
                    // Una cella che copre più righe non fa alta la sua prima riga: la si sistema dopo, su tutte quelle che copre.
                    guard !isCovered(r, c), span(r, c).rows == 1 else { continue }
                    let insets = padding(r, c)
                    height = max(height, top + CGFloat(insets.top + insets.bottom))
                }
                let topEdge = (0..<columns).map { edge(r > 0 ? (r - 1, $0, .bottom) : nil, (r, $0, .top)) }.max() ?? 0
                let bottomEdge = (0..<columns).map { edge((r, $0, .bottom), r < rowCount - 1 ? (r + 1, $0, .top) : nil) }.max() ?? 0
                rows.append(ComposedRow(index: r, cells: composed, contentHeights: contentHeights, topEdge: topEdge, bottomEdge: bottomEdge,
                                        height: height + topEdge / 2 + bottomEdge / 2))
            }
            // Sulla virgola, in una colonna: i segni decimali delle righe allineate così stanno uno sotto l'altro; il blocco
            // (la parte più larga prima del segno più quella più larga dopo) sta al centro della cella.
            for c in 0..<columns {
                var before: CGFloat = 0, after: CGFloat = 0, found = false
                for row in rows where !isCovered(row.index, c) && span(row.index, c).columns == 1 {
                    for entry in row.cells[c] {
                        guard let offset = entry.line.decimalOffset else { continue }
                        before = max(before, offset)
                        after = max(after, entry.line.width - offset)
                        found = true
                    }
                }
                guard found else { continue }
                for r in rows.indices where !isCovered(rows[r].index, c) && span(rows[r].index, c).columns == 1 {
                    for e in rows[r].cells[c].indices {
                        guard let offset = rows[r].cells[c][e].line.decimalOffset else { continue }
                        let available = rows[r].cells[c][e].line.availableWidth
                        let head = rows[r].cells[c][e].line.x - (available / 2 - offset)
                        rows[r].cells[c][e].line.x = head + (available - before - after) / 2 + before - offset
                    }
                }
            }
            /// Lo spazio per il testo di una cella che copre più righe: le loro altezze, senza metà dei filetti sopra e sotto.
            func spannedHeight(_ r: Int, _ rowsSpanned: Int) -> CGFloat {
                let last = min(r + rowsSpanned, rowCount) - 1
                return rows[r...last].reduce(0) { $0 + $1.height } - rows[r].topEdge / 2 - rows[last].bottomEdge / 2
            }
            // Le celle che coprono più righe: se il loro testo non ci sta, l'ultima riga che coprono si allunga.
            for (origin, cellSpan) in spans.sorted(by: { $0.key[0] < $1.key[0] }) where cellSpan.rows > 1 {
                let insets = padding(origin[0], origin[1])
                let needed = rows[origin[0]].contentHeights[origin[1]] + CGFloat(insets.top + insets.bottom)
                let have = spannedHeight(origin[0], cellSpan.rows)
                if needed > have { rows[min(origin[0] + cellSpan.rows, rowCount) - 1].height += needed - have }
            }
            /// L'ultima riga legata alla riga `r` da celle che coprono più righe: le righe di un gruppo stanno nella stessa pagina.
            func groupEnd(_ r: Int) -> Int {
                var end = r, row = r
                while row <= end {
                    for c in 0..<columns where !isCovered(row, c) { end = max(end, min(row + span(row, c).rows, rowCount) - 1) }
                    row += 1
                }
                return end
            }

            /// Il disegno di una riga, dal suo bordo alto: fondi, testo, il filetto sopra ogni cella (con la riga che le sta
            /// sopra in questa pagina, o nel blocco; senza, il solo lato della cella) e i filetti verticali.
            func drawing(of row: ComposedRow, below previous: ComposedRow?) -> BlockDrawing {
                var drawing = BlockDrawing()
                drawing.height = row.height
                let r = row.index
                func horizontalRule(column c: Int, width: CGFloat) {
                    guard width > 0 else { return }
                    let left = lefts[c] - verticalEdges[r][c] / 2, right = lefts[c] + widths[c] + verticalEdges[r][c + 1] / 2
                    drawing.rules.append(CGRect(x: left, y: -width / 2, width: right - left, height: width))
                }
                for c in 0..<columns {
                    // Il filetto sopra: con la riga che sta sopra (dentro una cella unita, nessuno).
                    horizontalRule(column: c, width: edge(previous.map { ($0.index, c, .bottom) }, (r, c, .top)))
                    // Una posizione coperta la disegna la cella che la copre.
                    guard !isCovered(r, c) else { continue }
                    let cellSpan = span(r, c)
                    let lastRow = min(r + cellSpan.rows, rowCount) - 1
                    let boxHeight = rows[r...lastRow].reduce(0) { $0 + $1.height }
                    let box = CGRect(x: lefts[c], y: 0, width: widths[c..<min(c + cellSpan.columns, columns)].reduce(0, +), height: boxHeight)
                    // Il fondo, sotto i filetti e il testo.
                    let background = values(r, c).background ?? look.background ?? ""
                    if !background.isEmpty, let color = TextStyling.color(hex: background) { drawing.fills.append((box, color.cgColor)) }
                    let insets = padding(r, c)
                    // L'allineamento verticale: lo spazio che il testo lascia libero nella riga va sopra, sotto o a metà.
                    let free = boxHeight - row.topEdge / 2 - rows[lastRow].bottomEdge / 2 - CGFloat(insets.top + insets.bottom) - row.contentHeights[c]
                    let alignment = values(r, c).verticalAlignment ?? look.verticalAlignment ?? .top
                    let shift = alignment == .middle ? free / 2 : alignment == .bottom ? free : 0
                    let textTop = row.topEdge / 2 + CGFloat(insets.top) + max(shift, 0)
                    let textLeft = lefts[c] + verticalEdges[r][c] / 2 + CGFloat(insets.left)
                    for entry in row.cells[c] {
                        drawing.lines.append(BlockDrawing.Line(line: entry.line, top: textTop + entry.top, left: textLeft, map: entry.paragraph.map,
                                                               paragraphLocation: entry.paragraph.range.location, cell: box))
                    }
                }
                for c in 0...columns where verticalEdges[r][c] > 0 {
                    let width = verticalEdges[r][c]
                    drawing.rules.append(CGRect(x: (c < columns ? lefts[c] : lefts[columns - 1] + widths[columns - 1]) - width / 2,
                                                y: 0, width: width, height: row.height))
                }
                return drawing
            }
            /// Il filetto sotto l'ultima riga di una pagina (o della tabella), all'altezza zero del disegno.
            func closing(_ last: ComposedRow) -> BlockDrawing {
                var drawing = BlockDrawing()
                for c in 0..<columns {
                    let width = edge((last.index, c, .bottom), nil)
                    guard width > 0 else { continue }
                    let left = lefts[c] - verticalEdges[last.index][c] / 2, right = lefts[c] + widths[c] + verticalEdges[last.index][c + 1] / 2
                    drawing.rules.append(CGRect(x: left, y: -width / 2, width: right - left, height: width))
                }
                return drawing
            }

            // Una tabella flottante: lo stile di flottante (una figura) e la didascalia, con il numero della sua Lista davanti.
            let floatStyle = tableMark?.floatStyle.flatMap { name in options.floatStyles.first { $0.name == name && $0.placement == .figure } }
            var captionDrawing: BlockDrawing?
            if let floatStyle, floatStyle.caption != .none, !captionParagraphs.isEmpty {
                var label = ""
                if let list = floatLists[floatStyle.name] {
                    noteNumberer.setPage(pages.count)
                    if let mark = noteNumberer.next(list) {
                        noticeOverflow(mark, in: list)
                        label = mark.text + " "
                    }
                }
                var caption = BlockDrawing()
                var top: CGFloat = 0
                for (index, paragraph) in captionParagraphs.enumerated() {
                    var body = paragraph.body, map = paragraph.map
                    if index == 0, !label.isEmpty {
                        let attributes = paragraph.range.length > 0 ? text.attributes(at: paragraph.range.location, effectiveRange: nil)
                            : text.attributes(at: max(paragraph.range.location - 1, 0), effectiveRange: nil)
                        let labelled = NSMutableAttributedString(string: label, attributes: attributes.filter { $0.key == .font || $0.key == .foregroundColor || $0.key == .paragraphStyle })
                        labelled.append(body)
                        let shift = (label as NSString).length
                        map = TextMap(segments: map.segments.map { TextMap.Segment(composed: $0.composed + shift, document: $0.document, length: $0.length) })
                        body = labelled
                    }
                    if index > 0 { top += paragraph.style.paragraphSpacingBefore }
                    var lines = composedLines(body, style: paragraph.style, width: column.width, options: options)
                    if lines.isEmpty {
                        map = .identity(location: paragraph.range.location, length: 0)
                        lines = [emptyLine(paragraph)]
                    }
                    for line in lines {
                        caption.lines.append(BlockDrawing.Line(line: line, top: top, left: column.minX, map: map, paragraphLocation: paragraph.range.location, cell: nil))
                        top += line.height + line.spacingAfter
                    }
                    if index < captionParagraphs.count - 1 { top += paragraph.style.paragraphSpacing }
                }
                caption.height = top
                captionDrawing = caption
            }
            let captionAbove = floatStyle?.caption == .above

            if let floatStyle {
                // Tutta la tabella come un blocco, da collocare come una figura: subito (h, H), in fondo alla pagina, o dopo.
                var block = BlockDrawing()
                var top: CGFloat = 0
                if captionAbove, let captionDrawing {
                    block.append(captionDrawing, at: 0)
                    top = captionDrawing.height + figureGap
                }
                var previous: ComposedRow?
                for row in rows {
                    block.append(drawing(of: row, below: previous), at: top)
                    top += row.height
                    previous = row
                }
                if let previous { block.append(closing(previous), at: top) }
                if !captionAbove, let captionDrawing {
                    top += figureGap
                    block.append(captionDrawing, at: top)
                    top += captionDrawing.height
                }
                block.height = top
                // Più alta di una pagina, non si può spostare tutta insieme: va nel testo, e si spezza tra le righe.
                if top <= column.height {
                    let figure = FigureBlock(style: floatStyle, drawing: block, height: top)
                    let fits = y + (y > 0 ? floatSeparation : 0) + top + pageNotesHeight + bottomFiguresHeight <= column.height
                    if floatStyle.exactlyHere || floatStyle.positions.contains(.here) && fits && !isBlocked(figure) {
                        if !fits, !pageIsEmpty { startNewPage() }
                        if y > 0 { y += floatSeparation }
                        placeFigure(figure, top: y)
                        y += top + floatSeparation
                    } else if isBlocked(figure) || !tryBottom(figure) {
                        deferredFigures.append(figure)
                    }
                    return cursor
                }
            }

            // Nel testo: riga per riga, con l'intestazione ripetuta in cima a ogni pagina nuova.
            if y > 0 { y += 6 }
            func placeCaption() {
                guard let captionDrawing else { return }
                if y + captionDrawing.height + pageNotesHeight + bottomFiguresHeight > column.height, !pageIsEmpty { startNewPage() }
                emit(captionDrawing, top: y)
                y += captionDrawing.height
            }
            if captionAbove, captionDrawing != nil {
                placeCaption()
                y += figureGap
            }
            var previous: ComposedRow?
            var groupLast = -1
            for (index, row) in rows.enumerated() {
                // All'inizio di un gruppo di righe legate da celle unite: il gruppo intero deve stare nella pagina.
                var needed = row.height
                if index > groupLast {
                    groupLast = groupEnd(index)
                    needed = rows[index...groupLast].reduce(0) { $0 + $1.height }
                } else {
                    needed = 0
                }
                if needed > 0, y + needed + pageNotesHeight + bottomFiguresHeight > column.height, !pageIsEmpty {
                    if let previous { emit(closing(previous), top: y) }
                    startNewPage()
                    previous = nil
                    // L'intestazione si ripete in cima alla pagina nuova.
                    if index >= headerRows {
                        for header in rows.prefix(headerRows) {
                            emit(drawing(of: header, below: previous), top: y)
                            y += header.height
                            previous = header
                        }
                    }
                }
                emit(drawing(of: row, below: previous), top: y)
                y += row.height
                previous = row
            }
            if let previous { emit(closing(previous), top: y) }
            if !captionAbove, captionDrawing != nil {
                y += figureGap
                placeCaption()
            }
            y += 6
            return cursor
        }
        var pageStarts: [Int: PageStartPlacement] = [:]
        var layoutRulesApplied: [Int: [TextRule]] = [:]

        /// Fotografa lo stato dell'impaginazione; la funzione restituita lo rimette com'era.
        func checkpoint() -> () -> Void {
            let saved = (column, pages, openSections, pageNumbering, pageValue, runningActive, runningFirst, pageRunning, pageSections, openingPages)
            let savedText = (y, location, noteNumber, notes, listMarks, noteMarks, numbering, named, noteNumberer, floatLists, overflowing)
            let savedNotes = (assumedNotePages, notePages, pageNotes, carried, marginBoxes, marginConflicts, endNotes)
            let savedFigures = (deferredFigures, hereFigures, bottomFigures, topFigureCount, pageFigureCount)
            let savedRest = (previousParagraphStyle, finalParagraphPlaced, layoutRulesApplied, pageStarts)
            return {
                (column, pages, openSections, pageNumbering, pageValue, runningActive, runningFirst, pageRunning, pageSections, openingPages) = saved
                (y, location, noteNumber, notes, listMarks, noteMarks, numbering, named, noteNumberer, floatLists, overflowing) = savedText
                (assumedNotePages, notePages, pageNotes, carried, marginBoxes, marginConflicts, endNotes) = savedNotes
                (deferredFigures, hereFigures, bottomFigures, topFigureCount, pageFigureCount) = savedFigures
                (previousParagraphStyle, finalParagraphPlaced, layoutRulesApplied, pageStarts) = savedRest
            }
        }
        /// Tieni col seguente: una catena di paragrafi che restano con l'inizio del successivo. Si fotografa lo stato prima
        /// del primo; se un paragrafo della catena (o quello che la segue) comincia in una pagina dopo l'ultima riga del
        /// precedente, si torna alla fotografia e la catena comincia nella pagina dopo. Se neanche lì sta con il suo
        /// seguito, si torna ancora indietro e la si posa com'era, senza spostarla.
        struct KeepChain {
            var restore: () -> Void
            var start: Int
            /// La pagina dell'ultima riga del paragrafo precedente della catena.
            var lastPage = 0
            /// La catena comincia in una pagina vuota: spostarla non servirebbe.
            var startsOnEmptyPage = false
            /// L'ultimo paragrafo della catena: quante righe del seguente vuole con sé, e quante delle sue il seguente
            /// vuole con sé (tieni col precedente, formato 17).
            var lastStart = 0
            var nextLines = 1
            var tailLines = 0
        }
        var styleValues: [String: StyleValues] = [:]
        var reducedStart: [Int: CGFloat] = [:]
        var keepChain: KeepChain?
        var keepBreakAt: Int?
        var keepMoved: Set<Int> = [], keepGivenUp: Set<Int> = []
        /// Tieni col precedente: le ultime righe di un paragrafo che passano alla pagina del seguente, dopo un tentativo.
        var keepTail: [Int: Int] = [:]
        /// Dopo un paragrafo (o una tabella) che segue un paragrafo della catena: vero se si è tornati indietro.
        func keepChainBroken(by start: Int, from mark: (page: Int, line: Int), pending: KeepChain?) -> Bool {
            guard let pending, !keepGivenUp.contains(pending.start) else { return false }
            var firstPage: Int?
            for index in mark.page..<pages.count where firstPage == nil {
                let lines = pages[index].lines[(index == mark.page ? mark.line : 0)...]
                if lines.contains(where: { !$0.isNote && $0.paragraphLocation >= start }) { firstPage = index }
            }
            guard let firstPage else { return false }
            // Il seguente vuole con sé le ultime righe di questo: se nella pagina in cui comincia ne stanno meno, si
            // spezza il paragrafo perché ci arrivino, invece di spostarlo tutto.
            if pending.tailLines > 0, keepTail[pending.lastStart] == nil {
                let recent = pages[max(0, firstPage - 4)...firstPage].flatMap(\.lines).filter { !$0.isNote && $0.paragraphLocation == pending.lastStart }
                let here = pages[firstPage].lines.filter { !$0.isNote && $0.paragraphLocation == pending.lastStart }.count
                if here < min(pending.tailLines, recent.count) {
                    keepTail[pending.lastStart] = pending.tailLines
                    pending.restore()
                    keepChain = nil
                    return true
                }
            }
            guard firstPage > pending.lastPage, !pending.startsOnEmptyPage else { return false }
            pending.restore()
            if keepMoved.contains(pending.start) {
                keepGivenUp.insert(pending.start)
                keepBreakAt = nil
            } else {
                keepMoved.insert(pending.start)
                keepBreakAt = pending.start
            }
            keepChain = nil
            return true
        }

        paragraphs: while location < string.length {
            // I paragrafi del corpo: gli a capo dentro una nota non li spezzano.
            let paragraphRange = TextStyling.bodyParagraph(in: text, at: location).range
            let paragraphStyleName = text.attribute(.paragraphStyleName, at: paragraphRange.location, effectiveRange: nil) as? String
            let sectionStart = SectionEditing.start(in: text, atParagraph: paragraphRange.location)
            let isTable = text.attribute(.tableCell, at: paragraphRange.location, effectiveRange: nil) != nil
            // La tenuta delle righe (sotto, vedove e orfane); qui conta «tieni col seguente».
            // La tenuta dello stile si legge una volta per stile: risalire la catena degli stili a ogni paragrafo costa.
            let values = styleValues[paragraphStyleName ?? ""] ?? {
                let found = options.styles.values(of: paragraphStyleName)
                styleValues[paragraphStyleName ?? ""] = found
                return found
            }()
            var keeping = TextStyling.lineKeeping(in: text, at: paragraphRange.location).over(values.keeping).resolved
            // Il paragrafo precedente voleva restare con questo: lo si controlla dopo averlo posato. Un paragrafo che apre
            // comunque una pagina nuova chiude la catena senza controllo.
            let pendingKeep = sectionStart == .continuous ? keepChain : nil
            // Il precedente vuole con sé n righe di questo: se in fondo alla pagina non ne stanno n, passa tutto alla
            // pagina dopo (e la catena porta con sé il precedente).
            if let pendingKeep, pendingKeep.nextLines > 1 { keeping.linesAtEnd = max(keeping.linesAtEnd, pendingKeep.nextLines) }
            // Il seguente vuole con sé le ultime righe di questo (tieni col precedente): questo entra nella catena.
            let followerWantsTail: Int = {
                let next = NSMaxRange(paragraphRange)
                guard next < text.length else { return 0 }
                let nextRange = TextStyling.bodyParagraph(in: text, at: next).range
                guard SectionEditing.start(in: text, atParagraph: nextRange.location) == .continuous,
                      text.attribute(.tableCell, at: nextRange.location, effectiveRange: nil) == nil else { return 0 }
                let name = text.attribute(.paragraphStyleName, at: nextRange.location, effectiveRange: nil) as? String
                let nextValues = styleValues[name ?? ""] ?? {
                    let found = options.styles.values(of: name)
                    styleValues[name ?? ""] = found
                    return found
                }()
                return TextStyling.lineKeeping(in: text, at: nextRange.location).over(nextValues.keeping).resolved.previousLines
            }()
            let keepsWithNext = (keeping.withNext || followerWantsTail > 0) && !isTable
            if !keepsWithNext { keepChain = nil } else if keepChain == nil || sectionStart != .continuous {
                keepChain = KeepChain(restore: checkpoint(), start: paragraphRange.location)
            }
            if keepsWithNext {
                keepChain?.lastStart = paragraphRange.location
                keepChain?.nextLines = keeping.withNext ? keeping.nextLines : 1
                keepChain?.tailLines = followerWantsTail
            }
            // Dopo un tentativo andato male: le ultime righe di questo paragrafo passano alla pagina del seguente.
            let tailCount = keepTail[paragraphRange.location] ?? 0
            let startsKeepChain = keepChain?.start == paragraphRange.location
            let keepMark = (page: pages.count - 1, line: pages[pages.count - 1].lines.count)
            if let target = returns[paragraphRange.location] {
                if let keep = openSections.lastIndex(where: { $0.mark.id == target }) {
                    openSections.removeLast(openSections.count - keep - 1)
                } else {
                    openSections.removeAll()
                }
            }
            // Una tabella: la si colloca tutta insieme.
            if let cellMark = (text.attribute(.tableCell, at: paragraphRange.location, effectiveRange: nil) as? String).flatMap(CellMark.init(encoded:)) {
                let tableMark = (page: pages.count - 1, line: pages[pages.count - 1].lines.count)
                location = placeTable(cellMark.table, from: paragraphRange.location)
                previousParagraphStyle = nil
                _ = keepChainBroken(by: paragraphRange.location, from: tableMark, pending: pendingKeep)
                continue
            }
            var style = text.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle ?? .default
            // Il titolo di una sezione: le liste che ripartono a ogni sua sezione ripartono (anche quelle delle note, che si
            // numerano componendo il corpo qui sotto).
            let sectionMark = (text.attribute(.sectionTitle, at: paragraphRange.location, effectiveRange: nil) as? String).flatMap(SectionMark.init(encoded:))
            if let sectionMark {
                named.passSection(role: sectionMark.role)
                noteNumberer.passSection(role: sectionMark.role)
            }
            // Una voce di elenco: il testo rientra secondo il livello, e il segno va accanto alla prima riga.
            var item = (text.attribute(.listItem, at: paragraphRange.location, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
            // Un titolo di sezione senza un elenco suo è un elemento della Lista che numera il suo ruolo, se c'è.
            if item == nil, let sectionMark, let numbering = named.list(numbering: sectionMark.role) { item = ListItem(listName: numbering) }
            var marker: ComposedMarker?
            let listed = listMarker(for: item)
            if let markerText = listed?.text { listMarks[paragraphRange.location] = markerText }
            if let (item, markerText) = listed {
                // Il segno prende l'aspetto del primo carattere del testo della voce (non di una nota che la apre).
                var first = paragraphRange.location
                while first < NSMaxRange(paragraphRange) - 1, text.attribute(.footnote, at: first, effectiveRange: nil) != nil { first += 1 }
                (style, marker) = listLayout(item: item, markerText: markerText, attributes: text.attributes(at: first, effectiveRange: nil), style: style)
            }
            // Il titolo di una sezione che comincia su una pagina nuova (o dispari): si apre la pagina, e il titolo apre una
            // sequenza, come l'inizio del documento.
            if let sectionMark {
                // Le sezioni aperte, per i tipi di pagina (come nella ricostruzione dell'albero).
                while let last = openSections.last, last.declared >= sectionMark.depth { openSections.removeLast() }
                let titleText = BodyText(text, paragraph: paragraphRange).string.trimmingCharacters(in: .whitespacesAndNewlines)
                openSections.append((sectionMark.depth, sectionMark, titleText, listMarks[paragraphRange.location]))
            }
            // Il corpo del paragrafo, con i numeri di richiamo al posto delle note, e le note da comporre a parte.
            var body = composedBody(of: text.attributedSubstring(from: paragraphRange), location: paragraphRange.location, field: fieldText,
                                    floatStyles: options.floatStyles, noteMark: noteMark)
            notes.append(contentsOf: body.notes.map(\.range))
            endNotes += body.notes.filter { $0.style.placement == .documentEnd }.map { ($0, style) }
            var bodyText = body.text
            var lineRules = bodyText.length > 0 ? bodyText.attribute(.lineRules, at: 0, effectiveRange: nil) as? LineRuleSpec : nil
            // Le regole che dipendono dalla composizione: si compone il paragrafo al naturale, si controllano le condizioni
            // (e se comincia una pagina), e si applicano quelle che valgono.
            if sectionStart != .continuous {
                if !pageIsEmpty { startNewPage(sectionFirst: true) }
                // La pagina dispari: se questa è pari, resta bianca (con il tipo delle pagine normali) e si va alla prossima.
                if sectionStart == .oddPage, pages.count % 2 == 0 {
                    applyPageSetup()
                    startNewPage(sectionFirst: true)
                }
            }
            // Una catena «tieni col seguente» che non stava con il suo seguito: ricomincia nella pagina dopo.
            if startsKeepChain { keepChain?.startsOnEmptyPage = pageIsEmpty }
            if keepBreakAt == paragraphRange.location {
                keepBreakAt = nil
                if !pageIsEmpty { startNewPage() }
            }
            // Un titolo in cima a una pagina ancora vuota: è la prima pagina della sua sezione, e ne prende il tipo.
            if sectionMark != nil, pageIsEmpty { applyPageSetup(sectionFirst: true) }
            // Una sezione con la sua Lista per le pagine: la numerazione riparte dalla sua pagina.
            if let list = sectionMark?.pageNumbering.flatMap({ listsByName[$0] }) {
                pageNumbering = list
                pageValue = list.start - 1
                numberNewPage()
            }
            if let sectionMark, sectionStart != .continuous { openingPages[pages.count - 1] = sectionMark.id }
            // Un titolo in cima alla pagina: per i campi della pagina, la sua sezione è già in corso.
            if sectionMark != nil, pageIsEmpty { snapshotPage() }
            // «Scrivi risultato» dello stile: il testo calcolato prima o dopo il testo, sulle sue righe. Si calcola qui, dove
            // la pagina e le sezioni del paragrafo sono già quelle giuste.
            let writes = options.styles.writtenResults(ofParagraphStyle: paragraphStyleName)
            if !writes.isEmpty {
                let location = paragraphRange.location
                var context = fieldContext()
                if writes.contains(where: { $0.formula.presentationRead == .pageNumber }) {
                    context.pageNumber = assumedPageNumbers.paragraphs[location] ?? context.pageNumber
                    pageNumbers.paragraphs[location] = context.pageNumber
                }
                body = writingResults(writes, into: body, context: context, sheet: options.styles,
                                      retracks: options.appliesFontTracking, resolver: FontRoleResolver(table: options.fontRoles))
                bodyText = body.text
            }
            // Le intestazioni e i piè di pagina ancorati qui: valgono da qui in poi (dalla pagina in corso, se è ancora vuota).
            let runningNotes = body.notes.filter { $0.style.placement.isRunning }
            if !runningNotes.isEmpty {
                for note in runningNotes {
                    let entry = RunningEntry(note: note, paragraphStyle: style)
                    if note.style.pages == .first {
                        runningFirst[FirstKey(placement: note.style.placement, section: openSections.last?.mark.id)] = entry
                    } else {
                        runningActive[RunningKey(placement: note.style.placement, pages: note.style.pages)] = entry
                    }
                }
                if pageIsEmpty { snapshotPage() }
            }
            let context = TextRule.ParagraphContext(styleName: paragraphStyleName, previousStyleName: previousParagraphStyle,
                                                    isSequenceStart: SectionEditing.opensSequence(in: text, atParagraph: paragraphRange.location), isFirstOnPage: true)
            previousParagraphStyle = paragraphStyleName
            let candidates = layoutRules.filter { $0.applies(to: context) }
            if !candidates.isEmpty {
                let natural = composedLines(bodyText, style: style, width: column.width, options: options, lineRules: lineRules)
                let facts = TextRule.NaturalFacts(
                    // Contare le parole costa: solo se una condizione lo chiede.
                    lineCount: natural.count,
                    wordCount: candidates.contains { $0.condition?.property == .words } ? BodyText(text, paragraph: paragraphRange).wordCount : 0,
                    lastLineFill: natural.last.map { $0.availableWidth > 0 ? Double(min($0.width / $0.availableWidth, 1)) : 0 } ?? 0,
                    hyphenatedLines: natural.filter(\.endsWithHyphen).count)
                let startsPage = pageIsEmpty || natural.first.map {
                    y + (y > 0 ? style.paragraphSpacingBefore : 0) + $0.height + pageNotesHeight + bottomFiguresHeight > column.height
                } ?? false
                let holding = candidates.filter { ($0.position != .firstOnPage || startsPage) && ($0.condition?.holds(for: facts) ?? true) }
                if !holding.isEmpty {
                    layoutRulesApplied[paragraphRange.location] = holding
                    let piece = NSMutableAttributedString(attributedString: bodyText)
                    let whole = NSRange(location: 0, length: piece.length)
                    var base = text.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle ?? .default
                    let retracks = options.appliesFontTracking
                    for rule in holding where !rule.target.isLineTarget {
                        if rule.target == .paragraph {
                            base = Rules.restyledParagraph(base, styleName: paragraphStyleName, with: rule.styleName, sheet: options.styles,
                                                           except: TextStyling.ruleExceptions(in: text, at: paragraphRange.location))
                            Rules.applyStyle(rule.styleName, to: whole, in: piece, sheet: options.styles, retracks: retracks, resolver: FontRoleResolver(table: options.fontRoles))
                            continue
                        }
                        // Ciò che la regola trova si cerca nel testo del documento, e si riporta al corpo composto.
                        for range in BodyText(text, paragraph: paragraphRange).ranges(of: rule.target, selections: options.styles.selections) {
                            guard let start = body.map.composedIndex(forDocument: range.location),
                                  let end = body.map.composedIndex(forDocument: NSMaxRange(range)), end > start else { continue }
                            Rules.applyStyle(rule.styleName, to: NSRange(location: start, length: end - start), in: piece, sheet: options.styles, retracks: retracks, resolver: FontRoleResolver(table: options.fontRoles))
                        }
                    }
                    if let merged = LineRuleSpec(holding.filter(\.target.isLineTarget), over: lineRules), merged != lineRules {
                        lineRules = merged
                        piece.addAttribute(.lineRules, value: merged, range: whole)
                    }
                    bodyText = piece
                    style = base
                    if let (item, markerText) = listed {
                        var first = paragraphRange.location
                        while first < NSMaxRange(paragraphRange) - 1, text.attribute(.footnote, at: first, effectiveRange: nil) != nil { first += 1 }
                        (style, marker) = listLayout(item: item, markerText: markerText, attributes: text.attributes(at: first, effectiveRange: nil), style: base)
                    }
                }
            }
            // Il paragrafo che apre una sequenza, in cima alla pagina, scende della sua distanza d'apertura (dal margine superiore).
            // Lo spazio prima, che in cima a una pagina non conta, non vi si aggiunge.
            if y == 0, SectionEditing.opensSequence(in: text, atParagraph: paragraphRange.location) {
                y = CGFloat(TextStyling.effectiveOpeningDistance(in: text, atParagraph: paragraphRange.location, sheet: options.styles))
            } else if y > 0 {
                y += style.paragraphSpacingBefore
            }

            // La testata dello stile del titolo: le parti prima delle sue righe e quelle dopo. Il numero lo scrive la
            // testata; il segno dell'elenco del titolo allora non si disegna, e il numero compare una volta sola.
            let heading = options.styles.heading(ofParagraphStyle: paragraphStyleName)
            if heading?.showsNumber == true { marker = nil }
            let headingNumber = listMarks[paragraphRange.location] ?? ""
            let headingBefore = heading.map { headingPieces($0.split.before, number: headingNumber, titleStyle: paragraphStyleName) } ?? []
            // Il numero accanto al titolo, sulla sua prima riga: le righe del titolo si scostano della sua larghezza più
            // la distanza (al massimo metà della misura). Senza numero, il titolo occupa tutta la misura.
            let beside = heading?.numberBeside
            let besidePiece = heading.flatMap { heading in
                heading.numberBesideIndex.flatMap {
                    headingPieces([heading.parts[$0]], number: headingNumber, titleStyle: paragraphStyleName).first
                }
            }
            var titleReserve: CGFloat = 0
            if let besidePiece, let beside, case .text(_, _, _, let width) = besidePiece.kind {
                titleReserve = min(width + CGFloat(beside.gap), column.width / 2)
            }
            // Un allineamento proprio del titolo: le righe si compongono a bandiera e si posano al loro lato.
            let titleAlignment = heading?.titleOptions.alignment
            if titleAlignment != nil, let flush = style.mutableCopy() as? NSMutableParagraphStyle {
                flush.alignment = .left
                style = flush
            }
            var paragraphLines = composedLines(bodyText, style: style, width: column.width - titleReserve, options: options, lineRules: lineRules)
            var composedWidth = column.width
            // L'altezza minima del titolo: una fascia in cui le sue righe poggiano sul fondo; lo spazio in più va sopra.
            let titleLinesHeight = paragraphLines.reduce(CGFloat(0)) { $0 + $1.height + $1.spacingAfter } - (paragraphLines.last?.spacingAfter ?? 0)
            let titleExtra = max(0, CGFloat(heading?.titleOptions.minHeight ?? 0) - titleLinesHeight)
            let headingBeforeHeight = headingBefore.reduce(CGFloat(0)) { $0 + $1.height } + titleExtra
            /// Dove comincia una riga del titolo, se la testata la sposta: accanto al numero, o al lato scelto.
            func titleLeft(_ line: ComposedLine) -> CGFloat? {
                guard titleReserve > 0 || titleAlignment != nil else { return nil }
                let index = pages.count - 1
                let leftPage = pages[index].setup.facing && index % 2 == 1
                var minX = column.minX
                if titleReserve > 0, let side = beside?.side, side.resolved(onLeftPage: leftPage) != .right { minX += titleReserve }
                let width = column.width - titleReserve
                switch titleAlignment?.resolved(onLeftPage: leftPage) {
                case .right: return minX + width - line.width - line.x
                case .center: return minX + (width - line.width) / 2 - line.x
                default: return minX
                }
            }
            // Le note richiamate in una riga devono stare nella stessa pagina della riga.
            // (Le note di chiusura no: vanno dopo l'ultimo paragrafo.)
            // Le righe di ogni nota, composte una volta per larghezza: la tenuta le conta prima di posarle.
            var composedNotes: [Int: (width: CGFloat, lines: [ComposedLine])] = [:]
            func footNotes(of line: ComposedLine) -> [(lines: [ComposedLine], info: ComposedNote)] {
                body.notes.filter { NSLocationInRange($0.marker, line.composedRange) && $0.style.placement == .pageFoot }.map { note in
                    if let known = composedNotes[note.marker], known.width == column.width { return (lines: known.lines, info: note) }
                    let lines = noteLines(note, paragraphStyle: style)
                    composedNotes[note.marker] = (column.width, lines)
                    return (lines: lines, info: note)
                }
            }
            // La tenuta delle righe: se è accesa, all'inizio del paragrafo e a ogni pagina nuova si decide dove spezzare.
            var plannedBreak: Int?
            let hasFootNotes = body.notes.contains { $0.style.placement == .pageFoot }
            // Una variante vale soltanto per la prima riga del corpo. Una figura già
            // posata occupa lo specchio, le note riportate al piede lasciano libero il sommo.
            func applyPageStart() {
                pageStarts.removeValue(forKey: paragraphRange.location)
                guard case .distance(let requested) = values.pageStartSpacing,
                      let name = paragraphStyleName, let first = paragraphLines.first,
                      pages[pages.count - 1].lines.isEmpty, pages[pages.count - 1].images.isEmpty,
                      !(SectionEditing.opensSequence(in: text, atParagraph: paragraphRange.location)
                        && TextStyling.openingDistance(in: text, at: paragraphRange.location) != nil) else { return }
                let room = max(0, column.height - headingBeforeHeight - first.height - pageNotesHeight - bottomFiguresHeight)
                y = min(requested, room, reducedStart[paragraphRange.location] ?? requested)
                pageStarts[paragraphRange.location] = PageStartPlacement(style: name, requested: requested, effective: y, pageIndex: pages.count - 1)
            }
            applyPageStart()
            /// Quante righe del paragrafo, da `start`, entrano ancora nella pagina in corso: lo stesso conto della posa
            /// (la riga con la prima riga della sua prima nota, poi le note che entrano), senza posare niente.
            func linesFitting(from start: Int) -> Int {
                // Se il resto del paragrafo entra tutto, note comprese per intero, non serve simulare riga per riga.
                if carried.isEmpty {
                    let rest = paragraphLines[start...]
                    var height = y + (start == 0 ? headingBeforeHeight : 0)
                    for line in rest { height += line.height + line.spacingAfter }
                    height -= rest.last?.spacingAfter ?? 0
                    let allNotes = hasFootNotes ? rest.flatMap { line in footNotes(of: line).flatMap { note in note.lines.map { NoteEntry(line: $0, info: note.info) } } } : []
                    if height + (allNotes.isEmpty ? pageNotesHeight : notesHeight(pageNotes + allNotes)) + bottomFiguresHeight <= column.height { return rest.count }
                }
                var top = y, simulatedNotes = pageNotes, simulatedCarried = !carried.isEmpty
                var placedOnPage = pages[pages.count - 1].lines.count
                let images = pages[pages.count - 1].images.count
                var count = 0
                for index in start..<paragraphLines.count {
                    let line = paragraphLines[index]
                    let lineNotes = footNotes(of: line)
                    var required: [NoteEntry] = []
                    for (position, note) in lineNotes.enumerated() {
                        let entries = note.lines.map { NoteEntry(line: $0, info: note.info) }
                        if !note.info.style.canSplit { required += entries } else if position == 0, let first = entries.first { required.append(first) }
                    }
                    let empty = placedOnPage == 0 && simulatedNotes.isEmpty && images == 0
                    if top + line.height + notesHeight(simulatedNotes + required) + bottomFiguresHeight > column.height, !empty { break }
                    count += 1
                    placedOnPage += 1
                    top += line.height + line.spacingAfter
                    for note in lineNotes {
                        let entries = note.lines.map { NoteEntry(line: $0, info: note.info) }
                        for group in note.info.style.canSplit ? entries.map({ [$0] }) : [entries] {
                            let fits = top + notesHeight(simulatedNotes + group) + bottomFiguresHeight <= column.height
                            if !simulatedCarried && (fits || simulatedNotes.isEmpty && placedOnPage == 1) { simulatedNotes += group } else { simulatedCarried = true }
                        }
                    }
                }
                return count
            }
            /// Il punto in cui spezzare il paragrafo che continua da `start` in questa pagina, perché in cima alla pagina dopo
            /// restino almeno le righe minime; `nil` se entra tutto o se basta lo spezzamento naturale.
            func widowBreak(from start: Int, fitting: Int) -> Int? {
                let natural = start + fitting
                guard natural < paragraphLines.count, paragraphLines.count - natural < keeping.linesAtStart else { return nil }
                let earlier = paragraphLines.count - keeping.linesAtStart
                return earlier > start ? earlier : nil
            }
            /// Il paragrafo comincia qui, in una pagina già avviata: vero se deve passare tutto alla pagina dopo.
            func movesToNextPage() -> Bool {
                let fitting = linesFitting(from: 0)
                guard fitting < paragraphLines.count else { return false }
                if keeping.together || fitting < keeping.linesAtEnd { return true }
                if let earlier = widowBreak(from: 0, fitting: fitting) {
                    if earlier < keeping.linesAtEnd { return true }
                    plannedBreak = earlier
                }
                return false
            }
            if !keeping.isNone, !paragraphLines.isEmpty {
                if !pageIsEmpty, movesToNextPage() {
                    startNewPage()
                    if abs(column.width - composedWidth) > 0.01 {
                        paragraphLines = composedLines(bodyText, style: style, width: column.width - titleReserve, options: options, lineRules: lineRules)
                        composedWidth = column.width
                    }
                    applyPageStart()
                }
                // In cima a una pagina (anche dopo le note portate dalla precedente) contano solo le righe in cima alla seguente.
                if plannedBreak == nil, pages[pages.count - 1].lines.isEmpty || y == 0 {
                    plannedBreak = widowBreak(from: 0, fitting: linesFitting(from: 0))
                }
            }
            // Tieni col precedente del seguente: il punto in cui spezzare perché le ultime righe vadano con lui. Se ne
            // resterebbero troppo poche qui (o il paragrafo non si spezza), passa tutto.
            var tailBreak: Int?
            if tailCount > 0, !paragraphLines.isEmpty {
                let split = paragraphLines.count - tailCount
                if split <= 0 || split < keeping.linesAtEnd || keeping.together {
                    if !pageIsEmpty {
                        startNewPage()
                        if abs(column.width - composedWidth) > 0.01 {
                            paragraphLines = composedLines(bodyText, style: style, width: column.width - titleReserve, options: options, lineRules: lineRules)
                            composedWidth = column.width
                        }
                        applyPageStart()
                    }
                } else {
                    tailBreak = split
                    plannedBreak = min(plannedBreak ?? split, split)
                }
            }
            var lineNumber = 0
            while lineNumber < paragraphLines.count {
                defer { lineNumber += 1 }
                var line = paragraphLines[lineNumber]
                var lineNotes = footNotes(of: line)
                // La riga deve stare nella pagina insieme almeno alla prima riga della sua prima nota: il resto
                // della nota, se non entra, continua in fondo alla pagina successiva.
                func minimumHeight() -> CGFloat {
                    // La prima riga della prima nota, o tutta la nota se non si spezza; e tutte le note che non si spezzano.
                    var required: [NoteEntry] = []
                    for (position, note) in lineNotes.enumerated() {
                        let entries = note.lines.map { NoteEntry(line: $0, info: note.info) }
                        if !note.info.style.canSplit { required += entries } else if position == 0, let first = entries.first { required.append(first) }
                    }
                    return line.height + addedHeight(required) + (lineNumber == 0 ? headingBeforeHeight : 0)
                }
                if lineNumber == 0, let pendingKeep, let start = pageStarts[pendingKeep.start],
                   start.pageIndex == pages.count - 1, reducedStart[pendingKeep.start] == nil {
                    let excess = y + minimumHeight() + pageNotesHeight + bottomFiguresHeight - column.height
                    if excess > 0, start.effective > 0 {
                        reducedStart[pendingKeep.start] = max(0, start.effective - excess - 0.000001)
                        pendingKeep.restore()
                        keepBreakAt = pendingKeep.start
                        keepChain = nil
                        continue paragraphs
                    }
                }
                if lineNumber == plannedBreak || y + minimumHeight() + pageNotesHeight + bottomFiguresHeight > column.height, !pageIsEmpty {
                    startNewPage()
                    plannedBreak = nil
                    // La pagina nuova ha uno specchio di un'altra larghezza: il seguito del paragrafo si ricompone.
                    if abs(column.width - composedWidth) > 0.01 {
                        paragraphLines = Array(paragraphLines[..<lineNumber])
                            + continuationLines(bodyText, from: line.composedRange.location, style: style, width: column.width - titleReserve, options: options)
                        composedWidth = column.width
                        guard lineNumber < paragraphLines.count else { break }
                        line = paragraphLines[lineNumber]
                        lineNotes = footNotes(of: line)
                    }
                    if lineNumber == 0 { applyPageStart() }
                    // Il seguito, in cima alla pagina nuova: se continua ancora, che nella pagina dopo restino le righe minime.
                    if !keeping.isNone { plannedBreak = widowBreak(from: lineNumber, fitting: linesFitting(from: lineNumber)) }
                    if let tailBreak, tailBreak > lineNumber { plannedBreak = min(plannedBreak ?? tailBreak, tailBreak) }
                }
                for note in lineNotes { notePages[note.info.range.location] = pages.count }
                if lineNumber == 0 {
                    // Ricomposte qui: se il titolo è passato a una pagina nuova, i risultati leggono questa.
                    placeHeading(heading.map { headingPieces($0.split.before, number: headingNumber, titleStyle: paragraphStyleName, indices: $0.splitIndices.before) } ?? [],
                                 paragraphLocation: paragraphRange.location)
                    y += titleExtra
                }
                let placedLine = placed(line, top: y, map: body.map, paragraphLocation: paragraphRange.location, noteRange: nil, left: titleLeft(line))
                pages[pages.count - 1].lines.append(placedLine)
                if lineNumber == 0, let besidePiece, case .text(let numberLine, _, _, let width) = besidePiece.kind {
                    let index = pages.count - 1
                    let leftPage = pages[index].setup.facing && index % 2 == 1
                    let x = besidePiece.alignment.resolved(onLeftPage: leftPage) == .right ? column.maxX - width : column.minX
                    pages[index].markers.append(PlacedMarker(line: numberLine, origin: CGPoint(x: x, y: placedLine.origin.y), paragraphLocation: paragraphRange.location))
                    if let part = heading?.numberBesideIndex {
                        var ascent: CGFloat = 0, descent: CGFloat = 0
                        _ = CTLineGetTypographicBounds(numberLine, &ascent, &descent, nil)
                        pages[index].headingParts.append(PlacedHeadingPart(paragraphLocation: paragraphRange.location, part: part,
                            rect: CGRect(x: x, y: placedLine.origin.y - descent, width: width, height: ascent + descent)))
                    }
                }
                if lineNumber == 0, let marker {
                    pages[pages.count - 1].markers.append(PlacedMarker(
                        line: marker.line, origin: CGPoint(x: column.minX + marker.x, y: placedLine.origin.y), paragraphLocation: paragraphRange.location))
                }
                for note in body.notes where NSLocationInRange(note.marker, line.composedRange) && note.style.placement == .outerMargin {
                    placeMarginNote(note, beside: placedLine, paragraphStyle: style)
                }
                // Le figure richiamate in questa riga: a fine paragrafo (h, H), in fondo a questa pagina (b), o in attesa.
                for note in body.notes where NSLocationInRange(note.marker, line.composedRange) && note.style.placement == .figure {
                    let block = figureBlock(note, paragraphStyle: style)
                    if note.style.exactlyHere || note.style.positions.contains(.here) {
                        hereFigures.append(block)
                    } else if isBlocked(block) || !tryBottom(block) {
                        deferredFigures.append(block)
                    }
                }
                y += line.height + line.spacingAfter
                for note in lineNotes {
                    let entries = note.lines.map { NoteEntry(line: $0, info: note.info) }
                    // Una nota che non si spezza si colloca tutta insieme: qui, o tutta nella pagina dopo.
                    let groups = note.info.style.canSplit ? entries.map { [$0] } : [entries]
                    for group in groups {
                        // Una volta che una riga è stata rimandata, lo sono anche tutte le successive: l'ordine non cambia.
                        let fits = y + pageNotesHeight + bottomFiguresHeight + addedHeight(group) <= column.height
                        if carried.isEmpty && (fits || pageNotes.isEmpty && pages[pages.count - 1].lines.count == 1) {
                            for entry in group { addToPage(entry) }
                        } else {
                            carried += group
                        }
                    }
                }
            }
            placeHeading(heading.map { headingPieces($0.split.after, number: headingNumber, titleStyle: paragraphStyleName, indices: $0.splitIndices.after) } ?? [],
                         paragraphLocation: paragraphRange.location)
            // Tieni col seguente: se questo paragrafo è finito oltre la pagina del precedente della catena, si torna indietro.
            if keepChainBroken(by: paragraphRange.location, from: keepMark, pending: pendingKeep) { continue }
            keepChain?.lastPage = pages.count - 1
            // I filetti liberi del paragrafo, dati a mano o dallo stile: su ogni pagina in cui il paragrafo sta.
            if let rules = (TextStyling.paragraphRules(in: text, at: paragraphRange.location) ?? values.rules)?.rules, !rules.isEmpty {
                placeParagraphRules(rules, paragraph: paragraphRange.location, fromPage: keepMark.page)
            }
            y += style.paragraphSpacing
            location = NSMaxRange(paragraphRange)
            // Le figure da mettere subito dopo il paragrafo: H sempre (se non entra, nella pagina dopo), h se c'è posto.
            for block in hereFigures {
                let fits = y + floatSeparation + block.height + pageNotesHeight + bottomFiguresHeight <= column.height
                if block.style.exactlyHere {
                    if !fits, !pageIsEmpty { startNewPage() }
                } else if !fits || isBlocked(block) {
                    if !(isBlocked(block) ? false : tryBottom(block)) { deferredFigures.append(block) }
                    continue
                }
                if y > 0 { y += floatSeparation }
                placeFigure(block, top: y)
                y += block.height + floatSeparation
            }
            hereFigures = []
        }

        // Dopo l'ultimo a capo (o in un testo vuoto) c'è un paragrafo senza caratteri: non ha nulla da disegnare,
        // ma è lì che va il cursore a fine documento, quindi gli spetta una riga con le misure del suo font.
        if !finalParagraphPlaced, string.length == 0 || string.paragraphRange(for: NSRange(location: string.length, length: 0)).length == 0 {
            let font = (string.length > 0 ? text.attribute(.font, at: string.length - 1, effectiveRange: nil) as? NSFont : nil)
                ?? NSFont.userFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
            var style = (string.length > 0 ? text.attribute(.paragraphStyle, at: string.length - 1, effectiveRange: nil) as? NSParagraphStyle : nil) ?? .default
            // Anche una voce di elenco ancora vuota mostra il suo segno.
            var marker: ComposedMarker?
            if let (item, markerText) = listMarker(for: TextStyling.finalParagraphListItem(in: text)) {
                (style, marker) = listLayout(item: item, markerText: markerText, attributes: text.attributes(at: string.length - 1, effectiveRange: nil), style: style)
            }
            let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font), leading = CTFontGetLeading(font)
            let height = ascent + descent + leading
            if y + height + pageNotesHeight + bottomFiguresHeight > column.height, !pageIsEmpty { startNewPage() }
            let shift: CGFloat = switch style.alignment {
            case .right: column.width
            case .center: column.width / 2
            default: style.firstLineHeadIndent
            }
            let empty = ComposedLine(
                line: CTLineCreateWithAttributedString(NSAttributedString()), composedRange: NSRange(location: 0, length: 0), composedOffset: 0,
                endsWithHyphen: false, ascent: ascent, descent: descent, height: height, baselineFromTop: ascent, x: shift, spacingAfter: 0)
            let placedLine = placed(empty, top: y, map: .identity(location: string.length, length: 0), paragraphLocation: string.length, noteRange: nil)
            pages[pages.count - 1].lines.append(placedLine)
            if let marker {
                pages[pages.count - 1].markers.append(PlacedMarker(
                    line: marker.line, origin: CGPoint(x: column.minX + marker.x, y: placedLine.origin.y), paragraphLocation: string.length))
            }
        }
        // Le note di chiusura: dopo il testo, una serie dopo l'altra nell'ordine degli stili, ciascuna con il suo filetto e
        // il suo titolo. Le righe scorrono come quelle del corpo, e si scrivono al loro posto come le note a piè di pagina.
        for series in options.floatStyles where series.placement == .documentEnd {
            let members = endNotes.filter { $0.info.style.name == series.name }
            guard !members.isEmpty else { continue }
            if series.startsOnNewPage, !pageIsEmpty { startNewPage() } else if y > 0 { y += CGFloat(series.spaceAbove) }
            if series.showsRule {
                if y + noteRuleThickness + CGFloat(series.spaceBelow) + pageNotesHeight > column.height, !pageIsEmpty { startNewPage() }
                pages[pages.count - 1].rules.append(CGRect(x: column.minX, y: column.maxY - y - noteRuleThickness,
                                                           width: series.ruleLength.map { CGFloat($0) } ?? min(column.width / 3, 144), height: noteRuleThickness))
                y += noteRuleThickness + CGFloat(series.spaceBelow)
            }
            if let heading = series.heading, !heading.isEmpty {
                // Il titolo prende l'aspetto dello stile «Titolo 2», se il documento ce l'ha; non fa parte del testo.
                let headingStyle = ["Heading 2", "Titolo 2"].first { options.styles.style(named: $0) != nil }
                let character = options.styles.resolveCharacter(paragraphStyle: headingStyle, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: heading, attributes: TextStyling.characterAttributes(for: character).attributes))
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                if y + ascent + descent + pageNotesHeight > column.height, !pageIsEmpty { startNewPage() }
                pages[pages.count - 1].markers.append(PlacedMarker(line: line, origin: CGPoint(x: column.minX, y: column.maxY - (y + ascent)),
                                                                   paragraphLocation: members[0].info.textRange.location))
                y += ascent + descent + leading + ascent / 2
            }
            for (position, member) in members.enumerated() {
                if position > 0 { y += noteGap }
                for line in noteLines(member.info, paragraphStyle: member.paragraphStyle) {
                    if y + line.height + pageNotesHeight + bottomFiguresHeight > column.height, !pageIsEmpty { startNewPage() }
                    pages[pages.count - 1].lines.append(placed(line, top: y, map: member.info.map, paragraphLocation: member.info.textRange.location,
                                                               noteRange: member.info.textRange))
                    y += line.height + line.spacingAfter
                }
            }
        }
        // Le figure ancora in attesa alla fine del documento vanno nelle pagine seguenti; se una non trova posto nemmeno in
        // una pagina vuota, la si mette lo stesso in cima, senza limiti.
        var guardCount = 0
        while !deferredFigures.isEmpty, guardCount < 1000 {
            guardCount += 1
            let before = deferredFigures.count
            startNewPage()
            if deferredFigures.count == before, let first = deferredFigures.first {
                placeFigure(first, top: y)
                y += first.height + floatSeparation
                deferredFigures.removeFirst()
            }
        }
        // Le note rimaste in sospeso alla fine del documento proseguono su pagine proprie.
        if !carried.isEmpty { startNewPage() }
        closePage()
        // Intestazioni e piè di pagina, pagina per pagina, composti con i campi della loro pagina.
        for index in pages.indices {
            let opening = openingPages[index]
            let active = index < pageRunning.count ? pageRunning[index] : [:]
            let isEven = (index + 1) % 2 == 0
            for placement in [FloatStyle.Placement.pageHead, .pageBottom] {
                var chosen: RunningEntry?
                if let opening, let first = runningFirst[FirstKey(placement: placement, section: opening)] {
                    chosen = first
                } else if opening != nil, placement == .pageHead {
                    chosen = nil  // la prima pagina di una sezione che apre una pagina: senza intestazione
                } else {
                    chosen = active[RunningKey(placement: placement, pages: isEven ? .even : .odd)] ?? active[RunningKey(placement: placement, pages: .all)]
                }
                guard let entry = chosen else { continue }
                let pageSetup = pages[index].setup
                let area = pageSetup.textRect
                let sections = index < pageSections.count ? pageSections[index] : []
                let context = FieldContext(pageNumber: pages[index].number, pageCount: pageCount.map(String.init) ?? String(pages.count),
                                           sections: sections.map { FieldContext.Section(role: $0.role, title: $0.title, number: $0.number) })
                var note = entry.note
                let resolved = NSMutableAttributedString()
                var segments: [TextMap.Segment] = []
                appendResolvingFields(text, range: note.textRange, documentStart: 0, into: resolved, segments: &segments) { field, _ in field.asFormula.value(in: context) }
                note.text = resolved
                note.map = TextMap(segments: segments)
                let lines = noteLines(note, paragraphStyle: entry.paragraphStyle, width: area.width)
                guard !lines.isEmpty else { continue }
                let height = lines.dropLast().reduce(0) { $0 + $1.height + $1.spacingAfter } + lines.last!.height
                // Dal bordo del foglio: la distanza dello stile, o a metà del margine.
                let style = note.style
                let top: CGFloat = placement == .pageHead
                    ? CGFloat(style.edgeDistance ?? Double(max((pageSetup.top - height) / 2, 0)))
                    : pageSetup.paperSize.height - CGFloat(style.edgeDistance ?? Double(max((pageSetup.bottom - height) / 2, 0))) - height
                var y = top
                for line in lines {
                    let start = note.map.documentIndex(forComposed: line.composedRange.location)
                    let end = note.map.documentIndex(forComposed: NSMaxRange(line.composedRange))
                    pages[index].lines.append(PlacedLine(
                        line: line.line, origin: CGPoint(x: area.minX + line.x, y: pageSetup.paperSize.height - (y + line.baselineFromTop)),
                        // Come le righe delle note: il testo della nota, senza richiamo (lo cerca così chi mostra il cursore).
                        range: NSRange(location: start, length: max(end - start, 0)), paragraphLocation: note.textRange.location,
                        endsWithHyphen: line.endsWithHyphen, ascent: line.ascent, descent: line.descent, noteRange: note.textRange,
                        composedRange: line.composedRange, composedOffset: line.composedOffset, map: note.map,
                        naturalWidth: line.naturalWidth, width: line.width, availableWidth: line.availableWidth))
                    y += line.height + line.spacingAfter
                }
                if style.showsRule {
                    let length = style.ruleLength.map { CGFloat($0) } ?? area.width
                    let ruleTop = placement == .pageHead ? top + height + CGFloat(style.spaceBelow) : top - CGFloat(style.spaceAbove) - noteRuleThickness
                    pages[index].rules.append(CGRect(x: area.minX, y: pageSetup.paperSize.height - ruleTop - noteRuleThickness, width: length, height: noteRuleThickness))
                }
            }
        }
        // Con le pagine affacciate le pagine pari si spostano: il loro specchio sta dall'altra parte.
        for index in pages.indices where index % 2 == 1 && pages[index].setup.facing {
            do {
                let dx = pages[index].setup.horizontalShift(forPage: index)
                for line in pages[index].lines.indices { pages[index].lines[line].origin.x += dx }
                for marker in pages[index].markers.indices { pages[index].markers[marker].origin.x += dx }
                for rule in pages[index].rules.indices { pages[index].rules[rule].origin.x += dx }
                for fill in pages[index].fills.indices { pages[index].fills[fill].rect.origin.x += dx }
                for image in pages[index].images.indices { pages[index].images[image].rect.origin.x += dx }
            }
        }
        var layout = DocumentLayout(setup: setup, text: text, pages: pages, notes: notes)
        layout.listsNeedingOverflowChoice = overflowing
        layout.pageStarts = pageStarts
        layout.marginConflicts = marginConflicts
        layout.layoutRulesApplied = layoutRulesApplied
        layout.listMarks = listMarks
        layout.noteMarks = noteMarks
        return (layout, assumedNotePages, notePages, pageNumbers)
    }

    // MARK: Composizione di un paragrafo

    /// Il seguito di un paragrafo da `start`, composto con un'altra larghezza (su una pagina nuova di un altro tipo): senza
    /// il rientro della prima riga, con le posizioni riportate al paragrafo.
    private static func continuationLines(_ paragraph: NSAttributedString, from start: Int, style: NSParagraphStyle, width: CGFloat,
                                          options: LayoutOptions) -> [ComposedLine] {
        guard start < paragraph.length else { return [] }
        let continuing = (style.mutableCopy() as! NSMutableParagraphStyle)
        continuing.firstLineHeadIndent = style.headIndent
        let text = paragraph.attributedSubstring(from: NSRange(location: start, length: paragraph.length - start))
        return composedLines(text, style: start == 0 ? style : continuing, width: width, options: options).map { line in
            var line = line
            line.composedRange.location += start
            line.composedOffset += start
            return line
        }
    }

    /// Una riga composta, non ancora collocata in una pagina. Le posizioni sono quelle del paragrafo composto.
    private struct ComposedLine {
        /// Per una riga allineata sulla virgola: dove sta il segno decimale, dall'inizio della riga.
        var decimalOffset: CGFloat? = nil
        var line: CTLine
        var composedRange: NSRange
        var composedOffset: Int
        var endsWithHyphen: Bool
        var ascent: CGFloat
        var descent: CGFloat
        var height: CGFloat
        /// Distanza della linea di base dal bordo superiore della riga.
        var baselineFromTop: CGFloat
        /// Spostamento dell'inizio della riga rispetto al bordo sinistro della colonna.
        var x: CGFloat
        var spacingAfter: CGFloat
        var naturalWidth: CGFloat = 0
        var width: CGFloat = 0
        var availableWidth: CGFloat = 0
    }

    /// Spezza in righe un paragrafo già pronto per Core Text e ne calcola misure e allineamento.
    /// Chiave della memoria delle righe: lo stesso testo (con i numeri delle note già dentro), con lo stesso stile di
    /// paragrafo, la stessa larghezza e le stesse scelte, dà le stesse righe.
    private final class LinesKey: NSObject {
        let paragraph: NSAttributedString
        let style: NSParagraphStyle
        let width: CGFloat
        let composition: LayoutOptions.LineComposition
        /// Solo per i paragrafi con regole di riga, che si compongono anche con gli stili delle regole.
        let ruleStyles: StyleSheet?
        private let hashValueCache: Int

        init(paragraph: NSAttributedString, style: NSParagraphStyle, width: CGFloat, options: LayoutOptions, usesRuleStyles: Bool) {
            // Una copia: il testo che arriva può essere modificabile, e la chiave non deve cambiare dopo.
            self.paragraph = paragraph.copy() as! NSAttributedString
            self.style = style.copy() as! NSParagraphStyle
            self.width = width
            composition = options.lineComposition
            ruleStyles = usesRuleStyles ? options.styles : nil
            hashValueCache = paragraph.string.hashValue ^ Int(width * 16) ^ style.hash
        }

        override var hash: Int { hashValueCache }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? LinesKey else { return false }
            return width == other.width && composition == other.composition && ruleStyles == other.ruleStyles && style.isEqual(other.style)
                && paragraph.isEqual(to: other.paragraph)
        }
    }

    private final class LinesValue: NSObject {
        let lines: [ComposedLine]
        init(_ lines: [ComposedLine]) { self.lines = lines }
    }

    /// Le righe di ogni paragrafo già composte: a ogni tasto si ricompone solo il paragrafo che è cambiato (o la cui
    /// numerazione di note è cambiata); gli altri ritrovano qui le loro righe. La disposizione nelle pagine si rifà.
    private static let linesCache = TwoGenerationCache<LinesKey, LinesValue>(limit: 8000)

    /// Svuota le memorie degli a capo e delle righe (per le prove: una composizione da zero).
    static func clearCaches() {
        breakCache.removeAll()
        linesCache.removeAll()
    }

    private static func composedLines(_ paragraph: NSAttributedString, style: NSParagraphStyle, width columnWidth: CGFloat,
                                      options: LayoutOptions, lineRules: LineRuleSpec? = nil) -> [ComposedLine] {
        guard paragraph.length > 0 else { return [] }
        // Le regole di riga sono annotate nel testo: la chiave le distingue già.
        let key = LinesKey(paragraph: paragraph, style: style, width: columnWidth, options: options, usesRuleStyles: lineRules != nil)
        if let cached = linesCache.object(forKey: key) { return cached.lines }
        let lines = if let lineRules {
            composeLines(paragraph, style: style, width: columnWidth, options: options, applying: lineRules)
        } else {
            composeLines(paragraph, style: style, width: columnWidth, options: options)
        }
        linesCache.setObject(LinesValue(lines), forKey: key)
        return lines
    }

    /// Le righe di un paragrafo con regole di riga. Le prime N righe sono quelle del paragrafo composto tutto nello stile
    /// della regola: così il testo nello stile coincide con le righe, e la riga successiva comincia esattamente dove
    /// quelle finiscono. Il resto si compone a parte, come seguito del paragrafo. L'ultima riga si trova componendo il
    /// resto normalmente, e si ricompone nello stile della sua regola (se lo stile la allarga, possono diventare due).
    private static func composeLines(_ paragraph: NSAttributedString, style: NSParagraphStyle, width columnWidth: CGFloat,
                                     options: LayoutOptions, applying rules: LineRuleSpec) -> [ComposedLine] {
        let length = paragraph.length
        func styled(_ text: NSAttributedString, _ name: String) -> NSAttributedString {
            let copy = NSMutableAttributedString(attributedString: text)
            Rules.applyStyle(name, to: NSRange(location: 0, length: copy.length), in: copy, sheet: options.styles, retracks: options.appliesFontTracking, resolver: FontRoleResolver(table: options.fontRoles))
            return copy
        }
        // Il seguito di un paragrafo: senza il rientro della prima riga, con le posizioni riportate al paragrafo.
        let continuing = (style.mutableCopy() as! NSMutableParagraphStyle)
        continuing.firstLineHeadIndent = style.headIndent
        func lines(from start: Int, styledWith name: String? = nil) -> [ComposedLine] {
            var text = paragraph.attributedSubstring(from: NSRange(location: start, length: length - start))
            if let name { text = styled(text, name) }
            return composeLines(text, style: start == 0 ? style : continuing, width: columnWidth, options: options).map { line in
                var line = line
                line.composedRange.location += start
                line.composedOffset += start
                return line
            }
        }
        var result: [ComposedLine] = []
        var start = 0
        if let first = rules.firstLines {
            let all = composeLines(styled(paragraph, first.style), style: style, width: columnWidth, options: options)
            result = Array(all.prefix(first.count))
            start = result.last.map { NSMaxRange($0.composedRange) } ?? length
        }
        guard start < length else { return result }
        var rest = lines(from: start)
        if let last = rules.lastLine, let final = rest.last {
            rest.removeLast()
            rest += lines(from: final.composedRange.location, styledWith: last)
        }
        return result + rest
    }

    /// Larghezza degli spazi visibili della riga: quelli finali non partecipano alla giustificazione. Gli indici di
    /// una riga sillabata ripartono da zero, mentre quelli di una riga del compositore restano nel paragrafo.
    private static func spaceWidth(of line: CTLine, string: NSString, range: NSRange, base: Int) -> Double {
        let whitespace = CharacterSet.whitespacesAndNewlines
        let local = NSRange(location: range.location - base, length: range.length)
        var end = NSMaxRange(local)
        while end > local.location, Unicode.Scalar(string.character(at: end - 1)).map(whitespace.contains) ?? false { end -= 1 }
        var result = 0.0
        for index in local.location..<end where Unicode.Scalar(string.character(at: index)).map(whitespace.contains) ?? false {
            let before = CTLineGetOffsetForStringIndex(line, index, nil)
            let after = CTLineGetOffsetForStringIndex(line, index + 1, nil)
            result += max(after - before, 0)
        }
        return result
    }

    private static func composeLines(_ paragraph: NSAttributedString, style: NSParagraphStyle, width columnWidth: CGFloat,
                                     options: LayoutOptions) -> [ComposedLine] {
        // La famiglia scelta viaggia con ogni tratto: così si riconoscono i caratteri disegnati con un font di ripiego.
        let paragraph = FontFallback.annotated(paragraph)
        let paragraphString = paragraph.string as NSString
        let length = paragraph.length
        guard length > 0 else { return [] }
        // Per Core Text il testo Graphite sono segnaposto; gli a capo si cercano nel testo vero (`paragraph`).
        let typesetterText = GraphiteLayout.placeholders(paragraph)
        let typesetter = CTTypesetterCreateWithAttributedString(typesetterText)
        // Con i segnaposto Core Text andrebbe a capo fra due gruppi qualsiasi, anche dentro una parola.
        let hasPlaceholders = typesetterText !== paragraph
        // Come in NSParagraphStyle: un rientro di coda positivo si misura dal margine sinistro, altrimenti dal destro.
        let tail = style.tailIndent > 0 ? style.tailIndent : columnWidth + style.tailIndent
        func availableWidth(firstLine: Bool) -> CGFloat { max(tail - (firstLine ? style.firstLineHeadIndent : style.headIndent), 1) }
        // Gli a capo decisi in anticipo per tutto il paragrafo, se la scelta ottimale è richiesta e applicabile.
        let planned: [LineBreak]? = options.lineBreaking == .optimal
            ? plannedBreaks(paragraph: paragraph, typesetter: typesetter, firstWidth: availableWidth(firstLine: true),
                            restWidth: availableWidth(firstLine: false), justified: style.alignment == .justified,
                            protrusion: protrusion(for: style.alignment, options: options), options: options)
            : nil
        var plannedIndex = 0
        var lines: [ComposedLine] = []

        var start = 0
        var consecutiveHyphens = 0
        while start < length {
            let head = start == 0 ? style.firstLineHeadIndent : style.headIndent
            let available = availableWidth(firstLine: start == 0)
            var count: Int
            var line: CTLine
            // La stringa a cui si riferiscono gli indici della riga, e la posizione del suo indice zero nel paragrafo.
            var lineString = paragraphString
            var lineBase = 0
            var endsWithHyphen = false
            if let planned, plannedIndex < planned.count, planned[plannedIndex].end > start {
                let lineBreak = planned[plannedIndex]
                plannedIndex += 1
                count = lineBreak.end - start
                if let hyphen = lineBreak.hyphen {
                    let composed = hyphenatedLine(paragraph: paragraph, start: start, end: lineBreak.end, hyphen: hyphen, tracked: options.appliesFontTracking)
                    line = composed.line
                    lineString = composed.string
                    lineBase = start
                    endsWithHyphen = true
                } else {
                    line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                }
            } else {
                count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(available)), 1)
                if hasPlaceholders, start + count < length,
                   let end = GraphiteLayout.lastLineBreak(in: paragraphString, after: start, notBeyond: start + count) {
                    count = end - start
                }
                line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                // Si divide una parola solo se la riga, senza, resterebbe visibilmente corta (più del 4% della
                // giustezza da riempire allargando gli spazi), e mai per più di due righe di seguito.
                let slack = available - (CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line)))
                if options.hyphenates, slack > available * hyphenationZone, consecutiveHyphens < maximumConsecutiveHyphens,
                   let hyphenated = firstFitHyphenation(paragraph: paragraph, start: start, breakAt: start + count, width: available,
                                                        defaultLanguage: options.hyphenationLanguage, tracked: options.appliesFontTracking) {
                    line = hyphenated.line
                    count = hyphenated.count
                    lineString = hyphenated.string
                    lineBase = start
                    endsWithHyphen = true
                }
                consecutiveHyphens = endsWithHyphen ? consecutiveHyphens + 1 : 0
            }
            // Come l'ultima riga del paragrafo, una riga chiusa da un a capo scritto non si giustifica. Vale per
            // l'a capo interno e, nelle note di più paragrafi, per la fine di ciascun paragrafo.
            let isLastLine = start + count >= length || [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(Int(paragraphString.character(at: start + count - 1)))
            // La spaziatura aggiunta dopo l'ultimo glifo visibile non deve contare per l'allineamento a destra.
            let trailingKern = kernAfterLastVisibleCharacter(of: paragraph, in: NSRange(location: start, length: count))
            // Di quanto i bordi ottici del primo e dell'ultimo glifo rientrano rispetto alla loro cassa.
            let insets = options.usesOpticalMargins ? opticalInsets(of: line, string: lineString) : (left: 0, right: 0)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line)) - trailingKern
            let spaces = spaceWidth(of: line, string: lineString, range: NSRange(location: start, length: count), base: lineBase)
            // Come nella scelta degli a capo: nel testo giustificato la riga si allarga dei due rientri ottici.
            let expansion = LineBreaker.glyphExpansion(natural: Double(naturalWidth - insets.left - insets.right), spaces: spaces, width: Double(available),
                                                       justified: style.alignment == .justified, forced: isLastLine, hyphenated: endsWithHyphen,
                                                       expansionLimit: options.glyphExpansionLimit)
            if abs(expansion) > 1e-9 {
                if endsWithHyphen {
                    line = hyphenatedLine(paragraph: paragraph, start: start, end: start + count, hyphen: lineString.substring(from: count),
                                          tracked: options.appliesFontTracking, expansion: expansion).line
                } else {
                    let expandedText = NSMutableAttributedString(attributedString: typesetterText)
                    expandFonts(in: expandedText, by: expansion)
                    let expandedTypesetter = CTTypesetterCreateWithAttributedString(expandedText)
                    line = CTTypesetterCreateLine(expandedTypesetter, CFRange(location: start, length: count))
                }
            }
            if style.alignment == .justified, !isLastLine,
               let justified = CTLineCreateJustifiedLine(line, 1, Double(available + trailingKern + insets.left + insets.right)) {
                line = justified
            }

            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let visibleWidth = width - CGFloat(CTLineGetTrailingWhitespaceWidth(line)) - trailingKern
            var height = ascent + descent + leading
            if style.lineHeightMultiple > 0 { height *= style.lineHeightMultiple }
            if style.minimumLineHeight > 0 { height = max(height, style.minimumLineHeight) }
            if style.maximumLineHeight > 0 { height = min(height, style.maximumLineHeight) }

            // I bordi ottici, non le casse dei glifi, vanno sui margini: a sinistra la riga arretra del rientro
            // ottico del primo glifo, a destra avanza di quello dell'ultimo. Nel testo centrato, invece, i due bianchi
            // devono essere uguali: misuriamo il contorno davvero disegnato, spalline dei glifi comprese.
            let centeredBounds = style.alignment == .center ? CTLineGetImageBounds(line, nil) : .null
            var shift: CGFloat = switch style.alignment {
            case .right: available - visibleWidth + insets.right
            case .center: centeredBounds.isNull || centeredBounds.isInfinite || centeredBounds.isEmpty
                ? (available - visibleWidth + insets.right - insets.left) / 2
                : (available - centeredBounds.width) / 2 - centeredBounds.minX
            default: -insets.left
            }
            // Sulla virgola: il segno decimale al centro della riga (in una tabella lo sposta poi la colonna).
            var decimalOffset: CGFloat?
            if style.isDecimalAligned, !endsWithHyphen {
                let language = paragraph.attribute(.language, at: min(start, max(length - 1, 0)), effectiveRange: nil) as? String ?? options.hyphenationLanguage
                let offset = decimalSeparatorOffset(line, in: paragraphString, range: NSRange(location: start, length: count), language: language, visibleWidth: visibleWidth)
                decimalOffset = offset
                shift = available / 2 - offset
            }
            lines.append(ComposedLine(decimalOffset: decimalOffset,
                line: line, composedRange: NSRange(location: start, length: count), composedOffset: lineBase, endsWithHyphen: endsWithHyphen,
                ascent: ascent, descent: descent, height: height,
                // L'eventuale interlinea aggiunta va sopra la riga: la linea di base resta a `descent + leading` dal fondo.
                baselineFromTop: height - descent - leading, x: head + shift, spacingAfter: style.lineSpacing,
                naturalWidth: naturalWidth, width: visibleWidth, availableWidth: available))
            start += count
        }
        return lines
    }

    /// Dove sta, dall'inizio della riga, il segno decimale della lingua (la virgola per l'italiano, il punto per l'inglese):
    /// il primo segno tra due cifre; se non c'è, la fine dell'ultima cifra (un numero intero si allinea sulla sua fine);
    /// senza cifre, la fine del testo.
    private static func decimalSeparatorOffset(_ line: CTLine, in string: NSString, range: NSRange, language: String?, visibleWidth: CGFloat) -> CGFloat {
        let separator = ((language.map { Locale(identifier: $0) } ?? Locale.current).decimalSeparator ?? ",") as NSString
        let digits = CharacterSet.decimalDigits
        func isDigit(_ index: Int) -> Bool {
            index >= range.location && index < NSMaxRange(range) && (UnicodeScalar(string.character(at: index)).map { digits.contains($0) } ?? false)
        }
        var lastDigitEnd: Int?
        for index in range.location..<NSMaxRange(range) {
            if separator.length > 0, index + separator.length <= NSMaxRange(range),
               string.substring(with: NSRange(location: index, length: separator.length)) == separator as String,
               isDigit(index - 1), isDigit(index + separator.length) {
                return CTLineGetOffsetForStringIndex(line, index, nil)
            }
            if isDigit(index) { lastDigitEnd = index + 1 }
        }
        if let lastDigitEnd { return CTLineGetOffsetForStringIndex(line, lastDigitEnd, nil) }
        return visibleWidth
    }

    // MARK: Elenchi

    /// Il segno di una voce di elenco, composto, con la sua ascissa rispetto al bordo sinistro della colonna.
    private struct ComposedMarker {
        var line: CTLine
        var x: CGFloat
    }

    /// Dispone una voce di elenco: ogni livello rientra di due volte il corpo, il testo comincia alla fine del
    /// rientro e il segno gli sta davanti, allineato a destra (così i punti di «9.» e «10.» cadono uno sotto
    /// l'altro) e staccato di mezzo corpo. Un segno più largo del rientro comincia all'inizio del livello e
    /// sposta a destra la sola prima riga.
    ///
    /// Il segno prende font, corpo e funzioni dal primo carattere della voce.
    private static func listLayout(item: ListItem, markerText: String, attributes: [NSAttributedString.Key: Any], style: NSParagraphStyle)
        -> (style: NSParagraphStyle, marker: ComposedMarker) {
        var markerAttributes = attributes
        for key in [NSAttributedString.Key.footnote, .paragraphStyle, .listItem, .finalParagraphList] { markerAttributes[key] = nil }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: markerText, attributes: markerAttributes))
        // La spaziatura aggiunta dopo l'ultimo glifo non fa parte della larghezza visibile del segno.
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat((markerAttributes[.kern] as? NSNumber)?.doubleValue ?? 0)
        // Misure fisse in punti (scelte di Artemij Keidan, 17 ottobre 2026): dove comincia il testo e dove finisce il segno,
        // due posizioni indipendenti; il segno si allinea a destra sulla sua. Senza misure proprie, il testo a 24 pt per
        // livello e il segno che finisce 6 pt prima, come prima a corpo 12.
        let measures = item.resolvedMeasures(in: [])
        let textStart = style.headIndent + CGFloat(measures.textIndent)
        let markerEnd = style.headIndent + CGFloat(measures.markerPosition)
        let x = max(markerEnd - width, 0)
        let result = style.mutableCopy() as! NSMutableParagraphStyle
        result.headIndent = textStart
        // Un segno che arriva oltre l'inizio del testo spinge solo la prima riga.
        result.firstLineHeadIndent = max(textStart, x + width + CGFloat(ListItem.minimumMarkerSpace))
        return (result, ComposedMarker(line: line, x: x))
    }

    // MARK: Note a piè di pagina

    private static let noteRuleThickness: CGFloat = 0.5
    /// Spazio tra una nota e la successiva.
    private static let noteGap: CGFloat = 2

    /// Una nota pronta per essere composta: il suo testo preceduto dal numero.
    private struct ComposedNote {
        /// Caratteri del documento dal richiamo alla fine del testo della nota.
        var range: NSRange
        /// Caratteri del documento che formano il testo della nota, senza il richiamo.
        var textRange: NSRange
        /// Posizione, nel corpo composto, del numero di richiamo.
        var marker: Int
        var text: NSAttributedString
        var map: TextMap
        /// Lo stile di flottante della nota: la sua serie.
        var style: FloatStyle
        /// Per una figura, la sua immagine.
        var image: ImageObject?
    }

    /// Il corpo di un paragrafo come va composto: il testo di ogni nota è sostituito dal numero di richiamo.
    /// Restituisce anche la mappa verso il documento e le note, ciascuna con il suo numero davanti.
    /// Aggiunge a `result` il tratto `range` di `source`, con i campi sostituiti dal loro testo: i tratti di testo vero
    /// entrano nella mappa (dal composto al documento, che comincia in `documentStart`), il testo dei campi no.
    private static func appendResolvingFields(_ source: NSAttributedString, range: NSRange, documentStart: Int, into result: NSMutableAttributedString,
                                              segments: inout [TextMap.Segment], field: (Field, Int) -> String) {
        var cursor = range.location
        func flush(upTo end: Int) {
            guard end > cursor else { return }
            segments.append(TextMap.Segment(composed: result.length, document: documentStart + cursor, length: end - cursor))
            result.append(source.attributedSubstring(from: NSRange(location: cursor, length: end - cursor)))
            cursor = end
        }
        source.enumerateAttribute(.field, in: range) { value, run, _ in
            guard let found = (value as? String).flatMap(Field.init(encoded:)) else { return }
            for index in run.location..<NSMaxRange(run) {
                flush(upTo: index)
                var attributes = source.attributes(at: index, effectiveRange: nil)
                attributes[.field] = nil
                attributes[.composedField] = documentStart + index
                result.append(NSAttributedString(string: field(found, documentStart + index), attributes: attributes))
                cursor = index + 1
            }
        }
        flush(upTo: NSMaxRange(range))
    }

    private static func composedBody(of paragraph: NSAttributedString, location: Int, field: (Field, Int) -> String, floatStyles: [FloatStyle],
                                     noteMark: (_ anchor: Int) -> String)
        -> (text: NSAttributedString, map: TextMap, notes: [ComposedNote]) {
        let length = paragraph.length
        var effective = NSRange(location: 0, length: 0)
        var fieldRun = NSRange(location: 0, length: 0)
        let hasFields = length > 0 && !(paragraph.attribute(.field, at: 0, longestEffectiveRange: &fieldRun, in: NSRange(location: 0, length: length)) == nil
            && fieldRun.length == length)
        if length == 0 || (!hasFields && paragraph.attribute(.footnote, at: 0, longestEffectiveRange: &effective, in: NSRange(location: 0, length: length)) == nil
                           && effective.length == length) {
            return (paragraph, .identity(location: location, length: length), [])
        }
        // Ogni carattere-richiamo marcato come nota apre una nota, che dura fino al richiamo successivo o alla fine del tratto marcato.
        var spans: [(anchor: Int, end: Int)] = []
        paragraph.enumerateAttribute(.footnote, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard value != nil else { return }
            var open: Int?
            for index in range.location..<NSMaxRange(range) where TextStyling.isNoteAnchor(in: paragraph, at: index) {
                if let anchor = open { spans.append((anchor, index)) }
                open = index
            }
            if let anchor = open { spans.append((anchor, NSMaxRange(range))) }
        }
        guard !spans.isEmpty || hasFields else { return (paragraph, .identity(location: location, length: length), []) }

        let body = NSMutableAttributedString()
        var segments: [TextMap.Segment] = []
        var notes: [ComposedNote] = []
        var cursor = 0
        for span in spans {
            appendResolvingFields(paragraph, range: NSRange(location: cursor, length: span.anchor - cursor), documentStart: location, into: body,
                                  segments: &segments, field: field)
            let styleName = paragraph.attribute(.footnote, at: span.anchor, effectiveRange: nil) as? String ?? FloatStyle.footnoteName
            let floatStyle = floatStyles.first { $0.name == styleName } ?? FloatStyle(name: styleName)
            // Senza richiamo la nota non consuma un numero; una figura si numera (nella didascalia) se ha una Lista.
            let isFigure = floatStyle.placement == .figure
            let mark = isFigure ? (floatStyle.listName != nil ? noteMark(location + span.anchor) : "")
                : (floatStyle.reference == .none ? "" : noteMark(location + span.anchor))
            var noteAttributes = paragraph.attributes(at: span.anchor, effectiveRange: nil)
            noteAttributes[.footnote] = nil
            // Il richiamo prende l'aspetto del testo che lo precede; in testa al paragrafo, quello della nota.
            var bodyAttributes = body.length > 0 ? body.attributes(at: body.length - 1, effectiveRange: nil) : noteAttributes
            bodyAttributes[.footnote] = nil
            bodyAttributes[.composedField] = nil
            let marker = body.length
            let text = NSMutableAttributedString()
            switch isFigure ? .none : floatStyle.reference {
            case .superscript:
                body.append(referenceMark(mark, attributes: bodyAttributes))
                text.append(referenceMark(mark, attributes: noteAttributes))
                text.append(NSAttributedString(string: " ", attributes: noteAttributes))
            case .plain:
                body.append(NSAttributedString(string: mark, attributes: bodyAttributes))
                text.append(NSAttributedString(string: mark + " ", attributes: noteAttributes))
            case .none:
                // Un segno senza larghezza che non permette di andare a capo: tiene il posto del richiamo, così la nota
                // sa in quale riga cade.
                body.append(NSAttributedString(string: "\u{2060}", attributes: bodyAttributes))
                // La didascalia di una figura comincia con il suo numero («Figura 1.»).
                if isFigure, !mark.isEmpty { text.append(NSAttributedString(string: mark + " ", attributes: noteAttributes)) }
            }
            let textRange = NSRange(location: span.anchor + 1, length: span.end - span.anchor - 1)
            var noteSegments: [TextMap.Segment] = []
            appendResolvingFields(paragraph, range: textRange, documentStart: location, into: text, segments: &noteSegments, field: field)
            notes.append(ComposedNote(
                range: NSRange(location: location + span.anchor, length: span.end - span.anchor),
                textRange: NSRange(location: location + textRange.location, length: textRange.length), marker: marker, text: text,
                map: TextMap(segments: noteSegments),
                style: floatStyle, image: (paragraph.attribute(.floatImage, at: span.anchor, effectiveRange: nil) as? ImageAttachment)?.image))
            cursor = span.end
        }
        appendResolvingFields(paragraph, range: NSRange(location: cursor, length: length - cursor), documentStart: location, into: body,
                              segments: &segments, field: field)
        return (body, TextMap(segments: segments), notes)
    }

    /// Il corpo di un paragrafo con il testo che il suo stile scrive prima e dopo (vedi `WrittenResult`). Il testo aggiunto
    /// non ha posto nella mappa: per il cursore è materiale composto, come un numero di richiamo. Prende l'aspetto del
    /// carattere vicino (il primo, o l'ultimo prima della fine del paragrafo) e, sopra, quello del suo stile.
    private static func writingResults(_ writes: [WrittenResult], into body: (text: NSAttributedString, map: TextMap, notes: [ComposedNote]),
                                       context: FieldContext, sheet: StyleSheet, retracks: Bool, resolver: FontRoleResolver)
        -> (text: NSAttributedString, map: TextMap, notes: [ComposedNote]) {
        let text = NSMutableAttributedString(attributedString: body.text)
        let string = text.string as NSString
        // La fine del testo: prima del separatore del paragrafo.
        var end = string.length
        while end > 0, let scalar = Unicode.Scalar(string.character(at: end - 1)), CharacterSet.newlines.contains(scalar) { end -= 1 }
        func piece(_ written: WrittenResult, near index: Int) -> NSAttributedString? {
            let string = written.text(in: context)
            guard !string.isEmpty else { return nil }
            var attributes = text.length > 0 ? text.attributes(at: min(max(index, 0), text.length - 1), effectiveRange: nil) : [:]
            for key in [NSAttributedString.Key.field, .composedField, .footnote, .link] { attributes[key] = nil }
            let piece = NSMutableAttributedString(string: string, attributes: attributes)
            if let style = written.style, sheet.style(named: style) != nil {
                Rules.applyStyle(style, to: NSRange(location: 0, length: piece.length), in: piece, sheet: sheet, retracks: retracks, resolver: resolver)
            }
            return piece
        }
        let before = NSMutableAttributedString()
        for written in writes where written.place == .before { if let piece = piece(written, near: 0) { before.append(piece) } }
        let after = NSMutableAttributedString()
        for written in writes where written.place == .after { if let piece = piece(written, near: end - 1) { after.append(piece) } }
        guard before.length > 0 || after.length > 0 else { return body }
        // Il testo dopo entra prima del separatore; quello prima sposta tutto il resto.
        text.insert(after, at: end)
        text.insert(before, at: 0)
        let shift = before.length
        var segments: [TextMap.Segment] = []
        for segment in body.map.segments {
            let start = segment.composed + shift
            // Un tratto che attraversa il punto in cui entra il testo dopo si divide in due.
            if after.length > 0, segment.composed < end, segment.composed + segment.length > end {
                let head = end - segment.composed
                segments.append(TextMap.Segment(composed: start, document: segment.document, length: head))
                segments.append(TextMap.Segment(composed: start + head + after.length, document: segment.document + head, length: segment.length - head))
            } else {
                segments.append(TextMap.Segment(composed: start + (after.length > 0 && segment.composed >= end ? after.length : 0),
                                                document: segment.document, length: segment.length))
            }
        }
        let notes = body.notes.map { note in
            var moved = note
            moved.marker += shift + (note.marker >= end ? after.length : 0)
            return moved
        }
        return (text, TextMap(segments: segments), notes)
    }

    /// Le cifre in apice di Unicode, da 0 a 9.
    private static let superiorDigits: [unichar] = [0x2070, 0x00B9, 0x00B2, 0x00B3, 0x2074, 0x2075, 0x2076, 0x2077, 0x2078, 0x2079]

    /// Un numero di richiamo, con l'aspetto migliore che il font consente. In ordine di preferenza:
    /// 1. le vere cifre in apice attivate da una funzione del font (AAT «Vertical Position» o OpenType `sups`);
    /// 2. i glifi Unicode delle cifre in apice (¹ ² ³…), se il font li ha tutti: sono disegnati apposta, anche
    ///    quando il font non dichiara la funzione (è il caso di Hoefler Text);
    /// 3. la cifra normale rimpicciolita e alzata, leggermente ingrossata perché non risulti più chiara del testo.
    static func referenceMark(_ number: Int, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        referenceMark(String(number), attributes: attributes)
    }

    /// Un segno di richiamo qualsiasi, dato da una Lista. I segni tipografici (* † ‡ § ‖ ¶) si scrivono a corpo
    /// pieno, come vuole l'uso; cifre e lettere vanno in apice come i numeri.
    static func referenceMark(_ digits: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var result = attributes
        result[.footnote] = nil
        if !digits.isEmpty, digits.allSatisfy({ ListCounter.symbolSeries.contains(String($0)) }) {
            return NSAttributedString(string: digits, attributes: result)
        }
        guard let nsFont = attributes[.font] as? NSFont else { return NSAttributedString(string: digits, attributes: result) }
        let font = nsFont as CTFont

        let current = FontFeatures.settings(of: font)
        for type in FontFeatures.types(of: font) {
            for selector in type.selectors where selector.setting == .aat(type: 10, selector: 1) || selector.openTypeTag == "sups" {
                let settings = type.isExclusive ? type.selecting(selector, in: current) : type.setting(selector, on: true, in: current)
                let candidate = FontFeatures.font(font, with: settings)
                // La funzione conta solo se cambia davvero il glifo di ogni carattere del segno.
                if digits.allSatisfy({ Shaper.glyphIDs(for: String($0), font: candidate) != Shaper.glyphIDs(for: String($0), font: font) }) {
                    result[.font] = candidate
                    return NSAttributedString(string: digits, attributes: result)
                }
            }
        }

        var characters = superiorDigits
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        if digits.allSatisfy({ ("0"..."9").contains($0) }), CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) {
            let superiors = digits.unicodeScalars.map { superiorDigits[Int($0.value) - 0x30] }
            return NSAttributedString(string: String(utf16CodeUnits: superiors, count: superiors.count), attributes: result)
        }

        let size = CTFontGetSize(font)
        let small = TextStyling.resized(font, to: size * 0.62)
        result[.font] = small
        // Alzata quanto basta, ma senza superare l'altezza delle lettere: altrimenti la riga col richiamo sarebbe più alta delle altre.
        result[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] = min(size * 0.34, CTFontGetAscent(font) - CTFontGetAscent(small))
        // Un contorno sottile (in percentuale del corpo, negativo = contorno più riempimento) compensa l'assottigliamento dovuto alla riduzione.
        result[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -2.5
        return NSAttributedString(string: digits, attributes: result)
    }

    /// Le note si compongono con l'allineamento del paragrafo che le richiama, ma senza rientri né spazi aggiunti.
    /// Con uno stile del contenuto, le note si compongono con quello stile di paragrafo.
    private static func noteParagraphStyle(for floatStyle: FloatStyle, from style: NSParagraphStyle, options: LayoutOptions) -> NSParagraphStyle {
        if let content = floatStyle.contentStyle, options.styles.style(named: content) != nil {
            return options.styles.resolveParagraph(styleName: content).nsParagraphStyle
        }
        return noteParagraphStyle(from: style)
    }

    private static func noteParagraphStyle(from style: NSParagraphStyle) -> NSParagraphStyle {
        let result = NSMutableParagraphStyle()
        result.alignment = style.alignment
        result.lineHeightMultiple = style.lineHeightMultiple
        return result
    }

    // MARK: Sillabazione

    /// Quanta parte della giustezza può restare vuota prima che convenga dividere una parola.
    private static let hyphenationZone: CGFloat = 0.04
    private static let maximumConsecutiveHyphens = 2

    /// Prova a far entrare nella riga un pezzo della parola che altrimenti andrebbe tutta a capo.
    ///
    /// Tra i punti di divisione della parola nella lingua data si prende il più avanzato per cui la riga, con il
    /// trattino, sta ancora nella larghezza. La riga sillabata è composta a parte, perché il trattino non esiste
    /// nel testo del documento.
    private static func firstFitHyphenation(paragraph: NSAttributedString, start: Int, breakAt: Int, width: CGFloat, defaultLanguage: String?, tracked: Bool)
        -> (line: CTLine, count: Int, string: NSString)? {
        let string = paragraph.string as NSString
        guard breakAt > start, breakAt < string.length else { return nil }
        let letters = CharacterSet.letters.union(CharacterSet(charactersIn: "'\u{2019}"))
        func isLetter(_ index: Int) -> Bool { Unicode.Scalar(string.character(at: index)).map(letters.contains) ?? true }
        // La riga deve finire tra due parole (dopo uno spazio), e la parola seguente deve essere fatta di lettere.
        guard !isLetter(breakAt - 1), isLetter(breakAt) else { return nil }
        var wordEnd = breakAt
        while wordEnd < string.length, isLetter(wordEnd) { wordEnd += 1 }
        guard wordEnd - breakAt >= 5, let language = Hyphenation.language(in: paragraph, at: breakAt, default: defaultLanguage) else { return nil }

        for point in Hyphenation.points(in: string, word: NSRange(location: breakAt, length: wordEnd - breakAt), language: language).reversed() {
            let composed = hyphenatedLine(paragraph: paragraph, start: start, end: point.index, hyphen: point.hyphen, tracked: tracked)
            if CGFloat(CTLineGetTypographicBounds(composed.line, nil, nil, nil)) <= width + 0.01 {
                return (composed.line, point.index - start, composed.string)
            }
        }
        return nil
    }

    /// Allarga o stringe orizzontalmente i font: la matrice scala insieme disegno e avanzamenti, mantenendo coerenti
    /// composizione, cursore e PDF. Le altre caratteristiche del font restano nel suo descrittore.
    private static func expandFonts(in text: NSMutableAttributedString, by expansion: Double) {
        guard abs(expansion) > 1e-9 else { return }
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: all) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let original = font as CTFont
            var matrix = CTFontGetMatrix(original).concatenating(CGAffineTransform(scaleX: CGFloat(1 + expansion), y: 1))
            let expanded = CTFontCreateWithFontDescriptor(CTFontCopyFontDescriptor(original), CTFontGetSize(original), &matrix)
            text.addAttribute(.font, value: expanded, range: range)
        }
    }

    /// Compone a parte una riga che finisce con un trattino di sillabazione, che nel testo del documento non c'è.
    ///
    /// Il trattino lo inseriamo noi, e non deve mai stare più vicino alla lettera di quanto vuole il suo disegno:
    /// davanti a lui si tolgono sia la spaziatura `trak` negativa (con `tracked`) sia l'avvicinamento che il font
    /// prevede per quella coppia (in Hoefler Text, dopo «r» e «t»). Un allontanamento previsto dal font resta.
    static func hyphenatedLine(paragraph: NSAttributedString, start: Int, end: Int, hyphen: String, tracked: Bool,
                               expansion: Double = 0) -> (line: CTLine, string: NSString) {
        let piece = NSMutableAttributedString(attributedString: paragraph.attributedSubstring(from: NSRange(location: start, length: end - start)))
        piece.append(NSAttributedString(string: hyphen, attributes: paragraph.attributes(at: end - 1, effectiveRange: nil)))
        let join = hyphenJoin(paragraph: paragraph, end: end, hyphen: hyphen, tracked: tracked)
        let first = max(join.cluster.location, start) - start
        let last = NSRange(location: first, length: end - start - first)
        if join.gap > 1e-9, last.length > 0 {
            let kern = ((piece.attribute(.kern, at: last.location, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0) + join.gap
            // Un kerning esplicito pari a zero spegnerebbe quello del font: in quel caso l'attributo si toglie.
            if abs(kern) < 1e-9 { piece.removeAttribute(.kern, range: last) } else { piece.addAttribute(.kern, value: kern, range: last) }
        }
        expandFonts(in: piece, by: expansion)
        return (CTLineCreateWithAttributedString(GraphiteLayout.placeholders(piece)), piece.string as NSString)
    }

    /// Come il trattino di sillabazione si attacca al glifo che lo precede.
    struct HyphenJoin {
        /// I caratteri del paragrafo che formano l'ultimo glifo prima del trattino: una lettera, o un'intera
        /// legatura. La spaziatura va cambiata su tutti insieme, altrimenti la legatura si scioglie.
        var cluster: NSRange
        /// L'avvicinamento (negativo) o l'allontanamento (positivo) che il font prevede tra quel glifo e il trattino.
        var fontKerning: Double
        /// Lo spazio da aggiungere tra il glifo e il trattino perché questo torni alla sua distanza naturale.
        var gap: Double
        var hyphenWidth: Double
        /// Di quanto il trattino sporge oltre il margine quando i margini ottici sono attivi.
        var hyphenOverhang: Double
    }

    /// Misura l'attacco del trattino componendo la coda della parola seguita dal trattino.
    static func hyphenJoin(paragraph: NSAttributedString, end: Int, hyphen: String, tracked: Bool) -> HyphenJoin {
        let string = paragraph.string as NSString
        let whitespace = CharacterSet.whitespacesAndNewlines
        // Basta la coda della parola: legature e forme contestuali dipendono dalle lettere vicine.
        var tailStart = end - 1
        while tailStart > 0, end - tailStart < 8, !(Unicode.Scalar(string.character(at: tailStart - 1)).map(whitespace.contains) ?? false) { tailStart -= 1 }
        tailStart = string.rangeOfComposedCharacterSequence(at: tailStart).location
        let attributes = paragraph.attributes(at: end - 1, effectiveRange: nil)
        let tail = NSMutableAttributedString(attributedString: paragraph.attributedSubstring(from: NSRange(location: tailStart, length: end - tailStart)))
        tail.append(NSAttributedString(string: hyphen, attributes: attributes))
        let line = CTLineCreateWithAttributedString(GraphiteLayout.placeholders(tail))

        // L'ultimo glifo prima del trattino, e la larghezza del trattino.
        var previous: (glyph: CGGlyph, font: CTFont, index: Int, advance: Double)?
        var hyphenWidth = 0.0
        var hyphenSeen = false
        var leftToRight = true
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0, let attribute = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { continue }
            if CTRunGetStatus(run).contains(.rightToLeft) { leftToRight = false }
            let all = CFRange(location: 0, length: count)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, all, &glyphs)
            CTRunGetStringIndices(run, all, &indices)
            CTRunGetAdvances(run, all, &advances)
            for position in 0..<count {
                if indices[position] >= end - tailStart {
                    hyphenSeen = true
                    hyphenWidth += Double(advances[position].width)
                } else if !hyphenSeen {
                    previous = (glyphs[position], attribute as! CTFont, indices[position], Double(advances[position].width))
                }
            }
        }

        var cluster = string.rangeOfComposedCharacterSequence(at: end - 1)
        var fontKerning = 0.0
        if leftToRight, let previous {
            var glyph = previous.glyph
            var natural = CGSize.zero
            CTFontGetAdvancesForGlyphs(previous.font, .horizontal, &glyph, &natural, 1)
            let kern = (tail.attribute(.kern, at: previous.index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
            fontKerning = previous.advance - Double(natural.width) - kern
            if abs(fontKerning) < 0.001 { fontKerning = 0 }
            let first = string.rangeOfComposedCharacterSequence(at: tailStart + previous.index).location
            cluster = NSRange(location: first, length: end - first)
        }
        // Nelle scritture indiane un gruppo di consonanti è tenuto insieme dal virama (classe di combinazione 9):
        // non va diviso tra due tratti di testo con attributi diversi.
        while cluster.location > 0, Unicode.Scalar(string.character(at: cluster.location - 1))?.properties.canonicalCombiningClass.rawValue == 9 {
            let first = string.rangeOfComposedCharacterSequence(at: cluster.location - 1).location
            cluster = NSRange(location: first, length: end - first)
        }

        var gap = -min(fontKerning, 0)
        if tracked, let font = attributes[.font] as? NSFont, let tracking = Tracking.normalTracking(for: font as CTFont) { gap -= min(Double(tracking), 0) }
        return HyphenJoin(cluster: cluster, fontKerning: fontKerning, gap: gap, hyphenWidth: hyphenWidth,
                          hyphenOverhang: Double(opticalInsets(of: line, string: tail.string as NSString).right))
    }

    /// Di quanto si allunga, dentro la giustezza, una riga chiusa da un trattino dopo il carattere `end − 1`.
    /// Con `hanging` (margini ottici) conta solo la metà del trattino che resta dentro il margine.
    static func hyphenAdvance(paragraph: NSAttributedString, end: Int, hyphen: String, tracked: Bool, hanging: Bool) -> Double {
        let join = hyphenJoin(paragraph: paragraph, end: end, hyphen: hyphen, tracked: tracked)
        // Lo spazio aggiunto davanti al trattino, e l'eventuale allontanamento voluto dal font, allargano la riga.
        return join.hyphenWidth + join.gap + join.fontKerning - (hanging ? join.hyphenOverhang : 0)
    }

    // MARK: A capo ottimali

    /// Chiave della memoria degli a capo: lo stesso paragrafo, con le stesse larghezze e scelte, dà gli stessi a capo.
    private final class BreakKey: NSObject {
        let paragraph: NSAttributedString
        let firstWidth: CGFloat, restWidth: CGFloat
        let justified: Bool
        let protrusion: LineBreaker.Protrusion
        let composition: LayoutOptions.LineComposition

        init(paragraph: NSAttributedString, firstWidth: CGFloat, restWidth: CGFloat, justified: Bool, protrusion: LineBreaker.Protrusion, options: LayoutOptions) {
            self.paragraph = paragraph
            self.firstWidth = firstWidth; self.restWidth = restWidth
            self.justified = justified
            self.protrusion = protrusion
            composition = options.lineComposition
        }

        override var hash: Int { paragraph.string.hashValue ^ Int(firstWidth * 16) ^ (justified ? 1 : 0) }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? BreakKey else { return false }
            return firstWidth == other.firstWidth && restWidth == other.restWidth && justified == other.justified && protrusion == other.protrusion
                && composition == other.composition && paragraph.isEqual(to: other.paragraph)
        }
    }

    private final class BreakList: NSObject {
        let breaks: [LineBreak]?
        init(_ breaks: [LineBreak]?) { self.breaks = breaks }
    }

    /// Memoria degli a capo, a due generazioni: quando la più recente è piena diventa la vecchia, e quella che era
    /// vecchia si butta. Ciò che viene riletto torna nella recente, quindi resta ciò che serve ancora.
    ///
    /// Non è una `NSCache`: quella può essere svuotata dal sistema in qualsiasi momento, e allora ogni tasto
    /// costerebbe la ricomposizione di tutti i paragrafi.
    private final class TwoGenerationCache<Key: Hashable, Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var recent: [Key: Value] = [:]
        private var old: [Key: Value] = [:]
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func object(forKey key: Key) -> Value? {
            lock.lock()
            defer { lock.unlock() }
            if let found = recent[key] { return found }
            guard let found = old[key] else { return nil }
            store(found, key)
            return found
        }

        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            recent = [:]
            old = [:]
        }

        func setObject(_ value: Value, forKey key: Key) {
            lock.lock()
            defer { lock.unlock() }
            store(value, key)
        }

        private func store(_ value: Value, _ key: Key) {
            if recent.count >= limit {
                old = recent
                recent = [:]
            }
            recent[key] = value
        }
    }

    /// A ogni tasto si ricompone tutto il documento, ma cambia un paragrafo solo: gli altri ritrovano qui i propri a capo.
    private static let breakCache = TwoGenerationCache<BreakKey, BreakList>(limit: 4000)

    /// I bordi su cui i glifi possono sporgere, come li tratta la composizione della riga: nel testo giustificato e
    /// allineato a sinistra entrambi, in quello allineato a destra il destro, in quello centrato nessuno.
    static func protrusion(for alignment: NSTextAlignment, options: LayoutOptions) -> LineBreaker.Protrusion {
        guard options.usesOpticalMargins else { return [] }
        switch alignment {
        case .center: return []
        case .right: return .right
        default: return [.left, .right]
        }
    }

    private static func plannedBreaks(paragraph: NSAttributedString, typesetter: CTTypesetter, firstWidth: CGFloat, restWidth: CGFloat,
                                      justified: Bool, protrusion: LineBreaker.Protrusion, options: LayoutOptions) -> [LineBreak]? {
        let key = BreakKey(paragraph: paragraph, firstWidth: firstWidth, restWidth: restWidth, justified: justified, protrusion: protrusion, options: options)
        if let cached = breakCache.object(forKey: key) { return cached.breaks }
        let breaks = LineBreaker.optimalBreaks(paragraph: paragraph, typesetter: typesetter, firstWidth: firstWidth, restWidth: restWidth,
                                               justified: justified, expansionLimit: options.glyphExpansionLimit,
                                               hyphenates: options.hyphenates, hyphenationLanguage: options.hyphenationLanguage,
                                               tracked: options.appliesFontTracking, hangsHyphens: options.usesOpticalMargins,
                                               protrusion: protrusion)
        breakCache.setObject(BreakList(breaks), forKey: key)
        return breaks
    }

    // MARK: Margini ottici

    /// I rientri ottici dei glifi alle due estremità visibili di una riga: di quanto il bordo ottico sta dentro
    /// (positivo) o fuori (negativo) dalla cassa del glifo. Core Text li ricava da `opbd` o da `lfbd`/`rtbd`.
    static func opticalInsets(of line: CTLine, string: NSString) -> (left: CGFloat, right: CGFloat) {
        var first: (glyph: CGGlyph, font: CTFont)?
        var last: (glyph: CGGlyph, font: CTFont)?
        var lastCharacter: unichar = 0
        let whitespace = CharacterSet.whitespacesAndNewlines
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0, let attribute = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { continue }
            let font = attribute as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            for position in 0..<count {
                let index = indices[position]
                if index < string.length, let scalar = Unicode.Scalar(string.character(at: index)), whitespace.contains(scalar) { continue }
                if first == nil { first = (glyphs[position], font) }
                last = (glyphs[position], font)
                lastCharacter = index < string.length ? string.character(at: index) : 0
            }
        }
        let left = first.map { opticalInset(glyph: $0.glyph, font: $0.font, character: 0, right: false) } ?? 0
        let right = last.map { opticalInset(glyph: $0.glyph, font: $0.font, character: lastCharacter, right: true) } ?? 0
        return (left, right)
    }

    /// Di quanto il bordo ottico di un glifo rientra dalla sua cassa, a sinistra o a destra (alla fine della riga).
    static func opticalInset(glyph: CGGlyph, font: CTFont, character: unichar, right: Bool) -> CGFloat {
        var glyph = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        // Un trattino a fine riga (di sillabazione o scritto) sta a cavallo del margine: metà dentro, metà fuori.
        // È una nostra regola, che per questo glifo prende il posto del valore dichiarato dal font.
        if right, isHangingHyphen(character) {
            var box = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &box, 1)
            return advance.width - box.midX
        }
        var rect = CGRect.zero
        _ = CTFontGetOpticalBoundsForGlyphs(font, &glyph, &rect, 1, 0)
        return right ? advance.width - rect.maxX : rect.minX
    }

    static func isHangingHyphen(_ character: unichar) -> Bool { [0x2D, 0x2010, 0x2011, 0xAD].contains(Int(character)) }

    /// Toglie dal testo ciò che dipende dallo schermo: i colori dinamici di sistema (che in aspetto scuro
    /// darebbero testo bianco su carta bianca) e gli sfondi.
    static func prepared(_ source: NSAttributedString, appliesFontTracking: Bool = true) -> NSAttributedString {
        var counts = (graphite: 0, coreText: 0)
        return prepared(source, appliesFontTracking: appliesFontTracking, documentLanguage: nil, graphite: &counts)
    }

    /// Come sopra, contando i tratti composti con Graphite e quelli che lo chiedevano ma restano a Core Text.
    static func prepared(_ source: NSAttributedString, appliesFontTracking: Bool, documentLanguage: String?,
                         graphite counts: inout (graphite: Int, coreText: Int)) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: source)
        let all = NSRange(location: 0, length: text.length)
        text.removeAttribute(.backgroundColor, range: all)
        text.enumerateAttribute(.foregroundColor, in: all) { value, range, _ in
            guard let color = value as? NSColor else { return }
            if color.type == .catalog {
                text.removeAttribute(.foregroundColor, range: range)
            } else {
                text.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: color.cgColor, range: range)
            }
        }
        // Le immagini nella riga: per Core Text uno spazio delle loro misure.
        text.enumerateAttribute(.inlineImage, in: all) { value, range, _ in
            guard let attachment = value as? ImageAttachment else { return }
            text.addAttributes(InlineImages.layoutAttributes(for: attachment.image), range: range)
        }
        // Il testo alzato o abbassato (apice, pedice): prima della spaziatura `trak`, che dipende dal corpo.
        applyVerticalPositions(in: text)
        // Il testo può arrivare dall'editor con la spaziatura `trak` già dentro: si riparte da zero.
        TextStyling.syncFontTracking(in: text, range: all, enabled: appliesFontTracking)
        text.removeAttribute(.fontTracking, range: all)
        // La lingua del testo a Core Text: quella del tratto o, se non ne ha, quella del documento. Serve alle forme
        // locali dei font OpenType (funzione locl): la jha nepalese in un testo nepalese. Prima la lingua serviva solo a
        // sillabazione e ortografia (trovato il 20 ottobre 2026, preparando il documento su Annapurna SIL).
        let languageKey = NSAttributedString.Key(kCTLanguageAttributeName as String)
        text.enumerateAttribute(.language, in: all) { value, range, _ in
            if let language = (value as? String) ?? documentLanguage, !language.isEmpty { text.addAttribute(languageKey, value: language, range: range) }
        }
        applyAutomaticOpticalSizes(in: text, range: all)
        // Il testo che chiede Graphite: per Core Text, spazi delle misure dei gruppi di Graphite.
        counts = GraphiteLayout.apply(in: text)
        return text
    }

    /// Nei font con l'asse `opsz` non fissato la dimensione ottica segue il corpo: lo si chiede a Core Text qui, dove il
    /// testo dell'editor diventa testo da comporre, così valgono lo schermo, il PDF e la scelta degli a capo.
    static func applyAutomaticOpticalSizes(in text: NSMutableAttributedString, range: NSRange) {
        var converted: [NSFont: NSFont] = [:]
        var changes: [(NSRange, NSFont)] = []
        text.enumerateAttribute(.font, in: range) { value, piece, _ in
            guard let font = value as? NSFont else { return }
            let automatic = converted[font] ?? (FontVariations.withAutomaticOpticalSize(font as CTFont) as NSFont)
            converted[font] = automatic
            if automatic !== font { changes.append((piece, automatic)) }
        }
        for (piece, font) in changes { text.addAttribute(.font, value: font, range: piece) }
    }

    /// Il testo alzato o abbassato. Con i glifi del font, se il font ha la funzione (AAT «Vertical Position», OpenType
    /// `sups` o `subs`/`sinf`) e se cambia davvero il glifo di ogni carattere del tratto; altrimenti il testo
    /// rimpicciolito e spostato, senza uscire dall'altezza e dalla profondità delle lettere, così la riga non cambia
    /// altezza (come per i richiami di nota).
    static func applyVerticalPositions(in text: NSMutableAttributedString) {
        let all = NSRange(location: 0, length: text.length)
        var pieces: [(range: NSRange, position: VerticalPosition, font: CTFont)] = []
        text.enumerateAttribute(.verticalPosition, in: all) { value, range, _ in
            guard let encoded = value as? String, let position = VerticalPosition(encoded: encoded) else { return }
            text.enumerateAttribute(.font, in: range) { font, piece, _ in
                if let font = font as? NSFont { pieces.append((piece, position, font as CTFont)) }
            }
        }
        let string = text.string as NSString
        for piece in pieces {
            let characters = string.substring(with: piece.range).filter { !$0.isWhitespace }
            if piece.position.usesFontGlyphs, let variant = fontGlyphVariant(of: piece.font, raised: piece.position.isRaised, for: characters) {
                text.addAttribute(.font, value: variant, range: piece.range)
                continue
            }
            let size = CTFontGetSize(piece.font)
            let small = TextStyling.resized(piece.font, to: size * CGFloat(piece.position.scale))
            let wanted = size * CGFloat(piece.position.shift)
            let offset = wanted > 0 ? min(wanted, max(CTFontGetAscent(piece.font) - CTFontGetAscent(small), 0))
                                    : max(wanted, -max(CTFontGetDescent(piece.font) - CTFontGetDescent(small), 0))
            text.addAttribute(.font, value: small, range: piece.range)
            text.addAttribute(NSAttributedString.Key(kCTBaselineOffsetAttributeName as String), value: offset, range: piece.range)
        }
    }

    /// La faccia con i glifi in apice (o in pedice) accesi, se cambia il glifo di ogni carattere dato e lo mette davvero più
    /// in alto (o più in basso): non tutti i font sono affidabili (Iowan Old Style dà per gli inferiori scientifici lo
    /// stesso glifo dell'apice).
    private static func fontGlyphVariant(of font: CTFont, raised: Bool, for characters: String) -> CTFont? {
        guard !characters.isEmpty else { return nil }
        let current = FontFeatures.settings(of: font)
        let aat: FeatureSetting = .aat(type: 10, selector: raised ? 1 : 2)
        let tags: Set<String> = raised ? ["sups"] : ["subs", "sinf"]
        for type in FontFeatures.types(of: font) {
            for selector in type.selectors where selector.setting == aat || selector.openTypeTag.map(tags.contains) == true {
                let settings = type.isExclusive ? type.selecting(selector, in: current) : type.setting(selector, on: true, in: current)
                let candidate = FontFeatures.font(font, with: settings)
                if characters.allSatisfy({ isMoved(String($0), from: font, to: candidate, raised: raised) }) { return candidate }
            }
        }
        return nil
    }

    /// Vero se il carattere, con la funzione accesa, ha un altro glifo, il cui centro sta più in alto (o più in basso).
    private static func isMoved(_ character: String, from font: CTFont, to candidate: CTFont, raised: Bool) -> Bool {
        let before = Shaper.glyphIDs(for: character, font: font), after = Shaper.glyphIDs(for: character, font: candidate)
        guard before != after, let original = before.first, let moved = after.first else { return false }
        var boxes = [CGRect](repeating: .zero, count: 2)
        CTFontGetBoundingRectsForGlyphs(font, .default, [CGGlyph(original)], &boxes, 1)
        CTFontGetBoundingRectsForGlyphs(candidate, .default, [CGGlyph(moved)], &boxes[1], 1)
        // Un segno senza altezza (uno spazio, un trattino) basta che cambi.
        if boxes[0].height == 0 || boxes[1].height == 0 { return true }
        return raised ? boxes[1].midY > boxes[0].midY : boxes[1].midY < boxes[0].midY
    }

    private static func kernAfterLastVisibleCharacter(of text: NSAttributedString, in range: NSRange) -> CGFloat {
        let string = text.string as NSString
        var index = NSMaxRange(range) - 1
        while index >= range.location, let scalar = Unicode.Scalar(string.character(at: index)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { index -= 1 }
        guard index >= range.location else { return 0 }
        return CGFloat((text.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0)
    }
}
