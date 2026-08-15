import AppKit
import XCTest
@testable import Minidown

/// Liquid Glass is the default chrome, and appearance is a separate axis from it.
@MainActor
final class LiquidGlassTests: XCTestCase {
    // MARK: - Defaults and availability

    func testLiquidGlassIsTheDefaultOnSupportedSystems() {
        if #available(macOS 26.0, *) {
            XCTAssertEqual(ChromeStyle.defaultValue, .liquidGlass, "glass is the default on macOS 26+")
            XCTAssertTrue(ChromeStyle.isGlassAvailable)
        } else {
            XCTAssertEqual(ChromeStyle.defaultValue, .solid, "older systems fall back")
            XCTAssertFalse(ChromeStyle.isGlassAvailable)
        }
    }

    /// The preference is stored as chosen and downgraded at render time, so it survives an OS
    /// upgrade rather than being rewritten to `solid` on an older machine.
    func testGlassResolvesToSolidWhenUnavailable() {
        if ChromeStyle.isGlassAvailable {
            XCTAssertEqual(ChromeStyle.liquidGlass.resolved, .liquidGlass)
            XCTAssertTrue(ChromeStyle.liquidGlass.usesGlass)
        } else {
            XCTAssertEqual(ChromeStyle.liquidGlass.resolved, .solid)
            XCTAssertFalse(ChromeStyle.liquidGlass.usesGlass)
        }
        XCTAssertEqual(ChromeStyle.solid.resolved, .solid)
        XCTAssertFalse(ChromeStyle.solid.usesGlass)
    }

    // MARK: - Appearance is independent of material

    /// The old model made "Liquid Glass" a fourth *appearance*, so it could not be combined with an
    /// explicit light or dark setting — picking it silently meant "System".
    func testAppearanceAndChromeAreIndependent() {
        XCTAssertEqual(ThemePreference.allCases, [.system, .light, .dark])
        XCTAssertEqual(ThemePreference.light.colorScheme, .light)
        XCTAssertEqual(ThemePreference.dark.colorScheme, .dark)
        XCTAssertNil(ThemePreference.system.colorScheme)
    }

    func testLegacyLiquidGlassThemeMigratesToGlassChrome() {
        // Stored by an older build, where the two settings were one.
        XCTAssertEqual(ChromeStyle.migrating(themeRaw: "liquidGlass", chromeRaw: nil), .liquidGlass)
        // …and it is not a valid appearance, so appearance falls back to System.
        XCTAssertEqual(ThemePreference.migrating("liquidGlass"), .system)
    }

    func testExplicitChromeChoiceWinsOverLegacyTheme() {
        XCTAssertEqual(ChromeStyle.migrating(themeRaw: "liquidGlass", chromeRaw: "solid"), .solid)
        XCTAssertEqual(ChromeStyle.migrating(themeRaw: "dark", chromeRaw: "liquidGlass"), .liquidGlass)
    }

    func testUnknownStoredValuesFallBackCleanly() {
        XCTAssertEqual(ThemePreference.migrating("nonsense"), .system)
        XCTAssertEqual(ChromeStyle.migrating(themeRaw: "nonsense", chromeRaw: "nonsense"), ChromeStyle.defaultValue)
    }

    // MARK: - Canvas tint

    /// The regression that made the editor unreadable: the glass tint was resolved eagerly against
    /// whatever appearance was current when the backdrop was built, so a dark colour scheme got a
    /// light paper tint and dark-mode text became invisible against it.
    func testCanvasTintIsDynamicAcrossAppearances() {
        let light = resolve(AppColors.glassCanvasTint, in: .aqua)
        let dark = resolve(AppColors.glassCanvasTint, in: .darkAqua)

        XCTAssertNotEqual(
            light.brightnessComponentApproximation,
            dark.brightnessComponentApproximation,
            "the tint must track appearance, not bake one in"
        )
        XCTAssertGreaterThan(light.brightnessComponentApproximation, 0.5, "light tint should be paper")
        XCTAssertLessThan(dark.brightnessComponentApproximation, 0.5, "dark tint should be ink")
    }

    /// Text has to stay readable on the tinted canvas — that is the whole reason for the tint.
    func testForegroundContrastsWithCanvasTintInBothAppearances() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let tint = resolve(AppColors.glassCanvasTint, in: appearance)
            let text = resolve(AppColors.foreground, in: appearance)
            let delta = abs(tint.brightnessComponentApproximation - text.brightnessComponentApproximation)
            XCTAssertGreaterThan(delta, 0.4, "text is not legible on the canvas in \(appearance.rawValue)")
        }
    }

    /// A fully transparent canvas is what made the desktop bleed through the prose.
    func testCanvasTintIsSubstantiallyOpaque() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let tint = resolve(AppColors.glassCanvasTint, in: appearance)
            XCTAssertGreaterThan(tint.alphaComponent, 0.8, "canvas needs enough paper to read on")
            XCTAssertLessThan(tint.alphaComponent, 1.0, "…but not so much that the glass is pointless")
        }
    }

    /// Under glass the editor must not paint its own surface, or the material is hidden behind it.
    func testEditorBackgroundIsClearUnderGlass() {
        XCTAssertEqual(AppColors.editorBackground(glass: true), .clear)
        XCTAssertNotEqual(AppColors.editorBackground(glass: false), .clear)
    }

    // MARK: - Layout parity

    /// Switching the window material must not move anything.
    ///
    /// It used to: `.buttonStyle(.glass)` and `.buttonStyle(.plain)` have different metrics —
    /// padded capsules versus bare text — so the status bar changed height when the chrome
    /// changed, and the editor shifted with it. Metrics now live in one place and only the
    /// background varies.
    func testStatusChipMetricsAreIdenticalAcrossChromeStyles() {
        let glass = StatusChipStyle(chrome: .liquidGlass)
        let solid = StatusChipStyle(chrome: .solid)
        XCTAssertEqual(glass.metrics, solid.metrics, "chrome must not change control metrics")
    }

    /// A control's size may depend on whether it is highlighted only through colour.
    func testHighlightDoesNotChangeMetrics() {
        XCTAssertEqual(
            StatusChipStyle(chrome: .liquidGlass, isHighlighted: true).metrics,
            StatusChipStyle(chrome: .liquidGlass, isHighlighted: false).metrics
        )
    }

    // MARK: - Helpers

    private func resolve(_ color: NSColor, in name: NSAppearance.Name) -> NSColor {
        guard let appearance = NSAppearance(named: name) else { return color }
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }
}

private extension NSColor {
    /// Perceived brightness, for contrast assertions.
    var brightnessComponentApproximation: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else { return 0 }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }
}
