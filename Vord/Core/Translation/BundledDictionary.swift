import Foundation
import SQLite3

struct DictionaryCandidate: Identifiable, Equatable, Sendable {
    enum Match: Equatable, Sendable { case exact, inflection, prefix, meaning }
    var item: DictionaryItem
    var source: String
    var match: Match
    var frequency: Int = 0
    var id: String { item.english.lowercased() }

    func result(for text: String) -> TranslationResult {
        let language = LanguageDetector.detect(text)
        return TranslationResult(sourceText: text.trimmed,
            translatedText: language == .english ? item.chinese : item.english,
            sourceLanguage: language, targetLanguage: language == .english ? .chinese : .english,
            phonetic: item.phonetic, partOfSpeech: item.partOfSpeech,
            englishDefinition: item.englishDefinition, chineseDefinition: item.chinese,
            exampleSentence: item.exampleSentence, providerName: source, dictionaryHeadword: item.english)
    }
}

/// A read-only resource, separate from the learner's SQLite library and imported overrides.
final class BundledDictionary: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let count: Int

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            throw TranslationFailure.failed("The built-in dictionary could not be opened.")
        }
        db = handle
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM metadata WHERE key='entries'", -1, &statement, nil) == SQLITE_OK else {
            sqlite3_close(handle); db = nil
            throw TranslationFailure.failed("The built-in dictionary format is not supported.")
        }
        defer { sqlite3_finalize(statement) }
        count = sqlite3_step(statement) == SQLITE_ROW ? Int(Self.text(statement!, 0) ?? "") ?? 0 : 0
    }
    deinit { if let db { sqlite3_close(db) } }

    func exact(_ text: String) throws -> DictionaryCandidate? {
        lock.lock(); defer { lock.unlock() }
        let normalized = text.trimmed.lowercased()
        if let entry = try query("SELECT * FROM lexicon WHERE normalized = ? LIMIT 1", [normalized], match: .exact).first { return entry }
        return try query("SELECT l.* FROM forms f JOIN lexicon l ON l.id=f.word_id WHERE f.form=? ORDER BY l.rank LIMIT 1", [normalized], match: .inflection).first
    }
    func search(_ text: String, language: Language, limit: Int) throws -> [DictionaryCandidate] {
        lock.lock(); defer { lock.unlock() }
        let maximum = min(30, max(1, limit))
        if language == .english {
            let prefix = text.trimmed.lowercased()
            return try query("SELECT * FROM lexicon WHERE normalized >= ? AND normalized < ? ORDER BY rank, length(english), normalized LIMIT \(maximum)", [prefix, prefix + "\u{10FFFF}"], match: .prefix)
        }
        let normalized = DictionaryStore.normalizeChinese(text)
        let terms = Self.chineseTerms(normalized)
        if terms.isEmpty { return [] }
        let all = terms.map { "\"\($0)\"" }.joined(separator: " AND ")
        let sql = """
        SELECT l.* FROM chinese_search f JOIN lexicon l ON l.id=f.rowid
        WHERE chinese_search MATCH ?
        ORDER BY CASE WHEN instr(l.search,?) > 0 THEN 0 ELSE 1 END, l.rank, length(l.english)
        LIMIT 180
        """
        var matches = try query(sql, [all, normalized], match: .meaning)
        if matches.isEmpty, terms.count > 1 {
            let any = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
            matches = try query(sql, [any, normalized], match: .meaning)
        }
        if normalized.count == 1 {
            matches = try query("SELECT * FROM lexicon WHERE instr(search,?)>0 ORDER BY rank, length(english) LIMIT 180", [normalized], match: .meaning)
        }
        return Array(matches.sorted { Self.score($0, query: normalized) < Self.score($1, query: normalized) }.prefix(maximum))
    }
    private func query(_ sql: String, _ bindings: [String], match: DictionaryCandidate.Match) throws -> [DictionaryCandidate] {
        guard let db else { throw TranslationFailure.failed("The dictionary is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TranslationFailure.failed("Dictionary search failed: " + String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient) == SQLITE_OK else {
                throw TranslationFailure.failed("Dictionary search could not be prepared.")
            }
        }
        var result: [DictionaryCandidate] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw TranslationFailure.failed("Dictionary search failed.") }
            // lexicon columns: id, english, normalized, chinese, phonetic, pos, definition, rank, search
            let item = DictionaryItem(english: Self.text(statement, 1) ?? "", chinese: Self.text(statement, 3) ?? "",
                phonetic: Self.text(statement, 4), partOfSpeech: Self.text(statement, 5), englishDefinition: Self.text(statement, 6))
            result.append(DictionaryCandidate(item: item, source: "ECDICT · offline", match: match,
                                              frequency: Int(sqlite3_column_int(statement, 7))))
        }
        return result
    }
    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
    private static func chineseTerms(_ value: String) -> [String] {
        let characters = value.filter { $0.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }.map(String.init)
        if characters.count <= 1 { return characters }
        return Array(Set((0..<characters.count - 1).map { characters[$0] + characters[$0 + 1] })).sorted()
    }
    static func score(_ candidate: DictionaryCandidate, query: String) -> Int {
        let chinese = DictionaryStore.normalizeChinese(candidate.item.chinese)
        let senses = chinese.components(separatedBy: CharacterSet(charactersIn: "；;、,，\n"))
            .map { $0.replacingOccurrences(of: "^[a-z. ]+", with: "", options: .regularExpression).trimmed }
        let match = senses.contains(query) || senses.contains(query + "的") ? 0 : (chinese.contains(query) ? 1 : 2)
        // Common words with a close sense are more useful than rare exact synonyms.
        return match * 10_000 + min(1_000_000, max(0, candidate.frequency))
    }
}
