import Foundation

struct ContextExample: Codable, Equatable, Identifiable, Sendable {
    var entryID: UUID
    var word: String
    var sentence: String
    var translation: String
    var explanation: String
    var id: UUID { entryID }
}

struct ContextRecord: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var topic: String
    var level: String
    var provider: String
    var model: String
    var examples: [ContextExample]
    var inputTokens: Int?
    var outputTokens: Int?
    var duration: Double?
    var attempts: Int?
}

struct ContextGeneration: Sendable {
    var response: AITextResponse
    var examples: [ContextExample]
    var attempts: Int
}
