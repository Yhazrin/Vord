import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settings: AppSettings
    @State private var tab: AppTab = .today
    @State private var contentExpanded = false
    @State private var isFullScreen = false
    @State private var fullScreenSidebarVisible = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        GeometryReader { geometry in
            let hidden = isFullScreen ? !fullScreenSidebarVisible : contentExpanded
            let railWidth = AppLayout.railWidth(windowWidth: geometry.size.width)
            let layout = AppLayout(contentSize: CGSize(width: geometry.size.width - (hidden ? 0 : railWidth) - 24,
                                                       height: geometry.size.height - (isFullScreen ? 24 : 48)))
        HStack(spacing: 0) {
            NavigationRail(selection: $tab, compact: railWidth < 100) {
                if isFullScreen { fullScreenSidebarVisible = false } else { contentExpanded = true }
            }
            .frame(width: railWidth)
            .frame(width: hidden ? 0 : railWidth)
            .clipped()
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            ContentSurface {
                ZStack(alignment: .topLeading) {
                    page.modifier(MotionArrival()).id(tab)
                    if let warning = dependencies.warning {
                        Text(warning)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .padding(12)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if hidden {
                    ChromeIconButton(
                        symbol: "arrow.down.right.and.arrow.up.left",
                        help: "Show Sidebar"
                    ) {
                        if isFullScreen { fullScreenSidebarVisible = true } else { contentExpanded = false }
                    }
                    .padding(12)
                }
            }
            .padding(hidden
                ? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                : EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 12))
        }
        .padding(.top, isFullScreen ? 0 : 24)
        .animation(AppMotion.layout(reducedMotion), value: hidden)
        .environment(\.vordContentExpanded, hidden)
        .environment(\.vordLayout, layout)
        }
        .background { ContentSurfaceBackground(woodGrain: settings.woodGrainEnabled) }
        .background(WindowChrome(isFullScreen: $isFullScreen))
        .frame(minWidth: 720, minHeight: 520)
        // The traffic lights live above the rail; the content card uses its own outer inset.
        .ignoresSafeArea(.container, edges: .top)
        .font(AppTypography.body)
        .tint(AppColors.accent)
        .modifier(AppleTranslationTaskModifier(bridge: dependencies.appleBridge))
        .onAppear {
            tab = dependencies.requestedTab
            if !AppDependencies.isTestHost { dependencies.quickAdd.start() }
        }
        .onChange(of: tab) { _, destination in dependencies.requestedTab = destination }
        .task { if !AppDependencies.isTestHost { await dependencies.sync.start() } }
        .task { if !AppDependencies.isTestHost { await dependencies.updates.checkIfDue() } }
        .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
            if !AppDependencies.isTestHost { Task { await dependencies.updates.checkIfDue() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vordNavigate)) { notification in
            if let destination = notification.object as? AppTab { tab = destination }
        }
        .onChange(of: isFullScreen) { _, fullScreen in
            if fullScreen { fullScreenSidebarVisible = false }
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .today: TodayView(onStartReview: { tab = .review }, onNavigate: { tab = $0 })
        case .add: AddView()
        case .review: ReviewView { tab = .today }
        case .dictation: DictationView(model: dependencies.dictation)
        case .context: ContextView { tab = .settings }
        case .agent: AgentView(agent: dependencies.agent) { ids in
            dependencies.startPlanReview(entryIDs: ids); tab = .review
        }
        case .library: LibraryView(onImport: { dependencies.openVocabularyImport() })
        case .settings: SettingsView()
        }
    }
}

private struct WindowChrome: NSViewRepresentable {
    @Binding var isFullScreen: Bool
    func makeCoordinator() -> Coordinator { Coordinator(fullScreen: $isFullScreen) }
    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.onWindow = { window in context.coordinator.attach(window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.fullScreen = $isFullScreen
        context.coordinator.attach(nsView.window)
    }

    private final class ChromeView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindow?(window) }
    }

    final class Coordinator {
        var fullScreen: Binding<Bool>
        private weak var attachedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        init(fullScreen: Binding<Bool>) { self.fullScreen = fullScreen }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func attach(_ window: NSWindow?) {
            guard let window, attachedWindow !== window else { return }
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
            attachedWindow = window
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(AppColors.windowBackground)
            DispatchQueue.main.async { [weak self, weak window] in self?.fullScreen.wrappedValue = window?.styleMask.contains(.fullScreen) ?? false }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    self?.fullScreen.wrappedValue = window?.styleMask.contains(.fullScreen) ?? false
                })
            }
        }
    }
}
