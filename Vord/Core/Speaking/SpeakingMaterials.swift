import Foundation

struct SpeakingMaterial: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable { case phrase, sentence, story, angle, correction }
    enum Part: String, Codable, CaseIterable {
        case any = "Any part", one = "Part 1", two = "Part 2", three = "Part 3"
        var speakingSeconds: Int { self == .two ? 120 : (self == .one ? 30 : 60) }
        var preparationSeconds: Int { self == .two ? 60 : 10 }
    }
    var id = UUID()
    var title: String
    var english: String
    var chinese = ""
    var prompt = ""
    var notes = ""
    var topic = "General"
    var kind: Kind = .sentence
    var part: Part = .any
    var source = "Personal"
    var sourceDocumentID: UUID?
    var sourceExcerpt: String?
    var createdAt = Date()
    var archived = false

    var isValid: Bool {
        !title.trimmed.isEmpty && title.count <= 200 && !english.trimmed.isEmpty && english.range(of: "[A-Za-z]", options: .regularExpression) != nil && english.count <= 12000
        && chinese.count <= 12000 && prompt.count <= 2000 && notes.count <= 6000
        && topic.count <= 200 && source.count <= 300 && (sourceExcerpt?.count ?? 0) <= 12000
    }
    var duplicateKey: String {
        [english, prompt].map { $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }.joined(separator: "\n")
    }
}

struct SpeakingDocument: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var text: String
    var createdAt = Date()
}

struct SpeakingPack: Codable {
    var schemaVersion = 1
    var materials: [SpeakingMaterial]
    var documents: [SpeakingDocument] = []

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4_000_000 else { throw AIError.configuration("Choose a material pack under 4 MB.") }
        let pack = try JSONDecoder().decode(Self.self, from: data)
        guard pack.schemaVersion == 1, pack.materials.count <= 500,
              Set(pack.materials.map(\.id)).count == pack.materials.count,
              pack.materials.allSatisfy(\.isValid), pack.documents.count <= 100,
              Set(pack.documents.map(\.id)).count == pack.documents.count,
              pack.documents.allSatisfy({ !$0.name.trimmed.isEmpty && $0.name.count <= 300 && $0.text.count <= 60000 }),
              pack.materials.allSatisfy({ item in
                  guard let id = item.sourceDocumentID else { return true }
                  return pack.documents.contains { $0.id == id }
              }) else { throw AIError.configuration("This material pack is incomplete or uses an unsupported version.") }
        return pack
    }
}

struct SpeakingAttempt: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable { case recalled, revisit }
    var id = UUID()
    var materialID: UUID
    var question: String
    var answer: String
    var outcome: Outcome
    var seconds: Int
    var referenceRevealed: Bool
    var createdAt = Date()
}

