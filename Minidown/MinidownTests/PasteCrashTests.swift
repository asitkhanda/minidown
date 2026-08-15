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

        for name in ["04-torture-test.md", "06-extended.md"] {
            let text = try ExampleDocuments.text(named: name)
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
