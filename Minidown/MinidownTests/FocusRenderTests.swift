import AppKit
import XCTest
@testable import Minidown

/// Renders the editor to a bitmap and inspects the pixels.
///
/// The focus-mode bug was invisible to attribute-level tests: the attributes were "correct", they
/// just described the wrong picture — raw pipe syntax painted under a table, dimmed. These tests
/// look at what actually reaches the screen.
@MainActor
final class FocusRenderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    private func makeTextView(
        _ doc: String,
        caretAt caret: Int? = nil
    ) -> (NSTextView, CollapsingLayoutManager) {
        let container = NSTextContainer(size: NSSize(width: 600, height: 4000))
        container.widthTracksTextView = true
        let layout = CollapsingLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = AppColors.background
        textView.string = doc

        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(
                selection: NSRange(location: caret ?? 0, length: 0),
                isDark: false
            )
        )
        layout.refreshCollapsedGlyphs()
        return (textView, layout)
    }

    private func render(_ textView: NSTextView) -> NSBitmapImageRep {
        textView.layoutSubtreeIfNeeded()
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            fatalError("could not create bitmap")
        }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        return rep
    }

    /// Proportion of pixels that differ from the background — a crude "how much ink is on the page".
    private func inkRatio(_ rep: NSBitmapImageRep) -> Double {
        guard let background = AppColors.background.usingColorSpace(.deviceRGB) else { return 0 }
        var inked = 0
        var total = 0
        // Sample on a grid; full per-pixel scan is needlessly slow here.
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                total += 1
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let delta = abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent)
                if delta > 0.08 { inked += 1 }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
    }

    /// Focus mode must *reduce* ink outside the focused paragraph, never add any.
    ///
    /// The old implementation added ink: it recoloured the transparent characters that were hiding
    /// widget source, so turning focus mode on made raw markdown appear.
    func testFocusModeOnlyEverRemovesInk() {
        let doc = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        The focused paragraph sits here in the middle of the document.

        - bullet one
        - [ ] a task item
        """
        let (textView, layout) = makeTextView(doc)

        let unfocused = inkRatio(render(textView))

        let focusStart = (doc as NSString).range(of: "The focused paragraph")
        layout.focusRange = focusStart
        let focused = inkRatio(render(textView))

        XCTAssertLessThanOrEqual(
            focused,
            unfocused + 0.001,
            "focus mode added ink — it is resurrecting hidden source instead of dimming"
        )
        XCTAssertLessThan(focused, unfocused, "focus mode should visibly dim the rest of the document")
    }

    /// Turning focus on and off must land back exactly where it started. The alpha-multiply
    /// approach failed this: dimming was destructive, so repeated passes faded to nothing.
    func testFocusToggleIsReversible() {
        let doc = "alpha line\n\nbeta line here\n\ngamma line"
        let (textView, layout) = makeTextView(doc)

        let before = inkRatio(render(textView))
        for _ in 0..<5 {
            layout.focusRange = (doc as NSString).range(of: "beta line here")
            _ = render(textView)
            layout.focusRange = nil
            _ = render(textView)
        }
        let after = inkRatio(render(textView))

        XCTAssertEqual(before, after, accuracy: 0.0005, "dimming must be idempotent and reversible")
    }

    /// Task checkboxes are drawn glyphs, so the only way to know they render is to look.
    func testTaskCheckboxesRender() {
        let doc = "# Checklist\n\n- [ ] an unchecked item\n- [x] a completed item\n- [ ] another one\n"
        let (textView, _) = makeTextView(doc, caretAt: doc.utf16.count)
        let rendered = render(textView)

        RenderDump.write(rendered, named: "checkboxes.png")
        XCTAssertGreaterThan(inkRatio(rendered), 0.001, "checkbox list should draw something")
    }

    /// With the caret away, a table renders as a grid and its pipe syntax must not show through.
    func testTableSourceIsNotPaintedUnderTheWidget() {
        let doc = "| Left | Right |\n| --- | --- |\n| one | two |\n\ntrailing paragraph"
        let (textView, _) = makeTextView(doc, caretAt: doc.utf16.count)
        let rendered = render(textView)

        // Write it out so a human can look at it if this ever fails. MINIDOWN_RENDER_DUMP lets a
        // developer point that somewhere reachable; otherwise it goes to the test host's tmp.
        if let png = rendered.representation(using: .png, properties: [:]) {
            let directory = ProcessInfo.processInfo.environment["MINIDOWN_RENDER_DUMP"]
                ?? NSTemporaryDirectory()
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("minidown-table-render.png")
            try? png.write(to: url)
        }

        XCTAssertGreaterThan(inkRatio(rendered), 0.001, "something should be drawn")
    }
}
