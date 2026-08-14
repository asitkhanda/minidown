import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var focusMode = UserDefaults.standard.bool(forKey: "focus")
    @Published var typewriter = UserDefaults.standard.bool(forKey: "typewriter")
    @Published var statsMode = StatsMode(rawValue: UserDefaults.standard.string(forKey: "statsMode") ?? "words") ?? .words
    @Published var selectionLocation: Int = 0
    @Published var selectionLength: Int = 0

    private var autosaveTask: Task<Void, Never>?
    private var loading = false

    var fileName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    var directoryURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    var windowTitle: String {
        isDirty ? "\(fileName) — Edited" : fileName
    }

    func setDocument(text: String, url: URL?) {
        loading = true
        self.text = text
        fileURL = url
        isDirty = false
        loading = false
    }

    func updateText(_ newText: String) {
        guard !loading else { return }
        text = newText
        if !isDirty {
            isDirty = true
        }
        scheduleAutosave()
    }

    func updateSelection(location: Int, length: Int) {
        selectionLocation = location
        selectionLength = length
    }

    func newFile() {
        if isDirty && fileURL == nil && !text.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes?"
            alert.informativeText = "This untitled document has unsaved edits."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        setDocument(text: "", url: nil)
    }

    func openFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                setDocument(text: contents, url: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @discardableResult
    func saveFile(saveAs: Bool = false) -> Bool {
        var url = fileURL
        if saveAs || url == nil {
            let panel = NSSavePanel()
            if let md = UTType(filenameExtension: "md") {
                panel.allowedContentTypes = [md]
            }
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            url = chosen
        }
        guard let url else { return false }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            isDirty = false
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func toggleFocus() {
        focusMode.toggle()
        UserDefaults.standard.set(focusMode, forKey: "focus")
    }

    func toggleTypewriter() {
        typewriter.toggle()
        UserDefaults.standard.set(typewriter, forKey: "typewriter")
    }

    func cycleStatsMode() {
        statsMode = statsMode.next
        UserDefaults.standard.set(statsMode.rawValue, forKey: "statsMode")
    }

    private func scheduleAutosave() {
        guard fileURL != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                _ = self?.saveFile(saveAs: false)
            }
        }
    }
}
