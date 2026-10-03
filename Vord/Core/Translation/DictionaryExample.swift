import Foundation

/// Example sentences copied from dictionary text. Nothing here is generated.
enum DictionaryExample {
    static func extract(from definition: String?, headword: String) -> String? {
        guard var body = definition?.trimmed, !body.isEmpty else { return nil }
        let word = headword.trimmed
        guard !word.isEmpty else { return nil }
        body = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if let origin = body.range(of: " ORIGIN ", options: .caseInsensitive) {
            body = String(body[..<origin.lowerBound])
        }
        var search = body[...]
        while let colon = search.range(of: ": ") {
            var after = search[colon.upperBound...]
            after = skipAnnotations(after)
            guard let clause = readClause(from: after) else {
                search = search[colon.upperBound...]
                continue
            }
            let sentence = firstSentence(clause)
            if looksLikeExample(sentence), containsHeadword(sentence, word: word) {
                return sentence
            }
            search = search[colon.upperBound...]
        }
        return nil
    }

    private static func skipAnnotations(_ text: Substring) -> Substring {
        var rest = text.drop(while: { $0 == " " })
        while rest.hasPrefix("[") {
            guard let end = rest.firstIndex(of: "]") else { break }
            var next = rest[rest.index(after: end)...]
            while next.first == " " || next.first == ":" { next = next.dropFirst() }
            rest = next
        }
        return rest
    }

    private static func readClause(from text: Substring) -> String? {
        var end = text.endIndex
        for marker in [" | ", " • "] {
            if let range = text.range(of: marker) { end = min(end, range.lowerBound) }
        }
        let clause = text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return clause.isEmpty ? nil : String(clause)
    }

    private static func firstSentence(_ clause: String) -> String {
        var index = clause.startIndex
        while index < clause.endIndex {
            let character = clause[index]
            let next = clause.index(after: index)
            if character == "." || character == "!" || character == "?" {
                var cursor = next
                while cursor < clause.endIndex, clause[cursor] == " " { cursor = clause.index(after: cursor) }
                if cursor == clause.endIndex { return clause.trimmed }
                let following = clause[cursor]
                if following.isNumber || following.isUppercase || "•“\"".contains(following) {
                    return String(clause[..<next]).trimmed
                }
            }
            index = next
        }
        return clause.trimmed
    }

    private static func looksLikeExample(_ sentence: String) -> Bool {
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2, sentence.count >= 8, sentence.count <= 400 else { return false }
        let lower = sentence.lowercased()
        if lower.hasPrefix("from ") || lower.hasPrefix("origin ") { return false }
        return sentence.contains(where: { $0.isLetter })
    }

    private static func containsHeadword(_ sentence: String, word: String) -> Bool {
        let needle = word.trimmed.lowercased()
        guard !needle.isEmpty else { return false }
        if needle.contains(" ") { return sentence.lowercased().contains(needle) }
        let tokens = sentence.lowercased().split { !($0.isLetter || $0 == "'" || $0 == "’" || $0 == "-") }.map(String.init)
        if needle.count < 3 { return tokens.contains(needle) }
        return tokens.contains { token in
            token == needle || (token.hasPrefix(needle) && token.count - needle.count <= 3)
        }
    }
}
