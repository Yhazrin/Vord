import SwiftUI

struct StudySessionBar: View {
    var title: String
    var progress: String
    var trailing: String = "Pause"
    var onTrailing: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(AppTypography.ui(size: 13, weight: .medium))
                .foregroundStyle(AppColors.primaryText)
            Text(progress)
                .font(AppTypography.ui(size: 13))
                .foregroundStyle(AppColors.secondaryText)
                .monospacedDigit()
            Spacer(minLength: 12)
            Button(trailing, action: onTrailing)
                .buttonStyle(.plain)
                .font(AppTypography.ui(size: 13))
                .foregroundStyle(AppColors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StudyPrompt: View {
    var text: String
    var phonetic: String?
    var answer: String?
    var example: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(AppTypography.studyWord(text))
                .foregroundStyle(AppColors.primaryText)
                .tracking(text.count > 18 ? -0.2 : -1.1)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
            if let phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppTypography.ui(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
            }
            if let answer, !answer.isEmpty {
                Text(answer)
                    .font(AppTypography.studyWord(answer).mapSize { min($0, 28) })
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
                    .padding(.top, 18)
            }
            if let example, !example.isEmpty {
                Text(example)
                    .font(AppTypography.ui(size: 15))
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct StudyBlank: View {
    @Binding var text: String
    var placeholder: String
    var focused: Bool
    var disabled: Bool
    var onSubmit: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AppTypography.input)
                        .foregroundStyle(AppColors.tertiaryText)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(AppTypography.input)
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
                    .disabled(disabled)
                    .onSubmit(onSubmit)
            }
            .frame(maxWidth: 300, minHeight: 32)
            Rectangle()
                .fill(AppColors.primaryText.opacity(fieldFocused ? 0.5 : 0.16))
                .frame(width: 280, height: 1)
        }
        .onChange(of: focused) { _, value in
            fieldFocused = value
        }
        .onAppear { fieldFocused = focused }
    }
}

private extension Font {
    func mapSize(_ transform: (CGFloat) -> CGFloat) -> Font { self }
}
