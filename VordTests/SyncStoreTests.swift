import XCTest
@testable import Vord

final class SyncStoreTests: XCTestCase {
    private func fixtures() throws -> (AppDatabase, SQLiteVocabularyRepository, SyncStore) {
        let db = try AppDatabase(path: ":memory:")
        return (db, SQLiteVocabularyRepository(database: db, onChange: {}), SyncStore(database: db))
    }
    private func echoed(_ request: SyncRequest, start: Int64 = 1) -> SyncResponse {
        let records = request.changes.enumerated().map { index, value -> SyncRecord in
            var value = value; value.seq = start + Int64(index); return value
        }
        return SyncResponse(protocolVersion: 1, cursor: records.last?.seq ?? request.cursor, hasMore: false,
            changes: records, acknowledged: request.changes.map { SyncAcknowledgement(kind: $0.kind, id: $0.id, clock: $0.clock, deviceID: $0.deviceID) }, aliases: [:])
    }
    func testLocalWriteQueuesWordAndBothDirectionsInSameTransaction() async throws {
        let (_, repository, store) = try fixtures()
        let entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date())
        let request = try await store.request()
        XCTAssertEqual(request.changes.count, 3)
        XCTAssertEqual(request.changes.first?.id, entry.id.uuidString)
        XCTAssertEqual(Set(request.changes.first?.changedFields ?? []), Set(SyncStore.entryFields))
        try await store.apply(echoed(request), sent: request)
        let next = try await store.request()
        XCTAssertTrue(next.changes.isEmpty)
        XCTAssertEqual(next.cursor, 3)
        let archivedAt = Date()
        try await repository.setArchived(id: entry.id, archived: true, now: archivedAt)
        let update = try await store.request()
        XCTAssertEqual(Set(update.changes.first?.changedFields ?? []), ["archived", "updatedAt"])
    }
    func testLargeLibraryUsesBoundedRequestsWithoutDroppingQueuedRecords() async throws {
        let (_, repository, store) = try fixtures()
        let note = String(repeating: "x", count: 30_000)
        for index in 0..<150 {
            _ = try await repository.upsert(EntryDraft(english: "batch-word-\(index)", chinese: "释义", source: note), now: Date())
        }
        let first = try await store.request()
        XCTAssertLessThanOrEqual(try SyncCodec.encoder().encode(first).count, 4 * 1024 * 1024)
        XCTAssertLessThan(first.changes.filter { $0.kind == "entry" }.count, 150)
        var sentCount = 0
        var request = first
        while !request.changes.isEmpty {
            XCTAssertLessThanOrEqual(try SyncCodec.encoder().encode(request).count, 4 * 1024 * 1024)
            sentCount += request.changes.count
            try await store.apply(echoed(request, start: request.cursor + 1), sent: request)
            request = try await store.request()
        }
        XCTAssertEqual(sentCount, 450)
    }
    func testEditWhileRequestInFlightSurvivesItsAcknowledgement() async throws {
        let (_, repository, store) = try fixtures()
        var entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date(timeIntervalSince1970: 100))
        let sent = try await store.request()
        entry.chinese = "窘境"; entry.updatedAt = Date(timeIntervalSince1970: 200)
        try await repository.update(entry)
        try await store.apply(echoed(sent), sent: sent)
        let saved = try await repository.entry(id: entry.id)
        let next = try await store.request()
        XCTAssertEqual(saved?.chinese, "窘境")
        XCTAssertEqual(next.changes.count, 1)
        XCTAssertGreaterThan(next.changes[0].clock, sent.changes[0].clock)
        XCTAssertEqual(Set(next.changes[0].changedFields ?? []), ["chinese", "updatedAt"])
    }
    func testRemoteDifferentFieldPreservesUnsentMeaning() async throws {
        let (_, repository, store) = try fixtures()
        var entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date(timeIntervalSince1970: 100))
        let initial = try await store.request()
        try await store.apply(echoed(initial), sent: initial)
        entry.chinese = "窘境"; entry.updatedAt = Date(timeIntervalSince1970: 200)
        try await repository.update(entry)
        var remote = entry; remote.chinese = "困境"; remote.tags = ["reading"]
        let record = SyncRecord(kind: "entry", id: entry.id.uuidString, clock: 40, deviceID: UUID().uuidString, deleted: false,
                                payload: try SyncCodec.json(remote), changedFields: ["tags"], seq: 4)
        let poll = SyncRequest(deviceID: initial.deviceID, cursor: 3, changes: [])
        try await store.apply(SyncResponse(protocolVersion: 1, cursor: 4, hasMore: false, changes: [record], acknowledged: [], aliases: [:]), sent: poll)
        let saved = try await repository.entry(id: entry.id)
        XCTAssertEqual(saved?.chinese, "窘境")
        XCTAssertEqual(saved?.tags, ["reading"])
        let next = try await store.request()
        XCTAssertEqual(Set(next.changes.first?.changedFields ?? []), ["chinese"])
        var revised = saved!; revised.source = "article"
        try await repository.update(revised)
        let after = try await store.request()
        XCTAssertGreaterThan(after.changes.first?.clock ?? 0, 40)
    }
    func testFirstUploadAcknowledgementRebasesOnlyEditsMadeInFlight() async throws {
        let (_, repository, store) = try fixtures()
        var entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date(timeIntervalSince1970: 100))
        let sent = try await store.request()
        entry.chinese = "窘境"; entry.updatedAt = Date(timeIntervalSince1970: 200)
        try await repository.update(entry)
        var response = echoed(sent)
        var remote = entry; remote.chinese = "困境"; remote.tags = ["reading"]
        response.changes[0].payload = try SyncCodec.json(remote)
        try await store.apply(response, sent: sent)
        let saved = try await repository.entry(id: entry.id)
        XCTAssertEqual(saved?.chinese, "窘境")
        XCTAssertEqual(saved?.tags, ["reading"])
        let next = try await store.request()
        XCTAssertEqual(Set(next.changes.first?.changedFields ?? []), ["chinese"])
    }
    func testDeletionSurvivesOfflineRestartAndOldRemotePages() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        var id: UUID!
        var old: SyncRequest!
        do {
            let db = try AppDatabase(path: url.path)
            let repository = SQLiteVocabularyRepository(database: db, onChange: {})
            let store = SyncStore(database: db)
            id = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date()).id
            old = try await store.request()
            try await repository.delete(id: id)
        }
        let db = try AppDatabase(path: url.path)
        let repository = SQLiteVocabularyRepository(database: db, onChange: {})
        let store = SyncStore(database: db)
        try await store.apply(echoed(old), sent: old)
        let request = try await store.request()
        XCTAssertEqual(request.changes.count, 1)
        XCTAssertTrue(request.changes[0].deleted)
        let absent = try await repository.entry(id: id)
        XCTAssertNil(absent)
    }
    func testRemoteDeleteWinsOverUnsentEdit() async throws {
        let (_, repository, store) = try fixtures()
        var entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date())
        let sent = try await store.request()
        try await store.apply(echoed(sent), sent: sent)
        entry.source = "local edit"; try await repository.update(entry)
        let deletion = SyncRecord(kind: "entry", id: entry.id.uuidString, clock: 50, deviceID: UUID().uuidString, deleted: true, seq: 4)
        let poll = SyncRequest(deviceID: sent.deviceID, cursor: 3, changes: [])
        try await store.apply(SyncResponse(protocolVersion: 1, cursor: 4, hasMore: false, changes: [deletion], acknowledged: [], aliases: [:]), sent: poll)
        let absent = try await repository.entry(id: entry.id)
        let next = try await store.request()
        XCTAssertNil(absent); XCTAssertTrue(next.changes.isEmpty)
    }
    func testAliasConsolidatesWordAndReviewHistory() async throws {
        let (_, repository, store) = try fixtures()
        let entry = try await repository.upsert(EntryDraft(english: "plight", chinese: "困境"), now: Date())
        let state = try await repository.reviewState(entryID: entry.id)!
        let result = SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .good, now: Date())
        try await repository.recordReview(result)
        let sent = try await store.request()
        let canonical = UUID()
        var response = echoed(sent)
        response.aliases = [entry.id.uuidString: canonical.uuidString]
        try await store.apply(response, sent: sent)
        let library = try await repository.exportSnapshot()
        XCTAssertEqual(library.entries.map(\.id), [canonical])
        XCTAssertEqual(library.reviewLogs.first?.entryID, canonical)
        XCTAssertEqual(library.reviewStates.first?.state(for: .englishToChinese)?.reviewCount, 1)
        let next = try await store.request()
        XCTAssertTrue(next.changes.isEmpty)
    }
    func testInvalidRemotePayloadRollsBackCursorAndWriteSuppression() async throws {
        let (db, repository, store) = try fixtures()
        let sent = try await store.request()
        let invalid = SyncRecord(kind: "entry", id: "invalid", clock: 4, deviceID: UUID().uuidString, deleted: true, seq: 1)
        do {
            try await store.apply(SyncResponse(protocolVersion: 1, cursor: 1, hasMore: false, changes: [invalid], acknowledged: [], aliases: [:]), sent: sent)
            XCTFail("Malformed remote IDs must fail atomically")
        } catch {}
        let next = try await store.request()
        XCTAssertEqual(next.cursor, 0)
        let suppress = try await db.perform { try db.query($0, "SELECT value FROM meta WHERE key='sync.applying'").first?.text("value") }
        XCTAssertEqual(suppress, "0")
        _ = try await repository.upsert(EntryDraft(english: "retry", chinese: "重试"), now: Date())
        let queued = try await store.request()
        XCTAssertEqual(queued.changes.count, 3)
    }
    func testServerRestoreRecoveryRequeuesCurrentLibraryAndPermanentDeletions() async throws {
        let (_, repository, store) = try fixtures()
        let removed = try await repository.upsert(EntryDraft(english: "removed", chinese: "已删除"), now: Date())
        let kept = try await repository.upsert(EntryDraft(english: "kept", chinese: "保留"), now: Date())
        let sent = try await store.request()
        try await store.apply(echoed(sent), sent: sent)
        try await repository.delete(id: removed.id)
        try await store.recoverFromRestoredServer()
        let replay = try await store.request()
        XCTAssertEqual(replay.cursor, 0)
        XCTAssertEqual(replay.changes.filter { $0.kind == "entry" && !$0.deleted }.map(\.id), [kept.id.uuidString])
        XCTAssertEqual(replay.changes.filter(\.deleted).map(\.id), [removed.id.uuidString])
        XCTAssertEqual(Set(replay.changes.first { $0.id == kept.id.uuidString }?.changedFields ?? []), Set(SyncStore.entryFields))
    }
}
