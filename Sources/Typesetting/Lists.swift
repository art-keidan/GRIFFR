import AppKit

/// L'appartenenza di un paragrafo a un elenco.
///
/// Il numero di una voce non è scritto da nessuna parte: si calcola componendo la pagina, come per le note.
public struct ListItem: Hashable, Sendable {
    /// Il segno davanti alla voce. Può essere un simbolo qualsiasi («•», «–», «→») oppure un modello di
    /// numerazione: un contatore («1», «a», «A», «i», «I») con la punteggiatura che lo accompagna, come «1.»,
    /// «a)», «(i)».
    public var marker: String
    /// Livello di annidamento, da 1 (il più esterno) a `maximumLevel`.
    public var level: Int
    /// La Lista con un nome a cui la voce appartiene. Se c'è, segno e numero vengono da lei, e `marker` non conta.
    public var listName: String?
    /// Misure proprie della voce, in punti dal rientro sinistro del paragrafo (`nil`: quelle della Lista, o i valori
    /// iniziali): dove comincia il testo, e dove finisce il segno (i segni si allineano a destra su questa posizione, così
    /// «(9)» e «(10)» restano allineati sulla parentesi).
    public var textIndent: Double?
    public var markerPosition: Double?
    /// Vero se questo paragrafo è un altro capoverso della voce precedente, e non una voce nuova: non ha segno, non
    /// consuma un numero, e prende dal paragrafo che apre la voce i rientri. Vale per una voce di più capoversi, che
    /// ha un solo segno sul primo. Il segno e il livello servono solo a riconoscere la voce che continua.
    public var continuesPreviousItem: Bool
    /// Il numero da cui comincia un nuovo tratto della stessa Lista: è la ripartenza scelta dall'autore («riparte
    /// da 1»), e vale per il capoverso che apre il tratto e per le voci che lo seguono. `nil`: il tratto continua
    /// quello prima, con la politica ordinaria della Lista. Non convive con `sequenceResume`.
    public var sequenceStart: Int? = nil
    /// L'identità del capoverso che apre il tratto della stessa Lista che questo capoverso riprende («prosegue
    /// l'elenco che comincia con…»). Il tratto ripreso è lo stesso: si continua la numerazione da dove era arrivato,
    /// e le voci dopo restano sue. `nil`: nessuna ripresa. Non convive con `sequenceStart`.
    public var sequenceResume: UUID? = nil

    public static let maximumLevel = 9
    /// I valori iniziali delle misure: di quanto rientra ogni livello, e lo spazio fra segno e testo.
    public static let indentStep = 24.0
    public static let defaultMarkerGap = 6.0
    /// Lo spazio minimo fra un segno che arriva oltre l'inizio del testo e la prima riga.
    public static let minimumMarkerSpace = 6.0

    public init(marker: String, level: Int = 1, continuesPreviousItem: Bool = false) {
        self.marker = marker
        self.level = min(max(level, 1), Self.maximumLevel)
        self.continuesPreviousItem = continuesPreviousItem
    }

    /// Una voce di una Lista con un nome.
    public init(listName: String, continuesPreviousItem: Bool = false) {
        self.marker = ""
        self.level = 1
        self.listName = listName
        self.continuesPreviousItem = continuesPreviousItem
    }

    /// Come si scrive il contatore di un elenco numerato.
    public enum Counter: Character, Sendable, CaseIterable {
        case decimal = "1", lowerLetter = "a", upperLetter = "A", lowerRoman = "i", upperRoman = "I"

        public func text(for number: Int) -> String {
            switch self {
            case .decimal: return String(number)
            case .lowerLetter: return Self.letters(number)
            case .upperLetter: return Self.letters(number).uppercased()
            case .lowerRoman: return Self.roman(number)
            case .upperRoman: return Self.roman(number).uppercased()
            }
        }

        /// a, b, … z, aa, ab, …
        private static func letters(_ number: Int) -> String {
            var value = max(number, 1), result = ""
            while value > 0 {
                value -= 1
                result = String(UnicodeScalar(UInt8(97 + value % 26))) + result
                value /= 26
            }
            return result
        }

        private static func roman(_ number: Int) -> String {
            guard number > 0, number < 4000 else { return String(number) }
            var value = number, result = ""
            for (amount, symbol) in [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")] {
                while value >= amount {
                    result += symbol
                    value -= amount
                }
            }
            return result
        }
    }

    /// Le parti di un modello di numerazione, oppure `nil` se il segno è un simbolo fisso. È un modello di
    /// numerazione il segno che contiene una sola lettera o cifra, e questa è uno dei cinque contatori.
    public var numbering: (prefix: String, counter: Counter, suffix: String)? {
        let characters = Array(marker)
        let alphanumeric = characters.indices.filter { characters[$0].isLetter || characters[$0].isNumber }
        guard alphanumeric.count == 1, let position = alphanumeric.first, let counter = Counter(rawValue: characters[position]) else { return nil }
        return (String(characters[..<position]), counter, String(characters[(position + 1)...]))
    }

