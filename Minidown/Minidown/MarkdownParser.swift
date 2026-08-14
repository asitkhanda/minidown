import Foundation
import Markdown

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
        case table
        case frontmatter
        case footnoteRef
        case inlineMath(tex: String)
        case blockMath(tex: String)
        case mermaid(source: String)
        case image(alt: String, url: String)
    }
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownRange] {
        var ranges: [MarkdownRange] = []
        let ns = text as NSString
        var body = text
        var bodyOffset = 0

        if let end = frontmatterEnd(in: text) {
            ranges.append(MarkdownRange(from: 0, to: end, kind: .frontmatter))
            body = ns.substring(from: end)
            bodyOffset = end
        }

        let map = SourceMap(body)
        let document = Document(parsing: body)
        var collector = RangeCollector(map: map, base: bodyOffset, source: body)
        collector.visit(document)
        ranges.append(contentsOf: collector.ranges)
        ranges.append(contentsOf: parseSupplemental(text))

        return ranges.sorted {
            $0.from < $1.from || ($0.from == $1.from && $0.to < $1.to)
        }
    }

    private static func frontmatterEnd(in text: String) -> Int? {
        let ns = text as NSString
        guard ns.length >= 3 else { return nil }
        let firstLine = ns.lineRange(for: NSRange(location: 0, length: 0))
        let firstText = ns.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstText == "---" else { return nil }

        var loc = NSMaxRange(firstLine)
        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let trimmed = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                return NSMaxRange(line)
            }
            loc = NSMaxRange(line)
        }
        // No closing fence — treat leading --- as a thematic break, not frontmatter.
        return nil
    }

    private static func parseSupplemental(_ text: String) -> [MarkdownRange] {
        var out: [MarkdownRange] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        out.append(contentsOf: parseTaskLines(text))

        if let re = try? NSRegularExpression(pattern: #"\[\^[^\s\[\]]+\]"#) {
            re.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                out.append(
                    MarkdownRange(
                        from: match.range.location,
                        to: match.range.location + match.range.length,
                        kind: .footnoteRef
                    )
                )
            }
        }

        if let re = try? NSRegularExpression(pattern: #"(?<!\$)\$(?![\s$])([^$\n]+?)(?<![\s$])\$(?!\$)"#) {
            re.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let inner = ns.substring(with: match.range(at: 1))
                out.append(
                    MarkdownRange(
                        from: match.range.location,
                        to: match.range.location + match.range.length,
                        kind: .inlineMath(tex: inner)
                    )
                )
            }
        }

        if let re = try? NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$"#) {
            re.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let inner = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(
                    MarkdownRange(
                        from: match.range.location,
                        to: match.range.location + match.range.length,
                        kind: .blockMath(tex: inner)
                    )
                )
            }
        }

        return out
    }

    /// GFM task lists (`- [ ]`, `* [x]`, `1. [ ]`) plus bare line-start `[ ]` / `[x]` / `[X]`.
    private static func parseTaskLines(_ text: String) -> [MarkdownRange] {
        var out: [MarkdownRange] = []
        let ns = text as NSString
        var loc = 0
        // Indent + optional bullet/ordered marker + [ ] / [x] / [X]
        let pattern = #"^([ \t]*)(?:([*+-])([ \t]+)|(\d+\.)([ \t]+))?(\[[ xX]\])"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return out
        }

        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let lineText = ns.substring(with: line)
            let lineLocal = NSRange(location: 0, length: (lineText as NSString).length)
            if let m = re.firstMatch(in: lineText, range: lineLocal), m.numberOfRanges >= 7 {
                let markerLocal = m.range(at: 6)
                let markerAbs = NSRange(
                    location: line.location + markerLocal.location,
                    length: markerLocal.length
                )
                let inner = (lineText as NSString).substring(with: markerLocal)
                let checked = inner.range(of: "x", options: .caseInsensitive) != nil
                out.append(
                    MarkdownRange(
                        from: markerAbs.location,
                        to: NSMaxRange(markerAbs),
                        kind: .taskMarker(checked: checked)
                    )
                )

                // Hide list marker + following spaces when present (`- `, `* `, `1. `).
                if m.range(at: 2).location != NSNotFound {
                    let bullet = m.range(at: 2)
                    let spaces = m.range(at: 3)
                    let mark = NSRange(
                        location: line.location + bullet.location,
                        length: bullet.length + spaces.length
                    )
                    out.append(
                        MarkdownRange(from: mark.location, to: NSMaxRange(mark), kind: .taskListMark)
                    )
                } else if m.range(at: 4).location != NSNotFound {
                    let num = m.range(at: 4)
                    let spaces = m.range(at: 5)
                    let mark = NSRange(
                        location: line.location + num.location,
                        length: num.length + spaces.length
                    )
                    out.append(
                        MarkdownRange(from: mark.location, to: NSMaxRange(mark), kind: .taskListMark)
                    )
                }
            }
            loc = NSMaxRange(line)
            if line.length == 0 { break }
        }
        return out
    }
}

