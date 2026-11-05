import Foundation

/// Il documento come albero: i blocchi che vengono prima delle sezioni, poi le sezioni, annidate (`Section`).
///
/// Per ora l'unico blocco è il paragrafo. Una voce di elenco è un paragrafo che dichiara il proprio elenco e il
/// proprio livello (`Paragraph.list`); le tabelle saranno un altro caso di `Block`. Le note a piè di pagina sono
/// un caso di `Inline` che porta con sé il proprio testo, così che richiamo e nota viaggino insieme.
public struct Document: Equatable, Sendable {
    /// Versione minima da conservare al salvataggio dopo la lettura.
    public internal(set) var sourceVersion = 1
    /// Ingresso di documento conservato per le formule relative (per esempio corpo + 2 pt).
    public var formulaBase: CharacterStyle?
    public var pageSetup: PageSetup
    /// Se applicare la spaziatura dipendente dal corpo che i font dichiarano nella tabella `trak`.
    public var appliesFontTracking: Bool
    /// Se allineare ai margini i bordi ottici dei glifi (tabella `opbd`, o `lfbd`/`rtbd`).
    public var usesOpticalMargins: Bool
    /// Massima espansione o compressione dei glifi nel testo giustificato; zero la disattiva.
    public var glyphExpansionLimit: Double
    /// Lingua del documento (per esempio "it"): serve alla sillabazione e al controllo ortografico. Vale per
    /// tutto il testo a cui non è assegnata una lingua propria (`CharacterStyle.language`).
    public var language: String?
    /// Se dividere le parole a fine riga, dove la lingua è nota e si sa sillabare.
    public var hyphenates: Bool
    /// Gli stili del documento. Un documento scritto prima degli stili non ne ha.
    public var styles: StyleSheet
    /// Le Liste con un nome del documento.
    public var lists: [ListDefinition]
    /// Gli stili di flottante: che cosa fa un oggetto ancorato a un punto del testo ma collocato altrove (fase 5).
    /// Per ora c'è sempre, e solo, la nota a piè di pagina.
    public var floatStyles: [FloatStyle]
    /// Le regole: danno l'aspetto di uno stile a pezzi di testo che si trovano componendo (fase 7).
    public var rules: [TextRule] = []
    /// I tipi di pagina con un nome, che le sezioni scelgono (`pageSetup` è il tipo predefinito, delle pagine senza un tipo).
    public var pageTypes: [PageType] = []
    /// Gli stili di tabella: l'aspetto che le tabelle prendono dal loro stile (filetti, margini interni, fondo…).
    public var tableStyles: [TableStyle] = TableStyle.builtIn
    /// Le facce scelte per i ruoli (tondo, nero, corsivo, nero corsivo) in questo documento. Prevalgono su quelle
    /// delle impostazioni del programma.
    public var fontRoles = FontRoleTable()
    /// La Lista che numera le pagine dall'inizio del documento; `nil` per 1, 2, 3.
    public var pageNumbering: String?
    /// I blocchi che vengono prima della prima sezione (tutto il contenuto, in un documento senza sezioni).
    public var blocks: [Block]
    /// Le sezioni di primo livello: parti, capitoli, appendici. Ognuna contiene i suoi paragrafi e le sue sezioni interne.
    public var sections: [Section] = []

    /// La Lista che numera le note a piè di pagina (quella del loro stile di flottante); `nil` per la numerazione
    /// semplice 1, 2, 3.
    public var noteList: String? {
        get { floatStyles.first { $0.name == FloatStyle.footnoteName }?.listName }
        set {
            if let index = floatStyles.firstIndex(where: { $0.name == FloatStyle.footnoteName }) {
                floatStyles[index].listName = newValue
            } else {
                floatStyles.append(.footnote(listName: newValue))
            }
        }
    }

    public init(pageSetup: PageSetup = .a4, appliesFontTracking: Bool = true, usesOpticalMargins: Bool = true,
                glyphExpansionLimit: Double = LayoutOptions.defaultGlyphExpansionLimit, language: String? = nil, hyphenates: Bool = true,
                styles: StyleSheet = StyleSheet(), lists: [ListDefinition] = [], noteList: String? = nil, blocks: [Block] = []) {
        self.pageSetup = pageSetup
        self.appliesFontTracking = appliesFontTracking
        self.usesOpticalMargins = usesOpticalMargins
        self.glyphExpansionLimit = glyphExpansionLimit
        self.language = language
        self.hyphenates = hyphenates
        self.styles = styles
        self.lists = lists
        self.floatStyles = [.footnote(listName: noteList)]
        self.blocks = blocks
    }

    /// Le scelte di composizione che derivano dalle impostazioni del documento.
    public var layoutOptions: LayoutOptions {
        var options = LayoutOptions(appliesFontTracking: appliesFontTracking, usesOpticalMargins: usesOpticalMargins,
                                    glyphExpansionLimit: glyphExpansionLimit, hyphenationLanguage: language, hyphenates: hyphenates,
                                    lists: lists, floatStyles: floatStyles, styles: styles, rules: rules)
        options.fontRoles = fontRoles
        options.pageTypes = pageTypes
        options.pageNumbering = pageNumbering
        options.tableStyles = tableStyles
        return options
    }

    /// Lo stesso documento senza contenuto: le sole impostazioni.
    public var settingsOnly: Document {
        var copy = self
        copy.blocks = []
        copy.sections = []
        return copy
    }
}

/// Un tipo di pagina con un nome: formato, margini, pagine affacciate.
public struct PageType: Equatable, Sendable {
    public var name: String
    public var setup: PageSetup

    public init(name: String, setup: PageSetup) {
        self.name = name
        self.setup = setup
    }

    /// Il nome con cui si indica il tipo predefinito del documento.
    public static let defaultName = "Default"
    /// Il nome del tipo predefinito nei documenti di prima: alla lettura diventa `defaultName`.
    public static let legacyDefaultName = "Predefinito"
}

/// I tipi di pagina che una sezione indica (per nome; `nil` dove non ne indica uno): per le sue pagine (e per le dispari,
/// se indica anche le pari), per le pari, per la sua prima pagina. Dispari e pari passano alle sezioni interne, la prima
/// pagina no.
public struct SectionPageTypes: Hashable, Sendable {
    public var pages: String?
    public var evenPages: String?
    public var firstPage: String?

    public init(pages: String? = nil, evenPages: String? = nil, firstPage: String? = nil) {
        self.pages = pages
        self.evenPages = evenPages
        self.firstPage = firstPage
    }
}

/// Dove comincia una sezione: di seguito al testo prima, su una pagina nuova, o sulla prossima pagina dispari (lasciando
/// bianca la pari prima, se serve).
public enum SectionStart: String, CaseIterable, Sendable {
    case continuous
    case newPage = "new-page"
    case oddPage = "odd-page"
}

