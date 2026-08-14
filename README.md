# minidown

A minimal, distraction-free Markdown writer for macOS.

Typora-style live preview: syntax renders in place and hides when your cursor
leaves it — while the file stays plain Markdown, byte for byte. No lock-in,
no rewriting your files, no feature bloat.

## Features

- **Live preview** — headings, emphasis, links, quotes, and lists render as
  you write; marks reappear, dimmed, when the cursor touches them
- **Full syntax** — CommonMark + GFM (tables, task lists, strikethrough),
  plus footnotes, YAML frontmatter, KaTeX math, and Mermaid diagrams
- **Rendered blocks** — highlighted code fences, inline images, real table
  grids, clickable task checkboxes; click any of them to edit the raw text
- **Distraction-free** — focus mode dims all but the current paragraph;
  typewriter scrolling keeps your line vertically centered; light/dark/system
  appearance
- **Mac-native** — menu bar, ⌘-shortcuts, autosave, ~10 MB app (Tauri, not
  Electron)
- **Export** — standalone styled HTML (print that to PDF from any browser)

## Shortcuts

| Action               | Keys |
| -------------------- | ---- |
| New                  | ⌘N   |
| Open                 | ⌘O   |
| Save                 | ⌘S   |
| Save As              | ⇧⌘S  |
| Export as HTML       | ⇧⌘E  |
| Focus mode           | ⌘D   |
| Typewriter scrolling | ⌥⌘T  |

Files autosave once they have a name.

## Development

Requires [Node.js](https://nodejs.org) and [Rust](https://rustup.rs).

```sh
npm install
npm run tauri dev    # run the app
npm test             # regression suite
npm run tauri build  # release .app/.dmg
```

The editor core is CodeMirror 6; the live preview is decoration-based
(see `src/livePreview.ts`), so the document text is never modified by
rendering. Custom syntax (frontmatter, footnotes, math) lives in
`src/markdownExtensions.ts`. Example documents to try are in `examples/`.

## License

[AGPL-3.0](LICENSE)
