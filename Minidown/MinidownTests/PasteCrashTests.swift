import AppKit
import XCTest
@testable import Minidown

/// Regression: pasting example docs that contain math/mermaid used to crash with
/// `NSInvalidArgumentException: Invalid top-level type in JSON write` inside
/// `WebBlockRenderer.jsonEscape`, because `JSONSerialization` rejects a bare
/// String unless `.fragmentsAllowed` is set.
@MainActor
final class PasteCrashTests: XCTestCase {
    func testJsonEscapeAllowsStringFragments() {
        // Crash was synchronous inside renderKatex → jsonEscape, before any network I/O.
        WebBlockRenderer.isEnabled = true
        defer { WebBlockRenderer.isEnabled = false }

        XCTAssertNoThrow(
            WebBlockRenderer.shared.renderKatex(
                tex: #"e^{i\pi} + 1 = 0"#,
                display: false,
                dark: true,
                completion: { _ in }
            )
        )
        XCTAssertNoThrow(
            WebBlockRenderer.shared.renderMermaid(
                source: "graph TD; A-->B",
                dark: true,
                completion: { _ in }
            )
        )
    }

    func testPasteTortureAndExtendedWithWebRenderer() throws {
        WebBlockRenderer.isEnabled = true
        defer { WebBlockRenderer.isEnabled = false }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("examples")

        for name in ["04-torture-test.md", "06-extended.md"] {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            let storage = NSTextStorage(string: text)
            let layout = CollapsingLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 640, height: 10_000))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)

            XCTAssertNoThrow(
                LivePreviewStyler.apply(
                    to: storage,
                    text: text,
                    options: .init(
                        selection: NSRange(location: text.utf16.count, length: 0),
                        focusMode: false,
                        directoryURL: nil,
                        isDark: true
                    )
                ),
                name
            )
            XCTAssertNoThrow(layout.refreshCollapsedGlyphs(), name)
        }
    }
}
