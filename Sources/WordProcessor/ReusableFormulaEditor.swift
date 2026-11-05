import SwiftUI
import Typesetting

struct FormulaExpressionEditor: View {
    @Binding var expression: FormulaExpression
    let type: FormulaValueType
    let parameters: [FormulaParameter]
    let definitions: [ReusableFormula]
    var depth = 0

    var body: some View { content }
    private var content: AnyView {
        guard depth < 24 else { return AnyView(Text("Expression too deep").foregroundStyle(.red)) }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Menu {
                Button("Constant value") { expression = .constant(type.zero) }
                if type != .boolean { Button("Sum") { expression = .add(.constant(type.zero), .constant(type.zero)) } }
                ForEach(parameters.filter { $0.type == type }) { parameter in
                    Button("Parameter · " + parameter.name) { expression = .parameter(parameter.id) }
                }
                ForEach(definitions.filter { $0.resultType == type }) { definition in
                    Button("Call · " + definition.name) {
                        expression = .call(definition.id, arguments: Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, .constant($0.type.zero)) }))
                    }
                }
            } label: { Text(title) }
            switch expression {
            case .constant(let value):
                FormulaValueEditor(value: Binding(get: { value }, set: { expression = .constant($0) }))
            case .parameter, .variable: EmptyView()
            case .add(let a, let b):
                child(Binding(get: { a }, set: { expression = .add($0, b) }), type)
                Text("+")
                child(Binding(get: { b }, set: { expression = .add(a, $0) }), type)
            case .call(let id, let arguments):
                if let definition = definitions.first(where: { $0.id == id }) {
                    ForEach(definition.parameters) { parameter in
                        Text(parameter.name + " · " + parameter.type.title).font(.caption)
                        child(Binding(get: { arguments[parameter.id] ?? .constant(parameter.type.zero) }, set: { value in
                            var updated = arguments; updated[parameter.id] = value; expression = .call(id, arguments: updated)
                        }), parameter.type)
                    }
                    if Set(arguments.keys) != Set(definition.parameters.map(\.id)) {
                        Button("Update Arguments to the Signature") {
                            expression = .call(id, arguments: Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, arguments[$0.id] ?? .constant($0.type.zero)) }))
                        }
                    }
                } else { Text("Definition not found").foregroundStyle(.red) }
            }
        }.padding(10).overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3))))
    }
    private func child(_ binding: Binding<FormulaExpression>, _ type: FormulaValueType) -> some View {
        FormulaExpressionEditor(expression: binding, type: type, parameters: parameters, definitions: definitions, depth: depth + 1).padding(.leading, 12)
    }
    private var title: String {
        switch expression {
        case .constant: "Value · " + type.title
        case .parameter(let id): "Parameter · " + (parameters.first { $0.id == id }?.name ?? "assente")
        case .add: "Sum · " + type.title
        case .call(let id, _): "Call · " + (definitions.first { $0.id == id }?.name ?? "assente")
        case .variable: "Variable"
        }
    }
}

struct FormulaValueEditor: View {
    @Binding var value: FormulaValue
    var body: some View {
        switch value {
        case .number(let n), .length(let n):
            TextField("Value", value: Binding(get: { n }, set: { value = value.type == .length ? .length($0) : .number($0) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 140)
        case .boolean(let flag): Toggle("Yes", isOn: Binding(get: { flag }, set: { value = .boolean($0) }))
        }
    }
}

struct ReusableDefinitionEditor: View {
    @Binding var definition: ReusableFormula
    let definitions: [ReusableFormula]
    let remove: () -> Void
    @State private var arguments: [UUID: FormulaValue] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Name", text: $definition.name).textFieldStyle(.roundedBorder)
                Picker("Result", selection: $definition.resultType) {
                    ForEach([FormulaValueType.number, .length, .boolean], id: \.self) { Text($0.title).tag($0) }
                }.frame(width: 240)
                Button("Remove", action: remove)
            }
            ForEach($definition.parameters) { $parameter in
                HStack {
                    TextField("Parameter", text: $parameter.name)
                    Picker("Type", selection: $parameter.type) {
                        ForEach([FormulaValueType.number, .length, .boolean], id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Remove") { definition.parameters.removeAll { $0.id == parameter.id } }
                }
            }
            Button("Add Parameter") { definition.parameters.append(FormulaParameter(name: "Parameter \(definition.parameters.count + 1)", type: .length)) }
            FormulaExpressionEditor(expression: $definition.expression, type: definition.resultType, parameters: definition.parameters, definitions: definitions)
            if !definition.parameters.isEmpty { Text("Test arguments").font(.caption.bold()) }
            ForEach(definition.parameters) { parameter in
                HStack {
                    Text(parameter.name)
                    FormulaValueEditor(value: Binding(get: { arguments[parameter.id]?.type == parameter.type ? arguments[parameter.id]! : parameter.type.zero }, set: { arguments[parameter.id] = $0 }))
                }
            }
            Text(result).font(.caption).textSelection(.enabled)
        }.padding(16).background(.background).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private var result: String {
        let args = Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, arguments[$0.id]?.type == $0.type ? arguments[$0.id]! : $0.type.zero) })
        do { return "Test result: " + (try ReusableFormulaLibrary(definitions: definitions).evaluate(definition.id, arguments: args)).description }
        catch { var sheet = StyleSheet(); sheet.reusableFormulas = definitions; return sheet.reusableProblem(error) }
    }
}
