import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let vordOpenAgentImport = Notification.Name("vord.openAgentImport")
}

struct VocabularyImportSource: View {
    var onAnalyze: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Import words").font(AppTypography.title)
                Spacer()
                SubtleButton(title: "Open text file") { openFile() }
            }
            Text("Paste a word list or an English passage.")
                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            TextEditor(text: $text).font(AppTypography.body).scrollContentBackground(.hidden)
                .padding(12).background(AppColors.inputSurface, in: RoundedRectangle(cornerRadius: 12))
                .frame(minHeight: 240).accessibilityLabel("Words or passage to import")
            HStack {
                Text("\(text.count.formatted()) / 15,000").font(AppTypography.tertiary)
                    .foregroundStyle(text.count > 15000 ? AppColors.primaryText : AppColors.secondaryText)
                Spacer()
                SubtleButton(title: "Cancel") { dismiss() }
                PrimaryButton(title: "Find words") { onAnalyze(text.trimmed); dismiss() }
                    .disabled(text.trimmed.isEmpty || text.count > 15000)
            }
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText) }
        }.padding(28).frame(width: 600, height: 450)
            .background(AppColors.contentBackground)
    }
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, .commaSeparatedText, .json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64000 else { throw AIError.configuration("Choose a text file under 64 KB.") }
                let data = try Data(contentsOf: url)
                guard let value = String(data: data, encoding: .utf8), value.count <= 15000 else {
                    throw AIError.configuration("Use UTF-8 text with up to 15,000 characters.")
                }
                text = value; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct VocabularyImportPreview: View {
    @ObservedObject var agent: LearningAgent
    var messageID: UUID
    var proposal: VocabularyImport
    var compact = false
    private var busy: Bool { agent.importingMessageID != nil }
    private var buttonTitle: String {
        if busy { return "Adding…" }
        if proposal.pendingCount > 0 { return "Add \(proposal.pendingCount) words" }
        return proposal.addedCount > 0 ? "Added" : "Select words"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(proposal.items.count) words").font(AppTypography.headline)
                Spacer()
                if proposal.addedCount > 0 {
                    Text("\(proposal.addedCount) added").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(proposal.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("Select \(item.english)", isOn: Binding(get: { item.selected }, set: {
                                agent.editImport(messageID: messageID, itemID: item.id, selected: $0)
                            })).labelsHidden().toggleStyle(.checkbox)
                                .disabled(busy || item.status == .added || item.status == .existing)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    TextField("English word", text: Binding(get: { item.english }, set: {
                                        agent.editImport(messageID: messageID, itemID: item.id, english: $0)
                                    })).font(AppTypography.headline).textFieldStyle(.plain)
                                    if item.status == .added || item.status == .existing {
                                        Text(item.status == .added ? "Added" : "In library")
                                            .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                                    }
                                }
                                TextField("Chinese meaning", text: Binding(get: { item.chinese }, set: {
                                    agent.editImport(messageID: messageID, itemID: item.id, chinese: $0)
                                }), axis: .vertical).font(AppTypography.body).textFieldStyle(.plain)
                                if let definition = item.englishDefinition {
                                    Text(definition).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                                }
                                if let sentence = item.exampleSentence {
                                    Text(sentence).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                                }
                                if !item.isValid { Text("Enter an English word and a meaning.").font(AppTypography.tertiary) }
                                if let error = item.error { Text(error).font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText) }
                            }.disabled(busy || item.status == .added || item.status == .existing)
                        }
                        Hairline()
                    }
                }.padding(.trailing, 6)
            }.frame(height: min(compact ? 230 : 380, CGFloat(proposal.items.count) * 115))
            HStack {
                Text("Existing words are kept.").font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                Spacer()
                PrimaryButton(title: buttonTitle) {
                    Task { await agent.importWords(messageID: messageID) }
                }.disabled(busy || proposal.pendingCount == 0)
            }
        }.padding(14).background(AppColors.inputSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
