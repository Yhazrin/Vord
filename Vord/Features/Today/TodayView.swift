import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var summary = TodaySummary(dueCount: 0, addedToday: 0, reviewedToday: 0)
    @Published var recent: [VocabularyEntry] = []
    @Published var totalWords = 0
    @Published var activity: StudyActivity?
    @Published var nextDue: Date?
    @Published var speakingWords: [VocabularyEntry] = []
    @Published var error: String?
    @Published private(set) var round = StudyRound(entryIDs: [])
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }
    func load(_ repository: any VocabularyRepository, practice: [ExamPracticeRecord] = [], dailyGoal: Int = 10) async {
        do {
            let now = Date()
            summary = try await repository.todaySummary(now: now)
            recent = try await repository.recentEntries(limit: 5)
            let snapshot = try await repository.exportSnapshot()
            let activeIDs = Set(snapshot.entries.filter { !$0.archived }.map(\.id))
            let dueIDs = Set(snapshot.reviewStates.filter { $0.directions.contains { $0.dueAt <= now } }.map(\.entryID))
            let todayIDs = Set(snapshot.reviewLogs.filter { Calendar.current.isDate($0.reviewedAt, inSameDayAs: now) }.map(\.entryID))
            let active = snapshot.entries.filter { !$0.archived }
            speakingWords = active.filter { dueIDs.contains($0.id) || todayIDs.contains($0.id) }
            if speakingWords.isEmpty { speakingWords = recent.filter { !$0.archived } }
            totalWords = activeIDs.count
            nextDue = snapshot.reviewStates.filter { activeIDs.contains($0.entryID) }
                .flatMap(\.directions).map(\.dueAt).filter { $0 > now }.min()
            activity = StudyActivity(snapshot: snapshot, practice: practice, now: now)
            round = StudyRound.make(snapshot: snapshot, practice: practice, dailyGoal: dailyGoal, now: now)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct TodayView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: LearningHistory
    var onStartReview: () -> Void
    var onStartRound: ([UUID]) -> Void
    var onNavigate: (AppTab) -> Void
    @StateObject private var model = TodayViewModel()
    @State private var selectedEntry: VocabularyEntry?
    @State private var preparingRound = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.vordLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dateRow
                overview
                Hairline()
                dailyPractice
                DailySpeakingBridge(library: dependencies.speaking, entries: model.speakingWords)
                if let activity = model.activity { StudyCalendar(activity: activity) }
                Hairline()
                libraryBand
                if let error = model.error {
                    Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive)
                }
            }
            .frame(maxWidth: AppSpacing.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .modifier(PageInset(top: 20, bottom: AppSpacing.lg))
        }
        .task { await model.load(dependencies.repository, practice: history.practice, dailyGoal: settings.dailyPracticeGoal) }
        .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in reload() }
        .onReceive(history.$practice.dropFirst()) { _ in reload() }
        .onChange(of: settings.dailyPracticeGoal) { _, _ in reload() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in reload() }
        .sheet(item: $selectedEntry) { entry in
            WordDetailView(entryID: entry.id) { selectedEntry = nil }
                .environmentObject(dependencies).frame(width: 900, height: 650)
        }
    }

    private func reload() {
        Task { await model.load(dependencies.repository, practice: history.practice, dailyGoal: settings.dailyPracticeGoal) }
    }

    private func startRound() {
        guard !preparingRound else { return }
        preparingRound = true
        Task {
            defer { preparingRound = false }
            // Re-select from current data, including changes synced since the
            // page opened. Review loading validates these IDs again.
            await model.load(dependencies.repository, practice: history.practice, dailyGoal: settings.dailyPracticeGoal)
            guard model.error == nil else { return }
            if model.round.entryIDs.isEmpty { onNavigate(.dictation) }
            else { onStartRound(model.round.entryIDs) }
        }
    }

    private var roundButton: some View {
        let count = model.round.entryIDs.count
        return QuietButton(title: count > 0 ? "Review \(count) \(count == 1 ? "word" : "words")" : "Practice dictation", action: startRound)
            .disabled(preparingRound)
            .help("A short round of up to five due words. Today's unseen words come first.")
    }

    private var dailyPractice: some View {
        let completed = model.activity?.day(model.activity?.now ?? Date()).practicedWords.count ?? 0
        let goal = settings.dailyPracticeGoal
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.md) {
                    practiceStatus(completed: completed, goal: goal)
                    Spacer(minLength: AppSpacing.sm)
                    if let streak = model.activity?.practiceStreak, streak > 1 {
                        Text("\(streak)-day streak").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    }
                    roundButton
                }
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    practiceStatus(completed: completed, goal: goal)
                    roundButton
                }
            }
            StudyProgress(completed: completed, total: goal)
                .accessibilityLabel("Daily practice goal")
        }
        .help("Different words answered in review or completed dictation rounds. Adding words and skipping questions do not count toward the goal.")
    }

    private func practiceStatus(completed: Int, goal: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if completed >= goal { SuccessMark(size: 18) }
            Text(completed >= goal ? "Daily goal reached" : "Daily practice").font(AppTypography.headline)
            Text("\(completed) / \(goal) words")
                .font(AppTypography.caption).monospacedDigit().foregroundStyle(AppColors.secondaryText)
                .contentTransition(.numericText(value: Double(completed)))
                .animation(AppMotion.feedback(reducedMotion), value: completed)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var dateRow: some View {
        HStack(alignment: .center) {
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            Spacer()
            QuietButton(title: "Add word") { onNavigate(.add) }
        }
    }

    /// Review is the action; the three counts sit beside it so the first screen reads as one status row.
    private var overview: some View {
        Group {
            if layout.usesColumns {
                HStack(alignment: .top, spacing: 40) {
                    reviewFocus.frame(maxWidth: .infinity, alignment: .leading)
                    stats.frame(width: 300, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    reviewFocus
                    stats
                }
            }
        }
    }

    private var reviewFocus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review").font(AppTypography.headline)
            Text(model.summary.dueCount == 0 ? "No words due." : "\(model.summary.dueCount) words to revisit.")
                .font(AppTypography.ui(size: 28))
                .fixedSize(horizontal: false, vertical: true)
            if model.summary.dueCount == 0 {
                Text(nextReview)
                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if model.summary.dueCount > 0 {
                    PrimaryButton(title: "Start review", action: onStartReview)
                } else {
                    QuietButton(title: "Practice dictation") { onNavigate(.dictation) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 0) {
            statistic("words in Library", count: model.totalWords)
            Hairline()
            statistic("added today", count: model.summary.addedToday)
            Hairline()
            statistic("words studied today", count: model.activity?.day(Date()).count ?? 0)
        }
    }

    private var libraryBand: some View {
        Group {
            if layout.usesColumns {
                HStack(alignment: .top, spacing: 28) {
                    recentWords.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(AppColors.subtleBorder).frame(width: 1)
                    examples.frame(width: 220, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    recentWords
                    examples
                }
            }
        }
    }

    private var recentWords: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Recently added").font(AppTypography.headline)
                Spacer()
                SubtleButton(title: "Open Library") { onNavigate(.library) }
            }
            if model.recent.isEmpty {
                Text("Add an English or Chinese word to start your library.")
                    .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                    .padding(.vertical, 16)
            } else {
                ForEach(model.recent) { entry in
                    Button { selectedEntry = entry } label: {
                        HStack(spacing: 16) {
                            Text(entry.headword)
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .frame(width: layout.usesColumns ? 160 : 120, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.gloss.isEmpty ? "Meaning not added" : entry.gloss)
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day())
                                .font(AppTypography.ui(size: 11)).foregroundStyle(AppColors.tertiaryText)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Examples").font(AppTypography.headline)
            SubtleButton(title: "Choose words") { onNavigate(.context) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var nextReview: String {
        if let next = model.nextDue { return "Next review: " + next.formatted(date: .abbreviated, time: .shortened) }
        return "Add a word with a meaning to begin reviewing."
    }

    private func statistic(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            Spacer(minLength: 12)
            Text("\(count)")
                .font(AppTypography.stat)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .animation(AppMotion.feedback(reducedMotion), value: count)
        }
        .padding(.vertical, 8)
    }
}

private struct DailySpeakingBridge: View {
    @ObservedObject var library: SpeakingLibrary
    var entries: [VocabularyEntry]
    @State private var selected: SpeakingMaterial?
    var body: some View {
        SpeakingNextSteps(materials: SpeakingConnections.studyPrompts(materials: library.materials,
            entries: entries, revisitIDs: library.revisitIDs, limit: 2), entries: entries, title: "Use today's words") { selected = $0 }
            .sheet(item: $selected) { material in SpeakingPracticeView(library: library, material: material) }
    }
}
