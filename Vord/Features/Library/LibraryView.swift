import SwiftUI

enum LibraryScope: String, CaseIterable, Identifiable {
    case active = "All words", due = "Due now", pending = "Needs meaning", archived = "Archived"
    var id: String { rawValue }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var rows: [LibraryRow] = []
    @Published var visible: [LibraryRow] = []
    @Published var entries: [UUID: VocabularyEntry] = [:]
    @Published var search = ""
    @Published var sort: LibrarySort = .added
    @Published var error: String?
    @Published var scope: LibraryScope = .active
    @Published var tag = "All tags"
    func load(_ repository: any VocabularyRepository) async {
        do {
            async let loadedRows = repository.libraryRows()
            async let snapshot = repository.exportSnapshot()
            let (rows, library) = try await (loadedRows, snapshot)
            self.rows = rows
            entries = Dictionary(uniqueKeysWithValues: library.entries.map { ($0.id, $0) })
            applyVisible()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    var tags: [String] { ["All tags"] + Set(rows.flatMap(\.tags)).sorted() }
    func searchChanged() { applyVisible() }
    func sortChanged() { applyVisible() }
    private func applyVisible() {
        let scoped = rows.filter { row in
            guard tag == "All tags" || row.tags.contains(tag) else { return false }
            switch scope {
            case .active: return !row.archived
            case .due: return !row.archived && !row.english.trimmed.isEmpty && !row.chinese.trimmed.isEmpty && (row.nextDueAt ?? .distantFuture) <= Date()
            case .pending: return !row.archived && (row.english.trimmed.isEmpty || row.chinese.trimmed.isEmpty)
            case .archived: return row.archived
            }
        }
        let query = search.trimmed.lowercased()
        let matching = query.isEmpty ? scoped : scoped.filter { row in
            row.english.lowercased().contains(query)
                || row.chinese.lowercased().contains(query)
                || (row.lemma?.lowercased().contains(query) ?? false)
                || row.tags.contains { $0.lowercased().contains(query) }
                || (entries[row.id]?.chineseDefinition?.lowercased().contains(query) ?? false)
                || (entries[row.id]?.englishDefinition?.lowercased().contains(query) ?? false)
        }
        visible = LibraryQuery.apply(rows: matching, search: "", sort: sort)
    }

}

struct LibraryView: View {
    var onImport: (() -> Void)? = nil
    @Environment(\.vordLayout) private var layout
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var model = LibraryViewModel()
    @State private var selectedID: UUID?

    var body: some View {
        Group {
            if let selectedID {
                WordDetailView(entryID: selectedID) {
                    self.selectedID = nil
                    Task { await model.load(dependencies.repository) }
                }
                .modifier(MotionArrival()).id(selectedID)
            } else {
                list
            }
        }
        .task { await model.load(dependencies.repository) }
        .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in
            guard selectedID == nil else { return }
            Task { await model.load(dependencies.repository) }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let error = model.error {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(.top, AppSpacing.md)
            }
            if model.visible.isEmpty {
                EmptyLearningState(symbol: "books.vertical", title: model.rows.isEmpty ? "No words yet" : "No matching words",
                    detail: model.rows.isEmpty ? "Add a word to get started." : "Try another search or filter.")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, row in
                            LibraryEntryRow(row: row, entry: model.entries[row.id], usesColumns: layout.usesColumns) {
                                selectedID = row.id
                            }
                            if index < model.visible.count - 1 {
                                Hairline()
                                    .padding(.horizontal, AppSpacing.sm)
                            }
                        }
                    }
                    .padding(.bottom, AppSpacing.xl)
                }
                .contentMargins(.trailing, scrollLane, for: .scrollContent)
                .contentMargins(.trailing, 0, for: .scrollIndicators)
                .scrollIndicators(.automatic)
                .padding(.top, AppSpacing.xs)
            }
        }
        .frame(maxWidth: AppSpacing.library, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(PageInset(top: 20, bottom: AppSpacing.lg))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.md) {
                    scopeTabs
                    wordCount.fixedSize()
                    Spacer(minLength: AppSpacing.sm)
                    importButton
                }
                HStack(spacing: AppSpacing.sm) {
                    MenuSelect(name: "Collection", selection: $model.scope, choices: LibraryScope.allCases, label: { $0.rawValue })
                    wordCount
                    Spacer(minLength: 0)
                    importButton
                }
            }
            .onChange(of: model.scope) { _, _ in model.sortChanged() }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.sm) {
                    searchField.frame(minWidth: 220)
                    filterMenus
                }
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    searchField
                    filterMenus
                }
            }
            if !model.visible.isEmpty {
                HStack(spacing: AppSpacing.md) {
                    Text("Word").frame(width: layout.usesColumns ? 180 : 132, alignment: .leading)
                    Text("Meaning").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Review").frame(width: layout.usesColumns ? 98 : 78, alignment: .trailing)
                    if layout.usesColumns {
                        Text("Added").frame(width: 68, alignment: .trailing)
                    }
                }
                .font(AppTypography.ui(size: 11, weight: .medium))
                .foregroundStyle(AppColors.tertiaryText)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.trailing, scrollLane)
                .padding(.top, AppSpacing.xs)
                Hairline().padding(.trailing, scrollLane)
            }
        }
    }

    /// Reserved track so an overlay or always-on scroller never covers Added.
    private let scrollLane: CGFloat = 18

    private var wordCount: some View {
        Text(librarySubtitle)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.secondaryText)
            .lineLimit(1)
            .help(librarySubtitle)
    }

    @ViewBuilder private var importButton: some View {
        if let onImport {
            VordButton(title: "Import words", role: .secondary, action: onImport)
        }
    }

    private var scopeTabs: some View {
        ChoiceTabs(name: "Collection", selection: $model.scope, choices: LibraryScope.allCases, label: { $0.rawValue })
            .fixedSize(horizontal: true, vertical: false)
    }

    private var searchField: some View {
        FieldChrome {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypography.ui(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.tertiaryText)
                TextField(
                    "",
                    text: $model.search,
                    prompt: Text("Search").foregroundStyle(AppColors.tertiaryText)
                )
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.primaryText)
                .onChange(of: model.search) { _, _ in model.searchChanged() }
                if !model.search.isEmpty {
                    ChromeIconButton(symbol: "xmark", help: "Clear search") { model.search = "" }
                }
            }
        }
        .accessibilityLabel("Search words")
    }

    private var filterMenus: some View {
        HStack(spacing: AppSpacing.sm) {
            MenuSelect(name: "Tags", selection: $model.tag, choices: model.tags, label: { $0 })
                .onChange(of: model.tag) { _, _ in model.sortChanged() }
            MenuSelect(name: "Sort", selection: $model.sort, choices: LibrarySort.allCases, label: { $0.title })
                .onChange(of: model.sort) { _, _ in model.sortChanged() }
        }
    }

    private var librarySubtitle: String {
        let activeCount = model.rows.filter { !$0.archived }.count
        let archivedCount = model.rows.count - activeCount
        let count = model.scope == .archived ? archivedCount : activeCount
        let suffix = model.scope == .archived ? " archived" : ""
        let words = count == 1 ? "1 word\(suffix)" : "\(count) words\(suffix)"
        return !model.search.trimmed.isEmpty || model.tag != "All tags" || model.scope == .due || model.scope == .pending
            ? "\(model.visible.count) shown · \(words)" : words
    }
}

