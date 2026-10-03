import XCTest
@testable import Vord

@MainActor
final class LibraryFlowTests: XCTestCase {
    func testRemovedTagDoesNotLeaveLibraryInAnInvisibleFilter() async throws {
        let repository = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let tagged = try await repository.upsert(.init(english: "cat", chinese: "猫", tags: ["Reading"]), now: Date())
        let retained = try await repository.upsert(.init(english: "dog", chinese: "狗"), now: Date())
        let model = LibraryViewModel()
        await model.load(repository)
        model.tag = "Reading"
        model.sortChanged()
        XCTAssertEqual(model.visible.map(\.id), [tagged.id])

        try await repository.delete(id: tagged.id)
        await model.load(repository)
        XCTAssertEqual(model.tag, "All tags")
        XCTAssertEqual(model.visible.map(\.id), [retained.id])
    }

    func testRetainedTagSurvivesReload() async throws {
        let repository = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repository.upsert(.init(english: "cat", chinese: "猫", tags: ["Reading"]), now: Date())
        let model = LibraryViewModel()
        model.tag = "Reading"
        await model.load(repository)
        XCTAssertEqual(model.tag, "Reading")
        XCTAssertEqual(model.visible.map(\.id), [entry.id])
    }

    func testDueFilterUpdatesAsTimePassesWithoutReloadOrScheduleChanges() async throws {
        let repository = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let now = Date()
        let later = now.addingTimeInterval(120)
        let entry = try await repository.upsert(.init(english: "cat", chinese: "猫"), now: later)
        _ = try await repository.upsert(.init(english: "pending", chinese: ""), now: now)
        let before = try await repository.exportSnapshot()
        let model = LibraryViewModel()
        model.scope = .due
        await model.load(repository)
        model.refreshDue(now: now)
        XCTAssertTrue(model.visible.isEmpty)
        model.refreshDue(now: later)
        XCTAssertEqual(model.visible.map(\.id), [entry.id])
        let after = try await repository.exportSnapshot()
        XCTAssertEqual(before, after)
    }
}
