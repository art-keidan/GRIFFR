import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Stato della vista conservato nel file

    @objc func windowWillCloseForViewState(_ notification: Notification) {
        composerController?.close()
        composerController = nil
        composerModel = nil
        stopObserving()
        guard let url = (document as? NSDocument)?.fileURL else { return }
        currentViewState().write(to: url)
    }


    /// Zoom, cursore, scorrimento e finestra di adesso.
    func currentViewState() -> DocumentViewState {
        let origin = pagesScroll.contentView.bounds.origin
        let frame = window?.frame ?? .zero
        return DocumentViewState(zoom: pagesView.zoom.map(Double.init), anchor: selection.anchor, head: selection.head,
                                 scroll: [Double(origin.x), Double(origin.y)],
                                 frame: [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)])
    }

    /// Rimette zoom, finestra, cursore e scorrimento. Lo zoom va prima della finestra (lo zoom può allargarla), lo
    /// scorrimento per ultimo, a impaginazione fatta. Una finestra che non cadrebbe su nessuno schermo resta dov'è.
    func restoreViewState(_ state: DocumentViewState) {
        pagesView.zoom = state.zoom.map { CGFloat($0) }
        showZoomInBar(pagesView.zoom)
        if let window, state.frame.count == 4 {
            var frame = NSRect(x: state.frame[0], y: state.frame[1], width: state.frame[2], height: state.frame[3])
            frame.size.width = max(frame.width, window.minSize.width)
            frame.size.height = max(frame.height, window.minSize.height)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: frame.midX, y: frame.maxY - 10)) }) {
                // Anche un vecchio stato salvato dal difetto del percorso deve
                // riaprire una finestra interamente raggiungibile sullo schermo.
                window.setFrame(Self.clamped(frame, to: screen.visibleFrame), display: true)
                frameBeforeZoom = nil
                frameSetByZoom = nil
            }
        }
        let length = documentText.length
        apply(TextSelection(anchor: min(max(state.anchor, 0), length), head: min(max(state.head, 0), length)))
        guard state.scroll.count == 2 else { return }
        // Lo scorrimento salvato ha l'ultima parola, appena le pagine impaginate lo permettono.
        pagesView.pendingScroll = NSPoint(x: state.scroll[0], y: state.scroll[1])
    }

    func setZoom(_ zoom: CGFloat?) {
        pagesView.zoom = zoom
        pagesView.scrollCaretToVisible()
        showZoomInBar(zoom)
    }

    /// Mostra nella barra l'ingrandimento corrente. Un valore fuori elenco (da un pizzico sul trackpad) compare
    /// in una voce a parte, l'ultima del menu, che altrimenti resta nascosta.
    func showZoomInBar(_ zoom: CGFloat?) {
        defer { refreshRuler() }
        guard let custom = zoomPopup.lastItem else { return }
        if let zoom, let index = Self.zoomLevels.firstIndex(where: { abs($0 - zoom) < 0.005 }) {
            custom.isHidden = true
            zoomPopup.selectItem(at: index + 1)
        } else if let zoom {
            custom.title = "\(Int((zoom * 100).rounded()))%"
            custom.isHidden = false
            zoomPopup.select(custom)
        } else {
            custom.isHidden = true
            zoomPopup.selectItem(at: 0)
        }
    }

    @objc func zoomPopupChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        // La prima voce è «Automatico»; l'ultima è il valore libero già in uso, che non cambia nulla.
        if index == 0 { setZoom(nil) } else if index <= Self.zoomLevels.count { setZoom(Self.zoomLevels[index - 1]) }
        window?.makeFirstResponder(pagesView)
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(Self.zoomLevels.first { $0 > pagesView.scale + 0.005 } ?? Self.zoomLevels.last)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(Self.zoomLevels.last { $0 < pagesView.scale - 0.005 } ?? Self.zoomLevels.first)
    }

    @objc func zoomToActualSize(_ sender: Any?) { setZoom(1) }
    @objc func zoomToFit(_ sender: Any?) { setZoom(nil) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleHyphenation(_:)):
            menuItem.state = settings.hyphenates ? .on : .off
        case #selector(setDocumentLanguage(_:)):
            menuItem.state = (menuItem.representedObject as? String) == settings.language ? .on : .off
        case #selector(setSelectionLanguage(_:)):
            // Con una selezione in più lingue, nessuna voce è spuntata.
            if let language = selectionLanguage() { menuItem.state = (menuItem.representedObject as? String) == language ? .on : .off } else { menuItem.state = .off }
        case #selector(zoomToFit(_:)):
            menuItem.state = pagesView.zoom == nil ? .on : .off
        case #selector(toggleInvisibles(_:)):
            menuItem.state = pagesView.showsInvisibles ? .on : .off
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleSmallCaps(_:)), #selector(toggleSuperscript(_:)), #selector(toggleSubscript(_:)),
             #selector(toggleUnderline(_:)), #selector(toggleStrikethrough(_:)):
            let name = switch menuItem.action {
            case #selector(toggleBold(_:)): "grassetto"
            case #selector(toggleItalic(_:)): "corsivo"
            case #selector(toggleSuperscript(_:)): "apice"
            case #selector(toggleUnderline(_:)): "sottolineato"
            case #selector(toggleStrikethrough(_:)): "barrato"
            case #selector(toggleSubscript(_:)): "pedice"
            default: "maiuscoletto"
            }
            menuItem.state = (bandControls[name] as? NSButton)?.state ?? .off
        case #selector(toggleInterfaceMode(_:)):
            menuItem.state = interfaceMode == .advanced ? .on : .off
        case #selector(toggleObjectTree(_:)):
            menuItem.state = interfaceMode == .advanced && Self.showsObjectTree ? .on : .off
        case #selector(toggleProvenanceMarks(_:)):
            menuItem.state = interfaceMode == .advanced && showsProvenanceMarks ? .on : .off
        case #selector(toggleSpellChecking(_:)):
            menuItem.state = checksSpelling ? .on : .off
        case #selector(insertFootnote(_:)), #selector(insertNoteOfSeries(_:)), #selector(insertImage(_:)), #selector(insertFigure(_:)), #selector(insertSectionSameLevel(_:)):
            return noteAnchor == nil
        case #selector(insertRunning(_:)):
            return noteAnchor == nil && store.length > 0
        case #selector(insertTable(_:)):
            return canInsertTable
        case #selector(tableCommand(_:)):
            return noteAnchor == nil && TableEditing.cell(at: selection.range.location, in: store) != nil
        case #selector(mergeTableCells(_:)):
            let marks = selectedCells()
            return marks.count > 1
        case #selector(splitTableCell(_:)):
            let cell = noteAnchor == nil ? TableEditing.cell(at: selection.range.location, in: store) : nil
            return cell.map { $0.columnSpan > 1 || $0.rowSpan > 1 } ?? false
        case #selector(toggleTableFloat(_:)):
            let cell = noteAnchor == nil ? TableEditing.cell(at: selection.range.location, in: store) : nil
            menuItem.state = cell?.floatStyle != nil ? .on : .off
            return cell != nil
        case #selector(insertSectionInside(_:)):
            return noteAnchor == nil && !enclosingSections().isEmpty
        case #selector(insertSectionOutside(_:)):
            return noteAnchor == nil && enclosingSections().count >= 2
        case #selector(returnToOuterSection(_:)):
            let title = returnMenuTitle()
            menuItem.title = title ?? "Back to the Outer Section"
            return title != nil
        case #selector(joinPreviousSection(_:)):
            let title = joinMenuTitle()
            menuItem.title = title ?? "Into the Previous Section"
            return title != nil
        case #selector(removeEnclosingSection(_:)):
            if noteAnchor == nil, let title = enclosingSections().last {
                menuItem.title = "Remove the Section \(displayTitle(of: title))"
                return true
            }
            menuItem.title = "Remove Section"
            return false
        case #selector(editImageSize(_:)):
            return selectedImage != nil
        case #selector(setWordStyle(_:)):
            menuItem.state = (menuItem.representedObject as? String) == selectionStyleName(.word) ? .on : .off
        case #selector(setCharacterStyle(_:)):
            menuItem.state = (menuItem.representedObject as? String) == selectionStyleName(.character) ? .on : .off
        case #selector(newStyleFromSelection(_:)):
            return (textStorage?.length ?? 0) > 0
        case #selector(updateStyleFromSelection(_:)):
            let target = (menuItem.representedObject as? String).flatMap(StyleTarget.init(rawValue:)) ?? .paragraph
            let kind = switch target { case .paragraph: "paragraph"; case .word: "word"; case .character: "character" }
            if let name = selectionStyleName(target) {
                menuItem.title = "Update Style “\(name)” from Selection"
                return true
            }
            menuItem.title = "Update \(kind) Style from Selection"
            return false
        case #selector(setListMarker(_:)):
            menuItem.state = (menuItem.representedObject as? String) == selectionListItem()?.marker ? .on : .off
        case #selector(toggleList(_:)):
            menuItem.state = selectionListItem() == nil ? .off : .on
        case #selector(increaseListLevel(_:)):
            return selectionListItem()?.listName == nil && (selectionListItem()?.level ?? ListItem.maximumLevel) < ListItem.maximumLevel
        case #selector(decreaseListLevel(_:)):
            return selectionListItem()?.listName == nil && (selectionListItem()?.level ?? 1) > 1
        case #selector(setNamedList(_:)):
            menuItem.state = (menuItem.representedObject as? String) == selectionListItem()?.listName ? .on : .off
        default:
            break
        }
        return true
    }
    // MARK: Ingrandimento (menu Vista e barra)


    /// Lo spazio in cui la finestra può allargarsi per lo zoom: lo schermo senza barra dei menu e Dock, come quando macOS
    /// la fa «riempire lo schermo» (con il margine delle finestre affiancate, se è acceso; la misura di 8 punti è supposta).
    static func zoomArea(screen: NSRect) -> NSRect {
        let margins = UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "EnableTiledWindowMargins") as? Bool ?? false
        return margins ? screen.insetBy(dx: 8, dy: 8) : screen
    }

    /// Una cornice tenuta dentro `area`: non più larga né più alta, e spostata quanto serve perché nessun lato ne esca.
    static func clamped(_ frame: NSRect, to area: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, area.width)
        result.size.height = min(result.height, area.height)
        result.origin.x = min(max(result.minX, area.minX), area.maxX - result.width)
        result.origin.y = min(max(result.minY, area.minY), area.maxY - result.height)
        return result
    }

    /// Dopo un cambio di zoom: se la pagina non entra più nella larghezza visibile, la finestra si allarga, senza mai uscire
    /// dallo schermo (oltre, si scorre in orizzontale come prima); riducendo lo zoom torna verso la misura che aveva, mai sotto.
    func adaptWindowToZoom() {
        guard let window, let clip = pagesView.enclosingScrollView?.contentView,
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let area = Self.zoomArea(screen: screen)
        // Ridimensionata a mano dopo l'ultimo allargamento: la misura di prima si dimentica, non la si rimette più da sé.
        if let set = frameSetByZoom, window.frame != set {
            frameBeforeZoom = nil
            frameSetByZoom = nil
        }
        func apply(_ frame: NSRect) {
            window.setFrame(frame, display: true)
            // Se la finestra fosse finita comunque fuori dallo spazio dello schermo, la si riporta dentro.
            if !area.contains(window.frame), window.frame.width <= area.width + 0.5 { window.setFrame(Self.clamped(window.frame, to: area), display: true) }
            window.contentView?.layoutSubtreeIfNeeded()
            frameSetByZoom = frameBeforeZoom == nil ? nil : window.frame
        }
        // Più passi: la larghezza in più non va tutta alla colonna delle pagine se ci sono i pannelli ai lati.
        for _ in 0..<3 {
            let needed = pagesView.widthNeededForZoom
            let visible = clip.bounds.width
            var frame = window.frame
            if let needed, needed > visible + 0.5 {
                guard frame.width < area.width - 0.5 else { return }
                if frameBeforeZoom == nil { frameBeforeZoom = frame }
                frame.size.width = frame.width + needed - visible
                // Dentro lo schermo: al più larga quanto lo spazio, e spostata a sinistra se a destra non ci sta.
                frame = Self.clamped(frame, to: area)
            } else if let original = frameBeforeZoom {
                let target = needed.map { max(original.width, frame.width - (visible - $0)) } ?? original.width
                if target <= original.width + 0.5 {
                    frame = original
                    frameBeforeZoom = nil
                } else if target < frame.width - 0.5 {
                    frame.size.width = target
                } else {
                    return
                }
            } else {
                return
            }
            guard frame != window.frame else { return }
            apply(frame)
        }
    }

    // MARK: Caratteri nascosti (menu Vista)

    static let showsInvisiblesKey = "ShowsInvisibles"

    /// Mostra o nasconde i segni di spazi, tabulazioni, a capo, fine paragrafo e richiami di nota. Vale per tutte le
    /// finestre e si ricorda alla prossima apertura.
    @objc func toggleInvisibles(_ sender: Any?) {
        let shows = !pagesView.showsInvisibles
        UserDefaults.standard.set(shows, forKey: Self.showsInvisiblesKey)
        for case let editor as EditorWindowController in NSApp.windows.compactMap(\.windowController) {
            editor.pagesView.showsInvisibles = shows
            editor.refreshBandState()
        }
        // Una finestra non ancora elencata (nelle prove) va aggiornata comunque.
        pagesView.showsInvisibles = shows
        refreshBandState()
    }
}
