import Foundation

final class SyncStore: @unchecked Sendable {
    let database: AppDatabase
    private let repository: SQLiteVocabularyRepository
    static let entryFields = ["english", "chinese", "lemma", "phonetic", "partOfSpeech", "englishDefinition", "chineseDefinition", "exampleSentence", "sourceSentence", "source", "tags", "createdAt", "updatedAt", "archived"]

    init(database: AppDatabase) {
        self.database = database
        repository = SQLiteVocabularyRepository(database: database, onChange: {})
    }

    func prepare(account: String) async throws {
        try await database.perform { db in
            let old = try self.meta(db, "sync.account")
            if !old.isEmpty, old != account {
                try self.database.exec(db, "DELETE FROM sync_outbox; DELETE FROM sync_baselines; DELETE FROM sync_tombstones;")
                try self.setMeta(db, "sync.cursor", "0")
                try SyncSchema.bootstrap(in: self.database, db: db)
            }
            try self.setMeta(db, "sync.account", account)
        }
    }

    func request(limit: Int = 200) async throws -> SyncRequest {
        var request = try await database.perform { db in
            SyncRequest(deviceID: try self.meta(db, "sync.device"),
                        cursor: Int64(try self.meta(db, "sync.cursor")) ?? 0,
                        changes: Array(try self.pending(db).prefix(min(200, limit))))
        }
        while request.changes.count > 1 {
            if try SyncCodec.encoder().encode(request).count <= 4 * 1024 * 1024 { break }
            request.changes.removeLast()
        }
        return request
    }

    func pendingRevision() async throws -> Int64 {
        try await database.perform { db in
            Int64(try self.database.query(db, "SELECT COALESCE(MAX(clock),0) AS revision FROM sync_outbox").first?.integer("revision") ?? 0)
        }
    }

    func recoverFromRestoredServer() async throws {
        try await database.perform { db in
            try self.setMeta(db, "sync.cursor", "0")
            try self.database.exec(db, "DELETE FROM sync_baselines")
            try SyncSchema.bootstrap(in: self.database, db: db)
            for row in try self.database.query(db, "SELECT entry_id FROM sync_tombstones") {
                guard let id = row.text("entry_id") else { continue }
                try self.database.exec(db, "UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='sync.clock'")
                try self.database.run(db, """
                INSERT OR REPLACE INTO sync_outbox(kind,record_id,clock,device_id,deleted)
                VALUES ('entry',?,(SELECT CAST(value AS INTEGER) FROM meta WHERE key='sync.clock'),
                  (SELECT value FROM meta WHERE key='sync.device'),1)
                """, [.text(id)])
            }
        }
    }

    func apply(_ response: SyncResponse, sent: SyncRequest) async throws {
        guard response.protocolVersion == 1, response.cursor >= sent.cursor,
              response.changes.allSatisfy({ $0.clock > 0 && ($0.seq ?? 0) > sent.cursor && ($0.seq ?? 0) <= response.cursor }) else {
            throw SQLiteError.message("The sync server returned an invalid revision.")
        }
        try await database.perform { db in
            guard (Int64(try self.meta(db, "sync.cursor")) ?? 0) == sent.cursor else {
                throw SQLiteError.message("The sync cursor changed during this request.")
            }
            try self.setMeta(db, "sync.applying", "1")
            for ack in response.acknowledged {
                guard sent.changes.contains(where: { $0.kind == ack.kind && $0.id == ack.id && $0.clock == ack.clock && $0.deviceID == ack.deviceID }) else {
                    throw SQLiteError.message("The sync server acknowledged an unknown change.")
                }
                try self.database.run(db, "DELETE FROM sync_outbox WHERE kind=? AND record_id=? AND clock=? AND device_id=?",
                    [.text(ack.kind), .text(ack.id), .integer(ack.clock), .text(ack.deviceID)])
                if let captured = sent.changes.first(where: { $0.kind == "entry" && $0.id == ack.id && $0.clock == ack.clock && !$0.deleted }) {
                    // Only edits made after this captured payload remain local. An empty first-upload
                    // baseline would otherwise re-send every field and erase another device's tags.
                    try self.saveBaseline(db, captured)
                }
            }
            let pending = try self.pending(db)
            for (from, _) in response.aliases.sorted(by: { $0.key < $1.key }) {
                let to = try Self.canonical(from, aliases: response.aliases)
                if from != to { try self.alias(db, from: from, to: to) }
            }
            var local: [String: SyncRecord] = [:]
            for var record in pending {
                record = try Self.remap(record, aliases: response.aliases)
                let key = Self.key(record)
                if let previous = local[key], Self.newer(previous, than: record) { continue }
                local[key] = record
            }
            for record in response.changes.sorted(by: { ($0.seq ?? 0) < ($1.seq ?? 0) }) {
                let record = try Self.remap(record, aliases: response.aliases)
                let pending = local[Self.key(record)]
                try self.applyRecord(db, record, pending: pending)
                if record.kind == "entry", record.deleted {
                    local = local.filter { _, value in value.id != record.id && !value.id.hasPrefix(record.id + "/") && value.payload?.object["entryID"]?.string != record.id }
                }
                let clock = max(Int64(try self.meta(db, "sync.clock")) ?? 0, record.clock)
                try self.setMeta(db, "sync.clock", String(clock))
            }
            try self.setMeta(db, "sync.cursor", String(response.cursor))
            try self.setMeta(db, "sync.applying", "0")
        }
    }

