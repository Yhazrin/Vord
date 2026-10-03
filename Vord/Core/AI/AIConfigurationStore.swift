import Foundation

@MainActor
final class AIConfigurationStore: ObservableObject {
    @Published private(set) var providers: [AIProviderDescriptor] = []
    @Published private(set) var selectedID: UUID?
    @Published var notice: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "ai.providers") {
            do { providers = try JSONDecoder().decode([AIProviderDescriptor].self, from: data) }
            catch { notice = "Saved AI configurations could not be read. \(error.localizedDescription)" }
        }
        selectedID = defaults.string(forKey: "ai.selected").flatMap(UUID.init(uuidString:))
    }
    var selected: AIProviderDescriptor? { providers.first { $0.id == selectedID } }
    func select(_ id: UUID) {
        selectedID = id
        defaults.set(id.uuidString, forKey: "ai.selected")
    }
    func save(_ descriptor: AIProviderDescriptor, key: String) throws {
        guard !descriptor.name.trimmed.isEmpty, !descriptor.modelID.trimmed.isEmpty else {
            throw AIError.configuration("Provider name and model ID are required.")
        }
        _ = try HTTPAIProvider.endpoint(descriptor, model: descriptor.modelID)
        // Update only after validation; blank means keep the existing key.
        if !key.trimmed.isEmpty { try KeychainStore.set(account: descriptor.keychainAccount, secret: key.trimmed) }
        var next = providers
        if let index = next.firstIndex(where: { $0.id == descriptor.id }) { next[index] = descriptor }
        else { next.append(descriptor) }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "ai.providers")
        providers = next
        if selected == nil { select(descriptor.id) }
    }
    func remove(_ descriptor: AIProviderDescriptor) throws {
        let next = providers.filter { $0.id != descriptor.id }
        let data = try JSONEncoder().encode(next)
        try KeychainStore.delete(account: descriptor.keychainAccount)
        defaults.set(data, forKey: "ai.providers")
        providers = next
        if selectedID == descriptor.id {
            selectedID = next.first?.id
            defaults.set(selectedID?.uuidString, forKey: "ai.selected")
        }
    }
    func generate(prompt: String, system: String?) async throws -> AITextResponse {
        guard let descriptor = selected else { throw AIError.noProvider }
        return try await HTTPAIProvider(descriptor: descriptor).generate(
            request: .init(modelID: descriptor.modelID, prompt: prompt, system: system)
        )
    }
}
