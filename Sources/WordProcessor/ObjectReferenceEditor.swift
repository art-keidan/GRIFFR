import SwiftUI
import Typesetting

struct ObjectReferenceEditor: View {
    struct Target: Identifiable {
        let id: UUID
        let title: String
        let kind: String
        let number: String?
        let excerpt: String
        /// Per una nota dichiarata, la sua occorrenza: `id` allora distingue solo la riga dell'elenco.
        var declaredNote: DeclaredNoteSlot? = nil

        /// Il rimando a questo oggetto, con la lettura data.
        func reference(reading: ObjectReference.Reading = .number) -> ObjectReference {
            declaredNote.map { ObjectReference(declaredNote: $0, reading: reading) } ?? ObjectReference(target: id, reading: reading)
        }

        /// Vero se `reference` punta a questo oggetto.
        func isTarget(of reference: ObjectReference) -> Bool {
            if let declaredNote { return reference.declaredNote == declaredNote }
            return reference.declaredNote == nil && reference.target == id
        }

        var details: String {
            guard let number, !number.isEmpty, number != title else { return kind }
            return number
        }

        func matches(_ query: String) -> Bool {
            query.isEmpty || [title, kind, number ?? "", excerpt].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    let targets: [Target]
    let editing: Bool
    let preview: (ObjectReference) -> String
    let finish: (ObjectReference?) -> Void
    @State var reference: ObjectReference
    @State private var choosingObject = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var target: Target? { targets.first { $0.isTarget(of: reference) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing ? "Object Reference" : "New Object Reference").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                FieldFormulaBlock(number: 1, symbol: "scope", verb: "Start from") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Referenced object").font(.caption).foregroundStyle(.secondary)
                        Button {
                            search = ""
                            choosingObject = true
                        } label: {
                            ComposerPill(title: target?.title ?? "Missing object", placeholder: target == nil)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose referenced object")
                        .accessibilityValue(target?.title ?? "Missing object")
                        .popover(isPresented: $choosingObject, arrowEdge: .bottom) {
                            objectPicker
                        }
                    }
                    .layoutPriority(1)
                }
                ComposerPathEditor(rows: [.node(ComposerPathNode(
                    verb: "Read", symbol: "text.viewfinder", title: reference.reading.title,
                    choices: ComposerPathChoice.choices(ObjectReference.Reading.allCases, title: { $0.title },
                                                        select: { reference.reading = $0 })))],
                                   layout: .blocks, startNumber: 2)
                FieldFormulaBlock(number: 3, symbol: "square.and.pencil", verb: "Write result") {
                    Text("Here").foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Divider()
            let result = target == nil ? "(??)" : preview(reference)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Preview").foregroundStyle(.secondary)
                Text(result.isEmpty ? "(nothing)" : result).fontWeight(.medium)
            }
            if target == nil {
                Label(targets.isEmpty ? "The referenced object is missing." : "Choose another object to repair the reference.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(nsColor: Theme.warn))
            }

            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button(editing ? "Apply" : "Insert") { finish(reference) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
        .background(Color(nsColor: Theme.window))
    }

    private var objectPicker: some View {
        let visible = targets.filter { $0.matches(search.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Search objects", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit {
                    if visible.count == 1, let object = visible.first { select(object) }
                }

            if visible.isEmpty {
                Text(targets.isEmpty ? "There are no figures or notes in this document." : "No objects match your search.")
                    .foregroundStyle(.secondary)
                    .padding(6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { object in
                            Button { select(object) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(object.title).fontWeight(.medium).lineLimit(1)
                                        Text(object.details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if !object.excerpt.isEmpty {
                                            Text(object.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if object.isTarget(of: reference) {
                                        Image(systemName: "checkmark").foregroundStyle(Color(nsColor: Theme.glyph))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.hover(.borderless))
                            .accessibilityAddTraits(object.isTarget(of: reference) ? .isSelected : [])
                        }
                    }
                }
                .frame(maxHeight: 255)
            }
        }
        .padding(12)
        .frame(width: 350)
        .background(Color(nsColor: Theme.window))
        .onAppear { searchFocused = true }
    }

    private func select(_ object: Target) {
        reference = object.reference(reading: reference.reading)
        choosingObject = false
    }
}
