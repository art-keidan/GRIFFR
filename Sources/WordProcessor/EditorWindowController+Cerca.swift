import AppKit
import CoreText
import Typesetting
import UniformTypeIdentifiers

extension EditorWindowController {
    // MARK: Cerca e sostituisci


    func connectFindBar() {
        findBar.view.isHidden = true
        findBar.onChange = { [weak self] in self?.refreshSearch(moving: true) }
        findBar.onNext = { [weak self] in self?.moveToMatch(forward: true) }
        findBar.onPrevious = { [weak self] in self?.moveToMatch(forward: false) }
        findBar.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        findBar.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
        findBar.onClose = { [weak self] in self?.closeFindBar() }
    }

    /// Modifica › Trova › Cerca e sostituisci… (⌘F), e il pulsante della barra: apre la barra con il cursore nel campo
    /// di ricerca. Una selezione di una riga diventa ciò che si cerca.
    @objc func showFindBar(_ sender: Any?) {
        takeSelectionForFind()
        findBar.view.isHidden = false
        window?.makeFirstResponder(findBar.searchField)
        refreshSearch(moving: false)
    }

    /// Modifica › Trova › Usa la selezione per cercare.
    @objc func useSelectionForFind(_ sender: Any?) {
        takeSelectionForFind()
        refreshSearch(moving: false)
    }

    func takeSelectionForFind() {
        guard selection.range.length > 0 else { return }
        let selected = (store.string as NSString).substring(with: selection.range)
        guard !selected.contains(where: \.isNewline), !selected.contains("\u{FFFC}") else { return }
        findBar.searchField.stringValue = selected
    }

    @objc func findNext(_ sender: Any?) { moveToMatch(forward: true) }
    @objc func findPrevious(_ sender: Any?) { moveToMatch(forward: false) }

    func closeFindBar() {
        findBar.view.isHidden = true
        searchMatches = []
        pagesView.searchRanges = []
        window?.makeFirstResponder(pagesView)
    }

    /// Ricalcola le occorrenze. Vero se ciò che si cerca è valido (un modello può non esserlo).
    @discardableResult
    func computeMatches() -> Bool {
        do {
            searchMatches = try TextSearch.matches(of: findBar.query, in: store, options: findBar.options)
            return true
        } catch {
            searchMatches = []
            return false
        }
    }

    /// Ricalcola le occorrenze e le mostra. Con `moving` (mentre si scrive ciò che si cerca) sceglie la prima a
    /// partire dal cursore.
    func refreshSearch(moving: Bool) {
        let valid = computeMatches()
        pagesView.searchRanges = isFindBarVisible ? searchMatches : []
        guard valid else {
            findBar.showCount("Invalid pattern", warning: true)
            return
        }
        if moving, let first = searchMatches.first(where: { $0.location >= selection.range.location }) ?? searchMatches.first {
            apply(TextSelection(anchor: first.location, head: NSMaxRange(first)))
        }
        updateFindCount()
    }

    func updateFindCount() {
        if findBar.query.isEmpty {
            findBar.showCount("")
        } else if searchMatches.isEmpty {
            findBar.showCount("No matches")
        } else if let index = searchMatches.firstIndex(of: selection.range) {
            findBar.showCount("\(index + 1) of \(searchMatches.count)")
        } else {
            findBar.showCount(searchMatches.count == 1 ? "1 match" : "\(searchMatches.count) matches")
        }
    }

    /// Va all'occorrenza dopo (o prima) della selezione; dall'ultima si ricomincia dalla prima.
    func moveToMatch(forward: Bool) {
        guard !findBar.query.isEmpty else {
            showFindBar(nil)
            return
        }
        guard computeMatches(), !searchMatches.isEmpty else {
            NSSound.beep()
            refreshSearch(moving: false)
            return
        }
        let current = selection.range
        let target = forward
            ? searchMatches.first { current.length == 0 ? $0.location >= current.location : $0.location > current.location } ?? searchMatches[0]
            : searchMatches.last { $0.location < current.location } ?? searchMatches[searchMatches.count - 1]
        apply(TextSelection(anchor: target.location, head: NSMaxRange(target)))
        pagesView.searchRanges = isFindBarVisible ? searchMatches : []
        updateFindCount()
    }

    /// Sostituisce l'occorrenza selezionata e va alla successiva; se la selezione non è un'occorrenza, prima ci va.
    func replaceCurrentMatch() {
        guard computeMatches() else { return refreshSearch(moving: false) }
        guard let match = searchMatches.first(where: { $0 == selection.range }) else { return moveToMatch(forward: true) }
        guard let replacement = try? TextSearch.replacement(for: match, in: store, query: findBar.query, template: findBar.template, options: findBar.options) else { return }
        let attributes = store.attributes(at: match.location, effectiveRange: nil)
        endUndoStep(next: .none)
        _ = writeStore(actionName: "Replace") { TableEditing.replace(match, in: $0, with: NSAttributedString(string: replacement, attributes: attributes)) }
        apply(TextSelection(caret: match.location + (replacement as NSString).length))
        if computeMatches(), !searchMatches.isEmpty { moveToMatch(forward: true) } else { refreshSearch(moving: false) }
    }

