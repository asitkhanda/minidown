import AppKit

/// Holds the styling state for one editor so restyles can be narrowed to what actually changed,
/// and so the parse can leave the keystroke path entirely.
///
/// Two independent costs had to go. Attribute writes were whole-document, which is fixed by
/// narrowing the applied range. Parsing is whole-document *by necessity* — a fence or `$$` opened
/// anywhere above a slice changes how it parses, so slicing the parse silently corrupts meaning —
/// and swift-markdown offers no incremental API, with cmark alone costing ~60ms on a 20k-word
/// document. So the parse moves off the main thread: an edit restyles immediately against the
/// previous constructs shifted into their new positions, and a fresh parse reconciles a moment
/// later, touching only the ranges that actually differ.
@MainActor
final class LivePreviewSession {
    /// Tests drive this synchronously so they exercise the same code path the app uses.
    enum ParseMode {
        case immediate
        case background
    }

    private let parseMode: ParseMode
    private let parseQueue = DispatchQueue(label: "io.humanx.minidown.parse", qos: .userInitiated)

    private var constructs: [MarkdownRange] = []
    private var styledSelections: [NSRange] = []
    private var hasStyled = false
    private var generation = 0

    /// Fired after a background parse reconciles, so the layout manager can refresh.
    var onReconciled: (() -> Void)?

    init(parseMode: ParseMode = .immediate) {
        self.parseMode = parseMode
    }

    // MARK: - Entry points

    func applyFull(to storage: NSTextStorage, text: String, options: LivePreviewStyler.Options) {
        generation += 1
        constructs = LivePreviewStyler.apply(to: storage, text: text, options: options)
        styledSelections = options.selections
        hasStyled = true
    }

    func applyEdit(
        to storage: NSTextStorage,
        text: String,
        editedRange: NSRange,
        changeInLength: Int,
        options: LivePreviewStyler.Options
    ) {
        guard hasStyled else {
            applyFull(to: storage, text: text, options: options)
            return
        }

        // Slide cached constructs into their post-edit positions so everything below the caret
        // keeps its styling without a reparse.
        let shifted = Self.shift(constructs, afterLocation: editedRange.location, by: changeInLength)

        // An edit moves the caret as well as the text, and reveal state depends on the caret. Both
        // regions need restyling — but as *separate* ranges, since unioning a caret that jumped to
        // the far end of the document with the edit point would restyle everything in between.
        var seeds = [editedRange]
        seeds.append(contentsOf: selectionSeeds(shiftedBy: changeInLength, after: editedRange.location, options: options))

        constructs = shifted
        styledSelections = options.selections

        // Immediate pass using the shifted constructs. Freshly typed syntax is not represented
        // yet; the reconcile below fixes that within a frame or two.
        applySeeds(seeds, to: storage, text: text, constructs: shifted, previous: shifted, options: options)

        scheduleReparse(storage: storage, text: text, options: options)
    }

    func applySelectionChange(
        to storage: NSTextStorage,
        text: String,
        options: LivePreviewStyler.Options
    ) {
        guard hasStyled else {
            applyFull(to: storage, text: text, options: options)
            return
        }
        let seeds = selectionSeeds(shiftedBy: 0, after: 0, options: options)
        guard !seeds.isEmpty else {
            applyFull(to: storage, text: text, options: options)
            return
        }
        applySeeds(seeds, to: storage, text: text, constructs: constructs, previous: constructs, options: options)
        styledSelections = options.selections
    }

    /// Ranges whose reveal state could have changed: everywhere the caret was, and everywhere it
    /// now is. Kept as separate ranges so a caret jumping across the document does not drag the
    /// whole span in between into the restyle.
    private func selectionSeeds(
        shiftedBy delta: Int,
        after location: Int,
        options: LivePreviewStyler.Options
    ) -> [NSRange] {
        let previous = styledSelections.map { range -> NSRange in
            guard delta != 0, range.location >= location else { return range }
            return NSRange(location: max(0, range.location + delta), length: range.length)
        }
        // Reveal is inclusive at both boundaries, so a caret can affect the construct ending
        // exactly at it. Widen by one so the expansion picks that construct up.
        return (previous + options.selections).map {
            NSRange(location: max(0, $0.location - 1), length: $0.length + 2)
        }
    }

