import XCTest
@testable import Vord

final class DictionaryFlowTests: XCTestCase {
    private func store() -> DictionaryStore {
        DictionaryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }
    private func service(_ store: DictionaryStore) -> TranslationService {
        let service = TranslationService(selectedID: "apple")
        service.register(LocalDictionaryProvider(store: store))
        service.register(UnavailableTranslation())
        return service
    }
    private func repository() throws -> SQLiteVocabularyRepository {
        SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
    }
    func testBundledDictionaryIsIncludedAndEnglishLookupSkipsTranslation() async throws {
        let store = store()
        XCTAssertEqual(store.bundledCount, 768_739)
        let found = try await service(store).lookup(text: " Reluctant ")
        XCTAssertFalse(found.requiresSelection)
        let entry = try XCTUnwrap(found.results.first)
        XCTAssertEqual(entry.english, "reluctant")
        XCTAssertTrue(entry.chinese.contains("不情愿"))
        XCTAssertTrue(try XCTUnwrap(entry.englishDefinition).contains("not eager"))
        XCTAssertNotNil(entry.phonetic)
        XCTAssertEqual(entry.providerName, "ECDICT · offline")
    }
    func testChineseReverseLookupReturnsDistinctCandidatesWithFullDefinitions() async throws {
        let found = try await service(store()).lookup(text: "害怕")
        XCTAssertTrue(found.requiresSelection)
        XCTAssertGreaterThan(found.results.count, 1)
        XCTAssertEqual(Set(found.results.map(\.english)).count, found.results.count)
        XCTAssertTrue(found.results.contains { $0.english == "fear" })
        let afraid = try XCTUnwrap(found.results.first { $0.english == "afraid" })
        XCTAssertTrue(afraid.chinese.contains("恐怕"))
        XCTAssertNotEqual(afraid.chinese, "害怕")
        XCTAssertNotNil(afraid.englishDefinition)
        XCTAssertEqual(afraid.sourceText, "害怕")
    }
    func testPartialChineseAndTraditionalChineseAreSearchable() throws {
        let store = store()
        XCTAssertFalse(try store.search("缓解", from: .chinese).isEmpty)
        XCTAssertFalse(try store.search("嚴肅", from: .chinese).isEmpty)
        let simplified = try store.search("严肃", from: .chinese)
        let traditional = try store.search("嚴肅", from: .chinese)
        XCTAssertEqual(simplified.map(\.id), traditional.map(\.id))
        XCTAssertFalse(try store.search("猫", from: .chinese).isEmpty)
    }
    func testPrefixesAreSuggestionsAndDoNotSilentlySaveADifferentHeadword() async throws {
        let service = service(store())
        let found = try await service.lookup(text: "serendi")
        XCTAssertTrue(found.requiresSelection)
        XCTAssertTrue(found.results.contains { $0.english == "serendipity" })
        XCTAssertTrue(try store().search("%", from: .english).allSatisfy { $0.item.english.hasPrefix("%") })
        XCTAssertTrue(try store().search("' OR 1=1 --", from: .english).isEmpty)
    }
    func testImportedDefinitionOverridesBundledEntryAndSearchDeduplicates() async throws {
        let store = store()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let isolated = DictionaryStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try isolated.importData(Data(#"[{"english":"reluctant","chinese":"我自己的释义","englishDefinition":"My own definition"}]"#.utf8))
        let found = try await service(isolated).lookup(text: "reluctant")
        XCTAssertEqual(found.results.first?.chinese, "我自己的释义")
        XCTAssertEqual(found.results.first?.englishDefinition, "My own definition")
        XCTAssertEqual(found.results.first?.providerName, "Imported dictionary")
        XCTAssertEqual(try isolated.search("reluctant", from: .english).filter { $0.id == "reluctant" }.count, 1)
        XCTAssertEqual(store.count, 0)
    }
    @MainActor
    func testEnglishImmediateSaveIncludesBothDefinitions() async throws {
        let repo = try repository(), service = service(store()), model = AddViewModel()
        model.query = "estrangement"
        model.scheduleLookup(service)
        await model.save(repository: repo, translation: service)
        let entries = try await repo.activeEntries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.english, "estrangement")
        XCTAssertTrue(entry.chinese.contains("疏远"))
        XCTAssertNotNil(entry.englishDefinition)
        XCTAssertNotNil(entry.chineseDefinition)
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(model.lastSavedWord, "estrangement")
    }
    @MainActor
    func testFailedWriteDoesNotShowSuccessAndRetryPreservesTheWord() async throws {
        let database = try AppDatabase(path: ":memory:")
        let repo = SQLiteVocabularyRepository(database: database, onChange: {})
        try await database.perform { handle in
            try database.exec(handle, "CREATE TRIGGER reject_capture BEFORE INSERT ON vocabulary_entries BEGIN SELECT RAISE(ABORT, 'Test disk failure'); END;")
        }
        let model = AddViewModel(), translation = service(store())
        model.query = "reluctant"
        await model.save(repository: repo, translation: translation)
        XCTAssertEqual(model.query, "reluctant")
        XCTAssertEqual(model.savedCount, 0)
        XCTAssertNil(model.lastSavedWord)
        XCTAssertTrue(model.message?.contains("Test disk failure") == true)
        try await database.perform { handle in try database.exec(handle, "DROP TRIGGER reject_capture;") }
        await model.save(repository: repo, translation: translation)
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(model.lastSavedWord, "reluctant")
        XCTAssertEqual(model.query, "")
        let entries = try await repo.activeEntries()
        XCTAssertEqual(entries.count, 1)
    }
    @MainActor
    func testManualChineseMeaningKeepsAutomaticEnglishDefinition() async throws {
        let repo = try repository(), service = service(store()), model = AddViewModel()
        model.query = "reluctant"; model.meaning = "不情愿的（我的笔记）"
        await model.save(repository: repo, translation: service)
        let entries = try await repo.activeEntries()
        let saved = try XCTUnwrap(entries.first)
        XCTAssertEqual(saved.chinese, "不情愿的（我的笔记）")
        XCTAssertTrue(try XCTUnwrap(saved.englishDefinition).contains("not eager"))
        XCTAssertEqual(saved.source, "Manual")
        model.scheduleLookup(service)
        XCTAssertEqual(model.message, "Saved")
    }
    @MainActor
    func testChineseRequiresSelectionAndPersistsSelectedEntry() async throws {
        let repo = try repository(), service = service(store()), model = AddViewModel()
        model.query = "害怕"
        await model.save(repository: repo, translation: service)
        var entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertNil(model.preview)
        let selected = try XCTUnwrap(model.candidates.first { $0.english == "afraid" })
        await model.choose(selected, translation: service)
        await model.save(repository: repo, translation: service)
        entries = try await repo.activeEntries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.english, "afraid")
        XCTAssertTrue(entry.chinese.contains("恐怕"))
        XCTAssertNotNil(entry.englishDefinition)
        XCTAssertEqual(entry.sourceSentence, "害怕")
    }
    @MainActor
    func testQuickAddUsesSameDictionaryAndChineseSelectionFlow() async throws {
        let repo = try repository(), service = service(store())
        let model = QuickAddModel(repository: repo, translation: service)
        model.text = "reluctant"
        let savedEnglish = await model.submit()
        XCTAssertTrue(savedEnglish)
        model.reset(); model.text = "害怕"
        let savedAmbiguous = await model.submit()
        XCTAssertFalse(savedAmbiguous)
        let selected = try XCTUnwrap(model.candidates.first { $0.english == "fear" })
        let savedChinese = await model.submit(candidate: selected)
        XCTAssertTrue(savedChinese)
        let entries = try await repo.activeEntries()
        XCTAssertEqual(Set(entries.map(\.english)), Set(["reluctant", "fear"]))
        XCTAssertTrue(entries.allSatisfy { $0.englishDefinition != nil && !$0.chinese.isEmpty })
    }
    func testDictionaryExampleUsesOnlyARealQuotedSentence() {
        let reluctant = "reluctant re·luc·tant | rəˈləkt(ə)nt | adjective unwilling and hesitant; disinclined: [with infinitive] : she seemed reluctant to discuss the matter. ORIGIN early 17th century: from Latin reluctant- ‘struggling against’."
        XCTAssertEqual(DictionaryExample.extract(from: reluctant, headword: "reluctant"), "she seemed reluctant to discuss the matter.")
        let example = "example | iɡˈzampəl | noun 1 a thing characteristic of its kind or illustrating a general rule: it's a good example of how European action can produce results | some of these carpets are among the finest examples of the period. ORIGIN late Middle English."
        XCTAssertEqual(DictionaryExample.extract(from: example, headword: "example"), "it's a good example of how European action can produce results")
        let serendipity = "serendipity | ˌserənˈdipədē | noun the occurrence and development of events by chance in a happy or beneficial way: a fortunate stroke of serendipity | a series of small serendipities. ORIGIN 1754."
        XCTAssertEqual(DictionaryExample.extract(from: serendipity, headword: "serendipity"), "a fortunate stroke of serendipity")
        let phrase = "PHRASAL VERBS look after | take care of someone or something: Meg is expected to look after her younger sister | I'm quite capable of looking after myself."
        XCTAssertEqual(DictionaryExample.extract(from: phrase, headword: "look after"), "Meg is expected to look after her younger sister")
        XCTAssertNil(DictionaryExample.extract(from: "noun a supply or stock held in reserve", headword: "bank"))
        XCTAssertNil(DictionaryExample.extract(from: nil, headword: "bank"))
        XCTAssertNil(DictionaryExample.extract(from: "adjective unwilling and hesitant", headword: "reluctant"))
    }
    @MainActor
    func testSavingKeepsDictionaryExampleUnlessTheLearnerWritesOne() async throws {
        let repo = try repository(), service = service(store()), model = AddViewModel()
        model.query = "astonish"
        await model.save(repository: repo, translation: service)
        var entries = try await repo.activeEntries()
        XCTAssertEqual(entries.first?.exampleSentence, "His sudden decision astonished everyone.")

        let custom = AddViewModel()
        custom.query = "mitigate"
        custom.example = "My own sentence."
        custom.exampleEdited = true
        await custom.save(repository: repo, translation: service)
        entries = try await repo.activeEntries()
        XCTAssertEqual(entries.first { $0.english == "mitigate" }?.exampleSentence, "My own sentence.")

        let cleared = AddViewModel()
        cleared.query = "exacerbate"
        cleared.example = ""
        cleared.exampleEdited = true
        await cleared.save(repository: repo, translation: service)
        entries = try await repo.activeEntries()
        let clearedEntry = try XCTUnwrap(entries.first { $0.english == "exacerbate" })
        XCTAssertNil(clearedEntry.exampleSentence)
    }
    @MainActor
    func testImportedDictionaryExampleIsSaved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let isolated = DictionaryStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try isolated.importData(Data(#"[{"english":"resilient","chinese":"有韧性的","exampleSentence":"The resilient team adapted to a difficult season."}]"#.utf8))
        let repo = try repository(), model = AddViewModel()
        model.query = "resilient"
        await model.save(repository: repo, translation: service(isolated))
        let entries = try await repo.activeEntries()
        XCTAssertEqual(entries.first?.exampleSentence, "The resilient team adapted to a difficult season.")
    }
    @MainActor
    func testChoosingAStaleResultCannotSavePreviousQuery() async throws {
        let service = service(store()), model = AddViewModel(), repo = try repository()
        let old = try await service.lookup(text: "害怕")
        model.query = "缓解"
        await model.choose(try XCTUnwrap(old.results.first), translation: service)
        XCTAssertNil(model.preview)
        await model.save(repository: repo, translation: service)
        let entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(model.candidates.allSatisfy { $0.sourceText == "缓解" })
    }
}

private struct UnavailableTranslation: TranslationProvider {
    let id = "apple"
    let displayName = "Unavailable test translation"
    func translate(text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        throw TranslationFailure.failed("Dictionary words must not call the fallback translator.")
    }
}
