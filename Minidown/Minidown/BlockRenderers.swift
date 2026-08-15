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
import Foundation

extension NSAttributedString.Key {
    /// Glyphs with this attribute are omitted from layout (zero width) via CollapsingLayoutManager.
    static let mdCollapse = NSAttributedString.Key("minidown.collapse")
    /// Glyphs with this attribute keep their advance but are never painted.
    ///
    /// This exists because hiding used to be expressed as `NSColor.clear`, which any later
    /// `.foregroundColor` write silently undid — focus mode did exactly that, resurrecting raw
    /// pipe syntax and image markup *underneath* the widgets still drawn on top. Hiding is now a
    /// property of the glyph, not of its colour, so no attribute write can reverse it.
    ///
    /// Distinct from `mdCollapse`: collapsed glyphs are `.null` (zero width), hidden glyphs keep
    /// their width. Task and bullet markers need the width so the drawn checkbox has somewhere to
    /// sit and the line does not reflow onto its predecessor.
    static let mdHidden = NSAttributedString.Key("minidown.hidden")
    static let mdBullet = NSAttributedString.Key("minidown.bullet")
    static let mdTask = NSAttributedString.Key("minidown.task")
    /// CodeMirror-style block/inline replace widget painted by CollapsingLayoutManager.
    static let mdBlockWidget = NSAttributedString.Key("minidown.blockWidget")
    /// An inline replace widget that flows with the text rather than owning its own line.
    ///
    /// Kept separate from `mdBlockWidget` because the mechanism is completely different: block
    /// widgets force a line height via `.paragraphStyle`, which AppKit fixes up across the whole
    /// paragraph — one inline `$x$` in a prose paragraph would clamp every line in it. Inline
    /// widgets instead give their anchor glyph a custom advance through the control-character
    /// delegate, which is the only TextKit 1 hook that can set one.
    static let mdInlineWidget = NSAttributedString.Key("minidown.inlineWidget")
}

/// Presentation-only widget replacing a markdown construct while the caret is outside it.
/// The underlying characters stay in NSTextStorage unchanged (byte-faithful).
final class MDBlockWidget: NSObject {
    enum Kind: Equatable {
        case image(url: String, alt: String)
        case table(MarkdownTable)
        case math(tex: String, display: Bool)
        case mermaid(source: String)
        case hr
    }

    let kind: Kind
    /// Full source range covered by this widget.
    let sourceRange: NSRange
    /// Desired paint size in container points (width may be capped by the text container).
    private(set) var size: CGSize

    init(kind: Kind, sourceRange: NSRange, size: CGSize) {
        self.kind = kind
        self.sourceRange = sourceRange
        self.size = size
    }

    func updateSize(_ newSize: CGSize) {
        size = newSize
    }
}

// MARK: - Cache keys

/// One place that builds widget cache keys.
///
/// The styler and the layout manager used to build table keys independently and disagreed — the
/// styler stored `table:<family>:<hash>` while the drawing code looked up `table:<hash>`. The cache
/// therefore never hit, so every table re-rendered on every draw pass, always in light mode.
enum WidgetCacheKey {
    /// Rendered widgets bake the palette into a bitmap, so the active theme is part of their
    /// identity — without it, switching themes would keep serving the previous theme's tables,
    /// formulae and diagrams from cache.
    private static var theme: String { ThemeStore.current.id }

    static func table(_ table: MarkdownTable, dark: Bool, fontFamily: EditorFontFamily) -> String {
        "table:\(theme):\(dark ? "d" : "l"):\(fontFamily.rawValue):\(table.cacheDescription)"
    }

    static func math(tex: String, display: Bool, dark: Bool) -> String {
        "katex:\(theme):\(dark ? "d" : "l"):\(display ? "b" : "i"):\(tex)"
    }

    static func mermaid(source: String, dark: Bool) -> String {
        "mermaid:\(theme):\(dark ? "d" : "l"):\(source)"
    }

    /// Keyed by resolved absolute URL, not the raw markdown string: with several documents open,
    /// the same relative path resolves to different files.
    static func image(resolved: URL?, raw: String) -> String {
        "img:\(resolved?.absoluteString ?? raw)"
    }
}

private extension MarkdownTable {
    /// Stable, collision-resistant description. `hashValue` is randomly seeded per process, which
    /// is fine within a run but makes cache keys impossible to reason about.
    var cacheDescription: String {
        var parts: [String] = alignments.map { alignment in
            switch alignment {
            case .left: return "l"
            case .center: return "c"
            case .right: return "r"
            case nil: return "-"
            }
        }
        parts.append("|")
        parts.append(contentsOf: header.map(\.text))
        for row in rows {
            parts.append("|")
            parts.append(contentsOf: row.map(\.text))
        }
        return parts.joined(separator: "\u{1F}")
    }
}

