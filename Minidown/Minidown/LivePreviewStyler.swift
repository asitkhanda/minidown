import AppKit

enum LivePreviewStyler {
    struct Options {
        var selection: NSRange
        var focusMode: Bool
        var directoryURL: URL?
        var isDark: Bool
        var fontFamily: EditorFontFamily = .sansSerif
        /// Fired on the main queue when an async widget (image / KaTeX / Mermaid) finishes loading.
        var onNeedsRefresh: (() -> Void)?
    }

    static let bodyFontSize: CGFloat = 17
    static let contentWidth: CGFloat = 42 * 16

    @MainActor
    static func apply(to storage: NSTextStorage, text: String, options: Options) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length == (text as NSString).length else { return }

        storage.beginEditing()
        defer { storage.endEditing() }

        let family = options.fontFamily
        let bodyFont = family.font(ofSize: bodyFontSize)
        let mono = family.monoFont(ofSize: bodyFontSize * 0.88)
        let baseParagraph = Self.baseParagraphStyle()
        let maxWidth = contentWidth

        storage.setAttributes(
            [
                .font: bodyFont,
                .foregroundColor: AppColors.foreground,
                .paragraphStyle: baseParagraph,
                .kern: 0,
            ],
            range: full
        )
        storage.removeAttribute(.mdCollapse, range: full)
        storage.removeAttribute(.mdBullet, range: full)
        storage.removeAttribute(.mdTask, range: full)
        storage.removeAttribute(.mdBlockWidget, range: full)
        storage.removeAttribute(.backgroundColor, range: full)
        storage.removeAttribute(.underlineStyle, range: full)
        storage.removeAttribute(.strikethroughStyle, range: full)
        storage.removeAttribute(.baselineOffset, range: full)

        let constructs = MarkdownParser.parse(text)
        let focus = options.focusMode
            ? focusRange(in: text, at: options.selection.location)
            : nil
        let ns = text as NSString

        for c in constructs {
            let range = NSRange(location: c.from, length: max(0, c.to - c.from))
            guard range.location + range.length <= storage.length else { continue }
            let touches = selectionTouches(options.selection, range)
            let lineTouches = selectionTouchesLine(text: text, selection: options.selection, containing: c.from)

            switch c.kind {
            case .heading(let level):
                let scale: CGFloat = [1.55, 1.30, 1.15, 1.05, 1.0, 0.95][max(0, min(5, level - 1))]
                let font = family.font(ofSize: bodyFontSize * scale, weight: .semibold)
                let ps = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
                ps.paragraphSpacingBefore = level == 1 ? bodyFontSize : bodyFontSize * 0.55
                ps.paragraphSpacing = bodyFontSize * 0.15
                storage.addAttributes([.font: font, .paragraphStyle: ps], range: range)

            case .collapse(let revealFrom, let revealTo):
                let reveal = NSRange(location: revealFrom, length: max(0, revealTo - revealFrom))
                let active = selectionTouches(options.selection, reveal)
                if !active {
                    storage.addAttribute(.mdCollapse, value: true, range: range)
                }
                storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)

            case .collapseLine:
                // Don't null a line that already hosts a block widget (HR / table / etc.).
                let alreadyWidget =
                    storage.attribute(.mdBlockWidget, at: range.location, effectiveRange: nil) != nil
                if !lineTouches, !alreadyWidget {
                    storage.addAttribute(.mdCollapse, value: true, range: range)
                } else if lineTouches {
                    storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)
                }

            case .emphasis:
                storage.applyFontTrait(.italicFontMask, range: range)

            case .strong:
                storage.applyFontTrait(.boldFontMask, range: range)

            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

            case .inlineCode:
                storage.addAttributes(
                    [
                        .font: mono,
                        .foregroundColor: AppColors.code,
                        .backgroundColor: AppColors.codeBackground,
                    ],
                    range: range
                )

            case .linkText:
                storage.addAttributes(
                    [
                        .foregroundColor: AppColors.accent,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ],
                    range: range
                )

            case .blockquoteLine:
                let ps = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
                ps.firstLineHeadIndent = 16
                ps.headIndent = 16
                storage.addAttributes(
                    [
                        .foregroundColor: AppColors.quote,
                        .obliqueness: 0.12,
                        .paragraphStyle: ps,
                    ],
                    range: range
                )

