import XCTest
@testable import Vord

final class SpeakingConnectionsTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("speaking.json")
    }
    private func entry(_ english: String, lemma: String? = nil, archived: Bool = false) -> VocabularyEntry {
        VocabularyEntry(id: UUID(), english: english, chinese: "释义", lemma: lemma, tags: [],
            createdAt: Date(), updatedAt: Date(), archived: archived)
    }
    func testWholeWordPhrasesAndFlexibleFrames() {
        XCTAssertTrue(SpeakingConnections.contains("put ... into practice", in: "I put what I learned into practice."))
        XCTAssertTrue(SpeakingConnections.contains("eye-opener", in: "It’s an eye-opener."))
        XCTAssertFalse(SpeakingConnections.contains("rein", in: "Friends reinforce our confidence."))
        XCTAssertFalse(SpeakingConnections.contains("unwind", in: "An unwinding mechanism."))
        XCTAssertTrue(SpeakingConnections.contains("in common", in: "We have something in common."))
    }
    func testLinksCurrentVocabularyAndLemmaWithoutArchivedEntries() {
        let material = SpeakingMaterial(title: "Film", english: "These videos condense a film into a short summary.")
        let words = [entry("condense"), entry("videos", lemma: "video"), entry("rein"), entry("film", archived: true)]
        let linked = SpeakingConnections.linkedEntries(material, entries: words)
        XCTAssertEqual(linked.map(\.english), ["condense", "videos"])
        XCTAssertTrue(SpeakingConnections.matches(entry("unwinding", lemma: "unwind"), material: SpeakingMaterial(title: "Rest", english: "I unwind at home.")))
        XCTAssertFalse(SpeakingConnections.matches(entry("reliable sources"), material: SpeakingMaterial(title: "Posts", english: "Not every post is reliable.")))
    }
    func testRecommendationsRequireActualWordConnectionAndPreferOverlap() {
        let a = SpeakingMaterial(title: "A", english: "I unwind after coursework.")
        let b = SpeakingMaterial(title: "B", english: "I unwind after work.")
        let unrelated = SpeakingMaterial(title: "Unrelated", english: "A nice meal.")
        let result = SpeakingConnections.recommendations(materials: [b, unrelated, a], entries: [entry("unwind"), entry("coursework")], revisitIDs: [b.id])
        XCTAssertEqual(result.map(\.id), [a.id, b.id])
        XCTAssertTrue(SpeakingConnections.recommendations(materials: [a], entries: [entry("rein")]).isEmpty)
    }
    @MainActor func testOwnWordsHavePracticeEvenWithoutPresetAndOpeningPersistsOnce() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = SpeakingLibrary(url: url)
        let word = entry("stagnant")
        let prompts = SpeakingConnections.studyPrompts(materials: library.materials, entries: [word])
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(prompts[0].prompt.contains("stagnant"))
        XCTAssertTrue(library.personal.isEmpty)
        let first = try library.preparePractice(prompts[0])
        let second = try library.preparePractice(prompts[0])
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(library.personal.count, 1)
        XCTAssertTrue(library.attempts.isEmpty)
        XCTAssertEqual(first.english, "stagnant")
        XCTAssertEqual(first.keywords?.first?.english, word.english)
    }
    func testOldJSONMissingKeywordsStillLoadsAndCuratedFramesAreAvailable() throws {
        let item = SpeakingMaterial(title: "Apply", english: "I put what I learned into practice.")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object.removeValue(forKey: "keywords")
        let decoded = try JSONDecoder().decode(SpeakingMaterial.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(SpeakingConnections.expressions(decoded).first?.english, "put ... into practice")
        var edited = decoded; edited.keywords = []
        XCTAssertTrue(SpeakingConnections.expressions(edited).isEmpty)
    }
    @MainActor func testEditableExpressionsPersistAndExport() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = SpeakingLibrary(url: url)
        let keys = SpeakingConnections.parseKeywords("unwind = 放松\nUNWIND = duplicate\nput ... into practice = 付诸实践")
        XCTAssertEqual(keys.count, 2)
        let item = SpeakingMaterial(title: "Apply", english: "I unwind and put new ideas into practice.", keywords: keys)
        try library.add([item])
        XCTAssertEqual(SpeakingLibrary(url: url).personal.first?.keywords, keys)
        XCTAssertEqual(try SpeakingPack.decode(library.exportData()).materials.first?.keywords, keys)
        var invalid = item; invalid.keywords = [SpeakingKeyword(english: "", chinese: "blank")]
        XCTAssertFalse(invalid.isValid)
    }
    func testAIImportRetainsExpressionsForVocabularyBridge() throws {
        let document = SpeakingDocument(name: "lesson", text: "unwind means 放松")
        let items = try SpeakingImport.decode("""
        {"materials":[{"title":"Relax","english":"I unwind at home.","keywords":[{"english":"unwind","chinese":"放松"}]}]}
        """, document: document, chunk: document.text)
        XCTAssertEqual(items.first?.keywords?.first?.english, "unwind")
        XCTAssertTrue(SpeakingImport.system.contains("multiword collocations"))
    }
    @MainActor func testExplicitUseAssessmentUpdatesOnlyProductiveDirectionOnce() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let now = Date(timeIntervalSince1970: 100000)
        let word = try await repo.upsert(.init(english: "unwind", chinese: "放松"), now: now)
        let beforeValue = try await repo.reviewState(entryID: word.id)
        let before = try XCTUnwrap(beforeValue)
        let material = SpeakingMaterial(title: "Rest", english: "Watching a comedy helps me unwind.")
        let review = SpeakingWordReview()
        XCTAssertTrue(review.savedIDs.isEmpty)
        try await review.save(entryID: word.id, rating: .good, material: material, repository: repo, scheduler: SimpleScheduler(), now: now)
        try await review.save(entryID: word.id, rating: .good, material: material, repository: repo, scheduler: SimpleScheduler(), now: now)
        let afterValue = try await repo.reviewState(entryID: word.id)
        let after = try XCTUnwrap(afterValue)
        XCTAssertEqual(before.state(for: .englishToChinese), after.state(for: .englishToChinese))
        XCTAssertEqual(after.state(for: .chineseToEnglish)?.reviewCount, 1)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertEqual(snapshot.reviewLogs.count, 1)
        XCTAssertEqual(review.savedIDs, [word.id])
    }
    @MainActor func testUnrelatedAndArchivedWordsCannotReceiveSpeakingGrade() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let word = try await repo.upsert(.init(english: "rein", chinese: "缰绳"), now: Date())
        let review = SpeakingWordReview()
        do {
            try await review.save(entryID: word.id, rating: .good, material: SpeakingMaterial(title: "Rest", english: "I unwind."), repository: repo, scheduler: SimpleScheduler())
            XCTFail("Unrelated word must not be graded")
        } catch { }
        try await repo.setArchived(id: word.id, archived: true, now: Date())
        do {
            try await review.save(entryID: word.id, rating: .again, material: SpeakingMaterial(title: "Rein", english: "A rein."), repository: repo, scheduler: SimpleScheduler())
            XCTFail("Archived word must not be graded")
        } catch { }
        XCTAssertTrue(review.savedIDs.isEmpty)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertTrue(snapshot.reviewLogs.isEmpty)
    }
}
