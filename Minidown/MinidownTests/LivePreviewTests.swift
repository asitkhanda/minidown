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

@MainActor
final class LivePreviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }
    // MARK: - Task list syntax coverage

    func testTaskSyntaxVariants() {
        let doc = """
        - [ ] dash unchecked
        * [x] star checked
        + [X] plus checked upper
        1. [ ] ordered unchecked
        2. [x] ordered checked
          - [ ] indented
        """
        let ranges = MarkdownParser.parse(doc)
        let tasks = ranges.compactMap { c -> (Bool, String)? in
            guard case .taskMarker(let checked) = c.kind else { return nil }
            let ns = doc as NSString
            let slice = ns.substring(with: NSRange(location: c.from, length: c.to - c.from))
            return (checked, slice)
        }

        XCTAssertEqual(tasks.count, 6, "expected every GFM task line to parse, got \(tasks)")
        XCTAssertEqual(tasks.filter(\.0).count, 3, "checked count")
        XCTAssertEqual(tasks.filter { !$0.0 }.count, 3, "unchecked count")

        let listMarks = ranges.filter { if case .taskListMark = $0.kind { return true }; return false }
        XCTAssertEqual(listMarks.count, 6, "list-prefixed tasks hide their '- '/'* '/'+ '/'1. ' mark")
    }

    /// Bare `[ ]` with no list marker was a 0.2.0 extension. It was dropped: anything written that
    /// way renders as literal brackets in GitHub, Obsidian and every other Markdown tool, so the
    /// file was only a checklist inside minidown.
    func testBareBracketsAreNotTasks() {
        let doc = "[ ] Checklist\n[x] done\n\nbody"
        let tasks = MarkdownParser.parse(doc).filter {
            if case .taskMarker = $0.kind { return true }
            return false
        }
        XCTAssertTrue(tasks.isEmpty, "bare brackets are not GFM tasks and must stay literal")
    }

    /// Nested items indented four or more spaces used to miss their bullet, because the marker was
    /// matched with a `^ {0,3}` regex instead of read from the list item's own start.
    func testDeeplyNestedBulletsStillHideTheirMarker() {
        let doc = """
        - top level
            - nested four spaces
                - nested eight spaces
        """
        let bullets = MarkdownParser.parse(doc).filter {
            if case .bulletMark = $0.kind { return true }
            return false
        }
        XCTAssertEqual(bullets.count, 3, "every nesting depth should hide its bullet")
    }

    func testMidLineBracketsAreNotTasks() {
        let doc = "see [ ] in prose and [x] too"
        let tasks = MarkdownParser.parse(doc).filter {
            if case .taskMarker = $0.kind { return true }
            return false
        }
        XCTAssertTrue(tasks.isEmpty)
    }

    // MARK: - Inline code

    func testInlineCodeStylesContentNotBackticks() {
        let doc = "before `Code Block` after"
        let ranges = MarkdownParser.parse(doc)

        let code = ranges.first { if case .inlineCode = $0.kind { return true }; return false }
        XCTAssertNotNil(code)
        XCTAssertEqual(
            (doc as NSString).substring(with: NSRange(location: code!.from, length: code!.to - code!.from)),
            "Code Block",
            "inlineCode range must be inner text only — backticks get collapse, not background"
        )

        let collapses = ranges.filter { if case .collapse = $0.kind { return true }; return false }
        let tickRanges = collapses.map { NSRange(location: $0.from, length: $0.to - $0.from) }
        XCTAssertTrue(tickRanges.contains { $0.length == 1 && (doc as NSString).substring(with: $0) == "`" })
    }

    func testInlineCodeBackticksHideWhenUnfocused() {
        let doc = "`Code Block`\n\nnext"
        let outside = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: doc.utf16.count, length: 0)
        )
        let hiddenTicks = outside.filter { $0.length == 1 }
        XCTAssertEqual(hiddenTicks.count, 2, "both backticks should hide")

        let storage = NSTextStorage(string: doc)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(
                selection: NSRange(location: doc.utf16.count, length: 0),
                directoryURL: nil,
                isDark: true
            )
        )

        // Backticks collapsed — no background on them
        let openBG = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        XCTAssertNil(openBG, "opening backtick must not carry code background")

        // Inner content keeps code chrome
        let innerBG = storage.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(innerBG, "inner code content should keep background")
        let collapse = storage.attribute(.mdCollapse, at: 0, effectiveRange: nil) as? Bool
        XCTAssertEqual(collapse, true)
    }

    // MARK: - Layout collapse (null glyphs)

    func testTaskMarkerKeepsWidthAndStaysOnItsLine() {
        // Reproduces the bug: checkbox was painted on the heading above.
        let doc = "# Hello\n- [x] Hello world"
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 800))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(
                selection: NSRange(location: doc.utf16.count, length: 0),
                directoryURL: nil,
                isDark: true
            )
        )
        layout.refreshCollapsedGlyphs()

        // Marker must keep advance width (not .null) so it stays on its own line.
        let markerStart = (doc as NSString).range(of: "[x]").location
        XCTAssertNotNil(storage.attribute(.mdTask, at: markerStart, effectiveRange: nil))
        let gMarker = layout.glyphIndexForCharacter(at: markerStart)
        XCTAssertFalse(
            layout.propertyForGlyph(at: gMarker).contains(.null),
            "task marker glyphs must keep width — null glyphs jump to the previous line"
        )

        guard let box = layout.checkboxRect(forCharacterRange: NSRange(location: markerStart, length: 3)) else {
            XCTFail("expected checkbox rect")
            return
        }

        let headingGlyph = layout.glyphIndexForCharacter(at: 2) // 'H' of heading
        var headingFrag = NSRange()
        let headingLine = layout.lineFragmentRect(forGlyphAt: headingGlyph, effectiveRange: &headingFrag)

        let bodyGlyph = layout.glyphIndexForCharacter(at: markerStart)
        var bodyFrag = NSRange()
        let bodyLine = layout.lineFragmentRect(forGlyphAt: bodyGlyph, effectiveRange: &bodyFrag)

        XCTAssertGreaterThan(bodyLine.minY, headingLine.maxY - 1, "task line must be below heading")
        XCTAssertGreaterThanOrEqual(box.minY, bodyLine.minY - 1)
        XCTAssertLessThanOrEqual(box.maxY, bodyLine.maxY + 1)
        XCTAssertFalse(
            headingLine.intersects(box),
            "checkbox must not overlap the heading (was drawing on the H)"
        )
    }

    func testCollapsedSyntaxGlyphsBecomeNull() {
        let doc = "**bold** and `code`"
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 500, height: 500))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(
                selection: NSRange(location: doc.utf16.count, length: 0),
                directoryURL: nil,
                isDark: true
            )
        )
        layout.refreshCollapsedGlyphs()

        let g0 = layout.glyphIndexForCharacter(at: 0)
        let g1 = layout.glyphIndexForCharacter(at: 1)
        XCTAssertTrue(layout.propertyForGlyph(at: g0).contains(.null))
        XCTAssertTrue(layout.propertyForGlyph(at: g1).contains(.null))

        let gb = layout.glyphIndexForCharacter(at: 2)
        XCTAssertFalse(layout.propertyForGlyph(at: gb).contains(.null))
    }

    func testBlockWidgetsActivateWhenCaretAway() {
        let doc = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        $$
        x=1
        $$

        ```mermaid
        graph TD
          A-->B
        ```

        ![alt](https://example.com/a.png)

        ---

        trailing body
        """
        let away = LivePreviewStyler.activeBlockWidgetKinds(
            in: doc,
            selection: NSRange(location: doc.utf16.count, length: 0)
        )
        XCTAssertTrue(away.contains("table"), "\(away)")
        XCTAssertTrue(away.contains("blockMath"), "\(away)")
        XCTAssertTrue(away.contains("mermaid"), "\(away)")
        XCTAssertTrue(away.contains("image"), "\(away)")
        XCTAssertTrue(away.contains("hr"), "\(away)")

        // Caret inside the table → no table widget
        let tableStart = (doc as NSString).range(of: "| A |").location
        let inside = LivePreviewStyler.activeBlockWidgetKinds(
            in: doc,
            selection: NSRange(location: tableStart + 2, length: 0)
        )
        XCTAssertFalse(inside.contains("table"))
    }

    func testTableBitmapRenders() {
        let raw = """
        | Left | Right |
        | :--- | ---: |
        | a | b |
        """
        guard let table = MarkdownParser.parse(raw).compactMap({ range -> MarkdownTable? in
            if case .table(let data) = range.kind { return data }
            return nil
        }).first else {
            XCTFail("expected a table construct")
            return
        }
        let image = TableRenderer.image(for: table, maxWidth: 400, dark: true)
        XCTAssertGreaterThan(image.size.width, 40)
        XCTAssertGreaterThan(image.size.height, 20)
    }

    func testCoreMarksHideAwayFromCaret() {
        let samples: [(String, String)] = [
            ("# Heading\n\nbody", "heading"),
            ("**bold**\n\nbody", "strong"),
            ("*italic*\n\nbody", "emphasis"),
            ("~~strike~~\n\nbody", "strike"),
            ("> quote\n\nbody", "quote"),
            ("- bullet\n\nbody", "bullet"),
            ("[link](https://example.com)\n\nbody", "link"),
            ("`code`\n\nbody", "code"),
            ("para\n\n---\n\nbody", "hr"),
            ("- [ ] task\n\nbody", "gfm task"),
        ]
        for (doc, label) in samples {
            let hidden = LivePreviewStyler.hiddenMarkRanges(
                in: doc,
                selection: NSRange(location: doc.utf16.count, length: 0)
            )
            XCTAssertFalse(hidden.isEmpty, "\(label) should hide syntax when caret is away")
        }
    }
}
