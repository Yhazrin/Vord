import Foundation

struct ExamRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var mode: String
    var outcomes: [DictationOutcome]
    var correctCount: Int { outcomes.filter(\.correct).count }
}

@MainActor
final class LearningHistory: ObservableObject {
    @Published private(set) var contexts: [ContextRecord] = []
    @Published private(set) var exams: [ExamRecord] = []
    @Published private(set) var warning: String?
    private let url: URL
    private struct Snapshot: Codable { var contexts: [ContextRecord]; var exams: [ExamRecord] }
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vord/learning-history.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.url))
                contexts = snapshot.contexts; exams = snapshot.exams
            } catch { warning = "Learning history could not be read. \(error.localizedDescription)" }
        }
    }
    func append(_ record: ContextRecord) throws {
        let next = Array(([record] + contexts).prefix(100))
        try persist(contexts: next, exams: exams)
        contexts = next
    }
    func append(_ record: ExamRecord) throws {
        let next = Array(([record] + exams).prefix(100))
        try persist(contexts: contexts, exams: next)
        exams = next
    }
    private func persist(contexts: [ContextRecord], exams: [ExamRecord]) throws {
        // Do not overwrite an unreadable file silently.
        if let warning { throw AIError.configuration(warning) }
        let data = try JSONEncoder().encode(Snapshot(contexts: contexts, exams: exams))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
