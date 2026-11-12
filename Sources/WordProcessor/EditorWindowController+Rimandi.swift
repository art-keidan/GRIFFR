import AppKit
import SwiftUI
import Typesetting

extension EditorWindowController {
    var objectAnchorForLabel: Int? {
        if let noteAnchor { return noteAnchor }
        let location = selection.range.location
        return location < store.length && TextStyling.isNoteAnchor(in: store, at: location) ? location : nil
    }

    @objc func editObjectLabel(_ sender: Any?) {
        guard let window, let anchor = objectAnchorForLabel, let identity = FloatingIdentity.at(anchor, in: store) else { return }
        let alert = NSAlert()
        alert.messageText = "Object Label"
        alert.informativeText = "Give this object a unique label to find it when inserting a reference."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: identity.label ?? "")
        input.frame.size = CGSize(width: 270, height: 24)
        input.placeholderString = "Label"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { [weak self] answer in
            guard answer == .alertFirstButtonReturn else { return }
            self?.applyObjectLabel(input.stringValue, id: identity.id)
        }
    }

    private func applyObjectLabel(_ value: String, id: UUID) {
        let occurrences = FloatingIdentity.occurrences(in: store)
        guard let current = occurrences.first(where: { $0.identity.id == id }) else { return }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.isEmpty || (FloatingIdentity.validLabel(label) && !occurrences.contains {
            $0.identity.id != id && $0.identity.label == label
        }) else {
            guard let window else { return }
            let warning = NSAlert()
            warning.messageText = "Choose a unique label on one line."
            warning.beginSheetModal(for: window)
            return
        }
        let identity = FloatingIdentity(id: id, label: label.isEmpty ? nil : label)
        guard identity != current.identity else { return }
        endUndoStep(next: .none)
        writeStore(actionName: "Object Label") {
            $0.addAttribute(.floatingIdentity, value: identity.encoded, range: NSRange(location: current.location, length: 1))
        }
    }

    @objc func insertObjectReference(_ sender: Any?) {
        presentObjectReference(nil, replacing: selection.range)
    }

    func presentObjectReference(_ existing: ObjectReference?, replacing range: NSRange) {
        guard let window, window.attachedSheet == nil else { return }
        let layout = currentLayout()
        let floatingTargets = FloatingIdentity.occurrences(in: store).enumerated().map { offset, object in
            let kind = store.attribute(.footnote, at: object.location, effectiveRange: nil) as? String ?? "Object"
            let number = layout?.noteMarks[object.location]
            let title = object.identity.label ?? number.flatMap { $0.isEmpty ? nil : $0 } ?? "\(kind) \(offset + 1)"
            let excerpt = TextStyling.footnoteSpan(in: store, anchoredAt: object.location).map { span in
                let content = NSRange(location: span.location + 1, length: span.length - 1)
                let words = (store.string as NSString).substring(with: content)
                    .replacingOccurrences(of: Field.placeholder, with: " ").split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                return String(words.prefix(110)) + (words.count > 110 ? "…" : "")
            } ?? ""
            return ObjectReferenceEditor.Target(id: object.identity.id, title: title, kind: kind, number: number, excerpt: excerpt)
        }
        // Le note dichiarate presentate: un rimando legge il loro numero o la loro pagina, come per una nota scritta.
        let declaredTargets = (layout?.declaredNotes ?? []).compactMap { note -> ObjectReferenceEditor.Target? in
            guard let paragraph = note.paragraphID else { return nil }
            let slot = DeclaredNoteSlot(paragraph: paragraph, declaringStyle: note.declaringStyle, declaration: note.declaration)
            // Il testo del capoverso senza le note scritte che contiene (`BodyText` le salta), per riconoscerlo.
            let paragraphRange = TextStyling.bodyParagraph(in: store, at: min(note.paragraph, max(store.length - 1, 0))).range
            let words = TextStyling.bodyText(in: store, paragraph: paragraphRange)
                .replacingOccurrences(of: Field.placeholder, with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let text = settings.declaredNoteTexts[slot]?.plainText ?? ""
            return ObjectReferenceEditor.Target(id: UUID(), title: note.mark.isEmpty ? "Declared note" : note.mark,
                                                kind: "Declared note · \(note.declaringStyle)", number: note.mark,
                                                excerpt: text.isEmpty ? String(words.prefix(110)) : text, declaredNote: slot)
        }
        let targets = floatingTargets + declaredTargets
        guard let reference = existing ?? targets.first.map({ $0.reference() }) else { return }

        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = existing == nil ? "New Object Reference" : "Object Reference"
        let sourceStore = ObjectIdentifier(store)
        let view = ObjectReferenceEditor(targets: targets, editing: existing != nil,
                                         preview: { layout?.referenceValue($0) ?? "" },
                                         finish: { [weak self, weak window, weak sheet] chosen in
            if let sheet { window?.endSheet(sheet) }
            guard let self, let chosen, ObjectIdentifier(self.store) == sourceStore,
                  NSMaxRange(range) <= self.store.length else { return }
            if let existing {
                guard let encoded = self.store.attribute(.field, at: range.location, effectiveRange: nil) as? String,
                      Field(encoded: encoded) == .reference(existing), existing != chosen else { return }
                self.endUndoStep(next: .none)
                self.writeStore(actionName: "Object Reference") {
                    $0.addAttribute(.field, value: Field.reference(chosen).encoded, range: range)
                }
            } else if self.selection.range == range {
                self.insert(field: .reference(chosen))
            }
        }, reference: reference)
        let controller = NSHostingController(rootView: view.themed())
        sheet.contentViewController = controller
        sheet.setContentSize(controller.view.fittingSize)
        window.beginSheet(sheet)
    }
}
