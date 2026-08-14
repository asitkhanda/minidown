import { HighlightStyle } from "@codemirror/language";
import { tags } from "@lezer/highlight";

// Markdown typography — applied as fallback so embedded-language styles win
// inside code blocks.
export const mdHighlight = HighlightStyle.define([
  { tag: tags.heading1, fontSize: "1.55em", fontWeight: "700" },
  { tag: tags.heading2, fontSize: "1.3em", fontWeight: "700" },
  { tag: tags.heading3, fontSize: "1.15em", fontWeight: "650" },
  { tag: tags.heading, fontWeight: "650" },
  { tag: tags.strong, fontWeight: "700" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  // No color here: it would override token colors inside code fences.
  // Inline-code coloring lives on the .cm-inlinecode chip instead.
  {
    tag: tags.monospace,
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace",
    fontSize: "0.88em",
  },
  { tag: tags.link, color: "var(--accent)" },
  { tag: tags.url, color: "var(--accent)" },
  { tag: tags.quote, color: "var(--quote)", fontStyle: "italic" },
  { tag: tags.processingInstruction, color: "var(--syntax)" },
  { tag: tags.meta, color: "var(--syntax)" },
  { tag: tags.contentSeparator, color: "var(--syntax)" },
  // Raw TeX between $ marks
  {
    tag: tags.special(tags.content),
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace",
    fontSize: "0.88em",
    color: "var(--code)",
  },
  // Footnote references render superscript
  {
    tag: tags.special(tags.link),
    color: "var(--accent)",
    fontSize: "0.75em",
    verticalAlign: "super",
  },
]);

// Restrained, theme-aware token colors for code inside fences.
export const codeHighlight = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--sx-keyword)" },
  {
    tag: [tags.string, tags.special(tags.string), tags.regexp],
    color: "var(--sx-string)",
  },
  {
    tag: [tags.comment, tags.lineComment, tags.blockComment],
    color: "var(--sx-comment)",
    fontStyle: "italic",
  },
  {
    tag: [tags.number, tags.bool, tags.atom, tags.null],
    color: "var(--sx-number)",
  },
  {
    tag: [tags.typeName, tags.className, tags.namespace],
    color: "var(--sx-type)",
  },
  {
    tag: [tags.function(tags.variableName), tags.function(tags.propertyName)],
    color: "var(--sx-func)",
  },
]);