private struct LibraryEntryRow: View {
    var row: LibraryRow
    var entry: VocabularyEntry?
    var usesColumns: Bool
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                headword.frame(width: usesColumns ? 180 : 132, alignment: .leading)
                meaning.frame(maxWidth: .infinity, alignment: .leading)
                Text(statusText)
                    .font(AppTypography.ui(size: 12, weight: isDue ? .semibold : .regular))
                    .foregroundStyle(isDue ? AppColors.primaryText : AppColors.secondaryText)
                    .lineLimit(1)
                    .frame(width: usesColumns ? 98 : 78, alignment: .trailing)
                if usesColumns {
                    Text(AppFormat.day(row.createdAt))
                        .font(AppTypography.ui(size: 12))
                        .foregroundStyle(AppColors.tertiaryText)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .trailing)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
        .buttonStyle(LibraryRowButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .animation(reducedMotion ? nil : AppMotion.quick, value: hovering)
        .help(detailSummary)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open word details")
    }

    private var headword: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleText)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
            if let phonetic = entry?.phonetic?.trimmed.nilIfEmpty {
                Text(phonetic)
                    .font(AppTypography.ui(size: 11))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var meaning: some View {
        let definition = chineseMeaning ?? entry?.englishDefinition?.trimmed.nilIfEmpty
        return Text(definition?.replacingOccurrences(of: "\n", with: " ") ?? "—")
            .font(AppTypography.ui(size: 13))
            .foregroundStyle(definition == nil ? AppColors.tertiaryText : AppColors.primaryText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var detailSummary: String {
        ([titleText, entry?.phonetic, chineseMeaning, entry?.englishDefinition,
          row.tags.isEmpty ? nil : row.tags.joined(separator: " · "),
          "Review: \(statusText)", "Added \(AppFormat.dayYear(row.createdAt))"] as [String?])
            .compactMap { $0?.trimmed.nilIfEmpty }
            .joined(separator: "\n")
    }

    private var titleText: String {
        let english = row.english.trimmed
        return english.isEmpty ? row.chinese : english
    }

    private var chineseMeaning: String? {
        if let definition = entry?.chineseDefinition?.trimmed.nilIfEmpty { return definition }
        let meaning = row.chinese.trimmed
        return meaning.isEmpty || meaning == titleText ? nil : meaning
    }

    private var isDue: Bool {
        !row.archived && !row.english.trimmed.isEmpty && !row.chinese.trimmed.isEmpty
            && (row.nextDueAt ?? .distantFuture) <= Date()
    }

    private var statusText: String {
        if row.archived { return "Archived" }
        if row.english.trimmed.isEmpty || row.chinese.trimmed.isEmpty { return "No meaning" }
        if isDue { return "Due now" }
        if let due = row.nextDueAt { return AppFormat.day(due) }
        return "Not reviewed"
    }
}

private struct LibraryRowButtonStyle: ButtonStyle {
    var hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.selected : (hovering ? AppColors.hover : .clear))
            )
            .scaleEffect(reducedMotion ? 1 : configuration.isPressed ? 0.995 : 1)
            .animation(AppMotion.feedback(reducedMotion), value: configuration.isPressed)
    }
}

