import SwiftUI

@MainActor
final class AddViewModel: ObservableObject {
    @Published var query = ""
    @Published var meaning = ""
    @Published var example = ""
    @Published var exampleBaseline = ""
    @Published var exampleEdited = false
    @Published var tags = ""
    @Published var source = ""
    @Published var preview: TranslationResult?
    @Published var candidates: [TranslationResult] = []
    @Published var isTranslating = false
    @Published var message: String?
    @Published var savedCount = 0
    @Published private(set) var lastSavedWord: String?
    @Published var isSaving = false
    private var lookupTask: Task<Void, Never>?

    func cancelLookup() { lookupTask?.cancel(); isTranslating = false }

    func scheduleLookup(_ translation: TranslationService) {
        cancelLookup()
        let raw = query.trimmed
        preview = nil; candidates = []; meaning = ""
        example = ""; exampleBaseline = ""; exampleEdited = false
        guard !raw.isEmpty else { return }
        message = nil
        isTranslating = true
        lookupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await self?.lookupNow(raw, translation: translation)
        }
    }

    func choose(_ candidate: TranslationResult, translation: TranslationService) async {
        let raw = query.trimmed
        guard CaptureService.matches(candidate, raw: raw) else { return }
        cancelLookup()
        preview = candidate; candidates = []
        isTranslating = true
        let enriched = await translation.enrich(candidate)
        guard query.trimmed == raw, preview?.english == candidate.english else { return }
        preview = enriched; isTranslating = false; message = nil
        applyLookedUpExample(enriched.exampleSentence)
    }

    func save(repository: any VocabularyRepository, translation: TranslationService) async {
        let raw = query.trimmed
        guard !raw.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        cancelLookup()
        var result = preview.flatMap { CaptureService.matches($0, raw: raw) ? $0 : nil }
        do {
            if result == nil, meaning.trimmed.isEmpty {
                let found = try await translation.lookup(text: raw)
                guard query.trimmed == raw else { return }
                if found.requiresSelection {
                    candidates = found.results
                    message = "Choose the English word that fits your meaning."
                    return
                }
                result = found.results.first
            } else if result == nil, LanguageDetector.detect(raw) == .english,
                      let found = try? await translation.lookup(text: raw), !found.requiresSelection {
                result = found.results.first
            }
            if let selected = result { result = await translation.enrich(selected) }
            guard query.trimmed == raw else { return }
            var draft: EntryDraft
            if !meaning.trimmed.isEmpty {
                draft = result.map(CaptureService.draft) ?? CaptureService.pendingDraft(raw: raw)
                if LanguageDetector.detect(raw) == .english {
                    draft.chinese = meaning.trimmed; draft.chineseDefinition = meaning.trimmed
                } else {
                    if draft.english.caseInsensitiveCompare(meaning.trimmed) != .orderedSame {
                        draft.englishDefinition = nil; draft.phonetic = nil; draft.partOfSpeech = nil
                        draft.exampleSentence = nil
                    }
                    draft.english = meaning.trimmed; draft.lemma = meaning.trimmed.lowercased()
                    // The manual English headword can still supply a local English definition.
                    if let manual = try? await translation.lookup(text: meaning.trimmed), !manual.requiresSelection,
                       let entry = manual.results.first {
                        draft.englishDefinition = entry.englishDefinition
                        draft.phonetic = entry.phonetic; draft.partOfSpeech = entry.partOfSpeech
                        if draft.exampleSentence?.trimmed.isEmpty != false {
                            draft.exampleSentence = entry.exampleSentence
                        }
                    }
                }
                draft.source = "Manual"
            } else if let result {
                draft = CaptureService.draft(from: result)
            } else { throw TranslationFailure.notInLocalDictionary }
            guard query.trimmed == raw else { return }
            draft.tags = tags.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
            draft.source = source.trimmed.nilIfEmpty ?? draft.source ?? result?.providerName ?? "Manual"
            if exampleEdited { draft.exampleSentence = example.trimmed.nilIfEmpty }
            let saved = try await repository.upsert(draft, now: Date())
            lastSavedWord = saved.headword
            query = ""; meaning = ""; example = ""; exampleBaseline = ""; exampleEdited = false; tags = ""; source = ""
            preview = nil; candidates = []; message = "Saved"
            savedCount += 1
        } catch { message = error.localizedDescription }
    }

    private func applyLookedUpExample(_ sentence: String?) {
        guard !exampleEdited else { return }
        let value = sentence?.trimmed ?? ""
        exampleBaseline = value
        example = value
    }

    private func lookupNow(_ raw: String, translation: TranslationService) async {
        do {
            let found = try await translation.lookup(text: raw)
            guard !Task.isCancelled, query.trimmed == raw else { return }
            candidates = found.requiresSelection ? found.results : []
            preview = found.requiresSelection ? nil : found.results.first
            applyLookedUpExample(preview?.exampleSentence)
            message = nil; isTranslating = false
        } catch {
            guard !Task.isCancelled, query.trimmed == raw else { return }
            preview = nil; candidates = []; message = error.localizedDescription; isTranslating = false
        }
    }
}

