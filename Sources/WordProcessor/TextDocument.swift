import AppKit
import PDFKit
import Typesetting

/// Il documento visto da AppKit: lettura e scrittura del file, finestra, stato «modificato», annullamento.
@objc(TextDocument)
final class TextDocument: NSDocument {
    static let typeName = "local.wordprocessor.document"

    /// Contenuto letto da un file, in attesa che venga creata la finestra.
    /// AppKit dichiara lettura e scrittura fuori dal thread principale, ma senza lettura concorrente
    /// (che non abilitiamo) le chiama da lì: l'accesso resta di fatto seriale.
    nonisolated(unsafe) private var loaded: Document?

    nonisolated(unsafe) private var backingVersion = 1

    private var editor: EditorWindowController? {
        MainActor.assumeIsolated { windowControllers.first as? EditorWindowController }
    }

    // Salvataggio esplicito, come in un programma classico: niente scritture automatiche sul file originale.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        MainActor.assumeIsolated {
            let editor = EditorWindowController(content: loaded)
            addWindowController(editor)
            // Riaprendo un file, lo si guarda come lo si guardava alla chiusura.
            if let url = fileURL, let state = DocumentViewState.read(from: url) { editor.restoreViewState(state) }
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let document = try DocumentFormat.document(from: data)
        backingVersion = document.sourceVersion
        loaded = document
        // «Ripristina»: la finestra esiste già e va riportata al contenuto del file.
        MainActor.assumeIsolated {
            (windowControllers.first as? EditorWindowController)?.replaceContent(document)
        }
    }

    /// File › Stampa…: le stesse pagine del PDF esportato, sul formato del foglio del documento. Se la carta scelta nel
    /// pannello è più piccola, la pagina si riduce per starci; altrimenti si stampa a grandezza vera.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        try MainActor.assumeIsolated {
            guard let editor else { throw CocoaError(.featureUnsupported) }
            let printable = editor.printablePDF(title: displayName)
            guard let pdf = PDFDocument(data: printable.data) else { throw CocoaError(.featureUnsupported) }
            let info = printInfo.copy() as! NSPrintInfo
            info.dictionary().addEntries(from: printSettings)
            info.paperSize = printable.paperSize
            info.topMargin = 0
            info.bottomMargin = 0
            info.leftMargin = 0
            info.rightMargin = 0
            guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else {
                throw CocoaError(.featureUnsupported)
            }
            operation.jobTitle = displayName
            return operation
        }
    }

    nonisolated private var snapshot: Document {
        MainActor.assumeIsolated { editor?.currentDocument() ?? loaded ?? Document() }
    }

    override func save(_ sender: Any?) {
        if fileURL != nil, DocumentFormat.writingVersion(for: snapshot) > backingVersion {
            saveAs(sender)
        } else {
            super.save(sender)
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        let accepted = super.prepareSavePanel(savePanel)
        if let fileURL, DocumentFormat.writingVersion(for: snapshot) > backingVersion {
            savePanel.message = "The document's styles or fields need format \(DocumentFormat.writingVersion(for: snapshot)). Choose a name for the copy."
            savePanel.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + " (styles).grx"
        }
        return accepted
    }

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        let version = max(backingVersion, DocumentFormat.writingVersion(for: snapshot))
        if version > backingVersion, url.standardizedFileURL.resolvingSymlinksInPath() == fileURL?.standardizedFileURL.resolvingSymlinksInPath() {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                          userInfo: [NSLocalizedDescriptionKey: "To keep the original document, use Save As to create a copy in format \(version)."])
        }
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation { backingVersion = version }
    }

    override func data(ofType typeName: String) throws -> Data {
        DocumentFormat.data(for: snapshot, minimumVersion: backingVersion)
    }

}

/// Riconosce i file `.grx` e `.wpx` dall'estensione anche se il sistema non ha ancora registrato il tipo dell'app.
final class DocumentController: NSDocumentController {
    override func typeForContents(of url: URL) throws -> String {
        if DocumentFormat.readableExtensions.contains(url.pathExtension.lowercased()) { return TextDocument.typeName }
        return try super.typeForContents(of: url)
    }

    override var defaultType: String? { TextDocument.typeName }

    override func documentClass(forType typeName: String) -> AnyClass? {
        typeName == TextDocument.typeName ? TextDocument.self : super.documentClass(forType: typeName)
    }
}
