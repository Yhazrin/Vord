import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor
final class QuickAddModel: ObservableObject {
    @Published var text = ""
    @Published var hint = ""
    @Published var candidates: [TranslationResult] = []
    @Published private(set) var selectedCandidateIndex = 0
    @Published var isTranslating = false
    @Published var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var preview: TranslationResult?
    @Published private(set) var sourceNote: String?
    @Published private(set) var selectionPrompt: String?
    @Published private(set) var lastSavedWord: String?
    @Published private(set) var panelHeight: CGFloat = 112
    @Published private(set) var focusRequest = 0
    func requestInputFocus() { focusRequest += 1 }
    var canSave: Bool { !text.trimmed.isEmpty && !isSaving }
    var selectedCandidate: TranslationResult? {
        candidates.indices.contains(selectedCandidateIndex) ? candidates[selectedCandidateIndex] : nil
    }
    func moveCandidate(_ offset: Int) {
        guard !candidates.isEmpty, !isSaving else { return }
        selectedCandidateIndex = min(max(0, selectedCandidateIndex + offset), candidates.count - 1)
    }
    func fitPreview(contentHeight: CGFloat) {
        guard preview != nil, !isTranslating, contentHeight > 0, contentHeight.isFinite else { return }
        let next = min(420, max(180, ceil(contentHeight) + 134 + (sourceNote == nil ? 0 : 26)))
        if abs(next - panelHeight) > 1 { panelHeight = next }
    }
    private let repository: any VocabularyRepository
    private let translation: TranslationService
    private var lookup: Task<Void, Never>?
    private var session = 0

    init(repository: any VocabularyRepository, translation: TranslationService) {
        self.repository = repository; self.translation = translation
    }
    func reset() {
        session += 1
        lookup?.cancel(); text = ""; hint = ""; candidates = []
        selectedCandidateIndex = 0
        isTranslating = false; isSaving = false; preview = nil; sourceNote = nil; selectionPrompt = nil; errorMessage = nil; lastSavedWord = nil
        panelHeight = 112
    }
    func presentWordChoices(_ words: [String]) {
        let listed = words.prefix(8).joined(separator: ", ")
        selectionPrompt = listed.isEmpty ? "Type one word from your selection." : "Type one word to add: \(listed)"
        panelHeight = 260
    }
    func prepare(selection: ExternalCaptureRequest) {
        reset(); text = selection.text; sourceNote = selection.source; scheduleLookup()
    }
    func scheduleLookup() {
        lookup?.cancel()
        let raw = text.trimmed
        preview = nil; candidates = []; selectedCandidateIndex = 0; hint = ""; errorMessage = nil
        guard !raw.isEmpty else {
            isTranslating = false
            if selectionPrompt == nil { panelHeight = 112 }
            return
        }
        isTranslating = true
        panelHeight = max(156, panelHeight)
        lookup = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await self?.lookupNow(raw)
        }
    }
    func submit(candidate: TranslationResult? = nil) async -> Bool {
        let raw = text.trimmed
        guard !raw.isEmpty, !isSaving else { return false }
        let currentSession = session
        lookup?.cancel(); isTranslating = false
        errorMessage = nil; isSaving = true
        defer { if session == currentSession { isSaving = false } }
        var result = (candidate ?? preview).flatMap { CaptureService.matches($0, raw: raw) ? $0 : nil }
        do {
            if result == nil {
                let found = try await translation.lookup(text: raw)
                guard !Task.isCancelled, session == currentSession, text.trimmed == raw else { return false }
                if found.requiresSelection {
                    candidates = found.results; hint = "Choose an English word below."
                    panelHeight = 420
                    return false
                }
                result = found.results.first
            }
            guard let result else { throw TranslationFailure.notInLocalDictionary }
            let enriched = await translation.enrich(result)
            guard !Task.isCancelled, session == currentSession, text.trimmed == raw else { return false }
            var draft = CaptureService.draft(from: enriched)
            if let sourceNote { draft.source = sourceNote }
            let saved = try await repository.upsert(draft, now: Date())
            guard session == currentSession else { return false }
            lastSavedWord = saved.english
            return true
        } catch {
            guard session == currentSession, !Task.isCancelled else { return false }
            errorMessage = error.localizedDescription; return false
        }
    }
    private func lookupNow(_ raw: String) async {
        do {
            let found = try await translation.lookup(text: raw)
            guard !Task.isCancelled, text.trimmed == raw else { return }
            candidates = found.requiresSelection ? found.results : []
            preview = found.requiresSelection ? nil : found.results.first
            hint = found.requiresSelection ? "Choose an English word below." : (preview?.chinese ?? "")
            isTranslating = false
            let showsExample = preview?.exampleSentence?.trimmed.isEmpty == false
            panelHeight = candidates.isEmpty ? (preview == nil ? 156 : (showsExample ? 300 : 256)) : 380
        } catch {
            guard !Task.isCancelled, text.trimmed == raw else { return }
            preview = nil; hint = error.localizedDescription; isTranslating = false
            panelHeight = 156
        }
    }
}