struct AddView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model = AddViewModel()
    @State private var detailsPresented = false
    @State private var meaningExpanded = false
    @State private var savedFeedbackVisible = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var focused = false
    @Environment(\.vordLayout) private var layout

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width - layout.pagePadding * 2 >= 760
            VStack(alignment: .leading, spacing: 20) {
                FieldChrome(focused: focused, minHeight: 48) {
                    HStack(spacing: 12) {
                        CaptureInput(text: $model.query, focused: $focused) { Task { await save() } }
                            .frame(height: 28)
                        if !model.query.isEmpty {
                            ChromeIconButton(symbol: "xmark", help: "Clear word") { model.query = ""; focused = true }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    lookupPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide {
                        Divider()
                        ScrollView { detailsFields.padding(.bottom, 12) }
                            .frame(width: 230)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Hairline()
                HStack(spacing: 16) {
                    if !wide {
                        QuietButton(title: "Details…") { detailsPresented = true }
                            .popover(isPresented: $detailsPresented, arrowEdge: .bottom) {
                                ScrollView { detailsFields.padding(24) }
                                    .frame(width: 310, height: 380)
                            }
                    }
                    ZStack(alignment: .leading) {
                        if savedFeedbackVisible, let word = model.lastSavedWord {
                            SavedWordFeedback(word: word).id(model.savedCount)
                                .transition(AppMotion.reveal(reducedMotion))
                        } else {
                            Text(model.isSaving ? "Saving…" : (model.message ?? ""))
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    PrimaryButton(title: "Save word", shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        Task { await save() }
                    }
                    .disabled(model.query.trimmed.isEmpty || model.isSaving ||
                              (!model.candidates.isEmpty && model.preview == nil && model.meaning.trimmed.isEmpty))
                }
            }
            .modifier(PageInset(top: 28, bottom: 24))
        }
        .foregroundStyle(AppColors.primaryText)
        .task { focused = true }
        .disabled(model.isSaving)
        .onDisappear { model.cancelLookup() }
        .onChange(of: model.query) { _, query in
            if !query.isEmpty { savedFeedbackVisible = false }
            model.scheduleLookup(dependencies.translation)
        }
        .onChange(of: model.savedCount) { _, _ in focused = true; detailsPresented = false }
        .task(id: model.savedCount) {
            guard model.savedCount > 0 else { return }
            withAnimation(AppMotion.feedback(reducedMotion)) { savedFeedbackVisible = true }
            do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
            withAnimation(AppMotion.reading(reducedMotion)) { savedFeedbackVisible = false }
        }
    }

    private var lookupPane: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 0).id("lookup-top")
                    if model.isTranslating && model.preview == nil {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Looking up…").font(AppTypography.body)
                        }
                    } else if let preview = model.preview {
                        previewBlock(preview)
                            .modifier(MotionArrival()).id(preview.english)
                        if LanguageDetector.detect(model.query) == .chinese {
                            SubtleButton(title: "Choose another word") { model.scheduleLookup(dependencies.translation) }
                        }
                    } else if !model.candidates.isEmpty {
                        Text("Choose a word").font(AppTypography.headline)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.candidates, id: \.english) { candidate in
                                Button {
                                    Task { await model.choose(candidate, translation: dependencies.translation) }
                                } label: {
                                    HStack(alignment: .top, spacing: 16) {
                                        Text(candidate.english).font(AppTypography.title)
                                            .frame(width: 132, alignment: .leading)
                                        Text(candidate.chinese).font(AppTypography.body)
                                            .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(AppTypography.caption)
                                    }
                                    .padding(.vertical, 14).contentShape(Rectangle())
                                }.buttonStyle(MotionPressStyle())
                                Hairline()
                            }
                        }
                        .modifier(MotionArrival())
                    } else {
                        Text(model.query.isEmpty ? "Enter an English or Chinese word." : "No dictionary entry found.")
                            .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        if !model.query.isEmpty {
                            SubtleButton(title: "Enter a meaning manually") {
                                meaningExpanded = true; detailsPresented = true
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8).padding(.bottom, 16)
            }
            .onChange(of: model.query) { _, _ in scroll.scrollTo("lookup-top", anchor: .top) }
            .onChange(of: model.preview?.english) { _, _ in scroll.scrollTo("lookup-top", anchor: .top) }
        }
    }

    private var detailsFields: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Details").font(AppTypography.headline)
            DisclosureGroup(isExpanded: $meaningExpanded) {
                LineField(title: LanguageDetector.detect(model.query) == .english ? "Chinese meaning" : "English word",
                          text: $model.meaning, placeholder: "Enter your own meaning")
                    .padding(.top, 8)
            } label: { Text("Custom meaning").font(AppTypography.caption) }
            .animation(AppMotion.reading(reducedMotion), value: meaningExpanded)
            LineField(title: "Example", text: Binding(
                get: { model.example },
                set: { value in
                    model.example = value
                    if value != model.exampleBaseline { model.exampleEdited = true }
                }
            ), placeholder: "Optional", multiline: true)
            LineField(title: "Tags", text: $model.tags, placeholder: "e.g. IELTS, reading")
            LineField(title: "Source or note", text: $model.source, placeholder: "Optional")
        }
    }

    private func previewBlock(_ preview: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(preview.english).font(.system(size: 34, weight: .medium, design: .serif))
                    .tracking(-0.4).fixedSize(horizontal: false, vertical: true)
                SpeechButton(text: preview.english)
            }
            HStack(spacing: 10) {
                if let phonetic = preview.phonetic { Text(phonetic) }
                if let part = preview.partOfSpeech { Text(part) }
            }.font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
            Text(preview.chinese).font(AppTypography.ui(size: 20)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .id(preview.english + "-zh")
            if let definition = preview.englishDefinition, !definition.trimmed.isEmpty {
                Text("English definition").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    .padding(.top, 6)
                Text(definition).font(AppTypography.ui(size: 17)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .id(preview.english + "-en")
            }
            if let example = preview.exampleSentence?.trimmed, !example.isEmpty {
                Text("Example").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    .padding(.top, 6)
                Text(example).font(AppTypography.body).italic().lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let provider = preview.providerName {
                Text(provider).font(AppTypography.caption).foregroundStyle(AppColors.tertiaryText)
                    .padding(.top, 8)
            }
        }
    }
    private func save() async {
        await model.save(repository: dependencies.repository, translation: dependencies.translation)
    }
}
