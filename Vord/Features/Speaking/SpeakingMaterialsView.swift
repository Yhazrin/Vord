import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContextWorkspaceView: View {
    @ObservedObject var library: SpeakingLibrary
    var onSettings: () -> Void
    @State private var section = "Materials"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Examples section", selection: $section) {
                Text("Materials").tag("Materials")
                Text("Generate examples").tag("Generate")
            }.pickerStyle(.segmented).frame(width: 310).padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 14)
            if section == "Materials" { SpeakingMaterialsView(library: library) }
            else { ContextView(onSettings: onSettings) }
        }
    }
}

private enum MaterialSheet: Identifiable {
    case edit(SpeakingMaterial), practice(SpeakingMaterial), importing
    var id: String {
        switch self {
        case .edit(let item): return "edit-\(item.id)"
        case .practice(let item): return "practice-\(item.id)"
        case .importing: return "import"
        }
    }
}

struct SpeakingMaterialsView: View {
    @ObservedObject var library: SpeakingLibrary
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.vordLayout) private var layout
    @State private var search = ""
    @State private var scope = "All materials"
    @State private var part = SpeakingMaterial.Part.any
    @State private var selectedID: UUID?
    @State private var sheet: MaterialSheet?
    @State private var error: String?
    private var filtered: [SpeakingMaterial] {
        let revisit = scope == "To revisit" ? library.revisitIDs : []
        let personalIDs = Set(library.personal.map(\.id))
        return library.materials.filter { item in
            (scope == "All materials" || (scope == "To revisit" ? revisit.contains(item.id)
                : (scope == "My materials" ? personalIDs.contains(item.id) : item.source.hasPrefix("Starter pack"))))
            && (part == .any || item.part == part || item.part == .any)
            && (search.trimmed.isEmpty || [item.title, item.english, item.chinese, item.topic, item.prompt].contains { $0.localizedCaseInsensitiveContains(search.trimmed) })
        }
    }
    private var selected: SpeakingMaterial? { library.materials.first { $0.id == selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { searchField; filters; actions }
                VStack(alignment: .leading, spacing: 10) { searchField; HStack { filters; Spacer(); actions } }
            }
            if let warning = library.warning { Text(warning).foregroundStyle(AppColors.destructive) }
            if let error { Text(error).foregroundStyle(AppColors.destructive) }
            if layout.usesColumns {
                HStack(alignment: .top, spacing: 24) {
                    materialList.frame(width: 310)
                    Rectangle().fill(AppColors.subtleBorder).frame(width: 1)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                materialList.frame(maxHeight: selected == nil ? .infinity : 220)
                if selected != nil { Hairline(); detail }
            }
        }
        .font(AppTypography.caption).padding(.horizontal, 28).padding(.bottom, 24)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .edit(let item): MaterialEditor(library: library, material: item)
            case .practice(let item): SpeakingPracticeView(library: library, material: item)
            case .importing: MaterialImportView(library: library)
            }
        }
        .onChange(of: search) { _, _ in reconcileSelection() }
        .onChange(of: scope) { _, _ in reconcileSelection() }
        .onChange(of: part) { _, _ in reconcileSelection() }
        .onChange(of: library.attempts.count) { _, _ in reconcileSelection() }
        .onChange(of: library.personal) { _, _ in reconcileSelection() }
    }
    private var searchField: some View {
        TextField("Search materials", text: $search).textFieldStyle(.roundedBorder).frame(minWidth: 130)
    }
    private var filters: some View {
        HStack {
            MenuSelect(name: "Collection", selection: $scope, choices: ["All materials", "My materials", "To revisit", "Starter pack"], label: { $0 })
            MenuSelect(name: "Speaking part", selection: $part, choices: SpeakingMaterial.Part.allCases, label: { $0.rawValue })
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            SubtleButton(title: "Export") { export() }.help("Includes materials and original source documents")
            QuietButton(title: "Import") { sheet = .importing }
            PrimaryButton(title: "Add") { sheet = .edit(SpeakingMaterial(title: "", english: "")) }
        }
    }
    private var materialList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filtered.isEmpty {
                    Text("No matching materials").foregroundStyle(AppColors.secondaryText).padding(.vertical, 20)
                }
                ForEach(filtered) { item in
                    Button { selectedID = item.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(AppTypography.headline).lineLimit(1)
                            HStack {
                                Text(item.topic).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(item.part == .any ? item.kind.rawValue.capitalized : item.part.rawValue)
                            }.font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedID == item.id ? AppColors.inputSurface : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.trailing, 8)
        }
    }
    @ViewBuilder private var detail: some View {
        if let item = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(item.title).font(AppTypography.ui(size: 23, weight: .semibold))
                        Spacer()
                        SubtleButton(title: "Edit") { sheet = .edit(item) }
                        PrimaryButton(title: "Practise") { sheet = .practice(item) }
                    }
                    if !item.prompt.isEmpty { Text(item.prompt).font(AppTypography.headline).textSelection(.enabled) }
                    DictionaryText(item.english, translation: dependencies.translation, repository: dependencies.repository, fontSize: 21, lineSpacing: 5)
                    SpeechButton(text: item.english)
                    if !item.chinese.isEmpty { Text(item.chinese).font(AppTypography.body).foregroundStyle(AppColors.secondaryText).textSelection(.enabled) }
                    if !item.notes.isEmpty { Hairline(); Text(item.notes).font(AppTypography.body).textSelection(.enabled) }
                    HStack {
                        Text(item.source).font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                        Spacer()
                        SubtleButton(title: "Discuss") { discuss(item) }
                    }
                    if let document = library.documents.first(where: { $0.id == item.sourceDocumentID }) {
                        DisclosureGroup("Original notes") {
                            Text(document.text).font(AppTypography.caption).textSelection(.enabled).padding(.top, 8)
                        }
                    }
                    if let excerpt = item.sourceExcerpt {
                        DisclosureGroup("Source excerpt") { Text(excerpt).textSelection(.enabled).padding(.top, 8) }
                    }
                    let attempts = library.attempts.filter { $0.materialID == item.id }
                    if !attempts.isEmpty {
                        Hairline()
                        Text("\(attempts.count) practices · self-reported").foregroundStyle(AppColors.secondaryText)
                        ForEach(Array(attempts.suffix(3).reversed())) { attempt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(attempt.outcome == .revisit ? "To revisit" : "Recalled") · \(attempt.seconds)s\(attempt.referenceRevealed ? " · Reference viewed" : "")")
                                if !attempt.answer.isEmpty { Text(attempt.answer).foregroundStyle(AppColors.secondaryText).textSelection(.enabled) }
                            }
                        }
                    }
                }.padding(.trailing, 10)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(filtered.count) materials").font(AppTypography.ui(size: 24))
                Text("Choose one to read or practise.").foregroundStyle(AppColors.secondaryText)
            }.padding(.top, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    private func reconcileSelection() {
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }
    private func discuss(_ item: SpeakingMaterial) {
        dependencies.agent.appendToDraft("请围绕这份口语素材问我一个问题，等我回答后指出最值得改的一处表达，并让我换一个场景再说一次。\n问题：\(item.prompt)\n参考：\(item.english)\n使用提示：\(item.notes)")
        NotificationCenter.default.post(name: .vordNavigate, object: AppTab.agent)
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "speaking-materials.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try library.exportData().write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct MaterialEditor: View {
    @ObservedObject var library: SpeakingLibrary
    @State var material: SpeakingMaterial
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Material").font(AppTypography.ui(size: 24, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LineField(title: "Title", text: $material.title)
                    HStack {
                        MenuSelect(name: "Kind", selection: $material.kind, choices: SpeakingMaterial.Kind.allCases, label: { $0.rawValue.capitalized })
                        MenuSelect(name: "Part", selection: $material.part, choices: SpeakingMaterial.Part.allCases, label: { $0.rawValue })
                        TextField("Topic", text: $material.topic).textFieldStyle(.roundedBorder)
                    }
                    LineField(title: "Question or situation", text: $material.prompt)
                    Text("English").font(AppTypography.caption)
                    TextEditor(text: $material.english).frame(height: 140).font(AppTypography.body).accessibilityLabel("Material English")
                    LineField(title: "Chinese", text: $material.chinese, multiline: true)
                    LineField(title: "Usage or correction", text: $material.notes, multiline: true)
                    LineField(title: "Source", text: $material.source)
                }
            }
            if let error { Text(error).foregroundStyle(AppColors.destructive).font(AppTypography.caption) }
            HStack {
                Spacer(); SubtleButton(title: "Cancel") { dismiss() }
                PrimaryButton(title: "Save") {
                    do {
                        if library.materials.contains(where: { $0.id == material.id }) { try library.update(material) }
                        else { try library.add([material]) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(!material.isValid)
            }
        }.padding(28).frame(width: 620, height: 610).background(AppColors.contentBackground)
    }
}
