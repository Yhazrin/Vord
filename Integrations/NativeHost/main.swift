import Foundation
import AppKit

func reply(ok: Bool, error: String? = nil) -> Never {
    var response: [String: Any] = ["ok": ok]
    if let error { response["error"] = error }
    let data = try! JSONSerialization.data(withJSONObject: response)
    var length = UInt32(data.count).littleEndian
    FileHandle.standardOutput.write(Data(bytes: &length, count: 4))
    FileHandle.standardOutput.write(data)
    exit(ok ? 0 : 1)
}
func readExactly(_ length: Int) -> Data? {
    var result = Data()
    while result.count < length {
        guard let next = try? FileHandle.standardInput.read(upToCount: length - result.count), !next.isEmpty else { return nil }
        result.append(next)
    }
    return result
}
guard CommandLine.arguments.dropFirst().first == BrowserIntegrationIdentity.origin else {
    reply(ok: false, error: "This browser extension is not authorized for Vord.")
}
guard let header = readExactly(4) else { reply(ok: false, error: "Missing message header.") }
let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
guard length > 0, length <= 16_384, let data = readExactly(Int(length)),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = object["text"] as? String,
      object.keys.allSatisfy({ $0 == "text" || $0 == "source" }) else {
    reply(ok: false, error: "The selected text message is invalid or too large.")
}
let request: ExternalCaptureRequest
do { request = try ExternalCaptureRequest(text: text, source: object["source"] as? String) }
catch { reply(ok: false, error: error.localizedDescription) }
// The helper lives inside Vord.app; explicitly target its owner rather than another installed debug build.
let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
guard app.pathExtension == "app", FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/Vord").path) else {
    reply(ok: false, error: "The Vord browser helper must run from its application bundle.")
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
NSWorkspace.shared.open([request.url], withApplicationAt: app, configuration: configuration) { _, error in
    if error != nil { reply(ok: false, error: "Could not open Vord. Open the application once and retry.") }
    reply(ok: true)
}
Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in reply(ok: false, error: "Opening Vord timed out.") }
RunLoop.main.run()
