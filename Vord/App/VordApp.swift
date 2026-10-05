import SwiftUI

@main
struct VordApp: App {
    @NSApplicationDelegateAdaptor(SelectionServiceDelegate.self) private var selectionService
    @StateObject private var dependencies = AppDependencies()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Vord", id: "main") {
            RootView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.settings)
                .environmentObject(dependencies.ai)
                .environmentObject(dependencies.history)
                .onAppear {
                    selectionService.configure { request in dependencies.quickAdd.show(selection: request) }
                    dependencies.revealMainWindow = { openWindow(id: "main"); NSApp.activate() }
                    if !AppDependencies.isTestHost {
                        dependencies.selectionMonitor.start { text in
                            InAppSelection.present(text, using: dependencies.quickAdd)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Word") { navigate(.add) }.keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Button("Add Selection to Library") {
                    guard let text = InAppSelection.focusedSelection() else { return }
                    InAppSelection.present(text, using: dependencies.quickAdd)
                }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { navigate(.settings) }.keyboardShortcut(",")
            }
            CommandMenu("Study") {
                Button("Today") { navigate(.today) }.keyboardShortcut("1")
                Button("Library") { navigate(.library) }.keyboardShortcut("2")
                Button("Review") { navigate(.review) }.keyboardShortcut("3")
                Button("Dictation") { navigate(.dictation) }.keyboardShortcut("4")
                Button("Speaking") { navigate(.context) }.keyboardShortcut("5")
                Button("Study Companion") { navigate(.agent) }.keyboardShortcut("6")
            }
        }
    }
    private func navigate(_ tab: AppTab) {
        dependencies.requestedTab = tab
        openWindow(id: "main"); NSApp.activate()
        NotificationCenter.default.post(name: .vordNavigate, object: tab)
    }
}

extension Notification.Name {
    static let vordNavigate = Notification.Name("vord.navigate")
}
