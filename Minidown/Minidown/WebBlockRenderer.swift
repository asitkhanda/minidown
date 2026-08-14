import AppKit
import WebKit

/// Offscreen WKWebView snapshots for Mermaid diagrams and KaTeX math.
@MainActor
final class WebBlockRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WebBlockRenderer()

    /// Unit tests set this false so apply() never spins up WKWebView.
    static var isEnabled = true

    private var webView: WKWebView?
    private var queue: [(html: String, key: String, completion: (NSImage?) -> Void)] = []
    private var busy = false
    private var snapshotWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 640), configuration: config)
        view.navigationDelegate = self
        view.configuration.userContentController.add(self, name: "done")
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        return view
    }

    func renderMermaid(source: String, dark: Bool, completion: @escaping (NSImage?) -> Void) {
        guard Self.isEnabled else {
            completion(nil)
            return
        }
        let key = "mermaid:\(dark ? "d" : "l"):\(source)"
        if let cached = WidgetRenderCache.bitmap(forKey: key) {
            completion(cached)
            return
        }
        let theme = dark ? "dark" : "neutral"
        let bg = dark ? "#1b1b1d" : "#fbfbfa"
        let escaped = jsonEscape(source)
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;padding:16px;background:\(bg);}</style>
        </head><body>
        <div id="host"></div>
        <script type="module">
          import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
          mermaid.initialize({ startOnLoad: false, theme: '\(theme)', securityLevel: 'loose' });
          try {
            const { svg } = await mermaid.render('m1', \(escaped));
            document.getElementById('host').innerHTML = svg;
          } catch (e) {
            document.getElementById('host').textContent = String(e);
          }
          window.webkit.messageHandlers.done.postMessage('ok');
        </script>
        </body></html>
        """
        enqueue(html: html, key: key, completion: completion)
    }

    func renderKatex(tex: String, display: Bool, dark: Bool, completion: @escaping (NSImage?) -> Void) {
        guard Self.isEnabled else {
            completion(nil)
            return
        }
        let key = "katex:\(dark ? "d" : "l"):\(display ? "b" : "i"):\(tex)"
        if let cached = WidgetRenderCache.bitmap(forKey: key) {
            completion(cached)
            return
        }
        let fg = dark ? "#e8e6e3" : "#1b1b1d"
        let bg = dark ? "#1b1b1d" : "#fbfbfa"
        let escaped = jsonEscape(tex)
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css">
        <style>
          html,body{margin:0;padding:\(display ? "12px" : "2px 4px");background:\(bg);color:\(fg);}
          body{display:inline-block;}
          .err{color:#e4572e;font-family:ui-monospace,monospace;font-size:14px;}
        </style>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.js"></script>
        </head><body>
        <div id="host"></div>
        <script>
          try {
            katex.render(\(escaped), document.getElementById('host'), {
              displayMode: \(display ? "true" : "false"),
              throwOnError: false,
              strict: "ignore"
            });
          } catch (e) {
            const el = document.getElementById('host');
            el.className = 'err';
            el.textContent = \(escaped);
          }
          setTimeout(() => window.webkit.messageHandlers.done.postMessage('ok'), 40);
        </script>
        </body></html>
        """
        enqueue(html: html, key: key, completion: completion)
    }

    private func enqueue(html: String, key: String, completion: @escaping (NSImage?) -> Void) {
        queue.append((html, key, completion))
        pump()
    }

    private func pump() {
        guard !busy, let next = queue.first else { return }
        busy = true
        snapshotWorkItem?.cancel()
        ensureWebView().loadHTMLString(next.html, baseURL: URL(string: "https://cdn.jsdelivr.net/"))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let work = DispatchWorkItem { [weak self] in
                self?.finish(force: true)
            }
            self.snapshotWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.failCurrent()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.failCurrent()
        }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            self.finish(force: false)
        }
    }

    private func failCurrent() {
        guard busy, !queue.isEmpty else { return }
        snapshotWorkItem?.cancel()
        snapshotWorkItem = nil
        let item = queue.removeFirst()
        item.completion(nil)
        busy = false
        pump()
    }

    private func finish(force: Bool) {
        guard busy else { return }
        snapshotWorkItem?.cancel()
        snapshotWorkItem = nil

        let delay: UInt64 = force ? 0 : 80_000_000
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard let webView = self.webView else {
                self.failCurrent()
                return
            }
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                Task { @MainActor in
                    guard let self, !self.queue.isEmpty else { return }
                    let item = self.queue.removeFirst()
                    if let image {
                        WidgetRenderCache.store(image, forKey: item.key)
                    }
                    item.completion(image)
                    self.busy = false
                    self.pump()
                }
            }
        }
    }

    private func jsonEscape(_ s: String) -> String {
        // Top-level String is a JSON fragment — requires `.fragmentsAllowed` or
        // NSJSONSerialization throws NSInvalidArgumentException (paste crash on math/mermaid).
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
