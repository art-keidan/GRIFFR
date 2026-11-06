import AppKit
import SwiftUI

/// Lo stato del foglio «Personalizza gli strumenti…»: i comandi del livello corrente e quelli che si possono aggiungere.
@MainActor
final class ToolbarSheetModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        var command: String
    }

    struct Command {
        var id: String
        var title: String
        var symbol: String
    }

    @Published var entries: [Entry]
    @Published var selection: Entry.ID?
    let commands: [Command]
    private let defaults: [String]
    /// Chiamata alla chiusura: con i comandi scelti per «OK», con `nil` per «Annulla».
    var finish: (([String]?) -> Void)?

    init(items: [String], commands: [(String, String, String)], defaults: [String]) {
        entries = items.map { Entry(command: $0) }
        self.commands = commands.map { Command(id: $0.0, title: $0.1, symbol: $0.2) }
        self.defaults = defaults
    }

    func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: ToolbarSheetView(model: self).themed())
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(controller.view.fittingSize)
        return window
    }

    func command(_ id: String) -> Command? { commands.first { $0.id == id } }

    /// I comandi che non sono già nella barra (la riga di separazione si può aggiungere sempre).
    var available: [Command] { commands.filter { command in !entries.contains { $0.command == command.id } } }

    func add(_ id: String) {
        let entry = Entry(command: id)
        if let selected = entries.firstIndex(where: { $0.id == selection }) {
            entries.insert(entry, at: selected + 1)
        } else {
            entries.append(entry)
        }
        selection = entry.id
    }

    func removeSelected() {
        guard let index = entries.firstIndex(where: { $0.id == selection }) else { return }
        entries.remove(at: index)
        selection = entries.indices.contains(index) ? entries[index].id : entries.last?.id
    }

    func reset() {
        entries = defaults.map { Entry(command: $0) }
        selection = nil
    }
}

struct ToolbarSheetView: View {
    @ObservedObject var model: ToolbarSheetModel

    private func label(_ id: String) -> some View {
        HStack(spacing: 8) {
            if id == "|" {
                Rectangle().frame(width: 1, height: 14).foregroundStyle(.secondary)
                Text("New Group").foregroundStyle(.secondary)
            } else if let command = model.command(id) {
                Image(systemName: command.symbol).frame(width: 18)
                Text(command.title)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize Tools").font(.headline)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In the toolbar").font(.subheadline.bold())
                    List(selection: $model.selection) {
                        ForEach(model.entries) { entry in label(entry.command).tag(entry.id) }
                            .onMove { model.entries.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(width: 280, height: 360)
                    HStack(spacing: 4) {
                        Button { model.removeSelected() } label: { Image(systemName: "minus") }
                            .disabled(model.selection == nil)
                            .help("Remove the chosen command from the toolbar")
                        Spacer()
                        Button("Restore") { model.reset() }.help("The toolbar as it was at the start")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("To add").font(.subheadline.bold())
                    List {
                        ForEach(model.available, id: \.id) { command in
                            HStack {
                                label(command.id)
                                Spacer()
                                Button { model.add(command.id) } label: { Image(systemName: "plus") }.buttonStyle(.hover(.borderless))
                                    .help("Add after the chosen command")
                            }
                        }
                        HStack {
                            label("|")
                            Spacer()
                            Button { model.add("|") } label: { Image(systemName: "plus") }.buttonStyle(.hover(.borderless))
                        }
                    }
                    .frame(width: 300, height: 360)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.finish?(nil) }.keyboardShortcut(.cancelAction)
                Button("OK") { model.finish?(model.entries.map(\.command)) }.keyboardShortcut(.defaultAction).buttonStyle(.hover(.prominent))
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}
