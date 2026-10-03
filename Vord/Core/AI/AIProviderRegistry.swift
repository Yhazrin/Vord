import Foundation

struct AIModel: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
}
struct AITextRequest: Codable, Sendable, Equatable {
    var modelID: String
    var prompt: String
    var system: String?
}
struct AITextResponse: Codable, Sendable, Equatable {
    var text: String
    var modelID: String
    var inputTokens: Int?
    var outputTokens: Int?
}
protocol AITextProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var availableModels: [AIModel] { get }
    func generate(request: AITextRequest) async throws -> AITextResponse
}

enum AIProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatCompletions, responses, anthropic, gemini, ollama
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chatCompletions: return "OpenAI Compatible"
        case .responses: return "OpenAI Responses"
        case .anthropic: return "Anthropic Messages"
        case .gemini: return "Gemini Native"
        case .ollama: return "Ollama (local)"
        }
    }
}

/// Secrets live only in Keychain. A descriptor can safely be persisted without its API key.
struct AIProviderDescriptor: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var modelID: String
    var keychainAccount: String
    var format: AIProtocol = .chatCompletions
    var fullEndpoint: Bool = false
    var timeout: Double = 60
    var maxTokens: Int = 2048

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, modelID, keychainAccount, format, fullEndpoint, timeout, maxTokens
    }
    init(id: UUID = UUID(), name: String, baseURL: String, modelID: String, keychainAccount: String,
         format: AIProtocol = .chatCompletions, fullEndpoint: Bool = false, timeout: Double = 60, maxTokens: Int = 2048) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.modelID = modelID
        self.keychainAccount = keychainAccount; self.format = format; self.fullEndpoint = fullEndpoint
        self.timeout = timeout; self.maxTokens = maxTokens
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        modelID = try values.decode(String.self, forKey: .modelID)
        keychainAccount = try values.decode(String.self, forKey: .keychainAccount)
        format = try values.decodeIfPresent(AIProtocol.self, forKey: .format) ?? .chatCompletions
        fullEndpoint = try values.decodeIfPresent(Bool.self, forKey: .fullEndpoint) ?? false
        timeout = try values.decodeIfPresent(Double.self, forKey: .timeout) ?? 60
        maxTokens = try values.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
    }
}

struct AIPreset: Identifiable {
    var id: String { name }
    var name: String
    var baseURL: String
    var model: String
    var format: AIProtocol
    var timeout: Double = 60
    var maxTokens: Int = 2048
    static let miniMaxModels = ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.5"]
    static let all: [AIPreset] = [
        .init(name: "MiniMax · Anthropic", baseURL: "https://api.minimax.cn/anthropic/v1", model: "MiniMax-M3", format: .anthropic, timeout: 90, maxTokens: 8192),
        .init(name: "MiniMax · OpenAI", baseURL: "https://api.minimax.cn/v1", model: "MiniMax-M3", format: .chatCompletions, timeout: 90, maxTokens: 8192),
        .init(name: "MiniMax Global · Anthropic", baseURL: "https://api.minimax.io/anthropic/v1", model: "MiniMax-M3", format: .anthropic, timeout: 90, maxTokens: 8192),
        .init(name: "MiniMax Global · OpenAI", baseURL: "https://api.minimax.io/v1", model: "MiniMax-M3", format: .chatCompletions, timeout: 90, maxTokens: 8192),
        .init(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "", format: .responses),
        .init(name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "", format: .anthropic),
        .init(name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "", format: .gemini),
        .init(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", format: .chatCompletions),
        .init(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "", format: .chatCompletions),
        .init(name: "Ollama", baseURL: "http://localhost:11434", model: "", format: .ollama),
        .init(name: "Custom", baseURL: "", model: "", format: .chatCompletions)
    ]
}

final class AIProviderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [String: any AITextProvider] = [:]
    func register(_ provider: any AITextProvider) {
        lock.lock(); defer { lock.unlock() }; providers[provider.id] = provider
    }
    func provider(id: String) -> (any AITextProvider)? {
        lock.lock(); defer { lock.unlock() }; return providers[id]
    }
    var registeredIDs: [String] {
        lock.lock(); defer { lock.unlock() }; return providers.keys.sorted()
    }
}
