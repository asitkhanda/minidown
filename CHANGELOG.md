# Changelog

## 0.3.0 — unreleased

Correctness, performance and parity pass over the native rewrite. The 0.2.0
port had drifted a long way from what the README describes; this closes the gap.

### Editor

- Hiding markdown syntax is now a glyph property rather than a transparent colour, so no
  later styling pass can resurrect it. Focus mode used to do exactly that, painting raw
  pipe and image syntax underneath the widgets drawn on top of it
- Focus dimming moved to draw time; a caret move no longer restyles the document
- Reveal is multi-cursor aware again; ⌘A no longer un-renders every table, image and diagram
- Typing on a 20k-word document went from ~243ms to ~9ms per keystroke: the parse moved off
  the main thread and restyling is narrowed to what actually changed
- IME composition (CJK, dead keys) is no longer interrupted by restyling
- Regex-driven syntax no longer fires inside code: `cd $dir/$file` in a shell fence is not
  math, `[^0-9]` is not a footnote reference, and `- [ ] item` in a fence is not a checkbox
- Bare `[ ]` / `[x]` checkboxes without a list marker are **no longer** treated as tasks.
  They were a minidown-only extension and rendered as literal brackets everywhere else;
  GFM `- [ ]` is required
- Nested list items indented four or more spaces now hide their bullet marker
- Bare URLs autolink; setext heading underlines hide with their own line
- A document opening with a `---` thematic break is no longer swallowed as frontmatter
- Table structure comes from the parser instead of being re-split from the raw pipe text

### Rendering

- Tables render as a real grid again — borders, padding, header fill and column
  alignment. The previous renderer drew cell text with no grid at all, because
  `NSAttributedString.draw` cannot lay out `NSTextTable`
- Inline math sits on the text baseline inside the sentence instead of inflating
  its whole paragraph, and no longer renders at viewport size
- Mermaid diagrams render with correct labels, arrowheads and bounds
- KaTeX and Mermaid are **bundled**, so math and diagrams render offline
- Widget bitmaps are cached with a size limit and one shared key builder; the
  editor used to re-render every table on every draw and never evict anything
- Tall images no longer vanish when their first line scrolls off screen
- Replaced a private-API call (`WKWebView.drawsBackground` via KVC)

### Themes

- Six colour themes covering the whole editor — prose, headings, links, quotes,
  code and every syntax token: **minidown**, **Solarized**, **Nord**,
  **Dracula**, **Gruvbox** and **One**
- Each theme carries the upstream project's own light *and* dark palette
  (Solarized Light/Dark, Nord's Snow Storm and Polar Night, Dracula's Alucard,
  Gruvbox light/dark, One Light/Dark), so choosing a theme never overrides your
  Light/Dark/System appearance
- Palettes are `Codable`, so user-supplied themes can be loaded later without
  reworking the model
- Every built-in palette is contrast-checked by tests, in both appearances

### Typography

- **DM Sans** (sans serif), **Spectral** (serif) and **Fira Code** (typewriter),
  all bundled under the SIL Open Font License with their licence files
- **All code — fenced blocks and inline — sets in Fira Code**, with its
  programming ligatures, regardless of the prose font
- Spectral stands in for Sentient, which was the original choice for the serif:
  the Fontshare licence permits free use but forbids redistributing the files,
  which shipping them in this repository would be. Spectral is a redistributable
  serif built for long-form reading
- Weights resolve through font descriptors, so DM Sans — which ships only as a
  variable font — renders real semibold headings rather than faux-bolding Regular

### Code highlighting

- Fenced code is highlighted per language with tree-sitter: JavaScript,
  TypeScript, Python, Rust, CSS, JSON, HTML and shell, plus Splash for Swift.
  Every fence used to be tokenised as Swift regardless of its language tag
- Extension aliases work again (` ```py `, ` ```rs `)

### Export

- Rewritten on swift-markdown's `HTMLFormatter`. Lists, tables, task lists,
  images, rules, setext headings, multi-line blockquotes and nested emphasis
  were **all silently dropped** by the previous line-based renderer, which also
  split hard-wrapped paragraphs into one `<p>` per source line
- Word, RTF and plain text convert natively instead of shelling out to
  `textutil`, which cannot run inside a sandbox
- PDF uses WebKit's own paginating print operation and waits for content to
  settle, rather than `NSPrintOperation(view:)` after a fixed 0.8s sleep

### App

- Real document architecture: `.md` files open from Finder, several documents
  can be open at once, and unsaved-changes prompts, autosave-in-place, Recents,
  Duplicate and Revert To come from the framework. Opening a file used to
  silently discard unsaved work
- Sandboxed
- App icon restored — the rewrite deleted the icon set and never replaced it
- Phosphor icons for task checkboxes
- **Liquid Glass is the default** on macOS 26+, using the native APIs —
  `NSGlassEffectView` for the window surface, `glassEffect` and `.glass` button
  styles for the status bar and its controls. Below macOS 26 the chrome falls
  back to a vibrant material, and the preference is kept rather than rewritten,
  so it takes effect after an OS upgrade
- Appearance and window material are now separate settings. They used to be one,
  which meant "Liquid Glass" *was* an appearance — it could not be combined with
  an explicit light or dark mode, and choosing it silently meant "System".
  Liquid Glass now has proper light and dark variants
- Switching between Liquid Glass and Solid changes only the material — layout and
  sizing are identical. They were not: the glass and plain button styles have
  different metrics, so the status bar changed height with the window style and
  the editor moved with it
- The writing surface is tinted over the glass. Untinted, whatever sits behind
  the window shows through the prose; Liquid Glass is designed for the interface
  layer above content, not for the content itself
- Menus use real checkmarks instead of a `"✓"` baked into the title, and there
  is one View menu instead of two
- Window minimum size (480×320) restored

### Distribution

- Releases are tag-driven: pushing a `v*` tag builds, tests, publishes a GitHub
  Release and bumps a Homebrew cask, so updates arrive via `brew upgrade` rather
  than a manual download-and-reinstall. Pushing to `main` ships nothing
- CI and release builds moved to macOS 26 runners. Liquid Glass needs the
  macOS 26 SDK to compile, so the older runner image could not have built this
  release at all
- `CURRENT_PROJECT_VERSION` is derived from the tag instead of being hardcoded
  to `1`. It feeds `CFBundleVersion`, and a `CFBundleVersion` that does not
  increase is an update Sparkle silently never offers
- Source files carry `SPDX-License-Identifier: AGPL-3.0-or-later` headers

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
