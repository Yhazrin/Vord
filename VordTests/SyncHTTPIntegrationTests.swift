import XCTest
@testable import Vord

final class SyncHTTPIntegrationTests: XCTestCase {
    func testNativeAndroidFixtureAndMacFixtureExchange() async throws {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Vord/Sync")
        guard let fixturePath = ProcessInfo.processInfo.environment["VORD_ANDROID_SYNC_FIXTURE"] else { throw XCTSkip("Set VORD_ANDROID_SYNC_FIXTURE for the opt-in cross-device test") }
        let receipt = URL(fileURLWithPath: fixturePath)
        guard FileManager.default.fileExists(atPath: receipt.path), FileManager.default.fileExists(atPath: folder.appendingPathComponent("pairing-test.json").path) else {
            throw XCTSkip("Android cross-platform fixture is not available")
        }
        let pairing = try JSONDecoder().decode(SyncPairing.self, from: Data(contentsOf: folder.appendingPathComponent("pairing-test.json")))
        let fixture = try JSONDecoder().decode(SyncJSON.self, from: Data(contentsOf: receipt)).object
        let db = try AppDatabase(path: ":memory:")
        let repository = SQLiteVocabularyRepository(database: db, onChange: {})
        let store = SyncStore(database: db)
        try await drain(store, pairing: pairing)
        let androidID = UUID(uuidString: fixture["id"]!.string!)!
        let android = try await repository.entry(id: androidID)
        XCTAssertEqual(android?.english, fixture["english"]?.string)
        XCTAssertEqual(android?.chinese, fixture["chinese"]?.string)
        XCTAssertEqual(android?.tags, ["sync-test-fixture"])
        let state = try await repository.reviewState(entryID: androidID)
        XCTAssertEqual(state?.state(for: .chineseToEnglish)?.reviewCount, 1)
        XCTAssertEqual(state?.state(for: .englishToChinese)?.reviewCount, 0)
        let received = try await repository.exportSnapshot()
        XCTAssertEqual(received.reviewLogs.filter { $0.entryID == androidID }.count, 1)
        let mac = try await repository.upsert(EntryDraft(english: "mac-cross-platform-" + UUID().uuidString.lowercased(), chinese: "Mac设备创建，供安卓交叉验证", tags: ["mac-sync-fixture"]), now: Date())
        let review = try await repository.reviewState(entryID: mac.id)!
        try await repository.recordReview(SimpleScheduler().schedule(state: review, direction: .englishToChinese, rating: .good, now: Date()))
        try await drain(store, pairing: pairing)
        let exported = try await repository.exportSnapshot()
        let snapshot = LibraryExport(schemaVersion: 1, entries: [mac], reviewStates: exported.reviewStates.filter { $0.entryID == mac.id }, reviewLogs: exported.reviewLogs.filter { $0.entryID == mac.id })
        try LibraryExporter.data(from: snapshot).write(to: receipt.deletingLastPathComponent().appendingPathComponent("mac-sync-fixture.json"), options: .atomic)
    }
    private func drain(_ store: SyncStore, pairing: SyncPairing) async throws {
        let transport = HTTPSyncTransport()
        let endpoint = try SyncFailure.validatedEndpoint(pairing.endpoint)
        for _ in 0..<15 {
            let request = try await store.request()
            let response = try await transport.exchange(request, endpoint: endpoint, token: pairing.token)
            try await store.apply(response, sent: request)
            let next = try await store.request()
            if !response.hasMore && next.changes.isEmpty { return }
        }
        XCTFail("Sync did not converge within 15 batches")
    }
    func testRealHTTPSOfflineEditsReviewsAndDeletionConverge() async throws {
        guard let path = ProcessInfo.processInfo.environment["VORD_SYNC_TEST_PAIRING"] else { throw XCTSkip("Set VORD_SYNC_TEST_PAIRING for the opt-in HTTP integration test") }
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Private integration pairing is not available") }
        let pairing = try JSONDecoder().decode(SyncPairing.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let dbA = try AppDatabase(path: ":memory:"), dbB = try AppDatabase(path: ":memory:")
        let a = SQLiteVocabularyRepository(database: dbA, onChange: {}), b = SQLiteVocabularyRepository(database: dbB, onChange: {})
        let storeA = SyncStore(database: dbA), storeB = SyncStore(database: dbB)
        let initial = try await a.upsert(EntryDraft(english: "mac-sync-probe-" + UUID().uuidString.lowercased(), chinese: "同步测试"), now: Date())
        try await drain(storeA, pairing: pairing)
        try await drain(storeB, pairing: pairing)
        var aWord = try await a.entry(id: initial.id)!, bWord = try await b.entry(id: initial.id)!
        aWord.source = "offline article"; aWord.updatedAt = Date()
        bWord.chinese = "离线释义"; bWord.updatedAt = Date()
        try await a.update(aWord); try await b.update(bWord)
        try await drain(storeB, pairing: pairing)
        try await drain(storeA, pairing: pairing)
        try await drain(storeB, pairing: pairing)
        let mergedA = try await a.entry(id: initial.id), mergedB = try await b.entry(id: initial.id)
        XCTAssertEqual(mergedA?.chinese, "离线释义"); XCTAssertEqual(mergedA?.source, "offline article")
        XCTAssertEqual(mergedA, mergedB)
        let stateA = try await a.reviewState(entryID: initial.id)!, stateB = try await b.reviewState(entryID: initial.id)!
        try await a.recordReview(SimpleScheduler().schedule(state: stateA, direction: .englishToChinese, rating: .good, now: Date()))
        try await b.recordReview(SimpleScheduler().schedule(state: stateB, direction: .chineseToEnglish, rating: .hard, now: Date()))
        try await drain(storeA, pairing: pairing); try await drain(storeB, pairing: pairing); try await drain(storeA, pairing: pairing)
        let reviewedA = try await a.reviewState(entryID: initial.id), reviewedB = try await b.reviewState(entryID: initial.id)
        XCTAssertEqual(reviewedA?.state(for: .englishToChinese)?.reviewCount, 1)
        XCTAssertEqual(reviewedA?.state(for: .chineseToEnglish)?.reviewCount, 1)
        XCTAssertEqual(reviewedA, reviewedB)
        let library = try await a.exportSnapshot()
        XCTAssertEqual(library.reviewLogs.filter { $0.entryID == initial.id }.count, 2)
        var stale = try await a.entry(id: initial.id)!; stale.source = "unsent stale edit"
        try await a.update(stale)
        try await b.delete(id: initial.id)
        try await drain(storeB, pairing: pairing); try await drain(storeA, pairing: pairing); try await drain(storeB, pairing: pairing)
        let absentA = try await a.entry(id: initial.id), absentB = try await b.entry(id: initial.id)
        XCTAssertNil(absentA); XCTAssertNil(absentB)
        let pending = try await storeA.request()
        XCTAssertTrue(pending.changes.isEmpty)
    }
}
