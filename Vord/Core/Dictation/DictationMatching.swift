import Foundation

enum DictationMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case chineseToEnglish
    case englishToChinese
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chineseToEnglish: return "Chinese → English"
        case .englishToChinese: return "English → Chinese"
        case .mixed: return "Mixed"
        }
    }
}

enum DictationDirection: String, Sendable, Equatable, Codable {
    case chineseToEnglish
    case englishToChinese

    var answerPlaceholder: String {
        switch self {
        case .chineseToEnglish: return "English"
        case .englishToChinese: return "Chinese"
        }
    }
}

struct DictationQuestion: Identifiable, Equatable, Sendable, Codable {
    var id: UUID
    var prompt: String
    var phonetic: String?
    var expected: String
    var accepted: [String]
    var direction: DictationDirection
}

enum DictationMatching {
    static func isEligible(_ entry: VocabularyEntry) -> Bool {
        !english(of: entry).isEmpty && !chinese(of: entry).isEmpty
    }

    static func questions(
        from entries: [VocabularyEntry],
        count: Int,
        mode: DictationMode,
        random: inout some RandomNumberGenerator
    ) -> [DictationQuestion] {
        let eligible = entries.filter(isEligible)
        guard count > 0, !eligible.isEmpty else { return [] }
        return eligible.shuffled(using: &random).prefix(count).map { entry in
            let direction = direction(for: mode, random: &random)
            return DictationQuestion(
                id: UUID(),
                prompt: prompt(entry, direction),
                phonetic: direction == .englishToChinese ? entry.phonetic?.trimmed.nilIfEmpty : nil,
                expected: displayAnswer(entry, direction),
                accepted: acceptedAnswers(entry, direction),
                direction: direction
            )
        }
    }

    static func matches(input: String, accepted: [String]) -> Bool {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return false }
        return accepted.contains { normalize($0) == normalized }
    }

    static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }

    private static func direction(
        for mode: DictationMode,
        random: inout some RandomNumberGenerator
    ) -> DictationDirection {
        switch mode {
        case .chineseToEnglish:
            return .chineseToEnglish
        case .englishToChinese:
            return .englishToChinese
        case .mixed:
            return Bool.random(using: &random) ? .chineseToEnglish : .englishToChinese
        }
    }

    private static func prompt(_ entry: VocabularyEntry, _ direction: DictationDirection) -> String {
        switch direction {
        case .chineseToEnglish: return chinese(of: entry)
        case .englishToChinese: return english(of: entry)
        }
    }

    private static func displayAnswer(_ entry: VocabularyEntry, _ direction: DictationDirection) -> String {
        switch direction {
        case .chineseToEnglish: return english(of: entry)
        case .englishToChinese: return chinese(of: entry)
        }
    }

    private static func acceptedAnswers(_ entry: VocabularyEntry, _ direction: DictationDirection) -> [String] {
        switch direction {
        case .chineseToEnglish:
            var answers = [english(of: entry)]
            if let lemma = entry.lemma?.trimmed, !lemma.isEmpty {
                answers.append(lemma)
            }
            return answers
        case .englishToChinese:
            var answers = [entry.chinese, entry.chineseDefinition ?? "", entry.gloss]
            answers.append(contentsOf: answers.flatMap(pieces))
            return answers
        }
    }

    private static func english(of entry: VocabularyEntry) -> String {
        entry.english.trimmed
    }

    private static func chinese(of entry: VocabularyEntry) -> String {
        if let fuller = entry.chineseDefinition?.trimmed, !fuller.isEmpty {
            return fuller
        }
        return entry.chinese.trimmed
    }

    private static func pieces(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: "；;、,，/|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