    public var isNumbered: Bool { numbering != nil }

    /// Le misure con cui si compone la voce, in punti: le sue, poi quelle della sua Lista, poi i valori iniziali (il
    /// livello di una voce di Lista è la profondità della Lista).
    public func resolvedMeasures(in lists: [ListDefinition]) -> (textIndent: Double, markerPosition: Double) {
        let definition = listName.flatMap { name in lists.first { $0.name == name } }
        let level = listName.map { ListNumberer(definitions: lists).depth(of: $0) + 1 } ?? self.level
        let text = textIndent ?? definition?.textIndent ?? Double(level) * Self.indentStep
        // Senza una posizione propria il segno finisce 6 pt prima del testo del suo livello.
        let marker = markerPosition ?? definition?.markerPosition ?? (Double(level) * Self.indentStep - Self.defaultMarkerGap)
        return (text, marker)
    }

    /// Il segno da comporre davanti a una voce che, nel suo elenco, è la numero `number`.
    public func text(number: Int) -> String {
        guard let numbering else { return marker }
        return numbering.prefix + numbering.counter.text(for: number) + numbering.suffix
    }

    /// Vero se questa voce e `other` sono la stessa voce: la stessa Lista con un nome, oppure, per un elenco senza
    /// nome, lo stesso segno allo stesso livello. Serve a sapere se un paragrafo può continuare la voce prima.
    public func belongsToSameItem(as other: ListItem) -> Bool {
        if let name = listName { return other.listName == name }
        return other.listName == nil && other.marker == marker && other.level == level
    }

    /// Il valore dell'attributo di testo: una stringa («livello segno», o «@Lista»), che copia e incolla conservano. Le
    /// misure proprie, se ci sono, seguono dopo una tabulazione («rientro distanza», «-» per quella che manca). Dopo le
    /// misure vengono i segni del tratto: «c» se il paragrafo continua la voce precedente, «s» con il numero se apre una
    /// ripartenza, «r» con l'identità se riprende un tratto.
    public var encoded: String {
        let base = listName.map { "@" + $0 } ?? "\(level) \(marker)"
        guard textIndent != nil || markerPosition != nil || continuesPreviousItem || sequenceStart != nil || sequenceResume != nil else { return base }
        func number(_ value: Double?) -> String { value.map { String(format: "%g", $0) } ?? "-" }
        var value = base + "\t" + number(textIndent) + " " + number(markerPosition)
        // Una continuazione non apre né riprende un tratto: le due scelte non convivono.
        if continuesPreviousItem {
            value += " c"
        } else {
            if let start = sequenceStart { value += " s\(start)" }
            if let resume = sequenceResume { value += " r\(resume.uuidString)" }
        }
        return value
    }

    public init?(encoded: String) {
        if let tab = encoded.firstIndex(of: "\t") {
            guard var item = ListItem(encoded: String(encoded[..<tab])) else { return nil }
            let measures = encoded[encoded.index(after: tab)...].split(separator: " ")
            // Le due misure, poi i segni del tratto: un capoverso non può insieme continuare la voce e aprire o
            // riprendere un tratto.
            guard measures.count >= 2 else { return nil }
            item.textIndent = measures[0] == "-" ? nil : Double(measures[0])
            item.markerPosition = measures[1] == "-" ? nil : Double(measures[1])
            var continuation = false, start: Int?, resume: UUID?
            for token in measures.dropFirst(2) {
                if token == "c" {
                    guard !continuation else { return nil }
                    continuation = true
                } else if token.hasPrefix("s"), let number = Int(token.dropFirst()), number >= 1 {
                    guard start == nil else { return nil }
                    start = number
                } else if token.hasPrefix("r"), let identity = UUID(uuidString: String(token.dropFirst())) {
                    guard resume == nil else { return nil }
                    resume = identity
                } else {
                    return nil
                }
            }
            guard !(continuation && (start != nil || resume != nil)), !(start != nil && resume != nil) else { return nil }
            item.continuesPreviousItem = continuation
            item.sequenceStart = start
            item.sequenceResume = resume
            self = item
            return
        }
        if encoded.hasPrefix("@") {
            let name = String(encoded.dropFirst())
            guard !name.isEmpty else { return nil }
            self.init(listName: name)
            return
        }
        guard let space = encoded.firstIndex(of: " "), let level = Int(encoded[..<space]) else { return nil }
        let marker = String(encoded[encoded.index(after: space)...])
        guard !marker.isEmpty else { return nil }
        self.init(marker: marker, level: level)
    }
}

