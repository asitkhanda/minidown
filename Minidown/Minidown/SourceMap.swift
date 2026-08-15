import Foundation
import Markdown

/// Maps swift-markdown 1-based line/column SourceLocations onto UTF-16 offsets for NSTextStorage.
///
/// `SourceLocation.column` is a **UTF-8 byte** offset from the start of the line (1-based), not a
/// UTF-16 column. ASCII markdown is identical either way; non-ASCII needs the conversion below.
struct SourceMap {
    private let lineStarts: [Int]
    /// Parallel to `lineStarts`: true when the line is pure ASCII, so byte offset == UTF-16 offset
    /// and no conversion work is needed. The overwhelmingly common case.
    private let lineIsASCII: [Bool]
    private let utf16Length: Int
    private let ns: NSString

    /// Cache of the last non-ASCII line converted. Markup nodes cluster on the same line — a
    /// heading's range, its delimiters, and every inline child all resolve against it — so a
    /// one-entry cache removes nearly all repeat work without the cost of a full table.
    private let cache = LineByteCache()

    init(_ text: String) {
        let ns = text as NSString
        self.ns = ns
        var starts: [Int] = [0]
        var ascii: [Bool] = []
        var lineHasHighCharacter = false
        var i = 0
        while i < ns.length {
            let ch = ns.character(at: i)
            if ch > 0x7F { lineHasHighCharacter = true }
            if ch == 0x0A {
                starts.append(i + 1)
                ascii.append(!lineHasHighCharacter)
                lineHasHighCharacter = false
            } else if ch == 0x0D {
                if i + 1 < ns.length && ns.character(at: i + 1) == 0x0A { i += 1 }
                starts.append(i + 1)
                ascii.append(!lineHasHighCharacter)
                lineHasHighCharacter = false
            }
            i += 1
        }
        ascii.append(!lineHasHighCharacter) // trailing line
        lineStarts = starts
        lineIsASCII = ascii
        utf16Length = ns.length
    }

    func utf16Offset(line: Int, column: Int) -> Int {
        guard line >= 1, !lineStarts.isEmpty else { return 0 }
        let idx = min(line, lineStarts.count) - 1
        let start = lineStarts[idx]
        let end = idx + 1 < lineStarts.count ? lineStarts[idx + 1] : utf16Length
        let lineLen = end - start
        guard lineLen > 0 else { return start }

        let byteOffset = max(column, 1) - 1
        if byteOffset <= 0 { return start }

        // Fast path: an all-ASCII line has one byte per UTF-16 unit.
        if idx < lineIsASCII.count, lineIsASCII[idx] {
            return min(start + byteOffset, end)
        }

        let utf8 = cache.utf8(forLine: idx) ?? {
            let bytes = Array(ns.substring(with: NSRange(location: start, length: lineLen)).utf8)
            cache.store(bytes, forLine: idx)
            return bytes
        }()

        if byteOffset >= utf8.count { return end }
        let prefix = String(decoding: utf8[..<byteOffset], as: UTF8.self)
        return start + (prefix as NSString).length
    }

    func nsRange(from range: SourceRange) -> NSRange {
        let a = utf16Offset(line: range.lowerBound.line, column: range.lowerBound.column)
        let b = utf16Offset(line: range.upperBound.line, column: range.upperBound.column)
        return NSRange(location: a, length: max(0, b - a))
    }
}

/// Reference-typed so `SourceMap` can stay a struct with value semantics at the call site.
private final class LineByteCache {
    private var line: Int = -1
    private var bytes: [UInt8] = []

    func utf8(forLine index: Int) -> [UInt8]? {
        line == index ? bytes : nil
    }

    func store(_ newBytes: [UInt8], forLine index: Int) {
        line = index
        bytes = newBytes
    }
}
