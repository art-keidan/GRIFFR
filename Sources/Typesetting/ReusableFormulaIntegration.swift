import Foundation

public enum FormulaCodec {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        // Tutti i tipi di questo schema sono valori concreti codificabili; i numeri non finiti sono conservati per la diagnosi.
        return try! encoder.encode(value).base64EncodedString()
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ encoded: String) throws -> T {
        guard let data = Data(base64Encoded: encoded) else { throw ReusableFormulaError.incompatibleTypes }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try decoder.decode(type, from: data)
    }
}

extension FormulaExpression {
    public var references: Set<UUID> {
        switch self {
        case .constant, .parameter, .variable: []
        case .add(let a, let b): a.references.union(b.references)
        case .call(let id, let arguments): arguments.values.reduce([id]) { $0.union($1.references) }
        }
    }
    /// Le variabili dello stile che l'espressione richiama.
    public var variableReferences: Set<UUID> {
        switch self {
        case .constant, .parameter: []
        case .variable(let id): [id]
        case .add(let a, let b): a.variableReferences.union(b.variableReferences)
        case .call(_, let arguments): arguments.values.reduce([]) { $0.union($1.variableReferences) }
        }
    }
    /// L'espressione con le variabili dello stile al posto dei loro nomi, anche quando una variabile ne usa un'altra.
    /// Una variabile assente o un giro di variabili è un errore.
    public func substitutingVariables(_ variables: [StyleVariable], visiting: [UUID] = []) throws -> FormulaExpression {
        switch self {
        case .constant, .parameter: return self
        case .variable(let id):
            if let start = visiting.firstIndex(of: id) { throw ReusableFormulaError.cycle(Array(visiting[start...]) + [id]) }
            guard visiting.count < 64 else { throw ReusableFormulaError.expansionLimit }
            guard let variable = variables.first(where: { $0.id == id }) else { throw ReusableFormulaError.missingVariable(id) }
            return try variable.expression.substitutingVariables(variables, visiting: visiting + [id])
        case .add(let a, let b):
            return .add(try a.substitutingVariables(variables, visiting: visiting), try b.substitutingVariables(variables, visiting: visiting))
        case .call(let id, let arguments):
            return .call(id, arguments: try arguments.mapValues { try $0.substitutingVariables(variables, visiting: visiting) })
        }
    }
    public func remapping(_ ids: [UUID: UUID]) -> FormulaExpression {
        switch self {
        case .constant, .parameter, .variable: self
        case .add(let a, let b): .add(a.remapping(ids), b.remapping(ids))
        case .call(let id, let args): .call(ids[id] ?? id, arguments: args.mapValues { $0.remapping(ids) })
        }
    }
}

extension FormulaValueType {
    public var title: String { switch self { case .number: "Number"; case .length: "Length (pt)"; case .boolean: "Yes / No" } }
    public var zero: FormulaValue { switch self { case .number: .number(0); case .length: .length(0); case .boolean: .boolean(false) } }
}

extension ReusableFormulaLibrary {
    public func evaluate(_ expression: FormulaExpression) throws -> FormulaValue {
        // La firma del nodo radice è dedotta provando i tre tipi ammessi, senza coercizioni.
        for type in [FormulaValueType.number, .length, .boolean] {
            let root = ReusableFormula(name: UUID().uuidString, resultType: type, expression: expression)
            let library = ReusableFormulaLibrary(definitions: definitions + [root])
            if (try? library.validate()) != nil { return try library.evaluate(root.id) }
        }
        // Conserva la diagnosi precisa di riferimenti o cicli; il tipo è l'unico tentativo variabile.
        let root = ReusableFormula(name: UUID().uuidString, resultType: .number, expression: expression)
        return try ReusableFormulaLibrary(definitions: definitions + [root]).evaluate(root.id)
    }
}

