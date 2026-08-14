import SwiftUI

@main
struct MinidownApp: App {
    @StateObject private var store = DocumentStore()
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(ThemePreference(rawValue: themeRaw)?.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 720)
        .commands {
            AppCommands(store: store)
        }
    }
}
