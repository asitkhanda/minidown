// minidown — a minimal, distraction-free Markdown writer for macOS.
// Copyright (C) 2026 Asit Khanda
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version. See <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Markdown

/// Column alignment for a GFM table, mirrored from swift-markdown so the parser stays AppKit-free.
enum MarkdownColumnAlignment: Equatable {
    case left
    case center
    case right
}

/// Structured table contents, captured during the AST walk.
///
/// The renderer used to re-split the raw pipe text itself, which meant alignment and cell contents
/// were parsed twice by two different sets of rules. This carries cmark's own answer instead.
struct MarkdownTable: Equatable {
    struct Cell: Equatable {
        let text: String
        /// 0 means "covered by an earlier cell" and must be skipped when laying out.
        let colspan: Int
        let rowspan: Int
    }

    let alignments: [MarkdownColumnAlignment?]
    let header: [Cell]
    let rows: [[Cell]]
}

/// Presentation-only construct ranges. Document text is never rewritten here.
struct MarkdownRange: Equatable {
    let from: Int
    let to: Int
    let kind: Kind

    enum Kind: Equatable {
        case heading(level: Int)
        /// Hide when selection does not touch `reveal` (typically the parent construct).
        case collapse(revealFrom: Int, revealTo: Int)
        case collapseLine
        case emphasis
        case strong
        case strikethrough
        case inlineCode
        case linkText
        case blockquoteLine
        case bulletMark
        /// Hide list marker (`- `) on task items — checkbox replaces it.
        case taskListMark
        case taskMarker(checked: Bool)
        case thematicBreak
        case codeBlock(language: String?)
        case table(MarkdownTable)
        case frontmatter
        case footnoteRef
        case inlineMath(tex: String)
        case blockMath(tex: String)
        case mermaid(source: String)
        case image(alt: String, url: String)
    }
}

/// Compiled once, not per line.
///
/// These used to be built inline: one per blockquote *line*, two per list *item*, and four per
/// `parseSupplemental` call. A 500-item document therefore compiled roughly a thousand
/// `NSRegularExpression`s on every keystroke, which dwarfed the actual cmark parse.
enum MarkdownPatterns {
    static let footnoteRef = regex(#"\[\^[^\s\[\]]+\]"#)
    /// Pandoc dollar rules: opening `$` followed by non-space, closing `$` preceded by non-space,
    /// so `$5 and $10` stays prose.
    static let inlineMath = regex(#"(?<!\$)\$(?![\s$])([^$\n]+?)(?<![\s$])\$(?!\$)"#)
    static let blockMath = regex(#"\$\$([\s\S]+?)\$\$"#)
    static let blockquoteMark = regex(#"^ {0,3}> ?"#)
    static let taskMarker = regex(#"\[([ xX])\]"#)
    /// Bare URLs. cmark-gfm's autolink extension is not attached by swift-markdown and cannot be
    /// enabled through its public API, so this is the only way to honour the documented behaviour.
    static let autolink = regex(#"(?<![\w@/.-])(https?://[^\s<>\)\]"'`]+[^\s<>\)\]"'`.,;:!?])"#)
    /// YAML-ish `key:` line, used to tell real frontmatter from a document opening with a rule.
    static let yamlKey = regex(#"^[A-Za-z_][\w.\-]*\s*:"#, options: .anchorsMatchLines)

    private static func regex(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programmer error, not input.
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("invalid built-in pattern: \(pattern)")
        }
        return expression
    }
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownRange] {
        var ranges: [MarkdownRange] = []
        let ns = text as NSString
        var body = text
        var bodyOffset = 0
        var protected = IndexSet()

        if let end = frontmatterEnd(in: text) {
            ranges.append(MarkdownRange(from: 0, to: end, kind: .frontmatter))
            body = ns.substring(from: end)
            bodyOffset = end
            protected.insert(integersIn: 0..<end)
        }

        let map = SourceMap(body)
        // `.disableSmartOpts` keeps cmark from rewriting quotes and dashes in Text nodes. Only
        // ranges are read today, but export reads the tree's text, and a silently transformed
        // document would violate round-trip fidelity.
        let document = Document(parsing: body, options: .disableSmartOpts)
        var collector = RangeCollector(map: map, base: bodyOffset, source: body)
        collector.visit(document)
        ranges.append(contentsOf: collector.ranges)
        protected.formUnion(collector.protected)

        ranges.append(contentsOf: parseSupplemental(text, protected: protected))

        return ranges.sorted {
            $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to)
        }
    }

    /// Frontmatter only when the document genuinely opens with a YAML block.
    ///
    /// A leading `---` is ambiguous: it is also a thematic break. Requiring a closing fence within
    /// a sane distance *and* at least one `key:` line stops a document that merely starts with a
    /// horizontal rule from having everything up to the next `---` swallowed as metadata.
    private static func frontmatterEnd(in text: String) -> Int? {
        let ns = text as NSString
        guard ns.length >= 3 else { return nil }
        let firstLine = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard ns.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }

        var loc = NSMaxRange(firstLine)
        var scannedLines = 0
        let maximumFrontmatterLines = 200
        while loc < ns.length, scannedLines < maximumFrontmatterLines {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let trimmed = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                let end = NSMaxRange(line)
                let interior = NSRange(
                    location: NSMaxRange(firstLine),
                    length: max(0, line.location - NSMaxRange(firstLine))
                )
                guard interior.length > 0 else { return nil }
                let hasKey = MarkdownPatterns.yamlKey.firstMatch(
                    in: text,
                    range: interior
                ) != nil
                return hasKey ? end : nil
            }
            loc = NSMaxRange(line)
            scannedLines += 1
        }
        // No closing fence — treat leading --- as a thematic break, not frontmatter.
        return nil
    }

    private static func parseSupplemental(_ text: String, protected: IndexSet) -> [MarkdownRange] {
        var out: [MarkdownRange] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        /// Regex-driven constructs must not fire inside code, HTML or link destinations. Without
        /// this a shell fence containing `cd $dir/$file` renders as math, `- [ ] item` inside a
        /// fence becomes a live checkbox, and a regex character class like `[^0-9]` anywhere
        /// becomes a footnote reference.
        func isProtected(_ range: NSRange) -> Bool {
            guard range.length > 0 else { return protected.contains(range.location) }
            return protected.intersects(integersIn: range.location..<NSMaxRange(range))
        }

        MarkdownPatterns.footnoteRef.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, !isProtected(match.range) else { return }
            out.append(
                MarkdownRange(
                    from: match.range.location,
                    to: NSMaxRange(match.range),
                    kind: .footnoteRef
                )
            )
        }

        MarkdownPatterns.inlineMath.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1, !isProtected(match.range) else { return }
            let inner = ns.substring(with: match.range(at: 1))
            out.append(
                MarkdownRange(
                    from: match.range.location,
                    to: NSMaxRange(match.range),
                    kind: .inlineMath(tex: inner)
                )
            )
        }

        MarkdownPatterns.blockMath.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.numberOfRanges > 1, !isProtected(match.range) else { return }
            let inner = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(
                MarkdownRange(
                    from: match.range.location,
                    to: NSMaxRange(match.range),
                    kind: .blockMath(tex: inner)
                )
            )
        }

