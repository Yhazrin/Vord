import Foundation

final class SQLiteVocabularyRepository: VocabularyRepository, @unchecked Sendable {
    private let database: AppDatabase
    private let onChange: @Sendable () -> Void

    init(database: AppDatabase, onChange: @escaping @Sendable () -> Void = notifyLibraryChange) {
        self.database = database
        self.onChange = onChange
    }

    func todaySummary(now: Date) async throws -> TodaySummary {
        let bounds = DayBounds.range(for: now)
        return try await database.perform { db in
            let due = try self.database.query(
                db,
                """
                SELECT COUNT(DISTINCT e.id) AS count
                FROM vocabulary_entries e
                JOIN review_direction_states r ON r.entry_id = e.id
                WHERE e.archived = 0 AND TRIM(e.english) != '' AND TRIM(e.chinese) != '' AND r.due_at <= ?
                """,
                [.text(DateCodec.shared.format(now))]
            )
            let added = try self.database.query(
                db,
                """
                SELECT COUNT(*) AS count FROM vocabulary_entries
                WHERE created_at >= ? AND created_at < ?
                """,
                [.text(DateCodec.shared.format(bounds.start)), .text(DateCodec.shared.format(bounds.end))]
            )
            let reviewed = try self.database.query(
                db,
                """
                SELECT COUNT(*) AS count FROM review_logs
                WHERE reviewed_at >= ? AND reviewed_at < ?
                """,
                [.text(DateCodec.shared.format(bounds.start)), .text(DateCodec.shared.format(bounds.end))]
            )
            return TodaySummary(
                dueCount: due.first?.integer("count") ?? 0,
                addedToday: added.first?.integer("count") ?? 0,
                reviewedToday: reviewed.first?.integer("count") ?? 0
            )
        }
    }

    func recentEntries(limit: Int) async throws -> [VocabularyEntry] {
        try await database.perform { db in
            let rows = try self.database.query(
                db,
                """
                SELECT * FROM vocabulary_entries
                WHERE archived = 0
                ORDER BY created_at DESC
                LIMIT ?
                """,
                [.integer(Int64(limit))]
            )
            return rows.compactMap(Self.entry(from:))
        }
    }

    func dueCards(now: Date, limit: Int) async throws -> [ReviewCard] {
        return try await database.perform { db in
            let rows = try self.database.query(
                db,
                """
                SELECT
                  e.id AS entry_id,
                  e.english, e.chinese, e.lemma, e.phonetic, e.part_of_speech,
                  e.english_definition, e.chinese_definition, e.example_sentence,
                  e.source_sentence, e.source, e.tags_json, e.created_at, e.updated_at, e.archived,
                  r.direction, r.due_at, r.last_reviewed_at, r.stage, r.interval_seconds,
                  r.difficulty, r.stability, r.review_count, r.lapse_count, r.correct_count, r.incorrect_count
                FROM review_direction_states r
                JOIN vocabulary_entries e ON e.id = r.entry_id
                WHERE e.archived = 0 AND TRIM(e.english) != '' AND TRIM(e.chinese) != '' AND r.due_at <= ?
                ORDER BY r.due_at ASC
                LIMIT ?
                """,
                [.text(DateCodec.shared.format(now)), .integer(Int64(limit))]
            )
            return rows.compactMap(Self.card(from:))
        }
    }

    func activeEntries() async throws -> [VocabularyEntry] {
        try await database.perform { db in
            let rows = try self.database.query(
                db,
                """
                SELECT * FROM vocabulary_entries
                WHERE archived = 0
                ORDER BY created_at DESC
                """
            )
            return rows.compactMap(Self.entry(from:))
        }
    }

