import AppKit
import SwiftUI

/// Native selectable reading text: select one English word, or right-click a word,
/// to read its dictionary entry and explicitly add it to the library.
struct DictionaryText: NSViewRepresentable {
    var text: String
    var translation: TranslationService
    var repository: any VocabularyRepository
    var fontSize: CGFloat = 15
    var lineSpacing: CGFloat = 4
    var color: Color = AppColors.primaryText
    var alignment: NSTextAlignment = .left
    var highlightWord: String?

    init(_ text: String, translation: TranslationService, repository: any VocabularyRepository,
         fontSize: CGFloat = 15, lineSpacing: CGFloat = 4, color: Color = AppColors.primaryText,
         alignment: NSTextAlignment = .left, highlightWord: String? = nil) {
        self.text = text; self.translation = translation; self.repository = repository
        self.fontSize = fontSize; self.lineSpacing = lineSpacing; self.color = color
        self.alignment = alignment; self.highlightWord = highlightWord
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> DictionaryNSTextView {
        let view = DictionaryNSTextView()
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setAccessibilityHelp("Select an English word to see its meaning. Press Return to look up a keyboard selection.")
        view.onLookup = { [weak coordinator = context.coordinator, weak view] range in
            guard let view else { return }
            coordinator?.show(range: range, in: view)
        }
        return view
    }

    func updateNSView(_ view: DictionaryNSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text { context.coordinator.close(); view.setSelectedRange(NSRange(location: 0, length: 0)) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing; paragraph.alignment = alignment
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: AppTypography.nativeUI(size: fontSize), .foregroundColor: NSColor(color), .paragraphStyle: paragraph
        ])
        if let highlightWord {
            for range in ContextGenerator.wordRanges(in: text, word: highlightWord) {
                attributed.addAttributes([.font: AppTypography.nativeUI(size: fontSize, weight: .semibold),
                    .foregroundColor: NSColor(AppColors.accent)], range: NSRange(range, in: text))
            }
        }
        if view.textStorage?.isEqual(to: attributed) != true {
            let selected = view.selectedRange()
            view.textStorage?.setAttributedString(attributed)
            if NSMaxRange(selected) <= attributed.length { view.setSelectedRange(selected) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DictionaryNSTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 500)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: max(fontSize + lineSpacing, ceil(manager.usedRect(for: container).height)))
    }

    static func dismantleNSView(_ view: DictionaryNSTextView, coordinator: Coordinator) {
        view.onLookup = nil
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var parent: DictionaryText
        let model: DictionarySelectionModel
        private var popover: NSPopover?
        private var task: Task<Void, Never>?
        init(_ parent: DictionaryText) {
            self.parent = parent
            model = DictionarySelectionModel(translation: parent.translation, repository: parent.repository)
        }

        func show(range: NSRange, in view: DictionaryNSTextView) {
            guard let word = DictionarySelection.word(in: view.string, selected: range),
                  let manager = view.layoutManager, let container = view.textContainer, view.window != nil else { return }
            close()
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += view.textContainerOrigin.x
            rect.origin.y += view.textContainerOrigin.y
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.delegate = self
            let content = DictionaryEntryPopover(model: model, retry: { [weak self, weak view] in
                guard let view else { return }
                self?.load(word: word, sentence: view.string)
            })
            popover.contentViewController = NSHostingController(rootView: content)
            popover.contentSize = NSSize(width: 340, height: 300)
            self.popover = popover
            load(word: word, sentence: view.string)
            // NSPopover handles screen edges and scrolling anchors. No app activation is needed.
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.identifier = NSUserInterfaceItemIdentifier("vord.dictionaryPopover")
        }

        private func load(word: String, sentence: String) {
            task?.cancel()
            task = Task { [weak self] in await self?.model.lookup(word: word, sentence: sentence) }
        }
        func close() {
            task?.cancel(); task = nil; model.dismiss()
            popover?.close(); popover = nil
        }
        func popoverDidClose(_ notification: Notification) {
            guard notification.object as? NSPopover === popover else { return }
            task?.cancel(); task = nil; model.dismiss(); popover = nil
        }
    }
}

/// Public within the app so review keyboard shortcuts can respect reading selections.
final class DictionaryNSTextView: NSTextView {
    var onLookup: ((NSRange) -> Void)?
    override func mouseDown(with event: NSEvent) {
        // NSTextView tracks the drag through mouse-up inside super.mouseDown.
        super.mouseDown(with: event)
        let range = selectedRange()
        if DictionarySelection.word(in: string, selected: range) != nil { onLookup?(range) }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let range = rangeUnderMouse(event) else { super.rightMouseDown(with: event); return }
        setSelectedRange(range)
        onLookup?(range)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76,
           DictionarySelection.word(in: string, selected: selectedRange()) != nil {
            onLookup?(selectedRange()); return
        }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        if let range = rangeUnderMouse(event) { setSelectedRange(range) }
        let menu = super.menu(for: event) ?? NSMenu()
        if DictionarySelection.word(in: string, selected: selectedRange()) != nil {
            let item = NSMenuItem(title: "Meaning and Add to Vord", action: #selector(lookupSelection(_:)), keyEquivalent: "")
            item.target = self
            menu.insertItem(.separator(), at: 0); menu.insertItem(item, at: 0)
        }
        return menu
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard DictionarySelection.word(in: string, selected: selectedRange()) != nil else {
            return super.accessibilityPerformShowMenu()
        }
        onLookup?(selectedRange()); return true
    }
    @objc private func lookupSelection(_ sender: Any?) { onLookup?(selectedRange()) }

    private func rangeUnderMouse(_ event: NSEvent) -> NSRange? {
        guard let manager = layoutManager, let container = textContainer, !string.isEmpty else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x; point.y -= textContainerOrigin.y
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                .insetBy(dx: 2, dy: 2).contains(point) else { return nil }
        return DictionarySelection.wordRange(in: string, atUTF16: manager.characterIndexForGlyph(at: glyph))
    }
}

private struct DictionaryEntryPopover: View {
    @ObservedObject var model: DictionarySelectionModel
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.result?.english ?? model.word).font(AppTypography.ui(size: 22, weight: .semibold)).lineLimit(1)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let result = model.result {
                        if let phonetic = result.phonetic { Text(phonetic).foregroundStyle(AppColors.secondaryText) }
                        Text(result.chinese).font(AppTypography.ui(size: 17)).textSelection(.enabled)
                        if let english = result.englishDefinition, !english.isEmpty {
                            Text(english).font(AppTypography.body).foregroundStyle(AppColors.secondaryText).textSelection(.enabled)
                        }
                        if let provider = result.providerName {
                            Text(provider).font(AppTypography.tertiary).foregroundStyle(AppColors.tertiaryText)
                        }
                    }
                    ForEach(model.candidates, id: \.english) { candidate in
                        Button { Task { await model.choose(candidate) } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.english).font(AppTypography.headline)
                                Text(candidate.chinese).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }.buttonStyle(.plain)
                        Hairline()
                    }
                    if let error = model.error {
                        Text(error).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                        QuietButton(title: "Try again", action: retry)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
            }
            HStack {
                Text(model.saved ? "Added" : model.inLibrary ? "Already in your library" : "Dictionary lookup")
                    .font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                Spacer()
                PrimaryButton(title: model.isSaving ? "Adding…" : "Add word") { Task { await model.add() } }
                    .disabled(model.result == nil || model.isLoading || model.isSaving || model.inLibrary)
            }
        }.padding(18).frame(width: 340, height: 300)
            .foregroundStyle(AppColors.primaryText).background(AppColors.contentBackground)
    }
}
