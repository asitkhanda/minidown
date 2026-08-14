import Foundation

enum StatsMode: String, CaseIterable {
    case words
    case characters
    case reading

    var next: StatsMode {
        switch self {
        case .words: return .characters
        case .characters: return .reading
        case .reading: return .words
        }
    }

    func format(_ text: String) -> String {
        switch self {
        case .words:
            let count = wordCount(text)
            return count == 1 ? "1 word" : "\(count) words"
        case .characters:
            let count = text.count
            return count == 1 ? "1 character" : "\(count) characters"
        case .reading:
            let minutes = max(1, Int(ceil(Double(wordCount(text)) / 200.0)))
            return minutes == 1 ? "1 min read" : "\(minutes) min read"
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
