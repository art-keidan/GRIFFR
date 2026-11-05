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
        case .constant, .parameter: []
        case .add(let a, let b): a.references.union(b.references)
        case .call(let id, let arguments): arguments.values.reduce([id]) { $0.union($1.references) }
        }
    }
    public func remapping(_ ids: [UUID: UUID]) -> FormulaExpression {
        switch self {
        case .constant, .parameter: self
        case .add(let a, let b): .add(a.remapping(ids), b.remapping(ids))
        case .call(let id, let args): .call(ids[id] ?? id, arguments: args.mapValues { $0.remapping(ids) })
        }
    }
}

extension FormulaValueType {
    public var title: String { switch self { case .number: "Numero"; case .length: "Lunghezza (pt)"; case .boolean: "Sì / No" } }
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
    public func resolved(in library: ReusableFormulaLibrary) throws -> StyleFormula {
        guard let binding else { return self }
        let value = try library.evaluate(binding)
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
            let resolved = try $0.resolved(in: library)
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
        func name(_ id: UUID) -> String { reusableFormulas.first { $0.id == id }?.name ?? "definizione assente" }
        switch error {
        case ReusableFormulaError.cycle(let path): return "Collegamento circolare: " + path.map(name).joined(separator: " → ")
        case ReusableFormulaError.missingDefinition(let id): return "Formula non trovata: " + name(id)
        case ReusableFormulaError.missingParameter: return "Un parametro richiamato è stato rimosso."
        case ReusableFormulaError.invalidArguments(let id): return "Completa gli argomenti di «" + name(id) + "»."
        case ReusableFormulaError.invalidName: return "Assegna nomi non vuoti e distinti alle definizioni e ai loro parametri."
        case ReusableFormulaError.expansionLimit: return "La formula supera il limite di valutazione: riduci i passaggi o le chiamate."
        case ReusableFormulaError.invalidNumber: return "Il risultato numerico non è valido."
        default: return "Tipi incompatibili o valore non ammesso: controlla i collegamenti delle formule."
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
    public func summary(in definitions: [ReusableFormula]) -> String {
        switch self {
        case .constant(let value): return value.description
        case .parameter: return "Parametro"
        case .add(let a, let b): return "(" + a.summary(in: definitions) + " + " + b.summary(in: definitions) + ")"
        case .call(let id, let args):
            let definition = definitions.first { $0.id == id }
            return (definition?.name ?? "Formula assente") + "(" + (definition?.parameters ?? []).map { $0.name + ": " + (args[$0.id]?.summary(in: definitions) ?? "mancante") }.joined(separator: ", ") + ")"
        }
    }
}
extension FormulaValue {
    public var description: String {
        switch self { case .number(let n): n.formatted(); case .length(let n): n.formatted() + " pt"; case .boolean(let flag): flag ? "Sì" : "No" }
    }
}
