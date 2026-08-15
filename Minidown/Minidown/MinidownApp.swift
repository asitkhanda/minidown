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
