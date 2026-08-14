import type {
  MarkdownConfig,
  InlineContext,
  BlockContext,
  Line,
} from "@lezer/markdown";
import { tags as t } from "@lezer/highlight";

// Custom syntax the stock markdown parser doesn't ship: YAML frontmatter,
// footnote references, and TeX math. Parsing only — rendering happens in
// livePreview decorations.

export const Frontmatter: MarkdownConfig = {
  defineNodes: [{ name: "Frontmatter", block: true, style: t.meta }],
  parseBlock: [
    {
      name: "Frontmatter",
      before: "HorizontalRule",
      parse(cx: BlockContext, line: Line): boolean {
        // Only a "---" on the very first line of the document
        if (cx.lineStart !== 0 || line.text.trim() !== "---") return false;
        const from = cx.lineStart;
        while (cx.nextLine()) {
          if (/^(---|\.\.\.)\s*$/.test(line.text)) {
            cx.nextLine();
            cx.addElement(cx.elt("Frontmatter", from, cx.prevLineEnd()));
            return true;
          }
        }
        // Unclosed: block parsers may not rewind, so the rest of the
        // document is frontmatter until the closing fence is typed
        cx.addElement(cx.elt("Frontmatter", from, cx.prevLineEnd()));
        return true;
      },
    },
  ],
};

export const Footnotes: MarkdownConfig = {
  defineNodes: [{ name: "FootnoteRef", style: t.special(t.link) }],
  parseInline: [
    {
      name: "FootnoteRef",
      before: "Link",
      parse(cx: InlineContext, next: number, pos: number): number {
        if (next !== 91 /* [ */ || cx.char(pos + 1) !== 94 /* ^ */) return -1;
        for (let i = pos + 2; i < cx.end; i++) {
          const ch = cx.char(i);
          if (ch === 93 /* ] */) {
            if (i === pos + 2) return -1;
            return cx.addElement(cx.elt("FootnoteRef", pos, i + 1));
          }
          // Footnote labels contain no spaces, newlines, or brackets
          if (ch === 32 || ch === 10 || ch === 91) return -1;
        }
        return -1;
      },
    },
  ],
};

export const MathSyntax: MarkdownConfig = {
  defineNodes: [
    { name: "InlineMath", style: t.special(t.content) },
    { name: "InlineMathMark", style: t.processingInstruction },
    { name: "BlockMath", block: true, style: t.special(t.content) },
  ],
  parseInline: [
    {
      name: "InlineMath",
      before: "Link",
      parse(cx: InlineContext, next: number, pos: number): number {
        if (next !== 36 /* $ */ || cx.char(pos + 1) === 36) return -1;
        // Pandoc rules against "$5 and $10": opening $ must be followed by
        // non-space, closing $ preceded by non-space
        const after = cx.char(pos + 1);
        if (after === 32 || after === 9 || after < 0) return -1;
        for (let i = pos + 2; i < cx.end; i++) {
          const ch = cx.char(i);
          if (ch === 10) return -1;
          if (ch === 36) {
            const prev = cx.char(i - 1);
            if (prev === 32 || prev === 9) return -1;
            return cx.addElement(
              cx.elt("InlineMath", pos, i + 1, [
                cx.elt("InlineMathMark", pos, pos + 1),
                cx.elt("InlineMathMark", i, i + 1),
              ]),
            );
          }
        }
        return -1;
      },
    },
  ],
  parseBlock: [
    {
      name: "BlockMath",
      parse(cx: BlockContext, line: Line): boolean {
        if (!line.text.startsWith("$$")) return false;
        const from = cx.lineStart;
        // Single-line form: $$ ... $$
        if (/^\$\$.+\$\$\s*$/.test(line.text)) {
          const to = cx.lineStart + line.text.length;
          cx.nextLine();
          cx.addElement(cx.elt("BlockMath", from, to));
          return true;
        }
        while (cx.nextLine()) {
          if (/^\$\$\s*$/.test(line.text)) {
            cx.nextLine();
            cx.addElement(cx.elt("BlockMath", from, cx.prevLineEnd()));
            return true;
          }
        }
        cx.addElement(cx.elt("BlockMath", from, cx.prevLineEnd()));
        return true;
      },
    },
  ],
};

export const markdownExtensions = [Frontmatter, Footnotes, MathSyntax];
