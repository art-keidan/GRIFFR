import AppKit
import Typesetting

// MARK: - Tastiera e mouse nelle pagine

extension EditorWindowController: PagesViewEditing {
    var pagesTextLength: Int { textStorage?.length ?? 0 }
    var pagesSelectedRange: NSRange { selection.range }
    var pagesMarkedRange: NSRange { markedRange ?? NSRange(location: NSNotFound, length: 0) }

    func pagesAttributedSubstring(for range: NSRange) -> NSAttributedString? {
        NSMaxRange(range) <= store.length ? store.attributedSubstring(from: range) : nil
    }

    func pagesInsert(_ text: Any, replacementRange: NSRange) {
        endUndoStep(next: .insertion)
        let string = (text as? NSAttributedString)?.string ?? (text as? String) ?? ""
        // Il testo definitivo prende il posto di quello provvisorio del metodo di input, se c'è.
        let range = replacementRange.location != NSNotFound ? replacementRange : (markedRange ?? selection.range)
        markedRange = nil
        let attributes = typingAttributes
        let inNote = noteAnchor != nil
        // A capo all'inizio di un titolo: i paragrafi nuovi vanno prima del titolo, che resta titolo.
        let lastNewline = (string as NSString).range(of: "\n", options: .backwards)
        let beforeTitle = lastNewline.location != NSNotFound && !inNote && range.location < store.length
            && TextStyling.bodyParagraph(in: store, at: range.location).range.location == range.location
            && store.attribute(.sectionTitle, at: range.location, effectiveRange: nil) != nil
        var start = range.location
        writeStore(actionName: "Typing", breakingUndo: false) { store in
            // Su una selezione che attraversa celle: le celle si svuotano, la tabella resta.
            start = TableEditing.replace(range, in: store, with: NSAttributedString(string: string, attributes: attributes))
            if beforeTitle { store.removeAttribute(.sectionTitle, range: NSRange(location: start, length: NSMaxRange(lastNewline))) }
        }
        setSelection(caretAfterEdit(at: start + (string as NSString).length, inNote: inNote))
    }

    /// Il cursore dopo un tasto o una cancellazione. Alla fine del testo di una nota la stessa posizione è anche il
    /// punto del corpo dopo il richiamo: se si stava scrivendo nella nota, ci si resta (affinità «a monte»).
    private func caretAfterEdit(at location: Int, inNote: Bool) -> TextSelection {
        TextSelection(caret: location, affinity: inNote ? .upstream : .downstream)
    }

    /// Il testo provvisorio di un metodo di input: entra nel testo come un tasto (nello stesso passo d'annullamento) e
    /// si ricorda dov'è, perché il testo definitivo lo sostituisca.
    func pagesSetMarkedText(_ text: Any, selectedRange: NSRange, replacementRange: NSRange) {
        endUndoStep(next: .insertion)
        let string = (text as? NSAttributedString)?.string ?? (text as? String) ?? ""
        let range = replacementRange.location != NSNotFound ? replacementRange : (markedRange ?? selection.range)
        let attributes = typingAttributes
        let inNote = noteAnchor != nil
        var location = range.location
        writeStore(actionName: "Typing", breakingUndo: false) { store in
            location = TableEditing.replace(range, in: store, with: NSAttributedString(string: string, attributes: attributes))
        }
        let length = (string as NSString).length
        markedRange = length > 0 ? NSRange(location: location, length: length) : nil
        let start = location + min(selectedRange.location, length)
        setSelection(TextSelection(anchor: start, head: start + min(selectedRange.length, length - min(selectedRange.location, length)),
                                   affinity: inNote ? .upstream : .downstream))
    }

    /// Il metodo di input conferma il testo provvisorio così com'è.
    func pagesUnmarkText() {
        markedRange = nil
    }