    func libraryRows() async throws -> [LibraryRow] {
        try await database.perform { db in
            let rows = try self.database.query(
                db,
                """
                SELECT e.id, e.english, e.chinese, e.lemma, e.tags_json, e.created_at, e.archived,
                       MIN(r.due_at) AS next_due
                FROM vocabulary_entries e
                LEFT JOIN review_direction_states r ON r.entry_id = e.id
                GROUP BY e.id
                """
            )
            return rows.compactMap { row in
                guard let id = row.text("id").flatMap(UUID.init(uuidString:)),
                      let created = row.date("created_at") else { return nil }
                return LibraryRow(
                    id: id,
                    english: row.text("english") ?? "",
                    chinese: row.text("chinese") ?? "",
                    lemma: row.text("lemma"),
                    tags: Self.tags(from: row.text("tags_json")),
                    createdAt: created,
                    nextDueAt: row.date("next_due"),
                    archived: row.integer("archived") != 0
                )
            }
        }
    }

    func entry(id: UUID) async throws -> VocabularyEntry? {
        try await database.perform { db in
            try self.loadEntry(db, id)
        }
    }

    func reviewState(entryID: UUID) async throws -> ReviewState? {
        try await database.perform { db in
            try self.loadState(db, entryID)
        }
    }

    func upsert(_ draft: EntryDraft, now: Date) async throws -> VocabularyEntry {
        let entry = try await database.perform { db -> VocabularyEntry in
            if let existingID = draft.existingID {
                guard var current = try self.loadEntry(db, existingID) else { throw SQLiteError.message("This word no longer exists.") }
                current = self.merging(current, with: draft, now: now)
                if let winner = try self.collidingEntry(db, english: current.english, excluding: current.id) {
                    var merged = self.merging(winner, with: draft, now: now)
                    if !current.chinese.trimmed.isEmpty {
                        merged.chinese = current.chinese.trimmed
                    }
                    try self.writeEntry(db, merged)
                    try self.deleteRow(db, current.id)
                    return merged
                }
                try self.writeEntry(db, current)
                return current
            }

            if let existing = try self.collidingEntry(db, english: draft.english, excluding: nil) {
                let merged = self.merging(existing, with: draft, now: now)
                try self.writeEntry(db, merged)
                return merged
            }

            let entry = VocabularyEntry(
                id: UUID(),
                english: draft.english.trimmed,
                chinese: draft.chinese.trimmed,
                lemma: draft.lemma ?? Self.lemma(from: draft.english),
                phonetic: draft.phonetic,
                partOfSpeech: draft.partOfSpeech,
                englishDefinition: draft.englishDefinition,
                chineseDefinition: draft.chineseDefinition,
                exampleSentence: draft.exampleSentence,
                sourceSentence: draft.sourceSentence,
                source: draft.source,
                tags: draft.tags,
                createdAt: now,
                updatedAt: now,
                archived: false
            )
            try self.insertEntry(db, entry)
            try self.insertState(db, .initial(entryID: entry.id, now: now))
            return entry
        }
        onChange()
        return entry
    }

    /// Checking and inserting share one database transaction so concurrent captures cannot overwrite a learner's entry.
    func insertIfAbsent(_ draft: EntryDraft, now: Date) async throws -> VocabularyEntry? {
        let entry = try await database.perform { db -> VocabularyEntry? in
            if try self.collidingEntry(db, english: draft.english, excluding: nil) != nil { return nil }
            let entry = VocabularyEntry(id: UUID(), english: draft.english.trimmed, chinese: draft.chinese.trimmed,
                lemma: draft.lemma ?? Self.lemma(from: draft.english), phonetic: draft.phonetic,
                partOfSpeech: draft.partOfSpeech, englishDefinition: draft.englishDefinition,
                chineseDefinition: draft.chineseDefinition, exampleSentence: draft.exampleSentence,
                sourceSentence: draft.sourceSentence, source: draft.source, tags: draft.tags,
                createdAt: now, updatedAt: now, archived: false)
            try self.insertEntry(db, entry)
            try self.insertState(db, .initial(entryID: entry.id, now: now))
            return entry
        }
        if entry != nil { onChange() }
        return entry
    }