/// Conta le voci degli elenchi mentre si scorrono i paragrafi nell'ordine del documento.
///
/// Una voce continua la numerazione della precedente dello stesso livello se ha lo stesso segno e se in mezzo ci
/// sono solo voci più interne. Un paragrafo che non è una voce, o un segno diverso allo stesso livello, fa
/// ripartire da uno.
public struct ListNumbering {
    private var counters: [Int: (marker: String, count: Int)] = [:]

    public init() {}

    /// Il segno da comporre davanti al prossimo paragrafo, o `nil` se non è una voce di elenco.
    public mutating func next(_ item: ListItem?) -> String? {
        guard let item else {
            counters = [:]
            return nil
        }
        for level in counters.keys where level > item.level { counters[level] = nil }
        if let current = counters[item.level], current.marker == item.marker {
            counters[item.level] = (item.marker, current.count + 1)
        } else {
            counters[item.level] = (item.marker, 1)
        }
        return item.text(number: counters[item.level]!.count)
    }
}

// MARK: - Liste con un nome

/// Una Lista: la definizione di una numerazione, a cui rimandano voci di elenco, esempi e note.
///
/// È una definizione come uno stile: il testo vi rimanda per nome, e cambiandola cambiano tutti i numeri.
public struct ListDefinition: Hashable, Sendable {
    public var name: String
    /// Come si scrive il numero.
    public var counter: ListCounter
    /// Ciò che sta prima e dopo il numero: «(» e «)» in «(1)». Per una lista senza numero è il segno stesso («•»).
    public var prefix: String
    public var suffix: String
    public var start: Int
    /// L'ultimo valore: per le serie finite, se `nil`, quello della serie (3 asterischi, 6 segni); per le altre
    /// un limite facoltativo.
    public var end: Int?
    /// La lista superiore: questa riparte a ogni suo passo.
    public var parent: ListParent?
    /// Se la numerazione prosegue dopo un paragrafo che non fa parte della lista (gli esempi di un articolo),
    /// o se riparte (un elenco comune).
    public var continues: Bool
    /// Se davanti al proprio numero si scrive quello della lista superiore («1.2», «3a»).
    public var showsParent: Bool
    /// Che cosa fare oltre l'ultimo valore. Finché non è deciso, il programma lo chiede.
    public var overflow: ListOverflow
    /// Le misure delle voci, in punti dal rientro sinistro del paragrafo (`nil`: i valori iniziali, il testo a 24 pt per
    /// livello e il segno che finisce 6 pt prima): dove comincia il testo, e dove finisce il segno.
    public var textIndent: Double?
    public var markerPosition: Double?
    /// Il ruolo delle sezioni che questa Lista numera («Capitoli» numera i capitoli): ogni titolo di quel ruolo è un suo
    /// elemento, con il numero davanti, e le altre liste possono ripartire a ogni suo passo e scriverne il numero.
    public var numbersSections: String?

    public init(name: String, counter: ListCounter, prefix: String = "", suffix: String = "", start: Int = 1, end: Int? = nil,
                parent: ListParent? = nil, continues: Bool = false, showsParent: Bool = false, overflow: ListOverflow = .ask,
                numbersSections: String? = nil) {
        self.numbersSections = numbersSections
        self.name = name
        self.counter = counter
        self.prefix = prefix
        self.suffix = suffix
        self.start = start
        self.end = end
        self.parent = parent
        self.continues = continues
        self.showsParent = showsParent
        self.overflow = overflow
    }

    /// L'ultimo valore prima di andare oltre, se c'è.
    public var lastValue: Int? { end ?? counter.seriesLength }

    /// La Lista delle figure: «Figura 1.», «Figura 2.»…
    public static let figures = ListDefinition(name: "Figures", counter: .decimal, prefix: "Figure ", suffix: ".", continues: true)

    /// La Lista delle tabelle flottanti: «Tabella 1.», «Tabella 2.»…
    public static let tables = ListDefinition(name: "Tables", counter: .decimal, prefix: "Table ", suffix: ".", continues: true)

    /// Le Liste con cui nasce un documento nuovo.
    public static let builtIn: [ListDefinition] = [
        ListDefinition(name: "Numbered List", counter: .decimal, suffix: "."),
        ListDefinition(name: "Examples", counter: .decimal, prefix: "(", suffix: ")", continues: true),
        ListDefinition(name: "Subexamples", counter: .lowerLetter, suffix: ".", parent: .list("Examples"), continues: true),
        ListDefinition(name: "Notes", counter: .decimal, continues: true),
        ListDefinition(name: "Symbol Notes", counter: .symbols, parent: .page, continues: true),
    ]
}

