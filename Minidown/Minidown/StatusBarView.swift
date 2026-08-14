import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("theme") private var themeRaw = ThemePreference.system.rawValue
    @AppStorage("fontFamily") private var fontFamilyRaw = EditorFontFamily.sansSerif.rawValue
    @State private var exportPresented = false

    private var theme: ThemePreference {
        ThemePreference(rawValue: themeRaw) ?? .system
    }

    private var fontFamily: EditorFontFamily {
        EditorFontFamily(rawValue: fontFamilyRaw) ?? .sansSerif
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(store.windowTitle)
                .foregroundStyle(Color(nsColor: AppColors.muted))
                .lineLimit(1)

            Spacer()

            toggleButton("Focus", isOn: store.focusMode, action: store.toggleFocus)
            toggleButton("Typewriter", isOn: store.typewriter, action: store.toggleTypewriter)

            Menu {
                ForEach(EditorFontFamily.allCases) { family in
                    Button(fontFamily == family ? "\(family.title) ✓" : family.title) {
                        fontFamilyRaw = family.rawValue
                    }
                }
            } label: {
                Text(fontFamily.title)
                    .foregroundStyle(Color(nsColor: AppColors.muted))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Editor font")

            Menu {
                ForEach(ThemePreference.allCases) { pref in
                    Button(theme == pref ? "\(pref.title) ✓" : pref.title) {
                        themeRaw = pref.rawValue
                    }
                }
            } label: {
                Text(theme.title)
                    .foregroundStyle(Color(nsColor: AppColors.muted))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Appearance")

            Button("Export") { exportPresented.toggle() }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: AppColors.muted))
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

            Button(store.statsMode.format(store.text)) {
                store.cycleStatsMode()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: AppColors.muted))
            .help("Words · characters · reading time")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background { statusBarChrome }
        .overlay(alignment: .top) {
            if !theme.usesLiquidGlassChrome {
                Divider().opacity(0.35)
            }
        }
    }

    @ViewBuilder
    private var statusBarChrome: some View {
        if theme.usesLiquidGlassChrome {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        } else {
            Color(nsColor: AppColors.background).opacity(0.92)
        }
    }

    private func toggleButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(isOn ? Color(nsColor: AppColors.accent) : Color(nsColor: AppColors.muted))
    }

    private func exportRow(_ title: String, _ format: ExportFormat) -> some View {
        Button(title) {
            exportPresented = false
            Exporter.export(store.text, format: format, baseURL: store.fileURL)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
