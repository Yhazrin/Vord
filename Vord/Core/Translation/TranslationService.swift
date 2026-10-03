import Foundation
import Translation

final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
    let id = "apple"
    let displayName = "Apple Translation"
    private let bridge: AppleTranslationBridge

    init(bridge: AppleTranslationBridge) {
        self.bridge = bridge
    }

    func translate(
        text: String,
        from sourceLanguage: Language,
        to targetLanguage: Language
    ) async throws -> TranslationResult {
        if #available(macOS 26.0, *) {
            let source = Locale.Language(identifier: sourceLanguage.localeIdentifier)
            let target = Locale.Language(identifier: targetLanguage.localeIdentifier)
            let status = await LanguageAvailability().status(from: source, to: target)
            if status == .installed {
                do {
                    return try await translateInstalled(
                        text: text,
                        from: sourceLanguage,
                        to: targetLanguage,
                        source: source,
                        target: target
                    )
                } catch let failure as TranslationFailure {
                    throw failure
                } catch {
                    if Self.isMissingLanguage(error) {
                        return try await bridge.translate(text: text, from: sourceLanguage, to: targetLanguage)
                    }
                    throw TranslationFailure.failed(error.localizedDescription)
                }
            }
            if status == .unsupported {
                throw TranslationFailure.languageResourcesMissing
            }
        }
        return try await bridge.translate(text: text, from: sourceLanguage, to: targetLanguage)
    }

    @available(macOS 26.0, *)
    private func translateInstalled(
        text: String,
        from sourceLanguage: Language,
        to targetLanguage: Language,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> TranslationResult {
        let session = TranslationSession(installedSource: source, target: target)
        let response = try await session.translate(text)
        return TranslationResult(
            sourceText: text.trimmed,
            translatedText: response.targetText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            phonetic: nil,
            partOfSpeech: nil,
            englishDefinition: nil,
            chineseDefinition: nil,
            exampleSentence: nil
        )
    }

    private static func isMissingLanguage(_ error: Error) -> Bool {
        if #available(macOS 26.0, *) , TranslationError.notInstalled ~= error {
            return true
        }
        return TranslationError.unsupportedLanguagePairing ~= error
            || TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error
    }
}

struct DictionaryLookup: Sendable {
    var results: [TranslationResult]
    var requiresSelection: Bool
}

final class TranslationService: @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [String: any TranslationProvider] = [:]
    private var selectedID: String
    private var cached: [String: TranslationResult] = [:]

    init(selectedID: String) {
        self.selectedID = selectedID
    }

    func register(_ provider: any TranslationProvider) {
        lock.lock()
        providers[provider.id] = provider
        cached.removeAll()
        lock.unlock()
    }

    func select(id: String) {
        lock.lock()
        selectedID = id
        lock.unlock()
    }

    func currentID() -> String {
        lock.lock()
        defer { lock.unlock() }
        return selectedID
    }

    func options() -> [(id: String, name: String)] {
        lock.lock()
        defer { lock.unlock() }
        return ["apple", "local"].compactMap { id in
            guard let provider = providers[id] else { return nil }
            return (provider.id, provider.displayName)
        }
    }

    func translate(text: String) async throws -> TranslationResult {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { throw TranslationFailure.emptyInput }
        let source = LanguageDetector.detect(trimmed)
        let target: Language = source == .english ? .chinese : .english
        let provider = try currentProvider()
        let cacheKey = provider.id + ":" + trimmed
        if let cached = cachedResult(cacheKey) { return cached }
        var result: TranslationResult
        // A translation is a fallback; dictionary entries retain all senses and definitions.
        if let offline = registeredProvider("local"),
           let local = try? await offline.translate(text: trimmed, from: source, to: target) {
            result = local
        } else {
            try Task.checkCancellation()
            result = try await provider.translate(text: trimmed, from: source, to: target)
            result.providerName = result.providerName ?? provider.displayName
        }
        try Task.checkCancellation()
        result = await enrich(result)
        cache(result, key: cacheKey)
        return result
    }

    /// Chinese reverse lookup never commits the first synonym without the learner choosing it.
    func lookup(text: String) async throws -> DictionaryLookup {
        let raw = text.trimmed
        guard !raw.isEmpty else { throw TranslationFailure.emptyInput }
        let language = LanguageDetector.detect(raw)
        if let local = registeredProvider("local") as? LocalDictionaryProvider {
            let candidates = try await Task.detached {
                try local.store.search(raw, from: language)
            }.value
            try Task.checkCancellation()
            if language == .english,
               let exact = candidates.first(where: { $0.match == .exact || $0.match == .inflection }) {
                return DictionaryLookup(results: [await enrich(exact.result(for: raw))], requiresSelection: false)
            }
            if !candidates.isEmpty {
                return DictionaryLookup(results: candidates.map { $0.result(for: raw) }, requiresSelection: true)
            }
        }
        let result = try await translate(text: raw)
        return DictionaryLookup(results: [result], requiresSelection: language == .chinese)
    }

    func enrich(_ original: TranslationResult) async -> TranslationResult {
        var result = SampleLexicon.enrich(original)
        let needsDefinition = result.englishDefinition?.trimmed.isEmpty != false
        let needsExample = result.exampleSentence?.trimmed.isEmpty != false
        guard needsDefinition || needsExample else { return result }
        let headword = result.english
        let definition = await Task.detached(operation: { DictionaryStore.systemDefinition(headword) }).value
        if needsDefinition, let definition, LanguageDetector.detect(definition) == .english {
            result.englishDefinition = definition
        }
        // Dictionary text only. An empty result stays empty; nothing is invented or requested from AI.
        if needsExample, let example = DictionaryExample.extract(from: definition, headword: headword) {
            result.exampleSentence = example
        }
        return result
    }

    func invalidateCache() {
        lock.lock(); defer { lock.unlock() }; cached.removeAll()
    }
    private func cachedResult(_ key: String) -> TranslationResult? {
        lock.lock(); defer { lock.unlock() }; return cached[key]
    }
    private func cache(_ result: TranslationResult, key: String) {
        lock.lock(); defer { lock.unlock() }
        if cached.count >= 500 { cached.removeAll() }
        cached[key] = result
    }
    private func registeredProvider(_ id: String) -> (any TranslationProvider)? {
        lock.lock(); defer { lock.unlock() }; return providers[id]
    }
    private func currentProvider() throws -> any TranslationProvider {
        lock.lock()
        defer { lock.unlock() }
        if let provider = providers[selectedID] ?? providers.values.first {
            return provider
        }
        throw TranslationFailure.failed("No translation provider is registered.")
    }
}