            case .bulletMark:
                if !touches {
                    storage.addAttribute(.mdBullet, value: true, range: range)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                } else {
                    storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)
                }

            case .taskListMark:
                if !touches {
                    storage.addAttribute(.mdCollapse, value: true, range: range)
                }
                storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)

            case .taskMarker(let checked):
                if !touches {
                    storage.addAttribute(.mdTask, value: checked, range: range)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                } else {
                    storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)
                }
                storage.addAttribute(.font, value: mono, range: range)

            case .thematicBreak:
                if !lineTouches {
                    installWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        size: CGSize(width: maxWidth, height: 28),
                        kind: .hr,
                        options: options
                    )
                } else {
                    storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)
                }

            case .codeBlock(let language):
                storage.addAttributes(
                    [
                        .font: mono,
                        .backgroundColor: AppColors.codeBackground,
                    ],
                    range: range
                )
                if let language, !language.isEmpty {
                    CodeHighlighter.apply(to: storage, codeRange: range, source: text)
                }

            case .table:
                if !touches {
                    let raw = ns.substring(with: range)
                    let key = "table:\(family.rawValue):\(raw.hashValue)"
                    let bitmap: NSImage
                    if let cached = WidgetRenderCache.bitmap(forKey: key) {
                        bitmap = cached
                    } else {
                        bitmap = TableRenderer.bitmap(
                            from: raw,
                            maxWidth: maxWidth,
                            dark: options.isDark,
                            fontFamily: family
                        )
                        WidgetRenderCache.store(bitmap, forKey: key)
                    }
                    installWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        size: bitmap.size,
                        kind: .table(raw: raw),
                        options: options
                    )
                } else {
                    storage.addAttribute(.font, value: mono, range: range)
                }

            case .frontmatter:
                storage.addAttributes(
                    [
                        .font: mono,
                        .foregroundColor: AppColors.muted,
                    ],
                    range: range
                )

            case .footnoteRef:
                storage.addAttributes(
                    [
                        .font: family.font(ofSize: 11, weight: .semibold),
                        .baselineOffset: 6,
                        .foregroundColor: AppColors.accent,
                    ],
                    range: range
                )

            case .inlineMath(let tex):
                if !touches {
                    installMathWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        tex: tex,
                        display: false,
                        maxWidth: maxWidth,
                        options: options
                    )
                } else {
                    storage.addAttributes(
                        [
                            .foregroundColor: AppColors.accent,
                            .backgroundColor: AppColors.codeBackground,
                            .font: mono,
                        ],
                        range: range
                    )
                }

            case .blockMath(let tex):
                if !touches {
                    installMathWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        tex: tex,
                        display: true,
                        maxWidth: maxWidth,
                        options: options
                    )
                } else {
                    storage.addAttributes(
                        [
                            .foregroundColor: AppColors.accent,
                            .backgroundColor: AppColors.codeBackground,
                            .font: mono,
                        ],
                        range: range
                    )
                }

            case .mermaid(let source):
                if !touches {
                    installMermaidWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        source: source,
                        maxWidth: maxWidth,
                        options: options
                    )
                } else {
                    storage.addAttributes(
                        [
                            .font: mono,
                            .foregroundColor: AppColors.accent,
                            .backgroundColor: AppColors.codeBackground,
                        ],
                        range: range
                    )
                }

            case .image(let alt, let url):
                if !lineTouches {
                    installImageWidget(
                        in: storage,
                        ns: ns,
                        range: range,
                        alt: alt,
                        url: url,
                        maxWidth: maxWidth,
                        options: options
                    )
                }
            }
        }

        if let focus {
            let dim = AppColors.foreground.withAlphaComponent(0.32)
            if focus.from > 0 {
                storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: 0, length: focus.from))
            }
            if focus.to < storage.length {
                storage.addAttribute(
                    .foregroundColor,
                    value: dim,
                    range: NSRange(location: focus.to, length: storage.length - focus.to)
                )
            }
        }
    }

    // MARK: - Widget installers (CodeMirror replace-decoration equivalent)

    /// Hide source: first line keeps forced height for the widget; remaining lines collapse to zero.
    @MainActor
    private static func installWidget(
        in storage: NSTextStorage,
        ns: NSString,
        range: NSRange,
        size: CGSize,
        kind: MDBlockWidget.Kind,
        options: Options
    ) {
        let widget = MDBlockWidget(kind: kind, sourceRange: range, size: size)
        let firstLine = ns.lineRange(for: NSRange(location: range.location, length: 0))
        let anchor = NSIntersectionRange(firstLine, range)
        guard anchor.length > 0 else { return }

        let ps = baseParagraphStyle().mutableCopy() as! NSMutableParagraphStyle
        ps.minimumLineHeight = max(size.height, 24)
        ps.maximumLineHeight = max(size.height, 24)
        ps.paragraphSpacing = 8

        storage.addAttribute(.paragraphStyle, value: ps, range: anchor)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.addAttribute(.mdBlockWidget, value: widget, range: anchor)

        let restLocation = NSMaxRange(anchor)
        let restEnd = NSMaxRange(range)
        if restEnd > restLocation {
            storage.addAttribute(
                .mdCollapse,
                value: true,
                range: NSRange(location: restLocation, length: restEnd - restLocation)
            )
        }
    }

    @MainActor
    private static func installImageWidget(
        in storage: NSTextStorage,
        ns: NSString,
        range: NSRange,
        alt: String,
        url: String,
        maxWidth: CGFloat,
        options: Options
    ) {
        let key = "img:\(url)"
        var size = WidgetSizing.placeholder(maxWidth: maxWidth, height: 120)
        if let cached = WidgetImageCache.image(forKey: key) {
            size = WidgetSizing.fit(cached.size, maxWidth: maxWidth)
        } else if let resolved = ImageSourceResolver.resolve(url, directoryURL: options.directoryURL) {
            WidgetImageCache.loadImage(url: resolved, key: key) { _ in
                options.onNeedsRefresh?()
            }
        }

        installWidget(
            in: storage,
            ns: ns,
            range: range,
            size: size,
            kind: .image(url: url, alt: alt),
            options: options
        )
    }

    @MainActor
    private static func installMathWidget(
        in storage: NSTextStorage,
        ns: NSString,
        range: NSRange,
        tex: String,
        display: Bool,
        maxWidth: CGFloat,
        options: Options
    ) {
        let cacheKey = "katex:\(options.isDark ? "d" : "l"):\(display ? "b" : "i"):\(tex)"
        var size = display
            ? WidgetSizing.placeholder(maxWidth: maxWidth, height: 64)
            : CGSize(width: min(maxWidth, 180), height: 28)

        if let cached = WidgetRenderCache.bitmap(forKey: cacheKey) {
            size = WidgetSizing.fit(cached.size, maxWidth: maxWidth)
        } else {
            WebBlockRenderer.shared.renderKatex(tex: tex, display: display, dark: options.isDark) { _ in
                options.onNeedsRefresh?()
            }
        }

        installWidget(
            in: storage,
            ns: ns,
            range: range,
            size: size,
            kind: .math(tex: tex, display: display),
            options: options
        )
    }

    @MainActor
    private static func installMermaidWidget(
        in storage: NSTextStorage,
        ns: NSString,
        range: NSRange,
        source: String,
        maxWidth: CGFloat,
        options: Options
    ) {
        let cacheKey = "mermaid:\(options.isDark ? "d" : "l"):\(source)"
        var size = WidgetSizing.placeholder(maxWidth: maxWidth, height: 160)
        if let cached = WidgetRenderCache.bitmap(forKey: cacheKey) {
            size = WidgetSizing.fit(cached.size, maxWidth: maxWidth)
        } else {
            WebBlockRenderer.shared.renderMermaid(source: source, dark: options.isDark) { _ in
                options.onNeedsRefresh?()
            }
        }

        installWidget(
            in: storage,
            ns: ns,
            range: range,
            size: size,
            kind: .mermaid(source: source),
            options: options
        )
    }

    // MARK: - Tests / focus helpers

    static func hiddenMarkRanges(in text: String, selection: NSRange) -> [NSRange] {
        MarkdownParser.parse(text).compactMap { c in
            let range = NSRange(location: c.from, length: max(0, c.to - c.from))
            switch c.kind {
            case .collapse(let revealFrom, let revealTo):
                let reveal = NSRange(location: revealFrom, length: max(0, revealTo - revealFrom))
                return selectionTouches(selection, reveal) ? nil : range
            case .collapseLine, .thematicBreak:
                return selectionTouchesLine(text: text, selection: selection, containing: c.from) ? nil : range
            case .bulletMark, .taskListMark, .taskMarker:
                return selectionTouches(selection, range) ? nil : range
            default:
                return nil
            }
        }
    }

    /// Whether a block-level replace widget would be active for this selection (tests).
    static func activeBlockWidgetKinds(in text: String, selection: NSRange) -> [String] {
        MarkdownParser.parse(text).compactMap { c in
            let range = NSRange(location: c.from, length: max(0, c.to - c.from))
            let touches = selectionTouches(selection, range)
            let lineTouches = selectionTouchesLine(text: text, selection: selection, containing: c.from)
            switch c.kind {
            case .table where !touches: return "table"
            case .blockMath where !touches: return "blockMath"
            case .inlineMath where !touches: return "inlineMath"
            case .mermaid where !touches: return "mermaid"
            case .image where !lineTouches: return "image"
            case .thematicBreak where !lineTouches: return "hr"
            default: return nil
            }
        }
    }

    static func focusRange(in text: String, at location: Int) -> (from: Int, to: Int) {
        let ns = text as NSString
        let clamped = max(0, min(location, ns.length))
        let lineRange = ns.lineRange(for: NSRange(location: min(clamped, max(0, ns.length - 1)), length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            return (lineRange.location, NSMaxRange(lineRange))
        }
        var start = lineRange.location
        var end = NSMaxRange(lineRange)
        while start > 0 {
            let prev = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            if ns.substring(with: prev).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            start = prev.location
        }
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            if ns.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            end = NSMaxRange(next)
        }
        return (start, end)
    }

    private static func baseParagraphStyle() -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.28
        ps.paragraphSpacing = 8
        ps.alignment = .natural
        return ps
    }

    private static func selectionTouches(_ selection: NSRange, _ range: NSRange) -> Bool {
        selection.location <= NSMaxRange(range) && NSMaxRange(selection) >= range.location
    }

    private static func selectionTouchesLine(text: String, selection: NSRange, containing location: Int) -> Bool {
        let ns = text as NSString
        guard ns.length > 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length - 1), length: 0))
        return selectionTouches(selection, line)
    }
}

private extension NSMutableAttributedString {
    func applyFontTrait(_ trait: NSFontTraitMask, range: NSRange) {
        enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: LivePreviewStyler.bodyFontSize)
            let converted = NSFontManager.shared.convert(current, toHaveTrait: trait)
            addAttribute(.font, value: converted, range: subrange)
        }
    }
}
