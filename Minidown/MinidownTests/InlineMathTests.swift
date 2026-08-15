import AppKit
import XCTest
@testable import Minidown

/// Phase 4b spike: inline `$…$` must flow inside a sentence.
///
/// The previous implementation routed inline math through the *block* widget path, which forces a
/// line height with `.paragraphStyle`. AppKit fixes paragraph styles across whole paragraphs, so a
/// single `$x$` clamped every line of its paragraph to the formula's height. That is an entirely
/// separate cause from the oversized snapshots, and fixing the snapshot alone would not have
/// helped.
@MainActor
final class InlineMathTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = true
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = false
        super.tearDown()
    }

    private func makeEditor(_ doc: String, width: CGFloat = 600) -> (NSTextView, CollapsingLayoutManager) {
        let container = NSTextContainer(size: NSSize(width: width, height: 100_000))
        container.widthTracksTextView = true
        let layout = CollapsingLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 600), textContainer: container)
        textView.backgroundColor = AppColors.background
        textView.string = doc

        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: doc.utf16.count, length: 0), isDark: false)
        )
        layout.refreshCollapsedGlyphs()
        layout.ensureLayout(for: container)
        return (textView, layout)
    }

    /// Warm the render cache so sizing reflects a real formula, not the placeholder.
    private func renderMath(_ tex: String, display: Bool) {
        let done = expectation(description: "katex \(tex)")
        WebBlockRenderer.shared.renderKatex(tex: tex, display: display, dark: false) { _ in done.fulfill() }
        wait(for: [done], timeout: 20)
    }

    private func lineHeights(_ layout: CollapsingLayoutManager, upTo length: Int) -> [CGFloat] {
        var heights: [CGFloat] = []
        var glyph = 0
        while glyph < layout.numberOfGlyphs {
            var effective = NSRange()
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            heights.append(rect.height)
            glyph = NSMaxRange(effective)
            if effective.length == 0 { break }
        }
        return heights
    }

    /// The headline check: a formula mid-paragraph must not inflate the paragraph's other lines.
    func testInlineMathDoesNotInflateSurroundingLines() {
        renderMath("x^2", display: false)

        let plain = """
        This is a long paragraph of prose that will certainly wrap across several lines in the \
        text container so that we have something to compare against, and it continues here.
        """
        let withMath = """
        This is a long paragraph of prose that will certainly wrap across several lines in the \
        text container so that we have $x^2$ to compare against, and it continues here.
        """

        let (_, plainLayout) = makeEditor(plain)
        let (_, mathLayout) = makeEditor(withMath)

        let plainHeights = lineHeights(plainLayout, upTo: plain.utf16.count)
        let mathHeights = lineHeights(mathLayout, upTo: withMath.utf16.count)

        XCTAssertFalse(plainHeights.isEmpty)
        XCTAssertFalse(mathHeights.isEmpty)

        let plainTypical = plainHeights.min() ?? 0
        // Every line except the one hosting the formula should match the plain paragraph.
        let unaffected = mathHeights.filter { abs($0 - plainTypical) < 0.5 }
        XCTAssertGreaterThanOrEqual(
            unaffected.count,
            mathHeights.count - 1,
            "only the line containing the formula may change height; got \(mathHeights) vs \(plainHeights)"
        )
    }

    /// Guards the regression the oversized-snapshot bug produced: a ~500pt tall line for one glyph.
    func testInlineMathLineStaysCloseToBodyHeight() {
        renderMath("x", display: false)
        let (_, layout) = makeEditor("Some prose with $x$ inside a sentence that keeps going.")
        let heights = lineHeights(layout, upTo: 0)
        let tallest = heights.max() ?? 0
        XCTAssertLessThan(tallest, LivePreviewStyler.bodyFontSize * 3, "inline math blew up the line: \(heights)")
        XCTAssertGreaterThan(tallest, 4)
    }

    /// A wide formula must be capped to the space left on the line rather than run off the edge —
    /// `.whitespace` control glyphs are elastic and will not wrap on their own.
    func testWideInlineMathIsCappedToTheContainer() {
        let wide = #"\sum_{i=0}^{n} \frac{a_i + b_i}{c_i} \cdot \sqrt{x_i^2 + y_i^2}"#
        renderMath(wide, display: false)

        let width: CGFloat = 400
        let (_, layout) = makeEditor("Prefix text $\(wide)$ suffix.", width: width)
        layout.ensureLayout(for: layout.textContainers[0])

        var glyph = 0
        while glyph < layout.numberOfGlyphs {
            var effective = NSRange()
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            let used = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            XCTAssertLessThanOrEqual(
                used.maxX,
                width + 1,
                "content ran past the container edge: \(used) in \(rect)"
            )
            glyph = NSMaxRange(effective)
            if effective.length == 0 { break }
        }
    }

    /// Display math keeps the block treatment — it owns its line by design.
    func testDisplayMathStillUsesTheBlockPath() {
        let doc = "before\n\n$$\nx = 1\n$$\n\nafter"
        let storage = NSTextStorage(string: doc)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )
        let mathStart = (doc as NSString).range(of: "$$").location
        XCTAssertNotNil(
            storage.attribute(.mdBlockWidget, at: mathStart, effectiveRange: nil),
            "display math should be a block widget"
        )
        XCTAssertNil(
            storage.attribute(.mdInlineWidget, at: mathStart, effectiveRange: nil),
            "display math should not be an inline widget"
        )
    }

    /// Renders a paragraph containing inline math so a human can confirm it sits on the baseline.
    func testRenderInlineMathForInspection() {
        renderMath("e^{i\\pi} + 1 = 0", display: false)
        let doc = "Euler's identity $e^{i\\pi} + 1 = 0$ sits inside this sentence and the text "
            + "continues afterwards so wrapping and baseline alignment are both visible here."
        let (textView, _) = makeEditor(doc, width: 560)
        textView.layoutSubtreeIfNeeded()
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        guard let directory = ProcessInfo.processInfo.environment["MINIDOWN_RENDER_DUMP"],
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("inline-math.png"))
    }

    func testInlineMathUsesTheInlinePath() {
        let doc = "prose with $a+b$ inside"
        let storage = NSTextStorage(string: doc)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )
        let mathStart = (doc as NSString).range(of: "$a+b$").location
        XCTAssertNotNil(
            storage.attribute(.mdInlineWidget, at: mathStart, effectiveRange: nil),
            "inline math should be an inline widget"
        )
        // Crucially: no paragraph-style line-height forcing, which AppKit would spread across the
        // whole paragraph.
        XCTAssertNil(
            storage.attribute(.mdBlockWidget, at: mathStart, effectiveRange: nil),
            "inline math must not take the block path"
        )
    }
}