// MARK: - Caches

/// Bitmaps are large and unbounded in number — editing `$x$` into `$xy$` produces a new key per
/// keystroke — so these are size-limited caches, not dictionaries that grow forever.
@MainActor
enum WidgetImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static var inFlight: [String: [(NSImage?) -> Void]] = [:]

    static func image(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    static func store(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.approximateByteCost)
    }

    static func loadImage(url: URL, key: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = image(forKey: key) {
            completion(cached)
            return
        }
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            return
        }
        inFlight[key] = [completion]

        if url.isFileURL {
            // Off the main thread: decoding a large local image was blocking the styling pass.
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(contentsOf: url)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { finish(key: key, image: image) }
                }
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { finish(key: key, image: image) }
            }
        }.resume()
    }

    private static func finish(key: String, image: NSImage?) {
        if let image { store(image, forKey: key) }
        let waiters = inFlight.removeValue(forKey: key) ?? []
        waiters.forEach { $0(image) }
    }
}

@MainActor
enum WidgetRenderCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func bitmap(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    static func store(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.approximateByteCost)
    }
}

private extension NSImage {
    /// Rough backing-store size, so the cache limit means something.
    var approximateByteCost: Int {
        let pixels = representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh }
        return max(pixels * 4, Int(size.width * size.height * 4))
    }
}

// MARK: - Table → bitmap

/// Draws the grid directly rather than going through `NSTextTable`.
///
/// The previous implementation built an `NSAttributedString` of `NSTextTableBlock`s and called
/// `draw(with:)` on it. That path does not lay out text tables — the result had no borders, no
/// padding and no column separation, just cell text run together — and `boundingRect` under-measured
/// it, so what did draw was clipped.
enum TableRenderer {
    private static let cellPadding = CGSize(width: 10, height: 6)
    private static let borderWidth: CGFloat = 1

    static func image(
        for table: MarkdownTable,
        maxWidth: CGFloat,
        dark: Bool,
        fontFamily: EditorFontFamily = .sansSerif
    ) -> NSImage {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        let headerFont = fontFamily.font(ofSize: 14, weight: .semibold)
        let bodyFont = fontFamily.font(ofSize: 14)

        let columnCount = max(
            table.alignments.count,
            max(table.header.count, table.rows.map(\.count).max() ?? 0)
        )
        guard columnCount > 0 else { return NSImage(size: CGSize(width: 1, height: 1)) }

        let allRows = [table.header] + table.rows
        let columnWidths = Self.columnWidths(
            rows: allRows,
            columnCount: columnCount,
            headerFont: headerFont,
            bodyFont: bodyFont,
            maxWidth: maxWidth
        )
        let totalWidth = columnWidths.reduce(0, +) + borderWidth

        var rowHeights: [CGFloat] = []
        for (index, row) in allRows.enumerated() {
            let font = index == 0 ? headerFont : bodyFont
            var height: CGFloat = 0
            for column in 0..<columnCount {
                let text = column < row.count ? row[column].text : ""
                let available = max(1, columnWidths[column] - cellPadding.width * 2 - borderWidth)
                height = max(height, Self.textHeight(text, font: font, width: available))
            }
            rowHeights.append(height + cellPadding.height * 2)
        }
        let totalHeight = rowHeights.reduce(0, +) + borderWidth

        let canvas = CGSize(width: ceil(totalWidth), height: ceil(totalHeight))
        let image = NSImage(size: canvas, flipped: true) { _ in
            // Resolve dynamic colours against the editor's appearance, not whatever happens to be
            // current — the old renderer ignored its `dark` argument entirely.
            appearance.performAsCurrentDrawingAppearance {
                Self.draw(
                    table: table,
                    rows: allRows,
                    columnCount: columnCount,
                    columnWidths: columnWidths,
                    rowHeights: rowHeights,
                    headerFont: headerFont,
                    bodyFont: bodyFont,
                    canvas: canvas
                )
            }
            return true
        }
        return image
    }

