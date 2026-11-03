import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Il deposito del documento")
    struct DocumentStoreTests {
        nonisolated(unsafe) private static let regular = NSFont(name: "HoeflerText-Regular", size: 12)!
        nonisolated(unsafe) private static let italic = NSFont(name: "HoeflerText-Italic", size: 12)!
        private static let anchor = String(utf16CodeUnits: [FloatingObject.anchorCharacter], count: 1)

        private func plain(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: Self.regular])
        }

        // MARK: Identità

        @Test("Spezzando un paragrafo l'identità resta alla parte con l'inizio; unendo, al primo dei due")
        func splitAndMerge() throws {
            let store = DocumentStore(text: plain("abcdef"))
            let a = try #require(store.paragraphIDs.first)
            store.replaceCharacters(in: NSRange(location: 3, length: 0), with: "\n")
            #expect(store.paragraphIDs.count == 2 && store.paragraphIDs[0] == a)
            #expect(store.range(of: a) == NSRange(location: 0, length: 4))
            let b = store.paragraphIDs[1]
            store.replaceCharacters(in: NSRange(location: 3, length: 1), with: "")
            #expect(store.paragraphIDs == [a], "unendo resta il primo")
            #expect(store.range(of: b) == nil)
            // A capo all'inizio: il testo tiene l'identità, il paragrafo vuoto nuovo ne ha un'altra.
            store.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\n")
            #expect(store.paragraphIDs.count == 2 && store.paragraphIDs[1] == a)
            #expect(store.structuralProblem() == nil)
        }

        @Test("Il paragrafo finale vuoto ha la sua identità, e la conserva quando ci si scrive")
        func finalParagraph() throws {
            let store = DocumentStore(text: plain("abc\n"))
            #expect(store.paragraphIDs.count == 2)
            let final = store.paragraphIDs[1]
            #expect(store.paragraphID(at: 4) == final)
            store.replaceCharacters(in: NSRange(location: 4, length: 0), with: "x")
            #expect(store.paragraphIDs.count == 2 && store.paragraphIDs[1] == final)
            let empty = DocumentStore()
            let only = try #require(empty.paragraphIDs.first)
            empty.replaceCharacters(in: NSRange(location: 0, length: 0), with: plain("uno\ndue"))
            #expect(empty.paragraphIDs.count == 2 && empty.paragraphIDs.contains(only))
            #expect(empty.structuralProblem() == nil)
        }

        @Test("Incollare più paragrafi in mezzo: il paragrafo tiene la parte iniziale; quelli lontani non cambiano")
        func pasteAndDistance() throws {
            let store = DocumentStore(text: plain("uno\ndue\ntre\nquattro"))
            let ids = store.paragraphIDs
            store.replaceCharacters(in: NSRange(location: 5, length: 0), with: plain("X\nY\n"))
            #expect(store.string == "uno\ndXe\nY\nue\ntre\nquattro".replacingOccurrences(of: "dXe", with: "dX\nY\nue").replacingOccurrences(of: "\nY\nue\nY\nue", with: "\nY\nue"))
            #expect(store.paragraphIDs.first == ids[0] && store.paragraphIDs[1] == ids[1])
            #expect(store.paragraphIDs.suffix(2) == ids.suffix(2), "i paragrafi dopo restano gli stessi")
            #expect(store.range(of: ids[3]) == NSRange(location: store.length - 7, length: 7))
            #expect(store.structuralProblem() == nil)
        }

        @Test("Un a capo che entra in una nota smette di dividere i paragrafi, e viceversa")
        func footnoteNewline() throws {
            let store = DocumentStore(text: plain("ab\ncd\nef"))
            let ids = store.paragraphIDs
            store.addAttribute(.footnote, value: true, range: NSRange(location: 2, length: 1))
            #expect(store.paragraphIDs == [ids[0], ids[2]])
            store.removeAttribute(.footnote, range: NSRange(location: 2, length: 1))
            #expect(store.paragraphIDs.count == 3 && store.paragraphIDs[0] == ids[0] && store.paragraphIDs[2] == ids[2])
            #expect(store.structuralProblem() == nil)
        }

        @Test("Il deposito si compone come il testo da cui viene")
        func layout() {
            let text = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Testo con nota", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 12))),
                                               .floating(FloatingObject(runs: [TextRun("Una nota.", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 10))]))])),
                .paragraph(Paragraph(list: ListItem(marker: "1."), inlines: [.text(TextRun("Voce", style: CharacterStyle(fontName: "HoeflerText-Regular", size: 12)))])),
            ]).attributedString().text
            let store = DocumentStore(text: text)
            #expect(store.isEqual(to: text))
            let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false)
            let a = PageLayout.layout(text, options: options), b = PageLayout.layout(store, options: options)
            #expect(a.pages.count == b.pages.count && a.notes == b.notes)
            #expect(a.pages[0].lines.map(\.range) == b.pages[0].lines.map(\.range))
            #expect(a.pages[0].markers.count == b.pages[0].markers.count)
        }

        @Test("Dal modello al deposito e ritorno: contenuto e impostazioni restano gli stessi")
        func documentRoundTrip() throws {
            let sheet = StyleSheet.builtIn
            let style = sheet.resolveCharacter(paragraphStyle: "Esempio", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            let document = Document(language: "it", styles: sheet, lists: ListDefinition.builtIn, noteList: "Note", blocks: [
                .paragraph(Paragraph(styleName: "Esempio", style: sheet.resolveParagraph(styleName: "Esempio"), list: ListItem(listName: "Esempi"),
                                     inlines: [.text(TextRun("Un esempio", style: style)), .floating(FloatingObject(runs: [TextRun("Nota", style: style)]))])),
            ])
            let store = DocumentStore(document: document)
            #expect(store.document == document)
            #expect(store.settings.noteList == "Note")
        }

        @Test("Il primo punto in cui due testi differiscono: per un carattere, per un attributo, per la lunghezza")
        func firstDifference() {
            let a = NSMutableAttributedString(attributedString: plain("abcdef"))
            #expect(TextStyling.firstDifference(a, DocumentStore(text: a)) == nil)
            let b = NSMutableAttributedString(attributedString: a)
            b.replaceCharacters(in: NSRange(location: 3, length: 1), with: "X")
            #expect(TextStyling.firstDifference(a, b) == 3)
            let c = NSMutableAttributedString(attributedString: a)
            c.addAttribute(.footnote, value: true, range: NSRange(location: 4, length: 2))
            #expect(TextStyling.firstDifference(a, c) == 4)
            #expect(TextStyling.firstDifference(a, c, in: NSRange(location: 0, length: 4)) == nil)
            #expect(TextStyling.firstDifference(a, plain("abc")) == 3)
        }

        @Test("La memoria delle righe non restituisce mai righe vecchie: dopo ogni modifica, le pagine sono quelle di una composizione da zero")
        func linesCacheIsNeverStale() {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12), small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
            let long = "Parole che riempiono più righe di un paragrafo giustificato, per vedere se gli a capo cambiano davvero. "
            let text = NSMutableAttributedString(attributedString: Document(lists: ListDefinition.builtIn, noteList: "Note a simboli", blocks: (0..<12).map { index in
                .paragraph(Paragraph(style: { var style = ParagraphStyle(); style.alignment = .justified; return style }(),
                                     list: index % 4 == 0 ? ListItem(listName: "Esempi") : nil, inlines: [
                    .text(TextRun(String(repeating: long, count: 2 + index % 3), style: body)),
                    .floating(FloatingObject(runs: [TextRun("Nota \(index).", style: small)])),
                ]))
            }).attributedString().text)
            let options = LayoutOptions(appliesFontTracking: true, usesOpticalMargins: true, hyphenationLanguage: "it",
                                        lists: ListDefinition.builtIn, noteList: "Note a simboli")
            func fingerprint(_ layout: DocumentLayout) -> [String] {
                layout.pages.enumerated().flatMap { page, content in
                    content.lines.map { "\(page) \($0.range) \(Int($0.origin.x * 100)) \(Int($0.origin.y * 100))" } + content.markers.map { "\(page) segno \(Int($0.origin.y))" }
                }
            }
            _ = PageLayout.layout(text, options: options)
            // Modifiche che cambiano gli a capo di un paragrafo, la numerazione degli esempi e quella delle note.
            let edits: [(NSMutableAttributedString) -> Void] = [
                { $0.replaceCharacters(in: NSRange(location: 30, length: 0), with: "inserito qui ") },
                { $0.deleteCharacters(in: NSRange(location: 0, length: 80)) },
                { TextStyling.setList(in: $0, range: NSRange(location: 900, length: 0)) { _ in ListItem(listName: "Esempi") } },
                { $0.replaceCharacters(in: NSRange(location: 500, length: 0), with: NSAttributedString(string: Self.anchor + "Nota nuova", attributes: [.font: Self.regular, .footnote: true])) },
            ]
            for (index, edit) in edits.enumerated() {
                edit(text)
                let warm = fingerprint(PageLayout.layout(text, options: options))
                PageLayout.clearCaches()
                let cold = fingerprint(PageLayout.layout(text, options: options))
                #expect(warm == cold, "modifica \(index)")
            }
        }

        // MARK: Equivalenza con il testo di Apple

        /// Un generatore di numeri casuali ripetibile (SplitMix64), perché un errore si possa ritrovare.
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
            mutating func bool() -> Bool { next() & 1 == 1 }
        }

        private func randomAttributes(_ random: inout Random) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [.font: random.bool() ? Self.regular : Self.italic]
            if random.int(4) == 0 { attributes[.footnote] = true }
            if random.int(4) == 0 { attributes[.listItem] = ListItem(marker: "1.").encoded }
            if random.int(5) == 0 { attributes[.language] = "la" }
            return attributes
        }

        private func randomText(_ random: inout Random) -> NSAttributedString {
            let pieces = ["a", "b", "c", " ", "é", "\n", "\n", Self.anchor, "xyz", "\u{2028}"]
            let result = NSMutableAttributedString()
            for _ in 0..<random.int(6) {
                result.append(NSAttributedString(string: pieces[random.int(pieces.count)], attributes: randomAttributes(&random)))
            }
            return result
        }

        private func randomRange(_ random: inout Random, length: Int) -> NSRange {
            let location = random.int(length + 1)
            return NSRange(location: location, length: random.int(min(length - location, 12) + 1))
        }

        @Test("Migliaia di modifiche casuali danno lo stesso testo del testo di Apple, e una struttura sempre coerente", arguments: [1, 2, 3, 4, 5])
        func randomEquivalence(seed: Int) {
            var random = Random(state: UInt64(seed) * 7919)
            let reference = NSMutableAttributedString(attributedString: plain("Uno due\ntre quattro\n\ncinque"))
            let store = DocumentStore(text: reference)
            let sheet = StyleSheet.builtIn
            for step in 0..<400 {
                let range = randomRange(&random, length: reference.length)
                let operation = random.int(10)
                var description = ""
                func both(_ body: (NSMutableAttributedString) -> Void) {
                    body(reference)
                    body(store)
                }
                switch operation {
                case 0, 1, 2:
                    let text = randomText(&random)
                    description = "sostituisce \(range) con \(text.string.debugDescription)"
                    both { $0.replaceCharacters(in: range, with: text) }
                case 3:
                    let string = ["x", "\n", "", "ab\ncd"][random.int(4)]
                    description = "sostituisce \(range) con la stringa \(string.debugDescription)"
                    both { $0.replaceCharacters(in: range, with: string) }
                case 4:
                    let attributes = randomAttributes(&random)
                    description = "fissa attributi in \(range)"
                    both { $0.setAttributes(attributes, range: range) }
                case 5:
                    description = "aggiunge o toglie la nota in \(range)"
                    let add = random.bool()
                    both { add ? $0.addAttribute(.footnote, value: true, range: range) : $0.removeAttribute(.footnote, range: range) }
                case 6:
                    description = "elenco in \(range)"
                    let marker = random.bool() ? ListItem(marker: "a)") : nil
                    both { TextStyling.setList(in: $0, range: range) { _ in marker } }
                case 7:
                    description = "ripara elenchi e note in \(range)"
                    both {
                        TextStyling.repairFootnotes(in: $0, range: range)
                        TextStyling.repairLists(in: $0, range: range)
                    }
                case 8:
                    description = "stile di paragrafo in \(range)"
                    both { TextStyling.restyle($0, range: TextStyling.paragraphRange(in: $0, for: range), from: sheet, to: sheet) { $0.paragraph = "Citazione" } }
                default:
                    description = "allineamento in \(range)"
                    var values = StyleValues()
                    values.alignment = .center
                    both { TextStyling.setValue(values, of: .alignment, in: $0, range: range) }
                }
                guard store.isEqual(to: reference) else {
                    Issue.record("seme \(seed), passo \(step): dopo «\(description)» il deposito differisce dal testo di Apple")
                    return
                }
                if let problem = store.structuralProblem() {
                    Issue.record("seme \(seed), passo \(step): dopo «\(description)»: \(problem)")
                    return
                }
            }
        }
        // MARK: Annullamento

        /// La fine di un evento: il gestore dell'annullamento chiude il gruppo aperto, come nell'app.
        /// Senza una sorgente di eventi il ciclo ritornerebbe subito, senza fare il giro: gli si dà un timer.
        @MainActor private func endEvent() {
            RunLoop.main.add(Timer(timeInterval: 0.0005, repeats: false) { _ in }, forMode: .default)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }

        @Test("I tasti di seguito sono un passo solo; chiudendo il passo se ne apre un altro") @MainActor
        func coalescing() {
            let undo = UndoManager()
            let store = DocumentStore(text: plain("x"))
            store.undoManager = undo
            for (index, character) in "abc".enumerated() {
                                store.replaceCharacters(in: NSRange(location: 1 + index, length: 0), with: String(character))
                endEvent()
            }
            store.breakUndoCoalescing()
                        store.replaceCharacters(in: NSRange(location: 4, length: 0), with: "!")
            endEvent()
            #expect(store.string == "xabc!")
            undo.undo()
            #expect(store.string == "xabc")
            undo.undo()
            #expect(store.string == "x")
            #expect(store.lastRevertedRange == NSRange(location: 1, length: 0), "il cursore va dove il testo è stato tolto")
            undo.redo()
            #expect(store.string == "xabc")
            #expect(undo.canRedo, "resta da rifare il punto esclamativo")
        }

        @Test("Annullare un'unione di paragrafi restituisce al secondo la sua identità") @MainActor
        func undoRestoresIdentity() throws {
            let undo = UndoManager()
            let store = DocumentStore(text: plain("uno\ndue"))
            store.undoManager = undo
            let ids = store.paragraphIDs
                        store.replaceCharacters(in: NSRange(location: 3, length: 1), with: "")
            endEvent()
            #expect(store.paragraphIDs == [ids[0]])
            undo.undo()
            #expect(store.paragraphIDs == ids)
            #expect(store.structuralProblem() == nil)
            undo.redo()
            #expect(store.paragraphIDs == [ids[0]])
        }

        @Test("Un comando fatto di molte modifiche elementari si annulla in un passo") @MainActor
        func commandIsOneStep() {
            let undo = UndoManager()
            let original = plain("uno\ndue\ntre")
            let store = DocumentStore(text: original)
            store.undoManager = undo
                        TextStyling.setList(in: store, range: NSRange(location: 0, length: store.length)) { _ in ListItem(marker: "1.") }
            TextStyling.restyle(store, range: NSRange(location: 0, length: store.length), from: .builtIn, to: .builtIn) { $0.paragraph = "Citazione" }
            endEvent()
            #expect(!store.isEqual(to: original))
            undo.undo()
            #expect(store.isEqual(to: original))
        }

        @Test("Passi casuali, annullati tutti e poi rifatti tutti: ogni volta testo e identità tornano quelli di quel momento",
              arguments: [11, 12, 13]) @MainActor
        func randomUndoRedo(seed: Int) {
            var random = Random(state: UInt64(seed) * 104_729)
            let undo = UndoManager()
            undo.levelsOfUndo = 0
            let store = DocumentStore(text: plain("Uno due\ntre quattro\n\ncinque"))
            store.undoManager = undo
            typealias State = (text: NSAttributedString, ids: [DocumentStore.ParagraphID])
            func state() -> State { (NSAttributedString(attributedString: store), store.paragraphIDs) }
            var states: [State] = [state()]
            let sheet = StyleSheet.builtIn
            // Ci si può accodare solo a un passo ancora aperto: uno che ha registrato qualcosa e non è stato chiuso.
            var canCoalesce = false
            for _ in 0..<150 {
                // Uno su tre si aggiunge al passo precedente, come un tasto scritto di seguito.
                let coalesce = random.int(3) == 0 && canCoalesce
                if !coalesce { store.breakUndoCoalescing() }
                                let range = randomRange(&random, length: store.length)
                switch random.int(6) {
                case 0, 1: store.replaceCharacters(in: range, with: randomText(&random))
                case 2: store.setAttributes(randomAttributes(&random), range: range)
                case 3: random.bool() ? store.addAttribute(.footnote, value: true, range: range) : store.removeAttribute(.footnote, range: range)
                case 4: TextStyling.setList(in: store, range: range) { _ in ListItem(marker: "a)") }
                default: TextStyling.restyle(store, range: TextStyling.paragraphRange(in: store, for: range), from: sheet, to: sheet) { $0.paragraph = "Titolo 1" }
                }
                endEvent()
                // Un passo che non ha cambiato nulla può non essere registrato: allora non conta come stato.
                let now = state()
                if now.text.isEqual(to: states.last!.text) && now.ids == states.last!.ids {
                    if !coalesce { canCoalesce = false }
                    continue
                }
                if coalesce { states[states.count - 1] = now } else { states.append(now) }
                canCoalesce = true
            }
            func matches(_ expected: State) -> Bool { store.isEqual(to: expected.text) && store.paragraphIDs == expected.ids }
            for index in stride(from: states.count - 2, through: 0, by: -1) {
                undo.undo()
                guard matches(states[index]), store.structuralProblem() == nil else {
                    Issue.record("seme \(seed): annullando non si torna allo stato \(index) di \(states.count - 1); testo uguale \(store.isEqual(to: states[index].text)), stringa uguale \(store.string == states[index].text.string), identità \(store.paragraphIDs) invece di \(states[index].ids); struttura \(store.structuralProblem() ?? "ok")")
                    return
                }
            }
            #expect(!undo.canUndo, "annullato tutto")
            for index in 1..<states.count {
                undo.redo()
                guard matches(states[index]), store.structuralProblem() == nil else {
                    Issue.record("seme \(seed): rifacendo non si arriva allo stato \(index)")
                    return
                }
            }
        }
    }
}
