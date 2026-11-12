import AppKit
import Typesetting

/// Le note dichiarate dagli stili (una nota dopo la quinta parola…): il loro testo si scrive qui, per il capoverso del
/// cursore. Il testo sta nel registro del documento (`Document.declaredNoteTexts`), non nel testo dei capoversi: resta
/// anche quando la nota è sospesa, e torna con la sua parola.
extension EditorWindowController {
    /// Una nota dichiarata del capoverso del cursore: l'occorrenza, se è presentata (il segno) e la parola dichiarata.
    struct DeclaredNoteEntry {
        let slot: DeclaredNoteSlot
        let word: Int
        let mark: String?
    }

    /// Le note che lo stile del capoverso del cursore dichiara, presentate o sospese, dalla base allo stile assegnato.
    func declaredNotesAtSelection() -> [DeclaredNoteEntry] {
        guard noteAnchor == nil, store.length > 0 else { return [] }
        let location = min(selection.range.location, store.length)
        guard TableEditing.cell(at: min(location, store.length - 1), in: store) == nil else { return [] }
        let paragraph = store.paragraphID(at: location)
        // Il deposito risolve gli agganci con le definizioni correnti dell'editor.
        store.settings.styles = settings.styles
        let declarations = Dictionary(settings.styles.styles.flatMap { style in style.declaredNotes.map { ($0.id, $0.word) } },
                                      uniquingKeysWith: { first, _ in first })
        let placed = currentLayout()?.declaredNotes ?? []
        return store.declaredNotePositions(in: paragraph).map { slot, position in
            let mark = position == nil ? nil : placed.first {
                $0.paragraphID == slot.paragraph && $0.declaration == slot.declaration && $0.declaringStyle == slot.declaringStyle
            }?.mark
            return DeclaredNoteEntry(slot: slot, word: declarations[slot.declaration] ?? 0, mark: mark)
        }
    }

    /// Insert › Declared Note Text…: un campo per ogni nota dichiarata del capoverso.
    @objc func editDeclaredNoteText(_ sender: Any?) {
        let entries = declaredNotesAtSelection()
        guard !entries.isEmpty else { NSSound.beep(); return }
        if let answers = declaredNoteTextAnswerForTests {
            applyDeclaredNoteTexts(Array(zip(entries.map(\.slot), answers)))
            return
        }
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = entries.count == 1 ? "Declared Note" : "Declared Notes"
        alert.informativeText = entries.count == 1
            ? "The paragraph's style places this note after a word. The note keeps its text while its word is missing."
            : "The paragraph's style places these notes after a word. A note keeps its text while its word is missing."
        let rows = entries.map { entry in
            let state = entry.mark.map { $0.isEmpty ? "Shown" : "Note " + $0 } ?? "Suspended"
            return ("\(state) · after word \(entry.word) · \(entry.slot.declaringStyle)", settings.declaredNoteTexts[entry.slot] ?? "")
        }
        let (accessory, fields) = sheetRows(rows, width: 340, placeholder: "Text of the note")
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = fields.first
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let slots = entries.map(\.slot)
        let source = ObjectIdentifier(store)
        alert.beginSheetModal(for: window) { [weak self] answer in
            MainActor.assumeIsolated {
                guard answer == .alertFirstButtonReturn, let self, ObjectIdentifier(self.store) == source else { return }
                self.applyDeclaredNoteTexts(Array(zip(slots, fields.map(\.stringValue))))
            }
        }
    }

    /// Scrive i testi nel registro: un passo di Annulla. Un testo vuoto toglie la voce (la nota resta, senza testo).
    func applyDeclaredNoteTexts(_ changes: [(DeclaredNoteSlot, String)]) {
        var texts = settings.declaredNoteTexts
        for (slot, value) in changes {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            texts[slot] = text.isEmpty ? nil : text
        }
        guard texts != settings.declaredNoteTexts else { return }
        endUndoStep(next: .none)
        changeDeclaredNoteTexts(to: texts, actionName: "Declared Note")
    }