    private static let movements: [Selector: (movement: TextMovement, extending: Bool)] = [
        #selector(NSResponder.moveLeft(_:)): (.left, false), #selector(NSResponder.moveBackward(_:)): (.left, false),
        #selector(NSResponder.moveRight(_:)): (.right, false), #selector(NSResponder.moveForward(_:)): (.right, false),
        #selector(NSResponder.moveWordLeft(_:)): (.wordLeft, false), #selector(NSResponder.moveWordBackward(_:)): (.wordLeft, false),
        #selector(NSResponder.moveWordRight(_:)): (.wordRight, false), #selector(NSResponder.moveWordForward(_:)): (.wordRight, false),
        #selector(NSResponder.moveUp(_:)): (.up, false), #selector(NSResponder.moveDown(_:)): (.down, false),
        #selector(NSResponder.moveToBeginningOfLine(_:)): (.lineStart, false), #selector(NSResponder.moveToLeftEndOfLine(_:)): (.lineStart, false),
        #selector(NSResponder.moveToEndOfLine(_:)): (.lineEnd, false), #selector(NSResponder.moveToRightEndOfLine(_:)): (.lineEnd, false),
        #selector(NSResponder.moveToBeginningOfParagraph(_:)): (.paragraphStart, false), #selector(NSResponder.moveToEndOfParagraph(_:)): (.paragraphEnd, false),
        #selector(NSResponder.moveToBeginningOfDocument(_:)): (.documentStart, false), #selector(NSResponder.moveToEndOfDocument(_:)): (.documentEnd, false),
        #selector(NSResponder.moveLeftAndModifySelection(_:)): (.left, true), #selector(NSResponder.moveBackwardAndModifySelection(_:)): (.left, true),
        #selector(NSResponder.moveRightAndModifySelection(_:)): (.right, true), #selector(NSResponder.moveForwardAndModifySelection(_:)): (.right, true),
        #selector(NSResponder.moveWordLeftAndModifySelection(_:)): (.wordLeft, true), #selector(NSResponder.moveWordBackwardAndModifySelection(_:)): (.wordLeft, true),
        #selector(NSResponder.moveWordRightAndModifySelection(_:)): (.wordRight, true), #selector(NSResponder.moveWordForwardAndModifySelection(_:)): (.wordRight, true),
        #selector(NSResponder.moveUpAndModifySelection(_:)): (.up, true), #selector(NSResponder.moveDownAndModifySelection(_:)): (.down, true),
        #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)): (.lineStart, true), #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)): (.lineStart, true),
        #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)): (.lineEnd, true), #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)): (.lineEnd, true),
        #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)): (.paragraphStart, true), #selector(NSResponder.moveParagraphBackwardAndModifySelection(_:)): (.paragraphStart, true),
        #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)): (.paragraphEnd, true), #selector(NSResponder.moveParagraphForwardAndModifySelection(_:)): (.paragraphEnd, true),
        #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)): (.documentStart, true), #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)): (.documentEnd, true),
    ]

    private static let deletions: [Selector: TextMovement] = [
        #selector(NSResponder.deleteBackward(_:)): .left, #selector(NSResponder.deleteForward(_:)): .right,
        #selector(NSResponder.deleteWordBackward(_:)): .wordLeft, #selector(NSResponder.deleteWordForward(_:)): .wordRight,
        #selector(NSResponder.deleteToBeginningOfLine(_:)): .lineStart, #selector(NSResponder.deleteToEndOfLine(_:)): .lineEnd,
        #selector(NSResponder.deleteToBeginningOfParagraph(_:)): .paragraphStart, #selector(NSResponder.deleteToEndOfParagraph(_:)): .paragraphEnd,
    ]

    private static let insertions: [Selector: String] = [
        #selector(NSResponder.insertNewline(_:)): "\n", #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): "\n",
        #selector(NSResponder.insertParagraphSeparator(_:)): "\n", #selector(NSResponder.insertLineBreak(_:)): "\u{2028}",
        #selector(NSResponder.insertTab(_:)): "\t", #selector(NSResponder.insertTabIgnoringFieldEditor(_:)): "\t",
    ]