    /// Expands each seed independently, merges any that end up overlapping, and styles each.
    private func applySeeds(
        _ seeds: [NSRange],
        to storage: NSTextStorage,
        text: String,
        constructs: [MarkdownRange],
        previous: [MarkdownRange],
        options: LivePreviewStyler.Options
    ) {
        let expanded = seeds
            .map { Self.expandedRange(seed: $0, text: text, previous: previous, next: constructs) }
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in expanded {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        for range in merged {
            LivePreviewStyler.apply(
                to: storage,
                text: text,
                constructs: constructs,
                in: range,
                options: options
            )
        }
    }

    func invalidate() {
        hasStyled = false
        constructs = []
        generation += 1
    }

    // MARK: - Reparse and reconcile

    private func scheduleReparse(
        storage: NSTextStorage,
        text: String,
        options: LivePreviewStyler.Options
    ) {
        generation += 1
        let token = generation

        switch parseMode {
        case .immediate:
            reconcile(storage: storage, text: text, parsed: MarkdownParser.parse(text), token: token, options: options)
        case .background:
            parseQueue.async { [weak self] in
                let parsed = MarkdownParser.parse(text)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.reconcile(
                            storage: storage,
                            text: text,
                            parsed: parsed,
                            token: token,
                            options: options
                        )
                    }
                }
            }
        }
    }

    private func reconcile(
        storage: NSTextStorage,
        text: String,
        parsed: [MarkdownRange],
        token: Int,
        options: LivePreviewStyler.Options
    ) {
        // A newer edit has superseded this parse, or the document moved on beneath it.
        guard token == generation, storage.string == text else { return }

        guard let differing = Self.differingRange(between: constructs, and: parsed) else {
            constructs = parsed
            return
        }
        let range = Self.expandedRange(
            seed: differing,
            text: text,
            previous: constructs,
            next: parsed
        )
        LivePreviewStyler.apply(to: storage, text: text, constructs: parsed, in: range, options: options)
        constructs = parsed
        if parseMode == .background { onReconciled?() }
    }

    /// The span covered by constructs that differ between two lists, or nil when identical.
    ///
    /// Both lists are sorted by start offset, so scanning in from each end finds the changed
    /// window without comparing everything in between.
    static func differingRange(
        between previous: [MarkdownRange],
        and next: [MarkdownRange]
    ) -> NSRange? {
        var head = 0
        let shared = min(previous.count, next.count)
        while head < shared, previous[head] == next[head] { head += 1 }
        if head == shared, previous.count == next.count { return nil }

        var tail = 0
        while tail < shared - head,
              previous[previous.count - 1 - tail] == next[next.count - 1 - tail] {
            tail += 1
        }

        var lower = Int.max
        var upper = 0
        func absorb(_ list: [MarkdownRange], _ index: Int) {
            guard index >= 0, index < list.count else { return }
            lower = min(lower, list[index].from)
            upper = max(upper, list[index].to)
        }
        for index in head..<(previous.count - tail) { absorb(previous, index) }
        for index in head..<(next.count - tail) { absorb(next, index) }

        guard lower <= upper else {
            // Counts differ but every compared element matched; be conservative.
            return NSRange(location: 0, length: Int.max / 2)
        }
        return NSRange(location: lower, length: upper - lower)
    }

    // MARK: - Range arithmetic

    /// Old construct ranges are in pre-edit coordinates; slide the ones past the edit point.
    private static func shift(
        _ ranges: [MarkdownRange],
        afterLocation location: Int,
        by delta: Int
    ) -> [MarkdownRange] {
        guard delta != 0 else { return ranges }
        // Sorted by `from`, so only a suffix needs touching.
        var result = ranges
        var index = lowerBound(ranges, firstFromAtLeast: location)
        while index < result.count {
            let construct = result[index]
            result[index] = MarkdownRange(
                from: max(0, construct.from + delta),
                to: max(0, construct.to + delta),
                kind: construct.kind
            )
            index += 1
        }
        return result
    }

    private static func lowerBound(_ list: [MarkdownRange], firstFromAtLeast location: Int) -> Int {
        var low = 0
        var high = list.count
        while low < high {
            let mid = (low + high) / 2
            if list[mid].from < location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Grows `seed` until it covers whole markdown blocks and wholly contains every construct —
    /// old or new — that it touches.
    ///
    /// Both rules are load-bearing. Without block snapping, `.paragraphStyle` fixups smear a base
    /// style across a widget's forced line height, because AppKit fixes paragraph styles over whole
    /// paragraphs. Without the construct rule, a widget or collapse attribute belonging to a
    /// construct that used to reach into the range is left behind as a stale artifact.
    static func expandedRange(
        seed: NSRange,
        text: String,
        previous: [MarkdownRange],
        next: [MarkdownRange]
    ) -> NSRange {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return full }

        var range = NSIntersectionRange(
            NSRange(location: max(0, seed.location), length: max(0, seed.length)),
            full
        )
        if range.length == 0 {
            range = NSRange(location: min(max(0, seed.location), max(0, full.length - 1)), length: 0)
        }

        // Bounded: each pass can only grow the range, and it is capped by the document.
        for _ in 0..<8 {
            let before = range
            range = blockBounds(ns, containing: range)
            range = union(range, withConstructsTouching: previous)
            range = union(range, withConstructsTouching: next)
            if NSEqualRanges(range, before) { break }
        }
        return NSIntersectionRange(range, full)
    }

    private static func union(_ range: NSRange, withConstructsTouching list: [MarkdownRange]) -> NSRange {
        guard !list.isEmpty else { return range }
        var result = range
        // Sorted by `from`, so start just before the first construct that could reach the range and
        // stop once starts run past its end. Constructs are not strictly nested, so walk back a
        // little to catch a long one starting earlier.
        var index = lowerBound(list, firstFromAtLeast: result.location)
        index = max(0, index - 32)
        while index < list.count {
            let construct = list[index]
            if construct.from > NSMaxRange(result) { break }
            let candidate = NSRange(location: construct.from, length: max(0, construct.to - construct.from))
            // Touching counts, not just overlapping: an adjacent construct still owns attributes
            // at the boundary.
            if candidate.location <= NSMaxRange(result) && NSMaxRange(candidate) >= result.location {
                let grown = NSUnionRange(result, candidate)
                if !NSEqualRanges(grown, result) {
                    result = grown
                    // The range moved; restart so earlier constructs get another look.
                    index = max(0, lowerBound(list, firstFromAtLeast: result.location) - 32)
                    continue
                }
            }
            index += 1
        }
        return result
    }

    /// Expands to the surrounding blank-line-delimited blocks, which is the granularity markdown
    /// block structure actually changes at.
    private static func blockBounds(_ ns: NSString, containing range: NSRange) -> NSRange {
        guard ns.length > 0 else { return range }
        let startProbe = min(max(0, range.location), ns.length - 1)
        let endProbe = min(max(0, NSMaxRange(range)), ns.length - 1)

        var start = ns.lineRange(for: NSRange(location: startProbe, length: 0)).location
        var end = NSMaxRange(ns.lineRange(for: NSRange(location: endProbe, length: 0)))

        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            let blank = ns.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            start = previous.location
            if blank { break }
        }
        while end < ns.length {
            let following = ns.lineRange(for: NSRange(location: end, length: 0))
            let blank = ns.substring(with: following).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            end = NSMaxRange(following)
            if blank { break }
        }
        return NSRange(location: start, length: max(0, end - start))
    }
}