private struct RangeCollector: MarkupWalker {
    let map: SourceMap
    let base: Int
    let source: String
    var ranges: [MarkdownRange] = []

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
            let trailStart = NSMaxRange(lr)
            let trailing = NSRange(location: trailStart, length: max(0, NSMaxRange(parent) - trailStart))
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
        if let range = r(link) { add(.linkText, range) }
        collapseDelimiters(of: link)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        if let range = r(image) {
            add(.image(alt: image.plainText, url: image.source ?? ""), range)
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
                if let regex = try? NSRegularExpression(pattern: #"^ {0,3}> ?"#),
                   let m = regex.firstMatch(
                    in: lineText,
                    range: NSRange(location: 0, length: (lineText as NSString).length)
                   )
                {
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

    private mutating func visitListItem(_ item: ListItem, ordered: Bool) {
        if let range = r(item) {
            let ns = source as NSString
            let localLoc = min(max(0, range.location - base), max(0, ns.length - 1))
            let line = ns.lineRange(for: NSRange(location: localLoc, length: 0))
            let lineText = ns.substring(with: line)
            // Task markers are collected in parseTaskLines (covers bare [ ] and GFM variants).
            let isTask = item.checkbox != nil
                || (try? NSRegularExpression(pattern: #"^\s*(?:[*+-]|\d+\.)?\s*\[[ xX]\]"#))?
                .firstMatch(
                    in: lineText,
                    range: NSRange(location: 0, length: (lineText as NSString).length)
                ) != nil

            if !ordered, !isTask,
               let regex = try? NSRegularExpression(pattern: #"^ {0,3}([*+-])( +)"#),
               let m = regex.firstMatch(
                in: lineText,
                range: NSRange(location: 0, length: (lineText as NSString).length)
               ),
               m.numberOfRanges > 1
            {
                let mark = m.range(at: 1)
                add(.bulletMark, NSRange(location: line.location + base + mark.location, length: mark.length))
            }
        }
        descendInto(item)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = r(codeBlock) else { return }
        let lang = codeBlock.language
        if lang == "mermaid" {
            add(.mermaid(source: codeBlock.code), range)
            // Fence marks still collapse when the caret is on the block for editing.
            let ns = source as NSString
            let local = NSRange(location: range.location - base, length: range.length)
            guard local.location >= 0, NSMaxRange(local) <= ns.length else { return }
            let block = ns.substring(with: local)
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            if let first = lines.first, first.hasPrefix("```") {
                let len = min((first as NSString).length, range.length)
                add(.collapseLine, NSRange(location: range.location, length: len))
            }
            if lines.count > 1, let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let lastLen = (last as NSString).length
                add(.collapseLine, NSRange(location: NSMaxRange(range) - lastLen, length: lastLen))
            }
            return
        }
        add(.codeBlock(language: lang), range)

        let ns = source as NSString
        let local = NSRange(location: range.location - base, length: range.length)
        guard local.location >= 0, NSMaxRange(local) <= ns.length else { return }
        let block = ns.substring(with: local)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        if let first = lines.first, first.hasPrefix("```") {
            let len = min((first as NSString).length, range.length)
            add(.collapseLine, NSRange(location: range.location, length: len))
        }
        if lines.count > 1, let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            let lastLen = (last as NSString).length
            add(.collapseLine, NSRange(location: NSMaxRange(range) - lastLen, length: lastLen))
        }
    }

    mutating func visitTable(_ table: Table) {
        if let range = r(table) { add(.table, range) }
        descendInto(table)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = r(thematicBreak) {
            add(.thematicBreak, range)
        }
    }
}