        MarkdownPatterns.autolink.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, !isProtected(match.range) else { return }
            out.append(
                MarkdownRange(
                    from: match.range.location,
                    to: NSMaxRange(match.range),
                    kind: .linkText
                )
            )
        }

        return out
    }
}

private struct RangeCollector: MarkupWalker {
    let map: SourceMap
    let base: Int
    let source: String
    var ranges: [MarkdownRange] = []
    /// Regions the regex pass must not touch: code, raw HTML, link destinations.
    var protected = IndexSet()

    private func r(_ markup: Markup) -> NSRange? {
        guard let sr = markup.range else { return nil }
        var nsr = map.nsRange(from: sr)
        nsr.location += base
        return nsr
    }

    private mutating func add(_ kind: MarkdownRange.Kind, _ range: NSRange) {
        guard range.length > 0 else { return }
        ranges.append(MarkdownRange(from: range.location, to: range.location + range.length, kind: kind))
    }

    private mutating func protect(_ range: NSRange) {
        guard range.length > 0 else { return }
        protected.insert(integersIn: range.location..<NSMaxRange(range))
    }

    private mutating func collapseDelimiters(of markup: Markup) {
        guard let parent = r(markup) else { return }
        let revealFrom = parent.location
        let revealTo = NSMaxRange(parent)
        let children = Array(markup.children)
        guard let first = children.first, let last = children.last,
              let fr = r(first), let lr = r(last)
        else {
            add(.collapse(revealFrom: revealFrom, revealTo: revealTo), parent)
            return
        }
        let leading = NSRange(location: parent.location, length: max(0, fr.location - parent.location))
        let trailStart = NSMaxRange(lr)
        let trailing = NSRange(location: trailStart, length: max(0, NSMaxRange(parent) - trailStart))
        add(.collapse(revealFrom: revealFrom, revealTo: revealTo), leading)
        add(.collapse(revealFrom: revealFrom, revealTo: revealTo), trailing)
    }