/// Come si scrive il numero di una Lista.
public enum ListCounter: String, Hashable, Sendable, CaseIterable {
    case decimal = "1", lowerLetter = "a", upperLetter = "A", lowerRoman = "i", upperRoman = "I"
    /// *, **, ***: una serie finita.
    case asterisks = "*"
    /// *, †, ‡, §, ‖, ¶: la serie dei segni tipografici, finita.
    case symbols = "†"
    /// Nessun numero: la lista mostra solo prefisso e suffisso (un segno come «•»).
    case none

    static let symbolSeries = ["*", "\u{2020}", "\u{2021}", "\u{00A7}", "\u{2016}", "\u{00B6}"]

    /// La lunghezza delle serie finite.
    public var seriesLength: Int? {
        switch self {
        case .asterisks: 3
        case .symbols: Self.symbolSeries.count
        default: nil
        }
    }

    /// Il numero `value` scritto con questo contatore (`value` da 1).
    public func text(for value: Int) -> String {
        let value = max(value, 1)
        switch self {
        case .decimal: return String(value)
        case .lowerLetter: return ListItem.Counter.lowerLetter.text(for: value)
        case .upperLetter: return ListItem.Counter.upperLetter.text(for: value)
        case .lowerRoman: return ListItem.Counter.lowerRoman.text(for: value)
        case .upperRoman: return ListItem.Counter.upperRoman.text(for: value)
        case .asterisks: return String(repeating: "*", count: value)
        case .symbols:
            let series = Self.symbolSeries
            return String(repeating: series[(value - 1) % series.count], count: (value - 1) / series.count + 1)
        case .none: return ""
        }
    }
}

public enum ListParent: Hashable, Sendable {
    /// Riparte a ogni passo di un'altra lista.
    case list(String)
    /// Riparte a ogni pagina.
    case page
    /// Riparte a ogni sezione di un ruolo (gli esempi a ogni capitolo).
    case section(String)
}

/// Che cosa fa una Lista oltre il suo ultimo valore.
public enum ListOverflow: String, Hashable, Sendable, CaseIterable {
    /// Non ancora deciso: il programma lo chiede alla prima occorrenza.
    case ask
    /// Ricomincia dal primo valore.
    case restart
    /// Raddoppia i simboli (per le serie finite): **, ††…
    case double
    /// Passa ai numeri.
    case numbers
}

/// Un tratto di numerazione di una Lista: il capoverso che lo apre, la sua prima voce e dove è arrivato. Un autore
/// può chiuderlo con una ripartenza e riprenderlo da un altro punto del documento.
public struct ListSequence: Hashable, Sendable {
    /// L'identità del tratto: quella del capoverso che lo apre.
    public var identity: UUID
    public var listName: String
    /// La posizione nel testo del capoverso che apre il tratto.
    public var start: Int
    public var firstNumber: Int
    public var lastNumber: Int
    /// Quante voci ha il tratto fin qui (compreso il capoverso finale vuoto, se ne mostra il numero).
    public var items: Int

    public init(identity: UUID, listName: String, start: Int, firstNumber: Int, lastNumber: Int, items: Int) {
        self.identity = identity
        self.listName = listName
        self.start = start
        self.firstNumber = firstNumber
        self.lastNumber = lastNumber
        self.items = items
    }
}

/// Un problema di una voce o di un tratto di Lista, da mostrare all'autore: il capoverso che lo mostra.
///
/// Non è un errore di lettura: il documento si compone lo stesso (la voce riparte), ma il silenzio nasconderebbe
/// una scelta rimasta senza effetto.
public struct ListWarning: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Un capoverso che continua la voce precedente, ma la voce non c'è (cancellata, o dopo un altro paragrafo).
        case continuationWithoutItem
        /// Un capoverso che riprende un tratto che non c'è (cancellato, o di un'altra Lista).
        case resumeWithoutSequence
    }
    public var kind: Kind
    /// La posizione nel testo del capoverso.
    public var paragraph: Int
    /// La Lista del capoverso; per un elenco senza nome, il suo segno.
    public var list: String

    public init(kind: Kind, paragraph: Int, list: String) {
        self.kind = kind
        self.paragraph = paragraph
        self.list = list
    }
}

/// Il segno del prossimo elemento di una Lista, con il tratto a cui appartiene.
public struct ListAdvance: Equatable, Sendable {
    public var mark: ListMark
    /// L'identità del tratto: quella del capoverso che lo apre.
    public var segment: UUID
    /// Vero se questo elemento apre il tratto (primo elemento, ripartenza, o ripresa che non trova il tratto).
    public var isNewSegment: Bool
}

