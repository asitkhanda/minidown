import { StateEffect, StateField } from "@codemirror/state";
import type { EditorState } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";

// Focus mode: everything except the paragraph being written is dimmed.

export const setFocusMode = StateEffect.define<boolean>();

export const focusModeField = StateField.define<boolean>({
  create: () => false,
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setFocusMode)) value = effect.value;
    }
    return value;
  },
});

// The contiguous run of non-blank lines containing pos
export function focusRange(
  state: EditorState,
  pos: number,
): { from: number; to: number } {
  const doc = state.doc;
  const line = doc.lineAt(pos);
  if (line.text.trim() === "") return { from: line.from, to: line.to };
  let first = line.number;
  let last = line.number;
  while (first > 1 && doc.line(first - 1).text.trim() !== "") first--;
  while (last < doc.lines && doc.line(last + 1).text.trim() !== "") last++;
  return { from: doc.line(first).from, to: doc.line(last).to };
}

const dimLine = Decoration.line({ class: "cm-dim-line" });

export function buildFocusDecorations(view: EditorView): DecorationSet {
  if (!view.state.field(focusModeField)) return Decoration.none;
  const { from, to } = focusRange(
    view.state,
    view.state.selection.main.head,
  );
  const deco = [];
  for (const range of view.visibleRanges) {
    let pos = range.from;
    while (pos <= range.to) {
      const line = view.state.doc.lineAt(pos);
      if (line.to < from || line.from > to) {
        deco.push(dimLine.range(line.from));
      }
      pos = line.to + 1;
    }
  }
  return Decoration.set(deco);
}

const focusDim = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildFocusDecorations(view);
    }
    update(update: ViewUpdate) {
      if (
        update.docChanged ||
        update.selectionSet ||
        update.viewportChanged ||
        update.startState.field(focusModeField) !==
          update.state.field(focusModeField)
      ) {
        this.decorations = buildFocusDecorations(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

export const focusMode = [focusModeField, focusDim];
