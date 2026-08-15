import XCTest
@testable import Minidown

@MainActor
final class MarkdownParserTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    func testRecognizesCoreSyntax() {
        let doc = """
        # Heading
        **bold** and *italic*
        `code`
        > quote
        - bullet
        - [x] done
        ---
        """
        let kinds = MarkdownParser.parse(doc).map(\.kind)
        XCTAssertTrue(kinds.contains { if case .heading = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .strong = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .emphasis = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .inlineCode = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .blockquoteLine = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .bulletMark = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .taskMarker(checked: true) = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .thematicBreak = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .collapse = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .taskListMark = $0 { return true }; return false })
    }

    func testTaskCheckboxHidesWhenUnfocused() {
        let doc = "- [ ] todo\n\nbody"
        let outside = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: doc.utf16.count, length: 0)
        )
        XCTAssertTrue(outside.contains { $0.length == 3 }, "task marker [ ] should collapse")
        XCTAssertTrue(outside.contains { $0.length >= 2 }, "task list mark '- ' should collapse")
    }

    func testBoldMarksRevealWhenCaretInsideWord() {
        let doc = "say **bold** now"
        let insideWord = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: 7, length: 0) // inside "bold"
        )
        let boldMarkHides = insideWord.filter { $0.length == 2 && ($0.location == 4 || $0.location == 10) }
        XCTAssertTrue(boldMarkHides.isEmpty, "** should reveal while caret is inside the strong span")

        let outside = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: 0, length: 0)
        )
        XCTAssertTrue(outside.contains { $0.length == 2 }, "** should hide when caret is away")
    }

    func testHideRevealHeadingMarks() {
        let doc = "# Hello\n\nbody"
        let outside = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: doc.utf16.count, length: 0)
        )
        XCTAssertFalse(outside.isEmpty, "heading marks should collapse when caret is away")

        let inside = LivePreviewStyler.hiddenMarkRanges(
            in: doc,
            selection: NSRange(location: 2, length: 0)
        )
        // On the heading line, collapseLine marks should not hide
        let headingLineHides = inside.filter { $0.location < 7 }
        XCTAssertTrue(headingLineHides.isEmpty)
    }

    func testFocusRangeSpansParagraph() {
        let doc = "one\ntwo\n\nthree"
        let focus = LivePreviewStyler.focusRange(in: doc, at: 2)
        XCTAssertEqual(focus.from, 0)
        XCTAssertEqual(focus.to, 8)
    }

    func testExtendedSyntax() {
        let doc = """
        ---
        title: Demo
        ---

        Math $a+b$ and footnote[^1]

        $$
        x=1
        $$

        ```mermaid
        graph TD
          A-->B
        ```
        """
        let ranges = MarkdownParser.parse(doc)
        XCTAssertTrue(ranges.contains { if case .frontmatter = $0.kind { return true }; return false })
        XCTAssertTrue(ranges.contains { if case .inlineMath = $0.kind { return true }; return false })
        XCTAssertTrue(ranges.contains { if case .blockMath = $0.kind { return true }; return false })
        XCTAssertTrue(ranges.contains { if case .footnoteRef = $0.kind { return true }; return false })
        XCTAssertTrue(ranges.contains { if case .mermaid = $0.kind { return true }; return false })
    }

    func testDollarAmountsAreNotMath() {
        let doc = "Price is $5 and $10 today"
        let maths = MarkdownParser.parse(doc).filter { if case .inlineMath = $0.kind { return true }; return false }
        XCTAssertTrue(maths.isEmpty)
    }

    func testStrongIsStyledNotJustMarks() {
        let doc = "say **bold** now"
        let ranges = MarkdownParser.parse(doc)
        XCTAssertTrue(ranges.contains { if case .strong = $0.kind { return true }; return false })
        XCTAssertTrue(ranges.contains { if case .collapse = $0.kind { return true }; return false })
    }

    func testExampleDocumentsParse() throws {
        let files = try ExampleDocuments.allMarkdownNames()
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try ExampleDocuments.text(named: file)
            for pos in [0, text.utf16.count / 2, text.utf16.count] {
                XCTAssertNoThrow(MarkdownParser.parse(text), file)
                XCTAssertNoThrow(
                    LivePreviewStyler.hiddenMarkRanges(in: text, selection: NSRange(location: pos, length: 0)),
                    "\(file)@\(pos)"
                )
            }
        }
    }

    func testStatsCycle() {
        XCTAssertEqual(StatsMode.words.next, .characters)
        XCTAssertEqual(StatsMode.words.format("one two"), "2 words")
    }

    func testExportHTMLContainsTitle() {
        let html = HTMLExport.build("# Hello\n\nWorld", forPrint: false)
        XCTAssertTrue(html.contains("<title>Hello</title>"))
        XCTAssertTrue(html.contains("<h1>Hello</h1>"))
    }
}
