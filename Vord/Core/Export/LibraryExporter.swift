import Foundation

enum LibraryExporter {
    static func data(from library: LibraryExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCodec.shared.format(date))
        }
        return try encoder.encode(library)
    }

    static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = DateCodec.shared.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        return try decoder.decode(LibraryExport.self, from: data)
    }
}

enum CaptureService {
    static func matches(_ result: TranslationResult, raw: String) -> Bool {
        result.sourceText.caseInsensitiveCompare(raw.trimmed) == .orderedSame
    }

    static func draft(from result: TranslationResult) -> EntryDraft {
        let english = cleanHeadword(result.english)
        let chinese: String
        if result.sourceLanguage == .chinese, let fuller = result.chineseDefinition?.trimmed, !fuller.isEmpty {
            chinese = fuller
        } else {
            chinese = result.chinese.trimmed
        }
        return EntryDraft(
            english: english,
            chinese: chinese,
            lemma: english.lowercased().nilIfEmpty,
            phonetic: result.phonetic,
            partOfSpeech: result.partOfSpeech,
            englishDefinition: result.englishDefinition,
            chineseDefinition: result.chineseDefinition,
            exampleSentence: result.exampleSentence,
            sourceSentence: result.sourceText,
            source: result.providerName ?? "translation"
        )
    }

    static func pendingDraft(raw: String) -> EntryDraft {
        let text = raw.trimmed
        if LanguageDetector.detect(text) == .english {
            return EntryDraft(english: text, chinese: "", lemma: text.lowercased(), source: "pending")
        }
        return EntryDraft(english: "", chinese: text, source: "pending")
    }

    static func capture(
        raw: String,
        result: TranslationResult?,
        repository: any VocabularyRepository,
        translation: TranslationService,
        now: Date = Date()
    ) async throws -> VocabularyEntry {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { throw TranslationFailure.emptyInput }
        if let result, matches(result, raw: trimmed) {
            return try await repository.upsert(draft(from: result), now: now)
        }
        let saved = try await repository.upsert(pendingDraft(raw: trimmed), now: now)
        Task {
            await complete(id: saved.id, raw: trimmed, translation: translation, repository: repository)
        }
        return saved
    }

    private static func complete(
        id: UUID,
        raw: String,
        translation: TranslationService,
        repository: any VocabularyRepository
    ) async {
        do {
            let translated = try await translation.translate(text: raw)
            guard let current = try await repository.entry(id: id), !current.archived else { return }
            let source = LanguageDetector.detect(raw)
            guard source == .english
                    ? current.english.caseInsensitiveCompare(raw.trimmed) == .orderedSame && current.chinese.trimmed.isEmpty
                    : current.chinese == raw.trimmed && current.english.trimmed.isEmpty else { return }
            var draft = draft(from: translated)
            draft.existingID = id
            if current.source != "pending" { draft.source = current.source }
            _ = try await repository.upsert(draft, now: Date())
        } catch {
            // Keep the original word. The user can edit it later.
        }
    }

    private static func cleanHeadword(_ text: String) -> String {
        var value = text.trimmed
        while value.hasSuffix(".") || value.hasSuffix("。") {
            value.removeLast()
            value = value.trimmed
        }
        return value
    }
}

enum SampleSeeder {
    static func load(into repository: any VocabularyRepository, now: Date = Date()) async throws {
        for lexeme in SampleLexicon.entries {
            _ = try await repository.upsert(SampleLexicon.draft(from: lexeme, source: "sample"), now: now)
        }
    }
}
