import AppKit
import Splash

/// Token colors for fenced code using Splash (John Sundell's highlighter).
enum CodeHighlighter {
    static func apply(to storage: NSTextStorage, codeRange: NSRange, source: String) {
        let ns = source as NSString
        guard NSMaxRange(codeRange) <= ns.length else { return }
        var code = ns.substring(with: codeRange)
        var contentStart = codeRange.location
        if code.hasPrefix("```"), let nl = code.firstIndex(of: "\n") {
            let prefixLen = code.distance(from: code.startIndex, to: nl) + 1
            contentStart += prefixLen
            code = String(code[code.index(after: nl)...])
        }
        if code.hasSuffix("```") {
            code = String(code.dropLast(3))
            if code.hasSuffix("\n") { code = String(code.dropLast()) }
        }

        let format = StorageFormat(storage: storage, base: contentStart)
        let highlighter = SyntaxHighlighter(format: format)
        _ = highlighter.highlight(code)
    }
}

private struct StorageFormat: OutputFormat {
    let storage: NSTextStorage
    let base: Int

    func makeBuilder() -> Builder {
        Builder(storage: storage, base: base)
    }

    struct Builder: OutputBuilder {
        let storage: NSTextStorage
        let base: Int
        private var offset = 0

        init(storage: NSTextStorage, base: Int) {
            self.storage = storage
            self.base = base
        }

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let length = (token as NSString).length
            let range = NSRange(location: base + offset, length: length)
            offset += length
            guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
            let color: NSColor?
            switch type {
            case .keyword: color = AppColors.sxKeyword
            case .string: color = AppColors.sxString
            case .comment: color = AppColors.sxComment
            case .number: color = AppColors.sxNumber
            case .type: color = AppColors.sxType
            case .call: color = AppColors.sxFunc
            case .property, .dotAccess: color = AppColors.sxFunc
            default: color = nil
            }
            if let color {
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        mutating func addPlainText(_ text: String) {
            offset += (text as NSString).length
        }

        mutating func addWhitespace(_ whitespace: String) {
            offset += (whitespace as NSString).length
        }

        func build() {}
    }
}
