import AppKit
import XCTest
@testable import Minidown

/// Phase 6: export fidelity.
///
/// The Swift rewrite replaced a markdown-it pipeline with a ~50-line line-based renderer that
/// silently dropped lists, tables, task lists, images, rules, setext headings, multi-line
/// blockquotes and nested emphasis. These assertions are the ones the Tauri suite carried, plus
/// the regressions found while restoring it.
final class ExportTests: XCTestCase {
    private func html(_ markdown: String) -> String {
        HTMLExport.build(markdown, forPrint: false)
    }

    // MARK: - Structure that used to be dropped entirely

    func testHeadingsAndTitle() {
        let output = html("# Hello\n\nWorld")
        XCTAssertTrue(output.contains("<title>Hello</title>"))
        XCTAssertTrue(output.contains("<h1>Hello</h1>"))
    }

    func testUnorderedAndOrderedListsSurvive() {
        let output = html("- one\n- two\n\n1. first\n2. second\n")
        XCTAssertTrue(output.contains("<ul>"), "bullet lists were dropped entirely")
        // Tight list items render their text inline; wrapping each in <p> is a loose-list feature.
        XCTAssertTrue(output.contains("<li>one</li>"), output)
        XCTAssertTrue(output.contains("<ol>"), "ordered lists were dropped entirely")
    }

    func testTasksRenderAsCheckboxes() {
        let output = html("- [ ] todo\n- [x] done\n")
        XCTAssertTrue(output.contains("type=\"checkbox\""), "task lists were dropped")
        XCTAssertTrue(output.contains("checked"), "a completed task should render checked")
    }

    func testTablesRenderWithAlignment() {
        let output = html("| Left | Right |\n| :--- | ----: |\n| a | b |\n")
        XCTAssertTrue(output.contains("<table>"), "tables were dropped entirely")
        XCTAssertTrue(output.contains("<th"), "table headers")
        XCTAssertTrue(output.contains("text-align:left"), "column alignment must carry over")
        XCTAssertTrue(output.contains("text-align:right"))
    }

    func testImagesKeepAltText() {
        let output = html("![a cat](cat.png)")
        XCTAssertTrue(output.contains("<img"), "images were dropped")
        XCTAssertTrue(output.contains("alt=\"a cat\""), "HTMLFormatter drops alt text; we restore it")
        XCTAssertTrue(output.contains("src=\"cat.png\""))
    }

    func testThematicBreakAndBlockquote() {
        let output = html("para\n\n---\n\n> quoted line one\n> quoted line two\n")
        XCTAssertTrue(output.contains("<hr />"), "horizontal rules were dropped")
        XCTAssertTrue(output.contains("<blockquote>"))
    }

    func testHardWrappedParagraphStaysOneParagraph() {
        // Every non-empty line used to become its own <p>.
        let output = html("This sentence is\nhard wrapped across\nthree source lines.\n")
        XCTAssertEqual(
            output.components(separatedBy: "<p>").count - 1,
            1,
            "hard-wrapped prose must stay a single paragraph"
        )
    }

    func testNestedEmphasisAndLinks() {
        let output = html("A **bold with *italic* inside** and a [link](https://example.com).")
        XCTAssertTrue(output.contains("<strong>"))
        XCTAssertTrue(output.contains("<em>"))
        XCTAssertTrue(output.contains("href=\"https://example.com\""))
    }

    func testSetextHeadings() {
        let output = html("Title Here\n==========\n\nbody\n")
        XCTAssertTrue(output.contains("<h1>Title Here</h1>"), "setext headings were dropped")
    }

    // MARK: - Escaping

    func testRawHtmlIsEscapedNotPassedThrough() {
        let output = html("<script>alert(1)</script>\n")
        XCTAssertFalse(output.contains("<script>alert(1)</script>"), "raw HTML must not pass through")
        XCTAssertTrue(output.contains("&lt;script&gt;"))
    }

    func testEmphasisInsideCodeSpansIsNotApplied() {
        // The old inline pass ran regexes across the whole line, mangling code spans.
        let output = html("Use `a*b*c` literally.")
        XCTAssertTrue(output.contains("<code>a*b*c</code>"), output)
        XCTAssertFalse(output.contains("<code>a<em>b</em>c</code>"))
    }