/// Una parte del documento: una parte, un capitolo, una sezione, un'appendice. Ha un titolo, che è un paragrafo vero in un
/// posto suo (può restare vuoto), poi i suoi blocchi, poi le sue sezioni interne. Dopo una sezione il testo può tornare
/// alla sezione che la contiene (o fuori da ogni sezione, al primo livello): quei blocchi stanno in `afterward` della
/// sezione dopo la quale vengono.
public struct Section: Equatable, Sendable {
    /// I ruoli già pronti; se ne possono usare altri, con un nome qualsiasi.
    public enum Role {
        public static let part = "part"
        public static let chapter = "chapter"
        public static let section = "section"
        public static let appendix = "appendix"
        public static let builtIn = [part, chapter, section, appendix]
    }

    /// L'identità stabile della sezione: non cambia quando la si sposta o se ne cambia il titolo.
    public var id: String
    /// Che cosa è la sezione (parte, capitolo…): è distinto dalla profondità e dallo stile del titolo.
    public var role: String
    public var title: Paragraph
    public var blocks: [Block]
    public var sections: [Section]
    /// I blocchi della sezione esterna (o del documento, al primo livello) che vengono dopo questa sezione.
    public var afterward: [Block]
    public var start: SectionStart
    public var pageTypes: SectionPageTypes
    /// La Lista con cui la sezione numera le pagine da lei in poi, ripartendo dal suo primo valore; `nil` per proseguire.
    public var pageNumbering: String?

    public init(id: String = Section.newID(), role: String = Role.section, title: Paragraph = Paragraph(), blocks: [Block] = [], sections: [Section] = [],
                start: SectionStart = .continuous, pageTypes: SectionPageTypes = SectionPageTypes(), pageNumbering: String? = nil,
                afterward: [Block] = []) {
        self.pageNumbering = pageNumbering
        self.afterward = afterward
        self.id = id
        self.role = role
        self.start = start
        self.pageTypes = pageTypes
        self.title = title
        self.blocks = blocks
        self.sections = sections
    }

    /// Un identificativo nuovo, che non si ripete nemmeno tra documenti diversi.
    public static func newID() -> String {
        "s" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }
}

/// Il segno che il titolo di una sezione porta nel testo piatto dell'editor: quale sezione apre, con che ruolo, a che
/// profondità (1 per una sezione di primo livello).
public struct SectionMark: Equatable, Sendable {
    public var id: String
    public var role: String
    public var depth: Int
    public var start: SectionStart
    public var pageTypes: SectionPageTypes
    public var pageNumbering: String?

    public init(id: String, role: String, depth: Int, start: SectionStart = .continuous, pageTypes: SectionPageTypes = SectionPageTypes(),
                pageNumbering: String? = nil) {
        self.pageNumbering = pageNumbering
        self.id = id
        self.role = role
        self.depth = depth
        self.start = start
        self.pageTypes = pageTypes
    }

    /// Righe di testo (identificativo, profondità, inizio, i tre tipi di pagina, ruolo): il valore dell'attributo resta una
    /// stringa. I nomi dei tipi sono vuoti dove non ce n'è uno; il ruolo va per ultimo perché è un nome libero.
    public var encoded: String {
        [id, String(depth), start.rawValue, pageTypes.pages ?? "", pageTypes.evenPages ?? "", pageTypes.firstPage ?? "", pageNumbering ?? "", role]
            .joined(separator: "\n")
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "\n", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8, !parts[0].isEmpty, let depth = Int(parts[1]), depth >= 1, let start = SectionStart(rawValue: parts[2]), !parts[7].isEmpty else { return nil }
        func name(_ text: String) -> String? { text.isEmpty ? nil : text }
        self.init(id: parts[0], role: parts[7], depth: depth, start: start,
                  pageTypes: SectionPageTypes(pages: name(parts[3]), evenPages: name(parts[4]), firstPage: name(parts[5])), pageNumbering: name(parts[6]))
    }
}

/// Un paragrafo del documento visto in fila, come nell'editor: con il segno della sezione, se è un titolo.
public struct FlatParagraph: Equatable, Sendable {
    public var paragraph: Paragraph
    public var section: SectionMark?
    /// Per un paragrafo di una cella di tabella: quale cella.
    public var cell: CellMark?
    /// Per il primo paragrafo che dopo una sezione torna a quella che la contiene: l'identità di quella sezione (vuota
    /// per il primo livello, fuori da ogni sezione).
    public var sectionReturn: String?

    public init(_ paragraph: Paragraph, section: SectionMark? = nil, cell: CellMark? = nil, sectionReturn: String? = nil) {
        self.paragraph = paragraph
        self.section = section
        self.cell = cell
        self.sectionReturn = sectionReturn
    }
}

extension Document {
    /// I ruoli delle sezioni del documento, nell'ordine in cui compaiono la prima volta.
    public var sectionRoles: [String] {
        var result: [String] = []
        func visit(_ sections: [Section]) {
            for section in sections {
                if !result.contains(section.role) { result.append(section.role) }
                visit(section.sections)
            }
        }
        visit(sections)
        return result
    }

