import AppKit
import Testing
@testable import Typesetting
@testable import WordProcessor

/// Una finestra dell'editor guidata dalle prove: tasti e comandi arrivano come li manda la vista delle pagine,
/// e tra un'azione e l'altra passa un giro del ciclo degli eventi, come quando si scrive davvero (l'annullamento
/// raggruppa le modifiche evento per evento).
@MainActor
final class EditorHarness {
    let document: TextDocument
    let editor: EditorWindowController

    static let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)

    /// Un editor con i paragrafi dati (ciascuno nello stile «Testo», senza elenco), con gli stili e le Liste
    /// predefiniti; `nil` per il testo di prova di un documento nuovo.
    init(paragraphs: [String]? = nil) {
        _ = NSApplication.shared
        document = TextDocument()
        document.makeWindowControllers()
        editor = document.windowControllers.first as! EditorWindowController
        editor.pasteboard = NSPasteboard(name: NSPasteboard.Name("local.wordprocessor.tests.\(UUID().uuidString)"))
        if let paragraphs {
            let sheet = StyleSheet.builtIn
            let style = sheet.resolveCharacter(paragraphStyle: "Testo", wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            editor.replaceContent(Document(styles: sheet, lists: ListDefinition.builtIn, noteList: "Note", blocks: paragraphs.map {
                .paragraph(Paragraph(styleName: "Testo", style: sheet.resolveParagraph(styleName: "Testo"), inlines: [.text(TextRun($0, style: style))]))
            }))
            document.undoManager?.removeAllActions()
        }
        step()
    }

    /// Lascia passare un giro del ciclo degli eventi.
    func step() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }

    var text: String { editor.editingText.string }
    var attributed: NSAttributedString { editor.editingText }
    var selection: NSRange { editor.selection.range }

    /// Mette il cursore (o la selezione) dove si vuole.
    func select(_ location: Int, length: Int = 0) {
        editor.apply(TextSelection(anchor: location, head: location + length))
        step()
    }

    /// Scrive un carattere alla volta, come dalla tastiera.
    func type(_ string: String) {
        for character in string {
            editor.pagesInsert(String(character), replacementRange: editor.pagesSelectedRange)
            step()
        }
    }

    /// Un comando di tastiera (a capo, cancella, frecce, Esc…), come lo traduce il sistema.
    func press(_ command: Selector, times: Int = 1) {
        for _ in 0..<times {
            editor.pagesPerform(command)
            step()
        }
    }

    /// Una voce dei menu che arriva alla vista delle pagine (Taglia, Copia, Incolla, Seleziona tutto).
    @discardableResult
    func menu(_ action: Selector) -> Bool {
        let done = editor.pagesForwardAction(action, sender: nil)
        step()
        return done
    }

    func undo() {
        document.undoManager?.undo()
        step()
    }

    func redo() {
        document.undoManager?.redo()
        step()
    }

    var undoActionName: String { document.undoManager?.undoActionName ?? "" }

    /// La Lista o l'elenco del paragrafo che contiene `index`.
    func list(at index: Int) -> ListItem? { TextStyling.listItem(in: attributed, at: index) }

    /// La struttura interna del deposito è coerente con il suo testo (paragrafi, posizioni, identità).
    var storeIsConsistent: Bool { editor.store.structuralProblem() == nil }

    func close() {
        #expect(storeIsConsistent, "deposito coerente: \(editor.store.structuralProblem() ?? "")")
        document.undoManager?.removeAllActions()
        editor.window?.orderOut(nil)
        document.close()
    }
}
