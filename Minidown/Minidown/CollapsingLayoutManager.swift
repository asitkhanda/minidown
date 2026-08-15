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

/// Collapses markdown syntax glyphs and paints CodeMirror-style replace widgets.
///
/// Main-actor isolated: every entry point is TextKit layout or drawing, and the widget caches it
/// reads are main-actor too.
@MainActor
final class CollapsingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private var collapsedCharacters = IndexSet()
    private(set) var taskHitTargets: [(charRange: NSRange, checked: Bool)] = []
    private var blockWidgets: [MDBlockWidget] = []
    /// Anchor character index → inline widget. Anchors become control characters with a custom
    /// advance; the rest of each widget's source collapses to zero width.
    private var inlineWidgets: [Int: MDBlockWidget] = [:]

    /// Focus-mode paragraph. Everything outside it paints at `dimFactor`.
    ///
    /// Deliberately a layout-manager property rather than a text attribute: the dimmed region is a
    /// function of the caret, so it moves on every arrow key. Expressing it as an attribute made
    /// caret movement O(document) in attribute writes — and, because it was written as a
    /// `.foregroundColor`, it also destroyed the `NSColor.clear` that used to hide widget source
    /// text. Dimming at draw time is idempotent, invertible, and costs one `invalidateDisplay`.
    var focusRange: NSRange? {
        didSet {
            guard focusRange != oldValue else { return }
            invalidateDisplayForFocusChange(from: oldValue, to: focusRange)
        }
    }

    /// Set to 1 while a range selection is active — `drawBackground` also paints the selection
    /// highlight, and dimming a selection that extends past the focused paragraph looks broken.
    var dimFactor: CGFloat = 0.32

    /// Presentation inputs the drawing code needs to look up the right cached bitmap. Kept in sync
    /// by the coordinator so widget lookups use the same key the styler stored under.
    var isDark = false
    var fontFamily: EditorFontFamily = .sansSerif
    var documentDirectory: URL?

    private var effectiveDim: CGFloat {
        focusRange == nil ? 1 : max(0, min(1, dimFactor))
    }

    override init() {
        super.init()
        delegate = self
        // Without this, every invalidation forces the whole document to be laid out before the
        // next draw. With it, TextKit lays out only what the viewport needs.
        allowsNonContiguousLayout = true
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

        inlineWidgets = [:]
        storage.enumerateAttribute(.mdInlineWidget, in: full, options: []) { value, range, _ in
            guard let widget = value as? MDBlockWidget, range.length > 0 else { return }
            inlineWidgets[range.location] = widget
        }

        if full.length > 0 {
            invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
        // Deliberately no `ensureLayout(for:)` here. It forced a synchronous, whole-document
        // layout on every keystroke *and* every caret move. With non-contiguous layout enabled,
        // TextKit lays out lazily for whatever the viewport actually draws.
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
        guard !collapsedCharacters.isEmpty || !inlineWidgets.isEmpty else { return 0 }

        let count = glyphRange.length
        var newProps = Array(UnsafeBufferPointer(start: props, count: count))
        var changed = false

        for i in 0..<count {
            if inlineWidgets[charIndexes[i]] != nil {
                // Marks the glyph as a control character so the delegate can give it a bespoke
                // advance — the only way to make a run of text occupy a custom width in TextKit 1
                // without inserting an attachment character into the document.
                newProps[i].insert(.controlCharacter)
                changed = true
            } else if collapsedCharacters.contains(charIndexes[i]) {
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

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        inlineWidgets[charIndex] != nil ? .whitespace : action
    }

    /// The returned width becomes the glyph's advance — this is what makes an inline widget take
    /// up exactly as much room as the formula it stands in for.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: CGRect,
        glyphPosition: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        guard let widget = inlineWidgets[charIndex] else { return .zero }
        // Never wider than the remaining space on the line, so a long formula cannot be pushed
        // off the right edge and clipped — `.whitespace` glyphs are elastic and will not wrap.
        let remaining = max(24, textContainer.size.width - glyphPosition.x - 8)
        return CGRect(
            x: 0,
            y: 0,
            width: min(widget.size.width, remaining),
            height: widget.size.height
        )
    }

    /// Grows the line so a tall inline widget is not clipped by its neighbours' line height.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard !inlineWidgets.isEmpty else { return false }
        let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var tallest: CGFloat = 0
        for (anchor, widget) in inlineWidgets where NSLocationInRange(anchor, charRange) {
            tallest = max(tallest, widget.size.height)
        }
        guard tallest > lineFragmentUsedRect.pointee.height else { return false }

        let extra = tallest - lineFragmentUsedRect.pointee.height
        // Both rects must grow: the fragment rect drives where the next line starts, the used rect
        // drives the container's used size and therefore the text view's height and dirty rects.
        lineFragmentRect.pointee.size.height += extra
        lineFragmentUsedRect.pointee.size.height += extra
        baselineOffset.pointee += extra
        return true
    }

    /// Suppresses painting for `.mdHidden` runs. The glyphs still lay out and keep their advance —
    /// they are simply never drawn. Attribute-driven, so no character-index mapping is needed here.
    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<CGPoint>,
        count glyphCount: Int,
        font: NSFont,
        textMatrix: CGAffineTransform,
        attributes: [NSAttributedString.Key: Any],
        in CGContext: CGContext
    ) {
        guard attributes[.mdHidden] == nil else { return }
        super.showCGGlyphs(
            glyphs,
            positions: positions,
            count: glyphCount,
            font: font,
            textMatrix: textMatrix,
            attributes: attributes,
            in: CGContext
        )
    }

    /// Backgrounds are a separate pass from glyphs, so focus dimming has to be applied here too —
    /// otherwise inline-code and code-fence bands stay at full strength under dimmed text, which
    /// reads worse than no focus mode at all.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let dim = effectiveDim
        let ctx = NSGraphicsContext.current?.cgContext
        for span in focusSpans(in: glyphsToShow) {
            guard span.range.length > 0 else { continue }
            if span.dimmed, dim < 1, let ctx {
                ctx.saveGState()
                ctx.setAlpha(dim)
                super.drawBackground(forGlyphRange: span.range, at: origin)
                ctx.restoreGState()
            } else {
                super.drawBackground(forGlyphRange: span.range, at: origin)
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let dim = effectiveDim
        let ctx = NSGraphicsContext.current?.cgContext

        for span in focusSpans(in: glyphsToShow) {
            guard span.range.length > 0 else { continue }
            if span.dimmed, dim < 1, let ctx {
                ctx.saveGState()
                ctx.setAlpha(dim)
                super.drawGlyphs(forGlyphRange: span.range, at: origin)
                ctx.restoreGState()
            } else {
                super.drawGlyphs(forGlyphRange: span.range, at: origin)
            }
        }

        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.mdBullet, in: charRange, options: []) { value, range, _ in
            guard value as? Bool == true else { return }
            drawSymbol(
                "•",
                forCharacterRange: range,
                origin: origin,
                color: AppColors.syntax,
                alpha: alpha(forCharacterRange: range)
            )
        }

        storage.enumerateAttribute(.mdTask, in: charRange, options: []) { value, range, _ in
            guard let checked = value as? Bool else { return }
            drawCheckbox(
                checked: checked,
                forCharacterRange: range,
                origin: origin,
                alpha: alpha(forCharacterRange: range)
            )
        }

        for widget in widgets(intersecting: charRange) {
            drawBlockWidget(widget, origin: origin, alpha: alpha(forCharacterRange: widget.sourceRange))
        }

        for (anchor, widget) in inlineWidgets where NSLocationInRange(anchor, charRange) {
            drawInlineWidget(widget, anchor: anchor, origin: origin, alpha: alpha(forCharacterRange: widget.sourceRange))
        }
    }

    /// Paints an inline widget sitting on the text baseline.
    private func drawInlineWidget(_ widget: MDBlockWidget, anchor: Int, origin: NSPoint, alpha: CGFloat) {
        guard case .math(let tex, let display) = widget.kind else { return }
        let glyph = glyphIndexForCharacter(at: anchor)
        guard numberOfGlyphs > 0, glyph < numberOfGlyphs else { return }
        var fragmentRange = NSRange()
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentRange)
        let location = self.location(forGlyphAt: glyph)

        guard let image = WidgetRenderCache.bitmap(
            forKey: WidgetCacheKey.math(tex: tex, display: display, dark: isDark)
        ) else { return }

        let fitted = WidgetSizing.fit(image.size, maxWidth: max(24, widget.size.width), maxHeight: fragment.height)

        // KaTeX reports how far its box extends *below* the baseline. Without that, the formula
        // sits visibly high — its descenders float above the surrounding text's baseline.
        let key = WidgetCacheKey.math(tex: tex, display: display, dark: isDark)
        var depth: CGFloat = 0
        if let measurement = WebBlockRenderer.shared.measurement(forKey: key), measurement.height > 0 {
            depth = measurement.depth * (fitted.height / measurement.height)
        }

        // `location` is the glyph's baseline position within the fragment.
        let baseline = fragment.minY + location.y
        let rect = CGRect(
            x: origin.x + location.x,
            y: origin.y + baseline + depth - fitted.height,
            width: fitted.width,
            height: fitted.height
        )
        withAlpha(alpha) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Widgets overlapping `charRange`, found by binary search rather than a full scan.
    ///
    /// Two reasons this matters. Correctness: the old test was `NSLocationInRange(widget.sourceRange
    /// .location, charRange)`, so a tall image vanished the moment its *first* line scrolled off,
    /// even with most of it still on screen. Performance: with non-contiguous layout enabled,
    /// touching an off-screen widget's geometry would force layout there and undo the benefit — so
    /// the range filter has to come before any `glyphIndexForCharacter` call.
    private func widgets(intersecting charRange: NSRange) -> ArraySlice<MDBlockWidget> {
        guard !blockWidgets.isEmpty else { return [] }
        let rangeEnd = NSMaxRange(charRange)

        // blockWidgets is built by enumerateAttribute, so it is already in document order.
        var low = 0
        var high = blockWidgets.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(blockWidgets[mid].sourceRange) <= charRange.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var end = low
        while end < blockWidgets.count, blockWidgets[end].sourceRange.location < rangeEnd {
            end += 1
        }
        return blockWidgets[low..<end]
    }

    // MARK: - Focus dimming

    /// Splits a glyph range into at most three spans: before the focused paragraph, the paragraph
    /// itself, and after it.
    private func focusSpans(in glyphsToShow: NSRange) -> [(range: NSRange, dimmed: Bool)] {
        guard focusRange != nil, effectiveDim < 1, let focus = focusRange else {
            return [(glyphsToShow, false)]
        }
        let focusGlyphs = glyphRange(forCharacterRange: focus, actualCharacterRange: nil)
        let lit = NSIntersectionRange(glyphsToShow, focusGlyphs)
        guard lit.length > 0 else { return [(glyphsToShow, true)] }

        var spans: [(range: NSRange, dimmed: Bool)] = []
        if lit.location > glyphsToShow.location {
            spans.append((
                NSRange(location: glyphsToShow.location, length: lit.location - glyphsToShow.location),
                true
            ))
        }
        spans.append((lit, false))
        let tailStart = NSMaxRange(lit)
        let end = NSMaxRange(glyphsToShow)
        if end > tailStart {
            spans.append((NSRange(location: tailStart, length: end - tailStart), true))
        }
        return spans
    }

    private func alpha(forCharacterRange range: NSRange) -> CGFloat {
        guard let focus = focusRange else { return 1 }
        return NSIntersectionRange(focus, range).length > 0 ? 1 : effectiveDim
    }

    /// A focus change repaints only the old and new paragraphs — no reparse, no attribute writes,
    /// no glyph or layout invalidation.
    private func invalidateDisplayForFocusChange(from old: NSRange?, to new: NSRange?) {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        // Dimming applies to everything *outside* the focused paragraph, so a move between two
        // paragraphs changes the appearance of both regions and everything between them.
        let candidates = [old, new].compactMap { $0 }.map { NSIntersectionRange($0, full) }
        guard let first = candidates.min(by: { $0.location < $1.location }),
              let last = candidates.max(by: { NSMaxRange($0) < NSMaxRange($1) })
        else {
            invalidateDisplay(forCharacterRange: full)
            return
        }
        invalidateDisplay(
            forCharacterRange: NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        )
    }

    /// The task checkbox drawn under `pointInContainer`, if any.
    ///
    /// Hit-tested against the painted checkbox rect rather than the marker's character range: the
    /// `[ ]` marker keeps its full advance width, so treating the whole run as a hit target meant a
    /// click anywhere in those three characters toggled instead of placing the caret.
    func taskTarget(at pointInContainer: NSPoint) -> (charRange: NSRange, checked: Bool)? {
        for target in taskHitTargets {
            if let hit = checkboxRect(forCharacterRange: target.charRange),
               hit.insetBy(dx: -2, dy: -2).contains(pointInContainer)
            {
                return target
            }
        }
        return nil
    }

    // Note: clicking a block widget to reveal its source needs no special hit testing. The widget's
    // first line keeps its full advance width (hidden, not collapsed), so NSTextView's own hit
    // testing already lands the caret inside the raw markdown.

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

    /// Runs `body` with the context alpha reduced. Preferred over `NSColor.withAlphaComponent`
    /// because the palette is built from dynamic `NSColor(name:)` providers, where mutating alpha
    /// resolves the colour eagerly against whatever appearance happens to be current.
    private func withAlpha(_ alpha: CGFloat, _ body: () -> Void) {
        guard alpha < 1, let ctx = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        body()
        ctx.restoreGState()
    }

    private func drawCheckbox(checked: Bool, forCharacterRange range: NSRange, origin: NSPoint, alpha: CGFloat) {
        guard let rect = checkboxRect(forCharacterRange: range) else { return }
        // Phosphor glyphs, template-rendered so they pick up the foreground colour the way SF
        // Symbols did. Regular weight for off, Fill for on — the same weight jump that makes the
        // state readable at a glance.
        let name = checked ? "checkbox-on" : "checkbox-off"
        guard let image = NSImage(named: name) else { return }
        image.isTemplate = true
        let target = rect.offsetBy(dx: origin.x, dy: origin.y)
        let tint = checked ? AppColors.accent : AppColors.syntax

        withAlpha(alpha) {
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
                return
            }
            // The tint has to happen inside a transparency layer. Applied straight to the context,
            // `sourceAtop` composites against the opaque page background and paints a solid block
            // instead of the glyph.
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
            ctx.setBlendMode(.sourceAtop)
            tint.setFill()
            NSBezierPath(rect: target).fill()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
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

    private func drawBlockWidget(_ widget: MDBlockWidget, origin: NSPoint, alpha: CGFloat) {
        withAlpha(alpha) {
            drawBlockWidgetBody(widget, origin: origin)
        }
    }

    private func drawBlockWidgetBody(_ widget: MDBlockWidget, origin: NSPoint) {
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
            if let image = WidgetImageCache.image(forKey: WidgetCacheKey.image(resolved: nil, raw: url))
                ?? imageForCurrentDocument(url) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: drawRect.width)
                let r = CGRect(x: drawRect.minX, y: drawRect.minY, width: fitted.width, height: fitted.height)
                image.draw(
                    in: r,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            } else {
                drawPlaceholder(in: drawRect, text: alt.isEmpty ? "Image" : alt)
            }

        case .table(let table):
            // Rendering here would rasterise inside the draw pass and mutate a cache while drawing;
            // the styler primes this entry when it installs the widget.
            if let image = WidgetRenderCache.bitmap(
                forKey: WidgetCacheKey.table(table, dark: isDark, fontFamily: fontFamily)
            ) {
                image.draw(
                    in: CGRect(origin: drawRect.origin, size: image.size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            } else {
                drawPlaceholder(in: drawRect, text: "Table")
            }

        case .math(let tex, let display):
            if let image = WidgetRenderCache.bitmap(
                forKey: WidgetCacheKey.math(tex: tex, display: display, dark: isDark)
            ) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: max(drawRect.width, image.size.width))
                image.draw(
                    in: CGRect(origin: drawRect.origin, size: fitted),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            } else {
                drawPlaceholder(in: drawRect, text: display ? "$$\(tex)$$" : "$\(tex)$")
            }

        case .mermaid(let source):
            if let image = WidgetRenderCache.bitmap(
                forKey: WidgetCacheKey.mermaid(source: source, dark: isDark)
            ) {
                let fitted = WidgetSizing.fit(image.size, maxWidth: drawRect.width)
                image.draw(
                    in: CGRect(origin: drawRect.origin, size: fitted),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            } else {
                drawPlaceholder(in: drawRect, text: "Rendering diagram…")
            }
        }
    }

    private func imageForCurrentDocument(_ url: String) -> NSImage? {
        guard let resolved = documentDirectory.map({ ImageSourceResolver.resolve(url, directoryURL: $0) }) ?? nil
        else { return nil }
        return WidgetImageCache.image(forKey: WidgetCacheKey.image(resolved: resolved, raw: url))
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

    private func drawSymbol(
        _ symbol: String,
        forCharacterRange range: NSRange,
        origin: NSPoint,
        color: NSColor,
        alpha: CGFloat
    ) {
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
        withAlpha(alpha) {
            text.draw(
                at: CGPoint(
                    x: origin.x + loc.x,
                    y: origin.y + frag.minY + (frag.height - size.height) / 2
                ),
                withAttributes: [.font: font, .foregroundColor: color]
            )
        }
    }
}
