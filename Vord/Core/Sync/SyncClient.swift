import Foundation

protocol SyncTransport: Sendable {
    func exchange(_ request: SyncRequest, endpoint: URL, token: String) async throws -> SyncResponse
}

struct HTTPSyncTransport: SyncTransport {
    var session: URLSession = .shared
    func exchange(_ request: SyncRequest, endpoint: URL, token: String) async throws -> SyncResponse {
        var http = URLRequest(url: endpoint.appendingPathComponent("v1/sync"))
        http.httpMethod = "POST"
        http.timeoutInterval = 25
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        http.httpBody = try SyncCodec.encoder().encode(request)
        let (data, response) = try await session.data(for: http)
        guard let response = response as? HTTPURLResponse else { throw SyncFailure.server }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw SyncFailure.authentication
        case 429: throw SyncFailure.busy
        default: throw SyncFailure.status(response.statusCode)
        }
        guard data.count <= 40 * 1024 * 1024 else { throw SyncFailure.server }
        return try SyncCodec.decoder().decode(SyncResponse.self, from: data)
    }
}

enum SyncFailure: LocalizedError {
    case endpoint, authentication, busy, server, status(Int)
    var errorDescription: String? {
        switch self {
        case .endpoint: return "Use an HTTPS sync server address without a query or password."
        case .authentication: return "The sync code was not accepted. Check it in Settings. Your local words are safe."
        case .busy: return "The server is busy. Sync will retry shortly."
        case .server: return "The sync server returned an invalid response."
        case .status(let code): return "Sync could not finish (HTTP \(code)). Your changes remain on this Mac."
        }
    }
    static func validatedEndpoint(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw SyncFailure.endpoint }
        return url
    }
}
