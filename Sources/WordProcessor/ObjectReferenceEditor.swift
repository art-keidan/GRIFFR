import SwiftUI
import Typesetting

struct ObjectReferenceEditor: View {
    struct Target: Identifiable {
        let id: UUID
        let title: String
        let kind: String
        let number: String?
        let excerpt: String

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

    private var target: Target? { targets.first { $0.id == reference.target } }

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
                FieldFormulaBlock(number: 2, symbol: "text.viewfinder", verb: "Read") {
                    Menu {
                        ForEach(ObjectReference.Reading.allCases, id: \.self) { reading in
                            Button(reading.title) { reference.reading = reading }
                        }
                    } label: {
                        ComposerPill(title: reference.reading.title)
                    }
                    .accessibilityLabel("Read")
                    .accessibilityValue(reference.reading.title)
                }
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
                                    if reference.target == object.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color(nsColor: Theme.glyph))
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.hover(.borderless))
                            .accessibilityAddTraits(reference.target == object.id ? .isSelected : [])
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
        reference.target = object.id
        choosingObject = false
    }
}
