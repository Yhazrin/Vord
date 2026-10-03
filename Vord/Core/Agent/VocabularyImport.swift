import Foundation

struct VocabularyImportItem: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case pending, existing, added, failed }
    var id = UUID()
    var english: String
    var chinese: String
    var englishDefinition: String?
    var exampleSentence: String?
    var sourceSentence: String?
    var phonetic: String?
    var partOfSpeech: String?
    var origin = "AI"
    var selected = true
    var status: Status = .pending
    var error: String?
    var isValid: Bool { Self.validHeadword(english) && !chinese.trimmed.isEmpty && chinese.count <= 2000 }
    static func validHeadword(_ word: String) -> Bool {
        word.count <= 80 && word.range(of: #"^[A-Za-z]+(?:[ '’-][A-Za-z]+)*$"#, options: .regularExpression) != nil
    }
}

struct VocabularyImport: Codable, Equatable {
    var items: [VocabularyImportItem]
    var sourceText: String
    var pendingCount: Int { items.filter { $0.selected && $0.isValid && ($0.status == .pending || $0.status == .failed) }.count }
    var addedCount: Int { items.filter { $0.status == .added }.count }
}

enum AgentReply {
    struct Decoded { var text: String; var items: [VocabularyImportItem] }
    private struct Payload: Decodable {
        var reply: String
        var words: [Word]?
        struct Word: Decodable {
            var english: String
            var chinese: String
            var englishDefinition: String?
            var exampleSentence: String?
        }
    }
    static func decode(_ raw: String) throws -> Decoded {
        var text = raw.trimmed
        if text.hasPrefix("```json") || text.hasPrefix("```\n{") {
            let lines = text.components(separatedBy: "\n")
            if lines.last?.trimmed == "```" { text = lines.dropFirst().dropLast().joined(separator: "\n") }
        }
        // Plain-text replies from compatible providers still work; only a validated envelope can propose a write.
        guard text.hasPrefix("{") else { return Decoded(text: raw, items: []) }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)),
              (payload.words?.count ?? 0) <= 50, !payload.reply.trimmed.isEmpty else {
            throw AIError.configuration("Could not read the word list. Try importing fewer words.")
        }
        var seen = Set<String>()
        let items = try (payload.words ?? []).compactMap { word -> VocabularyImportItem? in
            let english = word.english.trimmed
            guard VocabularyImportItem.validHeadword(english), !word.chinese.trimmed.isEmpty,
                  word.chinese.count <= 2000,
                  (word.englishDefinition?.count ?? 0) <= 4000,
                  (word.exampleSentence?.count ?? 0) <= 2000 else {
                throw AIError.configuration("A word or meaning is incomplete. Try again.")
            }
            guard seen.insert(english.lowercased()).inserted else { return nil }
            return VocabularyImportItem(english: english, chinese: word.chinese.trimmed,
                englishDefinition: word.englishDefinition?.trimmed.nilIfEmpty,
                exampleSentence: word.exampleSentence?.trimmed.nilIfEmpty)
        }
        return Decoded(text: payload.reply.trimmed, items: items)
    }
}
