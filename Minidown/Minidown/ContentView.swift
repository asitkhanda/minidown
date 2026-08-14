import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 44)
                .background(WindowDragRegion())

            MarkdownEditorView()
                .environmentObject(store)

            StatusBarView()
                .environmentObject(store)
        }
        .background(Color(nsColor: AppColors.background))
        .ignoresSafeArea()
        .onAppear {
            NSApp.windows.first?.title = store.windowTitle
        }
        .onChange(of: store.windowTitle) { _, title in
            NSApp.windows.first?.title = title
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
