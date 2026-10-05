import Foundation

struct SpeakingKeyword: Codable, Equatable, Hashable, Identifiable, Sendable {
    var english: String
    var chinese: String
    var id: String { SpeakingConnections.normalized(english) }
    var isValid: Bool { !english.trimmed.isEmpty && english.count <= 120 && chinese.count <= 300 }
}

/// Associations are derived from current vocabulary, never a copied second word list.
enum SpeakingConnections {
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && $0 != "'" }).joined(separator: " ")
    }

    static func contains(_ expression: String, in text: String) -> Bool {
        let haystack = " " + normalized(text) + " "
        let pieces = expression.components(separatedBy: "...").map(normalized)
        guard !pieces.contains(where: \.isEmpty) else { return false }
        if pieces.count == 1 { return haystack.contains(" " + pieces[0] + " ") }
        // A reusable frame such as put ... into practice may contain a short object.
        let escaped = pieces.map(NSRegularExpression.escapedPattern(for:))
        let pattern = " " + escaped.joined(separator: " (?:[a-z']+ ){0,8}") + " "
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }

    static func matches(_ entry: VocabularyEntry, material: SpeakingMaterial) -> Bool {
        matches(entry, english: material.english, keywords: expressions(material))
    }
    private static func matches(_ entry: VocabularyEntry, english: String, keywords: [SpeakingKeyword]) -> Bool {
        guard !entry.archived, !entry.english.trimmed.isEmpty else { return false }
        let terms = [entry.english, entry.lemma ?? ""].filter { !$0.trimmed.isEmpty }
        return terms.contains { term in
            contains(term, in: english) || keywords.contains {
                contains(term, in: $0.english)
            }
        }
    }

    static func linkedEntries(_ material: SpeakingMaterial, entries: [VocabularyEntry]) -> [VocabularyEntry] {
        let expressions = expressions(material)
        return entries.filter { matches($0, english: material.english, keywords: expressions) }
    }

    static func expressions(_ material: SpeakingMaterial) -> [SpeakingKeyword] {
        if let explicit = material.keywords { return unique(explicit) }
        return catalogue.filter { contains($0.english, in: material.english) }
    }

    static func keywords(_ material: SpeakingMaterial, entries: [VocabularyEntry]) -> [SpeakingKeyword] {
        unique(expressions(material) + linkedEntries(material, entries: entries).map {
            SpeakingKeyword(english: $0.english, chinese: $0.gloss)
        })
    }

    static func recommendations(materials: [SpeakingMaterial], entries: [VocabularyEntry], revisitIDs: Set<UUID> = [], limit: Int = 3) -> [SpeakingMaterial] {
        materials.filter { !$0.archived }.compactMap { item -> (SpeakingMaterial, Int)? in
            let links = linkedEntries(item, entries: entries).count
            guard links > 0 else { return nil }
            return (item, links * 10 + (revisitIDs.contains(item.id) ? 5 : 0))
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id.uuidString < rhs.0.id.uuidString : lhs.1 > rhs.1
        }.prefix(max(0, limit)).map(\.0)
    }

    static func parseKeywords(_ text: String) -> [SpeakingKeyword] {
        unique(text.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: " = ")
            guard let first = parts.first, !first.trimmed.isEmpty else { return nil }
            return SpeakingKeyword(english: first.trimmed, chinese: parts.dropFirst().joined(separator: " = ").trimmed)
        })
    }
    static func studyPrompts(materials: [SpeakingMaterial], entries: [VocabularyEntry], revisitIDs: Set<UUID> = [], limit: Int = 2) -> [SpeakingMaterial] {
        var prompts = recommendations(materials: materials, entries: entries, revisitIDs: revisitIDs, limit: limit)
        var seen = Set<UUID>()
        for entry in entries where !entry.archived && !entry.english.trimmed.isEmpty && entry.english.count <= 120 && seen.insert(entry.id).inserted {
            guard prompts.count < limit else { break }
            guard !prompts.contains(where: { matches(entry, material: $0) }) else { continue }
            prompts.append(wordExercise(entry))
        }
        return prompts
    }
    static func wordExercise(_ entry: VocabularyEntry) -> SpeakingMaterial {
        let example = entry.exampleSentence?.trimmed ?? ""
        // An existing sentence is a reference; without one show only the expression, never invent an answer.
        let english = example.isEmpty ? entry.english : example
        return SpeakingMaterial(id: entry.id, title: "Use \(entry.english)", english: english, chinese: entry.gloss,
            prompt: "Describe a real situation where you could use ‘\(entry.english)’. What happened, and why does this expression fit?",
            notes: "先说一个自己的场景，再用目标词表达原因或感受。对照词义检查是否合适，最后换一个场景再说一次。",
            topic: entry.tags.first ?? "My vocabulary", kind: .phrase, source: "Vocabulary · " + entry.english,
            keywords: [SpeakingKeyword(english: entry.english, chinese: String(entry.gloss.prefix(300)))])
    }
    static func keywordText(_ items: [SpeakingKeyword]) -> String {
        items.map { $0.english + ($0.chinese.isEmpty ? "" : " = " + $0.chinese) }.joined(separator: "\n")
    }
    private static func unique(_ items: [SpeakingKeyword]) -> [SpeakingKeyword] {
        var seen = Set<String>()
        return items.filter { $0.isValid && seen.insert($0.id).inserted }
    }

    static let catalogue: [SpeakingKeyword] = [
        ("share ideas", "交流想法"), ("coursework", "课程作业"), ("teamwork", "团队合作"),
        ("to be honest", "说实话"), ("prepare for", "为……做准备"), ("in common", "共同的"),
        ("strengthen", "加强；巩固"), ("bonds", "纽带；感情"), ("swamped with", "忙于……"),
        ("put ... into practice", "把……付诸实践"), ("workflow", "工作流程"), ("comes to mind", "想到"),
        ("caught my attention", "吸引了我的注意"), ("eye-opener", "让人大开眼界的事"),
        ("intrigued by", "对……感兴趣"), ("condense", "浓缩；精简"), ("summary", "梗概；总结"),
        ("addicted to", "沉迷于……"), ("lose track of time", "忘了时间"),
        ("small pockets of free time", "零碎的空闲时间"), ("unwind", "放松"),
        ("light-hearted", "轻松愉快的"), ("at their own pace", "按自己的节奏"),
        ("that being said", "话虽如此"), ("atmosphere", "氛围"), ("reliable", "可靠的"),
        ("misinformation", "错误信息"), ("sense of belonging", "归属感"),
        ("engaging", "吸引人的"), ("help each other", "互相帮助")
    ].map { SpeakingKeyword(english: $0.0, chinese: $0.1) }
}

