import Foundation

indirect enum SyncJSON: Codable, Sendable, Equatable {
    case object([String: SyncJSON]), array([SyncJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: SyncJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([SyncJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var object: [String: SyncJSON] { if case .object(let v) = self { return v }; return [:] }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    func replacing(_ key: String, with value: String) -> SyncJSON {
        var v = object; v[key] = .string(value); return .object(v)
    }
}

struct SyncRecord: Codable, Sendable, Equatable {
    var kind: String
    var id: String
    var clock: Int64
    var deviceID: String
    var deleted: Bool
    var payload: SyncJSON?
    var changedFields: [String]?
    var seq: Int64?
}
struct SyncAcknowledgement: Codable, Sendable {
    var kind: String; var id: String; var clock: Int64; var deviceID: String
}
struct SyncRequest: Codable, Sendable {
    var protocolVersion = 1
    var deviceID: String
    var cursor: Int64
    var changes: [SyncRecord]
}
struct SyncResponse: Codable, Sendable {
    var protocolVersion: Int
    var cursor: Int64
    var hasMore: Bool
    var changes: [SyncRecord]
    var acknowledged: [SyncAcknowledgement]
    var aliases: [String: String]
}
struct SyncDirection: Codable, Sendable {
    var entryID: UUID
    var state: ReviewDirectionState
}

enum SyncCodec {
    static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        value.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer(); try c.encode(DateCodec.shared.format(date))
        }
        return value
    }
    static func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            guard let date = DateCodec.shared.parse(try c.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid sync date")
            }
            return date
        }
        return value
    }
    static func json<T: Encodable>(_ value: T) throws -> SyncJSON {
        try decoder().decode(SyncJSON.self, from: encoder().encode(value))
    }
    static func model<T: Decodable>(_ type: T.Type, from json: SyncJSON) throws -> T {
        try decoder().decode(type, from: encoder().encode(json))
    }
    static func text(_ json: SyncJSON) throws -> String {
        String(decoding: try encoder().encode(json), as: UTF8.self)
    }
}
