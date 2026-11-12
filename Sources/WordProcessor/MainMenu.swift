import AppKit
import Typesetting

@MainActor
enum MainMenu {
    /// Il nome del programma come lo vede l'utente.
    static let appName = "GRIFFR"

    static func build() -> NSMenu {
        let main = NSMenu()

        let app = submenu(of: main, title: appName)
        app.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showFontRoleSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(of: main, title: "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        file.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Page Setup…", action: #selector(EditorWindowController.showPageSetup(_:)), keyEquivalent: "P")
        file.addItem(withTitle: "Export as PDF…", action: #selector(EditorWindowController.exportPDF(_:)), keyEquivalent: "e")
        file.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(of: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        find.addItem(withTitle: "Find and Replace…", action: #selector(EditorWindowController.showFindBar(_:)), keyEquivalent: "f")
        find.addItem(withTitle: "Find Next", action: #selector(EditorWindowController.findNext(_:)), keyEquivalent: "g")
        find.addItem(withTitle: "Find Previous", action: #selector(EditorWindowController.findPrevious(_:)), keyEquivalent: "G")
        find.addItem(withTitle: "Use Selection for Find", action: #selector(EditorWindowController.useSelectionForFind(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        edit.addItem(.separator())
        edit.addItem(withTitle: "Check Spelling While Typing", action: #selector(EditorWindowController.toggleSpellChecking(_:)), keyEquivalent: "")

        let insert = submenu(of: main, title: "Insert")
        let note = insert.addItem(withTitle: "Footnote", action: #selector(EditorWindowController.insertFootnote(_:)), keyEquivalent: "f")
        // Le altre serie di note (stili di flottante), elencate al momento perché ogni documento ha le sue.
        let series = NSMenu(title: "Note of Another Series")
        series.delegate = FloatSeriesMenuFiller.shared
        insert.addItem(withTitle: "Note of Another Series", action: nil, keyEquivalent: "").submenu = series
        insert.addItem(withTitle: "Declared Note Text…", action: #selector(EditorWindowController.editDeclaredNoteText(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Inactive Declared Notes…", action: #selector(EditorWindowController.editInactiveDeclaredNotes(_:)), keyEquivalent: "")
        insert.addItem(.separator())
        insert.addItem(withTitle: "Image…", action: #selector(EditorWindowController.insertImage(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Figure…", action: #selector(EditorWindowController.insertFigure(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Table", action: #selector(EditorWindowController.insertTable(_:)), keyEquivalent: "")
        for (title, placement) in [("Header", "head"), ("Footer", "bottom")] {
            let running = NSMenu(title: title)
            for (label, pages) in [("For All Pages", "all"), ("For Odd Pages", "odd"), ("For Even Pages", "even"),
                                   ("For the First Page of the Section", "first")] {
                running.addItem(withTitle: label, action: #selector(EditorWindowController.insertRunning(_:)), keyEquivalent: "").representedObject = "\(placement) \(pages)"
            }
            insert.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = running
        }
        let fields = NSMenu(title: "Field")
        fields.delegate = FieldMenuFiller.shared
        insert.addItem(withTitle: "Field", action: nil, keyEquivalent: "").submenu = fields
        insert.addItem(.separator())
        insert.addItem(withTitle: "Section at the Same Level", action: #selector(EditorWindowController.insertSectionSameLevel(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Section Inside This One", action: #selector(EditorWindowController.insertSectionInside(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Section One Level Out", action: #selector(EditorWindowController.insertSectionOutside(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Remove Section", action: #selector(EditorWindowController.removeEnclosingSection(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Back to the Outer Section", action: #selector(EditorWindowController.returnToOuterSection(_:)), keyEquivalent: "")
        insert.addItem(withTitle: "Into the Previous Section", action: #selector(EditorWindowController.joinPreviousSection(_:)), keyEquivalent: "")
        note.keyEquivalentModifierMask = [.command, .option]

        let format = submenu(of: main, title: "Format")
        format.addItem(withTitle: "Show Fonts", action: #selector(NSFontManager.orderFrontFontPanel(_:)), keyEquivalent: "t").target = NSFontManager.shared
        format.addItem(withTitle: "Bold", action: #selector(EditorWindowController.toggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(EditorWindowController.toggleItalic(_:)), keyEquivalent: "i")
        format.addItem(withTitle: "Underline", action: #selector(EditorWindowController.toggleUnderline(_:)), keyEquivalent: "u")
        format.addItem(withTitle: "Strikethrough", action: #selector(EditorWindowController.toggleStrikethrough(_:)), keyEquivalent: "")
        format.addItem(withTitle: "Small Caps", action: #selector(EditorWindowController.toggleSmallCaps(_:)), keyEquivalent: "")
        let superscript = format.addItem(withTitle: "Superscript", action: #selector(EditorWindowController.toggleSuperscript(_:)), keyEquivalent: "+")
        superscript.keyEquivalentModifierMask = [.command, .control]
        let subscriptItem = format.addItem(withTitle: "Subscript", action: #selector(EditorWindowController.toggleSubscript(_:)), keyEquivalent: "-")
        subscriptItem.keyEquivalentModifierMask = [.command, .control]
        format.addItem(.separator())
        // Elenchi: il segno si sceglie voce per voce del menu, o si scrive con «Altro segno…».
        let lists = NSMenu(title: "List")
        let toggle = lists.addItem(withTitle: "List On/Off", action: #selector(EditorWindowController.toggleList(_:)), keyEquivalent: "l")
        toggle.keyEquivalentModifierMask = [.command, .option]
        // Le Liste con un nome stanno nel menu «Lista» del righello; si definiscono nella scheda Liste dell'avanzata.
        lists.addItem(.separator())
        lists.addItem(withTitle: "None", action: #selector(EditorWindowController.setListMarker(_:)), keyEquivalent: "").representedObject = nil
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
        lists.addItem(withTitle: "Other Marker…", action: #selector(EditorWindowController.chooseListMarker(_:)), keyEquivalent: "")
        lists.addItem(.separator())
        lists.addItem(withTitle: "Increase Level (Tab)", action: #selector(EditorWindowController.increaseListLevel(_:)), keyEquivalent: "")
        lists.addItem(withTitle: "Decrease Level (Shift-Tab)", action: #selector(EditorWindowController.decreaseListLevel(_:)), keyEquivalent: "")
        lists.addItem(.separator())
        // Una voce di più capoversi: i capoversi dopo il primo si segnano qui, e non consumano un numero.
        lists.addItem(withTitle: "Continue Previous Item", action: #selector(EditorWindowController.toggleListContinuation(_:)), keyEquivalent: "")
        lists.addItem(.separator())
        // Due elenchi della stessa Lista, e uno che riprende il primo.
        lists.addItem(withTitle: "Restart Numbering", action: #selector(EditorWindowController.restartListNumbering(_:)), keyEquivalent: "")
        lists.addItem(withTitle: "Resume Numbering…", action: #selector(EditorWindowController.resumeListNumbering(_:)), keyEquivalent: "")
        format.addItem(withTitle: "List", action: nil, keyEquivalent: "").submenu = lists
        // Gli stili si scelgono nel righello (paragrafo) e nel Ribbon (parola e carattere); Liste e stili di flottante si
        // definiscono nelle schede dell'avanzata, le formule contestuali nel compositore degli stili; le misure di un'immagine con un doppio clic su di lei.
        format.addItem(.separator())
        format.addItem(withTitle: "Style Composer…", action: #selector(EditorWindowController.openStyleComposer(_:)), keyEquivalent: "")
        format.addItem(withTitle: "New Style from Selection…", action: #selector(EditorWindowController.newStyleFromSelection(_:)), keyEquivalent: "")
        for target in StyleTarget.allCases {
            format.addItem(withTitle: "Update Style from Selection", action: #selector(EditorWindowController.updateStyleFromSelection(_:)), keyEquivalent: "")
                .representedObject = target.rawValue
        }
        format.addItem(.separator())
        format.addItem(withTitle: "Hyphenation", action: #selector(EditorWindowController.toggleHyphenation(_:)), keyEquivalent: "")
        let languages = NSMenu(title: "Document Language")
        let none = languages.addItem(withTitle: "None", action: #selector(EditorWindowController.setDocumentLanguage(_:)), keyEquivalent: "")
        none.representedObject = nil
        languages.addItem(.separator())
        for code in EditorWindowController.languages {
            languages.addItem(withTitle: EditorWindowController.languageName(code), action: #selector(EditorWindowController.setDocumentLanguage(_:)), keyEquivalent: "").representedObject = code
        }
        format.addItem(withTitle: "Document Language", action: nil, keyEquivalent: "").submenu = languages
        // La lingua di un pezzo di testo: decide come si divide a fine riga e con quale dizionario si controlla.
        let textLanguages = NSMenu(title: "Language of Selected Text")
        let inherited = textLanguages.addItem(withTitle: "Same as Document", action: #selector(EditorWindowController.setSelectionLanguage(_:)), keyEquivalent: "")
        inherited.representedObject = nil
        textLanguages.addItem(.separator())
        for code in EditorWindowController.languages {
            textLanguages.addItem(withTitle: EditorWindowController.languageName(code), action: #selector(EditorWindowController.setSelectionLanguage(_:)), keyEquivalent: "").representedObject = code
        }
        format.addItem(withTitle: "Language of Selected Text", action: nil, keyEquivalent: "").submenu = textLanguages

        // Le righe e le colonne della tabella del cursore.
        let table = submenu(of: main, title: "Table")
        for command in TableCommand.allCases {
            if command == .removeRow || command == .removeTable { table.addItem(.separator()) }
            table.addItem(withTitle: command.title, action: #selector(EditorWindowController.tableCommand(_:)), keyEquivalent: "").representedObject = command.rawValue
        }
        table.addItem(.separator())
        table.addItem(withTitle: "Merge Cells", action: #selector(EditorWindowController.mergeTableCells(_:)), keyEquivalent: "")
        table.addItem(withTitle: "Split Cell", action: #selector(EditorWindowController.splitTableCell(_:)), keyEquivalent: "")
        table.addItem(.separator())
        table.addItem(withTitle: "Floating Table with Caption", action: #selector(EditorWindowController.toggleTableFloat(_:)), keyEquivalent: "")

        let view = submenu(of: main, title: "View")
        view.addItem(withTitle: "Zoom In", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        view.addItem(withTitle: "Zoom Out", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(EditorWindowController.zoomToActualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Fit to Window", action: #selector(EditorWindowController.zoomToFit(_:)), keyEquivalent: "9")
        view.addItem(.separator())
        // Come in Pages: Maiuscole-Comando-I.
        view.addItem(withTitle: "Show Invisibles", action: #selector(EditorWindowController.toggleInvisibles(_:)), keyEquivalent: "I")
        view.addItem(.separator())
        // Lo stesso comando del pulsante compatto in alto a destra cambia il livello degli strumenti.
        let advanced = view.addItem(withTitle: "Detailed Interface", action: #selector(EditorWindowController.toggleInterfaceMode(_:)), keyEquivalent: "a")
        advanced.keyEquivalentModifierMask = [.command, .option]
        let tree = view.addItem(withTitle: "Object Tree", action: #selector(EditorWindowController.toggleObjectTree(_:)), keyEquivalent: "o")
        tree.keyEquivalentModifierMask = [.command, .option]
        let marks = view.addItem(withTitle: "Provenance Marks", action: #selector(EditorWindowController.toggleProvenanceMarks(_:)), keyEquivalent: "p")
        marks.keyEquivalentModifierMask = [.command, .option]
        let design = view.addItem(withTitle: "Design Paragraph", action: #selector(EditorWindowController.toggleParagraphDesign(_:)), keyEquivalent: "g")
        design.keyEquivalentModifierMask = [.command, .option]
        view.addItem(withTitle: "Customize Tools…", action: #selector(EditorWindowController.customizeToolbar(_:)), keyEquivalent: "")



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
/// Inserisci › Campo: numero di pagina, numero delle pagine, e titolo e numero della sezione in corso per ogni ruolo (quelli
/// pronti e quelli del documento, letti quando il menu si apre). Ogni voce inserisce una formula; il suggerimento ne dice
/// la catena («Posizione → Pagina contenente → Numero»).
final class FieldMenuFiller: NSObject, NSMenuDelegate {
    static let shared = FieldMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ formula: FieldFormula) {
            let item = menu.addItem(withTitle: formula.title, action: #selector(EditorWindowController.insertField(_:)), keyEquivalent: "")
            item.representedObject = Field.formula(formula).encoded
            item.toolTip = formula.chain
        }
        add(.pageContainingNumber)
        add(.documentPageCount)
        let roles = (NSApp.mainWindow?.windowController as? EditorWindowController)?.fieldRoles() ?? Section.Role.builtIn
        menu.addItem(.separator())
        for role in roles { add(.sectionContainingTitle(role: role)) }
        menu.addItem(.separator())
        for role in roles { add(.sectionContainingNumber(role: role)) }
        menu.addItem(.separator())
        if let editor = NSApp.mainWindow?.windowController as? EditorWindowController {
            if !FloatingIdentity.occurrences(in: editor.documentText).isEmpty || editor.currentLayout()?.declaredNotes.isEmpty == false {
                menu.addItem(withTitle: "Object Reference…", action: #selector(EditorWindowController.insertObjectReference(_:)), keyEquivalent: "").target = editor
            }
            if editor.objectAnchorForLabel != nil {
                menu.addItem(withTitle: "Object Label…", action: #selector(EditorWindowController.editObjectLabel(_:)), keyEquivalent: "").target = editor
            }
        }
        menu.addItem(withTitle: "Other Field…", action: #selector(EditorWindowController.insertCustomField(_:)), keyEquivalent: "")
            .toolTip = "Compose the field's formula: start, steps, result"
    }
}

@MainActor
final class FloatSeriesMenuFiller: NSObject, NSMenuDelegate {
    static let shared = FloatSeriesMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let styles = (NSApp.mainWindow?.windowController as? EditorWindowController)?.otherFloatStyles() ?? []
        if styles.isEmpty {
            menu.addItem(withTitle: "No other series: create them in the Floats tab of the detailed interface", action: nil, keyEquivalent: "").isEnabled = false
        }
        for style in styles {
            menu.addItem(withTitle: style, action: #selector(EditorWindowController.insertNoteOfSeries(_:)), keyEquivalent: "").representedObject = style
        }
    }
}