    func update(_ entry: VocabularyEntry) async throws {
        guard !entry.english.trimmed.isEmpty || !entry.chinese.trimmed.isEmpty else {
            throw SQLiteError.message("A word or meaning is required.")
        }
        try await database.perform { db in
            guard try self.loadEntry(db, entry.id) != nil else { throw SQLiteError.message("This word no longer exists.") }
            if try self.collidingEntry(db, english: entry.english, excluding: entry.id) != nil {
                throw SQLiteError.message("This English word already exists. Edit its existing entry instead.")
            }
            try self.writeEntry(db, entry)
        }
        onChange()
    }

    func setArchived(id: UUID, archived: Bool, now: Date) async throws {
        try await database.perform { db in
            try self.database.run(
                db,
                "UPDATE vocabulary_entries SET archived = ?, updated_at = ? WHERE id = ?",
                [.integer(archived ? 1 : 0), .text(DateCodec.shared.format(now)), .text(id.uuidString)]
            )
        }
        onChange()
    }

    func delete(id: UUID) async throws {
        try await database.perform { db in
            try self.deleteRow(db, id)
        }
        onChange()
    }

    func recordReview(_ result: ReviewScheduleResult) async throws {
        try await database.perform { db in
            guard let directionState = result.state.directions.first(where: { $0.direction == result.log.direction }) else {
                return
            }
            try self.writeDirection(db, entryID: result.state.entryID, state: directionState)
            try self.insertLog(db, result.log)
        }
        onChange()
    }

    func importSnapshot(_ snapshot: LibraryExport) async throws -> Int {
        guard snapshot.schemaVersion == Schema.currentVersion else { throw SQLiteError.message("Unsupported library backup version.") }
        guard snapshot.entries.count <= 100_000,
              Set(snapshot.entries.map(\.id)).count == snapshot.entries.count,
              Set(snapshot.reviewStates.map(\.entryID)).count == snapshot.reviewStates.count,
              Set(snapshot.reviewLogs.map(\.id)).count == snapshot.reviewLogs.count else {
            throw SQLiteError.message("Backup is too large or contains duplicate IDs.")
        }
        let ids = Set(snapshot.entries.map(\.id))
        guard snapshot.reviewStates.allSatisfy({ state in
            ids.contains(state.entryID) && Set(state.directions.map(\.direction)).count == state.directions.count &&
            state.directions.allSatisfy { $0.interval >= 0 && $0.stability >= 0 && (1...10).contains($0.difficulty) && $0.reviewCount >= 0 }
        }), snapshot.reviewLogs.allSatisfy({ ids.contains($0.entryID) && $0.interval >= 0 }) else {
            throw SQLiteError.message("Backup contains invalid review states or orphaned logs.")
        }
        let count = try await database.perform { db in
            var imported = Set<UUID>()
            for entry in snapshot.entries {
                guard !entry.english.trimmed.isEmpty || !entry.chinese.trimmed.isEmpty else { throw SQLiteError.message("Backup contains an empty word.") }
                if try self.loadEntry(db, entry.id) != nil || self.collidingEntry(db, english: entry.english, excluding: nil) != nil { continue }
                try self.insertEntry(db, entry)
                var state = snapshot.reviewStates.first { $0.entryID == entry.id } ?? .initial(entryID: entry.id, now: Date())
                for direction in ReviewDirection.allCases where state.state(for: direction) == nil {
                    state.directions.append(.initial(direction: direction, now: Date()))
                }
                try self.insertState(db, state)
                imported.insert(entry.id)
            }
            for log in snapshot.reviewLogs where imported.contains(log.entryID) {
                // A log ID may already exist for another word; skip it without touching existing history.
                let exists = try self.database.query(db, "SELECT id FROM review_logs WHERE id = ?", [.text(log.id.uuidString)])
                if exists.isEmpty { try self.insertLog(db, log) }
            }
            return imported.count
        }
        onChange()
        return count
    }

