import type { BrowserWindowConstructorOptions } from "electron";

export const windowFrameOptions = {
  width: 360,
  height: 520,
  resizable: false,
  maximizable: false,
  titleBarStyle: "hiddenInset"
} satisfies BrowserWindowConstructorOptions;
