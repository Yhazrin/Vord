import Foundation

enum AIError: LocalizedError, Equatable {
    case configuration(String), http(Int), invalidResponse, noProvider
    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .noProvider: return "Add and select an AI provider in Settings first."
        case .invalidResponse: return "The provider returned no usable text. Check the model and API format."
        case .http(let status):
            switch status {
            case 401, 403: return "Authentication failed (\(status)). Check the API key and access to this model."
            case 404: return "Endpoint or model not found (404). Check the base URL and API format."
            case 429: return "Rate limit or quota reached (429). Wait a moment or check your provider balance."
            default: return "The AI provider returned HTTP \(status). Try again or check its service status."
            }
        }
    }
}

struct HTTPAIProvider: AITextProvider {
    let descriptor: AIProviderDescriptor
    let session: URLSession
    var id: String { descriptor.id.uuidString }
    var displayName: String { descriptor.name }
    var availableModels: [AIModel] { [.init(id: descriptor.modelID, displayName: descriptor.modelID)] }

    init(descriptor: AIProviderDescriptor, session: URLSession = .shared) {
        self.descriptor = descriptor; self.session = session
    }

    static func endpoint(_ descriptor: AIProviderDescriptor, model: String) throws -> URL {
        guard let base = URL(string: descriptor.baseURL.trimmed),
              let host = base.host, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw AIError.configuration("Use an HTTPS base URL, or HTTP for a local service. Do not put an API key in the URL.")
        }
        if descriptor.fullEndpoint { return base }
        switch descriptor.format {
        case .chatCompletions: return base.appendingPathComponent("chat/completions")
        case .responses: return base.appendingPathComponent("responses")
        case .anthropic: return base.appendingPathComponent("messages")
        case .gemini:
            guard !model.contains("/"), !model.contains(":"), !model.contains("?") else {
                throw AIError.configuration("Enter a Gemini model ID without a models/ prefix or URL.")
            }
            return base.appendingPathComponent("models/\(model):generateContent")
        case .ollama: return base.appendingPathComponent("api/generate")
        }
    }

    func generate(request: AITextRequest) async throws -> AITextResponse {
        try Task.checkCancellation()
        let key = try KeychainStore.get(account: descriptor.keychainAccount) ?? ""
        try Task.checkCancellation()
        if key.isEmpty && descriptor.format != .ollama {
            throw AIError.configuration("No API key saved for this provider. Enter one in Settings.")
        }
        let http = try makeRequest(request, key: key)
        return try await execute(http, model: request.modelID)
    }

    func execute(_ http: URLRequest, model: String) async throws -> AITextResponse {
        let (data, response) = try await session.data(for: http)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw AIError.http(httpResponse.statusCode) }
        return try Self.decode(data, format: descriptor.format, model: model)
    }

    func makeRequest(_ request: AITextRequest, key: String) throws -> URLRequest {
        guard !request.modelID.trimmed.isEmpty else { throw AIError.configuration("Enter a model ID.") }
        var http = URLRequest(url: try Self.endpoint(descriptor, model: request.modelID))
        http.httpMethod = "POST"
        http.timeoutInterval = min(180, max(10, descriptor.timeout))
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        let limit = min(8192, max(128, descriptor.maxTokens))
        var body: [String: Any]
        switch descriptor.format {
        case .chatCompletions:
            var messages: [[String: String]] = []
            if let system = request.system { messages.append(["role": "system", "content": system]) }
            messages.append(["role": "user", "content": request.prompt])
            body = ["model": request.modelID, "messages": messages, "max_tokens": limit, "stream": false]
            // MiniMax can otherwise include <think> blocks in the visible content.
            if Self.isMiniMax(http.url) { body["reasoning_split"] = true }
            http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .responses:
            body = ["model": request.modelID, "input": request.prompt, "max_output_tokens": limit, "store": false]
            if let system = request.system { body["instructions"] = system }
            http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            body = ["model": request.modelID, "messages": [["role": "user", "content": request.prompt]], "max_tokens": limit]
            if let system = request.system { body["system"] = system }
            http.setValue(key, forHTTPHeaderField: "x-api-key")
            http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            body = ["contents": [["role": "user", "parts": [["text": request.prompt]]]],
                    "generationConfig": ["maxOutputTokens": limit]]
            if let system = request.system { body["systemInstruction"] = ["parts": [["text": system]]] }
            http.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .ollama:
            body = ["model": request.modelID, "prompt": request.prompt, "stream": false, "options": ["num_predict": limit]]
            if let system = request.system { body["system"] = system }
            if !key.isEmpty { http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        return http
    }

    static func decode(_ data: Data, format: AIProtocol, model: String) throws -> AITextResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        let choices = object["choices"] as? [[String: Any]]
        let candidates = object["candidates"] as? [[String: Any]]
        if object["stop_reason"] as? String == "max_tokens" || choices?.first?["finish_reason"] as? String == "length"
            || object["status"] as? String == "incomplete" || candidates?.first?["finishReason"] as? String == "MAX_TOKENS" {
            throw AIError.configuration("The response was cut short. Increase Output tokens in provider settings, or choose fewer words.")
        }
        let text: String
        switch format {
        case .chatCompletions:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String ?? ""
        case .responses:
            let output = object["output"] as? [[String: Any]] ?? []
            text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .anthropic:
            text = (object["content"] as? [[String: Any]] ?? [])
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .gemini:
            let candidates = object["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            text = (content?["parts"] as? [[String: Any]] ?? [])
                .filter { $0["thought"] as? Bool != true }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .ollama: text = object["response"] as? String ?? ""
        }
        let visible = try visibleText(text)
        guard !visible.isEmpty else { throw AIError.invalidResponse }
        let usage = object["usage"] as? [String: Any] ?? [:]
        let geminiUsage = object["usageMetadata"] as? [String: Any] ?? [:]
        let input = usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int
            ?? geminiUsage["promptTokenCount"] as? Int ?? object["prompt_eval_count"] as? Int
        let output = usage["output_tokens"] as? Int ?? usage["completion_tokens"] as? Int
            ?? geminiUsage["candidatesTokenCount"] as? Int ?? object["eval_count"] as? Int
        return AITextResponse(text: visible, modelID: object["model"] as? String ?? model, inputTokens: input, outputTokens: output)
    }

    static func isMiniMax(_ url: URL?) -> Bool {
        ["api.minimax.cn", "api.minimax.io", "api.minimaxi.com"].contains(url?.host?.lowercased() ?? "")
    }

    private static func visibleText(_ text: String) throws -> String {
        // Some compatible gateways still emit thinking inline despite reasoning_split.
        // Never display an unfinished thinking block as a vocabulary example.
        let pattern = "(?is)<think>.*?</think>"
        let visible = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmed
        guard visible.range(of: "<think>", options: .caseInsensitive) == nil else { throw AIError.invalidResponse }
        return visible
    }
}