    /// Tutti i paragrafi in fila: quelli prima delle sezioni, poi ogni sezione col suo titolo, i suoi paragrafi e le sue
    /// sezioni interne.
    public var flatParagraphs: [FlatParagraph] {
        var result: [FlatParagraph] = []
        func add(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .paragraph(let paragraph): result.append(FlatParagraph(paragraph))
                case .table(let table):
                    // Prima la didascalia (riga −1), poi le celle una dopo l'altra, riga per riga, ogni paragrafo con il segno
                    // della sua cella.
                    let captionMark = CellMark(table: table.id, row: -1, column: 0, headerRows: table.headerRows, style: table.styleName,
                                               tableValues: table.values, floatStyle: table.floatStyle)
                    for paragraph in table.caption { result.append(FlatParagraph(paragraph, cell: captionMark)) }
                    for (r, row) in table.rows.enumerated() {
                        for (c, cell) in row.cells.enumerated() where !cell.isCovered {
                            var mark = CellMark(table: table.id, row: r, column: c, headerRows: table.headerRows,
                                                style: table.styleName, tableValues: table.values, cellValues: cell.values, floatStyle: table.floatStyle)
                            mark.columnSpan = cell.columnSpan
                            mark.rowSpan = cell.rowSpan
                            for paragraph in cell.paragraphs { result.append(FlatParagraph(paragraph, cell: mark)) }
                        }
                    }
                }
            }
        }
        func add(_ section: Section, depth: Int) {
            result.append(FlatParagraph(section.title, section: SectionMark(id: section.id, role: section.role, depth: depth, start: section.start,
                                                                                 pageTypes: section.pageTypes, pageNumbering: section.pageNumbering)))
            add(section.blocks)
            for inner in section.sections {
                add(inner, depth: depth + 1)
                add(inner.afterward, returningTo: section.id)
            }
        }
        // Il primo paragrafo dei blocchi che tornano porta il segno del ritorno.
        func add(_ blocks: [Block], returningTo id: String) {
            let first = result.count
            add(blocks)
            if result.count > first { result[first].sectionReturn = id }
        }
        add(blocks)
        for section in sections {
            add(section, depth: 1)
            add(section.afterward, returningTo: "")
        }
        return result
    }

    /// Ricostruisce blocchi e sezioni dai paragrafi in fila. Un titolo chiude le sezioni aperte con una profondità
    /// scritta uguale o maggiore della sua, poi apre la sua dentro quella che resta (come i titoli di un testo: una
    /// profondità che salta livelli si accorcia, e le sorelle restano sorelle). Un segno già visto non apre una seconda
    /// sezione con la stessa identità: quel paragrafo è testo della sezione (così Invio in fondo a un titolo, che si porta
    /// dietro il segno, fa un paragrafo del corpo). Un segno di ritorno chiude le sezioni aperte dentro quella in cui
    /// torna (o tutte, al primo livello): i blocchi che seguono vanno in `afterward` dell'ultima sezione chiusa. Un ritorno
    /// a una sezione che non è aperta, o senza nulla da chiudere, non conta.
    public mutating func setFlatParagraphs(_ items: [FlatParagraph]) {
        var front: [Block] = []
        var roots: [Section] = []
        // `returned`: dopo l'ultima sezione interna il testo è tornato a questa.
        var open: [(declared: Int, section: Section, returned: Bool)] = []
        var rootReturned = false
        var seen: Set<String> = []
        func closeInnermost() {
            let closed = open.removeLast().section
            if open.isEmpty {
                roots.append(closed)
                rootReturned = false
            } else {
                open[open.count - 1].section.sections.append(closed)
                open[open.count - 1].returned = false
            }
        }
        func append(_ block: Block) {
            if open.isEmpty {
                if rootReturned, !roots.isEmpty { roots[roots.count - 1].afterward.append(block) } else { front.append(block) }
            } else {
                let top = open.count - 1
                if open[top].returned, !open[top].section.sections.isEmpty {
                    open[top].section.sections[open[top].section.sections.count - 1].afterward.append(block)
                } else {
                    open[top].section.blocks.append(block)
                }
            }
        }
        func returnTo(_ id: String) {
            if id.isEmpty {
                guard !open.isEmpty else { return }
                while !open.isEmpty { closeInnermost() }
                rootReturned = true
            } else if let index = open.lastIndex(where: { $0.section.id == id }), index < open.count - 1 {
                while open.count - 1 > index { closeInnermost() }
                open[index].returned = true
            }
        }
        // La tabella in costruzione: i paragrafi con il segno della stessa tabella, uno di seguito all'altro.
        var table: Table?
        var tableIDs: Set<String> = []
        func closeTable() {
            guard var finished = table else { return }
            table = nil
            // Le posizioni coperte dalle celle unite (le righe interamente coperte si aggiungono).
            var covered: Set<[Int]> = []
            for (r, row) in finished.rows.enumerated() {
                for (c, cell) in row.cells.enumerated() where !cell.paragraphs.isEmpty && (cell.columnSpan > 1 || cell.rowSpan > 1) {
                    for rr in r..<(r + cell.rowSpan) { for cc in c..<(c + cell.columnSpan) where rr != r || cc != c { covered.insert([rr, cc]) } }
                }
            }
            let lastRow = covered.map { $0[0] }.max() ?? -1
            while finished.rows.count <= lastRow { finished.rows.append(TableRow()) }
            let spanColumns = covered.map { $0[1] + 1 }.max() ?? 0
            // Le righe più corte si completano con celle vuote, con l'aspetto del primo paragrafo della tabella.
            let columns = max(finished.columnCount, spanColumns)
            let model = finished.rows.first?.cells.first?.paragraphs.first
            let empty = Paragraph(styleName: model?.styleName, style: model?.style ?? ParagraphStyle(),
                                  inlines: model.flatMap { $0.inlines.first.map { first -> [Inline] in
                                      if case .text(let run) = first { return [.text(run.with(text: ""))] } else { return [] } } } ?? [])
            for index in finished.rows.indices {
                while finished.rows[index].cells.count < columns { finished.rows[index].cells.append(TableCell()) }
                for cell in finished.rows[index].cells.indices where finished.rows[index].cells[cell].paragraphs.isEmpty {
                    if covered.contains([index, cell]) {
                        finished.rows[index].cells[cell] = .covered
                    } else {
                        finished.rows[index].cells[cell].paragraphs = [empty]
                    }
                }
            }
            finished.headerRows = min(finished.headerRows, finished.rows.count)
            append(.table(finished))
        }
        for item in items {
            if item.section == nil, let target = item.sectionReturn {
                closeTable()
                returnTo(target)
            }
            if let mark = item.cell, item.section == nil {
                if table?.id != mark.table {
                    closeTable()
                    // Una tabella interrotta da altro testo, se riprende, è un'altra tabella.
                    let id = tableIDs.insert(mark.table).inserted ? mark.table : Table.newID()
                    table = Table(id: id, headerRows: mark.headerRows, styleName: mark.style, values: mark.tableValues, floatStyle: mark.floatStyle)
                }
                if mark.row < 0 {
                    table!.caption.append(item.paragraph)
                    continue
                }
                while table!.rows.count <= mark.row { table!.rows.append(TableRow()) }
                while table!.rows[mark.row].cells.count <= mark.column { table!.rows[mark.row].cells.append(TableCell()) }
                // L'aspetto della cella (e le posizioni che copre) è quello del segno del suo primo paragrafo.
                if table!.rows[mark.row].cells[mark.column].paragraphs.isEmpty {
                    table!.rows[mark.row].cells[mark.column].values = mark.cellValues
                    table!.rows[mark.row].cells[mark.column].columnSpan = mark.columnSpan
                    table!.rows[mark.row].cells[mark.column].rowSpan = mark.rowSpan
                }
                table!.rows[mark.row].cells[mark.column].paragraphs.append(item.paragraph)
                continue
            }
            closeTable()
            if let mark = item.section, seen.insert(mark.id).inserted {
                while let last = open.last, last.declared >= mark.depth { closeInnermost() }
                open.append((mark.depth, Section(id: mark.id, role: mark.role, title: item.paragraph, start: mark.start, pageTypes: mark.pageTypes,
                                                pageNumbering: mark.pageNumbering), false))
            } else {
                append(.paragraph(item.paragraph))
            }
        }
        closeTable()
        while !open.isEmpty { closeInnermost() }
        blocks = front
        sections = roots
    }
}

