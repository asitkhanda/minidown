import AppKit

enum LivePreviewStyler {
    struct Options {
        /// All insertion points / selected ranges, so multi-cursor editing reveals every construct
        /// it touches rather than only the ones under the primary selection.
        var selections: [NSRange]
        var directoryURL: URL?
        var isDark: Bool
        var fontFamily: EditorFontFamily = .sansSerif
        /// Fired on the main queue when an async widget (image / KaTeX / Mermaid) finishes loading.
        var onNeedsRefresh: (() -> Void)?

        init(
            selections: [NSRange],
            directoryURL: URL? = nil,
            isDark: Bool,
            fontFamily: EditorFontFamily = .sansSerif,
            onNeedsRefresh: (() -> Void)? = nil
        ) {
            self.selections = selections
            self.directoryURL = directoryURL
            self.isDark = isDark
            self.fontFamily = fontFamily
            self.onNeedsRefresh = onNeedsRefresh
        }

        init(
            selection: NSRange,
            directoryURL: URL? = nil,
            isDark: Bool,
            fontFamily: EditorFontFamily = .sansSerif,
            onNeedsRefresh: (() -> Void)? = nil
        ) {
            self.init(
                selections: [selection],
                directoryURL: directoryURL,
                isDark: isDark,
                fontFamily: fontFamily,
                onNeedsRefresh: onNeedsRefresh
            )
        }
    }

    static let bodyFontSize: CGFloat = 17
    static let contentWidth: CGFloat = 42 * 16

    @MainActor
    @discardableResult
    static func apply(to storage: NSTextStorage, text: String, options: Options) -> [MarkdownRange] {
        let constructs = MarkdownParser.parse(text)
        apply(to: storage, text: text, constructs: constructs, in: nil, options: options)
        return constructs
    }

    /// Styles `restyleRange`, or the whole document when it is nil.
    ///
    /// Parsing is always whole-document — parsing a slice silently changes meaning (a fence opened
    /// above it makes its contents markdown again). Only the *attribute writes* are narrowed, which
    /// is where the per-keystroke cost actually lives.
    @MainActor
    static func apply(
        to storage: NSTextStorage,
        text: String,
        constructs: [MarkdownRange],
        in restyleRange: NSRange?,
        options: Options
    ) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length == (text as NSString).length else { return }
        let ns = text as NSString
        let target = restyleRange.map { NSIntersectionRange($0, full) } ?? full
        guard target.length > 0 || full.length == 0 else { return }

        storage.beginEditing()
        defer { storage.endEditing() }

        let family = options.fontFamily
        let bodyFont = family.font(ofSize: bodyFontSize)
        let mono = family.monoFont(ofSize: bodyFontSize * 0.88)
        let baseParagraph = Self.baseParagraphStyle()
        let maxWidth = contentWidth

        // setAttributes replaces the whole dictionary for the range, so this is already a complete
        // reset — the custom keys and background/underline/strikethrough all go with it.
        storage.setAttributes(
            [
                .font: bodyFont,
                .foregroundColor: AppColors.foreground,
                .paragraphStyle: baseParagraph,
                .kern: 0,
            ],
            range: target
        )

        let reveal = RevealPolicy(selections: options.selections, text: text)

