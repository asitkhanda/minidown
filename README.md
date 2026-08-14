# minidown

**A minimal, distraction-free Markdown writer for macOS.**

minidown gives you a Typora-style live preview — syntax renders in place and
hides when your cursor leaves it — while your file stays plain Markdown,
byte for byte. No lock-in, no reformatting your source, no feature bloat.

> One window, your text, nothing else.

## Why minidown

Most Markdown editors make you choose: see your prose (split preview, WYSIWYG
lock-in) or see your source (raw syntax everywhere). minidown does neither:

- **The screen shows the writing, not the wiring.** `**bold**` renders bold;
  put the cursor inside and the `**` marks reappear, dimmed and editable.
- **Your Markdown stays yours.** Rendering is presentation-only — minidown
  never rewrites, normalizes, or reformats the text you typed. What you save
  is exactly what you wrote.
- **Genuinely native.** A SwiftUI + AppKit app on macOS — fast startup, one
  window, a whisper-quiet status bar.

## Features

### Live preview
- Headings, bold, italic, strikethrough, inline code, links, and blockquotes
  render in place; their marks reveal when the cursor touches them
- Bullets and task lists; clicking a task checkbox writes `[x]` / `[ ]` back
  into the file
- Code fences render as monospace blocks with Splash highlighting; Mermaid
  fences render as diagrams when the caret is outside
- Tables render as a real grid when the caret is outside; click in to edit
  pipe syntax
- Images render inline (remote URLs and paths relative to the open file)
- Math (`$…$` / `$$…$$`) renders via KaTeX snapshots when the caret is outside

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
- **Appearance** — system, light, or dark (View → Appearance)
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

## Install

**Build from source:** requires macOS 14+, Xcode 15+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone <this-repo>
cd minidown/Minidown
xcodegen generate
open Minidown.xcodeproj
```

Or from the command line:

```sh
cd Minidown
xcodegen generate
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
