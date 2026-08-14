# Manual testing checklist

The automated suite (`npm test`) covers parsing, decorations, and export
output. This checklist covers what automation can't reach: native menus,
dialogs, printing, and feel. Run it in the built app (`npm run tauri dev`
or the release build) before tagging a release.

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
- [ ] Ordered list numbers stay visible; bullets render as •

Open `examples/03-tables-images.md`:
- [ ] Table renders as a grid with left/center/right alignment
- [ ] Click inside → raw monospace pipes; click away → grid again
- [ ] Remote image loads; local `gradient.png` renders (file must be open
  from disk, not pasted)

Open `examples/04-torture-test.md`:
- [ ] Everything renders per its italic annotations; nothing crashes,
  nothing is silently eaten

Open `examples/06-extended.md`:
- [ ] Frontmatter is quiet metadata; inline + block math render;
  `$5 and $10` stay dollars; footnote refs are superscript
- [ ] Mermaid diagram renders; click it → raw source; click away → diagram
- [ ] Switch appearance (View → Appearance) → diagram theme matches on
  next render, editor palette flips immediately

## Menus & shortcuts

- [ ] All five menus present: minidown, File, Edit, View, Window
- [ ] Edit → Undo/Redo work on typing (CodeMirror history, not stale native)
- [ ] Cut/Copy/Paste/Select All work via menu and keys
- [ ] View → Focus Mode and Typewriter Scrolling checkmarks track state,
  including when toggled via ⌘D / ⌥⌘T or the status bar buttons
- [ ] Appearance submenu: exactly one of System/Light/Dark checked

## Focus & typewriter

- [ ] ⌘D dims all but the current paragraph; moving the cursor re-lights
  the paragraph under it with a soft transition
- [ ] ⌥⌘T: typing keeps the caret line vertically centered; mouse clicks
  and arrow keys do NOT recenter
- [ ] Status bar buttons show accent color exactly when the mode is on

## Status bar

- [ ] Click stats: words → characters → reading time → words; choice persists
- [ ] Export button opens the popover; clicking elsewhere closes it

## Export

Use a document containing a table, code fence, math, a mermaid diagram,
and a footnote (e.g. `examples/06-extended.md`):
- [ ] ⌘P opens the macOS print dialog showing the *rendered* document
  (no editor chrome); PDF via the dialog's Save as PDF looks right,
  including math and the diagram
- [ ] ⇧⌘E saves an `.html` file and opens it in the browser; content and
  styling correct in light and dark system modes
- [ ] Word export opens in Pages/Word: headings, bold, lists, tables
  intact (math/diagrams are expected to degrade to text)
- [ ] RTF and Plain Text exports open and read correctly
- [ ] Export a document with *no* math/diagrams as HTML → file references
  no CDN assets (fully standalone)

## Window

- [ ] Traffic lights overlay the canvas; the top strip drags the window
- [ ] Window size below 480×320 is prevented
- [ ] ⌘W closes the window and quits cleanly (autosaved work intact on relaunch)