public enum Block: Equatable, Sendable {
    case paragraph(Paragraph)
    case table(Table)
}

/// Una tabella: righe di celle, ogni cella con i suoi paragrafi. Le prime `headerRows` righe sono l'intestazione, che si
/// ripete in cima a ogni pagina quando la tabella si spezza.
public struct Table: Equatable, Sendable {
    public var id: String
    public var rows: [TableRow]
    public var headerRows: Int
    /// Lo stile di tabella; `nil` per quello predefinito («Griglia»).
    public var styleName: String?
    /// Ciò che la tabella cambia, solo per sé, dell'aspetto del suo stile.
    public var values: TableValues
    /// Lo stile di flottante che la colloca (qui, in cima, in fondo, in una pagina a parte) e la numera; `nil`: la
    /// tabella sta nel testo, dove si trova, senza didascalia.
    public var floatStyle: String?
    /// La didascalia (per una tabella flottante): i suoi paragrafi, senza il numero, che aggiunge la composizione.
    public var caption: [Paragraph]

    public init(id: String = Table.newID(), rows: [TableRow] = [], headerRows: Int = 0, styleName: String? = nil, values: TableValues = TableValues(),
                floatStyle: String? = nil, caption: [Paragraph] = []) {
        self.id = id
        self.rows = rows
        self.headerRows = headerRows
        self.styleName = styleName
        self.values = values
        self.floatStyle = floatStyle
        self.caption = caption
    }

    /// Un identificativo nuovo.
    public static func newID() -> String {
        "t" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }

    /// Quante colonne ha: quelle della riga più lunga.
    public var columnCount: Int { rows.map(\.cells.count).max() ?? 0 }
}

public struct TableRow: Equatable, Sendable {
    public var cells: [TableCell]
    public init(cells: [TableCell] = []) { self.cells = cells }
}

/// Una cella: almeno un paragrafo (vuoto, se la cella è vuota).
public struct TableCell: Equatable, Sendable {
    public var paragraphs: [Paragraph]
    /// L'aspetto proprio della cella (lati, fondo, allineamento verticale, margini interni).
    public var values: CellValues
    /// Quante colonne e quante righe copre (una cella unita ne copre più di una).
    public var columnSpan: Int
    public var rowSpan: Int
    /// Vero per una posizione coperta da una cella unita: non ha paragrafi, e non si scrive nel file.
    public var isCovered: Bool

    public init(paragraphs: [Paragraph] = [], values: CellValues = CellValues(), columnSpan: Int = 1, rowSpan: Int = 1, isCovered: Bool = false) {
        self.paragraphs = paragraphs
        self.values = values
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.isCovered = isCovered
    }

    /// Una posizione coperta da una cella unita.
    public static let covered = TableCell(isCovered: true)
}

/// Il segno che ogni paragrafo di una cella porta nel testo piatto dell'editor: di quale tabella, in quale riga e colonna,
/// e quante righe d'intestazione ha la tabella.
public struct CellMark: Equatable, Sendable {
    public var table: String
    public var row: Int
    public var column: Int
    public var headerRows: Int
    /// Lo stile della tabella e ciò che la tabella ne cambia (uguali in tutte le sue celle).
    public var style: String?
    public var tableValues: TableValues
    /// L'aspetto proprio della cella.
    public var cellValues: CellValues
    /// Lo stile di flottante della tabella (uguale in tutte le sue celle).
    public var floatStyle: String?
    /// Quante colonne e righe copre la cella (più di una se è unita).
    public var columnSpan = 1
    public var rowSpan = 1

    /// Vero per un paragrafo della didascalia (riga −1).
    public var isCaption: Bool { row < 0 }

    public init(table: String, row: Int, column: Int, headerRows: Int = 0, style: String? = nil,
                tableValues: TableValues = TableValues(), cellValues: CellValues = CellValues(), floatStyle: String? = nil) {
        self.table = table
        self.row = row
        self.column = column
        self.headerRows = headerRows
        self.style = style
        self.tableValues = tableValues
        self.cellValues = cellValues
        self.floatStyle = floatStyle
    }

    /// Lo stesso segno, per una cella che copre `columns` colonne e `rows` righe.
    public func spanning(columns: Int, rows: Int) -> CellMark {
        var mark = self
        mark.columnSpan = columns
        mark.rowSpan = rows
        return mark
    }

    /// Il segno di un'altra cella della stessa tabella (con il suo aspetto, e senza quello proprio di questa cella).
    public func cell(row: Int, column: Int, headerRows: Int? = nil) -> CellMark {
        CellMark(table: table, row: row, column: column, headerRows: headerRows ?? self.headerRows, style: style, tableValues: tableValues,
                 floatStyle: floatStyle)
    }

    /// Nove righe di testo: tabella, riga, colonna, righe d'intestazione, stile, aspetto della tabella, della cella, stile
    /// di flottante, colonne e righe coperte («2 1»; vuota per una cella sola).
    public var encoded: String {
        [table, String(row), String(column), String(headerRows), style ?? "", tableValues.encoded, cellValues.encoded, floatStyle ?? "",
         columnSpan == 1 && rowSpan == 1 ? "" : "\(columnSpan) \(rowSpan)"].joined(separator: "\n")
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard [4, 7, 8, 9].contains(parts.count), !parts[0].isEmpty, let row = Int(parts[1]), let column = Int(parts[2]), let header = Int(parts[3]),
              row >= -1, column >= 0, header >= 0 else { return nil }
        self.init(table: parts[0], row: row, column: column, headerRows: header)
        if parts.count >= 7 {
            guard let table = TableValues(encoded: parts[5]), let cell = CellValues(encoded: parts[6]) else { return nil }
            style = parts[4].isEmpty ? nil : parts[4]
            tableValues = table
            cellValues = cell
        }
        if parts.count >= 8, !parts[7].isEmpty { floatStyle = parts[7] }
        if parts.count == 9, !parts[8].isEmpty {
            let spans = parts[8].split(separator: " ").compactMap { Int($0) }
            guard spans.count == 2, spans[0] >= 1, spans[1] >= 1 else { return nil }
            columnSpan = spans[0]
            rowSpan = spans[1]
        }
    }
}

public struct Paragraph: Equatable, Sendable {
    /// Lo stile di paragrafo con un nome, se il paragrafo ne usa uno.
    public var styleName: String?
    /// Lo stile del paragrafo già risolto: i valori dello stile con un nome, più quelli dati a mano.
    public var style: ParagraphStyle
    /// L'elenco di cui il paragrafo è una voce, se lo è.
    public var list: ListItem?
    public var inlines: [Inline]
    /// La distanza d'apertura data a mano (in punti); senza, vale quella dello stile.
    public var openingDistance: Double?
    /// La tenuta data a mano; i valori assenti vengono dallo stile.
    public var keeping: LineKeeping

