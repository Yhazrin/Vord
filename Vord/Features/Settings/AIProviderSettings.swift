import SwiftUI

struct AIProviderSettings: View {
    @EnvironmentObject private var ai: AIConfigurationStore
    @State private var editing: AIProviderDescriptor?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "AI services", detail: "API keys are saved in macOS Keychain.")
                Spacer()
                QuietButton(title: "Add service") {
                    let id = UUID()
                    let preset = AIPreset.all[0]
                    editing = .init(id: id, name: preset.name, baseURL: preset.baseURL, modelID: preset.model,
                                    keychainAccount: "provider-\(id)", format: preset.format,
                                    timeout: preset.timeout, maxTokens: preset.maxTokens)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if ai.providers.isEmpty {
                    Text("No AI service connected.")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        .padding(.vertical, 16)
                }
                ForEach(Array(ai.providers.enumerated()), id: \.element.id) { index, provider in
                    HStack(spacing: 12) {
                        Button { ai.select(provider.id) } label: {
                            Image(systemName: ai.selectedID == provider.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(AppColors.accent)
                        }
                        .buttonStyle(.plain).help("Use \(provider.name)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name).font(AppTypography.headline)
                            Text("\(provider.format.title) · \(provider.modelID)")
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText).lineLimit(2)
                        }
                        Spacer()
                        SubtleButton(title: "Edit") { editing = provider }
                    }.padding(.vertical, 14)
                    if index < ai.providers.count - 1 { RowDivider() }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let message = error ?? ai.notice {
                Text(message).font(AppTypography.caption).foregroundStyle(AppColors.destructive)
            }
        }
        .sheet(item: $editing) { descriptor in
            AIProviderEditor(descriptor: descriptor)
                .environmentObject(ai)
        }
    }
}

private struct AIProviderEditor: View {
    @EnvironmentObject private var ai: AIConfigurationStore
    @Environment(\.dismiss) private var dismiss
    @State var descriptor: AIProviderDescriptor
    @State private var key = ""
    @State private var testing = false
    @State private var testSucceeded = false
    @State private var testTask: Task<Void, Never>?
    @State private var message: String?
    @State private var confirmRemoval = false
    @State private var presetChoice = "Choose preset"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "AI service")
            Group {
            HStack {
                Text("Preset").font(AppTypography.caption)
                Spacer()
                MenuSelect(name: "Preset", selection: $presetChoice,
                           choices: ["Choose preset"] + AIPreset.all.map(\.name), label: { $0 })
                    .onChange(of: presetChoice) { _, name in
                        guard let preset = AIPreset.all.first(where: { $0.name == name }) else { return }
                        descriptor.name = preset.name; descriptor.baseURL = preset.baseURL
                        descriptor.modelID = preset.model; descriptor.format = preset.format
                        descriptor.fullEndpoint = false
                        descriptor.timeout = preset.timeout; descriptor.maxTokens = preset.maxTokens
                    }
            }
            LineField(title: "Name", text: $descriptor.name)
            HStack {
                Text("API format").font(AppTypography.caption)
                Spacer()
                MenuSelect(name: "API format", selection: $descriptor.format,
                           choices: AIProtocol.allCases, label: { $0.title })
            }
            LineField(title: "Base URL (include /v1 or /v1beta where required)", text: $descriptor.baseURL)
            HStack(alignment: .bottom) {
                LineField(title: "Model ID", text: $descriptor.modelID)
                if HTTPAIProvider.isMiniMax(URL(string: descriptor.baseURL)) {
                    MenuSelect(name: "Model", selection: $descriptor.modelID,
                               choices: AIPreset.miniMaxModels, label: { $0 })
                        .padding(.bottom, 8)
                }
            }
            SecureField(descriptor.format == .ollama ? "API key (optional for local Ollama)" : "API key — leave blank to keep saved key", text: $key)
                .textFieldStyle(.roundedBorder)
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use this URL as the complete endpoint", isOn: $descriptor.fullEndpoint)
                    Stepper("Timeout: \(Int(descriptor.timeout))s", value: $descriptor.timeout, in: 10...180, step: 10)
                    Stepper("Output: \(descriptor.maxTokens) tokens", value: $descriptor.maxTokens, in: 512...8192, step: 512)
                    Text("Thinking counts toward the output limit.")
                        .foregroundStyle(AppColors.secondaryText)
                }.padding(.top, 10)
            }.font(AppTypography.caption)
            }.disabled(testing)
            if let message {
                Text(message).font(AppTypography.caption)
                    .foregroundStyle(testSucceeded ? AppColors.accent : AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if ai.providers.contains(where: { $0.id == descriptor.id }) {
                    VordButton(title: "Remove", role: .destructive) { confirmRemoval = true }
                }
                Spacer()
                SubtleButton(title: "Cancel") { dismiss() }
                QuietButton(title: testing ? "Testing…" : "Test Connection") { test() }
                    .disabled(testing)
                PrimaryButton(title: "Save") { save() }.disabled(testing)
            }
            Text("Requests send your text and relevant vocabulary or review data to this service.")
                .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
        }
        .padding(28).frame(width: 610)
        .background(AppColors.surface)
        .onDisappear { testTask?.cancel() }
        .onChange(of: descriptor) { _, _ in testSucceeded = false; message = nil }
        .onChange(of: key) { _, _ in testSucceeded = false; message = nil }
        .alert("Remove this AI provider and its saved key?", isPresented: $confirmRemoval) {
            Button("Remove", role: .destructive) {
                do { try ai.remove(descriptor); dismiss() }
                catch { message = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func save() {
        do { try ai.save(descriptor, key: key); key = ""; dismiss() }
        catch { testSucceeded = false; message = error.localizedDescription }
    }
    private func test() {
        testing = true; testSucceeded = false; message = nil
        let current = descriptor
        let suppliedKey = key
        testTask = Task {
            defer { testing = false }
            do {
                // A test must not persist unfinished settings or alter the active provider.
                let secret = suppliedKey.trimmed.isEmpty ? try KeychainStore.get(account: current.keychainAccount) ?? "" : suppliedKey.trimmed
                guard !secret.isEmpty || current.format == .ollama else { throw AIError.configuration("Enter an API key first.") }
                let provider = HTTPAIProvider(descriptor: current)
                let request = try provider.makeRequest(.init(modelID: current.modelID, prompt: "Reply with OK.", system: nil), key: secret)
                let started = Date()
                let response = try await provider.execute(request, model: current.modelID)
                testSucceeded = true
                message = "Connected to \(response.modelID) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s."
            } catch is CancellationError {} catch { message = error.localizedDescription }
        }
    }
}
