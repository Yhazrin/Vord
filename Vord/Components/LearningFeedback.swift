import SwiftUI

struct StudyProgress: View {
    var completed: Int
    var total: Int
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var fraction: CGFloat { min(1, max(0, CGFloat(completed) / CGFloat(max(1, total)))) }
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(AppColors.accentWash)
                .overlay(alignment: .leading) {
                    Capsule().fill(AppColors.primaryText)
                        .frame(width: geometry.size.width)
                        .scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
                .clipShape(Capsule())
        }
        .frame(height: 5)
        .animation(AppMotion.feedback(reduced), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(completed) of \(total)")
    }
}

private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.51))
            path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.69))
            path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.34))
        }
    }
}

struct SuccessMark: View {
    var size: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var drawn: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().stroke(AppColors.primaryText.opacity(0.18), lineWidth: 1)
            CheckStroke().trim(from: 0, to: reduced ? 1 : drawn)
                .stroke(AppColors.primaryText, style: StrokeStyle(lineWidth: size > 30 ? 2.5 : 1.7, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .scaleEffect(reduced ? 1 : 0.88 + 0.12 * drawn)
        .onAppear { withAnimation(AppMotion.feedback(reduced)) { drawn = 1 } }
        .accessibilityHidden(true)
    }
}

struct SavedWordFeedback: View {
    var word: String
    var body: some View {
        HStack(spacing: 8) {
            SuccessMark(size: 20)
            Text("Saved · \(word)").font(AppTypography.caption).lineLimit(1)
        }
        .foregroundStyle(AppColors.primaryText)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(AppColors.accentWash, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct StudyCompletion: View {
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 16) {
            SuccessMark(size: 54)
            Text(title).font(AppTypography.reading)
            Text(detail).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .padding(32).frame(maxWidth: .infinity)
        .modifier(MotionArrival())
    }
}
