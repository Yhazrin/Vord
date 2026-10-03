import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var summary = TodaySummary(dueCount: 0, addedToday: 0, reviewedToday: 0)
    @Published var recent: [VocabularyEntry] = []
    @Published var totalWords = 0
    @Published var activity: StudyActivity?
    @Published var nextDue: Date?
    @Published var error: String?
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }
    func load(_ repository: any VocabularyRepository) async {
        do {
            let now = Date()
            summary = try await repository.todaySummary(now: now)
            recent = try await repository.recentEntries(limit: 5)
            let snapshot = try await repository.exportSnapshot()
            let activeIDs = Set(snapshot.entries.filter { !$0.archived }.map(\.id))
            totalWords = activeIDs.count
            nextDue = snapshot.reviewStates.filter { activeIDs.contains($0.entryID) }
                .flatMap(\.directions).map(\.dueAt).filter { $0 > now }.min()
            activity = StudyActivity(snapshot: snapshot, now: now)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct TodayView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    var onStartReview: () -> Void
    var onNavigate: (AppTab) -> Void
    @StateObject private var model = TodayViewModel()
    @State private var selectedEntry: VocabularyEntry?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.vordLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dateRow
                overview
                Hairline()
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
        .task { await model.load(dependencies.repository) }
        .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in Task { await model.load(dependencies.repository) } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in Task { await model.load(dependencies.repository) } }
        .sheet(item: $selectedEntry) { entry in
            WordDetailView(entryID: entry.id) { selectedEntry = nil }
                .environmentObject(dependencies).frame(width: 900, height: 650)
        }
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
