import AppKit
import XCTest
@testable import Minidown

/// Phase 5: fenced code must be tokenised by its own language.
///
/// The bug: `codeBlock.language` was parsed and thrown away, and Splash — which ships exactly one
/// grammar and defaults to it — tokenised Python, JSON and shell as Swift.
@MainActor
final class CodeHighlightingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WebBlockRenderer.isEnabled = false
    }

    override func tearDown() {
        WebBlockRenderer.isEnabled = true
        super.tearDown()
    }

    /// All colours applied inside the fence body, keyed by the text they cover.
    private func colouredTokens(_ doc: String) -> [String: NSColor] {
        let storage = NSTextStorage(string: doc)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )
        let ns = doc as NSString
        var out: [String: NSColor] = [:]
        storage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor, range.length > 0 else { return }
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            out[text] = color
        }
        return out
    }

    private func fence(_ language: String, _ body: String) -> String {
        "intro\n\n```\(language)\n\(body)\n```\n\nafter\n"
    }

    private func assertColoured(
        _ token: String,
        _ expected: NSColor,
        in tokens: [String: NSColor],
        _ message: String,
        line: UInt = #line
    ) {
        guard let actual = tokens[token] else {
            XCTFail("\(message): no colour applied to \(token.debugDescription)", file: #filePath, line: line)
            return
        }
        XCTAssertEqual(actual, expected, message, file: #filePath, line: line)
    }

    func testPythonKeywordsAndStringsAreColoured() {
        let tokens = colouredTokens(fence("python", "def greet(name):\n    return \"hello\""))
        assertColoured("def", AppColors.sxKeyword, in: tokens, "python def is a keyword")
        assertColoured("\"hello\"", AppColors.sxString, in: tokens, "python string literal")
    }

    /// The alias the Tauri build supported and `examples/02-code.md` uses.
    func testPythonExtensionAliasWorks() {
        let tokens = colouredTokens(fence("py", "def greet():\n    pass"))
        assertColoured("def", AppColors.sxKeyword, in: tokens, "`py` must alias to python")
    }

    func testJavaScriptIsNotTokenisedAsSwift() {
        let tokens = colouredTokens(fence("js", "function add(a, b) {\n  return a + b;\n}"))
        assertColoured("function", AppColors.sxKeyword, in: tokens, "js function is a keyword")
        assertColoured("return", AppColors.sxKeyword, in: tokens, "js return is a keyword")
    }

    func testRustAliasAndKeywords() {
        let tokens = colouredTokens(fence("rs", "fn main() {\n    let x = 1;\n}"))
        assertColoured("fn", AppColors.sxKeyword, in: tokens, "rust fn is a keyword")
        assertColoured("let", AppColors.sxKeyword, in: tokens, "rust let is a keyword")
    }

    func testShellCommentsAndStrings() {
        let tokens = colouredTokens(fence("bash", "# a comment\necho \"hi\""))
        assertColoured("# a comment", AppColors.sxComment, in: tokens, "shell comment")
    }

    func testJsonStringsAreColoured() {
        let tokens = colouredTokens(fence("json", "{\n  \"key\": \"value\"\n}"))
        assertColoured("\"value\"", AppColors.sxString, in: tokens, "json string value")
    }

    func testCssIsColoured() {
        let tokens = colouredTokens(fence("css", "body {\n  color: red;\n}"))
        XCTAssertFalse(tokens.isEmpty, "css should get some colouring")
    }

    func testSwiftStillUsesSplash() {
        let tokens = colouredTokens(fence("swift", "let value = \"text\"\nfunc go() {}"))
        assertColoured("let", AppColors.sxKeyword, in: tokens, "swift keyword via Splash")
        assertColoured("\"text\"", AppColors.sxString, in: tokens, "swift string via Splash")
    }

    /// An unlabelled fence gets block styling but no token colours — honest rather than wrong.
    func testUnlabelledFenceIsNotTokenised() {
        let doc = "```\nsome plain text that is not any language\n```"
        let storage = NSTextStorage(string: doc)
        LivePreviewStyler.apply(
            to: storage,
            text: doc,
            options: .init(selection: NSRange(location: 0, length: 0), isDark: false)
        )
        var colours = Set<NSColor>()
        storage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, _, _ in
            if let colour = value as? NSColor { colours.insert(colour) }
        }
        XCTAssertFalse(colours.contains(AppColors.sxKeyword), "no language, no keyword colouring")
    }

    func testUnknownLanguageDoesNotCrashOrColour() {
        let tokens = colouredTokens(fence("brainfuck", "+++[->+++<]"))
        XCTAssertNil(tokens["+++"], "unsupported languages render plain")
    }

    // MARK: - Capture mapping

    /// Grammars disagree on capture vocabulary, so the mapping falls back by dropping trailing
    /// components. Without that, most languages would come out nearly uncoloured.
    func testCaptureNamesFallBackByPrefix() {
        XCTAssertEqual(CodeHighlighter.color(forCapture: "keyword"), AppColors.sxKeyword)
        XCTAssertEqual(CodeHighlighter.color(forCapture: "keyword.function"), AppColors.sxKeyword)
        XCTAssertEqual(CodeHighlighter.color(forCapture: "keyword.control.conditional"), AppColors.sxKeyword)
        XCTAssertEqual(CodeHighlighter.color(forCapture: "string.special.url"), AppColors.sxString)
        XCTAssertEqual(CodeHighlighter.color(forCapture: "function.method.call"), AppColors.sxFunc)
        // Deliberately uncoloured: every identifier is captured as @variable by the official
        // JavaScript and Python queries, and colouring them all looks like a rainbow.
        XCTAssertNil(CodeHighlighter.color(forCapture: "variable"))
        XCTAssertNil(CodeHighlighter.color(forCapture: "punctuation.bracket"))
    }
}
