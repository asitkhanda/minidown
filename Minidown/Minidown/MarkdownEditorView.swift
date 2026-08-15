// minidown — a minimal, distraction-free Markdown writer for macOS.
// Copyright (C) 2026 Asit Khanda
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version. See <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var chrome: ChromeStyle = .solid
    @AppStorage("colorTheme") private var colorThemeID = EditorTheme.minidown.id
    @EnvironmentObject var settings: EditorSettings
    @Environment(\.undoManager) private var undoManager
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue

    private var fontFamily: EditorFontFamily {
        EditorFontFamily(rawValue: fontFamilyRaw) ?? .sansSerif
    }

    func makeCoordinator() -> Coordinator { Coordinator(document: document, settings: settings) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        // Under Liquid Glass the editor must not paint its own surface — an opaque background
        // here would sit on top of the material and defeat it entirely.
        scroll.drawsBackground = !chrome.usesGlass
        scroll.backgroundColor = AppColors.editorBackground(glass: chrome.usesGlass)
        scroll.autohidesScrollers = true

        let contentSize = scroll.contentSize
        let container = NSTextContainer(size: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)

        let layoutManager = CollapsingLayoutManager()
        let storage = NSTextStorage()
        storage.delegate = context.coordinator
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
        textView.drawsBackground = !chrome.usesGlass
        textView.backgroundColor = AppColors.editorBackground(glass: chrome.usesGlass)
        textView.insertionPointColor = AppColors.accent
        textView.selectedTextAttributes = [.backgroundColor: AppColors.selection]
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
        context.coordinator.document = document
        context.coordinator.settings = settings
        context.coordinator.undoManager = undoManager
        context.coordinator.fontFamily = fontFamily
        context.coordinator.colorThemeID = colorThemeID
        context.coordinator.chrome = chrome
        context.coordinator.syncFromStoreIfNeeded()
        context.coordinator.applyTypewriterChrome(force: false)
        context.coordinator.applyStyle(force: false)
        let glass = chrome.usesGlass
        scrollView.drawsBackground = !glass
        scrollView.backgroundColor = AppColors.editorBackground(glass: glass)
        if let textView = scrollView.documentView as? NSTextView {
            textView.drawsBackground = !glass
            textView.backgroundColor = AppColors.editorBackground(glass: glass)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var document: MarkdownDocument
        var settings: EditorSettings
        var undoManager: UndoManager?
        var fontFamily: EditorFontFamily = .sansSerif
        var colorThemeID: String = EditorTheme.minidown.id
        var chrome: ChromeStyle = .solid
        weak var textView: EditorTextView?
        weak var layoutManager: CollapsingLayoutManager?
        weak var scrollView: NSScrollView?

        private let session = LivePreviewSession(parseMode: .background)
        private var applying = false
        private var lastText: String?
        private var lastSelection = NSRange(location: 0, length: 0)
        private var lastTypewriter = false
        private var lastDark: Bool?
        private var lastFontFamily: EditorFontFamily?
        private var lastColorTheme: String?
        private var lastViewportHeight: CGFloat = 0
        /// Set by the text storage delegate, consumed by the next restyle.
        private var pendingEdit: (range: NSRange, delta: Int)?

        init(document: MarkdownDocument, settings: EditorSettings) {
            self.document = document
            self.settings = settings
            super.init()
            // A background parse can change collapse/widget attributes after the fact.
            session.onReconciled = { [weak self] in
                self?.layoutManager?.refreshCollapsedGlyphs()
            }
        }

        // MARK: - NSTextStorageDelegate

        /// Records what an edit touched so the restyle can be narrowed to it.
        ///
        /// Only observes here — attributes are applied later, from `applyStyle`. Writing them
        /// inside `processEditing` would re-enter this callback, and layout invalidation is not
        /// permitted from here at all.
        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                if let existing = pendingEdit {
                    // Coalesce bursts (autocorrect, paste) into one covering range.
                    pendingEdit = (NSUnionRange(existing.range, editedRange), existing.delta + delta)
                } else {
                    pendingEdit = (editedRange, delta)
                }
            }
        }

        func syncFromStoreIfNeeded() {
            guard let textView, !applying else { return }
            // Replacing `string` mid-composition destroys the IME's provisional text.
            guard !textView.hasMarkedText() else { return }
            if textView.string != document.text {
                applying = true
                textView.string = document.text
                applying = false
                // A wholesale document swap invalidates every cached construct range.
                session.invalidate()
                pendingEdit = nil
                lastText = nil
            }
        }

        func applyTypewriterChrome(force: Bool) {
            guard let textView, let scrollView else { return }
            let viewport = scrollView.contentView.bounds.height
            let needs =
                force
                || lastTypewriter != settings.typewriter
                || abs(lastViewportHeight - viewport) > 1
            guard needs else { return }

            // Match Tauri: ~45vh vertical padding while typewriter is on so the caret can sit
            // in the vertical center. textContainerInset.height applies to both top and bottom.
            let pad = settings.typewriter ? max(viewport * 0.45, 160) : 28
            textView.textContainerInset = NSSize(width: 56, height: pad)
            // Track the viewport rather than growing monotonically: the old
            // `max(viewport, textView.minSize.height)` meant shrinking the window left the text
            // view stuck at its largest size, with dead scroll space below the text.
            textView.minSize = NSSize(width: 0, height: viewport)

            let turnedOn = settings.typewriter && (force || !lastTypewriter)
            lastTypewriter = settings.typewriter
            lastViewportHeight = viewport
            if turnedOn {
                DispatchQueue.main.async { [weak self] in
                    self?.centerCaret()
                }
            }
        }

        func applyStyle(force: Bool) {
            guard let textView, let storage = textView.textStorage, let layoutManager else { return }
            // Restyling during IME composition rewrites the marked run's attributes and can abort
            // the composition outright. Wait for it to commit.
            guard !textView.hasMarkedText() else { return }

            let text = textView.string
            let selection = textView.selectedRange()
            let dark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // The drawing code looks widgets up by the same key the styler stored them under.
            layoutManager.isDark = dark
            layoutManager.fontFamily = fontFamily
            layoutManager.documentDirectory = document.directoryURL

            // Focus dimming is a draw-time concern now, so a caret move inside the same paragraph
            // costs one invalidateDisplay rather than a restyle.
            updateFocusRange(text: text, selection: selection, layoutManager: layoutManager)

            // Applying here rather than in the view keeps the store and the restyle in step.
            let themeChanged = ThemeStore.select(id: colorThemeID) || lastColorTheme != colorThemeID
            if themeChanged {
                textView.selectedTextAttributes = [.backgroundColor: AppColors.selection]
                textView.insertionPointColor = AppColors.accent
                textView.backgroundColor = AppColors.editorBackground(glass: self.chrome.usesGlass)
            }

            let textChanged = lastText != text
            let presentationChanged = lastDark != dark || lastFontFamily != fontFamily || themeChanged
            let selectionChanged = lastSelection != selection
            let needs = force || textChanged || presentationChanged || selectionChanged
            guard needs else { return }

            let options = LivePreviewStyler.Options(
                selections: textView.selectedRanges.map(\.rangeValue),
                directoryURL: document.directoryURL,
                isDark: dark,
                fontFamily: fontFamily,
                onNeedsRefresh: { [weak self] in
                    self?.scheduleAsyncRefresh()
                }
            )

            applying = true
            let edit = pendingEdit
            pendingEdit = nil

            if presentationChanged || lastText == nil {
                // Appearance or font affects every run; nothing to narrow.
                session.applyFull(to: storage, text: text, options: options)
            } else if textChanged, let edit {
                session.applyEdit(
                    to: storage,
                    text: text,
                    editedRange: edit.range,
                    changeInLength: edit.delta,
                    options: options
                )
            } else if textChanged {
                session.applyFull(to: storage, text: text, options: options)
            } else {
                session.applySelectionChange(to: storage, text: text, options: options)
            }

            layoutManager.refreshCollapsedGlyphs()
            applying = false

            lastText = text
            lastSelection = selection
            lastDark = dark
            lastFontFamily = fontFamily
            lastColorTheme = colorThemeID
        }

        private func updateFocusRange(
            text: String,
            selection: NSRange,
            layoutManager: CollapsingLayoutManager
        ) {
            guard settings.focusMode else {
                layoutManager.focusRange = nil
                return
            }
            // drawBackground also paints the selection highlight, so dimming a selection that
            // reaches past the focused paragraph reads as a rendering fault. Light everything.
            layoutManager.dimFactor = selection.length > 0 ? 1 : 0.32
            let focus = RevealPolicy.focusRange(in: text, at: selection.location)
            layoutManager.focusRange = NSRange(
                location: focus.from,
                length: max(0, focus.to - focus.from)
            )
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
            // The document buffer is authoritative even mid-composition, so the store still tracks
            // it; only the restyle waits (applyStyle guards on marked text itself).
            document.updateText(textView.string, undoManager: undoManager)
            lastText = nil
            applyStyle(force: true)
            if settings.typewriter, !textView.hasMarkedText() { centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !applying else { return }
            let sel = textView.selectedRange()
            document.updateSelection(location: sel.location, length: sel.length)
            applyStyle(force: false)
        }

        /// Flips a task checkbox, writing `[x]` / `[ ]` straight back into the document.
        ///
        /// The one place rendering is allowed to mutate text, per CONTRIBUTING's round-trip
        /// invariant. Driven by the layout manager's already-computed hit targets rather than
        /// re-parsing the whole document on every mouse-down.
        func toggleTask(_ target: (charRange: NSRange, checked: Bool)) -> Bool {
            guard let textView else { return false }
            guard NSMaxRange(target.charRange) <= (textView.string as NSString).length else { return false }
            let replacement = target.checked ? "[ ]" : "[x]"
            guard textView.shouldChangeText(in: target.charRange, replacementString: replacement) else {
                return false
            }
            textView.replaceCharacters(in: target.charRange, with: replacement)
            textView.didChangeText()
            return true
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
        if let layoutManager = layoutManager as? CollapsingLayoutManager {
            let pointInContainer = NSPoint(
                x: pointInView.x - textContainerOrigin.x,
                y: pointInView.y - textContainerOrigin.y
            )
            if let target = layoutManager.taskTarget(at: pointInContainer),
               let coordinator = delegate as? MarkdownEditorView.Coordinator,
               coordinator.toggleTask(target)
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