        for c in constructs where NSIntersectionRange(
            NSRange(location: c.from, length: max(0, c.to - c.from)),
            target
        ).length > 0 || (c.from == c.to && NSLocationInRange(c.from, target)) {
            let range = NSRange(location: c.from, length: max(0, c.to - c.from))
            guard range.location + range.length <= storage.length else { continue }
            let touches = reveal.touchesInline(range)
            let lineTouches = reveal.touchesLine(containing: c.from)
            // Block widgets use the stricter test: a selection spanning them is not editing them.
            let editingBlock = reveal.isEditing(range)
            let editingLine = reveal.isEditingLine(containing: c.from)

            switch c.kind {
            case .heading(let level):
                let scale: CGFloat = [1.55, 1.30, 1.15, 1.05, 1.0, 0.95][max(0, min(5, level - 1))]
                let font = family.font(ofSize: bodyFontSize * scale, weight: .semibold)
                let ps = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
                ps.paragraphSpacingBefore = level == 1 ? bodyFontSize : bodyFontSize * 0.55
                ps.paragraphSpacing = bodyFontSize * 0.15
                storage.addAttributes([.font: font, .paragraphStyle: ps], range: range)

            case .collapse(let revealFrom, let revealTo):
                // Marks hide unless the selection touches the *parent* construct, so the `**` of a
                // bold span reveal together rather than one at a time.
                let parent = NSRange(location: revealFrom, length: max(0, revealTo - revealFrom))
                let active = reveal.touchesInline(parent)
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
                    storage.addAttribute(.mdHidden, value: true, range: range)
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
                    storage.addAttribute(.mdHidden, value: true, range: range)
                } else {
                    storage.addAttribute(.foregroundColor, value: AppColors.syntax, range: range)
                }
                storage.addAttribute(.font, value: mono, range: range)

            case .thematicBreak:
                if !editingLine {
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
                    CodeHighlighter.apply(
                        to: storage,
                        codeRange: range,
                        source: text,
                        language: language
                    )
                }

            case .table(let table):
                if !editingBlock {
                    let key = WidgetCacheKey.table(table, dark: options.isDark, fontFamily: family)
                    let bitmap: NSImage
                    if let cached = WidgetRenderCache.bitmap(forKey: key) {
                        bitmap = cached
                    } else {
                        bitmap = TableRenderer.image(
                            for: table,
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
                        kind: .table(table),
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
                if !editingBlock {
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
                if !editingBlock {
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
                if !editingBlock {
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
                if !editingLine {
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

        // Focus dimming deliberately does NOT happen here. It used to reassign `.foregroundColor`
        // across everything outside the focused paragraph, which erased syntax, link, quote and
        // code colours — and, worse, overwrote the `NSColor.clear` that hid widget source text,
        // resurrecting raw pipe syntax and image markup underneath the widgets drawn on top.
        // Dimming is now a draw-time concern owned by CollapsingLayoutManager.focusRange.
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
        storage.addAttribute(.mdHidden, value: true, range: range)
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

    /// Installs an inline widget: the first character carries the widget and gets a custom advance,
    /// the rest collapse to nothing. No paragraph style is touched, so surrounding lines keep their
    /// normal height.
    @MainActor
    private static func installInlineWidget(
        in storage: NSTextStorage,
        range: NSRange,
        size: CGSize,
        kind: MDBlockWidget.Kind
    ) {
        guard range.length > 0 else { return }
        let widget = MDBlockWidget(kind: kind, sourceRange: range, size: size)
        let anchor = NSRange(location: range.location, length: 1)
        storage.addAttribute(.mdInlineWidget, value: widget, range: anchor)
        storage.addAttribute(.mdHidden, value: true, range: range)
        if range.length > 1 {
            storage.addAttribute(
                .mdCollapse,
                value: true,
                range: NSRange(location: range.location + 1, length: range.length - 1)
            )
        }
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
        let cacheKey = WidgetCacheKey.math(tex: tex, display: display, dark: options.isDark)
        var size = display
            ? WidgetSizing.placeholder(maxWidth: maxWidth, height: 64)
            : CGSize(width: min(maxWidth, 180), height: bodyFontSize * 1.2)

        if let cached = WidgetRenderCache.bitmap(forKey: cacheKey) {
            size = WidgetSizing.fit(cached.size, maxWidth: maxWidth)
        } else {
            WebBlockRenderer.shared.renderKatex(tex: tex, display: display, dark: options.isDark) { _ in
                options.onNeedsRefresh?()
            }
        }

        // Inline math flows with the sentence; only display math owns a line.
        guard display else {
            installInlineWidget(
                in: storage,
                range: range,
                size: size,
                kind: .math(tex: tex, display: false)
            )
            return
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

    /// Ranges whose glyphs are suppressed — collapsed to zero width or hidden — for this selection.
    ///
    /// Deliberately measured off a real `NSTextStorage` that has been through `apply`, rather than
    /// recomputed from the construct list. The previous version was a parallel implementation of
    /// the styling rules, so the tests built on it could not observe what `apply` actually did:
    /// the focus-mode overwrite, the table cache-key mismatch and the oversized math snapshots all
    /// shipped green.
    @MainActor
    static func hiddenMarkRanges(in text: String, selection: NSRange) -> [NSRange] {
        let storage = styledStorage(text: text, selection: selection)
        var out: [NSRange] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mdCollapse, in: full, options: []) { value, range, _ in
            if value as? Bool == true { out.append(range) }
        }
        storage.enumerateAttribute(.mdHidden, in: full, options: []) { value, range, _ in
            if value as? Bool == true, !out.contains(where: { NSEqualRanges($0, range) }) {
                out.append(range)
            }
        }
        return out.sorted { $0.location < $1.location }
    }

    /// Which replace widgets are actually installed for this selection.
    @MainActor
    static func activeBlockWidgetKinds(in text: String, selection: NSRange) -> [String] {
        let storage = styledStorage(text: text, selection: selection)
        var out: [String] = []
        let full = NSRange(location: 0, length: storage.length)
        for key in [NSAttributedString.Key.mdBlockWidget, .mdInlineWidget] {
            storage.enumerateAttribute(key, in: full, options: []) { value, _, _ in
                guard let widget = value as? MDBlockWidget else { return }
                switch widget.kind {
                case .table: out.append("table")
                case .math(_, let display): out.append(display ? "blockMath" : "inlineMath")
                case .mermaid: out.append("mermaid")
                case .image: out.append("image")
                case .hr: out.append("hr")
                }
            }
        }
        return out
    }

    @MainActor
    private static func styledStorage(text: String, selection: NSRange) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        apply(
            to: storage,
            text: text,
            options: .init(selection: selection, directoryURL: nil, isDark: false)
        )
        return storage
    }

    static func focusRange(in text: String, at location: Int) -> (from: Int, to: Int) {
        RevealPolicy.focusRange(in: text, at: location)
    }

    private static func baseParagraphStyle() -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.28
        ps.paragraphSpacing = 8
        ps.alignment = .natural
        return ps
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
