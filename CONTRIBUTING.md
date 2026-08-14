# Contributing to minidown

Thanks for your interest! minidown is deliberately small — the bar for new
features is *"does a writer need this while writing?"* — but bug fixes,
polish, and performance work are always welcome.

## Setup

Requires [Node.js](https://nodejs.org) ≥ 20 and [Rust](https://rustup.rs)
(stable). macOS is the primary target.

```sh
npm install
npm run tauri dev   # runs the app with hot reload
```

The frontend also runs in a plain browser (`npm run dev`) — file dialogs
and export are disabled there, but it's the fastest loop for editor work.

## Before you open a PR

1. `npm test` — the suite must pass. **Add a test with every feature or
   bug fix**; the project has a hard rule that previously working syntax
   and behavior must never silently break.
2. `npx tsc --noEmit` — no type errors.
3. For anything touching the native shell (menus, dialogs, print), run the
   relevant sections of [`docs/MANUAL_TESTING.md`](docs/MANUAL_TESTING.md).

## Architecture in one minute

- `src/editorSetup.ts` — the CodeMirror extension stack (shared with tests)
- `src/livePreview.ts` — all rendering, as decorations. Inline hide/reveal
  lives in a ViewPlugin; block widgets (tables, block math, mermaid) must
  live in the StateField (CodeMirror forbids block decorations from plugins)
- `src/markdownExtensions.ts` — Lezer parser extensions (frontmatter,
  footnotes, math)
- `src/export.ts` — markdown-it export pipeline (export only; the editor
  itself never round-trips through it)
- `src-tauri/` — Rust shell; keep it thin

Two invariants to preserve:

1. **Round-trip fidelity.** Rendering must never modify document text.
   Decorations only. The single exception is an explicit user action
   (e.g. clicking a task checkbox).
2. **Reveal correctness.** Any construct whose syntax hides must reveal it
   when the selection touches it.

## License

By contributing you agree your work is licensed under
[AGPL-3.0](LICENSE).
