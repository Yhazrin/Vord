import SwiftUI
import AppKit

struct ContextView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var ai: AIConfigurationStore
    @EnvironmentObject private var history: LearningHistory
    var onSettings: () -> Void
    @State private var entries: [VocabularyEntry] = []
    @State private var selection = Set<UUID>()
    @State private var search = ""
    @State private var topic = "Everyday life"
    @State private var level = "B1 · Intermediate"
    @State private var record: ContextRecord?
    @State private var generating = false
    @State private var startedAt: Date?
    @State private var generationTask: Task<Void, Never>?
    @State private var error: String?
    @State private var saved = Set<UUID>()
    @State private var revealTranslation = true
    @State private var hideWords = false
    @State private var revealed = Set<UUID>()
    @State private var replacement: ContextExample?
    @State private var confirmReplacement = false
    @State private var selectionExpanded = true
    @Environment(\.vordLayout) private var layout
    private let levels = ["A2 · Elementary", "B1 · Intermediate", "B2 · Upper intermediate", "C1 · Advanced"]

    private var selected: [VocabularyEntry] { entries.filter { selection.contains($0.id) } }
    private var filtered: [VocabularyEntry] {
        entries.filter { search.trimmed.isEmpty || $0.headword.localizedCaseInsensitiveContains(search) || $0.gloss.contains(search) }
    }
    var body: some View {
        PageScroll(width: 1100) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    Text(selected.isEmpty ? "Choose words from your library." : "\(selection.count) of 8 selected")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                    Spacer()
                    SubtleButton(title: "AI settings", action: onSettings)
                }
                if layout.usesColumns {
                HStack(alignment: .top, spacing: 28) {
                    wordSelection.frame(width: 250)
                    Rectangle().fill(AppColors.subtleBorder).frame(width: 1, height: 470)
                    results.frame(maxWidth: .infinity, alignment: .leading)
                }
                } else {
                    DisclosureGroup("Words and situation", isExpanded: $selectionExpanded) {
                        wordSelection.padding(.top, 16)
                    }.font(AppTypography.headline)
                    Hairline()
                    results.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task {
            await load()
            if record == nil, let latest = history.contexts.first {
                record = latest
                selection = Set(latest.examples.map(\.entryID)).intersection(Set(entries.map(\.id)))
                topic = latest.topic; level = latest.level
            }
        }
        .onDisappear { generationTask?.cancel() }
        .onChange(of: hideWords) { _, _ in revealed = [] }
        .onChange(of: generating) { _, value in
            if value && !layout.usesColumns { selectionExpanded = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in Task { await load() } }
        .alert("Replace the saved example?", isPresented: $confirmReplacement) {
            Button("Replace") { if let replacement { Task { await save(replacement, replacing: true) } } }
            Button("Cancel", role: .cancel) { replacement = nil }
        } message: { Text("The current sentence and translation will be replaced.") }
    }
    private var wordSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Words").font(AppTypography.headline)
                Spacer()
                Text("\(selection.count) / 8").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            }
            TextField("Search words", text: $search).textFieldStyle(.roundedBorder)
            if entries.isEmpty {
                Text("Add words with Chinese meanings to begin.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            Button {
                                if selection.contains(entry.id) { selection.remove(entry.id) }
                                else if selection.count < 8 { selection.insert(entry.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selection.contains(entry.id) ? "checkmark.square.fill" : "square")
                                        .font(AppTypography.ui(size: 14)).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.headword).font(.system(size: 18, design: .serif))
                                        Text(entry.gloss).font(AppTypography.ui(size: 12)).foregroundStyle(AppColors.secondaryText).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(generating || (selection.count == 8 && !selection.contains(entry.id)))
                        }
                    }
                }.frame(height: 250)
                HStack {
                    SubtleButton(title: "Random 5") { selection = Set(entries.shuffled().prefix(5).map(\.id)) }
                    Spacer(minLength: 0)
                    SubtleButton(title: "Clear") { selection = [] }
                }.disabled(generating)
            }
            Hairline()
            LineField(title: "Situation", text: $topic).disabled(generating)
            MenuSelect(name: "Level", selection: $level, choices: levels, label: { $0 }).disabled(generating)
            if ai.selected == nil {
                SubtleButton(title: "Connect an AI service", action: onSettings)
            }
            if generating {
                HStack {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Generating · \(Int(context.date.timeIntervalSince(startedAt ?? context.date)))s")
                            .font(AppTypography.caption).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    SubtleButton(title: "Cancel") { generationTask?.cancel() }
                }
            } else {
                PrimaryButton(title: record == nil ? "Generate sentences" : "New sentences") { generate() }
                    .disabled(selected.isEmpty || ai.selected == nil)
            }
            if !history.contexts.isEmpty {
                Hairline()
                Text("Saved sets").font(AppTypography.headline)
                ForEach(history.contexts.prefix(10)) { item in
                    Button {
                        record = item; saved = []; revealed = []; error = nil
                        selection = Set(item.examples.map(\.entryID)).intersection(Set(entries.map(\.id)))
                        topic = item.topic; level = item.level
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.examples.map(\.word).joined(separator: ", ")).lineLimit(2)
                            Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(AppTypography.ui(size: 11)).foregroundStyle(AppColors.tertiaryText)
                        }.font(AppTypography.caption).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(generating)
                }
            }
        }
    }
    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive).textSelection(.enabled) }
            if let record {
                VStack(alignment: .leading, spacing: 14) {
                    Text(record.topic).font(AppTypography.ui(size: 24))
                    HStack(spacing: 18) {
                        Toggle("Hide words", isOn: $hideWords)
                        Toggle("Show Chinese", isOn: $revealTranslation)
                    }.toggleStyle(.checkbox).font(AppTypography.caption)
                }
                ForEach(Array(record.examples.enumerated()), id: \.element.id) { index, example in
                    exampleView(example, number: index + 1)
                    Hairline()
                }
                HStack(alignment: .top) {
                    Text(record.level).font(AppTypography.ui(size: 11)).foregroundStyle(AppColors.tertiaryText)
                    Spacer()
                    SubtleButton(title: "Copy sentences") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.examples.map { "\($0.sentence)\n\($0.translation)" }.joined(separator: "\n\n"), forType: .string)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No examples yet").font(AppTypography.ui(size: 28))
                    Text("Choose words to generate sentences.")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText).lineSpacing(5)
                }.padding(.top, 28)
            }
        }
    }
    private func exampleView(_ example: ContextExample, number: Int) -> some View {
        let hidden = hideWords && !revealed.contains(example.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(hidden ? "Sentence \(number)" : example.word)
                    .font(hidden ? AppTypography.caption : .system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(hidden ? AppColors.secondaryText : AppColors.primaryText)
                Spacer()
                if !hidden { SpeechButton(text: example.sentence) }
            }
            DictionaryText(hidden ? ContextGenerator.blankedSentence(example) : example.sentence,
                translation: dependencies.translation, repository: dependencies.repository,
                fontSize: 22, lineSpacing: 6, highlightWord: hidden ? nil : example.word)
                // Recreate the selectable native text view so its accessibility/copy value
                // cannot retain a revealed answer after switching into practice mode.
                .id(hidden)
            if revealTranslation && !hidden {
                Text(example.translation).font(AppTypography.body).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
                Text(example.explanation).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            }
            if hidden {
                QuietButton(title: "Reveal word") { revealed.insert(example.id) }
            } else {
                SubtleButton(title: saved.contains(example.id) ? "Saved" : "Save to word") {
                    Task { await save(example) }
                }.disabled(saved.contains(example.id) || generating)
            }
        }.padding(.vertical, 8)
    }
    private func load() async {
        do {
            entries = try await dependencies.repository.activeEntries().filter(DictationMatching.isEligible)
            selection.formIntersection(Set(entries.map(\.id)))
        } catch { self.error = error.localizedDescription }
    }
    private func generate() {
        guard !generating, let descriptor = ai.selected else { return }
        let words = selected, scene = String(topic.trimmed.prefix(200)), difficulty = level
        let previous = record?.examples ?? []
        generating = true; error = nil; saved = []; startedAt = Date()
        generationTask = Task {
            defer { generating = false }
            do {
                let generated = try await ContextGenerator.generate(entries: words, topic: scene, level: difficulty,
                    previous: previous, provider: HTTPAIProvider(descriptor: descriptor), model: descriptor.modelID)
                try Task.checkCancellation()
                let next = ContextRecord(topic: scene.isEmpty ? "Everyday life" : scene, level: difficulty,
                                         provider: descriptor.name, model: generated.response.modelID, examples: generated.examples,
                                         inputTokens: generated.response.inputTokens, outputTokens: generated.response.outputTokens,
                                         duration: Date().timeIntervalSince(startedAt ?? Date()), attempts: generated.attempts)
                record = next; revealed = []
                try history.append(next)
            } catch is CancellationError {} catch let failure as URLError where failure.code == .cancelled {}
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(_ example: ContextExample, replacing: Bool = false) async {
        do {
            guard var entry = try await dependencies.repository.entry(id: example.entryID) else {
                throw AIError.configuration("This word has been removed from your library.")
            }
            let sentence = example.sentence + "\n" + example.translation
            if !replacing, let existing = entry.exampleSentence, !existing.trimmed.isEmpty, existing != sentence {
                replacement = example; confirmReplacement = true; return
            }
            entry.exampleSentence = sentence
            entry.updatedAt = Date()
            try await dependencies.repository.update(entry)
            saved.insert(example.id)
        } catch { self.error = error.localizedDescription }
    }
    private func highlight(_ text: String, word: String) -> AttributedString {
        var value = AttributedString(text)
        for stringRange in ContextGenerator.wordRanges(in: text, word: word) {
            guard let start = AttributedString.Index(stringRange.lowerBound, within: value),
                  let end = AttributedString.Index(stringRange.upperBound, within: value) else { continue }
            let range = start..<end
            value[range].foregroundColor = AppColors.accent
            value[range].font = AppTypography.ui(size: 22, weight: .semibold)
        }
        return value
    }
}
