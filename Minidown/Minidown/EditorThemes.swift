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

/// A colour, stored so a theme can round-trip through JSON later without change.
struct ThemeColor: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`, which is how every upstream palette publishes its values.
    init(_ hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ newAlpha: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    /// Perceived brightness, used to check a palette is internally legible.
    var brightness: Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }
}

/// Every colour role the editor draws with.
///
/// One palette covers a single appearance; a theme carries two of them.
struct Palette: Equatable, Codable {
    // Surface
    var background: ThemeColor
    var foreground: ThemeColor
    /// Secondary text: status bar, placeholders.
    var muted: ThemeColor
    /// Revealed markdown syntax, bullets, rules, table borders.
    var syntax: ThemeColor
    /// Links, insertion point, active toggles.
    var accent: ThemeColor
    var selection: ThemeColor
    var quote: ThemeColor
    var inlineCode: ThemeColor
    var codeBackground: ThemeColor

    // Code tokens
    var keyword: ThemeColor
    var string: ThemeColor
    var comment: ThemeColor
    var number: ThemeColor
    var type: ThemeColor
    var function: ThemeColor
}

/// A named pair of palettes.
///
/// Themes are paired rather than standalone so the app's Light/Dark/System appearance keeps
/// working — picking "Nord" does not force you out of following the system. Each pair uses the
/// upstream project's own light and dark variants rather than an inverted approximation.
struct EditorTheme: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var light: Palette
    var dark: Palette

    func palette(isDark: Bool) -> Palette {
        isDark ? dark : light
    }

    func palette(for appearance: NSAppearance) -> Palette {
        palette(isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}

// MARK: - Built-in themes

extension EditorTheme {
    static let allBuiltIn: [EditorTheme] = [
        .minidown, .solarized, .nord, .dracula, .gruvbox, .one,
    ]

    static func named(_ id: String) -> EditorTheme {
        allBuiltIn.first { $0.id == id } ?? .minidown
    }

    /// The original paper-and-ink palette. Deliberately quiet: it is the writing default.
    static let minidown = EditorTheme(
        id: "minidown",
        name: "minidown",
        light: Palette(
            background: ThemeColor(0xFBFBFA),
            foreground: ThemeColor(0x1C1C1C),
            muted: ThemeColor(0xA3A39C),
            syntax: ThemeColor(0xB0B0A8),
            accent: ThemeColor(0x1C7ED6),
            selection: ThemeColor(0x1C7ED6, alpha: 0.16),
            quote: ThemeColor(0x6F6F68),
            inlineCode: ThemeColor(0xC2255C),
            codeBackground: ThemeColor(0x1B1B1D, alpha: 0.05),
            keyword: ThemeColor(0x1971C2),
            string: ThemeColor(0x2F9E44),
            comment: ThemeColor(0x9A9A92),
            number: ThemeColor(0xE8590C),
            type: ThemeColor(0x9C36B5),
            function: ThemeColor(0x3B5BDB)
        ),
        dark: Palette(
            background: ThemeColor(0x1B1B1D),
            foreground: ThemeColor(0xD8D8D3),
            muted: ThemeColor(0x5E5E5A),
            syntax: ThemeColor(0x4F4F4B),
            accent: ThemeColor(0x4DABF7),
            selection: ThemeColor(0x4DABF7, alpha: 0.22),
            quote: ThemeColor(0x8F8F88),
            inlineCode: ThemeColor(0xFAA2C1),
            codeBackground: ThemeColor(0xFFFFFF, alpha: 0.08),
            keyword: ThemeColor(0x4DABF7),
            string: ThemeColor(0x69DB7C),
            comment: ThemeColor(0x6E6E68),
            number: ThemeColor(0xFFA94D),
            type: ThemeColor(0xDA77F2),
            function: ThemeColor(0x91A7FF)
        )
    )

    /// Ethan Schoonover's Solarized — the canonical light/dark pair, designed together.
    static let solarized = EditorTheme(
        id: "solarized",
        name: "Solarized",
        light: Palette(
            background: ThemeColor(0xFDF6E3), // base3
            foreground: ThemeColor(0x657B83), // base00
            muted: ThemeColor(0x93A1A1), // base1
            syntax: ThemeColor(0xADB8B8),
            accent: ThemeColor(0x268BD2), // blue
            selection: ThemeColor(0x268BD2, alpha: 0.16),
            quote: ThemeColor(0x586E75), // base01
            inlineCode: ThemeColor(0xD33682), // magenta
            codeBackground: ThemeColor(0xEEE8D5), // base2
            keyword: ThemeColor(0x859900), // green
            string: ThemeColor(0x2AA198), // cyan
            comment: ThemeColor(0x93A1A1), // base1
            number: ThemeColor(0xD33682), // magenta
            type: ThemeColor(0xB58900), // yellow
            function: ThemeColor(0x268BD2) // blue
        ),
        dark: Palette(
            background: ThemeColor(0x002B36), // base03
            foreground: ThemeColor(0x839496), // base0
            muted: ThemeColor(0x586E75), // base01
            syntax: ThemeColor(0x4A6068),
            accent: ThemeColor(0x268BD2),
            selection: ThemeColor(0x268BD2, alpha: 0.26),
            quote: ThemeColor(0x93A1A1), // base1
            inlineCode: ThemeColor(0xD33682),
            codeBackground: ThemeColor(0x073642), // base02
            keyword: ThemeColor(0x859900),
            string: ThemeColor(0x2AA198),
            comment: ThemeColor(0x586E75),
            number: ThemeColor(0xD33682),
            type: ThemeColor(0xB58900),
            function: ThemeColor(0x268BD2)
        )
    )

    /// Nord: Polar Night for dark, Snow Storm for light.
    static let nord = EditorTheme(
        id: "nord",
        name: "Nord",
        light: Palette(
            background: ThemeColor(0xECEFF4), // nord6
            foreground: ThemeColor(0x2E3440), // nord0
            muted: ThemeColor(0x7B88A1),
            syntax: ThemeColor(0x9AA5B8),
            accent: ThemeColor(0x5E81AC), // nord10
            selection: ThemeColor(0x5E81AC, alpha: 0.18),
            quote: ThemeColor(0x4C566A), // nord3
            inlineCode: ThemeColor(0xB48EAD), // nord15
            codeBackground: ThemeColor(0xD8DEE9), // nord4
            keyword: ThemeColor(0x5E81AC),
            string: ThemeColor(0xA3BE8C), // nord14
            comment: ThemeColor(0x7B88A1),
            number: ThemeColor(0xB48EAD),
            type: ThemeColor(0x8FBCBB), // nord7
            function: ThemeColor(0x88C0D0) // nord8
        ),
        dark: Palette(
            background: ThemeColor(0x2E3440), // nord0
            foreground: ThemeColor(0xD8DEE9), // nord4
            muted: ThemeColor(0x6E7A90),
            syntax: ThemeColor(0x4C566A), // nord3
            accent: ThemeColor(0x88C0D0), // nord8
            selection: ThemeColor(0x88C0D0, alpha: 0.24),
            quote: ThemeColor(0x9AA5B8),
            inlineCode: ThemeColor(0xB48EAD),
            codeBackground: ThemeColor(0x3B4252), // nord1
            keyword: ThemeColor(0x81A1C1), // nord9
            string: ThemeColor(0xA3BE8C),
            comment: ThemeColor(0x616E88),
            number: ThemeColor(0xB48EAD),
            type: ThemeColor(0x8FBCBB),
            function: ThemeColor(0x88C0D0)
        )
    )

    /// Dracula, with its official light counterpart Alucard.
    static let dracula = EditorTheme(
        id: "dracula",
        name: "Dracula",
        light: Palette(
            background: ThemeColor(0xFFFBEB), // Alucard background
            foreground: ThemeColor(0x1F1F1F),
            muted: ThemeColor(0x8C876B),
            syntax: ThemeColor(0xB3AE93),
            accent: ThemeColor(0x644AC9), // purple
            selection: ThemeColor(0x644AC9, alpha: 0.16),
            quote: ThemeColor(0x6C664B),
            inlineCode: ThemeColor(0xA3144D), // pink
            codeBackground: ThemeColor(0xEFE7C8),
            keyword: ThemeColor(0xA3144D),
            string: ThemeColor(0x846E15), // yellow
            comment: ThemeColor(0x6C664B),
            number: ThemeColor(0x644AC9),
            type: ThemeColor(0x036A96), // cyan
            function: ThemeColor(0x14710A) // green
        ),
        dark: Palette(
            background: ThemeColor(0x282A36),
            foreground: ThemeColor(0xF8F8F2),
            muted: ThemeColor(0x6272A4),
            syntax: ThemeColor(0x565A72),
            accent: ThemeColor(0xBD93F9), // purple
            selection: ThemeColor(0xBD93F9, alpha: 0.26),
            quote: ThemeColor(0x9AA5D0),
            inlineCode: ThemeColor(0xFF79C6), // pink
            codeBackground: ThemeColor(0x44475A), // current line
            keyword: ThemeColor(0xFF79C6),
            string: ThemeColor(0xF1FA8C), // yellow
            comment: ThemeColor(0x6272A4),
            number: ThemeColor(0xBD93F9),
            type: ThemeColor(0x8BE9FD), // cyan
            function: ThemeColor(0x50FA7B) // green
        )
    )

    /// Gruvbox, warm and retro, in its published light and dark variants.
    static let gruvbox = EditorTheme(
        id: "gruvbox",
        name: "Gruvbox",
        light: Palette(
            background: ThemeColor(0xFBF1C7), // bg0
            foreground: ThemeColor(0x3C3836), // fg1
            muted: ThemeColor(0x928374), // gray
            syntax: ThemeColor(0xB5A88F),
            accent: ThemeColor(0x076678), // blue
            selection: ThemeColor(0x076678, alpha: 0.16),
            quote: ThemeColor(0x665C54),
            inlineCode: ThemeColor(0x9D0006), // red
            codeBackground: ThemeColor(0xEBDBB2), // bg1
            keyword: ThemeColor(0x9D0006),
            string: ThemeColor(0x79740E), // green
            comment: ThemeColor(0x928374),
            number: ThemeColor(0x8F3F71), // purple
            type: ThemeColor(0xB57614), // yellow
            function: ThemeColor(0x427B58) // aqua
        ),
        dark: Palette(
            background: ThemeColor(0x282828), // bg0
            foreground: ThemeColor(0xEBDBB2), // fg1
            muted: ThemeColor(0x928374),
            syntax: ThemeColor(0x665C54),
            accent: ThemeColor(0x83A598), // blue
            selection: ThemeColor(0x83A598, alpha: 0.24),
            quote: ThemeColor(0xBDAE93),
            inlineCode: ThemeColor(0xFB4934), // red
            codeBackground: ThemeColor(0x3C3836), // bg1
            keyword: ThemeColor(0xFB4934),
            string: ThemeColor(0xB8BB26), // green
            comment: ThemeColor(0x928374),
            number: ThemeColor(0xD3869B), // purple
            type: ThemeColor(0xFABD2F), // yellow
            function: ThemeColor(0x8EC07C) // aqua
        )
    )

    /// One Light and One Dark, from Atom.
    static let one = EditorTheme(
        id: "one",
        name: "One",
        light: Palette(
            background: ThemeColor(0xFAFAFA),
            foreground: ThemeColor(0x383A42),
            muted: ThemeColor(0xA0A1A7),
            syntax: ThemeColor(0xC2C3C7),
            accent: ThemeColor(0x4078F2), // blue
            selection: ThemeColor(0x4078F2, alpha: 0.14),
            quote: ThemeColor(0x696C77),
            inlineCode: ThemeColor(0xE45649), // red
            codeBackground: ThemeColor(0x383A42, alpha: 0.06),
            keyword: ThemeColor(0xA626A4), // purple
            string: ThemeColor(0x50A14F), // green
            comment: ThemeColor(0xA0A1A7),
            number: ThemeColor(0xC18401), // yellow
            type: ThemeColor(0xC18401),
            function: ThemeColor(0x4078F2)
        ),
        dark: Palette(
            background: ThemeColor(0x282C34),
            foreground: ThemeColor(0xABB2BF),
            muted: ThemeColor(0x5C6370),
            syntax: ThemeColor(0x4B5263),
            accent: ThemeColor(0x61AFEF), // blue
            selection: ThemeColor(0x61AFEF, alpha: 0.24),
            quote: ThemeColor(0x8B92A0),
            inlineCode: ThemeColor(0xE06C75), // red
            codeBackground: ThemeColor(0xFFFFFF, alpha: 0.07),
            keyword: ThemeColor(0xC678DD), // purple
            string: ThemeColor(0x98C379), // green
            comment: ThemeColor(0x5C6370),
            number: ThemeColor(0xE5C07B), // yellow
            type: ThemeColor(0xE5C07B),
            function: ThemeColor(0x61AFEF)
        )
    )
}

// MARK: - Current selection

/// Holds the active theme.
///
/// Not main-actor isolated: the dynamic `NSColor` providers in `AppColors` may be resolved by
/// AppKit on whichever thread is drawing, and they read through here.
enum ThemeStore {
    private static let lock = NSLock()
    private static var storage: EditorTheme = .minidown

    static var current: EditorTheme {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Returns true when the theme actually changed, so callers can skip a needless restyle.
    @discardableResult
    static func select(id: String) -> Bool {
        let theme = EditorTheme.named(id)
        lock.lock()
        let changed = storage.id != theme.id
        storage = theme
        lock.unlock()
        if changed { AppColors.invalidate() }
        return changed
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        current.palette(for: appearance)
    }
}
