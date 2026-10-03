import Foundation

/// UTF-16 ranges match AppKit's text system, including sentences containing emoji.
enum DictionarySelection {
    static func wordRange(in text: String, atUTF16 index: Int) -> NSRange? {
        let value = text as NSString
        guard index >= 0, index < value.length else { return nil }
        let expression = try! NSRegularExpression(pattern: #"[A-Za-z]+(?:[-'’][A-Za-z]+)*"#)
        return expression.matches(in: text, range: NSRange(location: 0, length: value.length))
            .first { NSLocationInRange(index, $0.range) }?.range
    }

    static func word(in text: String, selected range: NSRange) -> String? {
        let value = text as NSString
        guard range.location != NSNotFound, range.length > 0, range.location >= 0,
              range.location <= value.length, range.length <= value.length - range.location else { return nil }
        return ClipboardWord.parse(value.substring(with: range))
    }
}

@MainActor
final class DictionarySelectionModel: ObservableObject {
    @Published private(set) var word = ""
    @Published private(set) var result: TranslationResult?
    @Published private(set) var candidates: [TranslationResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var inLibrary = false
    @Published private(set) var saved = false
    @Published private(set) var error: String?
    private let translation: TranslationService
    private let repository: any VocabularyRepository
    private var generation = 0
    private var sourceSentence = ""
    private var active = false

    init(translation: TranslationService, repository: any VocabularyRepository) {
        self.translation = translation; self.repository = repository
    }

    func lookup(word: String, sentence: String) async {
        guard !Task.isCancelled, let lexical = ClipboardWord.parse(word) else { return }
        generation += 1
        active = true
        let request = generation
        self.word = lexical; sourceSentence = String(sentence.prefix(4000))
        result = nil; candidates = []; error = nil; saved = false; inLibrary = false; isSaving = false
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let lookup = try await translation.lookup(text: lexical)
            guard request == generation, !Task.isCancelled else { return }
            if lookup.requiresSelection { candidates = Array(lookup.results.prefix(8)) }
            else { result = lookup.results.first }
            if let result {
                let exists = try await contains(result.english)
                guard request == generation, !Task.isCancelled else { return }
                inLibrary = exists
            }
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func choose(_ candidate: TranslationResult) async {
        guard active, !Task.isCancelled, candidates.contains(candidate), !isSaving else { return }
        let request = generation
        result = candidate; candidates = []; isLoading = true; error = nil
        defer { if request == generation { isLoading = false } }
        do {
            let exists = try await contains(candidate.english)
            guard request == generation, !Task.isCancelled else { return }
            inLibrary = exists
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func add() async {
        guard active, !Task.isCancelled, let result, !isLoading, !isSaving, !inLibrary, !saved else { return }
        let request = generation
        let sentence = sourceSentence
        isSaving = true; error = nil
        defer { if request == generation { isSaving = false } }
        do {
            let exists = try await contains(result.english)
            guard request == generation, !Task.isCancelled else { return }
            if exists { inLibrary = true; return }
            var draft = CaptureService.draft(from: result)
            draft.exampleSentence = sentence.nilIfEmpty ?? draft.exampleSentence
            draft.sourceSentence = sentence.nilIfEmpty
            draft.source = "Vord reading · " + (result.providerName ?? "Dictionary")
            _ = try await repository.upsert(draft, now: Date())
            guard request == generation, !Task.isCancelled else { return }
            saved = true; inLibrary = true
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func dismiss() {
        generation += 1
        active = false; result = nil; candidates = []
        isLoading = false; isSaving = false
    }

    private func contains(_ english: String) async throws -> Bool {
        try await repository.libraryRows().contains { $0.english.caseInsensitiveCompare(english) == .orderedSame }
    }
}
