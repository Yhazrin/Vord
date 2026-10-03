import AppKit
import ObjectiveC

extension Notification.Name {
    static let vordAddInAppSelection = Notification.Name("vord.addInAppSelection")
}

/// Turns text selected inside a Vord window into the existing quick-add flow.
enum InAppSelection {
    enum Capture: Equatable {
        /// A single word or a short lexical phrase the learner can confirm.
        case word(String)
        /// A longer selection. The sentence itself is not a headword.
        case choose([String])
    }

    private static let functionWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "than", "so", "to", "of", "in", "on",
        "for", "with", "at", "from", "by", "as", "is", "are", "was", "were", "be", "been", "being",
        "it", "its", "this", "that", "these", "those", "i", "you", "he", "she", "we", "they",
        "me", "him", "her", "us", "them", "my", "your", "his", "our", "their", "not", "no",
        "do", "does", "did", "have", "has", "had", "will", "would", "can", "could", "should",
        "may", "might", "must", "just", "very", "into", "about", "also", "there", "here"
    ]

    static func capture(from raw: String) -> Capture? {
        let tokens = englishTokens(raw)
        guard !tokens.isEmpty else { return nil }
        if tokens.count == 1 { return .word(tokens[0]) }
        let sentence = raw.contains { ".!?;".contains($0) } || tokens.count > 3
        if !sentence, let request = try? ExternalCaptureRequest(text: tokens.joined(separator: " ")) {
            return .word(request.text)
        }
        let content = tokens.filter { !functionWords.contains($0.lowercased()) }
        if content.count == 1 { return .word(content[0]) }
        let choices = content.isEmpty ? tokens : content
        return .choose(Array(choices.prefix(12)))
    }

    @MainActor
    static func present(_ raw: String, using quickAdd: QuickAddController) {
        switch capture(from: raw) {
        case .word(let word):
            guard let request = try? ExternalCaptureRequest(text: word) else { return }
            quickAdd.show(selection: request)
        case .choose(let words):
            quickAdd.showWordChoices(words)
        case nil:
            return
        }
    }

    @MainActor
    static func focusedSelection() -> String? {
        guard let window = NSApp.keyWindow, isVordWindow(window) else { return nil }
        guard let textView = window.firstResponder as? NSTextView else { return nil }
        return selectedString(in: textView)
    }

    static func selectedString(in textView: NSTextView) -> String? {
        let range = textView.selectedRange()
        let storage = textView.string as NSString
        guard range.location != NSNotFound, range.length > 0, range.location + range.length <= storage.length else { return nil }
        let text = storage.substring(with: range).trimmed
        return text.isEmpty ? nil : text
    }

    static func isVordWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.identifier?.rawValue.hasPrefix("vord.") == true { return true }
        if window.title == "Vord" || window.title.hasPrefix("Vord ") { return true }
        return window === NSApp.mainWindow
    }

    static func englishTokens(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            let token = current.trimmingCharacters(in: CharacterSet(charactersIn: "'-’"))
            if token.contains(where: isLatinLetter) { tokens.append(token) }
            current = ""
        }
        for character in raw {
            if isLatinLetter(character) || character.isNumber || character == "'" || character == "’" || character == "-" {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func isLatinLetter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }
}

@MainActor
final class InAppSelectionMonitor {
    private var observers: [NSObjectProtocol] = []
    private var handler: ((String) -> Void)?

    func start(handler: @escaping (String) -> Void) {
        guard observers.isEmpty else { self.handler = handler; return }
        self.handler = handler
        InAppSelectionMenu.install()
        let observer = NotificationCenter.default.addObserver(
            forName: .vordAddInAppSelection, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let text = note.object as? String else { return }
                self?.handler?(text)
            }
        }
        observers.append(observer)
    }
}

enum InAppSelectionMenu {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        guard let original = class_getInstanceMethod(NSTextView.self, #selector(NSTextView.menu(for:))),
              let replacement = class_getInstanceMethod(NSTextView.self, #selector(NSTextView.vord_menu(for:))) else { return }
        method_exchangeImplementations(original, replacement)
    }
}

extension NSTextView {
    @objc dynamic func vord_menu(for event: NSEvent) -> NSMenu? {
        let menu = vord_menu(for: event)
        guard let menu, InAppSelection.isVordWindow(window), InAppSelection.selectedString(in: self) != nil else { return menu }
        let action = #selector(NSTextView.vordAddSelection(_:))
        guard !menu.items.contains(where: { $0.action == action }) else { return menu }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Add to Library", action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func vordAddSelection(_ sender: Any?) {
        guard let text = InAppSelection.selectedString(in: self) else { return }
        NotificationCenter.default.post(name: .vordAddInAppSelection, object: text)
    }
}