    public init(styleName: String? = nil, style: ParagraphStyle = ParagraphStyle(), list: ListItem? = nil, inlines: [Inline] = [], openingDistance: Double? = nil,
                keeping: LineKeeping = LineKeeping()) {
        self.styleName = styleName
        self.style = style
        self.list = list
        self.inlines = inlines
        self.openingDistance = openingDistance
        self.keeping = keeping
    }

    /// Il testo del paragrafo senza attributi.
    public var plainText: String {
        inlines.map { inline in
            switch inline {
            case .text(let run): run.text
            case .floating: ""
            case .image: "\u{FFFC}"
            }
        }.joined()
    }
}

public enum Inline: Equatable, Sendable {
    case text(TextRun)
    /// Una nota a piè di pagina, nel punto del testo in cui cade il suo richiamo.
    case floating(FloatingObject)
    /// Un'immagine nella riga, che si comporta come un carattere.
    case image(ImageObject)
}

/// Un'immagine: inclusa nel documento (i suoi byte viaggiano con il file) o collegata a un file esterno, con le misure
/// a cui la si mostra, in punti.
public struct ImageObject: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// I byte dell'immagine (PNG, JPEG, TIFF, GIF, HEIC, PDF…), scritti nel file.
        case embedded(Data)
        /// Il percorso di un file esterno: se lo si sposta o lo si cancella, l'immagine non si trova più.
        case linked(String)
    }

    public var source: Source
    public var width: Double
    public var height: Double

    public init(source: Source, width: Double, height: Double) {
        self.source = source
        self.width = width
        self.height = height
    }

    /// I byte dell'immagine: quelli inclusi, o letti dal file collegato (`nil` se non c'è più).
    public var data: Data? {
        switch source {
        case .embedded(let data): data
        case .linked(let path): FileManager.default.contents(atPath: path)
        }
    }
}

/// Uno stile di flottante: dove va un oggetto ancorato nel testo, e come si numera. La nota a piè di pagina, la nota a
/// margine, la nota di chiusura e la figura saranno stili di flottante (fase 5); per ora c'è la prima.
public struct FloatStyle: Hashable, Sendable {
    public static let footnoteName = "Footnote"
    /// Il nome che lo stile delle note a piè di pagina aveva nei documenti di prima: alla lettura diventa `footnoteName`.
    public static let legacyFootnoteName = "Nota a piè di pagina"

    /// Dove va il contenuto.
    public enum Placement: String, Hashable, Sendable {
        /// In fondo alla pagina in cui cade il richiamo, sotto un filetto.
        case pageFoot
        /// Tutte insieme dopo l'ultimo paragrafo del documento (note di chiusura).
        case documentEnd
        /// Nel margine esterno (a destra nelle pagine dispari, a sinistra nelle pari), accanto alla riga del richiamo.
        case outerMargin
        /// Una figura: un'immagine con la sua didascalia, collocata secondo le posizioni ammesse (come in LaTeX).
        case figure
        /// Un'intestazione: in testa alle pagine, ripetuta da dove è ancorata finché un'altra non prende il suo posto.
        case pageHead
        /// Un piè di pagina: in fondo alle pagine, come l'intestazione.
        case pageBottom

        /// Le collocazioni che si ripetono pagina per pagina.
        public var isRunning: Bool { self == .pageHead || self == .pageBottom }
    }

    /// Per quali pagine vale un'intestazione o un piè di pagina.
    public enum RunningPages: String, Hashable, Sendable, CaseIterable {
        case all, odd, even
        /// La sola prima pagina della sezione in cui è ancorata, quando la sezione comincia su una pagina nuova.
        case first
    }

    /// Dove può andare una figura, in ordine di preferenza (le lettere di LaTeX).
    public enum FigurePosition: String, Hashable, Sendable, CaseIterable {
        /// h: subito dopo il paragrafo che la richiama, se c'è posto.
        case here = "h"
        /// t: in cima a una pagina.
        case top = "t"
        /// b: in fondo a una pagina, sopra le note.
        case bottom = "b"
        /// p: su una pagina di sole figure.
        case page = "p"
    }

    /// Dove sta la didascalia di una figura.
    public enum CaptionPosition: String, Hashable, Sendable, CaseIterable {
        case below, above, none
    }

    /// Come si richiama nel testo.
    public enum Reference: String, Hashable, Sendable, CaseIterable {
        /// Il numero in apice (le cifre in apice del font, se ci sono).
        case superscript
        /// Il numero normale, sulla linea di base.
        case plain
        /// Nessun richiamo: il contenuto comincia senza numero.
        case none
    }

    public var name: String
    public var placement: Placement
    /// La Lista che lo numera; `nil` per la numerazione semplice 1, 2, 3.
    public var listName: String?
    public var reference: Reference
    /// Il filetto sopra il blocco di questa serie in fondo alla pagina, con la sua lunghezza (`nil`: un terzo della
    /// giustezza, al massimo 144 pt) e gli spazi sopra e sotto, in punti.
    public var showsRule: Bool
    public var ruleLength: Double?
    public var spaceAbove: Double
    public var spaceBelow: Double
    /// Se un contenuto che non entra nella pagina del richiamo può continuare nella pagina dopo.
    public var canSplit: Bool
    /// Lo stile di paragrafo con cui si compone il contenuto (rientri, interlinea, spazi, allineamento); `nil` per
    /// l'allineamento del paragrafo che lo richiama, senza rientri né spazi.
    public var contentStyle: String?
    /// Per le note di chiusura: il titolo che precede il loro blocco (`nil` o vuoto: nessuno), e se il blocco comincia
    /// su una pagina nuova.
    public var heading: String?
    public var startsOnNewPage: Bool
    /// Per le figure: le posizioni ammesse, in ordine di preferenza; con `exactlyHere` (H) la figura sta sempre subito
    /// dopo il suo paragrafo, come un paragrafo; con `ignoresLimits` (!) non valgono i limiti per pagina.
    public var positions: [FigurePosition]
    public var exactlyHere: Bool
    public var ignoresLimits: Bool
    public var caption: CaptionPosition
    /// Per intestazioni e piè di pagina: per quali pagine valgono, e la distanza del blocco dal bordo del foglio (in punti;
    /// `nil` per stare a metà del margine).
    public var pages: RunningPages = .all
    public var edgeDistance: Double?

