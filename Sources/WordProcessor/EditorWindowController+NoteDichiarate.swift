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
        alert.informativeText = "The paragraph's style places these notes after a word. A note keeps its text while its word is missing."
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        var fields: [NSTextField] = []
        for entry in entries {
            let state = entry.mark.map { $0.isEmpty ? "Shown" : "Note " + $0 } ?? "Suspended"
            let label = NSTextField(labelWithString: "\(state) · after word \(entry.word) · \(entry.slot.declaringStyle)")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(string: settings.declaredNoteTexts[entry.slot] ?? "")
            field.placeholderString = "Text of the note"
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
            fields.append(field)
        }
        stack.layoutSubtreeIfNeeded()
        stack.frame.size = stack.fittingSize
        alert.accessoryView = stack
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
}