    func changeDeclaredNoteTexts(to texts: [DeclaredNoteSlot: String], actionName: String) {
        let old = settings.declaredNoteTexts
        guard texts != old else { return }
        document?.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.changeDeclaredNoteTexts(to: old, actionName: actionName) }
        }
        document?.undoManager?.setActionName(actionName)
        settings.declaredNoteTexts = texts
        store.settings.declaredNoteTexts = texts
        layoutPages()
        refreshFromSelection()
    }

    // MARK: Note inattive

    /// Che cosa fare del testo di note la cui dichiarazione sparisce (§10 del modello degli oggetti).
    enum DeclaredTextChoice { case keep, delete, cancel }

    /// I testi del registro che appartengono a dichiarazioni presenti in `old` e assenti in `new` (lo stile tolto, o la
    /// dichiarazione tolta dallo stile).
    func declaredTextsLosingDeclaration(from old: StyleSheet, to new: StyleSheet) -> [DeclaredNoteSlot] {
        func pairs(_ sheet: StyleSheet) -> Set<String> {
            Set(sheet.styles.flatMap { style in style.declaredNotes.map { style.name + "\n" + $0.id.uuidString } })
        }
        let removed = pairs(old).subtracting(pairs(new))
        guard !removed.isEmpty else { return [] }
        return settings.declaredNoteTexts.keys
            .filter { removed.contains($0.declaringStyle + "\n" + $0.declaration.uuidString) }
            .sorted { $0.paragraph.uuidString < $1.paragraph.uuidString }
    }

    /// Chiede se conservare il testo come note inattive o eliminarlo. Conservare è la scelta predefinita.
    func askAboutDeclaredTexts(count: Int) -> DeclaredTextChoice {
        if let answer = declaredTextChoiceForTests { return answer }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "A declared note has text" : "\(count) declared notes have text"
        alert.informativeText = (count == 1
            ? "The declaration that places this note goes away. Keep its text as an inactive note"
            : "The declaration that places these notes goes away. Keep their text as inactive notes")
            + " (Insert › Inactive Declared Notes… finds it again), or delete it. Undo restores either choice."
        alert.addButton(withTitle: count == 1 ? "Keep as Inactive Note" : "Keep as Inactive Notes")
        alert.addButton(withTitle: "Delete the Text")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keep
        case .alertSecondButtonReturn: return .delete
        default: return .cancel
        }
    }

    /// Le note del registro che nessun capoverso presenta né tiene sospese: il loro capoverso non c'è più, o il suo stile
    /// non le dichiara più. Il testo resta, e l'autore lo ritrova qui.
    func inactiveDeclaredNotes() -> [DeclaredNoteSlot] {
        let texts = settings.declaredNoteTexts
        guard !texts.isEmpty else { return [] }
        var active: Set<DeclaredNoteSlot> = []
        for span in store.paragraphSpans where span.range.length > 0 {
            let name = store.attribute(.paragraphStyleName, at: span.range.location, effectiveRange: nil) as? String
            for (declaringStyle, declaration) in settings.styles.declaredNotes(ofParagraphStyle: name) {
                active.insert(DeclaredNoteSlot(paragraph: span.id.persistent, declaringStyle: declaringStyle, declaration: declaration.id))
            }
        }
        return texts.keys.filter { !active.contains($0) }.sorted {
            ($0.declaringStyle, $0.paragraph.uuidString) < ($1.declaringStyle, $1.paragraph.uuidString)
        }
    }

    /// Insert › Inactive Declared Notes…: il testo di ciascuna, modificabile; un campo vuotato lo elimina.
    @objc func editInactiveDeclaredNotes(_ sender: Any?) {
        let slots = inactiveDeclaredNotes()
        guard !slots.isEmpty else { NSSound.beep(); return }
        if let answers = declaredNoteTextAnswerForTests {
            applyDeclaredNoteTexts(Array(zip(slots, answers)))
            return
        }
        guard let window else { return }
        let paragraphs = Set(store.paragraphIDs.map(\.persistent))
        let alert = NSAlert()
        alert.messageText = "Inactive Declared Notes"
        alert.informativeText = "No paragraph shows these notes: their paragraph is gone, or its style no longer declares them. Empty a field to delete that text."
        let rows = slots.map { slot in
            let reason = paragraphs.contains(slot.paragraph) ? "its paragraph's style no longer declares it" : "its paragraph is gone"
            return ("Declared by “\(slot.declaringStyle)” · \(reason)", settings.declaredNoteTexts[slot] ?? "")
        }
        let (accessory, fields) = sheetRows(rows, width: 360, placeholder: "")
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = fields.first
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let source = ObjectIdentifier(store)
        alert.beginSheetModal(for: window) { [weak self] answer in
            MainActor.assumeIsolated {
                guard answer == .alertFirstButtonReturn, let self, ObjectIdentifier(self.store) == source else { return }
                self.applyDeclaredNoteTexts(Array(zip(slots, fields.map(\.stringValue))))
            }
        }
    }

    /// Le righe dei fogli delle note: per ciascuna un'etichetta (che va a capo alla larghezza del campo) e un campo.
    /// Le misure sono esplicite: un foglio di avviso non dà all'autolayout l'altezza giusta, e l'etichetta si taglierebbe.
    private func sheetRows(_ rows: [(label: String, text: String)], width: CGFloat, placeholder: String) -> (NSView, [NSTextField]) {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        var pieces: [(label: NSTextField, labelHeight: CGFloat, field: NSTextField)] = []
        for row in rows {
            let label = NSTextField(wrappingLabelWithString: row.label)
            label.font = font
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = width
            let labelHeight = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 16)
            let field = NSTextField(string: row.text)
            field.placeholderString = placeholder
            pieces.append((label, labelHeight, field))
        }
        let fieldHeight: CGFloat = 22, gap: CGFloat = 3, rowGap: CGFloat = 10
        let height = pieces.reduce(0) { $0 + $1.labelHeight + gap + fieldHeight } + rowGap * CGFloat(max(pieces.count - 1, 0))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        // Dall'alto in basso; le coordinate della vista crescono verso l'alto.
        var top = height
        for piece in pieces {
            top -= piece.labelHeight
            piece.label.frame = NSRect(x: 0, y: top, width: width, height: piece.labelHeight)
            top -= gap + fieldHeight
            piece.field.frame = NSRect(x: 0, y: top, width: width, height: fieldHeight)
            top -= rowGap
            view.addSubview(piece.label)
            view.addSubview(piece.field)
        }
        return (view, pieces.map(\.field))
    }
}