    private func pending(_ db: OpaquePointer) throws -> [SyncRecord] {
        let rows = try database.query(db, "SELECT * FROM sync_outbox ORDER BY CASE kind WHEN 'entry' THEN 0 WHEN 'direction' THEN 1 ELSE 2 END, clock, record_id")
        return try rows.compactMap { row in
            guard let kind = row.text("kind"), let id = row.text("record_id"), let device = row.text("device_id") else { return nil }
            let deleted = row.integer("deleted") != 0
            let payload = deleted ? nil : try self.payload(db, kind: kind, id: id)
            if !deleted && payload == nil {
                // The parent may have been deleted after this direction/log was queued.
                try database.run(db, "DELETE FROM sync_outbox WHERE kind=? AND record_id=?", [.text(kind), .text(id)])
                return nil
            }
            var fields: [String]?
            if kind == "entry", !deleted, let payload {
                let baseline = try self.baseline(db, kind: kind, id: id)?.object
                fields = Self.entryFields.filter { baseline == nil || (payload.object[$0] ?? .null) != (baseline?[$0] ?? .null) }
            }
            return SyncRecord(kind: kind, id: id, clock: Int64(row.integer("clock")), deviceID: device,
                              deleted: deleted, payload: payload, changedFields: fields)
        }
    }

    private func payload(_ db: OpaquePointer, kind: String, id: String) throws -> SyncJSON? {
        switch kind {
        case "entry":
            guard let uuid = UUID(uuidString: id), let entry = try repository.loadEntry(db, uuid) else { return nil }
            var value = try SyncCodec.json(entry).object
            for key in Self.entryFields where value[key] == nil { value[key] = .null }
            return .object(value)
        case "direction":
            let parts = id.split(separator: "/")
            guard parts.count == 2, let uuid = UUID(uuidString: String(parts[0])),
                  let direction = ReviewDirection(rawValue: String(parts[1])),
                  let state = try repository.loadState(db, uuid)?.state(for: direction) else { return nil }
            return try SyncCodec.json(SyncDirection(entryID: uuid, state: state))
        case "log":
            guard let row = try database.query(db, "SELECT * FROM review_logs WHERE id=?", [.text(id)]).first,
                  let log = SQLiteVocabularyRepository.log(from: row) else { return nil }
            return try SyncCodec.json(log)
        default: throw SQLiteError.message("Unknown queued sync record.")
        }
    }