/// Il segno calcolato per un elemento di una Lista.
public struct ListMark: Equatable, Sendable {
    public var text: String
    /// Vero se l'elemento va oltre l'ultimo valore della lista e la scelta su che cosa fare non è ancora stata fatta:
    /// il segno è provvisorio (un numero).
    public var needsOverflowChoice: Bool
    /// Il numero nella lista (da `start`).
    public var value: Int
}

/// Conta gli elementi delle Liste con un nome mentre si scorre il documento nell'ordine.
///
/// I numeri appartengono a un *tratto* della Lista: quello che comincia con la sua prima voce e continua finché la
/// politica della Lista lo lascia continuare. Un tratto ha un'identità — l'identità del capoverso che lo apre — e
/// un autore può chiuderlo e aprirne un altro (ripartenza) o riprendere quello di prima (ripresa) da qualsiasi punto.
/// Senza scelte dell'autore i tratti sono impliciti e si ricostruiscono a ogni composizione, come prima.
public struct ListNumberer {
    private let definitions: [String: ListDefinition]
    /// L'ultimo numero di ogni tratto, per identità del tratto.
    private var counts: [UUID: Int] = [:]
    /// Il tratto in corso di ogni Lista: le sue voci senza scelte proprie continuano questo.
    private var current: [String: UUID] = [:]
    /// A quale Lista appartiene ogni tratto.
    private var segmentList: [UUID: String] = [:]
    /// L'ultimo numero assegnato in ogni Lista: serve al numero della Lista superiore da scrivere davanti.
    private var lastValue: [String: Int] = [:]
    /// Per ogni lista, il passo della sua lista superiore (o la pagina) al momento dell'ultimo elemento.
    private var parentSteps: [String: Int] = [:]
    /// Ogni passo di ogni lista ha un numero d'ordine unico: così una lista inferiore riconosce un passo nuovo
    /// della superiore anche quando questa, ripartendo, ritorna allo stesso numero.
    private var lastStep: [String: Int] = [:]
    private var serial = 0
    private var page = 1
    /// Per ogni ruolo, il numero d'ordine dell'ultima sezione di quel ruolo che si è incontrata.
    private var sectionSteps: [String: Int] = [:]

    public init(definitions: [ListDefinition]) {
        var map: [String: ListDefinition] = [:]
        for definition in definitions { map[definition.name] = definition }
        self.definitions = map
    }

    /// Si passa alla pagina `number`.
    public mutating func setPage(_ number: Int) { page = number }

    /// Comincia una sezione di quel ruolo: le liste che ripartono a ogni sua sezione ripartono.
    public mutating func passSection(role: String) {
        serial += 1
        sectionSteps[role] = serial
    }

    /// La Lista che numera le sezioni di un ruolo, se c'è.
    public func list(numbering role: String) -> String? {
        definitions.values.filter { $0.numbersSections == role }.map(\.name).min()
    }

    /// Un paragrafo che non appartiene a nessuna Lista: le liste che non proseguono chiudono il loro tratto, e la
    /// voce dopo riparte dalla definizione. Il numero del tratto chiuso resta noto: una ripresa esplicita può
    /// continuarlo anche dopo l'interruzione.
    public mutating func interrupt() {
        for (name, definition) in definitions where !definition.continues { closeSegment(of: name) }
    }

    /// Le liste da cui una lista discende (la sua superiore, la superiore di quella…).
    private func ancestors(of name: String) -> Set<String> {
        var result: Set<String> = []
        var next = definitions[name]?.parent
        while case .list(let parent)? = next, !result.contains(parent) {
            result.insert(parent)
            next = definitions[parent]?.parent
        }
        return result
    }

    /// Quanti livelli ha sopra di sé una lista (0 per una lista senza superiore): serve al rientro.
    public func depth(of name: String) -> Int { ancestors(of: name).count }

    /// Il segno del prossimo elemento della lista. `nil` se la lista non esiste.
    public mutating func next(_ name: String, id: UUID? = nil, start: Int? = nil, resume: UUID? = nil) -> ListMark? {
        advance(name, id: id, start: start, resume: resume)?.mark
    }

