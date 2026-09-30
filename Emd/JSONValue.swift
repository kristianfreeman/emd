import Foundation

enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    init(any value: Any) {
        if let number = value as? NSNumber {
            self = Self.from(number: number)
            return
        }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let array = value as? [Any] {
            self = .array(array.map(JSONValue.init(any:)))
            return
        }
        if let object = value as? [String: Any] {
            self = .object(object.mapValues(JSONValue.init(any:)))
            return
        }
        self = .null
    }

    private static func from(number: NSNumber) -> JSONValue {
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return .number(number.doubleValue) }
        return .bool(number.boolValue)
    }

    func any() -> Any {
        switch self {
        case .null, .bool, .number, .string:
            return scalar()
        case .array(let value):
            return value.map { $0.any() }
        case .object(let value):
            return value.mapValues { $0.any() }
        }
    }

    private func scalar() -> Any {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .null, .array, .object:
            return NSNull()
        }
    }

    func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: any(), options: [.sortedKeys])
    }

    var boolish: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return Bool(value)
        case .null, .array, .object:
            return nil
        }
    }
}

enum JSONDecoding {
    static func value(from data: Data) throws -> JSONValue {
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(any: parsed)
    }
}