    private func applyRecord(_ db: OpaquePointer, _ record: SyncRecord, pending: SyncRecord?) throws {
        switch record.kind {
        case "entry":
            guard let uuid = UUID(uuidString: record.id) else { throw SQLiteError.message("Invalid synced word ID.") }
            if record.deleted {
                try database.run(db, "INSERT OR IGNORE INTO sync_tombstones(entry_id) VALUES (?)", [.text(record.id)])
                // Clear dependent logs before their parent disappears through the FK cascade.
                try database.run(db, "DELETE FROM sync_outbox WHERE kind='log' AND record_id IN (SELECT id FROM review_logs WHERE entry_id=?)", [.text(record.id)])
                try database.run(db, "DELETE FROM sync_outbox WHERE (kind='entry' AND record_id=?) OR (kind='direction' AND record_id LIKE ?)", [.text(record.id), .text(record.id + "/%")])
                try repository.deleteRow(db, uuid)
                try saveBaseline(db, record)
                return
            }
            if try isDeleted(db, record.id) || pending?.deleted == true { return }
            guard let remote = record.payload else { throw SQLiteError.message("Missing synced word.") }
            var value = remote.object
            if let pending, let local = pending.payload {
                for field in pending.changedFields ?? Self.entryFields { value[field] = local.object[field] ?? .null }
            }
            value["id"] = .string(record.id)
            let entry = try SyncCodec.model(VocabularyEntry.self, from: .object(value))
            guard !entry.headword.isEmpty else { throw SQLiteError.message("The synced word is empty.") }
            if try repository.loadEntry(db, uuid) != nil { try repository.writeEntry(db, entry) }
            else { try repository.insertEntry(db, entry) }
            try saveBaseline(db, record)
        case "direction":
            guard !record.deleted, let payload = record.payload else { return }
            let value = try SyncCodec.model(SyncDirection.self, from: payload)
            guard record.id == value.entryID.uuidString + "/" + value.state.direction.rawValue else { throw SQLiteError.message("Invalid sync direction ID.") }
            guard try !isDeleted(db, value.entryID.uuidString), try repository.loadEntry(db, value.entryID) != nil else { return }
            if pending == nil {
                let insert = try repository.loadState(db, value.entryID)?.state(for: value.state.direction) == nil
                try repository.writeDirection(db, entryID: value.entryID, state: value.state, insert: insert)
            }
            try saveBaseline(db, record)
        case "log":
            guard !record.deleted, let payload = record.payload else { return }
            let value = try SyncCodec.model(ReviewLog.self, from: payload)
            guard record.id == value.id.uuidString else { throw SQLiteError.message("Invalid synced review ID.") }
            guard try !isDeleted(db, value.entryID.uuidString), try repository.loadEntry(db, value.entryID) != nil else { return }
            if try database.query(db, "SELECT id FROM review_logs WHERE id=?", [.text(record.id)]).isEmpty { try repository.insertLog(db, value) }
            try saveBaseline(db, record)
        default: throw SQLiteError.message("Unsupported sync record type.")
        }
    }

    private func alias(_ db: OpaquePointer, from: String, to: String) throws {
        guard let oldID = UUID(uuidString: from), let newID = UUID(uuidString: to) else { throw SQLiteError.message("Invalid sync alias.") }
        guard var entry = try repository.loadEntry(db, oldID) else { return }
        if try repository.loadEntry(db, newID) == nil {
            entry.id = newID
            try repository.insertEntry(db, entry)
        }
        for state in try repository.loadState(db, oldID)?.directions ?? [] {
            if try repository.loadState(db, newID)?.state(for: state.direction) == nil {
                try repository.writeDirection(db, entryID: newID, state: state, insert: true)
            }
        }
        try database.run(db, "UPDATE review_logs SET entry_id=? WHERE entry_id=?", [.text(to), .text(from)])
        for row in try database.query(db, "SELECT * FROM sync_outbox WHERE (kind='entry' AND record_id=?) OR (kind='direction' AND record_id LIKE ?)", [.text(from), .text(from + "/%")]) {
            guard let id = row.text("record_id"), let kind = row.text("kind"), let device = row.text("device_id") else { continue }
            let target = id.replacingOccurrences(of: from, with: to)
            try database.run(db, """
            INSERT INTO sync_outbox(kind,record_id,clock,device_id,deleted) VALUES (?,?,?,?,?)
            ON CONFLICT(kind,record_id) DO UPDATE SET clock=excluded.clock,device_id=excluded.device_id,deleted=excluded.deleted
            WHERE excluded.clock > sync_outbox.clock OR (excluded.clock=sync_outbox.clock AND excluded.device_id>sync_outbox.device_id)
            """, [.text(kind), .text(target), .integer(Int64(row.integer("clock"))), .text(device), .integer(Int64(row.integer("deleted")))])
        }
        try database.run(db, "DELETE FROM sync_outbox WHERE (kind='entry' AND record_id=?) OR (kind='direction' AND record_id LIKE ?)", [.text(from), .text(from + "/%")])
        if let old = try baseline(db, kind: "entry", id: from) {
            try database.run(db, "INSERT OR IGNORE INTO sync_baselines(kind,record_id,payload) VALUES ('entry',?,?)", [.text(to), .text(try SyncCodec.text(old.replacing("id", with: to)))])
        }
        try database.run(db, "DELETE FROM sync_baselines WHERE (kind='entry' AND record_id=?) OR (kind='direction' AND record_id LIKE ?)", [.text(from), .text(from + "/%")])
        if try isDeleted(db, from) { try database.run(db, "INSERT OR IGNORE INTO sync_tombstones(entry_id) VALUES (?)", [.text(to)]) }
        try repository.deleteRow(db, oldID)
    }