    func exportSnapshot() async throws -> LibraryExport {
        try await database.perform { db in
            let entries = try self.database.query(db, "SELECT * FROM vocabulary_entries ORDER BY created_at ASC")
                .compactMap(Self.entry(from:))
            var states: [ReviewState] = []
            for entry in entries {
                if let state = try self.loadState(db, entry.id) {
                    states.append(state)
                }
            }
            let logs = try self.database.query(db, "SELECT * FROM review_logs ORDER BY reviewed_at ASC")
                .compactMap(Self.log(from:))
            return LibraryExport(
                schemaVersion: Schema.currentVersion,
                entries: entries,
                reviewStates: states,
                reviewLogs: logs
            )
        }
    }

    func loadEntry(_ db: OpaquePointer, _ id: UUID) throws -> VocabularyEntry? {
        let rows = try database.query(db, "SELECT * FROM vocabulary_entries WHERE id = ? LIMIT 1", [.text(id.uuidString)])
        return rows.first.flatMap(Self.entry(from:))
    }

    func loadState(_ db: OpaquePointer, _ id: UUID) throws -> ReviewState? {
        let rows = try database.query(
            db,
            "SELECT * FROM review_direction_states WHERE entry_id = ? ORDER BY direction ASC",
            [.text(id.uuidString)]
        )
        let directions = rows.compactMap(Self.directionState(from:))
        guard !directions.isEmpty else { return nil }
        return ReviewState(entryID: id, directions: directions)
    }

    func collidingEntry(_ db: OpaquePointer, english: String, excluding: UUID?) throws -> VocabularyEntry? {
        let normalized = english.trimmed
        guard !normalized.isEmpty else { return nil }
        var sql = "SELECT * FROM vocabulary_entries WHERE english = ? COLLATE NOCASE"
        var bindings: [SQLValue] = [.text(normalized)]
        if let excluding {
            sql += " AND id != ?"
            bindings.append(.text(excluding.uuidString))
        }
        sql += " LIMIT 1"
        return try database.query(db, sql, bindings).first.flatMap(Self.entry(from:))
    }

    private func merging(_ entry: VocabularyEntry, with draft: EntryDraft, now: Date) -> VocabularyEntry {
        var copy = entry
        if !draft.english.trimmed.isEmpty { copy.english = draft.english.trimmed }
        if !draft.chinese.trimmed.isEmpty { copy.chinese = draft.chinese.trimmed }
        copy.lemma = draft.lemma ?? copy.lemma ?? Self.lemma(from: copy.english)
        copy.phonetic = draft.phonetic ?? copy.phonetic
        copy.partOfSpeech = draft.partOfSpeech ?? copy.partOfSpeech
        copy.englishDefinition = draft.englishDefinition ?? copy.englishDefinition
        copy.chineseDefinition = draft.chineseDefinition ?? copy.chineseDefinition
        if let incoming = draft.exampleSentence?.trimmed, !incoming.isEmpty,
           copy.exampleSentence?.trimmed.isEmpty != false {
            copy.exampleSentence = incoming
        }
        copy.sourceSentence = draft.sourceSentence ?? copy.sourceSentence
        copy.source = draft.source ?? copy.source
        if !draft.tags.isEmpty { copy.tags = draft.tags }
        copy.updatedAt = now
        return copy
    }

