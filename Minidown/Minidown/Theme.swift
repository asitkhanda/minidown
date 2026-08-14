import AppKit
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system, .liquidGlass: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var usesLiquidGlassChrome: Bool {
        self == .liquidGlass
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

    func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
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

    func monoFont(ofSize size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

enum AppColors {
    static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.30, green: 0.67, blue: 0.97, alpha: 1)
            : NSColor(calibratedRed: 0.11, green: 0.49, blue: 0.84, alpha: 1)
    }

    static let muted = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.37, alpha: 1)
            : NSColor(calibratedWhite: 0.64, alpha: 1)
    }

    static let syntax = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.31, alpha: 1)
            : NSColor(calibratedWhite: 0.69, alpha: 1)
    }

    static let code = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.76, alpha: 1)
            : NSColor(calibratedRed: 0.76, green: 0.15, blue: 0.36, alpha: 1)
    }

    static let quote = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.56, alpha: 1)
            : NSColor(calibratedWhite: 0.44, alpha: 1)
    }

    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.114, alpha: 1)
            : NSColor(calibratedRed: 0.984, green: 0.984, blue: 0.980, alpha: 1)
    }

    static let foreground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.847, alpha: 1)
            : NSColor(calibratedWhite: 0.110, alpha: 1)
    }
}