    /// Sostituisce tutte le occorrenze, in un passo solo di «Annulla»; ciascuna prende l'aspetto del suo primo carattere.
    func replaceAllMatches() {
        guard computeMatches() else { return refreshSearch(moving: false) }
        guard !searchMatches.isEmpty else { return NSSound.beep() }
        var replacements: [(NSRange, NSAttributedString)] = []
        for match in searchMatches {
            guard let text = try? TextSearch.replacement(for: match, in: store, query: findBar.query, template: findBar.template, options: findBar.options) else { return }
            replacements.append((match, NSAttributedString(string: text, attributes: store.attributes(at: match.location, effectiveRange: nil))))
        }
        endUndoStep(next: .none)
        _ = writeStore(actionName: "Replace All") { store in
            // Una sostituzione non unisce due celle (gli a capo tra le celle restano).
            for (range, text) in replacements.reversed() { TableEditing.replace(range, in: store, with: text) }
        }
        apply(TextSelection(caret: min(selection.range.location, store.length)))
        refreshSearch(moving: false)
        findBar.showCount(replacements.count == 1 ? "1 replaced" : "\(replacements.count) replaced")
    }

    // MARK: Controllo ortografico

    /// Chiede al correttore di sistema, dopo una breve pausa, quali parole non riconosce.
    func scheduleSpellCheck() {
        pendingSpellCheck?.cancel()
        guard checksSpelling else {
            pagesView.misspelledRanges = []
            return
        }
        // Mentre il testo cambia, le sottolineature già note seguirebbero posizioni vecchie: si tolgono e si rifanno.
        let work = DispatchWorkItem { [weak self] in self?.checkSpelling() }
        pendingSpellCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func checkSpelling() {
        pendingSpellCheck = nil
        guard checksSpelling else { return }
        let string = documentText.string as NSString
        // Si cerca un errore dopo l'altro con la chiamata classica del correttore. Quella unificata
        // (`check(_:range:types:…)`) dentro questa app non restituisce errori di ortografia, pur funzionando
        // da riga di comando sullo stesso testo: provato, causa non chiarita.
        var ranges: [NSRange] = []
        for run in spellingRuns() {
            // Ogni tratto si controlla da solo, nella sua lingua.
            let piece = string.substring(with: run.range)
            var start = 0
            while start < run.range.length, ranges.count < 2000 {
                let found = NSSpellChecker.shared.checkSpelling(
                    of: piece, startingAt: start, language: run.language, wrap: false, inSpellDocumentWithTag: spellTag, wordCount: nil)
                guard found.location != NSNotFound, found.length > 0, found.location >= start else { break }
                ranges.append(NSRange(location: run.range.location + found.location, length: found.length))
                start = NSMaxRange(found)
            }
        }
        // La parola che si sta ancora scrivendo non si segnala.
        let caret = selection.isEmpty ? selection.head : NSNotFound
        pagesView.misspelledRanges = ranges.filter { !(caret >= $0.location && caret <= NSMaxRange($0)) }
    }

    /// La lingua del testo in una posizione: quella assegnata a quel testo, altrimenti quella del documento.
    func language(at index: Int) -> String? {
        guard let storage = textStorage, index < storage.length else { return settings.language }
        return (storage.attribute(.language, at: index, effectiveRange: nil) as? String) ?? settings.language
    }

    /// I tratti di testo da controllare, ciascuno con la lingua da dare al correttore (`nil`: decide il sistema).
    /// Il testo in una lingua per cui il Mac non ha un dizionario (latino, greco antico, sanscrito) resta fuori.
    func spellingRuns() -> [(range: NSRange, language: String?)] {
        let text = documentText
        var runs: [(range: NSRange, language: String?)] = []
        text.enumerateAttribute(.language, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            var language: String?
            if let code = (value as? String) ?? settings.language {
                guard let known = Self.spellingLanguage(for: code) else { return }
                language = known
            }
            if let last = runs.last, last.language == language, NSMaxRange(last.range) == range.location {
                runs[runs.count - 1].range.length += range.length
            } else {
                runs.append((range, language))
            }
        }
        return runs
    }

    /// Accende o spegne la correzione ortografica in tutte le finestre; si ricorda alla prossima apertura.
    @objc func toggleSpellChecking(_ sender: Any?) {
        checksSpelling.toggle()
        var editors = NSApp.windows.compactMap { $0.windowController as? EditorWindowController }
        // Una finestra non ancora elencata (nelle prove) va aggiornata comunque.
        if !editors.contains(where: { $0 === self }) { editors.append(self) }
        for editor in editors {
            (editor.bandControls["correzione"] as? NSButton)?.state = checksSpelling ? .on : .off
            editor.refreshBandState()
            editor.scheduleSpellCheck()
        }
    }

    @objc func replaceMisspelling(_ sender: NSMenuItem) {
        guard let (range, replacement) = sender.representedObject as? (NSRange, String) else { return }
        endUndoStep(next: .none)
        writeStore(actionName: "Correction") { $0.replaceCharacters(in: range, with: replacement) }
        setSelection(TextSelection(caret: range.location + (replacement as NSString).length))
    }

    @objc func ignoreSpelling(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: spellTag)
        checkSpelling()
    }

