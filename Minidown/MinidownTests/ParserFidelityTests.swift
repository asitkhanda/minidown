import XCTest
@testable import Minidown

/// Phase 3: the parser must not see markup where there is none, and must see it where there is.
@MainActor
final class ParserFidelityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    private func kinds(_ doc: String) -> [MarkdownRange] {
        MarkdownParser.parse(doc)
    }

    private func has(_ doc: String, _ predicate: (MarkdownRange.Kind) -> Bool) -> Bool {
        kinds(doc).contains { predicate($0.kind) }
    }

    // MARK: - Code awareness

    /// The regex pass used to run over the raw document with no idea where code was, so a shell
    /// snippet became math and a checklist inside a fence became clickable.
    func testFencedCodeIsNotScannedForMarkup() {
        let doc = """
        Prose before.

        ```bash
        cd $dir/$file
        grep '[^0-9]' input.txt
        # - [ ] not a task
        ```

        Prose after.
        """
        XCTAssertFalse(
            has(doc) { if case .inlineMath = $0 { return true }; return false },
            "`$dir/$file` in a shell fence is not math"
        )
        XCTAssertFalse(
            has(doc) { if case .footnoteRef = $0 { return true }; return false },
            "a regex character class in a fence is not a footnote reference"
        )
        XCTAssertFalse(
            has(doc) { if case .taskMarker = $0 { return true }; return false },
            "a checklist inside a fence is code, not a task"
        )
    }

    func testInlineCodeIsNotScannedForMarkup() {
        let doc = "Use `$HOME/$USER` and `[^abc]` in prose."
        XCTAssertFalse(
            has(doc) { if case .inlineMath = $0 { return true }; return false },
            "inline code contents are not math"
        )
        XCTAssertFalse(
            has(doc) { if case .footnoteRef = $0 { return true }; return false },
            "inline code contents are not footnote references"
        )
    }

    /// A regex character class in ordinary prose is genuinely ambiguous, but the common real case
    /// is code, and `[^1]` as a footnote must keep working.
    func testGenuineFootnoteReferenceStillParses() {
        let doc = "A claim[^1] that needs support.\n\n[^1]: the support."
        XCTAssertTrue(has(doc) { if case .footnoteRef = $0 { return true }; return false })
    }

    func testLinkDestinationsAreNotScannedForMarkup() {
        let doc = "See [the page](https://example.com/a$b$c) for more."
        XCTAssertFalse(
            has(doc) { if case .inlineMath = $0 { return true }; return false },
            "dollars inside a URL are not math"
        )
    }

    // MARK: - Smart punctuation

    /// `Document(parsing:)` enables CMARK_OPT_SMART by default, which rewrites quotes and dashes in
    /// the tree. Ranges must still line up with the untouched source buffer.
    func testSmartPunctuationDoesNotShiftRanges() {
        let doc = #"He said "hello" -- then **left** for a while."#
        let ns = doc as NSString
        guard let strong = kinds(doc).first(where: { if case .strong = $0.kind { return true }; return false })
        else {
            XCTFail("expected a strong span")
            return
        }
        let slice = ns.substring(with: NSRange(location: strong.from, length: strong.to - strong.from))
        XCTAssertEqual(slice, "**left**", "ranges must index the original text, not a smart-quoted copy")
    }

    // MARK: - Frontmatter

    func testRealFrontmatterIsRecognised() {
        let doc = "---\ntitle: Demo\nauthor: someone\n---\n\n# Body"
        XCTAssertTrue(has(doc) { if case .frontmatter = $0 { return true }; return false })
    }

    /// A document opening with a horizontal rule used to have everything up to the next `---`
    /// swallowed as metadata.
    func testLeadingThematicBreakIsNotFrontmatter() {
        let doc = "---\n\nA normal paragraph of prose.\n\n---\n\nMore prose.\n"
        XCTAssertFalse(
            has(doc) { if case .frontmatter = $0 { return true }; return false },
            "a leading rule is not frontmatter — there are no YAML keys between the fences"
        )
        XCTAssertTrue(has(doc) { if case .thematicBreak = $0 { return true }; return false })
    }

    // MARK: - Autolinks

    /// `examples/01-basics.md` promises bare URLs autolink. cmark-gfm's autolink extension is not
    /// attached by swift-markdown and cannot be enabled through its API, so this is a regex pass.
    func testBareUrlsAutolink() {
        let doc = "Visit https://example.com/page for details."
        let links = kinds(doc).filter { if case .linkText = $0.kind { return true }; return false }
        XCTAssertEqual(links.count, 1, "expected exactly one autolinked URL")
        let ns = doc as NSString
        let slice = ns.substring(with: NSRange(location: links[0].from, length: links[0].to - links[0].from))
        XCTAssertEqual(slice, "https://example.com/page", "trailing punctuation must not be swallowed")
    }

    func testUrlsInsideCodeDoNotAutolink() {
        let doc = "Run `curl https://example.com` first."
        let links = kinds(doc).filter { if case .linkText = $0.kind { return true }; return false }
        XCTAssertTrue(links.isEmpty, "a URL inside inline code is not a link")
    }

    func testExplicitLinksAreNotDoubleCounted() {
        let doc = "See [the page](https://example.com) now."
        let links = kinds(doc).filter { if case .linkText = $0.kind { return true }; return false }
        XCTAssertEqual(links.count, 1, "the destination must not also autolink")
    }

    // MARK: - Setext headings

    func testSetextUnderlineHidesWithItsOwnLine() {
        let doc = "Heading One\n===========\n\nbody text"
        XCTAssertTrue(has(doc) { if case .heading(let level) = $0 { return level == 1 }; return false })

        let ns = doc as NSString
        let underline = ns.range(of: "===========")
        // Caret parked in the body: the underline should be hidden.
        let awayHidden = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: doc.utf16.count, length: 0)
        )
        XCTAssertTrue(
            awayHidden.contains { NSIntersectionRange($0, underline).length > 0 },
            "the setext underline is syntax and should hide when the caret is elsewhere"
        )

        // Caret on the underline itself: it must reveal.
        let onUnderline = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: underline.location + 2, length: 0)
        )
        XCTAssertFalse(
            onUnderline.contains { NSIntersectionRange($0, underline).length > 0 },
            "the underline must reveal when the caret is on it, or it cannot be edited"
        )
    }

    // MARK: - Tables

    /// The renderer used to re-split the pipe text with its own rules. Alignment and cell contents
    /// now come from cmark.
    func testTableStructureIsCapturedFromTheAst() {
        let doc = """
        | Left | Middle | Right |
        | :--- | :----: | ----: |
        | a | b | c |
        | d | e | f |
        """
        guard let table = kinds(doc).compactMap({ range -> MarkdownTable? in
            if case .table(let data) = range.kind { return data }
            return nil
        }).first else {
            XCTFail("expected a table construct")
            return
        }

        XCTAssertEqual(table.alignments, [.left, .center, .right])
        XCTAssertEqual(table.header.map(\.text), ["Left", "Middle", "Right"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows.first?.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(table.rows.last?.map(\.text), ["d", "e", "f"])
    }
}
