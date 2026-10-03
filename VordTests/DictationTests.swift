import XCTest
@testable import Vord

final class DictationTests: XCTestCase {
    func testChinesePromptAcceptsTheEnglishHeadword() throws {
        let entry = sample(english: "Astonish", chinese: "使惊讶；使震惊", definition: "使惊讶；使震惊")
        var random = SplitGenerator(nextValue: 0)
        let questions = DictationMatching.questions(
            from: [entry],
            count: 1,
            mode: .chineseToEnglish,
            random: &random
        )
        let question = try XCTUnwrap(questions.first)
        XCTAssertEqual(question.prompt, "使惊讶；使震惊")
        XCTAssertEqual(question.direction, .chineseToEnglish)
        XCTAssertTrue(DictationMatching.matches(input: " astonish ", accepted: question.accepted))
        XCTAssertFalse(DictationMatching.matches(input: "shock", accepted: question.accepted))
    }

    func testEnglishPromptAcceptsEitherChineseSense() throws {
        let entry = sample(english: "deteriorate", chinese: "恶化", definition: "恶化；退化")
        var random = SplitGenerator(nextValue: 0)
        let questions = DictationMatching.questions(
            from: [entry],
            count: 1,
            mode: .englishToChinese,
            random: &random
        )
        let question = try XCTUnwrap(questions.first)
        XCTAssertEqual(question.prompt, "deteriorate")
        XCTAssertTrue(DictationMatching.matches(input: "退化", accepted: question.accepted))
        XCTAssertTrue(DictationMatching.matches(input: "恶化；退化", accepted: question.accepted))
        XCTAssertFalse(DictationMatching.matches(input: "惊", accepted: question.accepted))
    }

    func testRoundUsesOnlyEligibleWordsAndRespectsTheCount() {
        let ready = [
            sample(english: "mitigate", chinese: "减轻"),
            sample(english: "ubiquitous", chinese: "无处不在的")
        ]
        let blank = sample(english: "orphan", chinese: "")
        var random = SplitGenerator(nextValue: 1)
        let questions = DictationMatching.questions(
            from: ready + [blank],
            count: 10,
            mode: .mixed,
            random: &random
        )
        XCTAssertEqual(questions.count, 2)
        XCTAssertTrue(questions.allSatisfy { $0.direction == .chineseToEnglish || $0.direction == .englishToChinese })
        XCTAssertFalse(questions.contains { $0.prompt == "orphan" })
    }

    func testActiveEntriesSkipArchivedWords() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = SQLiteVocabularyRepository(database: try AppDatabase(path: url.path), onChange: {})
        let kept = try await repository.upsert(EntryDraft(english: "mitigate", chinese: "减轻"), now: Date())
        let hidden = try await repository.upsert(EntryDraft(english: "obsolete", chinese: "过时的"), now: Date())
        try await repository.setArchived(id: hidden.id, archived: true, now: Date())
        let entries = try await repository.activeEntries()
        XCTAssertEqual(entries.map(\.id), [kept.id])
    }

    private func sample(english: String, chinese: String, definition: String? = nil) -> VocabularyEntry {
        let now = Date(timeIntervalSince1970: 0)
        return VocabularyEntry(
            id: UUID(),
            english: english,
            chinese: chinese,
            lemma: english.lowercased(),
            phonetic: nil,
            partOfSpeech: nil,
            englishDefinition: nil,
            chineseDefinition: definition,
            exampleSentence: nil,
            sourceSentence: nil,
            source: nil,
            tags: [],
            createdAt: now,
            updatedAt: now,
            archived: false
        )
    }
}

private struct SplitGenerator: RandomNumberGenerator {
    var nextValue: UInt64
    mutating func next() -> UInt64 { nextValue }
}
