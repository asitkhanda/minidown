import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

enum ExportFormat: String {
    case pdf, html, docx, rtf, txt
}

enum Exporter {
    @MainActor
    static func export(_ markdown: String, format: ExportFormat, baseURL: URL?) {
        switch format {
        case .pdf:
            exportPDF(markdown)
        case .html:
            exportHTML(markdown, baseURL: baseURL)
        case .docx, .rtf, .txt:
            exportViaTextutil(markdown, format: format, baseURL: baseURL)
        }
    }

    @MainActor
    private static func exportPDF(_ markdown: String) {
        let html = HTMLExport.build(markdown, forPrint: true)
        let webView = PrintWebView(html: html)
        webView.runPrint()
    }

    @MainActor
    private static func exportHTML(_ markdown: String, baseURL: URL?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = defaultName(baseURL, ext: "html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = HTMLExport.build(markdown, forPrint: false)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    private static func exportViaTextutil(_ markdown: String, format: ExportFormat, baseURL: URL?) {
        let ext = format.rawValue
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = defaultName(baseURL, ext: ext)
        guard panel.runModal() == .OK, let output = panel.url else { return }

        let html = HTMLExport.build(markdown, forPrint: false)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidown-export-\(ProcessInfo.processInfo.processIdentifier).html")
        do {
            try html.write(to: tmp, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", ext, tmp.path, "-output", output.path]
            try process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: tmp)
            if process.terminationStatus == 0 {
                NSWorkspace.shared.open(output)
            } else {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = "textutil exited with status \(process.terminationStatus)"
                alert.runModal()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private static func defaultName(_ baseURL: URL?, ext: String) -> String {
        if let baseURL {
            return baseURL.deletingPathExtension().lastPathComponent + ".\(ext)"
        }
        return "Untitled.\(ext)"
    }
}

enum HTMLExport {
    static func build(_ source: String, forPrint: Bool) -> String {
        let parsed = parse(source)
        let body = renderMarkdownRough(parsed.body)
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(parsed.title ?? "Untitled"))</title>
        <style>\(css)</style>
        """
        if parsed.usesMath {
            head += #"<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css">"#
            head += #"<script src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.js"></script>"#
            head += #"<script src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/contrib/auto-render.min.js"></script>"#
            head += #"<script>document.addEventListener('DOMContentLoaded',()=>renderMathInElement(document.body,{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}]}));</script>"#
        }
        if parsed.usesMermaid {
            head += #"<script type="module">import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';mermaid.initialize({startOnLoad:true});</script>"#
        }
        return "<!doctype html>\n<html lang=\"en\"><head>\n\(head)\n</head><body>\n\(body)\n</body></html>\n"
    }

    private struct Parsed {
        var body: String
        var title: String?
        var usesMath: Bool
        var usesMermaid: Bool
    }

    private static func parse(_ source: String) -> Parsed {
        var body = source
        var title: String?
        if body.hasPrefix("---\n"), let end = body.range(of: "\n---\n") ?? body.range(of: "\n...\n") {
            let fm = String(body[body.index(body.startIndex, offsetBy: 4)..<end.lowerBound])
            body = String(body[end.upperBound...])
            if let match = fm.range(of: #"^title:\s*(.+)$"#, options: .regularExpression) {
                title = String(fm[match])
                    .replacingOccurrences(of: #"^title:\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        if title == nil {
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    let level = trimmed.prefix(while: { $0 == "#" }).count
                    if level >= 1 && level <= 6 {
                        title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
        }
        let usesMath = body.range(of: #"\$[^\s$]"#, options: .regularExpression) != nil
        let usesMermaid = body.contains("```mermaid")
        return Parsed(body: body, title: title, usesMath: usesMath, usesMermaid: usesMermaid)
    }

    /// Lightweight Markdown→HTML for export (not used by the editor).
    private static func renderMarkdownRough(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out = ""
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let info = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body = ""
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    if !body.isEmpty { body += "\n" }
                    body += lines[i]
                    i += 1
                }
                if info == "mermaid" {
                    out += "<pre class=\"mermaid\">\(escape(body))</pre>\n"
                } else {
                    out += "<pre><code>\(escape(body))</code></pre>\n"
                }
                i += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                out += "<h\(min(level, 6))>\(inline(String(text)))</h\(min(level, 6))>\n"
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                out += "<blockquote><p>\(inline(String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))))</p></blockquote>\n"
                i += 1
                continue
            }

            if trimmed.isEmpty {
                out += "\n"
                i += 1
                continue
            }

            out += "<p>\(inline(line))</p>\n"
            i += 1
        }
        return out
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        s = s.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"~~([^~]+)~~"#, with: "<del>$1</del>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        return s
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      font-size: 17px; line-height: 1.75; max-width: 42rem;
      margin: 0 auto; padding: 3rem 1.5rem 6rem;
      color: #1c1c1c; background: #fbfbfa;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #d8d8d3; background: #1b1b1d; }
    }
    code { font-family: ui-monospace, SF Mono, Menlo, monospace; font-size: 0.88em;
      background: rgba(27,27,29,0.05); border-radius: 4px; padding: 0.1em 0.25em; }
    pre { background: rgba(27,27,29,0.05); border-radius: 8px; padding: 0.8rem 1rem; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0; padding-left: 1rem; border-left: 3px solid #b0b0a8; color: #6f6f68; font-style: italic; }
    a { color: #1c7ed6; }
    @media print { body { background: #fff; color: #000; } }
    """
}

@MainActor
final class PrintWebView: NSObject, WKUIDelegate {
    private let webView: WKWebView
    private let html: String

    init(html: String) {
        self.html = html
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        super.init()
    }

    func runPrint() {
        webView.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let info = NSPrintInfo.shared
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.topMargin = 36
            info.bottomMargin = 36
            info.leftMargin = 36
            info.rightMargin = 36
            let op = NSPrintOperation(view: self.webView, printInfo: info)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }
    }
}
