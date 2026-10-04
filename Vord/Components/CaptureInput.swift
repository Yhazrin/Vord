import AppKit
import SwiftUI

/// The native panel owns the first focus request, independent of SwiftUI's insertion transition.
protocol CaptureInputFocusOwner: AnyObject {
    func captureInputDidAttach(_ field: CaptureNativeField)
}

/// Capture is keyboard-first. Request focus after the native field is attached to a key window,
/// including when a retained quick-add panel is opened for a second time.
struct CaptureInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var fontSize: CGFloat = 20
    var onSubmit: () -> Void
    var onCancel: (() -> Void)? = nil
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CaptureNativeField {
        let field = CaptureNativeField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = AppTypography.nativeUI(size: fontSize, weight: .medium)
        field.placeholderString = "English or Chinese"
        field.setAccessibilityLabel("English or Chinese")
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: CaptureNativeField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.textColor = NSColor(AppColors.primaryText)
        field.isEnabled = enabled
        field.wantsInputFocus = focused
        field.requestInputFocus()
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CaptureInput
        init(_ parent: CaptureInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                // Return first confirms an IME composition; it must not also save the word.
                guard !textView.hasMarkedText() else { return false }
                parent.onSubmit(); return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)), let onCancel = parent.onCancel {
                onCancel(); return true
            }
            return false
        }
    }
}

final class CaptureNativeField: NSTextField {
    var wantsInputFocus = false
    private var keyWindowObserver: NSObjectProtocol?
    private var focusQueued = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
        if let window {
            keyWindowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.requestInputFocus() }
                }
        }
        requestInputFocus()
        (window as? any CaptureInputFocusOwner)?.captureInputDidAttach(self)
    }
    func requestInputFocus() {
        guard wantsInputFocus, isEnabled, currentEditor() == nil, !focusQueued else { return }
        focusQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusQueued = false
            guard self.wantsInputFocus, self.isEnabled, self.currentEditor() == nil,
                  let window = self.window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
            self.selectText(nil)
        }
    }
    deinit { if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) } }
}