    /// Il segno del prossimo elemento e il tratto a cui appartiene.
    ///
    /// `id` è l'identità del capoverso: apre un tratto nuovo quando non c'è ancora, e dà al tratto la sua identità.
    /// `start` apre un tratto nuovo da quel numero (la ripartenza); `resume` riprende il tratto che ha quell'identità,
    /// continuandone il numero. Le due scelte non convivono.
    public mutating func advance(_ name: String, id: UUID? = nil, start: Int? = nil, resume: UUID? = nil) -> ListAdvance? {
        guard let definition = definitions[name] else { return nil }
        // Un elemento di questa lista interrompe le liste che non proseguono, tranne le sue superiori.
        let keep = ancestors(of: name).union([name])
        for (other, otherDefinition) in definitions where !otherDefinition.continues && !keep.contains(other) {
            // Le liste che discendono da questa ripartono comunque al prossimo passo; le altre si interrompono.
            if !ancestors(of: other).contains(name) { closeSegment(of: other) }
        }
        let step: Int = switch definition.parent {
        case .list(let parent)?: lastStep[parent] ?? 0
        case .page?: page
        case .section(let role)?: sectionSteps[role] ?? 0
        case nil: 0
        }
        // Un nuovo passo della lista superiore chiude il tratto: la numerazione riparte dalla definizione. Il
        // numero del tratto resta noto per una ripresa esplicita.
        if parentSteps[name] != step { closeSegment(of: name) }
        parentSteps[name] = step
        let segment: UUID
        let value: Int
        var isNew = false
        if let resume {
            if let resumed = counts[resume], segmentList[resume] == name {
                // La ripresa continua il tratto ripreso: le voci dopo restano sue.
                segment = resume
                value = resumed + 1
            } else {
                // La ripresa non trova il tratto (capoverso cancellato, Lista diversa, numero già chiuso): la voce
                // riparte dalla definizione invece di continuare il tratto in corso, che non ha scelto.
                segment = id ?? UUID()
                value = max(definition.start, 1)
                isNew = true
            }
        } else if let start {
            segment = id ?? UUID()
            value = max(start, 1)
            isNew = true
        } else if let together = current[name], let count = counts[together] {
            segment = together
            value = count + 1
        } else {
            segment = id ?? UUID()
            value = max(definition.start, 1)
            isNew = true
        }
        counts[segment] = value
        segmentList[segment] = name
        current[name] = segment
        lastValue[name] = value
        serial += 1
        lastStep[name] = serial
        return ListAdvance(mark: mark(value, of: definition), segment: segment, isNewSegment: isNew)
    }

    /// Chiude il tratto in corso di una Lista, senza dimenticarne il numero: le voci che vengono dopo aprono un
    /// tratto nuovo dalla definizione, oppure riprendono un tratto con una scelta esplicita.
    private mutating func closeSegment(of name: String) {
        current[name] = nil
    }

    /// I primi segni di una lista, per mostrarla: «(1) (2) (3)». Se la lista ha una superiore, come dopo il suo primo passo.
    public static func sample(of name: String, in definitions: [ListDefinition], count: Int = 3) -> [String] {
        var numberer = ListNumberer(definitions: definitions)
        numberer.setPage(1)
        if case .list(let parent)? = numberer.definitions[name]?.parent { _ = numberer.next(parent) }
        return (0..<count).compactMap { _ in numberer.next(name)?.text }
    }

    private func mark(_ value: Int, of definition: ListDefinition) -> ListMark {
        var shown = value
        var counter = definition.counter
        var needsChoice = false
        if let last = definition.lastValue, value > last {
            switch definition.overflow {
            case .ask:
                needsChoice = true
                counter = .decimal
            case .restart:
                shown = (value - 1) % last + 1
            case .double:
                break  // il contatore delle serie finite raddoppia da sé i simboli; gli altri proseguono
            case .numbers:
                counter = .decimal
            }
        }
        var text = definition.prefix + counter.text(for: shown) + definition.suffix
        if counter == .none { text = definition.prefix + definition.suffix }
        // Il numero della Lista superiore vale solo se il suo tratto è ancora aperto: dopo un'interruzione non c'è.
        if definition.showsParent, case .list(let parent)? = definition.parent, current[parent] != nil,
           let parentDefinition = definitions[parent], let parentValue = lastValue[parent] {
            text = parentDefinition.counter.text(for: parentValue) + text
        }
        // Con una sezione per superiore, il numero davanti è quello della sezione, se una Lista numera quel ruolo.
        if definition.showsParent, case .section(let role)? = definition.parent, let numbering = list(numbering: role),
           current[numbering] != nil, let parentDefinition = definitions[numbering], let parentValue = lastValue[numbering] {
            text = parentDefinition.counter.text(for: parentValue) + text
        }
        return ListMark(text: text, needsOverflowChoice: needsChoice, value: value)
    }
}

extension NSAttributedString.Key {
    /// Segna i caratteri di un paragrafo che è una voce di elenco. Il valore è `ListItem.encoded`, uguale su tutto
    /// il paragrafo, a capo finale compreso.
    public static let listItem = NSAttributedString.Key("WordProcessorListItem")

    /// Sull'ultimo a capo del testo: l'elenco del paragrafo vuoto che lo segue, quando è diverso da quello del
    /// paragrafo che l'a capo chiude. Quel paragrafo non ha caratteri propri a cui attaccare un attributo.
    /// Il valore è `ListItem.encoded`, oppure una stringa vuota per «nessun elenco».
    public static let finalParagraphList = NSAttributedString.Key("WordProcessorFinalParagraphList")
}

