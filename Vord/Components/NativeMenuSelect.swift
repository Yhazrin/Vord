import AppKit
import SwiftUI

/// The menu stays native; its trigger uses the same size and type as our fields.
/// A native button avoids macOS rewriting a SwiftUI Menu label as a small bezel.
struct NativeMenuSelect<Selection: Hashable>: NSViewRepresentable {
    var name: String
    @Binding var selection: Selection
    var choices: [Selection]
    var label: (Selection) -> String
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelectionMenuButton {
        let button = SelectionMenuButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.openMenu(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: SelectionMenuButton, context: Context) {
        context.coordinator.parent = self
        button.title = label(selection)
        button.isEnabled = isEnabled
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityLabel(name)
        button.setAccessibilityValue(label(selection))
        button.toolTip = name
        button.needsDisplay = true
    }

    @MainActor final class Coordinator: NSObject {
        var parent: NativeMenuSelect
        init(_ parent: NativeMenuSelect) { self.parent = parent }

        @objc func openMenu(_ sender: SelectionMenuButton) {
            let menu = NSMenu(title: parent.name)
            menu.font = AppTypography.nativeUI(size: 13)
            menu.minimumWidth = sender.bounds.width
            for (index, choice) in parent.choices.enumerated() {
                let item = NSMenuItem(title: parent.label(choice), action: #selector(selectItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = choice == parent.selection ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }

        @objc func selectItem(_ item: NSMenuItem) {
            guard parent.choices.indices.contains(item.tag) else { return }
            parent.selection = parent.choices[item.tag]
        }
    }
}

final class SelectionMenuButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        font = AppTypography.nativeUI(size: 13, weight: .medium)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { isEnabled }

    override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Space, Return and the arrow keys open the native, keyboard-driven menu.
        if [36, 49, 125, 126].contains(event.keyCode) {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = NSColor(AppColors.inputSurface)
        let foreground = NSColor(AppColors.primaryText).withAlphaComponent(isEnabled ? 1 : 0.45)
        let border = NSColor(window?.firstResponder === self ? AppColors.accentNeutral : AppColors.subtleBorder)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: AppRadius.control, yRadius: AppRadius.control)
        (isHighlighted ? NSColor(AppColors.selected) : fill).setFill()
        shape.fill()
        border.withAlphaComponent(window?.firstResponder === self ? 0.5 : 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textFont = font ?? AppTypography.nativeUI(size: 13, weight: .medium)
        let height = ceil(textFont.ascender - textFont.descender)
        let textRect = NSRect(x: 12, y: floor((bounds.height - height) / 2) - 1,
                              width: max(0, bounds.width - 38), height: height + 2)
        (title as NSString).draw(in: textRect, withAttributes: [
            .font: textFont, .foregroundColor: foreground, .paragraphStyle: paragraph
        ])
        let arrow = NSBezierPath()
        let centerX = bounds.maxX - 16
        let centerY = bounds.midY
        arrow.move(to: NSPoint(x: centerX - 3, y: centerY + 1.5))
        arrow.line(to: NSPoint(x: centerX, y: centerY - 1.5))
        arrow.line(to: NSPoint(x: centerX + 3, y: centerY + 1.5))
        arrow.lineWidth = 1.3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        foreground.withAlphaComponent(isEnabled ? 0.65 : 0.4).setStroke()
        arrow.stroke()
    }
}