    func insertEntry(_ db: OpaquePointer, _ entry: VocabularyEntry) throws {
        try database.run(
            db,
            """
            INSERT INTO vocabulary_entries (
              id, english, chinese, lemma, phonetic, part_of_speech, english_definition,
              chinese_definition, example_sentence, source_sentence, source, tags_json,
              created_at, updated_at, archived
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            Self.entryBindings(entry)
        )
    }

    func writeEntry(_ db: OpaquePointer, _ entry: VocabularyEntry) throws {
        try database.run(
            db,
            """
            UPDATE vocabulary_entries SET
              english = ?, chinese = ?, lemma = ?, phonetic = ?, part_of_speech = ?,
              english_definition = ?, chinese_definition = ?, example_sentence = ?,
              source_sentence = ?, source = ?, tags_json = ?, created_at = ?, updated_at = ?, archived = ?
            WHERE id = ?
            """,
            [
                .text(entry.english),
                .text(entry.chinese),
                entry.lemma.map(SQLValue.text) ?? .null,
                entry.phonetic.map(SQLValue.text) ?? .null,
                entry.partOfSpeech.map(SQLValue.text) ?? .null,
                entry.englishDefinition.map(SQLValue.text) ?? .null,
                entry.chineseDefinition.map(SQLValue.text) ?? .null,
                entry.exampleSentence.map(SQLValue.text) ?? .null,
                entry.sourceSentence.map(SQLValue.text) ?? .null,
                entry.source.map(SQLValue.text) ?? .null,
                .text(Self.tagsJSON(entry.tags)),
                .text(DateCodec.shared.format(entry.createdAt)),
                .text(DateCodec.shared.format(entry.updatedAt)),
                .integer(entry.archived ? 1 : 0),
                .text(entry.id.uuidString)
            ]
        )
    }

    private func insertState(_ db: OpaquePointer, _ state: ReviewState) throws {
        for direction in state.directions {
            try writeDirection(db, entryID: state.entryID, state: direction, insert: true)
        }
    }

    func writeDirection(_ db: OpaquePointer, entryID: UUID, state: ReviewDirectionState, insert: Bool = false) throws {
        let sql = insert
            ? """
            INSERT INTO review_direction_states (
              entry_id, direction, due_at, last_reviewed_at, stage, interval_seconds,
              difficulty, stability, review_count, lapse_count, correct_count, incorrect_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            : """
            UPDATE review_direction_states SET
              due_at = ?, last_reviewed_at = ?, stage = ?, interval_seconds = ?, difficulty = ?,
              stability = ?, review_count = ?, lapse_count = ?, correct_count = ?, incorrect_count = ?
            WHERE entry_id = ? AND direction = ?
            """
        let shared: [SQLValue] = [
            .text(DateCodec.shared.format(state.dueAt)),
            state.lastReviewedAt.map { .text(DateCodec.shared.format($0)) } ?? .null,
            .integer(Int64(state.stage)),
            .double(state.interval),
            .double(state.difficulty),
            .double(state.stability),
            .integer(Int64(state.reviewCount)),
            .integer(Int64(state.lapseCount)),
            .integer(Int64(state.correctCount)),
            .integer(Int64(state.incorrectCount))
        ]
        let bindings: [SQLValue]
        if insert {
            bindings = [.text(entryID.uuidString), .text(state.direction.rawValue)] + shared
        } else {
            bindings = shared + [.text(entryID.uuidString), .text(state.direction.rawValue)]
        }
        try database.run(db, sql, bindings)
    }

    func insertLog(_ db: OpaquePointer, _ log: ReviewLog) throws {
        try database.run(
            db,
            """
            INSERT INTO review_logs (
              id, entry_id, direction, rating, reviewed_at, previous_due_at, scheduled_due_at, interval_seconds
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(log.id.uuidString),
                .text(log.entryID.uuidString),
                .text(log.direction.rawValue),
                .text(log.rating.rawValue),
                .text(DateCodec.shared.format(log.reviewedAt)),
                log.previousDueAt.map { .text(DateCodec.shared.format($0)) } ?? .null,
                .text(DateCodec.shared.format(log.scheduledDueAt)),
                .double(log.interval)
            ]
        )
    }

    func deleteRow(_ db: OpaquePointer, _ id: UUID) throws {
        try database.run(db, "DELETE FROM vocabulary_entries WHERE id = ?", [.text(id.uuidString)])
    }

    private static func entryBindings(_ entry: VocabularyEntry) -> [SQLValue] {
        [
            .text(entry.id.uuidString),
            .text(entry.english),
            .text(entry.chinese),
            entry.lemma.map(SQLValue.text) ?? .null,
            entry.phonetic.map(SQLValue.text) ?? .null,
            entry.partOfSpeech.map(SQLValue.text) ?? .null,
            entry.englishDefinition.map(SQLValue.text) ?? .null,
            entry.chineseDefinition.map(SQLValue.text) ?? .null,
            entry.exampleSentence.map(SQLValue.text) ?? .null,
            entry.sourceSentence.map(SQLValue.text) ?? .null,
            entry.source.map(SQLValue.text) ?? .null,
            .text(tagsJSON(entry.tags)),
            .text(DateCodec.shared.format(entry.createdAt)),
            .text(DateCodec.shared.format(entry.updatedAt)),
            .integer(entry.archived ? 1 : 0)
        ]
    }

    static func entry(from row: [String: SQLValue]) -> VocabularyEntry? {
        let idText = row.text("id") ?? row.text("entry_id")
        guard let idText, let id = UUID(uuidString: idText),
              let created = row.date("created_at"),
              let updated = row.date("updated_at") else { return nil }
        return VocabularyEntry(
            id: id,
            english: row.text("english") ?? "",
            chinese: row.text("chinese") ?? "",
            lemma: row.text("lemma"),
            phonetic: row.text("phonetic"),
            partOfSpeech: row.text("part_of_speech"),
            englishDefinition: row.text("english_definition"),
            chineseDefinition: row.text("chinese_definition"),
            exampleSentence: row.text("example_sentence"),
            sourceSentence: row.text("source_sentence"),
            source: row.text("source"),
            tags: tags(from: row.text("tags_json")),
            createdAt: created,
            updatedAt: updated,
            archived: row.integer("archived") != 0
        )
    }

    static func directionState(from row: [String: SQLValue]) -> ReviewDirectionState? {
        guard let raw = row.text("direction"), let direction = ReviewDirection(rawValue: raw),
              let due = row.date("due_at") else { return nil }
        return ReviewDirectionState(
            direction: direction,
            dueAt: due,
            lastReviewedAt: row.date("last_reviewed_at"),
            stage: row.integer("stage"),
            interval: row.double("interval_seconds"),
            difficulty: row.double("difficulty"),
            stability: row.double("stability"),
            reviewCount: row.integer("review_count"),
            lapseCount: row.integer("lapse_count"),
            correctCount: row.integer("correct_count"),
            incorrectCount: row.integer("incorrect_count")
        )
    }

    private static func card(from row: [String: SQLValue]) -> ReviewCard? {
        guard let entry = entry(from: row), let state = directionState(from: row) else { return nil }
        return ReviewCard(entry: entry, direction: state.direction, state: state)
    }

    static func log(from row: [String: SQLValue]) -> ReviewLog? {
        guard let id = row.text("id").flatMap(UUID.init(uuidString:)),
              let entryID = row.text("entry_id").flatMap(UUID.init(uuidString:)),
              let direction = row.text("direction").flatMap(ReviewDirection.init(rawValue:)),
              let rating = row.text("rating").flatMap(ReviewRating.init(rawValue:)),
              let reviewed = row.date("reviewed_at"),
              let scheduled = row.date("scheduled_due_at") else { return nil }
        return ReviewLog(
            id: id,
            entryID: entryID,
            direction: direction,
            rating: rating,
            reviewedAt: reviewed,
            previousDueAt: row.date("previous_due_at"),
            scheduledDueAt: scheduled,
            interval: row.double("interval_seconds")
        )
    }

    private static func tags(from json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return tags
    }

    private static func tagsJSON(_ tags: [String]) -> String {
        guard let data = try? JSONEncoder().encode(tags), let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func lemma(from english: String) -> String? {
        let trimmed = english.trimmed.lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

private let notifyLibraryChange: @Sendable () -> Void = {
    if Thread.isMainThread {
        NotificationCenter.default.post(name: .vordLibraryDidChange, object: nil)
    } else {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .vordLibraryDidChange, object: nil)
        }
    }
}
