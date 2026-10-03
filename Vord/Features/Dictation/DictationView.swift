import SwiftUI

@MainActor
final class DictationModel: ObservableObject {
    @Published var count = 10
    @Published var mode: DictationMode = .chineseToEnglish
    @Published var available = 0
    @Published var tag = "All tags"
    @Published var tags = ["All tags"]
    @Published var starting = false
    @Published var questions: [DictationQuestion] = []
    @Published var index = 0
    @Published var answer = ""
    @Published var revealed = false
    @Published var wasCorrect = false
    @Published var outcomes: [DictationOutcome] = []
    @Published var finished = false
    @Published var error: String?

    var roundCount: Int { min(count, available) }

    var current: DictationQuestion? {
        guard questions.indices.contains(index) else { return nil }
        return questions[index]
    }

    var correctCount: Int { outcomes.filter(\.correct).count }

    var missed: [DictationOutcome] { outcomes.filter { !$0.correct } }

    func refresh(_ repository: any VocabularyRepository) async {
        do {
            let entries = try await repository.activeEntries()
            tags = ["All tags"] + Set(entries.flatMap(\.tags)).sorted()
            available = entries.filter { DictationMatching.isEligible($0) && (tag == "All tags" || $0.tags.contains(tag)) }.count
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func start(_ repository: any VocabularyRepository) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let entries = try await repository.activeEntries()
            tags = ["All tags"] + Set(entries.flatMap(\.tags)).sorted()
            available = entries.filter { DictationMatching.isEligible($0) && (tag == "All tags" || $0.tags.contains(tag)) }.count
            var random = SystemRandomNumberGenerator()
            let next = DictationMatching.questions(
                from: entries.filter { tag == "All tags" || $0.tags.contains(tag) },
                count: roundCount,
                mode: mode,
                random: &random
            )
            guard !next.isEmpty else { return }
            questions = next
            index = 0
            answer = ""
            revealed = false
            outcomes = []
            finished = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func retryMissed() {
        let next = missed.map(\.question).shuffled()
        guard !next.isEmpty else { return }
        questions = next; index = 0; answer = ""; revealed = false
        outcomes = []; finished = false; error = nil
    }
    func skip() {
        guard current != nil, !revealed else { return }
        wasCorrect = false; answer = ""; revealed = true
    }
    func check() {
        guard let current, !revealed, !answer.trimmed.isEmpty else { return }
        wasCorrect = DictationMatching.matches(input: answer, accepted: current.accepted)
        revealed = true
    }

    func advance() {
        guard let current, revealed else { return }
        outcomes.append(DictationOutcome(question: current, attempt: answer.trimmed, correct: wasCorrect))
        if index + 1 >= questions.count {
            finished = true
            return
        }
        index += 1
        answer = ""
        revealed = false
    }

    func end() {
        questions = []
        outcomes = []
        finished = false
        revealed = false
        answer = ""
        index = 0
    }
}

struct DictationOutcome: Identifiable, Equatable, Codable {
    var question: DictationQuestion
    var attempt: String
    var correct: Bool

    var id: UUID { question.id }
}

struct DictationView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: LearningHistory
    @State private var confirmEnd = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.vordLayout) private var layout
    @ObservedObject var model: DictationModel
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if model.finished {
                summary
            } else if model.current != nil {
                session
            } else {
                setup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            if model.questions.isEmpty {
                model.count = settings.dictationCount
                model.mode = settings.dictationMode
            }
            await model.refresh(dependencies.repository)
        }
        .onChange(of: model.finished) { _, finished in
            guard finished else { return }
            do { try history.append(ExamRecord(mode: model.mode.title, outcomes: model.outcomes)) }
            catch { model.error = "Results are shown, but history could not be saved: " + error.localizedDescription }
        }
        .onChange(of: model.tag) { _, _ in Task { await model.refresh(dependencies.repository) } }
        .alert("End this exam?", isPresented: $confirmEnd) {
            Button("End Exam", role: .destructive) { model.end() }
            Button("Continue", role: .cancel) {}
        } message: { Text("Unfinished results will be discarded.") }
        .onChange(of: model.count) { _, count in
            settings.setDictationCount(count)
        }
        .onChange(of: model.mode) { _, mode in
            settings.setDictationMode(mode)
        }
        .onChange(of: model.index) { _, _ in
            focused = true
        }
    }

    private var setup: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                PageHeader(
                    title: "Dictation",
                    subtitle: "Practice without changing review dates."
                )

                ControlRow(title: "Collection") {
                    MenuSelect(name: "Tag", selection: $model.tag, choices: model.tags, label: { $0 })
                }
                LearningCard {
                SectionBlock(title: "Words", detail: availability) {
                    FieldChrome(minHeight: 56) {
                        HStack(spacing: AppSpacing.md) {
                            Text("\(model.count)")
                                .font(AppTypography.stat)
                                .foregroundStyle(AppColors.primaryText)
                                .monospacedDigit()
                                .frame(minWidth: 36, alignment: .leading)
                            Spacer(minLength: AppSpacing.md)
                            Stepper("Words", value: $model.count, in: 1...100)
                                .labelsHidden()
                        }
                    }
                }

                ControlRow(title: "Mode") {
                    MenuSelect(
                        name: "Mode",
                        selection: $model.mode,
                        choices: DictationMode.allCases,
                        label: { $0.title }
                    )
                }

                }
                if let error = model.error {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                PrimaryButton(title: model.starting ? "Preparing…" : "Start Exam") {
                    Task { await model.start(dependencies.repository) }
                }
                .disabled(model.roundCount == 0 || model.starting)
                if !history.exams.isEmpty {
                    SectionBlock(title: "Recent exams", detail: "Your last 100 completed rounds are kept on this Mac.") {
                        ForEach(history.exams.prefix(5)) { exam in
                            HStack {
                                Text(exam.createdAt, style: .date)
                                Text(exam.mode).foregroundStyle(AppColors.secondaryText)
                                Spacer()
                                Text("\(exam.correctCount) / \(exam.outcomes.count)").monospacedDigit()
                            }.font(AppTypography.caption).padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var availability: String {
        if model.available == 0 { return "No words ready." }
        let library = model.available == 1 ? "1 word in the library." : "\(model.available) words in the library."
        if model.count > model.available {
            return "\(library) This round uses \(model.roundCount)."
        }
        return library
    }

    private var session: some View {
        PageColumn {
            VStack(spacing: 0) {
                sessionBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sessionBody: some View {
        if let question = model.current {
            VStack(spacing: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    PageHeader(
                        title: "Dictation",
                        subtitle: "\(model.index + 1) of \(model.questions.count)"
                    )
                    StudyProgress(completed: model.index, total: model.questions.count)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: AppSpacing.lg)

                VStack(spacing: AppSpacing.lg) {
                    ZStack {
                        VStack(spacing: AppSpacing.md) {
                            VStack(spacing: AppSpacing.md) {
                                Text(question.prompt)
                                    .font(AppTypography.studyWord(question.prompt))
                                    .foregroundStyle(AppColors.primaryText)
                                    .tracking(-0.5)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 520)
                                if let phonetic = question.phonetic {
                                    Text(phonetic)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.xl)
                        }
                        .frame(maxWidth: .infinity, minHeight: min(220, layout.studyHeight))
                        .padding(.horizontal, AppSpacing.lg)
                        .id(question.id)
                        .transition(AppMotion.reveal(reducedMotion))
                    }
                    .animation(AppMotion.reading(reducedMotion), value: question.id)

                    FieldChrome(focused: focused, minHeight: 52, alignment: .center) {
                        ZStack {
                            if model.answer.isEmpty {
                                Text(question.direction.answerPlaceholder)
                                    .font(AppTypography.input)
                                    .foregroundStyle(AppColors.tertiaryText)
                                    .allowsHitTesting(false)
                            }
                            TextField("", text: $model.answer)
                                .textFieldStyle(.plain)
                                .font(AppTypography.input)
                                .foregroundStyle(AppColors.primaryText)
                                .multilineTextAlignment(.center)
                                .focused($focused)
                                .disabled(model.revealed)
                                .onSubmit(submit)
                        }
                    }
                    .frame(maxWidth: 420)

                    if model.revealed {
                        VStack(spacing: AppSpacing.xs) {
                            HStack(spacing: 8) {
                                if model.wasCorrect { SuccessMark(size: 20) }
                                Text(model.wasCorrect ? "Correct" : model.answer.isEmpty ? "Skipped" : "Not quite")
                                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            }
                            DictionaryText(question.expected, translation: dependencies.translation,
                                repository: dependencies.repository, fontSize: 22, alignment: .center)
                        }
                        .transition(AppMotion.reveal(reducedMotion))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: AppSpacing.lg)

                HStack(spacing: AppSpacing.sm) {
                    PrimaryButton(
                        title: model.revealed ? (isLast ? "Finish" : "Next") : "Check",
                        shortcut: model.revealed ? KeyboardShortcut(.return) : nil,
                        action: submit
                    )
                    .disabled(!model.revealed && model.answer.trimmed.isEmpty)
                    if !model.revealed { SubtleButton(title: "Skip") { model.skip() } }
                    QuietButton(title: "End") { confirmEnd = true }
                }
            }
            .animation(AppMotion.reading(reducedMotion), value: model.revealed)
            .onAppear { focused = true }
        }
    }

    private var summary: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                PageHeader(title: "Dictation", subtitle: summarySubtitle)

                StudyCompletion(title: "Round complete",
                    detail: model.missed.isEmpty ? "You recalled every word in this round." : "\(model.outcomes.count) words practiced. Revisit the missed words when you're ready.")
                StudyProgress(completed: model.outcomes.count, total: model.outcomes.count)

                Text("\(model.correctCount) / \(model.outcomes.count)")
                    .font(AppTypography.heroStat)
                    .foregroundStyle(AppColors.primaryText)
                    .monospacedDigit()
                    .tracking(-1.2)
                    .contentTransition(.numericText(value: Double(model.correctCount)))

                if !model.missed.isEmpty {
                    SectionBlock(title: "Missed") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.missed.enumerated()), id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(item.question.prompt)
                                        .font(AppTypography.rowTitle)
                                        .foregroundStyle(AppColors.primaryText)
                                    Text("Your answer: " + (item.attempt.isEmpty ? "Skipped" : item.attempt))
                                        .font(AppTypography.caption).foregroundStyle(AppColors.tertiaryText)
                                    Text(item.question.expected)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                                .padding(.vertical, AppSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if index < model.missed.count - 1 {
                                    Hairline()
                                }
                            }
                        }
                    }
                }

                if let error = model.error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive) }
                HStack(spacing: AppSpacing.sm) {
                    if !model.missed.isEmpty {
                        PrimaryButton(title: "Practice missed words") { model.retryMissed() }
                    }
                    QuietButton(title: "New exam") {
                        Task { await model.start(dependencies.repository) }
                    }
                    QuietButton(title: "Done") { model.end() }
                }
            }
        }
    }

    private var summarySubtitle: String {
        model.missed.isEmpty ? "All clear." : "A few to look at again."
    }

    private var isLast: Bool { model.index + 1 >= model.questions.count }

    private func submit() {
        if model.revealed {
            model.advance()
            focused = true
        } else {
            model.check()
        }
    }
}
