import SwiftUI

struct SpeakingPracticeView: View {
    @ObservedObject var library: SpeakingLibrary
    @State private var material: SpeakingMaterial
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var exercise: SpeakingExercise
    @State private var clock = Date()
    @State private var answer = ""
    @State private var error: String?
    @State private var entries: [VocabularyEntry] = []
    @State private var ratings: [UUID: ReviewRating] = [:]
    @State private var saving = false
    @State private var prepared = false
    @StateObject private var wordReview = SpeakingWordReview()

    init(library: SpeakingLibrary, material: SpeakingMaterial) {
        self.library = library; _material = State(initialValue: material)
        _exercise = State(initialValue: SpeakingExercise(part: material.part))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(material.part == .any ? "Speaking practice" : material.part.rawValue).font(AppTypography.ui(size: 24, weight: .semibold))
                Spacer()
                SubtleButton(title: "Close") { dismiss() }.disabled(saving)
            }
            Text(question).font(AppTypography.ui(size: 22)).textSelection(.enabled)
            HStack {
                Text(exercise.phase.rawValue)
                Spacer()
                if exercise.phase == .finished {
                    Text("\(exercise.spokenSeconds)s practised").font(AppTypography.caption)
                } else {
                    let seconds = exercise.remaining(at: clock)
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .monospacedDigit().font(AppTypography.ui(size: 32, weight: .medium))
                }
            }.accessibilityElement(children: .combine)
            phaseAction
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if exercise.phase != .finished {
                        let targets = SpeakingConnections.keywords(material, entries: entries)
                        if !targets.isEmpty {
                            Text(targets.prefix(6).map(\.english).joined(separator: " · "))
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    if exercise.referenceRevealed {
                        DictionaryText(material.english, translation: dependencies.translation, repository: dependencies.repository, fontSize: 19, lineSpacing: 5)
                        Text(material.chinese).foregroundStyle(AppColors.secondaryText)
                        Text(material.notes).font(AppTypography.caption)
                    } else if exercise.phase != .ready {
                        SubtleButton(title: "Show reference") { exercise.reveal() }
                    }
                    if exercise.phase == .speaking || exercise.phase == .finished {
                        Text(exercise.phase == .finished ? "Your answer · one thing to improve" : "Your answer or a quick note")
                            .font(AppTypography.caption)
                        TextEditor(text: $answer).font(AppTypography.body).frame(height: 130).accessibilityLabel("Speaking answer or note")
                            .help("Speak aloud; enter a note or paste a transcript. No microphone is recorded.")
                    }
                    if exercise.phase == .finished, !entries.isEmpty { vocabularyAssessment }
                }
            }
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive) }
            if exercise.phase == .finished {
                HStack {
                    SubtleButton(title: "Discuss answer") { discuss() }.disabled(answer.trimmed.isEmpty || saving)
                    Spacer()
                    QuietButton(title: "To revisit") { save(.revisit) }.disabled(!exercise.canRecord || saving)
                    PrimaryButton(title: saving ? "Saving…" : "Recalled") { save(.recalled) }.disabled(!exercise.canRecord || saving)
                }
                .help("Only the words you explicitly assess below update their productive review schedule.")
            }
        }.padding(28).frame(width: 650, height: 610).background(AppColors.contentBackground)
            .interactiveDismissDisabled(saving)
            .task {
                do { material = try library.preparePractice(material); prepared = true; await refreshEntries() }
                catch { self.error = error.localizedDescription }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in Task { await refreshEntries() } }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                clock = now; exercise.advance(to: now)
            }
    }
    private var vocabularyAssessment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            Text("Use in your answer").font(AppTypography.headline)
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.english).font(AppTypography.body).lineLimit(2)
                    Spacer(minLength: 8)
                    if wordReview.savedIDs.contains(entry.id) {
                        Text("Review saved").foregroundStyle(AppColors.secondaryText)
                    } else {
                        ratingButton("Needed help", entry: entry, rating: .again)
                        ratingButton("Used myself", entry: entry, rating: .good)
                    }
                }
            }
            Text("Only selected words update Chinese → English review.")
                .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
        }
    }
    private func ratingButton(_ title: String, entry: VocabularyEntry, rating: ReviewRating) -> some View {
        Button { ratings[entry.id] = ratings[entry.id] == rating ? nil : rating } label: {
            Text(title).font(AppTypography.caption).padding(.horizontal, 10).padding(.vertical, 7)
                .background(ratings[entry.id] == rating ? AppColors.inputSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(saving).accessibilityAddTraits(ratings[entry.id] == rating ? .isSelected : [])
    }
    private func refreshEntries() async {
        do { entries = SpeakingConnections.linkedEntries(material, entries: try await dependencies.repository.activeEntries()) }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private var phaseAction: some View {
        switch exercise.phase {
        case .ready:
            PrimaryButton(title: "Prepare") { clock = Date(); exercise.prepare(at: clock) }.disabled(!prepared)
        case .preparing:
            PrimaryButton(title: "Start speaking") { clock = Date(); exercise.beginSpeaking(at: clock) }
        case .speaking:
            QuietButton(title: "Finish speaking") { clock = Date(); exercise.finish(at: clock) }
                .disabled(exercise.remaining(at: clock) >= material.part.speakingSeconds)
        case .finished: EmptyView()
        }
    }
    private var question: String {
        material.prompt.isEmpty ? "Use this expression in a short answer about your own experience: \(material.title)" : material.prompt
    }
    private func save(_ outcome: SpeakingAttempt.Outcome) {
        guard exercise.canRecord, !saving else { return }
        saving = true; error = nil
        Task {
            defer { saving = false }
            do {
                guard answer.count <= 12000, library.warning == nil,
                      library.materials.contains(where: { $0.id == material.id }) else {
                    throw AIError.configuration(library.warning ?? "Keep your answer under 12,000 characters and choose an available material.")
                }
                for entry in entries {
                    if let rating = ratings[entry.id] {
                        try await wordReview.save(entryID: entry.id, rating: rating, material: material,
                            repository: dependencies.repository, scheduler: dependencies.scheduler)
                    }
                }
                let attempt = SpeakingAttempt(materialID: material.id, question: question, answer: answer.trimmed,
                    outcome: outcome, seconds: exercise.spokenSeconds, referenceRevealed: exercise.referenceRevealed,
                    practicedEntryIDs: Array(wordReview.savedIDs))
                try library.record(attempt); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func discuss() {
        dependencies.agent.appendToDraft("请点评我这段口语回答：先看有没有回答问题，再选一处最重要的表达或语法修正，给一个更自然的版本，最后问一个迁移问题。不要从文本推测发音、口语流利度或给雅思分数。\n问题：\(question)\n我的回答：\(answer)\n参考（只是例子）：\(material.english)")
        dismiss()
        NotificationCenter.default.post(name: .vordNavigate, object: AppTab.agent)
    }
}
