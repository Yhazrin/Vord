import XCTest
@testable import Vord

final class LearningFlowTests: XCTestCase {
    private func requiredState(_ repo: SQLiteVocabularyRepository, id: UUID) async throws -> ReviewState {
        let loaded = try await repo.reviewState(entryID: id)
        return try XCTUnwrap(loaded)
    }
    func testDueQueueExcludesFutureAndIncompleteWordsAndArchives() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let now = Date()
        let entry = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: now)
        _ = try await repo.upsert(.init(english: "pending", chinese: ""), now: now)
        var state = try await requiredState(repo, id: entry.id)
        let result = SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .again, now: now)
        try await repo.recordReview(result)
        var cards = try await repo.dueCards(now: now, limit: 100)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.direction, .chineseToEnglish)
        cards = try await repo.dueCards(now: now.addingTimeInterval(601), limit: 100)
        XCTAssertEqual(cards.count, 2)
        try await repo.setArchived(id: entry.id, archived: true, now: now)
        cards = try await repo.dueCards(now: now.addingTimeInterval(601), limit: 100)
        XCTAssertTrue(cards.isEmpty)
        state = try await requiredState(repo, id: entry.id)
        XCTAssertEqual(state.state(for: .englishToChinese)?.reviewCount, 1)
    }
    @MainActor
    func testAgainReappearsAndCompletesAfterGood() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        _ = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        let model = ReviewViewModel(repository: repo, scheduler: SimpleScheduler(), mode: .englishToChinese)
        await model.load()
        XCTAssertEqual(model.total, 1)
        model.reveal(); await model.rate(.again)
        XCTAssertEqual(model.remaining, 1)
        XCTAssertTrue(model.repeated)
        XCTAssertEqual(model.completed, 0)
        XCTAssertEqual(model.lastRating, .again)
        model.reveal(); await model.rate(.good)
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.completed, 1)
        XCTAssertEqual(model.attempts, 2)
        XCTAssertEqual(model.lastRating, .good)
    }
    @MainActor
    func testFailedSaveDoesNotDropTheCard() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        let model = ReviewViewModel(repository: repo, scheduler: SimpleScheduler(), mode: .englishToChinese)
        await model.load(); model.reveal()
        try await repo.delete(id: entry.id)
        await model.rate(.good)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.remaining, 1)
        XCTAssertTrue(model.showAnswer)
        XCTAssertEqual(model.attempts, 0)
        XCTAssertNil(model.lastRating)
    }
    @MainActor
    func testExamDoesNotChangeReviewAndRetriesOnlyMistakes() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        _ = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        _ = try await repo.upsert(.init(english: "dog", chinese: "狗"), now: Date())
        let before = try await repo.exportSnapshot()
        let exam = DictationModel()
        await exam.start(repo)
        exam.answer = exam.current!.expected; exam.check(); exam.advance()
        exam.skip(); exam.advance()
        XCTAssertTrue(exam.finished)
        XCTAssertEqual(exam.correctCount, 1)
        exam.retryMissed()
        XCTAssertEqual(exam.questions.count, 1)
        XCTAssertFalse(exam.finished)
        let after = try await repo.exportSnapshot()
        XCTAssertEqual(before.reviewStates, after.reviewStates)
        XCTAssertEqual(before.reviewLogs, after.reviewLogs)
    }
    func testDictionaryImportValidationPersistenceAndBothDirections() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("dictionary.json")
        let store = DictionaryStore(url: url, bundledURL: nil)
        let data = Data(#"[{"english":"resilient","chinese":"有韧性的；坚韧的","phonetic":"/rɪˈzɪliənt/"}]"#.utf8)
        XCTAssertEqual(try store.importData(data), 1)
        XCTAssertEqual(store.match(" Resilient ", from: .english)?.chinese, "有韧性的；坚韧的")
        XCTAssertEqual(store.match("坚韧的", from: .chinese)?.english, "resilient")
        XCTAssertThrowsError(try store.importData(Data(#"[{"english":"bad","chinese":""}]"#.utf8)))
        XCTAssertEqual(DictionaryStore(url: url).count, 1)
    }
    func testBackupImportIsIdempotentAndKeepsReviewHistory() async throws {
        let source = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await source.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        let state = try await requiredState(source, id: entry.id)
        try await source.recordReview(SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .easy, now: Date()))
        let snapshot = try await source.exportSnapshot()
        let target = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let firstCount = try await target.importSnapshot(snapshot)
        let secondCount = try await target.importSnapshot(snapshot)
        XCTAssertEqual(firstCount, 1); XCTAssertEqual(secondCount, 0)
        let restored = try await target.exportSnapshot()
        XCTAssertEqual(snapshot, restored)
    }
    func testDuplicateReviewLogRollsBackDirectionUpdate() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        let state = try await requiredState(repo, id: entry.id)
        let first = SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .good, now: Date())
        try await repo.recordReview(first)
        var second = SimpleScheduler().schedule(state: first.state, direction: .englishToChinese, rating: .easy, now: Date())
        second.log.id = first.log.id
        do { try await repo.recordReview(second); XCTFail("Expected duplicate log failure") } catch {}
        let stored = try await repo.reviewState(entryID: entry.id)
        XCTAssertEqual(stored?.state(for: .englishToChinese)?.reviewCount, 1)
    }
}

extension LearningFlowTests {
    func testMissingEntryUpdateCannotRecreateADeletedWord() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repo.upsert(.init(english: "cat", chinese: ""), now: Date())
        try await repo.delete(id: entry.id)
        do {
            _ = try await repo.upsert(.init(existingID: entry.id, english: "cat", chinese: "猫"), now: Date())
            XCTFail("A late translation must not recreate a deleted entry")
        } catch {}
        let entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
    }
    @MainActor
    func testAppleBridgeCancellationDrainsPendingAndQueuedRequests() async throws {
        let bridge = AppleTranslationBridge()
        let first = Task { try await bridge.translate(text: "cat", from: .english, to: .chinese) }
        await Task.yield()
        let second = Task { try await bridge.translate(text: "dog", from: .english, to: .chinese) }
        await Task.yield()
        first.cancel(); second.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
        do { _ = try await second.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertNil(bridge.configuration)
    }
    @MainActor
    func testLearningHistorySurvivesReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let history = LearningHistory(url: url)
        let example = ContextExample(entryID: UUID(), word: "cat", sentence: "The cat sleeps.", translation: "猫在睡觉。", explanation: "猫")
        let record = ContextRecord(topic: "Home", level: "B1", provider: "Test", model: "model", examples: [example])
        try history.append(record)
        XCTAssertEqual(LearningHistory(url: url).contexts.first, record)
    }
}
