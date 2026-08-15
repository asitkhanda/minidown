import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The system UTI for `.md` / `.markdown`.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}

/// The document model.
///
/// `ReferenceFileDocument` rather than `FileDocument` because the latter is a struct and SwiftUI
/// copies it on every mutation — for an editor holding the whole file in memory that is a copy per
/// keystroke.
///
/// Adopting the document architecture retires a pile of hand-rolled machinery: the dirty flag and
/// its `" — Edited"` title suffix, the debounced autosave, the discard-changes alert, and the
/// open/save panels. It also closes real data-loss holes — the old `openFile()` never checked
/// whether the current document was dirty, so opening a file silently discarded unsaved work — and
/// brings Recents, Duplicate, Rename, Revert To, autosave-in-place and window restoration.
@MainActor
final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.markdownText, .plainText, .text] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    @Published var text: String
    /// Where the file lives, for resolving relative image paths. Set by the window on appear.
    @Published var fileURL: URL?
    @Published var selectionLocation: Int = 0
    @Published var selectionLength: Int = 0

    var directoryURL: URL? { fileURL?.deletingLastPathComponent() }

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Fall back rather than refusing to open a file that is not valid UTF-8.
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        // Byte-faithful: whatever is in the buffer is exactly what lands on disk.
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    func updateText(_ newText: String, undoManager: UndoManager?) {
        guard newText != text else { return }
        let previous = text
        text = newText
        // Registering here is what marks the document edited and drives autosave-in-place.
        undoManager?.registerUndo(withTarget: self) { document in
            document.updateText(previous, undoManager: undoManager)
        }
    }

    func updateSelection(location: Int, length: Int) {
        selectionLocation = location
        selectionLength = length
    }
}

/// Editor preferences that are not part of any document.
@MainActor
final class EditorSettings: ObservableObject {
    @Published var focusMode: Bool {
        didSet { UserDefaults.standard.set(focusMode, forKey: "focus") }
    }

    @Published var typewriter: Bool {
        didSet { UserDefaults.standard.set(typewriter, forKey: "typewriter") }
    }

    @Published var statsMode: StatsMode {
        didSet { UserDefaults.standard.set(statsMode.rawValue, forKey: "statsMode") }
    }

    init() {
        focusMode = UserDefaults.standard.bool(forKey: "focus")
        typewriter = UserDefaults.standard.bool(forKey: "typewriter")
        statsMode = StatsMode(rawValue: UserDefaults.standard.string(forKey: "statsMode") ?? "words") ?? .words
    }

    func toggleFocus() { focusMode.toggle() }
    func toggleTypewriter() { typewriter.toggle() }
    func cycleStatsMode() { statsMode = statsMode.next }
}
