import AppKit

@MainActor
final class SelectionServiceDelegate: NSObject, NSApplicationDelegate {
    private var receiver: ((ExternalCaptureRequest) -> Void)?
    private var queued: [ExternalCaptureRequest] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
    func configure(receiver: @escaping (ExternalCaptureRequest) -> Void) {
        self.receiver = receiver
        let pending = queued; queued.removeAll()
        for request in pending { receiver(request) }
    }
    func receive(_ request: ExternalCaptureRequest) {
        if let receiver { receiver(request) }
        else {
            // Cold launches can deliver a service request before SwiftUI creates its window.
            queued = Array((queued + [request]).suffix(8))
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do { receive(try ExternalCaptureRequest(url: url)) }
            catch { showError(error.localizedDescription) }
        }
    }
    @objc func addSelectedWord(_ pasteboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do {
            guard let text = pasteboard.string(forType: .string) else { throw CaptureInputError.invalidSelection }
            let source = NSWorkspace.shared.frontmostApplication?.localizedName
            receive(try ExternalCaptureRequest(text: text, source: source))
        } catch let failure { error.pointee = failure.localizedDescription as NSString }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Could not add selection"
        alert.informativeText = message; alert.addButton(withTitle: "OK")
        NSApp.activate(); alert.runModal()
    }
}
