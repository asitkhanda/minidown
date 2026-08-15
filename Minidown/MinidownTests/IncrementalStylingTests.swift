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

/// The safety net for narrowed restyling.
///
/// Narrowing is only sound if it is invisible: after any sequence of edits and selection moves, the
/// incrementally-styled storage must be byte-for-byte identical to one styled from scratch. These
/// tests assert exactly that, so a missed expansion rule shows up here rather than as a stale
/// widget in someone's document.
@MainActor
final class IncrementalStylingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    private func options(_ selection: NSRange) -> LivePreviewStyler.Options {
        .init(selection: selection, directoryURL: nil, isDark: false)
    }

    /// Canonical dump of every attribute run, so two storages can be compared exactly.
    private func snapshot(_ storage: NSTextStorage) -> String {
        var parts: [String] = []
        storage.enumerateAttributes(
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { attrs, range, _ in
            let rendered = attrs.keys
                .map(\.rawValue)
                .sorted()
                .map { key -> String in
                    let value = attrs[NSAttributedString.Key(key)]
                    switch value {
                    case let font as NSFont:
                        return "\(key)=\(font.fontName):\(font.pointSize)"
                    case let color as NSColor:
                        return "\(key)=\(color.description)"
                    case let style as NSParagraphStyle:
                        return "\(key)=\(style.minimumLineHeight):\(style.maximumLineHeight):"
                            + "\(style.firstLineHeadIndent):\(style.paragraphSpacingBefore)"
                    case let widget as MDBlockWidget:
                        return "\(key)=\(widget.kind)"
                    case let flag as Bool:
                        return "\(key)=\(flag)"
                    case let number as NSNumber:
                        return "\(key)=\(number)"
                    default:
                        return key
                    }
                }
                .joined(separator: ",")
            parts.append("[\(range.location),\(range.length)] \(rendered)")
        }
        return parts.joined(separator: "\n")
    }

    private func fullyStyled(_ text: String, selection: NSRange) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: text, options: options(selection))
        return storage
    }

    private func assertMatchesFullRestyle(
        _ storage: NSTextStorage,
        selection: NSRange,
        _ message: String,
        line: UInt = #line
    ) {
        let expected = fullyStyled(storage.string, selection: selection)
        let actualLines = snapshot(storage).components(separatedBy: "\n")
        let expectedLines = snapshot(expected).components(separatedBy: "\n")
        guard actualLines != expectedLines else { return }

        // Report the first divergence plus the surrounding source, which is far more actionable
        // than two multi-kilobyte attribute dumps.
        var index = 0
        while index < min(actualLines.count, expectedLines.count),
              actualLines[index] == expectedLines[index] {
            index += 1
        }
        let actual = index < actualLines.count ? actualLines[index] : "<end>"
        let want = index < expectedLines.count ? expectedLines[index] : "<end>"
        XCTFail(
            """
            \(message)
            first divergence at run \(index):
              incremental: \(actual)
              full:        \(want)
            document (\(storage.length) chars):
            \(storage.string.debugDescription)
            """,
            file: #filePath,
            line: line
        )
    }

    private let document = """
    # Heading one

    A paragraph with **bold**, *italic*, `code`, and a [link](https://example.com).

    - bullet one
    - bullet two
    - [ ] a task

    > a quoted line

    | Left | Right |
    | --- | ---: |
    | a | b |

    ```swift
    let x = 1
    ```

    Math $a+b$ inline, and a rule below.

    ---

    Trailing paragraph.
    """

    // MARK: - Edits

    func testTypingCharactersMatchesFullRestyle() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession()
        let caret = NSRange(location: document.utf16.count, length: 0)
        session.applyFull(to: storage, text: document, options: options(caret))

        // Type into the middle of the prose paragraph.
        let insertionPoint = (document as NSString).range(of: "A paragraph").location + 2
        for (offset, character) in "XYZ".enumerated() {
            let location = insertionPoint + offset
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: String(character))
            session.applyEdit(
                to: storage,
                text: storage.string,
                editedRange: NSRange(location: location, length: 1),
                changeInLength: 1,
                options: options(NSRange(location: location + 1, length: 0))
            )
        }
        assertMatchesFullRestyle(
            storage,
            selection: NSRange(location: insertionPoint + 3, length: 0),
            "typing must produce the same styling as a full restyle"
        )
    }

    /// Opening a fence changes how everything below it parses. The expansion has to notice.
    func testInsertingACodeFenceRestylesWhatItSwallows() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        let location = (document as NSString).range(of: "- bullet one").location
        let insert = "```\n"
        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: insert)
        session.applyEdit(
            to: storage,
            text: storage.string,
            editedRange: NSRange(location: location, length: (insert as NSString).length),
            changeInLength: (insert as NSString).length,
            options: options(NSRange(location: location, length: 0))
        )

        assertMatchesFullRestyle(
            storage,
            selection: NSRange(location: location, length: 0),
            "an opened fence changes parsing far beyond the edited line"
        )
    }

    /// Deleting one `$` unpairs block math that may span a large region.
    func testDeletingAcrossAConstructBoundaryMatchesFullRestyle() {
        let doc = "before\n\n$$\nx = 1\n$$\n\nafter the block\n"
        let storage = NSTextStorage(string: doc)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: doc, options: options(NSRange(location: 0, length: 0)))

        let dollars = (doc as NSString).range(of: "$$")
        storage.replaceCharacters(in: NSRange(location: dollars.location, length: 1), with: "")
        session.applyEdit(
            to: storage,
            text: storage.string,
            editedRange: NSRange(location: dollars.location, length: 0),
            changeInLength: -1,
            options: options(NSRange(location: dollars.location, length: 0))
        )

        assertMatchesFullRestyle(
            storage,
            selection: NSRange(location: dollars.location, length: 0),
            "unpairing block math must clear the widget it used to own"
        )
    }

    func testRandomisedEditsAlwaysMatchFullRestyle() {
        var generator = SeededGenerator(seed: 0x5EED)
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        let insertions = ["a", " ", "\n", "*", "`", "#", "-", "|", "$", "> ", "```", "[ ] "]
        for step in 0..<120 {
            let length = storage.length
            guard length > 1 else { break }
            let location = Int.random(in: 0..<length, using: &generator)

            // The caret after the edit. Both the incremental pass and the reference full restyle
            // must use exactly this, or they differ for a legitimate reason (reveal state) and the
            // comparison proves nothing.
            let caret: NSRange
            if step.isMultiple(of: 3) {
                let removable = min(Int.random(in: 1...3, using: &generator), length - location)
                guard removable > 0 else { continue }
                caret = NSRange(location: location, length: 0)
                storage.replaceCharacters(in: NSRange(location: location, length: removable), with: "")
                session.applyEdit(
                    to: storage,
                    text: storage.string,
                    editedRange: NSRange(location: location, length: 0),
                    changeInLength: -removable,
                    options: options(caret)
                )
            } else {
                let insert = insertions.randomElement(using: &generator)!
                storage.replaceCharacters(in: NSRange(location: location, length: 0), with: insert)
                let inserted = (insert as NSString).length
                caret = NSRange(location: location + inserted, length: 0)
                session.applyEdit(
                    to: storage,
                    text: storage.string,
                    editedRange: NSRange(location: location, length: inserted),
                    changeInLength: inserted,
                    options: options(caret)
                )
            }

            assertMatchesFullRestyle(storage, selection: caret, "diverged after edit \(step)")
        }
    }

    // MARK: - Selection moves

    func testSelectionMovesMatchFullRestyle() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        let ns = document as NSString
        // Walk the caret across every construct boundary in the document.
        for location in stride(from: 0, to: ns.length, by: 7) {
            let selection = NSRange(location: location, length: 0)
            session.applySelectionChange(to: storage, text: document, options: options(selection))
            assertMatchesFullRestyle(storage, selection: selection, "diverged with caret at \(location)")
        }
    }

    // MARK: - Background reconcile

    /// In the app the parse runs off the main thread, so the immediate pass is deliberately styled
    /// against stale constructs. What matters is that the reconcile lands and converges.
    func testBackgroundReconcileConvergesToFullRestyle() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession(parseMode: .background)
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        let reconciled = expectation(description: "reconciled")
        session.onReconciled = { reconciled.fulfill() }

        // Type syntax the stale construct list cannot know about.
        let location = (document as NSString).range(of: "Trailing paragraph.").location
        let insert = "**new bold** "
        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: insert)
        let inserted = (insert as NSString).length
        let caret = NSRange(location: location + inserted, length: 0)
        session.applyEdit(
            to: storage,
            text: storage.string,
            editedRange: NSRange(location: location, length: inserted),
            changeInLength: inserted,
            options: options(caret)
        )

        wait(for: [reconciled], timeout: 5)
        assertMatchesFullRestyle(storage, selection: caret, "background reconcile did not converge")
    }

    /// Typing faster than the parser must not leave stale styling behind: superseded parses are
    /// dropped by generation, and the last one wins.
    func testRapidEditsConvergeAfterTheLastParse() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession(parseMode: .background)
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        var location = (document as NSString).range(of: "Trailing paragraph.").location
        var caret = NSRange(location: location, length: 0)
        for character in "`code` and **bold**" {
            let text = String(character)
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: text)
            let inserted = (text as NSString).length
            location += inserted
            caret = NSRange(location: location, length: 0)
            session.applyEdit(
                to: storage,
                text: storage.string,
                editedRange: NSRange(location: location - inserted, length: inserted),
                changeInLength: inserted,
                options: options(caret)
            )
        }

        // Let the queue drain, then confirm the final state is exactly a full restyle.
        let settled = expectation(description: "settled")
        session.onReconciled = { settled.fulfill() }
        settled.assertForOverFulfill = false
        wait(for: [settled], timeout: 5)
        // Give any already-queued reconciles a chance to land before comparing.
        let drained = expectation(description: "drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { drained.fulfill() }
        wait(for: [drained], timeout: 5)

        assertMatchesFullRestyle(storage, selection: caret, "rapid typing left stale styling")
    }

    func testSelectAllThenCollapseMatchesFullRestyle() {
        let storage = NSTextStorage(string: document)
        let session = LivePreviewSession()
        session.applyFull(to: storage, text: document, options: options(NSRange(location: 0, length: 0)))

        let all = NSRange(location: 0, length: document.utf16.count)
        session.applySelectionChange(to: storage, text: document, options: options(all))
        assertMatchesFullRestyle(storage, selection: all, "select-all diverged")

        let collapsed = NSRange(location: 5, length: 0)
        session.applySelectionChange(to: storage, text: document, options: options(collapsed))
        assertMatchesFullRestyle(storage, selection: collapsed, "collapsing after select-all diverged")
    }
}

/// Deterministic RNG so a failure is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
