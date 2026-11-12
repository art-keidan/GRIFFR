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
        if let answers = declaredNoteContentAnswerForTests {
            applyDeclaredNoteContents(Array(zip(entries.map(\.slot), answers.map(DeclaredNoteText.init(attributedString:)))))
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
            return ("\(state) · after word \(entry.word) · \(entry.slot.declaringStyle)", settings.declaredNoteTexts[entry.slot])
        }
        let (accessory, fields) = sheetRows(rows, width: 360)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = fields.first
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let slots = entries.map(\.slot)
        let source = ObjectIdentifier(store)
        alert.beginSheetModal(for: window) { [weak self] answer in
            MainActor.assumeIsolated {
                guard answer == .alertFirstButtonReturn, let self, ObjectIdentifier(self.store) == source else { return }
                self.applyDeclaredNoteContents(Array(zip(slots, fields.map { DeclaredNoteText(attributedString: $0.attributedString()) })))
            }
        }
    }

    /// L'aspetto di partenza del testo di una nota: quello del corpo, a cinque sesti (12 → 10), come una nota appena
    /// inserita.
    var declaredNoteBaseStyle: CharacterStyle {
        var character = settings.styles.resolveCharacter(paragraphStyle: settings.styles.bodyStyleName, wordStyle: nil, characterStyle: nil,
                                                         base: settings.formulaBase ?? TextStyling.styleBase, resolver: fontRoleResolver)
        character.size = max((character.size * 5 / 6 * 2).rounded() / 2, 4)
        return character
    }

    /// Testi senza formattazione, nell'aspetto di partenza delle note (per le prove e per i testi semplici).
    func applyDeclaredNoteTexts(_ changes: [(DeclaredNoteSlot, String)]) {
        let style = declaredNoteBaseStyle
        applyDeclaredNoteContents(changes.map { ($0.0, DeclaredNoteText($0.1.trimmingCharacters(in: .whitespacesAndNewlines), style: style)) })
    }

    /// Scrive i testi nel registro: un passo di Annulla. Un testo vuoto toglie la voce (la nota resta, senza testo).
    func applyDeclaredNoteContents(_ changes: [(DeclaredNoteSlot, DeclaredNoteText)]) {
        var texts = settings.declaredNoteTexts
        for (slot, value) in changes { texts[slot] = value.isBlank ? nil : value }
        guard texts != settings.declaredNoteTexts else { return }
        endUndoStep(next: .none)
        changeDeclaredNoteTexts(to: texts, actionName: "Declared Note")
    }

    func changeDeclaredNoteTexts(to texts: [DeclaredNoteSlot: DeclaredNoteText], actionName: String) {
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
        if let answers = declaredNoteContentAnswerForTests {
            applyDeclaredNoteContents(Array(zip(slots, answers.map(DeclaredNoteText.init(attributedString:)))))
            return
        }
        guard let window else { return }
        let paragraphs = Set(store.paragraphIDs.map(\.persistent))
        let alert = NSAlert()
        alert.messageText = "Inactive Declared Notes"
        alert.informativeText = "No paragraph shows these notes: their paragraph is gone, or its style no longer declares them. Empty a field to delete that text."
        let rows = slots.map { slot in
            let reason = paragraphs.contains(slot.paragraph) ? "its paragraph's style no longer declares it" : "its paragraph is gone"
            return ("Declared by “\(slot.declaringStyle)” · \(reason)", settings.declaredNoteTexts[slot])
        }
        let (accessory, fields) = sheetRows(rows, width: 360)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = fields.first
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let source = ObjectIdentifier(store)
        alert.beginSheetModal(for: window) { [weak self] answer in
            MainActor.assumeIsolated {
                guard answer == .alertFirstButtonReturn, let self, ObjectIdentifier(self.store) == source else { return }
                self.applyDeclaredNoteContents(Array(zip(slots, fields.map { DeclaredNoteText(attributedString: $0.attributedString()) })))
            }
        }
    }

    /// Le righe dei fogli delle note: per ciascuna un'etichetta (che va a capo), i pulsanti del neretto e del corsivo, e
    /// un campo di testo formattato con il testo della nota. Le misure sono esplicite: un foglio di avviso non dà
    /// all'autolayout l'altezza giusta, e l'etichetta si taglierebbe.
    private func sheetRows(_ rows: [(label: String, text: DeclaredNoteText?)], width: CGFloat) -> (NSView, [NSTextView]) {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let base = TextStyling.characterAttributes(for: declaredNoteBaseStyle).attributes
        let buttonWidth: CGFloat = 28, fieldHeight: CGFloat = 48, gap: CGFloat = 4, rowGap: CGFloat = 10
        let labelWidth = width - 2 * (buttonWidth + 4)
        var pieces: [(label: NSTextField, labelHeight: CGFloat, buttons: [NSButton], scroll: NSScrollView, view: NSTextView)] = []
        for row in rows {
            let label = NSTextField(wrappingLabelWithString: row.label)
            label.font = font
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = labelWidth
            let labelHeight = max(ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: 1000)).height ?? 16), 22)
            let scroll = NSTextView.scrollableTextView()
            scroll.borderType = .bezelBorder
            let view = scroll.documentView as! NSTextView
            view.isRichText = true
            view.allowsUndo = true
            view.typingAttributes = base
            view.textStorage?.setAttributedString(row.text?.attributedString ?? NSAttributedString())
            view.setAccessibilityLabel("Text of the note")
            let buttons: [NSButton] = [("B", NSFontTraitMask.boldFontMask, "Bold"), ("I", NSFontTraitMask.italicFontMask, "Italic")].map { title, trait, name in
                let button = NoteTraitButton(title: title, trait: trait, view: view)
                button.font = trait == .boldFontMask ? .boldSystemFont(ofSize: 13)
                    : NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
                // Un pulsante quadrato alla misura del suo riquadro: il pulsante arrotondato piccolo si riduce a un
                // segno minuscolo.
                button.bezelStyle = .smallSquare
                button.controlSize = .regular
                button.toolTip = name
                button.setAccessibilityLabel(name)
                return button
            }
            pieces.append((label, labelHeight, buttons, scroll, view))
        }
        let height = pieces.reduce(0) { $0 + $1.labelHeight + gap + fieldHeight } + rowGap * CGFloat(max(pieces.count - 1, 0))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        // Dall'alto in basso; le coordinate della vista crescono verso l'alto.
        var top = height
        for piece in pieces {
            top -= piece.labelHeight
            piece.label.frame = NSRect(x: 0, y: top, width: labelWidth, height: piece.labelHeight)
            for (index, button) in piece.buttons.enumerated() {
                button.frame = NSRect(x: labelWidth + 4 + CGFloat(index) * (buttonWidth + 4), y: top - 2, width: buttonWidth, height: 22)
                container.addSubview(button)
            }
            top -= gap + fieldHeight
            piece.scroll.frame = NSRect(x: 0, y: top, width: width, height: fieldHeight)
            top -= rowGap
            container.addSubview(piece.label)
            container.addSubview(piece.scroll)
        }
        return (container, pieces.map(\.view))
    }
}

