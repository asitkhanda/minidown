import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { undo, redo } from "@codemirror/commands";
import { editorExtensions } from "./editorSetup";
import { focusModeField, setFocusMode } from "./focusMode";
import { typewriterField, setTypewriter } from "./typewriter";
import { docState, IN_TAURI } from "./docState";
import { formatStats, nextStatsMode, type StatsMode } from "./stats";

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

let statsMode = (localStorage.getItem("statsMode") ?? "words") as StatsMode;

function updateWordCount() {
  wordsEl.textContent = formatStats(view.state.doc.toString(), statsMode);
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

async function exportHtml() {
  if (!IN_TAURI) return;
  const { buildExportHtml } = await import("./export");
  const { save } = await import("@tauri-apps/plugin-dialog");
  const suggested = currentPath
    ? currentPath.replace(/\.(md|markdown|txt)$/i, "") + ".html"
    : "Untitled.html";
  const path = await save({
    defaultPath: suggested,
    filters: [{ name: "HTML", extensions: ["html"] }],
  });
  if (!path) return;
  const { writeTextFile } = await import("@tauri-apps/plugin-fs");
  await writeTextFile(path, buildExportHtml(view.state.doc.toString()));
  // Open in the default browser — print to PDF from there
  const { openPath } = await import("@tauri-apps/plugin-opener");
  await openPath(path).catch(() => {
    /* export succeeded; opening is best-effort */
  });
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
      editorExtensions,
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

// ---------- View settings (persisted) ----------

type ThemePref = "system" | "light" | "dark";

function loadPref(key: string, fallback: string): string {
  return localStorage.getItem(key) ?? fallback;
}

function applyTheme(theme: ThemePref) {
  if (theme === "system") {
    delete document.documentElement.dataset.theme;
  } else {
    document.documentElement.dataset.theme = theme;
  }
  localStorage.setItem("theme", theme);
}

function syncStatusToggles() {
  document
    .getElementById("btn-focus")!
    .classList.toggle("active", view.state.field(focusModeField));
  document
    .getElementById("btn-typewriter")!
    .classList.toggle("active", view.state.field(typewriterField));
}

function toggleFocus(): boolean {
  const on = !view.state.field(focusModeField);
  view.dispatch({ effects: setFocusMode.of(on) });
  localStorage.setItem("focus", String(on));
  syncStatusToggles();
  return on;
}

function toggleTypewriter(): boolean {
  const on = !view.state.field(typewriterField);
  view.dispatch({ effects: setTypewriter.of(on) });
  document.getElementById("editor")!.classList.toggle("typewriter", on);
  localStorage.setItem("typewriter", String(on));
  syncStatusToggles();
  if (on) {
    view.dispatch({
      effects: EditorView.scrollIntoView(view.state.selection.main.head, {
        y: "center",
      }),
    });
  }
  return on;
}

const initialTheme = loadPref("theme", "system") as ThemePref;
applyTheme(initialTheme);
if (loadPref("focus", "false") === "true") toggleFocus();
if (loadPref("typewriter", "false") === "true") toggleTypewriter();

// ---------- Menu & shortcuts ----------

if (IN_TAURI) {
  void (async () => {
    try {
      const { setupMenu } = await import("./menu");
      await setupMenu(
    {
      newFile: () => void newFile(),
      openFile: () => void openFile(),
      saveFile: (saveAs) => void saveFile(saveAs),
      exportHtml: () => void exportHtml(),
      undo: () => undo(view),
      redo: () => redo(view),
      toggleFocus,
      toggleTypewriter,
      setTheme: applyTheme,
    },
        {
          focus: view.state.field(focusModeField),
          typewriter: view.state.field(typewriterField),
          theme: initialTheme,
        },
      );
    } catch (error) {
      // Keyboard shortcuts still work without a menu — never block startup
      console.error("menu setup failed", error);
    }
  })();
}

// Fallback shortcuts for when no native menu intercepts them (browser dev).
// In the app the menu accelerators consume these keys first.
document.addEventListener("keydown", (event) => {
  if (!event.metaKey || event.ctrlKey) return;
  const key = event.key.toLowerCase();
  if (event.altKey) {
    if (key === "t" || key === "†") {
      event.preventDefault();
      toggleTypewriter();
    }
    return;
  }
  if (key === "s") {
    event.preventDefault();
    void saveFile(event.shiftKey);
  } else if (key === "e" && event.shiftKey) {
    event.preventDefault();
    void exportHtml();
  } else if (key === "o") {
    event.preventDefault();
    void openFile();
  } else if (key === "n") {
    event.preventDefault();
    void newFile();
  } else if (key === "d") {
    event.preventDefault();
    toggleFocus();
  }
});

// Status bar tools
wordsEl.addEventListener("click", () => {
  statsMode = nextStatsMode(statsMode);
  localStorage.setItem("statsMode", statsMode);
  updateWordCount();
});
document
  .getElementById("btn-focus")!
  .addEventListener("click", () => toggleFocus());
document
  .getElementById("btn-typewriter")!
  .addEventListener("click", () => toggleTypewriter());
const exportBtn = document.getElementById("btn-export")!;
if (IN_TAURI) {
  exportBtn.addEventListener("click", () => void exportHtml());
} else {
  exportBtn.style.display = "none";
}

syncStatusToggles();
void refreshStatus();
updateWordCount();
view.focus();