struct QuickAddView: View {
    @ObservedObject var model: QuickAddModel
    var onClose: () -> Void
    var onSaved: (() -> Void)? = nil
    @State private var focused = true
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CaptureInput(text: $model.text, focused: $focused, fontSize: 22, onSubmit: submit, onCancel: onClose, onMoveCandidate: { offset in
                        guard !model.candidates.isEmpty else { return false }
                        model.moveCandidate(offset); return true
                    })
                    .frame(height: 30)
                ChromeIconButton(symbol: "xmark", help: "Close quick add", action: onClose)
            }
            if let source = model.sourceNote {
                Text(source).font(AppTypography.caption).foregroundStyle(AppColors.tertiaryText)
                    .lineLimit(1).truncationMode(.middle).help(source)
            }
            if hasLookupContent {
              Hairline()
              ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.isTranslating {
                        ProgressView().controlSize(.small).accessibilityLabel("Looking up")
                    } else if let preview = model.preview {
                        VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            if let phonetic = preview.phonetic?.nilIfEmpty {
                                Text(phonetic).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            }
                            if model.text.trimmed.caseInsensitiveCompare(preview.english) != .orderedSame {
                                Text(preview.english).font(AppTypography.headline)
                            }
                            Spacer()
                            SpeechButton(text: preview.english)
                        }
                        Text(preview.chinese).font(AppTypography.ui(size: 18)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).id(preview.chinese)
                        if let definition = preview.englishDefinition {
                            Text(definition).font(AppTypography.body).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).id(definition)
                        }
                        if let example = preview.exampleSentence?.trimmed, !example.isEmpty {
                            Text(example).font(AppTypography.body).italic().lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if let provider = preview.providerName {
                            Text(provider).font(AppTypography.caption).foregroundStyle(AppColors.tertiaryText)
                        }
                        }
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: CapturePreviewHeight.self, value: geometry.size.height)
                        })
                        .modifier(MotionArrival()).id(preview.english)
                    } else if !model.hint.isEmpty {
                        Text(model.hint).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                    } else if model.text.trimmed.isEmpty, let prompt = model.selectionPrompt, !prompt.isEmpty {
                        Text(prompt).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.candidates.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.candidates, id: \.english) { candidate in
                                Button {
                                    Task { if await model.submit(candidate: candidate) { (onSaved ?? onClose)() } }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(candidate.english).font(AppTypography.headline).frame(width: 115, alignment: .leading)
                                        Text(candidate.chinese).font(AppTypography.caption)
                                            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                                    }.padding(.vertical, 10).padding(.horizontal, 8).contentShape(Rectangle())
                                        .background(model.selectedCandidate?.english == candidate.english ? AppColors.accentWash : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(MotionPressStyle()).disabled(model.isSaving)
                                    .accessibilityAddTraits(model.selectedCandidate?.english == candidate.english ? .isSelected : [])
                                    .id(candidate.english)
                                Hairline()
                            }
                        }
                        .modifier(MotionArrival())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
              }.frame(maxHeight: .infinity)
                .onPreferenceChange(CapturePreviewHeight.self) { model.fitPreview(contentHeight: $0) }
                .onChange(of: model.selectedCandidateIndex) { _, _ in
                    if let selected = model.selectedCandidate { proxy.scrollTo(selected.english, anchor: .center) }
                }
              }
            }
            HStack {
                if model.isSaving {
                    ProgressView().controlSize(.small).accessibilityLabel("Saving")
                } else if let error = model.errorMessage {
                    Text(error).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText).lineLimit(2)
                }
                Spacer()
                PrimaryButton(title: model.candidates.isEmpty ? "Add" : "Add selected", action: submit).disabled(!model.canSave)
                    .help("Return to add")
            }
        }
        .padding(18).disabled(model.isSaving)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(AppTypography.body)
        .foregroundStyle(AppColors.primaryText)
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { _, _ in focused = true }
        .onChange(of: model.text) { _, _ in model.scheduleLookup() }
        .onExitCommand(perform: onClose)
    }
    private var hasLookupContent: Bool {
        model.isTranslating || model.preview != nil || !model.hint.isEmpty || model.selectionPrompt != nil || !model.candidates.isEmpty
    }
    private func submit() {
        let chosen = model.selectedCandidate
        Task { if await model.submit(candidate: chosen) { (onSaved ?? onClose)() } }
    }
}