/// Un pulsante dei fogli delle note che mette o toglie un tratto (neretto, corsivo) al testo scelto nel suo campo, e a
/// quello che si scriverà.
final class NoteTraitButton: NSButton {
    private let trait: NSFontTraitMask
    private weak var view: NSTextView?

    init(title: String, trait: NSFontTraitMask, view: NSTextView) {
        self.trait = trait
        self.view = view
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(toggle(_:))
    }

    required init?(coder: NSCoder) { fatalError("non si legge da un archivio") }

    @objc func toggle(_ sender: Any?) {
        guard let view, let storage = view.textStorage else { return }
        let manager = NSFontManager.shared
        let range = view.selectedRange()
        // Lo stato di partenza è quello del primo carattere scelto (o della scrittura): lo si inverte per tutti.
        let probe = range.length > 0 ? storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : view.typingAttributes[.font] as? NSFont
        let adding = !(probe.map { manager.traits(of: $0).contains(trait) } ?? false)
        func changed(_ font: NSFont) -> NSFont {
            adding ? manager.convert(font, toHaveTrait: trait) : manager.convert(font, toNotHaveTrait: trait)
        }
        if range.length > 0, view.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                if let font = value as? NSFont { storage.addAttribute(.font, value: changed(font), range: run) }
            }
            storage.endEditing()
            view.didChangeText()
        }
        if let font = view.typingAttributes[.font] as? NSFont { view.typingAttributes[.font] = changed(font) }
        view.window?.makeFirstResponder(view)
    }
}
