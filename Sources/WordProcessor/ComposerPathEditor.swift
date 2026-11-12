import SwiftUI
import Typesetting

/// A path is a projection of the owning draft. Choices write through to that draft;
/// this view stores no second copy of the path or its values.
struct ComposerPathChoice {
    let title: String
    let select: () -> Void

    static func choices<T>(_ values: [T], title: (T) -> String, select: @escaping (T) -> Void) -> [Self] {
        values.map { value in Self(title: title(value), select: { select(value) }) }
    }
}

struct ComposerPathNode {
    let verb: String
    let symbol: String
    let title: String
    let choices: [ComposerPathChoice]
    var emptyMessage: String? = nil
    var remove: (() -> Void)? = nil
    var detail: AnyView = AnyView(EmptyView())
}

enum ComposerPathRow {
    case node(ComposerPathNode)
    case insertion(AnyView)
}

/// The same path editor serves a full field chain and a style target. Each caller
/// supplies only choices allowed by its existing model and validation rules.
struct ComposerPathEditor: View {
    enum Layout { case blocks, inline }
    let rows: [ComposerPathRow]
    let layout: Layout
    var startNumber = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                switch row {
                case .insertion(let view): view
                case .node(let node):
                    if layout == .blocks {
                        FieldFormulaBlock(number: startNumber - 1 + rows.prefix(index + 1).filter { if case .node = $0 { true } else { false } }.count,
                                          symbol: node.symbol, verb: node.verb, remove: node.remove) {
                            controls(node)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(node.verb).font(.caption).foregroundStyle(.secondary)
                            controls(node)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func controls(_ node: ComposerPathNode) -> some View {
        if let message = node.emptyMessage {
            Text(message).foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(Array(node.choices.enumerated()), id: \.offset) { _, choice in
                    Button(choice.title, action: choice.select)
                }
            } label: { ComposerPill(title: node.title) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(node.verb).accessibilityValue(node.title)
            node.detail
        }
    }
}

/// Value controls use bindings to the owning draft, including typed formula constants.
struct ComposerValueEditor: View {
    enum Input {
        case text(label: String, value: Binding<String>, width: CGFloat)
        case formula(Binding<FormulaValue>)
    }
    let input: Input

    var body: some View {
        switch input {
        case .text(let label, let value, let width):
            TextField(label, text: value).textFieldStyle(.roundedBorder).frame(width: width)
        case .formula(let value):
            switch value.wrappedValue {
            case .number(let n), .length(let n):
                TextField("Value", value: Binding(get: { n }, set: {
                    value.wrappedValue = value.wrappedValue.type == .length ? .length($0) : .number($0)
                }), format: .number).textFieldStyle(.roundedBorder).frame(width: 140)
            case .boolean(let flag):
                Toggle("Yes", isOn: Binding(get: { flag }, set: { value.wrappedValue = .boolean($0) }))
            }
        }
    }
}
