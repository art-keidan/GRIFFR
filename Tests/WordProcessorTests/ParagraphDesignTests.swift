import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Progettazione del capoverso sulla pagina", .serialized) @MainActor
struct ParagraphDesignTests {
    private static let text = ["Primo capoverso, abbastanza lungo da andare a capo più volte nella colonna della pagina di prova, così si vedono le righe e la distanza fra loro.",
                               "Secondo capoverso, con lo stesso stile del primo.",
                               "Terzo capoverso."]

    private func style(_ h: EditorHarness, _ name: String = "Body") -> ParagraphStyle {
        h.editor.settings.styles.resolveParagraph(styleName: name)
    }

    private func paragraphStyle(_ h: EditorHarness, at index: Int) throws -> NSParagraphStyle {
        try #require(h.attributed.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)
    }

    private func third(_ h: EditorHarness) -> Int { (h.text as NSString).range(of: "Terzo").location }

    @Test("Entrare e uscire: il capoverso del cursore, le sue maniglie sulla pagina, Esc esce")
    func entersAndLeaves() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        #expect(h.editor.paragraphDesignOverlayForTests == nil)
        h.editor.toggleParagraphDesign(nil)
        h.step()
        let overlay = try #require(h.editor.paragraphDesignOverlayForTests)
        #expect(overlay.paragraphLocation == 0)
        let handles = h.editor.designHandleRectsForTests
        #expect(Set(handles.keys) == Set(DesignHandle.allCases), "tutte le maniglie, anche l'interlinea: il primo capoverso ha più righe")
        #expect(h.editor.paragraphDesignBarForTests?.styleName == "Body")
        // Il cursore in un altro capoverso: la progettazione lo segue.
        let second = (h.text as NSString).range(of: "Secondo").location
        h.select(second + 3)
        h.step()
        #expect(h.editor.paragraphDesignOverlayForTests?.paragraphLocation == second)
        #expect(h.editor.designHandleRectsForTests[.lineSpacing] == nil, "una riga sola: niente linee di base da trascinare")
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.editor.paragraphDesignOverlayForTests == nil && !h.editor.isDesigningParagraph)
    }

    @Test("Le maniglie cambiano la bozza; Salva la porta nello stile in un passo di Annulla, per tutti i capoversi")
    func handlesChangeTheStyleOnSave() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let before = style(h)
        let cases: [(DesignHandle, CGSize, (ParagraphStyle) -> Double, Double)] = [
            (.leftIndent, CGSize(width: 18, height: 0), { $0.leftIndent }, before.leftIndent + 18),
            (.rightIndent, CGSize(width: -24, height: 0), { $0.rightIndent }, before.rightIndent + 24),
            (.firstLineIndent, CGSize(width: 12, height: 0), { $0.firstLineIndent }, before.firstLineIndent + 12),
            (.spaceBefore, CGSize(width: 0, height: -10), { $0.spaceBefore }, before.spaceBefore + 10),
            (.spaceAfter, CGSize(width: 0, height: 7), { $0.spaceAfter }, before.spaceAfter + 7),
            (.lineSpacing, CGSize(width: 0, height: 3), { $0.lineSpacing }, before.lineSpacing + 3),
        ]
        for (handle, delta, _, _) in cases {
            h.editor.dragDesignHandleForTests(handle, by: delta)
        }
        #expect(style(h) == before, "prima di Salva il documento non cambia")
        #expect(h.editor.paragraphDesignOverlayForTests?.value(.leftIndent) == CGFloat(before.leftIndent + 18), "le maniglie mostrano la bozza")
        let shownLine = try #require(h.editor.currentLayout()?.pages[0].lines.last?.origin.x)
        h.editor.saveParagraphDesign()
        h.step()
        #expect(!h.editor.isDesigningParagraph)
        for (handle, _, read, expected) in cases {
            #expect(abs(read(style(h)) - expected) < 0.01, "\(handle): nello stile \(read(style(h))), atteso \(expected)")
        }
        let thirdIndent = try paragraphStyle(h, at: third(h)).headIndent
        #expect(abs(thirdIndent - CGFloat(before.leftIndent + 18)) < 0.01, "anche il terzo capoverso segue lo stile")
        #expect(abs((h.editor.currentLayout()?.pages[0].lines.last?.origin.x ?? 0) - shownLine) < 0.5, "le pagine salvate sono quelle dell'anteprima")
        #expect(h.undoActionName == "Paragraph Design")
        h.undo()
        #expect(style(h) == before, "un passo solo toglie tutto")
        h.redo()
        #expect(abs(style(h).leftIndent - before.leftIndent - 18) < 0.01)
    }

    @Test("Annulla scarta la bozza; dentro la progettazione, Annulla e Ripeti tolgono e rimettono i passi della bozza")
    func cancelAndInnerUndo() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        let undoBefore = h.undoActionName
        h.editor.setParagraphDesign(true)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 10, height: 0))
        h.editor.dragDesignHandleForTests(.spaceAfter, by: CGSize(width: 0, height: 6))
        #expect(h.editor.paragraphDesignDraftForTests?.styleEdits["Body"]?.count == 2)
        // Annulla e Ripeti dal menu, come li manda la vista delle pagine.
        #expect(h.menu(Selector(("undo:"))))
        #expect(h.editor.paragraphDesignDraftForTests?.styleEdits["Body"]?.keys.sorted { $0.rawValue < $1.rawValue } == [.leftIndent])
        #expect(h.menu(Selector(("redo:"))))
        #expect(h.editor.paragraphDesignDraftForTests?.styleEdits["Body"]?.count == 2)
        let before = style(h)
        h.editor.cancelParagraphDesign()
        h.step()
        #expect(style(h) == before && h.undoActionName == undoBefore, "nulla nel documento, nessun passo di Annulla")
        let indent = try paragraphStyle(h, at: 0).headIndent
        #expect(abs(indent) < 0.01)
    }

    @Test("Solo questo capoverso: il valore resta sul capoverso, lo stile non cambia")
    func onlyThisParagraph() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setScope?(.paragraph)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        bar.change(.alignment) { $0.alignment = .center }
        h.editor.saveParagraphDesign()
        h.step()
        #expect(style(h).leftIndent == 0 && style(h).alignment != .center, "lo stile resta com'era")
        let first = try paragraphStyle(h, at: 0)
        #expect(abs(first.headIndent - 18) < 0.01 && first.alignment == .center)
        #expect(try paragraphStyle(h, at: third(h)).headIndent == 0, "gli altri capoversi no")
        h.undo()
        #expect(try paragraphStyle(h, at: 0).headIndent == 0)
    }

    @Test("Un valore dato a mano lascia il posto allo stile, salvando; l'anteprima segue il gesto")
    func previewAndManualValue() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.changeForTests(.leftIndent) { $0.leftIndent = 40 }
        h.step()
        h.editor.setParagraphDesign(true)
        #expect(h.editor.paragraphDesignOverlayForTests?.value(.leftIndent) == 40, "la maniglia parte dal valore che il capoverso ha")
        let firstLineX = try #require(h.editor.currentLayout()?.pages[0].lines.first?.origin.x)
        h.editor.designDragged(.leftIndent, by: .zero, phase: .began, modifiers: [])
        h.editor.designDragged(.leftIndent, by: CGSize(width: -20, height: 0), phase: .changed, modifiers: [])
        let preview = try #require(h.editor.currentLayout()?.pages[0].lines.first?.origin.x)
        #expect(abs(preview - (firstLineX - 20)) < 0.5, "l'anteprima sposta le righe")
        h.editor.designDragged(.leftIndent, by: CGSize(width: -20, height: 0), phase: .ended, modifiers: [])
        #expect(try paragraphStyle(h, at: 0).headIndent == 40, "il documento non è ancora cambiato")
        h.editor.saveParagraphDesign()
        h.step()
        #expect(style(h).leftIndent == 20)
        #expect(try paragraphStyle(h, at: 0).headIndent == 20, "il valore dato a mano se ne va: ora vale lo stile")
        h.undo()
        let restored = try paragraphStyle(h, at: 0).headIndent
        #expect(restored == 40 && style(h).leftIndent == 0)
    }

    @Test("Una misura calcolata da una formula è bloccata nello stile, non per il solo capoverso")
    func formulaIsLocked() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        var sheet = h.editor.settings.styles
        let i = try #require(sheet.styles.firstIndex { $0.name == "Body" })
        sheet.styles[i].formulas.append(StyleFormula(operation: StylePropertyOperation(.add, .leftIndent, .length(6, .points))))
        h.editor.changeStyles(to: sheet, restyle: true, actionName: "Formula")
        h.select(5)
        h.editor.setParagraphDesign(true)
        #expect(h.editor.paragraphDesignOverlayForTests?.locked == [.leftIndent])
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 30, height: 0))
        #expect(h.editor.paragraphDesignDraftForTests?.isEmpty == true)
        h.editor.paragraphDesignBarForTests?.setScope?(.paragraph)
        #expect(h.editor.paragraphDesignOverlayForTests?.locked.isEmpty == true)
    }

    @Test("I pulsanti intorno al capoverso: allineamento, divisione fra le pagine, stile dopo Invio")
    func barButtons() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.change(.alignment) { $0.alignment = .center }
        #expect(bar.alignment == .center && bar.hasChanges, "il pulsante segue la bozza")
        bar.change(.keepTogether) { $0.keeping.together = true }
        bar.change(.orphanLines) { $0.keeping.linesAtEnd = 3 }
        bar.setNextStyle?("Heading 1")
        #expect(bar.keepTogether && bar.linesAtEnd == 3)
        bar.save?()
        h.step()
        #expect(style(h).alignment == .center)
        let keeping = h.editor.settings.styles.lineKeeping(styleName: "Body")
        #expect(keeping.together && keeping.linesAtEnd == 3)
        #expect(h.editor.settings.styles.style(named: "Body")?.values.nextStyle == "Heading 1")
        h.undo()
        #expect(style(h).alignment != .center && h.editor.settings.styles.style(named: "Body")?.values.nextStyle == nil)
    }

    @Test("I margini della pagina si trascinano: al mezzo millimetro, nel formato, con Salva")
    func margins() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        let before = h.editor.settings.pageSetup
        h.editor.setParagraphDesign(true)
        h.editor.dragMarginForTests(page: 0, side: .left, by: CGSize(width: 20, height: 0))
        h.editor.dragMarginForTests(page: 0, side: .top, by: CGSize(width: 0, height: -10))
        #expect(h.editor.settings.pageSetup == before)
        #expect(abs((h.editor.currentLayout()?.setup.left ?? 0) - before.left - 20) < 1.5, "l'anteprima ha il margine nuovo")
        h.editor.saveParagraphDesign()
        h.step()
        let after = h.editor.settings.pageSetup
        #expect(abs(after.left - before.left - 20) < 1.5 && abs(after.top - before.top + 10) < 1.5)
        let step = PageSetup.points(fromMillimetres: 0.5)
        #expect(abs((after.left / step).rounded() * step - after.left) < 0.001, "al mezzo millimetro")
        h.undo()
        #expect(h.editor.settings.pageSetup == before)
    }

    @Test("Con le pagine affacciate, sulle pagine pari il margine di sinistra è quello esterno")
    func facingMargins() {
        #expect(MarginSide.left.field(onPage: 0, facing: true) == \PageSetup.left)
        #expect(MarginSide.left.field(onPage: 1, facing: true) == \PageSetup.right)
        #expect(MarginSide.right.field(onPage: 1, facing: false) == \PageSetup.right)
        #expect(MarginSide.bottom.value(from: 50, moved: CGSize(width: 0, height: 10)) == 40)
    }

    @Test("Aggiornamento dal vivo spento: l'anteprima cambia solo il capoverso evidenziato, Save vale per lo stile")
    func livePreviewOff() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setLivePreviewAll?(false)
        #expect(!bar.livePreviewAll)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        let preview = try #require(h.editor.paragraphDesignPreviewForTests)
        func indent(_ text: NSAttributedString, _ index: Int) -> CGFloat {
            (text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
        }
        #expect(indent(preview, 0) == 18, "il capoverso evidenziato cambia dal vivo")
        #expect(indent(preview, third(h)) == 0, "gli altri no, finché non si salva")
        h.editor.saveParagraphDesign()
        h.step()
        #expect(indent(h.attributed, third(h)) == 18, "salvando, lo stile cambia per tutti")
    }

    @Test("Live riacceso: le altre occorrenze dello stile tornano ad aggiornarsi")
    func liveBackOn() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        func indent(_ index: Int) -> CGFloat {
            (h.editor.paragraphDesignPreviewForTests?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
        }
        bar.setLivePreviewAll?(false)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        #expect(indent(third(h)) == 0)
        bar.setLivePreviewAll?(true)
        #expect(indent(third(h)) == 18, "riacceso, l'anteprima vale per tutti")
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 10, height: 0))
        #expect(indent(third(h)) == 28, "e i gesti dopo anche")
        let layoutX = h.editor.currentLayout()?.pages[0].lines.last?.origin.x ?? 0
        #expect(layoutX > 30, "le pagine mostrano il rientro sugli altri capoversi: \(layoutX)")
    }

    @Test("Occhio barrato: la tenuta rimane sul solo capoverso evidenziato")
    func livePreviewKeepingIsLocal() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setLivePreviewAll?(false)
        bar.change(.keepTogether) { $0.keeping.together = true }
        let text = try #require(h.editor.paragraphDesignPreviewForTests)
        let layout = try #require(h.editor.currentLayout())
        #expect(TextStyling.lineKeeping(in: text, at: 0).together == true)
        #expect(TextStyling.lineKeeping(in: text, at: third(h)).together != true)
        #expect(TextStyling.lineKeeping(in: layout.text, at: third(h)).together != true)
        #expect(h.editor.settings.styles.lineKeeping(styleName: "Body").together == false)
        h.editor.saveParagraphDesign()
        #expect(h.editor.settings.styles.lineKeeping(styleName: "Body").together)
        h.undo()
        #expect(!h.editor.settings.styles.lineKeeping(styleName: "Body").together)
    }

    @Test("Occhio barrato: l'impaginazione usa la tenuta solo sul paragrafo scelto")
    func livePreviewKeepingLayout() throws {
        let paragraph = Array(repeating: "Una frase per riempire la pagina.", count: 4).joined(separator: " ")
        let h = EditorHarness(paragraphs: [paragraph, paragraph, paragraph])
        defer { h.close() }
        let setup = PageSetup(paperSize: CGSize(width: 240, height: 170), top: 20, bottom: 20, left: 20, right: 20)
        h.editor.change(\.pageSetup, to: setup, actionName: "Page Setup")
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setLivePreviewAll?(false)
        bar.change(.keepTogether) { $0.keeping.together = true }

        let expectedText = NSMutableAttributedString(attributedString: h.attributed)
        var values = StyleValues()
        values.keeping.together = true
        TextStyling.setValue(values, of: .keepTogether, in: expectedText, range: NSRange(location: 0, length: 1))
        let expected = PageLayout.layout(expectedText, setup: setup, options: h.editor.documentLayoutOptions)
        let actual = try #require(h.editor.currentLayout())
        func positions(_ layout: DocumentLayout) -> [String] {
            layout.pages.enumerated().flatMap { page, item in
                item.lines.map { "\(page):\($0.range.location):\($0.range.length):\($0.origin.x):\($0.origin.y)" }
            }
        }
        #expect(positions(actual) == positions(expected))
        var globalOptions = h.editor.documentLayoutOptions
        globalOptions.styles = h.editor.draftSheet(try #require(h.editor.paragraphDesignDraftForTests))
        let globallyKept = PageLayout.layout(expectedText, setup: setup, options: globalOptions)
        #expect(positions(expected) != positions(globallyKept), "la prova distingue la tenuta locale da quella globale")
    }

    @Test("Occhio barrato: la distanza d'apertura vale solo sul capoverso scelto")
    func livePreviewOpeningDistanceIsLocal() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setLivePreviewAll?(false)
        bar.change(.openingDistance) { $0.openingDistance = 72 }
        let text = try #require(h.editor.paragraphDesignPreviewForTests)
        #expect(TextStyling.openingDistance(in: text, at: 0) == 72)
        #expect(TextStyling.openingDistance(in: text, at: third(h)) == nil)
        #expect(h.editor.settings.styles.values(of: "Body").openingDistance != 72)
    }

    @Test("Occhio barrato: la bozza segue il cursore e il cambio di portata")
    func livePreviewFollowsSelection() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        bar.setLivePreviewAll?(false)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        func indent(_ index: Int) -> CGFloat {
            (h.editor.paragraphDesignPreviewForTests?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
        }
        #expect(indent(0) == 18 && indent(third(h)) == 0)
        h.select(third(h) + 2)
        #expect(indent(0) == 0 && indent(third(h)) == 18)
        bar.setScope?(.paragraph)
        #expect(indent(0) == 0 && indent(third(h)) == 18)
        bar.setScope?(.style)
        #expect(indent(0) == 0 && indent(third(h)) == 18)
        bar.setLivePreviewAll?(true)
        #expect(indent(0) == 18 && indent(third(h)) == 18)
    }

    @Test("Trascinatori della tenuta: con quante righe del seguente e del precedente, nello stile o nel solo capoverso")
    func keepHandles() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        let second = (h.text as NSString).range(of: "Secondo").location
        h.select(second + 2)
        h.editor.setParagraphDesign(true)
        #expect(h.editor.paragraphDesignOverlayForTests?.keep == [.next: 0, .previous: 0])
        h.editor.dragKeepForTests(.next, to: 2)
        h.editor.dragKeepForTests(.previous, to: 3)
        #expect(h.editor.paragraphDesignOverlayForTests?.keep == [.next: 2, .previous: 3], "le maniglie mostrano la bozza")
        h.editor.saveParagraphDesign()
        h.step()
        let keeping = h.editor.settings.styles.lineKeeping(styleName: "Body")
        #expect(keeping.withNext && keeping.nextLines == 2 && keeping.previousLines == 3)
        #expect(h.undoActionName == "Paragraph Design")
        // Tirata a zero, la tenuta col seguente si spegne.
        h.editor.setParagraphDesign(true)
        h.editor.dragKeepForTests(.next, to: 0)
        h.editor.saveParagraphDesign()
        #expect(!h.editor.settings.styles.lineKeeping(styleName: "Body").withNext)
        h.undo(); h.undo()
        #expect(!h.editor.settings.styles.lineKeeping(styleName: "Body").withNext && h.editor.settings.styles.lineKeeping(styleName: "Body").previousLines == 0)
        // Solo questo capoverso: la tenuta va sul capoverso, lo stile non cambia.
        h.select(second + 2)
        h.editor.setParagraphDesign(true)
        h.editor.paragraphDesignBarForTests?.setScope?(.paragraph)
        h.editor.dragKeepForTests(.previous, to: 2)
        h.editor.saveParagraphDesign()
        #expect(TextStyling.lineKeeping(in: h.attributed, at: second).previousLines == 2)
        #expect(h.editor.settings.styles.lineKeeping(styleName: "Body").previousLines == 0)
    }

    @Test("Occhio barrato: un capoverso progettato prima tiene il suo valore dato a mano finché non si salva")
    func eyeClosedKeepsEarlierManualValue() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.changeForTests(.leftIndent) { $0.leftIndent = 40 }
        h.step()
        h.editor.setParagraphDesign(true)
        h.editor.paragraphDesignBarForTests?.setLivePreviewAll?(false)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: -20, height: 0))
        func indent(_ index: Int) -> CGFloat {
            (h.editor.paragraphDesignPreviewForTests?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
        }
        #expect(indent(0) == 20, "sul capoverso evidenziato vale lo stile della bozza")
        h.select(third(h) + 2)
        h.step()
        #expect(indent(0) == 40, "passati a un altro capoverso, il primo torna com'è nel documento")
        #expect(indent(third(h)) == 20)
        h.editor.saveParagraphDesign()
        h.step()
        #expect(try paragraphStyle(h, at: 0).headIndent == 20, "salvando, il valore dato a mano se ne va come prima")
    }

    @Test("Il righello in progettazione legge e scrive la bozza; i suoi margini vanno nella bozza")
    func rulerInDesign() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        h.editor.dragDesignHandleForTests(.leftIndent, by: CGSize(width: 18, height: 0))
        h.editor.refreshRuler()
        #expect(abs((h.editor.rulerGeometry?.left ?? 0) - 18) < 0.01, "il righello mostra il rientro della bozza")
        let millimetre = 72 / 25.4
        h.editor.dragRulerForTests(.right, to: 10 * millimetre)
        #expect(abs((h.editor.paragraphDesignDraftForTests?.styleEdits["Body"]?[.rightIndent]?.rightIndent ?? 0) - 10 * millimetre) < 0.01,
                "il triangolo del righello va nella bozza")
        #expect(h.editor.settings.styles.resolveParagraph(styleName: "Body").rightIndent == 0, "il documento non cambia")
        let before = h.editor.settings.pageSetup
        h.editor.dragRulerForTests(.marginLeft, to: 40 * millimetre)
        #expect(abs((h.editor.paragraphDesignDraftForTests?.pageSetups[""]?.left ?? 0) - 40 * millimetre) < 0.01)
        #expect(h.editor.settings.pageSetup == before)
        h.editor.saveParagraphDesign()
        h.step()
        #expect(abs(h.editor.settings.pageSetup.left - 40 * millimetre) < 0.01)
        #expect(abs(h.editor.settings.styles.resolveParagraph(styleName: "Body").rightIndent - 10 * millimetre) < 0.01)
        h.undo()
        #expect(h.editor.settings.pageSetup == before)
    }

    @Test("Fuori dalla progettazione i margini si trascinano sul righello: un passo di Annulla")
    func rulerMargins() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        let before = h.editor.settings.pageSetup
        let millimetre = 72 / 25.4
        h.editor.dragRulerForTests(.marginRight, to: 35 * millimetre)
        h.step()
        #expect(abs(h.editor.settings.pageSetup.right - 35 * millimetre) < 0.01 && h.editor.settings.pageSetup.left == before.left)
        #expect(abs((h.editor.rulerGeometry?.columnWidth ?? 0) / (h.editor.rulerGeometry?.scale ?? 1) - (before.paperSize.width - before.left - 35 * millimetre)) < 0.5,
                "il righello mostra lo specchio nuovo")
        h.undo()
        #expect(h.editor.settings.pageSetup == before)
    }

    @Test("La testata nella progettazione: parti dalla barra, maniglie sulla pagina, nella bozza; spenta con l'occhio barrato")
    func headingInDesign() throws {
        let h = EditorHarness(paragraphs: Self.text)
        defer { h.close() }
        h.select(5)
        h.editor.setParagraphDesign(true)
        let bar = try #require(h.editor.paragraphDesignBarForTests)
        #expect(bar.headingEditable && bar.headingParts.isEmpty)
        bar.useStandardHeading?()
        #expect(bar.headingParts == HeadingComposition.standard.parts, "la barra mostra le parti della testata")
        let placed = h.editor.currentLayout()?.pages[0].headingParts.filter { $0.paragraphLocation == 0 } ?? []
        #expect(placed.contains { $0.part == 1 }, "lo spazio dopo il numero è posato sulla pagina: \(placed.map(\.part))")
        let before = HeadingComposition.standard.parts[1]
        guard case .space(let start) = before else { Issue.record("la parte 1 è uno spazio"); return }
        #expect(h.editor.designHeadingGripsForTests.isEmpty, "senza una parte scelta, nessuna maniglia")
        bar.selectHeadingPart?(1)
        #expect(Set(h.editor.designHeadingGripsForTests) == [HeadingGripID(part: 1, grip: .space)])
        h.editor.dragHeadingForTests(HeadingGripID(part: 1, grip: .space), by: CGSize(width: 0, height: 10))
        let step = PageSetup.points(fromMillimetres: 0.5)
        let expected = ((CGFloat(start) + 10) / step).rounded() * step
        guard case .space(let length)? = h.editor.paragraphDesignDraftForTests?.headings["Body"]??.parts[1] else { Issue.record("spazio nella bozza"); return }
        #expect(abs(CGFloat(length) - expected) < 0.01)
        #expect(h.editor.settings.styles.style(named: "Body")?.heading == nil, "il documento non cambia prima di Salva")
        // Con l'occhio barrato la testata non si cambia.
        bar.setLivePreviewAll?(false)
        #expect(!bar.headingEditable)
        bar.addHeadingPart?(.label(text: "Capitolo", style: nil, alignment: .left, minHeight: nil))
        #expect(h.editor.paragraphDesignDraftForTests?.headings["Body"]??.parts.count == HeadingComposition.standard.parts.count)
        bar.setLivePreviewAll?(true)
        h.editor.saveParagraphDesign()
        h.step()
        guard case .space(let saved)? = h.editor.settings.styles.style(named: "Body")?.heading?.parts[1] else { Issue.record("spazio salvato"); return }
        #expect(abs(CGFloat(saved) - expected) < 0.01)
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Body")?.heading == nil)
    }
}

