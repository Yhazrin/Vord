import XCTest
@testable import Vord

final class DictionarySelectionTests: XCTestCase {
    func testHitWordUsesUTF16AndKeepsContractionsAndHyphensTogether() throws {
        let text = "🌿 I can't see the mother-in-law’s kitchen."
        let value = text as NSString
        for word in ["can't", "mother-in-law’s", "kitchen"] {
            let location = value.range(of: word).location + 1
            let range = try XCTUnwrap(DictionarySelection.wordRange(in: text, atUTF16: location))
            XCTAssertEqual(value.substring(with: range), word)
            XCTAssertEqual(DictionarySelection.word(in: text, selected: range), word)
        }
        XCTAssertNil(DictionarySelection.wordRange(in: text, atUTF16: 0))
        XCTAssertNil(DictionarySelection.wordRange(in: text, atUTF16: value.length))
        XCTAssertNil(DictionarySelection.wordRange(in: text, atUTF16: value.range(of: " I").location))
        XCTAssertNil(DictionarySelection.word(in: text, selected: value.range(of: "see the")))
        XCTAssertNil(DictionarySelection.word(in: text, selected: NSRange(location: value.length + 3, length: 1)))
    }

    @MainActor
    func testDictionaryPopoverOnlySavesAfterExplicitAddAndKeepsSentenceAndDefinitions() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let service = try makeService()
        let model = DictionarySelectionModel(translation: service, repository: repo)
        let sentence = "The kitchen was quiet."
        await model.lookup(word: "kitchen", sentence: sentence)
        XCTAssertEqual(model.result?.english, "kitchen")
        XCTAssertEqual(model.result?.chinese, "厨房")
        XCTAssertEqual(model.result?.englishDefinition, "A room used for cooking.")
        var entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
        await model.add()
        await model.add()
        entries = try await repo.activeEntries()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.exampleSentence, sentence)
        XCTAssertEqual(entry.sourceSentence, sentence)
        XCTAssertEqual(entry.englishDefinition, "A room used for cooking.")
        XCTAssertTrue(model.saved)
    }

    @MainActor
    func testLookupDoesNotRewriteExistingWordOrReviewHistory() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let original = try await repo.upsert(EntryDraft(english: "kitchen", chinese: "我自己的释义", source: "My note"), now: Date())
        let before = try await repo.reviewState(entryID: original.id)
        let model = DictionarySelectionModel(translation: try makeService(), repository: repo)
        await model.lookup(word: "kitchen", sentence: "The kitchen was quiet.")
        XCTAssertTrue(model.inLibrary)
        await model.add()
        let entry = try await repo.entry(id: original.id)
        XCTAssertEqual(entry?.chinese, "我自己的释义")
        XCTAssertEqual(entry?.source, "My note")
        let after = try await repo.reviewState(entryID: original.id)
        XCTAssertEqual(before, after)
    }

    @MainActor
    func testDismissedLookupCannotFillOrSaveAnOldPopover() async throws {
        let provider = PausedSelectionTranslation()
        let service = TranslationService(selectedID: provider.id)
        service.register(provider)
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let model = DictionarySelectionModel(translation: service, repository: repo)
        let request = Task { await model.lookup(word: "kitchen", sentence: "The kitchen was quiet.") }
        let started = await provider.waitUntilRequested()
        XCTAssertTrue(started)
        model.dismiss()
        await provider.release()
        await request.value
        XCTAssertNil(model.result)
        await model.add()
        let entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    private func makeService() throws -> TranslationService {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("dictionary.json")
        let words = [DictionaryItem(english: "kitchen", chinese: "厨房", phonetic: nil, partOfSpeech: "n.",
            englishDefinition: "A room used for cooking.", exampleSentence: nil)]
        try JSONEncoder().encode(words).write(to: url)
        let store = DictionaryStore(url: url, bundledURL: nil)
        try FileManager.default.removeItem(at: folder)
        let service = TranslationService(selectedID: "local")
        service.register(LocalDictionaryProvider(store: store))
        return service
    }
}

private actor PausedSelectionTranslation: TranslationProvider {
    let id = "paused-selection"
    let displayName = "Paused selection translation"
    private var continuation: CheckedContinuation<TranslationResult, Never>?
    func translate(text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async -> Bool {
        for _ in 0..<200 {
            if continuation != nil { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }
    func release() {
        continuation?.resume(returning: TranslationResult(sourceText: "kitchen", translatedText: "厨房",
            sourceLanguage: .english, targetLanguage: .chinese, phonetic: nil, partOfSpeech: nil,
            englishDefinition: "A room used for cooking.", chineseDefinition: "厨房", exampleSentence: nil))
        continuation = nil
    }
}
