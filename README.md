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
- **Genuinely minimal.** A ~14 MB native app (Tauri + WebKit, not Electron),
  fast startup, one window, a whisper-quiet status bar.

## Features

### Live preview
- Headings, bold, italic, strikethrough, inline code, links, and blockquotes
  render in place; their marks reveal when the cursor touches them
- Bullets render as `•`, task lists as real clickable checkboxes (clicking
  writes `[x]` back into the file), `---` as a horizontal rule
- Code fences render as blocks with per-language syntax highlighting
  (` ```py ` and ` ```rust ` extension aliases work too)
- Images render inline — remote URLs and paths relative to the open file
- Tables render as real grids with column alignment; click to edit the raw
  pipe syntax, click away to re-render

### Full syntax
CommonMark + GFM, plus:
- **YAML frontmatter** (`---` block at the top, styled as quiet metadata)
- **Footnotes** — `[^ref]` renders superscript
- **Math** — `$inline$` and `$$block$$` TeX rendered by KaTeX
  (`$5 and $10` stay dollars)
- **Mermaid diagrams** — ` ```mermaid ` fences render as diagrams,
  lazy-loaded so documents without diagrams pay nothing

### Writing environment
- **Focus mode** (⌘D) — dims everything but the paragraph you're writing
- **Typewriter scrolling** (⌥⌘T) — your line stays vertically centered while
  you type; clicks and arrow keys never jump the view
- **Appearance** — system, light, or dark (View → Appearance)
- **Status bar** — filename and save state; clickable Focus/Typewriter
  toggles; stats that cycle words → characters → reading time
- Native macOS menu bar; autosave once a file has a name

### Export
| Format | How | Notes |
| ------ | --- | ----- |
| PDF | ⌘P | WebKit print pipeline — math and diagrams render fully, offline |
| HTML | ⇧⌘E | Single styled file; KaTeX/mermaid CDN links added only when used |
| Word (.docx) | File → Export | via macOS `textutil`; math/diagrams degrade to text |
| Rich Text (.rtf) | File → Export | via macOS `textutil` |
| Plain text | File → Export | rendered text without markup |

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

**Download:** grab the `.dmg` from the Releases page (unsigned for now — on
first open, right-click the app → Open).

**Build from source:** requires [Node.js](https://nodejs.org) ≥ 20 and
[Rust](https://rustup.rs) (stable).

```sh
git clone <this-repo>
cd minidown
npm install
npm run tauri dev      # development app
npm run tauri build    # release .app + .dmg in src-tauri/target/release/bundle/
```

## Try it

Open any file from [`examples/`](examples/) (⌘O) — a guided tour of the
basics, a code-language showcase, tables and images, a syntax torture test,
extended syntax (math, diagrams, footnotes), and a prose sample for judging
the writing feel.

## Architecture

- **Shell** — [Tauri 2](https://tauri.app) (`src-tauri/`): window, native
  menu ([`src/menu.ts`](src/menu.ts)), file dialogs, a single Rust command
  for `textutil` conversion
- **Editor** — [CodeMirror 6](https://codemirror.net):
  [`src/editorSetup.ts`](src/editorSetup.ts) is the full extension stack,
  shared by the app and the tests
- **Live preview** — [`src/livePreview.ts`](src/livePreview.ts): decorations
  built from the Lezer syntax tree. Inline marks hide/reveal in a ViewPlugin;
  block widgets (tables, block math, mermaid) live in a StateField. The
  document text is never modified by rendering
- **Custom syntax** —
  [`src/markdownExtensions.ts`](src/markdownExtensions.ts): Lezer parser
  extensions for frontmatter, footnotes, and TeX math
- **Export** — [`src/export.ts`](src/export.ts): a markdown-it pipeline
  (used only for export; the editor never round-trips through it)

## Testing

```sh
npm test
```

The vitest suite (`src/editor.test.ts`) covers highlighter wiring, parsing
of the full syntax set, hide/reveal decoration behavior, block-widget
replacement, focus/typewriter state, export output, and decorates every
example document at multiple cursor positions as a crash test.

Native-shell behavior that automation can't reach (menus, dialogs, print,
scrolling feel) is covered by the manual checklist in
[`docs/MANUAL_TESTING.md`](docs/MANUAL_TESTING.md) — run it before releases.

## Known limitations

- Table cells render their contents as plain text in the grid (formatting
  inside cells shows raw); in-cell editing is planned
- Math and diagrams degrade to text in Word/RTF export (faithful conversion
  would require Pandoc)
- An unclosed frontmatter fence at the top of a new file temporarily styles
  the document as metadata until the closing `---` is typed
- Unsigned builds until code signing is set up

## License

[AGPL-3.0](LICENSE) — free forever; forks and derivatives must stay open.
