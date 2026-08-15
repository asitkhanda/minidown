import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

enum ExportFormat: String {
    case pdf, html, docx, rtf, txt

    var utType: UTType? {
        switch self {
        case .pdf: return .pdf
        case .html: return .html
        case .docx: return UTType(filenameExtension: "docx")
        case .rtf: return .rtf
        case .txt: return .plainText
        }
    }
}

enum Exporter {
    @MainActor
    static func export(_ markdown: String, format: ExportFormat, baseURL: URL?) {
        switch format {
        case .pdf:
            printPDF(markdown)
        case .html:
            exportHTML(markdown, baseURL: baseURL)
        case .docx, .rtf, .txt:
            exportAttributed(markdown, format: format, baseURL: baseURL)
        }
    }

    // MARK: - PDF

    /// ⌘P opens the standard print panel, where "Save as PDF" lives, per the README.
    ///
    /// Two fixes over the previous implementation: it uses `WKWebView.printOperation(with:)`
    /// rather than `NSPrintOperation(view:)` — the former is WebKit's own paginating operation —
    /// and it waits for the page to actually finish instead of a fixed 0.8 second sleep that
    /// raced every render.
    @MainActor
    private static func printPDF(_ markdown: String) {
        let html = HTMLExport.build(markdown, forPrint: false)
        let printer = PrintWebView(html: html)
        printer.run()
    }

    // MARK: - HTML

    @MainActor
    private static func exportHTML(_ markdown: String, baseURL: URL?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = defaultName(baseURL, ext: "html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try HTMLExport.build(markdown, forPrint: false).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Word / RTF / plain text

    /// Converts through `NSAttributedString` rather than shelling out to `textutil`.
    ///
    /// `Process` cannot spawn inside the App Sandbox, so the subprocess had to go. Foundation's
    /// own HTML reader plus its `.docFormat` / `.rtf` writers cover the same ground without one,
    /// and without the temp file whose name collided across concurrent exports.
    @MainActor
    private static func exportAttributed(_ markdown: String, format: ExportFormat, baseURL: URL?) {
        let panel = NSSavePanel()
        if let type = format.utType {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = defaultName(baseURL, ext: format.rawValue)
        guard panel.runModal() == .OK, let output = panel.url else { return }

        let html = HTMLExport.build(markdown, forPrint: false)
        guard let htmlData = html.data(using: .utf8) else { return }

        do {
            let attributed = try NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
            let documentType: NSAttributedString.DocumentType
            switch format {
            case .docx: documentType = .officeOpenXML
            case .rtf: documentType = .rtf
            default: documentType = .plain
            }
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: documentType]
            )
            try data.write(to: output, options: .atomic)
            NSWorkspace.shared.open(output)
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

/// Loads the export HTML, waits for it to settle, then hands it to the print panel.
@MainActor
final class PrintWebView: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let html: String
    /// Holds itself alive until the print operation is done — the previous version relied on a
    /// closure incidentally capturing `self`.
    private var retain: PrintWebView?

    init(html: String) {
        self.html = html
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123))
        super.init()
        webView.navigationDelegate = self
    }

    func run() {
        retain = self
        // In a window so WebKit actually lays the content out before it is asked to paginate.
        if let host = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            let clip = NSView(frame: NSRect(x: -2, y: -2, width: 1, height: 1))
            clip.addSubview(webView)
            clip.alphaValue = 0.01
            host.contentView?.addSubview(clip, positioned: .below, relativeTo: nil)
        }
        webView.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.waitForContentThenPrint() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.present() }
    }

    /// Gives async content (KaTeX auto-render, mermaid) a chance to finish, but polls for a settled
    /// document height rather than assuming a fixed delay.
    private func waitForContentThenPrint(attempt: Int = 0, lastHeight: Int = -1) {
        let script = "document.body ? document.body.scrollHeight : 0"
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            Task { @MainActor in
                guard let self else { return }
                let height = (value as? NSNumber)?.intValue ?? 0
                let settled = height > 0 && height == lastHeight
                if settled || attempt >= 12 {
                    self.present()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        MainActor.assumeIsolated {
                            self.waitForContentThenPrint(attempt: attempt + 1, lastHeight: height)
                        }
                    }
                }
            }
        }
    }

    private func present() {
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36

        // WebKit's own print operation understands page breaks; NSPrintOperation(view:) does not.
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(
            for: NSApp.keyWindow ?? NSWindow(),
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc
    private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        webView.superview?.removeFromSuperview()
        retain = nil
    }
}
