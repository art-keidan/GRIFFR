import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Fase 4: il deposito, dove si scrive, resta coerente; annullando tutto si torna al testo di partenza.
@Suite("Scrittura nel deposito", .serialized) @MainActor
struct StoreEditingTests {
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ bound: Int) -> Int { bound <= 0 ? 0 : Int(next() % UInt64(bound)) }
    }

    @Test("Scrivendo, i paragrafi che non cambiano conservano la loro identità")
    func identities() {
        let h = EditorHarness(paragraphs: ["uno", "due", "tre"])
        defer { h.close() }
        let ids = h.editor.store.paragraphIDs
        h.select(5)
        h.type("xyz")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.editor.store.paragraphIDs.first == ids[0])
        #expect(h.editor.store.paragraphIDs.contains(ids[1]) && h.editor.store.paragraphIDs.contains(ids[2]))
    }

    @Test("Spostare un capoverso conserva testo e identità; Annulla e Ripeti fanno un passo solo")
    func moveParagraph() {
        let h = EditorHarness(paragraphs: ["uno", "due", "tre"])
        defer { h.close() }
        let store = h.editor.store
        let ids = store.paragraphIDs
        let original = NSAttributedString(attributedString: h.attributed)

        var moved: NSRange?
        h.editor.writeStore(actionName: "Sposta il capoverso") { moved = $0.moveParagraph(ids[0], .after, ids[2]) }
        #expect(h.text == "due\ntre\nuno")
        #expect(store.paragraphIDs == [ids[1], ids[2], ids[0]])
        #expect(moved == store.range(of: ids[0]))
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.text == "uno\ndue\ntre", "dopo Annulla: \(h.text)")
        #expect(h.attributed.isEqual(to: original) && store.paragraphIDs == ids, "differenza: \(String(describing: TextStyling.firstDifference(h.attributed, original)))")
        h.redo()
        #expect(h.text == "due\ntre\nuno" && store.paragraphIDs == [ids[1], ids[2], ids[0]])

        h.undo()
        h.editor.writeStore(actionName: "Sposta il capoverso") { _ = $0.moveParagraph(ids[2], .before, ids[1]) }
        #expect(h.text == "uno\ntre\ndue" && store.paragraphIDs == [ids[0], ids[2], ids[1]], "dopo il secondo spostamento: \(h.text)")
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original) && store.paragraphIDs == ids, "differenza: \(String(describing: TextStyling.firstDifference(h.attributed, original)))")

        let finalEmpty = DocumentStore(text: NSAttributedString(string: "uno\ndue\n"))
        let finalIDs = finalEmpty.paragraphIDs
        _ = finalEmpty.moveParagraph(finalIDs[0], .after, finalIDs[1])
        #expect(finalEmpty.string == "due\nuno\n" && finalEmpty.paragraphIDs == [finalIDs[1], finalIDs[0], finalIDs[2]])
        #expect(finalEmpty.structuralProblem() == nil)
    }

    @Test("Spostare una sezione porta testo e sottosezioni; entrare in un'altra cambia la profondità con un solo Annulla")
    func moveSection() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let document = try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <section id="a" role="capitolo"><title><p>Alfa</p></title><p>Testo di Alfa.</p>
        <section id="aa" role="sezione"><title><p>Alfa interna</p></title><p>Testo interno.</p></section></section>
        <section id="b" role="capitolo"><title><p>Beta</p></title><p>Testo di Beta.</p></section>
        </document>
        """)
        h.editor.replaceContent(document)
        let store = h.editor.store
        let ids = store.paragraphIDs
        let original = NSAttributedString(attributedString: h.attributed)
        #expect(ids.count == 6)

        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .after, ids[4]) }
        #expect(h.text == "Beta\nTesto di Beta.\nAlfa\nTesto di Alfa.\nAlfa interna\nTesto interno.")
        #expect(store.paragraphIDs == [ids[4], ids[5], ids[0], ids[1], ids[2], ids[3]])
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original) && store.paragraphIDs == ids)

        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .inside, ids[4]) }
        #expect(h.text == "Beta\nTesto di Beta.\nAlfa\nTesto di Alfa.\nAlfa interna\nTesto interno.")
        let titles = SectionEditing.titles(in: store)
        #expect(titles.map(\.depth) == [1, 2, 3])
        #expect(titles.map(\.mark.id) == ["b", "a", "aa"])
        #expect(titles.allSatisfy { $0.mark.depth == $0.depth })
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original) && store.paragraphIDs == ids)
        h.redo()
        #expect(SectionEditing.titles(in: store).map(\.depth) == [1, 2, 3])

        h.undo()
        #expect(store.moveSection(ids[0], .inside, ids[2]) == nil, "una sezione non può entrare in una propria sottosezione")
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("I discendenti scalano fino al livello 4; lo stile è quello che dichiara il livello, qualunque nome abbia")
    func moveSectionUpdatesStyles() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let document = try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Speciale" target="paragraph" outline-level="2"/></styles>
        <section id="a" role="capitolo"><title><p>Alfa</p></title>
        <section id="aa" role="sezione"><title><p style="Speciale">Alfa interna</p></title>
        <section id="aaa" role="sezione"><title><p>Alfa più interna</p></title></section></section></section>
        <section id="b" role="capitolo"><title><p>Beta</p></title></section>
        </document>
        """)
        h.editor.replaceContent(document)
        let store = h.editor.store
        let ids = store.paragraphIDs
        let original = NSAttributedString(attributedString: h.attributed)
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .inside, ids[3]) }
        let titles = SectionEditing.titles(in: store)
        #expect(titles.map(\.depth) == [1, 2, 3, 4])
        #expect(titles.map { store.attribute(.paragraphStyleName, at: $0.range.location, effectiveRange: nil) as? String }
                == [nil, "Speciale", "Heading 3", "Heading 4"],
                "Beta resta com'era; Alfa prende «Speciale», l'unico stile di livello 2; i livelli 3 e 4 nascono, ciascuno basato sul precedente")
        #expect(store.settings.styles.style(named: "Heading 3")?.basedOn == "Speciale")
        #expect(titles.map { (store.attribute(.outlineLevel, at: $0.range.location, effectiveRange: nil) as? NSNumber)?.intValue }
                == [1, 2, 3, 4])
        #expect(store.settings.styles.style(named: "Heading 4")?.values.outlineLevel == 4)
        #expect(store.settings.styles.style(named: "Speciale")?.values.outlineLevel == 2, "la definizione personalizzata non cambia")
        let saved = store.document
        // Nel file il livello dei titoli è l'annidamento: riaperto, ogni titolo ha di nuovo il livello della sua profondità.
        #expect(try DocumentFormat.document(from: DocumentFormat.data(for: saved)) == saved)
        let reopened = DocumentStore(document: saved)
        #expect(SectionEditing.titles(in: reopened).map { (reopened.attribute(.outlineLevel, at: $0.range.location, effectiveRange: nil) as? NSNumber)?.intValue }
                == [1, 2, 3, 4])
        h.undo()
        #expect(h.attributed.isEqual(to: original))
        #expect(store.settings.styles.style(named: "Heading 4") == nil)
        h.redo()
        #expect(store.settings.styles.style(named: "Heading 4")?.values.outlineLevel == 4)
        #expect(SectionEditing.titles(in: store).map(\.depth) == [1, 2, 3, 4])
    }

    @Test("Azioni casuali nell'editor: il deposito resta coerente, e annullando tutto si torna al testo di partenza", arguments: [21, 22, 23])
    func randomEditing(seed: Int) {
        let h = EditorHarness(paragraphs: ["Prima riga di prova", "Seconda riga", "Terza"])
        defer { h.close() }
        randomEdits(h, seed: seed, styles: ["Body", "Quotation", "Example", "Heading 1"])
    }

    @Test("Azioni casuali in un documento con i ritorni: editor e modello vedono la stessa struttura, Annulla fino all'inizio",
          arguments: [31, 32, 33, 34, 35])
    func randomEditingWithReturns(seed: Int) throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        _ = try returning(h)
        h.step()
        randomEdits(h, seed: seed, styles: ["Body", "Heading 1", "Heading 2"]) { action in
            let store = h.editor.store
            // Un ritorno senza senso può restare finché una modifica non tocca i segni (come i segni di titolo ripetuti):
            // non conta. Conta che l'editor e il modello vedano la stessa struttura.
            func preorder(_ sections: [Section]) -> [String] { sections.flatMap { [$0.id] + preorder($0.sections) } }
            let editorView = SectionEditing.titles(in: store).filter { $0.range.length > 0 || $0.range.location == store.length }.map(\.mark.id)
            let document = h.editor.currentDocument()
            let back = Document(attributedString: document.attributedString().text, settings: document.settingsOnly)
            if back.sections != document.sections || back.blocks != document.blocks { return "il modello non fa andata e ritorno dopo «\(action)»" }
            if preorder(document.sections) != editorView { return "editor \(editorView) e modello \(preorder(document.sections)) diversi dopo «\(action)»" }
            return nil
        }
    }

    private func randomEdits(_ h: EditorHarness, seed: Int, styles: [String], check: (String) -> String? = { _ in nil }) {
        var random = Random(state: UInt64(seed) * 6_700_417)
        let start = NSAttributedString(attributedString: h.attributed)
        for step in 0..<120 {
            let length = h.text.utf16.count
            var action = ""
            switch random.int(12) {
            case 0, 1, 2:
                let words = ["a", "è", "bc ", "Ελλάς", "x"]
                let word = words[random.int(words.count)]
                action = "scrive \(word)"
                h.type(word)
            case 3:
                action = "cancella"
                h.press(#selector(NSResponder.deleteBackward(_:)))
            case 4:
                action = "a capo"
                h.press(#selector(NSResponder.insertNewline(_:)))
            case 5:
                let location = random.int(length + 1)
                action = "cursore a \(location)"
                h.select(location)
            case 6:
                let location = random.int(length + 1)
                let extent = random.int(min(length - location, 15) + 1)
                action = "seleziona \(location)+\(extent)"
                h.select(location, length: extent)
            case 7:
                if h.editor.noteAnchor == nil {
                    action = "nota"
                    h.editor.insertFootnote(nil)
                    h.step()
                } else {
                    action = "esce dalla nota"
                    h.press(#selector(NSResponder.cancelOperation(_:)))
                }
            case 8:
                let style = styles[random.int(styles.count)]
                action = "stile \(style)"
                h.editor.applyNamedStyle(.paragraph, name: style)
                h.step()
            case 9:
                action = "elenco"
                _ = h.editor.changeList(actionName: "Elenco") { $0 == nil ? ListItem(marker: "1.") : nil }
                h.step()
            case 10:
                action = "copia e incolla"
                h.menu(#selector(NSText.copy(_:)))
                h.menu(#selector(NSText.paste(_:)))
            default:
                action = "annulla"
                h.undo()
            }
            if let problem = h.editor.store.structuralProblem() {
                Issue.record("seme \(seed), passo \(step): dopo «\(action)» il deposito non è coerente: \(problem)")
                return
            }
            if let problem = check(action) {
                Issue.record("seme \(seed), passo \(step): \(problem)")
                return
            }
        }
        // Annullando tutto (il testo di partenza era già lì quando si è cominciato) si torna a lui, carattere per carattere.
        var undos = 0
        while h.document.undoManager?.canUndo == true, undos < 500 {
            h.undo()
            undos += 1
        }
        #expect(h.attributed.isEqual(to: start), "seme \(seed): dopo \(undos) annullamenti il testo non è quello di partenza")
    }

    // MARK: Il livello di paragrafazione segue la profondità della sezione (tappa 1)

    /// Alfa e Beta capitoli; Alfa ha una sottosezione; ogni sezione ha un capoverso in «Testo».
    private func alfaBeta(_ h: EditorHarness) throws -> DocumentStore {
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Body" target="paragraph"/>
        <style name="Heading 1" target="paragraph" based-on="Body" size="18" outline-level="1"/>
        <style name="Heading 2" target="paragraph" based-on="Body" size="14" outline-level="2"/>
        <style name="Heading 3" target="paragraph" based-on="Body" size="13" outline-level="3"/></styles>
        <section id="a" role="capitolo"><title><p style="Heading 1">Alfa</p></title><p style="Body">Testo di Alfa.</p>
        <section id="aa" role="sezione"><title><p style="Heading 2">Alfa interna</p></title><p style="Body">Testo interno.</p></section></section>
        <section id="b" role="capitolo"><title><p style="Heading 1">Beta</p></title><p style="Body">Testo di Beta.</p></section>
        </document>
        """))
        return h.editor.store
    }

    /// Per ogni paragrafo: testo, stile e livello registrato.
    private func levels(_ store: DocumentStore) -> [String] {
        var result: [String] = []
        let string = store.string as NSString
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let text = string.substring(with: range).trimmingCharacters(in: .newlines)
            let style = store.attribute(.paragraphStyleName, at: range.location, effectiveRange: nil) as? String ?? "-"
            let level = (store.attribute(.outlineLevel, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue ?? -1
            result.append("\(text)|\(style)|\(level)")
            location = NSMaxRange(range)
        }
        return result
    }

    @Test("Alfa dentro Beta: Alfa diventa livello 2 e «Titolo 2», la sua interna livello 3 e «Titolo 3», il Testo non cambia; fuori di nuovo risalgono")
    func alfaIntoBetaAndBack() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try alfaBeta(h)
        #expect(levels(store) == ["Alfa|Heading 1|1", "Testo di Alfa.|Body|0", "Alfa interna|Heading 2|2", "Testo interno.|Body|0",
                                  "Beta|Heading 1|1", "Testo di Beta.|Body|0"])
        let original = NSAttributedString(attributedString: h.attributed)
        let ids = store.paragraphIDs
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .inside, ids[4]) }
        #expect(levels(store) == ["Beta|Heading 1|1", "Testo di Beta.|Body|0", "Alfa|Heading 2|2", "Testo di Alfa.|Body|0",
                                  "Alfa interna|Heading 3|3", "Testo interno.|Body|0"])
        #expect(h.editor.settings.styles == store.settings.styles, "l'editor ha la stessa copia degli stili")
        #expect(store.structuralProblem() == nil)

        // Riportata fuori, sorella di Beta: tutto risale di un gradino.
        h.step()
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .after, ids[4]) }
        #expect(levels(store) == ["Beta|Heading 1|1", "Testo di Beta.|Body|0", "Alfa|Heading 1|1", "Testo di Alfa.|Body|0",
                                  "Alfa interna|Heading 2|2", "Testo interno.|Body|0"])
        h.undo()
        #expect(levels(store) == ["Beta|Heading 1|1", "Testo di Beta.|Body|0", "Alfa|Heading 2|2", "Testo di Alfa.|Body|0",
                                  "Alfa interna|Heading 3|3", "Testo interno.|Body|0"])
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Dopo uno spostamento dalla mappa e dopo Annulla, lo stile mostrato è quello del titolo, anche se il cursore resta allo stesso carattere")
    func mapMoveRefreshesTypingStyle() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        _ = try alfaBeta(h)
        func shownStyle() -> String? { h.editor.typingAttributes[.paragraphStyleName] as? String }
        func item(_ title: String) throws -> OutlineItem {
            h.editor.refreshObjectTree()
            func find(_ list: [OutlineItem]) -> OutlineItem? {
                for item in list {
                    if item.title == title { return item }
                    if let found = item.children.flatMap(find) { return found }
                }
                return nil
            }
            return try #require(find(h.editor.objectTree.items))
        }
        h.editor.moveOutlineItem(try item("Alfa"), to: try item("Beta"), placement: .inside)
        #expect(shownStyle() == "Heading 2")
        let inside = h.editor.selection.range.location
        h.step()
        // Alfa esce dopo Beta: il titolo ricomincia allo stesso carattere, ma ora è «Titolo 1».
        h.editor.moveOutlineItem(try item("Alfa"), to: try item("Beta"), placement: .after)
        #expect(h.editor.selection.range.location == inside)
        #expect(shownStyle() == "Heading 1")
        h.undo()
        #expect(shownStyle() == "Heading 2")
    }

    @Test("Dare a un titolo lo stile di un altro livello sposta la sezione a quel livello, con il suo contenuto (come la mappa)")
    func styleMovesSectionToItsLevel() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Body" target="paragraph"/>
        <style name="Heading 1" target="paragraph" based-on="Body" size="18" outline-level="1"/>
        <style name="Heading 2" target="paragraph" based-on="Body" size="14" outline-level="2"/>
        <style name="Heading 3" target="paragraph" based-on="Body" size="13" outline-level="3"/></styles>
        <section id="a" role="capitolo"><title><p style="Heading 1">Alfa</p></title><p style="Body">Testo di Alfa.</p>
        <section id="a1" role="sezione"><title><p style="Heading 2">Alfa uno</p></title><p style="Body">Testo di uno.</p>
        <section id="a11" role="sezione"><title><p style="Heading 3">Alfa uno uno</p></title><p style="Body">Testo di uno uno.</p></section></section>
        <section id="a2" role="sezione"><title><p style="Heading 2">Alfa due</p></title><p style="Body">Testo di due.</p></section></section>
        <section id="b" role="capitolo"><title><p style="Heading 1">Beta</p></title><p style="Body">Testo di Beta.</p></section>
        </document>
        """))
        let store = h.editor.store
        let original = NSAttributedString(attributedString: h.attributed)
        func give(_ style: String, to id: String) throws {
            let title = try #require(SectionEditing.titles(in: store).first { $0.mark.id == id })
            h.select(title.range.location)
            h.editor.applyNamedStyle(.paragraph, name: style)
            h.step()
        }
        func outline() -> [String] { SectionEditing.titles(in: store).map { "\($0.mark.id)@\($0.depth)" } }

        // «Titolo 1» ad Alfa uno: esce da Alfa con la sua interna, dopo Alfa; Alfa due resta in Alfa.
        try give("Heading 1", to: "a1")
        #expect(outline() == ["a@1", "a2@2", "a1@1", "a11@2", "b@1"])
        #expect(levels(store) == ["Alfa|Heading 1|1", "Testo di Alfa.|Body|0", "Alfa due|Heading 2|2", "Testo di due.|Body|0",
                                  "Alfa uno|Heading 1|1", "Testo di uno.|Body|0", "Alfa uno uno|Heading 2|2", "Testo di uno uno.|Body|0",
                                  "Beta|Heading 1|1", "Testo di Beta.|Body|0"])
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original), "un solo passo di Annulla")

        // Da 3 a 1 in un colpo: dopo il capitolo che la conteneva.
        try give("Heading 1", to: "a11")
        #expect(outline() == ["a@1", "a1@2", "a2@2", "a11@1", "b@1"])
        h.undo()

        // Più dentro: Alfa due con «Titolo 3» diventa l'ultima interna di Alfa uno, la sorella che la precede.
        try give("Heading 3", to: "a2")
        #expect(outline() == ["a@1", "a1@2", "a11@3", "a2@3", "b@1"])
        h.undo()

        // Beta con «Titolo 3»: due gradini più dentro, prima in Alfa, poi nella sua ultima interna (Alfa due).
        try give("Heading 3", to: "b")
        #expect(outline() == ["a@1", "a1@2", "a11@3", "a2@2", "b@3"])
        h.undo()

        // Alfa con «Titolo 2»: non ha una sorella prima, resta al livello 1 e lo stile segue quello possibile.
        try give("Heading 2", to: "a")
        #expect(outline() == ["a@1", "a1@2", "a11@3", "a2@2", "b@1"])
        #expect(levels(store).first == "Alfa|Heading 1|1")
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Scheda Stili › Livello: cambiare il livello di uno stile sposta i titoli che lo usano, in un passo di Annulla")
    func stylesTabLevelMovesTitles() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try alfaBeta(h)
        let original = NSAttributedString(attributedString: h.attributed)
        let originalSheet = h.editor.settings.styles
        h.editor.stylesTab.onOutlineLevel?("Heading 2", 1)
        h.step()
        #expect(h.editor.settings.styles.resolveParagraph(styleName: "Heading 2").outlineLevel == 1)
        #expect(SectionEditing.titles(in: store).map { "\($0.mark.id)@\($0.depth)" } == ["a@1", "aa@1", "b@1"])
        #expect(levels(store)[2] == "Alfa interna|Heading 2|1")
        #expect(h.undoActionName == "Style “Heading 2”: level")
        h.undo()
        #expect(h.attributed.isEqual(to: original))
        #expect(h.editor.settings.styles == originalSheet, "Annulla rimette anche lo stile")
        // «Nessuno»: lo stile non dichiara più un livello; i titoli restano dove sono.
        h.editor.stylesTab.onOutlineLevel?("Heading 2", 0)
        h.step()
        #expect(h.editor.settings.styles.resolveParagraph(styleName: "Heading 2").outlineLevel == nil)
        #expect(SectionEditing.titles(in: store).map { "\($0.mark.id)@\($0.depth)" } == ["a@1", "aa@2", "b@1"])
    }

    @Test("Uno stile che dichiara un livello, anche senza «Apre una sezione», è uno stile di titolo: non toglie la sezione")
    func levelAloneMakesAHeadingStyle() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try alfaBeta(h)
        let inner = try #require(SectionEditing.titles(in: store).first { $0.mark.id == "aa" })
        h.select(inner.range.location)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 1")
        h.step()
        #expect(levels(store) == ["Alfa|Heading 1|1", "Testo di Alfa.|Body|0", "Alfa interna|Heading 1|1", "Testo interno.|Body|0",
                                  "Beta|Heading 1|1", "Testo di Beta.|Body|0"])
        // Un capoverso del corpo con «Titolo 2» diventa una sezione di livello 2.
        h.step()
        let body = (store.string as NSString).range(of: "Testo di Beta.")
        h.select(body.location)
        h.editor.applyNamedStyle(.paragraph, name: "Heading 2")
        h.step()
        #expect(levels(store).last == "Testo di Beta.|Heading 2|2")
        #expect(store.structuralProblem() == nil)
    }

    // MARK: La fine della sezione nell'editor (tappa 2)

    /// Un capitolo con due interne; dopo la prima il testo torna al capitolo, dopo il capitolo fuori da ogni sezione.
    private func returning(_ h: EditorHarness) throws -> DocumentStore {
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Body" target="paragraph"/>
        <style name="Heading 1" target="paragraph" based-on="Body" size="18" outline-level="1"/>
        <style name="Heading 2" target="paragraph" based-on="Body" size="14" outline-level="2"/></styles>
        <p>Premessa.</p>
        <section id="c" role="capitolo"><title><p style="Heading 1">Capitolo</p></title><p>Primo.</p>
        <section id="s" role="sezione"><title><p style="Heading 2">Sotto</p></title><p>Testo di sotto.</p></section>
        <p>Secondo.</p>
        <section id="t" role="sezione"><title><p style="Heading 2">Altra</p></title><p>Testo di altra.</p></section>
        </section>
        <p>Postfazione.</p>
        <section id="d" role="capitolo"><title><p style="Heading 1">Dopo</p></title><p>Testo di dopo.</p></section>
        </document>
        """))
        return h.editor.store
    }

    /// Le sezioni che contengono il paragrafo che comincia con `word`.
    private func owners(_ store: DocumentStore, _ word: String) -> [String] {
        let at = (store.string as NSString).range(of: word).location
        return SectionEditing.enclosing(in: store, at: at).map(\.mark.id)
    }

    @Test("Con i ritorni: profondità, sezioni che contengono un paragrafo ed estensione delle sezioni")
    func returnsStructure() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        #expect(SectionEditing.titles(in: store).map { "\($0.mark.id)@\($0.depth)" } == ["c@1", "s@2", "t@2", "d@1"])
        #expect(owners(store, "Primo.") == ["c"] && owners(store, "Testo di sotto.") == ["c", "s"])
        #expect(owners(store, "Secondo.") == ["c"], "torna al capitolo")
        #expect(owners(store, "Postfazione.") == [], "fuori da ogni capitolo")
        let titles = SectionEditing.titles(in: store)
        func spanText(_ id: String) -> String {
            (store.string as NSString).substring(with: SectionEditing.range(of: titles.first { $0.mark.id == id }!, in: store))
        }
        #expect(spanText("s") == "Sotto\nTesto di sotto.\n", "la sezione finisce dove il testo torna")
        #expect(spanText("c").hasSuffix("Testo di altra.\n") && !spanText("c").contains("Postfazione"))
        #expect(SectionEditing.contents(of: titles[0], in: store).paragraphs == 6)
        // Il modello dell'editor è quello del file.
        let document = h.editor.currentDocument()
        #expect(document.sections.first?.sections.first?.afterward.count == 1 && document.sections.first?.afterward.count == 1)
    }

    @Test("Spostare una sezione con i ritorni: porta solo il suo contenuto; il testo che tornava resta alla sezione esterna")
    func returnsWhenMoving() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        let ids = store.paragraphIDs
        func id(_ word: String) -> DocumentStore.ParagraphID { store.paragraphID(at: (store.string as NSString).range(of: word).location) }

        // Sotto dopo Altra: «Secondo.» resta del capitolo (il suo ritorno, ora inutile, si toglie).
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(id("Sotto"), .after, id("Altra")) }
        #expect(h.text.components(separatedBy: "\n").prefix(8) == ["Premessa.", "Capitolo", "Primo.", "Secondo.", "Altra", "Testo di altra.", "Sotto", "Testo di sotto."])
        #expect(owners(store, "Secondo.") == ["c"] && owners(store, "Testo di sotto.") == ["c", "s"])
        #expect(store.attribute(.sectionReturn, at: (store.string as NSString).range(of: "Secondo.").location, effectiveRange: nil) == nil)
        #expect(owners(store, "Postfazione.") == [], "la postfazione resta fuori")
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // Altra prima di Sotto: «Secondo.» continua a tornare al capitolo, ora dopo Sotto.
        h.step()
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(id("Altra"), .before, id("Sotto")) }
        #expect(owners(store, "Secondo.") == ["c"] && owners(store, "Testo di altra.") == ["c", "t"])
        h.undo()

        // Sotto dentro Dopo: porta solo il suo testo.
        h.step()
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(id("Sotto"), .inside, id("Dopo")) }
        #expect(owners(store, "Testo di sotto.") == ["d", "s"] && owners(store, "Secondo.") == ["c"] && owners(store, "Postfazione.") == [])
        h.undo()
        #expect(h.attributed.isEqual(to: original))
        _ = ids
    }

    @Test("La mappa con i ritorni: il testo che torna sta sotto la sezione esterna, dopo l'interna")
    func returnsInMap() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        _ = try returning(h)
        h.editor.refreshObjectTree()
        let items = h.editor.objectTree.items
        #expect(items.map(\.title) == ["Premessa.", "Capitolo", "Postfazione.", "Dopo"])
        let chapter = try #require(items.first { $0.title == "Capitolo" })
        #expect(chapter.children?.map(\.title) == ["Primo.", "Sotto", "Secondo.", "Altra"])
        #expect(chapter.children?[1].children?.map(\.title) == ["Testo di sotto."])
    }

    @Test("Trascinare con i ritorni: un sottocapitolo fra i capoversi del capitolo porta solo il suo contenuto; un capoverso dopo un'interna torna")
    func returnsWhenDragging() throws {
        let saved = EditorWindowController.showsObjectTree
        defer { EditorWindowController.showsObjectTree = saved }
        EditorWindowController.showsObjectTree = true
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.setInterfaceMode(.advanced)
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        let tree = h.editor.objectTree
        func item(_ title: String) throws -> OutlineItem {
            h.editor.refreshObjectTree()
            func find(_ list: [OutlineItem]) -> OutlineItem? {
                for item in list {
                    if item.title == title { return item }
                    if let found = item.children.flatMap(find) { return found }
                }
                return nil
            }
            return try #require(find(tree.items))
        }
        func drop(_ source: String, _ parent: String?, _ index: Int) throws {
            let moving = try item(source)
            let target = try #require(tree.dropBetween(source: moving.id, parent: try parent.map { try item($0).id }, index: index))
            tree.onMoveItem?(moving, target.target, target.placement)
            h.step()
            h.editor.refreshObjectTree()
        }
        func children(_ title: String) throws -> [String] { try item(title).children?.map(\.title) ?? [] }

        // Altra davanti a «Primo.»: Primo resta al capitolo, dopo Altra.
        try drop("Altra", "Capitolo", 0)
        #expect(try children("Capitolo") == ["Altra", "Primo.", "Sotto", "Secondo."])
        #expect(try children("Altra") == ["Testo di altra."])
        #expect(h.editor.store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // Sotto davanti a «Postfazione.» (primo livello): diventa capitolo; la postfazione resta fuori.
        h.step()
        try drop("Sotto", nil, 2)
        h.editor.refreshObjectTree()
        #expect(tree.items.map(\.title) == ["Premessa.", "Capitolo", "Sotto", "Postfazione.", "Dopo"])
        #expect(try children("Sotto") == ["Testo di sotto."])
        #expect(try children("Capitolo") == ["Primo.", "Secondo.", "Altra"])
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // «Testo di dopo.» dopo Sotto, al livello del capitolo: torna al capitolo.
        h.step()
        try drop("Testo di dopo.", "Capitolo", 2)
        #expect(try children("Capitolo") == ["Primo.", "Sotto", "Testo di dopo.", "Secondo.", "Altra"])
        #expect(try children("Sotto") == ["Testo di sotto."])
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // «Secondo.», che torna, portato dentro Sotto: non porta con sé il ritorno, e nulla resta in Sotto per sbaglio.
        h.step()
        try drop("Secondo.", "Sotto", 1)
        #expect(try children("Sotto") == ["Testo di sotto.", "Secondo."])
        #expect(try children("Capitolo") == ["Primo.", "Sotto", "Altra"])
        h.undo()

        // Un tratto che torna con due capoversi: portato via il primo, il secondo resta al capitolo.
        h.step()
        h.select((h.text as NSString).range(of: "Secondo.").location + "Secondo.".count)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("Terzo.")
        h.step()
        #expect(try children("Capitolo") == ["Primo.", "Sotto", "Secondo.", "Terzo.", "Altra"])
        try drop("Secondo.", "Altra", 1)
        #expect(try children("Capitolo") == ["Primo.", "Sotto", "Terzo.", "Altra"], "il ritorno passa a «Terzo.»")
        #expect(try children("Altra") == ["Testo di altra.", "Secondo."])
        #expect(store.structuralProblem() == nil)
    }

    @Test("Inserisci › Torna a… / Entra in…: dove si possono dare, che cosa fanno, Annulla")
    func returnCommands() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }
        func titles(at word: String) -> (String?, String?) {
            h.select(at(word))
            return (h.editor.returnMenuTitle(), h.editor.joinMenuTitle())
        }
        #expect(titles(at: "Testo di sotto.") == ("Back to “Capitolo”", nil))
        #expect(titles(at: "Secondo.") == (nil, "Into “Sotto”"), "dopo «Secondo.» il capitolo ha ancora Altra: non torna più su")
        #expect(titles(at: "Primo.") == (nil, nil), "dopo «Primo.» il capitolo ha sezioni interne")
        #expect(titles(at: "Postfazione.") == (nil, "Into “Altra”"))
        #expect(titles(at: "Testo di dopo.") == ("Back Out of the Sections", nil))
        #expect(titles(at: "Premessa.") == (nil, nil) && titles(at: "Sotto") == (nil, nil))

        // «Testo di sotto.» torna al capitolo: Sotto resta con il solo titolo.
        h.select(at("Testo di sotto."))
        h.editor.returnToOuterSection(nil)
        h.step()
        #expect(owners(store, "Testo di sotto.") == ["c"] && owners(store, "Secondo.") == ["c"])
        #expect(h.undoActionName == "Back to the Outer Section")
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // «Secondo.» entra in Sotto.
        h.step()
        h.select(at("Secondo."))
        h.editor.joinPreviousSection(nil)
        h.step()
        #expect(owners(store, "Secondo.") == ["c", "s"])
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // «Testo di dopo.» fuori da ogni sezione.
        h.step()
        h.select(at("Testo di dopo."))
        h.editor.returnToOuterSection(nil)
        h.step()
        #expect(owners(store, "Testo di dopo.") == [])
        #expect(h.editor.currentDocument().sections.last?.afterward.count == 1)
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Togli la sezione con i ritorni: il testo che tornava a lei torna a quella che la conteneva")
    func removeSectionWithReturns() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        h.select((h.text as NSString).range(of: "Primo.").location)
        h.editor.removeEnclosingSection(nil)
        h.step()
        #expect(SectionEditing.titles(in: store).map { "\($0.mark.id)@\($0.depth)" } == ["s@1", "t@1", "d@1"])
        #expect(owners(store, "Primo.") == [] && owners(store, "Testo di sotto.") == ["s"])
        #expect(owners(store, "Secondo.") == [], "tornava al capitolo tolto: ora fuori da ogni sezione, non dentro Sotto")
        #expect(owners(store, "Postfazione.") == [])
        #expect(store.structuralProblem() == nil)
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Copia e incolla con i ritorni: le sezioni incollate diventano interne di quella in cui si incolla e portano solo il loro contenuto")
    func returnsWhenPasting() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        func copy(from first: String, through last: String) {
            let string = h.text as NSString
            let start = string.range(of: first).location
            h.select(start, length: NSMaxRange(string.range(of: last + "\n")) - start)
            #expect(h.menu(#selector(NSText.copy(_:))))
        }
        func paste(at word: String, backwards: Bool = false) {
            h.select((h.text as NSString).range(of: word, options: backwards ? .backwards : []).location)
            #expect(h.menu(#selector(NSText.paste(_:))))
            h.step()
        }
        func ids() -> [String] { SectionEditing.titles(in: store).map { ["c", "s", "t", "d"].contains($0.mark.id) ? "\($0.mark.id)@\($0.depth)" : "nuova@\($0.depth)" } }
        func check() {
            let document = h.editor.currentDocument()
            let back = Document(attributedString: document.attributedString().text, settings: document.settingsOnly)
            #expect(back.sections == document.sections && back.blocks == document.blocks)
            #expect(store.structuralProblem() == nil)
        }

        // Altra e la postfazione, incollate all'inizio del testo di Dopo: Altra diventa interna di Dopo, la postfazione
        // (che tornava fuori dalla sezione copiata) torna a Dopo, e il testo di Dopo resta di Dopo.
        copy(from: "Altra", through: "Postfazione.")
        paste(at: "Testo di dopo.")
        #expect(ids() == ["c@1", "s@2", "t@2", "d@1", "nuova@2"])
        let pasted = (h.text as NSString).range(of: "Postfazione.", options: .backwards).location
        #expect(SectionEditing.enclosing(in: store, at: pasted).map(\.mark.id) == ["d"])
        #expect(owners(store, "Testo di dopo.") == ["d"])
        check()
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // Altra con il suo testo, incollata all'inizio di «Primo.»: interna del capitolo; «Primo.» resta del capitolo.
        h.step()
        copy(from: "Altra", through: "Testo di altra.")
        paste(at: "Primo.")
        #expect(ids() == ["c@1", "nuova@2", "s@2", "t@2", "d@1"])
        #expect(owners(store, "Primo.") == ["c"], "non finisce nella sezione incollata")
        check()
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // La stessa, all'inizio di «Secondo.» (che torna al capitolo): va in fondo a Sotto, e «Secondo.» resta del capitolo.
        h.step()
        paste(at: "Secondo.")
        #expect(ids() == ["c@1", "s@2", "nuova@3", "t@2", "d@1"])
        #expect(owners(store, "Secondo.") == ["c"])
        check()
        h.undo()
        #expect(h.attributed.isEqual(to: original))

        // Un capoverso senza il titolo della sezione a cui tornava: il ritorno non viaggia.
        h.step()
        copy(from: "Secondo.", through: "Secondo.")
        paste(at: "Testo di sotto.")
        #expect(SectionEditing.enclosing(in: store, at: (h.text as NSString).range(of: "Secondo.").location).map(\.mark.id) == ["c", "s"])
        #expect(owners(store, "Testo di sotto.") == ["c", "s"])
        check()
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Con i ritorni: Invio e la cancellazione del confine")
    func returnsWhenTyping() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try returning(h)
        let original = NSAttributedString(attributedString: h.attributed)
        func at(_ word: String) -> Int { (h.text as NSString).range(of: word).location }

        // Invio in fondo al testo di Sotto: il paragrafo nuovo resta in Sotto.
        h.select(at("Testo di sotto.") + "Testo di sotto.".count)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("Nuovo in sotto.")
        #expect(owners(store, "Nuovo in sotto.") == ["c", "s"] && owners(store, "Secondo.") == ["c"])
        h.step()

        // Invio in fondo a «Secondo.»: il paragrafo nuovo resta nel capitolo, e il ritorno non si raddoppia.
        h.select(at("Secondo.") + "Secondo.".count)
        h.press(#selector(NSResponder.insertNewline(_:)))
        h.type("Terzo.")
        #expect(owners(store, "Terzo.") == ["c"] && owners(store, "Secondo.") == ["c"])
        #expect(store.attribute(.sectionReturn, at: at("Terzo."), effectiveRange: nil) == nil)
        h.step()

        // Invio all'inizio di «Secondo.»: tutti e due nel capitolo.
        h.select(at("Secondo."))
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(owners(store, "Secondo.") == ["c"])
        #expect(SectionEditing.enclosing(in: store, at: at("Secondo.") - 1).map(\.mark.id) == ["c"], "il paragrafo vuoto prima")
        #expect(store.structuralProblem() == nil)
        h.step()

        // Cancellare il confine all'inizio di «Postfazione.»: si unisce all'ultimo paragrafo di Altra, e ne fa parte.
        h.select(at("Postfazione."))
        h.press(#selector(NSResponder.deleteBackward(_:)))
        #expect(owners(store, "Testo di altra.") == ["c", "t"])
        #expect(h.text.contains("Testo di altra.Postfazione."))
        #expect(SectionEditing.titles(in: store).map(\.mark.id) == ["c", "s", "t", "d"])
        #expect(store.structuralProblem() == nil)

        for _ in 0..<12 where h.document.undoManager?.canUndo == true { h.undo() }
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("«Più dentro» e «Più fuori» dall'ispettore cambiano livello e stile del titolo e delle interne, in un passo di Annulla")
    func inspectorDepthChangesLevelAndStyle() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try alfaBeta(h)
        let original = NSAttributedString(attributedString: h.attributed)
        let beta = try #require(SectionEditing.titles(in: store).last)
        h.editor.writeStore(actionName: "Sezione più dentro") { SectionEditing.moveSection(beta, by: 1, in: $0) }
        #expect(levels(store) == ["Alfa|Heading 1|1", "Testo di Alfa.|Body|0", "Alfa interna|Heading 2|2", "Testo interno.|Body|0",
                                  "Beta|Heading 2|2", "Testo di Beta.|Body|0"])
        h.step()
        let deeper = try #require(SectionEditing.titles(in: store).first { $0.mark.id == "aa" })
        h.editor.writeStore(actionName: "Sezione più fuori") { SectionEditing.moveSection(deeper, by: -1, in: $0) }
        #expect(levels(store)[2] == "Alfa interna|Heading 1|1", "più fuori: torna capitolo con lo stile del livello 1")
        h.step()
        h.undo()
        #expect(levels(store)[2] == "Alfa interna|Heading 2|2")
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Togliere una sezione: il titolo non ha più livello, le interne salgono di un gradino con lo stile del loro livello")
    func removingSectionRaisesInner() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try alfaBeta(h)
        let original = NSAttributedString(attributedString: h.attributed)
        let alfa = try #require(SectionEditing.titles(in: store).first)
        h.editor.writeStore(actionName: "Togli la sezione") { SectionEditing.removeSection(alfa, in: $0) }
        #expect(levels(store) == ["Alfa|Heading 1|0", "Testo di Alfa.|Body|0", "Alfa interna|Heading 1|1", "Testo interno.|Body|0",
                                  "Beta|Heading 1|1", "Testo di Beta.|Body|0"])
        h.undo()
        #expect(h.attributed.isEqual(to: original))
    }

    @Test("Un livello oltre i definiti crea lo stile che manca; Annulla lo toglie, anche nella copia dell'editor")
    func deeperLevelCreatesStyleUndoably() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Body" target="paragraph"/>
        <style name="Heading 1" target="paragraph" based-on="Body" size="18" outline-level="1"/>
        <style name="Heading 2" target="paragraph" based-on="Body" size="14" outline-level="2"/>
        <style name="Heading 3" target="paragraph" based-on="Body" size="13" outline-level="3"/></styles>
        <section id="a" role="capitolo"><title><p style="Heading 1">Alfa</p></title>
        <section id="aa" role="sezione"><title><p style="Heading 2">Alfa interna</p></title></section></section>
        <section id="b" role="capitolo"><title><p style="Heading 1">Beta</p></title>
        <section id="bb" role="sezione"><title><p style="Heading 2">Beta interna</p></title></section></section>
        </document>
        """))
        let store = h.editor.store
        let ids = store.paragraphIDs
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .inside, ids[3]) }
        #expect(levels(store) == ["Beta|Heading 1|1", "Beta interna|Heading 2|2", "Alfa|Heading 3|3", "Alfa interna|Heading 4|4"])
        #expect(h.editor.settings.styles.style(named: "Heading 4")?.values.outlineLevel == 4)
        #expect(h.editor.settings.styles.style(named: "Heading 4")?.basedOn == "Heading 3", "prende l'aspetto del livello sopra")
        // Il file si rilegge, e riaperto dà gli stessi livelli.
        let saved = h.editor.currentDocument()
        #expect(try DocumentFormat.document(from: DocumentFormat.data(for: saved)) == saved)
        #expect(levels(DocumentStore(document: saved)) == levels(store))
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Heading 4") == nil && store.settings.styles.style(named: "Heading 4") == nil)
        #expect(levels(store).first == "Alfa|Heading 1|1")
        h.redo()
        #expect(h.editor.settings.styles.style(named: "Heading 4") != nil)
    }

    // MARK: Lo stile si sceglie dal livello dichiarato, non dal nome (tappa 2)

    private func ownNames(_ h: EditorHarness) throws -> DocumentStore {
        h.editor.replaceContent(try DocumentFormat.document(from: """
        <document version="1" font="HoeflerText-Regular" size="12">
        <styles><style name="Body" target="paragraph"/>
        <style name="Capitolo" target="paragraph" based-on="Body" size="18" outline-level="1" opens-section="capitolo"/>
        <style name="Paragrafo" target="paragraph" based-on="Body" size="14" outline-level="2" opens-section="sezione"/>
        <style name="Sottoparagrafo" target="paragraph" based-on="Body" size="13" outline-level="3" opens-section="sezione"/>
        <style name="Heading 2" target="paragraph" based-on="Body" size="20"/>
        <style name="Titolo a mano" target="paragraph" based-on="Body" italic="on"/></styles>
        <section id="a" role="capitolo"><title><p style="Capitolo">Alfa</p></title><p style="Body">Testo di Alfa.</p>
        <section id="aa" role="sezione"><title><p style="Paragrafo">Alfa interna</p></title></section></section>
        <section id="b" role="capitolo"><title><p style="Capitolo">Beta</p></title>
        <section id="bb" role="sezione"><title><p style="Titolo a mano">Beta interna</p></title></section></section>
        </document>
        """))
        return h.editor.store
    }

    @Test("Con stili dai nomi propri: Alfa dentro Beta diventa «Paragrafo», la sua interna «Sottoparagrafo»; «Titolo 2» senza livello non conta")
    func ownStyleNamesFollowLevel() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try ownNames(h)
        #expect(h.editor.settings.styles.headingStyles(forLevel: 2) == ["Paragrafo"], "il nome «Titolo 2» da solo non dichiara un livello")
        let ids = store.paragraphIDs  // Alfa, Testo di Alfa, Alfa interna, Beta, Beta interna
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .after, ids[3]) }
        h.step()
        #expect(levels(store) == ["Beta|Capitolo|1", "Beta interna|Titolo a mano|2", "Alfa|Capitolo|1", "Testo di Alfa.|Body|0",
                                  "Alfa interna|Paragrafo|2"], "lo spostamento alla pari non cambia nulla")
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[0], .inside, ids[3]) }
        #expect(levels(store) == ["Beta|Capitolo|1", "Beta interna|Titolo a mano|2", "Alfa|Paragrafo|2", "Testo di Alfa.|Body|0",
                                  "Alfa interna|Sottoparagrafo|3"])
        #expect(store.settings.styles.style(named: "Heading 3") == nil, "nessuno stile nuovo: il livello 3 ce l'ha già")
    }

    @Test("Uno stile che non dichiara il livello del titolo è una scelta a mano: resta, e cambia solo il livello")
    func handChosenStyleStays() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try ownNames(h)
        let ids = store.paragraphIDs
        // Beta interna («Titolo a mano», livello 2) entra in Alfa interna: livello 3, lo stile resta.
        h.editor.writeStore(actionName: "Sposta la sezione") { _ = $0.moveSection(ids[4], .inside, ids[2]) }
        #expect(levels(store).contains("Beta interna|Titolo a mano|3"))
    }

    @Test("Dare uno stile di titolo apre la sezione al livello che lo stile dichiara, non a quello del suo ruolo")
    func givingStyleOpensAtDeclaredLevel() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try ownNames(h)
        // «Testo di Alfa.» diventa «Paragrafo»: sezione di livello 2 dentro Alfa, prima di «Alfa interna».
        h.select(("Alfa\n" as NSString).length + 2)
        h.editor.applyNamedStyle(.paragraph, name: "Paragrafo")
        #expect(levels(store)[1] == "Testo di Alfa.|Paragrafo|2")
        #expect(SectionEditing.titles(in: store).map(\.depth) == [1, 2, 2, 1, 2])
    }

    @Test("Uno stile che salterebbe un gradino («Sottoparagrafo» subito dentro un capitolo) dà il livello possibile, e lo stile lo segue")
    func skippedLevelBecomesPossibleOne() throws {
        let h = EditorHarness(paragraphs: ["segnaposto"])
        defer { h.close() }
        let store = try ownNames(h)
        h.select(("Alfa\n" as NSString).length + 2)
        h.editor.applyNamedStyle(.paragraph, name: "Sottoparagrafo")
        #expect(levels(store)[1] == "Testo di Alfa.|Paragrafo|2")
        h.step()
        h.undo()
        #expect(levels(store)[1] == "Testo di Alfa.|Body|0")
    }
}
