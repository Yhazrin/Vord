import XCTest
@testable import Vord

final class RepositoryTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: databaseURL)
        super.tearDown()
    }

    func testSaveSurvivesReopenAndReviewMovesTheDueDate() async throws {
        let now = Date()
        let repository = try makeRepository()
        let saved = try await repository.upsert(
            EntryDraft(english: "astonish", chinese: "使惊讶；使震惊", lemma: "astonish", source: "test"),
            now: now
        )
        let summary = try await repository.todaySummary(now: now)
        XCTAssertEqual(summary.dueCount, 1)
        XCTAssertEqual(summary.addedToday, 1)

        let scheduler = SimpleScheduler()
        for direction in ReviewDirection.allCases {
            let state = try await repository.reviewState(entryID: saved.id)
            let result = scheduler.schedule(state: try XCTUnwrap(state), direction: direction, rating: .good, now: now)
            try await repository.recordReview(result)
        }
        let after = try await repository.todaySummary(now: now)
        XCTAssertEqual(after.dueCount, 0)
        XCTAssertEqual(after.reviewedToday, 2)

        let reopened = try makeRepository()
        let loadedEntry = try await reopened.entry(id: saved.id)
        let loaded = try XCTUnwrap(loadedEntry)
        XCTAssertEqual(loaded.english, "astonish")
        XCTAssertEqual(loaded.chinese, "使惊讶；使震惊")

        let snapshot = try await reopened.exportSnapshot()
        let data = try LibraryExporter.data(from: snapshot)
        let decoded = try LibraryExporter.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.reviewStates.count, 1)
        XCTAssertEqual(decoded.reviewLogs.count, 2)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let object = try XCTUnwrap(json)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(object["entries"])
        XCTAssertNotNil(object["reviewStates"])
        XCTAssertNotNil(object["reviewLogs"])
    }

    func testDuplicateEnglishUpdatesTheSameRow() async throws {
        let repository = try makeRepository()
        let now = Date()
        let first = try await repository.upsert(EntryDraft(english: "Astonish", chinese: ""), now: now)
        let second = try await repository.upsert(EntryDraft(english: "astonish", chinese: "使惊讶"), now: now)
        XCTAssertEqual(first.id, second.id)
        let rows = try await repository.libraryRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].chinese, "使惊讶")
    }

    func testExistingExampleIsKeptWhenALaterSaveHasAnother() async throws {
        let repository = try makeRepository()
        let now = Date()
        let first = try await repository.upsert(EntryDraft(english: "cat", chinese: "猫", exampleSentence: "The cat sleeps."), now: now)
        let second = try await repository.upsert(EntryDraft(english: "cat", chinese: "猫", exampleSentence: "A different sentence."), now: now)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.exampleSentence, "The cat sleeps.")
        let empty = try await repository.upsert(EntryDraft(english: "dog", chinese: "狗"), now: now)
        let filled = try await repository.upsert(EntryDraft(english: "dog", chinese: "狗", exampleSentence: "Dogs bark."), now: now)
        XCTAssertEqual(empty.id, filled.id)
        XCTAssertEqual(filled.exampleSentence, "Dogs bark.")
    }

    func testLibrarySearchMatchesChineseAndTags() async throws {
        let repository = try makeRepository()
        _ = try await repository.upsert(
            EntryDraft(english: "ubiquitous", chinese: "无处不在的", tags: ["IELTS"]),
            now: Date()
        )
        let rows = try await repository.libraryRows()
        XCTAssertEqual(LibraryQuery.apply(rows: rows, search: "无处", sort: .added).count, 1)
        XCTAssertEqual(LibraryQuery.apply(rows: rows, search: "ielts", sort: .alphabetical).count, 1)
        XCTAssertEqual(LibraryQuery.apply(rows: rows, search: "missing", sort: .due).count, 0)
    }

    private func makeRepository() throws -> SQLiteVocabularyRepository {
        let database = try AppDatabase(path: databaseURL.path)
        return SQLiteVocabularyRepository(database: database, onChange: {})
    }
}
