import Foundation

enum Language: String, Codable, Sendable, Equatable {
    case english
    case chinese

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }
}

enum LanguageDetector {
    static func detect(_ text: String) -> Language {
        for scalar in text.unicodeScalars where (0x4E00...0x9FFF).contains(scalar.value) {
            return .chinese
        }
        return .english
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
