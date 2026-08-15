import AppKit
import XCTest
@testable import Minidown

/// Phase 1 regressions: hiding must be a glyph property, not a colour, and focus mode must not
/// touch the text storage at all.
@MainActor
final class RevealPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    private let blockDoc = """
    | A | B |
    | --- | --- |
    | 1 | 2 |

    $$
    x=1
    $$

    ![alt](https://example.com/a.png)

    ---

    Some **bold** trailing body.
    """

    private func styled(_ doc: String, selection: NSRange) -> NSTextStorage {
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: selection, directoryURL: nil, isDark: true)
        )
        return storage
    }

    // MARK: - Hiding survives colour writes

    /// The headline Phase 1 bug. Widget source, bullets and task markers used to be hidden with
    /// `NSColor.clear`, so *any* later `.foregroundColor` write resurrected them — which is exactly
    /// what focus mode did, painting raw pipe syntax underneath the table drawn on top of it.
    func testHidingSurvivesLaterForegroundColorWrites() {
        let doc = "| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- bullet\n\n- [ ] task"
        let storage = styled(doc, selection: NSRange(location: doc.utf16.count, length: 0))
        let full = NSRange(location: 0, length: storage.length)

        let hiddenBefore = hiddenRanges(in: storage)
        XCTAssertFalse(hiddenBefore.isEmpty, "table source, bullet and task marker should be hidden")

        // Simulate any pass that recolours text — focus mode used to be one of these.
        storage.addAttribute(.foregroundColor, value: NSColor.red, range: full)

        XCTAssertEqual(
            hiddenRanges(in: storage),
            hiddenBefore,
            "hiding must be a glyph property, not a colour — a recolour cannot reveal source"
        )
    }

    /// Nothing may hide by going transparent, or we regress to the same class of bug.
    func testNothingIsHiddenWithClearColor() {
        let storage = styled(blockDoc, selection: NSRange(location: blockDoc.utf16.count, length: 0))
        var offenders: [NSRange] = []
        storage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            if color == .clear || color.alphaComponent == 0 { offenders.append(range) }
        }
        XCTAssertTrue(offenders.isEmpty, "found clear-coloured text at \(offenders)")
    }

    // MARK: - Focus mode is draw-time only

    /// Focus mode must not write attributes. Beyond correctness this is what makes a caret move
    /// cheap: no restyle, no reparse, just an invalidateDisplay.
    func testFocusRangeDoesNotMutateTextStorage() {
        let doc = "para one line\n\npara two line\n\npara three line"
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: 10_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: true)
        )

        let before = attributeSnapshot(storage)
        layout.focusRange = NSRange(location: 15, length: 13)
        layout.focusRange = NSRange(location: 30, length: 15)
        layout.focusRange = nil

        XCTAssertEqual(attributeSnapshot(storage), before, "focus mode must be presentation-only")
    }

    // MARK: - Select-all

    /// ⌘A used to turn the whole document back into raw source, throwing away every widget's
    /// layout. Inline marks still reveal (Tauri parity); block widgets stay rendered.
    func testSelectAllRevealsInlineMarksButKeepsBlockWidgets() {
        let all = NSRange(location: 0, length: blockDoc.utf16.count)

        let widgets = LivePreviewStyler.activeBlockWidgetKinds(in: blockDoc, selection: all)
        for expected in ["table", "blockMath", "image", "hr"] {
            XCTAssertTrue(widgets.contains(expected), "\(expected) should survive select-all, got \(widgets)")
        }

        // Hidden ranges include block-widget source, which is legitimately still hidden here —
        // those widgets are still drawn. Everything outside a widget's span is an inline mark and
        // must have revealed.
        let ns = blockDoc as NSString
        let widgetSpans = [
            ns.range(of: "| A | B |\n| --- | --- |\n| 1 | 2 |"),
            ns.range(of: "$$\nx=1\n$$"),
            ns.range(of: "![alt](https://example.com/a.png)"),
            ns.range(of: "---\n"),
        ]
        let hidden = LivePreviewStyler.hiddenMarkRanges(in: blockDoc, selection: all)
        let inlineHidden = hidden.filter { candidate in
            !widgetSpans.contains { NSIntersectionRange($0, candidate).length > 0 }
        }
        XCTAssertTrue(
            inlineHidden.isEmpty,
            "every inline mark should reveal under select-all, still hidden: \(inlineHidden)"
        )
    }

    /// A selection with an endpoint inside a block *is* editing it, so the widget gives way.
    func testSelectionEndingInsideATableRevealsIt() {
        let tableStart = (blockDoc as NSString).range(of: "| A |").location
        let selection = NSRange(location: 0, length: tableStart + 4)
        let widgets = LivePreviewStyler.activeBlockWidgetKinds(in: blockDoc, selection: selection)
        XCTAssertFalse(widgets.contains("table"), "a selection ending inside the table is editing it")
    }

    // MARK: - Reveal boundaries

    func testInlineRevealIsInclusiveAtBothBoundaries() {
        let doc = "say **bold** now"
        let markRange = NSRange(location: 4, length: 8) // **bold**
        let policy = { (loc: Int) in
            RevealPolicy(selection: NSRange(location: loc, length: 0), text: doc)
        }
        XCTAssertTrue(policy(markRange.location).touchesInline(markRange), "caret at start reveals")
        XCTAssertTrue(policy(NSMaxRange(markRange)).touchesInline(markRange), "caret at end reveals")
        XCTAssertTrue(policy(markRange.location + 3).touchesInline(markRange), "caret inside reveals")
        XCTAssertFalse(policy(NSMaxRange(markRange) + 2).touchesInline(markRange), "caret past does not")
        XCTAssertFalse(policy(markRange.location - 2).touchesInline(markRange), "caret before does not")
    }

    /// The first Swift port looked at a single selection, silently dropping multi-cursor reveal.
    func testMultipleCursorsEachRevealTheirOwnConstruct() {
        let doc = "**one** plain **two**"
        let first = NSRange(location: 0, length: 7)
        let second = NSRange(location: 14, length: 7)
        let policy = RevealPolicy(
            selections: [
                NSRange(location: 2, length: 0),
                NSRange(location: 16, length: 0),
            ],
            text: doc
        )
        XCTAssertTrue(policy.touchesInline(first))
        XCTAssertTrue(policy.touchesInline(second))

        let single = RevealPolicy(selection: NSRange(location: 2, length: 0), text: doc)
        XCTAssertFalse(single.touchesInline(second), "control: one cursor reveals only its own span")
    }

    func testCaretTouchingABlockCountsAsEditingIt() {
        let table = NSRange(location: 0, length: 30)
        let doc = String(repeating: "x", length: 60)
        XCTAssertTrue(
            RevealPolicy(selection: NSRange(location: 10, length: 0), text: doc).isEditing(table)
        )
        XCTAssertFalse(
            RevealPolicy(selection: NSRange(location: 45, length: 0), text: doc).isEditing(table)
        )
    }

    // MARK: - Helpers

    private func hiddenRanges(in storage: NSTextStorage) -> [NSRange] {
        var out: [NSRange] = []
        storage.enumerateAttribute(
            .mdHidden,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            if value as? Bool == true { out.append(range) }
        }
        return out
    }

    private func attributeSnapshot(_ storage: NSTextStorage) -> String {
        var parts: [String] = []
        storage.enumerateAttributes(
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { attrs, range, _ in
            let keys = attrs.keys.map(\.rawValue).sorted().joined(separator: ",")
            let color = (attrs[.foregroundColor] as? NSColor)?.description ?? "-"
            parts.append("\(range.location):\(range.length):\(keys):\(color)")
        }
        return parts.joined(separator: "|")
    }
}

private extension String {
    init(repeating character: String, length: Int) {
        self = String(repeating: character, count: length)
    }
}
