import AppKit
import SwiftUI
import XCTest
@testable import Vord

final class CaptureInputTests: XCTestCase {
    @MainActor
    func testReturnDuringChineseCompositionDoesNotSaveAndNativeEditingKeepsUnicode() {
        var text = "", focused = false, submits = 0
        let input = CaptureInput(text: Binding(get: { text }, set: { text = $0 }),
            focused: Binding(get: { focused }, set: { focused = $0 }), onSubmit: { submits += 1 })
        let coordinator = input.makeCoordinator()
        let field = NSTextField(), editor = NSTextView()
        editor.setMarkedText("害怕", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(submits, 0)
        editor.unmarkText()
        field.stringValue = "害怕"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(text, "害怕")
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(submits, 1)
        XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
    }
}