    func testLinkDestinationsAreEscaped() {
        let output = html("[x](https://example.com/\"onmouseover=\"alert(1))")
        XCTAssertFalse(output.contains("\"onmouseover=\""), "destinations must be attribute-escaped")
    }

    // MARK: - Conditional heavy dependencies

    func testPlainDocumentReferencesNoCdnAssets() {
        let output = html("# Just prose\n\nNothing fancy here.\n")
        // Checks for network references specifically: the stylesheet legitimately carries a
        // `pre.mermaid` rule, so searching for the bare word would always match.
        XCTAssertFalse(output.contains("cdn.jsdelivr.net"), "a plain document must export standalone")
        XCTAssertFalse(output.contains("<script"), "no scripts needed for plain prose")
    }

    func testMathDocumentPullsInKatex() {
        let output = html("Euler: $e^{i\\pi} + 1 = 0$\n")
        XCTAssertTrue(output.contains("katex"))
    }

    func testMermaidDocumentPullsInMermaid() {
        let output = html("```mermaid\ngraph TD\n  A-->B\n```\n")
        XCTAssertTrue(output.contains("mermaid"))
        XCTAssertTrue(output.contains("<pre class=\"mermaid\">"))
    }

    /// The regression that matters most here: `\$[^\s$]` matched `$5`, so a document about prices
    /// loaded KaTeX and rendered "$5 and $10" as a formula.
    func testDollarAmountsDoNotPullInKatex() {
        let output = html("This costs $5 and that costs $10 today.\n")
        XCTAssertFalse(
            output.contains("katex"),
            "prices are not math — the editor is careful about this and export must match"
        )
    }

    // MARK: - Frontmatter

    func testFrontmatterTitleIsUsedAndStripped() {
        let output = html("---\ntitle: My Document\nauthor: someone\n---\n\n# Body heading\n\ntext\n")
        XCTAssertTrue(output.contains("<title>My Document</title>"))
        XCTAssertFalse(output.contains("author: someone"), "frontmatter must not appear in the body")
    }

    /// A document opening with a rule used to have everything up to the next `---` deleted.
    func testLeadingThematicBreakDoesNotEatContent() {
        let output = html("---\n\nImportant opening paragraph.\n\n---\n\nSecond paragraph.\n")
        XCTAssertTrue(output.contains("Important opening paragraph."), "content was deleted as frontmatter")
        XCTAssertTrue(output.contains("Second paragraph."))
    }

    // MARK: - Print stylesheet

    func testPrintStylesheetRetargetsTheContainer() {
        let printOutput = HTMLExport.build("# x", forPrint: true)
        XCTAssertTrue(printOutput.contains("#print-root"), "print CSS should target the print container")
    }

    // MARK: - Word / RTF / plain text conversion

    /// These formats go through NSAttributedString now; `textutil` cannot run inside a sandbox.
    func testAttributedConversionProducesRtfAndDocx() throws {
        let source = "# Title\n\n- one\n- two\n\n**bold** text\n"
        let data = try XCTUnwrap(HTMLExport.build(source, forPrint: false).data(using: .utf8))
        let attributed = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
        XCTAssertTrue(attributed.string.contains("Title"))
        XCTAssertTrue(attributed.string.contains("bold"))

        let full = NSRange(location: 0, length: attributed.length)
        let rtf = try attributed.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        XCTAssertGreaterThan(rtf.count, 32)

        let docx = try attributed.data(
            from: full,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        // .docx is a zip: check the magic bytes rather than trusting the byte count.
        XCTAssertEqual(Array(docx.prefix(2)), [0x50, 0x4B], "docx output should be a zip container")
    }

    // MARK: - Fixtures

    func testEveryExampleDocumentExportsWithoutLosingContent() throws {
        for name in try ExampleDocuments.allMarkdownNames() {
            let markdown = try ExampleDocuments.text(named: name)
            let output = html(markdown)
            XCTAssertTrue(output.contains("<body>"), "\(name) produced no body")
            XCTAssertGreaterThan(output.count, markdown.count / 4, "\(name) lost most of its content")
        }
    }
}