private struct CapturePreviewHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor
final class QuickAddController {
    let model: QuickAddModel
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let hotkey = HotKeyController()
    private let settings: AppSettings
    private let repository: any VocabularyRepository
    private let clipboard = ClipboardWordMonitor()
    private let candidateDictionary = LocalDictionaryProvider()
    private let presentation = QuickCapturePresentation()
    private let spring = CaptureFrameSpring()
    private let orbMotion = OrbMotion()
    private var dock = OrbDockPosition()
    private var dragStart = CGPoint.zero
    private var dragOrigin = CGPoint.zero
    private var dragLastPoint = CGPoint.zero
    private var dragLastTime: CFTimeInterval = 0
    private var dragVelocity = CGPoint.zero
    private var dragging = false
    private var panel: QuickAddPanel?
    private var screen: NSScreen?
    private var started = false
    private var subscriptions: Set<AnyCancellable> = []
    private var clipboardCheck: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var promptGeneration = 0
    private var previousApplication: NSRunningApplication?

    init(repository: any VocabularyRepository, translation: TranslationService, settings: AppSettings) {
        model = QuickAddModel(repository: repository, translation: translation)
        self.settings = settings
        self.repository = repository
        if let data = UserDefaults.standard.data(forKey: "quickCapture.orbDock"),
           let saved = try? JSONDecoder().decode(OrbDockPosition.self, from: data) { dock = saved }
        model.$panelHeight.removeDuplicates().sink { [weak self] _ in
            guard let self, self.presentation.mode == .adding else { return }
            // @Published emits before the value is installed.
            DispatchQueue.main.async { [weak self] in self?.resize() }
        }.store(in: &subscriptions)
    }

