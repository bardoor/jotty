import type { BrowserWindowConstructorOptions } from "electron";

export const windowFrameOptions = {
  width: 440,
  height: 552,
  resizable: false,
  maximizable: false,
  titleBarStyle: "hiddenInset"
} satisfies BrowserWindowConstructorOptions;
