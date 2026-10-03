import XCTest
@testable import Vord

final class VocabularyImportTests: XCTestCase {
    private let response = #"{"reply":"词条已整理，可以加入词库。","words":[{"english":"stagnant","chinese":"停滞的","englishDefinition":"not moving or developing"},{"english":"plight","chinese":"困境","englishDefinition":"a difficult situation","exampleSentence":"They were in a terrible plight."},{"english":"drip","chinese":"水滴","englishDefinition":"a small drop"}]}"#

    func testDecoderValidatesBoundsAndDeduplicatesWithoutInterpretingCommands() throws {
        let decoded = try AgentReply.decode(#"{"reply":"Ready","words":[{"english":"reign","chinese":"统治"},{"english":"Reign","chinese":"当政"}]}"#)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(try AgentReply.decode("Normal explanation").items.count, 0)
        XCTAssertThrowsError(try AgentReply.decode(#"{"reply":"Ready","words":[{"english":"$(rm -rf)","chinese":"词"}]}"#))
        XCTAssertThrowsError(try AgentReply.decode(#"{"reply":"Ready","words":[{"english":"word","chinese":""}]}"#))
        let words = Array(repeating: ["english": "word", "chinese": "词"], count: 51)
        let data = try JSONSerialization.data(withJSONObject: ["reply": "Ready", "words": words])
        XCTAssertThrowsError(try AgentReply.decode(String(decoding: data, as: UTF8.self)))
        XCTAssertThrowsError(try AgentReply.decode("{broken"))
    }

    @MainActor
    func testPreviewSelectionWritesOnlyChosenNewWordsAndSurvivesRestart() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let existing = try await repo.upsert(.init(english: "stagnant", chinese: "我的笔记", source: "Personal"), now: Date())
        let before = try await repo.exportSnapshot()
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let agent = LearningAgent(repository: repo, url: url) { _, _ in .init(text: self.response, modelID: "test") }
        agent.send("把 stagnant、plight、drip 加入我的词库。They were in a terrible plight.")
        while agent.isThinking { await Task.yield() }
        XCTAssertNil(agent.error)
        let message = try XCTUnwrap(agent.messages.last)
        let proposal = try XCTUnwrap(message.wordImport)
        XCTAssertEqual(proposal.items.first?.status, .existing)
        XCTAssertEqual(proposal.pendingCount, 2)
        let previewSnapshot = try await repo.exportSnapshot()
        XCTAssertEqual(previewSnapshot.entries.count, 1)
        let drip = try XCTUnwrap(proposal.items.first(where: { $0.english == "drip" }))
        agent.editImport(messageID: message.id, itemID: drip.id, selected: false)
        await agent.importWords(messageID: message.id)
        await agent.importWords(messageID: message.id)
        let after = try await repo.exportSnapshot()
        XCTAssertEqual(after.entries.count, 2)
        XCTAssertEqual(after.entries.first(where: { $0.id == existing.id }), before.entries.first(where: { $0.id == existing.id }))
        XCTAssertEqual(after.reviewStates.first(where: { $0.entryID == existing.id }), before.reviewStates.first(where: { $0.entryID == existing.id }))
        let plight = try XCTUnwrap(after.entries.first(where: { $0.english == "plight" }))
        XCTAssertEqual(plight.englishDefinition, "a difficult situation")
        XCTAssertEqual(plight.exampleSentence, "They were in a terrible plight.")
        XCTAssertTrue(after.reviewLogs.isEmpty)
        let restored = LearningAgent(repository: repo, url: url) { _, _ in throw AIError.noProvider }
        XCTAssertEqual(restored.messages, agent.messages)
        XCTAssertEqual(restored.messages.last?.wordImport?.addedCount, 1)
    }

    @MainActor
    func testConcurrentCaptureCannotBeOverwrittenByImport() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        async let first = repo.insertIfAbsent(.init(english: "plight", chinese: "我的笔记"), now: Date())
        async let second = repo.insertIfAbsent(.init(english: "PLIGHT", chinese: "导入释义"), now: Date())
        let results = try await [first, second]
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.reviewStates.count, 1)
    }

    @MainActor
    func testFailedRowsCanBeRetriedWithoutDuplicatingSuccessfulRows() async throws {
        let database = try AppDatabase(path: ":memory:")
        let repo = SQLiteVocabularyRepository(database: database, onChange: {})
        try await database.perform { db in
            try database.exec(db, "CREATE TRIGGER reject_plight BEFORE INSERT ON vocabulary_entries WHEN NEW.english = 'plight' BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
        }
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let agent = LearningAgent(repository: repo, url: url) { _, _ in .init(text: self.response, modelID: "test") }
        agent.send("导入这些词")
        while agent.isThinking { await Task.yield() }
        let id = try XCTUnwrap(agent.messages.last?.id)
        await agent.importWords(messageID: id)
        XCTAssertEqual(agent.messages.last?.wordImport?.addedCount, 2)
        XCTAssertEqual(agent.messages.last?.wordImport?.items.filter { $0.status == .failed }.count, 1)
        try await database.perform { db in try database.exec(db, "DROP TRIGGER reject_plight") }
        await agent.importWords(messageID: id)
        XCTAssertEqual(agent.messages.last?.wordImport?.addedCount, 3)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertEqual(snapshot.entries.count, 3)
    }

    @MainActor
    func testLatestPastedTextIsNotTruncatedToConversationHistoryLimit() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var prompt = ""
        let agent = LearningAgent(repository: repo, url: url) { value, _ in
            prompt = value
            return .init(text: #"{"reply":"Ready","words":[]}"#, modelID: "test")
        }
        agent.send(String(repeating: "source ", count: 900) + "LAST_WORD_SENTINEL")
        while agent.isThinking { await Task.yield() }
        XCTAssertTrue(prompt.contains("LAST_WORD_SENTINEL"))
        XCTAssertNil(agent.error)
    }

    @MainActor
    func testOfflineEnrichmentKeepsContextMeaningAndQueuesNormalSync() async throws {
        let database = try AppDatabase(path: ":memory:")
        let repo = SQLiteVocabularyRepository(database: database, onChange: {})
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let dictionary = DictionaryStore(url: url.deletingLastPathComponent().appendingPathComponent("dictionary.json"), bundledURL: nil)
        try dictionary.importData(JSONEncoder().encode([DictionaryItem(english: "plight", chinese: "困境；承诺", phonetic: "plaɪt", partOfSpeech: "n.", englishDefinition: "an unfortunate situation")]))
        let agent = LearningAgent(repository: repo, url: url, dictionary: dictionary) { _, _ in
            .init(text: #"{"reply":"Ready","words":[{"english":"plight","chinese":"窘境","exampleSentence":"This sentence was never supplied."}]}"#, modelID: "test")
        }
        agent.send("帮我加入 plight，意思是窘境")
        while agent.isThinking { await Task.yield() }
        let message = try XCTUnwrap(agent.messages.last)
        XCTAssertNil(message.wordImport?.items.first?.exampleSentence)
        await agent.importWords(messageID: message.id)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertEqual(snapshot.entries.first?.phonetic, "plaɪt")
        XCTAssertEqual(snapshot.entries.first?.chinese, "窘境")
        XCTAssertEqual(snapshot.entries.first?.englishDefinition, "an unfortunate situation")
        let sync = try await SyncStore(database: database).request()
        XCTAssertEqual(sync.changes.filter { $0.kind == "entry" }.count, 1)
        XCTAssertEqual(sync.changes.filter { $0.kind == "direction" }.count, 2)
    }

    @MainActor
    func testLibrarySearchIncludesFullDefinitionsAndArchivedEntries() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repo.upsert(.init(english: "plight", chinese: "困境", englishDefinition: "a solemn pledge of fidelity", chineseDefinition: "处于窘境"), now: Date())
        let model = LibraryViewModel()
        await model.load(repo)
        model.search = "fidelity"; model.searchChanged()
        XCTAssertEqual(model.visible.map(\.id), [entry.id])
        model.search = "窘境"; model.searchChanged()
        XCTAssertEqual(model.visible.map(\.id), [entry.id])
        try await repo.setArchived(id: entry.id, archived: true, now: Date())
        await model.load(repo)
        XCTAssertTrue(model.visible.isEmpty)
        model.scope = .archived; model.sortChanged()
        XCTAssertEqual(model.visible.map(\.id), [entry.id])
        XCTAssertNotNil(model.entries[entry.id]?.englishDefinition)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("assistant.json")
    }
}