    private func isDeleted(_ db: OpaquePointer, _ id: String) throws -> Bool {
        try !database.query(db, "SELECT entry_id FROM sync_tombstones WHERE entry_id=?", [.text(id)]).isEmpty
    }
    private func baseline(_ db: OpaquePointer, kind: String, id: String) throws -> SyncJSON? {
        guard let text = try database.query(db, "SELECT payload FROM sync_baselines WHERE kind=? AND record_id=?", [.text(kind), .text(id)]).first?.text("payload") else { return nil }
        return try SyncCodec.decoder().decode(SyncJSON.self, from: Data(text.utf8))
    }
    private func saveBaseline(_ db: OpaquePointer, _ record: SyncRecord) throws {
        try database.run(db, "INSERT OR REPLACE INTO sync_baselines(kind,record_id,payload) VALUES (?,?,?)", [.text(record.kind), .text(record.id), try record.payload.map { .text(try SyncCodec.text($0)) } ?? .null])
    }
    private func meta(_ db: OpaquePointer, _ key: String) throws -> String {
        try database.query(db, "SELECT value FROM meta WHERE key=?", [.text(key)]).first?.text("value") ?? ""
    }
    private func setMeta(_ db: OpaquePointer, _ key: String, _ value: String) throws {
        try database.run(db, "INSERT OR REPLACE INTO meta(key,value) VALUES (?,?)", [.text(key), .text(value)])
    }
    private static func key(_ record: SyncRecord) -> String { record.kind + ":" + record.id }
    private static func newer(_ lhs: SyncRecord, than rhs: SyncRecord) -> Bool {
        lhs.clock > rhs.clock || (lhs.clock == rhs.clock && lhs.deviceID > rhs.deviceID)
    }
    private static func canonical(_ id: String, aliases: [String: String]) throws -> String {
        var id = id; var visited = Set<String>()
        while let next = aliases[id] {
            guard visited.insert(id).inserted else { throw SQLiteError.message("The sync server returned cyclic aliases.") }
            id = next
        }
        return id
    }
    private static func remap(_ record: SyncRecord, aliases: [String: String]) throws -> SyncRecord {
        var record = record
        if record.kind == "entry" {
            record.id = try canonical(record.id, aliases: aliases)
            record.payload = record.payload?.replacing("id", with: record.id)
        } else if record.kind == "direction" {
            let parts = record.id.split(separator: "/")
            guard parts.count == 2 else { throw SQLiteError.message("Invalid direction ID.") }
            let id = try canonical(String(parts[0]), aliases: aliases)
            record.id = id + "/" + parts[1]
            record.payload = record.payload?.replacing("entryID", with: id)
        } else if record.kind == "log", let id = record.payload?.object["entryID"]?.string {
            record.payload = record.payload?.replacing("entryID", with: try canonical(id, aliases: aliases))
        }
        return record
    }
}
