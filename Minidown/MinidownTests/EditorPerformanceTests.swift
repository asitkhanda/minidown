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

/// Guards the "smooth to roughly 20,000 words" target.
///
/// The budgets are deliberately loose — they exist to catch an order-of-magnitude regression (a
/// regex compiled inside a loop, a whole-document `ensureLayout`), not to police small drift.
@MainActor
final class EditorPerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    /// ~20k words of realistic prose: headings, lists, quotes, code, emphasis, links, a table.
    private static func makeDocument(targetWords: Int) -> String {
        var out: [String] = []
        var words = 0
        var section = 0
        while words < targetWords {
            section += 1
            out.append("## Section \(section)")
            out.append("")
            out.append(
                "This paragraph carries **bold** and *italic* and `inline code` plus a "
                    + "[link](https://example.com/page-\(section)) so the inline walker has real work."
            )
            out.append("")
            out.append("- first bullet with **emphasis**")
            out.append("- second bullet mentioning `code`")
            out.append("- third bullet")
            out.append("")
            out.append("> A quoted line that spans the width of the column and then some.")
            out.append("> A second quoted line, because blockquotes are per-line work.")
            out.append("")
            out.append("```swift")
            out.append("let value = compute(section: \(section))")
            out.append("print(\"section \\(value)\")")
            out.append("```")
            out.append("")
            words += 60
        }
        out.append("| Column | Value |")
        out.append("| --- | ---: |")
        out.append("| total | \(words) |")
        return out.joined(separator: "\n")
    }

    private func measureSeconds(_ label: String, _ body: () -> Void) -> Double {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        print("PERF \(label): \(String(format: "%.1f", elapsed * 1000))ms")
        return elapsed
    }

    func testParseAndStyleStayWithinBudgetOnALongDocument() {
        let doc = Self.makeDocument(targetWords: 20_000)
        let wordCount = doc.split { $0.isWhitespace || $0.isNewline }.count
        XCTAssertGreaterThan(wordCount, 15_000, "fixture should actually be long")
        print("PERF document: \(wordCount) words, \(doc.utf16.count) utf16 units")

        let parseTime = measureSeconds("parse") {
            _ = MarkdownParser.parse(doc)
        }
        XCTAssertLessThan(parseTime, 1.0, "parsing a 20k-word document should be well under a second")

        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: 1_000_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let styleTime = measureSeconds("apply + refreshCollapsedGlyphs") {
            LivePreviewStyler.apply(
                to: storage,
                text: doc,
                options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
            )
            layout.refreshCollapsedGlyphs()
        }
        XCTAssertLessThan(styleTime, 2.0, "a full restyle of 20k words should not take seconds")
    }

    /// The keystroke budget. A full restyle of this document is hundreds of milliseconds; typing
    /// must not pay that.
    func testTypingIsCheapOnALongDocument() {
        let doc = Self.makeDocument(targetWords: 20_000)
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: 1_000_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        // Background mode is what the app uses: the parse leaves the main thread, so what is
        // measured here is the latency the typist actually feels.
        let session = LivePreviewSession(parseMode: .background)
        session.applyFull(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )

        // Type in the middle of the document, where a naive implementation restyles everything.
        var caret = storage.length / 2
        let keystrokes = 50
        let elapsed = measureSeconds("\(keystrokes) keystrokes mid-document") {
            for _ in 0..<keystrokes {
                storage.replaceCharacters(in: NSRange(location: caret, length: 0), with: "x")
                session.applyEdit(
                    to: storage,
                    text: storage.string,
                    editedRange: NSRange(location: caret, length: 1),
                    changeInLength: 1,
                    options: .init(selection: NSRange(location: caret + 1, length: 0), isDark: false)
                )
                caret += 1
            }
        }

        let perKeystroke = elapsed / Double(keystrokes)
        print("PERF per keystroke: \(String(format: "%.1f", perKeystroke * 1000))ms")
        XCTAssertLessThan(
            perKeystroke,
            0.030,
            "a keystroke should not cost a full-document restyle"
        )
    }

    /// A caret move must not cost a restyle. Focus dimming lives in the layout manager precisely so
    /// arrow keys stay cheap.
    func testFocusChangeIsCheap() {
        let doc = Self.makeDocument(targetWords: 20_000)
        let storage = NSTextStorage(string: doc)
        let layout = CollapsingLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 640, height: 1_000_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )

        let ns = doc as NSString
        let elapsed = measureSeconds("200 focus moves") {
            for i in 0..<200 {
                let location = (i * 97) % max(1, ns.length - 1)
                let focus = RevealPolicy.focusRange(in: doc, at: location)
                layout.focusRange = NSRange(location: focus.from, length: max(0, focus.to - focus.from))
            }
        }
        XCTAssertLessThan(elapsed, 1.0, "focus changes must not trigger reparsing or restyling")
    }
}
