import SwiftUI

struct StatusBarView: View {
    @ObservedObject var document: MarkdownDocument
    let chrome: ChromeStyle

    @EnvironmentObject private var settings: EditorSettings
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue
    @AppStorage("chrome") private var chromeRaw = ChromeStyle.defaultValue.rawValue
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue
    @AppStorage("colorTheme") private var colorThemeID = EditorTheme.minidown.id
    @State private var exportPresented = false

    private var theme: ThemePreference { ThemePreference.migrating(themeRaw) }

    private var fontFamily: EditorFontFamily {
        EditorFontFamily(rawValue: fontFamilyRaw) ?? .sansSerif
    }

    /// The window title bar already shows the filename and the edited dot, so the bar names the
    /// document without duplicating save state.
    private var name: String {
        document.fileURL?.lastPathComponent ?? "Untitled"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            toggleButton("Focus", isOn: settings.focusMode, action: settings.toggleFocus)
            toggleButton("Typewriter", isOn: settings.typewriter, action: settings.toggleTypewriter)

            menu(EditorTheme.named(colorThemeID).name, help: "Colour theme") {
                ForEach(EditorTheme.allBuiltIn) { theme in
                    checkedButton(theme.name, isOn: theme.id == colorThemeID) {
                        colorThemeID = theme.id
                    }
                }
            }

            menu(fontFamily.title, help: "Editor font") {
                ForEach(EditorFontFamily.allCases) { family in
                    checkedButton(family.menuTitle, isOn: fontFamily == family) {
                        fontFamilyRaw = family.rawValue
                    }
                }
            }

            menu(theme.title, help: "Appearance") {
                ForEach(ThemePreference.allCases) { preference in
                    checkedButton(preference.title, isOn: theme == preference) {
                        themeRaw = preference.rawValue
                    }
                }
                Divider()
                Section("Window") {
                    ForEach(ChromeStyle.allCases) { style in
                        checkedButton(style.title, isOn: chrome == style) {
                            chromeRaw = style.rawValue
                        }
                        .disabled(style == .liquidGlass && !ChromeStyle.isGlassAvailable)
                    }
                }
            }

            Button("Export") { exportPresented.toggle() }
                .statusChip(chrome)
                .popover(isPresented: $exportPresented, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        exportRow("PDF (Print)…", .pdf)
                        exportRow("HTML…", .html)
                        exportRow("Word (.docx)…", .docx)
                        exportRow("Rich Text (.rtf)…", .rtf)
                        exportRow("Plain Text…", .txt)
                    }
                    .padding(8)
                    .frame(minWidth: 180)
                }

            Button(settings.statsMode.format(document.text)) {
                settings.cycleStatsMode()
            }
            .statusChip(chrome)
            .help("Words · characters · reading time")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Wrapped unconditionally so the view tree — and therefore the layout — is identical in
        // every chrome style; the container is inert when glass is off.
        .glassGroup(chrome)
        .background { statusBarChrome }
        .overlay(alignment: .top) {
            // Always present, so the bar's geometry never depends on the material. Glass provides
            // its own edge, so the separator just fades out there.
            Divider().opacity(chrome.usesGlass ? 0 : 0.35)
        }
    }

    /// Under glass the bar is a floating glass surface; otherwise it keeps the flat background and
    /// its hairline separator.
    @ViewBuilder
    private var statusBarChrome: some View {
        if chrome.usesGlass {
            Color.clear.chromeGlass(chrome, cornerRadius: 0)
        } else {
            Color(nsColor: AppColors.background).opacity(0.92)
        }
    }

    private func toggleButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .statusChip(chrome, isHighlighted: isOn)
    }

    /// Menus keep the same padding as the chips so the row's height and rhythm do not depend on
    /// which controls happen to be menus.
    @ViewBuilder
    private func menu(
        _ title: String,
        help: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            Text(title).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
        .frame(minHeight: 20)
        .help(help)
    }

    private func checkedButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func exportRow(_ title: String, _ format: ExportFormat) -> some View {
        Button(title) {
            exportPresented = false
            Exporter.export(document.text, format: format, baseURL: document.fileURL)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
