import Foundation

extension Notification.Name {
    static let vordLibraryDidChange = Notification.Name("vord.libraryDidChange")
}

struct TodaySummary: Sendable, Equatable {
    var dueCount: Int
    var addedToday: Int
    var reviewedToday: Int
}

struct LibraryRow: Identifiable, Sendable, Equatable {
    var id: UUID
    var english: String
    var chinese: String
    var lemma: String?
    var tags: [String]
    var createdAt: Date
    var nextDueAt: Date?
    var archived: Bool = false
}

struct ReviewCard: Identifiable, Sendable, Equatable {
    var entry: VocabularyEntry
    var direction: ReviewDirection
    var state: ReviewDirectionState

    var id: String { "\(entry.id.uuidString)-\(direction.rawValue)" }
}

enum LibrarySort: String, CaseIterable, Sendable, Identifiable {
    case added
    case alphabetical
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: return "Date Added"
        case .alphabetical: return "Alphabetical"
        case .due: return "Due"
        }
    }
}

enum LibraryQuery {
    static func apply(rows: [LibraryRow], search: String, sort: LibrarySort) -> [LibraryRow] {
        let query = search.trimmed.lowercased()
        let filtered: [LibraryRow]
        if query.isEmpty {
            filtered = rows
        } else {
            filtered = rows.filter { row in
                row.english.lowercased().contains(query)
                    || row.chinese.lowercased().contains(query)
                    || (row.lemma?.lowercased().contains(query) ?? false)
                    || row.tags.contains { $0.lowercased().contains(query) }
            }
        }
        switch sort {
        case .added:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return filtered.sorted {
                $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
            }
        case .due:
            return filtered.sorted { lhs, rhs in
                switch (lhs.nextDueAt, rhs.nextDueAt) {
                case let (left?, right?):
                    return left < right
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                case (nil, nil):
                    return lhs.createdAt > rhs.createdAt
                }
            }
        }
    }
}

private extension LibraryRow {
    var sortKey: String {
        let english = english.trimmed
        return english.isEmpty ? chinese : english
    }
}

protocol VocabularyRepository: Sendable {
    func todaySummary(now: Date) async throws -> TodaySummary
    func recentEntries(limit: Int) async throws -> [VocabularyEntry]
    func dueCards(now: Date, limit: Int) async throws -> [ReviewCard]
    func libraryRows() async throws -> [LibraryRow]
    func activeEntries() async throws -> [VocabularyEntry]
    func entry(id: UUID) async throws -> VocabularyEntry?
    func reviewState(entryID: UUID) async throws -> ReviewState?
    func upsert(_ draft: EntryDraft, now: Date) async throws -> VocabularyEntry
    func insertIfAbsent(_ draft: EntryDraft, now: Date) async throws -> VocabularyEntry?
    func update(_ entry: VocabularyEntry) async throws
    func setArchived(id: UUID, archived: Bool, now: Date) async throws
    func delete(id: UUID) async throws
    func recordReview(_ result: ReviewScheduleResult) async throws
    func importSnapshot(_ snapshot: LibraryExport) async throws -> Int
    func exportSnapshot() async throws -> LibraryExport
}

extension VocabularyRepository {
    func insertIfAbsent(_ draft: EntryDraft, now: Date) async throws -> VocabularyEntry? {
        guard try await !libraryRows().contains(where: { $0.english.caseInsensitiveCompare(draft.english.trimmed) == .orderedSame }) else { return nil }
        return try await upsert(draft, now: now)
    }
}
