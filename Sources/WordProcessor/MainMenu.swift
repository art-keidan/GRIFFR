import AppKit
import Typesetting

@MainActor
enum MainMenu {
    /// Il nome del programma come lo vede l'utente.
    static let appName = "GRIFFR"

    static func build() -> NSMenu {
        let main = NSMenu()

        let app = submenu(of: main, title: appName)
        app.addItem(withTitle: "Informazioni su \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Impostazioni…", action: #selector(AppDelegate.showFontRoleSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Nascondi \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Esci da \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(of: main, title: "File")
        file.addItem(withTitle: "Nuovo", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Apri…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "Apri recente")
        recent.addItem(withTitle: "Cancella menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Apri recente", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Salva", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Salva con nome…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        file.addItem(withTitle: "Ripristina versione salvata", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Formato della pagina…", action: #selector(EditorWindowController.showPageSetup(_:)), keyEquivalent: "P")
        file.addItem(withTitle: "Esporta come PDF…", action: #selector(EditorWindowController.exportPDF(_:)), keyEquivalent: "e")
        file.addItem(withTitle: "Stampa…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        file.addItem(.separator())
        file.addItem(withTitle: "Chiudi", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(of: main, title: "Modifica")
        edit.addItem(withTitle: "Annulla", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Ripeti", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Trova")
        find.addItem(withTitle: "Cerca e sostituisci…", action: #selector(EditorWindowController.showFindBar(_:)), keyEquivalent: "f")
        find.addItem(withTitle: "Trova successivo", action: #selector(EditorWindowController.findNext(_:)), keyEquivalent: "g")
        find.addItem(withTitle: "Trova precedente", action: #selector(EditorWindowController.findPrevious(_:)), keyEquivalent: "G")
        find.addItem(withTitle: "Usa la selezione per cercare", action: #selector(EditorWindowController.useSelectionForFind(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Trova", action: nil, keyEquivalent: "").submenu = find
        edit.addItem(.separator())
        edit.addItem(withTitle: "Controlla ortografia durante la digitazione", action: #selector(EditorWindowController.toggleSpellChecking(_:)), keyEquivalent: "")

        let insert = submenu(of: main, title: "Inserisci")
        let note = insert.addItem(withTitle: "Nota a piè di pagina", action: #selector(EditorWindowController.insertFootnote(_:)), keyEquivalent: "f")
        // Le altre serie di note (stili di flottante), elencate al momento perché ogni documento ha le sue.
        let series = NSMenu(title: "Nota di un'altra serie")
        series.delegate = FloatSeriesMenuFiller.shared
        insert.addItem(withTitle: "Nota di un'altra serie", action: nil, keyEquivalent: "").submenu = series
        insert.addItem(.separator())
        insert.addItem(withTitle: "Immagine…", action: #selector(EditorWindowController.insertImage(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Figura…", action: #selector(EditorWindowController.insertFigure(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Tabella", action: #selector(EditorWindowController.insertTable(_:)), keyEquivalent: "")
        for (title, placement) in [("Intestazione", "head"), ("Piè di pagina", "bottom")] {
            let running = NSMenu(title: title)
            for (label, pages) in [("Per tutte le pagine", "all"), ("Per le pagine dispari", "odd"), ("Per le pagine pari", "even"),
                                   ("Per la prima pagina della sezione", "first")] {
                running.addItem(withTitle: label, action: #selector(EditorWindowController.insertRunning(_:)), keyEquivalent: "").representedObject = "\(placement) \(pages)"
            }
            insert.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = running
        }
        let fields = NSMenu(title: "Campo")
        fields.delegate = FieldMenuFiller.shared
        insert.addItem(withTitle: "Campo", action: nil, keyEquivalent: "").submenu = fields
        insert.addItem(.separator())
        insert.addItem(withTitle: "Sezione allo stesso livello", action: #selector(EditorWindowController.insertSectionSameLevel(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Sezione dentro questa", action: #selector(EditorWindowController.insertSectionInside(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Sezione più fuori", action: #selector(EditorWindowController.insertSectionOutside(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Togli la sezione", action: #selector(EditorWindowController.removeEnclosingSection(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Torna alla sezione esterna", action: #selector(EditorWindowController.returnToOuterSection(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Entra nella sezione precedente", action: #selector(EditorWindowController.joinPreviousSection(_:)), keyEquivalent: "")
        note.keyEquivalentModifierMask = [.command, .option]

        let format = submenu(of: main, title: "Formato")
        format.addItem(withTitle: "Mostra font", action: #selector(NSFontManager.orderFrontFontPanel(_:)), keyEquivalent: "t").target = NSFontManager.shared
        format.addItem(withTitle: "Grassetto", action: #selector(EditorWindowController.toggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Corsivo", action: #selector(EditorWindowController.toggleItalic(_:)), keyEquivalent: "i")
        format.addItem(withTitle: "Sottolineato", action: #selector(EditorWindowController.toggleUnderline(_:)), keyEquivalent: "u")
        format.addItem(withTitle: "Barrato", action: #selector(EditorWindowController.toggleStrikethrough(_:)), keyEquivalent: "")
        format.addItem(withTitle: "Maiuscoletto", action: #selector(EditorWindowController.toggleSmallCaps(_:)), keyEquivalent: "")
        let superscript = format.addItem(withTitle: "Apice", action: #selector(EditorWindowController.toggleSuperscript(_:)), keyEquivalent: "+")
        superscript.keyEquivalentModifierMask = [.command, .control]
        let subscriptItem = format.addItem(withTitle: "Pedice", action: #selector(EditorWindowController.toggleSubscript(_:)), keyEquivalent: "-")
        subscriptItem.keyEquivalentModifierMask = [.command, .control]
        format.addItem(.separator())
        // Elenchi: il segno si sceglie voce per voce del menu, o si scrive con «Altro segno…».
        let lists = NSMenu(title: "Elenco")
        let toggle = lists.addItem(withTitle: "Elenco sì/no", action: #selector(EditorWindowController.toggleList(_:)), keyEquivalent: "l")
        toggle.keyEquivalentModifierMask = [.command, .option]
        // Le Liste con un nome stanno nel menu «Lista» del righello; si definiscono nella scheda Liste dell'avanzata.
        lists.addItem(.separator())
        lists.addItem(withTitle: "Nessuno", action: #selector(EditorWindowController.setListMarker(_:)), keyEquivalent: "").representedObject = nil
        lists.addItem(.separator())
        for marker in EditorWindowController.bulletMarkers {
            lists.addItem(withTitle: EditorWindowController.bulletTitle(marker), action: #selector(EditorWindowController.setListMarker(_:)), keyEquivalent: "").representedObject = marker
        }
        lists.addItem(.separator())
        for marker in EditorWindowController.numberMarkers {
            let item = ListItem(marker: marker)
            let title = (1...3).map { item.text(number: $0) }.joined(separator: "  ")
            lists.addItem(withTitle: title, action: #selector(EditorWindowController.setListMarker(_:)), keyEquivalent: "").representedObject = marker
        }
        lists.addItem(.separator())
        lists.addItem(withTitle: "Altro segno…", action: #selector(EditorWindowController.chooseListMarker(_:)), keyEquivalent: "")
        lists.addItem(.separator())
        lists.addItem(withTitle: "Aumenta livello (Tab)", action: #selector(EditorWindowController.increaseListLevel(_:)), keyEquivalent: "")
        lists.addItem(withTitle: "Riduci livello (Maiusc-Tab)", action: #selector(EditorWindowController.decreaseListLevel(_:)), keyEquivalent: "")
        format.addItem(withTitle: "Elenco", action: nil, keyEquivalent: "").submenu = lists
        // Gli stili si scelgono nel righello (paragrafo) e nel Ribbon (parola e carattere); Liste, stili di flottante e
        // regole si definiscono nelle schede dell'avanzata; le misure di un'immagine con un doppio clic su di lei.
        format.addItem(.separator())
        format.addItem(withTitle: "Compositore di stili…", action: #selector(EditorWindowController.openStyleComposer(_:)), keyEquivalent: "")
        format.addItem(withTitle: "Nuovo stile dalla selezione…", action: #selector(EditorWindowController.newStyleFromSelection(_:)), keyEquivalent: "")
        for target in StyleTarget.allCases {
            format.addItem(withTitle: "Aggiorna lo stile dalla selezione", action: #selector(EditorWindowController.updateStyleFromSelection(_:)), keyEquivalent: "")
                .representedObject = target.rawValue
        }
        format.addItem(.separator())
        format.addItem(withTitle: "Sillabazione", action: #selector(EditorWindowController.toggleHyphenation(_:)), keyEquivalent: "")
        let languages = NSMenu(title: "Lingua del documento")
        let none = languages.addItem(withTitle: "Nessuna", action: #selector(EditorWindowController.setDocumentLanguage(_:)), keyEquivalent: "")
        none.representedObject = nil
        languages.addItem(.separator())
        for code in EditorWindowController.languages {
            languages.addItem(withTitle: EditorWindowController.languageName(code), action: #selector(EditorWindowController.setDocumentLanguage(_:)), keyEquivalent: "").representedObject = code
        }
        format.addItem(withTitle: "Lingua del documento", action: nil, keyEquivalent: "").submenu = languages
        // La lingua di un pezzo di testo: decide come si divide a fine riga e con quale dizionario si controlla.
        let textLanguages = NSMenu(title: "Lingua del testo selezionato")
        let inherited = textLanguages.addItem(withTitle: "Come il documento", action: #selector(EditorWindowController.setSelectionLanguage(_:)), keyEquivalent: "")
        inherited.representedObject = nil
        textLanguages.addItem(.separator())
        for code in EditorWindowController.languages {
            textLanguages.addItem(withTitle: EditorWindowController.languageName(code), action: #selector(EditorWindowController.setSelectionLanguage(_:)), keyEquivalent: "").representedObject = code
        }
        format.addItem(withTitle: "Lingua del testo selezionato", action: nil, keyEquivalent: "").submenu = textLanguages

        // Le righe e le colonne della tabella del cursore.
        let table = submenu(of: main, title: "Tabella")
        for command in TableCommand.allCases {
            if command == .removeRow || command == .removeTable { table.addItem(.separator()) }
            table.addItem(withTitle: command.title, action: #selector(EditorWindowController.tableCommand(_:)), keyEquivalent: "").representedObject = command.rawValue
        }
        table.addItem(.separator())
        table.addItem(withTitle: "Unisci le celle", action: #selector(EditorWindowController.mergeTableCells(_:)), keyEquivalent: "")
        table.addItem(withTitle: "Dividi la cella", action: #selector(EditorWindowController.splitTableCell(_:)), keyEquivalent: "")
        table.addItem(.separator())
        table.addItem(withTitle: "Tabella flottante, con didascalia", action: #selector(EditorWindowController.toggleTableFloat(_:)), keyEquivalent: "")

        let view = submenu(of: main, title: "Vista")
        view.addItem(withTitle: "Ingrandisci", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Riduci", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Dimensioni reali", action: #selector(EditorWindowController.zoomToActualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Adatta alla finestra", action: #selector(EditorWindowController.zoomToFit(_:)), keyEquivalent: "9")
        view.addItem(.separator())
        // Come in Pages: Maiuscole-Comando-I.
        view.addItem(withTitle: "Mostra caratteri nascosti", action: #selector(EditorWindowController.toggleInvisibles(_:)), keyEquivalent: "I")
        view.addItem(.separator())
        // Lo stesso comando del pulsante compatto in alto a destra cambia il livello degli strumenti.
        let advanced = view.addItem(withTitle: "Interfaccia dettagliata", action: #selector(EditorWindowController.toggleInterfaceMode(_:)), keyEquivalent: "a")
        advanced.keyEquivalentModifierMask = [.command, .option]
        let tree = view.addItem(withTitle: "Albero degli oggetti", action: #selector(EditorWindowController.toggleObjectTree(_:)), keyEquivalent: "o")
        tree.keyEquivalentModifierMask = [.command, .option]
        let marks = view.addItem(withTitle: "Segni della provenienza", action: #selector(EditorWindowController.toggleProvenanceMarks(_:)), keyEquivalent: "p")
        marks.keyEquivalentModifierMask = [.command, .option]
        view.addItem(withTitle: "Personalizza gli strumenti…", action: #selector(EditorWindowController.customizeToolbar(_:)), keyEquivalent: "")



        return main
    }

    private static func submenu(of main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}

/// Riempie il menu delle altre serie di note con gli stili di flottante del documento in primo piano.
@MainActor
/// Inserisci › Campo: numero di pagina, numero delle pagine, il primo campo formula, e titolo e numero della sezione in corso per ogni ruolo (quelli
/// pronti e quelli del documento, letti quando il menu si apre).
final class FieldMenuFiller: NSObject, NSMenuDelegate {
    static let shared = FieldMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ field: Field) {
            menu.addItem(withTitle: title, action: #selector(EditorWindowController.insertField(_:)), keyEquivalent: "").representedObject = field.encoded
        }
        add("Numero di pagina", .page)
        add("Numero delle pagine", .pageCount)
        // Il campo formula, accanto ai campi di sempre finché la sua grammatica non è completa.
        add("Pagina contenente → Numero", .formula(.pageContainingNumber))
        let roles = (NSApp.mainWindow?.windowController as? EditorWindowController)?.fieldRoles() ?? Section.Role.builtIn
        menu.addItem(.separator())
        for role in roles { add("Titolo della sezione in corso: \(role)", .sectionTitle(role: role)) }
        menu.addItem(.separator())
        for role in roles { add("Numero della sezione in corso: \(role)", .sectionNumber(role: role)) }
    }
}

@MainActor
final class FloatSeriesMenuFiller: NSObject, NSMenuDelegate {
    static let shared = FloatSeriesMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let styles = (NSApp.mainWindow?.windowController as? EditorWindowController)?.otherFloatStyles() ?? []
        if styles.isEmpty {
            menu.addItem(withTitle: "Nessun'altra serie: le crea la scheda Flottanti dell'interfaccia avanzata", action: nil, keyEquivalent: "").isEnabled = false
        }
        for style in styles {
            menu.addItem(withTitle: style, action: #selector(EditorWindowController.insertNoteOfSeries(_:)), keyEquivalent: "").representedObject = style
        }
    }
}
