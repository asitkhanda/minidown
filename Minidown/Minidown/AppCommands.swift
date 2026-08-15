import SwiftUI

/// Menu bar.
///
/// File open/save/new, and the unsaved-changes and quit prompts, all come from the document
/// architecture now — they used to be hand-rolled and, in the case of open, missing entirely.
/// Toggle state uses real menu-item checkmarks rather than a `"… ✓"` suffix baked into the title.
struct AppCommands: Commands {
    @ObservedObject var settings: EditorSettings
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue
    @AppStorage("chrome") private var chromeRaw = ChromeStyle.defaultValue.rawValue
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue
    @AppStorage("colorTheme") private var colorThemeID = EditorTheme.minidown.id

    @FocusedValue(\.documentText) private var documentText
    @FocusedValue(\.documentURL) private var documentURL

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About minidown") { showAbout() }
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                exportButton("PDF (Print)…", .pdf, shortcut: "p", modifiers: .command)
                exportButton("HTML…", .html, shortcut: "e", modifiers: [.command, .shift])
                exportButton("Word (.docx)…", .docx)
                exportButton("Rich Text (.rtf)…", .rtf)
                exportButton("Plain Text…", .txt)
            }
        }

        // Into the *existing* View menu. `CommandMenu("View")` creates a second one — macOS
        // already gives document apps a View menu, so the app ended up with two.
        CommandGroup(after: .toolbar) {
            Toggle("Focus Mode", isOn: Binding(
                get: { settings.focusMode },
                set: { _ in settings.toggleFocus() }
            ))
            .keyboardShortcut("d", modifiers: .command)

            Toggle("Typewriter Scrolling", isOn: Binding(
                get: { settings.typewriter },
                set: { _ in settings.toggleTypewriter() }
            ))
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            Picker("Font", selection: $fontFamilyRaw) {
                ForEach(EditorFontFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }

            Picker("Theme", selection: $colorThemeID) {
                ForEach(EditorTheme.allBuiltIn) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }

            Picker("Appearance", selection: $themeRaw) {
                ForEach(ThemePreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            }

            // Separate from appearance: Liquid Glass works in both light and dark.
            Picker("Window", selection: $chromeRaw) {
                ForEach(ChromeStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            .disabled(!ChromeStyle.isGlassAvailable)
        }
    }

    @ViewBuilder
    private func exportButton(
        _ title: String,
        _ format: ExportFormat,
        shortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command
    ) -> some View {
        let button = Button(title) {
            guard let documentText else { return }
            Exporter.export(documentText, format: format, baseURL: documentURL)
        }
        .disabled(documentText == nil)

        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: modifiers)
        } else {
            button
        }
    }

    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "minidown",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © 2026 Asit Khanda",
            .credits: NSAttributedString(
                string: "A minimal, distraction-free Markdown writer.\n"
                    + "Licensed under AGPL-3.0.\n\n"
                    + "Bundles KaTeX and Mermaid (MIT), and tree-sitter grammars (MIT).",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }
}

// MARK: - Focused document values

/// Lets menu commands reach the front-most document without a global singleton, which matters now
/// that several documents can be open at once.
struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

struct DocumentURLKey: FocusedValueKey {
    typealias Value = URL
}

extension FocusedValues {
    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }

    var documentURL: URL? {
        get { self[DocumentURLKey.self] }
        set { self[DocumentURLKey.self] = newValue }
    }
}
