import Foundation

enum ReviewDirection: String, Codable, Sendable, Hashable, CaseIterable {
    case englishToChinese
    case chineseToEnglish

    var title: String {
        switch self {
        case .englishToChinese:
            return "English → Chinese"
        case .chineseToEnglish:
            return "Chinese → English"
        }
    }
}

enum ReviewRating: String, Codable, Sendable, Hashable, CaseIterable {
    case again
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

enum ReviewMode: String, Codable, Sendable, Hashable, CaseIterable {
    case englishToChinese
    case chineseToEnglish
    case mixed

    var title: String {
        switch self {
        case .englishToChinese: return "English → Chinese"
        case .chineseToEnglish: return "Chinese → English"
        case .mixed: return "Mixed"
        }
    }
}

struct ReviewDirectionState: Codable, Sendable, Equatable {
    var direction: ReviewDirection
    /// Seconds until the next review. `stability` is stored in days so a future FSRS scheduler can replace this one.
    var dueAt: Date
    var lastReviewedAt: Date?
    var stage: Int
    var interval: TimeInterval
    var difficulty: Double
    var stability: Double
    var reviewCount: Int
    var lapseCount: Int
    var correctCount: Int
    var incorrectCount: Int

    static func initial(direction: ReviewDirection, now: Date) -> ReviewDirectionState {
        ReviewDirectionState(
            direction: direction,
            dueAt: now,
            lastReviewedAt: nil,
            stage: 0,
            interval: 0,
            difficulty: 5,
            stability: 0,
            reviewCount: 0,
            lapseCount: 0,
            correctCount: 0,
            incorrectCount: 0
        )
    }
}

struct ReviewState: Codable, Sendable, Equatable {
    var entryID: UUID
    var directions: [ReviewDirectionState]

    static func initial(entryID: UUID, now: Date) -> ReviewState {
        ReviewState(
            entryID: entryID,
            directions: ReviewDirection.allCases.map { ReviewDirectionState.initial(direction: $0, now: now) }
        )
    }

    func state(for direction: ReviewDirection) -> ReviewDirectionState? {
        directions.first { $0.direction == direction }
    }
}

struct ReviewLog: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var entryID: UUID
    var direction: ReviewDirection
    var rating: ReviewRating
    var reviewedAt: Date
    var previousDueAt: Date?
    var scheduledDueAt: Date
    var interval: TimeInterval
}

struct ReviewScheduleResult: Sendable, Equatable {
    var state: ReviewState
    var log: ReviewLog
}

struct LibraryExport: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var entries: [VocabularyEntry]
    var reviewStates: [ReviewState]
    var reviewLogs: [ReviewLog]
}
