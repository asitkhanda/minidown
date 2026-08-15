import Foundation
import Markdown

/// Markdown → HTML for export.
///
/// Replaces a hand-rolled line-based renderer that silently dropped lists, tables, task lists,
/// images, rules, setext headings, multi-line blockquotes and nested emphasis — every non-empty
/// line became its own `<p>`, so hard-wrapped prose shattered into one paragraph per line.
///
/// swift-markdown ships `HTMLFormatter`, which handles all of that from the same AST the editor
/// uses. It is subclassed here to fix two defects: `visitImage` drops alt text entirely, and link
/// and image destinations are interpolated into attributes without escaping.
enum HTMLExport {
    static func build(_ source: String, forPrint: Bool) -> String {
        let parsed = parse(source)
        let body = renderBody(parsed.body)

        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(parsed.title ?? "Untitled"))</title>
        <style>\(forPrint ? printCSS : css)</style>
        """
        // Heavy dependencies are referenced only when the document actually uses them, so a
        // plain document exports as a standalone file that needs no network at all.
        if parsed.usesMath {
            head += #"<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css">"#
            head += #"<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.js"></script>"#
            head += #"<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/contrib/auto-render.min.js"></script>"#
            // Only `$$…$$` and Pandoc-style `$…$` are treated as math, matching the editor, so
            // prices like "$5 and $10" are not rendered as formulae.
            head += """
            <script>document.addEventListener('DOMContentLoaded',function(){renderMathInElement(document.body,{\
            delimiters:[{left:'$$',right:'$$',display:true},{left:'\\\\[',right:'\\\\]',display:true},\
            {left:'\\\\(',right:'\\\\)',display:false}],throwOnError:false});});</script>
            """
        }
        if parsed.usesMermaid {
            head += #"<script type="module">import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';mermaid.initialize({startOnLoad:true});</script>"#
        }
        return "<!doctype html>\n<html lang=\"en\"><head>\n\(head)\n</head><body>\n\(body)\n</body></html>\n"
    }

    /// Body markup only, for the in-app print container.
    static func renderBody(_ markdown: String) -> String {
        let document = Document(parsing: markdown, options: .disableSmartOpts)
        var formatter = MinidownHTMLFormatter()
        formatter.visit(document)
        return formatter.result
    }

    struct Parsed {
        var body: String
        var title: String?
        var usesMath: Bool
        var usesMermaid: Bool
    }

    static func parse(_ source: String) -> Parsed {
        var body = source
        var title: String?

        // Reuse the editor's frontmatter rule rather than scanning the whole document for the next
        // `\n---\n`, which could delete content from any file opening with a thematic break.
        if let end = frontmatterEnd(in: source) {
            let ns = source as NSString
            let frontmatter = ns.substring(to: end)
            body = ns.substring(from: end)
            if let match = frontmatter.range(of: #"(?m)^title:\s*(.+)$"#, options: .regularExpression) {
                title = String(frontmatter[match])
                    .replacingOccurrences(of: #"^title:\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        if title == nil {
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { continue }
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level >= 1, level <= 6 {
                    title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        return Parsed(
            body: body,
            title: title,
            usesMath: documentUsesMath(body),
            usesMermaid: body.range(of: #"(?m)^\s*```mermaid\s*$"#, options: .regularExpression) != nil
        )
    }

    /// The old sniffer was `\$[^\s$]`, which matches `$5`. A document mentioning prices therefore
    /// loaded KaTeX and rendered "$5 and $10" as a formula — the exact case the editor is careful
    /// to avoid. This reuses the editor's Pandoc dollar rules.
    static func documentUsesMath(_ body: String) -> Bool {
        let constructs = MarkdownParser.parse(body)
        return constructs.contains { construct in
            switch construct.kind {
            case .inlineMath, .blockMath: return true
            default: return false
            }
        }
    }

    private static func frontmatterEnd(in text: String) -> Int? {
        let constructs = MarkdownParser.parse(text)
        for construct in constructs {
            if case .frontmatter = construct.kind { return construct.to }
        }
        return nil
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Stylesheet

    static let css = """
    :root { color-scheme: light dark; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      font-size: 17px; line-height: 1.75; max-width: 42rem;
      margin: 0 auto; padding: 3rem 1.5rem 6rem;
      color: #1c1c1c; background: #fbfbfa;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #d8d8d3; background: #1b1b1d; }
      td, th { border-color: #4f4f4b !important; }
      blockquote { border-color: #4f4f4b !important; color: #8f8f88 !important; }
      hr { background: #4f4f4b !important; }
    }
    h1 { font-size: 1.55em; } h2 { font-size: 1.3em; } h3 { font-size: 1.15em; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.5em; }
    code { font-family: ui-monospace, SF Mono, Menlo, monospace; font-size: 0.88em;
      background: rgba(27,27,29,0.05); border-radius: 4px; padding: 0.1em 0.25em; }
    pre { background: rgba(27,27,29,0.05); border-radius: 8px; padding: 0.8rem 1rem; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0; padding-left: 1rem; border-left: 3px solid #b0b0a8; color: #6f6f68; font-style: italic; }
    a { color: #1c7ed6; }
    img { max-width: 100%; height: auto; border-radius: 6px; }
    hr { border: 0; height: 1px; background: #b0b0a8; margin: 2.5em 0; }
    table { border-collapse: collapse; margin: 1.2em 0; width: 100%; }
    th, td { border: 1px solid #b0b0a8; padding: 0.4em 0.8em; text-align: left; }
    th { font-weight: 650; background: rgba(27,27,29,0.05); }
    ul, ol { padding-left: 1.4em; }
    li { margin: 0.2em 0; }
    li input[type="checkbox"] { margin-right: 0.4em; }
    ul:has(> li > input[type="checkbox"]) { list-style: none; padding-left: 0.4em; }
    .footnotes { margin-top: 3em; border-top: 1px solid #b0b0a8; padding-top: 1em; font-size: 0.9em; }
    sup.footnote-ref { font-size: 0.75em; vertical-align: super; }
    pre.mermaid { background: none; text-align: center; }
    @media print { body { background: #fff; color: #000; max-width: none; padding: 0; } }
    """

    /// The export stylesheet retargeted at the in-app print container.
    static let printCSS = css.replacingOccurrences(of: "body {", with: "#print-root {")
        .replacingOccurrences(of: "body { ", with: "#print-root { ")
}

/// `HTMLFormatter` with the gaps filled in.
private struct MinidownHTMLFormatter: MarkupWalker {
    private(set) var result = ""

    mutating func defaultVisit(_ markup: Markup) {
        let rendered = HTMLFormatter.format(markup)
        result += rendered
    }

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        // Mermaid fences become a container the client-side script picks up.
        if codeBlock.language == "mermaid" {
            result += "<pre class=\"mermaid\">\(HTMLExport.escape(codeBlock.code))</pre>\n"
            return
        }
        let language = codeBlock.language.map { " class=\"language-\(HTMLExport.escape($0))\"" } ?? ""
        result += "<pre><code\(language)>\(HTMLExport.escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        for child in paragraph.children { visit(child) }
        result += "</p>\n"
    }

    mutating func visitImage(_ image: Image) {
        // HTMLFormatter drops alt text and does not escape the destination.
        let source = HTMLExport.escape(image.source ?? "")
        let alt = HTMLExport.escape(image.plainText)
        var tag = "<img src=\"\(source)\" alt=\"\(alt)\""
        if let title = image.title, !title.isEmpty {
            tag += " title=\"\(HTMLExport.escape(title))\""
        }
        result += tag + " />"
    }

    mutating func visitLink(_ link: Link) {
        let destination = HTMLExport.escape(link.destination ?? "")
        result += "<a href=\"\(destination)\">"
        for child in link.children { visit(child) }
        result += "</a>"
    }

    mutating func visitText(_ text: Text) {
        result += HTMLExport.escape(text.string)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(HTMLExport.escape(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        for child in emphasis.children { visit(child) }
        result += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        for child in strong.children { visit(child) }
        result += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        for child in strikethrough.children { visit(child) }
        result += "</del>"
    }

    mutating func visitHeading(_ heading: Heading) {
        let level = min(max(heading.level, 1), 6)
        result += "<h\(level)>"
        for child in heading.children { visit(child) }
        result += "</h\(level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        for child in blockQuote.children { visit(child) }
        result += "</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br />\n"
    }

    /// Tracks whether the list currently being rendered is tight, so its items do not wrap their
    /// text in `<p>`. CommonMark makes tightness a property of the list, and swift-markdown does
    /// not surface it, so it is derived: a list is tight when no item holds more than one block.
    private var tightListDepth = 0

    private static func isTight(_ items: some Sequence<ListItem>) -> Bool {
        items.allSatisfy { Array($0.children).count <= 1 }
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let tight = Self.isTight(unorderedList.listItems)
        result += "<ul>\n"
        if tight { tightListDepth += 1 }
        for item in unorderedList.listItems { visitListItem(item) }
        if tight { tightListDepth -= 1 }
        result += "</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let tight = Self.isTight(orderedList.listItems)
        let start = orderedList.startIndex
        result += start == 1 ? "<ol>\n" : "<ol start=\"\(start)\">\n"
        if tight { tightListDepth += 1 }
        for item in orderedList.listItems { visitListItem(item) }
        if tight { tightListDepth -= 1 }
        result += "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        result += "<li>"
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            result += "<input type=\"checkbox\" disabled\(checked) />"
        }
        for child in listItem.children {
            // In a tight list the item's paragraph is rendered inline, not as a block.
            if tightListDepth > 0, let paragraph = child as? Paragraph {
                for inline in paragraph.children { visit(inline) }
            } else {
                visit(child)
            }
        }
        result += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }

        result += "<table>\n<thead>\n<tr>\n"
        for (column, child) in table.head.children.enumerated() {
            guard let cell = child as? Table.Cell else { continue }
            result += "<th\(style(column))>"
            for inner in cell.children { visit(inner) }
            result += "</th>\n"
        }
        result += "</tr>\n</thead>\n<tbody>\n"
        for rowMarkup in table.body.children {
            guard let row = rowMarkup as? Table.Row else { continue }
            result += "<tr>\n"
            for (column, child) in row.children.enumerated() {
                guard let cell = child as? Table.Cell else { continue }
                // colspan/rowspan of 0 mean the cell is covered by an earlier one.
                guard cell.colspan > 0, cell.rowspan > 0 else { continue }
                var attributes = style(column)
                if cell.colspan > 1 { attributes += " colspan=\"\(cell.colspan)\"" }
                if cell.rowspan > 1 { attributes += " rowspan=\"\(cell.rowspan)\"" }
                result += "<td\(attributes)>"
                for inner in cell.children { visit(inner) }
                result += "</td>\n"
            }
            result += "</tr>\n"
        }
        result += "</tbody>\n</table>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        // Raw HTML is escaped rather than passed through, matching the Tauri build's `html: false`.
        result += "<pre><code>\(HTMLExport.escape(html.rawHTML))</code></pre>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += HTMLExport.escape(inlineHTML.rawHTML)
    }
}
