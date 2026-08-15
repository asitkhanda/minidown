import Foundation

/// Decides which markdown constructs show their raw syntax for a given selection.
///
/// CONTRIBUTING states reveal correctness as an invariant, in two parts:
///
/// 1. **Inline marks** (`**`, `` ` ``, `#`, `>`, link syntax) reveal whenever *any* selection range
///    touches them, inclusively at both ends. Ported from the CodeMirror predicate, including its
///    multi-cursor behaviour, which the first Swift port dropped by looking at only one range.
/// 2. **Block constructs** (tables, images, math, mermaid, rules) reveal when the selection is
///    *editing inside* them — not merely spanning them. This is the one deliberate divergence from
///    the CodeMirror original, where ⌘A turned the entire document back into raw source and threw
///    away every widget's layout.
struct RevealPolicy {
    let selections: [NSRange]
    private let ns: NSString

    init(selections: [NSRange], text: String) {
        self.selections = selections.isEmpty ? [NSRange(location: 0, length: 0)] : selections
        self.ns = text as NSString
    }

    init(selection: NSRange, text: String) {
        self.init(selections: [selection], text: text)
    }

    /// True when any selection range overlaps `range`, counting a caret resting on either boundary.
    ///
    /// The inclusivity is intentional and load-bearing: a caret immediately after a closing `**`
    /// must still reveal the marks, or you cannot type your way out of a construct.
    func touchesInline(_ range: NSRange) -> Bool {
        selections.contains { touches($0, range) }
    }

    /// Line-granular reveal, used where the whole line's syntax belongs together — heading marks,
    /// quote marks, fence lines, thematic breaks.
    func touchesLine(containing location: Int) -> Bool {
        guard ns.length > 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: min(max(0, location), ns.length - 1), length: 0))
        return selections.contains { touches($0, line) }
    }

    /// True only when the user is working *inside* a block, so its widget should give way to source.
    ///
    /// A collapsed caret touching the block counts. A range selection counts only if one of its
    /// endpoints falls strictly inside — so a selection that wholly contains the block (⌘A, or
    /// dragging past it to copy a section) leaves the rendered widget alone.
    func isEditing(_ range: NSRange) -> Bool {
        let blockStart = range.location
        let blockEnd = NSMaxRange(range)
        for selection in selections {
            if selection.length == 0 {
                if selection.location >= blockStart && selection.location <= blockEnd { return true }
                continue
            }
            let selectionStart = selection.location
            let selectionEnd = NSMaxRange(selection)
            let startsInside = selectionStart > blockStart && selectionStart < blockEnd
            let endsInside = selectionEnd > blockStart && selectionEnd < blockEnd
            if startsInside || endsInside { return true }
        }
        return false
    }

    /// Line-granular form of `isEditing`, for block widgets that own a whole line and cannot easily
    /// be clicked "into" — images and thematic breaks. A caret anywhere on the line reveals the
    /// source; a selection that merely spans the line does not.
    func isEditingLine(containing location: Int) -> Bool {
        guard ns.length > 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: min(max(0, location), ns.length - 1), length: 0))
        return isEditing(line)
    }

    /// The paragraph focus mode lights: the contiguous run of non-blank lines around `location`.
    func focusRange(at location: Int) -> NSRange {
        let range = Self.focusRange(in: ns as String, at: location)
        return NSRange(location: range.from, length: max(0, range.to - range.from))
    }

    static func focusRange(in text: String, at location: Int) -> (from: Int, to: Int) {
        let ns = text as NSString
        let clamped = max(0, min(location, ns.length))
        guard ns.length > 0 else { return (0, 0) }
        let lineRange = ns.lineRange(for: NSRange(location: min(clamped, ns.length - 1), length: 0))
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

    private func touches(_ selection: NSRange, _ range: NSRange) -> Bool {
        selection.location <= NSMaxRange(range) && NSMaxRange(selection) >= range.location
    }
}
