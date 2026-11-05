import AppKit
import SwiftUI
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Compositore di stili ad azioni", .serialized) @MainActor
struct ActionComposerTests {
    private func leftIndent(_ h: EditorHarness) -> CGFloat? {
        (h.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent
    }

    @Test("Base 12 pt + margine 6 pt → Distanza → rientro sinistro: 18 pt; con margine 10 pt, 22 pt; Annulla e file")
    func distanceThroughTheComposer() throws {
        let h = EditorHarness(paragraphs: ["Prova del rientro.", "Secondo capoverso."])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        // La formula del documento, come la definisce la scheda Formule.
        let base = FormulaParameter(name: "Base", type: .length)
        let definition = ReusableFormula(name: "Rientro con margine", parameters: [base], resultType: .length,
                                         expression: .add(.parameter(base.id), .constant(.length(6))))
        board.sheet.reusableFormulas = [definition]
        // Dalla libreria: «Rientro con margine» diventa una variabile; Base 12 pt; la variabile si chiama Distanza.
        let variable = try #require(board.addVariable(calling: definition))
        board.updateVariable(variable, expression: .call(definition.id, arguments: [base.id: .constant(.length(12))]))
        board.renameVariable(variable, to: "Distanza")
        let distance = try #require(board.currentStyle?.variables.first { $0.id == variable })
        #expect(board.value(of: distance).value == .length(18))
        // Dalla libreria: Imposta rientro sinistro, poi il suo valore diventa la variabile.
        let action = try #require(board.addAction(.leftIndent))
        let formula = try #require(board.currentStyle?.formulas.first { $0.id == action })
        #expect(board.compatibleVariables(for: formula).map(\.name) == ["Distanza"])
        board.bind(action, to: variable)
        #expect(board.validationIssue == nil, "\(board.validationIssue ?? "")")
        #expect(board.users(of: variable) == 1)
        board.apply(); h.step()
        #expect(leftIndent(h) == 18)
        // La definizione cambia (margine 10 pt): tutte le occorrenze dello stile seguono.
        board.sheet.reusableFormulas[0].expression = .add(.parameter(base.id), .constant(.length(10)))
        board.apply(); h.step()
        #expect(leftIndent(h) == 22)
        #expect((h.attributed.attribute(.paragraphStyle, at: 20, effectiveRange: nil) as? NSParagraphStyle)?.headIndent == 22)
        h.undo()
        #expect(leftIndent(h) == 18)
        h.redo()
        #expect(leftIndent(h) == 22)
        // Il file conserva variabile e collegamento, alla versione 12.
        let data = try h.document.data(ofType: TextDocument.typeName)
        let xml = try #require(String(data: data, encoding: .utf8))
        #expect(xml.contains("version=\"12\"") && xml.contains("name=\"Distanza\""))
        let read = try DocumentFormat.document(from: data)
        #expect(read.styles.resolveParagraph(styleName: "Body").leftIndent == 22)
        // Il ritorno a un valore fisso conserva il valore che la variabile dava.
        board.bind(action, to: nil)
        #expect(board.currentStyle?.formulas.first { $0.id == action }?.operation.argument == .length(22, .points))
    }

    @Test("Una variabile usata non si toglie; le azioni non escono dalla loro fase; una condizione non ammessa si spiega")
    func guards() throws {
        let h = EditorHarness(paragraphs: ["Prova."])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        let variable = try #require(board.addVariable(named: "Spazio", expression: .constant(.length(6))))
        let before = try #require(board.addAction(.spaceBefore))
        board.bind(before, to: variable)
        board.removeVariable(variable)
        #expect(board.problem?.contains("used by") == true)
        #expect(board.currentStyle?.variables.contains { $0.id == variable } == true)
        // Una direttiva (stile dopo Invio) e una formattazione non si scambiano di posto.
        let next = try #require(board.addAction(.nextStyle))
        #expect(!board.canMove(next, by: -1))
        let size = try #require(board.addAction(.size))
        #expect(board.canMove(size, by: -1), "fra formattazioni della stessa fase sì")
        // Trascinando: la formattazione va al posto di un'altra formattazione, non della direttiva.
        let first = try #require(board.currentStyle?.formulas.first { $0.phase == .base }?.id)
        #expect(board.canMoveAction(size, to: first) && !board.canMoveAction(size, to: next))
        board.moveAction(size, to: first)
        #expect(board.currentStyle?.formulas.first { $0.phase == .base }?.id == size)
        let order = board.currentStyle?.formulas.map(\.id)
        board.moveAction(next, to: size)
        #expect(board.currentStyle?.formulas.map(\.id) == order, "fra fasi diverse non si sposta")
        board.applyCondition(.firstOnPage, to: next)
        #expect(board.problem?.contains("does not accept") == true)
        board.applyCondition(.firstOnPage, to: size)
        #expect(board.problem == nil)
        #expect(board.currentStyle?.formulas.first { $0.id == size }?.when.position == .firstOnPage)
        // La condizione vale per quell'azione sola, non per le seguenti.
        #expect(board.currentStyle?.formulas.first { $0.id == before }?.when.isAlways == true)
        // Rinominare non interrompe; una variabile in giro si segnala.
        board.renameVariable(variable, to: "Respiro")
        #expect(board.validationIssue == nil, "\(board.validationIssue ?? "")")
        board.updateVariable(variable, expression: .variable(variable))
        #expect(board.validationIssue != nil)
    }

    @Test("La testata dal compositore: pronta, un'etichetta prima del titolo, parti spostate e tolte; Applica, Annulla, file")
    func headingThroughTheComposer() throws {
        let h = EditorHarness(paragraphs: ["Prova."])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Heading 1")
        board.useStandardHeading()
        #expect(board.currentHeading == .standard)
        board.addHeadingPart(.label(text: "Capitolo", style: nil, alignment: .center, minHeight: nil))
        let parts = try #require(board.currentHeading?.parts)
        let label = try #require(parts.firstIndex { if case .label = $0 { true } else { false } })
        #expect(label < (parts.firstIndex(of: .title) ?? 0), "l'etichetta va prima del titolo")
        board.moveHeadingPart(at: label, by: -1)
        // Trascinando la prima parte in fondo e di nuovo in cima, l'ordine torna quello di prima.
        let before = try #require(board.currentHeading?.parts)
        board.moveHeadingPart(from: 0, to: before.count - 1)
        #expect(board.currentHeading?.parts.last == before.first)
        board.moveHeadingPart(from: before.count - 1, to: 0)
        #expect(board.currentHeading?.parts == before)
        board.removeHeadingPart(at: parts.count - 1)
        #expect(board.currentHeading?.parts.last == .title, "tolto lo spazio dopo il titolo")
        #expect(board.validationIssue == nil, "\(board.validationIssue ?? "")")
        board.apply(); h.step()
        let applied = try #require(h.editor.settings.styles.style(named: "Heading 1")?.heading)
        #expect(applied == board.currentHeading)
        let xml = try #require(String(data: try h.document.data(ofType: TextDocument.typeName), encoding: .utf8))
        #expect(xml.contains("<heading encoding=\"json-v1\""))
        h.undo()
        #expect(h.editor.settings.styles.style(named: "Heading 1")?.heading == nil)
        h.redo()
        #expect(h.editor.settings.styles.style(named: "Heading 1")?.heading == applied)
        // Una seconda parte «titolo» è una diagnosi.
        board.updateHeadingPart(at: 0, to: .title)
        #expect(board.validationIssue?.contains("title") == true)
    }

    @Test("La finestra del compositore si disegna anche stretta, con le tre aree e le azioni aperte")
    func layout() throws {
        let h = EditorHarness(paragraphs: ["Prova."])
        defer { h.close() }
        h.editor.openStyleComposer(nil)
        let board = try #require(h.editor.composerModel)
        board.selectStyle("Body")
        _ = board.addVariable(named: "Distanza", expression: .add(.constant(.length(12)), .constant(.length(6))))
        _ = board.addAction(.leftIndent)
        let window = try #require(h.editor.composerController?.window)
        #expect(window.title.hasPrefix("Style Composer"))
        for width in [740.0, 1000, 1400] {
            window.setContentSize(NSSize(width: width, height: 560))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(abs(window.frame.width - window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: 560)).width) < 1,
                    "la finestra resta larga \(width): \(window.frame.width)")
        }
        window.close()
    }
}
