# minidown

**A minimal, distraction-free Markdown writer for macOS.**

minidown gives you a Typora-style live preview — syntax renders in place and
hides when your cursor leaves it — while your file stays plain Markdown,
byte for byte. No lock-in, no reformatting your source, no feature bloat.

> Your text, nothing else.

## Why minidown

Most Markdown editors make you choose: see your prose (split preview, WYSIWYG
lock-in) or see your source (raw syntax everywhere). minidown does neither:

- **The screen shows the writing, not the wiring.** `**bold**` renders bold;
  put the cursor inside and the `**` marks reappear, dimmed and editable.
- **Your Markdown stays yours.** Rendering is presentation-only — minidown
  never rewrites, normalizes, or reformats the text you typed. What you save
  is exactly what you wrote.
- **Genuinely native.** A SwiftUI + AppKit document app on macOS — fast startup,
  Finder integration, and a whisper-quiet status bar.

## Features

### Live preview
- Headings, bold, italic, strikethrough, inline code, links, and blockquotes
  render in place; their marks reveal when the cursor touches them
- Bullets and GFM task lists (`- [ ]`); clicking a checkbox writes `[x]` / `[ ]`
  back into the file
- Code fences render as monospace blocks, highlighted per language via
  tree-sitter (js, ts, python, rust, css, json, html, shell) and Splash for
  Swift; Mermaid fences render as diagrams when the caret is outside
- Tables render as a real grid when the caret is outside; click in to edit
  pipe syntax
- Images render inline (remote URLs and paths relative to the open file)
- Math (`$…$` / `$$…$$`) renders via KaTeX when the caret is outside — inline
  math sits on the text baseline, display math takes its own line. KaTeX and
  Mermaid are bundled, so rendering works offline

### Full syntax
CommonMark + GFM, plus:
- **YAML frontmatter** (`---` block at the top, styled as quiet metadata)
- **Footnotes** — `[^ref]` renders superscript
- **Math** — `$inline$` and `$$block$$` (Pandoc dollar rules so `$5 and $10`
  stay dollars); export renders via KaTeX
- **Mermaid diagrams** — ` ```mermaid ` fences; export/lazy WebKit rendering

### Writing environment
- **Focus mode** (⌘D) — dims everything but the paragraph you're writing
- **Typewriter scrolling** (⌥⌘T) — your line stays vertically centered while
  you type; clicks and arrow keys never jump the view
- **Liquid Glass by default** on macOS 26+ — the window, status bar and controls
  use native Liquid Glass, in both light and dark. Older systems fall back to a
  vibrant material automatically (View → Window)
- **Colour themes** — minidown, Solarized, Nord, Dracula, Gruvbox and One.
  Each ships the project's own light *and* dark palette, so a theme follows your
  appearance rather than overriding it (View → Theme)
- **Appearance** — system, light or dark, independent of the theme and the
  window material (View → Appearance)
- **Editor font** — **DM Sans**, **Spectral** and **Fira Code**, all bundled.
  Code always sets in Fira Code, ligatures and all, whatever the prose font is
  (View → Font)
- **Status bar** — filename and save state; Focus/Typewriter toggles; stats
  that cycle words → characters → reading time
- Native macOS menu bar; autosave once a file has a name

### Export
| Format | How | Notes |
| ------ | --- | ----- |
| PDF | ⌘P | WebKit print pipeline |
| HTML | ⇧⌘E | Single styled file; KaTeX/mermaid CDN links only when used |
| Word (.docx) | File → Export | via macOS `textutil` |
| Rich Text (.rtf) | File → Export | via macOS `textutil` |
| Plain text | File → Export | via macOS `textutil` |

## Keyboard shortcuts

| Action               | Keys |
| -------------------- | ---- |
| New                  | ⌘N   |
| Open                 | ⌘O   |
| Save                 | ⌘S   |
| Save As              | ⇧⌘S  |
| Export as PDF        | ⌘P   |
| Export as HTML       | ⇧⌘E  |
| Focus mode           | ⌘D   |
| Typewriter scrolling | ⌥⌘T  |

### Fonts

All three faces ship with the app under the SIL Open Font License, with their
licence files alongside them:

| Face | Font | |
| --- | --- | --- |
| Sans Serif | [DM Sans](https://fonts.google.com/specimen/DM+Sans) | Colophon Foundry / Google |
| Serif | [Spectral](https://fonts.google.com/specimen/Spectral) | Production Type |
| Typewriter & code | [Fira Code](https://github.com/tonsky/FiraCode) | Mozilla, with ligatures |

## Install

```bash
brew tap asitkhanda/minidown
brew install --cask minidown
```

Update with `brew upgrade --cask minidown`.

> **First launch.** Builds are not notarized yet, so macOS will ask you to confirm the app once:
> **System Settings → Privacy & Security → Open Anyway**. See
> [docs/RELEASING.md](docs/RELEASING.md) for why, and what it takes to remove that step.

**Build from source:** requires macOS 14+, Xcode 16+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd Minidown
xcodegen generate
open Minidown.xcodeproj
```

Or from the command line:

```sh
xcodebuild -scheme Minidown -destination 'platform=macOS' build
```

## Try it

Open any file from [`examples/`](examples/) (⌘O) — a guided tour of the
basics, a code-language showcase, tables and images, a syntax torture test,
extended syntax (math, diagrams, footnotes), and a prose sample for judging
the writing feel.

## Architecture

- **App shell** — SwiftUI (`Minidown/Minidown/`): window, menus, status bar,
  document state
- **Editor** — AppKit `NSTextView` + custom `CollapsingLayoutManager` that
  zero-widths inactive markdown marks (same idea as CodeMirror replace
  decorations)
- **Parsing** — [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (cmark-gfm) for the document AST; supplemental rules for frontmatter,
  footnotes, and TeX math
- **Code fences** — [Splash](https://github.com/JohnSundell/Splash) token colors
- **Export** — HTML/PDF pipeline plus macOS `textutil` for Word/RTF/plain text

Rendering never rewrites the file. The only text mutations are explicit user
actions (e.g. clicking a task checkbox).

## Testing

```sh
cd Minidown
xcodegen generate
xcodebuild -scheme Minidown -destination 'platform=macOS' test
```

Native-shell behavior that automation can't reach (menus, dialogs, print,
scrolling feel) is covered by the manual checklist in
[`docs/MANUAL_TESTING.md`](docs/MANUAL_TESTING.md) — run it before releases.

## Known limitations

- KaTeX / Mermaid in the editor are WKWebView snapshots (async); first paint may
  show a short placeholder until the CDN render completes. Export still embeds
  live KaTeX/Mermaid scripts.
- Table cell contents in the widget are plain text (no nested bold/code), matching
  the previous app's grid limitation
- Code signing / notarization not set up yet

## License

[AGPL-3.0](LICENSE) — free forever; forks and derivatives must stay open.