    public init(name: String, placement: Placement = .pageFoot, listName: String? = nil, reference: Reference = .superscript,
                showsRule: Bool = true, ruleLength: Double? = nil, spaceAbove: Double = 7, spaceBelow: Double = 4,
                canSplit: Bool = true, contentStyle: String? = nil, heading: String? = nil, startsOnNewPage: Bool = false,
                positions: [FigurePosition] = [.here, .top, .bottom, .page], exactlyHere: Bool = false, ignoresLimits: Bool = false,
                caption: CaptionPosition = .below) {
        self.name = name
        self.placement = placement
        self.listName = listName
        self.reference = reference
        self.showsRule = showsRule
        self.ruleLength = ruleLength
        self.spaceAbove = spaceAbove
        self.spaceBelow = spaceBelow
        self.canSplit = canSplit
        self.contentStyle = contentStyle
        self.heading = heading
        self.startsOnNewPage = startsOnNewPage
        self.positions = positions
        self.exactlyHere = exactlyHere
        self.ignoresLimits = ignoresLimits
        self.caption = caption
    }

    /// Lo stile delle figure con cui nasce un documento nuovo: numerate con la Lista «Figure», senza richiamo.
    public static let figureName = "Figure"
    public static var defaultFigure: FloatStyle {
        FloatStyle(name: figureName, placement: .figure, listName: ListDefinition.figures.name, reference: .none, showsRule: false)
    }

    /// Lo stile delle tabelle flottanti, che nasce la prima volta che una tabella diventa flottante: numerate con la Lista
    /// «Tabelle», didascalia sopra.
    public static let tableName = "Table"
    public static var defaultTable: FloatStyle {
        FloatStyle(name: tableName, placement: .figure, listName: ListDefinition.tables.name, reference: .none, showsRule: false, caption: .above)
    }

    /// Lo stile delle note a piè di pagina.
    public static func footnote(listName: String?) -> FloatStyle { FloatStyle(name: footnoteName, listName: listName) }

    public static let headName = "Header"
    public static let bottomName = "Footer"

    /// Uno stile di intestazione (o, con `.pageBottom`, di piè di pagina): senza richiamo né numero, senza filetto.
    public static func running(name: String, placement: Placement = .pageHead, pages: RunningPages = .all) -> FloatStyle {
        var style = FloatStyle(name: name, placement: placement, reference: .none, showsRule: false, canSplit: false)
        style.pages = pages
        return style
    }
}

/// Un flottante: un oggetto ancorato in un punto del testo ma collocato altrove, secondo il suo stile (per ora, la nota
/// a piè di pagina). Il suo contenuto viaggia con il richiamo: spostando o cancellando il richiamo si sposta o si
/// cancella il flottante, e il numero non è scritto da nessuna parte, si calcola componendo la pagina.
///
/// Il contenuto può avere più paragrafi; non ha uno stile di paragrafo proprio, e non contiene altri flottanti.
public struct FloatingObject: Equatable, Sendable {
    /// I paragrafi del contenuto, ciascuno come sequenza di tratti di testo. Un paragrafo vuoto contiene un tratto
    /// vuoto, che ne conserva lo stile.
    public var paragraphs: [[TextRun]]
    /// Il nome del suo stile di flottante.
    public var style: String
    /// Per una figura: la sua immagine (i paragrafi sono la didascalia).
    public var image: ImageObject?

    public init(paragraphs: [[TextRun]], style: String = FloatStyle.footnoteName) {
        self.paragraphs = paragraphs
        self.style = style
    }

    /// Un flottante di un solo paragrafo.
    public init(runs: [TextRun], style: String = FloatStyle.footnoteName) {
        self.paragraphs = [runs]
        self.style = style
    }

    /// Tutti i tratti della nota, di seguito.
    public var runs: [TextRun] { paragraphs.flatMap { $0 } }

    public var plainText: String { paragraphs.map { $0.map(\.text).joined() }.joined(separator: "\n") }
}

/// Una formula inserita nel testo. Il carattere che la ospita ne è la posizione persistente; il suo aspetto è quello
/// del tratto che la contiene. Ogni formula parte da un oggetto (la posizione del carattere, o il documento), ne prende
/// un risultato e lo scrive nel punto del campo.
public enum FieldFormula: Hashable, Sendable {
    /// Posizione → Pagina contenente → Numero → Scrivi risultato qui.
    case pageContainingNumber
    /// Documento → Numero delle pagine → Scrivi risultato qui.
    case documentPageCount
    /// Posizione → Sezione contenente (di un ruolo) → Titolo → Scrivi risultato qui.
    case sectionContainingTitle(role: String)
    /// Posizione → Sezione contenente (di un ruolo) → Numero → Scrivi risultato qui.
    case sectionContainingNumber(role: String)

    /// L'espressione come la scrive il file; il ruolo, per le sezioni, sta a parte.
    public var expression: String {
        switch self {
        case .pageContainingNumber: "position.page-containing.number.write-here"
        case .documentPageCount: "document.page-count.write-here"
        case .sectionContainingTitle: "position.section-containing.title.write-here"
        case .sectionContainingNumber: "position.section-containing.number.write-here"
        }
    }

    public var role: String? {
        switch self {
        case .sectionContainingTitle(let role), .sectionContainingNumber(let role): role
        default: nil
        }
    }

    public init?(expression: String, role: String? = nil) {
        switch (expression, role) {
        case ("position.page-containing.number.write-here", nil): self = .pageContainingNumber
        case ("document.page-count.write-here", nil): self = .documentPageCount
        case ("position.section-containing.title.write-here", let role?) where !role.isEmpty: self = .sectionContainingTitle(role: role)
        case ("position.section-containing.number.write-here", let role?) where !role.isEmpty: self = .sectionContainingNumber(role: role)
        default: return nil
        }
    }

    /// La versione del formato che ha introdotto la formula.
    public var formatVersion: Int { self == .pageContainingNumber ? 9 : 13 }

    /// Il nome nei menu.
    public var title: String {
        switch self {
        case .pageContainingNumber: "Page number"
        case .documentPageCount: "Number of pages"
        case .sectionContainingTitle(let role): "Title of the current section: \(role)"
        case .sectionContainingNumber(let role): "Number of the current section: \(role)"
        }
    }

    /// La catena dell'espressione, da leggere: «Posizione → Pagina contenente → Numero».
    public var chain: String {
        switch self {
        case .pageContainingNumber: "Position → Containing page → Number"
        case .documentPageCount: "Document → Number of pages"
        case .sectionContainingTitle(let role): "Position → Containing section (\(role)) → Title"
        case .sectionContainingNumber(let role): "Position → Containing section (\(role)) → Number"
        }
    }
}

/// Un campo: un testo che la composizione calcola nel punto in cui compare (un «rimando relativo»). Nel testo è un carattere solo.
///
/// I quattro casi storici restano per leggere i documenti di prima; entrando nel documento o nel testo diventano le
/// formule equivalenti (`formula`), e il file scrive soltanto formule.
public enum Field: Hashable, Sendable {
    /// Il numero della pagina, come lo scrive la Lista che numera le pagine.
    case page
    /// Quante pagine ha il documento.
    case pageCount
    /// Il titolo della sezione in corso di un ruolo («capitolo»).
    case sectionTitle(role: String)
    /// Il numero della sezione in corso di un ruolo, come lo scrive la Lista che numera quel ruolo.
    case sectionNumber(role: String)
    /// Una formula salvata nel punto del testo in cui ne viene scritto il risultato.
    case formula(FieldFormula)

