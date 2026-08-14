import { StateEffect, StateField } from "@codemirror/state";
import { EditorView } from "@codemirror/view";

// Typewriter mode: while typing, the cursor line stays vertically centered.
// Only typing (input/delete) recenters — mouse clicks and arrow keys scroll
// normally, so reading and navigating never jump.

export const setTypewriter = StateEffect.define<boolean>();

export const typewriterField = StateField.define<boolean>({
  create: () => false,
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setTypewriter)) value = effect.value;
    }
    return value;
  },
});

const typewriterScroll = EditorView.updateListener.of((update) => {
  if (!update.state.field(typewriterField)) return;
  if (!update.docChanged) return;
  const typed = update.transactions.some(
    (tr) => tr.isUserEvent("input") || tr.isUserEvent("delete"),
  );
  if (!typed) return;
  const head = update.state.selection.main.head;
  // Dispatching directly from an update listener is not allowed
  requestAnimationFrame(() => {
    update.view.dispatch({
      effects: EditorView.scrollIntoView(head, { y: "center" }),
    });
  });
});

export const typewriter = [typewriterField, typewriterScroll];
