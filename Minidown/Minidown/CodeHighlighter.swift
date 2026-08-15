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
import Splash
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterCSS
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterRust
import TreeSitterTypeScript

/// Syntax colouring for fenced code blocks.
///
/// The bug this replaces: `codeBlock.language` was parsed and then discarded, and every fence —
/// Python, JSON, shell — was tokenised with `SwiftGrammar`, because Splash ships exactly one
/// grammar and defaults to it. Languages now route to tree-sitter, with Splash kept for the one
/// language it genuinely handles.
enum CodeHighlighter {
    /// Languages we can colour, and how. Extension aliases are included because the Tauri build
    /// accepted them and `examples/02-code.md` uses them.
    enum Language {
        case swift
        case treeSitter(TreeSitterLanguage)

        static func named(_ info: String?) -> Language? {
            guard let info else { return nil }
            let name = info
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .split(separator: " ").first.map(String.init) ?? ""
            switch name {
            case "swift": return .swift
            case "js", "javascript", "jsx", "mjs", "cjs": return .treeSitter(.javascript)
            case "ts", "typescript", "tsx": return .treeSitter(.typescript)
            case "py", "python": return .treeSitter(.python)
            case "rs", "rust": return .treeSitter(.rust)
            case "css": return .treeSitter(.css)
            case "json": return .treeSitter(.json)
            case "html", "htm": return .treeSitter(.html)
            case "sh", "bash", "shell", "zsh": return .treeSitter(.bash)
            default: return nil
            }
        }
    }

    enum TreeSitterLanguage: String, CaseIterable {
        case javascript, typescript, python, rust, css, json, html, bash

        var configuration: LanguageConfiguration? {
            TreeSitterConfigurations.shared.configuration(for: self)
        }
    }

    @MainActor
    static func apply(
        to storage: NSTextStorage,
        codeRange: NSRange,
        source: String,
        language: String?
    ) {
        guard let language = Language.named(language) else { return }
        let ns = source as NSString
        guard NSMaxRange(codeRange) <= ns.length else { return }

        // Trim the fence lines so offsets line up with the code itself.
        var code = ns.substring(with: codeRange)
        var contentStart = codeRange.location
        if code.hasPrefix("```") || code.hasPrefix("~~~"), let newline = code.firstIndex(of: "\n") {
            let prefixLength = code.distance(from: code.startIndex, to: newline) + 1
            contentStart += prefixLength
            code = String(code[code.index(after: newline)...])
        }
        if let fenceStart = code.range(of: "```", options: .backwards) ?? code.range(of: "~~~", options: .backwards) {
            code = String(code[code.startIndex..<fenceStart.lowerBound])
        }
        guard !code.isEmpty else { return }

        switch language {
        case .swift:
            let format = StorageFormat(storage: storage, base: contentStart)
            _ = SyntaxHighlighter(format: format, grammar: SwiftGrammar()).highlight(code)
        case .treeSitter(let treeSitterLanguage):
            applyTreeSitter(
                to: storage,
                code: code,
                base: contentStart,
                language: treeSitterLanguage
            )
        }
    }

