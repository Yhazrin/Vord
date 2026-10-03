import AppKit

enum BrowserIntegrationTarget: String, CaseIterable, Identifiable {
    case chrome, edge
    var id: String { rawValue }
    var title: String { self == .chrome ? "Chrome" : "Edge" }
    var profile: String { self == .chrome ? "Google/Chrome" : "Microsoft Edge" }
}

@MainActor
enum BrowserIntegrationSetup {
    static func install(bundle: Bundle = .main, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        browser: BrowserIntegrationTarget = .chrome) throws -> URL {
        guard let helper = bundle.url(forResource: "VordSelectionBridge", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: helper.path),
              let packaged = bundle.url(forResource: "BrowserExtension", withExtension: nil) else {
            throw TranslationFailure.failed("The browser extension is missing from this build of Vord.")
        }
        let support = home.appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("Vord/BrowserExtension")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Copy individual files atomically, so loading a previous extension during an update is safe.
        for file in try FileManager.default.contentsOfDirectory(at: packaged, includingPropertiesForKeys: nil) {
            try Data(contentsOf: file).write(to: folder.appendingPathComponent(file.lastPathComponent), options: .atomic)
        }
        let manifest: [String: Any] = ["name": BrowserIntegrationIdentity.hostName, "description": "Vord selected-word capture",
            "path": helper.path, "type": "stdio", "allowed_origins": [BrowserIntegrationIdentity.origin]]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            let hosts = support.appendingPathComponent(browser.profile + "/NativeMessagingHosts")
            try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
            try data.write(to: hosts.appendingPathComponent(BrowserIntegrationIdentity.hostName + ".json"), options: .atomic)
        return folder
    }
}
