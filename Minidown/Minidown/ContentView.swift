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
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    let chrome: ChromeStyle

    @EnvironmentObject private var settings: EditorSettings

    var body: some View {
        VStack(spacing: 0) {
            MarkdownEditorView(document: document, chrome: chrome)
                .environmentObject(settings)

            StatusBarView(document: document, chrome: chrome)
                .environmentObject(settings)
        }
        // The backdrop sits behind everything and provides the window surface. Under glass the
        // editor and status bar are transparent so this material is what the writer actually sees.
        .background {
            GlassBackdrop(style: chrome, tint: nil)
                .ignoresSafeArea()
        }
        .onAppear { document.fileURL = fileURL }
        .onChange(of: fileURL) { _, url in document.fileURL = url }
        // Publishes the front-most document to the menu bar's export commands.
        .focusedSceneValue(\.documentText, document.text)
        .focusedSceneValue(\.documentURL, fileURL)
    }
}