    private static func draw(
        table: MarkdownTable,
        rows: [[MarkdownTable.Cell]],
        columnCount: Int,
        columnWidths: [CGFloat],
        rowHeights: [CGFloat],
        headerFont: NSFont,
        bodyFont: NSFont,
        canvas: CGSize
    ) {
        let border = AppColors.syntax
        let headerBackground = AppColors.codeBackground

        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let height = rowHeights[rowIndex]
            var x: CGFloat = 0

            if rowIndex == 0 {
                headerBackground.setFill()
                NSRect(x: 0, y: 0, width: canvas.width, height: height).fill()
            }

            for column in 0..<columnCount {
                let width = columnWidths[column]
                let cell = column < row.count ? row[column] : nil
                // colspan/rowspan of 0 mean "covered by an earlier cell" — skip drawing text.
                let covered = (cell?.colspan == 0) || (cell?.rowspan == 0)
                if let cell, !covered {
                    let alignment = column < table.alignments.count ? table.alignments[column] : nil
                    let rect = NSRect(
                        x: x + cellPadding.width,
                        y: y + cellPadding.height,
                        width: max(1, width - cellPadding.width * 2),
                        height: max(1, height - cellPadding.height * 2)
                    )
                    Self.drawText(
                        cell.text,
                        in: rect,
                        font: rowIndex == 0 ? headerFont : bodyFont,
                        alignment: alignment
                    )
                }
                x += width
            }
            y += height
        }

        // Grid lines last so they sit on top of the header fill.
        border.setStroke()
        let path = NSBezierPath()
        path.lineWidth = borderWidth
        var lineY: CGFloat = 0
        for height in [0] + rowHeights.map({ $0 }) {
            lineY += height
            path.move(to: CGPoint(x: 0, y: lineY))
            path.line(to: CGPoint(x: canvas.width, y: lineY))
        }
        var lineX: CGFloat = 0
        for width in [0] + columnWidths {
            lineX += width
            path.move(to: CGPoint(x: lineX, y: 0))
            path.line(to: CGPoint(x: lineX, y: canvas.height))
        }
        path.stroke()
    }

    private static func attributes(
        font: NSFont,
        alignment: MarkdownColumnAlignment?
    ) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        switch alignment {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        case nil: style.alignment = .natural
        }
        style.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: AppColors.foreground,
            .paragraphStyle: style,
        ]
    }

    private static func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        alignment: MarkdownColumnAlignment?
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, alignment: alignment))
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return ceil(font.ascender - font.descender) }
        let attributed = NSAttributedString(string: text, attributes: attributes(font: font, alignment: nil))
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(bounds.height)
    }

    private static func columnWidths(
        rows: [[MarkdownTable.Cell]],
        columnCount: Int,
        headerFont: NSFont,
        bodyFont: NSFont,
        maxWidth: CGFloat
    ) -> [CGFloat] {
        var natural = [CGFloat](repeating: 0, count: columnCount)
        for (rowIndex, row) in rows.enumerated() {
            let font = rowIndex == 0 ? headerFont : bodyFont
            for column in 0..<columnCount {
                let text = column < row.count ? row[column].text : ""
                let size = (text as NSString).size(withAttributes: [.font: font])
                natural[column] = max(natural[column], ceil(size.width) + cellPadding.width * 2 + borderWidth)
            }
        }

        let total = natural.reduce(0, +)
        guard total > maxWidth, total > 0 else { return natural }
        // Scale proportionally, but never below something a word can sit in.
        let minimum: CGFloat = 48
        let scale = max(0.1, maxWidth / total)
        return natural.map { max(minimum, floor($0 * scale)) }
    }
}

// MARK: - Resolve image URLs

enum ImageSourceResolver {
    static func resolve(_ urlString: String, directoryURL: URL?) -> URL? {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.hasPrefix("data:") {
            return URL(string: urlString)
        }
        if urlString.hasPrefix("file://") {
            return URL(string: urlString)
        }
        // Percent-decode so paths containing spaces resolve; `URL(string:)` would return nil.
        let decoded = urlString.removingPercentEncoding ?? urlString
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }
        guard let directoryURL else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: directoryURL).standardizedFileURL
    }
}

// MARK: - Fitted size helpers

enum WidgetSizing {
    static func fit(_ imageSize: CGSize, maxWidth: CGFloat, maxHeight: CGFloat = 480) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: min(240, maxWidth), height: 120)
        }
        let scale = min(1, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
        return CGSize(
            width: max(1, floor(imageSize.width * scale)),
            height: max(1, floor(imageSize.height * scale))
        )
    }

    static func placeholder(maxWidth: CGFloat, height: CGFloat = 72) -> CGSize {
        CGSize(width: min(maxWidth, 320), height: height)
    }
}
