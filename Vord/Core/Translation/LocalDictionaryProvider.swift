import Foundation

struct LocalDictionaryProvider: TranslationProvider {
    let id = "local"
    let displayName = "Offline Dictionary"
    var store: DictionaryStore = DictionaryStore()

    func translate(text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        if let candidate = try store.search(text, from: sourceLanguage).first,
           sourceLanguage == .chinese || candidate.match == .exact || candidate.match == .inflection {
            return candidate.result(for: text)
        }
        if let lexeme = SampleLexicon.match(text: text, from: sourceLanguage) {
            return TranslationResult(sourceText: text.trimmed,
                translatedText: sourceLanguage == .english ? lexeme.chinese : lexeme.english,
                sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                phonetic: lexeme.phonetic, partOfSpeech: lexeme.partOfSpeech,
                englishDefinition: lexeme.englishDefinition, chineseDefinition: lexeme.chineseDefinition,
                exampleSentence: lexeme.exampleSentence, providerName: "Starter dictionary")
        }
        // The system dictionary is a definition source, not a bilingual translation API.
        throw TranslationFailure.notInLocalDictionary
    }
}
