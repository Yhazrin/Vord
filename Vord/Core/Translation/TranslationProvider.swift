import Foundation

struct TranslationResult: Sendable, Equatable {
    var sourceText: String
    var translatedText: String
    var sourceLanguage: Language
    var targetLanguage: Language
    var phonetic: String?
    var partOfSpeech: String?
    var englishDefinition: String?
    var chineseDefinition: String?
    var exampleSentence: String?
    var providerName: String? = nil
    var dictionaryHeadword: String? = nil

    var english: String {
        dictionaryHeadword ?? (sourceLanguage == .english ? sourceText : translatedText)
    }

    var chinese: String {
        sourceLanguage == .chinese ? (chineseDefinition?.nilIfEmpty ?? sourceText) : translatedText
    }
}

enum TranslationFailure: LocalizedError, Equatable {
    case emptyInput
    case notInLocalDictionary
    case languageResourcesMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a word first."
        case .notInLocalDictionary:
            return "No entry found in the offline dictionary. Check the spelling, try a shorter Chinese meaning, or add the meaning manually."
        case .languageResourcesMissing:
            return "Chinese and English language resources are not installed. Download them to use Apple Translation, or switch to Local Dictionary in Settings."
        case .failed(let message):
            return message
        }
    }
}

protocol TranslationProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func translate(
        text: String,
        from sourceLanguage: Language,
        to targetLanguage: Language
    ) async throws -> TranslationResult
}
