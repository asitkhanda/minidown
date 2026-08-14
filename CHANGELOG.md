# Changelog

## 0.2.0 — 2026-08-15

Native Swift rewrite. Replaces the Tauri + CodeMirror stack with a macOS
SwiftUI + AppKit app. Same product goals: Typora-style live preview, byte-
faithful Markdown, focus/typewriter, and multi-format export.

- SwiftUI shell with AppKit `NSTextView` editor
- Live preview via presentation-only attributed styling
- Focus mode, typewriter scrolling, appearance, status bar stats
- Status bar font picker: Sans Serif, Serif, Typewriter
- Theme options including Liquid Glass chrome (macOS 26+)
- Extended syntax: frontmatter, footnotes, math, Mermaid (export/lazy WebKit)
- Export: PDF, HTML, Word, RTF, plain text (`textutil`)
- XCTest suite + XcodeGen project; CI on `xcodebuild`
- Fix live-preview syntax collapse (null glyphs during typesetting, not
  post-layout `setNotShownAttribute`)
- Fix GFM task lists: hide `- `, draw/click checkboxes, write `[x]`/`[ ]`
- Also accept bare line-start `[ ]` / `[x]` / `[X]` (no list marker)
- Fix inline code: style content only so collapsed backticks don't leave a
  full-width gray band
- Fix unclosed leading `---` no longer swallowing the whole file as frontmatter
- Fix bare task checkboxes drawing on the wrong line (null glyphs jumped to
  the previous fragment and painted over headings); markers now keep width
- Live-preview block widgets (CodeMirror replace parity): tables, images,
  KaTeX math, Mermaid diagrams, and HR rules when the caret is outside

## 0.1.0 — 2026-08-15

Initial release (Tauri + CodeMirror). Superseded by 0.2.0.