// MARK: - Elenchi nel testo

extension TextStyling {
    /// Vero se dopo l'ultimo carattere c'è un paragrafo vuoto: il testo è vuoto, o finisce con un a capo del corpo.
    public static func hasEmptyFinalParagraph(_ text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return true }
        let last = text.length - 1
        return isLineTerminator((text.string as NSString).character(at: last)) && text.attribute(.footnote, at: last, effectiveRange: nil) == nil
    }

    /// L'elenco del paragrafo vuoto in fondo al testo: quello dichiarato sull'ultimo a capo, altrimenti lo stesso
    /// del paragrafo precedente (andando a capo in fondo a un elenco, la voce nuova ne fa parte).
    public static func finalParagraphListItem(in text: NSAttributedString) -> ListItem? {
        guard text.length > 0 else { return nil }
        let last = text.length - 1
        if let declared = text.attribute(.finalParagraphList, at: last, effectiveRange: nil) as? String { return ListItem(encoded: declared) }
        return (text.attribute(.listItem, at: last, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
    }

    /// L'elenco a cui appartiene il paragrafo che contiene una posizione.
    public static func listItem(in text: NSAttributedString, at index: Int) -> ListItem? {
        if index >= text.length { return hasEmptyFinalParagraph(text) ? finalParagraphListItem(in: text) : listItem(in: text, at: text.length - 1) }
        let start = bodyParagraph(in: text, at: index).range.location
        return (text.attribute(.listItem, at: start, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
    }

    /// I caratteri i cui attributi cambiano quando si modifica l'elenco dei paragrafi toccati da un intervallo:
    /// quei paragrafi per intero e, se è toccato il paragrafo vuoto finale, l'ultimo a capo.
    public static func listEditRange(in text: NSAttributedString, for range: NSRange) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        if range.location >= text.length, hasEmptyFinalParagraph(text) { return NSRange(location: text.length - 1, length: 1) }
        let first = bodyParagraph(in: text, at: min(range.location, text.length - 1)).range
        // Una selezione che finisce all'inizio di un paragrafo non lo comprende.
        let lastIndex = range.length > 0 ? NSMaxRange(range) - 1 : range.location
        let last = bodyParagraph(in: text, at: min(lastIndex, text.length - 1)).range
        return NSUnionRange(first, last)
    }

    /// Cambia l'elenco dei paragrafi toccati da un intervallo: a ciascuno si applica `transform`.
    public static func setList(in text: NSMutableAttributedString, range: NSRange, _ transform: (ListItem?) -> ListItem?) {
        guard text.length > 0 else { return }
        let touchesFinal = NSMaxRange(range) >= text.length && hasEmptyFinalParagraph(text)
        // Va letto prima: cambiando il paragrafo precedente cambierebbe anche ciò che il paragrafo finale eredita.
        let finalItem = touchesFinal ? transform(finalParagraphListItem(in: text)) : nil
        // Il cursore dopo l'ultimo carattere, senza un a capo finale, sta ancora nell'ultimo paragrafo.
        let start = range.location < text.length ? range.location : (touchesFinal ? nil : text.length - 1)
        if let start {
            let affected = listEditRange(in: text, for: NSRange(location: start, length: min(range.length, text.length - start)))
            var location = affected.location
            while location < NSMaxRange(affected) {
                let paragraph = bodyParagraph(in: text, at: location).range
                let current = (text.attribute(.listItem, at: paragraph.location, effectiveRange: nil) as? String).flatMap(ListItem.init(encoded:))
                if let updated = transform(current) {
                    text.addAttribute(.listItem, value: updated.encoded, range: paragraph)
                } else {
                    text.removeAttribute(.listItem, range: paragraph)
                }
                location = max(NSMaxRange(paragraph), location + 1)
            }
        }
        if touchesFinal {
            text.addAttribute(.finalParagraphList, value: finalItem?.encoded ?? "", range: NSRange(location: text.length - 1, length: 1))
        }
    }

    /// Cambia l'elenco di un solo capoverso — quello che contiene `location` — senza toccare il paragrafo finale vuoto
    /// quando non è lui. Serve alle scelte che valgono solo per l'apertura di un tratto: ripartenza e ripresa, che
    /// applicate a tutta la selezione aprirebbero un tratto per ogni voce.
    public static func setListItem(in text: NSMutableAttributedString, at location: Int, _ transform: (ListItem) -> ListItem) {
        guard text.length > 0 else { return }
        if location >= text.length {
            guard hasEmptyFinalParagraph(text), let item = finalParagraphListItem(in: text) else { return }
            text.addAttribute(.finalParagraphList, value: transform(item).encoded, range: NSRange(location: text.length - 1, length: 1))
            return
        }
        let paragraph = bodyParagraph(in: text, at: min(location, text.length - 1)).range
        guard let encoded = text.attribute(.listItem, at: paragraph.location, effectiveRange: nil) as? String,
              let item = ListItem(encoded: encoded) else { return }
        text.addAttribute(.listItem, value: transform(item).encoded, range: paragraph)
    }

    /// Dopo una modifica rimette in ordine gli attributi di elenco: ogni paragrafo ha per intero l'elenco del suo
    /// primo carattere (come fa AppKit per lo stile di paragrafo), e la dichiarazione per il paragrafo finale
    /// resta solo sull'ultimo a capo.
    public static func repairLists(in text: NSMutableAttributedString, range: NSRange) {
        let length = text.length
        guard length > 0 else { return }
        // Un a capo che era l'ultimo può trovarsi subito prima del testo appena aggiunto.
        let start = max(min(range.location, length - 1) - 1, 0)
        let end = min(max(NSMaxRange(range), start + 1), length)
        var location = bodyParagraph(in: text, at: start).range.location
        while location < end {
            let paragraph = bodyParagraph(in: text, at: location).range
            // Elenco e stile di paragrafo valgono per tutto il paragrafo: quelli del primo carattere.
            for key in [NSAttributedString.Key.listItem, .paragraphStyleName] {
                var effective = NSRange(location: 0, length: 0)
                let value = text.attribute(key, at: paragraph.location, longestEffectiveRange: &effective, in: paragraph)
                if NSMaxRange(effective) < NSMaxRange(paragraph) {
                    if let value { text.addAttribute(key, value: value, range: paragraph) } else { text.removeAttribute(key, range: paragraph) }
                }
            }
            location = max(NSMaxRange(paragraph), location + 1)
        }
        let scanned = NSRange(location: start, length: end - start)
        var misplaced: [NSRange] = []
        text.enumerateAttribute(.finalParagraphList, in: scanned) { value, found, _ in
            guard value != nil else { return }
            // Può restare solo sull'ultimo carattere, se è un a capo del corpo.
            let keepsLast = NSMaxRange(found) == length && hasEmptyFinalParagraph(text)
            let stale = keepsLast ? NSRange(location: found.location, length: found.length - 1) : found
            if stale.length > 0 { misplaced.append(stale) }
        }
        for stale in misplaced { text.removeAttribute(.finalParagraphList, range: stale) }
    }
}

// MARK: - Liste rinominate o tolte

/// Che cosa è diventata ogni Lista dopo una modifica delle Liste: il suo nome nuovo, oppure `nil` se è stata tolta.
/// Le Liste che non compaiono restano come sono.
public typealias ListRenames = [String: String?]

extension StyleSheet {
    /// Gli stessi stili, con le Liste che danno rinominate o tolte.
    public func renamingLists(_ renames: ListRenames) -> StyleSheet {
        var result = self
        for index in result.styles.indices {
            if let old = result.styles[index].values.listName, let new = renames[old] { result.styles[index].values.listName = new }
        }
        return result
    }
}

extension TextStyling {
    /// Porta le voci del testo dalle Liste vecchie alle nuove: le voci di una Lista tolta non sono più voci.
    public static func renameLists(in text: NSMutableAttributedString, _ renames: ListRenames) {
        guard !renames.isEmpty, text.length > 0 else { return }
        let all = NSRange(location: 0, length: text.length)
        for key in [NSAttributedString.Key.listItem, .finalParagraphList] {
            text.enumerateAttribute(key, in: all) { value, range, _ in
                guard let encoded = value as? String, var item = ListItem(encoded: encoded), let name = item.listName, let new = renames[name] else { return }
                if let new {
                    // Il nome cambia, le misure proprie e la continuazione della voce restano.
                    item.listName = new
                    text.addAttribute(key, value: item.encoded, range: range)
                } else if key == .listItem {
                    text.removeAttribute(key, range: range)
                } else {
                    text.addAttribute(key, value: "", range: range)
                }
            }
        }
    }
}

// MARK: - Stili di flottante rinominati o tolti

extension TextStyling {
    /// Porta le note del testo dagli stili di flottante vecchi ai nuovi (`renames`: il nome nuovo, o `nil` se lo stile è
    /// stato tolto). Le note di uno stile tolto tornano note a piè di pagina.
    public static func renameFloatStyles(in text: NSMutableAttributedString, _ renames: [String: String?]) {
        guard !renames.isEmpty, text.length > 0 else { return }
        text.enumerateAttribute(.footnote, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let name = value as? String, let new = renames[name] else { return }
            text.addAttribute(.footnote, value: new ?? FloatStyle.footnoteName, range: range)
        }
    }
}
