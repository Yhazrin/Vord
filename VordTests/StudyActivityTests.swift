import XCTest
@testable import Vord

final class StudyActivityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!; value.firstWeekday = 2
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func entry(_ created: Date) -> VocabularyEntry {
        .init(id: UUID(), english: "word", chinese: "词", tags: [], createdAt: created, updatedAt: created, archived: false)
    }
    private func log(_ id: UUID, at time: Date, direction: ReviewDirection = .englishToChinese) -> ReviewLog {
        .init(id: UUID(), entryID: id, direction: direction, rating: .good, reviewedAt: time, previousDueAt: nil, scheduledDueAt: time.addingTimeInterval(86400), interval: 86400)
    }
    func testDailySquaresCountDistinctWordsAcrossDirectionsAndAdding() {
        let now = date(2026, 10, 3)
        let first = entry(now), second = entry(date(2026, 10, 2))
        let logs = [log(first.id, at: now), log(first.id, at: now, direction: .chineseToEnglish), log(second.id, at: now), log(second.id, at: now)]
        let snapshot = LibraryExport(schemaVersion: 1, entries: [first, second], reviewStates: [], reviewLogs: logs)
        let activity = StudyActivity(snapshot: snapshot, now: now, calendar: calendar)
        XCTAssertEqual(activity.day(now).count, 2)
        XCTAssertEqual(activity.day(now).added.count, 1)
        XCTAssertEqual(activity.day(now).reviewed.count, 2)
        XCTAssertEqual(activity.activeDays(in: activity.interval(.month, anchor: now)), 2)
        XCTAssertEqual(activity.uniqueWords(in: activity.interval(.month, anchor: now)), 2)
    }
    func testLeapYearAndDSTKeepEveryCalendarDayExactlyOnce() {
        let snapshot = LibraryExport(schemaVersion: 1, entries: [], reviewStates: [], reviewLogs: [])
        let activity = StudyActivity(snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(activity.dates(in: activity.interval(.year, anchor: date(2024, 5, 1))).count, 366)
        let march = activity.dates(in: activity.interval(.month, anchor: date(2026, 3, 1)))
        XCTAssertEqual(march.count, 31)
        XCTAssertEqual(Set(march).count, 31)
        XCTAssertTrue(zip(march, march.dropFirst()).contains { $1.timeIntervalSince($0) == 23 * 3600 })
        let weeks = activity.weeks(in: activity.interval(.year, anchor: date(2024, 1, 1)))
        XCTAssertEqual(weeks.flatMap { $0.compactMap { $0 } }.count, 366)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }
    func testLocalDayBoundariesFutureRecordsAndOrphans() {
        let now = date(2026, 10, 3)
        let word = entry(date(2026, 10, 2))
        let snapshot = LibraryExport(schemaVersion: 1, entries: [word, entry(date(2026, 10, 5))], reviewStates: [], reviewLogs: [log(word.id, at: date(2026, 10, 2, 23)), log(word.id, at: date(2026, 10, 3, 0)), log(word.id, at: date(2026, 10, 5)), log(UUID(), at: now)])
        let activity = StudyActivity(snapshot: snapshot, now: now, calendar: calendar)
        XCTAssertEqual(activity.day(now).count, 1)
        XCTAssertEqual(activity.day(date(2026, 10, 2)).count, 1)
        XCTAssertEqual(activity.day(date(2026, 10, 5)).count, 0)
        XCTAssertEqual(activity.dates(in: activity.interval(.week, anchor: now)).count, 7)
    }

    func testPracticeGoalDeduplicatesReviewAndDictationAndExcludesAddsSkipsAndFuture() {
        let now = date(2026, 10, 3)
        let reviewed = entry(date(2026, 10, 1)), practiced = entry(date(2026, 10, 1)), skipped = entry(now)
        func outcome(_ word: VocabularyEntry, attempt: String) -> DictationOutcome {
            .init(question: .init(id: UUID(), entryID: word.id, prompt: "词", expected: word.english,
                                 accepted: [word.english], direction: .chineseToEnglish), attempt: attempt, correct: false)
        }
        let exams = [ExamRecord(createdAt: now, mode: "Mixed", outcomes: [
            outcome(reviewed, attempt: "wrong"), outcome(practiced, attempt: "wrong"),
            outcome(practiced, attempt: "wrong again"), outcome(skipped, attempt: "  ")
        ]), ExamRecord(createdAt: date(2026, 10, 5), mode: "Mixed", outcomes: [outcome(skipped, attempt: "word")])]
        let snapshot = LibraryExport(schemaVersion: 1, entries: [reviewed, practiced, skipped], reviewStates: [],
                                    reviewLogs: [log(reviewed.id, at: now)])
        let activity = StudyActivity(snapshot: snapshot, exams: exams, now: now, calendar: calendar)
        XCTAssertEqual(activity.day(now).practicedWords, Set([reviewed.id, practiced.id]))
        XCTAssertEqual(activity.day(now).count, 3)
        XCTAssertEqual(activity.day(date(2026, 10, 5)).count, 0)
    }

    func testOldExamBackupsWithoutEntryIDsStillDecodeAndMatchEnglishOnly() throws {
        let now = date(2026, 10, 3)
        var word = entry(date(2026, 10, 1)); word.english = "stagnant"
        let question = DictationQuestion(id: UUID(), prompt: "停滞的", expected: "STAGNANT", accepted: ["stagnant"], direction: .chineseToEnglish)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(question)) as? [String: Any])
        object.removeValue(forKey: "entryID")
        let decoded = try JSONDecoder().decode(DictationQuestion.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.entryID)
        let exam = ExamRecord(createdAt: now, mode: "Chinese → English", outcomes: [.init(question: decoded, attempt: "stagnent", correct: false)])
        let snapshot = LibraryExport(schemaVersion: 1, entries: [word], reviewStates: [], reviewLogs: [])
        XCTAssertEqual(StudyActivity(snapshot: snapshot, exams: [exam], now: now, calendar: calendar).day(now).practicedWords, [word.id])
    }

    func testPracticeStreakAcrossDSTAndUnfinishedToday() {
        let now = date(2026, 3, 9), word = entry(date(2026, 3, 1))
        var snapshot = LibraryExport(schemaVersion: 1, entries: [word], reviewStates: [],
                                    reviewLogs: [log(word.id, at: date(2026, 3, 7)), log(word.id, at: date(2026, 3, 8))])
        XCTAssertEqual(StudyActivity(snapshot: snapshot, now: now, calendar: calendar).practiceStreak, 2)
        snapshot.reviewLogs.append(log(word.id, at: now))
        XCTAssertEqual(StudyActivity(snapshot: snapshot, now: now, calendar: calendar).practiceStreak, 3)
        XCTAssertEqual(StudyActivity(snapshot: snapshot, now: date(2026, 3, 11), calendar: calendar).practiceStreak, 0)
        let onlyAdds = LibraryExport(schemaVersion: 1, entries: [entry(now)], reviewStates: [], reviewLogs: [])
        XCTAssertEqual(StudyActivity(snapshot: onlyAdds, now: now, calendar: calendar).practiceStreak, 0)
    }

    @MainActor func testDailyPracticeGoalPersistsAndClampsInIsolatedDefaults() throws {
        let suite = "VordTests.daily-goal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let translation = TranslationService(selectedID: "local")
        let settings = AppSettings(defaults: defaults, translation: translation)
        XCTAssertEqual(settings.dailyPracticeGoal, 10)
        settings.setDailyPracticeGoal(24)
        XCTAssertEqual(AppSettings(defaults: defaults, translation: translation).dailyPracticeGoal, 24)
        settings.setDailyPracticeGoal(0)
        XCTAssertEqual(settings.dailyPracticeGoal, 1)
        settings.setDailyPracticeGoal(1000)
        XCTAssertEqual(settings.dailyPracticeGoal, 100)
    }

    @MainActor func testPracticeEvidenceSurvivesExamHistoryLimitAndReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.json")
        let history = LearningHistory(url: url), now = date(2026, 10, 3)
        let words = (0..<101).map { _ in entry(date(2026, 10, 1)) }
        for word in words {
            let question = DictationQuestion(id: UUID(), entryID: word.id, prompt: "词", expected: word.english,
                                             accepted: [word.english], direction: .chineseToEnglish)
            try history.append(ExamRecord(createdAt: now, mode: "Mixed", outcomes: [.init(question: question, attempt: "wrong", correct: false)]))
        }
        let reopened = LearningHistory(url: url)
        XCTAssertEqual(reopened.exams.count, 100)
        XCTAssertEqual(reopened.practice.count, 101)
        let snapshot = LibraryExport(schemaVersion: 1, entries: words, reviewStates: [], reviewLogs: [])
        let activity = StudyActivity(snapshot: snapshot, practice: reopened.practice, now: now, calendar: calendar)
        XCTAssertEqual(activity.day(now).practicedWords.count, 101)
    }
}
