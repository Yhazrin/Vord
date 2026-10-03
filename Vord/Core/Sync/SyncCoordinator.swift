import AppKit
import Combine
import CryptoKit
import Foundation

struct SyncPairing: Codable {
    var endpoint: String
    var token: String
}

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var syncing = false
    @Published private(set) var message = "Keep words and review progress on your devices."
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var pendingCount = 0
    @Published var endpoint: String
    static let defaultEndpoint = "https://yhazrin.xyz/vord-sync"
    private let store: SyncStore
    private let transport: any SyncTransport
    private let defaults: UserDefaults
    private let readCredential: () throws -> String?
    private var token: String?
    private var account = ""
    private var observers = Set<AnyCancellable>()
    private var scheduled: Task<Void, Never>?
    private var retryNeeded = false
    private var connectionGeneration = 0
    private var observedPendingRevision: Int64 = 0
    private let keychainService = "app.vord.macos.sync"
    private let keychainAccount = "library"

    init(database: AppDatabase, defaults: UserDefaults = .standard, transport: any SyncTransport = HTTPSyncTransport(),
         readCredential: @escaping () throws -> String? = { try KeychainStore.get(account: "library", service: "app.vord.macos.sync") }) {
        self.store = SyncStore(database: database)
        self.defaults = defaults; self.transport = transport; self.readCredential = readCredential
        endpoint = defaults.string(forKey: "sync.endpoint") ?? Self.defaultEndpoint
        lastSuccess = defaults.object(forKey: "sync.lastSuccess") as? Date
        NotificationCenter.default.publisher(for: .vordLibraryDidChange)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                if notification.userInfo?["origin"] as? String != "sync" { self?.schedule() }
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule(delay: 0) }.store(in: &observers)
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.schedule(delay: 0) }.store(in: &observers)
        Timer.publish(every: 3, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                if NSApplication.shared.isActive { self?.schedule() }
            }.store(in: &observers)
        // Another running build or capture helper can commit to this same SQLite library.
        // In-process notifications alone cannot observe those writes.
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in Task { await self?.checkForLocalChanges() } }.store(in: &observers)
    }

    func start() async {
        do {
            if defaults.bool(forKey: "sync.connected"), let saved = try readCredential() {
                try await activate(endpoint: endpoint, code: saved)
                await syncNow()
            }
            // A deployment can deliver a one-time private pairing file without embedding a secret in the app.
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Vord", isDirectory: true)
            let file = folder.appendingPathComponent("sync-pairing.json")
            if FileManager.default.fileExists(atPath: file.path) {
                try await importPairing(file)
                try FileManager.default.removeItem(at: file)
            }
        } catch { message = error.localizedDescription }
    }

    func connect(code: String, server: String? = nil) async throws {
        let url = try SyncFailure.validatedEndpoint(server ?? endpoint)
        let code = code.trimmed
        guard !code.isEmpty else { throw SyncFailure.authentication }
        // Authenticate before switching the durable cursor or uploading the user's library.
        _ = try await transport.exchange(SyncRequest(deviceID: UUID().uuidString, cursor: 0, changes: []), endpoint: url, token: code)
        try KeychainStore.set(account: keychainAccount, secret: code, service: keychainService)
        try await activate(endpoint: url.absoluteString, code: code)
        await syncNow()
    }

    private func activate(endpoint: String, code: String) async throws {
        _ = try SyncFailure.validatedEndpoint(endpoint)
        let identity = SHA256.hash(data: Data((endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "\n" + code).utf8))
            .map { String(format: "%02x", $0) }.joined()
        connectionGeneration += 1
        try await store.prepare(account: identity)
        self.endpoint = endpoint; token = code; account = identity; connected = true
        defaults.set(endpoint, forKey: "sync.endpoint"); defaults.set(true, forKey: "sync.connected")
    }

    func importPairing(_ url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 8192 else { throw SyncFailure.authentication }
        let pairing = try JSONDecoder().decode(SyncPairing.self, from: data)
        try await connect(code: pairing.token, server: pairing.endpoint)
    }

    func disconnect() {
        connectionGeneration += 1; scheduled?.cancel(); scheduled = nil
        token = nil; connected = false; defaults.set(false, forKey: "sync.connected")
        message = "Disconnected. Your words remain on this Mac."
    }

    func syncNow() async {
        guard connected, let token else { return }
        if syncing { retryNeeded = true; return }
        syncing = true; retryNeeded = false
        let generation = connectionGeneration
        defer { syncing = false }
        do {
            let url = try SyncFailure.validatedEndpoint(endpoint)
            var changed = false
            for _ in 0..<30 {
                guard connected, generation == connectionGeneration else { return }
                let request = try await store.request()
                pendingCount = request.changes.count
                message = "Syncing…"
                let response = try await transport.exchange(request, endpoint: url, token: token)
                guard connected, generation == connectionGeneration else { return }
                try await store.apply(response, sent: request)
                changed = changed || !response.changes.isEmpty
                let remaining = try await store.request()
                pendingCount = remaining.changes.count
                if !response.hasMore && remaining.changes.isEmpty {
                    lastSuccess = Date(); defaults.set(lastSuccess, forKey: "sync.lastSuccess")
                    message = "Up to date"
                    if changed { NotificationCenter.default.post(name: .vordLibraryDidChange, object: nil, userInfo: ["origin": "sync"]) }
                    if retryNeeded { schedule() }
                    return
                }
            }
            message = "Continuing sync…"; schedule(delay: 1)
        } catch {
            if case SyncFailure.status(409) = error {
                do {
                    try await store.recoverFromRestoredServer()
                    message = "Reconnecting after a server restore. Local words and deletions are preserved."
                    schedule(delay: 1)
                    return
                } catch { message = "Unable to reconnect. Your local changes are preserved."; return }
            }
            message = (error as? SyncFailure)?.localizedDescription ?? "Offline or unable to sync. Changes are kept here and will retry."
            schedule(delay: 30)
        }
    }

    func checkForLocalChanges() async {
        guard connected else { return }
        guard let revision = try? await store.pendingRevision() else { return }
        let changed = revision > 0 && revision != observedPendingRevision
        observedPendingRevision = revision
        if changed { schedule() }
    }

    func schedule(delay: Double = 0) {
        guard connected else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.scheduled = nil
            await self.syncNow()
        }
    }
}