    /// Il carattere che tiene il posto del campo nel testo.
    public static let placeholder = "\u{FFFC}"

    /// La formula che il campo calcola: per i campi storici, quella equivalente.
    public var asFormula: FieldFormula {
        switch self {
        case .page: .pageContainingNumber
        case .pageCount: .documentPageCount
        case .sectionTitle(let role): .sectionContainingTitle(role: role)
        case .sectionNumber(let role): .sectionContainingNumber(role: role)
        case .formula(let formula): formula
        }
    }

    /// Il campo come formula.
    public var formula: Field { .formula(asFormula) }

    /// Un campo storico e la sua formula sono lo stesso campo.
    public static func == (lhs: Field, rhs: Field) -> Bool { lhs.asFormula == rhs.asFormula }
    public func hash(into hasher: inout Hasher) { hasher.combine(asFormula) }

    /// Il campo come valore di un attributo: «formula», l'espressione e, per le sezioni, il ruolo, separati da a capo.
    public var encoded: String {
        let formula = asFormula
        return "formula\n" + formula.expression + (formula.role.map { "\n" + $0 } ?? "")
    }

    /// Legge anche le forme storiche («page», «pages», «section-title» e «section-number» col ruolo), che diventano
    /// formule.
    public init?(encoded: String) {
        let parts = encoded.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("page"?, 1): self = .formula(.pageContainingNumber)
        case ("pages"?, 1): self = .formula(.documentPageCount)
        case ("section-title"?, 2) where !parts[1].isEmpty: self = .formula(.sectionContainingTitle(role: parts[1]))
        case ("section-number"?, 2) where !parts[1].isEmpty: self = .formula(.sectionContainingNumber(role: parts[1]))
        case ("formula"?, 2), ("formula"?, 3):
            guard let formula = FieldFormula(expression: parts[1], role: parts.count == 3 ? parts[2] : nil) else { return nil }
            self = .formula(formula)
        default: return nil
        }
    }
}

public struct TextRun: Equatable, Sendable {
    public var text: String
    /// Lo stile già risolto: ciò che viene dagli stili con un nome, più i valori dati a mano.
    public var style: CharacterStyle
    /// Gli stili con un nome del tratto, se ne ha.
    public var wordStyleName: String?
    public var characterStyleName: String?
    /// Le proprietà che le regole non toccano in questo tratto: vedi `NSAttributedString.Key.ruleExceptions`.
    public var ruleExceptions: Set<InspectorProperty>
    /// Per un campo, quale: il tratto è allora il solo carattere `Field.placeholder`.
    public var field: Field?

    public init(_ text: String, style: CharacterStyle, wordStyleName: String? = nil, characterStyleName: String? = nil,
                ruleExceptions: Set<InspectorProperty> = [], field: Field? = nil) {
        self.field = field
        self.text = text
        self.style = style
        self.wordStyleName = wordStyleName
        self.characterStyleName = characterStyleName
        self.ruleExceptions = ruleExceptions
    }

    /// Vero se `other` può proseguire questo tratto: stesso aspetto, stessi stili, stesse eccezioni alle regole.
    func continues(with other: TextRun) -> Bool {
        style == other.style && wordStyleName == other.wordStyleName && characterStyleName == other.characterStyleName
            && ruleExceptions == other.ruleExceptions && field == nil && other.field == nil
    }

    /// Lo stesso tratto con un altro testo.
    func with(text: String) -> TextRun {
        var copy = self
        copy.text = text
        return copy
    }
}

public struct CharacterStyle: Hashable, Sendable {
    /// Nome PostScript del font: identifica una faccia precisa (tondo, corsivo, nero sono font diversi).
    /// Per un font a più assi è il nome del font di base, con tutti gli assi al valore predefinito.
    public var fontName: String
    /// Corpo in punti.
    public var size: Double
    /// Funzioni tipografiche non predefinite. Hanno senso solo per questo font.
    public var features: [FeatureSetting]
    /// Lingua di questo testo (per esempio "la"), se diversa da quella del documento; `nil` per quella del documento.
    public var language: String?
    /// Nei font a più assi, i valori degli assi fissati. Hanno senso solo per questo font.
    public var variations: [AxisValue]
    /// Vero se si vuole il font a più assi anche quando lo stesso nome è installato in un file statico, che
    /// macOS altrimenti preferirebbe. Non serve quando ci sono assi fissati: quelli lo dicono già.
    public var prefersVariableFont: Bool
    /// Il ruolo richiesto dai comandi corsivo e nero, indipendentemente dalla faccia che lo realizza. `nil` nei
    /// documenti precedenti e nelle facce scelte esplicitamente: in quel caso si ricava dal font quando serve.
    public var fontRole: FontRole?
    /// Corpo ottico statico fissato a mano; `nil` sceglie automaticamente in base a `size`.
    /// Nei font variabili la stessa intenzione resta espressa dall'asse `opsz` in `variations`.
    public var opticalSize: StaticOpticalSize?
    /// Se le parole di questo testo si possono dividere a fine riga (dove la sillabazione del documento è accesa).
    public var hyphenates: Bool
    /// Il colore del testo, come `#rrggbb`; `nil` per il colore automatico (nero sulla pagina).
    public var color: String?
    /// Testo alzato o abbassato (apice, pedice, o una posizione propria); `nil` sulla linea di base.
    public var verticalPosition: VerticalPosition?
    /// I filetti del testo: sottolineato, barrato, o filetti propri.
    public var decorations: [LineDecoration]
    /// La composizione con Graphite, se chiesta: le funzioni Graphite (`tag=valore` separate da spazi, la stringa vuota
    /// per nessuna); `nil` per Core Text.
    public var graphite: String?
    /// Il maiuscoletto voluto, qualunque sia il font: le forme tecniche che il font conosce si scelgono solo al momento
    /// di comporre, e non stanno in `features`.
    public var smallCaps: SmallCaps

    public init(fontName: String, size: Double, features: [FeatureSetting] = [], language: String? = nil, variations: [AxisValue] = [],
                prefersVariableFont: Bool = false, fontRole: FontRole? = nil, opticalSize: StaticOpticalSize? = nil,
                hyphenates: Bool = true, color: String? = nil,
                verticalPosition: VerticalPosition? = nil, decorations: [LineDecoration] = [], graphite: String? = nil,
                smallCaps: SmallCaps = .off) {
        self.smallCaps = smallCaps
        self.fontName = fontName
        self.size = size
        self.features = features
        self.language = language
        self.variations = variations
        self.prefersVariableFont = prefersVariableFont
        self.fontRole = fontRole
        self.opticalSize = opticalSize
        self.hyphenates = hyphenates
        self.color = color
        self.verticalPosition = verticalPosition
        self.decorations = decorations
        self.graphite = graphite
    }
}

