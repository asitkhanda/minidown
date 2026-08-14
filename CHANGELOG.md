# Changelog

## 0.1.0 — 2026-08-15

Initial release.

- Typora-style live preview on CodeMirror 6: syntax renders in place and
  hides when the cursor leaves it; the file stays plain Markdown
- CommonMark + GFM: headings, emphasis, links, quotes, lists, task lists
  (clickable checkboxes), tables (rendered grids with click-to-edit),
  code fences with per-language highlighting, inline images
- Extended syntax: YAML frontmatter, footnotes, KaTeX math
  (`$…$` / `$$…$$`), Mermaid diagrams
- Focus mode (⌘D), typewriter scrolling (⌥⌘T), system/light/dark appearance
- Native macOS menu bar, autosave, persistent view settings
- Status bar: mode toggles, export popover, cycling stats
  (words / characters / reading time)
- Export: PDF (native print pipeline), styled standalone HTML,
  Word (.docx), RTF, plain text
- Regression test suite (vitest) and manual QA checklist
