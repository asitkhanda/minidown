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
import XCTest
@testable import Minidown

/// Every built-in theme has to be usable, in both appearances.
///
/// A palette is just data, so the risk is not that the code breaks — it is that a theme ships with
/// an unreadable combination. These assertions are what stop that.
@MainActor
final class EditorThemeTests: XCTestCase {
    override func tearDown() {
        ThemeStore.select(id: EditorTheme.minidown.id)
        super.tearDown()
    }

    private func contrast(_ a: ThemeColor, _ b: ThemeColor) -> Double {
        abs(a.brightness - b.brightness)
    }

    /// Flattens a partly transparent colour over its background, the way it actually draws.
    private func composited(_ color: ThemeColor, over background: ThemeColor) -> ThemeColor {
        let alpha = color.alpha
        return ThemeColor(
            red: color.red * alpha + background.red * (1 - alpha),
            green: color.green * alpha + background.green * (1 - alpha),
            blue: color.blue * alpha + background.blue * (1 - alpha)
        )
    }

    private func eachPalette(_ body: (String, Palette) -> Void) {
        for theme in EditorTheme.allBuiltIn {
            body("\(theme.name) light", theme.light)
            body("\(theme.name) dark", theme.dark)
        }
    }

    // MARK: - Legibility

    func testProseIsLegibleInEveryPalette() {
        eachPalette { label, palette in
            XCTAssertGreaterThan(
                contrast(palette.foreground, palette.background), 0.35,
                "\(label): body text does not contrast with the page"
            )
        }
    }

    func testSecondaryTextIsLegibleInEveryPalette() {
        eachPalette { label, palette in
            for (role, color) in [("quote", palette.quote), ("muted", palette.muted)] {
                XCTAssertGreaterThan(
                    contrast(color, palette.background), 0.12,
                    "\(label): \(role) is too close to the background to read"
                )
            }
        }
    }

    /// Revealed markdown syntax is deliberately quiet, but it still has to be visible.
    func testSyntaxMarksAreVisibleButSubdued() {
        eachPalette { label, palette in
            let delta = contrast(palette.syntax, palette.background)
            XCTAssertGreaterThan(delta, 0.06, "\(label): syntax marks are invisible")
            XCTAssertLessThan(delta, contrast(palette.foreground, palette.background),
                              "\(label): syntax marks should be quieter than prose")
        }
    }

    func testCodeTokensAreLegibleOnTheCodeBackground() {
        eachPalette { label, palette in
            let surface = composited(palette.codeBackground, over: palette.background)
            let tokens: [(String, ThemeColor)] = [
                ("keyword", palette.keyword), ("string", palette.string),
                ("comment", palette.comment), ("number", palette.number),
                ("type", palette.type), ("function", palette.function),
                ("inline code", palette.inlineCode),
            ]
            for (role, color) in tokens {
                XCTAssertGreaterThan(
                    contrast(color, surface), 0.08,
                    "\(label): \(role) is unreadable on the code surface"
                )
            }
        }
    }

    func testLinksStandOutFromProse() {
        eachPalette { label, palette in
            XCTAssertGreaterThan(
                contrast(palette.accent, palette.background), 0.10,
                "\(label): links vanish into the page"
            )
        }
    }

    /// Light palettes must actually be light, and dark ones dark, or "Light" and "Dark" lie.
    func testLightAndDarkPalettesAreOrientedCorrectly() {
        for theme in EditorTheme.allBuiltIn {
            XCTAssertGreaterThan(theme.light.background.brightness, 0.5, "\(theme.name) light is not light")
            XCTAssertLessThan(theme.dark.background.brightness, 0.5, "\(theme.name) dark is not dark")
        }
    }

    func testEveryThemeHasADistinctIdentity() {
        let ids = EditorTheme.allBuiltIn.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "theme ids must be unique — they are persisted")
        XCTAssertTrue(EditorTheme.allBuiltIn.contains { $0.id == EditorTheme.minidown.id })
    }

    // MARK: - Selection plumbing

    func testSelectingAThemeChangesTheResolvedColours() {
        ThemeStore.select(id: EditorTheme.minidown.id)
        let before = resolved(AppColors.background, dark: false)

        XCTAssertTrue(ThemeStore.select(id: EditorTheme.dracula.id), "changing theme reports a change")
        let after = resolved(AppColors.background, dark: false)

        XCTAssertNotEqual(before, after, "the palette must actually follow the selected theme")
        XCTAssertFalse(ThemeStore.select(id: EditorTheme.dracula.id), "re-selecting is a no-op")
    }

    /// Widget bitmaps bake the palette in, so their cache key has to include the theme.
    func testWidgetCacheKeysIncludeTheTheme() {
        let table = MarkdownTable(alignments: [nil], header: [.init(text: "a", colspan: 1, rowspan: 1)], rows: [])

        ThemeStore.select(id: EditorTheme.minidown.id)
        let a = WidgetCacheKey.table(table, dark: false, fontFamily: .sansSerif)
        let mathA = WidgetCacheKey.math(tex: "x", display: false, dark: false)

        ThemeStore.select(id: EditorTheme.nord.id)
        let b = WidgetCacheKey.table(table, dark: false, fontFamily: .sansSerif)
        let mathB = WidgetCacheKey.math(tex: "x", display: false, dark: false)

        XCTAssertNotEqual(a, b, "a themed table must not be served from another theme's cache")
        XCTAssertNotEqual(mathA, mathB, "same for rendered math")
    }

    func testUnknownThemeIdFallsBackToTheDefault() {
        XCTAssertEqual(EditorTheme.named("does-not-exist").id, EditorTheme.minidown.id)
    }

    /// Palettes are Codable so user-supplied themes can be loaded later without a redesign.
    func testThemesRoundTripThroughJSON() throws {
        for theme in EditorTheme.allBuiltIn {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(EditorTheme.self, from: data)
            XCTAssertEqual(decoded, theme, "\(theme.name) did not survive a JSON round trip")
        }
    }

    private func resolved(_ color: NSColor, dark: Bool) -> NSColor {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return color }
        var out = color
        appearance.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.deviceRGB) ?? color
        }
        return out
    }
}
