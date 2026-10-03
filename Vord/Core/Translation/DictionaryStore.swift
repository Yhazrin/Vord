import Foundation
import CoreServices

struct DictionaryItem: Codable, Equatable, Sendable {
    var english: String
    var chinese: String
    var phonetic: String?
    var partOfSpeech: String?
    var englishDefinition: String?
    var exampleSentence: String?
}

/// Imported dictionaries are independent from the learner's library.
final class DictionaryStore: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var entries: [DictionaryItem] = []
    private var englishIndex: [String: DictionaryItem] = [:]
    private var chineseIndex: [String: DictionaryItem] = [:]
    private let bundled: BundledDictionary?
    private(set) var loadWarning: String?
    init(url: URL? = nil, bundledURL: URL? = Bundle.main.url(forResource: "lexicon", withExtension: "sqlite")) {
        if let bundledURL {
            do { bundled = try BundledDictionary(url: bundledURL) }
            catch { bundled = nil; loadWarning = error.localizedDescription }
        } else { bundled = nil }
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vord/dictionary.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { entries = try Self.decode(Data(contentsOf: self.url)); rebuild() }
            catch { loadWarning = "Imported dictionary could not be loaded: \(error.localizedDescription)" }
        }
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    var bundledCount: Int { bundled?.count ?? 0 }
    func match(_ text: String, from language: Language) -> DictionaryItem? {
        if language == .chinese { return try? search(text, from: language, limit: 1).first?.item }
        lock.lock()
        let imported = englishIndex[text.trimmed.lowercased()]
        lock.unlock()
        return imported ?? (try? bundled?.exact(text))?.item
    }
    func search(_ text: String, from language: Language, limit: Int = 12) throws -> [DictionaryCandidate] {
        let raw = text.trimmed
        guard !raw.isEmpty else { return [] }
        let normalized = language == .english ? raw.lowercased() : Self.normalizeChinese(raw)
        lock.lock()
        let imported = entries
        lock.unlock()
        var candidates = imported.compactMap { item -> DictionaryCandidate? in
            let matches = language == .english ? item.english.lowercased().hasPrefix(normalized)
                : Self.normalizeChinese(item.chinese).contains(normalized)
            guard matches else { return nil }
            return DictionaryCandidate(item: item, source: "Imported dictionary",
                match: language == .chinese ? .meaning : (item.english.lowercased() == normalized ? .exact : .prefix))
        }
        if language == .english, let exact = try bundled?.exact(raw) {
            if !candidates.contains(where: { $0.id == exact.id }) { candidates.insert(exact, at: 0) }
        }
        let packaged = try bundled?.search(raw, language: language, limit: max(20, limit)) ?? []
        var seen = Set(candidates.map(\.id))
        for candidate in packaged where seen.insert(candidate.id).inserted { candidates.append(candidate) }
        if language == .english {
            candidates.sort { lhs, rhs in
                let left = lhs.match == .exact || lhs.match == .inflection
                let right = rhs.match == .exact || rhs.match == .inflection
                if left != right { return left }
                return lhs.frequency == rhs.frequency ? lhs.id < rhs.id : lhs.frequency < rhs.frequency
            }
        } else {
            candidates.sort {
                let left = BundledDictionary.score($0, query: normalized), right = BundledDictionary.score($1, query: normalized)
                return left == right ? $0.id < $1.id : left < right
            }
        }
        return Array(candidates.prefix(min(30, max(1, limit))))
    }
    static func normalizeChinese(_ value: String) -> String {
        (value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value).trimmed
    }
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let incoming = try Self.decode(data)
        lock.lock(); defer { lock.unlock() }
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.english.lowercased(), $0) })
        for item in incoming { merged[item.english.lowercased()] = item }
        let next = merged.values.sorted { $0.english < $1.english }
        let encoded = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
        entries = next; rebuild(); loadWarning = nil
        return incoming.count
    }
    static func decode(_ data: Data) throws -> [DictionaryItem] {
        guard data.count <= 50_000_000 else { throw TranslationFailure.failed("Dictionary must be smaller than 50 MB.") }
        let incoming = try JSONDecoder().decode([DictionaryItem].self, from: data)
        guard !incoming.isEmpty, incoming.count <= 100_000 else { throw TranslationFailure.failed("Use a dictionary with 1–100,000 entries.") }
        var seen = Set<String>()
        return try incoming.map { original in
            var item = original
            item.english = item.english.trimmed; item.chinese = item.chinese.trimmed
            guard !item.english.isEmpty, !item.chinese.isEmpty,
                  seen.insert(item.english.lowercased()).inserted else {
                throw TranslationFailure.failed("Every dictionary row needs English and Chinese, with no duplicate English headwords.")
            }
            return item
        }
    }
    private func rebuild() {
        englishIndex = [:]; chineseIndex = [:]
        for item in entries {
            englishIndex[item.english.lowercased()] = item
            chineseIndex[item.chinese] = item
            for part in item.chinese.components(separatedBy: CharacterSet(charactersIn: "；;、")) where !part.trimmed.isEmpty {
                // Keep a stable first match when several words share a meaning.
                if chineseIndex[part.trimmed] == nil { chineseIndex[part.trimmed] = item }
            }
        }
    }
    static func systemDefinition(_ text: String) -> String? {
        let value = text.trimmed as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(value))
        return DCSCopyTextDefinition(nil, value, range)?.takeRetainedValue() as String?
    }
}
