import XCTest
@testable import Vord

final class AgentLiveIntegrationTests: XCTestCase {
    @MainActor
    func testConfiguredProviderExtractsAndImportsVocabulary() async throws {
        guard ProcessInfo.processInfo.environment["VORD_AGENT_IMPORT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live import check is opt-in.")
        }
        let ai = AIConfigurationStore()
        guard ai.selected != nil else { throw XCTSkip("No AI provider configured.") }
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("assistant.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let agent = LearningAgent(repository: repo, url: url) { prompt, system in
            try await ai.generate(prompt: prompt, system: system)
        }
        agent.send("帮我把这三个词添加到生词库，补充中英文释义：stagnant、plight、mitigate。")
        while agent.isThinking { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(agent.error)
        let message = try XCTUnwrap(agent.messages.last)
        let proposal = try XCTUnwrap(message.wordImport)
        XCTAssertEqual(Set(proposal.items.map { $0.english.lowercased() }), Set(["stagnant", "plight", "mitigate"]))
        XCTAssertTrue(proposal.items.allSatisfy { !$0.chinese.isEmpty && $0.englishDefinition?.isEmpty == false })
        let before = try await repo.exportSnapshot()
        XCTAssertTrue(before.entries.isEmpty)
        await agent.importWords(messageID: message.id)
        let after = try await repo.exportSnapshot()
        XCTAssertEqual(after.entries.count, 3)
        XCTAssertTrue(after.reviewLogs.isEmpty)
    }

    @MainActor
    func testConfiguredProviderAnswersGroundedQuestion() async throws {
        guard ProcessInfo.processInfo.environment["VORD_AGENT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live provider check is opt-in.")
        }
        let ai = AIConfigurationStore()
        guard ai.selected != nil else { throw XCTSkip("No AI provider configured.") }
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        _ = try await repo.upsert(.init(english: "stagnant", chinese: "停滞的"), now: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("assistant.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let agent = LearningAgent(repository: repo, url: url, providerName: { ai.selected?.name ?? "AI" }) { prompt, system in
            try await ai.generate(prompt: prompt, system: system)
        }
        agent.send("请只用两句话回答：我有几个待复习的单词？再用 stagnant 写一句简单的英文例句。")
        while agent.isThinking { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(agent.error)
        XCTAssertEqual(agent.messages.count, 2)
        XCTAssertTrue(agent.messages.last?.text.lowercased().contains("stagnant") == true)
        let after = try await repo.exportSnapshot()
        XCTAssertTrue(after.reviewLogs.isEmpty)
    }
}
