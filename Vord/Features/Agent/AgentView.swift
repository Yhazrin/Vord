import SwiftUI

struct AgentView: View {
    @ObservedObject var agent: LearningAgent
    var onStartPlan: ([UUID]) -> Void
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.vordLayout) private var layout
    @State private var section = "Conversation"
    @State private var showingImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack { header; Spacer(); importButton; sections.fixedSize() }
                VStack(alignment: .leading, spacing: 12) { header; HStack { sections; Spacer(); importButton } }
            }
            if let profile = agent.profile {
                HStack(spacing: 20) {
                    metric("Due words", profile.dueWords)
                    metric("Reviewed today", profile.reviewedToday)
                    metric("Words to revisit", profile.weakWords.count)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            if section == "Conversation" {
                AgentConversation(agent: agent)
            } else if section == "Plan" {
                ScrollView { AgentPlanView(agent: agent, onStart: onStartPlan, onDiscuss: { section = "Conversation" }) }
            } else {
                ScrollView { CompanionPractice(quiz: agent.quiz, agent: agent, onDiscuss: { section = "Conversation" }) }
            }
        }
        .frame(maxWidth: AppSpacing.measure, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, layout.pagePadding).padding(.top, 32).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await agent.refresh() }
        .onAppear {
            if dependencies.openImportOnNextVisit {
                dependencies.openImportOnNextVisit = false; section = "Conversation"; showingImport = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vordOpenAgentImport)) { _ in
            dependencies.openImportOnNextVisit = false; section = "Conversation"; showingImport = true
        }
        .sheet(isPresented: $showingImport) {
            VocabularyImportSource { source in
                section = "Conversation"
                agent.send("请把下面的英文词单或文章中的生词导入我的词库，提取词条并补充中英文释义：\n\n" + source)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in
            guard agent.importingMessageID == nil else { return }
            Task { await agent.refresh() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in Task { await agent.refresh() } }
    }
    private var importButton: some View {
        QuietButton(title: "Import words") { showingImport = true }
            .disabled(agent.isThinking || agent.importingMessageID != nil)
    }
    private var header: some View {
        PageHeader(title: "Companion", subtitle: dependencies.ai.selected.map { "\($0.name) · \($0.modelID)" } ?? "Choose an AI service in Settings for conversation.")
    }
    private var sections: some View {
        ChoiceTabs(
            name: "Companion section",
            selection: $section,
            choices: ["Conversation", "Plan", "Practice"],
            label: { $0 }
        )
    }
    private func metric(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count.formatted()).font(AppTypography.stat).monospacedDigit()
            Text(title).font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
        }
    }
}

/// Conversation and import actions share the same persisted agent.
struct AgentConversation: View {
    @ObservedObject var agent: LearningAgent
    var compact = false
    @State private var draft = ""
    @FocusState private var composing: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: compact ? 14 : 22) {
                        if agent.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("What shall we study?").font(compact ? AppTypography.headline : AppTypography.reading)
                                ForEach(["今天先复习哪些词？", "抽一个我容易忘的词考考我。", "帮我导入一份生词表。"], id: \.self) { question in
                                    Button { agent.send(question) } label: {
                                        Text(question).font(AppTypography.caption).multilineTextAlignment(.leading)
                                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(AppColors.inputSurface, in: RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(MotionPressStyle()).disabled(agent.isThinking)
                                }
                            }.padding(.vertical, 10)
                        }
                        ForEach(agent.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == .user ? "You" : "Companion").font(AppTypography.ui(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColors.secondaryText)
                                CompanionRichText(text: message.text, compact: compact)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if let proposal = message.wordImport {
                                    VocabularyImportPreview(agent: agent, messageID: message.id, proposal: proposal, compact: compact)
                                }
                            }.padding(message.role == .user ? 12 : 0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == .user ? AppColors.inputSurface : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .id(message.id)
                        }
                        if agent.isThinking { ProgressView("Thinking…").controlSize(.small).font(AppTypography.caption) }
                        Color.clear.frame(height: 1).id("conversation-end")
                    }.padding(.trailing, 6)
                }
                .onChange(of: agent.messages.count) { _, _ in
                    withAnimation(reducedMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo("conversation-end", anchor: .bottom) }
                }
                .onChange(of: agent.isThinking) { _, _ in proxy.scrollTo("conversation-end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("conversation-end", anchor: .bottom) }
            }
            if let error = agent.error ?? agent.storageWarning {
                HStack(alignment: .top) {
                    Text(error).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText).textSelection(.enabled)
                    if agent.messages.last?.role == .user { SubtleButton(title: "Retry") { agent.retry() }.disabled(agent.isThinking) }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a question or paste words to import…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).font(AppTypography.body)
                    .padding(12).background(AppColors.inputSurface, in: RoundedRectangle(cornerRadius: 12))
                    .focused($composing).onSubmit(send)
                if agent.isThinking {
                    ChromeIconButton(symbol: "stop.fill", help: "Stop reply") { agent.cancel() }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(AppTypography.ui(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36).foregroundStyle(AppColors.primaryButtonText)
                            .background(AppColors.primaryButton, in: Circle())
                    }.buttonStyle(MotionPressStyle()).disabled(draft.trimmed.isEmpty || agent.importingMessageID != nil).help("Send message").accessibilityLabel("Send message")
                }
            }
        }
        .onAppear { if compact { composing = true } }
    }
    private func send() {
        guard !agent.isThinking, !draft.trimmed.isEmpty else { return }
        let question = draft
        agent.send(question)
        if agent.isThinking { draft = "" }
    }
}

