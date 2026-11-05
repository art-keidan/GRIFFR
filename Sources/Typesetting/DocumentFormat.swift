import Foundation

/// Il formato di file nativo: XML in UTF-8, pensato per essere letto e corretto anche a mano.
///
/// ```xml
/// <?xml version="1.0" encoding="UTF-8"?>
/// <document version="1" font="HoeflerText-Regular" size="12">
/// <page width="210mm" height="297mm" top="25mm" bottom="25mm" left="25mm" right="25mm"/>
/// <p align="justified">Testo con <t small-caps="lowercase">maiuscoletto</t> e <t font="Vulcanius" size="14" features="17/1003">𐌹𐍃</t>.</p>
/// </document>
/// ```
///
/// - Un paragrafo per riga, in un elemento `p`. Dentro `p` ogni spazio conta; tra un `p` e l'altro no.
/// - `font` (nome PostScript), `size` (punti) e `features` si ereditano: documento → paragrafo → tratto `t`.
///   Chi cambia `font` azzera le funzioni ereditate, perché tipi e selettori valgono solo dentro un font.
/// - `features` è un elenco separato da spazi: `tipo/selettore` per AAT (`17/1003`), `tag=valore` per OpenType (`cv01=2`).
/// - `axes`, per i font a più assi, dà i valori degli assi diversi dal predefinito: `axes="wght=650 wdth=85"`.
///   `font` è allora il nome del font di base. Si eredita come `features`, e come quelle si azzera cambiando font.
/// - `small-caps` è il maiuscoletto voluto, qualunque sia il font: `lowercase` (le minuscole, il maiuscoletto consueto),
///   `uppercase` (le maiuscole: sigle, numeri romani), `all`, `off`. Le forme che lo realizzano (AAT 3/3, 37/1, 38/1,
///   OpenType `smcp`, `c2sc`) si scelgono quando si compone, fra quelle che il font conosce, e non si scrivono in
///   `features`. Si eredita, ma come nei file di prima, dove stava fra le funzioni, si azzera dove cambiano `font` o
///   `features`: lì va ripetuto. Leggendo un file di prima, quelle forme in `features` diventano `small-caps`.
/// - `variable="on"` chiede il font a più assi quando lo stesso nome è installato anche in un file statico (che
///   macOS altrimenti preferirebbe). Serve solo senza `axes`: un testo con assi fissati lo sottintende.
/// - Attributi di paragrafo, in punti: `align` (`left`, `right`, `center`, `justified`), `first-indent`,
///   `left-indent`, `right-indent`, `space-before`, `space-after`, `line-spacing`; `line-height` è un moltiplicatore.
///   `outline-level`, su `p` e sugli stili di paragrafo, registra il livello di paragrafazione (1, 2, 3…); 0 toglie
///   esplicitamente il livello ereditato. Nei file precedenti (senza alcun `outline-level`) lo stile «Titolo N» ha il
///   livello N; nei file nuovi il nome non conta.
/// - Sul documento: `lang` è la lingua (per esempio `it`), usata per sillabare e per l'ortografia;
///   `hyphenation="off"` spegne la sillabazione, `trak="off"` la spaziatura dipendente dal corpo, `opbd="off"`
///   i margini ottici (accesi se mancano).
/// - `lang` su `p`, `t` o `note` dà a quel testo una lingua diversa da quella del documento (`la`, `grc`, `sa`…);
///   si eredita come lo stile, e `lang=""` torna alla lingua del documento.
/// - `list` su `p` ne fa una voce di elenco. Il valore è il segno: un simbolo (`•`, `–`) oppure un modello di
///   numerazione, cioè un contatore (`1`, `a`, `A`, `i`, `I`) con la sua punteggiatura (`1.`, `a)`, `(i)`).
///   `level` è il livello di annidamento, da 1 (sottinteso) a 9. I numeri non si scrivono: si calcolano.
/// - `<lists>`, prima degli stili, contiene le Liste con un nome: `<list name="Esempi" counter="1" prefix="("
///   suffix=")" continues="on"/>`. `counter` è `1`, `a`, `A`, `i`, `I`, `*` (asterischi), `†` (segni
///   tipografici) o `none`; poi `start`, `end`, `parent` (un'altra lista, oppure `page`), `continues`,
///   `shows-parent`, `overflow` (`ask`, `restart`, `double`, `numbers`). Sul documento `notes` nomina la Lista
///   delle note. `in-list` su `p` (o su uno stile di paragrafo) mette il paragrafo in una Lista; `in-list=""`
///   lo toglie da quella che gli darebbe il suo stile.
/// - `<styles>`, subito dopo `<document>`, contiene gli stili con un nome: `<style name="Citazione"
///   target="paragraph" based-on="Testo" size="11" left-indent="24"/>`. `target` è `paragraph`, `word` o
///   `character`; uno stile può fissare `font` (faccia precisa) oppure `family`, `italic`, `bold`, e poi
///   `size`, `features`, `axes`, `small-caps`, `lang`, `hyphenation` e, per i paragrafi, le misure di paragrafo.
/// - `style` su `p` dà al paragrafo uno stile di paragrafo; `word-style` e `char-style` su `t` danno al tratto
///   uno stile di parola e uno di carattere. Gli attributi scritti accanto sono i valori dati a mano, che valgono
///   sopra quelli dello stile. Ordine: documento, stile del paragrafo, attributi del paragrafo, stile di parola,
///   stile di carattere, attributi del tratto.
/// - `color="#8b1a1a"` su `p`, `t`, `note` o `style` è il colore del testo; `color=""` torna al colore automatico.
/// - `vertical="superscript"` o `"subscript"` alza o abbassa il testo (apice, pedice); una posizione propria si scrive
///   «alzata corpo glyphs|synthetic», per esempio `vertical="0.4 0.6 synthetic"` (alzata e corpo in frazioni del corpo).
/// - `lines="underline"`, `"strikethrough"` o filetti propri, separati da «;»: «posizione tipo distanza spessore colore
///   skip|noskip», per esempio `lines="under dotted 1 0.6 #9b1c1c noskip"` (posizione `under`, `through`, `over`; tipo
///   `solid`, `double`, `dotted`, `dashed`, `wavy`; spessore e colore anche `auto`). `lines=""` toglie quelli ereditati.
/// - `hyphenation="off"` su `p` o `t` impedisce di dividere le parole di quel testo (sul documento spegne la
///   sillabazione di tutto il documento).
/// - `note`, dentro `p`, è una nota a piè di pagina nel punto del suo richiamo; il numero non si scrive, si calcola.
///   Può avere `font`, `size`, `features` propri e contenere testo, `t` e `br`; se ha più paragrafi, ciascuno sta
///   in un proprio `p`: `<note><p>Primo.</p><p>Secondo.</p></note>`.
/// - `<float-styles>`, dopo gli stili, contiene gli stili di flottante, se qualcosa differisce dalla sola nota a piè
///   di pagina predefinita: `<float-style name="Note del curatore" list="Note" reference="plain" rule="off"
///   rule-length="100" space-above="7" space-below="4" split="off" content="Nota"/>`. `reference` è `superscript`
///   (sottinteso), `plain` o `none`; `content` è uno stile di paragrafo. `placement="end"` raccoglie le note alla fine
///   del documento (note di chiusura), con un titolo facoltativo (`heading`) e `new-page="on"` per cominciare su una
///   pagina nuova. `placement="margin"` mette le note nel margine esterno, accanto alla riga del richiamo. Lo stile «Nota a piè di pagina» c'è sempre.
///   `style` su `note` la mette in una serie diversa da quella delle note a piè di pagina.
/// - `<rules>`, dopo gli stili di flottante, contiene le regole: `<rule find="first-words" count="2" in="Testo"
///   after="Titolo 1" style="Maiuscoletto"/>`. `find` è `first-letter`, `first-words` (con `count`), `first-sentence`,
///   `first-lines` (con `count`), `last-line` o `words` (con `pattern`: `capitals`, `roman`, `numbers`, oppure `list` con le parole in `list`, separate da
///   spazi). `in` limita la regola ai paragrafi di uno stile; `after` al primo paragrafo dopo uno stile;
///   `position="sequence-start"` al primo paragrafo di una sequenza (del documento, o il titolo di una sezione che
///   comincia su una pagina nuova), `position="page-start"` al primo di una pagina.
///   `find="paragraph"` è il paragrafo intero, e può avere uno stile di paragrafo. Una condizione su una proprietà
///   dinamica: `if="lines|words|last-line-fill|hyphens" compare="eq|lt|le|gt|ge" value="1"`.
///   `style` è uno stile di carattere o di parola;
///   `enabled="off"` spegne la regola senza toglierla.
/// - `img`, dentro `p`, è un'immagine nella riga, con `width` e `height` (in punti, o con l'unità): collegata a un
///   file esterno (`src="/percorso/foto.jpg"`, vuota), oppure inclusa, con i suoi byte in base64 come contenuto.
/// - Le misure delle voci di elenco, in punti o con l'unità, dal rientro sinistro del paragrafo: `list-indent` (dove
///   comincia il testo) e `list-marker` (dove finisce il segno, allineato a destra) su `p`; `indent` e `marker` su `list`,
///   per tutte le voci della Lista. Senza, il testo a 24 pt per livello e il segno che finisce 6 pt prima.
/// - `br` è un a capo dentro il paragrafo. Le misure della pagina accettano `mm`, `cm`, `in`, `pt`.
/// - `section`, dopo i paragrafi iniziali, è una parte del documento (`role`: `parte`, `capitolo`, `sezione`,
///   `appendice` o un altro nome; `id` è la sua identità stabile). Comincia con `<title>`, che contiene un solo `p`
///   (o nessuno, per un titolo vuoto), poi i suoi paragrafi, poi le sue sezioni interne. Paragrafi e tabelle dopo una
///   sezione interna tornano alla sezione che la contiene; dopo una sezione di primo livello, fuori da ogni sezione.
///   `start="new-page"` la fa cominciare su una pagina nuova, `start="odd-page"` sulla prossima pagina dispari.
/// - `<table id header-rows>`, tra i paragrafi (anche in una sezione, prima delle sue sezioni interne): righe `<row>`, celle
///   `<cell>`, e in ogni cella i suoi `p` (`<cell/>` è una cella con un paragrafo vuoto). `header-rows`: quante righe sono
///   l'intestazione. `style` è lo stile di tabella (senza, «Griglia»); `rules` (`grid`, `three-rules`, `horizontal`,
///   `frame`, `none`), `rule-width`, `padding` («4» o «sopra destra sotto sinistra»), `valign` (`top`, `middle`,
///   `bottom`) e `background` («#rrggbb», «» per nessuno) cambiano lo stile solo per quella tabella. Su `cell`: `top`,
///   `right`, `bottom`, `left` (uno spessore, o `none`), `background`, `valign`, `padding`, solo per quella cella.
/// - `colspan` e `rowspan` su `cell`: quante colonne e righe copre una cella unita; le posizioni coperte non hanno un
///   `cell` (come in HTML: la cella dopo prende la prima colonna libera; una riga tutta coperta è `<row/>`).
/// - `float="Tabella"` su `table`: la colloca lo stile di flottante indicato (dove va, la didascalia sopra o sotto, la Lista
///   che la numera); la didascalia sta in `<caption>`, prima delle righe, con i suoi `p` (senza il numero).
/// - `<table-styles>`, dopo gli stili di flottante, contiene gli stili di tabella se non sono quelli con cui nasce ogni
///   documento: `<table-style name="Tre filetti" rules="three-rules" rule-width="0.75"/>`, con gli attributi di `table`.
/// - `<page-types>`, dopo `page`, contiene i tipi di pagina con un nome: `<page-type name="Apertura" top="80mm"/>`, con gli
///   attributi di `page` (quelli che mancano vengono da `page`). Una sezione li sceglie con `page-type` (le sue pagine),
///   `even-page-type` (le pari) e `first-page-type` (la sua prima pagina); `Predefinito` è il tipo di `page`.
/// - `placement="head"` o `placement="bottom"` su `float-style`: intestazione o piè di pagina, ripetuti da dove sono ancorati
///   finché un altro dello stesso tipo non prende il loro posto; `pages="odd|even|first"` (le dispari, le pari, la sola prima
///   pagina della sezione in cui sono ancorati) e `edge` (la distanza dal bordo del foglio; senza, a metà del margine).
/// - `<field kind="page"/>`, dentro `p` o `note`, è un campo storico del numero della pagina. `pages` dà quante pagine;
///   `section-title` e `section-number` (con `role`) danno la sezione in corso di quel ruolo. La versione 9 introduce
///   `<field kind="formula" expression="position.page-containing.number.write-here"/>`: la posizione del carattere
///   ospite determina la pagina, il numero segue la numerazione del documento e il risultato usa lo stile del campo.
///   Tutti i campi accettano gli attributi di `t`. `page-numbering`, su `document` e su `section`, nomina la Lista che
///   numera le pagine (da una sezione in poi, ripartendo).
/// - `opening-distance` (in punti, o con l'unità), su `style` di paragrafo e su `p`: la distanza d'apertura, dal margine
///   superiore, del paragrafo che apre una sequenza di pagine. `opens-section` su `style` di paragrafo: il ruolo della
///   sezione che lo stile apre quando lo si dà a un paragrafo (vuoto: nessuno).
///
/// La lettura è severa: elementi o attributi sconosciuti sono un errore con il numero di riga, non vengono
/// ignorati, così un refuso in un file corretto a mano non fa perdere contenuto in silenzio.
public enum DocumentFormat {
    public static let version = 11

    public static func writingVersion(for document: Document) -> Int {
        let contextual = document.styles.styles.flatMap(\.formulas).contains {
            $0.operation.property.isDirective || $0.operation.property == .applyStyle || !$0.when.isAlways || $0.target != .paragraph
        } || document.styles.styles.contains { $0.values.nextStyle != nil }
        let preciseFace = document.styles.styles.flatMap(\.formulas).contains { $0.operation.property == .face }
        let subtracts = document.styles.styles.flatMap(\.formulas).contains { $0.operation.predicate == .subtract }
        let extended = document.styles.styles.flatMap(\.formulas).contains {
            [.family, .color, .smallCaps, .hyphenates].contains($0.operation.property)
        }
        let formulaFields = document.flatParagraphs.contains { paragraph in
            func containsFormula(_ paragraph: Paragraph) -> Bool {
                paragraph.inlines.contains { inline in
                    switch inline {
                    case .text(let run):
                        if case .some(.formula(_)) = run.field { return true }
                        return false
                    case .floating(let object):
                        return object.paragraphs.contains { runs in runs.contains { if case .some(.formula(_)) = $0.field { return true }; return false } }
                    case .image: return false
                    }
                }
            }
            return containsFormula(paragraph.paragraph)
        }
        let styles = document.styles.styles
        // La versione più bassa che sa leggere tutto ciò che il documento usa: ogni costrutto con la versione che l'ha
        // introdotto. Un documento aperto da una versione più nuova non scende sotto di essa.
        let needs: [(version: Int, used: Bool)] = [
            (2, styles.contains { $0.values.pageStartSpacing != nil }),
            (3, !document.styles.selections.isEmpty),
            (4, styles.contains { !$0.formulas.isEmpty }),
            (5, extended),
            (6, subtracts),
            (7, preciseFace),
            (8, contextual),
            (9, formulaFields),
            (10, !document.styles.reusableFormulas.isEmpty),
            (11, styles.contains { $0.formulas.contains { $0.binding != nil } }),
        ]
        return needs.filter(\.used).map(\.version).reduce(max(1, document.sourceVersion), max)
    }
    public static let fileExtension = "grx"
    /// Le estensioni che si aprono: quella d'ora in poi e `.wpx`, quella dei file scritti prima.
    public static let readableExtensions: Set<String> = [fileExtension, "wpx"]

    // MARK: Scrittura

    public static func data(for document: Document, minimumVersion: Int = 1) -> Data {
        Data(string(for: document, minimumVersion: minimumVersion).utf8)
    }

