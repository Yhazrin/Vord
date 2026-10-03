import XCTest
@testable import Vord

final class ReleaseUpdateTests: XCTestCase {
    func testNumericVersionsHandleDifferentComponentLengths() throws {
        XCTAssertEqual(AppVersion("v1.0"), AppVersion("1.0.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.9")), try XCTUnwrap(AppVersion("1.10.0")))
        XCTAssertNil(AppVersion("1.0-rc"))
        XCTAssertNil(AppVersion("latest"))
    }
    func testReleaseMustBeStableAndBelongToConfiguredRepository() throws {
        let data = Data(#"{"tag_name":"v1.1.0","html_url":"https://github.com/Yhazrin/Vord/releases/tag/v1.1.0","draft":false,"prerelease":false,"assets":[{"name":"Vord-macOS.zip","size":1024,"browser_download_url":"https://github.com/Yhazrin/Vord/releases/download/v1.1.0/Vord-macOS.zip"}]}"#.utf8)
        let release = try GitHubAppRelease.decode(data, repository: "Yhazrin/Vord")
        XCTAssertNotNil(release.macDownload(repository: "Yhazrin/Vord"))
        XCTAssertNil(release.macDownload(repository: "Other/Repo"))
        XCTAssertThrowsError(try GitHubAppRelease.decode(data, repository: "Other/Repo"))
        let draft = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true")
        XCTAssertThrowsError(try GitHubAppRelease.decode(Data(draft.utf8), repository: "Yhazrin/Vord"))
    }

    @MainActor
    func testHTTP404MeansNoPublishedRelease() async {
        let fixture = ReleaseHTTPFixture(replies: [.init(status: 404)])
        defer { fixture.close() }
        await fixture.checker.check()
        XCTAssertFalse(fixture.checker.checking)
        XCTAssertNil(fixture.checker.release)
        XCTAssertNil(fixture.checker.downloadURL)
        XCTAssertEqual(fixture.checker.message, "No releases published yet.")
        XCTAssertEqual(fixture.server.requests.first?.url?.path, "/repos/Yhazrin/Vord/releases/latest")
        XCTAssertEqual(fixture.server.requests.first?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    @MainActor
    func testHTTPNewerVersionOffersMacDownload() async {
        let fixture = ReleaseHTTPFixture(replies: [.release("v1.1.0")], version: "1.0.0")
        defer { fixture.close() }
        await fixture.checker.check()
        XCTAssertEqual(fixture.checker.release?.tag_name, "v1.1.0")
        XCTAssertEqual(fixture.checker.downloadURL?.lastPathComponent, "Vord-macOS.zip")
        XCTAssertEqual(fixture.checker.message, "v1.1.0 is available.")
        XCTAssertEqual(fixture.server.requests.first?.value(forHTTPHeaderField: "User-Agent"), "Vord/1.0.0")
    }

    @MainActor
    func testHTTPCurrentVersionClearsPreviousOffer() async {
        let fixture = ReleaseHTTPFixture(replies: [.release("v1.1.0"), .release("v1.0.0")], version: "1.0")
        defer { fixture.close() }
        await fixture.checker.check()
        XCTAssertNotNil(fixture.checker.downloadURL)
        await fixture.checker.check()
        XCTAssertNil(fixture.checker.release)
        XCTAssertNil(fixture.checker.downloadURL)
        XCTAssertEqual(fixture.checker.message, "You're up to date.")
    }

    @MainActor
    func testHTTPFailureRemovesStaleDownloadAndReportsError() async {
        let fixture = ReleaseHTTPFixture(replies: [.release("v1.1.0"), .init(status: 500)])
        defer { fixture.close() }
        await fixture.checker.check()
        XCTAssertNotNil(fixture.checker.downloadURL)
        await fixture.checker.check()
        XCTAssertFalse(fixture.checker.checking)
        XCTAssertNil(fixture.checker.release)
        XCTAssertNil(fixture.checker.downloadURL)
        XCTAssertEqual(fixture.checker.message, "Could not check for updates. Try again later.")
        XCTAssertNotNil(fixture.defaults.object(forKey: "updates.lastAttempt") as? Date)
    }

    @MainActor
    func testMalformedHTTPReleaseRemovesPreviousDownload() async {
        let fixture = ReleaseHTTPFixture(replies: [.release("v1.1.0"), .init(status: 200, body: Data("invalid".utf8))])
        defer { fixture.close() }
        await fixture.checker.check()
        await fixture.checker.check()
        XCTAssertNil(fixture.checker.downloadURL)
        XCTAssertEqual(fixture.checker.message, "Could not check for updates. Try again later.")
    }

    @MainActor
    func testAutomaticCheckRunsAtMostOncePerDayIncludingFailures() async {
        let fixture = ReleaseHTTPFixture(replies: [.init(status: 500), .init(status: 404)])
        defer { fixture.close() }
        await fixture.checker.checkIfDue()
        await fixture.checker.checkIfDue()
        XCTAssertEqual(fixture.server.requests.count, 1)
        fixture.defaults.set(Date().addingTimeInterval(-86401), forKey: "updates.lastAttempt")
        await fixture.checker.checkIfDue()
        XCTAssertEqual(fixture.server.requests.count, 2)
        XCTAssertEqual(fixture.checker.message, "No releases published yet.")
    }

    @MainActor
    func testDisabledAutomaticChecksKeepManualChecksAvailable() async {
        let fixture = ReleaseHTTPFixture(replies: [.init(status: 404), .init(status: 404)])
        defer { fixture.close() }
        fixture.checker.automatic = false
        await fixture.checker.checkIfDue()
        XCTAssertEqual(fixture.server.requests.count, 0)
        XCTAssertNil(fixture.defaults.object(forKey: "updates.lastAttempt"))
        XCTAssertFalse(fixture.defaults.bool(forKey: "updates.automatic"))
        await fixture.checker.check()
        await fixture.checker.check()
        XCTAssertEqual(fixture.server.requests.count, 2)
    }
}

@MainActor
private final class ReleaseHTTPFixture {
    let defaults: UserDefaults
    let checker: ReleaseUpdateChecker
    let server: ReleaseHTTPServer
    private let session: URLSession
    private let identifier: String
    private let suite: String

    init(replies: [ReleaseHTTPServer.Reply], version: String = "1.0.0") {
        let identifier = UUID().uuidString
        let suite = "Vord.ReleaseUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let server = ReleaseHTTPServer(replies: replies)
        ReleaseStubURLProtocol.register(server, identifier: identifier)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Vord-Test-ID": identifier]
        let session = URLSession(configuration: configuration)
        self.identifier = identifier; self.suite = suite
        self.defaults = defaults; self.server = server; self.session = session
        checker = ReleaseUpdateChecker(defaults: defaults, session: session, version: version)
    }

    func close() {
        session.invalidateAndCancel()
        ReleaseStubURLProtocol.remove(identifier: identifier)
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class ReleaseHTTPServer {
    struct Reply {
        var status: Int
        var body = Data()
        static func release(_ version: String) -> Self {
            let object: [String: Any] = ["tag_name": version,
                "html_url": "https://github.com/Yhazrin/Vord/releases/tag/\(version)",
                "draft": false, "prerelease": false,
                "assets": [["name": "Vord-macOS.zip", "size": 1024,
                    "browser_download_url": "https://github.com/Yhazrin/Vord/releases/download/\(version)/Vord-macOS.zip"]]]
            return Self(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
        }
    }
    private let lock = NSLock()
    private var replies: [Reply]
    private var observed: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return observed }
    init(replies: [Reply]) { self.replies = replies }
    func reply(to request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }
        observed.append(request)
        return replies.isEmpty ? Reply(status: 599) : replies.removeFirst()
    }
}

private final class ReleaseStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var servers: [String: ReleaseHTTPServer] = [:]
    static func register(_ server: ReleaseHTTPServer, identifier: String) {
        lock.lock(); defer { lock.unlock() }; servers[identifier] = server
    }
    static func remove(identifier: String) {
        lock.lock(); defer { lock.unlock() }; servers.removeValue(forKey: identifier)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let server = Self.servers[request.value(forHTTPHeaderField: "X-Vord-Test-ID") ?? ""]
        Self.lock.unlock()
        guard let server, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let reply = server.reply(to: request)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