/// Un filetto legato al testo: una riga sotto, in mezzo o sopra le lettere, con il suo tipo, la sua distanza, il suo
/// spessore e il suo colore. Sottolineato e barrato sono due valori già pronti.
public struct LineDecoration: Hashable, Sendable {
    public enum Position: String, CaseIterable, Sendable {
        case under, through, over
    }

    public enum Pattern: String, CaseIterable, Sendable {
        case solid, double, dotted, dashed, wavy
    }

    public var position: Position
    public var pattern: Pattern
    /// Distanza in più dalla posizione consueta, in punti, allontanandosi dal testo (verso il basso per «sotto»).
    public var offset: Double
    /// Spessore in punti; `nil` per quello che il font dichiara per la sottolineatura.
    public var thickness: Double?
    /// Colore `#rrggbb`; `nil` per il colore del testo.
    public var color: String?
    /// Se il filetto sotto si interrompe dove passano le discendenti (g, p, q).
    public var skipsDescenders: Bool

    public init(position: Position, pattern: Pattern = .solid, offset: Double = 0, thickness: Double? = nil, color: String? = nil,
                skipsDescenders: Bool = false) {
        self.position = position
        self.pattern = pattern
        self.offset = offset
        self.thickness = thickness
        self.color = color
        self.skipsDescenders = skipsDescenders
    }

    public static let underline = LineDecoration(position: .under, skipsDescenders: true)
    public static let strikethrough = LineDecoration(position: .through)

    /// Come si scrive: «underline», «strikethrough», oppure «posizione tipo distanza spessore|auto colore|auto skip|noskip».
    public var encoded: String {
        if self == .underline { return "underline" }
        if self == .strikethrough { return "strikethrough" }
        func number(_ value: Double) -> String { String(format: "%g", value) }
        return [position.rawValue, pattern.rawValue, number(offset), thickness.map(number) ?? "auto", color ?? "auto",
                skipsDescenders ? "skip" : "noskip"].joined(separator: " ")
    }

    public init?(encoded: String) {
        let text = encoded.trimmingCharacters(in: .whitespaces)
        switch text {
        case "underline": self = .underline
        case "strikethrough": self = .strikethrough
        default:
            let parts = text.split(separator: " ").map(String.init)
            guard parts.count == 6, let position = Position(rawValue: parts[0]), let pattern = Pattern(rawValue: parts[1]),
                  let offset = Double(parts[2]), ["skip", "noskip"].contains(parts[5]) else { return nil }
            var thickness: Double?
            if parts[3] != "auto" {
                guard let value = Double(parts[3]), value > 0 else { return nil }
                thickness = value
            }
            var color: String?
            if parts[4] != "auto" {
                guard parts[4].hasPrefix("#"), parts[4].count == 7, UInt32(parts[4].dropFirst(), radix: 16) != nil else { return nil }
                color = parts[4].lowercased()
            }
            self.init(position: position, pattern: pattern, offset: offset, thickness: thickness, color: color, skipsDescenders: parts[5] == "skip")
        }
    }

    /// Più filetti in una stringa, separati da punto e virgola; la stringa vuota è «nessuno».
    public static func encode(_ decorations: [LineDecoration]) -> String { decorations.map(\.encoded).joined(separator: "; ") }

    public static func decode(_ text: String) -> [LineDecoration]? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var result: [LineDecoration] = []
        for part in text.split(separator: ";") {
            guard let decoration = LineDecoration(encoded: String(part)) else { return nil }
            result.append(decoration)
        }
        return result
    }
}

/// La posizione verticale di un testo: di quanto si alza (o, se negativa, si abbassa), in frazioni del corpo; di quanto
/// si rimpicciolisce; e se usare i glifi in apice o in pedice disegnati dal font, quando li ha per tutti i caratteri.
/// Apice e pedice sono due valori già pronti.
public struct VerticalPosition: Hashable, Sendable {
    public var shift: Double
    public var scale: Double
    public var usesFontGlyphs: Bool

    public init(shift: Double, scale: Double, usesFontGlyphs: Bool = true) {
        self.shift = shift
        self.scale = scale
        self.usesFontGlyphs = usesFontGlyphs
    }

    public static let superscript = VerticalPosition(shift: 0.33, scale: 0.65)
    public static let `subscript` = VerticalPosition(shift: -0.15, scale: 0.65)

    public var isRaised: Bool { shift > 0 }

    /// Come si scrive nel file e negli attributi: «superscript», «subscript», oppure «0.3 0.7 glyphs|synthetic».
    public var encoded: String {
        if self == .superscript { return "superscript" }
        if self == .subscript { return "subscript" }
        func number(_ value: Double) -> String { String(format: "%g", value) }
        return "\(number(shift)) \(number(scale)) \(usesFontGlyphs ? "glyphs" : "synthetic")"
    }

    public init?(encoded: String) {
        switch encoded {
        case "superscript": self = .superscript
        case "subscript": self = .subscript
        default:
            let parts = encoded.split(separator: " ")
            guard parts.count == 3, let shift = Double(parts[0]), let scale = Double(parts[1]), scale > 0, scale <= 1,
                  ["glyphs", "synthetic"].contains(parts[2]) else { return nil }
            self.init(shift: shift, scale: scale, usesFontGlyphs: parts[2] == "glyphs")
        }
    }
}

/// Stile di paragrafo. Le misure sono in punti.
public struct ParagraphStyle: Hashable, Sendable {
    public enum Alignment: String, Sendable, CaseIterable {
        case natural, left, right, center, justified
        /// Sulla virgola: il segno decimale della lingua del testo (la virgola per l'italiano, il punto per l'inglese) al
        /// centro della riga, e in una colonna di tabella uno sotto l'altro.
        case decimal
    }

    public var alignment: Alignment = .natural
    public var firstLineIndent: Double = 0
    public var leftIndent: Double = 0
    public var rightIndent: Double = 0
    public var spaceBefore: Double = 0
    public var spaceAfter: Double = 0
    /// Spazio aggiunto tra le righe.
    public var lineSpacing: Double = 0
    /// Moltiplicatore dell'altezza di riga; 0 significa l'altezza naturale del font.
    public var lineHeightMultiple: Double = 0
    /// Il livello di paragrafazione (1, 2, 3…); `nil` per un capoverso che non è un titolo.
    public var outlineLevel: Int?

    public init() {}
}
