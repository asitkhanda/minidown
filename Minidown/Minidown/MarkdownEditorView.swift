import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @EnvironmentObject var store: DocumentStore
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue

    private var fontFamily: EditorFontFamily {
        EditorFontFamily(rawValue: fontFamilyRaw) ?? .sansSerif
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = AppColors.background
        scroll.autohidesScrollers = true

        let contentSize = scroll.contentSize
        let container = NSTextContainer(size: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)

        let layoutManager = CollapsingLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = AppColors.background
        textView.insertionPointColor = AppColors.accent
        textView.selectedTextAttributes = [
            .backgroundColor: AppColors.accent.withAlphaComponent(0.22)
        ]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 56, height: 28)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: contentSize.height)

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.layoutManager = layoutManager
        context.coordinator.scrollView = scroll
        context.coordinator.fontFamily = fontFamily
        context.coordinator.applyTypewriterChrome(force: true)
        context.coordinator.applyStyle(force: true)
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.store = store
        context.coordinator.fontFamily = fontFamily
        context.coordinator.syncFromStoreIfNeeded()
        context.coordinator.applyTypewriterChrome(force: false)
        context.coordinator.applyStyle(force: false)
        scrollView.backgroundColor = AppColors.background
        (scrollView.documentView as? NSTextView)?.backgroundColor = AppColors.background
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var store: DocumentStore
        var fontFamily: EditorFontFamily = .sansSerif
        weak var textView: EditorTextView?
        weak var layoutManager: CollapsingLayoutManager?
        weak var scrollView: NSScrollView?

        private var applying = false
        private var lastText: String?
        private var lastSelection = NSRange(location: 0, length: 0)
        private var lastFocus = false
        private var lastTypewriter = false
        private var lastDark: Bool?
        private var lastFontFamily: EditorFontFamily?
        private var lastViewportHeight: CGFloat = 0

        init(store: DocumentStore) {
            self.store = store
        }

        func syncFromStoreIfNeeded() {
            guard let textView, !applying else { return }
            if textView.string != store.text {
                applying = true
                textView.string = store.text
                applying = false
                lastText = nil
            }
        }

        func applyTypewriterChrome(force: Bool) {
            guard let textView, let scrollView else { return }
            let viewport = scrollView.contentView.bounds.height
            let needs =
                force
                || lastTypewriter != store.typewriter
                || abs(lastViewportHeight - viewport) > 1
            guard needs else { return }

            // Match Tauri: ~45vh vertical padding while typewriter is on so the caret can sit
            // in the vertical center. textContainerInset.height applies to both top and bottom.
            let pad = store.typewriter ? max(viewport * 0.45, 160) : 28
            textView.textContainerInset = NSSize(width: 56, height: pad)
            textView.minSize = NSSize(width: 0, height: max(viewport, textView.minSize.height))

            let turnedOn = store.typewriter && (force || !lastTypewriter)
            lastTypewriter = store.typewriter
            lastViewportHeight = viewport
            if turnedOn {
                DispatchQueue.main.async { [weak self] in
                    self?.centerCaret()
                }
            }
        }

        func applyStyle(force: Bool) {
            guard let textView, let storage = textView.textStorage, let layoutManager else { return }
            let text = textView.string
            let selection = textView.selectedRange()
            let dark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let needs =
                force
                || lastText != text
                || lastSelection != selection
                || lastFocus != store.focusMode
                || lastDark != dark
                || lastFontFamily != fontFamily
            guard needs else { return }

            applying = true
            let selected = textView.selectedRange()
            LivePreviewStyler.apply(
                to: storage,
                text: text,
                options: .init(
                    selection: selection,
                    focusMode: store.focusMode,
                    directoryURL: store.directoryURL,
                    isDark: dark,
                    fontFamily: fontFamily,
                    onNeedsRefresh: { [weak self] in
                        self?.scheduleAsyncRefresh()
                    }
                )
            )
            layoutManager.refreshCollapsedGlyphs()
            let maxLoc = textView.string.utf16.count
            let loc = min(selected.location, maxLoc)
            let len = min(selected.length, max(0, maxLoc - loc))
            textView.setSelectedRange(NSRange(location: loc, length: len))
            applying = false

            lastText = text
            lastSelection = selection
            lastFocus = store.focusMode
            lastDark = dark
            lastFontFamily = fontFamily
        }

        private var asyncRefreshWork: DispatchWorkItem?

        private func scheduleAsyncRefresh() {
            asyncRefreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastText = nil
                self.applyStyle(force: true)
            }
            asyncRefreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !applying else { return }
            store.updateText(textView.string)
            lastText = nil
            applyStyle(force: true)
            if store.typewriter { centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !applying else { return }
            let sel = textView.selectedRange()
            store.updateSelection(location: sel.location, length: sel.length)
            applyStyle(force: false)
        }

        func handleClick(at characterIndex: Int) -> Bool {
            guard let textView else { return false }
            let text = textView.string
            for c in MarkdownParser.parse(text) {
                if case .taskMarker(let checked) = c.kind,
                   characterIndex >= c.from, characterIndex < c.to
                {
                    let replacement = checked ? "[ ]" : "[x]"
                    let range = NSRange(location: c.from, length: 3)
                    if textView.shouldChangeText(in: range, replacementString: replacement) {
                        textView.replaceCharacters(in: range, with: replacement)
                        textView.didChangeText()
                    }
                    return true
                }
            }
            return false
        }

        func centerCaret() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
                  let scrollView
            else { return }
            let sel = textView.selectedRange()
            layoutManager.ensureLayout(for: container)
            let utf16Count = textView.string.utf16.count
            guard utf16Count > 0 else { return }
            let idx = min(sel.location, utf16Count - 1)
            let glyph = layoutManager.glyphIndexForCharacter(at: idx)
            var rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1),
                in: container
            )
            let origin = textView.textContainerOrigin
            rect = rect.offsetBy(dx: origin.x, dy: origin.y)

            let visible = scrollView.contentView.bounds
            let targetY = rect.midY - visible.height / 2
            let maxY = max(0, textView.bounds.height - visible.height)
            let y = min(max(0, targetY), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: visible.origin.x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

final class EditorTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        if let layoutManager = layoutManager as? CollapsingLayoutManager, let textContainer {
            let pointInContainer = NSPoint(
                x: pointInView.x - textContainerOrigin.x,
                y: pointInView.y - textContainerOrigin.y
            )
            let idx = layoutManager.characterIndexForInteraction(at: pointInContainer, fraction: nil)
            if let coordinator = delegate as? MarkdownEditorView.Coordinator,
               coordinator.handleClick(at: idx)
            {
                return
            }
        }
        super.mouseDown(with: event)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }
}
