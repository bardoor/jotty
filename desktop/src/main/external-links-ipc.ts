import type { IpcMain, Shell } from "electron";

export function installExternalLinksIpc(
  ipcMain: Pick<IpcMain, "on">,
  shell: Pick<Shell, "openExternal">
): void {
  ipcMain.on("jotty:open-external", (_event, value: unknown) => {
    const url = safeWebUrl(value);
    if (url) void shell.openExternal(url);
  });
}

function safeWebUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch {
    return null;
  }
}
