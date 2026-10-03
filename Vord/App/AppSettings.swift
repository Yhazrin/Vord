import Foundation

struct QuickAddShortcut: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var keyCode: UInt32
    var modifiers: UInt32

    static let optionSpace = QuickAddShortcut(id: "option-space", title: "⌥ Space", keyCode: 49, modifiers: 1 << 11)
    static let optionShiftSpace = QuickAddShortcut(
        id: "option-shift-space",
        title: "⌥ ⇧ Space",
        keyCode: 49,
        modifiers: (1 << 11) | (1 << 9)
    )
    static let controlOptionSpace = QuickAddShortcut(
        id: "control-option-space",
        title: "⌃ ⌥ Space",
        keyCode: 49,
        modifiers: (1 << 12) | (1 << 11)
    )
    static let all = [optionSpace, optionShiftSpace, controlOptionSpace]

    static func from(id: String) -> QuickAddShortcut {
        all.first { $0.id == id } ?? .optionSpace
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var reviewMode: ReviewMode
    @Published private(set) var dictationMode: DictationMode
    @Published private(set) var dictationCount: Int
    @Published private(set) var translationProviderID: String
    @Published private(set) var shortcut: QuickAddShortcut
    @Published private(set) var clipboardCaptureEnabled: Bool
    @Published private(set) var floatingQuickAddEnabled: Bool
    @Published private(set) var navigationIconStyle: NavigationIconStyle
    @Published private(set) var navigationIconSize: Double
    static let navigationIconSizeRange = 12.0...36.0
    @Published private(set) var woodGrainEnabled: Bool
    @Published var hotKeyWarning: String?
    @Published var loginWarning: String?

    private let defaults: UserDefaults
    private let translation: TranslationService

    init(defaults: UserDefaults = .standard, translation: TranslationService) {
        self.defaults = defaults
        self.translation = translation
        let mode = ReviewMode(rawValue: defaults.string(forKey: Key.reviewMode) ?? "") ?? .mixed
        let dictation = DictationMode(rawValue: defaults.string(forKey: Key.dictationMode) ?? "") ?? .chineseToEnglish
        let storedCount = defaults.integer(forKey: Key.dictationCount)
        let provider = defaults.string(forKey: Key.provider) ?? "apple"
        let shortcutID = defaults.string(forKey: Key.shortcut) ?? QuickAddShortcut.optionSpace.id
        reviewMode = mode
        dictationMode = dictation
        dictationCount = storedCount == 0 ? 10 : min(max(storedCount, 1), 100)
        translationProviderID = provider
        shortcut = QuickAddShortcut.from(id: shortcutID)
        clipboardCaptureEnabled = defaults.bool(forKey: Key.clipboardCapture)
        floatingQuickAddEnabled = defaults.object(forKey: Key.floatingQuickAdd) == nil
            ? true : defaults.bool(forKey: Key.floatingQuickAdd)
        navigationIconStyle = NavigationIconStyle(rawValue: defaults.string(forKey: Key.navigationIconStyle) ?? "") ?? .sculpted
        let storedIconSize = defaults.object(forKey: Key.navigationIconSize) as? Double ?? 18
        navigationIconSize = Self.clampedIconSize(storedIconSize)
        woodGrainEnabled = defaults.bool(forKey: Key.woodGrain)
        translation.select(id: provider)
    }

    func setReviewMode(_ mode: ReviewMode) {
        reviewMode = mode
        defaults.set(mode.rawValue, forKey: Key.reviewMode)
    }

    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
        defaults.set(mode.rawValue, forKey: Key.dictationMode)
    }

    func setDictationCount(_ count: Int) {
        let clamped = min(max(count, 1), 100)
        dictationCount = clamped
        defaults.set(clamped, forKey: Key.dictationCount)
    }

    func setTranslationProvider(_ id: String) {
        translationProviderID = id
        defaults.set(id, forKey: Key.provider)
        translation.select(id: id)
    }

    func setShortcut(_ shortcut: QuickAddShortcut) {
        self.shortcut = shortcut
        defaults.set(shortcut.id, forKey: Key.shortcut)
    }

    func setClipboardCaptureEnabled(_ enabled: Bool) {
        clipboardCaptureEnabled = enabled
        defaults.set(enabled, forKey: Key.clipboardCapture)
    }

    func setFloatingQuickAddEnabled(_ enabled: Bool) {
        floatingQuickAddEnabled = enabled
        defaults.set(enabled, forKey: Key.floatingQuickAdd)
    }

    func setNavigationIconStyle(_ style: NavigationIconStyle) {
        navigationIconStyle = style
        defaults.set(style.rawValue, forKey: Key.navigationIconStyle)
    }

    func setNavigationIconSize(_ size: Double) {
        navigationIconSize = Self.clampedIconSize(size)
        defaults.set(navigationIconSize, forKey: Key.navigationIconSize)
    }

    private static func clampedIconSize(_ size: Double) -> Double {
        size.isFinite ? min(navigationIconSizeRange.upperBound, max(navigationIconSizeRange.lowerBound, size)) : 18
    }

    func setWoodGrainEnabled(_ enabled: Bool) {
        woodGrainEnabled = enabled
        defaults.set(enabled, forKey: Key.woodGrain)
    }

    var providerOptions: [(id: String, name: String)] {
        translation.options()
    }

    private enum Key {
        static let reviewMode = "reviewMode"
        static let dictationMode = "dictationMode"
        static let dictationCount = "dictationCount"
        static let provider = "translationProviderID"
        static let shortcut = "quickAddShortcut"
        static let clipboardCapture = "clipboardCaptureEnabled"
        static let floatingQuickAdd = "floatingQuickAddEnabled"
        static let navigationIconStyle = "navigationIconStyle"
        static let navigationIconSize = "appearance.navigationIconSize"
        static let woodGrain = "appearance.woodGrain"
    }
}
