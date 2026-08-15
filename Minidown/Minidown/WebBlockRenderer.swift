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
import WebKit

/// Renders Mermaid diagrams and KaTeX math for the editor, using assets bundled in the app.
///
/// Three things were wrong with the previous version and all of them showed on screen:
///
/// - It snapshotted the whole 900×640 web view because `WKSnapshotConfiguration.rect` was never
///   set, so a one-character `$x$` became a ~500pt-tall block of mostly background.
/// - The web view was never in a window. WebKit throttles rendering for windowless views, so
///   snapshots came back blank or stale, especially once web fonts were involved.
/// - The queue never de-duplicated in-flight keys, popped its item inside the async snapshot
///   callback (so a race could store an image under the wrong key), and had an early-return path
///   that left `busy` set forever, wedging the renderer for the rest of the session.
///
/// Mermaid now avoids snapshotting entirely: it hands back its SVG over the existing message
/// bridge and we rasterise that. KaTeX still needs a bitmap, but measures its own content box in
/// JavaScript and reports it back, so the snapshot is exactly the size of the formula.
@MainActor
final class WebBlockRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = WebBlockRenderer()

    /// Unit tests set this false so apply() never spins up WKWebView.
    static var isEnabled = true

    struct Measurement {
        let width: CGFloat
        let height: CGFloat
        /// Distance from the baseline to the bottom of the box, for inline alignment.
        let depth: CGFloat
    }

    private enum Job {
        case mermaid(source: String, key: String)
        case katex(tex: String, display: Bool, key: String)

        var key: String {
            switch self {
            case .mermaid(_, let key): return key
            case .katex(_, _, let key): return key
            }
        }
    }

    private var webView: WKWebView?
    private var renderWindow: NSWindow?
    private var queue: [Job] = []
    /// Completions keyed by job, so repeated requests for the same content coalesce instead of
    /// queueing another render. Typing used to grow this without bound.
    private var waiting: [String: [(NSImage?) -> Void]] = [:]
    private var current: Job?
    private var timeout: DispatchWorkItem?
    private(set) var measurements: [String: Measurement] = [:]

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func renderMermaid(source: String, dark: Bool, completion: @escaping (NSImage?) -> Void) {
        let key = WidgetCacheKey.mermaid(source: source, dark: dark)
        enqueue(.mermaid(source: source, key: key), completion: completion)
    }

    func renderKatex(tex: String, display: Bool, dark: Bool, completion: @escaping (NSImage?) -> Void) {
        let key = WidgetCacheKey.math(tex: tex, display: display, dark: dark)
        enqueue(.katex(tex: tex, display: display, key: key), completion: completion)
    }

    func measurement(forKey key: String) -> Measurement? { measurements[key] }

    // MARK: - Queue

    private func enqueue(_ job: Job, completion: @escaping (NSImage?) -> Void) {
        guard Self.isEnabled else {
            completion(nil)
            return
        }
        if let cached = WidgetRenderCache.bitmap(forKey: job.key) {
            completion(cached)
            return
        }
        // Already rendering or queued: just add a waiter.
        if waiting[job.key] != nil {
            waiting[job.key]?.append(completion)
            return
        }
        waiting[job.key] = [completion]
        queue.append(job)
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        current = job

        let html: String
        switch job {
        case .mermaid(let source, _):
            html = mermaidHTML(source: source, dark: job.key.hasPrefix("mermaid:d"))
        case .katex(let tex, let display, _):
            html = katexHTML(tex: tex, display: display, dark: job.key.hasPrefix("katex:d"))
        }

        // A stuck render must not wedge the queue: always have a way out.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.finish(job: job, image: nil) }
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)

        guard load(html: html, into: ensureWebView()) else {
            finish(job: job, image: nil)
            return
        }
    }

    /// Single exit point. Always clears `current` and pumps, so no path can leave the queue wedged.
    private func finish(job: Job, image: NSImage?, measurement: Measurement? = nil) {
        guard current?.key == job.key else { return }
        timeout?.cancel()
        timeout = nil
        current = nil

        if let image { WidgetRenderCache.store(image, forKey: job.key) }
        if let measurement { measurements[job.key] = measurement }

        let waiters = waiting.removeValue(forKey: job.key) ?? []
        waiters.forEach { $0(image) }
        pump()
    }

    // MARK: - Web view

    /// Hosted inside the key window, clipped to a 1×1 box and fully transparent.
    ///
    /// It has to be in a window: WebKit does not reliably render — and therefore does not
    /// reliably snapshot — a view that is not in one. `isHidden = true` does not work either,
    /// because hidden views do not render at all.
    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        view.navigationDelegate = self
        view.configuration.userContentController.add(self, name: "done")
        // `drawsBackground` is private API and was being set through KVC, which risks an
        // exception on any OS update. This is the public equivalent.
        view.underPageBackgroundColor = .clear

        // Its own window rather than borrowing the document's. WebKit will not reliably render a
        // view that is not in a window, and with a DocumentGroup there may be no window at all yet
        // — the renderer must not depend on whether a document happens to be open.
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.level = .normal
        host.alphaValue = 0.01
        host.ignoresMouseEvents = true
        host.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        host.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        host.contentView?.addSubview(view)
        // Far offscreen so it never shows, but still "on screen" as far as the compositor cares.
        host.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.orderFrontRegardless()
        renderWindow = host

        webView = view
        return view
    }

    /// Working directory holding a copy of the bundled assets plus the page being rendered.
    ///
    /// `loadHTMLString(_:baseURL:)` cannot pull local subresources under App Sandbox — the page
    /// loads but KaTeX's script, stylesheet and fonts are all blocked. `loadFileURL(_:
    /// allowingReadAccessTo:)` does work, but it needs the HTML and its assets under one readable
    /// directory, and the app bundle is not writable. So the assets are mirrored into Caches once
    /// and the page is written alongside them.
    private static let workingDirectory: URL? = {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("WebAssets") else { return nil }
        let fileManager = FileManager.default
        guard let caches = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let destination = caches.appendingPathComponent("WebAssets", isDirectory: true)
        let marker = destination.appendingPathComponent(".version")
        let version = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"

        let installed = (try? String(contentsOf: marker, encoding: .utf8)) == version
        if !installed {
            try? fileManager.removeItem(at: destination)
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundled.path) {
                for item in contents {
                    try? fileManager.copyItem(
                        at: bundled.appendingPathComponent(item),
                        to: destination.appendingPathComponent(item)
                    )
                }
            }
            try? version.write(to: marker, atomically: true, encoding: .utf8)
        }
        return destination
    }()

    /// Writes the page next to the assets and loads it as a file URL.
    private func load(html: String, into webView: WKWebView) -> Bool {
        guard let directory = Self.workingDirectory else { return false }
        let page = directory.appendingPathComponent("render.html")
        guard (try? html.write(to: page, atomically: true, encoding: .utf8)) != nil else { return false }
        webView.loadFileURL(page, allowingReadAccessTo: directory)
        return true
    }

    // MARK: - Documents

    private func mermaidHTML(source: String, dark: Bool) -> String {
        let theme = dark ? "dark" : "neutral"
        let background = dark ? "#1b1b1d" : "#fbfbfa"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;padding:12px;background:\(background);}</style>
        <script src="mermaid/mermaid.min.js"></script>
        </head><body>
        <div id="host"></div>
        <script>
          // Rendered by WebKit and snapshotted at the diagram's measured size.
          //
          // Handing the raw SVG back to NSImage was tried and looks wrong: NSImage's SVG support
          // drops <foreignObject>, mis-renders marker-end arrowheads as filled blobs, and
          // mispositions labels. WebKit draws what mermaid actually intended.
          (async () => {
            const post = (payload) => window.webkit.messageHandlers.done.postMessage(payload);
            const measure = () => {
              const svg = document.querySelector('#host svg');
              const rect = (svg || document.getElementById('host')).getBoundingClientRect();
              // Origin matters: the element sits at the body's padding offset, and snapshotting
              // from (0,0) clipped the right and bottom edges off every diagram.
              post({
                kind: 'measured',
                x: Math.max(0, Math.floor(rect.left)),
                y: Math.max(0, Math.floor(rect.top)),
                width: Math.max(1, Math.ceil(rect.width)),
                height: Math.max(1, Math.ceil(rect.height)),
                depth: 0
              });
            };
            try {
              // htmlLabels must be off: with it on, mermaid puts node labels inside
              // <foreignObject>, which NSImage's SVG renderer ignores — the diagram comes back
              // with correct shapes and no text in them at all.
              mermaid.initialize({
                startOnLoad: false,
                theme: '\(theme)',
                securityLevel: 'strict',
                htmlLabels: false,
                flowchart: { htmlLabels: false, useMaxWidth: false },
                sequence: { useMaxWidth: false },
                gantt: { useMaxWidth: false },
                class: { useMaxWidth: false },
                state: { useMaxWidth: false }
              });
              const { svg } = await mermaid.render('m1', \(jsonEscape(source)));
              document.getElementById('host').innerHTML = svg;
              if (document.fonts && document.fonts.ready) {
                await document.fonts.ready.catch(() => {});
              }
              // Timers, not requestAnimationFrame: the host view is deliberately near-invisible
              // so the compositor can throttle rAF indefinitely, and the render would never report.
              setTimeout(measure, 32);
            } catch (error) {
              document.getElementById('host').textContent = String(error);
              setTimeout(measure, 0);
            }
          })();
        </script>
        </body></html>
        """
    }

    private func katexHTML(tex: String, display: Bool, dark: Bool) -> String {
        let foreground = dark ? "#e8e6e3" : "#1b1b1d"
        let background = dark ? "#1b1b1d" : "#fbfbfa"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="katex/katex.min.css">
        <style>
          html,body{margin:0;padding:0;background:\(background);color:\(foreground);}
          #host{display:inline-block;padding:\(display ? "8px 12px" : "1px 2px");}
          .err{color:#e4572e;font-family:ui-monospace,monospace;font-size:14px;}
        </style>
        <script src="katex/katex.min.js"></script>
        </head><body>
        <div id="host"></div>
        <script>
          (function () {
            const host = document.getElementById('host');
            const post = (payload) => window.webkit.messageHandlers.done.postMessage(payload);
            try {
              katex.render(\(jsonEscape(tex)), host, {
                displayMode: \(display ? "true" : "false"),
                throwOnError: false,
                strict: "ignore"
              });
            } catch (error) {
              host.className = 'err';
              host.textContent = \(jsonEscape(tex));
            }
            // Report the real content box so the snapshot is the size of the formula rather than
            // the whole viewport, and report the depth so inline math can sit on the baseline.
            const measure = () => {
              const rect = host.getBoundingClientRect();
              let depth = 0;
              const base = host.querySelector('.katex-html .base');
              if (base) {
                const baseRect = base.getBoundingClientRect();
                const strut = base.querySelector('.strut');
                if (strut) {
                  const strutRect = strut.getBoundingClientRect();
                  depth = Math.max(0, baseRect.bottom - strutRect.bottom);
                }
              }
              post({
                kind: 'measured',
                x: Math.max(0, Math.floor(rect.left)),
                y: Math.max(0, Math.floor(rect.top)),
                width: Math.max(1, Math.ceil(rect.width)),
                height: Math.max(1, Math.ceil(rect.height)),
                depth: Math.ceil(depth)
              });
            };
            if (document.fonts && document.fonts.ready) {
              document.fonts.ready.then(measure).catch(measure);
            } else {
              measure();
            }
          })();
        </script>
        </body></html>
        """
    }

    // MARK: - Delegates

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.failCurrent() }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in self.failCurrent() }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in self.handle(body) }
    }

    private func failCurrent() {
        guard let job = current else { return }
        finish(job: job, image: nil)
    }

    private func handle(_ body: Any) {
        guard let job = current, let payload = body as? [String: Any] else { return }
        switch payload["kind"] as? String {
        case "measured":
            let x = (payload["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (payload["y"] as? NSNumber)?.doubleValue ?? 0
            let width = (payload["width"] as? NSNumber)?.doubleValue ?? 1
            let height = (payload["height"] as? NSNumber)?.doubleValue ?? 1
            let depth = (payload["depth"] as? NSNumber)?.doubleValue ?? 0
            snapshot(
                job: job,
                rect: CGRect(x: x, y: y, width: width, height: height),
                measurement: Measurement(width: width, height: height, depth: depth)
            )

        default:
            finish(job: job, image: nil)
        }
    }

    private func snapshot(job: Job, rect: CGRect, measurement: Measurement) {
        guard let webView else {
            finish(job: job, image: nil)
            return
        }
        let configuration = WKSnapshotConfiguration()
        // Without this the snapshot is the whole viewport — the cause of comically tall math.
        configuration.rect = rect
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor in
                self?.finish(job: job, image: image, measurement: measurement)
            }
        }
    }

    private func jsonEscape(_ s: String) -> String {
        // Top-level String is a JSON fragment — requires `.fragmentsAllowed` or
        // NSJSONSerialization throws NSInvalidArgumentException (paste crash on math/mermaid).
        let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        // JSON does not escape `/`, so a literal `</script>` inside the payload would close the
        // script element early and break out of it.
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }
}
