import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Controlli e bacheca condividono le formule", .serialized) @MainActor
struct FormulaControlTests {
    @Test("Una formula con un riferimento rotto non si tace: compare fra gli avvisi, e sparisce annullando")
    func brokenReferenceIsWarned() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        #expect(!h.editor.warningTitles.contains { $0.hasPrefix("Style formulas") })
        var sheet = h.editor.settings.styles
        let index = try #require(sheet.styles.firstIndex { $0.name == "Body" })
        sheet.styles[index].formulas.append(StyleFormula(operation: StylePropertyOperation(.set, .nextStyle, .styleName("Inesistente"))))
        h.editor.changeStyles(to: sheet, restyle: true, actionName: "Prova")
        h.step()
        #expect(h.editor.warningTitles.contains { $0.hasPrefix("Style formulas") && $0.contains("Inesistente") }, "\(h.editor.warningTitles)")
        h.undo()
        #expect(!h.editor.warningTitles.contains { $0.hasPrefix("Style formulas") })
    }

    @Test("Un corpo modificato dal controllo e dalla pill resta sincronizzato con Annulla e il file")
    func sharedDefinition() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        h.editor.stylesTab.selection = "Body"
        h.editor.refreshStylesTab()
        var value = StyleValues(); value.size = 16
        h.editor.styleInspector.change(.size) { $0.size = 16 }
        h.editor.flushStyleChanges(); h.step()
        let f = try #require(h.editor.settings.styles.style(named: "Body")?.formulas.first { $0.operation.property == .size })
        #expect(h.editor.settings.styles.style(named: "Body")?.values.size == nil)
        #expect(board.sheet.style(named: "Body")?.formulas.first { $0.operation.property == .size } == f)
        #expect(board.problem == nil)
        board.updateFormula(f.id, operation: StylePropertyOperation(.set, .size, .length(18, .points)))
        board.apply(); h.step()
        #expect(h.editor.styleInspector.values.first { $0.property == .size }?.value.size == 18)
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        h.undo()
        #expect(h.editor.styleInspector.values.first { $0.property == .size }?.value.size == 16)
        #expect(board.sheet.style(named: "Body")?.formulas.first { $0.id == f.id }?.operation.argument == .length(16, .points))
        h.redo()
        let loaded = try DocumentFormat.document(from: h.document.data(ofType: TextDocument.typeName))
        #expect(loaded.styles.style(named: "Body")?.formulas.first { $0.id == f.id }?.operation.argument == .length(18, .points))
        // Una bozza dell'autore viene conservata quando cambia lo stesso stile altrove.
        board.updateFormula(f.id, operation: StylePropertyOperation(.add, .size, .length(2, .points)))
        value.size = 20
        h.editor.setStyleValue(.size, value); h.editor.flushStyleChanges()
        #expect(board.sheet.style(named: "Body")?.formulas.first { $0.id == f.id }?.operation.predicate == .add)
        #expect(board.problem != nil)
    }

    @Test("Una formula ereditata richiede la scelta del valore fisso e può tornare in eredità")
    func inheritedFormula() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        var values = StyleValues(); values.leftIndent = 24
        sheet.styles += [NamedStyle(name: "Base", target: .paragraph, values: values),
            NamedStyle(name: "Calcolo", target: .paragraph, basedOn: "Base", formulas: [StyleFormula(operation: StylePropertyOperation(.add, .leftIndent, .length(6, .points)))]),
            NamedStyle(name: "Figlio", target: .paragraph, basedOn: "Calcolo")]
        h.editor.changeStyles(to: sheet, restyle: false, actionName: "Stili")
        h.editor.stylesTab.selection = "Figlio"
        h.editor.refreshStylesTab()
        let inspector = h.editor.styleInspector
        #expect(inspector.formulaDefinitions[.leftIndent]?.owner == "Calcolo")
        #expect(inspector.formulaIsLocked(.leftIndent))
        inspector.change(.leftIndent) { $0.leftIndent = 8 }
        h.editor.flushStyleChanges()
        #expect(h.editor.settings.styles.resolveParagraph(styleName: "Figlio").leftIndent == 30)
        inspector.replaceFormula?(.leftIndent); h.step()
        #expect(!inspector.formulaIsLocked(.leftIndent))
        #expect(h.editor.settings.styles.style(named: "Figlio")?.formulas.first?.operation == StylePropertyOperation(.set, .leftIndent, .length(30, .points)))
        h.editor.resetStyleValue(.leftIndent); h.editor.flushStyleChanges(); h.step()
        #expect(inspector.formulaIsLocked(.leftIndent))
        h.undo()
        #expect(!inspector.formulaIsLocked(.leftIndent))
        h.redo()
        #expect(inspector.formulaIsLocked(.leftIndent))
    }

    @Test("Aggiornare dalla selezione conserva i calcoli invariati e sostituisce solo quelli scelti")
    func selectionUpdate() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var sheet = h.editor.settings.styles
        let i = try #require(sheet.styles.firstIndex { $0.name == "Body" })
        let formula = StyleFormula(operation: StylePropertyOperation(.add, .size, .length(2, .points)))
        sheet.styles[i].formulas = [formula]
        h.editor.changeStyles(to: sheet, restyle: true, actionName: "Calcolo")
        h.select(0, length: 5)
        let item = NSMenuItem(); item.representedObject = StyleTarget.paragraph.rawValue
        h.editor.updateStyleFromSelection(item)
        #expect(h.editor.settings.styles.style(named: "Body")?.formulas == [formula])
        h.editor.changeForTests(.size) { $0.size = 20 }
        h.editor.replaceFormulaAnswerForTests = false
        h.editor.updateStyleFromSelection(item)
        #expect(h.editor.settings.styles.style(named: "Body")?.formulas == [formula])
        h.editor.replaceFormulaAnswerForTests = true
        h.editor.updateStyleFromSelection(item)
        let changed = try #require(h.editor.settings.styles.style(named: "Body")?.formulas.first { $0.id == formula.id })
        #expect(changed.operation == StylePropertyOperation(.set, .size, .length(20, .points)))
        h.editor.duplicateStyle("Body")
        #expect(h.editor.settings.styles.style(named: "Body copy")?.formulas == h.editor.settings.styles.style(named: "Body")?.formulas)
    }

    @Test("Bacheca, controlli e testo usano la base salvata del documento per il corpo relativo")
    func documentBase() throws {
        let h = EditorHarness()
        defer { h.close() }
        let xml = """
        <document version="18" font="HoeflerText-Regular" size="14"><styles><style name="P" target="paragraph">
        <formula id="7F6DC1BB-29CF-4AF2-A253-00F000000001" predicate="subtract" property="size" kind="length" value="2" unit="pt"/>
        </style></styles><p style="P">Prova</p></document>
        """
        try h.document.read(from: Data(xml.utf8), ofType: TextDocument.typeName)
        h.editor.stylesTab.selection = "P"; h.editor.refreshStylesTab()
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("P")
        let style = try #require(board.sheet.style(named: "P"))
        #expect(try board.preview(style).character.size == 12)
        #expect(h.editor.styleInspector.values.first { $0.property == .size }?.value.size == 12)
        let f = try #require(style.formulas.first)
        board.updateFormula(f.id, operation: StylePropertyOperation(.subtract, .size, .length(3, .points)))
        board.apply()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 11)
        #expect(h.editor.styleInspector.values.first { $0.property == .size }?.value.size == 11)
        h.undo()
        #expect((h.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 12)
    }

    @Test("Il controllo della faccia usa le equivalenze dei ruoli del documento")
    func documentFontRoles() throws {
        let h = EditorHarness(paragraphs: ["Prova"])
        defer { h.close() }
        var doc = h.editor.currentDocument()
        doc.fontRoles.customize(family: "Hoefler Text", role: .bold,
            to: FontRoleEquivalence(staticFace: "HoeflerText-Regular"))
        let i = try #require(doc.styles.styles.firstIndex { $0.name == "Body" })
        doc.styles.styles[i].values.bold = true
        h.editor.replaceContent(doc)
        h.editor.stylesTab.selection = "Body"; h.editor.refreshStylesTab()
        #expect(h.editor.styleInspector.values.first { $0.property == .face }?.value.fontName == "HoeflerText-Regular")
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        #expect(try board.preview(try #require(board.sheet.style(named: "Body"))).character.fontName == "HoeflerText-Regular")
    }

}
