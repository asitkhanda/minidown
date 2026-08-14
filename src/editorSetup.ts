import type { Extension } from "@codemirror/state";
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
import {
  syntaxHighlighting,
  LanguageDescription,
} from "@codemirror/language";

// Match fence info strings by name and alias ("python", "ts") but also by
// file extension ("py", "rs"), which the default matcher ignores.
function codeLanguage(info: string): LanguageDescription | null {
  return (
    LanguageDescription.matchLanguageName(languages, info, true) ??
    languages.find((lang) =>
      lang.extensions.includes(info.toLowerCase()),
    ) ??
    null
  );
}
import { livePreview } from "./livePreview";
import { focusMode } from "./focusMode";
import { typewriter } from "./typewriter";
import { mdHighlight, codeHighlight } from "./highlight";

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

// The full editor wiring, shared by the app and the regression tests.
// NOTE: both highlight styles must be registered as PRIMARY highlighters.
// A `fallback: true` highlighter is ignored entirely once any primary
// highlighter exists — registering codeHighlight as primary while
// mdHighlight was fallback is exactly what broke heading styling once.
export const editorExtensions: Extension[] = [
  history(),
  drawSelection(),
  dropCursor(),
  EditorView.lineWrapping,
  placeholder("Start writing…"),
  markdown({ base: markdownLanguage, codeLanguages: codeLanguage }),
  livePreview,
  focusMode,
  typewriter,
  syntaxHighlighting(mdHighlight),
  syntaxHighlighting(codeHighlight),
  keymap.of([...markdownKeymap, ...defaultKeymap, ...historyKeymap]),
  editorTheme,
];