extension StyleFormula {
    public var bindingType: FormulaValueType? {
        switch operation.argument {
        case .length, .pageStart: .length
        case .integer: .number
        case .boolean, .hyphenates: .boolean
        default: nil
        }
    }
    public func resolved(in library: ReusableFormulaLibrary, variables: [StyleVariable] = []) throws -> StyleFormula {
        guard let binding else { return self }
        let value = try library.evaluate(binding.substitutingVariables(variables))
        guard value.type == bindingType else { throw ReusableFormulaError.incompatibleTypes }
        let argument: StyleArgument
        switch (operation.argument, value) {
        case (.length, .length(let value)): argument = .length(value, .points)
        case (.pageStart, .length(let value)): argument = .pageStart(.distance(value))
        case (.integer, .number(let value)):
            guard value.isFinite, value.rounded() == value, value >= 0, value <= 99 else { throw ReusableFormulaError.invalidNumber }
            argument = .integer(Int(value))
        case (.boolean, .boolean(let value)): argument = .boolean(value)
        case (.hyphenates, .boolean(let value)): argument = .hyphenates(value)
        default: throw ReusableFormulaError.incompatibleTypes
        }
        var result = self
        result.binding = nil
        result.operation = StylePropertyOperation(operation.predicate, operation.property, argument)
        return result
    }
}

extension StyleSheet {
    public func resolvingReusableStyle(_ style: NamedStyle) throws -> NamedStyle {
        var result = style
        let library = ReusableFormulaLibrary(definitions: reusableFormulas)
        result.formulas = try style.formulas.map {
            let resolved = try $0.resolved(in: library, variables: style.variables)
            try resolved.validate(for: style.target)
            return resolved
        }
        return result
    }
    public func resolvingReusable() throws -> StyleSheet {
        try ReusableFormulaLibrary(definitions: reusableFormulas).validate()
        var result = self
        result.styles = try styles.map(resolvingReusableStyle)
        return result
    }
    public func reusableProblem(_ error: Error) -> String {
        func name(_ id: UUID) -> String { reusableFormulas.first { $0.id == id }?.name ?? "missing definition" }
        switch error {
        case ReusableFormulaError.cycle(let path): return "Circular link: " + path.map(name).joined(separator: " → ")
        case ReusableFormulaError.missingDefinition(let id): return "Formula not found: " + name(id)
        case ReusableFormulaError.missingParameter: return "A referenced parameter was removed."
        case ReusableFormulaError.missingVariable: return "A referenced variable no longer exists in the style."
        case ReusableFormulaError.invalidArguments(let id): return "Complete the arguments of “" + name(id) + "”."
        case ReusableFormulaError.invalidName: return "Give the definitions and their parameters names that are not empty and all different."
        case ReusableFormulaError.expansionLimit: return "The formula exceeds the evaluation limit: reduce the steps or the calls."
        case ReusableFormulaError.invalidNumber: return "The numeric result is not valid."
        default: return "Incompatible types or a value that is not allowed: check the formula links."
        }
    }
}

extension StyleFormula {
    public var bindingSeed: FormulaValue {
        switch operation.argument {
        case .length(let n, let unit): .length(n * unit.points)
        case .integer(let n): .number(Double(n))
        case .boolean(let flag), .hyphenates(let flag): .boolean(flag)
        case .pageStart(.distance(let n)): .length(n)
        default: bindingType?.zero ?? .number(0)
        }
    }
}
extension FormulaExpression {
    public func summary(in definitions: [ReusableFormula], variables: [StyleVariable] = []) -> String {
        switch self {
        case .constant(let value): return value.description
        case .parameter: return "Parameter"
        case .variable(let id): return variables.first { $0.id == id }?.name ?? "Missing variable"
        case .add(let a, let b): return "(" + a.summary(in: definitions, variables: variables) + " + " + b.summary(in: definitions, variables: variables) + ")"
        case .call(let id, let args):
            let definition = definitions.first { $0.id == id }
            return (definition?.name ?? "Missing formula") + "(" + (definition?.parameters ?? []).map { $0.name + ": " + (args[$0.id]?.summary(in: definitions, variables: variables) ?? "mancante") }.joined(separator: ", ") + ")"
        }
    }
}
extension FormulaValue {
    public var description: String {
        switch self { case .number(let n): n.formatted(); case .length(let n): n.formatted() + " pt"; case .boolean(let flag): flag ? "Yes" : "No" }
    }
}
