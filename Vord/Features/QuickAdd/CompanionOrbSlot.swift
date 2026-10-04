import AppKit
import SwiftUI

/// Reserves an actual place in the page for the same native orb used on the desktop.
/// No duplicate image or second mascot is drawn during the window handoff.
struct CompanionOrbSlot: View {
    @ObservedObject var controller: QuickAddController
    var onOpen: () -> Void

    var body: some View {
        Button { controller.rejoinCompanion() } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(AppTypography.ui(size: 14, weight: .medium))
                .foregroundStyle(AppColors.tertiaryText)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Bring Companion back")
        .accessibilityLabel("Bring Companion back")
        .opacity(controller.companionIsDocked ? 0 : 1)
        .disabled(controller.companionIsDocked)
        .accessibilityHidden(controller.companionIsDocked)
        .frame(width: OrbDockPosition.diameter, height: OrbDockPosition.diameter)
        .background(CompanionOrbAnchor(controller: controller, onOpen: onOpen))
    }
}

private struct CompanionOrbAnchor: NSViewRepresentable {
    var controller: QuickAddController
    var onOpen: () -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.controller = controller; view.onOpen = onOpen
        return view
    }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.onOpen = onOpen
        view.refresh()
    }
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        view.controller?.detachCompanion(anchor: view)
        view.removeObservers()
    }

    final class AnchorView: NSView {
        weak var controller: QuickAddController?
        var onOpen: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var updateScheduled = false
        private var sheetCovered = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { controller?.detachCompanion(anchor: self); return }
            sheetCovered = window.attachedSheet != nil
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        // willBegin arrives before attachedSheet is guaranteed to be set.
                        if name == NSWindow.willBeginSheetNotification { self.sheetCovered = true }
                        if name == NSWindow.didEndSheetNotification { self.sheetCovered = false }
                        self.refresh()
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.controller?.detachCompanion(anchor: self)
                }
            })
            refresh()
        }
        override func layout() { super.layout(); refresh() }
        func refresh() {
            guard !updateScheduled else { return }
            updateScheduled = true
            // SwiftUI may still be laying out its ancestors; read screen coordinates afterward.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard self.window != nil, self.bounds.width > 0 else { return }
                self.controller?.attachCompanion(anchor: self, sheetCovered: self.sheetCovered) { [weak self] in self?.onOpen?() }
            }
        }
        func removeObservers() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
