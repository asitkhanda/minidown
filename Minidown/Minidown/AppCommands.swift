import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var store: DocumentStore
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { store.newFile() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { store.openFile() }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Save") { _ = store.saveFile(saveAs: false) }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save As…") { _ = store.saveFile(saveAs: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Menu("Export") {
                Button("PDF (Print)…") {
                    Exporter.export(store.text, format: .pdf, baseURL: store.fileURL)
                }
                .keyboardShortcut("p", modifiers: .command)
                Button("HTML…") {
                    Exporter.export(store.text, format: .html, baseURL: store.fileURL)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Word (.docx)…") {
                    Exporter.export(store.text, format: .docx, baseURL: store.fileURL)
                }
                Button("Rich Text (.rtf)…") {
                    Exporter.export(store.text, format: .rtf, baseURL: store.fileURL)
                }
                Button("Plain Text…") {
                    Exporter.export(store.text, format: .txt, baseURL: store.fileURL)
                }
            }
        }

        CommandMenu("View") {
            Button(store.focusMode ? "Focus Mode ✓" : "Focus Mode") {
                store.toggleFocus()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button(store.typewriter ? "Typewriter Scrolling ✓" : "Typewriter Scrolling") {
                store.toggleTypewriter()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            Menu("Font") {
                ForEach(EditorFontFamily.allCases) { family in
                    Button(fontFamilyRaw == family.rawValue ? "\(family.title) ✓" : family.title) {
                        fontFamilyRaw = family.rawValue
                    }
                }
            }

            Menu("Appearance") {
                ForEach(ThemePreference.allCases) { pref in
                    Button(themeRaw == pref.rawValue ? "\(pref.title) ✓" : pref.title) {
                        themeRaw = pref.rawValue
                    }
                }
            }
        }
    }
}
