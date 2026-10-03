import XCTest
@testable import Vord

private actor RecordingSyncTransport: SyncTransport {
    private var uploaded: [SyncRecord] = []
    func exchange(_ request: SyncRequest, endpoint: URL, token: String) async throws -> SyncResponse {
        uploaded += request.changes
        return SyncResponse(protocolVersion: 1, cursor: request.cursor, hasMore: false, changes: [],
            acknowledged: request.changes.map { SyncAcknowledgement(kind: $0.kind, id: $0.id, clock: $0.clock, deviceID: $0.deviceID) }, aliases: [:])
    }
    func contains(_ id: UUID) -> Bool { uploaded.contains { $0.kind == "entry" && $0.id == id.uuidString } }
}

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    private func setup() throws -> (AppDatabase, SyncCoordinator, RecordingSyncTransport, UserDefaults, String) {
        let database = try AppDatabase(path: ":memory:")
        let name = "vord.sync-trigger-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: "sync.connected")
        let transport = RecordingSyncTransport()
        let coordinator = SyncCoordinator(database: database, defaults: defaults, transport: transport,
                                          readCredential: { "isolated-test-code" })
        return (database, coordinator, transport, defaults, name)
    }
    private func waitForUpload(_ id: UUID, transport: RecordingSyncTransport) async -> Bool {
        for _ in 0..<30 {
            if await transport.contains(id) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    func testSavingWordTriggersUploadWithoutManualSync() async throws {
        let (database, coordinator, transport, defaults, name) = try setup()
        defer { coordinator.disconnect(); defaults.removePersistentDomain(forName: name) }
        await coordinator.start()
        let repository = SQLiteVocabularyRepository(database: database)
        let word = try await repository.upsert(EntryDraft(english: "stagnant", chinese: "停滞的"), now: Date())
        let uploaded = await waitForUpload(word.id, transport: transport)
        XCTAssertTrue(uploaded, "A committed write must upload immediately, without waiting for the periodic timer.")
    }
    func testFallbackFindsCommitsWithoutInProcessNotification() async throws {
        let (database, coordinator, transport, defaults, name) = try setup()
        defer { coordinator.disconnect(); defaults.removePersistentDomain(forName: name) }
        await coordinator.start()
        let repository = SQLiteVocabularyRepository(database: database, onChange: {})
        let word = try await repository.upsert(EntryDraft(english: "external-commit", chinese: "外部写入"), now: Date())
        await coordinator.checkForLocalChanges()
        let uploaded = await waitForUpload(word.id, transport: transport)
        XCTAssertTrue(uploaded, "The local queue watcher must also observe commits from another app process.")
    }
}
