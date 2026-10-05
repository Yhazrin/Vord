import SwiftUI

struct QuickCaptureSettingsSection: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlRow(title: "Floating glass orb", detail: "Drag to either edge. Click to add a word.") {
                Toggle("Floating glass orb", isOn: Binding(get: { settings.floatingQuickAddEnabled },
                    set: settings.setFloatingQuickAddEnabled)).toggleStyle(.switch).labelsHidden()
            }
            RowDivider()
            ControlRow(title: "Suggest copied words", detail: "Show offline meanings for newly copied English words. Click Add to save.") {
                Toggle("Suggest copied words", isOn: Binding(get: { settings.clipboardCaptureEnabled },
                    set: settings.setClipboardCaptureEnabled)).toggleStyle(.switch).labelsHidden()
            }
        }
    }
}
