import XCTest
@testable import Vord

final class LearningAgentTests: XCTestCase {
    private func repository() throws -> SQLiteVocabularyRepository {
        SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
    }
    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("assistant.json") }

    func testProfileUsesAllWordsButBoundsContextAndExcludesArchived() async throws {
        let repo = try repository(), now = Date()
        for index in 0..<30 { _ = try await repo.upsert(.init(english: "word\(index)", chinese: "词\(index)"), now: now) }
        let archived = try await repo.upsert(.init(english: "archived", chinese: "归档"), now: now)
        try await repo.setArchived(id: archived.id, archived: true, now: now)
        _ = try await repo.upsert(.init(english: "empty", chinese: ""), now: now)
        let profile = LearningProfile(snapshot: try await repo.exportSnapshot(), now: now.addingTimeInterval(1))
        XCTAssertEqual(profile.entries.count, 30)
        XCTAssertEqual(profile.dueWords, 30)
        XCTAssertEqual(profile.dueDirections, 60)
        let context = try profile.context(question: "What is word29?")
        let data = try XCTUnwrap(context.data(using: .utf8))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(parsed["activeWords"] as? Int, 30)
        let words = try XCTUnwrap(parsed["sampledWords"] as? [[String: Any]])
        XCTAssertEqual(words.count, 24)
        XCTAssertEqual(words.first?["word"] as? String, "word29")
        XCTAssertFalse(words.contains { $0["word"] as? String == "archived" })
    }

    func testPlanLimitsSpreadsOverdueAndKeepsFutureDatesAndCurve() async throws {
        let repo = try repository(), now = Date()
        for index in 0..<18 { _ = try await repo.upsert(.init(english: "term\(index)", chinese: "单词"), now: now) }
        var snapshot = try await repo.exportSnapshot()
        let futureID = snapshot.entries.first!.id
        let future = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        for index in snapshot.reviewStates.indices where snapshot.reviewStates[index].entryID == futureID {
            for direction in snapshot.reviewStates[index].directions.indices { snapshot.reviewStates[index].directions[direction].dueAt = future }
        }
        let profile = LearningProfile(snapshot: snapshot, now: now)
        let plan = StudyPlan.make(profile: profile, dailyLimit: 1)
        XCTAssertEqual(plan.dailyLimit, 5)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertTrue(plan.days.allSatisfy { $0.entryIDs.count <= 5 })
        XCTAssertEqual(Set(plan.days.flatMap(\.entryIDs)).count, 18)
        XCTAssertTrue(plan.days.prefix(3).allSatisfy { !$0.entryIDs.contains(futureID) })
        XCTAssertTrue(plan.days[3].entryIDs.contains(futureID))
        let after = try await repo.exportSnapshot()
        XCTAssertEqual(after.reviewLogs.count, 0)
        XCTAssertEqual(after.reviewStates.flatMap(\.directions).filter { $0.reviewCount != 0 }.count, 0)
    }

    @MainActor
    func testQuizDrawRevealAndDuplicateRatingOnlyExplicitReviewChangesState() async throws {
        let repo = try repository(), now = Date()
        _ = try await repo.upsert(.init(english: "stagnant", chinese: "停滞的"), now: now)
        let quiz = IslandQuizModel(repository: repo, scheduler: SimpleScheduler())
        await quiz.next()
        quiz.answer = "slow"
        await quiz.record(.good)
        var snapshot = try await repo.exportSnapshot()
        XCTAssertTrue(snapshot.reviewLogs.isEmpty)
        quiz.reveal()
        await quiz.record(.good)
        await quiz.record(.easy)
        snapshot = try await repo.exportSnapshot()
        XCTAssertEqual(snapshot.reviewLogs.count, 1)
        XCTAssertTrue(quiz.recorded)
        XCTAssertEqual(quiz.completed, 1)
        quiz.changeDirection(.chineseToEnglish)
        quiz.reveal(); await quiz.record(.good)
        XCTAssertEqual(quiz.completed, 2)
        quiz.changeDirection(.englishToChinese)
        quiz.reveal(); await quiz.record(.easy)
        XCTAssertEqual(quiz.completed, 2)
        await quiz.next()
        XCTAssertFalse(quiz.revealed)
        XCTAssertFalse(quiz.recorded)
    }

    @MainActor
    func testDeletedOrChangedQuizCannotRecordOldAnswer() async throws {
        let repo = try repository()
        let entry = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        let quiz = IslandQuizModel(repository: repo, scheduler: SimpleScheduler())
        await quiz.next(); quiz.reveal()
        var changed = entry; changed.chinese = "猫科动物"
        try await repo.update(changed)
        await quiz.record(.good)
        XCTAssertFalse(quiz.revealed)
        XCTAssertNotNil(quiz.error)
        quiz.reveal(); try await repo.delete(id: entry.id)
        await quiz.record(.good)
        XCTAssertFalse(quiz.recorded)
        XCTAssertNotNil(quiz.error)
    }

    @MainActor
    func testAgentConversationGroundingAndPlanPersistenceWithoutReviewWrites() async throws {
        let repo = try repository(), url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try await repo.upsert(.init(english: "stagnant", chinese: "停滞的"), now: Date())
        var capturedPrompt = "", capturedSystem = ""
        let agent = LearningAgent(repository: repo, url: url, providerName: { "Test" }) { prompt, system in
            capturedPrompt = prompt; capturedSystem = system
            return AITextResponse(text: "今天先复习 stagnant。", modelID: "stub")
        }
        agent.send("今天先看什么？")
        while agent.isThinking { await Task.yield() }
        XCTAssertEqual(agent.messages.count, 2)
        XCTAssertTrue(capturedPrompt.contains("stagnant"))
        XCTAssertTrue(capturedPrompt.contains("\"dueWords\":1"))
        XCTAssertTrue(capturedSystem.contains("Only the user can record a rating"))
        XCTAssertEqual(agent.messages.last?.provider, "Test · stub")
        await agent.proposePlan(dailyLimit: 15)
        XCTAssertNotNil(agent.proposedPlan)
        XCTAssertNil(agent.plan)
        agent.adoptPlan()
        XCTAssertNotNil(agent.plan)
        let restored = LearningAgent(repository: repo, url: url) { _, _ in throw AIError.noProvider }
        XCTAssertEqual(restored.messages, agent.messages)
        XCTAssertEqual(restored.plan, agent.plan)
        let after = try await repo.exportSnapshot()
        XCTAssertTrue(after.reviewLogs.isEmpty)
        XCTAssertEqual(after.reviewStates.flatMap(\.directions).filter { $0.reviewCount > 0 }.count, 0)
    }

    @MainActor
    func testRequestFailureKeepsQuestionForRetryAndDoesNotInventReply() async throws {
        let repo = try repository(), url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var attempts = 0
        let agent = LearningAgent(repository: repo, url: url) { _, _ in
            attempts += 1
            if attempts == 1 { throw AIError.noProvider }
            return AITextResponse(text: "Connected", modelID: "test")
        }
        agent.send("Review")
        while agent.isThinking { await Task.yield() }
        XCTAssertEqual(agent.messages.count, 1)
        XCTAssertNotNil(agent.error)
        agent.retry()
        while agent.isThinking { await Task.yield() }
        XCTAssertEqual(agent.messages.count, 2)
        XCTAssertEqual(agent.messages.first?.text, "Review")
        XCTAssertNil(agent.error)
    }

    func testAgainDoesNotCompletePlanAndArchivedWordsAreRemoved() async throws {
        let repo = try repository(), now = Date()
        let entry = try await repo.upsert(.init(english: "stagnant", chinese: "停滞的"), now: now)
        let profile = LearningProfile(snapshot: try await repo.exportSnapshot(), now: now)
        let plan = StudyPlan.make(profile: profile, dailyLimit: 10)
        let storedState = try await repo.reviewState(entryID: entry.id)
        let state = try XCTUnwrap(storedState)
        try await repo.recordReview(SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .again, now: now.addingTimeInterval(1)))
        let afterAgain = LearningProfile(snapshot: try await repo.exportSnapshot(), now: now.addingTimeInterval(2))
        XCTAssertEqual(plan.remaining(day: plan.days[0], profile: afterAgain), [entry.id])
        try await repo.setArchived(id: entry.id, archived: true, now: now.addingTimeInterval(3))
        let afterArchive = LearningProfile(snapshot: try await repo.exportSnapshot(), now: now.addingTimeInterval(4))
        XCTAssertTrue(plan.remaining(day: plan.days[0], profile: afterArchive).isEmpty)
    }

    @MainActor
    func testPlanReviewOnlySelectedEligibleWordsAndPreservesNormalQueue() async throws {
        let repo = try repository()
        let selected = try await repo.upsert(.init(english: "cat", chinese: "猫"), now: Date())
        _ = try await repo.upsert(.init(english: "dog", chinese: "狗"), now: Date())
        let planned = ReviewViewModel(repository: repo, scheduler: SimpleScheduler(), mode: .mixed, plannedEntryIDs: [selected.id, selected.id, UUID()])
        await planned.load()
        XCTAssertEqual(planned.total, 1)
        XCTAssertEqual(planned.card?.entry.id, selected.id)
        let normal = ReviewViewModel(repository: repo, scheduler: SimpleScheduler(), mode: .mixed)
        await normal.load()
        XCTAssertEqual(normal.total, 4)
    }
}

