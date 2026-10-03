import AppKit
import SwiftUI

struct AboutSoftwareView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vord").font(AppTypography.ui(size: 28, weight: .semibold))
                    Text("Version \(version) (\(build))").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    Text("A personal vocabulary notebook.").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                }
            }
            Hairline()
            VStack(alignment: .leading, spacing: 0) {
                ControlRow(title: "Platform") { Text("macOS").font(AppTypography.caption) }
                RowDivider()
                ControlRow(title: "Dictionary") {
                    Link("ECDICT · MIT license", destination: URL(string: "https://github.com/skywind3000/ECDICT")!).font(AppTypography.caption)
                }
                RowDivider()
                ControlRow(title: "App information") {
                    QuietButton(title: "About Vord") { NSApp.orderFrontStandardAboutPanel(options: [:]) }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 4)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
            AppUpdateSettings(checker: dependencies.updates)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppUpdateSettings: View {
    @ObservedObject var checker: ReleaseUpdateChecker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Updates")
            VStack(alignment: .leading, spacing: 0) {
                ControlRow(title: "Check automatically", detail: "Once a day, through GitHub Releases.") {
                    Toggle("Check automatically", isOn: $checker.automatic).toggleStyle(.switch).labelsHidden()
                }
                RowDivider()
                ControlRow(title: "New versions", detail: checker.message) {
                    QuietButton(title: checker.checking ? "Checking…" : "Check for updates") { Task { await checker.check() } }.disabled(checker.checking)
                }
                if let url = checker.downloadURL {
                    ControlRow(title: "Download update") {
                        PrimaryButton(title: "Download") { NSWorkspace.shared.open(url) }
                    }
                }
                RowDivider()
                ControlRow(title: "Release history") {
                    Link("GitHub Releases", destination: ReleaseUpdateChecker.releasesURL).font(AppTypography.caption)
                }
            }.padding(.horizontal, 20).padding(.vertical, 4)
                .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
