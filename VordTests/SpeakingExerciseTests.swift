import XCTest
@testable import Vord

final class SpeakingExerciseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    func testPartTwoTransitionsAtExactDeadlinesWithoutFakeClockDrift() {
        var exercise = SpeakingExercise(part: .two)
        XCTAssertEqual(exercise.phase, .ready)
        XCTAssertFalse(exercise.canRecord)
        exercise.prepare(at: start)
        exercise.advance(to: start.addingTimeInterval(59))
        XCTAssertEqual(exercise.phase, .preparing)
        XCTAssertEqual(exercise.remaining(at: start.addingTimeInterval(59)), 1)
        exercise.advance(to: start.addingTimeInterval(65))
        XCTAssertEqual(exercise.phase, .speaking)
        XCTAssertEqual(exercise.speakingStartedAt, start.addingTimeInterval(60))
        XCTAssertEqual(exercise.remaining(at: start.addingTimeInterval(65)), 115)
        exercise.advance(to: start.addingTimeInterval(180))
        XCTAssertEqual(exercise.phase, .finished)
        XCTAssertEqual(exercise.spokenSeconds, 120)
        XCTAssertTrue(exercise.canRecord)
        exercise.advance(to: start.addingTimeInterval(600))
        XCTAssertEqual(exercise.spokenSeconds, 120)
    }
    func testEarlyFinishDoesNotCountPreparationOrReflectionAsSpeaking() {
        var exercise = SpeakingExercise(part: .one)
        exercise.prepare(at: start)
        exercise.beginSpeaking(at: start.addingTimeInterval(4))
        exercise.finish(at: start.addingTimeInterval(18))
        XCTAssertEqual(exercise.spokenSeconds, 14)
        exercise.finish(at: start.addingTimeInterval(90))
        XCTAssertEqual(exercise.spokenSeconds, 14)
        XCTAssertTrue(exercise.canRecord)
    }
    func testInvalidTransitionsAndInstantFinishCannotCreatePracticeEvidence() {
        var exercise = SpeakingExercise(part: .three)
        exercise.beginSpeaking(at: start); exercise.finish(at: start); exercise.reveal()
        XCTAssertEqual(exercise.phase, .ready)
        XCTAssertFalse(exercise.referenceRevealed)
        exercise.prepare(at: start); exercise.beginSpeaking(at: start); exercise.finish(at: start)
        XCTAssertEqual(exercise.spokenSeconds, 0)
        XCTAssertFalse(exercise.canRecord)
        exercise.beginSpeaking(at: start.addingTimeInterval(5))
        XCTAssertEqual(exercise.phase, .finished)
    }
    @MainActor func testTimerExpiryAndReferenceViewingDoNotSaveOrRateAnything() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("materials.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        var exercise = SpeakingExercise(part: .two)
        exercise.prepare(at: start); exercise.reveal(); exercise.advance(to: start.addingTimeInterval(181))
        XCTAssertTrue(exercise.referenceRevealed)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @MainActor func testRevisitFilterUsesLatestDatedSelfReportAndRetainsHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("materials.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        let item = try XCTUnwrap(store.materials.first)
        var again = SpeakingAttempt(materialID: item.id, question: item.prompt, answer: "", outcome: .revisit, seconds: 20, referenceRevealed: true, createdAt: start)
        try store.record(again)
        XCTAssertEqual(store.revisitIDs, [item.id])
        var good = again; good.id = UUID(); good.outcome = .recalled; good.createdAt = start.addingTimeInterval(60)
        try store.record(good)
        XCTAssertTrue(store.revisitIDs.isEmpty)
        again.id = UUID(); again.createdAt = start.addingTimeInterval(30)
        try store.record(again) // Late arrival of an older attempt cannot reverse the newer outcome.
        XCTAssertTrue(store.revisitIDs.isEmpty)
        XCTAssertEqual(store.attempts.count, 3)
        XCTAssertTrue(SpeakingLibrary(url: url).revisitIDs.isEmpty)
    }
}
