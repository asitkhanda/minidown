declare module "markdown-it-footnote" {
  import type MarkdownIt from "markdown-it";
  const plugin: MarkdownIt.PluginSimple;
  export default plugin;
}

declare module "markdown-it-task-lists" {
  import type MarkdownIt from "markdown-it";
  const plugin: MarkdownIt.PluginWithOptions<{
    enabled?: boolean;
    label?: boolean;
  }>;
  export default plugin;
}

declare module "markdown-it-texmath" {
  import type MarkdownIt from "markdown-it";
  const plugin: MarkdownIt.PluginWithOptions<{
    engine?: unknown;
    delimiters?: string;
    katexOptions?: Record<string, unknown>;
  }>;
  export default plugin;
}
