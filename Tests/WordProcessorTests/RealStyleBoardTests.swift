import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Stili reali nella bacheca", .serialized) @MainActor
struct RealStyleBoardTests {
    @Test("Forte passa fra Aggiungi, Imposta e Sottrai, con Annulla e salvataggio")
    func changePredicate() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        let resolver = FontRoleResolver()
        let italic = try #require(resolver.applying(role: .boldItalic, to: EditorHarness.body))
        var doc = h.editor.currentDocument()
        let bodyIndex = try #require(doc.styles.styles.firstIndex { $0.name == "Body" })
        doc.styles.styles[bodyIndex].values.italic = true
        doc.styles.styles[bodyIndex].values.bold = true
        doc.blocks = [.paragraph(Paragraph(styleName: "Body", inlines: [.text(TextRun("Prova", style: italic, characterStyleName: "Strong"))]))]
        h.editor.replaceContent(doc)
        h.document.undoManager?.removeAllActions()
        let model = ComposerBoardModel(sheet: doc.styles, owner: "Body", sample: "Prova")
        model.commit = { h.editor.applyStyleBoard(base: $0, updated: $1) }
        model.selectStyle("Strong")
        let style = try #require(model.sheet.style(named: "Strong"))
        let f = try #require(style.formulas.first)
        #expect(f.operation.predicate == .add && style.values.bold == nil)
        model.apply()
        let actual = h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(actual?.fontName == "HoeflerText-BlackItalic")
        model.updateFormula(f.id, operation: StylePropertyOperation(.set, .font, .font(.bold)))
        model.apply()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
        h.undo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-BlackItalic")
        h.redo()
        model.updateFormula(f.id, operation: StylePropertyOperation(.subtract, .font, .font(.bold)))
        model.apply()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
        h.undo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
        h.redo()
        let data = try h.document.data(ofType: TextDocument.typeName)
        try h.document.read(from: data, ofType: TextDocument.typeName)
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
        _ = try DocumentFormat.document(from: data)
    }

    @Test("La conversione dei predefiniti conserva la resa dei quattro ruoli")
    func preserveBuiltins() throws {
        let old = StyleSheet.builtIn
        let migrated = StyleSheet(styles: old.styles.map { $0.materializingFormulas() })
        for role in FontRole.allCases {
            let input = try #require(FontRoleResolver().applying(role: role, to: EditorHarness.body))
            for style in old.styles {
                func resolve(_ sheet: StyleSheet) -> CharacterStyle {
                    sheet.resolveCharacter(paragraphStyle: style.target == .paragraph ? style.name : nil,
                        wordStyle: style.target == .word ? style.name : nil, characterStyle: style.target == .character ? style.name : nil, base: input)
                }
                let a = resolve(old), b = resolve(migrated)
                #expect(a.fontName == b.fontName && a.size == b.size && a.smallCaps == b.smallCaps && a.language == b.language)
                #expect(old.resolveParagraph(styleName: style.name) == migrated.resolveParagraph(styleName: style.name))
            }
        }
        let loaded = try DocumentFormat.document(from: DocumentFormat.data(for: Document(styles: migrated, lists: ListDefinition.builtIn)))
        #expect(loaded.styles.styles == migrated.styles)
        for style in migrated.styles { #expect(style.materializingFormulas() == style) }
    }

    @Test("Una scelta avanzata ereditata conserva precedenze e funzioni nella conversione")
    func preserveAdvancedInheritance() throws {
        var root = StyleValues()
        root.fontName = "HoeflerText-Regular"
        root.size = 14
        root.features = []
        var child = StyleValues()
        child.family = "Times"
        child.bold = true
        child.leftIndent = 24
        let old = StyleSheet(styles: [NamedStyle(name: "Base", target: .paragraph, values: root),
            NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Base", values: child)])
        var migrated = old
        for name in ["Base", "Figlio"] {
            let i = try #require(migrated.styles.firstIndex { $0.name == name })
            migrated.styles[i] = try #require(migrated.materializingFormulas(of: name))
        }
        for role in FontRole.allCases {
            let base = try #require(FontRoleResolver().applying(role: role, to: EditorHarness.body))
            var a = old.resolveCharacter(paragraphStyle: "Figlio", wordStyle: nil, characterStyle: nil, base: base)
            var b = migrated.resolveCharacter(paragraphStyle: "Figlio", wordStyle: nil, characterStyle: nil, base: base)
            // Il vecchio percorso può conservare un ruolo descrittivo ormai superato.
            // Si confronta tutta la resa, senza quella cache di metadati.
            a.fontRole = nil; b.fontRole = nil
            #expect(a == b)
        }
        #expect(migrated.style(named: "Figlio")?.values.family == "Times")
        #expect(migrated.resolveParagraph(styleName: "Figlio").leftIndent == 24)
        let reopened = try DocumentFormat.document(from: DocumentFormat.data(for: Document(styles: migrated)))
        #expect(reopened.styles.styles == migrated.styles)
    }

    @Test("La bacheca mostra ingressi e uscite, conserva le esclusioni e rifiuta modifiche su una base superata")
    func traceAndConflicts() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var root = StyleValues(); root.leftIndent = 24
        var child = StyleValues(); child.bold = false
        let sheet = StyleSheet(styles: [NamedStyle(name: "Base", target: .paragraph, values: root),
            NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Base", values: child,
                formulas: [StyleFormula(operation: StylePropertyOperation(.add, .leftIndent, .length(6, .points)))])])
        let model = ComposerBoardModel(sheet: sheet, owner: "Figlio", sample: "Prova")
        model.selectStyle("Figlio")
        let style = try #require(model.sheet.style(named: "Figlio"))
        let state = try #require(model.formulaStates(style).first { $0.output.paragraph.leftIndent == 30 })
        #expect(state.input.paragraph.leftIndent == 24 && state.output.paragraph.leftIndent == 30)
        #expect(style.values.bold == nil)
        #expect(style.formulas.contains { $0.operation == StylePropertyOperation(.subtract, .font, .font(.bold)) })
        model.commit = { h.editor.applyStyleBoard(base: $0, updated: $1) }
        model.updateFormula(state.id, operation: StylePropertyOperation(.set, .leftIndent, .length(6, .points)))
        let before = h.editor.currentDocument()
        model.apply()
        #expect(model.problem != nil)
        #expect(h.editor.currentDocument().styles == before.styles)
        model.reload = { sheet }
        model.discard()
        #expect(model.problem == nil)
        #expect(try model.preview(try #require(model.sheet.style(named: "Figlio"))).paragraph.leftIndent == 30)
    }

    @Test("Cambiare scheda non permette di applicare una formula con risultato impossibile")
    func invalidDraftStaysInvalid() throws {
        let sheet = StyleSheet(styles: [NamedStyle(name: "A", target: .paragraph), NamedStyle(name: "B", target: .paragraph)])
        let model = ComposerBoardModel(sheet: sheet, owner: "A", sample: "Prova")
        model.addStyleFormula()
        let id = try #require(model.sheet.style(named: "A")?.formulas.first?.id)
        model.updateFormula(id, operation: StylePropertyOperation(.add, .size, .length(-100, .points)))
        #expect(!model.valid)
        model.selectStyle("B")
        #expect(!model.valid && model.validationIssue?.contains("“A”") == true)
        model.selectStyle("A")
        model.updateFormula(id, operation: StylePropertyOperation(.add, .size, .length(2, .points)))
        #expect(model.valid)
    }


    @Test("Applicare Senza grassetto al grassetto manuale rimuove il tratto e conserva il corsivo")
    func subtractFromSelectedText() throws {
        for italic in [false, true] {
            let h = EditorHarness(paragraphs: ["Prima Dopo"])
            defer { h.close() }
            var sheet = h.editor.settings.styles
            sheet.styles.append(NamedStyle(name: "Senza grassetto", target: .character,
                formulas: [StyleFormula(operation: StylePropertyOperation(.subtract, .font, .font(.bold)))]))
            h.editor.changeStyles(to: sheet, restyle: false, actionName: "Nuovo stile")
            h.select(0, length: 5)
            h.editor.toggleBold(nil)
            if italic { h.editor.toggleItalic(nil) }
            h.step()
            func font(_ at: Int = 0) -> String? {
                (h.attributed.attribute(.font, at: at, effectiveRange: nil) as? NSFont)?.fontName
            }
            let original = italic ? "HoeflerText-BlackItalic" : "HoeflerText-Black"
            let expected = italic ? "HoeflerText-Italic" : "HoeflerText-Regular"
            #expect(font() == original)
            h.document.undoManager?.removeAllActions()
            h.editor.applyNamedStyle(.character, name: "Senza grassetto")
            #expect(font() == expected)
            #expect(font(6) == "HoeflerText-Regular")
            h.undo()
            #expect(font() == original)
            h.redo()
            #expect(font() == expected)
            h.editor.applyNamedStyle(.character, name: "Senza grassetto")
            #expect(font() == expected)
            let data = try h.document.data(ofType: TextDocument.typeName)
            try h.document.read(from: data, ofType: TextDocument.typeName)
            #expect(font() == expected)
        }
    }


    @Test("I predicati del font agiscono sulla selezione per tutti i tipi di stile e anche al cursore")
    func assignFontFormulas() throws {
        for target in StyleTarget.allCases {
            let h = EditorHarness(paragraphs: ["Prova"])
            defer { h.close() }
            var sheet = h.editor.settings.styles
            sheet.styles.append(NamedStyle(name: "Senza grassetto", target: target,
                basedOn: target == .paragraph ? "Body" : nil,
                formulas: [StyleFormula(operation: StylePropertyOperation(.subtract, .font, .font(.bold)))]))
            h.editor.changeStyles(to: sheet, restyle: false, actionName: "Nuovo stile")
            h.select(0, length: 5)
            h.editor.toggleBold(nil)
            h.editor.toggleItalic(nil)
            h.editor.applyNamedStyle(target, name: "Senza grassetto")
            #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
        }
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        for predicate in StylePredicate.allCases {
            sheet.styles.append(NamedStyle(name: predicate.rawValue, target: .character,
                formulas: [StyleFormula(operation: StylePropertyOperation(predicate, .font, .font(.bold)))]))
        }
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Nuovi stili")
        h.select(0, length: 5)
        h.editor.toggleItalic(nil)
        h.editor.applyNamedStyle(.character, name: "add")
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-BlackItalic")
        h.editor.applyNamedStyle(.character, name: "set")
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Black")
        h.select(5)
        h.editor.toggleItalic(nil)
        h.editor.applyNamedStyle(.character, name: "subtract")
        h.type("X")
        #expect((h.attributed.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)?.fontName == "HoeflerText-Italic")
    }

}
