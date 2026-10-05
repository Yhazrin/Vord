import SwiftUI

/// Shared bridge between a speaking passage and the existing vocabulary repository.
struct SpeakingVocabularyView: View {
    var material: SpeakingMaterial
    var entries: [VocabularyEntry]
    @EnvironmentObject private var dependencies: AppDependencies
    var onAdded: () -> Void
    @State private var busy: String?
    @State private var error: String?
    @State private var selectedEntry: VocabularyEntry?

    var body: some View {
        let keywords = SpeakingConnections.keywords(material, entries: entries)
        if !keywords.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Words & phrases").font(AppTypography.headline).padding(.bottom, 8)
                ForEach(keywords) { keyword in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(keyword.english).font(AppTypography.ui(size: 15, weight: .medium))
                            if !keyword.chinese.isEmpty {
                                Text(keyword.chinese).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        Spacer(minLength: 8)
                        if let entry = entries.first(where: { SpeakingConnections.normalized($0.english) == keyword.id }) {
                            SubtleButton(title: "In vocabulary") { selectedEntry = entry }
                        } else {
                            SubtleButton(title: busy == keyword.id ? "Adding…" : "Add to vocabulary") { add(keyword) }
                                .disabled(busy != nil)
                        }
                    }.padding(.vertical, 8)
                    Hairline()
                }
                if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.destructive).padding(.top, 8) }
            }
            .sheet(item: $selectedEntry) { entry in
                WordDetailView(entryID: entry.id) { selectedEntry = nil }.frame(width: 850, height: 620)
            }
        }
    }
    private func add(_ keyword: SpeakingKeyword) {
        guard busy == nil else { return }
        busy = keyword.id; error = nil
        Task {
            defer { busy = nil }
            do {
                let added = try await dependencies.repository.insertIfAbsent(EntryDraft(english: keyword.english, chinese: keyword.chinese,
                    exampleSentence: material.english, sourceSentence: material.prompt, source: material.source,
                    tags: ["Speaking", material.topic]), now: Date())
                if added == nil, let existing = try await dependencies.repository.libraryRows().first(where: {
                    SpeakingConnections.normalized($0.english) == keyword.id
                }), existing.archived {
                    throw AIError.configuration("This expression is archived. Restore it in Library.")
                }
                onAdded()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct SpeakingNextSteps: View {
    var materials: [SpeakingMaterial]
    var entries: [VocabularyEntry]
    var title = "Use these words"
    var onPractise: (SpeakingMaterial) -> Void
    var body: some View {
        if !materials.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(AppTypography.headline)
                ForEach(materials) { material in
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(material.prompt.isEmpty ? material.title : material.prompt)
                                .font(AppTypography.body).fixedSize(horizontal: false, vertical: true)
                            Text(SpeakingConnections.linkedEntries(material, entries: entries).map(\.english).joined(separator: " · "))
                                .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer(minLength: 8)
                        QuietButton(title: "Speak") { onPractise(material) }
                    }.padding(.vertical, 6)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