/// Personal materials, original uploads and self-reported speaking practice stay on disk.
/// Built-in examples are immutable defaults; editing creates a persistent override.
@MainActor
final class SpeakingLibrary: ObservableObject {
    @Published private(set) var personal: [SpeakingMaterial] = []
    @Published private(set) var documents: [SpeakingDocument] = []
    @Published private(set) var attempts: [SpeakingAttempt] = []
    @Published private(set) var warning: String?
    private let url: URL
    private struct Snapshot: Codable {
        var schemaVersion = 1
        var materials: [SpeakingMaterial]
        var documents: [SpeakingDocument]
        var attempts: [SpeakingAttempt]
    }
    var materials: [SpeakingMaterial] {
        let overrides = Set(personal.map(\.id))
        return (personal + SpeakingStarterPack.materials.filter { !overrides.contains($0.id) }).filter { !$0.archived }
    }
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vord/speaking-materials.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.url))
                guard snapshot.schemaVersion == 1, snapshot.materials.allSatisfy(\.isValid),
                      Set(snapshot.materials.map(\.id)).count == snapshot.materials.count else {
                    throw AIError.configuration("Unsupported or incomplete speaking library.")
                }
                personal = snapshot.materials; documents = snapshot.documents; attempts = snapshot.attempts
            } catch { warning = "Speaking materials could not be read. \(error.localizedDescription)" }
        }
    }
    @discardableResult func add(_ items: [SpeakingMaterial], documents incoming: [SpeakingDocument] = []) throws -> Int {
        guard items.allSatisfy(\.isValid) else { throw AIError.configuration("A title and English text are required.") }
        var next = personal
        var resolvedDocuments = incoming
        var documentRemap: [UUID: UUID] = [:]
        for index in resolvedDocuments.indices {
            let document = resolvedDocuments[index]
            if let existing = documents.first(where: { $0.id == document.id }), existing != document {
                let nextID = UUID()
                documentRemap[document.id] = nextID; resolvedDocuments[index].id = nextID
            }
        }
        var keys = Set(materials.map(\.duplicateKey))
        var ids = Set((personal + SpeakingStarterPack.materials).map(\.id))
        for var item in items where keys.insert(item.duplicateKey).inserted {
            if let id = item.sourceDocumentID, let replacement = documentRemap[id] { item.sourceDocumentID = replacement }
            if ids.contains(item.id) { item.id = UUID() }
            ids.insert(item.id); next.insert(item, at: 0)
        }
        let referenced = Set(next.compactMap(\.sourceDocumentID))
        var docs = documents
        for doc in resolvedDocuments where referenced.contains(doc.id) && !docs.contains(where: { $0.id == doc.id }) { docs.append(doc) }
        // Validate references explicitly; a pack cannot silently attach an unrelated source.
        for item in next {
            if let id = item.sourceDocumentID, !docs.contains(where: { $0.id == id }) {
                throw AIError.configuration("The original source document is missing.")
            }
        }
        let count = next.count - personal.count
        try persist(materials: next, documents: docs, attempts: attempts)
        personal = next; documents = docs
        return count
    }
    func update(_ material: SpeakingMaterial) throws {
        guard material.isValid else { throw AIError.configuration("A title and English text are required.") }
        var next = personal.filter { $0.id != material.id }; next.insert(material, at: 0)
        try persist(materials: next, documents: documents, attempts: attempts); personal = next
    }
    func record(_ attempt: SpeakingAttempt) throws {
        guard materials.contains(where: { $0.id == attempt.materialID }), attempt.seconds > 0,
              attempt.seconds <= 3600, attempt.answer.count <= 12000 else {
            throw AIError.configuration("Start speaking before saving a practice attempt.")
        }
        let next = Array((attempts + [attempt]).suffix(5000))
        try persist(materials: personal, documents: documents, attempts: next); attempts = next
    }
    func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(SpeakingPack(materials: materials, documents: documents))
    }
    func context(question: String) -> String {
        var terms = question.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 }
        if let regex = try? NSRegularExpression(pattern: "\\p{Han}+") {
            for match in regex.matches(in: question, range: NSRange(question.startIndex..., in: question)) {
                guard let range = Range(match.range, in: question) else { continue }
                let characters = Array(question[range])
                if characters.count >= 2 {
                    for index in 0..<(characters.count - 1) { terms.append(String(characters[index...index + 1])) }
                }
            }
        }
        let selected = materials.sorted { lhs, rhs in
            func score(_ item: SpeakingMaterial) -> Int {
                let haystack = (item.title + " " + item.topic + " " + item.prompt + " " + item.chinese).lowercased()
                return terms.filter { haystack.contains($0) }.count
            }
            return score(lhs) > score(rhs)
        }.prefix(6)
        struct Context: Encodable {
            var total: Int; var sampledMaterials: [SpeakingMaterial]; var recentSelfReports: [SpeakingAttempt]
        }
        let samples = selected.map { value -> SpeakingMaterial in
            var item = value
            item.english = String(item.english.prefix(1200)); item.chinese = String(item.chinese.prefix(600))
            item.notes = String(item.notes.prefix(800)); item.prompt = String(item.prompt.prefix(400))
            item.sourceExcerpt = nil
            return item
        }
        let recent = attempts.suffix(6).map { value -> SpeakingAttempt in
            var item = value
            item.answer = String(item.answer.prefix(1000)); item.question = String(item.question.prefix(400))
            return item
        }
        let evidence = Context(total: materials.count, sampledMaterials: samples, recentSelfReports: recent)
        return (try? String(decoding: JSONEncoder().encode(evidence), as: UTF8.self)) ?? "{}"
    }
    private func persist(materials: [SpeakingMaterial], documents: [SpeakingDocument], attempts: [SpeakingAttempt]) throws {
        if let warning { throw AIError.configuration(warning) }
        guard Set(materials.map(\.id)).count == materials.count, materials.allSatisfy(\.isValid),
              documents.allSatisfy({ !$0.name.trimmed.isEmpty && $0.name.count <= 300 && $0.text.count <= 60000 }) else {
            throw AIError.configuration("Invalid speaking material or source document.")
        }
        for item in materials {
            if let id = item.sourceDocumentID, !documents.contains(where: { $0.id == id }) {
                throw AIError.configuration("The original source document is missing.")
            }
        }
        let value = Snapshot(materials: materials, documents: documents, attempts: attempts)
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
