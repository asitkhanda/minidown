import { EditorState } from "@codemirror/state";
import {
  EditorView,
  keymap,
  drawSelection,
  dropCursor,
  placeholder,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import {
  markdown,
  markdownLanguage,
  markdownKeymap,
} from "@codemirror/lang-markdown";
import { languages } from "@codemirror/language-data";
import { syntaxHighlighting } from "@codemirror/language";
import { livePreview } from "./livePreview";
import { mdHighlight, codeHighlight } from "./highlight";
import { docState, IN_TAURI } from "./docState";

const editorTheme = EditorView.theme({
  "&": { height: "100%", fontSize: "17px", backgroundColor: "transparent" },
  "&.cm-focused": { outline: "none" },
  ".cm-content": {
    maxWidth: "42rem",
    margin: "0 auto",
    padding: "1.5rem 1.5rem 45vh",
    lineHeight: "1.75",
    caretColor: "var(--accent)",
  },
  ".cm-cursor": {
    borderLeftWidth: "2px",
    borderLeftColor: "var(--accent)",
  },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    background: "var(--selection)",
  },
  ".cm-placeholder": { color: "var(--muted)" },
});

// ---------- Document / file state ----------

let currentPath: string | null = null;
let dirty = false;
let loadingDoc = false;
let autosaveTimer: number | undefined;
let wordCountTimer: number | undefined;

const fileEl = document.getElementById("status-file")!;
const wordsEl = document.getElementById("status-words")!;

function fileName(): string {
  return currentPath ? currentPath.split("/").pop()! : "Untitled";
}

function syncDocDir() {
  docState.dir = currentPath
    ? currentPath.slice(0, currentPath.lastIndexOf("/")) || null
    : null;
}

async function refreshStatus() {
  fileEl.textContent = dirty ? `${fileName()} — Edited` : fileName();
  if (IN_TAURI) {
    const { getCurrentWindow } = await import("@tauri-apps/api/window");
    await getCurrentWindow().setTitle(fileName());
  }
}

function updateWordCount() {
  const words = view.state.doc.toString().match(/\S+/g)?.length ?? 0;
  wordsEl.textContent = `${words.toLocaleString()} ${words === 1 ? "word" : "words"}`;
}

// ---------- File operations (Tauri only) ----------

async function writeCurrent(path: string) {
  const { writeTextFile } = await import("@tauri-apps/plugin-fs");
  await writeTextFile(path, view.state.doc.toString());
  dirty = false;
  void refreshStatus();
}

function scheduleAutosave() {
  if (!currentPath) return;
  clearTimeout(autosaveTimer);
  autosaveTimer = window.setTimeout(() => {
    if (currentPath) void writeCurrent(currentPath);
  }, 800);
}

async function saveFile(saveAs = false) {
  if (!IN_TAURI) return;
  let path = currentPath;
  if (saveAs || !path) {
    const { save } = await import("@tauri-apps/plugin-dialog");
    path = await save({
      defaultPath: currentPath ?? "Untitled.md",
      filters: [{ name: "Markdown", extensions: ["md", "markdown"] }],
    });
    if (!path) return;
  }
  currentPath = path;
  syncDocDir();
  await writeCurrent(path);
}

async function openFile() {
  if (!IN_TAURI) return;
  const { open } = await import("@tauri-apps/plugin-dialog");
  const path = await open({
    multiple: false,
    filters: [{ name: "Markdown", extensions: ["md", "markdown", "txt"] }],
  });
  if (typeof path !== "string") return;
  const { readTextFile } = await import("@tauri-apps/plugin-fs");
  const text = await readTextFile(path);
  setDocument(text, path);
}

async function newFile() {
  if (dirty && !currentPath && view.state.doc.length > 0 && IN_TAURI) {
    const { ask } = await import("@tauri-apps/plugin-dialog");
    const discard = await ask("Discard unsaved changes?", {
      title: "minidown",
      kind: "warning",
    });
    if (!discard) return;
  }
  setDocument("", null);
}

function setDocument(text: string, path: string | null) {
  clearTimeout(autosaveTimer);
  loadingDoc = true;
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
  loadingDoc = false;
  currentPath = path;
  syncDocDir();
  dirty = false;
  void refreshStatus();
  updateWordCount();
  view.focus();
}

// ---------- Editor ----------

const view = new EditorView({
  parent: document.getElementById("editor")!,
  state: EditorState.create({
    doc: "",
    extensions: [
      history(),
      drawSelection(),
      dropCursor(),
      EditorView.lineWrapping,
      placeholder("Start writing…"),
      markdown({ base: markdownLanguage, codeLanguages: languages }),
      livePreview,
      syntaxHighlighting(codeHighlight),
      syntaxHighlighting(mdHighlight, { fallback: true }),
      keymap.of([...markdownKeymap, ...defaultKeymap, ...historyKeymap]),
      editorTheme,
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !loadingDoc) {
          if (!dirty) {
            dirty = true;
            void refreshStatus();
          }
          scheduleAutosave();
          clearTimeout(wordCountTimer);
          wordCountTimer = window.setTimeout(updateWordCount, 150);
        }
      }),
    ],
  }),
});

document.addEventListener("keydown", (event) => {
  if (!event.metaKey || event.ctrlKey || event.altKey) return;
  const key = event.key.toLowerCase();
  if (key === "s") {
    event.preventDefault();
    void saveFile(event.shiftKey);
  } else if (key === "o") {
    event.preventDefault();
    void openFile();
  } else if (key === "n") {
    event.preventDefault();
    void newFile();
  }
});

void refreshStatus();
updateWordCount();
view.focus();
