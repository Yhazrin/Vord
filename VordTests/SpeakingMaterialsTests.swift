import XCTest
@testable import Vord

final class SpeakingMaterialsTests: XCTestCase {
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("materials.json") }
    @MainActor func testStarterPackIsOfflineStableAndNotWrittenOnLoad() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url), second = SpeakingLibrary(url: url)
        XCTAssertEqual(store.materials.count, 26)
        XCTAssertEqual(store.materials.map(\.id), second.materials.map(\.id))
        XCTAssertTrue(store.materials.allSatisfy(\.isValid))
        XCTAssertTrue(store.materials.contains { $0.kind == .story && $0.part == .two })
        XCTAssertTrue(store.materials.contains { $0.kind == .angle && $0.part == .three })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @MainActor func testBilingualImportPersistenceAndExportRetainOriginal() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        let source = "A tutorial caught my attention.\n一个教程吸引了我。\n\nI put it into practice. = 我把它用于实践。"
        let pack = try SpeakingImport.local(text: source, name: "lesson.txt")
        XCTAssertEqual(pack.materials.count, 2)
        XCTAssertEqual(pack.materials[0].chinese, "一个教程吸引了我。")
        XCTAssertEqual(try store.add(pack.materials, documents: pack.documents), 2)
        let reopened = SpeakingLibrary(url: url)
        XCTAssertEqual(reopened.personal.count, 2)
        XCTAssertEqual(reopened.documents.first?.text, source)
        let exported = try SpeakingPack.decode(store.exportData())
        XCTAssertEqual(exported.materials.count, 28)
        XCTAssertEqual(exported.documents, pack.documents)
    }
    @MainActor func testDuplicatesAndIDCollisionsDoNotOverwrite() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        var a = SpeakingMaterial(title: "Test", english: "Take a short break.")
        XCTAssertEqual(try store.add([a]), 1)
        a.english = "  TAKE   A short break.  "
        XCTAssertEqual(try store.add([a]), 0)
        a.english = "Take a longer break."
        XCTAssertEqual(try store.add([a]), 1)
        XCTAssertEqual(Set(store.materials.map(\.id)).count, store.materials.count)
        XCTAssertEqual(store.personal.count, 2)
    }
    @MainActor func testEditingPresetCreatesPersistentOverride() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        var first = try XCTUnwrap(store.materials.first)
        first.english = "Friends help me feel at home."
        try store.update(first)
        let second = SpeakingLibrary(url: url)
        XCTAssertEqual(second.materials.count, 26)
        XCTAssertEqual(second.materials.first { $0.id == first.id }?.english, first.english)
    }
    @MainActor func testCorruptLibraryAndFailedSavePreserveState() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: url)
        let store = SpeakingLibrary(url: url)
        XCTAssertNotNil(store.warning)
        XCTAssertThrowsError(try store.add([SpeakingMaterial(title: "Test", english: "An example.")]))
        XCTAssertTrue(store.personal.isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid")
        let blocked = SpeakingLibrary(url: url.appendingPathComponent("cannot-write.json"))
        XCTAssertThrowsError(try blocked.add([SpeakingMaterial(title: "Test", english: "An example.")]))
        XCTAssertTrue(blocked.personal.isEmpty)
    }
    @MainActor func testMissingDocumentCannotBePersistedOrUpdated() throws {
        let store = SpeakingLibrary(url: location())
        var item = SpeakingMaterial(title: "Test", english: "An example.")
        item.sourceDocumentID = UUID()
        XCTAssertThrowsError(try store.add([item]))
        XCTAssertThrowsError(try store.update(item))
        XCTAssertTrue(store.personal.isEmpty)
    }
    func testPackRejectsUnknownSchemaDuplicateIDsAndDanglingSources() throws {
        let item = SpeakingMaterial(title: "Test", english: "An example.")
        let encoder = JSONEncoder()
        XCTAssertThrowsError(try SpeakingPack.decode(encoder.encode(SpeakingPack(schemaVersion: 2, materials: [item]))))
        XCTAssertThrowsError(try SpeakingPack.decode(encoder.encode(SpeakingPack(materials: [item, item]))))
        var invalid = item; invalid.sourceDocumentID = UUID()
        XCTAssertThrowsError(try SpeakingPack.decode(encoder.encode(SpeakingPack(materials: [invalid]))))
        XCTAssertThrowsError(try SpeakingImport.local(text: String(repeating: "a", count: 60001), name: "oversized"))
    }
    func testAIExcerptMustActuallyExistInSource() throws {
        let document = SpeakingDocument(name: "class", text: "老师讲了 unwind 来表达放松。")
        let raw = """
        {"materials":[{"title":"Unwind","english":"Watching a comedy helps me unwind.","sourceExcerpt":"老师讲了 unwind 来表达放松。"},{"title":"Invented","english":"It was an eye-opener.","sourceExcerpt":"fake quotation"}]}
        """
        let items = try SpeakingImport.decode(raw, document: document, chunk: document.text)
        XCTAssertEqual(items.first?.sourceExcerpt, document.text)
        XCTAssertNil(items.last?.sourceExcerpt)
        XCTAssertTrue(items.allSatisfy { $0.source.contains("AI adapted") })
        XCTAssertThrowsError(try SpeakingImport.decode("not JSON", document: document, chunk: document.text))
    }
    @MainActor func testLongAIImportChunksAndDeduplicatesBeforeAnyWrite() async throws {
        let store = SpeakingLibrary(url: location())
        let source = String(repeating: "lesson notes.\n", count: 1500)
        var calls = 0, sizes: [Int] = []
        let pack = try await SpeakingImport.analyze(text: source, name: "class.md") { prompt, _ in
            calls += 1; sizes.append(prompt.count)
            return AITextResponse(text: "{\"materials\":[{\"title\":\"Unwind\",\"english\":\"I need to unwind.\"}]}", modelID: "stub")
        }
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(sizes.allSatisfy { $0 < 9000 })
        XCTAssertEqual(pack.materials.count, 1)
        XCTAssertTrue(store.personal.isEmpty)
        XCTAssertEqual(pack.documents.first?.text, source)
    }
    @MainActor func testSpeakingSelfReportDoesNotChangeVocabularySchedule() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SpeakingLibrary(url: url)
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        _ = try await repo.upsert(.init(english: "unwind", chinese: "放松"), now: Date())
        let before = try await repo.exportSnapshot()
        let item = try XCTUnwrap(store.materials.first)
        let attempt = SpeakingAttempt(materialID: item.id, question: item.prompt, answer: "I couldn't recall it.", outcome: .revisit, seconds: 30, referenceRevealed: true)
        try store.record(attempt)
        let after = try await repo.exportSnapshot()
        XCTAssertEqual(before.entries, after.entries)
        XCTAssertEqual(before.reviewStates, after.reviewStates)
        XCTAssertEqual(before.reviewLogs, after.reviewLogs)
        XCTAssertEqual(SpeakingLibrary(url: url).attempts, [attempt])
        var invalid = attempt; invalid.seconds = 0
        XCTAssertThrowsError(try store.record(invalid))
        XCTAssertEqual(store.attempts.count, 1)
    }
    @MainActor func testCompanionReceivesRealSpeakingContextAndPreservesDraft() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = SpeakingLibrary(url: url)
        let item = try XCTUnwrap(library.materials.first)
        try library.record(SpeakingAttempt(materialID: item.id, question: item.prompt, answer: "My real answer", outcome: .revisit, seconds: 30, referenceRevealed: true))
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        var captured = ""
        let agent = LearningAgent(repository: repo, url: url.deletingLastPathComponent().appendingPathComponent("assistant.json"), speakingContext: { library.context(question: $0) }) { prompt, _ in
            captured = prompt
            return AITextResponse(text: "Let's practise.", modelID: "stub")
        }
        agent.conversationDraft = "Unfinished thought"
        agent.appendToDraft("Discuss a material")
        XCTAssertEqual(agent.conversationDraft, "Unfinished thought\n\nDiscuss a material")
        agent.send("Help me practise friends")
        while agent.isThinking { await Task.yield() }
        XCTAssertTrue(captured.contains("SPEAKING_MATERIALS_JSON"))
        XCTAssertTrue(captured.contains("My real answer"))
        XCTAssertTrue(captured.contains("recentSelfReports"))
        XCTAssertEqual(library.attempts.count, 1)
        let snapshot = try await repo.exportSnapshot()
        XCTAssertTrue(snapshot.reviewLogs.isEmpty)
    }
    @MainActor func testCancelAnalysisCannotProduceAProposalOrSaveAnything() async throws {
        let library = SpeakingLibrary(url: location())
        let task = Task {
            try await SpeakingImport.analyze(text: "A source sentence.", name: "lesson") { _, _ in
                try await Task.sleep(for: .seconds(30))
                return AITextResponse(text: "{\"materials\":[]}", modelID: "stub")
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled analysis must not succeed") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertTrue(library.personal.isEmpty)
    }

    @MainActor func testSpeakingContextBoundsLongTextAndFindsChineseTopic() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = SpeakingLibrary(url: url)
        let item = SpeakingMaterial(title: "Dining", english: String(repeating: "a", count: 12000), chinese: "餐厅体验", prompt: "Why visit restaurants?", notes: String(repeating: "b", count: 6000), topic: "Food")
        try library.add([item])
        let context = library.context(question: "帮我练练餐厅题")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any])
        let samples = try XCTUnwrap(object["sampledMaterials"] as? [[String: Any]])
        XCTAssertEqual(samples.first?["title"] as? String, "Dining")
        XCTAssertLessThanOrEqual(samples.count, 6)
        XCTAssertTrue(samples.allSatisfy { ($0["english"] as? String ?? "").count <= 1200 })
        XCTAssertTrue(samples.allSatisfy { $0["sourceExcerpt"] == nil })
        XCTAssertEqual(object["total"] as? Int, 27)
    }

    @MainActor func testCollidingSourceDocumentIDIsRemappedWithoutReplacingOriginal() throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = SpeakingLibrary(url: url)
        let first = SpeakingDocument(name: "First", text: "Original source")
        let a = SpeakingMaterial(title: "A", english: "An original example.", sourceDocumentID: first.id)
        try library.add([a], documents: [first])
        var second = first; second.text = "Different source"; second.name = "Second"
        let b = SpeakingMaterial(title: "B", english: "A different example.", sourceDocumentID: second.id)
        try library.add([b], documents: [second])
        XCTAssertEqual(library.documents.count, 2)
        XCTAssertEqual(library.documents.first { $0.id == first.id }?.text, "Original source")
        let saved = try XCTUnwrap(library.personal.first { $0.title == "B" })
        XCTAssertNotEqual(saved.sourceDocumentID, first.id)
        XCTAssertEqual(library.documents.first { $0.id == saved.sourceDocumentID }?.text, "Different source")
    }

}
