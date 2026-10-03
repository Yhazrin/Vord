import Foundation

struct Lexeme: Sendable, Equatable {
    var english: String
    var chinese: String
    var phonetic: String
    var partOfSpeech: String
    var englishDefinition: String
    var chineseDefinition: String
    var exampleSentence: String
    var tags: [String]
}

enum SampleLexicon {
    static let entries: [Lexeme] = [
        Lexeme(
            english: "astonish",
            chinese: "使惊讶；使震惊",
            phonetic: "/əˈstɒnɪʃ/",
            partOfSpeech: "verb",
            englishDefinition: "to surprise someone very much",
            chineseDefinition: "使非常惊讶；使震惊",
            exampleSentence: "His sudden decision astonished everyone.",
            tags: ["IELTS", "TV"]
        ),
        Lexeme(
            english: "deteriorate",
            chinese: "恶化；退化",
            phonetic: "/dɪˈtɪəriəreɪt/",
            partOfSpeech: "verb",
            englishDefinition: "to become progressively worse",
            chineseDefinition: "恶化；退化",
            exampleSentence: "His health began to deteriorate.",
            tags: ["IELTS"]
        ),
        Lexeme(
            english: "ubiquitous",
            chinese: "无处不在的",
            phonetic: "/juːˈbɪkwɪtəs/",
            partOfSpeech: "adjective",
            englishDefinition: "seeming to be everywhere",
            chineseDefinition: "无处不在的",
            exampleSentence: "Mobile phones are now ubiquitous.",
            tags: ["IELTS"]
        ),
        Lexeme(
            english: "intimidate",
            chinese: "恐吓；威胁",
            phonetic: "/ɪnˈtɪmɪdeɪt/",
            partOfSpeech: "verb",
            englishDefinition: "to frighten or threaten someone",
            chineseDefinition: "恐吓；威胁",
            exampleSentence: "The interviewer tried to intimidate her.",
            tags: ["IELTS"]
        ),
        Lexeme(
            english: "mitigate",
            chinese: "缓解；减轻",
            phonetic: "/ˈmɪtɪɡeɪt/",
            partOfSpeech: "verb",
            englishDefinition: "to make something less severe",
            chineseDefinition: "缓解；减轻",
            exampleSentence: "Measures were taken to mitigate the damage.",
            tags: ["IELTS"]
        ),
        Lexeme(
            english: "exacerbate",
            chinese: "加剧；恶化",
            phonetic: "/ɪɡˈzæsəbeɪt/",
            partOfSpeech: "verb",
            englishDefinition: "to make a problem worse",
            chineseDefinition: "加剧；恶化",
            exampleSentence: "The new policy may exacerbate inequality.",
            tags: ["IELTS"]
        )
    ]

    static func match(text: String, from source: Language) -> Lexeme? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        if source == .english {
            return entries.first { $0.english.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
        let normalized = trimmed.replacingOccurrences(of: " ", with: "")
        let hits = entries.filter { senses($0.chinese).contains(normalized) || $0.chinese == normalized }
        if let primary = hits.first(where: { senses($0.chinese).first == normalized }) {
            return primary
        }
        return hits.first
    }

    static func enrich(_ result: TranslationResult) -> TranslationResult {
        guard let lexeme = entries.first(where: { $0.english.caseInsensitiveCompare(result.english.trimmed) == .orderedSame }) else {
            return result
        }
        var copy = result
        if copy.phonetic == nil { copy.phonetic = lexeme.phonetic }
        if copy.partOfSpeech == nil { copy.partOfSpeech = lexeme.partOfSpeech }
        if copy.englishDefinition == nil { copy.englishDefinition = lexeme.englishDefinition }
        if copy.chineseDefinition == nil { copy.chineseDefinition = lexeme.chineseDefinition }
        if copy.exampleSentence == nil { copy.exampleSentence = lexeme.exampleSentence }
        return copy
    }

    static func draft(from lexeme: Lexeme, source: String) -> EntryDraft {
        EntryDraft(
            english: lexeme.english,
            chinese: lexeme.chinese,
            lemma: lexeme.english,
            phonetic: lexeme.phonetic,
            partOfSpeech: lexeme.partOfSpeech,
            englishDefinition: lexeme.englishDefinition,
            chineseDefinition: lexeme.chineseDefinition,
            exampleSentence: lexeme.exampleSentence,
            source: source,
            tags: lexeme.tags
        )
    }

    private static func senses(_ chinese: String) -> [String] {
        chinese
            .split { "；;，,".contains($0) }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
