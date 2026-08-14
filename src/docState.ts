// Shared document state, kept out of main.ts so extensions can read it
// without circular imports.

export const IN_TAURI = "__TAURI_INTERNALS__" in window;

export const docState = {
  // Directory of the currently open file, for resolving relative image paths.
  dir: null as string | null,
};
