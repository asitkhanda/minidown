# Manual testing checklist

The automated suite (`xcodebuild … test`) covers parsing, hide/reveal, and
export output. This checklist covers what automation can't reach: native
menus, dialogs, printing, and feel. Run it in the built app
(`open Minidown/Minidown.xcodeproj` → Run, or an archived build) before
tagging a release.

## Files

- [ ] ⌘N opens a new Untitled document window
- [ ] ⌘O opens a `.md` file; the title bar shows the filename
- [ ] ⌘S on Untitled opens the Save dialog; afterwards the title shows the name
- [ ] Type after saving: the close button shows the edited dot, and the change
  autosaves in place
- [ ] ⇧⌘S (Duplicate / Save As) writes a copy and switches to it
- [ ] Closing a window with unsaved changes prompts; so does Quit
- [ ] **Double-click a `.md` file in Finder** — it opens in minidown
- [ ] **Drag a `.md` file onto the Dock icon** — it opens
- [ ] Two documents open at once, each in its own window, both editable
- [ ] File → Open Recent lists documents opened earlier
- [ ] Reopen a saved file: content is byte-identical (no reformatting) —
  spot-check with `git diff` or `diff` against a copy
- [ ] Quit and relaunch: theme, focus, typewriter, and stats-mode choices persist

## Live preview

Open `examples/01-basics.md`:
- [ ] ⌘A selects all — tables, images, diagrams and rules **stay rendered**;
  inline marks (`**`, `` ` ``, `#`) reveal
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

Open `examples/02-code.md`:
- [ ] Each fence is coloured for **its own** language — `py` keywords differ
  from `js` keywords; JSON strings and shell comments are coloured
- [ ] The unlabelled fence gets block styling but no token colours

Open `examples/05-writing-sample.md`:
- [ ] Prose rhythm and line spacing read well; ⌘D and ⌥⌘T feel right here

Open `examples/04-torture-test.md`:
- [ ] Everything renders per its italic annotations; nothing crashes,
  nothing is silently eaten

Open `examples/06-extended.md`:
- [ ] Frontmatter is quiet metadata; inline + block math style distinctly;
  `$5 and $10` stay dollars; footnote refs are superscript
- [ ] Mermaid fence renders as a diagram with readable labels and arrows
- [ ] **Turn off Wi-Fi** — math and diagrams still render (assets are bundled)
- [ ] Switch appearance (View → Appearance) → editor palette flips
- [ ] Liquid Glass is the **default** on a fresh install (macOS 26+)
- [ ] Liquid Glass + Light and Liquid Glass + Dark are both legible — text never
  washes out against the canvas
- [ ] View → Window switches Liquid Glass / Solid; the item is disabled below macOS 26
- [ ] Status bar controls render as glass capsules and stay readable over a busy desktop
- [ ] View → Font switches sans serif / serif / typewriter, and persists
- [ ] Sans Serif renders as DM Sans, Serif as Spectral, Typewriter as Fira Code
- [ ] Code blocks are Fira Code in **every** prose font, with ligatures
  (`=>`, `!=`, `>=`) forming
- [ ] No Font menu entry is marked "(unavailable)" — all three are bundled
- [ ] View → Theme switches between all six themes; prose, links, quotes, code
  fences and inline code all recolour together
- [ ] Each theme is legible in **both** Light and Dark, and follows System
- [ ] Switching theme with a table, diagram or formula on screen redraws them in
  the new palette rather than showing the previous theme's bitmap
- [ ] The chosen theme survives a relaunch

## Menus & shortcuts

- [ ] File / Edit / View menus present with expected items
- [ ] Edit → Undo/Redo work on typing
- [ ] Cut/Copy/Paste/Select All work via menu and keys
- [ ] View → Focus Mode and Typewriter Scrolling track state, including when
  toggled via ⌘D / ⌥⌘T or the status bar buttons
- [ ] Appearance submenu: System / Light / Dark / Liquid Glass switches the window
- [ ] There is exactly **one** View menu
- [ ] minidown → About shows the version and licence
- [ ] Focus Mode and Typewriter show real checkmarks, not "✓" in the title

## Focus & typewriter

- [ ] ⌘D dims all but the current paragraph; moving the cursor re-lights
  the paragraph under it
- [ ] ⌥⌘T: typing keeps the caret line vertically centered; mouse clicks
  and arrow keys do NOT recenter

## Export

- [ ] ⌘P opens the print panel (Save as PDF available)
- [ ] ⇧⌘E writes a standalone HTML file and opens it
- [ ] File → Export → Word / RTF / Plain Text produce openable files
- [ ] Exported HTML keeps **lists, tables, task lists, images and rules**
- [ ] A document with no math or diagrams exports HTML that loads no CDN assets
- [ ] A document mentioning "$5 and $10" does **not** render those as math

## Appearance & icon

- [ ] The app icon appears in the Dock, Finder, ⌘-Tab and the About box
- [ ] Task checkboxes render as outlined / filled squares and toggle on click
- [ ] Focus mode dims without revealing any raw syntax underneath widgets

## Performance

- [ ] Typing in a long document (20k+ words) stays responsive
- [ ] Holding an arrow key scrolls smoothly with focus mode on
- [ ] CJK input via an IME composes normally and is not interrupted
