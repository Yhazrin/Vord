import AppKit
import SwiftUI

/// SwiftUI hosting for borderless panels whose frame is owned by AppKit.
/// The default hosting view resizes the window from `windowDidLayout`, which
/// aborts when a spring is already calling `setFrame` in the same display cycle.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sizingOptions = []
        safeAreaRegions = []
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("NSWindowDidLayoutNotification"), object: window)
        }
    }

    @objc func windowDidLayout() {
        // Intentionally empty: NSHostingView's implementation calls
        // updateAnimatedWindowSize, which setFrames the panel mid-layout.
    }
}

extension NSWindow {
    /// Resize a panel without asking AppKit to layout in the current display cycle.
    func setPanelFrame(_ frame: NSRect) {
        setFrame(frame, display: false)
    }
}
