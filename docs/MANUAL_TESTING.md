# Manual testing checklist

The automated suite (`xcodebuild … test`) covers parsing, hide/reveal, and
export output. This checklist covers what automation can't reach: native
menus, dialogs, printing, and feel. Run it in the built app
(`open Minidown/Minidown.xcodeproj` → Run, or an archived build) before
tagging a release.

## Files

- [ ] ⌘N clears to an Untitled document; with unsaved text it asks before discarding
- [ ] ⌘O opens a `.md` file; title bar and status bar show the filename
- [ ] ⌘S on Untitled opens Save dialog; afterwards the title shows the name
- [ ] Type after saving: status shows "— Edited", then autosaves within ~1s
  and the "Edited" marker clears
- [ ] ⇧⌘S (Save As) writes a copy and switches to it
- [ ] Reopen a saved file: content is byte-identical (no reformatting) —
  spot-check with `git diff` or `diff` against a copy
- [ ] Quit and relaunch: theme, focus, typewriter, and stats-mode choices persist

## Live preview

Open `examples/01-basics.md`:
- [ ] Cursor outside constructs → no `#`, `**`, `` ` ``, `>`, or link syntax visible
- [ ] Click into a bold word → only its `**` marks reveal, dimmed
- [ ] Arrow through a heading line → `# ` appears on entry, hides on exit
- [ ] Click a task checkbox → toggles; reopen file to confirm `[x]` was written
- [ ] Ordered list numbers stay visible; bullet markers soften when inactive

Open `examples/03-tables-images.md`:
- [ ] Table rows style as monospace grid; alignment markers parse correctly
- [ ] Click inside a table → raw pipe syntax remains editable
- [ ] Remote image loads when reachable; local `gradient.png` resolves when
  the file is opened from disk

Open `examples/04-torture-test.md`:
- [ ] Everything renders per its italic annotations; nothing crashes,
  nothing is silently eaten

Open `examples/06-extended.md`:
- [ ] Frontmatter is quiet metadata; inline + block math style distinctly;
  `$5 and $10` stay dollars; footnote refs are superscript
- [ ] Mermaid fence is recognizable; HTML/PDF export renders the diagram
- [ ] Switch appearance (View → Appearance) → editor palette flips

## Menus & shortcuts

- [ ] File / Edit / View menus present with expected items
- [ ] Edit → Undo/Redo work on typing
- [ ] Cut/Copy/Paste/Select All work via menu and keys
- [ ] View → Focus Mode and Typewriter Scrolling track state, including when
  toggled via ⌘D / ⌥⌘T or the status bar buttons
- [ ] Appearance submenu: System / Light / Dark switches the window

## Focus & typewriter

- [ ] ⌘D dims all but the current paragraph; moving the cursor re-lights
  the paragraph under it
- [ ] ⌥⌘T: typing keeps the caret line vertically centered; mouse clicks
  and arrow keys do NOT recenter

## Export

- [ ] ⌘P opens the print panel (Save as PDF available)
- [ ] ⇧⌘E writes a standalone HTML file and opens it
- [ ] File → Export → Word / RTF / Plain Text produce files via `textutil`
