import MarkdownIt from "markdown-it";
import footnote from "markdown-it-footnote";
import taskLists from "markdown-it-task-lists";
import texmath from "markdown-it-texmath";
import katex from "katex";

// Standalone HTML export. Typography mirrors the editor. KaTeX styles and
// mermaid come from CDN links so the file stays a single portable .html —
// documents without math or diagrams never load them.

const KATEX_CSS =
  "https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css";
const MERMAID_JS =
  "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: false,
})
  .use(footnote)
  .use(taskLists, { enabled: false, label: true })
  .use(texmath, {
    engine: katex,
    delimiters: "dollars",
    katexOptions: { throwOnError: false },
  });

// ```mermaid fences pass through as <pre class="mermaid"> for the script
const defaultFence =
  md.renderer.rules.fence ??
  ((tokens, idx, options, _env, self) =>
    self.renderToken(tokens, idx, options));
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  if (token.info.trim() === "mermaid") {
    return `<pre class="mermaid">${md.utils.escapeHtml(token.content)}</pre>\n`;
  }
  return defaultFence(tokens, idx, options, env, self);
};

interface ParsedDoc {
  body: string;
  title: string | null;
  usesMath: boolean;
  usesMermaid: boolean;
}

export function parseForExport(source: string): ParsedDoc {
  let body = source;
  let title: string | null = null;

  // Strip frontmatter; keep its title for the <title> tag
  const fm = /^---\n([\s\S]*?)\n(?:---|\.\.\.)\n?/.exec(body);
  if (fm) {
    body = body.slice(fm[0].length);
    const titleLine = /^title:\s*(.+)\s*$/m.exec(fm[1]);
    if (titleLine) title = titleLine[1].replace(/^["']|["']$/g, "");
  }
  if (!title) {
    const heading = /^#\s+(.+)\s*$/m.exec(body);
    if (heading) title = heading[1];
  }

  return {
    body,
    title,
    usesMath: /\$[^\s$]/.test(body),
    usesMermaid: /^```mermaid\s*$/m.test(body),
  };
}

const EXPORT_CSS = `
:root { color-scheme: light dark; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  font-size: 17px;
  line-height: 1.75;
  max-width: 42rem;
  margin: 0 auto;
  padding: 3rem 1.5rem 6rem;
  color: #1c1c1c;
  background: #fbfbfa;
}
@media (prefers-color-scheme: dark) {
  body { color: #d8d8d3; background: #1b1b1d; }
}
h1 { font-size: 1.55em; } h2 { font-size: 1.3em; } h3 { font-size: 1.15em; }
a { color: #1c7ed6; }
blockquote {
  margin: 0; padding-left: 1rem;
  border-left: 3px solid #b0b0a8; color: #6f6f68; font-style: italic;
}
code {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 0.88em;
  background: rgba(27, 27, 29, 0.05);
  border-radius: 4px; padding: 0.1em 0.25em;
}
@media (prefers-color-scheme: dark) {
  code { background: rgba(255, 255, 255, 0.08); }
  blockquote { color: #8f8f88; border-left-color: #4f4f4b; }
}
pre { background: rgba(27, 27, 29, 0.05); border-radius: 8px; padding: 0.8rem 1rem; overflow-x: auto; }
pre code { background: none; padding: 0; }
pre.mermaid { background: none; text-align: center; }
img { max-width: 100%; border-radius: 6px; }
table { border-collapse: collapse; }
th, td { border: 1px solid #b0b0a8; padding: 0.35em 0.8em; }
th { background: rgba(27, 27, 29, 0.05); }
hr { border: none; height: 2px; background: #b0b0a8; border-radius: 1px; }
ul.contains-task-list { list-style: none; padding-left: 0.5em; }
.footnotes-sep { margin-top: 3em; }
@media print { body { background: #fff; color: #000; } }
`;

export function buildExportHtml(source: string): string {
  const { body, title, usesMath, usesMermaid } = parseForExport(source);
  const rendered = md.render(body);
  const head = [
    `<meta charset="utf-8">`,
    `<meta name="viewport" content="width=device-width, initial-scale=1">`,
    `<title>${md.utils.escapeHtml(title ?? "Untitled")}</title>`,
    `<style>${EXPORT_CSS}</style>`,
    usesMath ? `<link rel="stylesheet" href="${KATEX_CSS}">` : "",
    usesMermaid
      ? `<script src="${MERMAID_JS}"></script>` +
        `<script>addEventListener("DOMContentLoaded",()=>mermaid.initialize({startOnLoad:true}));</script>`
      : "",
  ]
    .filter(Boolean)
    .join("\n");
  return `<!doctype html>\n<html lang="en">\n<head>\n${head}\n</head>\n<body>\n${rendered}</body>\n</html>\n`;
}
