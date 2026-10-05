import XCTest
@testable import Vord

final class StudyRoundTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_158_400)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func word(_ text: String) -> VocabularyEntry {
        VocabularyEntry(id: UUID(), english: text, chinese: "词", tags: [],
            createdAt: now.addingTimeInterval(-86400), updatedAt: now, archived: false)
    }
    private func snapshot(_ entries: [VocabularyEntry]) -> LibraryExport {
        LibraryExport(schemaVersion: 1, entries: entries,
            reviewStates: entries.map { .initial(entryID: $0.id, now: now) }, reviewLogs: [])
    }
    private func log(_ word: VocabularyEntry, at date: Date) -> ReviewLog {
        ReviewLog(id: UUID(), entryID: word.id, direction: .englishToChinese, rating: .good,
            reviewedAt: date, previousDueAt: nil, scheduledDueAt: date.addingTimeInterval(86400), interval: 86400)
    }

    func testFiveDistinctDueWordsExcludeArchivesMissingMeaningFutureAndMissingState() {
        let words = (0..<8).map { word("word\($0)") }
        var archived = word("archived"); archived.archived = true
        var missing = word("missing"); missing.chinese = ""
        let future = word("future"), orphan = word("no-state")
        var data = snapshot(words + [archived, missing, future, orphan])
        data.reviewStates.removeAll { $0.entryID == orphan.id }
        let index = data.reviewStates.firstIndex { $0.entryID == future.id }!
        data.reviewStates[index].directions = ReviewDirection.allCases.map {
            .initial(direction: $0, now: now.addingTimeInterval(3600))
        }
        let round = StudyRound.make(snapshot: data, now: now, calendar: calendar)
        XCTAssertEqual(round.entryIDs.count, 5)
        XCTAssertEqual(Set(round.entryIDs).count, 5)
        XCTAssertTrue(Set(round.entryIDs).isSubset(of: Set(words.map(\.id))))
    }

    func testUnseenWordsWinOverAlreadyPracticedWeakWordsAndGoalRemainderCapsRound() {
        let words = (0..<12).map { word("word\($0)") }
        var data = snapshot(words)
        data.reviewLogs = words.prefix(8).map { log($0, at: now) }
        // Previously answered words are still due in their other direction.
        for index in 0..<8 {
            data.reviewStates[index].directions[0].incorrectCount = 50
            data.reviewStates[index].directions[0].reviewCount = 50
        }
        let round = StudyRound.make(snapshot: data, dailyGoal: 10, now: now, calendar: calendar)
        XCTAssertEqual(round.entryIDs.count, 2)
        XCTAssertTrue(Set(round.entryIDs).isSubset(of: Set(words.suffix(4).map(\.id))))
        let beyondGoal = StudyRound.make(snapshot: data, dailyGoal: 8, now: now, calendar: calendar)
        XCTAssertEqual(beyondGoal.entryIDs.count, 5)
        XCTAssertEqual(Set(beyondGoal.entryIDs.prefix(4)), Set(words.suffix(4).map(\.id)))
    }

    func testDictationEvidenceCountsAndNextLocalDayMakesWordsFreshAgain() {
        let words = (0..<3).map { word("word\($0)") }
        let question = DictationQuestion(id: UUID(), entryID: words[0].id, prompt: "词",
            expected: words[0].english, accepted: [words[0].english], direction: .chineseToEnglish)
        let exam = ExamRecord(createdAt: now, mode: "Mixed", outcomes: [
            .init(question: question, attempt: "wrong but answered", correct: false)
        ])
        let data = snapshot(words), practice = [ExamPracticeRecord(exam)]
        let today = StudyRound.make(snapshot: data, practice: practice, dailyGoal: 2, now: now, calendar: calendar)
        XCTAssertEqual(today.entryIDs.count, 1)
        XCTAssertNotEqual(today.entryIDs.first, words[0].id)
        let tomorrow = StudyRound.make(snapshot: data, practice: practice, dailyGoal: 2,
            now: now.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(tomorrow.entryIDs.count, 2)
    }

    func testSummaryDoesNotCallMixedDirectionsMasteredOrCountAWordTwice() {
        let first = word("first"), second = word("second"), third = word("third")
        let result = ReviewRoundSummary(answers: [
            .init(entry: first, rating: .good), .init(entry: first, rating: .again),
            .init(entry: second, rating: .hard), .init(entry: second, rating: .easy),
            .init(entry: third, rating: .good)
        ])
        XCTAssertEqual(result.practicedCount, 3)
        XCTAssertEqual(Set(result.recalled.map(\.id)), Set([second.id, third.id]))
        XCTAssertEqual(result.revisit.map(\.id), [first.id])
    }

    @MainActor
    func testShortRoundLoadingDoesNotWriteAndAgainRemainsUnresolvedAtExit() async throws {
        let repository = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let time = Date().addingTimeInterval(-60)
        var ids: [UUID] = []
        for index in 0..<7 {
            let entry = try await repository.upsert(.init(english: "word\(index)", chinese: "词"), now: time)
            ids.append(entry.id)
        }
        let before = try await repository.exportSnapshot()
        let model = ReviewViewModel(repository: repository, scheduler: SimpleScheduler(), mode: .mixed,
            plannedEntryIDs: ids, shortRound: true)
        await model.load()
        XCTAssertEqual(model.total, 5)
        XCTAssertEqual(model.roundSummary.practicedCount, 0)
        let loaded = try await repository.exportSnapshot()
        XCTAssertEqual(before, loaded)
        // Three explicit Again ratings consume one word but do not recall it.
        let target = try XCTUnwrap(model.card?.entry.id)
        while !model.isEmpty {
            let rating: ReviewRating = model.card?.entry.id == target ? .again : .good
            model.reveal(); await model.rate(rating)
        }
        XCTAssertEqual(model.roundSummary.practicedCount, 5)
        XCTAssertEqual(model.roundSummary.recalled.count, 4)
        XCTAssertEqual(model.roundSummary.revisit.map(\.id), [target])
        let after = try await repository.exportSnapshot()
        XCTAssertEqual(after.reviewLogs.count, 7)
        XCTAssertEqual(after.reviewLogs.filter { $0.entryID == target && $0.rating == .again }.count, 3)
    }
}
