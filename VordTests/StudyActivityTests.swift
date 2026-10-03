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
}
