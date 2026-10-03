import XCTest
@testable import Vord

final class AIAdapterTests: XCTestCase {
    private func descriptor(_ format: AIProtocol) -> AIProviderDescriptor {
        .init(name: "Test", baseURL: "https://example.com/v1", modelID: "model", keychainAccount: "test", format: format)
    }
    func testEveryProtocolBuildsItsEndpointAndAuthentication() throws {
        let paths: [AIProtocol: String] = [.chatCompletions: "/v1/chat/completions", .responses: "/v1/responses", .anthropic: "/v1/messages", .gemini: "/v1/models/model:generateContent", .ollama: "/v1/api/generate"]
        for format in AIProtocol.allCases {
            let provider = HTTPAIProvider(descriptor: descriptor(format))
            let request = try provider.makeRequest(.init(modelID: "model", prompt: "hello", system: "teach"), key: "fake-test-key")
            XCTAssertEqual(request.url?.path, paths[format])
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertFalse(request.url!.absoluteString.contains("fake-test-key"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            if format == .anthropic {
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fake-test-key")
                XCTAssertEqual(body["system"] as? String, "teach")
            } else if format == .gemini {
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fake-test-key")
                XCTAssertNotNil(body["systemInstruction"])
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-key")
            }
            if format == .responses { XCTAssertEqual(body["store"] as? Bool, false) }
            if format == .ollama { XCTAssertEqual(body["stream"] as? Bool, false) }
        }
    }
    func testParsersReturnOnlyVisibleTextAcrossProtocols() throws {
        let cases: [(AIProtocol, String)] = [
            (.chatCompletions, #"{"choices":[{"message":{"content":"answer","reasoning_content":"private"}}]}"#),
            (.responses, #"{"output":[{"type":"reasoning"},{"content":[{"type":"output_text","text":"answer"}]}]}"#),
            (.anthropic, #"{"content":[{"type":"thinking","thinking":"private"},{"type":"text","text":"answer"}]}"#),
            (.gemini, #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"private"},{"text":"answer"}]}}]}"#),
            (.ollama, #"{"response":"answer"}"#)
        ]
        for (format, json) in cases {
            XCTAssertEqual(try HTTPAIProvider.decode(Data(json.utf8), format: format, model: "model").text, "answer")
        }
        XCTAssertThrowsError(try HTTPAIProvider.decode(Data(#"{"choices":[]}"#.utf8), format: .chatCompletions, model: "m"))
    }
    func testURLValidationAndCompleteEndpointMode() throws {
        var config = descriptor(.chatCompletions)
        for invalid in ["http://remote.example/v1", "https://secret@example.com/v1", "https://example.com/v1?key=secret", "file:///tmp/key"] {
            config.baseURL = invalid
            XCTAssertThrowsError(try HTTPAIProvider.endpoint(config, model: "m"))
        }
        config.baseURL = "http://localhost:11434"; config.format = .ollama
        XCTAssertEqual(try HTTPAIProvider.endpoint(config, model: "m").path, "/api/generate")
        config.baseURL = "https://example.com/custom/endpoint"; config.fullEndpoint = true
        XCTAssertEqual(try HTTPAIProvider.endpoint(config, model: "m").path, "/custom/endpoint")
    }
    func testMiniMaxPresetsHaveTheCorrectVersionedPaths() throws {
        for preset in AIPreset.all.filter({ $0.name.hasPrefix("MiniMax") }) {
            let config = AIProviderDescriptor(name: preset.name, baseURL: preset.baseURL, modelID: preset.model, keychainAccount: "test", format: preset.format)
            let endpoint = try HTTPAIProvider.endpoint(config, model: config.modelID)
            XCTAssertEqual(endpoint.path, preset.format == .anthropic ? "/anthropic/v1/messages" : "/v1/chat/completions")
        }
    }
    func testMiniMaxSeparatesReasoningAndAllowsRoomForEightExamples() throws {
        for preset in AIPreset.all.filter({ $0.name.hasPrefix("MiniMax") }) {
            let config = AIProviderDescriptor(name: preset.name, baseURL: preset.baseURL, modelID: preset.model,
                                              keychainAccount: "test", format: preset.format,
                                              timeout: preset.timeout, maxTokens: preset.maxTokens)
            XCTAssertEqual(config.maxTokens, 8192)
            let request = try HTTPAIProvider(descriptor: config).makeRequest(.init(modelID: config.modelID, prompt: "hello", system: nil), key: "fake")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            if preset.format == .chatCompletions { XCTAssertEqual(body["reasoning_split"] as? Bool, true) }
        }
        let request = try HTTPAIProvider(descriptor: descriptor(.chatCompletions)).makeRequest(.init(modelID: "m", prompt: "hello", system: nil), key: "fake")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertNil(body["reasoning_split"])
    }
    func testInlineThinkingIsRemovedAndTruncatedRepliesAreRejected() throws {
        let json = #"{"choices":[{"message":{"content":"<think>private reasoning</think>\nA sentence.","reasoning_content":"private"},"finish_reason":"stop"}],"usage":{"prompt_tokens":21,"completion_tokens":37}}"#
        let response = try HTTPAIProvider.decode(Data(json.utf8), format: .chatCompletions, model: "m")
        XCTAssertFalse(response.text.contains("private"))
        XCTAssertEqual(response.text, "A sentence.")
        XCTAssertEqual(response.inputTokens, 21)
        XCTAssertEqual(response.outputTokens, 37)
        XCTAssertThrowsError(try HTTPAIProvider.decode(Data(json.replacingOccurrences(of: "\"stop\"", with: "\"length\"").utf8), format: .chatCompletions, model: "m"))
        let unfinished = #"{"choices":[{"message":{"content":"<think>private reasoning"}}]}"#
        XCTAssertThrowsError(try HTTPAIProvider.decode(Data(unfinished.utf8), format: .chatCompletions, model: "m"))
        let partial = #"{"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}"#
        XCTAssertThrowsError(try HTTPAIProvider.decode(Data(partial.utf8), format: .anthropic, model: "m"))
    }
    func testClozeBlanksWholeWordsAndPhrasesWithoutDamagingOtherWords() {
        let example = ContextExample(entryID: UUID(), word: "cat", sentence: "The cat and CAT watched cattle.", translation: "", explanation: "")
        XCTAssertEqual(ContextGenerator.blankedSentence(example), "The ______ and ______ watched cattle.")
        let phrase = ContextExample(entryID: UUID(), word: "look up", sentence: "Please look up the address.", translation: "", explanation: "")
        XCTAssertEqual(ContextGenerator.blankedSentence(phrase), "Please ______ the address.")
    }
    func testInflectedFormsPassValidationAndAreHiddenDuringPractice() throws {
        let entry = VocabularyEntry(id: UUID(), english: "reassure", chinese: "使安心", tags: [], createdAt: Date(), updatedAt: Date(), archived: false)
        let json = #"{"items":[{"word":"reassure","sentence":"She reassured me that the files were safe.","translation":"她让我放心，文件是安全的。","explanation":"reassured 是 reassure 的过去式。"}]}"#
        let example = try XCTUnwrap(ContextGenerator.decode(json, entries: [entry]).first)
        XCTAssertEqual(ContextGenerator.blankedSentence(example), "She ______ me that the files were safe.")
        XCTAssertTrue(ContextGenerator.wordRanges(in: "We went home.", word: "go").count == 1)
    }
    func testMalformedExamplesAreCorrectedOnceAndUsageIsSummed() async throws {
        let entry = VocabularyEntry(id: UUID(), english: "cat", chinese: "猫", tags: [], createdAt: Date(), updatedAt: Date(), archived: false)
        let valid = #"{"items":[{"word":"cat","sentence":"The cat sleeps.","translation":"猫在睡觉。","explanation":"cat 指猫。"}]}"#
        let provider = ContextStubProvider(replies: ["broken JSON", valid])
        let result = try await ContextGenerator.generate(entries: [entry], topic: "Home", level: "A2", provider: provider, model: "test")
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.examples.count, 1)
        XCTAssertEqual(result.response.inputTokens, 20)
        XCTAssertEqual(result.response.outputTokens, 40)
        let prompts = await provider.prompts
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].contains("previous_response"))
    }
    func testCorrectionStopsAfterTwoInvalidResponses() async throws {
        let entry = VocabularyEntry(id: UUID(), english: "cat", chinese: "猫", tags: [], createdAt: Date(), updatedAt: Date(), archived: false)
        let provider = ContextStubProvider(replies: ["bad JSON", "bad JSON", "unused"])
        do {
            _ = try await ContextGenerator.generate(entries: [entry], topic: "Home", level: "A2", provider: provider, model: "test")
            XCTFail("Invalid examples must fail")
        } catch {}
        let calls = await provider.prompts.count
        XCTAssertEqual(calls, 2)
    }
    func testAuthenticationFailuresAreNotAutomaticallyRetried() async throws {
        let provider = ContextStubProvider(replies: [], failure: .http(401))
        do {
            _ = try await ContextGenerator.generate(entries: [], topic: "Home", level: "A2", provider: provider, model: "test")
            XCTFail("Authentication must fail")
        } catch { XCTAssertEqual(error as? AIError, .http(401)) }
        let calls = await provider.prompts.count
        XCTAssertEqual(calls, 1)
    }
    func testRegenerationSuppliesOnlyPreviousExamplesForSelectedWords() throws {
        let entry = VocabularyEntry(id: UUID(), english: "cat", chinese: "猫", tags: [], createdAt: Date(), updatedAt: Date(), archived: false)
        let previous = [ContextExample(entryID: entry.id, word: "cat", sentence: "The cat sleeps.", translation: "", explanation: ""),
                        ContextExample(entryID: UUID(), word: "dog", sentence: "The dog sleeps.", translation: "", explanation: "")]
        let prompt = try ContextGenerator.prompt(entries: [entry], topic: "Home", level: "A2", previous: previous)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
        let prior = try XCTUnwrap(json["previous_examples"] as? [[String: String]])
        XCTAssertEqual(prior.count, 1)
        XCTAssertEqual(prior.first?["sentence"], "The cat sleeps.")
    }
    func testContextValidationRejectsOmissionsDuplicatesAndWrongWords() throws {
        let entry = VocabularyEntry(id: UUID(), english: "cat", chinese: "猫", tags: [], createdAt: Date(), updatedAt: Date(), archived: false)
        let valid = #"{"items":[{"word":"cat","sentence":"The cat sleeps.","translation":"猫在睡觉。","explanation":"cat 指猫。"}]}"#
        let examples = try ContextGenerator.decode(valid, entries: [entry])
        XCTAssertEqual(examples.first?.entryID, entry.id)
        XCTAssertThrowsError(try ContextGenerator.decode(valid.replacingOccurrences(of: "The cat sleeps.", with: "The cattle sleep."), entries: [entry]))
        XCTAssertThrowsError(try ContextGenerator.decode(#"{"items":[]}"#, entries: [entry]))
        XCTAssertThrowsError(try ContextGenerator.decode(valid.replacingOccurrences(of: "猫在睡觉。", with: ""), entries: [entry]))
    }
}

private actor ContextStubProvider: AITextProvider {
    nonisolated let id = "context-stub"
    nonisolated let displayName = "Test"
    nonisolated var availableModels: [AIModel] { [] }
    var replies: [String]
    var failure: AIError?
    private(set) var prompts: [String] = []
    init(replies: [String], failure: AIError? = nil) { self.replies = replies; self.failure = failure }
    func generate(request: AITextRequest) async throws -> AITextResponse {
        prompts.append(request.prompt)
        if let failure { throw failure }
        guard !replies.isEmpty else { throw AIError.invalidResponse }
        return .init(text: replies.removeFirst(), modelID: "test", inputTokens: 10, outputTokens: 20)
    }
}

extension AIAdapterTests {
    func testHTTPTransportSendsJSONAndParsesTheResponse() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [AIStubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let config = descriptor(.ollama)
        let provider = HTTPAIProvider(descriptor: config, session: session)
        let request = try provider.makeRequest(.init(modelID: "model", prompt: "example", system: nil), key: "")
        let response = try await provider.execute(request, model: "model")
        XCTAssertEqual(response.text, "A contextual example.")
    }
    func testHTTPTransportSurfacesRateLimits() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [AIStubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        var config = descriptor(.ollama)
        config.baseURL = "https://example.com/rate-limit"
        let provider = HTTPAIProvider(descriptor: config, session: session)
        let request = try provider.makeRequest(.init(modelID: "model", prompt: "example", system: nil), key: "")
        do { _ = try await provider.execute(request, model: "model"); XCTFail("Expected HTTP 429") }
        catch { XCTAssertEqual(error as? AIError, .http(429)) }
    }
}
private final class AIStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url!.path.contains("rate-limit") ? 429 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"response":"A contextual example."}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
