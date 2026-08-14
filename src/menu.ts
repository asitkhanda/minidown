import {
  Menu,
  MenuItem,
  PredefinedMenuItem,
  Submenu,
  CheckMenuItem,
} from "@tauri-apps/api/menu";

export type ThemePref = "system" | "light" | "dark";

export interface MenuHandlers {
  newFile(): void;
  openFile(): void;
  saveFile(saveAs?: boolean): void;
  undo(): void;
  redo(): void;
  toggleFocus(): boolean;
  toggleTypewriter(): boolean;
  setTheme(theme: ThemePref): void;
}

export interface MenuInitialState {
  focus: boolean;
  typewriter: boolean;
  theme: ThemePref;
}

export async function setupMenu(
  handlers: MenuHandlers,
  initial: MenuInitialState,
): Promise<void> {
  const separator = () => PredefinedMenuItem.new({ item: "Separator" });

  const appMenu = await Submenu.new({
    text: "minidown",
    items: [
      await PredefinedMenuItem.new({
        text: "About minidown",
        item: { About: { name: "minidown", license: "AGPL-3.0" } },
      }),
      await separator(),
      await PredefinedMenuItem.new({ item: "Hide" }),
      await PredefinedMenuItem.new({ item: "HideOthers" }),
      await separator(),
      await PredefinedMenuItem.new({ item: "Quit" }),
    ],
  });

  const fileMenu = await Submenu.new({
    text: "File",
    items: [
      await MenuItem.new({
        text: "New",
        accelerator: "CmdOrCtrl+N",
        action: () => handlers.newFile(),
      }),
      await MenuItem.new({
        text: "Open…",
        accelerator: "CmdOrCtrl+O",
        action: () => handlers.openFile(),
      }),
      await separator(),
      await MenuItem.new({
        text: "Save",
        accelerator: "CmdOrCtrl+S",
        action: () => handlers.saveFile(false),
      }),
      await MenuItem.new({
        text: "Save As…",
        accelerator: "Shift+CmdOrCtrl+S",
        action: () => handlers.saveFile(true),
      }),
    ],
  });

  const editMenu = await Submenu.new({
    text: "Edit",
    items: [
      // CodeMirror owns document history, so Undo/Redo route to it rather
      // than to the native undo manager.
      await MenuItem.new({
        text: "Undo",
        accelerator: "CmdOrCtrl+Z",
        action: () => handlers.undo(),
      }),
      await MenuItem.new({
        text: "Redo",
        accelerator: "Shift+CmdOrCtrl+Z",
        action: () => handlers.redo(),
      }),
      await separator(),
      await PredefinedMenuItem.new({ item: "Cut" }),
      await PredefinedMenuItem.new({ item: "Copy" }),
      await PredefinedMenuItem.new({ item: "Paste" }),
      await PredefinedMenuItem.new({ item: "SelectAll" }),
    ],
  });

  const focusItem = await CheckMenuItem.new({
    text: "Focus Mode",
    accelerator: "CmdOrCtrl+D",
    checked: initial.focus,
    action: async () => {
      await focusItem.setChecked(handlers.toggleFocus());
    },
  });

  const typewriterItem = await CheckMenuItem.new({
    text: "Typewriter Scrolling",
    accelerator: "Alt+CmdOrCtrl+T",
    checked: initial.typewriter,
    action: async () => {
      await typewriterItem.setChecked(handlers.toggleTypewriter());
    },
  });

  const themeItems = new Map<ThemePref, CheckMenuItem>();
  const themeItem = async (theme: ThemePref, text: string) => {
    const item = await CheckMenuItem.new({
      text,
      checked: initial.theme === theme,
      action: async () => {
        handlers.setTheme(theme);
        for (const [key, entry] of themeItems) {
          await entry.setChecked(key === theme);
        }
      },
    });
    themeItems.set(theme, item);
    return item;
  };

  const viewMenu = await Submenu.new({
    text: "View",
    items: [
      focusItem,
      typewriterItem,
      await separator(),
      await Submenu.new({
        text: "Appearance",
        items: [
          await themeItem("system", "System"),
          await themeItem("light", "Light"),
          await themeItem("dark", "Dark"),
        ],
      }),
    ],
  });

  const windowMenu = await Submenu.new({
    text: "Window",
    items: [
      await PredefinedMenuItem.new({ item: "Minimize" }),
      await PredefinedMenuItem.new({ item: "Maximize" }),
      await separator(),
      await PredefinedMenuItem.new({ item: "CloseWindow" }),
    ],
  });

  const menu = await Menu.new({
    items: [appMenu, fileMenu, editMenu, viewMenu, windowMenu],
  });
  await menu.setAsAppMenu();
}
