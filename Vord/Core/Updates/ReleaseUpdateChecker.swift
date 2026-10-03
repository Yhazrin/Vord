import Foundation

struct AppVersion: Comparable, Equatable {
    var parts: [Int]
    init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = raw.components(separatedBy: ".")
        guard (1...4).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = fields.map { Int($0)! }
        while parts.count < 4 { parts.append(0) }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct GitHubAppRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        var name: String
        var browser_download_url: URL
        var size: Int
    }
    var tag_name: String
    var html_url: URL
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]
    static func decode(_ data: Data, repository: String) throws -> Self {
        let release = try JSONDecoder().decode(Self.self, from: data)
        guard !release.draft, !release.prerelease, AppVersion(release.tag_name) != nil,
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.path.hasPrefix("/\(repository)/releases/tag/") else {
            throw AIError.configuration("The release information is invalid.")
        }
        return release
    }
    func macDownload(repository: String) -> URL? {
        assets.first { asset in
            let name = asset.name.lowercased()
            return name.contains("vord") && name.contains("macos") && (name.hasSuffix(".zip") || name.hasSuffix(".dmg")) && asset.size > 0 &&
                asset.browser_download_url.scheme == "https" && asset.browser_download_url.host == "github.com" &&
                asset.browser_download_url.path.hasPrefix("/\(repository)/releases/download/")
        }?.browser_download_url
    }
}

@MainActor
final class ReleaseUpdateChecker: ObservableObject {
    static let repository = "Yhazrin/Vord"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    @Published private(set) var checking = false
    @Published private(set) var release: GitHubAppRelease?
    @Published private(set) var message: String?
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "updates.automatic") }
    }
    private let defaults: UserDefaults
    private let session: URLSession
    let installedVersion: String
    var downloadURL: URL? { release?.macDownload(repository: Self.repository) }
    init(defaults: UserDefaults = .standard, session: URLSession = .shared,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") {
        self.defaults = defaults; self.session = session; installedVersion = version
        automatic = defaults.object(forKey: "updates.automatic") as? Bool ?? true
    }
    func checkIfDue() async {
        guard automatic, Date().timeIntervalSince(defaults.object(forKey: "updates.lastAttempt") as? Date ?? .distantPast) >= 86400 else { return }
        await check()
    }
    func check() async {
        guard !checking else { return }
        checking = true; message = nil; release = nil
        defer { checking = false }
        defaults.set(Date(), forKey: "updates.lastAttempt")
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Vord/\(installedVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 { release = nil; message = "No releases published yet."; return }
            guard http.statusCode == 200, data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
            let latest = try GitHubAppRelease.decode(data, repository: Self.repository)
            guard let installed = AppVersion(installedVersion), let available = AppVersion(latest.tag_name) else { throw URLError(.cannotParseResponse) }
            if installed < available {
                release = latest; message = "\(latest.tag_name) is available."
            } else { release = nil; message = "You're up to date." }
        } catch is CancellationError { }
        catch { message = "Could not check for updates. Try again later." }
    }
}
