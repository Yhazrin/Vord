import XCTest
@testable import Vord

final class ClipboardCaptureTests: XCTestCase {
    func testClipboardRecognizesOnlySingleEnglishLexemes() {
        for word in ["plight", " STAGNANT ", "Serendipity", "mother-in-law", "can't", "isn’t", "a", "I"] {
            XCTAssertNotNil(ClipboardWord.parse(word), word)
        }
        for value in ["", "中文", "look after", "https://example.com", "sk-cp-123", "Word\n", "line\rbreak",
                      "word123", "abcXYZabcXYZ", "x", String(repeating: "a", count: 33), "foo_bar", "a@b.com"] {
            XCTAssertNil(ClipboardWord.parse(value), value)
        }
    }

    func testClipboardGateReadsOnlyChangesAndDoesNotRepeatDismissedWord() {
        var gate = ClipboardChangeGate()
        var reads = 0
        gate.reset(changeCount: 4)
        XCTAssertNil(gate.consume(changeCount: 4) { reads += 1; return "plight" })
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(gate.consume(changeCount: 5) { reads += 1; return "plight" }, "plight")
        XCTAssertNil(gate.consume(changeCount: 5) { reads += 1; return "plight" })
        XCTAssertEqual(reads, 1)
        XCTAssertNil(gate.consume(changeCount: 6) { reads += 1; return "private paragraph" })
        XCTAssertNil(gate.consume(changeCount: 6) { reads += 1; return "plight" })
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(gate.consume(changeCount: 7) { "plight" }, "plight")
    }

    func testSpringSettlesQuicklyAndRetargetsWithoutLosingVelocity() {
        var position = 48.0
        var velocity = 0.0
        var maximum = position
        for _ in 0..<60 {
            let next = CaptureSpringCurve.advance(position: position, velocity: velocity, target: 440, seconds: 1 / 60)
            position = next.position; velocity = next.velocity
            maximum = max(maximum, position)
        }
        XCTAssertEqual(position, 440, accuracy: 0.01)
        XCTAssertGreaterThan(maximum, 440)
        XCTAssertLessThan(maximum, 452)
        let sameInstant = CaptureSpringCurve.advance(position: 200, velocity: 100, target: 48, seconds: 0)
        XCTAssertEqual(sameInstant.position, 200, accuracy: 0.0001)
        XCTAssertEqual(sameInstant.velocity, 100, accuracy: 0.0001)
        let delayed = CaptureSpringCurve.advance(position: 48, velocity: 0, target: 440, seconds: 0.5)
        XCTAssertTrue(delayed.position.isFinite)
        XCTAssertEqual(delayed.position, 440, accuracy: 0.1)
    }
}

extension ClipboardCaptureTests {
    @MainActor
    func testCapturePreferencesStartPrivateAndPersistExplicitChoices() throws {
        let suite = "capture-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TranslationService(selectedID: "local")
        let settings = AppSettings(defaults: defaults, translation: service)
        XCTAssertFalse(settings.clipboardCaptureEnabled)
        XCTAssertTrue(settings.floatingQuickAddEnabled)
        settings.setClipboardCaptureEnabled(true)
        settings.setFloatingQuickAddEnabled(false)
        let reloaded = AppSettings(defaults: defaults, translation: service)
        XCTAssertTrue(reloaded.clipboardCaptureEnabled)
        XCTAssertFalse(reloaded.floatingQuickAddEnabled)
    }

    @MainActor
    func testClosingAndReopeningSameWordCannotCommitAnOldLookup() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let provider = HeldCaptureTranslation()
        let translation = TranslationService(selectedID: "held")
        translation.register(provider)
        let model = QuickAddModel(repository: repo, translation: translation)
        model.text = "plight"
        let pending = Task { await model.submit() }
        let started = await provider.waitUntilRequested()
        XCTAssertTrue(started)
        model.reset()
        model.text = "plight"
        await provider.release()
        let committed = await pending.value
        XCTAssertFalse(committed)
        XCTAssertFalse(model.isSaving)
        let entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
    }
}

private actor HeldCaptureTranslation: TranslationProvider {
    let id = "held"
    let displayName = "Held capture translation"
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
        continuation?.resume(returning: TranslationResult(sourceText: "plight", translatedText: "困境",
            sourceLanguage: .english, targetLanguage: .chinese, phonetic: nil, partOfSpeech: nil,
            englishDefinition: "A difficult situation.", chineseDefinition: "困境", exampleSentence: nil))
        continuation = nil
    }
}