    func pagesPerform(_ command: Selector) {
        // Esc esce dalla progettazione del capoverso.
        if command == #selector(NSResponder.cancelOperation(_:)), isDesigningParagraph {
            setParagraphDesign(false)
            return
        }
        if let (movement, extending) = Self.movements[command] {
            guard let layout = currentLayout() else { return }
            apply(layout.selection(selection, moving: movement, extending: extending))
        } else if [#selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:))].contains(command),
                  let title = titleMergedByDeletion(forward: command == #selector(NSResponder.deleteForward(_:))) {
            // Cancellare unirebbe un titolo al paragrafo prima: si chiede se togliere la sezione.
            let movement: TextMovement = command == #selector(NSResponder.deleteForward(_:)) ? .right : .left
            confirmSectionRemoval(title) { [weak self] in
                guard let self, let layout = self.currentLayout() else { return }
                let range = layout.deletionRange(for: self.selection, toward: movement)
                self.endUndoStep(next: .none)
                self.writeStore(actionName: "Remove Section") { store in
                    SectionEditing.removeSection(title, in: store)
                    if range.length > 0 { store.deleteCharacters(in: range) }
                }
                self.setSelection(TextSelection(caret: range.location))
                self.typingAttributes = Self.typingAttributes(in: self.store, at: self.selection)
            }
        } else if command == #selector(NSResponder.deleteBackward(_:)), caretInListItem(atStart: true) {
            // Cancellare all'indietro dall'inizio di una voce toglie il segno: il paragrafo torna normale.
            changeList(actionName: "Remove List") { _ in nil }
        } else if [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertParagraphSeparator(_:))].contains(command), caretInListItem(atStart: false) {
            // A capo in una voce vuota: esce di un livello, e dal primo livello chiude l'elenco.
            changeList(actionName: "End List") { $0.flatMap { $0.level > 1 ? ListItem(marker: $0.marker, level: $0.level - 1) : nil } }
        } else if [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:))].contains(command), noteAnchor == nil,
                  TableEditing.cell(at: selection.range.location, in: store) != nil {
            // In una tabella Tab e Maiusc-Tab passano alla cella dopo e prima (Opzione-Tab scrive un Tab).
            moveToNeighbourCell(forward: command == #selector(NSResponder.insertTab(_:)))
        } else if [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:))].contains(command), noteAnchor == nil,
                  changeListLevel(by: command == #selector(NSResponder.insertTab(_:)) ? 1 : -1) {
            // In un elenco Tab e Maiusc-Tab cambiano il livello delle voci.
            return
        } else if let movement = Self.deletions[command] {
            guard let layout = currentLayout() else { return }
            let range = layout.deletionRange(for: selection, toward: movement)
            // Gli a capo che chiudono una cella non si cancellano: all'inizio o alla fine di una cella il tasto non fa nulla.
            if range.length > 0, !TableEditing.deletablePieces(of: range, in: store).isEmpty {
                endUndoStep(next: .deletion)
                let inNote = noteAnchor != nil
                writeStore(actionName: "Delete", breakingUndo: false) { TableEditing.delete(range, in: $0) }
                setSelection(caretAfterEdit(at: range.location, inNote: inNote))
            }
        } else if let text = Self.insertions[command] {
            if text == "\n", noteAnchor == nil,
               let current = selectionStyleName(.paragraph), let next = settings.styles.values(of: current).nextStyle,
               !next.isEmpty, settings.styles.style(named: next)?.target == .paragraph {
                endUndoStep(next: .none)
                document?.undoManager?.beginUndoGrouping()
                pagesInsert(text, replacementRange: selection.range)
                applyNamedStyle(.paragraph, name: next)
                document?.undoManager?.endUndoGrouping()
                document?.undoManager?.setActionName("New Paragraph")
            } else { pagesInsert(text, replacementRange: selection.range) }
        } else if [#selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:))].contains(command) {
            pagesView.enclosingScrollView?.pageDown(nil)
        } else if [#selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:))].contains(command) {
            pagesView.enclosingScrollView?.pageUp(nil)
        } else if command == #selector(NSResponder.cancelOperation(_:)) {
            // Esc dentro una nota riporta al testo, dopo il richiamo.
            leaveNote()
        } else if [#selector(NSResponder.complete(_:)), #selector(NSResponder.insertBacktab(_:))].contains(command) {
            return
        } else {
            // Comandi meno comuni (scambia lettere, maiuscole della parola…); gli altri non sono previsti.
            if !performRareCommand(command) { NSSound.beep() }
        }
    }

    func pagesSelectLineRange(_ range: NSRange) {
        apply(TextSelection(anchor: range.location, head: NSMaxRange(range)))
    }

    func pagesMouseDown(at index: Int, affinity: NSSelectionAffinity, clickCount: Int, extending: Bool) {
        dragNote = textStorage.flatMap { TextStyling.footnoteSpan(in: $0, containing: index, affinity: affinity) }
        switch clickCount {
        case 1:
            dragUnit = .character
            apply(extending ? TextSelection(anchor: selection.anchor, head: index, affinity: affinity) : TextSelection(caret: index, affinity: affinity))
        case 2:
            dragUnit = .word
            // Sulla metà destra di un'immagine il punto più vicino è dopo di lei: il doppio clic vale per l'immagine.
            let isImage = { (position: Int) in position >= 0 && position < self.store.length && self.store.attribute(.inlineImage, at: position, effectiveRange: nil) != nil }
            let index = !isImage(index) && isImage(index - 1) ? index - 1 : index
            dragOrigin = selectionUnit(at: index, word: true)
            apply(TextSelection(anchor: dragOrigin.location, head: NSMaxRange(dragOrigin)))
            // Un doppio clic su un campo lo sceglie e ne apre la formula, finito il clic.
            let isField = { (position: Int) in position >= 0 && position < self.store.length && self.store.attribute(.field, at: position, effectiveRange: nil) != nil }
            if let field = [index, index - 1].first(where: isField), !isImage(index) {
                dragOrigin = NSRange(location: field, length: 1)
                apply(TextSelection(anchor: field, head: field + 1))
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    MainActor.assumeIsolated { self?.editFieldFormula(nil) }
                }
            }
            // Un doppio clic su un'immagine ne apre le misure, finito il clic.
            if selectedImage != nil {
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    MainActor.assumeIsolated { self?.editImageSize(nil) }
                }
            }
        default:
            dragUnit = .paragraph
            if let note = dragNote {
                // Dentro una nota: il paragrafo della nota, senza uscire dal suo testo.
                let paragraph = selectionUnit(at: index, word: false)
                dragOrigin = NSIntersectionRange(paragraph, NSRange(location: note.location + 1, length: note.length - 1))
                apply(TextSelection(anchor: dragOrigin.location, head: NSMaxRange(dragOrigin), affinity: NSMaxRange(dragOrigin) == NSMaxRange(note) ? .upstream : .downstream))
            } else if let storage = textStorage {
                // Nel corpo: il paragrafo intero, comprese le note che richiama, anche se di più paragrafi.
                dragOrigin = TextStyling.bodyParagraph(in: storage, at: index).range
                apply(TextSelection(anchor: dragOrigin.location, head: NSMaxRange(dragOrigin)))
            }
        }
    }

    func pagesMouseDragged(to index: Int, affinity: NSSelectionAffinity) {
        guard dragUnit != .character else {
            // La selezione non passa dal corpo a una nota o viceversa: resta nel testo in cui è cominciata.
            var head = index, headAffinity = affinity
            if let note = dragNote {
                head = min(max(index, note.location + 1), NSMaxRange(note))
                headAffinity = head == NSMaxRange(note) ? .upstream : .downstream
            } else if let storage = textStorage, let crossed = TextStyling.footnoteSpan(in: storage, containing: index, affinity: affinity) {
                head = index >= selection.anchor ? NSMaxRange(crossed) : crossed.location
                headAffinity = .downstream
            }
            apply(TextSelection(anchor: selection.anchor, head: head, affinity: headAffinity))
            return
        }
        // Trascinando dopo un doppio o triplo clic la selezione cresce di una parola o di un paragrafo alla volta.
        let unit = selectionUnit(at: index, word: dragUnit == .word)
        if unit.location < dragOrigin.location {
            apply(TextSelection(anchor: NSMaxRange(dragOrigin), head: unit.location))
        } else {
            apply(TextSelection(anchor: dragOrigin.location, head: max(NSMaxRange(unit), NSMaxRange(dragOrigin))))
        }
    }

    func pagesForwardAction(_ action: Selector, sender: Any?) -> Bool {
        switch action {
        case #selector(NSText.copy(_:)):
            return copySelection()
        case #selector(NSText.cut(_:)):
            guard copySelection() else { return false }
            endUndoStep(next: .none)
            let range = selection.range
            let fragment = store.identifiedFragment(in: range)
            let selected = Set(FloatingIdentity.occurrences(in: fragment).map { $0.identity.id })
            var selectedParagraphs: Set<UUID> = []
            fragment.enumerateAttribute(.paragraphIdentity, in: NSRange(location: 0, length: fragment.length)) { value, _, _ in
                if let id = (value as? String).flatMap(UUID.init(uuidString:)) { selectedParagraphs.insert(id) }
            }
            let sections = Set(SectionEditing.titles(in: fragment).map { $0.mark.id })
            let tables = TableEditing.identities(in: fragment)
            writeStore(actionName: "Cut") { TableEditing.delete(range, in: $0) }
            if !selected.isEmpty {
                let retained = Set(FloatingIdentity.occurrences(in: store).map { $0.identity.id })
                objectClipboard?.removed = selected.subtracting(retained)
            }
            objectClipboard?.paragraphs = selectedParagraphs.subtracting(store.paragraphIDs.map(\.persistent))
            if !sections.isEmpty { objectClipboard?.sections = sections.subtracting(SectionEditing.titles(in: store).map { $0.mark.id }) }
            if !tables.isEmpty { objectClipboard?.tables = tables.subtracting(TableEditing.identities(in: store)) }
            setSelection(TextSelection(caret: range.location))
            return true
        case #selector(NSText.paste(_:)):
            return paste()
        case #selector(NSText.delete(_:)):
            let range = selection.range
            guard range.length > 0 else { return false }
            endUndoStep(next: .none)
            writeStore(actionName: "Delete") { TableEditing.delete(range, in: $0) }
            setSelection(TextSelection(caret: range.location))
            return true
        case #selector(NSResponder.selectAll(_:)):
            apply(TextSelection(anchor: 0, head: store.length))
            return true
        case Selector(("undo:")), Selector(("redo:")):
            performUndo(redo: action == Selector(("redo:")))
            return true
        case #selector(NSTextView.changeFont(_:)):
            changeFontFromPanel()
            return true
        default:
            return false
        }
    }

    /// Il pannello dei font di sistema (Formato › Mostra font): converte il font di ogni tratto della selezione, o
    /// quello con cui si scriverà.
    private func changeFontFromPanel() {
        let manager = NSFontManager.shared
        let range = selection.range
        guard range.length > 0 else {
            if let font = typingAttributes[.font] as? NSFont { typingAttributes[.font] = manager.convert(font) }
            return
        }
        endUndoStep(next: .none)
        writeStore(actionName: "Font") { store in
            var changes: [(NSRange, NSFont)] = []
            store.enumerateAttribute(.font, in: range) { value, run, _ in
                if let font = value as? NSFont { changes.append((run, manager.convert(font))) }
            }
            for (run, font) in changes { TextStyling.writeFont(font, in: store, range: run) }
        }
        refreshFromSelection()
    }

    /// La parola (doppio clic) o il paragrafo (triplo clic) che contiene una posizione, come li sceglieva l'area di Apple.
    private func selectionUnit(at index: Int, word: Bool) -> NSRange {
        guard store.length > 0 else { return NSRange(location: 0, length: 0) }
        let location = min(index, store.length - 1)
        return word ? store.doubleClick(at: location) : (store.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    }

    /// I comandi meno comuni della tastiera: scambiare due lettere, maiuscole o minuscole di una parola. Vero se il
    /// comando è stato eseguito.
    private func performRareCommand(_ command: Selector) -> Bool {
        let string = store.string as NSString
        switch command {
        case #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)):
            pagesPerform(#selector(NSResponder.deleteBackward(_:)))
            return true
        case #selector(NSResponder.transpose(_:)):
            // Come nell'area di Apple: si scambiano i due caratteri intorno al cursore; in fondo al paragrafo, gli ultimi due.
            guard selection.isEmpty, string.length >= 2 else { return false }
            var location = selection.head
            if location == 0 { return false }
            if location >= string.length || TextStyling.isLineTerminator(string.character(at: location)) { location -= 1 }
            guard location >= 1 else { return false }
            let pair = NSRange(location: location - 1, length: 2)
            let swapped = NSMutableAttributedString(attributedString: store.attributedSubstring(from: NSRange(location: location, length: 1)))
            swapped.append(store.attributedSubstring(from: NSRange(location: location - 1, length: 1)))
            endUndoStep(next: .none)
            writeStore(actionName: "Transpose") { $0.replaceCharacters(in: pair, with: swapped) }
            setSelection(TextSelection(caret: NSMaxRange(pair)))
            return true
        case #selector(NSResponder.uppercaseWord(_:)), #selector(NSResponder.lowercaseWord(_:)), #selector(NSResponder.capitalizeWord(_:)):
            let range = selection.isEmpty ? selectionUnit(at: selection.head, word: true) : selection.range
            guard range.length > 0 else { return false }
            let original = string.substring(with: range)
            let changed = command == #selector(NSResponder.uppercaseWord(_:)) ? original.uppercased()
                : command == #selector(NSResponder.lowercaseWord(_:)) ? original.lowercased() : original.capitalized
            guard (changed as NSString).length == range.length, changed != original else { return changed == original }
            endUndoStep(next: .none)
            writeStore(actionName: "Change Case") { store in
                // Carattere per carattere, così ciascuno conserva i suoi attributi.
                for offset in 0..<range.length {
                    let character = (changed as NSString).substring(with: NSRange(location: offset, length: 1))
                    if character != (original as NSString).substring(with: NSRange(location: offset, length: 1)) {
                        store.replaceCharacters(in: NSRange(location: range.location + offset, length: 1), with: character)
                    }
                }
            }
            setSelection(TextSelection(anchor: range.location, head: NSMaxRange(range)))
            return true
        default:
            return false
        }
    }

    /// Il nostro formato sugli appunti: un frammento di documento, che conserva note, font e funzioni.
    private static let fragmentType = NSPasteboard.PasteboardType("local.griffr.fragment")

    /// Il testo del documento, per le prove.
    var editingText: NSAttributedString { store }

    /// Il testo da leggere: il deposito.
    var documentText: NSAttributedString { store }

    /// Mette la selezione negli appunti in tre forme: il frammento nel nostro formato (per incollare qui senza
    /// perdere le note), e per le altre applicazioni testo formattato e testo semplice con le note in coda.
    private func copySelection() -> Bool {
        let range = selection.range
        guard range.length > 0, let storage = textStorage else { return false }
        let fragment = storage.identifiedFragment(in: range)
        let flattened = TextStyling.flattenedForExport(fragment)
        let pasteboard = self.pasteboard
        pasteboard.clearContents()
        pasteboard.setData(DocumentFormat.data(for: Document(attributedString: fragment, settings: settings)), forType: Self.fragmentType)
        if let rtf = flattened.rtf(from: NSRange(location: 0, length: flattened.length), documentAttributes: [:]) { pasteboard.setData(rtf, forType: .rtf) }
        pasteboard.setString(flattened.string, forType: .string)
        objectClipboard = ObjectClipboard(store: ObjectIdentifier(storage), changeCount: pasteboard.changeCount)
        return true
    }

    /// Incolla un pezzo che viene da un documento: le definizioni che usa e che qui mancano (o che si è scelto di
    /// copiare con un altro nome) entrano nel documento, e il testo dopo. Un passo solo di «Annulla».
    private func pasteFragment(_ fragment: NSAttributedString, from source: Document, replacing range: NSRange, joinsParagraph: Bool,
                               policy: DefinitionImport.Policy, clipboardCount: Int? = nil) {
        let merged = DefinitionImport.merge(fragment, from: source, into: settings, policy: policy)
        let text = NSMutableAttributedString(attributedString: merged.text)
        let sameDocument = clipboardCount != nil && objectClipboard?.changeCount == clipboardCount
            && objectClipboard?.store == ObjectIdentifier(store)
        let validCut = sameDocument && clipboardCount == pasteboard.changeCount
        let moving = validCut ? objectClipboard?.removed ?? [] : []
        let movingParagraphs = validCut ? objectClipboard?.paragraphs ?? [] : []
        let movingSections = validCut ? objectClipboard?.sections ?? [] : []
        let movingTables = validCut ? objectClipboard?.tables ?? [] : []
        if !joinsParagraph {
            text.renewSectionIdentities(keeping: movingSections)
            let owners = pasteOwners(at: range.location)
            text.nestSections(under: owners.last?.mark.id ?? "", depth: owners.count)
        }
        FloatingIdentity.preparePaste(text, into: store, sameDocument: sameDocument, moving: moving)
        var copiedParagraphs: [NSRange] = []
        text.enumerateAttribute(.paragraphIdentity, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let id = (value as? String).flatMap(UUID.init(uuidString:)), !movingParagraphs.contains(id) else { return }
            copiedParagraphs.append(range)
        }
        for range in copiedParagraphs { text.removeAttribute(.paragraphIdentity, range: range) }
        if joinsParagraph, let storage = textStorage, let item = TextStyling.listItem(in: storage, at: range.location) {
            text.addAttribute(.listItem, value: item.encoded, range: NSRange(location: 0, length: text.length))
        }
        endUndoStep(next: .none)
        document?.undoManager?.beginUndoGrouping()
        if merged.styles != settings.styles || merged.lists != settings.lists || merged.floatStyles != settings.floatStyles {
            changeListSettings(lists: merged.lists, noteList: nil, styles: merged.styles, floatStyles: merged.floatStyles, actionName: "Paste")
        }
        // La sezione a cui appartiene il testo che seguirà il pezzo, prima di incollare (dopo, il pezzo potrebbe averlo preso).
        let after = min(NSMaxRange(range), store.length)
        let owner = joinsParagraph || store.length == 0 ? nil : SectionEditing.enclosing(in: store, at: after).last?.mark.id ?? ""
        insertFormatted(text, replacing: range, actionName: "Paste", keepingTableIdentities: movingTables)
        if validCut, text.length > 0 || range.length > 0 {
            objectClipboard = ObjectClipboard(store: ObjectIdentifier(store), changeCount: pasteboard.changeCount)
        }
        // Il testo che seguiva resta alla sua sezione: una sezione incollata porta solo il suo contenuto.
        if let owner, text.string.last.map({ $0.isNewline }) == true {
            let end = range.location + text.length
            writeStore(actionName: nil, breakingUndo: false) { SectionEditing.keepParagraph(at: end, in: owner, text: $0) }
        }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName("Paste")
        apply(TextSelection(caret: range.location + text.length))
    }

    /// Le sezioni in cui finisce ciò che si incolla in `location`: quelle del testo che precede (all'inizio di un
    /// paragrafo il pezzo va prima di lui, quindi conta ciò che sta prima: un titolo o un ritorno non valgono ancora).
    private func pasteOwners(at location: Int) -> [SectionEditing.Title] {
        guard location > 0, store.length > 0 else { return [] }
        let start = TextStyling.bodyParagraph(in: store, at: min(location, store.length - 1)).range.location
        return SectionEditing.enclosing(in: store, at: location == start || location >= store.length ? location - 1 : location)
    }

    /// Chiede che cosa fare dei nomi che il testo incollato usa e che il documento definisce in un altro modo.
    private func askAboutPasteConflicts(_ conflicts: [DefinitionImport.Conflict], then finish: @escaping (DefinitionImport.Policy?) -> Void) {
        guard let window else { return finish(.keepDestination) }
        func describe(_ conflict: DefinitionImport.Conflict) -> String {
            switch conflict.kind {
            case .style: "the style “\(conflict.name)”"
            case .list: "the list “\(conflict.name)”"
            case .floatStyle: "the series “\(conflict.name)”"
            }
        }
        var names = conflicts.prefix(6).map(describe)
        if conflicts.count > 6 { names.append("\(conflicts.count - 6) more") }
        let alert = NSAlert()
        alert.messageText = "The pasted text uses definitions that differ here"
        alert.informativeText = "This document already has " + names.joined(separator: ", ")
            + ", but with another definition. The text can take this document's (what was set by hand stays),"
            + " or bring its own as a copy with another name, for example “\(conflicts[0].name) (2)”."
        alert.addButton(withTitle: "Use This Document's")
        alert.addButton(withTitle: "Add Renamed Copies")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: finish(.keepDestination)
            case .alertSecondButtonReturn: finish(.renameCopies)
            default: finish(nil)
            }
        }
    }

    /// Il pulsante «Lorem»: circa due pagine di prosa italiana in Garamond Premier Pro, con tre titoletti, al posto della
    /// selezione. Entra come un pezzo incollato: i titoletti aprono sezioni interne a quella in cui si trova il cursore.
    @objc func insertLorem(_ sender: Any?) {
        guard noteAnchor == nil else { return }
        let fragment = LoremText.document(settings: settings, resolver: fontRoleResolver)
        let text = NSMutableAttributedString(attributedString: fragment.attributedString().text)
        pasteFragment(text, from: fragment, replacing: selection.range, joinsParagraph: false, policy: .keepDestination)
        document?.undoManager?.setActionName("Lorem")
        window?.makeFirstResponder(pagesView)
    }

    private func paste() -> Bool {
        let pasteboard = self.pasteboard
        endUndoStep(next: .none)
        if noteAnchor != nil {
            // In una nota si incolla solo il testo, con lo stile della nota: una nota non ne contiene altre.
            guard let string = pasteboard.string(forType: .string) else { return false }
            pagesInsert(string, replacementRange: selection.range)
        } else if let data = pasteboard.data(forType: Self.fragmentType), let fragment = try? DocumentFormat.document(from: data) {
            let text = NSMutableAttributedString(attributedString: fragment.attributedString().text)
            let range = selection.range
            // Un pezzo di un solo paragrafo entra nel paragrafo in cui lo si incolla, senza portarsi dietro il suo elenco.
            let joinsParagraph = !text.string.contains(where: \.isNewline)
            if joinsParagraph {
                let all = NSRange(location: 0, length: text.length)
                text.removeAttribute(.finalParagraphList, range: all)
                text.removeAttribute(.listItem, range: all)
                text.removeSectionMarks()
            }
            let conflicts = DefinitionImport.conflicts(of: text, from: fragment, into: settings)
            let clipboardCount = pasteboard.changeCount
            let targetStore = ObjectIdentifier(store)
            let finish: (DefinitionImport.Policy?) -> Void = { [weak self] policy in
                guard let self, let policy, ObjectIdentifier(self.store) == targetStore, self.selection.range == range else { return }
                self.pasteFragment(text, from: fragment, replacing: range, joinsParagraph: joinsParagraph, policy: policy, clipboardCount: clipboardCount)
            }
            if conflicts.isEmpty {
                finish(.keepDestination)
            } else if let choose = choosePasteConflictPolicy {
                choose(conflicts, finish)
            } else {
                askAboutPasteConflicts(conflicts, then: finish)
            }
            return true
        } else {
            // Da un'altra applicazione: testo formattato (con i suoi font), o semplice con gli attributi di scrittura.
            let range = selection.range
            var text: NSAttributedString?
            if let data = pasteboard.data(forType: .rtfd) { text = NSAttributedString(rtfd: data, documentAttributes: nil) }
            if text == nil, let data = pasteboard.data(forType: .rtf) { text = NSAttributedString(rtf: data, documentAttributes: nil) }
            if text == nil, let string = pasteboard.string(forType: .string) { text = NSAttributedString(string: string, attributes: typingAttributes) }
            guard let text else { return false }
            insertFormatted(text, replacing: range, actionName: "Paste")
            apply(TextSelection(caret: range.location + text.length))
            return true
        }
        document?.undoManager?.setActionName("Paste")
        endUndoStep(next: .none)
        return true
    }

    func pagesValidate(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.delete(_:)):
            return selection.range.length > 0
        case #selector(NSText.paste(_:)):
            return pasteboard.availableType(from: [Self.fragmentType, .rtfd, .rtf, .string]) != nil
        case #selector(NSResponder.selectAll(_:)):
            return store.length > 0
        case #selector(NSTextView.changeFont(_:)):
            return true
        case Selector(("undo:")):
            if isDesigningParagraph { return canUndoParagraphDesign }
            return (document as? NSDocument)?.undoManager?.canUndo == true || pendingStyles != nil
        case Selector(("redo:")):
            if isDesigningParagraph { return canRedoParagraphDesign }
            return (document as? NSDocument)?.undoManager?.canRedo == true
        default:
            return false
        }
    }
}
