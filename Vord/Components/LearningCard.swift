import SwiftUI
import AVFoundation

struct LearningCard<Content: View>: View {
    var centersContent = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: centersContent ? .center : .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: centersContent ? .center : .leading)
            .padding(24)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct StatusPill: View {
    var title: String
    var color: Color = AppColors.accent
    var body: some View {
        Text(title).font(AppTypography.ui(size: 11, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.09), in: Capsule())
    }
}

@MainActor
private final class WordSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
struct SpeechButton: View {
    var text: String
    @StateObject private var speaker = WordSpeaker()
    var body: some View {
        Button { speaker.speak(text) } label: {
            Image(systemName: "speaker.wave.2").font(AppTypography.ui(size: 14))
                .foregroundStyle(AppColors.accent).padding(10)
                .background(AppColors.accentWash, in: Circle())
        }.buttonStyle(.plain).help("Listen in English").accessibilityLabel("Listen to \(text)")
            .onDisappear { speaker.stop() }
    }
}

struct EmptyLearningState: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(AppTypography.ui(size: 24, weight: .light))
                .foregroundStyle(AppColors.secondaryText)
            Text(title).font(AppTypography.reading)
            Text(detail).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
        }.padding(40).frame(maxWidth: .infinity)
    }
}
