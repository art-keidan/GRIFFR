import Foundation

/// Una formula inserita nel testo: una catena che parte da un oggetto, passa di oggetto in oggetto, ne legge un risultato
/// e lo scrive nel punto del campo («Scrivi risultato → Qui»). Il carattere che la ospita ne è la posizione persistente;
/// il suo aspetto è quello del tratto che la contiene.
///
/// `Posizione → Pagina contenente → Numero → Scrivi risultato qui` è una catena di questo tipo, come
/// `Documento → Numero delle pagine` o `Posizione → Sezione contenente (capitolo) → Titolo`. Il file la scrive come
/// espressione a passi separati da punti (`position.page-containing.number.write-here`); il ruolo di una sezione sta a
/// parte.
public struct FieldFormula: Hashable, Sendable {
    /// L'oggetto da cui la catena parte.
    public enum Origin: String, Hashable, Sendable, CaseIterable {
        /// Il punto del testo in cui sta il campo.
        case position
        /// Il documento intero.
        case document

        public var title: String {
            switch self {
            case .position: "Position"
            case .document: "Document"
            }
        }
    }

    /// Un passo: da un oggetto a un altro che lo contiene.
    public enum Step: Hashable, Sendable {
        /// La pagina in cui cade la posizione.
        case containingPage
        /// La sezione più interna di un ruolo («chapter») che contiene la posizione.
        case containingSection(role: String)

        public var token: String {
            switch self {
            case .containingPage: "page-containing"
            case .containingSection: "section-containing"
            }
        }

        public var title: String {
            switch self {
            case .containingPage: "Containing page"
            case .containingSection(let role): "Containing section (\(role))"
            }
        }

        /// L'oggetto a cui il passo arriva.
        var subject: Subject {
            switch self {
            case .containingPage: .page
            case .containingSection: .section
            }
        }
    }

    /// Il risultato letto dall'ultimo oggetto della catena.
    public enum Reading: String, Hashable, Sendable, CaseIterable {
        case number
        case title
        case pageCount = "page-count"

        public var title: String {
            switch self {
            case .number: "Number"
            case .title: "Title"
            case .pageCount: "Number of pages"
            }
        }
    }

    /// Il genere di oggetto in un punto della catena: dice quali passi e quali risultati vengono dopo.
    public enum Subject: Hashable, Sendable {
        case position, document, page, section

        public var title: String {
            switch self {
            case .position: "position"
            case .document: "document"
            case .page: "page"
            case .section: "section"
            }
        }

        /// I passi che partono da questo oggetto (per le sezioni, con un ruolo da scegliere).
        public var steps: [Step] {
            switch self {
            case .position: [.containingPage, .containingSection(role: "")]
            default: []
            }
        }

        /// I risultati che questo oggetto dà.
        public var readings: [Reading] {
            switch self {
            case .position: []
            case .document: [.pageCount]
            case .page: [.number]
            case .section: [.title, .number]
            }
        }
    }

    public var origin: Origin
    public var steps: [Step]
    public var reading: Reading

    public init(origin: Origin, steps: [Step] = [], reading: Reading) {
        self.origin = origin
        self.steps = steps
        self.reading = reading
    }

    // MARK: Le formule pronte (le voci di Inserisci › Campo)

    /// Posizione → Pagina contenente → Numero.
    public static var pageContainingNumber: FieldFormula { FieldFormula(origin: .position, steps: [.containingPage], reading: .number) }
    /// Documento → Numero delle pagine.
    public static var documentPageCount: FieldFormula { FieldFormula(origin: .document, reading: .pageCount) }
    /// Posizione → Sezione contenente (di un ruolo) → Titolo.
    public static func sectionContainingTitle(role: String) -> FieldFormula {
        FieldFormula(origin: .position, steps: [.containingSection(role: role)], reading: .title)
    }
    /// Posizione → Sezione contenente (di un ruolo) → Numero.
    public static func sectionContainingNumber(role: String) -> FieldFormula {
        FieldFormula(origin: .position, steps: [.containingSection(role: role)], reading: .number)
    }

    // MARK: Catena

    /// L'oggetto dopo l'origine e dopo ogni passo; `nil` dal primo passo che non parte dall'oggetto a cui si è arrivati.
    public var subjects: [Subject]? {
        var current: Subject = origin == .position ? .position : .document
        var result = [current]
        for step in steps {
            guard current.steps.contains(where: { $0.token == step.token }) else { return nil }
            current = step.subject
            result.append(current)
        }
        return result
    }

    /// L'oggetto a cui la catena arriva prima di leggere il risultato.
    public var lastSubject: Subject? { subjects?.last }

    /// Che cosa non va nella catena, se qualcosa non va.
    public var problem: String? {
        guard let subjects else {
            return "A step of the field formula does not start from the object the chain has reached."
        }
        for step in steps {
            if case .containingSection(let role) = step, role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.contains("\n") {
                return "The containing section needs a role (for example “chapter”)."
            }
        }
        if steps.filter({ if case .containingSection = $0 { true } else { false } }).count > 1 {
            return "The field formula can name only one section role."
        }
        let last = subjects[subjects.count - 1]
        guard last.readings.contains(reading) else {
            return last.readings.isEmpty
                ? "The chain ends at the \(last.title), which gives no result: add a step."
                : "A \(last.title) gives no “\(reading.title.lowercased())”."
        }
        return nil
    }