private struct AgentPlanView: View {
    @ObservedObject var agent: LearningAgent
    var onStart: ([UUID]) -> Void
    var onDiscuss: () -> Void
    @State private var dailyLimit = 15
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Weekly plan", detail: "")
            ControlRow(title: "Words per day", detail: "") {
                Stepper("\(dailyLimit)", value: $dailyLimit, in: 5...60, step: 5).fixedSize()
                QuietButton(title: "Preview plan") { Task { await agent.proposePlan(dailyLimit: dailyLimit) } }
            }
            if let plan = agent.proposedPlan ?? agent.plan, let profile = agent.profile {
                HStack {
                    Text(agent.proposedPlan == nil ? "Your plan" : "Plan preview").font(AppTypography.headline)
                    Spacer()
                    if agent.proposedPlan != nil {
                        SubtleButton(title: "Cancel") { agent.dismissProposal() }
                        PrimaryButton(title: "Use this plan") { agent.adoptPlan() }
                    }
                }
                Text("Up to \(plan.dailyLimit) words a day · \(plan.days.reduce(0) { $0 + $1.entryIDs.count }) words this week")
                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                if let lastDay = plan.days.last {
                    let covered = Set(plan.days.flatMap(\.entryIDs))
                    let unassigned = profile.entries.filter { !covered.contains($0.id) && profile.calendar.startOfDay(for: profile.dueDate($0.id)) <= lastDay.date }.count
                    if unassigned > 0 {
                        Text("\(unassigned) more words remain in your regular review queue. Increase the daily target to include more.")
                            .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    }
                }
                if plan.days.allSatisfy({ $0.entryIDs.isEmpty }) {
                    Text("No eligible words are due this week. Add words with both an English word and a Chinese meaning, or draw a word in Practice.")
                        .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                }
                ForEach(plan.days) { scheduledDay in
                    let day = plan.displayDay(scheduledDay, profile: profile)
                    let remaining = plan.remaining(day: day, profile: profile)
                    let ready = remaining.filter { profile.dueDate($0) <= profile.now }
                    let activeCount = day.entryIDs.filter { profile.activeIDs.contains($0) }.count
                    let today = profile.calendar.isDate(day.date, inSameDayAs: profile.now)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(day.date, format: .dateTime.weekday(.wide).month().day()).font(AppTypography.headline)
                            if today { Text("Today").font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText) }
                            Spacer()
                            Text("\(activeCount - remaining.count) / \(activeCount)").font(AppTypography.caption).monospacedDigit()
                            if today, agent.proposedPlan == nil, !ready.isEmpty {
                                QuietButton(title: "Start") { onStart(ready) }
                            }
                        }
                        let words = day.entryIDs.compactMap { id in profile.entries.first { $0.id == id }?.english }
                        Text(words.isEmpty ? "No words scheduled" : words.joined(separator: " · "))
                            .font(AppTypography.body).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        if today, !remaining.isEmpty, ready.isEmpty {
                            Text("The remaining words are due later today.").font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                        }
                        if today, day.entryIDs.contains(where: { !scheduledDay.entryIDs.contains($0) }) {
                            Text("Includes unfinished words").font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(today ? AppColors.inputSurface : AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
                }
                if plan.days.last.map({ profile.calendar.startOfDay(for: profile.now) > $0.date }) ?? false {
                    Text("This plan has ended. Preview a new week using your latest reviews.").font(AppTypography.caption)
                }
                SubtleButton(title: "Discuss this plan") {
                    agent.send("请根据我目前的复习记录，评价每天复习 \(plan.dailyLimit) 个单词的目标，并给我一条具体的执行建议。")
                    onDiscuss()
                }.disabled(agent.isThinking)
            } else {
                Text("Choose a daily target, then preview your week.")
                    .font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
            }
            if let error = agent.error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText) }
        }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct CompanionPractice: View {
    @ObservedObject var quiz: IslandQuizModel
    @ObservedObject var agent: LearningAgent
    var onDiscuss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeader(title: "Quick practice", detail: "")
                Spacer()
                MenuSelect(name: "Direction", selection: Binding(get: { quiz.direction }, set: { quiz.changeDirection($0) }), choices: ReviewDirection.allCases, label: { $0.title })
            }
            if quiz.isLoading { ProgressView("Drawing a word…") }
            else if quiz.entry != nil {
                Text(quiz.prompt).font(AppTypography.studyWord(quiz.prompt)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 24).textSelection(.enabled)
                LineField(title: "Your answer (optional)", text: $quiz.answer)
                if quiz.revealed {
                    Text(quiz.solution).font(AppTypography.reading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if quiz.recorded {
                        Text("Review saved · \(quiz.completed) recorded this session").font(AppTypography.caption)
                    } else {
                        Text("Record your recall:").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                        HStack { ForEach(ReviewRating.allCases, id: \.self) { rating in
                            QuietButton(title: rating.title) { Task { await quiz.record(rating); await agent.refresh() } }.disabled(quiz.isSaving)
                        } }
                    }
                }
                HStack {
                    if !quiz.revealed { PrimaryButton(title: "Reveal") { quiz.reveal() } }
                    QuietButton(title: "Another word") { Task { await quiz.next() } }.disabled(quiz.isSaving || quiz.isLoading)
                    SubtleButton(title: "Discuss my answer") {
                        agent.send("请针对当前抽查单词，看看我的回答，解释我遗漏的含义或容易混淆的地方。不要替我记录评分。")
                        onDiscuss()
                    }.disabled(agent.isThinking)
                }
            } else {
                Text("Add a word with an English word and a Chinese meaning to begin.").foregroundStyle(AppColors.secondaryText)
                QuietButton(title: "Draw a word") { Task { await quiz.next() } }
            }
            if let error = quiz.error { Text(error).font(AppTypography.caption) }
        }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
            .task { if quiz.entry == nil { await quiz.next() } }
    }
}
