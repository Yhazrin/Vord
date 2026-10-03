import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SyncSettingsSection: View {
    @ObservedObject var model: SyncCoordinator
    @State private var server = ""
    @State private var code = ""
    @State private var error: String?
    @State private var connecting = false
    var body: some View {
        SectionBlock(title: "Sync") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                LineField(title: "Server", text: $server)
                if !model.connected {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Sync code").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                        FieldChrome {
                            SecureField("Use the same code on your Android device", text: $code)
                                .textFieldStyle(.plain).font(AppTypography.body)
                        }
                    }
                    Text("Connecting merges this library with your other devices. Your AI keys and device settings stay here.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                }
                HStack(spacing: AppSpacing.sm) {
                    if model.connected {
                        PrimaryButton(title: model.syncing ? "Syncing…" : "Sync now") { Task { await model.syncNow() } }
                            .disabled(model.syncing)
                        SubtleButton(title: "Disconnect") { model.disconnect() }
                    } else {
                        PrimaryButton(title: connecting ? "Connecting…" : "Connect") {
                            connecting = true; error = nil
                            Task {
                                defer { connecting = false }
                                do { try await model.connect(code: code, server: server); code = "" }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(connecting || code.trimmed.isEmpty)
                    }
                    SubtleButton(title: "Import sync file") { importFile() }.disabled(connecting || model.syncing)
                }
                Text(error ?? model.message).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = model.lastSuccess, model.connected {
                    Text("Last synced " + date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                }
            }
        }
        .onAppear { server = model.endpoint }
        .onChange(of: model.endpoint) { _, value in server = value }
    }
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose the private sync file shared with your Android device."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        connecting = true; error = nil
        Task {
            defer { connecting = false }
            do { try await model.importPairing(url); code = "" }
            catch { self.error = error.localizedDescription }
        }
    }
}
