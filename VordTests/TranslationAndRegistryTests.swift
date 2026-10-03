import XCTest
@testable import Vord

final class TranslationAndRegistryTests: XCTestCase {
    func testLanguageDetection() {
        XCTAssertEqual(LanguageDetector.detect("astonish"), .english)
        XCTAssertEqual(LanguageDetector.detect("恶化"), .chinese)
        XCTAssertEqual(LanguageDetector.detect("使惊讶"), .chinese)
    }

    func testLocalDictionaryBothDirections() async throws {
        let provider = LocalDictionaryProvider(store: DictionaryStore(bundledURL: nil))
        let english = try await provider.translate(text: "astonish", from: .english, to: .chinese)
        XCTAssertEqual(english.chinese, "使惊讶；使震惊")
        XCTAssertEqual(english.phonetic, "/əˈstɒnɪʃ/")

        let chinese = try await provider.translate(text: "恶化", from: .chinese, to: .english)
        XCTAssertEqual(chinese.english, "deteriorate")
    }

    func testRegistryStoresProvidersWithoutAPIKeys() async throws {
        let registry = AIProviderRegistry()
        let provider = StubProvider()
        registry.register(provider)
        let resolved = try XCTUnwrap(registry.provider(id: "stub") as? StubProvider)
        let response = try await resolved.generate(
            request: AITextRequest(modelID: "custom-model", prompt: "hello", system: nil)
        )
        XCTAssertEqual(response.modelID, "custom-model")
        XCTAssertEqual(registry.registeredIDs, ["stub"])
        let descriptor = AIProviderDescriptor(
            id: UUID(),
            name: "Custom",
            baseURL: "https://example.invalid/v1",
            modelID: "custom-model",
            keychainAccount: "custom"
        )
        let data = try JSONEncoder().encode(descriptor)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertTrue(text.contains("baseURL"))
    }
}

private struct StubProvider: AITextProvider {
    let id = "stub"
    let displayName = "Stub"
    let availableModels = [AIModel(id: "custom-model", displayName: "Custom")]

    func generate(request: AITextRequest) async throws -> AITextResponse {
        AITextResponse(text: request.prompt, modelID: request.modelID)
    }
}
