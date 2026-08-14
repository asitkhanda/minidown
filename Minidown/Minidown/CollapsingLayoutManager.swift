import AppKit

/// Collapses markdown syntax glyphs and paints CodeMirror-style replace widgets.
final class CollapsingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private var collapsedCharacters = IndexSet()
    private(set) var taskHitTargets: [(charRange: NSRange, checked: Bool)] = []
    private var blockWidgets: [MDBlockWidget] = []

    override init() {
        super.init()
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshCollapsedGlyphs() {
        guard let storage = textStorage else { return }

        collapsedCharacters = IndexSet()
        taskHitTargets = []
        blockWidgets = []

        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mdCollapse, in: full, options: []) { value, range, _ in
            guard value as? Bool == true, range.length > 0 else { return }
            collapsedCharacters.insert(integersIn: range.location..<NSMaxRange(range))
        }

        storage.enumerateAttribute(.mdTask, in: full, options: []) { value, range, _ in
            guard value is Bool, range.length > 0 else { return }
            taskHitTargets.append((charRange: range, checked: (value as? Bool) ?? false))
        }

        storage.enumerateAttribute(.mdBlockWidget, in: full, options: []) { value, range, _ in
            guard let widget = value as? MDBlockWidget else { return }
            blockWidgets.append(widget)
            _ = range
        }

        if full.length > 0 {
            invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
        if let container = textContainers.first {
            ensureLayout(for: container)
        }
        invalidateDisplay(forCharacterRange: full)
    }

    // MARK: - NSLayoutManagerDelegate

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !collapsedCharacters.isEmpty else { return 0 }

        let count = glyphRange.length
        var newProps = Array(UnsafeBufferPointer(start: props, count: count))
        var changed = false

        for i in 0..<count {
            if collapsedCharacters.contains(charIndexes[i]) {
                newProps[i].insert(.null)
                changed = true
            }
        }

        guard changed else { return 0 }

        newProps.withUnsafeBufferPointer { buf in
            layoutManager.setGlyphs(
                glyphs,
                properties: buf.baseAddress!,
                characterIndexes: charIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
        }
        return count
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.mdBullet, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            drawSymbol("•", forCharacterRange: range, origin: origin, color: AppColors.syntax)
        }

        storage.enumerateAttribute(.mdTask, in: charRange, options: []) { value, range, _ in
            guard let checked = value as? Bool else { return }
            drawCheckbox(checked: checked, forCharacterRange: range, origin: origin)
        }

        for widget in blockWidgets where NSLocationInRange(widget.sourceRange.location, charRange) {
            drawBlockWidget(widget, origin: origin)
        }
    }

    func characterIndexForInteraction(at pointInContainer: NSPoint, fraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        guard let container = textContainers.first else { return 0 }
        let idx = characterIndex(
            for: pointInContainer,
            in: container,
            fractionOfDistanceBetweenInsertionPoints: fraction
        )

        for target in taskHitTargets {
            if let hit = checkboxRect(forCharacterRange: target.charRange),
               hit.insetBy(dx: -2, dy: -2).contains(pointInContainer)
            {
                return target.charRange.location
            }
        }

        // Clicking a block widget places the caret inside its source so raw markdown reveals.
        for widget in blockWidgets {
            if let rect = blockWidgetRect(for: widget), rect.contains(pointInContainer) {
                return widget.sourceRange.location
            }
        }
        return idx
    }

    func checkboxRect(forCharacterRange range: NSRange) -> CGRect? {
        let gRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard gRange.length > 0, gRange.location < numberOfGlyphs else { return nil }
        var fragRange = NSRange()
        let frag = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: &fragRange)
        let loc = location(forGlyphAt: gRange.location)
        let size: CGFloat = 14
        return CGRect(
            x: loc.x,
            y: frag.minY + (frag.height - size) / 2,
            width: size,
            height: size
        )
    }

    // MARK: - Drawing

    private func drawCheckbox(checked: Bool, forCharacterRange range: NSRange, origin: NSPoint) {
        guard let rect = checkboxRect(forCharacterRange: range) else { return }
        let name = checked ? "checkmark.square.fill" : "square"
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        image.draw(in: rect.offsetBy(dx: origin.x, dy: origin.y))
    }

    private func blockWidgetRect(for widget: MDBlockWidget) -> CGRect? {
        let anchor = min(widget.sourceRange.location, max(0, (textStorage?.length ?? 1) - 1))
        let g = glyphIndexForCharacter(at: anchor)
        guard numberOfGlyphs > 0, g < numberOfGlyphs else { return nil }
        var fragRange = NSRange()
        let frag = lineFragmentRect(forGlyphAt: g, effectiveRange: &fragRange)
        let loc = location(forGlyphAt: g)
        return CGRect(
            x: loc.x,
            y: frag.minY,
            width: max(widget.size.width, 1),
            height: max(widget.size.height, frag.height)
        )
    }

    private func drawBlockWidget(_ widget: MDBlockWidget, origin: NSPoint) {
        guard let rect = blockWidgetRect(for: widget) else { return }
        let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)

        switch widget.kind {
        case .hr:
            let y = drawRect.midY
            let path = NSBezierPath()
            path.move(to: CGPoint(x: drawRect.minX, y: y))
            path.line(to: CGPoint(x: drawRect.minX + max(drawRect.width, 120), y: y))
            AppColors.syntax.setStroke()
            path.lineWidth = 1
            path.stroke()

        case .image(let url, let alt):
            let key = "img:\(url)"
            if let image = WidgetImageCache.image(forKey: key) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: drawRect.width)
                let r = CGRect(x: drawRect.minX, y: drawRect.minY, width: fitted.width, height: fitted.height)
                image.draw(in: r)
            } else {
                drawPlaceholder(in: drawRect, text: alt.isEmpty ? "Image" : alt)
            }

        case .table(let raw):
            let key = "table:\(raw.hashValue)"
            if let image = WidgetRenderCache.bitmap(forKey: key) {
                image.draw(in: CGRect(origin: drawRect.origin, size: image.size))
            } else {
                let bitmap = TableRenderer.bitmap(from: raw, maxWidth: drawRect.width, dark: false)
                WidgetRenderCache.store(bitmap, forKey: key)
                bitmap.draw(in: CGRect(origin: drawRect.origin, size: bitmap.size))
            }

        case .math(let tex, let display):
            let keyPrefix = "katex:"
            // Exact key is owned by WebBlockRenderer; probe common variants via render cache prefix walk.
            if let image = findKatexImage(tex: tex, display: display) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: max(drawRect.width, image.size.width))
                image.draw(in: CGRect(origin: drawRect.origin, size: fitted))
            } else {
                drawPlaceholder(in: drawRect, text: display ? "$$\(tex)$$" : "$\(tex)$")
            }
            _ = keyPrefix

        case .mermaid(let source):
            if let image = findMermaidImage(source: source) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: drawRect.width)
                image.draw(in: CGRect(origin: drawRect.origin, size: fitted))
            } else {
                drawPlaceholder(in: drawRect, text: "Rendering diagram…")
            }
        }
    }

    private func findKatexImage(tex: String, display: Bool) -> NSImage? {
        for dark in [true, false] {
            let key = "katex:\(dark ? "d" : "l"):\(display ? "b" : "i"):\(tex)"
            if let img = WidgetRenderCache.bitmap(forKey: key) { return img }
        }
        return nil
    }

    private func findMermaidImage(source: String) -> NSImage? {
        for dark in [true, false] {
            let key = "mermaid:\(dark ? "d" : "l"):\(source)"
            if let img = WidgetRenderCache.bitmap(forKey: key) { return img }
        }
        return nil
    }

    private func drawPlaceholder(in rect: CGRect, text: String) {
        let bg = AppColors.codeBackground
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: AppColors.muted,
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(
            at: CGPoint(x: rect.minX + 10, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawSymbol(_ symbol: String, forCharacterRange range: NSRange, origin: NSPoint, color: NSColor) {
        guard let storage = textStorage else { return }
        let gRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard gRange.length > 0, gRange.location < numberOfGlyphs else { return }
        var fragRange = NSRange()
        let frag = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: &fragRange)
        let loc = location(forGlyphAt: gRange.location)
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17)
        let text = symbol as NSString
        let size = text.size(withAttributes: [.font: font])
        text.draw(
            at: CGPoint(
                x: origin.x + loc.x,
                y: origin.y + frag.minY + (frag.height - size.height) / 2
            ),
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }
}
