import { describe, it, expect } from "vitest";
import { EditorSelection, EditorState } from "@codemirror/state";
import type { EditorView, DecorationSet } from "@codemirror/view";
import { ensureSyntaxTree, highlightingFor } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import { editorExtensions } from "./editorSetup";
import { buildDecorations, buildTableDecorations } from "./livePreview";

function makeState(doc: string, cursor: number): EditorState {
  const state = EditorState.create({
    doc,
    selection: EditorSelection.cursor(cursor),
    extensions: editorExtensions,
  });
  // Force a complete parse so decorations see the full tree
  ensureSyntaxTree(state, state.doc.length, 5000);
  return state;
}

// buildDecorations only reads .state and .visibleRanges
function fakeView(state: EditorState): EditorView {
  return {
    state,
    visibleRanges: [{ from: 0, to: state.doc.length }],
  } as unknown as EditorView;
}

// Replace decorations that hide syntax have from < to; line/widget points have from === to
function hiddenRanges(set: DecorationSet): { from: number; to: number }[] {
  const out: { from: number; to: number }[] = [];
  const iter = set.iter();
  while (iter.value) {
    const spec = iter.value.spec as { class?: string; widget?: unknown };
    if (iter.from < iter.to && !spec.class) {
      out.push({ from: iter.from, to: iter.to });
    }
    iter.next();
  }
  return out;
}

function hasHidden(set: DecorationSet, from: number, to: number): boolean {
  return hiddenRanges(set).some((r) => r.from === from && r.to === to);
}

function widgetsBetween(set: DecorationSet, from: number, to: number): number {
  let count = 0;
  set.between(from, to, (_f, _t, deco) => {
    if ((deco.spec as { widget?: unknown }).widget) count++;
  });
  return count;
}

describe("highlighter wiring", () => {
  // Regression: mdHighlight was registered with fallback:true, which CodeMirror
  // ignores entirely once any primary highlighter (codeHighlight) exists —
  // killing all heading/bold/italic styling.
  it("styles markdown typography and code tokens together", () => {
    const state = makeState("# Hello", 7);
    expect(highlightingFor(state, [tags.heading1])).toBeTruthy();
    expect(highlightingFor(state, [tags.strong])).toBeTruthy();
    expect(highlightingFor(state, [tags.emphasis])).toBeTruthy();
    expect(highlightingFor(state, [tags.keyword])).toBeTruthy();
    expect(highlightingFor(state, [tags.string])).toBeTruthy();
  });
});

describe("markdown parsing", () => {
  it("recognizes the core syntax set", () => {
    const doc = [
      "# Heading",
      "",
      "**bold** *italic* `code` ~~gone~~",
      "",
      "- [ ] task",
      "",
      "> quote",
      "",
      "| a | b |",
      "| --- | --- |",
      "| 1 | 2 |",
      "",
      "```js",
      "let x = 1;",
      "```",
      "",
      "![img](pic.png)",
      "",
      "[link](https://example.com)",
    ].join("\n");
    const state = makeState(doc, 0);
    const names = new Set<string>();
    ensureSyntaxTree(state, state.doc.length, 5000)!.iterate({
      enter: (node) => {
        names.add(node.name);
      },
    });
    for (const expected of [
      "ATXHeading1",
      "StrongEmphasis",
      "Emphasis",
      "InlineCode",
      "Strikethrough",
      "TaskMarker",
      "Blockquote",
      "Table",
      "FencedCode",
      "Image",
      "Link",
    ]) {
      expect(names, `missing node ${expected}`).toContain(expected);
    }
  });
});

describe("live preview hide/reveal", () => {
  const doc = "para\n\n**bold** here";
  // "**" marks at [6,8) and [12,14)

  it("hides emphasis marks when the cursor is elsewhere", () => {
    const set = buildDecorations(fakeView(makeState(doc, 0)));
    expect(hasHidden(set, 6, 8)).toBe(true);
    expect(hasHidden(set, 12, 14)).toBe(true);
  });

  it("reveals emphasis marks when the cursor is inside", () => {
    const set = buildDecorations(fakeView(makeState(doc, 9)));
    expect(hasHidden(set, 6, 8)).toBe(false);
    expect(hasHidden(set, 12, 14)).toBe(false);
  });

  it("hides heading marks only when the line is inactive", () => {
    const heading = "# Title\n\nmore";
    const away = buildDecorations(fakeView(makeState(heading, 12)));
    expect(hasHidden(away, 0, 2)).toBe(true); // "# " incl. trailing space
    const onLine = buildDecorations(fakeView(makeState(heading, 3)));
    expect(hasHidden(onLine, 0, 2)).toBe(false);
  });

  it("renders task markers as widgets and hides the bullet", () => {
    const task = "- [ ] task\n\nend";
    const set = buildDecorations(fakeView(makeState(task, task.length)));
    expect(widgetsBetween(set, 2, 5)).toBe(1); // checkbox over "[ ]"
    expect(hasHidden(set, 0, 2)).toBe(true); // "- " hidden for task items
  });

  it("hides code fence marks when inactive", () => {
    const fenced = "```js\nlet x = 1;\n```\n\nafter";
    const set = buildDecorations(fakeView(makeState(fenced, fenced.length)));
    expect(hasHidden(set, 0, 3)).toBe(true);
  });
});

describe("table rendering", () => {
  const doc = "| a | b |\n| --- | --- |\n| 1 | 2 |\n\nafter";

  it("replaces the table with a widget when the selection is outside", () => {
    const state = makeState(doc, doc.length);
    const set = buildTableDecorations(state);
    let widgets = 0;
    set.between(0, state.doc.length, () => {
      widgets++;
    });
    expect(widgets).toBe(1);
  });

  it("shows raw markdown when the selection is inside the table", () => {
    const state = makeState(doc, 2);
    const set = buildTableDecorations(state);
    let widgets = 0;
    set.between(0, state.doc.length, () => {
      widgets++;
    });
    expect(widgets).toBe(0);
  });
});