    /// La catena da leggere: «Position → Containing page → Number».
    public var chain: String {
        ([origin.title] + steps.map(\.title) + [reading.title]).joined(separator: " → ")
    }

    /// Il nome nei menu: quello delle formule pronte, altrimenti la catena.
    public var title: String {
        if self == .pageContainingNumber { return "Page number" }
        if self == .documentPageCount { return "Number of pages" }
        if let role, self == .sectionContainingTitle(role: role) { return "Title of the current section: \(role)" }
        if let role, self == .sectionContainingNumber(role: role) { return "Number of the current section: \(role)" }
        return chain
    }

    // MARK: File

    /// L'espressione come la scrive il file; il ruolo, per le sezioni, sta a parte.
    public var expression: String {
        ([origin.rawValue] + steps.map(\.token) + [reading.rawValue, "write-here"]).joined(separator: ".")
    }

    /// Il ruolo della sezione che la catena attraversa.
    public var role: String? {
        for step in steps { if case .containingSection(let role) = step { return role } }
        return nil
    }

    /// Legge un'espressione passo per passo; `nil` se non è una catena valida, o se il ruolo manca o avanza.
    public init?(expression: String, role: String? = nil) {
        let tokens = expression.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard tokens.count >= 3, tokens.last == "write-here", let origin = Origin(rawValue: tokens[0]),
              let reading = Reading(rawValue: tokens[tokens.count - 2]) else { return nil }
        var steps: [Step] = []
        for token in tokens[1..<(tokens.count - 2)] {
            switch token {
            case Step.containingPage.token: steps.append(.containingPage)
            case Step.containingSection(role: "").token:
                guard let role else { return nil }
                steps.append(.containingSection(role: role))
            default: return nil
            }
        }
        let formula = FieldFormula(origin: origin, steps: steps, reading: reading)
        guard formula.problem == nil, (role == nil) == (formula.role == nil) else { return nil }
        self = formula
    }

    /// La versione del formato che ha introdotto la formula.
    public var formatVersion: Int { self == .pageContainingNumber ? 9 : 13 }

    // MARK: Valore

    /// Il testo che la formula scrive, in un punto della composizione. Una catena che non dà risultato scrive niente.
    public func value(in context: FieldContext) -> String {
        guard problem == nil else { return "" }
        var section: FieldContext.Section?
        for step in steps {
            if case .containingSection(let role) = step { section = context.sections.last { $0.role == role } }
        }
        switch (lastSubject, reading) {
        case (.document?, .pageCount): return context.pageCount
        case (.page?, .number): return context.pageNumber
        case (.section?, .title): return section?.title ?? ""
        case (.section?, .number): return section?.number ?? ""
        default: return ""
        }
    }
}

extension FieldFormula: Codable {
    private enum CodingKeys: String, CodingKey { case expression, role }

    /// Come nel file: l'espressione a passi e, per le sezioni, il ruolo a parte.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expression = try container.decode(String.self, forKey: .expression)
        let role = try container.decodeIfPresent(String.self, forKey: .role)
        guard let formula = FieldFormula(expression: expression, role: role) else {
            throw DecodingError.dataCorruptedError(forKey: .expression, in: container, debugDescription: "Invalid field formula “\(expression)”")
        }
        self = formula
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expression, forKey: .expression)
        try container.encodeIfPresent(role, forKey: .role)
    }
}

/// Ciò che una formula di campo può leggere nel punto in cui si compone: la pagina, il documento, le sezioni aperte.
public struct FieldContext: Sendable {
    public struct Section: Sendable, Equatable {
        public var role: String
        public var title: String
        public var number: String?

        public init(role: String, title: String, number: String?) {
            self.role = role
            self.title = title
            self.number = number
        }
    }

    /// Il numero della pagina, come lo scrive la Lista che numera le pagine.
    public var pageNumber: String
    public var pageCount: String
    /// Le sezioni che contengono il punto, dalla più esterna alla più interna.
    public var sections: [Section]

    public init(pageNumber: String, pageCount: String, sections: [Section]) {
        self.pageNumber = pageNumber
        self.pageCount = pageCount
        self.sections = sections
    }
}

extension DocumentLayout {
    /// Ciò che un campo nella posizione `index` legge in questa composizione: per l'anteprima del suo editor.
    public func fieldContext(at index: Int) -> FieldContext {
        let page = locatedLine(for: index, affinity: .downstream)?.page ?? 0
        let sections = SectionEditing.enclosing(in: text, at: index).map { title in
            FieldContext.Section(role: title.mark.role, title: SectionEditing.titleText(of: title, in: text), number: listMarks[title.range.location])
        }
        return FieldContext(pageNumber: pages.indices.contains(page) ? pages[page].number : "", pageCount: String(pages.count), sections: sections)
    }
}