struct WordDetailView: View {
    @Environment(\.vordContentExpanded) private var contentExpanded
    @Environment(\.vordLayout) private var layout
    @EnvironmentObject private var dependencies: AppDependencies
    var entryID: UUID
    var onBack: () -> Void

    @State private var entry: VocabularyEntry?
    @State private var review: ReviewState?
    @State private var editing = false
    @State private var english = ""
    @State private var chinese = ""
    @State private var phonetic = ""
    @State private var partOfSpeech = ""
    @State private var englishDefinition = ""
    @State private var chineseDefinition = ""
    @State private var example = ""
    @State private var tags = ""
    @State private var confirmDelete = false
    @State private var translating = false
    @State private var systemDefinition: String?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton
                .padding(.top, contentExpanded ? AppSpacing.xl + 12 : AppSpacing.xl)
                .padding(.horizontal, layout.pagePadding)
                .padding(.bottom, AppSpacing.xl)

            GeometryReader { geometry in
                if geometry.size.width >= 820 {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            readingColumn
                                .padding(.leading, layout.pagePadding)
                                .padding(.trailing, AppSpacing.lg)
                                .padding(.bottom, AppSpacing.xxl)
                                .frame(maxWidth: AppSpacing.prose + layout.pagePadding, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { sidebar }
                            .frame(width: 252)
                            .background(AppColors.elevatedSurface.opacity(0.5))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            readingColumn.padding(.horizontal, layout.pagePadding)
                            Hairline().padding(.horizontal, layout.pagePadding)
                            sidebar
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .alert("Delete this word?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "chevron.left")
                    .font(AppTypography.ui(size: 10, weight: .semibold))
                Text("Library")
                    .font(AppTypography.tertiary)
            }
            .foregroundStyle(AppColors.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private var readingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                editor
            } else if let entry {
                reader(entry)
            }

            if let error {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(.top, AppSpacing.md)
            }
        }
    }

    private func reader(_ entry: VocabularyEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry.headword).font(AppTypography.word)
                Spacer()
                if !entry.english.isEmpty { SpeechButton(text: entry.english) }
            }
                .font(AppTypography.word)
                .foregroundStyle(AppColors.primaryText)
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            if hasSoundLine(entry) {
                soundLine(entry)
                    .padding(.top, AppSpacing.sm)
            }

