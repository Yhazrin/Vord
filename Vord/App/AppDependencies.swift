import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    static var isTestHost: Bool { NSClassFromString("XCTestCase") != nil }
    let repository: any VocabularyRepository
    let translation: TranslationService
    let scheduler: any ReviewScheduling
    let appleBridge: AppleTranslationBridge
    let aiRegistry: AIProviderRegistry
    let ai: AIConfigurationStore
    let history: LearningHistory
    let dictionary: DictionaryStore
    let dictation = DictationModel()
    private var currentReview: ReviewViewModel?
    let settings: AppSettings
    let quickAdd: QuickAddController
    let selectionMonitor = InAppSelectionMonitor()
    let sync: SyncCoordinator
    let warning: String?
    let updates = ReleaseUpdateChecker()
    var requestedTab: AppTab = .today
    var revealMainWindow: (() -> Void)?
    var openImportOnNextVisit = false
    lazy var agent = LearningAgent(repository: repository, scheduler: scheduler, dictionary: dictionary,
        providerName: { [weak self] in self?.ai.selected?.name ?? "AI" },
        practice: { [weak self] in self?.history.practice ?? [] },
        dailyPracticeGoal: { [weak self] in self?.settings.dailyPracticeGoal ?? 10 },
        generate: { [weak self] prompt, system in
            guard let self else { throw CancellationError() }
            return try await self.ai.generate(prompt: prompt, system: system)
        })
    func startPlanReview(entryIDs: [UUID]) {
        currentReview = ReviewViewModel(repository: repository, scheduler: scheduler, mode: .mixed, plannedEntryIDs: entryIDs)
    }

    func openVocabularyImport() {
        openImportOnNextVisit = true; requestedTab = .agent
        NotificationCenter.default.post(name: .vordNavigate, object: AppTab.agent)
        NotificationCenter.default.post(name: .vordOpenAgentImport, object: nil)
    }

    init() {
        let bridge = AppleTranslationBridge()
        let translation = TranslationService(selectedID: "apple")
        translation.register(AppleTranslationProvider(bridge: bridge))
        let dictionary = DictionaryStore()
        translation.register(LocalDictionaryProvider(store: dictionary))
        let settings = AppSettings(translation: translation)
        let registry = AIProviderRegistry()
        let opened = Self.openDatabase()
        let repository = SQLiteVocabularyRepository(database: opened.database)
        self.repository = repository
        self.sync = SyncCoordinator(database: opened.database)
        self.translation = translation
        self.scheduler = SimpleScheduler()
        self.appleBridge = bridge
        self.aiRegistry = registry
        self.ai = AIConfigurationStore()
        self.history = LearningHistory()
        self.dictionary = dictionary
        self.settings = settings
        self.quickAdd = QuickAddController(repository: repository, translation: translation, settings: settings)
        self.warning = opened.warning
        _ = registry.registeredIDs
    }

    func reviewModel() -> ReviewViewModel {
        if let currentReview, !currentReview.isEmpty { return currentReview }
        let next = ReviewViewModel(repository: repository, scheduler: scheduler, mode: settings.reviewMode)
        currentReview = next
        return next
    }

    private static func openDatabase() -> (database: AppDatabase, warning: String?) {
        do {
            let url = try databaseURL()
            return (try AppDatabase(path: url.path), nil)
        } catch {
            let memory = (try? AppDatabase(path: ":memory:")) ?? {
                preconditionFailure("Unable to open a database")
            }()
            return (memory, "The library could not be opened on disk, so this session is temporary. \(error.localizedDescription)")
        }
    }

    private static func databaseURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["VORD_DB_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Vord", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("library.sqlite")
    }
}
