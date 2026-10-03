import Foundation

/// Only short lexical selections are accepted; external inputs cannot issue app commands.
struct ExternalCaptureRequest: Equatable, Sendable {
    let text: String
    let source: String?
    init(text: String, source: String? = nil) throws {
        let normalized = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”.,;:!?()[]{}"))
        guard !normalized.isEmpty, normalized.count <= 120,
              normalized.split(separator: " ").count <= 8,
              normalized.unicodeScalars.contains(where: { (65...90).contains($0.value) || (97...122).contains($0.value) }),
              normalized.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) ||
                  " '-’.".unicodeScalars.contains($0)
              }) else { throw CaptureInputError.invalidSelection }
        self.text = normalized
        self.source = Self.cleanSource(source)
    }
    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "vord", components.host == "capture",
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else { throw CaptureInputError.invalidLink }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ $0.name == "text" || $0.name == "source" }),
              items.filter({ $0.name == "text" }).count == 1,
              items.filter({ $0.name == "source" }).count <= 1,
              let text = items.first(where: { $0.name == "text" })?.value else { throw CaptureInputError.invalidLink }
        try self.init(text: text, source: items.first(where: { $0.name == "source" })?.value)
    }
    var url: URL {
        var components = URLComponents()
        components.scheme = "vord"; components.host = "capture"
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        if let source { components.queryItems?.append(URLQueryItem(name: "source", value: source)) }
        return components.url!
    }
    private static func cleanSource(_ source: String?) -> String? {
        guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
        if var url = URLComponents(string: source), let scheme = url.scheme {
            guard ["http", "https"].contains(scheme.lowercased()), url.host != nil else { return nil }
            url.query = nil; url.fragment = nil; url.user = nil; url.password = nil
            return url.string.map { String($0.prefix(2048)) }
        }
        return String(source.prefix(160))
    }
}

enum CaptureInputError: LocalizedError {
    case invalidSelection, invalidLink
    var errorDescription: String? {
        switch self {
        case .invalidSelection: return "Select an English word or a short phrase (up to 8 words)."
        case .invalidLink: return "This Vord capture link is invalid."
        }
    }
}
