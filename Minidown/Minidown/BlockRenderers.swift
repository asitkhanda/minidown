import AppKit
import Foundation

extension NSAttributedString.Key {
    /// Glyphs with this attribute are omitted from layout (zero width) via CollapsingLayoutManager.
    static let mdCollapse = NSAttributedString.Key("minidown.collapse")
    static let mdBullet = NSAttributedString.Key("minidown.bullet")
    static let mdTask = NSAttributedString.Key("minidown.task")
    /// CodeMirror-style block/inline replace widget painted by CollapsingLayoutManager.
    static let mdBlockWidget = NSAttributedString.Key("minidown.blockWidget")
}

/// Presentation-only widget replacing a markdown construct while the caret is outside it.
/// The underlying characters stay in NSTextStorage unchanged (byte-faithful).
final class MDBlockWidget: NSObject {
    enum Kind: Equatable {
        case image(url: String, alt: String)
        case table(raw: String)
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

// MARK: - Caches

enum WidgetImageCache {
    private static var images: [String: NSImage] = [:]
    private static var loading: Set<String> = []
    private static var inFlight: [String: [(NSImage?) -> Void]] = [:]

    static func image(forKey key: String) -> NSImage? { images[key] }

    static func store(_ image: NSImage, forKey key: String) {
        images[key] = image
    }

    static func loadImage(url: URL, key: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = images[key] {
            completion(cached)
            return
        }
        inFlight[key, default: []].append(completion)
        guard !loading.contains(key) else { return }
        loading.insert(key)

        if url.isFileURL {
            let img = NSImage(contentsOf: url)
            finish(key: key, image: img)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let img = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                finish(key: key, image: img)
            }
        }.resume()
    }

    private static func finish(key: String, image: NSImage?) {
        loading.remove(key)
        if let image { images[key] = image }
        let waiters = inFlight.removeValue(forKey: key) ?? []
        waiters.forEach { $0(image) }
    }
}

enum WidgetRenderCache {
    private static var bitmaps: [String: NSImage] = [:]

    static func bitmap(forKey key: String) -> NSImage? { bitmaps[key] }

    static func store(_ image: NSImage, forKey key: String) {
        bitmaps[key] = image
    }
}

// MARK: - Table → bitmap

enum TableRenderer {
    static func bitmap(
        from raw: String,
        maxWidth: CGFloat,
        dark: Bool,
        fontFamily: EditorFontFamily = .sansSerif
    ) -> NSImage {
        _ = dark
        let attr = attributedTable(from: raw, fontFamily: fontFamily)
        let constraint = CGSize(width: max(120, maxWidth), height: .greatestFiniteMagnitude)
        let bounds = attr.boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let canvas = CGSize(
            width: ceil(max(bounds.width, 80)),
            height: ceil(max(bounds.height, 24))
        )
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        attr.draw(
            with: NSRect(origin: .zero, size: canvas),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        image.unlockFocus()
        return image
    }

    static func attributedTable(
        from raw: String,
        fontFamily: EditorFontFamily = .sansSerif
    ) -> NSAttributedString {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("|") }

        guard lines.count >= 2 else {
            return NSAttributedString(string: raw)
        }

        func cells(_ line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if parts.first?.isEmpty == true { parts.removeFirst() }
            if parts.last?.isEmpty == true { parts.removeLast() }
            return parts
        }

        let header = cells(lines[0])
        let aligns: [NSTextAlignment] = cells(lines[1]).map { part in
            let left = part.hasPrefix(":")
            let right = part.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            if left { return .left }
            return .natural
        }
        let rows = lines.dropFirst(2).map(cells)

        let table = NSTextTable()
        table.numberOfColumns = max(header.count, 1)
        let result = NSMutableAttributedString()

        func appendRow(_ values: [String], headerRow: Bool, rowIndex: Int) {
            for (col, value) in values.enumerated() {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: col,
                    columnSpan: 1
                )
                block.setBorderColor(AppColors.syntax)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                if headerRow {
                    block.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06)
                }
                let ps = NSMutableParagraphStyle()
                ps.textBlocks = [block]
                if col < aligns.count { ps.alignment = aligns[col] }
                let font = headerRow
                    ? fontFamily.font(ofSize: 14, weight: .semibold)
                    : fontFamily.font(ofSize: 14)
                result.append(
                    NSAttributedString(
                        string: value + (col == values.count - 1 ? "\n" : "\t"),
                        attributes: [
                            .font: font,
                            .foregroundColor: AppColors.foreground,
                            .paragraphStyle: ps,
                        ]
                    )
                )
            }
        }

        appendRow(header, headerRow: true, rowIndex: 0)
        for (i, row) in rows.enumerated() {
            appendRow(row, headerRow: false, rowIndex: i + 1)
        }
        return result
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
        if urlString.hasPrefix("/"), let url = URL(string: "file://\(urlString)") {
            return url
        }
        guard let directoryURL else { return nil }
        return directoryURL.appendingPathComponent(urlString)
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