    private mutating func collapseLineDelimiters(of markup: Markup) {
        guard let parent = r(markup) else { return }
        let children = Array(markup.children)
        guard let first = children.first, let fr = r(first) else {
            add(.collapseLine, parent)
            return
        }
        let leading = NSRange(location: parent.location, length: max(0, fr.location - parent.location))
        add(.collapseLine, leading)
        if let last = children.last, let lr = r(last) {
            var trailStart = NSMaxRange(lr)
            let end = NSMaxRange(parent)
            // A setext underline lives on its own line, and the trailing run starts with the
            // newline that ends the text line. Anchoring the hidden range on that newline would
            // key its reveal to the wrong line, so step past it.
            let ns = source as NSString
            while trailStart < end, trailStart - base >= 0, trailStart - base < ns.length,
                  ns.character(at: trailStart - base) == 0x0A || ns.character(at: trailStart - base) == 0x0D {
                trailStart += 1
            }
            let trailing = NSRange(location: trailStart, length: max(0, end - trailStart))
            if trailing.length > 0 { add(.collapseLine, trailing) }
        }
    }

    private mutating func descendInto(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = r(heading) { add(.heading(level: heading.level), range) }
        collapseLineDelimiters(of: heading)
        descendInto(heading)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = r(emphasis) { add(.emphasis, range) }
        collapseDelimiters(of: emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = r(strong) { add(.strong, range) }
        collapseDelimiters(of: strong)
        descendInto(strong)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = r(strikethrough) { add(.strikethrough, range) }
        collapseDelimiters(of: strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = r(inlineCode) else { return }
        protect(range)
        let ns = source as NSString
        let local = NSRange(location: range.location - base, length: range.length)
        guard local.location >= 0, NSMaxRange(local) <= ns.length else {
            add(.inlineCode, range)
            return
        }
        let raw = ns.substring(with: local)
        var ticks = 0
        for ch in raw {
            if ch == "`" { ticks += 1 } else { break }
        }
        // Style only the inner content — applying background to backticks caused a full-width
        // gray band once those glyphs collapsed to zero width.
        if ticks > 0, raw.utf16.count >= ticks * 2 {
            let revealFrom = range.location
            let revealTo = NSMaxRange(range)
            add(
                .collapse(revealFrom: revealFrom, revealTo: revealTo),
                NSRange(location: range.location, length: ticks)
            )
            add(
                .collapse(revealFrom: revealFrom, revealTo: revealTo),
                NSRange(location: NSMaxRange(range) - ticks, length: ticks)
            )
            let inner = NSRange(
                location: range.location + ticks,
                length: range.length - ticks * 2
            )
            if inner.length > 0 {
                add(.inlineCode, inner)
            }
        } else {
            add(.inlineCode, range)
        }
    }

    mutating func visitLink(_ link: Link) {
        if let range = r(link) {
            add(.linkText, range)
            // The destination is not prose; `$`, `[^…]` and the like inside it are not markup.
            if let first = Array(link.children).first, let fr = r(first) {
                protect(NSRange(location: NSMaxRange(fr), length: max(0, NSMaxRange(range) - NSMaxRange(fr))))
            } else {
                protect(range)
            }
        }
        collapseDelimiters(of: link)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        if let range = r(image) {
            protect(range)
            add(.image(alt: image.plainText, url: image.source ?? ""), range)
        }
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        if let range = r(inlineHTML) { protect(range) }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let range = r(html) { protect(range) }
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        // A hard break written as a trailing backslash is syntax; hide it with its line.
        guard let range = r(lineBreak) else { return }
        let ns = source as NSString
        let local = range.location - base
        guard local > 0, local <= ns.length else { return }
        if ns.character(at: local - 1) == UInt16(UInt8(ascii: "\\")) {
            add(.collapseLine, NSRange(location: range.location - 1, length: 1))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let range = r(blockQuote) {
            let ns = source as NSString
            var loc = max(0, range.location - base)
            let end = min(ns.length, NSMaxRange(range) - base)
            while loc < end {
                let line = ns.lineRange(for: NSRange(location: loc, length: 0))
                add(.blockquoteLine, NSRange(location: line.location + base, length: line.length))
                let lineText = ns.substring(with: line)
                if let m = MarkdownPatterns.blockquoteMark.firstMatch(
                    in: lineText,
                    range: NSRange(location: 0, length: (lineText as NSString).length)
                ) {
                    add(.collapseLine, NSRange(location: line.location + base, length: m.range.length))
                }
                loc = NSMaxRange(line)
            }
        }
        descendInto(blockQuote)
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        for item in list.listItems {
            visitListItem(item, ordered: false)
        }
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        for item in list.listItems {
            visitListItem(item, ordered: true)
        }
    }

    /// Handles both the bullet marker and the GFM task checkbox.
    ///
    /// Task detection comes from `ListItem.checkbox`, which cmark populates, rather than a regex.
    /// Marker location is found by scanning the item's own first line, since swift-markdown gives
    /// no range for the checkbox itself.
    private mutating func visitListItem(_ item: ListItem, ordered: Bool) {
        if let range = r(item) {
            let ns = source as NSString
            let localLoc = min(max(0, range.location - base), max(0, ns.length - 1))
            let line = ns.lineRange(for: NSRange(location: localLoc, length: 0))
            let lineText = ns.substring(with: line)
            let lineLocal = NSRange(location: 0, length: (lineText as NSString).length)
            let isTask = item.checkbox != nil

            // Bullet marker: read the character the item actually starts at rather than matching a
            // fixed indent, so items nested four or more spaces deep are handled too.
            var markerOffset: Int?
            var index = max(0, range.location - base - line.location)
            let lineNS = lineText as NSString
            while index < lineNS.length {
                let ch = lineNS.character(at: index)
                if ch == 0x20 || ch == 0x09 { index += 1; continue }
                if ch == UInt16(UInt8(ascii: "*")) || ch == UInt16(UInt8(ascii: "+"))
                    || ch == UInt16(UInt8(ascii: "-")) {
                    markerOffset = index
                }
                break
            }

            if isTask {
                if let m = MarkdownPatterns.taskMarker.firstMatch(in: lineText, range: lineLocal) {
                    let checked = item.checkbox == .checked
                    let absolute = NSRange(location: line.location + base + m.range.location, length: m.range.length)
                    add(.taskMarker(checked: checked), absolute)
                    // Hide the list marker and the space after it — the checkbox replaces them.
                    if let markerOffset {
                        let markLength = max(0, m.range.location - markerOffset)
                        if markLength > 0 {
                            add(
                                .taskListMark,
                                NSRange(location: line.location + base + markerOffset, length: markLength)
                            )
                        }
                    } else if ordered {
                        // `1. [ ]` — hide the number and its trailing space.
                        let start = max(0, range.location - base - line.location)
                        let markLength = max(0, m.range.location - start)
                        if markLength > 0 {
                            add(
                                .taskListMark,
                                NSRange(location: line.location + base + start, length: markLength)
                            )
                        }
                    }
                }
            } else if !ordered, let markerOffset {
                add(
                    .bulletMark,
                    NSRange(location: line.location + base + markerOffset, length: 1)
                )
            }
        }
        descendInto(item)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = r(codeBlock) else { return }
        protect(range)
        let lang = codeBlock.language
        if lang == "mermaid" {
            add(.mermaid(source: codeBlock.code), range)
            addFenceMarks(range)
            return
        }
        add(.codeBlock(language: lang), range)
        addFenceMarks(range)
    }

    private mutating func addFenceMarks(_ range: NSRange) {
        // Fence marks still collapse when the caret is on the block for editing.
        let ns = source as NSString
        let local = NSRange(location: range.location - base, length: range.length)
        guard local.location >= 0, NSMaxRange(local) <= ns.length else { return }
        let block = ns.substring(with: local)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        if let first = lines.first, first.hasPrefix("```") || first.hasPrefix("~~~") {
            let len = min((first as NSString).length, range.length)
            add(.collapseLine, NSRange(location: range.location, length: len))
        }
        if lines.count > 1, let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let lastLen = (last as NSString).length
                add(.collapseLine, NSRange(location: NSMaxRange(range) - lastLen, length: lastLen))
            }
        }
    }

    mutating func visitTable(_ table: Table) {
        guard let range = r(table) else { return }
        add(.table(Self.tableData(from: table)), range)
        descendInto(table)
    }

    /// Reads cmark's own view of the table rather than re-splitting the pipe text downstream.
    static func tableData(from table: Table) -> MarkdownTable {
        func cells(of container: some Markup) -> [MarkdownTable.Cell] {
            container.children.compactMap { child in
                guard let cell = child as? Table.Cell else { return nil }
                return MarkdownTable.Cell(
                    text: cell.plainText,
                    colspan: Int(cell.colspan),
                    rowspan: Int(cell.rowspan)
                )
            }
        }

        let alignments: [MarkdownColumnAlignment?] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            case .none: return nil
            }
        }

        var rows: [[MarkdownTable.Cell]] = []
        for child in table.body.children {
            guard let row = child as? Table.Row else { continue }
            rows.append(cells(of: row))
        }

        return MarkdownTable(alignments: alignments, header: cells(of: table.head), rows: rows)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = r(thematicBreak) {
            add(.thematicBreak, range)
        }
    }
}
