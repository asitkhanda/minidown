# minidown

A minimal, distraction-free Markdown writer for macOS.

**Status: early development.** The goal is a Typora-style live-preview editor — syntax renders in place and hides when your cursor leaves it — while the document stays plain Markdown at all times. No lock-in, no rewriting your files, no feature bloat.

## Principles

- **Distraction-free.** One window, your text, nothing else.
- **Your Markdown stays yours.** Perfect round-trip fidelity — minidown never reformats or normalizes your source.
- **Full syntax.** CommonMark + GFM first; footnotes, frontmatter, math, and Mermaid to follow.
- **Genuinely minimal.** Small binary (Tauri, not Electron), fast startup, low memory.

## Development

Requires [Node.js](https://nodejs.org) and [Rust](https://rustup.rs).

```sh
npm install
npm run tauri dev
```

## Shortcuts

| Action  | Keys |
| ------- | ---- |
| New     | ⌘N   |
| Open    | ⌘O   |
| Save    | ⌘S   |
| Save As | ⇧⌘S  |

Files autosave once they have a name.

## License

[AGPL-3.0](LICENSE)
