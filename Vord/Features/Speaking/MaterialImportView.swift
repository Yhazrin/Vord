import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MaterialImportView: View {
    @ObservedObject var library: SpeakingLibrary
    @EnvironmentObject private var ai: AIConfigurationStore
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var name = "Imported text"
    @State private var pack: SpeakingPack?
    @State private var selected = Set<UUID>()
    @State private var error: String?
    @State private var busy = false
    @State private var request: Task<Void, Never>?
    private var selectedItems: [SpeakingMaterial] { (pack?.materials ?? []).filter { selected.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Import materials").font(AppTypography.ui(size: 24, weight: .semibold))
                Spacer()
                SubtleButton(title: "Open file") { openFile() }.disabled(busy)
            }
            if let pack {
                HStack {
                    Text("\(pack.materials.count) materials · edit before saving").font(AppTypography.caption)
                    Spacer()
                    SubtleButton(title: "Back") { self.pack = nil; selected = [] }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(pack.materials.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top) {
                                Toggle("Select \(item.title)", isOn: Binding(get: { selected.contains(item.id) }, set: {
                                    if $0 { selected.insert(item.id) } else { selected.remove(item.id) }
                                })).labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("Title", text: field(index, \.title)).font(AppTypography.headline)
                                    TextField("English", text: field(index, \.english), axis: .vertical).lineLimit(2...6)
                                    TextField("Chinese", text: field(index, \.chinese), axis: .vertical).lineLimit(1...3)
                                    TextField("Question", text: field(index, \.prompt), axis: .vertical).lineLimit(1...3)
                                    TextField("Usage or correction", text: field(index, \.notes), axis: .vertical).lineLimit(1...4)
                                    HStack {
                                        MenuSelect(name: "Kind", selection: Binding(get: { self.pack?.materials[index].kind ?? .sentence }, set: { self.pack?.materials[index].kind = $0 }), choices: SpeakingMaterial.Kind.allCases, label: { $0.rawValue.capitalized })
                                        MenuSelect(name: "Part", selection: Binding(get: { self.pack?.materials[index].part ?? .any }, set: { self.pack?.materials[index].part = $0 }), choices: SpeakingMaterial.Part.allCases, label: { $0.rawValue })
                                        TextField("Topic", text: field(index, \.topic))
                                    }
                                    if !item.isValid { Text("Complete the title and English text.").foregroundStyle(AppColors.destructive) }
                                }.textFieldStyle(.plain)
                            }
                            Hairline()
                        }
                    }.padding(.trailing, 10)
                }
            } else {
                TextField("Source name", text: $name).textFieldStyle(.roundedBorder).disabled(busy)
                TextEditor(text: $source).font(AppTypography.body).frame(minHeight: 230).disabled(busy)
                    .accessibilityLabel("Speaking material source")
                Text("Separate English / Chinese blocks with a blank line, or analyse longer lesson notes.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                HStack {
                    QuietButton(title: "Preview text") {
                        do { prepare(try SpeakingImport.local(text: source, name: name)); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(busy || source.trimmed.isEmpty)
                    if busy { ProgressView().controlSize(.small); SubtleButton(title: "Stop") { request?.cancel() } }
                    else {
                        QuietButton(title: "Analyse with AI") { analyze() }.disabled(source.trimmed.isEmpty || ai.selected == nil)
                    }
                }
                Text("AI analysis sends this text to \(ai.selected?.name ?? "your selected provider").")
                    .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
            }
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive).textSelection(.enabled) }
            HStack {
                Spacer()
                SubtleButton(title: "Cancel") { request?.cancel(); dismiss() }
                if let pack {
                    PrimaryButton(title: "Save \(selected.count)") {
                        do { try library.add(selectedItems, documents: pack.documents); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(selectedItems.isEmpty || !selectedItems.allSatisfy(\.isValid))
                }
            }
        }.padding(28).frame(width: 680, height: 650).background(AppColors.contentBackground)
            .onDisappear { request?.cancel() }
    }
    private func field(_ index: Int, _ path: WritableKeyPath<SpeakingMaterial, String>) -> Binding<String> {
        Binding(get: { pack?.materials[index][keyPath: path] ?? "" }, set: { pack?.materials[index][keyPath: path] = $0 })
    }
    private func prepare(_ value: SpeakingPack) {
        pack = value; selected = Set(value.materials.map(\.id))
    }
    private func analyze() {
        guard !busy, source.count <= SpeakingImport.maxSourceCharacters else { error = "Use up to 60,000 characters."; return }
        let text = source, title = name
        busy = true; error = nil
        request = Task {
            defer { busy = false; request = nil }
            do {
                let value = try await SpeakingImport.analyze(text: text, name: title) { prompt, system in
                    try await ai.generate(prompt: prompt, system: system)
                }
                try Task.checkCancellation(); prepare(value)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func openFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .json, UTType(filenameExtension: "md") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4_000_000 else {
                    throw AIError.configuration("Choose a file under 4 MB.")
                }
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "json" { prepare(try SpeakingPack.decode(data)) }
                else {
                    guard let text = String(data: data, encoding: .utf8), text.count <= SpeakingImport.maxSourceCharacters else {
                        throw AIError.configuration("Use UTF-8 text with up to 60,000 characters.")
                    }
                    source = text; name = url.lastPathComponent; pack = nil; selected = []
                }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
