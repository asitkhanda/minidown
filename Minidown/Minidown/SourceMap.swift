import Foundation
import Markdown

/// Maps swift-markdown 1-based line/column SourceLocations onto UTF-16 offsets for NSTextStorage.
///
/// `SourceLocation.column` is a **UTF-8 byte** offset from the start of the line (1-based), not a
/// UTF-16 column. ASCII markdown is identical either way; non-ASCII needs the conversion below.
struct SourceMap {
    private let lineStarts: [Int]
    private let utf16Length: Int
    private let ns: NSString

    init(_ text: String) {
        let ns = text as NSString
        self.ns = ns
        var starts: [Int] = [0]
        var i = 0
        while i < ns.length {
            let ch = ns.character(at: i)
            if ch == 0x0A {
                starts.append(i + 1)
            } else if ch == 0x0D {
                if i + 1 < ns.length && ns.character(at: i + 1) == 0x0A { i += 1 }
                starts.append(i + 1)
            }
            i += 1
        }
        lineStarts = starts
        utf16Length = ns.length
    }

    func utf16Offset(line: Int, column: Int) -> Int {
        guard line >= 1, !lineStarts.isEmpty else { return 0 }
        let idx = min(line, lineStarts.count) - 1
        let start = lineStarts[idx]
        let end = idx + 1 < lineStarts.count ? lineStarts[idx + 1] : utf16Length
        let lineLen = end - start
        guard lineLen > 0 else { return start }

        let lineText = ns.substring(with: NSRange(location: start, length: lineLen))
        let utf8 = Array(lineText.utf8)
        let byteOffset = max(column, 1) - 1
        if byteOffset <= 0 { return start }
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
