import Foundation

protocol ReviewScheduling: Sendable {
    func schedule(
        state: ReviewState,
        direction: ReviewDirection,
        rating: ReviewRating,
        now: Date
    ) -> ReviewScheduleResult
}

struct SimpleScheduler: ReviewScheduling {
    func schedule(
        state: ReviewState,
        direction: ReviewDirection,
        rating: ReviewRating,
        now: Date
    ) -> ReviewScheduleResult {
        var directions = state.directions
        if !directions.contains(where: { $0.direction == direction }) {
            directions.append(.initial(direction: direction, now: now))
        }
        guard let index = directions.firstIndex(where: { $0.direction == direction }) else {
            return ReviewScheduleResult(
                state: state,
                log: ReviewLog(
                    id: UUID(),
                    entryID: state.entryID,
                    direction: direction,
                    rating: rating,
                    reviewedAt: now,
                    previousDueAt: nil,
                    scheduledDueAt: now,
                    interval: 0
                )
            )
        }

        var current = directions[index]
        let previousDue = current.dueAt
        let learning = current.stage == 0

        switch rating {
        case .again:
            current.interval = 10 * 60
            current.stability = max(0.01, current.stability * 0.5)
            current.stage = 0
            current.lapseCount += 1
            current.incorrectCount += 1
            current.difficulty = clamp(current.difficulty + 0.4)
        case .hard:
            if learning {
                current.interval = 8 * 60 * 60
                current.stability = 8.0 / 24.0
                current.stage = 1
            } else {
                current.stability = max(current.stability, 0.3) * 1.3
                current.interval = current.stability * 86_400
            }
            current.correctCount += 1
            current.difficulty = clamp(current.difficulty + 0.15)
        case .good:
            if learning {
                current.stability = 1
                current.interval = 86_400
                current.stage = 1
            } else {
                current.stability = max(current.stability, 1) * 2.3
                current.interval = current.stability * 86_400
                current.stage += 1
            }
            current.correctCount += 1
            current.difficulty = clamp(current.difficulty - 0.05)
        case .easy:
            if learning {
                current.stability = 3
                current.interval = 3 * 86_400
                current.stage = 1
            } else {
                current.stability = max(current.stability, 1) * 3.4
                current.interval = current.stability * 86_400
                current.stage += 1
            }
            current.correctCount += 1
            current.difficulty = clamp(current.difficulty - 0.2)
        }

        current.reviewCount += 1
        current.lastReviewedAt = now
        current.dueAt = now.addingTimeInterval(current.interval)
        directions[index] = current

        var updated = state
        updated.directions = directions
        let log = ReviewLog(
            id: UUID(),
            entryID: state.entryID,
            direction: direction,
            rating: rating,
            reviewedAt: now,
            previousDueAt: previousDue,
            scheduledDueAt: current.dueAt,
            interval: current.interval
        )
        return ReviewScheduleResult(state: updated, log: log)
    }

    private func clamp(_ value: Double) -> Double {
        min(10, max(1, value))
    }
}