    public static func string(for document: Document, minimumVersion: Int = 1) -> String {
        let paragraphs = document.flatParagraphs.map(\.paragraph)
        // Lo stile più usato diventa quello del documento, così la maggior parte dei paragrafi non lo ripete.
        var base = dominantStyle(paragraphs.flatMap { paragraph in runs(of: paragraph).map { ($0.style, $0.text.utf16.count + 1) } })
        if document.styles.styles.contains(where: { !$0.formulas.isEmpty }) {
            base = document.formulaBase ?? TextStyling.styleBase
        }
        // La lingua comune a tutto il testo è quella del documento, che ha il suo attributo; e sul documento
        // l'attributo della sillabazione è l'interruttore generale, non una proprietà delle parole.
        base?.language = nil
        base?.hyphenates = true
        let sheet = document.styles

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<document version=\"\(max(writingVersion(for: document), minimumVersion))\""
        if let base { out += styleAttributes(base, relativeTo: nil) }
        if let language = document.language { out += " lang=\"\(escapedAttribute(language))\"" }
        if !document.hyphenates { out += " hyphenation=\"off\"" }
        if !document.appliesFontTracking { out += " trak=\"off\"" }
        if !document.usesOpticalMargins { out += " opbd=\"off\"" }
        if document.glyphExpansionLimit != LayoutOptions.defaultGlyphExpansionLimit {
            out += " expansion=\"\(number(document.glyphExpansionLimit * 100))\""
        }
        // Un riferimento a una Lista che il documento non ha renderebbe il file illeggibile: non si scrive.
        let knownLists = Set(document.lists.map(\.name))
        if let notes = document.noteList, knownLists.contains(notes) { out += " notes=\"\(escapedAttribute(notes))\"" }
        if let pages = document.pageNumbering, knownLists.contains(pages) { out += " page-numbering=\"\(escapedAttribute(pages))\"" }
        out += ">\n"

        if !document.lists.isEmpty {
            out += "<lists>\n"
            for list in document.lists { out += listDefinitionElement(list) }
            out += "</lists>\n"
        }

        if !sheet.isEmpty {
            out += "<styles>\n"
            for style in sheet.styles {
                out += "<style name=\"\(escapedAttribute(style.name))\" target=\"\(style.target.rawValue)\""
                if let basedOn = style.basedOn { out += " based-on=\"\(escapedAttribute(basedOn))\"" }
                var values = style.values
                // La stringa vuota è «nessuna Lista»: toglie quella che darebbe lo stile su cui si basa.
                if let list = values.listName, !list.isEmpty, !knownLists.contains(list) { values.listName = nil }
                out += styleValueAttributes(values)
                if style.formulas.isEmpty { out += "/>\n" }
                else {
                    out += ">\n"
                    for formula in style.formulas { out += formulaElement(formula) }
                    out += "</style>\n"
                }
            }
            out += "</styles>\n"
        }

        // Gli stili di flottante, solo se c'è qualcosa oltre alla nota a piè di pagina predefinita.
        if document.floatStyles != [FloatStyle.footnote(listName: document.noteList)] {
            out += "<float-styles>\n"
            for style in document.floatStyles { out += floatStyleElement(style, knownLists: knownLists, sheet: sheet) }
            out += "</float-styles>\n"
        }

        // Gli stili di tabella, solo se non sono quelli con cui nasce ogni documento.
        if document.tableStyles != TableStyle.builtIn {
            out += "<table-styles>\n"
            for style in document.tableStyles { out += "<table-style name=\"\(escapedAttribute(style.name))\"" + tableValueAttributes(style.values) + "/>\n" }
            out += "</table-styles>\n"
        }
        let tableStyleNames = Set(document.tableStyles.map(\.name))

        // Le regole che rimandano a stili che non ci sono più non si scrivono: il file non si potrebbe riaprire.
        let rules = document.rules.filter { ruleIsWritable($0, sheet: sheet) }
        if !rules.isEmpty || !sheet.selections.isEmpty || !sheet.reusableFormulas.isEmpty {
            out += "<rules>\n"
            if !sheet.reusableFormulas.isEmpty {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
                let data = try! encoder.encode(sheet.reusableFormulas)
                out += "<reusable-formulas encoding=\"json-v1\" data=\"\(data.base64EncodedString())\"/>\n"
            }
            for selection in sheet.selections {
                out += "<selection id=\"\(selection.id.uuidString)\" name=\"\(escapedAttribute(selection.name))\" source=\"\(selection.source.rawValue)\" index=\"\(selection.index)\"/>\n"
            }
            for rule in rules { out += ruleElement(rule) }
            out += "</rules>\n"
        }

        out += "<page" + pageAttributes(document.pageSetup) + "/>\n"
        if !document.pageTypes.isEmpty {
            out += "<page-types>\n"
            for type in document.pageTypes { out += "<page-type name=\"\(escapedAttribute(type.name))\"" + pageAttributes(type.setup) + "/>\n" }
            out += "</page-types>\n"
        }

        if !document.fontRoles.isEmpty {
            out += "<font-roles>\n"
            for customization in document.fontRoles.customizations { out += fontRoleElement(customization) }
            out += "</font-roles>\n"
        }

        // Il contenuto in ordine: i paragrafi prima delle sezioni, poi ogni sezione con il titolo, i paragrafi e le interne.
        enum Piece { case paragraph(Paragraph), openSection(Section), openTitle, closeTitle, closeSection, openTable(Table), openCaption, closeCaption, openRow, openCell(TableCell), closeCell, closeRow, closeTable }
        var pieces: [Piece] = []
        func add(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .paragraph(let paragraph): pieces.append(.paragraph(paragraph))
                case .table(let table):
                    pieces.append(.openTable(table))
                    if !table.caption.isEmpty {
                        pieces.append(.openCaption)
                        pieces += table.caption.map(Piece.paragraph)
                        pieces.append(.closeCaption)
                    }
                    for row in table.rows {
                        pieces.append(.openRow)
                        for cell in row.cells where !cell.isCovered {
                            pieces.append(.openCell(cell))
                            pieces += cell.paragraphs.map(Piece.paragraph)
                            pieces.append(.closeCell)
                        }
                        pieces.append(.closeRow)
                    }
                    pieces.append(.closeTable)
                }
            }
        }
        add(document.blocks)
        func add(_ section: Section) {
            pieces += [.openSection(section), .openTitle, .paragraph(section.title), .closeTitle]
            add(section.blocks)
            for inner in section.sections {
                add(inner)
                add(inner.afterward)
            }
            pieces.append(.closeSection)
        }
        for section in document.sections {
            add(section)
            add(section.afterward)
        }

        var inTitle = false
        for piece in pieces {
            let paragraph: Paragraph
            switch piece {
            case .openSection(let section):
                out += "<section id=\"\(escapedAttribute(section.id))\" role=\"\(escapedAttribute(section.role))\""
                if section.start != .continuous { out += " start=\"\(section.start.rawValue)\"" }
                if let list = section.pageNumbering, knownLists.contains(list) { out += " page-numbering=\"\(escapedAttribute(list))\"" }
                // Un tipo di pagina che non c'è più renderebbe il file illeggibile: non si scrive.
                let known = Set(document.pageTypes.map(\.name) + [PageType.defaultName])
                for (attribute, name) in [("page-type", section.pageTypes.pages), ("even-page-type", section.pageTypes.evenPages),
                                          ("first-page-type", section.pageTypes.firstPage)] {
                    if let name, known.contains(name) { out += " \(attribute)=\"\(escapedAttribute(name))\"" }
                }
                out += ">\n"
                continue
            case .openTitle:
                out += "<title>"
                inTitle = true
                continue
            case .closeTitle:
                inTitle = false
                if out.hasSuffix("\n") { out.removeLast() }
                out += "</title>\n"
                continue
            case .closeSection:
                out += "</section>\n"
                continue
            case .openTable(let table):
                out += "<table id=\"\(escapedAttribute(table.id))\""
                if table.headerRows > 0 { out += " header-rows=\"\(table.headerRows)\"" }
                // Uno stile che il documento non ha più non si scrive: il file non si potrebbe riaprire.
                if let style = table.styleName, tableStyleNames.contains(style) { out += " style=\"\(escapedAttribute(style))\"" }
                if let float = table.floatStyle, document.floatStyles.contains(where: { $0.name == float }) { out += " float=\"\(escapedAttribute(float))\"" }
                out += tableValueAttributes(table.values) + ">\n"
                continue
            case .openCaption:
                out += "<caption>"
                continue
            case .closeCaption:
                if out.hasSuffix("\n") { out.removeLast() }
                out += "</caption>\n"
                continue
            case .openRow:
                out += "<row>\n"
                continue
            case .openCell(let cell):
                out += "<cell"
                if cell.columnSpan > 1 { out += " colspan=\"\(cell.columnSpan)\"" }
                if cell.rowSpan > 1 { out += " rowspan=\"\(cell.rowSpan)\"" }
                out += cellValueAttributes(cell.values) + ">"
                continue
            case .closeCell:
                if out.hasSuffix("\n") { out.removeLast() }
                out += "</cell>\n"
                continue
            case .closeRow:
                out += "</row>\n"
                continue
            case .closeTable:
                out += "</table>\n"
                continue
            case .paragraph(let next):
                paragraph = next
            }
            let runs = runs(of: paragraph)
            let styleName = paragraph.styleName.flatMap { sheet.style(named: $0)?.target == .paragraph ? $0 : nil }
            // Ciò che il paragrafo riceverebbe senza valori propri: il documento con sopra il suo stile.
            let paragraphBase = base.map { sheet.values(of: styleName).applied(to: $0) }
            // Lo stile comune si cerca tra i tratti senza stili propri, che altrimenti lo sposterebbero.
            let plain = runs.filter { $0.wordStyleName == nil && $0.characterStyleName == nil }
            let local = dominantStyle((plain.isEmpty ? runs : plain).map { ($0.style, $0.text.utf16.count) }) ?? paragraphBase
            out += "<p"
            if let styleName { out += " style=\"\(escapedAttribute(styleName))\"" }
            // Il livello di un titolo è la profondità della sua sezione: lo dice già l'annidamento, non si ripete.
            var titleAware = paragraph.style
            if inTitle { titleAware.outlineLevel = sheet.resolveParagraph(styleName: styleName).outlineLevel }
            out += paragraphAttributes(titleAware, relativeTo: sheet.resolveParagraph(styleName: styleName))
            // La Lista che lo stile darebbe al paragrafo non si ripete; un'altra, o nessuna, sì.
            let styleList = sheet.values(of: styleName).listName.flatMap { knownLists.contains($0) ? ListItem(listName: $0) : nil }
            let ownList = paragraph.list.flatMap { $0.listName == nil || knownLists.contains($0.listName!) ? $0 : nil }
            if ownList != styleList {
                if let list = ownList, let name = list.listName {
                    out += " in-list=\"\(escapedAttribute(name))\""
                } else if let list = ownList {
                    out += " list=\"\(escapedAttribute(list.marker))\""
                    if list.level != 1 { out += " level=\"\(list.level)\"" }
                } else {
                    out += " in-list=\"\""
                }
            }
            if let list = ownList {
                if let indent = list.textIndent { out += " list-indent=\"\(number(indent))\"" }
                if let marker = list.markerPosition { out += " list-marker=\"\(number(marker))\"" }
            }
            if let distance = paragraph.openingDistance { out += " opening-distance=\"\(number(distance))\"" }
            out += paragraph.keeping.xmlAttributes
            if let local { out += styleAttributes(local, relativeTo: paragraphBase) }
            func written(_ runs: [TextRun], relativeTo style: CharacterStyle?) -> String {
                runs.filter { !$0.text.isEmpty }.map { run -> String in
                    let word = run.wordStyleName.flatMap { sheet.style(named: $0)?.target == .word ? $0 : nil }
                    let character = run.characterStyleName.flatMap { sheet.style(named: $0)?.target == .character ? $0 : nil }
                    var attributes = ""
                    if let word { attributes += " word-style=\"\(escapedAttribute(word))\"" }
                    if let character { attributes += " char-style=\"\(escapedAttribute(character))\"" }
                    if let exceptions = TextStyling.encodedRuleExceptions(run.ruleExceptions) { attributes += " rules-off=\"\(exceptions)\"" }
                    // I valori del tratto si scrivono rispetto a ciò che gli darebbero i suoi stili.
                    let runBase = style.map { sheet.values(of: character).applied(to: sheet.values(of: word).applied(to: $0)) }
                    attributes += runBase.map { styleAttributes(run.style, relativeTo: $0) } ?? ""
                    if let field = run.field { return "<field" + fieldAttributes(field) + attributes + "/>" }
                    return attributes.isEmpty ? escapedText(run.text) : "<t\(attributes)>\(escapedText(run.text))</t>"
                }.joined()
            }
            let content = paragraph.inlines.map { inline -> String in
                switch inline {
                case .text(let run):
                    return written([run], relativeTo: local)
                case .floating(let note):
                    // Lo stile della nota si dichiara una volta, rispetto a quello del paragrafo che la contiene.
                    let noteStyle = dominantStyle(note.runs.map { ($0.style, $0.text.utf16.count) })
                    var attributes = noteStyle.map { styleAttributes($0, relativeTo: local) } ?? ""
                    if note.style != FloatStyle.footnoteName, document.floatStyles.contains(where: { $0.name == note.style }) {
                        attributes = " style=\"\(escapedAttribute(note.style))\"" + attributes
                    }
                    // Una nota di un solo paragrafo si scrive di seguito; con più paragrafi, ciascuno nel suo `p`.
                    let text = note.paragraphs.count == 1
                        ? written(note.runs, relativeTo: noteStyle)
                        : note.paragraphs.map { paragraph in
                            let content = written(paragraph, relativeTo: noteStyle)
                            return content.isEmpty ? "<p/>" : "<p>\(content)</p>"
                        }.joined()
                    let image = note.image.map(imageElement) ?? ""
                    return text.isEmpty && image.isEmpty ? "<note\(attributes)/>" : "<note\(attributes)>\(image)\(text)</note>"
                case .image(let image):
                    return imageElement(image)
                }
            }.joined()
            out += content.isEmpty ? "/>\n" : ">\(content)</p>\n"
        }
        return out + "</document>\n"
    }

    private static func runs(of paragraph: Paragraph) -> [TextRun] {
        paragraph.inlines.compactMap { inline in
            switch inline {
            case .text(let run): run
            case .floating, .image: nil  // note e immagini non pesano sullo stile del paragrafo
            }
        }
    }

    /// Lo stile da dichiarare una volta sola per un gruppo di tratti: il font e il corpo più usati.
    ///
    /// Le funzioni entrano nello stile comune solo se tutti i tratti con quel font le condividono. Così il
    /// predefinito resta il testo «liscio» e un tratto in maiuscoletto si legge come eccezione, invece di
    /// costringere il testo normale a dichiarare `features=""`; e aggiungere una parola non ribalta il file.
    private static func dominantStyle(_ weighted: [(CharacterStyle, Int)]) -> CharacterStyle? {
        struct Face: Hashable { var fontName: String; var size: Double }
        var totals: [Face: Int] = [:]
        var order: [Face] = []
        for (style, weight) in weighted {
            let face = Face(fontName: style.fontName, size: style.size)
            if totals[face] == nil { order.append(face) }
            totals[face, default: 0] += weight
        }
        // A parità vince il primo incontrato: l'esito non deve dipendere dall'ordine interno del dizionario.
        guard let best = order.enumerated().max(by: { totals[$0.element]! < totals[$1.element]! || (totals[$0.element]! == totals[$1.element]! && $0.offset > $1.offset) })?.element else { return nil }
        let features = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.features))
        // Lo stesso vale per i valori degli assi.
        let variations = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.variations))
        let variable = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.prefersVariableFont))
        let roles = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.fontRole))
        let opticalSizes = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.opticalSize))
        // Il maiuscoletto, come le funzioni: in comune solo se tutti i tratti con quel font lo condividono.
        let smallCaps = Set(weighted.filter { $0.0.fontName == best.fontName && $0.0.size == best.size }.map(\.0.smallCaps))
        // La lingua si dichiara in comune solo se è la stessa per tutto il testo del gruppo.
        let languages = Set((weighted.contains { $0.1 > 0 } ? weighted.filter { $0.1 > 0 } : weighted).map(\.0.language))
        let hyphenation = Set(weighted.map(\.0.hyphenates))
        // Il colore, come la lingua, si dichiara in comune solo se è lo stesso per tutto il gruppo.
        let colors = Set((weighted.contains { $0.1 > 0 } ? weighted.filter { $0.1 > 0 } : weighted).map(\.0.color))
        // La posizione verticale non si dichiara mai in comune: è sempre un'eccezione del tratto.
        return CharacterStyle(fontName: best.fontName, size: best.size, features: features.count == 1 ? features.first! : [],
                              language: languages.count == 1 ? languages.first! : nil, variations: variations.count == 1 ? variations.first! : [],
                              prefersVariableFont: variable == [true], fontRole: roles.count == 1 ? roles.first! : nil,
                              opticalSize: opticalSizes.count == 1 ? opticalSizes.first! : nil,
                              hyphenates: hyphenation != [false], color: colors.count == 1 ? colors.first! : nil,
                              smallCaps: smallCaps.count == 1 ? smallCaps.first! : .off)
    }

    /// Gli attributi che servono per passare dallo stile ereditato a `style`.
    private static func styleAttributes(_ style: CharacterStyle, relativeTo parent: CharacterStyle?) -> String {
        var out = ""
        let fontChanges = style.fontName != parent?.fontName
        if fontChanges { out += " font=\"\(escapedAttribute(style.fontName))\"" }
        if style.size != parent?.size { out += " size=\"\(number(style.size))\"" }
        let inherited = fontChanges ? [] : (parent?.features ?? [])
        if style.features != inherited {
            out += " features=\"\(escapedAttribute(style.features.map(\.description).joined(separator: " ")))\""
        }
        let inheritedAxes = fontChanges ? [] : (parent?.variations ?? [])
        if style.variations != inheritedAxes {
            out += " axes=\"\(escapedAttribute(style.variations.map(\.description).joined(separator: " ")))\""
        }
        let inheritedVariable = fontChanges ? false : (parent?.prefersVariableFont ?? false)
        if style.prefersVariableFont != inheritedVariable { out += " variable=\"\(style.prefersVariableFont ? "on" : "off")\"" }
        if style.fontRole != parent?.fontRole { out += " font-role=\"\(style.fontRole?.rawValue ?? "")\"" }
        if style.opticalSize != parent?.opticalSize { out += " optical=\"\(style.opticalSize?.rawValue ?? "")\"" }
        if style.language != parent?.language { out += " lang=\"\(escapedAttribute(style.language ?? ""))\"" }
        if style.hyphenates != (parent?.hyphenates ?? true) { out += " hyphenation=\"\(style.hyphenates ? "on" : "off")\"" }
        if style.color != parent?.color { out += " color=\"\(style.color ?? "")\"" }
        if style.verticalPosition != parent?.verticalPosition { out += " vertical=\"\(style.verticalPosition?.encoded ?? "")\"" }
        if style.decorations != (parent?.decorations ?? []) { out += " lines=\"\(escapedAttribute(LineDecoration.encode(style.decorations)))\"" }
        if style.graphite != parent?.graphite { out += " graphite=\"\(escapedAttribute(Graphite.encodedChoice(style.graphite)))\"" }
        // Chi legge azzera il maiuscoletto dove cambia il font o si dichiarano le funzioni (così valevano i file di
        // prima, che lo scrivevano fra le funzioni): lì va ripetuto.
        let featuresWritten = out.contains(" features=\"")
        let inheritedSmallCaps = fontChanges || featuresWritten ? .off : (parent?.smallCaps ?? .off)
        if style.smallCaps != inheritedSmallCaps { out += " small-caps=\"\(style.smallCaps.rawValue)\"" }
        return out
    }

    /// Le misure del paragrafo che differiscono da quelle che gli darebbe il suo stile.
    private static func paragraphAttributes(_ style: ParagraphStyle, relativeTo base: ParagraphStyle = ParagraphStyle()) -> String {
        var out = ""
        if style.alignment != base.alignment { out += " align=\"\(style.alignment.rawValue)\"" }
        let pairs: [(String, Double, Double)] = [
            ("first-indent", style.firstLineIndent, base.firstLineIndent), ("left-indent", style.leftIndent, base.leftIndent),
            ("right-indent", style.rightIndent, base.rightIndent), ("space-before", style.spaceBefore, base.spaceBefore),
            ("space-after", style.spaceAfter, base.spaceAfter), ("line-spacing", style.lineSpacing, base.lineSpacing),
            ("line-height", style.lineHeightMultiple, base.lineHeightMultiple)]
        for (name, value, inherited) in pairs where value != inherited {
            out += " \(name)=\"\(number(value))\""
        }
        if style.outlineLevel != base.outlineLevel { out += " outline-level=\"\(style.outlineLevel ?? 0)\"" }
        return out
    }

    /// Un elemento `img`: collegato (con `src`) o incluso (i byte in base64 come contenuto).
    private static func imageElement(_ image: ImageObject) -> String {
        let size = " width=\"\(number(image.width))\" height=\"\(number(image.height))\""
        switch image.source {
        case .linked(let path): return "<img src=\"\(escapedAttribute(path))\"\(size)/>"
        case .embedded(let data): return "<img\(size)>\(data.base64EncodedString())</img>"
        }
    }

    private static func ruleIsWritable(_ rule: TextRule, sheet: StyleSheet) -> Bool {
        guard let style = sheet.style(named: rule.styleName), style.target != .paragraph || rule.target == .paragraph else { return false }
        if case .selection(let id) = rule.target, !sheet.selections.contains(where: { $0.id == id }) { return false }
        if let name = rule.paragraphStyle, sheet.style(named: name)?.target != .paragraph { return false }
        if case .firstAfter(let name) = rule.position, sheet.style(named: name)?.target != .paragraph { return false }
        return true
    }

    /// Un elemento `rule`.
    private static func ruleElement(_ rule: TextRule) -> String {
        var out = "<rule"
        switch rule.target {
        case .selection(let id): out += " find=\"selection\" ref=\"\(id.uuidString)\""
        case .firstLetter: out += " find=\"first-letter\""
        case .firstWords(let count): out += " find=\"first-words\" count=\"\(count)\""
        case .firstSentence: out += " find=\"first-sentence\""
        case .words(.capitals): out += " find=\"words\" pattern=\"capitals\""
        case .words(.romanNumerals): out += " find=\"words\" pattern=\"roman\""
        case .words(.numbers): out += " find=\"words\" pattern=\"numbers\""
        case .words(.listed(let words)): out += " find=\"words\" pattern=\"list\" list=\"\(escapedAttribute(words.joined(separator: " ")))\""
        case .firstLines(let count): out += " find=\"first-lines\" count=\"\(count)\""
        case .lastLine: out += " find=\"last-line\""
        case .paragraph: out += " find=\"paragraph\""
        }
        if let style = rule.paragraphStyle { out += " in=\"\(escapedAttribute(style))\"" }
        switch rule.position {
        case .any: break
        case .firstAfter(let style): out += " after=\"\(escapedAttribute(style))\""
        case .sequenceStart: out += " position=\"sequence-start\""
        case .firstOnPage: out += " position=\"page-start\""
        }
        if let condition = rule.condition {
            out += " if=\"\(condition.property.rawValue)\" compare=\"\(condition.comparison.rawValue)\" value=\"\(number(condition.value))\""
        }
        out += " style=\"\(escapedAttribute(rule.styleName))\""
        if !rule.isEnabled { out += " enabled=\"off\"" }
        return out + "/>\n"
    }

    /// Gli attributi dell'aspetto di uno stile di tabella o di una tabella: solo quelli detti.
    static func tableValueAttributes(_ values: TableValues) -> String {
        var out = ""
        if let rules = values.rules { out += " rules=\"\(rules.rawValue)\"" }
        if let width = values.ruleWidth { out += " rule-width=\"\(CellInsets.number(width))\"" }
        if let padding = values.padding { out += " padding=\"\(padding.text)\"" }
        if let alignment = values.verticalAlignment { out += " valign=\"\(alignment.rawValue)\"" }
        if let background = values.background { out += " background=\"\(background)\"" }
        return out
    }

    /// Gli attributi dell'aspetto proprio di una cella.
    static func cellValueAttributes(_ values: CellValues) -> String {
        var out = ""
        for (key, border) in [("top", values.top), ("right", values.right), ("bottom", values.bottom), ("left", values.left)] {
            if let border { out += " \(key)=\"\(border.text)\"" }
        }
        if let background = values.background { out += " background=\"\(background)\"" }
        if let alignment = values.verticalAlignment { out += " valign=\"\(alignment.rawValue)\"" }
        if let padding = values.padding { out += " padding=\"\(padding.text)\"" }
        return out
    }

    /// Un elemento `float-style`, con i soli valori diversi da quelli predefiniti.
    private static func floatStyleElement(_ style: FloatStyle, knownLists: Set<String>, sheet: StyleSheet) -> String {
        // Ciò che si scrive è la differenza dai valori iniziali della sua collocazione (un'intestazione nasce senza filetto).
        let defaults = style.placement.isRunning ? FloatStyle.running(name: style.name, placement: style.placement) : FloatStyle(name: style.name)
        var out = "<float-style name=\"\(escapedAttribute(style.name))\""
        if style.placement == .documentEnd { out += " placement=\"end\"" }
        if style.placement == .outerMargin { out += " placement=\"margin\"" }
        if style.placement.isRunning {
            out += style.placement == .pageHead ? " placement=\"head\"" : " placement=\"bottom\""
            if style.pages != .all { out += " pages=\"\(style.pages.rawValue)\"" }
            if let distance = style.edgeDistance { out += " edge=\"\(number(distance))\"" }
        }
        if style.placement == .figure {
            out += " placement=\"figure\""
            let positions = (style.ignoresLimits ? "!" : "") + (style.exactlyHere ? "H" : style.positions.map(\.rawValue).joined())
            if positions != "htbp" { out += " positions=\"\(positions)\"" }
            if style.caption != .below { out += " caption=\"\(style.caption.rawValue)\"" }
        }
        if let heading = style.heading { out += " heading=\"\(escapedAttribute(heading))\"" }
        if style.startsOnNewPage { out += " new-page=\"on\"" }
        if let list = style.listName, knownLists.contains(list) { out += " list=\"\(escapedAttribute(list))\"" }
        if style.reference != defaults.reference { out += " reference=\"\(style.reference.rawValue)\"" }
        if style.showsRule != defaults.showsRule { out += " rule=\"\(style.showsRule ? "on" : "off")\"" }
        if let length = style.ruleLength { out += " rule-length=\"\(number(length))\"" }
        if style.spaceAbove != defaults.spaceAbove { out += " space-above=\"\(number(style.spaceAbove))\"" }
        if style.spaceBelow != defaults.spaceBelow { out += " space-below=\"\(number(style.spaceBelow))\"" }
        if style.canSplit != defaults.canSplit { out += " split=\"\(style.canSplit ? "on" : "off")\"" }
        if let content = style.contentStyle, sheet.style(named: content)?.target == .paragraph { out += " content=\"\(escapedAttribute(content))\"" }
        return out + "/>\n"
    }

    /// Una faccia scelta per un ruolo: `face` è la faccia statica, `base` e `axes` l'istanza del font variabile.
    private static func fontRoleElement(_ customization: FontRoleTable.Customization) -> String {
        var out = "<font-role family=\"\(escapedAttribute(customization.family))\" role=\"\(customization.role.rawValue)\""
        if let face = customization.equivalence.staticFace { out += " face=\"\(escapedAttribute(face))\"" }
        if let instance = customization.equivalence.variableInstance {
            out += " base=\"\(escapedAttribute(instance.fontName))\""
            if !instance.variations.isEmpty {
                out += " axes=\"\(escapedAttribute(instance.variations.map(\.description).joined(separator: " ")))\""
            }
            if !instance.prefersVariableFont { out += " variable=\"off\"" }
        }
        return out + "/>\n"
    }

    private static func listDefinitionElement(_ list: ListDefinition) -> String {
        func flag(_ value: Bool) -> String { value ? "on" : "off" }
        var out = "<list name=\"\(escapedAttribute(list.name))\" counter=\"\(escapedAttribute(list.counter.rawValue))\""
        if !list.prefix.isEmpty { out += " prefix=\"\(escapedAttribute(list.prefix))\"" }
        if !list.suffix.isEmpty { out += " suffix=\"\(escapedAttribute(list.suffix))\"" }
        if list.start != 1 { out += " start=\"\(list.start)\"" }
        if let end = list.end { out += " end=\"\(end)\"" }
        switch list.parent {
        case .list(let name)?: out += " parent=\"\(escapedAttribute(name))\""
        case .page?: out += " parent=\"page\""
        case .section(let role)?: out += " parent-section=\"\(escapedAttribute(role))\""
        case nil: break
        }
        if let role = list.numbersSections { out += " numbers-sections=\"\(escapedAttribute(role))\"" }
        if list.continues { out += " continues=\"on\"" }
        if list.showsParent { out += " shows-parent=\"on\"" }
        if list.overflow != .ask { out += " overflow=\"\(list.overflow.rawValue)\"" }
        if let indent = list.textIndent { out += " indent=\"\(number(indent))\"" }
        if let marker = list.markerPosition { out += " marker=\"\(number(marker))\"" }
        return out + "/>\n"
    }

    private static func formulaElement(_ formula: StyleFormula) -> String {
        let operation = formula.operation
        var out = "<formula id=\"\(formula.id.uuidString)\" predicate=\"\(operation.predicate.rawValue)\" property=\"\(operation.property.rawValue)\""
        if let binding = formula.binding { out += " binding=\"\(FormulaCodec.encode(binding))\"" }
        switch operation.argument {
        case .boolean(let enabled): out += " kind=\"boolean\" value=\"\(enabled ? "on" : "off")\""
        case .integer(let count): out += " kind=\"integer\" value=\"\(count)\""
        case .text(let value): out += " kind=\"text\" value=\"\(escapedAttribute(value))\""
        case .styleName(let name): out += " kind=\"style\" value=\"\(escapedAttribute(name ?? ""))\""
        case .pageStart(let spacing):
            let value: String
            switch spacing { case .disabled: value = "off"; case .distance(let points): value = number(points) }
            out += " kind=\"page-start\" value=\"\(value)\""
        case .face(let name): out += " kind=\"face\" value=\"\(escapedAttribute(name))\""
        case .family(let name): out += " kind=\"family\" value=\"\(escapedAttribute(name))\""
        case .color(let color): out += " kind=\"color\" value=\"\(color ?? "")\""
        case .smallCaps(let mode): out += " kind=\"smallCaps\" value=\"\(mode.rawValue)\""
        case .hyphenates(let enabled): out += " kind=\"hyphenates\" value=\"\(enabled ? "on" : "off")\""
        case .font(let role): out += " kind=\"font\" value=\"\(role.rawValue)\""
        case .length(let amount, let unit): out += " kind=\"length\" value=\"\(number(amount))\" unit=\"\(unit.rawValue)\""
        case .alignment(let alignment): out += " kind=\"alignment\" value=\"\(alignment.rawValue)\""
        case .language(let language): out += " kind=\"language\" value=\"\(escapedAttribute(language ?? ""))\""
        }
        switch formula.when.position {
        case .any: break
        case .sequenceStart: out += " when=\"sequence-start\""
        case .firstOnPage: out += " when=\"page-start\""
        case .firstAfter(let name): out += " when=\"after\" after-style=\"\(escapedAttribute(name))\""
        }
        if let condition = formula.when.measurement {
            out += " if=\"\(condition.property.rawValue)\" compare=\"\(condition.comparison.rawValue)\" threshold=\"\(number(condition.value))\""
        }
        switch formula.target {
        case .paragraph: break
        case .firstLetter: out += " find=\"first-letter\""
        case .firstWords(let count): out += " find=\"first-words\" count=\"\(count)\""
        case .firstSentence: out += " find=\"first-sentence\""
        case .firstLines(let count): out += " find=\"first-lines\" count=\"\(count)\""
        case .lastLine: out += " find=\"last-line\""
        case .selection(let id): out += " find=\"selection\" selection=\"\(id.uuidString)\""
        case .words(let pattern):
            out += " find=\"words\""
            switch pattern {
            case .capitals: out += " pattern=\"capitals\""
            case .romanNumerals: out += " pattern=\"roman\""
            case .numbers: out += " pattern=\"numbers\""
            case .listed(let words): out += " pattern=\"list\" words=\"\(escapedAttribute(words.joined(separator: " ")) )\""
            }
        }
        return out + "/>\n"
    }

    /// Gli attributi di una definizione di stile: solo i valori che lo stile fissa.
    private static func styleValueAttributes(_ values: StyleValues) -> String {
        var out = ""
        func flag(_ value: Bool) -> String { value ? "on" : "off" }
        if let next = values.nextStyle { out += " next-style=\"\(escapedAttribute(next))\"" }
        if let fontName = values.fontName { out += " font=\"\(escapedAttribute(fontName))\"" }
        if let family = values.family { out += " family=\"\(escapedAttribute(family))\"" }
        if let italic = values.italic { out += " italic=\"\(flag(italic))\"" }
        if let bold = values.bold { out += " bold=\"\(flag(bold))\"" }
        if let size = values.size { out += " size=\"\(number(size))\"" }
        if let features = values.features { out += " features=\"\(escapedAttribute(features.map(\.description).joined(separator: " ")))\"" }
        if let variations = values.variations { out += " axes=\"\(escapedAttribute(variations.map(\.description).joined(separator: " ")))\"" }
        if let opticalSize = values.opticalSize { out += " optical=\"\(opticalSize)\"" }
        if let language = values.language { out += " lang=\"\(escapedAttribute(language))\"" }
        if let hyphenates = values.hyphenates { out += " hyphenation=\"\(flag(hyphenates))\"" }
        if let color = values.color { out += " color=\"\(color)\"" }
        if let vertical = values.verticalPosition { out += " vertical=\"\(vertical)\"" }
        if let lines = values.decorations { out += " lines=\"\(escapedAttribute(lines))\"" }
        if let graphite = values.graphite { out += " graphite=\"\(escapedAttribute(graphite))\"" }
        if let smallCaps = values.smallCaps { out += " small-caps=\"\(smallCaps.rawValue)\"" }
        if let alignment = values.alignment { out += " align=\"\(alignment.rawValue)\"" }
        let measures: [(String, Double?)] = [
            ("first-indent", values.firstLineIndent), ("left-indent", values.leftIndent), ("right-indent", values.rightIndent),
            ("space-before", values.spaceBefore), ("space-after", values.spaceAfter), ("line-spacing", values.lineSpacing),
            ("line-height", values.lineHeightMultiple)]
        for (name, value) in measures { if let value { out += " \(name)=\"\(number(value))\"" } }
        if let list = values.listName { out += " in-list=\"\(escapedAttribute(list))\"" }
        if let role = values.opensSection { out += " opens-section=\"\(escapedAttribute(role))\"" }
        if let level = values.outlineLevel { out += " outline-level=\"\(level)\"" }
        if let distance = values.openingDistance { out += " opening-distance=\"\(number(distance))\"" }
        switch values.pageStartSpacing {
        case .distance(let points): out += " page-start-spacing=\"\(number(points))\""
        case .disabled: out += " page-start-spacing=\"off\""
        case nil: break
        }
        out += values.keeping.xmlAttributes
        return out
    }

    private static func escapedText(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\u{2028}": out += "<br/>"
            case "\r": out += "&#13;"
            case "\t", "\n": out.unicodeScalars.append(scalar)
            // XML 1.0 non ammette gli altri caratteri di controllo, né U+FFFE e U+FFFF.
            case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Come il testo, ma tabulazione, a capo e U+2028 restano tali: nel valore di un attributo XML li ridurrebbe a spazi,
    /// e due nomi diversi ne diventerebbero uno.
    private static func escapedAttribute(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\t": out += "&#9;"
            case "\n": out += "&#10;"
            case "\u{2028}": out.unicodeScalars.append(scalar)
            case "\"": out += "&quot;"
            default: out += escapedText(String(scalar))
            }
        }
        return out
    }

    /// Numero con al più quattro decimali, senza zeri finali e sempre con il punto decimale.
    static func number(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// Il tipo di un campo: `kind` e, per quelli di una sezione, `role`.
    private static func fieldAttributes(_ field: Field) -> String {
        switch field {
        case .page: " kind=\"page\""
        case .pageCount: " kind=\"pages\""
        case .sectionTitle(let role): " kind=\"section-title\" role=\"\(escapedAttribute(role))\""
        case .sectionNumber(let role): " kind=\"section-number\" role=\"\(escapedAttribute(role))\""
        case .formula(let formula): " kind=\"formula\" expression=\"\(formula.rawValue)\""
        }
    }

    /// Gli attributi di una pagina: formato, margini, pagine affacciate.
    private static func pageAttributes(_ page: PageSetup) -> String {
        var out = " width=\"\(millimetres(page.paperSize.width))\" height=\"\(millimetres(page.paperSize.height))\""
        out += " top=\"\(millimetres(page.top))\" bottom=\"\(millimetres(page.bottom))\""
        out += " left=\"\(millimetres(page.left))\" right=\"\(millimetres(page.right))\""
        if page.facing { out += " facing=\"on\"" }
        return out
    }

    private static func millimetres(_ points: CGFloat) -> String { number(PageSetup.millimetres(fromPoints: points)) + "mm" }

    // MARK: Lettura

    public static func document(from data: Data) throws -> Document {
        let reader = Reader()
        // Un file scritto prima del livello di paragrafazione non ne contiene nessuno: solo lì il nome «Titolo N» lo dice.
        reader.levelsFromNames = data.range(of: Data("outline-level=".utf8)) == nil && data.range(of: Data("property=\"outlineLevel\"".utf8)) == nil
        let parser = XMLParser(data: data)
        parser.delegate = reader
        let succeeded = parser.parse()
        if let error = reader.error { throw error }
        guard succeeded else {
            throw DocumentFormatError.malformed(line: parser.lineNumber, detail: parser.parserError?.localizedDescription ?? "XML non valido")
        }
        guard reader.sawDocument else { throw DocumentFormatError.malformed(line: 1, detail: "manca l'elemento <document>") }
        var document = reader.settings
        if let problem = document.styles.formulaReferenceProblem() { throw DocumentFormatError.malformed(line: 1, detail: problem) }
        do { try ReusableFormulaLibrary(definitions: document.styles.reusableFormulas).validate() }
        catch { throw DocumentFormatError.malformed(line: 1, detail: "Formule riutilizzabili non valide: \(error)") }
        if document.sourceVersion >= 4, reader.documentStyle.fontName != nil, reader.documentStyle.size != nil {
            document.formulaBase = try reader.documentStyle.resolved(line: 1)
        }
        document.setFlatParagraphs(reader.flatParagraphs)
        return document
    }

    public static func document(from string: String) throws -> Document {
        try document(from: Data(string.utf8))
    }

    /// Stile in costruzione: finché nessun livello dichiara un font, il font non c'è.
    private struct PartialStyle {
        var fontName: String?
        var size: Double?
        var features: [FeatureSetting] = []
        var variations: [AxisValue] = []
        var prefersVariableFont = false
        var fontRole: FontRole?
        var opticalSize: StaticOpticalSize?
        var language: String?
        var hyphenates = true
        var color: String?
        var verticalPosition: VerticalPosition?
        var decorations: [LineDecoration] = []
        var graphite: String?
        var smallCaps: SmallCaps = .off

        /// Sopra questo stile parziale, i valori di uno stile con un nome.
        func applying(_ values: StyleValues) -> PartialStyle {
            var fields = CharacterFields(fontName: fontName, size: size)
            if !values.resolutionSteps.isEmpty { fields.fontRole = fontRole }
            fields.features = features
            fields.variations = variations
            fields.prefersVariableFont = prefersVariableFont
            fields.opticalSize = opticalSize
            fields.language = language
            fields.hyphenates = hyphenates
            fields.color = color
            fields.verticalPosition = verticalPosition
            fields.decorations = decorations
            fields.graphite = graphite
            fields.smallCaps = smallCaps
            values.apply(to: &fields)
            var result = self
            if !values.resolutionSteps.isEmpty { result.fontRole = fields.fontRole }
            result.fontName = fields.fontName
            result.size = fields.size
            result.features = fields.features
            result.variations = fields.variations
            result.prefersVariableFont = fields.prefersVariableFont
            result.opticalSize = fields.opticalSize
            result.language = fields.language
            result.hyphenates = fields.hyphenates
            result.color = fields.color
            result.verticalPosition = fields.verticalPosition
            result.decorations = fields.decorations
            result.graphite = fields.graphite
            result.smallCaps = fields.smallCaps
            return result
        }

        func applying(_ attributes: [String: String], line: Int) throws -> PartialStyle {
            var result = self
            if let hyphenation = attributes["hyphenation"] {
                guard ["on", "off"].contains(hyphenation) else { throw DocumentFormatError.invalidValue(line: line, attribute: "hyphenation", value: hyphenation) }
                result.hyphenates = hyphenation == "on"
            }
            if let font = attributes["font"] {
                result.fontName = font
                result.features = []
                result.variations = []
                result.prefersVariableFont = false
                result.opticalSize = nil
                result.smallCaps = .off
            }
            if let variable = attributes["variable"] {
                guard ["on", "off"].contains(variable) else { throw DocumentFormatError.invalidValue(line: line, attribute: "variable", value: variable) }
                result.prefersVariableFont = variable == "on"
            }
            if let role = attributes["font-role"] {
                guard role.isEmpty || FontRole(rawValue: role) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "font-role", value: role)
                }
                result.fontRole = FontRole(rawValue: role)
            }
            if let optical = attributes["optical"] {
                guard optical.isEmpty || StaticOpticalSize(rawValue: optical) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "optical", value: optical)
                }
                result.opticalSize = StaticOpticalSize(rawValue: optical)
            }
            if let axes = attributes["axes"] {
                result.variations = try axes.split(whereSeparator: \.isWhitespace).map { token in
                    guard let variation = parseVariation(String(token)) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "axes", value: String(token))
                    }
                    return variation
                }
            }
            if let size = attributes["size"] {
                guard let value = DocumentFormat.finiteNumber(size), value > 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "size", value: size) }
                result.size = value
            }
            if let features = attributes["features"] {
                result.features = try features.split(whereSeparator: \.isWhitespace).map { token in
                    guard let setting = parseFeature(String(token)) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "features", value: String(token))
                    }
                    return setting
                }
                // Nei file di prima il maiuscoletto stava fra le funzioni: diventa la scelta tipografica.
                let split = SmallCaps.split(result.features)
                result.features = split.rest
                result.smallCaps = split.smallCaps
            }
            if let smallCaps = attributes["small-caps"] {
                guard let value = SmallCaps(rawValue: smallCaps) else { throw DocumentFormatError.invalidValue(line: line, attribute: "small-caps", value: smallCaps) }
                result.smallCaps = value
            }
            if let language = attributes["lang"] { result.language = language.isEmpty ? nil : language }
            if let color = attributes["color"] {
                guard color.isEmpty || TextStyling.color(hex: color) != nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "color", value: color) }
                result.color = color.isEmpty ? nil : color.lowercased()
            }
            if let vertical = attributes["vertical"] {
                guard vertical.isEmpty || VerticalPosition(encoded: vertical) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "vertical", value: vertical)
                }
                result.verticalPosition = VerticalPosition(encoded: vertical)
            }
            if let lines = attributes["lines"] {
                guard let decorations = LineDecoration.decode(lines) else { throw DocumentFormatError.invalidValue(line: line, attribute: "lines", value: lines) }
                result.decorations = decorations
            }
            if let graphite = attributes["graphite"] {
                guard let choice = Graphite.choice(fromEncoded: graphite) else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "graphite", value: graphite)
                }
                result.graphite = choice
            }
            return result
        }

        func resolved(line: Int) throws -> CharacterStyle {
            guard let fontName else { throw DocumentFormatError.missingAttribute(line: line, attribute: "font") }
            guard let size else { throw DocumentFormatError.missingAttribute(line: line, attribute: "size") }
            return CharacterStyle(fontName: fontName, size: size, features: features, language: language, variations: variations,
                                  prefersVariableFont: prefersVariableFont, fontRole: fontRole, opticalSize: opticalSize,
                                  hyphenates: hyphenates, color: color,
                                  verticalPosition: verticalPosition, decorations: decorations, graphite: graphite, smallCaps: smallCaps)
        }
    }

    static func parseFeature(_ token: String) -> FeatureSetting? {
        if let slash = token.firstIndex(of: "/") {
            guard let type = Int(token[..<slash]), let selector = Int(token[token.index(after: slash)...]) else { return nil }
            return .aat(type: type, selector: selector)
        }
        if let equals = token.firstIndex(of: "=") {
            let tag = String(token[..<equals])
            guard tag.utf8.count == 4, let value = Int(token[token.index(after: equals)...]) else { return nil }
            return .openType(tag: tag, value: value)
        }
        return nil
    }

    /// Un valore di asse: `tag=valore`, con un tag di quattro caratteri e un numero decimale.
    static func parseVariation(_ token: String) -> AxisValue? {
        guard let equals = token.firstIndex(of: "=") else { return nil }
        let tag = String(token[..<equals])
        guard tag.utf8.count == 4, let value = Double(token[token.index(after: equals)...]), value.isFinite else { return nil }
        return AxisValue(tag: tag, value: value)
    }

    /// Un numero decimale finito: `inf` e `nan`, che `Double` accetta, non sono misure.
    static func finiteNumber<S: StringProtocol>(_ text: S) -> Double? {
        Double(text).flatMap { $0.isFinite ? $0 : nil }
    }

    /// Misura con unità facoltativa (`pt` se manca), convertita in punti; finita anche dopo la conversione.
    static func parseLength(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var points: CGFloat?
        if let (unit, toPoints) = ([("mm", { PageSetup.points(fromMillimetres: $0) }), ("cm", { PageSetup.points(fromMillimetres: $0 * 10) }),
                                    ("in", { CGFloat($0 * 72) }), ("pt", { CGFloat($0) })] as [(String, (Double) -> CGFloat)])
            .first(where: { trimmed.hasSuffix($0.0) }) {
            points = finiteNumber(trimmed.dropLast(unit.count).trimmingCharacters(in: .whitespaces)).map(toPoints)
        } else {
            points = finiteNumber(trimmed).map { CGFloat($0) }
        }
        return points.flatMap { $0.isFinite ? $0 : nil }
    }

    private final class Reader: NSObject, XMLParserDelegate {
        /// Vero per i file precedenti al livello di paragrafazione: gli stili «Titolo N» ricevono il livello N.
        var levelsFromNames = false
        var error: DocumentFormatError?
        var sawDocument = false
        var settings = Document()
        var pageSetup: PageSetup {
            get { settings.pageSetup }
            set { settings.pageSetup = newValue }
        }
        var paragraphs: [FlatParagraph] = []
        /// Dopo la chiusura di una sezione: il primo paragrafo o la prima tabella che segue torna alla sezione esterna.
        private var afterClosedSection = false
        /// Le posizioni nella fila dei paragrafi che tornano, con l'identità della sezione in cui tornano.
        private var returns: [(index: Int, target: String)] = []

        private func markReturn(parent: String) {
            guard afterClosedSection else { return }
            afterClosedSection = false
            returns.append((paragraphs.count, parent == "section" ? openSections.last?.mark.id ?? "" : ""))
        }

        /// La fila dei paragrafi letti, con i segni dei ritorni.
        var flatParagraphs: [FlatParagraph] {
            var result = paragraphs
            for (index, target) in returns where index < result.count { result[index].sectionReturn = target }
            return result
        }

        /// Le sezioni aperte, dalla più esterna: il loro segno, se il titolo e una sezione interna sono già arrivati.
        private var openSections: [(mark: SectionMark, sawTitle: Bool, sawInner: Bool, line: Int)] = []
        private var sectionIDs: Set<String> = []
        private var sawSection = false
        private var inTitle = false
        private var titleHasParagraph = false
        /// La tabella in lettura: identità, righe d'intestazione, riga e colonna in corso; se la cella ha già un paragrafo.
        private var table: (id: String, headerRows: Int, row: Int, column: Int)?
        /// Lo stile e l'aspetto della tabella in lettura, e l'aspetto della cella in lettura.
        private var tableStyle: String?
        private var tableValues = TableValues()
        private var cellValues = CellValues()
        private var sawTableStyles = false
        /// Lo stile di flottante della tabella in lettura; se si è nella sua didascalia, e se questa ha già un paragrafo.
        private var tableFloat: String?
        /// Le posizioni (riga, colonna) coperte dalle celle unite della tabella in lettura, e le colonne e righe che copre
        /// la cella in lettura.
        private var coveredCells: Set<[Int]> = []
        private var cellSpans = (columns: 1, rows: 1)
        private var inCaption = false
        private var captionHasParagraph = false
        private var tableLine = 0
        private var rowLine = 0
        private var inCell = false
        private var cellHasParagraph = false
        private var tableIDs: Set<String> = []

        private var stack: [String] = []
        var documentStyle = PartialStyle()
        private var paragraphStyle = PartialStyle()
        private var paragraph: Paragraph?
        private var paragraphLine = 0
        private var runStyle: PartialStyle?
        private var runWordStyle: String?
        private var runCharacterStyle: String?
        private var runRuleExceptions: Set<InspectorProperty> = []
        private var styleLines: [String: Int] = [:]
        private var listLines: [String: Int] = [:]
        private var notesListName: String?
        private var pageNumberingName: String?
        private var sawFloatStyles = false
        private var sawRules = false
        private var sawReusableFormulas = false
        /// L'immagine in lettura e i suoi byte in base64.
        private var imageInProgress: (src: String?, width: Double, height: Double, line: Int)?
        private var imageText = ""
        private var floatStyleLines: [String: Int] = [:]
        private var notesLine = 0
        private var runStartLine = 0
        private var note: FloatingObject?
        private var noteStyle = PartialStyle()
        private var noteLine = 0
        /// Vero se la nota in lettura ha i suoi paragrafi in elementi `p`, e se uno di essi è aperto.
        private var noteUsesParagraphs = false
        private var noteParagraphOpen = false

        /// Il segno della cella in lettura, se si è dentro una cella.
        private var currentCell: CellMark? {
            if inCaption, let table {
                return CellMark(table: table.id, row: -1, column: 0, headerRows: table.headerRows, style: tableStyle, tableValues: tableValues,
                                floatStyle: tableFloat)
            }
            guard inCell, let table else { return nil }
            return CellMark(table: table.id, row: table.row, column: table.column, headerRows: table.headerRows,
                            style: tableStyle, tableValues: tableValues, cellValues: cellValues, floatStyle: tableFloat)
                .spanning(columns: cellSpans.columns, rows: cellSpans.rows)
        }

        static let tableValueNames: Set<String> = ["rules", "rule-width", "padding", "valign", "background"]

        private func length(_ text: String) -> Double? { DocumentFormat.parseLength(text).map(Double.init) }

        private func readBackground(_ attributes: [String: String], line: Int) throws -> String? {
            guard let text = attributes["background"] else { return nil }
            guard text.isEmpty || TextStyling.color(hex: text) != nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "background", value: text) }
            return text.lowercased()
        }

        private func readPadding(_ attributes: [String: String], line: Int) throws -> CellInsets? {
            guard let text = attributes["padding"] else { return nil }
            guard let padding = CellInsets(text: text, length: length) else { throw DocumentFormatError.invalidValue(line: line, attribute: "padding", value: text) }
            return padding
        }

        private func readAlignment(_ attributes: [String: String], line: Int) throws -> CellVerticalAlignment? {
            guard let text = attributes["valign"] else { return nil }
            guard let alignment = CellVerticalAlignment(rawValue: text) else { throw DocumentFormatError.invalidValue(line: line, attribute: "valign", value: text) }
            return alignment
        }

        /// L'aspetto di uno stile di tabella o di una tabella.
        private func readTableValues(_ attributes: [String: String], line: Int) throws -> TableValues {
            var values = TableValues()
            if let text = attributes["rules"] {
                guard let rules = TableRuleScheme(rawValue: text) else { throw DocumentFormatError.invalidValue(line: line, attribute: "rules", value: text) }
                values.rules = rules
            }
            if let text = attributes["rule-width"] {
                guard let width = length(text), width > 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "rule-width", value: text) }
                values.ruleWidth = width
            }
            values.padding = try readPadding(attributes, line: line)
            values.verticalAlignment = try readAlignment(attributes, line: line)
            values.background = try readBackground(attributes, line: line)
            return values
        }

        /// L'aspetto proprio di una cella.
        private func readCellValues(_ attributes: [String: String], line: Int) throws -> CellValues {
            var values = CellValues()
            for key in ["top", "right", "bottom", "left"] {
                guard let text = attributes[key] else { continue }
                guard let border = CellBorder(text: text, length: length) else { throw DocumentFormatError.invalidValue(line: line, attribute: key, value: text) }
                switch key {
                case "top": values.top = border
                case "right": values.right = border
                case "bottom": values.bottom = border
                default: values.left = border
                }
            }
            values.background = try readBackground(attributes, line: line)
            values.verticalAlignment = try readAlignment(attributes, line: line)
            values.padding = try readPadding(attributes, line: line)
            return values
        }

        private func fail(_ error: DocumentFormatError, _ parser: XMLParser) {
            if self.error == nil { self.error = error }
            parser.abortParsing()
        }

        private func check(_ attributes: [String: String], allowed: Set<String>, element: String, _ parser: XMLParser) -> Bool {
            if let unknown = attributes.keys.sorted().first(where: { !allowed.contains($0) }) {
                fail(.unknownAttribute(line: parser.lineNumber, element: element, attribute: unknown), parser)
                return false
            }
            return true
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let line = parser.lineNumber
            let parent = stack.last
            stack.append(name)
            do {
                switch (name, parent) {
                case ("document", nil):
                    guard check(attributes, allowed: ["version", "font", "size", "features", "axes", "small-caps", "variable", "font-role", "optical", "lang", "hyphenation", "trak", "opbd", "expansion", "notes", "page-numbering"],
                                element: name, parser) else { return }
                    func flag(_ attribute: String) throws -> Bool? {
                        guard let value = attributes[attribute] else { return nil }
                        guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: value) }
                        return value == "on"
                    }
                    settings.appliesFontTracking = try flag("trak") ?? true
                    settings.usesOpticalMargins = try flag("opbd") ?? true
                    if let value = attributes["expansion"] {
                        guard let percent = Double(value), percent.isFinite, (0...3).contains(percent) else {
                            throw DocumentFormatError.invalidValue(line: line, attribute: "expansion", value: value)
                        }
                        settings.glyphExpansionLimit = percent / 100
                    }
                    settings.hyphenates = try flag("hyphenation") ?? true
                    settings.language = attributes["lang"].flatMap { $0.isEmpty ? nil : $0 }
                    guard let version = attributes["version"].flatMap(Int.init) else { throw DocumentFormatError.missingAttribute(line: line, attribute: "version") }
                    guard version <= DocumentFormat.version else { throw DocumentFormatError.newerVersion(version) }
                    settings.sourceVersion = version
                    if version >= 8 { levelsFromNames = false }
                    sawDocument = true
                    documentStyle = try PartialStyle().applying(attributes, line: line)
                    // La lingua del documento è un'impostazione, non uno stile: il testo che non ne dichiara una resta senza.
                    documentStyle.language = nil
                    // Sul documento `hyphenation` è l'interruttore generale (letto sopra), non una proprietà delle parole.
                    documentStyle.hyphenates = true
                    notesListName = attributes["notes"]
                    pageNumberingName = attributes["page-numbering"]
                    notesLine = line

                case ("page", "document"):
                    let names = ["width", "height", "top", "bottom", "left", "right"]
                    guard check(attributes, allowed: Set(names + ["facing"]), element: name, parser) else { return }
                    pageSetup = try readPageSetup(attributes, base: pageSetup, line: line)

                case ("page-types", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, settings.pageTypes.isEmpty else {
                        throw DocumentFormatError.malformed(line: line, detail: "<page-types> va prima dei paragrafi, e una volta sola")
                    }

                case ("page-type", "page-types"):
                    let names = ["width", "height", "top", "bottom", "left", "right"]
                    guard check(attributes, allowed: Set(names + ["facing", "name"]), element: name, parser) else { return }
                    guard let typeName = attributes["name"], !typeName.isEmpty, typeName != PageType.defaultName, !typeName.contains("\n"),
                          !settings.pageTypes.contains(where: { $0.name == typeName }) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "name", value: attributes["name"] ?? "")
                    }
                    // Le misure che mancano vengono dalla pagina predefinita.
                    settings.pageTypes.append(PageType(name: typeName, setup: try readPageSetup(attributes, base: pageSetup, line: line)))

                case ("lists", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, settings.lists.isEmpty, settings.styles.isEmpty else {
                        throw DocumentFormatError.malformed(line: line, detail: "<lists> va prima degli stili e dei paragrafi, e una volta sola")
                    }

                case ("list", "lists"):
                    try readList(attributes, line: line, parser)

                case ("styles", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, settings.styles.isEmpty else {
                        throw DocumentFormatError.malformed(line: line, detail: "<styles> va prima dei paragrafi, e una volta sola")
                    }

                case ("style", "styles"):
                    try readStyle(attributes, line: line, parser)

                case ("float-styles", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, !sawFloatStyles else {
                        throw DocumentFormatError.malformed(line: line, detail: "<float-styles> va prima dei paragrafi, e una volta sola")
                    }
                    sawFloatStyles = true

                case ("float-style", "float-styles"):
                    try readFloatStyle(attributes, line: line, parser)

                case ("formula", "style") where settings.sourceVersion >= 4:
                    try readFormula(attributes, line: line, parser)

                case ("rules", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, !sawRules else {
                        throw DocumentFormatError.malformed(line: line, detail: "<rules> va prima dei paragrafi, e una volta sola")
                    }
                    sawRules = true

                case ("selection", "rules") where settings.sourceVersion >= 3:
                    guard check(attributes, allowed: ["id", "name", "source", "index"], element: name, parser) else { return }
                    guard let id = attributes["id"].flatMap(UUID.init(uuidString:)),
                          let label = attributes["name"], !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let source = attributes["source"].flatMap(WordSelection.Source.init(rawValue:)),
                          let index = attributes["index"].flatMap(Int.init), index > 0,
                          !settings.styles.selections.contains(where: { $0.id == id || $0.name == label }) else {
                        throw DocumentFormatError.malformed(line: line, detail: "Definizione di selezione non valida o duplicata")
                    }
                    settings.styles.selections.append(WordSelection(id: id, name: label, source: source, index: index))

                case ("reusable-formulas", "rules") where settings.sourceVersion >= 10:
                    guard check(attributes, allowed: ["encoding", "data"], element: name, parser) else { return }
                    guard !sawReusableFormulas, attributes["encoding"] == "json-v1", let encoded = attributes["data"],
                          let data = Data(base64Encoded: encoded) else {
                        throw DocumentFormatError.malformed(line: line, detail: "Definizioni di formule riutilizzabili non valide")
                    }
                    let decoder = JSONDecoder()
                    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
                    do { settings.styles.reusableFormulas = try decoder.decode([ReusableFormula].self, from: data) }
                    catch { throw DocumentFormatError.malformed(line: line, detail: "Definizioni di formule riutilizzabili non leggibili") }
                    sawReusableFormulas = true

                case ("rule", "rules"):
                    try readRule(attributes, line: line, parser)

                case ("section", "document"), ("section", "section"):
                    guard check(attributes, allowed: ["id", "role", "start", "page-type", "even-page-type", "first-page-type", "page-numbering"], element: name, parser) else { return }
                    if let list = attributes["page-numbering"], !settings.lists.contains(where: { $0.name == list }) {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "page-numbering", value: list)
                    }
                    if parent == "section" {
                        guard openSections.last?.sawTitle == true else { throw DocumentFormatError.malformed(line: line, detail: "una sezione comincia con il suo <title>") }
                        openSections[openSections.count - 1].sawInner = true
                    }
                    let id = attributes["id"] ?? Section.newID()
                    guard !id.isEmpty, !id.contains("\n"), sectionIDs.insert(id).inserted else { throw DocumentFormatError.invalidValue(line: line, attribute: "id", value: id) }
                    let role = attributes["role"] ?? Section.Role.section
                    guard !role.isEmpty else { throw DocumentFormatError.invalidValue(line: line, attribute: "role", value: role) }
                    guard let start = SectionStart(rawValue: attributes["start"] ?? SectionStart.continuous.rawValue) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "start", value: attributes["start"] ?? "")
                    }
                    sawSection = true
                    afterClosedSection = false
                    let types = SectionPageTypes(pages: try pageTypeName(attributes["page-type"], attribute: "page-type", line: line),
                                                 evenPages: try pageTypeName(attributes["even-page-type"], attribute: "even-page-type", line: line),
                                                 firstPage: try pageTypeName(attributes["first-page-type"], attribute: "first-page-type", line: line))
                    openSections.append((SectionMark(id: id, role: role, depth: openSections.count + 1, start: start, pageTypes: types,
                                                     pageNumbering: attributes["page-numbering"]), false, false, line))

                case ("font-roles", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, settings.fontRoles.isEmpty else {
                        throw DocumentFormatError.malformed(line: line, detail: "<font-roles> va prima dei paragrafi, e una volta sola")
                    }

                case ("font-role", "font-roles"):
                    guard check(attributes, allowed: ["family", "role", "face", "base", "axes", "variable"], element: name, parser) else { return }
                    guard let family = attributes["family"], !family.isEmpty else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "family", value: attributes["family"] ?? "")
                    }
                    guard let role = attributes["role"].flatMap(FontRole.init(rawValue:)) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "role", value: attributes["role"] ?? "")
                    }
                    var equivalence = FontRoleEquivalence(staticFace: attributes["face"].flatMap { $0.isEmpty ? nil : $0 })
                    if let base = attributes["base"], !base.isEmpty {
                        var variations: [AxisValue] = []
                        for token in (attributes["axes"] ?? "").split(separator: " ") {
                            guard let value = DocumentFormat.parseVariation(String(token)) else {
                                throw DocumentFormatError.invalidValue(line: line, attribute: "axes", value: attributes["axes"] ?? "")
                            }
                            variations.append(value)
                        }
                        let prefersVariable: Bool
                        switch attributes["variable"] {
                        case nil, "on": prefersVariable = true
                        case "off": prefersVariable = false
                        default: throw DocumentFormatError.invalidValue(line: line, attribute: "variable", value: attributes["variable"] ?? "")
                        }
                        equivalence.variableInstance = VariableFontInstance(fontName: base, variations: variations, prefersVariableFont: prefersVariable)
                    } else if attributes["axes"] != nil || attributes["variable"] != nil {
                        throw DocumentFormatError.malformed(line: line, detail: "axes e variable vanno con base")
                    }
                    guard settings.fontRoles.customization(family: family, role: role) == nil else {
                        throw DocumentFormatError.malformed(line: line, detail: "il ruolo \(role.rawValue) di \(family) è già dato")
                    }
                    settings.fontRoles.customize(family: family, role: role, to: equivalence)

                case ("table-styles", "document"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard paragraphs.isEmpty, paragraph == nil, !sawTableStyles else {
                        throw DocumentFormatError.malformed(line: line, detail: "<table-styles> va prima dei paragrafi, e una volta sola")
                    }
                    sawTableStyles = true
                    settings.tableStyles = []

                case ("table-style", "table-styles"):
                    guard check(attributes, allowed: Self.tableValueNames.union(["name"]), element: name, parser) else { return }
                    guard let styleName = attributes["name"], !styleName.isEmpty, !styleName.contains("\n"),
                          !settings.tableStyles.contains(where: { $0.name == styleName }) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "name", value: attributes["name"] ?? "")
                    }
                    settings.tableStyles.append(TableStyle(name: styleName, values: try readTableValues(attributes, line: line)))

                case ("table", "document"), ("table", "section"):
                    guard check(attributes, allowed: Self.tableValueNames.union(["id", "header-rows", "style", "float"]), element: name, parser) else { return }
                    if let float = attributes["float"], !settings.floatStyles.contains(where: { $0.name == float }) {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "float", value: float)
                    }
                    tableFloat = attributes["float"]
                    if let style = attributes["style"], !settings.tableStyles.contains(where: { $0.name == style }) {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "style", value: style)
                    }
                    tableStyle = attributes["style"]
                    tableValues = try readTableValues(attributes, line: line)
                    if parent == "section" {
                        guard openSections.last?.sawTitle == true else {
                            throw DocumentFormatError.malformed(line: line, detail: "in una sezione una tabella va dopo il titolo")
                        }
                    }
                    markReturn(parent: parent ?? "")
                    let id = attributes["id"] ?? Table.newID()
                    guard !id.isEmpty, !id.contains("\n"), tableIDs.insert(id).inserted else { throw DocumentFormatError.invalidValue(line: line, attribute: "id", value: id) }
                    var header = 0
                    if let text = attributes["header-rows"] {
                        guard let value = Int(text), value >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "header-rows", value: text) }
                        header = value
                    }
                    table = (id, header, -1, -1)
                    tableLine = line

                case ("caption", "table"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard table?.row == -1, !captionHasParagraph else {
                        throw DocumentFormatError.malformed(line: line, detail: "la didascalia di una tabella va prima delle righe, e una volta sola")
                    }
                    inCaption = true

                case ("row", "table"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    table?.row += 1
                    table?.column = -1
                    rowLine = line

                case ("cell", "row"):
                    guard check(attributes, allowed: ["top", "right", "bottom", "left", "background", "valign", "padding", "colspan", "rowspan"],
                                element: name, parser) else { return }
                    cellValues = try readCellValues(attributes, line: line)
                    var spans = (columns: 1, rows: 1)
                    for (key, path) in [("colspan", 0), ("rowspan", 1)] {
                        guard let text = attributes[key] else { continue }
                        guard let value = Int(text), value >= 1, value <= 1000 else { throw DocumentFormatError.invalidValue(line: line, attribute: key, value: text) }
                        if path == 0 { spans.columns = value } else { spans.rows = value }
                    }
                    cellSpans = spans
                    // La prima colonna libera: quelle coperte da una cella unita si saltano.
                    table?.column += 1
                    if let current = table {
                        var column = current.column
                        while coveredCells.contains([current.row, column]) { column += 1 }
                        table?.column = column
                        for r in current.row..<(current.row + cellSpans.rows) {
                            for c in column..<(column + cellSpans.columns) where r != current.row || c != column {
                                guard coveredCells.insert([r, c]).inserted else {
                                    throw DocumentFormatError.malformed(line: line, detail: "due celle unite si sovrappongono")
                                }
                            }
                        }
                    }
                    inCell = true
                    cellHasParagraph = false

                case ("title", "section"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    guard openSections.last?.sawTitle == false else { throw DocumentFormatError.malformed(line: line, detail: "una sezione ha un solo <title>, all'inizio") }
                    openSections[openSections.count - 1].sawTitle = true
                    inTitle = true
                    titleHasParagraph = false

                case ("p", "document"), ("p", "section"), ("p", "title"), ("p", "cell"), ("p", "caption"):
                    switch parent {
                    case "cell":
                        cellHasParagraph = true
                    case "caption":
                        captionHasParagraph = true
                    case "document":
                        markReturn(parent: parent ?? "")
                    case "section":
                        guard openSections.last?.sawTitle == true else { throw DocumentFormatError.malformed(line: line, detail: "una sezione comincia con il suo <title>") }
                        markReturn(parent: parent ?? "")
                    default:
                        guard !titleHasParagraph else { throw DocumentFormatError.malformed(line: line, detail: "il titolo di una sezione è un solo paragrafo") }
                        titleHasParagraph = true
                    }
                    let measures = ["first-indent", "left-indent", "right-indent", "space-before", "space-after", "line-spacing", "line-height"]
                    guard check(attributes, allowed: Set(measures + ["align", "font", "size", "features", "axes", "variable", "font-role", "optical", "lang", "hyphenation", "color", "vertical", "lines", "graphite", "small-caps", "list", "level", "style", "in-list", "list-indent", "list-marker", "list-gap", "opening-distance", "outline-level"] + LineKeeping.attributeNames), element: name, parser) else { return }
                    let styleName = try namedStyle(attributes["style"], target: .paragraph, attribute: "style", line: line)
                    var list: ListItem?
                    if let marker = attributes["list"] {
                        guard !marker.isEmpty else { throw DocumentFormatError.invalidValue(line: line, attribute: "list", value: marker) }
                        var level = 1
                        if let text = attributes["level"] {
                            guard let value = Int(text), (1...ListItem.maximumLevel).contains(value) else {
                                throw DocumentFormatError.invalidValue(line: line, attribute: "level", value: text)
                            }
                            level = value
                        }
                        list = ListItem(marker: marker, level: level)
                    } else if attributes["level"] != nil {
                        throw DocumentFormatError.missingAttribute(line: line, attribute: "list")
                    }
                    if let named = attributes["in-list"] {
                        guard list == nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "in-list", value: named) }
                        if !named.isEmpty {
                            guard settings.lists.contains(where: { $0.name == named }) else { throw DocumentFormatError.invalidValue(line: line, attribute: "in-list", value: named) }
                            list = ListItem(listName: named)
                        }
                    }
                    var style = settings.styles.resolveParagraph(styleName: styleName)
                    if let text = attributes["outline-level"] {
                        guard let level = Int(text), level >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "outline-level", value: text) }
                        style.outlineLevel = level > 0 ? level : nil
                    }
                    // Il livello del titolo di una sezione è la sua profondità nell'albero: nel modello resta quello dello
                    // stile, senza valore proprio.
                    if parent == "title" { style.outlineLevel = settings.styles.resolveParagraph(styleName: styleName).outlineLevel }
                    if let align = attributes["align"] {
                        guard let alignment = ParagraphStyle.Alignment(rawValue: align) else {
                            throw DocumentFormatError.invalidValue(line: line, attribute: "align", value: align)
                        }
                        style.alignment = alignment
                    }
                    for attribute in measures {
                        guard let text = attributes[attribute] else { continue }
                        guard let value = DocumentFormat.finiteNumber(text) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                        switch attribute {
                        case "first-indent": style.firstLineIndent = value
                        case "left-indent": style.leftIndent = value
                        case "right-indent": style.rightIndent = value
                        case "space-before": style.spaceBefore = value
                        case "space-after": style.spaceAfter = value
                        case "line-spacing": style.lineSpacing = value
                        default: style.lineHeightMultiple = value
                        }
                    }
                    paragraphStyle = try documentStyle.applying(settings.styles.values(of: styleName)).applying(attributes, line: line)
                    // Senza indicazioni proprie il paragrafo sta nella Lista del suo stile, se ne ha una.
                    if list == nil, attributes["in-list"] == nil, let styleList = settings.styles.values(of: styleName).listName { list = ListItem(listName: styleList) }
                    // Le misure proprie della voce, in punti (o con l'unità).
                    for (attribute, path) in [("list-indent", \ListItem.textIndent), ("list-marker", \ListItem.markerPosition)] {
                        guard let text = attributes[attribute] else { continue }
                        guard list != nil else { throw DocumentFormatError.missingAttribute(line: line, attribute: "list") }
                        guard let value = DocumentFormat.parseLength(text), value >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                        list?[keyPath: path] = Double(value)
                    }
                    // La forma di un giorno solo (17 ottobre 2026): la distanza fra segno e testo invece della posizione del segno.
                    if let text = attributes["list-gap"], list?.markerPosition == nil {
                        guard let gap = DocumentFormat.parseLength(text), gap >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "list-gap", value: text) }
                        if let item = list { list?.markerPosition = item.resolvedMeasures(in: settings.lists).textIndent - Double(gap) }
                    }
                    paragraph = Paragraph(styleName: styleName, style: style, list: list)
                    if let text = attributes["opening-distance"] {
                        guard let value = DocumentFormat.parseLength(text), value >= 0 else {
                            throw DocumentFormatError.invalidValue(line: line, attribute: "opening-distance", value: text)
                        }
                        paragraph?.openingDistance = Double(value)
                    }
                    paragraph?.keeping = try LineKeeping(xml: attributes) { throw DocumentFormatError.invalidValue(line: line, attribute: $0, value: $1) }
                    paragraphLine = line

                case ("field", "p"), ("field", "note"):
                    guard check(attributes, allowed: ["kind", "role", "font", "size", "features", "axes", "variable", "font-role", "optical", "lang", "hyphenation", "color", "vertical", "lines",
                                                      "graphite", "word-style", "char-style", "rules-off", "expression"], element: name, parser) else { return }
                    let field: Field
                    switch (attributes["kind"], attributes["role"]) {
                    case ("page"?, nil): field = .page
                    case ("pages"?, nil): field = .pageCount
                    case ("section-title"?, let role?) where !role.isEmpty: field = .sectionTitle(role: role)
                    case ("section-number"?, let role?) where !role.isEmpty: field = .sectionNumber(role: role)
                    case ("formula"?, nil):
                        guard settings.sourceVersion >= 9 else {
                            throw DocumentFormatError.malformed(line: line, detail: "Questa formula inserita nel testo richiede il formato 9")
                        }
                        guard let expression = attributes["expression"], let formula = FieldFormula(rawValue: expression) else {
                            throw DocumentFormatError.invalidValue(line: line, attribute: "expression", value: attributes["expression"] ?? "")
                        }
                        field = .formula(formula)
                    default: throw DocumentFormatError.invalidValue(line: line, attribute: "kind", value: attributes["kind"] ?? "")
                    }
                    if attributes["kind"] != "formula", attributes["expression"] != nil {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "expression", value: attributes["expression"] ?? "")
                    }
                    var runAttributes = attributes
                    runAttributes["kind"] = nil
                    runAttributes["role"] = nil
                    runAttributes["expression"] = nil
                    try startRun(from: note != nil ? noteStyle : paragraphStyle, runAttributes, line: line)
                    if note != nil, noteUsesParagraphs, !noteParagraphOpen {
                        throw DocumentFormatError.malformed(line: line, detail: "in una nota con paragrafi un campo va dentro <p>")
                    }
                    try append(Field.placeholder, line: line, field: field)

                case ("t", "p"):
                    guard check(attributes, allowed: ["font", "size", "features", "axes", "variable", "font-role", "optical", "lang", "hyphenation", "color", "vertical", "lines", "graphite", "small-caps", "word-style", "char-style", "rules-off"], element: name, parser) else { return }
                    // Dentro un paragrafo di nota lo stile di partenza è quello della nota.
                    try startRun(from: note != nil ? noteStyle : paragraphStyle, attributes, line: line)
                    runStartLine = line

                case ("note", "p"):
                    guard check(attributes, allowed: ["font", "size", "features", "axes", "variable", "font-role", "optical", "lang", "hyphenation", "color", "vertical", "lines", "graphite", "small-caps", "style"], element: name, parser) else { return }
                    var noteAttributes = attributes
                    let floatStyle = noteAttributes.removeValue(forKey: "style") ?? FloatStyle.footnoteName
                    guard settings.floatStyles.contains(where: { $0.name == floatStyle }) else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "style", value: floatStyle)
                    }
                    noteStyle = try paragraphStyle.applying(noteAttributes, line: line)
                    note = FloatingObject(paragraphs: [[]], style: floatStyle)
                    noteLine = line
                    noteUsesParagraphs = false
                    noteParagraphOpen = false

                case ("p", "note"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    // Gli spazi scritti prima del primo `p` servono solo a impaginare il file.
                    if !noteUsesParagraphs, note?.runs.allSatisfy({ $0.text.allSatisfy(\.isWhitespace) }) == true { note?.paragraphs = [[]] }
                    // Il primo `p` usa il paragrafo già aperto, se è ancora vuoto; gli altri ne aprono uno nuovo.
                    if noteUsesParagraphs || note?.paragraphs.last?.isEmpty == false { note?.paragraphs.append([]) }
                    noteUsesParagraphs = true
                    noteParagraphOpen = true

                case ("t", "note"):
                    guard check(attributes, allowed: ["font", "size", "features", "axes", "variable", "font-role", "optical", "lang", "hyphenation", "color", "vertical", "lines", "graphite", "small-caps", "word-style", "char-style", "rules-off"], element: name, parser) else { return }
                    try startRun(from: noteStyle, attributes, line: line)
                    runStartLine = line

                case ("img", "p"), ("img", "note"):
                    guard check(attributes, allowed: ["src", "width", "height"], element: name, parser) else { return }
                    func measure(_ attribute: String) throws -> Double {
                        guard let text = attributes[attribute] else { throw DocumentFormatError.missingAttribute(line: line, attribute: attribute) }
                        guard let value = DocumentFormat.parseLength(text), value > 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                        return Double(value)
                    }
                    imageInProgress = (src: attributes["src"], width: try measure("width"), height: try measure("height"), line: line)
                    imageText = ""

                case ("br", "p"), ("br", "t"), ("br", "note"):
                    guard check(attributes, allowed: [], element: name, parser) else { return }
                    try append("\u{2028}", line: line)

                default:
                    throw DocumentFormatError.unexpectedElement(line: line, element: name, parent: parent)
                }
            } catch let error as DocumentFormatError {
                fail(error, parser)
            } catch {
                fail(.malformed(line: line, detail: "\(error)"), parser)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
            switch name {
            case "t", "field":
                runStyle = nil
                runWordStyle = nil
                runCharacterStyle = nil
                runRuleExceptions = []
            case "styles":
                checkStyleReferences(parser)
            case "lists":
                checkListReferences(parser)
            case "document":
                if let notes = notesListName {
                    if settings.lists.contains(where: { $0.name == notes }) { settings.noteList = notes } else { fail(.invalidValue(line: notesLine, attribute: "notes", value: notes), parser) }
                }
                if let pages = pageNumberingName {
                    if settings.lists.contains(where: { $0.name == pages }) { settings.pageNumbering = pages } else { fail(.invalidValue(line: notesLine, attribute: "page-numbering", value: pages), parser) }
                }
            case "img":
                guard let image = imageInProgress else { return }
                imageInProgress = nil
                let encoded = imageText.filter { !$0.isWhitespace }
                let source: ImageObject.Source
                if let path = image.src {
                    guard encoded.isEmpty else { fail(.malformed(line: image.line, detail: "un'immagine collegata non contiene byte"), parser); return }
                    source = .linked(path)
                } else {
                    guard let data = Data(base64Encoded: encoded), !data.isEmpty else {
                        fail(.malformed(line: image.line, detail: "i byte dell'immagine non sono in base64"), parser)
                        return
                    }
                    source = .embedded(data)
                }
                let object = ImageObject(source: source, width: image.width, height: image.height)
                // Dentro una nota è l'immagine della figura; nel paragrafo, un'immagine nella riga.
                if note != nil { note?.image = object } else { paragraph?.inlines.append(.image(object)) }
            case "note":
                guard var finished = note else { return }
                for position in finished.paragraphs.indices where finished.paragraphs[position].isEmpty {
                    // Un paragrafo vuoto conserva lo stile con cui lo si scriverebbe.
                    do { finished.paragraphs[position] = [TextRun("", style: try noteStyle.resolved(line: noteLine))] } catch let error as DocumentFormatError {
                        fail(error, parser)
                    } catch {}
                }
                paragraph?.inlines.append(.floating(finished))
                note = nil
            case "p":
                if note != nil {
                    // Fine di un paragrafo della nota, non del paragrafo che la contiene.
                    noteParagraphOpen = false
                    return
                }
                guard var finished = paragraph else { return }
                if finished.inlines.isEmpty {
                    // Un paragrafo vuoto conserva lo stile con cui si scriverebbe.
                    do { finished.inlines = [.text(TextRun("", style: try paragraphStyle.resolved(line: paragraphLine)))] } catch let error as DocumentFormatError {
                        fail(error, parser)
                    } catch {}
                }
                paragraphs.append(FlatParagraph(finished, section: inTitle ? openSections.last?.mark : nil, cell: currentCell))
                paragraph = nil
            case "cell":
                defer {
                    inCell = false
                    cellValues = CellValues()
                    cellSpans = (1, 1)
                }
                guard !cellHasParagraph, let cell = currentCell else { return }
                // Una cella vuota è un paragrafo vuoto, con lo stile del documento.
                do {
                    let run = TextRun("", style: try documentStyle.resolved(line: parser.lineNumber))
                    paragraphs.append(FlatParagraph(Paragraph(style: settings.styles.resolveParagraph(styleName: nil), inlines: [.text(run)]), cell: cell))
                } catch let error as DocumentFormatError { fail(error, parser) } catch {}
            case "caption":
                defer { inCaption = false }
                guard !captionHasParagraph, let cell = currentCell else { return }
                // Una didascalia vuota è un paragrafo vuoto, con lo stile del documento.
                do {
                    let run = TextRun("", style: try documentStyle.resolved(line: parser.lineNumber))
                    paragraphs.append(FlatParagraph(Paragraph(style: settings.styles.resolveParagraph(styleName: nil), inlines: [.text(run)]), cell: cell))
                    captionHasParagraph = true
                } catch let error as DocumentFormatError { fail(error, parser) } catch {}
            case "row":
                // Una riga senza celle non si può rappresentare: non la si lascia sparire in silenzio.
                if let table, table.column < 0, !coveredCells.contains(where: { $0[0] == table.row }) {
                    fail(.malformed(line: rowLine, detail: "una riga di tabella ha almeno una cella"), parser)
                }
            case "table":
                if table?.row ?? 0 < 0 { fail(.malformed(line: tableLine, detail: "una tabella ha almeno una riga"), parser) }
                table = nil
                tableStyle = nil
                tableValues = TableValues()
                tableFloat = nil
                captionHasParagraph = false
                coveredCells = []
            case "title":
                inTitle = false
                guard !titleHasParagraph, let mark = openSections.last?.mark else { return }
                // Un titolo vuoto è un paragrafo vuoto, con lo stile del documento.
                do {
                    let run = TextRun("", style: try documentStyle.resolved(line: parser.lineNumber))
                    paragraphs.append(FlatParagraph(Paragraph(style: settings.styles.resolveParagraph(styleName: nil), inlines: [.text(run)]), section: mark))
                } catch let error as DocumentFormatError { fail(error, parser) } catch {}
            case "section":
                guard let closed = openSections.popLast() else { return }
                if !closed.sawTitle { fail(.malformed(line: closed.line, detail: "una sezione comincia con il suo <title>"), parser) }
                afterClosedSection = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            // I byte di un'immagine inclusa, in base64.
            if imageInProgress != nil {
                imageText += string
                return
            }
            guard paragraph != nil else {
                // Fuori dai paragrafi sono ammessi solo spazi e a capo, che servono a impaginare il file.
                if !string.allSatisfy(\.isWhitespace) {
                    fail(.malformed(line: parser.lineNumber, detail: "testo fuori da un paragrafo: «\(string.trimmingCharacters(in: .whitespacesAndNewlines))»"), parser)
                }
                return
            }
            do { try append(string, line: parser.lineNumber) } catch let error as DocumentFormatError { fail(error, parser) } catch {}
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            self.parser(parser, foundCharacters: String(decoding: block, as: UTF8.self))
        }

        /// Le misure di una pagina (`page` o `page-type`): quelle che mancano vengono da `base`.
        private func readPageSetup(_ attributes: [String: String], base: PageSetup, line: Int) throws -> PageSetup {
            let names = ["width", "height", "top", "bottom", "left", "right"]
            if let facing = attributes["facing"], !["on", "off"].contains(facing) {
                throw DocumentFormatError.invalidValue(line: line, attribute: "facing", value: facing)
            }
            var values: [String: CGFloat] = [:]
            for attribute in names {
                guard let text = attributes[attribute] else { continue }
                guard let value = DocumentFormat.parseLength(text), value >= 0 else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text)
                }
                values[attribute] = value
            }
            let page = PageSetup(
                paperSize: CGSize(width: values["width"] ?? base.paperSize.width, height: values["height"] ?? base.paperSize.height),
                top: values["top"] ?? base.top, bottom: values["bottom"] ?? base.bottom,
                left: values["left"] ?? base.left, right: values["right"] ?? base.right,
                facing: attributes["facing"] == "on")
            // Il foglio deve lasciare uno specchio: margini che si toccano o si incrociano non lasciano spazio al testo.
            guard page.paperSize.width - page.left - page.right >= 1, page.paperSize.height - page.top - page.bottom >= 1 else {
                throw DocumentFormatError.malformed(line: line, detail: "i margini del foglio non lasciano spazio al testo")
            }
            return page
        }

        /// Un riferimento a un tipo di pagina: deve esistere (o essere il predefinito).
        private func pageTypeName(_ name: String?, attribute: String, line: Int) throws -> String? {
            guard let name else { return nil }
            guard name == PageType.defaultName || settings.pageTypes.contains(where: { $0.name == name }) else {
                throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: name)
            }
            return name
        }

        /// Un riferimento a uno stile con un nome: deve esistere ed essere della specie giusta.
        private func namedStyle(_ name: String?, target: StyleTarget, attribute: String, line: Int) throws -> String? {
            guard let name else { return nil }
            guard settings.styles.style(named: name)?.target == target else {
                throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: name)
            }
            return name
        }

        /// Apre un tratto `t`: lo stile di partenza, poi lo stile di parola, quello di carattere e i valori dati a mano.
        private func startRun(from base: PartialStyle, _ attributes: [String: String], line: Int) throws {
            runWordStyle = try namedStyle(attributes["word-style"], target: .word, attribute: "word-style", line: line)
            runCharacterStyle = try namedStyle(attributes["char-style"], target: .character, attribute: "char-style", line: line)
            if let off = attributes["rules-off"] {
                runRuleExceptions = TextStyling.ruleExceptions(off)
                guard off.split(separator: " ").count == runRuleExceptions.count, !runRuleExceptions.isEmpty else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "rules-off", value: off)
                }
            }
            runStyle = try base.applying(settings.styles.values(of: runWordStyle)).applying(settings.styles.values(of: runCharacterStyle))
                .applying(attributes, line: line)
            runStartLine = line
        }

        private func readFormula(_ attributes: [String: String], line: Int, _ parser: XMLParser) throws {
            guard check(attributes, allowed: ["binding", "id", "predicate", "property", "kind", "value", "unit", "when", "after-style", "if", "compare", "threshold", "find", "count", "selection", "pattern", "words"], element: "formula", parser) else { return }
            guard let index = settings.styles.styles.indices.last,
                  let id = attributes["id"].flatMap(UUID.init(uuidString:)),
                  !settings.styles.styles[index].formulas.contains(where: { $0.id == id }),
                  let predicate = attributes["predicate"].flatMap(StylePredicate.init(rawValue:)),
                  let property = attributes["property"].flatMap(StyleProperty.init(rawValue:)),
                  let value = attributes["value"] else {
                throw DocumentFormatError.malformed(line: line, detail: "Formula incompleta, sconosciuta o con identità duplicata")
            }
            let modern = property.isDirective || property == .applyStyle || ["when", "after-style", "if", "compare", "threshold", "find", "count", "selection", "pattern", "words"].contains { attributes[$0] != nil }
            if settings.sourceVersion < 8, modern { throw DocumentFormatError.malformed(line: line, detail: "Questa formula richiede il formato 8") }
            if settings.sourceVersion < 7, attributes["kind"] == "face" {
                throw DocumentFormatError.malformed(line: line, detail: "La faccia precisa richiede il formato 7")
            }
            if settings.sourceVersion < 6, predicate == .subtract {
                throw DocumentFormatError.malformed(line: line, detail: "Sottrai richiede il formato 6")
            }
            if settings.sourceVersion < 5, ["family", "color", "smallCaps", "hyphenates"].contains(attributes["kind"] ?? "") {
                throw DocumentFormatError.malformed(line: line, detail: "Questo argomento richiede il formato 5")
            }
            let argument: StyleArgument
            switch attributes["kind"] {
            case "boolean":
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .boolean(value == "on")
            case "integer":
                guard let count = Int(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .integer(count)
            case "text": argument = .text(value)
            case "style": argument = .styleName(value.isEmpty ? nil : value)
            case "page-start":
                if value == "off" { argument = .pageStart(.disabled) }
                else if let points = DocumentFormat.finiteNumber(value), points >= 0 { argument = .pageStart(.distance(points)) }
                else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
            case "face": argument = .face(value)
            case "family": argument = .family(value)
            case "color": argument = .color(value.isEmpty ? nil : value)
            case "smallCaps":
                guard let mode = SmallCaps(rawValue: value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .smallCaps(mode)
            case "hyphenates":
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .hyphenates(value == "on")
            case "font":
                guard let role = FontRole(rawValue: value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .font(role)
            case "length":
                guard let amount = DocumentFormat.finiteNumber(value), let unit = attributes["unit"].flatMap(LengthUnit.init(rawValue:)) else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value)
                }
                argument = .length(amount, unit)
            case "alignment":
                guard let alignment = ParagraphStyle.Alignment(rawValue: value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: value) }
                argument = .alignment(alignment)
            case "language": argument = .language(value.isEmpty ? nil : value)
            default: throw DocumentFormatError.invalidValue(line: line, attribute: "kind", value: attributes["kind"] ?? "")
            }
            if attributes["kind"] != "length", attributes["unit"] != nil {
                throw DocumentFormatError.invalidValue(line: line, attribute: "unit", value: attributes["unit"] ?? "")
            }
            let position: TextRule.Position
            switch attributes["when"] {
            case nil, "any": position = .any
            case "page-start": position = .firstOnPage
            case "sequence-start": position = .sequenceStart
            case "after":
                guard let name = attributes["after-style"], !name.isEmpty else { throw DocumentFormatError.missingAttribute(line: line, attribute: "after-style") }
                position = .firstAfter(name)
            default: throw DocumentFormatError.invalidValue(line: line, attribute: "when", value: attributes["when"] ?? "")
            }
            if attributes["when"] != "after", attributes["after-style"] != nil { throw DocumentFormatError.malformed(line: line, detail: "after-style richiede when=after") }
            let measurement: TextRule.Condition?
            if let raw = attributes["if"] {
                guard let metric = TextRule.Condition.Property(rawValue: raw), let comparison = attributes["compare"].flatMap(TextRule.Condition.Comparison.init(rawValue:)),
                      let threshold = attributes["threshold"].flatMap(DocumentFormat.finiteNumber) else { throw DocumentFormatError.malformed(line: line, detail: "Condizione numerica incompleta") }
                measurement = TextRule.Condition(metric, comparison, threshold)
            } else {
                guard attributes["compare"] == nil && attributes["threshold"] == nil else { throw DocumentFormatError.malformed(line: line, detail: "Confronto privo di proprietà") }
                measurement = nil
            }
            let target: TextRule.Target
            switch attributes["find"] {
            case nil, "paragraph": target = .paragraph
            case "first-letter": target = .firstLetter
            case "first-sentence": target = .firstSentence
            case "last-line": target = .lastLine
            case "first-words", "first-lines":
                guard let count = attributes["count"].flatMap(Int.init), count > 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "count", value: attributes["count"] ?? "") }
                target = attributes["find"] == "first-words" ? .firstWords(count) : .firstLines(count)
            case "selection":
                guard let id = attributes["selection"].flatMap(UUID.init(uuidString:)) else { throw DocumentFormatError.invalidValue(line: line, attribute: "selection", value: attributes["selection"] ?? "") }
                target = .selection(id)
            case "words":
                switch attributes["pattern"] {
                case "capitals": target = .words(.capitals)
                case "roman": target = .words(.romanNumerals)
                case "numbers": target = .words(.numbers)
                case "list": target = .words(.listed((attributes["words"] ?? "").split(separator: " ").map(String.init)))
                default: throw DocumentFormatError.invalidValue(line: line, attribute: "pattern", value: attributes["pattern"] ?? "")
                }
            default: throw DocumentFormatError.invalidValue(line: line, attribute: "find", value: attributes["find"] ?? "")
            }
            if !["first-words", "first-lines"].contains(attributes["find"] ?? ""), attributes["count"] != nil { throw DocumentFormatError.malformed(line: line, detail: "count richiede parole o righe") }
            if attributes["find"] != "selection", attributes["selection"] != nil { throw DocumentFormatError.malformed(line: line, detail: "Selezione fuori dal destinatario") }
            if attributes["find"] != "words", attributes["pattern"] != nil || attributes["words"] != nil { throw DocumentFormatError.malformed(line: line, detail: "Modello fuori dalle parole") }
            if attributes["pattern"] != "list", attributes["words"] != nil { throw DocumentFormatError.malformed(line: line, detail: "Elenco di parole privo del relativo modello") }
            var formula = StyleFormula(id: id, operation: StylePropertyOperation(predicate, property, argument), when: StyleCondition(position: position, measurement: measurement), target: target)
            if let encoded = attributes["binding"] {
                guard settings.sourceVersion >= 11 else { throw DocumentFormatError.malformed(line: line, detail: "I collegamenti richiedono il formato 11") }
                do { formula.binding = try FormulaCodec.decode(FormulaExpression.self, encoded) }
                catch { throw DocumentFormatError.malformed(line: line, detail: "Collegamento di formula non valido") }
            }
            do { try formula.validate(for: settings.styles.styles[index].target) }
            catch { throw DocumentFormatError.malformed(line: line, detail: "Argomenti della formula incompatibili con il predicato o lo stile") }
            settings.styles.styles[index].formulas.append(formula)
        }

        /// Legge un elemento `style` della sezione degli stili.
        private func readStyle(_ attributes: [String: String], line: Int, _ parser: XMLParser) throws {
            let measures = ["first-indent", "left-indent", "right-indent", "space-before", "space-after", "line-spacing", "line-height"]
            let contextual = (settings.sourceVersion >= 2 ? ["page-start-spacing"] : []) + (settings.sourceVersion >= 8 ? ["next-style"] : [])
            guard check(attributes, allowed: Set(contextual + measures + ["name", "target", "based-on", "font", "family", "italic", "bold", "size", "features", "axes", "optical",
                                                             "lang", "hyphenation", "color", "vertical", "lines", "graphite", "small-caps", "align", "in-list", "opens-section", "opening-distance", "outline-level"] + LineKeeping.attributeNames), element: "style", parser) else { return }
            guard let name = attributes["name"], !name.isEmpty else { throw DocumentFormatError.missingAttribute(line: line, attribute: "name") }
            guard settings.styles.style(named: name) == nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "name", value: name) }
            guard let targetText = attributes["target"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "target") }
            guard let target = StyleTarget(rawValue: targetText) else { throw DocumentFormatError.invalidValue(line: line, attribute: "target", value: targetText) }
            func flag(_ attribute: String) throws -> Bool? {
                guard let value = attributes[attribute] else { return nil }
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: value) }
                return value == "on"
            }
            var values = StyleValues()
            values.fontName = attributes["font"]
            values.family = attributes["family"]
            values.nextStyle = attributes["next-style"]
            values.italic = try flag("italic")
            values.bold = try flag("bold")
            if let optical = attributes["optical"] {
                guard optical.isEmpty || StaticOpticalSize(rawValue: optical) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "optical", value: optical)
                }
                values.opticalSize = optical
            }
            values.hyphenates = try flag("hyphenation")
            if let color = attributes["color"] {
                guard color.isEmpty || TextStyling.color(hex: color) != nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "color", value: color) }
                values.color = color.lowercased()
            }
            if let vertical = attributes["vertical"] {
                guard vertical.isEmpty || VerticalPosition(encoded: vertical) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "vertical", value: vertical)
                }
                values.verticalPosition = vertical
            }
            if let lines = attributes["lines"] {
                guard LineDecoration.decode(lines) != nil else { throw DocumentFormatError.invalidValue(line: line, attribute: "lines", value: lines) }
                values.decorations = lines
            }
            if let graphite = attributes["graphite"] {
                guard Graphite.choice(fromEncoded: graphite) != nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "graphite", value: graphite)
                }
                values.graphite = graphite
            }
            values.language = attributes["lang"]
            if let size = attributes["size"] {
                guard let value = DocumentFormat.finiteNumber(size), value > 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "size", value: size) }
                values.size = value
            }
            if let features = attributes["features"] {
                values.features = try features.split(whereSeparator: \.isWhitespace).map { token in
                    guard let setting = parseFeature(String(token)) else { throw DocumentFormatError.invalidValue(line: line, attribute: "features", value: String(token)) }
                    return setting
                }
                // Nei file di prima il maiuscoletto stava fra le funzioni (lo stile «Maiuscoletto» chiedeva le sue tre
                // forme): diventa la scelta tipografica, e un elenco fatto solo di quello non fissa più funzioni.
                if let given = values.features {
                    let split = SmallCaps.split(given)
                    if split.smallCaps != .off {
                        values.smallCaps = split.smallCaps
                        values.features = split.rest.isEmpty ? nil : split.rest
                    }
                }
            }
            if let smallCaps = attributes["small-caps"] {
                guard let value = SmallCaps(rawValue: smallCaps) else { throw DocumentFormatError.invalidValue(line: line, attribute: "small-caps", value: smallCaps) }
                values.smallCaps = value
            }
            if let axes = attributes["axes"] {
                values.variations = try axes.split(whereSeparator: \.isWhitespace).map { token in
                    guard let variation = parseVariation(String(token)) else { throw DocumentFormatError.invalidValue(line: line, attribute: "axes", value: String(token)) }
                    return variation
                }
            }
            if let align = attributes["align"] {
                guard let alignment = ParagraphStyle.Alignment(rawValue: align) else { throw DocumentFormatError.invalidValue(line: line, attribute: "align", value: align) }
                values.alignment = alignment
            }
            for attribute in measures {
                guard let text = attributes[attribute] else { continue }
                guard let value = DocumentFormat.finiteNumber(text) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                switch attribute {
                case "first-indent": values.firstLineIndent = value
                case "left-indent": values.leftIndent = value
                case "right-indent": values.rightIndent = value
                case "space-before": values.spaceBefore = value
                case "space-after": values.spaceAfter = value
                case "line-spacing": values.lineSpacing = value
                default: values.lineHeightMultiple = value
                }
            }
            if let list = attributes["in-list"] {
                guard target == .paragraph, list.isEmpty || settings.lists.contains(where: { $0.name == list }) else { throw DocumentFormatError.invalidValue(line: line, attribute: "in-list", value: list) }
                values.listName = list
            }
            if let text = attributes["opening-distance"] {
                guard target == .paragraph, let value = DocumentFormat.parseLength(text), value >= 0 else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "opening-distance", value: text)
                }
                values.openingDistance = Double(value)
            }
            if let raw = attributes["page-start-spacing"] {
                guard target == .paragraph else { throw DocumentFormatError.invalidValue(line: line, attribute: "page-start-spacing", value: raw) }
                if raw == "off" { values.pageStartSpacing = .disabled }
                else if let points = DocumentFormat.parseLength(raw), points >= 0 { values.pageStartSpacing = .distance(points) }
                else { throw DocumentFormatError.invalidValue(line: line, attribute: "page-start-spacing", value: raw) }
            }
            values.keeping = try LineKeeping(xml: attributes) { throw DocumentFormatError.invalidValue(line: line, attribute: $0, value: $1) }
            if !values.keeping.isEmpty, target != .paragraph {
                throw DocumentFormatError.invalidValue(line: line, attribute: "keep-with-next", value: values.keeping.encoded)
            }
            if let role = attributes["opens-section"] {
                guard target == .paragraph, !role.contains("\n") else { throw DocumentFormatError.invalidValue(line: line, attribute: "opens-section", value: role) }
                values.opensSection = role
            }
            if let text = attributes["outline-level"] {
                guard target == .paragraph, let level = Int(text), level >= 0 else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "outline-level", value: text)
                }
                values.outlineLevel = level
            } else if levelsFromNames, target == .paragraph, let legacy = DocumentOutline.headingLevel(of: name) {
                // Migrazione: nei file precedenti il livello era implicito nel nome «Titolo N».
                values.outlineLevel = legacy
            }
            settings.styles.styles.append(NamedStyle(name: name, target: target, basedOn: attributes["based-on"], values: values))
            styleLines[name] = line
        }

        /// Legge un elemento `rule`. Gli stili a cui rimanda devono essere già stati letti.
        private func readRule(_ attributes: [String: String], line: Int, _ parser: XMLParser) throws {
            let refs: Set<String> = settings.sourceVersion >= 3 && attributes["find"] == "selection" ? ["ref"] : []
            guard check(attributes, allowed: refs.union(["find", "count", "pattern", "list", "in", "after", "position", "if", "compare", "value", "style", "enabled"]),
                        element: "rule", parser) else { return }
            func paragraphStyle(_ attribute: String) throws -> String? {
                guard let name = attributes[attribute] else { return nil }
                guard settings.styles.style(named: name)?.target == .paragraph else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: name) }
                return name
            }
            guard let find = attributes["find"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "find") }
            let target: TextRule.Target
            switch find {
            case "selection" where settings.sourceVersion >= 3:
                guard let id = attributes["ref"].flatMap(UUID.init(uuidString:)), settings.styles.selections.contains(where: { $0.id == id }) else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "ref", value: attributes["ref"] ?? "")
                }
                target = .selection(id)
            case "first-letter": target = .firstLetter
            case "first-sentence": target = .firstSentence
            case "first-words", "first-lines":
                guard let text = attributes["count"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "count") }
                guard let count = Int(text), count >= 1 else { throw DocumentFormatError.invalidValue(line: line, attribute: "count", value: text) }
                target = find == "first-words" ? .firstWords(count) : .firstLines(count)
            case "last-line": target = .lastLine
            case "paragraph": target = .paragraph
            case "words":
                guard let pattern = attributes["pattern"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "pattern") }
                switch pattern {
                case "capitals": target = .words(.capitals)
                case "roman": target = .words(.romanNumerals)
                case "numbers": target = .words(.numbers)
                case "list": target = .words(.listed((attributes["list"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)))
                default: throw DocumentFormatError.invalidValue(line: line, attribute: "pattern", value: pattern)
                }
            default: throw DocumentFormatError.invalidValue(line: line, attribute: "find", value: find)
            }
            var position = TextRule.Position.any
            if let after = try paragraphStyle("after") { position = .firstAfter(after) }
            if let value = attributes["position"] {
                guard ["sequence-start", "page-start"].contains(value), attributes["after"] == nil else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "position", value: value)
                }
                position = value == "sequence-start" ? .sequenceStart : .firstOnPage
            }
            var condition: TextRule.Condition?
            if let name = attributes["if"] {
                guard let property = TextRule.Condition.Property(rawValue: name) else { throw DocumentFormatError.invalidValue(line: line, attribute: "if", value: name) }
                let compareText = attributes["compare"] ?? "eq"
                guard let comparison = TextRule.Condition.Comparison(rawValue: compareText) else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "compare", value: compareText)
                }
                guard let valueText = attributes["value"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "value") }
                guard let value = DocumentFormat.finiteNumber(valueText) else { throw DocumentFormatError.invalidValue(line: line, attribute: "value", value: valueText) }
                condition = TextRule.Condition(property, comparison, value)
            } else if let stray = ["compare", "value"].first(where: { attributes[$0] != nil }) {
                throw DocumentFormatError.invalidValue(line: line, attribute: stray, value: attributes[stray]!)
            }
            guard let styleName = attributes["style"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "style") }
            guard let style = settings.styles.style(named: styleName), style.target != .paragraph || target == .paragraph else {
                throw DocumentFormatError.invalidValue(line: line, attribute: "style", value: styleName)
            }
            var enabled = true
            if let value = attributes["enabled"] {
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "enabled", value: value) }
                enabled = value == "on"
            }
            settings.rules.append(TextRule(target: target, paragraphStyle: try paragraphStyle("in"), position: position, condition: condition,
                                           styleName: styleName, isEnabled: enabled))
        }

        /// Legge un elemento `float-style`. Le Liste e gli stili a cui rimanda devono essere già stati letti.
        private func readFloatStyle(_ attributes: [String: String], line: Int, _ parser: XMLParser) throws {
            guard check(attributes, allowed: ["name", "placement", "positions", "caption", "heading", "new-page", "list", "reference", "rule", "rule-length", "space-above",
                                              "space-below", "split", "content", "pages", "edge"],
                        element: "float-style", parser) else { return }
            guard let name = attributes["name"], !name.isEmpty else { throw DocumentFormatError.missingAttribute(line: line, attribute: "name") }
            var style = FloatStyle(name: name)
            if let list = attributes["list"] {
                guard settings.lists.contains(where: { $0.name == list }) else { throw DocumentFormatError.invalidValue(line: line, attribute: "list", value: list) }
                style.listName = list
            }
            if let value = attributes["reference"] {
                guard let reference = FloatStyle.Reference(rawValue: value) else { throw DocumentFormatError.invalidValue(line: line, attribute: "reference", value: value) }
                style.reference = reference
            }
            func flag(_ attribute: String) throws -> Bool? {
                guard let value = attributes[attribute] else { return nil }
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: value) }
                return value == "on"
            }
            func measure(_ attribute: String) throws -> Double? {
                guard let text = attributes[attribute] else { return nil }
                guard let value = DocumentFormat.parseLength(text), value >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                return Double(value)
            }
            if let placement = attributes["placement"] {
                switch placement {
                case "foot": style.placement = .pageFoot
                case "end": style.placement = .documentEnd
                case "margin": style.placement = .outerMargin
                case "figure": style.placement = .figure
                case "head", "bottom":
                    // Intestazione e piè di pagina: senza richiamo, senza filetto, non si spezzano, salvo che il file dica altro.
                    style.placement = placement == "head" ? .pageHead : .pageBottom
                    if attributes["reference"] == nil { style.reference = .none }
                    if attributes["rule"] == nil { style.showsRule = false }
                    if attributes["split"] == nil { style.canSplit = false }
                default: throw DocumentFormatError.invalidValue(line: line, attribute: "placement", value: placement)
                }
            }
            if let pages = attributes["pages"] {
                guard style.placement.isRunning, let value = FloatStyle.RunningPages(rawValue: pages) else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "pages", value: pages)
                }
                style.pages = value
            }
            if let text = attributes["edge"] {
                guard style.placement.isRunning, let value = DocumentFormat.parseLength(text), value >= 0 else {
                    throw DocumentFormatError.invalidValue(line: line, attribute: "edge", value: text)
                }
                style.edgeDistance = Double(value)
            }
            if let positions = attributes["positions"] {
                var letters = Substring(positions)
                if letters.first == "!" {
                    style.ignoresLimits = true
                    letters = letters.dropFirst()
                }
                if letters == "H" {
                    style.exactlyHere = true
                } else {
                    let parsed = letters.compactMap { FloatStyle.FigurePosition(rawValue: String($0)) }
                    guard !parsed.isEmpty, parsed.count == letters.count, Set(parsed).count == parsed.count else {
                        throw DocumentFormatError.invalidValue(line: line, attribute: "positions", value: positions)
                    }
                    style.positions = parsed
                }
            }
            if let caption = attributes["caption"] {
                guard let value = FloatStyle.CaptionPosition(rawValue: caption) else { throw DocumentFormatError.invalidValue(line: line, attribute: "caption", value: caption) }
                style.caption = value
            }
            style.heading = attributes["heading"]
            style.startsOnNewPage = try flag("new-page") ?? false
            style.showsRule = try flag("rule") ?? style.showsRule
            style.canSplit = try flag("split") ?? style.canSplit
            style.ruleLength = try measure("rule-length")
            style.spaceAbove = try measure("space-above") ?? style.spaceAbove
            style.spaceBelow = try measure("space-below") ?? style.spaceBelow
            if let content = attributes["content"] {
                guard settings.styles.style(named: content)?.target == .paragraph else { throw DocumentFormatError.invalidValue(line: line, attribute: "content", value: content) }
                style.contentStyle = content
            }
            if name == FloatStyle.footnoteName, let index = settings.floatStyles.firstIndex(where: { $0.name == name }), !floatStyleLines.keys.contains(name) {
                settings.floatStyles[index] = style
            } else {
                guard !settings.floatStyles.contains(where: { $0.name == name }) else { throw DocumentFormatError.invalidValue(line: line, attribute: "name", value: name) }
                settings.floatStyles.append(style)
            }
            floatStyleLines[name] = line
        }

        /// Legge un elemento `list` della sezione delle Liste.
        private func readList(_ attributes: [String: String], line: Int, _ parser: XMLParser) throws {
            guard check(attributes, allowed: ["name", "counter", "prefix", "suffix", "start", "end", "parent", "parent-section", "numbers-sections", "continues",
                                              "shows-parent", "overflow", "indent", "marker", "gap"],
                        element: "list", parser) else { return }
            guard let name = attributes["name"], !name.isEmpty else { throw DocumentFormatError.missingAttribute(line: line, attribute: "name") }
            guard name != "page", !settings.lists.contains(where: { $0.name == name }) else { throw DocumentFormatError.invalidValue(line: line, attribute: "name", value: name) }
            guard let counterText = attributes["counter"] else { throw DocumentFormatError.missingAttribute(line: line, attribute: "counter") }
            guard let counter = ListCounter(rawValue: counterText) else { throw DocumentFormatError.invalidValue(line: line, attribute: "counter", value: counterText) }
            func flag(_ attribute: String) throws -> Bool {
                guard let value = attributes[attribute] else { return false }
                guard ["on", "off"].contains(value) else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: value) }
                return value == "on"
            }
            func integer(_ attribute: String) throws -> Int? {
                guard let text = attributes[attribute] else { return nil }
                guard let value = Int(text), value >= 1 else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                return value
            }
            var overflow = ListOverflow.ask
            if let text = attributes["overflow"] {
                guard let value = ListOverflow(rawValue: text) else { throw DocumentFormatError.invalidValue(line: line, attribute: "overflow", value: text) }
                overflow = value
            }
            if let role = attributes["parent-section"], role.isEmpty || attributes["parent"] != nil {
                throw DocumentFormatError.invalidValue(line: line, attribute: "parent-section", value: role)
            }
            if let role = attributes["numbers-sections"], role.isEmpty { throw DocumentFormatError.invalidValue(line: line, attribute: "numbers-sections", value: role) }
            let parent: ListParent? = attributes["parent"].map { $0 == "page" ? .page : .list($0) } ?? attributes["parent-section"].map { .section($0) }
            var definition = ListDefinition(name: name, counter: counter, prefix: attributes["prefix"] ?? "", suffix: attributes["suffix"] ?? "",
                                                 start: try integer("start") ?? 1, end: try integer("end"), parent: parent,
                                                 continues: try flag("continues"), showsParent: try flag("shows-parent"), overflow: overflow)
            definition.numbersSections = attributes["numbers-sections"]
            for (attribute, path) in [("indent", \ListDefinition.textIndent), ("marker", \ListDefinition.markerPosition)] {
                guard let text = attributes[attribute] else { continue }
                guard let value = DocumentFormat.parseLength(text), value >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: attribute, value: text) }
                definition[keyPath: path] = Double(value)
            }
            // La forma di un giorno solo: `gap`, la distanza fra segno e testo.
            if let text = attributes["gap"], definition.markerPosition == nil {
                guard let gap = DocumentFormat.parseLength(text), gap >= 0 else { throw DocumentFormatError.invalidValue(line: line, attribute: "gap", value: text) }
                definition.markerPosition = (definition.textIndent ?? ListItem.indentStep) - Double(gap)
            }
            settings.lists.append(definition)
            listLines[name] = line
        }

        /// A sezione chiusa: ogni `parent` nomina una lista esistente, e nessuna catena torna su se stessa.
        private func checkListReferences(_ parser: XMLParser) {
            for list in settings.lists {
                guard case .list(let parentName)? = list.parent else { continue }
                let line = listLines[list.name] ?? 0
                var seen: Set<String> = [list.name]
                var next: String? = parentName
                while let current = next {
                    guard let definition = settings.lists.first(where: { $0.name == current }), !seen.contains(current) else {
                        fail(.invalidValue(line: line, attribute: "parent", value: parentName), parser)
                        return
                    }
                    seen.insert(current)
                    if case .list(let above)? = definition.parent { next = above } else { next = nil }
                }
            }
        }

        /// A sezione chiusa: ogni `based-on` nomina uno stile della stessa specie, e nessuna catena torna su se stessa.
        private func checkStyleReferences(_ parser: XMLParser) {
            for style in settings.styles.styles {
                guard let parentName = style.basedOn else { continue }
                let line = styleLines[style.name] ?? 0
                guard let parent = settings.styles.style(named: parentName), parent.target == style.target else {
                    fail(.invalidValue(line: line, attribute: "based-on", value: parentName), parser)
                    return
                }
                var seen: Set<String> = [style.name]
                var next: String? = parentName
                while let current = next {
                    if seen.contains(current) {
                        fail(.invalidValue(line: line, attribute: "based-on", value: parentName), parser)
                        return
                    }
                    seen.insert(current)
                    next = settings.styles.style(named: current)?.basedOn
                }
            }
        }

        /// Aggiunge testo al paragrafo corrente, fondendolo con il tratto precedente se lo stile è lo stesso.
        private func append(_ text: String, line: Int, field: Field? = nil) throws {
            if var current = note {
                if noteUsesParagraphs && !noteParagraphOpen {
                    // Tra un paragrafo e l'altro della nota sono ammessi solo spazi, che servono a impaginare il file.
                    guard text.allSatisfy(\.isWhitespace) else {
                        throw DocumentFormatError.malformed(line: line, detail: "in una nota con paragrafi il testo va dentro <p>: «\(text.trimmingCharacters(in: .whitespacesAndNewlines))»")
                    }
                    return
                }
                // Dentro una nota il testo va al paragrafo in corso, con lo stesso criterio di fusione dei tratti.
                let style = try (runStyle ?? noteStyle).resolved(line: line)
                let last = current.paragraphs.count - 1
                let run = TextRun(text, style: style, wordStyleName: runWordStyle, characterStyleName: runCharacterStyle, ruleExceptions: runRuleExceptions, field: field)
                if var previous = current.paragraphs[last].last, previous.continues(with: run) {
                    previous.text += text
                    current.paragraphs[last][current.paragraphs[last].count - 1] = previous
                } else {
                    current.paragraphs[last].append(run)
                }
                note = current
                return
            }
            let style = try (runStyle ?? paragraphStyle).resolved(line: line)
            guard var current = paragraph else { return }
            let run = TextRun(text, style: style, wordStyleName: runWordStyle, characterStyleName: runCharacterStyle, ruleExceptions: runRuleExceptions, field: field)
            if case .text(var last)? = current.inlines.last, last.continues(with: run) {
                last.text += text
                current.inlines[current.inlines.count - 1] = .text(last)
            } else {
                current.inlines.append(.text(run))
            }
            paragraph = current
        }
    }
}

public enum DocumentFormatError: Error, Equatable, LocalizedError {
    case malformed(line: Int, detail: String)
    case unexpectedElement(line: Int, element: String, parent: String?)
    case unknownAttribute(line: Int, element: String, attribute: String)
    case missingAttribute(line: Int, attribute: String)
    case invalidValue(line: Int, attribute: String, value: String)
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .malformed(let line, let detail): "Riga \(line): \(detail)"
        case .unexpectedElement(let line, let element, let parent):
            "Riga \(line): elemento <\(element)> non previsto " + (parent.map { "dentro <\($0)>" } ?? "come radice del documento")
        case .unknownAttribute(let line, let element, let attribute): "Riga \(line): attributo «\(attribute)» sconosciuto in <\(element)>"
        case .missingAttribute(let line, let attribute): "Riga \(line): manca «\(attribute)» (né qui né nei livelli superiori)"
        case .invalidValue(let line, let attribute, let value): "Riga \(line): valore «\(value)» non valido per «\(attribute)»"
        case .newerVersion(let version): "Il file è nella versione \(version) del formato, più recente di quella che questa app conosce (\(DocumentFormat.version))"
        }
    }
}
