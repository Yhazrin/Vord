import Foundation

struct LearningProfile: Sendable {
    let snapshot: LibraryExport
    let now: Date
    let calendar: Calendar
    let entries: [VocabularyEntry]
    let states: [UUID: ReviewState]
    let activeIDs: Set<UUID>

    init(snapshot: LibraryExport, now: Date = Date(), calendar: Calendar = .current) {
        self.snapshot = snapshot; self.now = now; self.calendar = calendar
        entries = snapshot.entries.filter { !$0.archived && DictationMatching.isEligible($0) }
        states = Dictionary(snapshot.reviewStates.map { ($0.entryID, $0) }, uniquingKeysWith: { _, latest in latest })
        activeIDs = Set(entries.map(\.id))
    }
    var dueWords: Int { entries.filter { dueDate($0.id) <= now }.count }
    var dueDirections: Int { snapshot.reviewStates.filter { activeIDs.contains($0.entryID) }.flatMap(\.directions).filter { $0.dueAt <= now }.count }
    var reviewedToday: Int { Set(snapshot.reviewLogs.filter { activeIDs.contains($0.entryID) && calendar.isDate($0.reviewedAt, inSameDayAs: now) }.map(\.entryID)).count }
    var weakWords: [VocabularyEntry] {
        entries.filter { (states[$0.id]?.directions.reduce(0) { $0 + $1.incorrectCount } ?? 0) > 0 }
            .sorted { weakness($0.id) > weakness($1.id) }
    }
    func weakness(_ id: UUID) -> Double {
        let directions = states[id]?.directions ?? []
        let incorrect = directions.reduce(0) { $0 + $1.incorrectCount }
        let reviews = directions.reduce(0) { $0 + $1.reviewCount }
        return Double(incorrect) / Double(max(1, reviews)) + Double(directions.reduce(0) { $0 + $1.lapseCount }) * 0.05
    }
    func dueDate(_ id: UUID) -> Date { states[id]?.directions.map(\.dueAt).min() ?? now }
    var priorityWords: [VocabularyEntry] {
        entries.sorted {
            let leftDue = dueDate($0.id) <= now, rightDue = dueDate($1.id) <= now
            if leftDue != rightDue { return leftDue }
            let leftWeak = weakness($0.id), rightWeak = weakness($1.id)
            if leftWeak != rightWeak { return leftWeak > rightWeak }
            if dueDate($0.id) != dueDate($1.id) { return dueDate($0.id) < dueDate($1.id) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// All counts cover the full active library. Only the word-level sample is bounded.
    func context(question: String, focusedEntryID: UUID? = nil) throws -> String {
        let mentioned = entries.filter {
            guard !$0.english.isEmpty else { return false }
            let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: $0.english) + "(?![A-Za-z0-9])"
            return question.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let focused = entries.filter { $0.id == focusedEntryID }
        var seen = Set<UUID>()
        let selected = Array((focused + mentioned + priorityWords).filter { seen.insert($0.id).inserted }.prefix(24))
        let iso = ISO8601DateFormatter()
        let words: [[String: Any]] = selected.map { entry in
            ["id": entry.id.uuidString, "word": entry.english, "meaning": String(entry.gloss.prefix(220)),
             "englishDefinition": String((entry.englishDefinition ?? "").prefix(220)),
             "directions": (states[entry.id]?.directions ?? []).map { state in
                 ["direction": state.direction.rawValue, "dueAt": iso.string(from: state.dueAt),
                  "reviews": state.reviewCount, "incorrect": state.incorrectCount, "lapses": state.lapseCount,
                  "lastReviewedAt": state.lastReviewedAt.map { iso.string(from: $0) } ?? "never"] as [String: Any]
             }] as [String: Any]
        }
        let recentLogs = Array(snapshot.reviewLogs.filter { activeIDs.contains($0.entryID) }.sorted { $0.reviewedAt > $1.reviewedAt }.prefix(30))
        let data: [String: Any] = [
            "observedAt": iso.string(from: now), "timeZone": calendar.timeZone.identifier,
            "activeWords": entries.count, "dueWords": dueWords, "dueDirections": dueDirections,
            "weakWords": weakWords.count, "reviewedWordsToday": reviewedToday,
            "totalReviewAnswers": snapshot.reviewLogs.filter { activeIDs.contains($0.entryID) }.count,
            "sampledWords": words, "sampleLimit": 24,
            "recentAnswers": recentLogs.map { ["entryID": $0.entryID.uuidString, "direction": $0.direction.rawValue,
                                                 "rating": $0.rating.rawValue, "at": iso.string(from: $0.reviewedAt)] }
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]), as: UTF8.self)
    }
}

struct StudyPlanDay: Codable, Identifiable, Equatable, Sendable {
    var date: Date
    var entryIDs: [UUID]
    var id: Date { date }
}
struct StudyPlan: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var createdAt: Date
    var dailyLimit: Int
    var days: [StudyPlanDay]

    static func make(profile: LearningProfile, dailyLimit: Int) -> StudyPlan {
        let limit = min(60, max(5, dailyLimit))
        let start = profile.calendar.startOfDay(for: profile.now)
        var days = (0..<7).map { StudyPlanDay(date: profile.calendar.date(byAdding: .day, value: $0, to: start)!, entryIDs: []) }
        // Keep future reviews on or after their due day. Spread overdue work across the available days.
        for word in profile.priorityWords {
            let dueDay = profile.calendar.startOfDay(for: profile.dueDate(word.id))
            let first = max(0, profile.calendar.dateComponents([.day], from: start, to: dueDay).day ?? 0)
            guard first < days.count, let index = (first..<days.count).first(where: { days[$0].entryIDs.count < limit }) else { continue }
            days[index].entryIDs.append(word.id)
        }
        return StudyPlan(createdAt: profile.now, dailyLimit: limit, days: days)
    }
    func remaining(day: StudyPlanDay, profile: LearningProfile) -> [UUID] {
        let completed = Set(profile.snapshot.reviewLogs.filter { $0.rating != .again && $0.reviewedAt >= createdAt }.map(\.entryID))
        return day.entryIDs.filter { profile.activeIDs.contains($0) && !completed.contains($0) }
    }
    func displayDay(_ scheduled: StudyPlanDay, profile: LearningProfile) -> StudyPlanDay {
        guard profile.calendar.isDate(scheduled.date, inSameDayAs: profile.now) else { return scheduled }
        let completedToday = Set(profile.snapshot.reviewLogs.filter {
            $0.rating != .again && $0.reviewedAt >= createdAt && profile.calendar.isDate($0.reviewedAt, inSameDayAs: profile.now)
        }.map(\.entryID))
        var carry: [UUID] = []
        for earlier in days where earlier.date < scheduled.date {
            let pending = Set(remaining(day: earlier, profile: profile))
            carry += earlier.entryIDs.filter { profile.activeIDs.contains($0) && (pending.contains($0) || completedToday.contains($0)) }
        }
        var seen = Set<UUID>()
        return StudyPlanDay(date: scheduled.date, entryIDs: Array((carry + scheduled.entryIDs)
            .filter { profile.activeIDs.contains($0) && seen.insert($0).inserted }.prefix(dailyLimit)))
    }
}
