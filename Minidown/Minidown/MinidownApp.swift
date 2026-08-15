// minidown — a minimal, distraction-free Markdown writer for macOS.
// Copyright (C) 2026 Asit Khanda
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version. See <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

@main
struct MinidownApp: App {
    @StateObject private var settings = EditorSettings()
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue
    // Liquid Glass is the default: macOS 26 is where the app expects to run, and the chrome is
    // downgraded automatically on older systems rather than by storing a different preference.
    @AppStorage("chrome") private var chromeRaw = ChromeStyle.defaultValue.rawValue

    private var theme: ThemePreference {
        ThemePreference.migrating(themeRaw)
    }

    private var chrome: ChromeStyle {
        ChromeStyle.migrating(themeRaw: themeRaw, chromeRaw: chromeRaw)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL, chrome: chrome)
                .environmentObject(settings)
                // Appearance is independent of the material, so Liquid Glass gets a proper light
                // and dark variant rather than always following the system.
                .preferredColorScheme(theme.colorScheme)
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            AppCommands(settings: settings)
        }
    }
}
