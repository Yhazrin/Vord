import Foundation

@MainActor
final class IslandQuizModel: ObservableObject {
    @Published private(set) var entry: VocabularyEntry?
    @Published private(set) var direction: ReviewDirection = .englishToChinese
    @Published var answer = ""
    @Published private(set) var revealed = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var recorded = false
    @Published private(set) var completed = 0
    @Published private(set) var error: String?
    private let repository: any VocabularyRepository
    private let scheduler: any ReviewScheduling
    private var recordedDirections = Set<ReviewDirection>()
    init(repository: any VocabularyRepository, scheduler: any ReviewScheduling) {
        self.repository = repository; self.scheduler = scheduler
    }
    var prompt: String { direction == .englishToChinese ? entry?.english ?? "" : entry?.gloss ?? "" }
    var solution: String { direction == .englishToChinese ? entry?.gloss ?? "" : entry?.english ?? "" }
    func next() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let profile = LearningProfile(snapshot: try await repository.exportSnapshot())
            let pool = profile.entries.filter { $0.id != entry?.id }
            let due = pool.filter { profile.dueDate($0.id) <= Date() }
            entry = (due.isEmpty ? pool : due).randomElement() ?? profile.entries.randomElement()
            answer = ""; revealed = false; recorded = false; recordedDirections = []
        } catch { self.error = error.localizedDescription }
    }
    func reveal() { guard entry != nil, !isSaving else { return }; revealed = true }
    func changeDirection(_ value: ReviewDirection) {
        guard !isSaving, !isLoading, direction != value else { return }
        direction = value; answer = ""; revealed = false
        recorded = recordedDirections.contains(value)
    }
    func record(_ rating: ReviewRating) async {
        guard let entry, revealed, !recorded, !isSaving else { return }
        isSaving = true; error = nil
        defer { isSaving = false }
        do {
            guard let latest = try await repository.entry(id: entry.id), !latest.archived,
                  let state = try await repository.reviewState(entryID: entry.id) else {
                throw AIError.configuration("This word has been removed or archived. Draw another word.")
            }
            guard latest.english == entry.english, latest.gloss == entry.gloss else {
                self.entry = latest; revealed = false; answer = ""
                throw AIError.configuration("This word changed on another device. Check it again before recording a review.")
            }
            try await repository.recordReview(scheduler.schedule(state: state, direction: direction, rating: rating, now: Date()))
            recordedDirections.insert(direction); recorded = true; completed += 1
        } catch { self.error = error.localizedDescription }
    }
}
