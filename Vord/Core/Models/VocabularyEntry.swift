import Foundation

struct VocabularyEntry: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var english: String
    var chinese: String
    var lemma: String?
    var phonetic: String?
    var partOfSpeech: String?
    var englishDefinition: String?
    var chineseDefinition: String?
    var exampleSentence: String?
    var sourceSentence: String?
    var source: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var archived: Bool

    var headword: String {
        let english = english.trimmed
        if !english.isEmpty { return english }
        return chinese.trimmed
    }

    var gloss: String {
        if let definition = chineseDefinition?.trimmed, !definition.isEmpty, !chinese.trimmed.isEmpty {
            return definition
        }
        if !chinese.trimmed.isEmpty { return chinese.trimmed }
        return englishDefinition?.trimmed ?? ""
    }
}

struct EntryDraft: Sendable, Equatable {
    var existingID: UUID?
    var english: String
    var chinese: String
    var lemma: String?
    var phonetic: String?
    var partOfSpeech: String?
    var englishDefinition: String?
    var chineseDefinition: String?
    var exampleSentence: String?
    var sourceSentence: String?
    var source: String?
    var tags: [String] = []
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
