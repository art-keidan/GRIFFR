import Foundation

/// Valori scambiati dalle prime formule riutilizzabili. Le lunghezze sono espresse in punti.
public enum FormulaValue: Hashable, Sendable, Codable {
    case number(Double)
    case length(Double)
    case boolean(Bool)

    public var type: FormulaValueType {
        switch self {
        case .number: .number
        case .length: .length
        case .boolean: .boolean
        }
    }
}

public enum FormulaValueType: String, Hashable, Sendable, Codable {
    case number, length, boolean
}

public struct FormulaParameter: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var type: FormulaValueType

    public init(id: UUID = UUID(), name: String, type: FormulaValueType) {
        self.id = id
        self.name = name
        self.type = type
    }
}

/// I riferimenti usano identità, così rinominare una definizione o un parametro non li interrompe.
public indirect enum FormulaExpression: Hashable, Sendable, Codable {
    case constant(FormulaValue)
    case parameter(UUID)
    case add(FormulaExpression, FormulaExpression)
    case call(UUID, arguments: [UUID: FormulaExpression])
}

public struct ReusableFormula: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var parameters: [FormulaParameter]
    public var resultType: FormulaValueType
    public var expression: FormulaExpression

    public init(id: UUID = UUID(), name: String, parameters: [FormulaParameter] = [],
                resultType: FormulaValueType, expression: FormulaExpression) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.resultType = resultType
        self.expression = expression
    }
}

public enum ReusableFormulaError: Error, Equatable {
    case invalidName
    case expansionLimit
    case duplicateDefinition(UUID)
    case duplicateParameter(UUID)
    case missingDefinition(UUID)
    case missingParameter(UUID)
    case invalidArguments(UUID)
    case incompatibleTypes
    case invalidNumber
    case cycle([UUID])
}

/// Valida le firme e le chiamate prima della valutazione, comprese quelle annidate.
public struct ReusableFormulaLibrary: Sendable {
    public var definitions: [ReusableFormula]

    public init(definitions: [ReusableFormula] = []) { self.definitions = definitions }

    public func validate() throws {
        var byID: [UUID: ReusableFormula] = [:]
        var names = Set<String>()
        for definition in definitions {
            let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, names.insert(name).inserted else { throw ReusableFormulaError.invalidName }
            let labels = definition.parameters.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !labels.contains(""), Set(labels).count == labels.count else { throw ReusableFormulaError.invalidName }
            guard byID[definition.id] == nil else { throw ReusableFormulaError.duplicateDefinition(definition.id) }
            byID[definition.id] = definition
            var seen = Set<UUID>()
            for parameter in definition.parameters where !seen.insert(parameter.id).inserted {
                throw ReusableFormulaError.duplicateParameter(parameter.id)
            }
        }
        var finished = Set<UUID>()
        var nodes = 0
        func visit(_ id: UUID, path: [UUID]) throws {
            guard path.count < 128 else { throw ReusableFormulaError.expansionLimit }
            if let start = path.firstIndex(of: id) { throw ReusableFormulaError.cycle(Array(path[start...]) + [id]) }
            if finished.contains(id) { return }
            guard let definition = byID[id] else { throw ReusableFormulaError.missingDefinition(id) }
            let parameters = Dictionary(uniqueKeysWithValues: definition.parameters.map { ($0.id, $0.type) })
            func type(of expression: FormulaExpression) throws -> FormulaValueType {
                nodes += 1
                guard nodes < 10000 else { throw ReusableFormulaError.expansionLimit }
                switch expression {
                case .constant(let value):
                    switch value { case .number(let n), .length(let n): guard n.isFinite else { throw ReusableFormulaError.invalidNumber }; case .boolean: break }
                    return value.type
                case .parameter(let parameter):
                    guard let result = parameters[parameter] else { throw ReusableFormulaError.missingParameter(parameter) }
                    return result
                case .add(let lhs, let rhs):
                    let a = try type(of: lhs), b = try type(of: rhs)
                    guard a == b, a != .boolean else { throw ReusableFormulaError.incompatibleTypes }
                    return a
                case .call(let target, let arguments):
                    guard let callee = byID[target] else { throw ReusableFormulaError.missingDefinition(target) }
                    guard Set(arguments.keys) == Set(callee.parameters.map(\.id)) else { throw ReusableFormulaError.invalidArguments(target) }
                    for parameter in callee.parameters {
                        guard let argument = arguments[parameter.id], try type(of: argument) == parameter.type else { throw ReusableFormulaError.incompatibleTypes }
                    }
                    try visit(target, path: path + [id])
                    return callee.resultType
                }
            }
            guard try type(of: definition.expression) == definition.resultType else { throw ReusableFormulaError.incompatibleTypes }
            finished.insert(id)
        }
        for definition in definitions { try visit(definition.id, path: []) }
    }

    public func evaluate(_ id: UUID, arguments: [UUID: FormulaValue] = [:]) throws -> FormulaValue {
        try validate()
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        var steps = 0
        func invoke(_ id: UUID, _ arguments: [UUID: FormulaValue]) throws -> FormulaValue {
            guard let definition = byID[id] else { throw ReusableFormulaError.missingDefinition(id) }
            guard Set(arguments.keys) == Set(definition.parameters.map(\.id)) else { throw ReusableFormulaError.invalidArguments(id) }
            for parameter in definition.parameters where arguments[parameter.id]?.type != parameter.type { throw ReusableFormulaError.incompatibleTypes }
            func value(_ expression: FormulaExpression) throws -> FormulaValue {
                steps += 1
                guard steps < 10000 else { throw ReusableFormulaError.expansionLimit }
                switch expression {
                case .constant(let result): return result
                case .parameter(let id):
                    guard let result = arguments[id] else { throw ReusableFormulaError.missingParameter(id) }
                    return result
                case .add(let lhs, let rhs):
                    let a = try value(lhs), b = try value(rhs)
                    switch (a, b) {
                    case (.number(let x), .number(let y)) where (x + y).isFinite: return .number(x + y)
                    case (.length(let x), .length(let y)) where (x + y).isFinite: return .length(x + y)
                    case (.number, .number), (.length, .length): throw ReusableFormulaError.invalidNumber
                    default: throw ReusableFormulaError.incompatibleTypes
                    }
                case .call(let id, let bindings):
                    return try invoke(id, bindings.mapValues { try value($0) })
                }
            }
            let result = try value(definition.expression)
            guard result.type == definition.resultType else { throw ReusableFormulaError.incompatibleTypes }
            return result
        }
        for value in arguments.values {
            switch value { case .number(let n), .length(let n): guard n.isFinite else { throw ReusableFormulaError.invalidNumber }; case .boolean: break }
        }
        return try invoke(id, arguments)
    }
}
