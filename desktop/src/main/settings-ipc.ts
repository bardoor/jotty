import type { BrowserWindow, Dialog, IpcMain, WebContents } from "electron";

export interface ApprovedContextDirectory {
  path: string;
  approval: string;
}

export function installSettingsIpc(
  ipcMain: IpcMain,
  dialog: Dialog,
  windowForSender: (sender: WebContents) => BrowserWindow | null,
  approveDirectory: (path: string) => ApprovedContextDirectory
): void {
  ipcMain.handle("jotty:pick-context-directory", async (event) => {
    const window = windowForSender(event.sender);
    if (!window) return null;

    const result = await dialog.showOpenDialog(window, {
      properties: ["openDirectory", "createDirectory"]
    });
    const path = result.filePaths[0];
    return result.canceled || !path ? null : approveDirectory(path);
  });

  ipcMain.on("jotty:set-always-on-top", (event, enabled: unknown) => {
    const window = windowForSender(event.sender);
    if (window && typeof enabled === "boolean") window.setAlwaysOnTop(enabled);
  });
}