import Foundation

struct ExamRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var mode: String
    var outcomes: [DictationOutcome]
    var correctCount: Int { outcomes.filter(\.correct).count }
}

/// Compact evidence of an answered word, retained when full exam results expire.
struct ExamPracticeRecord: Codable, Identifiable, Sendable {
    struct Word: Codable, Hashable, Sendable {
        var entryID: UUID?
        var english: String
    }
    var id: UUID
    var createdAt: Date
    var words: [Word]

    init(_ exam: ExamRecord) {
        id = exam.id; createdAt = exam.createdAt
        words = Array(Set(exam.outcomes.filter { !$0.attempt.trimmed.isEmpty }.map { outcome in
            let question = outcome.question
            return Word(entryID: question.entryID,
                        english: (question.direction == .englishToChinese ? question.prompt : question.expected).trimmed.lowercased())
        }))
    }
}

@MainActor
final class LearningHistory: ObservableObject {
    @Published private(set) var contexts: [ContextRecord] = []
    @Published private(set) var exams: [ExamRecord] = []
    @Published private(set) var practice: [ExamPracticeRecord] = []
    @Published private(set) var warning: String?
    private let url: URL
    private struct Snapshot: Codable {
        var contexts: [ContextRecord]
        var exams: [ExamRecord]
        var practice: [ExamPracticeRecord]?
    }
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vord/learning-history.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.url))
                contexts = snapshot.contexts; exams = snapshot.exams
                practice = snapshot.practice ?? snapshot.exams.map(ExamPracticeRecord.init)
            } catch { warning = "Learning history could not be read. \(error.localizedDescription)" }
        }
    }
    func append(_ record: ContextRecord) throws {
        let next = Array(([record] + contexts).prefix(100))
        try persist(contexts: next, exams: exams, practice: practice)
        contexts = next
    }
    func append(_ record: ExamRecord) throws {
        let next = Array(([record] + exams).prefix(100))
        let evidence = ExamPracticeRecord(record)
        let nextPractice = practice.filter { $0.id != record.id } + [evidence]
        try persist(contexts: contexts, exams: next, practice: nextPractice)
        exams = next
        practice = nextPractice
    }
    private func persist(contexts: [ContextRecord], exams: [ExamRecord], practice: [ExamPracticeRecord]) throws {
        // Do not overwrite an unreadable file silently.
        if let warning { throw AIError.configuration(warning) }
        let data = try JSONEncoder().encode(Snapshot(contexts: contexts, exams: exams, practice: practice))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
