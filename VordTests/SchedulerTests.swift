import XCTest
@testable import Vord

final class SchedulerTests: XCTestCase {
    private let scheduler = SimpleScheduler()

    func testFirstGoodIsOneDay() {
        let now = Date(timeIntervalSince1970: 1_759_392_000)
        let state = ReviewState.initial(entryID: UUID(), now: now)
        let result = scheduler.schedule(state: state, direction: .englishToChinese, rating: .good, now: now)
        let updated = result.state.state(for: .englishToChinese)
        XCTAssertEqual(updated?.interval ?? 0, 86_400, accuracy: 1)
        XCTAssertEqual(updated?.stability ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(updated?.stage, 1)
        XCTAssertEqual(result.log.scheduledDueAt.timeIntervalSince(now), 86_400, accuracy: 1)
    }

    func testFirstAgainIsTenMinutesAndCountsALapse() {
        let now = Date()
        let state = ReviewState.initial(entryID: UUID(), now: now)
        let result = scheduler.schedule(state: state, direction: .chineseToEnglish, rating: .again, now: now)
        let updated = result.state.state(for: .chineseToEnglish)
        XCTAssertEqual(updated?.interval ?? 0, 600, accuracy: 0.1)
        XCTAssertEqual(updated?.lapseCount, 1)
        XCTAssertEqual(updated?.incorrectCount, 1)
        XCTAssertEqual(updated?.stage, 0)
    }

    func testGoodThenGoodGrows() {
        let now = Date()
        let state = ReviewState.initial(entryID: UUID(), now: now)
        let first = scheduler.schedule(state: state, direction: .englishToChinese, rating: .good, now: now)
        let second = scheduler.schedule(state: first.state, direction: .englishToChinese, rating: .good, now: now)
        XCTAssertEqual(second.state.state(for: .englishToChinese)?.stability ?? 0, 2.3, accuracy: 0.001)
    }

    func testEasyGrowsFasterThanHard() {
        let now = Date()
        let state = ReviewState.initial(entryID: UUID(), now: now)
        let learned = scheduler.schedule(state: state, direction: .englishToChinese, rating: .good, now: now).state
        let hard = scheduler.schedule(state: learned, direction: .englishToChinese, rating: .hard, now: now)
        let easy = scheduler.schedule(state: learned, direction: .englishToChinese, rating: .easy, now: now)
        XCTAssertGreaterThan(easy.state.state(for: .englishToChinese)?.stability ?? 0, hard.state.state(for: .englishToChinese)?.stability ?? 0)
    }

    func testDirectionsAreIndependent() {
        let now = Date()
        let state = ReviewState.initial(entryID: UUID(), now: now)
        let result = scheduler.schedule(state: state, direction: .englishToChinese, rating: .good, now: now)
        XCTAssertEqual(result.state.state(for: .chineseToEnglish)?.reviewCount, 0)
        XCTAssertEqual(result.state.state(for: .englishToChinese)?.reviewCount, 1)
    }
}
