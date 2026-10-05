import SwiftUI

struct SpeakingPracticeView: View {
    @ObservedObject var library: SpeakingLibrary
    var material: SpeakingMaterial
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var exercise: SpeakingExercise
    @State private var clock = Date()
    @State private var answer = ""
    @State private var error: String?

    init(library: SpeakingLibrary, material: SpeakingMaterial) {
        self.library = library; self.material = material
        _exercise = State(initialValue: SpeakingExercise(part: material.part))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(material.part == .any ? "Speaking practice" : material.part.rawValue).font(AppTypography.ui(size: 24, weight: .semibold))
                Spacer()
                SubtleButton(title: "Close") { dismiss() }
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
                }
            }
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive) }
            if exercise.phase == .finished {
                HStack {
                    SubtleButton(title: "Discuss answer") { discuss() }.disabled(answer.trimmed.isEmpty)
                    Spacer()
                    QuietButton(title: "To revisit") { save(.revisit) }.disabled(!exercise.canRecord)
                    PrimaryButton(title: "Recalled") { save(.recalled) }.disabled(!exercise.canRecord)
                }
                .help("Your own assessment. Word review schedules stay unchanged.")
            }
        }.padding(28).frame(width: 650, height: 610).background(AppColors.contentBackground)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                clock = now; exercise.advance(to: now)
            }
    }
    @ViewBuilder private var phaseAction: some View {
        switch exercise.phase {
        case .ready:
            PrimaryButton(title: "Prepare") { clock = Date(); exercise.prepare(at: clock) }
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
        guard exercise.canRecord else { return }
        let attempt = SpeakingAttempt(materialID: material.id, question: question, answer: answer.trimmed,
            outcome: outcome, seconds: exercise.spokenSeconds, referenceRevealed: exercise.referenceRevealed)
        do { try library.record(attempt); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func discuss() {
        dependencies.agent.appendToDraft("请点评我这段口语回答：先看有没有回答问题，再选一处最重要的表达或语法修正，给一个更自然的版本，最后问一个迁移问题。不要从文本推测发音、口语流利度或给雅思分数。\n问题：\(question)\n我的回答：\(answer)\n参考（只是例子）：\(material.english)")
        dismiss()
        NotificationCenter.default.post(name: .vordNavigate, object: AppTab.agent)
    }
}
