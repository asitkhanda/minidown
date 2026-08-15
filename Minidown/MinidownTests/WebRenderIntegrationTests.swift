import AppKit
import XCTest
@testable import Minidown

/// Exercises the real WebKit path with the bundled assets — no network.
///
/// The previous implementation produced ~900×640 bitmaps for a one-character formula and could
/// return blank images because its web view was never in a window. Both failures were invisible to
/// the rest of the suite, which stubbed the renderer out entirely.
@MainActor
final class WebRenderIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = true
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = false
        super.tearDown()
    }

    private func dump(_ image: NSImage, named name: String) {
        guard let directory = ProcessInfo.processInfo.environment["MINIDOWN_RENDER_DUMP"],
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    func testBundledAssetsArePresent() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("WebAssets"))
        let fileManager = FileManager.default
        for relative in ["katex/katex.min.js", "katex/katex.min.css", "mermaid/mermaid.min.js"] {
            XCTAssertTrue(
                fileManager.fileExists(atPath: resources.appendingPathComponent(relative).path),
                "\(relative) must ship in the bundle so rendering works offline"
            )
        }
        let fonts = try fileManager.contentsOfDirectory(
            atPath: resources.appendingPathComponent("katex/fonts").path
        )
        XCTAssertGreaterThan(fonts.count, 10, "KaTeX needs its webfonts to lay out correctly")
    }

    func testInlineMathRendersAtFormulaSizeNotViewportSize() {
        let done = expectation(description: "katex")
        var rendered: NSImage?
        WebBlockRenderer.shared.renderKatex(tex: "x", display: false, dark: false) { image in
            rendered = image
            done.fulfill()
        }
        wait(for: [done], timeout: 20)

        let image = try? XCTUnwrap(rendered)
        guard let image else { return }
        dump(image, named: "katex-inline.png")

        // The bug: every formula came back as the whole 900×640 viewport.
        XCTAssertLessThan(image.size.height, 80, "inline math must be formula-sized, got \(image.size)")
        XCTAssertLessThan(image.size.width, 200, "inline math must be formula-sized, got \(image.size)")
        XCTAssertGreaterThan(image.size.width, 2)
        XCTAssertGreaterThan(image.size.height, 2)
    }

    func testDisplayMathRendersLargerThanInline() {
        let inlineDone = expectation(description: "inline")
        var inline: NSImage?
        WebBlockRenderer.shared.renderKatex(tex: #"\frac{a}{b}"#, display: false, dark: false) {
            inline = $0
            inlineDone.fulfill()
        }
        wait(for: [inlineDone], timeout: 20)

        let blockDone = expectation(description: "block")
        var block: NSImage?
        WebBlockRenderer.shared.renderKatex(tex: #"\frac{a}{b}"#, display: true, dark: false) {
            block = $0
            blockDone.fulfill()
        }
        wait(for: [blockDone], timeout: 20)

        guard let inline, let block else {
            XCTFail("expected both renders")
            return
        }
        dump(block, named: "katex-display.png")
        XCTAssertGreaterThan(block.size.height, inline.size.height, "display math is set larger")
    }

    func testMermaidRendersFromBundledAssets() {
        let done = expectation(description: "mermaid")
        var rendered: NSImage?
        WebBlockRenderer.shared.renderMermaid(
            source: "graph TD\n  A[Write] --> B{Render?}\n  B -->|yes| C[Show]\n  B -->|no| A",
            dark: false
        ) { image in
            rendered = image
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        guard let image = rendered else {
            XCTFail("mermaid produced no image — bundled assets or the SVG bridge is broken")
            return
        }
        dump(image, named: "mermaid.png")
        XCTAssertGreaterThan(image.size.width, 40)
        XCTAssertGreaterThan(image.size.height, 40)
    }

    /// Repeated requests for the same content must coalesce. Typing used to enqueue a fresh render
    /// per keystroke, growing the queue without bound.
    func testIdenticalRequestsCoalesce() {
        let done = expectation(description: "all")
        done.expectedFulfillmentCount = 5
        for _ in 0..<5 {
            WebBlockRenderer.shared.renderKatex(tex: "y^2", display: false, dark: false) { _ in
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 20)
    }
}
