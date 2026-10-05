import Foundation

/// A clock-driven exercise, with no storage or implicit assessment side effects.
struct SpeakingExercise {
    enum Phase: String { case ready = "Ready", preparing = "Prepare", speaking = "Speak", finished = "Compare" }
    let part: SpeakingMaterial.Part
    private(set) var phase: Phase = .ready
    private(set) var phaseStartedAt: Date?
    private(set) var speakingStartedAt: Date?
    private(set) var spokenSeconds = 0
    private(set) var referenceRevealed = false

    func remaining(at now: Date) -> Int {
        let limit = phase == .preparing ? part.preparationSeconds : part.speakingSeconds
        if phase == .finished { return 0 }
        let elapsed = max(0, Int(now.timeIntervalSince(phaseStartedAt ?? now)))
        return max(0, limit - elapsed)
    }
    mutating func prepare(at now: Date) {
        guard phase == .ready else { return }
        phase = .preparing; phaseStartedAt = now
    }
    mutating func beginSpeaking(at now: Date) {
        guard phase == .preparing else { return }
        phase = .speaking; phaseStartedAt = now; speakingStartedAt = now
    }
    mutating func advance(to now: Date) {
        if phase == .preparing, let start = phaseStartedAt {
            let deadline = start.addingTimeInterval(TimeInterval(part.preparationSeconds))
            if now >= deadline { beginSpeaking(at: deadline) }
        }
        if phase == .speaking, let start = speakingStartedAt,
           now >= start.addingTimeInterval(TimeInterval(part.speakingSeconds)) { finish(at: now) }
    }
    mutating func finish(at now: Date) {
        guard phase == .speaking, let start = speakingStartedAt else { return }
        spokenSeconds = max(0, min(part.speakingSeconds, Int(now.timeIntervalSince(start))))
        phase = .finished; phaseStartedAt = now
    }
    mutating func reveal() { guard phase != .ready else { return }; referenceRevealed = true }
    var canRecord: Bool { phase == .finished && spokenSeconds > 0 }
}

extension SpeakingLibrary {
    /// Only the latest explicit self-report determines whether a material needs another attempt.
    var revisitIDs: Set<UUID> {
        var latest: [UUID: SpeakingAttempt] = [:]
        for attempt in attempts {
            if let previous = latest[attempt.materialID], previous.createdAt > attempt.createdAt { continue }
            latest[attempt.materialID] = attempt
        }
        return Set(latest.values.filter { $0.outcome == .revisit }.map(\.materialID))
    }
}