extension LearningAgentTests {
    @MainActor
    func testPlanStartRefreshesAndDoesNotReviewFutureWordsEarly() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let entry = try await repo.upsert(.init(english: "future", chinese: "未来"), now: Date().addingTimeInterval(3600))
        let planned = ReviewViewModel(repository: repo, scheduler: SimpleScheduler(), mode: .mixed, plannedEntryIDs: [entry.id])
        await planned.load()
        XCTAssertEqual(planned.total, 0)
        XCTAssertNil(planned.card)
        let after = try await repo.exportSnapshot()
        XCTAssertTrue(after.reviewLogs.isEmpty)
    }
}

extension LearningAgentTests {
    func testMissedPlanWordsCarryWithinTargetAndKeepTodayProgress() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        for index in 0..<8 { _ = try await repo.upsert(.init(english: "carry\(index)", chinese: "词"), now: start) }
        let first = LearningProfile(snapshot: try await repo.exportSnapshot(), now: start.addingTimeInterval(1))
        let plan = StudyPlan.make(profile: first, dailyLimit: 5)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        var profile = LearningProfile(snapshot: try await repo.exportSnapshot(), now: tomorrow)
        let carried = plan.displayDay(plan.days[1], profile: profile)
        XCTAssertEqual(carried.entryIDs, plan.days[0].entryIDs)
        XCTAssertEqual(carried.entryIDs.count, 5)
        let id = carried.entryIDs[0]
        let stored = try await repo.reviewState(entryID: id)
        let state = try XCTUnwrap(stored)
        try await repo.recordReview(SimpleScheduler().schedule(state: state, direction: .englishToChinese, rating: .good, now: tomorrow))
        profile = LearningProfile(snapshot: try await repo.exportSnapshot(), now: tomorrow.addingTimeInterval(1))
        let updated = plan.displayDay(plan.days[1], profile: profile)
        XCTAssertEqual(updated.entryIDs, carried.entryIDs)
        XCTAssertEqual(plan.remaining(day: updated, profile: profile).count, 4)
    }
}
