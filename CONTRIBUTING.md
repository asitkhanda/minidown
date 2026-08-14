# Contributing to minidown

Thanks for your interest! minidown is deliberately small — the bar for new
features is *"does a writer need this while writing?"* — but bug fixes,
polish, and performance work are always welcome.

## Setup

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

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
- `Minidown/Minidown/LivePreviewStyler.swift` — presentation-only styling
- `Minidown/Minidown/MarkdownParser.swift` — construct ranges (frontmatter,
  footnotes, math, fences, …)
- `Minidown/Minidown/Exporter.swift` — export only; the editor never
  round-trips through it
- `Minidown/project.yml` — XcodeGen project definition

Two invariants to preserve:

1. **Round-trip fidelity.** Rendering must never modify document text.
   Presentation only. The single exception is an explicit user action
   (e.g. clicking a task checkbox).
2. **Reveal correctness.** Any construct whose syntax hides must reveal it
   when the selection touches it.

## License

By contributing you agree your work is licensed under
[AGPL-3.0](LICENSE).
