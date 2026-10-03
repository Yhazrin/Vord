import Foundation
import SQLite3

final class AppDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.vord.sqlite")
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteError.message(message)
        }
        db = handle
        try sync { database in
            try self.exec(database, "PRAGMA journal_mode = WAL;")
            try self.exec(database, "PRAGMA foreign_keys = ON;")
            try self.exec(database, "PRAGMA synchronous = NORMAL;")
            try self.exec(database, Schema.v1)
            try self.exec(
                database,
                "INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', '\(Schema.currentVersion)');"
            )
            try SyncSchema.install(in: self, db: database)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func perform<T>(_ body: @escaping (OpaquePointer) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let db = self.db else {
                        throw SQLiteError.message("Database is closed")
                    }
                    try self.exec(db, "BEGIN IMMEDIATE")
                    do {
                        let value = try body(db)
                        try self.exec(db, "COMMIT")
                        continuation.resume(returning: value)
                    } catch {
                        try? self.exec(db, "ROLLBACK")
                        throw error
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func query(_ database: OpaquePointer, _ sql: String, _ bindings: [SQLValue] = []) throws -> [[String: SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.message(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, bindings)
        var rows: [[String: SQLValue]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            if code != SQLITE_ROW {
                throw SQLiteError.message(String(cString: sqlite3_errmsg(database)))
            }
            var row: [String: SQLValue] = [:]
            let count = sqlite3_column_count(statement)
            for index in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(statement, index)
            }
            rows.append(row)
        }
        return rows
    }

    func exec(_ database: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(database, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteError.message(String(cString: sqlite3_errmsg(database)))
        }
    }

    func run(_ database: OpaquePointer, _ sql: String, _ bindings: [SQLValue]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.message(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, bindings)
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            throw SQLiteError.message(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func sync<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var result: Result<T, Error>!
        queue.sync {
            result = Result {
                guard let db else { throw SQLiteError.message("Database is closed") }
                return try body(db)
            }
        }
        return try result.get()
    }

    private func bind(_ statement: OpaquePointer, _ bindings: [SQLValue]) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch binding {
            case .null:
                code = sqlite3_bind_null(statement, index)
            case .integer(let value):
                code = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                code = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                code = sqlite3_bind_text(statement, index, value, -1, transient)
            }
            if code != SQLITE_OK {
                throw SQLiteError.message("Unable to bind SQL value")
            }
        }
    }

    private func value(_ statement: OpaquePointer, _ index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        default:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        }
    }
}

extension [String: SQLValue] {
    func text(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        if case .text(let text) = value { return text }
        if case .integer(let number) = value { return String(number) }
        if case .double(let number) = value { return String(number) }
        return nil
    }

    func integer(_ key: String) -> Int {
        guard let value = self[key] else { return 0 }
        if case .integer(let number) = value { return Int(number) }
        if case .double(let number) = value { return Int(number) }
        if case .text(let text) = value { return Int(text) ?? 0 }
        return 0
    }

    func double(_ key: String) -> Double {
        guard let value = self[key] else { return 0 }
        if case .double(let number) = value { return number }
        if case .integer(let number) = value { return Double(number) }
        if case .text(let text) = value { return Double(text) ?? 0 }
        return 0
    }

    func date(_ key: String) -> Date? {
        guard let text = text(key) else { return nil }
        return DateCodec.shared.parse(text)
    }
}
