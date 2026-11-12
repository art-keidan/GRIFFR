import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Barra degli strumenti personalizzabile

    /// Un comando che si può mettere nella barra degli strumenti.
    struct ToolbarCommand {
        let id: String
        let title: String
        let symbol: String
    }

    /// Tutti i comandi della barra, nell'ordine in cui il foglio li propone. «|» è una riga di separazione.
    static let toolbarCommands: [ToolbarCommand] = [
        .init(id: "nuovo", title: "New", symbol: "doc.badge.plus"),
        .init(id: "apri", title: "Open…", symbol: "folder"),
        .init(id: "salva", title: "Save", symbol: "square.and.arrow.down"),
        .init(id: "salvaCome", title: "Save As…", symbol: "square.and.arrow.down.on.square"),
        .init(id: "chiudi", title: "Close", symbol: "xmark.square"),
        .init(id: "stampa", title: "Print…", symbol: "printer"),
        .init(id: "pdf", title: "Export as PDF…", symbol: "arrow.down.doc"),
        .init(id: "annulla", title: "Undo", symbol: "arrow.uturn.backward"),
        .init(id: "ripeti", title: "Redo", symbol: "arrow.uturn.forward"),
        .init(id: "cerca", title: "Find and Replace", symbol: "magnifyingglass"),
        .init(id: "nota", title: "Note", symbol: "text.append"),
        .init(id: "illustrazione", title: "Illustration", symbol: "photo"),
        .init(id: "tabella", title: "Table", symbol: "tablecells"),
        .init(id: "carattere", title: "Special Character", symbol: "character"),
        .init(id: "nuovoStile", title: "New Style from Selection…", symbol: "paintbrush"),
        .init(id: "liste", title: "Lists…", symbol: "list.number"),
        .init(id: "stiliFlottante", title: "Float Styles…", symbol: "rectangle.on.rectangle"),
        .init(id: "nascosti", title: "Invisibles", symbol: "paragraphsign"),
        .init(id: "provenienza", title: "Provenance Marks", symbol: "highlighter"),
        .init(id: "correzione", title: "Spelling", symbol: "textformat.abc.dottedunderline"),
        .init(id: "lorem", title: "Lorem", symbol: "text.page"),
    ]

    /// La configurazione dettagliata conserva quella già scelta dall'utente; l'essenziale ha una configurazione propria.
    static let defaultToolbar = ["nuovo", "apri", "salva", "salvaCome", "chiudi", "|", "stampa", "pdf", "|", "annulla", "ripeti", "cerca", "|",
                                 "nota", "illustrazione", "tabella", "|", "nascosti", "provenienza", "correzione", "|", "lorem"]
    static let defaultSimpleToolbar = ["salva", "|", "annulla", "ripeti", "cerca", "|", "nota", "illustrazione", "tabella"]
    static let toolbarKey = "ToolbarItems"
    static let simpleToolbarKey = "ToolbarItems.simple"
    static let toolbarChanged = Notification.Name("WordProcessorToolbarItemsChanged")

    static func sanitizedToolbar(_ items: [String]) -> [String] {
        let known = Set(toolbarCommands.map(\.id) + ["|"])
        return items.filter(known.contains)
    }

    /// La configurazione della barra nell'interfaccia dettagliata.
    static var toolbarItems: [String] {
        get { toolbarItems(for: .advanced) }
        set { setToolbarItems(newValue, for: .advanced) }
    }

    static func toolbarItems(for mode: InterfaceMode) -> [String] {
        let key = mode == .simple ? simpleToolbarKey : toolbarKey
        let fallback = mode == .simple ? defaultSimpleToolbar : defaultToolbar
        guard let stored = UserDefaults.standard.stringArray(forKey: key) else { return fallback }
        return sanitizedToolbar(stored)
    }

    static func setToolbarItems(_ items: [String], for mode: InterfaceMode) {
        let key = mode == .simple ? simpleToolbarKey : toolbarKey
        UserDefaults.standard.set(sanitizedToolbar(items), forKey: key)
        NotificationCenter.default.post(name: toolbarChanged, object: nil)
    }


    /// I gruppi scelti, poi il comando che cambia livello, fisso in fondo a destra.
    func buildToolbarBand() -> BandView {
        modeButton.setButtonType(.pushOnPushOff)
        named("interfaccia", modeButton)
        let band = Bands.band([])
        let menu = NSMenu()
        menu.addItem(withTitle: "Customize Tools…", action: #selector(customizeToolbar(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Restore This Level…", action: #selector(resetToolbar(_:)), keyEquivalent: "").target = self
        band.menu = menu
        toolbarBand = band
        notificationTokens.append(NotificationCenter.default.addObserver(forName: Self.toolbarChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildToolbar() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: BandLayout.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bandLayoutChanged() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: BandLayoutEditing.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutEditingChanged() }
        })
        return band
    }

    /// Rifà le fasce con i comandi scelti per il livello corrente.
    func rebuildToolbar() {
        // Nella dettagliata, se la barra è già come dice la disposizione (l'ha appena salvata questa finestra), resta.
        if interfaceMode == .advanced, toolbarBand.zones.contains(where: \.isLayoutZone), currentBandLayout().normalized() == BandLayout.load() { return }
        composeBands()
    }

    /// «|» delimita i gruppi; ogni gruppo ha una presa e si trascina come un tutto.
    func toolbarViews() -> [NSView] {
        var groups: [[String]] = [[]]
        for id in Self.toolbarItems(for: interfaceMode) {
            if id == "|" { groups.append([]) } else { groups[groups.count - 1].append(id) }
        }
        return groups.filter { !$0.isEmpty }.map { commands in
            let group = ToolbarGroupView(commands: commands, views: commands.compactMap(toolbarControl))
            group.onDrag = { [weak self] group, point in self?.dragToolbarGroup(group, at: point) }
            group.onFinish = { [weak self] _ in self?.persistToolbarGroupOrder() }
            let zone = Bands.zone(Self.zoneTitle(for: commands), [group], spacing: 0)
            zone.onMove = { [weak self] zone, point in self?.toolbarBand.move(zone, toWindowPoint: point) }
            zone.onDrop = { [weak self] _ in self?.persistToolbarGroupOrder() }
            return zone
        }
    }

    /// Il nome della zona di un gruppo della barra: il genere dei suoi comandi (quello dei più, a parità il primo).
    static func zoneTitle(for commands: [String]) -> String {
        func kind(_ id: String) -> String {
            switch id {
            case "nuovo", "apri", "salva", "salvaCome", "chiudi": "file"
            case "stampa", "pdf": "print"
            case "annulla", "ripeti", "cerca": "edit"
            case "nota", "illustrazione", "tabella", "carattere", "lorem": "insert"
            case "nuovoStile", "liste", "stiliFlottante": "styles"
            case "nascosti", "provenienza", "correzione": "view"
            default: "tools"
            }
        }
        let kinds = commands.map(kind)
        return kinds.max { a, b in
            let (countA, countB) = (kinds.filter { $0 == a }.count, kinds.filter { $0 == b }.count)
            return countA != countB ? countA < countB : kinds.firstIndex(of: a)! > kinds.firstIndex(of: b)!
        } ?? "tools"
    }

    /// I gruppi della barra, ciascuno nella sua zona.
    private func toolbarZones(in row: NSStackView) -> [BandZone] {
        row.arrangedSubviews.compactMap { $0 as? BandZone }.filter { $0.row.arrangedSubviews.first is ToolbarGroupView }
    }

    /// La presa di un gruppo (nell'essenziale): si sposta la sua zona.
    func dragToolbarGroup(_ dragged: ToolbarGroupView, at point: NSPoint) {
        guard let row = toolbarBand.subviews.first as? NSStackView,
              let zone = toolbarZones(in: row).first(where: { $0.row.arrangedSubviews.first === dragged }) else { return }
        toolbarBand.move(zone, toWindowPoint: point)
    }

    func persistToolbarGroupOrder() {
        guard let row = toolbarBand.subviews.first as? NSStackView else { return }
        let groups = toolbarZones(in: row).compactMap { ($0.row.arrangedSubviews.first as? ToolbarGroupView)?.commands }
        Self.setToolbarItems(groups.reduce(into: [String]()) { result, group in
            if !result.isEmpty { result.append("|") }
            result.append(contentsOf: group)
        }, for: interfaceMode)
    }

    /// L'ordine dei gruppi e lo spostamento, per le prove e per il ripristino della configurazione.
    var toolbarGroupsForTests: [[String]] {
        var groups: [[String]] = [[]]
        for id in Self.toolbarItems(for: interfaceMode) {
            if id == "|" { groups.append([]) } else { groups[groups.count - 1].append(id) }
        }
        return groups.filter { !$0.isEmpty }
    }

    func moveToolbarGroupForTests(from source: Int, to destination: Int) {
        var groups = toolbarGroupsForTests
        guard groups.indices.contains(source), destination >= 0, destination < groups.count, source != destination else { return }
        let group = groups.remove(at: source)
        groups.insert(group, at: destination)
        Self.setToolbarItems(groups.reduce(into: [String]()) { result, group in
            if !result.isEmpty { result.append("|") }
            result.append(contentsOf: group)
        }, for: interfaceMode)
    }

    /// Il controllo di un comando della barra.
    func toolbarControl(_ id: String) -> NSView? {
        switch id {
        case "nuovo": return button(id, "doc.badge.plus", help: "New", action: #selector(bandNew(_:)))
        case "apri": return button(id, "folder", help: "Open…", action: #selector(bandOpen(_:)))
        case "salva": return button(id, "square.and.arrow.down", help: "Save", action: #selector(bandSave(_:)))
        case "salvaCome": return button(id, "square.and.arrow.down.on.square", help: "Save As…", action: #selector(bandSaveAs(_:)))
        case "chiudi": return button(id, "xmark.square", help: "Close", action: #selector(bandClose(_:)))
        case "stampa": return button(id, "printer", help: "Print… (⌘P)", action: #selector(printFromBar(_:)))
        case "pdf": return button(id, "arrow.down.doc", help: "Export as PDF…", action: #selector(exportPDF(_:)))
        case "annulla": return button(id, "arrow.uturn.backward", help: "Undo", action: #selector(bandUndo(_:)))
        case "ripeti": return button(id, "arrow.uturn.forward", help: "Redo", action: #selector(bandRedo(_:)))
        case "cerca": return button(id, "magnifyingglass", help: "Find and Replace (⌘F)", action: #selector(showFindBar(_:)))
        case "tabella": return button(id, "tablecells", help: "Insert a table", action: #selector(insertTable(_:)))
        case "nuovoStile": return button(id, "paintbrush", help: "New Style from Selection…", action: #selector(newStyleFromSelection(_:)))
        case "liste": return button(id, "list.number", help: "Lists…", action: #selector(editLists(_:)))
        case "stiliFlottante": return button(id, "rectangle.on.rectangle", help: "Float Styles…", action: #selector(editFloatStyles(_:)))
        case "lorem": return button(id, nil, label: "Lorem", help: "Insert about two pages of sample text, with headings, in Garamond Premier Pro",
                                    action: #selector(insertLorem(_:)))
        case "nascosti":
            let invisibles = button(id, "paragraphsign", help: "Show invisibles", action: #selector(toggleInvisibles(_:)))
            invisibles.state = pagesView.showsInvisibles ? .on : .off
            return invisibles
        case "provenienza":
            let provenance = button(id, "highlighter",
                                    help: "Provenance marks (⌥⌘P): orange for what was set by hand, teal for what a rule sets",
                                    action: #selector(toggleProvenanceMarks(_:)))
            provenance.state = showsProvenanceMarks ? .on : .off
            return provenance
        case "correzione":
            let spelling = button(id, "textformat.abc.dottedunderline", help: "Check spelling while typing",
                                  action: #selector(toggleSpellChecking(_:)))
            spelling.state = checksSpelling ? .on : .off
            return spelling
        case "nota":
            // Una voce per la nota a piè di pagina e una per ogni altra serie del documento (gli stili di flottante).
            return pullDown(id, symbol: "text.append", title: "", width: 42, help: "Insert a note") { [weak self] menu in
                guard let self else { return }
                menu.addItem(withTitle: "Footnote", action: #selector(self.insertFootnote(_:)), keyEquivalent: "").target = self
                for style in self.otherFloatStyles() {
                    let item = menu.addItem(withTitle: style, action: #selector(self.insertNoteOfSeries(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = style
                }
            }
        case "illustrazione":
            // Una voce per ogni stile di figura del documento, poi l'immagine nella riga.
            return pullDown(id, symbol: "photo", title: "", width: 42, help: "Insert an illustration") { [weak self] menu in
                guard let self else { return }
                let figures = self.settings.floatStyles.filter { $0.placement == .figure }.map(\.name)
                for style in figures.isEmpty ? [FloatStyle.defaultFigure.name] : figures {
                    let title = figures.count <= 1 ? "Figure with Caption…" : "\(style)…"
                    let item = menu.addItem(withTitle: title, action: #selector(self.insertFigure(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = style
                }
                menu.addItem(withTitle: "Inline Image…", action: #selector(self.insertImage(_:)), keyEquivalent: "").target = self
            }
        case "carattere":
            return pullDown(id, symbol: "character", title: "", width: 42, help: "Insert a special character") { [weak self] menu in
                self?.fillSpecialCharacters(menu)
            }
        default: return nil
        }
    }

    /// Cambia gli stili di flottante come la finestra degli stili (per le prove).
    func editFloatStylesForTests(_ styles: [FloatStyle]) {
        changeListSettings(lists: settings.lists, noteList: nil, styles: settings.styles, floatStyles: styles, actionName: "Float Styles")
    }

    /// File › Formato della pagina… (⇧⌘P): formato, margini e pagine affacciate, in un foglio. Lo stesso modulo sta
    /// nell'ispettore della Pagina.
    @objc func showPageSetup(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let model = PageSetupSheetModel(setup: settings.pageSetup)
        let sheet = model.makeWindow()
        model.finish = { [weak self, weak window, weak sheet] setup in
            if let sheet { window?.endSheet(sheet) }
            if let setup { self?.change(\.pageSetup, to: setup, actionName: "Page Setup") }
        }
        window.beginSheet(sheet)
    }

    /// Vista › Personalizza gli strumenti… (anche con il tasto destro sulla barra).
    @objc func customizeToolbar(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let mode = interfaceMode
        let model = ToolbarSheetModel(items: Self.toolbarItems(for: mode), commands: Self.toolbarCommands.map { ($0.id, $0.title, $0.symbol) },
                                      defaults: mode == .simple ? Self.defaultSimpleToolbar : Self.defaultToolbar)
        let sheet = model.makeWindow()
        model.finish = { [weak window, weak sheet] items in
            if let sheet { window?.endSheet(sheet) }
            if let items { Self.setToolbarItems(items, for: mode) }
        }
        window.beginSheet(sheet)
    }

    /// Ripristina soltanto la configurazione del livello corrente, lasciando invariata l'altra.
    @objc func resetToolbar(_ sender: Any?) {
        Self.setToolbarItems(interfaceMode == .simple ? Self.defaultSimpleToolbar : Self.defaultToolbar, for: interfaceMode)
    }

    /// La fascia del carattere (il Ribbon di Word 5).
    func buildCharacterBand() -> BandView {
        named("grassetto", faceStrip.boldButton)
        named("mostraFacce", faceStrip.disclosureButton)
        let italic = button("corsivo", nil, label: "I", help: "Italic (⌘I)", action: #selector(toggleItalic(_:)))
        italic.labelFont = NSFont(name: "Georgia-Italic", size: 13) ?? .systemFont(ofSize: 13)
        let smallCaps = button("maiuscoletto", nil, label: "Aᴀ", help: "Small caps", action: #selector(toggleSmallCaps(_:)))
        smallCaps.labelFont = NSFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13)
        let language = named("lingua", BandPopUp(width: 112, help: "Language of selected text"))
        language.addItem(withTitle: "Same as document")
        language.lastItem?.representedObject = nil
        for code in Self.languages {
            language.addItem(withTitle: Self.languageName(code))
            language.lastItem?.representedObject = code
        }
        for item in language.itemArray {
            item.target = self
            item.action = #selector(setSelectionLanguage(_:))
        }
        let underline = button("sottolineato", nil, label: "S\u{0332}", help: "Underline (⌘U)", action: #selector(toggleUnderline(_:)))
        let strikethrough = button("barrato", nil, label: "S\u{0336}", help: "Strikethrough", action: #selector(toggleStrikethrough(_:)))
        for control in [underline, strikethrough] { control.labelFont = .systemFont(ofSize: 13) }
        let superscript = button("apice", nil, label: "x²", help: "Superscript", action: #selector(toggleSuperscript(_:)))
        let subscriptButton = button("pedice", nil, label: "x₂", help: "Subscript", action: #selector(toggleSubscript(_:)))
        for control in [superscript, subscriptButton] { control.labelFont = .systemFont(ofSize: 13) }
        let color = pullDown("colore", title: "A", width: 46, help: "Text color") { [weak self] menu in self?.fillColorMenu(menu) }
        color.titleFont = .systemFont(ofSize: 13, weight: .semibold)
        color.swatchColor = Theme.text
        // Gli stili di parola e di carattere del documento, come comandi.
        let runStyles = pullDown("stileCarattere", title: "Style: —", width: 120, help: "Word or character style") { [weak self] menu in
            guard let self else { return }
            for (target, title, action) in [(StyleTarget.word, "Word", #selector(self.setWordStyle(_:))), (.character, "Character", #selector(self.setCharacterStyle(_:)))] {
                menu.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
                let current = self.selectionStyleName(target)
                let none = menu.addItem(withTitle: "None", action: action, keyEquivalent: "")
                none.target = self
                none.indentationLevel = 1
                none.state = current == nil ? .on : .off
                for name in self.styleNames(for: target) {
                    let item = menu.addItem(withTitle: name, action: action, keyEquivalent: "")
                    item.target = self
                    item.representedObject = name
                    item.indentationLevel = 1
                    item.state = current == name ? .on : .off
                }
            }
        }
        let opticalSize = button("corpoOttico", "textformat.size", help: "Automatic optical size", action: #selector(toggleOpticalSize(_:)))
        let specialCharacter = pullDown("carattereSpeciale", symbol: "character", title: "", width: 42,
                                        help: "Insert a special character") { [weak self] menu in self?.fillSpecialCharacters(menu) }
        characterStylesControl = runStyles
        // Famiglia e faccia; peso; corpo e disegno ottico; corsivo; le altre funzioni (disposizione dell'utente, 29 ottobre).
        // Acceso: il font variabile della famiglia; spento: le istanze statiche. Solo se la famiglia ha tutte e due.
        let variable = button("variabile", nil, help: "Variable font (on) or static instances (off)",
                              action: #selector(toggleVariableFont(_:)))
        variable.symbolImage = Self.variableFontSymbol
        variable.isHidden = true
        register(["famiglia": named("famiglia", familyPopup), "variabile": variable, "faccia": named("faccia", facePopup), "pesi": faceStrip,
                  "ruoli": roleSlots, "corpo": named("corpo", sizeBox), "corpoOttico": opticalSize,
                  "corpoOtticoScelta": named("corpoOtticoScelta", opticalSizePopup), "corsivo": italic, "maiuscoletto": smallCaps,
                  "apice": superscript, "pedice": subscriptButton, "sottolineato": underline, "barrato": strikethrough, "colore": color,
                  "lingua": language, "carattereSpeciale": specialCharacter])
        return Bands.band([])
    }

    /// La fascia del paragrafo (il righello di Word 5): stile, allineamento, interlinea, spazi, elenchi, livello.
    func buildParagraphBand() -> BandView {
        let alignment = named("allineamento", BandSegments([
            .init(image: Theme.symbol("text.alignleft", "Left"), help: "Left"),
            .init(image: Theme.symbol("text.aligncenter", "Center"), help: "Center"),
            .init(image: Theme.symbol("text.alignright", "Right"), help: "Right"),
            .init(image: Theme.symbol("text.justify", "Justified"), help: "Justified"),
            .init(label: "0,0", help: "On the decimal point: decimal separators aligned (in a table column)"),
        ], help: "Alignment"))
        alignment.onSelect = { [weak self] index in
            let value: ParagraphStyle.Alignment = [.left, .center, .right, .justified, .decimal][index]
            self?.setParagraphValue(.alignment, actionName: "Alignment") { $0.alignment = value }
        }
        let spacing = named("interlinea", BandSegments([.init(label: "1", help: "Single spacing"), .init(label: "1,5", help: "1.5 spacing"),
                                                         .init(label: "2", help: "Double spacing")], help: "Line spacing"))
        spacing.onSelect = { [weak self] index in
            let value = [0, 1.5, 2][index]
            self?.setParagraphValue(.lineHeightMultiple, actionName: "Line spacing") { $0.lineHeightMultiple = value }
        }
        let spaces = pullDown("spazi", title: "0 · 0 pt", width: 96, help: "Space before and after the paragraph") { [weak self] menu in
            self?.fillSpacesMenu(menu)
        }
        let bullets = pullDown("puntato", symbol: "list.bullet", title: "", width: 46, help: "Bulleted list") { [weak self] menu in
            guard let self else { return }
            let none = menu.addItem(withTitle: "No list", action: #selector(self.setListMarker(_:)), keyEquivalent: "")
            none.target = self
            for marker in Self.bulletMarkers {
                let item = menu.addItem(withTitle: Self.bulletTitle(marker), action: #selector(self.setListMarker(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = marker
            }
        }
        let numbers = pullDown("numerato", symbol: "list.number", title: "", width: 46, help: "Numbered list") { [weak self] menu in
            guard let self else { return }
            for marker in Self.numberMarkers {
                let item = menu.addItem(withTitle: (1...3).map { ListItem(marker: marker).text(number: $0) }.joined(separator: "  "),
                                        action: #selector(self.setListMarker(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = marker
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Other Marker…", action: #selector(self.chooseListMarker(_:)), keyEquivalent: "").target = self
        }
        let lists = pullDown("lista", title: "List: —", width: 110, help: "Named list") { [weak self] menu in
            guard let self else { return }
            let none = menu.addItem(withTitle: "None", action: #selector(self.setListMarker(_:)), keyEquivalent: "")
            none.target = self
            for (name, sample) in self.namedLists() {
                let item = menu.addItem(withTitle: "\(name)    \(sample)", action: #selector(self.setNamedList(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Lists…", action: #selector(self.editLists(_:)), keyEquivalent: "").target = self
        }
        // Gli stili (paragrafo, carattere, flottanti); allineamento e spazi; elenchi (disposizione dell'utente, 29 ottobre).
        var items: [String: NSView] = ["stile": named("stile", stylePopup), "allineamento": alignment, "interlinea": spacing, "spazi": spaces,
                                       "puntato": bullets, "numerato": numbers, "lista": lists,
                                       "riduciLivello": button("riduciLivello", "decrease.indent", help: "Decrease level (Shift-Tab)", action: #selector(decreaseListLevel(_:))),
                                       "aumentaLivello": button("aumentaLivello", "increase.indent", help: "Increase level (Tab)", action: #selector(increaseListLevel(_:))),
                                       "progetta": button("progetta", "paragraphsign", label: "Design", help: "Design the paragraph on the page: drag its measures; changes go into its style (⌥⌘G)", action: #selector(toggleParagraphDesign(_:))),
                                       // Il compositore degli stili a un clic, senza passare dal menu Formato.
                                       "compositore": button("compositore", nil, label: "Styles", help: "Open the Style Composer", action: #selector(openStyleComposer(_:))),
                                       "stiliFlottanteBanda": button("stiliFlottanteBanda", "rectangle.on.rectangle", help: "Float Styles…", action: #selector(editFloatStyles(_:)))]
        if let characterStylesControl { items["stileCarattere"] = characterStylesControl }
        register(items)
        return Bands.band([])
    }

    /// La barra di stato: i conteggi, lo stile del punto con le aggiunte, la lingua, gli avvisi, lo zoom.
    func buildStatusBand() -> BandView {
        countsLabel.font = Theme.smallFont
        countsLabel.textColor = Theme.text
        countsLabel.lineBreakMode = .byTruncatingTail
        countsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countsLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countsLabel.toolTip = "Click: all counts, for the document and the selection"
        countsLabel.onClick = { [weak self] in self?.showCounts(nil) }
        let spelling = pullDown("ortografia", title: "Italian ✓", help: "Language and spelling") { [weak self] menu in
            guard let self else { return }
            let check = menu.addItem(withTitle: "Check Spelling While Typing", action: #selector(self.toggleSpellChecking(_:)), keyEquivalent: "")
            check.target = self
            check.state = self.checksSpelling ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "Document Language", action: nil, keyEquivalent: "").isEnabled = false
            for code in Self.languages {
                let item = menu.addItem(withTitle: Self.languageName(code), action: #selector(self.setDocumentLanguage(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = code
                item.state = code == self.settings.language ? .on : .off
                item.indentationLevel = 1
            }
        }
        spelling.drawsBox = false
        spelling.titleFont = Theme.smallFont
        let warnings = pullDown("avvisi", symbol: "exclamationmark.triangle", title: "0", help: "Warnings") { [weak self] menu in
            self?.fillWarnings(menu)
        }
        warnings.borderColor = Theme.warn
        warnings.inkColor = Theme.warn
        warnings.titleFont = Theme.smallFont
        let smaller = button("riduci", "minus", help: "Zoom out", action: #selector(zoomOut(_:)))
        let larger = button("ingrandisci", "plus", help: "Zoom in", action: #selector(zoomIn(_:)))
        named("zoom", zoomPopup)
        // Lo stile non si accorcia: se manca spazio, si accorciano i conteggi.
        stylePills.setContentCompressionResistancePriority(.required, for: .horizontal)
        stylePills.onRemove = { [weak self] indices in self?.removeStyleAdditions(indices) }
        stylePills.onMoveToStyle = { [weak self] index in self?.moveStyleAdditions([index]) }
        stylePills.additionMenu = { [weak self] index in self?.additionMonitorMenu(at: index) ?? NSMenu() }
        stylePills.styleMenu = { [weak self] in self?.styleMonitorMenu() ?? NSMenu() }
        stylePills.setContentHuggingPriority(.required, for: .horizontal)
        // La barra di stato resta senza zone, anche nella dettagliata.
        let band = Bands.band([countsLabel, Bands.separator(), stylePills, Bands.spacer(), spelling, warnings, smaller, zoomPopup, larger],
                              height: 30, spacing: 8)
        band.lineOnTop = true
        band.lineOnBottom = false
        // Se manca spazio, si accorciano i conteggi, non i controlli.
        countsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return band
    }

    /// Le fasce, dall'alto: per le prove sugli spazi.
    var bandRows: [NSStackView] {
        (window?.contentView as? NSStackView)?.arrangedSubviews.compactMap { $0.subviews.first as? NSStackView } ?? []
    }

    func configureFontControls() {
        fillFamilyPopup()
        notificationTokens.append(NotificationCenter.default.addObserver(forName: .fontMenuGroupingChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fontMenuGroupingChanged() }
        })
        familyPopup.target = self
        familyPopup.action = #selector(familyChanged(_:))
        familyPopup.centersInk = true
        // La spunta la mette `markFamily`, anche sulla voce del gruppo che contiene la famiglia.
        familyPopup.positioningItem = { [weak self] in self?.familyPositioningItem() }
        facePopup.target = self
        facePopup.action = #selector(faceChanged(_:))
        sizeBox.target = self
        sizeBox.action = #selector(sizeChanged(_:))
        opticalSizePopup.addItem(withTitle: "Automatic")
        opticalSizePopup.lastItem?.representedObject = ""
        for size in StaticOpticalSize.allCases {
            opticalSizePopup.addItem(withTitle: size.title)
            opticalSizePopup.lastItem?.representedObject = size.rawValue
        }
        opticalSizePopup.target = self
        opticalSizePopup.action = #selector(opticalSizeChanged(_:))

        zoomPopup.addItems(withTitles: ["Automatic"] + Self.zoomLevels.map { "\(Int($0 * 100))%" } + ["—"])
        zoomPopup.lastItem?.isHidden = true
        zoomPopup.target = self
        zoomPopup.action = #selector(zoomPopupChanged(_:))
        zoomPopup.titleFont = Theme.smallFont
        zoomPopup.drawsBox = false

        stylePopup.target = self
        stylePopup.action = #selector(stylePopupChanged(_:))
        reloadStylePopup()
    }
}
