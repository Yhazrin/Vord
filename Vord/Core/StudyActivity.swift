import Foundation

enum ActivityPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self { case .week: return .weekOfYear; case .month: return .month; case .year: return .year }
    }
}

struct StudyActivityDay: Identifiable, Equatable {
    var date: Date
    var added: Set<UUID> = []
    var reviewed: Set<UUID> = []
    var id: Date { date }
    var words: Set<UUID> { added.union(reviewed) }
    var count: Int { words.count }
    var level: Int {
        switch count { case 0: return 0; case 1...3: return 1; case 4...9: return 2; case 10...19: return 3; default: return 4 }
    }
}

struct StudyActivity {
    var days: [Date: StudyActivityDay] = [:]
    var calendar: Calendar
    var now: Date
    init(snapshot: LibraryExport, now: Date = Date(), calendar: Calendar = .current) {
        self.now = now; self.calendar = calendar
        let known = Set(snapshot.entries.map(\.id))
        for entry in snapshot.entries where entry.createdAt <= now && !entry.english.trimmed.isEmpty && !entry.chinese.trimmed.isEmpty {
            let date = calendar.startOfDay(for: entry.createdAt)
            var day = days[date] ?? StudyActivityDay(date: date)
            day.added.insert(entry.id); days[date] = day
        }
        for log in snapshot.reviewLogs where log.reviewedAt <= now && known.contains(log.entryID) {
            let date = calendar.startOfDay(for: log.reviewedAt)
            var day = days[date] ?? StudyActivityDay(date: date)
            day.reviewed.insert(log.entryID); days[date] = day
        }
    }
    func day(_ date: Date) -> StudyActivityDay {
        let date = calendar.startOfDay(for: date)
        return days[date] ?? StudyActivityDay(date: date)
    }
    func interval(_ period: ActivityPeriod, anchor: Date) -> DateInterval {
        calendar.dateInterval(of: period.component, for: anchor) ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 86400)
    }
    func dates(in interval: DateInterval) -> [Date] {
        var date = interval.start, result: [Date] = []
        while date < interval.end, result.count < 400 {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return result
    }
    func activeDays(in interval: DateInterval) -> Int {
        days.values.filter { $0.date >= interval.start && $0.date < interval.end && $0.count > 0 }.count
    }
    func uniqueWords(in interval: DateInterval) -> Int {
        days.values.filter { $0.date >= interval.start && $0.date < interval.end }.reduce(into: Set<UUID>()) { $0.formUnion($1.words) }.count
    }
    /// Weekday alignment follows the user's locale; padding cells never count as activity.
    func weeks(in interval: DateInterval) -> [[Date?]] {
        let start = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
        var columns: [[Date?]] = [], date = start
        while date < interval.end, columns.count < 54 {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(date >= interval.start && date < interval.end ? date : nil)
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return columns }
                date = next
            }
            columns.append(week)
        }
        return columns
    }
}
