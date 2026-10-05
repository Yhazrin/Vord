import SwiftUI

struct SpeakingPracticeView: View {
    @ObservedObject var library: SpeakingLibrary
    var material: SpeakingMaterial
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var phase = "Ready"
    @State private var beganAt: Date?
    @State private var speakingAt: Date?
    @State private var showReference = false
    @State private var answer = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(material.part == .any ? "Speaking practice" : material.part.rawValue).font(AppTypography.ui(size: 24, weight: .semibold))
                Spacer()
                SubtleButton(title: "Close") { dismiss() }
            }
            Text(material.prompt.isEmpty ? "Use this expression in a short answer about your own experience: \(material.title)" : material.prompt)
                .font(AppTypography.ui(size: 22)).textSelection(.enabled)
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                let elapsed = elapsed(at: clock.date)
                let limit = phase == "Prepare" ? material.part.preparationSeconds : material.part.speakingSeconds
                HStack {
                    Text(phase == "Ready" ? "Ready" : (phase == "Prepare" ? "Prepare" : "Speak"))
                    Spacer()
                    Text("\(max(0, limit - elapsed) / 60):\(String(format: "%02d", max(0, limit - elapsed) % 60))")
                        .monospacedDigit().font(AppTypography.ui(size: 32, weight: .medium))
                }
            }
            if phase == "Ready" {
                PrimaryButton(title: "Prepare") { phase = "Prepare"; beganAt = Date() }
            } else if phase == "Prepare" {
                PrimaryButton(title: "Start speaking") { phase = "Speak"; beganAt = Date(); speakingAt = beganAt }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showReference {
                        DictionaryText(material.english, translation: dependencies.translation, repository: dependencies.repository, fontSize: 19, lineSpacing: 5)
                        Text(material.chinese).foregroundStyle(AppColors.secondaryText)
                        Text(material.notes).font(AppTypography.caption)
                    } else if phase != "Ready" {
                        SubtleButton(title: "Show reference") { showReference = true }
                    }
                    if phase == "Speak" {
                        Text("Your answer or a quick note").font(AppTypography.caption)
                        TextEditor(text: $answer).font(AppTypography.body).frame(height: 130).accessibilityLabel("Speaking answer or note")
                        Text("Speak aloud; paste a transcript if you want feedback. No microphone is recorded.")
                            .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive) }
            if phase == "Speak" {
                HStack {
                    SubtleButton(title: "Discuss answer") { discuss() }.disabled(answer.trimmed.isEmpty)
                    Spacer()
                    QuietButton(title: "To revisit") { save(.revisit) }
                    PrimaryButton(title: "Recalled") { save(.recalled) }
                }
                Text("Your assessment · no word review schedule changes").font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
            }
        }.padding(28).frame(width: 650, height: 610).background(AppColors.contentBackground)
    }
    private func elapsed(at date: Date) -> Int { max(0, Int(date.timeIntervalSince(beganAt ?? date))) }
    private func save(_ outcome: SpeakingAttempt.Outcome) {
        guard let speakingAt else { return }
        let seconds = max(1, min(material.part.speakingSeconds, Int(Date().timeIntervalSince(speakingAt))))
        let attempt = SpeakingAttempt(materialID: material.id,
            question: material.prompt.isEmpty ? material.title : material.prompt, answer: answer.trimmed,
            outcome: outcome, seconds: seconds, referenceRevealed: showReference)
        do { try library.record(attempt); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func discuss() {
        dependencies.agent.appendToDraft("请点评我这段口语回答：先看有没有回答问题，再选一处最重要的表达或语法修正，给一个更自然的版本，最后问一个迁移问题。不要从文本推测发音、口语流利度或给雅思分数。\n问题：\(material.prompt)\n我的回答：\(answer)\n参考（只是例子）：\(material.english)")
        dismiss()
        NotificationCenter.default.post(name: .vordNavigate, object: AppTab.agent)
    }
}