            if !entry.gloss.isEmpty {
                Text(entry.gloss)
                    .font(AppTypography.reading)
                    .foregroundStyle(AppColors.primaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xl)
            }

            if let definition = entry.englishDefinition?.trimmed, !definition.isEmpty, definition != entry.gloss {
                Text(definition)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, entry.gloss.isEmpty ? AppSpacing.xl : AppSpacing.md)
            }

            if let example = entry.exampleSentence?.trimmed, !example.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Example")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.secondaryText)
                    DictionaryText(example, translation: dependencies.translation,
                        repository: dependencies.repository, lineSpacing: 5)
                }
                .padding(.top, AppSpacing.xxl)
            }
            if let systemDefinition, !systemDefinition.isEmpty {
                LearningCard {
                    SectionHeader(title: "macOS Dictionary", detail: "From dictionaries enabled on this Mac")
                    Text(systemDefinition).font(AppTypography.body).lineSpacing(4).textSelection(.enabled)
                }.padding(.top, 32)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: AppSpacing.prose, alignment: .leading)
    }

    private func hasSoundLine(_ entry: VocabularyEntry) -> Bool {
        !(entry.phonetic?.trimmed.isEmpty ?? true) || !(entry.partOfSpeech?.trimmed.isEmpty ?? true)
    }

    private func soundLine(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if let phonetic = entry.phonetic?.trimmed, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
            }
            if let phonetic = entry.phonetic?.trimmed, !phonetic.isEmpty,
               let part = entry.partOfSpeech?.trimmed, !part.isEmpty {
                Text("·")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.tertiaryText)
            }
            if let part = entry.partOfSpeech?.trimmed, !part.isEmpty {
                Text(part)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                metaBlock("Added", value: entry.map { AppFormat.dayYear($0.createdAt) } ?? "—")
                metaBlock("Source", value: sourceText)
                metaBlock("Tags", value: tagsText)
                reviewBlock
            }
            Spacer(minLength: AppSpacing.xl)
            actionBlock
        }
        .padding(.horizontal, layout.pagePadding)
        .padding(.bottom, AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sourceText: String {
        guard let entry else { return "—" }
        if let source = entry.source?.trimmed, !source.isEmpty { return source }
        return "Manual"
    }

    private var tagsText: String {
        guard let entry else { return "—" }
        return entry.tags.isEmpty ? "None" : entry.tags.joined(separator: " · ")
    }

    private func metaBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            metaLabel(label)
            Text(value)
                .font(AppTypography.metaValue)
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            metaLabel("Review")
            if let review {
                ForEach(ReviewDirection.allCases, id: \.self) { direction in
                    if let state = review.state(for: direction) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.shortDirection(direction))
                                .foregroundStyle(AppColors.secondaryText)
                            Spacer(minLength: AppSpacing.md)
                            Text(Self.reviewValue(state))
                                .foregroundStyle(AppColors.primaryText)
                        }
                        .font(AppTypography.caption)
                    }
                }
            } else {
                Text("—")
                    .font(AppTypography.metaValue)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }

    private func metaLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.metaLabel)
            .foregroundStyle(AppColors.secondaryText)
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            metaLabel("Actions")
                .padding(.bottom, AppSpacing.xs)
            if editing {
                VordButton(title: "Save", role: .primary, expands: true) { Task { await save() } }
                VordButton(title: "Cancel", role: .subtle, expands: true) { editing = false }
            } else {
                VordButton(title: "Edit", role: .primary, expands: true) {
                    if let entry { fill(entry) }
                    editing = true
                }
                VordButton(title: translating ? "Looking up…" : "Refresh Translation", role: .secondary, expands: true) { Task { await refreshTranslation() } }
                    .disabled(translating || saving)
                VordButton(title: entry?.archived == true ? "Restore to Library" : "Archive", role: .secondary, expands: true) { Task { await archive() } }
                VordButton(title: "Delete", role: .destructive, expands: true) { confirmDelete = true }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            LineField(title: "English", text: $english)
            LineField(title: "Chinese", text: $chinese)
            LineField(title: "Phonetic", text: $phonetic)
            LineField(title: "Part of speech", text: $partOfSpeech)
            LineField(title: "English definition", text: $englishDefinition)
            LineField(title: "Chinese definition", text: $chineseDefinition)
            LineField(title: "Example", text: $example)
            LineField(title: "Tags", text: $tags)
        }
        .frame(maxWidth: AppSpacing.prose, alignment: .leading)
    }

    private func load() async {
        do {
            entry = try await dependencies.repository.entry(id: entryID)
            review = try await dependencies.repository.reviewState(entryID: entryID)
            if let entry {
                fill(entry)
                let word = entry.english
                systemDefinition = await Task.detached { DictionaryStore.systemDefinition(word) }.value
            } else { error = "This word no longer exists." }
        } catch { self.error = error.localizedDescription }
    }

    private func fill(_ entry: VocabularyEntry) {
        english = entry.english
        chinese = entry.chinese
        phonetic = entry.phonetic ?? ""
        partOfSpeech = entry.partOfSpeech ?? ""
        englishDefinition = entry.englishDefinition ?? ""
        chineseDefinition = entry.chineseDefinition ?? ""
        example = entry.exampleSentence ?? ""
        tags = entry.tags.joined(separator: ", ")
    }

    private func save() async {
        guard var entry, !saving else { return }
        guard !english.trimmed.isEmpty || !chinese.trimmed.isEmpty else { error = "Enter a word or meaning."; return }
        saving = true
        defer { saving = false }
        entry.english = english.trimmed
        entry.chinese = chinese.trimmed
        entry.phonetic = phonetic.trimmed.nilIfEmpty
        entry.partOfSpeech = partOfSpeech.trimmed.nilIfEmpty
        entry.englishDefinition = englishDefinition.trimmed.nilIfEmpty
        entry.chineseDefinition = chineseDefinition.trimmed.nilIfEmpty
        entry.exampleSentence = example.trimmed.nilIfEmpty
        entry.lemma = entry.english.lowercased().nilIfEmpty
        entry.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        entry.updatedAt = Date()
        do {
            try await dependencies.repository.update(entry)
            self.entry = entry
            editing = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshTranslation() async {
        guard let entry, !translating else { return }
        translating = true; error = nil
        defer { translating = false }
        do {
            let result = try await dependencies.translation.translate(text: entry.english.isEmpty ? entry.chinese : entry.english)
            var draft = CaptureService.draft(from: result)
            draft.existingID = entry.id
            _ = try await dependencies.repository.upsert(draft, now: Date())
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func archive() async {
        do {
            try await dependencies.repository.setArchived(id: entryID, archived: !(entry?.archived ?? false), now: Date())
            onBack()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        do { try await dependencies.repository.delete(id: entryID); onBack() }
        catch { self.error = error.localizedDescription }
    }

    private static func shortDirection(_ direction: ReviewDirection) -> String {
        switch direction {
        case .englishToChinese: return "EN → ZH"
        case .chineseToEnglish: return "ZH → EN"
        }
    }

    private static func reviewValue(_ state: ReviewDirectionState, now: Date = Date()) -> String {
        if state.reviewCount == 0 {
            return "New"
        }
        if state.dueAt <= now {
            return "Due"
        }
        if Calendar.current.isDate(state.dueAt, inSameDayAs: now) { return state.dueAt.formatted(date: .omitted, time: .shortened) }
        return AppFormat.dayYear(state.dueAt)
    }
}
