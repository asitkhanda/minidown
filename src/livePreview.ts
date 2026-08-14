import { syntaxTree } from "@codemirror/language";
import type { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";

// Live preview: markdown syntax renders in place and its marks hide whenever
// the selection is outside the construct. The document itself never changes —
// everything here is presentation-only decorations.

const hide = Decoration.replace({});
const inlineCode = Decoration.mark({ class: "cm-inlinecode" });
const quoteLine = Decoration.line({ class: "cm-blockquote-line" });
const headingLines = [1, 2, 3, 4, 5, 6].map((level) =>
  Decoration.line({ class: `cm-heading-line cm-h${level}-line` }),
);

class BulletWidget extends WidgetType {
  eq() {
    return true;
  }
  toDOM() {
    const span = document.createElement("span");
    span.className = "cm-bullet";
    span.textContent = "•";
    return span;
  }
}
const bullet = Decoration.replace({ widget: new BulletWidget() });

class CheckboxWidget extends WidgetType {
  constructor(
    readonly checked: boolean,
    readonly pos: number,
  ) {
    super();
  }
  eq(other: CheckboxWidget) {
    return other.checked === this.checked && other.pos === this.pos;
  }
  toDOM(view: EditorView) {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.className = "cm-task";
    box.checked = this.checked;
    box.addEventListener("mousedown", (event) => {
      event.preventDefault();
      view.dispatch({
        changes: {
          from: this.pos,
          to: this.pos + 3,
          insert: this.checked ? "[ ]" : "[x]",
        },
      });
    });
    return box;
  }
}

class HRWidget extends WidgetType {
  eq() {
    return true;
  }
  toDOM() {
    const el = document.createElement("span");
    el.className = "cm-hr";
    return el;
  }
}
const hr = Decoration.replace({ widget: new HRWidget() });

function buildDecorations(view: EditorView): DecorationSet {
  const deco: Range<Decoration>[] = [];
  const { state } = view;
  const { doc } = state;

  const touches = (from: number, to: number) =>
    state.selection.ranges.some((r) => r.from <= to && r.to >= from);
  const lineActive = (pos: number) => {
    const line = doc.lineAt(pos);
    return touches(line.from, line.to);
  };
  // Extend a hidden range over one trailing space (e.g. after "#" or ">")
  const withSpace = (to: number) =>
    doc.sliceString(to, to + 1) === " " ? to + 1 : to;

  const quoteLinesSeen = new Set<number>();

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter: (node) => {
        const parent = node.node.parent;
        switch (node.name) {
          case "ATXHeading1":
          case "ATXHeading2":
          case "ATXHeading3":
          case "ATXHeading4":
          case "ATXHeading5":
          case "ATXHeading6":
          case "SetextHeading1":
          case "SetextHeading2": {
            const level = Number(node.name.slice(-1));
            deco.push(headingLines[level - 1].range(doc.lineAt(node.from).from));
            break;
          }

          case "HeaderMark": {
            if (!lineActive(node.from)) {
              deco.push(hide.range(node.from, withSpace(node.to)));
            }
            break;
          }

          case "EmphasisMark":
          case "StrikethroughMark": {
            if (parent && !touches(parent.from, parent.to)) {
              deco.push(hide.range(node.from, node.to));
            }
            break;
          }

          case "CodeMark": {
            if (
              parent?.name === "InlineCode" &&
              !touches(parent.from, parent.to)
            ) {
              deco.push(hide.range(node.from, node.to));
            }
            break;
          }

          case "InlineCode": {
            deco.push(inlineCode.range(node.from, node.to));
            break;
          }

          case "LinkMark":
          case "URL":
          case "LinkTitle": {
            if (parent?.name === "Link" && !touches(parent.from, parent.to)) {
              deco.push(hide.range(node.from, node.to));
            }
            break;
          }

          case "Blockquote": {
            const first = doc.lineAt(node.from).number;
            const last = doc.lineAt(node.to).number;
            for (let n = first; n <= last; n++) {
              const line = doc.line(n);
              if (!quoteLinesSeen.has(line.from)) {
                quoteLinesSeen.add(line.from);
                deco.push(quoteLine.range(line.from));
              }
            }
            break;
          }

          case "QuoteMark": {
            if (!lineActive(node.from)) {
              deco.push(hide.range(node.from, withSpace(node.to)));
            }
            break;
          }

          case "ListMark": {
            if (parent?.name !== "ListItem") break;
            if (parent.parent?.name !== "BulletList") break;
            if (touches(node.from, node.to)) break;
            if (parent.getChild("Task")) {
              // Task items show only the checkbox — hide "- " entirely
              deco.push(hide.range(node.from, withSpace(node.to)));
            } else {
              deco.push(bullet.range(node.from, node.to));
            }
            break;
          }

          case "TaskMarker": {
            if (touches(node.from, node.to)) break;
            const checked = /x/i.test(doc.sliceString(node.from, node.to));
            deco.push(
              Decoration.replace({
                widget: new CheckboxWidget(checked, node.from),
              }).range(node.from, node.to),
            );
            break;
          }

          case "HorizontalRule": {
            if (!lineActive(node.from)) {
              deco.push(hr.range(node.from, node.to));
            }
            break;
          }
        }
      },
    });
  }

  return Decoration.set(deco, true);
}

export const livePreview = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet || update.viewportChanged) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);