    func start() {
        guard !started else { return }
        started = true
        guard ProcessInfo.processInfo.environment["VORD_DISABLE_HOTKEY"] != "1" else { return }
        hotkey.handler = { [weak self] in self?.toggle() }
        applyShortcut(settings.shortcut)
        clipboard.onCandidate = { [weak self] word in self?.considerClipboard(word) }
        settings.$clipboardCaptureEnabled.removeDuplicates().sink { [weak self] enabled in
            self?.clipboard.setEnabled(enabled)
        }.store(in: &subscriptions)
        settings.$floatingQuickAddEnabled.removeDuplicates().sink { [weak self] enabled in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentation.mode == .collapsed else { return }
                if enabled { self.showWidget() } else { self.panel?.orderOut(nil) }
            }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.panel?.isVisible == true else { return }
                    self.screen = self.dockedScreen(); self.resize()
                }
            }
        if settings.floatingQuickAddEnabled { showWidget() }
    }

    func applyShortcut(_ shortcut: QuickAddShortcut) {
        guard ProcessInfo.processInfo.environment["VORD_DISABLE_HOTKEY"] != "1" else { return }
        settings.hotKeyWarning = hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }

    func toggle() {
        if presentation.mode == .adding { close() } else { show() }
    }

    func showWordChoices(_ words: [String]) {
        show()
        model.presentWordChoices(words)
    }

    func show(selection: ExternalCaptureRequest? = nil) {
        feedbackTask?.cancel(); clipboardCheck?.cancel(); promptGeneration += 1
        let panel = ensurePanel()
        if presentation.mode != .adding,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        if let selection { model.prepare(selection: selection) } else { model.reset() }
        if !panel.isVisible { screen = presentationScreen() }
        if !panel.isVisible {
            panel.setFrame(targetFrame(for: .collapsed), display: true)
            panel.orderFrontRegardless()
        }
        setMode(.adding)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.requestInputFocus()
        panel.requestCaptureFocus()
        // Activation may select the main window after a nonactivating panel has appeared.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentation.mode == .adding, panel.isVisible else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.requestCaptureFocus()
        }
        onPresent?()
    }

    func close() {
        feedbackTask?.cancel()
        clipboardCheck?.cancel(); promptGeneration += 1
        model.reset()
        panel?.makeFirstResponder(nil)
        panel?.resignKey()
        setMode(.collapsed)
        onDismiss?()
        restorePreviousApplication()
        hideCollapsedWhenDisabled()
    }

    private func showWidget() {
        let panel = ensurePanel()
        screen = dockedScreen()
        panel.setFrame(targetFrame(for: .collapsed), display: true)
        panel.orderFrontRegardless()
    }

    private func considerClipboard(_ word: String?) {
        clipboardCheck?.cancel(); promptGeneration += 1
        let generation = promptGeneration
        if presentation.mode == .prompt { dismissPrompt() }
        guard let word else {
            return
        }
        guard presentation.mode != .adding, presentation.mode != .saved else { return }
        let provider = candidateDictionary
        clipboardCheck = Task { [weak self] in
            // Dictionary-only validation. This path never invokes translation downloads or AI.
            let known = await Task.detached {
                (try? await provider.translate(text: word, from: .english, to: .chinese)) != nil
            }.value
            guard known,
                  let self, !Task.isCancelled else { return }
            let entries = try? await self.repository.activeEntries()
            guard !Task.isCancelled, self.promptGeneration == generation, self.settings.clipboardCaptureEnabled,
                  self.presentation.mode != .adding, self.presentation.mode != .saved else { return }
            guard entries?.contains(where: { $0.english.caseInsensitiveCompare(word) == .orderedSame }) != true else {
                if self.presentation.mode == .prompt { self.dismissPrompt() }
                return
            }
            self.presentation.word = word
            let panel = self.ensurePanel()
            if !panel.isVisible { self.screen = self.presentationScreen() }
            if !panel.isVisible { panel.setFrame(self.targetFrame(for: .collapsed), display: true) }
            // A suggestion is passive: keyboard focus remains in the user's current app.
            panel.orderFrontRegardless()
            self.setMode(.prompt)
        }
    }

    private func dismissPrompt() {
        setMode(.collapsed)
        hideCollapsedWhenDisabled()
    }

    private func acceptPrompt() {
        guard let selection = try? ExternalCaptureRequest(text: presentation.word) else { return }
        show(selection: selection)
    }

    private func saved() {
        presentation.word = model.lastSavedWord ?? model.preview?.english ?? model.text.trimmed
        panel?.makeFirstResponder(nil)
        panel?.resignKey()
        model.reset()
        setMode(.saved)
        onDismiss?()
        restorePreviousApplication()
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 950_000_000)
            guard !Task.isCancelled, let self, self.presentation.mode == .saved else { return }
            self.setMode(.collapsed)
            self.hideCollapsedWhenDisabled()
        }
    }

    private func hideCollapsedWhenDisabled() {
        guard !settings.floatingQuickAddEnabled else { return }
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, let self, self.presentation.mode == .collapsed,
                  !self.settings.floatingQuickAddEnabled else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func restorePreviousApplication() {
        if let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    private func setMode(_ mode: QuickCapturePresentation.Mode) {
        if dragging { finishDrag(dragLastPoint) }
        if mode != .collapsed { orbMotion.reset() }
        panel?.allowsKeyboardFocus = mode == .adding
        if mode == .adding { panel?.requestCaptureFocus() }
        if mode != .adding { panel?.cancelCaptureFocus() }
        panel?.hasShadow = mode != .collapsed
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduced ? nil : .spring(duration: 0.42, bounce: 0.12)) { presentation.mode = mode }
        resize()
    }

    private func resize() {
        guard !dragging, let panel else { return }
        spring.move(panel, to: targetFrame(for: presentation.mode))
    }

    private func targetFrame(for mode: QuickCapturePresentation.Mode) -> NSRect {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let size: CGSize
        switch mode {
        case .collapsed: size = CGSize(width: OrbDockPosition.diameter, height: OrbDockPosition.diameter)
        case .prompt: size = CGSize(width: 308, height: 100)
        case .saved: size = CGSize(width: 220, height: 64)
        case .adding: size = CGSize(width: 440, height: model.panelHeight)
        }
        let width = min(size.width, max(48, visible.width - 40))
        let height = min(size.height, max(48, visible.height - 52))
        let orb = dock.frame(in: visible)
        if mode == .collapsed { return orb }
        let x = dock.edge == .left ? orb.minX : orb.maxX - width
        let y = min(max(orb.midY - height / 2, visible.minY + 12), visible.maxY - height - 12)
        return NSRect(x: min(max(x, visible.minX + 8), visible.maxX - width - 8),
            y: y, width: width, height: height)
    }

    private func dockedScreen() -> NSScreen? {
        NSScreen.screens.first { displayID($0) == dock.displayID } ?? NSScreen.main
    }

    private func presentationScreen() -> NSScreen? {
        if settings.floatingQuickAddEnabled { return dockedScreen() }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func beginDrag(_ point: CGPoint) {
        guard presentation.mode == .collapsed, let panel else { return }
        spring.stop()
        let size = OrbDockPosition.diameter
        panel.setPanelFrame(NSRect(x: panel.frame.midX - size / 2, y: panel.frame.midY - size / 2,
            width: size, height: size))
        dragging = true; dragStart = point; dragOrigin = panel.frame.origin
        dragLastPoint = point; dragLastTime = CACurrentMediaTime(); dragVelocity = .zero
        orbMotion.begin()
    }

    private func updateDrag(_ point: CGPoint) {
        guard dragging, let panel else { return }
        if let next = NSScreen.screens.first(where: { $0.frame.contains(point) }) { screen = next }
        let now = CACurrentMediaTime(), dt = max(0.008, now - dragLastTime)
        let measured = CGPoint(x: (point.x - dragLastPoint.x) / dt, y: (point.y - dragLastPoint.y) / dt)
        // Filter event noise, retaining a small amount of release momentum.
        dragVelocity = CGPoint(x: dragVelocity.x * 0.35 + measured.x * 0.65,
            y: dragVelocity.y * 0.35 + measured.y * 0.65)
        dragLastPoint = point; dragLastTime = now
        let frame = NSRect(x: dragOrigin.x + point.x - dragStart.x,
            y: dragOrigin.y + point.y - dragStart.y,
            width: OrbDockPosition.diameter, height: OrbDockPosition.diameter)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        panel.setPanelFrame(OrbDockPosition.clamped(frame, in: visible))
        orbMotion.drive(dragVelocity)
    }

    private func finishDrag(_ point: CGPoint) {
        guard dragging, let panel else { return }
        updateDrag(point)
        dragging = false
        orbMotion.release()
        guard let screen = screen ?? NSScreen.main else { return }
        dock = .nearest(to: panel.frame, in: screen.visibleFrame, displayID: displayID(screen))
        if let encoded = try? JSONEncoder().encode(dock) { UserDefaults.standard.set(encoded, forKey: "quickCapture.orbDock") }
        // Strong damping draws the sphere to an edge; release speed is bounded to keep it on screen.
        let momentum = CGPoint(x: max(-240, min(240, dragVelocity.x)), y: max(-160, min(160, dragVelocity.y)))
        spring.move(panel, to: dock.frame(in: screen.visibleFrame), initialVelocity: momentum)
    }

    private func ensurePanel() -> QuickAddPanel {
        if let panel { return panel }
        let panel = QuickAddPanel(contentRect: NSRect(x: 0, y: 0, width: OrbDockPosition.diameter, height: OrbDockPosition.diameter),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("vord.quickadd")
        panel.title = "Vord Quick Add"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = PanelHostingView(rootView: QuickCaptureShell(model: model, presentation: presentation, orbMotion: orbMotion,
            onOpen: { [weak self] in self?.show() }, onClose: { [weak self] in self?.close() },
            onSaved: { [weak self] in self?.saved() }, onAccept: { [weak self] in self?.acceptPrompt() },
            onDismissPrompt: { [weak self] in self?.dismissPrompt() },
            onDragBegin: { [weak self] in self?.beginDrag($0) },
            onDragChange: { [weak self] in self?.updateDrag($0) },
            onDragEnd: { [weak self] in self?.finishDrag($0) }))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

private final class QuickAddPanel: NSPanel, CaptureInputFocusOwner {
    var allowsKeyboardFocus = false
    private var captureFocusPending = false
    private var pendingTyping: [NSEvent] = []
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    func requestCaptureFocus() {
        captureFocusPending = true
        if let field = captureField(in: contentView) { captureInputDidAttach(field) }
    }
    func cancelCaptureFocus() { captureFocusPending = false; pendingTyping.removeAll() }
    override func sendEvent(_ event: NSEvent) {
        // Keep the first keystrokes while SwiftUI inserts the field. Replay native
        // events into its editor so input methods still interpret them normally.
        if allowsKeyboardFocus, captureFocusPending, event.type == .keyDown,
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
           let characters = event.characters, characters.unicodeScalars.contains(where: { $0.value >= 32 }),
           captureField(in: contentView)?.currentEditor() == nil, pendingTyping.count < 32 {
            pendingTyping.append(event)
            return
        }
        super.sendEvent(event)
    }
    private func replayPendingTyping() {
        let events = pendingTyping
        pendingTyping.removeAll()
        for event in events { super.sendEvent(event) }
    }
    func captureInputDidAttach(_ field: CaptureNativeField) {
        guard captureFocusPending, allowsKeyboardFocus else { return }
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.captureFocusPending, self.allowsKeyboardFocus,
                  self.isVisible, field.window === self else { return }
            if !self.isKeyWindow { self.makeKey() }
            guard self.isKeyWindow else { return }
            if field.currentEditor() != nil {
                self.captureFocusPending = false
                self.replayPendingTyping()
                return
            }
            guard self.makeFirstResponder(field) else { return }
            self.captureFocusPending = false
            field.selectText(nil)
            self.replayPendingTyping()
        }
    }
    private func captureField(in view: NSView?) -> CaptureNativeField? {
        guard let view else { return nil }
        if let field = view as? CaptureNativeField { return field }
        for child in view.subviews {
            if let field = captureField(in: child) { return field }
        }
        return nil
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: false)
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: false, animate: false)
    }
}

@MainActor
private final class QuickCapturePresentation: ObservableObject {
    enum Mode { case collapsed, prompt, adding, saved }
    @Published var mode: Mode = .collapsed
    @Published var word = ""
}

private struct QuickCaptureShell: View {
    @ObservedObject var model: QuickAddModel
    @ObservedObject var presentation: QuickCapturePresentation
    @ObservedObject var orbMotion: OrbMotion
    var onOpen: () -> Void
    var onClose: () -> Void
    var onSaved: () -> Void
    var onAccept: () -> Void
    var onDismissPrompt: () -> Void
    var onDragBegin: (CGPoint) -> Void
    var onDragChange: (CGPoint) -> Void
    var onDragEnd: (CGPoint) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var compact: Bool { presentation.mode == .collapsed }

    var body: some View {
        ZStack {
            if presentation.mode == .adding {
                QuickAddView(model: model, onClose: onClose, onSaved: onSaved)
                    .transition(.opacity.combined(with: .offset(y: reduced ? 0 : 8)))
            } else if presentation.mode == .prompt {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Add").foregroundStyle(AppColors.secondaryText)
                        Text(presentation.word).fontWeight(.semibold).lineLimit(1)
                        Text("?").foregroundStyle(AppColors.secondaryText)
                        Spacer(minLength: 4)
                    }.font(AppTypography.body)
                    HStack {
                        Text("Copied word").font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                        Spacer()
                        Button("Not now", action: onDismissPrompt).buttonStyle(.plain).font(AppTypography.caption)
                        PrimaryButton(title: "Add", action: onAccept)
                    }
                }.padding(18).transition(.opacity)
            } else if presentation.mode == .saved {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                    Text("\(presentation.word) added").font(AppTypography.caption).lineLimit(1)
                }.padding(16).transition(.opacity)
                .accessibilityLabel("\(presentation.word) added to your library")
            } else {
                GlassOrbView(motion: orbMotion, onOpen: onOpen, onDragBegin: onDragBegin,
                    onDragChange: onDragChange, onDragEnd: onDragEnd).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppColors.primaryText)
        .background {
            if !compact { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AppColors.contentBackground) }
        }
        .onExitCommand(perform: onClose)
    }
}