extension SpeakingLibrary {
    /// Persist a vocabulary-derived prompt only when the learner explicitly opens practice.
    func preparePractice(_ material: SpeakingMaterial) throws -> SpeakingMaterial {
        if let existing = materials.first(where: { $0.id == material.id || $0.duplicateKey == material.duplicateKey }) { return existing }
        guard material.source.hasPrefix("Vocabulary · ") else { throw AIError.configuration("This material is no longer available.") }
        try add([material])
        guard let saved = materials.first(where: { $0.duplicateKey == material.duplicateKey }) else {
            throw AIError.configuration("The speaking exercise could not be saved.")
        }
        return saved
    }
}

/// Only an explicit assessment of productive use updates the Chinese → English direction.
@MainActor
final class SpeakingWordReview: ObservableObject {
    @Published private(set) var savedIDs = Set<UUID>()
    func save(entryID: UUID, rating: ReviewRating, material: SpeakingMaterial,
              repository: any VocabularyRepository, scheduler: any ReviewScheduling, now: Date = Date()) async throws {
        guard !savedIDs.contains(entryID) else { return }
        guard let entry = try await repository.entry(id: entryID), SpeakingConnections.matches(entry, material: material),
              let state = try await repository.reviewState(entryID: entryID), state.state(for: .chineseToEnglish) != nil else {
            throw AIError.configuration("This word is no longer available. Refresh the vocabulary links.")
        }
        let result = scheduler.schedule(state: state, direction: .chineseToEnglish, rating: rating, now: now)
        try await repository.recordReview(result)
        savedIDs.insert(entryID)
    }
}