    @objc func learnSpelling(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }
        NSSpellChecker.shared.learnWord(word)
        checkSpelling()
    }

    func pagesContextMenu(at index: Int) -> NSMenu? {
        let menu = NSMenu()
        if let range = pagesView.misspelledRanges.first(where: { index >= $0.location && index <= NSMaxRange($0) }) {
            let string = documentText.string as NSString
            let word = string.substring(with: range)
            // Il clic destro su una parola segnalata la seleziona, come nelle altre app.
            apply(TextSelection(anchor: range.location, head: NSMaxRange(range)))
            let guesses = NSSpellChecker.shared.guesses(forWordRange: range, in: string as String, language: language(at: range.location).flatMap(Self.spellingLanguage), inSpellDocumentWithTag: spellTag) ?? []
            if guesses.isEmpty {
                menu.addItem(withTitle: "No Suggestions", action: nil, keyEquivalent: "")
            }
            for guess in guesses.prefix(8) {
                let item = menu.addItem(withTitle: guess, action: #selector(replaceMisspelling(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (range, guess)
            }
            menu.addItem(.separator())
            for (title, action) in [("Ignore Spelling", #selector(ignoreSpelling(_:))), ("Learn Spelling", #selector(learnSpelling(_:)))] {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = word
            }
            menu.addItem(.separator())
        } else if !selection.range.contains(index), !(selection.isEmpty && selection.head == index) {
            apply(TextSelection(caret: index))
        }
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        if selectedImage != nil {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Image Size…", action: #selector(editImageSize(_:)), keyEquivalent: "").target = self
        }
        if selectedField == nil, index < store.length, store.attribute(.field, at: index, effectiveRange: nil) != nil {
            apply(TextSelection(anchor: index, head: index + 1))
        }
        if let selectedField {
            menu.addItem(.separator())
            menu.addItem(withTitle: selectedField.field.asFormula == nil ? "Edit Object Reference…" : "Edit Field Formula…", action: #selector(editFieldFormula(_:)), keyEquivalent: "").target = self
        }
        return menu
    }

    /// Ricompone dopo una breve pausa, così una raffica di tasti produce una sola ricomposizione.
    func scheduleLayout() {
        pendingLayout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.layoutPages() }
        pendingLayout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Dopo ogni modifica del testo.
    func textChanged() {
        // Si ricompone subito, così il cursore nella pagina non resta indietro di un tasto: dalla tappa 4.5 si
        // ricompongono solo i paragrafi cambiati (8 ms per un tasto su 85 pagine). Solo un testo enorme aspetta una
        // pausa nella scrittura.
        if (textStorage?.length ?? 0) < 1_000_000 { layoutPages() } else { scheduleLayout() }
        // Con la ricerca aperta, le occorrenze seguono il testo.
        if isFindBarVisible { refreshSearch(moving: false) }
        // Dopo un annullamento il cursore può restare dov'era mentre l'elenco del suo paragrafo è cambiato.
        syncListTypingAttributes()
    }

    /// Le immagini collegate che non si trovano più: un avviso con i loro percorsi. Al loro posto c'è un riquadro grigio.
    func reportMissingImages() {
        var missing: [String] = []
        store.enumerateAttribute(.inlineImage, in: NSRange(location: 0, length: store.length)) { value, _, _ in
            if let image = (value as? ImageAttachment)?.image, case .linked(let path) = image.source, !FileManager.default.fileExists(atPath: path), !missing.contains(path) { missing.append(path) }
        }
        guard !missing.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = missing.count == 1 ? "A linked image cannot be found" : "\(missing.count) linked images cannot be found"
        alert.informativeText = missing.joined(separator: "\n") + "\n\nA gray box is shown in their place. Putting the file back brings the image back."
        DispatchQueue.main.async { alert.beginSheetModal(for: window) }
    }
}
