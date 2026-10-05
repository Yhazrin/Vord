import Foundation

/// A small, real review session. Choosing a round never advances the scheduler.
struct StudyRound: Equatable {
    var entryIDs: [UUID]

    static func make(snapshot: LibraryExport, practice: [ExamPracticeRecord] = [],
                     dailyGoal: Int = 10, now: Date = Date(), calendar: Calendar = .current) -> Self {
        let profile = LearningProfile(snapshot: snapshot, practice: practice,
            dailyPracticeGoal: dailyGoal, now: now, calendar: calendar)
        let practiced = StudyActivity(snapshot: snapshot, practice: practice, now: now, calendar: calendar)
            .day(now).practicedWords
        let due = profile.priorityWords.filter { word in
            profile.states[word.id]?.directions.contains { $0.dueAt <= now } == true
        }
        // Fresh words first so the daily goal can grow; then permit voluntary
        // practice of another due direction when all remaining words were seen.
        let ordered = due.filter { !practiced.contains($0.id) } + due.filter { practiced.contains($0.id) }
        let remaining = max(0, profile.dailyPracticeGoal - practiced.count)
        let limit = remaining > 0 ? min(5, remaining) : 5
        return Self(entryIDs: Array(ordered.prefix(limit).map(\.id)))
    }
}

struct ReviewSessionAnswer {
    var entry: VocabularyEntry
    var rating: ReviewRating
}

/// The latest saved answer for each asked direction is the evidence. A word
/// with one still-forgotten direction must not appear in the recalled count.
struct ReviewRoundSummary {
    var recalled: [VocabularyEntry]
    var revisit: [VocabularyEntry]
    var practicedCount: Int { recalled.count + revisit.count }

    init(answers: [ReviewSessionAnswer]) {
        let grouped = Dictionary(grouping: answers, by: { $0.entry.id })
        recalled = []; revisit = []
        for answers in grouped.values {
            guard let word = answers.first?.entry else { continue }
            if answers.contains(where: { $0.rating == .again }) { revisit.append(word) }
            else { recalled.append(word) }
        }
        func ordered(_ lhs: VocabularyEntry, _ rhs: VocabularyEntry) -> Bool {
            if lhs.english.lowercased() != rhs.english.lowercased() { return lhs.english.lowercased() < rhs.english.lowercased() }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        recalled.sort(by: ordered); revisit.sort(by: ordered)
    }
}
