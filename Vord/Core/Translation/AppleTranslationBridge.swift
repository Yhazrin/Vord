import Foundation
import SwiftUI
import Translation

@MainActor
final class AppleTranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private struct Pending {
        var ticket: Int
        var text: String
        var source: Language
        var target: Language
        var continuation: CheckedContinuation<TranslationResult, Error>
    }

    private var pending: Pending?
    private var waiters: [Pending] = []
    private var ticket = 0
    private var timeoutTask: Task<Void, Never>?

    func translate(text: String, from source: Language, to target: Language) async throws -> TranslationResult {
        ticket += 1
        let requestTicket = ticket
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let item = Pending(ticket: requestTicket, text: text, source: source, target: target, continuation: continuation)
                if pending == nil { begin(item) } else { waiters.append(item) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(ticket: requestTicket) }
        }
    }

    private func cancel(ticket: Int) {
        if pending?.ticket == ticket { finish(.failure(CancellationError()), ticket: ticket) }
        else if let index = waiters.firstIndex(where: { $0.ticket == ticket }) {
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    func consume(_ session: TranslationSession) async {
        guard let pending else { return }
        let ticket = pending.ticket
        do {
            try await session.prepareTranslation()
            guard self.pending?.ticket == ticket else { return }
            let response = try await session.translate(pending.text)
            guard self.pending?.ticket == ticket else { return }
            let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            finish(
                .success(
                    TranslationResult(
                        sourceText: pending.text,
                        translatedText: translated,
                        sourceLanguage: pending.source,
                        targetLanguage: pending.target,
                        phonetic: nil,
                        partOfSpeech: nil,
                        englishDefinition: nil,
                        chineseDefinition: nil,
                        exampleSentence: nil
                    )
                ),
                ticket: ticket
            )
        } catch {
            finish(.failure(Self.map(error)), ticket: ticket)
        }
    }

    private func begin(_ item: Pending) {
        pending = item
        var configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: item.source.localeIdentifier),
            target: Locale.Language(identifier: item.target.localeIdentifier)
        )
        configuration.invalidate()
        self.configuration = configuration
        timeoutTask?.cancel()
        let ticket = item.ticket
        timeoutTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            self.finish(.failure(TranslationFailure.languageResourcesMissing), ticket: ticket)
        }
    }

    private func finish(_ result: Result<TranslationResult, Error>, ticket: Int) {
        guard let pending, pending.ticket == ticket else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        pending.continuation.resume(with: result)
        self.pending = nil
        self.configuration = nil
        if !waiters.isEmpty {
            begin(waiters.removeFirst())
        }
    }

    private static func map(_ error: Error) -> Error {
        if #available(macOS 26.0, *) , TranslationError.notInstalled ~= error {
            return TranslationFailure.languageResourcesMissing
        }
        if TranslationError.unsupportedLanguagePairing ~= error
            || TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error {
            return TranslationFailure.languageResourcesMissing
        }
        return TranslationFailure.failed(error.localizedDescription)
    }
}

struct AppleTranslationTaskModifier: ViewModifier {
    @ObservedObject var bridge: AppleTranslationBridge

    func body(content: Content) -> some View {
        content.translationTask(bridge.configuration) { session in
            await bridge.consume(session)
        }
    }
}