    @MainActor
    private static func applyTreeSitter(
        to storage: NSTextStorage,
        code: String,
        base: Int,
        language: TreeSitterLanguage
    ) {
        guard let configuration = language.configuration,
              let query = configuration.queries[.highlights]
        else { return }

        let parser = Parser()
        do {
            try parser.setLanguage(configuration.language)
        } catch {
            return
        }
        guard let tree = parser.parse(code) else { return }

        let cursor = query.execute(in: tree)
        // Highlight captures overlap and the convention is first-match-wins, so apply in the order
        // yielded and do not sort. Ranges come back in UTF-16, matching NSTextStorage.
        var claimed = IndexSet()
        for namedRange in cursor.resolve(with: .init(string: code)).highlights() {
            guard let color = color(forCapture: namedRange.name) else { continue }
            let range = NSRange(location: base + namedRange.range.location, length: namedRange.range.length)
            guard range.location >= base, NSMaxRange(range) <= storage.length, range.length > 0 else { continue }
            let span = range.location..<NSMaxRange(range)
            guard !claimed.contains(integersIn: span) else { continue }
            claimed.insert(integersIn: span)
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    /// Maps a tree-sitter capture name onto the theme palette by longest-prefix fallback.
    ///
    /// There is no single capture vocabulary — grammars disagree, exposing anywhere from 9 names
    /// (bash) to 21 (rust) — so an exact-match table would leave most languages nearly uncoloured.
    /// Splitting on `.` and dropping trailing components collapses the variants onto one palette.
    ///
    /// Bare `variable` and `punctuation.*` are deliberately left uncoloured: the official
    /// JavaScript and Python queries capture *every* identifier as `@variable`, and colouring that
    /// is the difference between looking like Xcode and looking like a rainbow.
    static func color(forCapture capture: String) -> NSColor? {
        var components = capture.split(separator: ".").map(String.init)
        while !components.isEmpty {
            let key = components.joined(separator: ".")
            if let color = paletteEntry(key) { return color }
            components.removeLast()
        }
        return nil
    }

    private static func paletteEntry(_ key: String) -> NSColor? {
        switch key {
        case "keyword", "operator", "boolean", "conditional", "repeat", "include", "exception":
            return AppColors.sxKeyword
        case "constant.builtin", "variable.builtin", "attribute", "tag":
            return AppColors.sxKeyword
        case "string", "character", "text.literal", "text.uri":
            return AppColors.sxString
        // Two spellings of the same concept across grammars; the prefix walk cannot unify them.
        case "escape", "string.escape", "string.special":
            return AppColors.sxString
        case "comment", "spell":
            return AppColors.sxComment
        case "number", "float", "constant":
            return AppColors.sxNumber
        case "type", "constructor", "module", "label":
            return AppColors.sxType
        case "function", "property", "method", "variable.member":
            return AppColors.sxFunc
        default:
            return nil
        }
    }
}

/// Loads and caches one `LanguageConfiguration` per language.
///
/// Constructing one parses every `.scm` in that grammar's resource bundle, so it must not happen
/// per fence.
private final class TreeSitterConfigurations {
    static let shared = TreeSitterConfigurations()

    private var cache: [CodeHighlighter.TreeSitterLanguage: LanguageConfiguration] = [:]
    private var failed: Set<CodeHighlighter.TreeSitterLanguage> = []
    private let lock = NSLock()

    func configuration(for language: CodeHighlighter.TreeSitterLanguage) -> LanguageConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[language] { return cached }
        guard !failed.contains(language) else { return nil }

        do {
            let configuration = try Self.load(language)
            cache[language] = configuration
            return configuration
        } catch {
            // A missing query bundle should degrade to plain monospace, not crash the editor.
            failed.insert(language)
            return nil
        }
    }

    private static func load(_ language: CodeHighlighter.TreeSitterLanguage) throws -> LanguageConfiguration {
        switch language {
        case .javascript:
            return try LanguageConfiguration(tree_sitter_javascript(), name: "JavaScript")
        case .typescript:
            return try LanguageConfiguration(tree_sitter_typescript(), name: "TypeScript")
        case .python:
            return try LanguageConfiguration(tree_sitter_python(), name: "Python")
        case .rust:
            return try LanguageConfiguration(tree_sitter_rust(), name: "Rust")
        case .css:
            return try LanguageConfiguration(tree_sitter_css(), name: "CSS")
        case .json:
            return try LanguageConfiguration(tree_sitter_json(), name: "JSON")
        case .html:
            return try LanguageConfiguration(tree_sitter_html(), name: "HTML")
        case .bash:
            return try LanguageConfiguration(tree_sitter_bash(), name: "Bash")
        }
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
