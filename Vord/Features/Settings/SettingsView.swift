import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var seeding = false
    @State private var dataMessage: String?
    @State private var dictionaryCount = 0
    @State private var importing = false
    @State private var browserTarget = BrowserIntegrationTarget.chrome
    @State private var category = SettingsCategory.general
    @Environment(\.vordLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Settings")
            Hairline()
            if layout.usesColumns {
                HStack(alignment: .top, spacing: 28) {
                    categories.frame(width: 148)
                    ScrollView { settingsContent.padding(.trailing, 6) }
                }
            } else {
                MenuSelect(name: "Settings section", selection: $category, choices: SettingsCategory.allCases, label: { $0.rawValue })
                ScrollView { settingsContent }
            }
        }
        .frame(maxWidth: AppSpacing.measure, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, layout.pagePadding).padding(.top, 32).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            dictionaryCount = dependencies.dictionary.count
            dataMessage = dependencies.dictionary.loadWarning ?? dependencies.history.warning
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsCategory.allCases) { item in
                Button { category = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(AppTypography.ui(size: 13)).frame(width: 18)
                        Text(item.rawValue).font(AppTypography.ui(size: 13, weight: category == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(height: 38)
                        .foregroundStyle(category == item ? AppColors.primaryText : AppColors.secondaryText)
                        .background(category == item ? AppColors.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityAddTraits(category == item ? [.isSelected] : [])
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch category {
            case .general:
                settingsGroup(title: "General") {
                    ControlRow(title: "Launch at login") {
                        Toggle("Launch at login", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                            .onChange(of: launchAtLogin) { _, enabled in updateLogin(enabled) }
                    }
                    RowDivider()
                    ControlRow(title: "Quick Add shortcut") {
                        MenuSelect(name: "Shortcut", selection: shortcutBinding, choices: QuickAddShortcut.all.map(\.id), label: { QuickAddShortcut.from(id: $0).title })
                    }
                }
                if let warning = settings.loginWarning ?? settings.hotKeyWarning { notice(warning) }
                #if DEBUG
                settingsGroup(title: "Developer") {
                    ControlRow(title: "Sample words") {
                        QuietButton(title: seeding ? "Loading…" : "Load sample words") { Task { await loadSamples() } }.disabled(seeding)
                    }
                }
                #endif
            case .appearance:
                settingsGroup(title: "Appearance") {
                    ControlRow(title: "Color scheme") { Text("Follows macOS").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText) }
                    RowDivider()
                    NavigationIconSettings(settings: settings)
                    RowDivider()
                    ControlRow(title: "Subtle wood grain") {
                        Toggle("Subtle wood grain", isOn: Binding(get: { settings.woodGrainEnabled }, set: { settings.setWoodGrainEnabled($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                ContentSurfaceBackground(woodGrain: settings.woodGrainEnabled)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .center) { Text("Aa").font(AppTypography.ui(size: 28)).foregroundStyle(AppColors.primaryText) }
                    .accessibilityLabel("Content background preview")
            case .learning:
                settingsGroup(title: "Review") {
                    ControlRow(title: "Review direction") {
                        MenuSelect(name: "Direction", selection: modeBinding, choices: ReviewMode.allCases, label: { $0.title })
                    }
                }
            case .capture:
                settingsGroup(title: "Quick capture") { QuickCaptureSettingsSection(settings: settings) }
                settingsGroup(title: "Selection & browser") {
                    ControlRow(title: "macOS Services", detail: "Selected text → Services → 快速添加到 Vord") {
                        QuietButton(title: "Service settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!) }
                    }
                    RowDivider()
                    ControlRow(title: "Browser extension") {
                        MenuSelect(name: "Browser", selection: $browserTarget, choices: BrowserIntegrationTarget.allCases, label: { $0.title })
                        QuietButton(title: "Set up") {
                            do {
                                let folder = try BrowserIntegrationSetup.install(browser: browserTarget)
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                                dataMessage = "Extensions → Developer mode → Load unpacked → select the BrowserExtension folder."
                            } catch { dataMessage = error.localizedDescription }
                        }
                    }
                }
            case .dictionary:
                settingsGroup(title: "Dictionary") {
                    ControlRow(title: "Offline entries", detail: "\(dependencies.dictionary.bundledCount.formatted()) built-in · \(dictionaryCount.formatted()) imported") {
                        QuietButton(title: importing ? "Importing…" : "Import JSON") { importDictionary() }.disabled(importing)
                    }
                    RowDivider()
                    ControlRow(title: "Translation fallback") {
                        MenuSelect(name: "Translation", selection: providerBinding, choices: settings.providerOptions.map(\.id), label: providerName)
                    }
                }
                Text("Imported dictionary entries replace matching definitions. Apple Translation may require a language download.")
                    .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
            case .ai:
                AIProviderSettings()
            case .data:
                SyncSettingsSection(model: dependencies.sync)
                settingsGroup(title: "Library backup") {
                    ControlRow(title: "Export library", detail: "Words and review history") {
                        QuietButton(title: "Export JSON") { Task { await exportLibrary() } }
                    }
                    RowDivider()
                    ControlRow(title: "Restore backup", detail: "Existing words are kept.") {
                        QuietButton(title: "Import JSON") { importLibrary() }.disabled(importing)
                    }
                }
            case .about:
                AboutSoftwareView()
            }
            if let dataMessage { notice(dataMessage) }
        }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.bottom, 20)
    }

    private func providerName(_ id: String) -> String {
        settings.providerOptions.first { $0.id == id }?.name ?? id
    }

    private var modeBinding: Binding<ReviewMode> {
        Binding(
            get: { settings.reviewMode },
            set: { settings.setReviewMode($0) }
        )
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { settings.translationProviderID },
            set: { settings.setTranslationProvider($0) }
        )
    }

    private var shortcutBinding: Binding<String> {
        Binding(
            get: { settings.shortcut.id },
            set: { newID in
                let shortcut = QuickAddShortcut.from(id: newID)
                settings.setShortcut(shortcut)
                dependencies.quickAdd.applyShortcut(shortcut)
            }
        )
    }

    private func settingsGroup<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, detail: detail)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, AppSpacing.sm)
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.loginWarning = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settings.loginWarning = "Launch at login could not be changed. \(error.localizedDescription)"
        }
    }

    private func exportLibrary() async {
        do {
            let snapshot = try await dependencies.repository.exportSnapshot()
            let data = try LibraryExporter.data(from: snapshot)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "vocabulary.json"
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic); dataMessage = "Library exported." }
                catch { dataMessage = error.localizedDescription }
            }
        } catch {
            dataMessage = error.localizedDescription
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importing = true
            Task {
                defer { importing = false }
                do {
                    let store = dependencies.dictionary
                    let count = try await Task.detached { try store.importData(Data(contentsOf: url)) }.value
                    dependencies.translation.invalidateCache()
                    dictionaryCount = store.count
                    dataMessage = "Imported \(count) dictionary entries."
                } catch { dataMessage = error.localizedDescription }
            }
        }
    }
    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importing = true
            Task {
                defer { importing = false }
                do {
                    let snapshot = try await Task.detached { try LibraryExporter.decode(Data(contentsOf: url)) }.value
                    let count = try await dependencies.repository.importSnapshot(snapshot)
                    dataMessage = "Imported \(count) words. Existing words were kept."
                } catch { dataMessage = error.localizedDescription }
            }
        }
    }

    private func loadSamples() async {
        seeding = true
        defer { seeding = false }
        do { try await SampleSeeder.load(into: dependencies.repository) }
        catch { dataMessage = error.localizedDescription }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", learning = "Learning", capture = "Capture", dictionary = "Dictionary", ai = "AI services", data = "Sync & backup", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .learning: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .capture: return "circle.dotted"
        case .dictionary: return "book.closed"
        case .ai: return "bubble.left.and.bubble.right"
        case .data: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}
