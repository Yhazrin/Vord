import AppKit
import SwiftUI

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var card: ReviewCard?
    @Published var showAnswer = false
    @Published var remaining = 0
    @Published var isEmpty = false
    @Published var isSaving = false
    @Published var isLoading = true
    @Published var error: String?
    @Published var total = 0
    @Published var completed = 0
    @Published var attempts = 0
    @Published var forgotten = 0
    @Published var repeated = false
    @Published private(set) var lastRating: ReviewRating?
    @Published private(set) var answers: [String: ReviewSessionAnswer] = [:]
    let shortRound: Bool
    var roundSummary: ReviewRoundSummary { ReviewRoundSummary(answers: Array(answers.values)) }

    private var queue: [ReviewCard] = []
    private var repeats: [String: Int] = [:]
    private var didLoad = false
    private let repository: any VocabularyRepository
    private let scheduler: any ReviewScheduling
    private let mode: ReviewMode
    private let plannedEntryIDs: [UUID]?

    init(repository: any VocabularyRepository, scheduler: any ReviewScheduling, mode: ReviewMode, plannedEntryIDs: [UUID]? = nil, shortRound: Bool = false) {
        self.repository = repository; self.scheduler = scheduler; self.mode = mode
        self.plannedEntryIDs = plannedEntryIDs
        self.shortRound = shortRound
    }
    func load() async {
        guard !didLoad else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let cards: [ReviewCard]
            if let plannedEntryIDs {
                let snapshot = try await repository.exportSnapshot()
                let entries = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                let states = Dictionary(snapshot.reviewStates.map { ($0.entryID, $0) }, uniquingKeysWith: { _, latest in latest })
                var seen = Set<UUID>()
                cards = plannedEntryIDs.filter { seen.insert($0).inserted }.compactMap { id in
                    guard let entry = entries[id], !entry.archived, DictationMatching.isEligible(entry), let state = states[id] else { return nil }
                    let eligible = state.directions.filter { mode == .mixed || $0.direction.rawValue == mode.rawValue }
                    guard let next = eligible.min(by: { $0.dueAt < $1.dueAt }), next.dueAt <= Date() else { return nil }
                    return ReviewCard(entry: entry, direction: next.direction, state: next)
                }
            } else { cards = try await repository.dueCards(now: Date(), limit: 240) }
            queue = Array(Self.makeQueue(cards: cards, mode: mode).prefix(shortRound ? 5 : 80))
            total = queue.count; didLoad = true; advance()
        } catch { self.error = error.localizedDescription }
    }
    func reveal() { guard card != nil, !isSaving else { return }; showAnswer = true }
    func confirm() { gradeIfAnswered(.good) }
    func gradeIfAnswered(_ rating: ReviewRating) {
        guard showAnswer, !isSaving else { return }
        isSaving = true
        Task { await rate(rating) }
    }
    func rate(_ rating: ReviewRating) async {
        guard let card, showAnswer else { isSaving = false; return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            guard let state = try await repository.reviewState(entryID: card.entry.id),
                  let entry = try await repository.entry(id: card.entry.id), !entry.archived else {
                throw SQLiteError.message("This word was removed or archived. Restart the session to refresh it.")
            }
            let result = scheduler.schedule(state: state, direction: card.direction, rating: rating, now: Date())
            try await repository.recordReview(result)
            answers[card.id] = ReviewSessionAnswer(entry: entry, rating: rating)
            lastRating = rating
            queue.removeFirst()
            attempts += 1
            if rating == .again { forgotten += 1 }
            let repeatCount = repeats[card.id] ?? 0
            if rating == .again, repeatCount < 2, let next = result.state.state(for: card.direction) {
                repeats[card.id] = repeatCount + 1
                let retry = ReviewCard(entry: entry, direction: card.direction, state: next)
                queue.insert(retry, at: min(3, queue.count))
            } else { completed += 1 }
            advance()
        } catch {
            // Keep the revealed card and allow a retry; never drop unsaved answers.
            self.error = error.localizedDescription
        }
    }
    func intervalLabel(_ rating: ReviewRating) -> String {
        guard let card else { return "" }
        let state = ReviewState(entryID: card.entry.id, directions: [card.state])
        let result = scheduler.schedule(state: state, direction: card.direction, rating: rating, now: Date())
        let seconds = result.log.interval
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) hr" }
        return "\(Int((seconds / 86400).rounded())) d"
    }
    private func advance() {
        showAnswer = false; card = queue.first; remaining = queue.count
        isEmpty = card == nil
        repeated = card.map { repeats[$0.id] != nil } ?? false
    }
    static func makeQueue(cards: [ReviewCard], mode: ReviewMode) -> [ReviewCard] {
        let filtered = cards.filter { card in
            guard DictationMatching.isEligible(card.entry) else { return false }
            switch mode {
            case .englishToChinese: return card.direction == .englishToChinese
            case .chineseToEnglish: return card.direction == .chineseToEnglish
            case .mixed: return true
            }
        }
        // Avoid showing both sides of the same word consecutively where possible.
        var remaining = filtered.shuffled(), result: [ReviewCard] = []
        while !remaining.isEmpty {
            let index = remaining.firstIndex { $0.entry.id != result.last?.entry.id } ?? 0
            result.append(remaining.remove(at: index))
        }
        return result
    }
}

