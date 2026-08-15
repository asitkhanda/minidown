# Contributing to minidown

Thanks for your interest! minidown is deliberately small — the bar for new
features is *"does a writer need this while writing?"* — but bug fixes,
polish, and performance work are always welcome.

## Setup

Requires **Xcode 26+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The
macOS 26 SDK is needed to compile the Liquid Glass chrome — the
`#available(macOS 26.0, *)` guards are runtime checks and will not make
`NSGlassEffectView` resolve against an older SDK. The app itself still targets
macOS 14+.

```sh
cd Minidown
xcodegen generate
open Minidown.xcodeproj
```

## Before you open a PR

1. `xcodebuild -scheme Minidown -destination 'platform=macOS' test` — the
   suite must pass. **Add a test with every feature or bug fix**; previously
   working syntax and behavior must never silently break.
2. For anything touching the native shell (menus, dialogs, print), run the
   relevant sections of [`docs/MANUAL_TESTING.md`](docs/MANUAL_TESTING.md).

## Architecture in one minute

- `Minidown/Minidown/MarkdownEditorView.swift` — `NSTextView` bridge
- `Minidown/Minidown/LivePreviewSession.swift` — narrows restyling to what
  changed, and keeps the parse off the main thread
- `Minidown/Minidown/LivePreviewStyler.swift` — presentation-only styling
- `Minidown/Minidown/RevealPolicy.swift` — the hide/reveal rules, in one place
- `Minidown/Minidown/CollapsingLayoutManager.swift` — glyph suppression, focus
  dimming, and widget painting
- `Minidown/Minidown/MarkdownParser.swift` — construct ranges (frontmatter,
  footnotes, math, fences, …)
- `Minidown/Minidown/HTMLExport.swift` — Markdown → HTML for export only; the
  editor never round-trips through it
- `Minidown/project.yml` — XcodeGen project definition. It owns `Info.plist`
  and the entitlements file, so edit those *here*, not in the generated files.

Three invariants to preserve:

1. **Round-trip fidelity.** Rendering must never modify document text.
   Presentation only. The single exception is an explicit user action
   (e.g. clicking a task checkbox).
2. **Inline reveal.** Inline marks — `**`, `` ` ``, `#`, `>`, link syntax —
   reveal whenever *any* selection range touches them, counting a caret resting
   on either boundary. Multi-cursor included.
3. **Block reveal.** Block constructs — tables, images, math, diagrams, rules —
   reveal when the selection is *editing inside* them: a caret touching them, or
   a selection with an endpoint within. A selection that merely spans a block
   leaves its widget rendered, so ⌘A does not turn the document back into raw
   source.

Two things worth knowing before you touch the editor:

- **Hiding is a glyph property, never a colour.** `.mdCollapse` gives a glyph
  zero width; `.mdHidden` keeps its width but never paints it. Hiding with a
  transparent `.foregroundColor` is what let focus mode resurrect raw syntax
  underneath the widgets drawn on top of it.
- **Focus dimming happens at draw time**, in the layout manager, not as
  attributes. That keeps a caret move from costing a restyle, and keeps it
  reversible.

## Releases

Merging to `main` ships nothing. Releases are tag-driven — see
[`docs/RELEASING.md`](docs/RELEASING.md).

## License

By contributing you agree your work is licensed under
[AGPL-3.0-or-later](LICENSE). Source files carry an SPDX header; new files should
too.
