import { syntaxTree } from "@codemirror/language";
import { StateField } from "@codemirror/state";
import type { EditorState, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { convertFileSrc } from "@tauri-apps/api/core";
import katex from "katex";
import "katex/dist/katex.min.css";
import { docState, IN_TAURI } from "./docState";

// Live preview: markdown syntax renders in place and its marks hide whenever
// the selection is outside the construct. The document itself never changes —
// everything here is presentation-only decorations.

const hide = Decoration.replace({});
const inlineCode = Decoration.mark({ class: "cm-inlinecode" });
const codeInfo = Decoration.mark({ class: "cm-codeinfo" });
const quoteLine = Decoration.line({ class: "cm-blockquote-line" });
const tableLine = Decoration.line({ class: "cm-table-line" });
const frontmatterLine = Decoration.line({ class: "cm-frontmatter-line" });
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

function resolveImageSrc(url: string): string | null {
  if (/^(https?:|data:|asset:)/.test(url)) return url;
  if (!IN_TAURI || !docState.dir) return null;
  const abs = url.startsWith("/") ? url : `${docState.dir}/${url}`;
  return convertFileSrc(abs);
}

class ImageWidget extends WidgetType {
  constructor(
    readonly src: string,
    readonly alt: string,
  ) {
    super();
  }
  eq(other: ImageWidget) {
    return other.src === this.src && other.alt === this.alt;
  }
  toDOM() {
    const img = document.createElement("img");
    img.className = "cm-image";
    img.src = this.src;
    img.alt = this.alt;
    img.onerror = () => img.classList.add("cm-image-broken");
    return img;
  }
  // Let the editor handle clicks so the cursor lands in the syntax and reveals it
  ignoreEvent() {
    return false;
  }
}

class MathWidget extends WidgetType {
  constructor(
    readonly tex: string,
    readonly display: boolean,
  ) {
    super();
  }
  eq(other: MathWidget) {
    return other.tex === this.tex && other.display === this.display;
  }
  toDOM() {
    const el = document.createElement(this.display ? "div" : "span");
    el.className = this.display ? "cm-math-block" : "cm-math-inline";
    try {
      katex.render(this.tex, el, {
        displayMode: this.display,
        throwOnError: false,
      });
    } catch {
      el.textContent = this.tex;
      el.classList.add("cm-math-error");
    }
    return el;
  }
  ignoreEvent() {
    return false;
  }
}

function isDarkTheme(): boolean {
  const forced = document.documentElement.dataset.theme;
  if (forced) return forced === "dark";
  return typeof window.matchMedia === "function"
    ? window.matchMedia("(prefers-color-scheme: dark)").matches
    : false;
}

let mermaidCounter = 0;
const mermaidCache = new Map<string, string>();

class MermaidWidget extends WidgetType {
  constructor(
    readonly src: string,
    readonly dark: boolean,
  ) {
    super();
  }
  eq(other: MermaidWidget) {
    return other.src === this.src && other.dark === this.dark;
  }
  toDOM() {
    const el = document.createElement("div");
    el.className = "cm-mermaid";
    const key = `${this.dark ? "d" : "l"}:${this.src}`;
    const cached = mermaidCache.get(key);
    if (cached) {
      el.innerHTML = cached;
      return el;
    }
    el.textContent = "Rendering diagram…";
    void (async () => {
      try {
        const mermaid = (await import("mermaid")).default;
        mermaid.initialize({
          startOnLoad: false,
          theme: this.dark ? "dark" : "neutral",
        });
        const { svg } = await mermaid.render(
          `mmd-${mermaidCounter++}`,
          this.src,
        );
        mermaidCache.set(key, svg);
        el.innerHTML = svg;
      } catch (error) {
        el.textContent = String(error);
        el.classList.add("cm-mermaid-error");
      }
    })();
    return el;
  }
  ignoreEvent() {
    return false;
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

export function buildDecorations(view: EditorView): DecorationSet {
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
            } else if (
              parent?.name === "FencedCode" &&
              !lineActive(node.from)
            ) {
              deco.push(hide.range(node.from, node.to));
            }
            break;
          }

          case "CodeInfo": {
            deco.push(codeInfo.range(node.from, node.to));
            break;
          }

          case "FencedCode": {
            const first = doc.lineAt(node.from).number;
            const last = doc.lineAt(node.to).number;
            for (let n = first; n <= last; n++) {
              let cls = "cm-codeblock-line";
              if (n === first) cls += " cm-codeblock-first";
              if (n === last) cls += " cm-codeblock-last";
              deco.push(Decoration.line({ class: cls }).range(doc.line(n).from));
            }
            break;
          }

          case "Table": {
            const first = doc.lineAt(node.from).number;
            const last = doc.lineAt(node.to).number;
            for (let n = first; n <= last; n++) {
              deco.push(tableLine.range(doc.line(n).from));
            }
            break;
          }

          case "Frontmatter": {
            const first = doc.lineAt(node.from).number;
            const last = doc.lineAt(node.to).number;
            for (let n = first; n <= last; n++) {
              deco.push(frontmatterLine.range(doc.line(n).from));
            }
            break;
          }

          case "InlineMath": {
            if (touches(node.from, node.to)) break;
            const tex = doc.sliceString(node.from + 1, node.to - 1);
            deco.push(
              Decoration.replace({ widget: new MathWidget(tex, false) }).range(
                node.from,
                node.to,
              ),
            );
            break;
          }

          case "Image": {
            if (lineActive(node.from)) break;
            const urlNode = node.node.getChild("URL");
            if (!urlNode) break;
            const src = resolveImageSrc(doc.sliceString(urlNode.from, urlNode.to));
            if (!src) break;
            const marks = node.node.getChildren("LinkMark");
            const alt =
              marks.length >= 2
                ? doc.sliceString(marks[0].to, marks[1].from)
                : "";
            deco.push(
              Decoration.replace({ widget: new ImageWidget(src, alt) }).range(
                node.from,
                node.to,
              ),
            );
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

const inlinePreview = ViewPlugin.fromClass(
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

// ---------- Block widgets (tables, block math, mermaid) ----------
// Block-replacing decorations must come from a StateField, not a ViewPlugin.
// Each renders whenever the selection is outside it; click (or move the
// cursor) into one and it reverts to raw text for editing.

interface TableData {
  header: string[];
  aligns: (string | null)[];
  rows: string[][];
}

function parseTable(state: EditorState, table: SyntaxNode): TableData {
  const cellsOf = (row: SyntaxNode) =>
    row
      .getChildren("TableCell")
      .map((cell) => state.sliceDoc(cell.from, cell.to).trim());
  const data: TableData = { header: [], aligns: [], rows: [] };
  for (let child = table.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableHeader") {
      data.header = cellsOf(child);
    } else if (child.name === "TableDelimiter") {
      data.aligns = state
        .sliceDoc(child.from, child.to)
        .split("|")
        .map((part) => part.trim())
        .filter((part) => part.length > 0)
        .map((part) => {
          const left = part.startsWith(":");
          const right = part.endsWith(":");
          return left && right ? "center" : right ? "right" : left ? "left" : null;
        });
    } else if (child.name === "TableRow") {
      data.rows.push(cellsOf(child));
    }
  }
  return data;
}

class TableWidget extends WidgetType {
  readonly key: string;
  constructor(readonly data: TableData) {
    super();
    this.key = JSON.stringify(data);
  }
  eq(other: TableWidget) {
    return other.key === this.key;
  }
  toDOM() {
    const table = document.createElement("table");
    table.className = "cm-table";
    const addRow = (
      parent: HTMLElement,
      cells: string[],
      tag: "th" | "td",
    ) => {
      const tr = document.createElement("tr");
      cells.forEach((text, i) => {
        const cell = document.createElement(tag);
        cell.textContent = text;
        const align = this.data.aligns[i];
        if (align) cell.style.textAlign = align;
        tr.appendChild(cell);
      });
      parent.appendChild(tr);
    };
    const thead = document.createElement("thead");
    addRow(thead, this.data.header, "th");
    table.appendChild(thead);
    const tbody = document.createElement("tbody");
    for (const row of this.data.rows) addRow(tbody, row, "td");
    table.appendChild(tbody);
    return table;
  }
  // Clicks fall through to the editor, putting the cursor in the raw table
  ignoreEvent() {
    return false;
  }
}

export function buildBlockDecorations(state: EditorState): DecorationSet {
  const deco: Range<Decoration>[] = [];
  const touches = (from: number, to: number) =>
    state.selection.ranges.some((r) => r.from <= to && r.to >= from);
  syntaxTree(state).iterate({
    enter: (node) => {
      switch (node.name) {
        case "Table": {
          if (touches(node.from, node.to)) return false;
          deco.push(
            Decoration.replace({
              widget: new TableWidget(parseTable(state, node.node)),
              block: true,
            }).range(node.from, node.to),
          );
          return false;
        }

        case "BlockMath": {
          if (touches(node.from, node.to)) return false;
          const tex = state
            .sliceDoc(node.from, node.to)
            .replace(/^\$\$\s*/, "")
            .replace(/\s*\$\$\s*$/, "");
          deco.push(
            Decoration.replace({
              widget: new MathWidget(tex, true),
              block: true,
            }).range(node.from, node.to),
          );
          return false;
        }

        case "FencedCode": {
          if (touches(node.from, node.to)) return false;
          const info = node.node.getChild("CodeInfo");
          if (!info || state.sliceDoc(info.from, info.to).trim() !== "mermaid")
            return false;
          const body = node.node.getChild("CodeText");
          if (!body) return false;
          deco.push(
            Decoration.replace({
              widget: new MermaidWidget(
                state.sliceDoc(body.from, body.to),
                isDarkTheme(),
              ),
              block: true,
            }).range(node.from, node.to),
          );
          return false;
        }
      }
      return undefined;
    },
  });
  return Decoration.set(deco, true);
}

const blockField = StateField.define<DecorationSet>({
  create: buildBlockDecorations,
  update(value, tr) {
    if (tr.docChanged || tr.selection) return buildBlockDecorations(tr.state);
    return value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

export const livePreview = [inlinePreview, blockField];