struct ReviewView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settings: AppSettings
    var onExit: () -> Void

    var body: some View {
        ReviewSession(model: dependencies.reviewModel(), speaking: dependencies.speaking, onExit: onExit)
    }
}

private struct ReviewSession: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var model: ReviewViewModel
    @ObservedObject var speaking: SpeakingLibrary
    var onExit: () -> Void
    @State private var monitor: Any?
    @State private var speakingMaterial: SpeakingMaterial?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.vordLayout) private var layout

    var body: some View {
        content
            .task { await model.load() }
            .onAppear { installMonitor() }
            .onDisappear { removeMonitor() }
            .sheet(item: $speakingMaterial) { item in SpeakingPracticeView(library: speaking, material: item) }
    }

    @ViewBuilder
    private var content: some View {
        if model.card != nil, !model.isLoading, !model.isEmpty {
            PageColumn {
                reviewStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            PageScroll { reviewStack }
        }
    }

    private var reviewStack: some View {
        VStack(alignment: .leading, spacing: 24) {
                if model.isLoading {
                    HStack {
                        Spacer()
                        SubtleButton(title: "Pause session", action: onExit)
                    }
                    ProgressView("Preparing your words…")
                } else if model.isEmpty {
                    LearningCard {
                        if model.total > 0 {
                            StudyCompletion(title: model.shortRound ? "Round complete" : "Session complete",
                                detail: "\(model.roundSummary.practicedCount) words practiced · \(model.attempts) answers")
                            roundResults
                            StudyProgress(completed: model.completed, total: model.total)
                            let words = model.roundSummary.recalled + model.roundSummary.revisit
                            SpeakingNextSteps(materials: SpeakingConnections.studyPrompts(materials: speaking.materials,
                                entries: words, revisitIDs: speaking.revisitIDs, limit: 2), entries: words,
                                title: "From recall to speaking") { speakingMaterial = $0 }
                        } else {
                            EmptyLearningState(symbol: "checkmark.seal", title: "No cards due",
                                detail: "No words are due in this review mode.")
                        }
                        HStack { Spacer(); PrimaryButton(title: "Back to Today", action: onExit); Spacer() }
                    }
                } else if let card = model.card {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.md) {
                            sessionProgress
                            Spacer(minLength: AppSpacing.sm)
                            StatusPill(title: model.repeated ? "Relearning" : card.direction.title)
                            SubtleButton(title: "Pause session", action: onExit)
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            sessionProgress
                            HStack {
                                StatusPill(title: model.repeated ? "Relearning" : card.direction.title)
                                Spacer()
                                SubtleButton(title: "Pause session", action: onExit)
                            }
                        }
                    }
                    StudyProgress(completed: model.completed, total: model.total)
                    Spacer(minLength: AppSpacing.lg)
                    ZStack {
                    VStack(spacing: AppSpacing.md) {
                        prompt(card, revealed: model.showAnswer)
                            .padding(.vertical, AppSpacing.lg)
                        if model.showAnswer, let example = card.entry.exampleSentence, !example.isEmpty {
                            DictionaryText(example, translation: dependencies.translation,
                                repository: dependencies.repository, fontSize: 16,
                                color: AppColors.secondaryText, alignment: .center)
                                .frame(maxWidth: 460)
                        }
                        if model.showAnswer,
                           let material = SpeakingConnections.studyPrompts(materials: speaking.materials, entries: [card.entry], limit: 1).first {
                            QuietButton(title: "Use \(card.entry.english) in an answer") { speakingMaterial = material }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: layout.studyHeight)
                    .padding(.horizontal, AppSpacing.lg)
                    .id("\(card.id)-\(model.attempts)")
                    .transition(AppMotion.reveal(reducedMotion))
                    }
                    .animation(AppMotion.reading(reducedMotion), value: model.attempts)
                    .animation(AppMotion.reading(reducedMotion), value: model.showAnswer)
                    Spacer(minLength: AppSpacing.lg)
                    if model.showAnswer {
                        HStack(spacing: 12) {
                            ForEach(Array(ReviewRating.allCases.enumerated()), id: \.element) { index, rating in
                                Button { model.gradeIfAnswered(rating) } label: {
                                    VStack(spacing: 7) {
                                        Text("\(index + 1) · \(rating.title)").font(AppTypography.button)
                                        Text(model.intervalLabel(rating)).font(AppTypography.ui(size: 11)).opacity(0.7)
                                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
                                        .foregroundStyle(rating == .good ? AppColors.primaryButtonText : AppColors.primaryText)
                                        .background(rating == .good ? AppColors.primaryButton : AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(MotionPressStyle()).disabled(model.isSaving)
                                    .help(rating == .again ? "Returns later in this session, up to twice. Still forgotten words stay due in 10 minutes." : "Schedule the next review for \(model.intervalLabel(rating)).")
                            }
                        }
                    } else {
                        HStack { Spacer(); PrimaryButton(title: "Reveal answer  ·  Space") { model.reveal() }; Spacer() }
                    }
                    Text("Space reveals · 1–4 rate · Return is Good · Esc pauses")
                        .font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                }
                if let error = model.error {
                    Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive)
                    if model.card == nil { QuietButton(title: "Try again") { Task { await model.load() } } }
                }
            }
    }

    private var roundResults: some View {
        let result = model.roundSummary
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.lg) {
                Text("Recalled · \(result.recalled.count)")
                Text("To revisit · \(result.revisit.count)").foregroundStyle(AppColors.secondaryText)
            }.font(AppTypography.headline)
                .accessibilityElement(children: .combine)
            if !result.revisit.isEmpty {
                Text(result.revisit.map(\.headword).joined(separator: " · "))
                    .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, AppSpacing.md)
            .help("Based on your last saved rating for each direction in this session.")
    }

    private var sessionProgress: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(model.completed) / \(model.total)")
                .font(AppTypography.caption).monospacedDigit()
                .contentTransition(.numericText(value: Double(model.completed)))
                .animation(AppMotion.feedback(reducedMotion), value: model.completed)
                .accessibilityLabel("\(model.completed) of \(model.total) cards completed")
            if let rating = model.lastRating {
                HStack(spacing: 6) {
                    if rating != .again { SuccessMark(size: 17).id(model.attempts) }
                    Text(rating == .again ? "We'll revisit it." : "Review saved")
                        .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                }.id(model.attempts).modifier(MotionArrival())
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func prompt(_ card: ReviewCard, revealed: Bool) -> some View {
        let showingEnglish = card.direction == .englishToChinese
        let promptText = showingEnglish ? card.entry.headword : card.entry.gloss
        VStack(spacing: AppSpacing.md) {
            Text(promptText)
                .font(promptFont(promptText))
                .foregroundStyle(AppColors.primaryText)
                .tracking(promptText.count > 24 ? -0.2 : -0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
            if showingEnglish, let phonetic = card.entry.phonetic {
                Text(phonetic)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
            }
            if revealed {
                VStack(spacing: AppSpacing.sm) {
                    Text(showingEnglish ? card.entry.gloss : card.entry.headword)
                        .font(AppTypography.reading)
                        .foregroundStyle(AppColors.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                    if !showingEnglish, let phonetic = card.entry.phonetic {
                        Text(phonetic)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .padding(.top, AppSpacing.sm)
                .transition(AppMotion.reveal(reducedMotion))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func promptFont(_ text: String) -> Font {
        AppTypography.studyWord(text)
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if speakingMaterial != nil { return false }
        if NSApp.keyWindow?.identifier?.rawValue == "vord.dictionaryPopover" { return false }
        if NSApp.keyWindow?.firstResponder is DictionaryNSTextView { return false }
        if NSApp.keyWindow is NSPanel {
            return false
        }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
            return false
        }
        let characters = event.charactersIgnoringModifiers ?? ""
        switch characters {
        case " ":
            model.reveal()
            return true
        case "1":
            model.gradeIfAnswered(.again)
            return true
        case "2":
            model.gradeIfAnswered(.hard)
            return true
        case "3":
            model.gradeIfAnswered(.good)
            return true
        case "4":
            model.gradeIfAnswered(.easy)
            return true
        case "\r", "\u{3}":
            model.confirm()
            return true
        default:
            if event.keyCode == 53 {
                onExit()
                return true
            }
            return false
        }
    }
}
