import AppKit
import SwiftUI

/// Light/dark appearance. Deliberately independent of the window material.
///
/// These used to be the same setting, with "Liquid Glass" as a fourth case — which meant glass
/// could not be combined with an explicit light or dark appearance, and picking it silently meant
/// "System". Appearance and material are orthogonal, so they are two settings now.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Older builds stored a combined value; "liquidGlass" meant "system appearance, glass chrome".
    static func migrating(_ raw: String) -> ThemePreference {
        ThemePreference(rawValue: raw) ?? .system
    }
}

/// The window material.
enum ChromeStyle: String, CaseIterable, Identifiable {
    /// Native Liquid Glass. The default, since macOS 26 is where most users are.
    case liquidGlass
    /// Flat, opaque chrome. Used below macOS 26, or by choice.
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .solid: return "Solid"
        }
    }

    /// Whether real Liquid Glass is available on this OS.
    static var isGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// What the app should actually draw, after accounting for OS support.
    ///
    /// Below macOS 26 the stored preference is honoured but downgraded at render time, so a user
    /// on an older OS still gets a coherent window and their choice survives an upgrade.
    var resolved: ChromeStyle {
        guard self == .liquidGlass, !Self.isGlassAvailable else { return self }
        return .solid
    }

    var usesGlass: Bool { resolved == .liquidGlass }

    /// Default for a fresh install: glass where it exists, solid otherwise.
    static var defaultValue: ChromeStyle {
        isGlassAvailable ? .liquidGlass : .solid
    }

    /// Migrates the old combined "theme" value, where `liquidGlass` was an appearance.
    static func migrating(themeRaw: String, chromeRaw: String?) -> ChromeStyle {
        if let chromeRaw, let stored = ChromeStyle(rawValue: chromeRaw) { return stored }
        if themeRaw == "liquidGlass" { return .liquidGlass }
        return defaultValue
    }
}

enum EditorFontFamily: String, CaseIterable, Identifiable {
    case sansSerif
    case serif
    case typewriter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sansSerif: return "Sans Serif"
        case .serif: return "Serif"
        case .typewriter: return "Typewriter"
        }
    }

    /// The families to try, in order. Falling through to nil means the system face.
    var candidates: [String] {
        switch self {
        case .sansSerif: return [EditorFonts.sansSerifFamily]
        case .serif: return [EditorFonts.serifFamily]
        case .typewriter: return [EditorFonts.monospaceFamily]
        }
    }

    /// True when the preferred face is missing and the editor is drawing a substitute.
    var isUsingFallback: Bool {
        EditorFonts.firstAvailable(candidates) == nil
    }

    /// Says so in the menu when a bundled face failed to register, rather than silently drawing
    /// something else and leaving the reader to wonder why the font looks wrong.
    var menuTitle: String {
        isUsingFallback ? "\(title) (unavailable)" : title
    }

    func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        EditorFonts.registerBundledFonts()

        if let family = EditorFonts.firstAvailable(candidates),
           let font = EditorFonts.font(family: family, size: size, weight: weight) {
            return font
        }
        return systemFallback(ofSize: size, weight: weight)
    }

    private func systemFallback(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .sansSerif:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        case .typewriter:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    /// The face used for code — fenced blocks and inline code — regardless of the prose font.
    ///
    /// Always Fira Code: code wants a monospaced face with programming ligatures whatever the
    /// surrounding prose is set in.
    func monoFont(ofSize size: CGFloat) -> NSFont {
        EditorFonts.registerBundledFonts()
        if EditorFonts.isAvailable(EditorFonts.monospaceFamily),
           let font = EditorFonts.font(family: EditorFonts.monospaceFamily, size: size, weight: .regular) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// The editor palette, resolved from the active theme and the current appearance.
///
/// Every member is a dynamic `NSColor` whose provider reads `ThemeStore` at resolve time, so the
/// ~50 call sites across the editor never mention a theme at all — they ask for a role and get the
/// right colour for whichever theme and appearance is live.
///
/// The instances are cached and rebuilt on `invalidate()` rather than being resolved fresh each
/// access: AppKit caches resolved values per appearance, so handing back the *same* NSColor after
/// a theme change could keep serving the previous theme's colour.
enum AppColors {
    private static let lock = NSLock()
    private static var cache: [String: NSColor] = [:]

    /// Called when the active theme changes.
    static func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func role(_ key: String, _ pick: @escaping (Palette) -> ThemeColor) -> NSColor {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let color = NSColor(name: nil) { appearance in
            pick(ThemeStore.palette(for: appearance)).nsColor
        }
        lock.lock()
        cache[key] = color
        lock.unlock()
        return color
    }

    static var background: NSColor { role("background") { $0.background } }
    static var foreground: NSColor { role("foreground") { $0.foreground } }
    static var muted: NSColor { role("muted") { $0.muted } }
    static var syntax: NSColor { role("syntax") { $0.syntax } }
    static var accent: NSColor { role("accent") { $0.accent } }
    static var selection: NSColor { role("selection") { $0.selection } }
    static var quote: NSColor { role("quote") { $0.quote } }
    static var code: NSColor { role("code") { $0.inlineCode } }
    static var codeBackground: NSColor { role("codeBackground") { $0.codeBackground } }

    static var sxKeyword: NSColor { role("sxKeyword") { $0.keyword } }
    static var sxString: NSColor { role("sxString") { $0.string } }
    static var sxComment: NSColor { role("sxComment") { $0.comment } }
    static var sxNumber: NSColor { role("sxNumber") { $0.number } }
    static var sxType: NSColor { role("sxType") { $0.type } }
    static var sxFunc: NSColor { role("sxFunc") { $0.function } }

    /// Paper tint for the Liquid Glass canvas: the theme's own background, kept mostly opaque so
    /// prose stays legible over whatever is behind the window.
    static var glassCanvasTint: NSColor {
        role("glassCanvasTint") { $0.background.withAlpha(0.90) }
    }
}
