import { describe, expect, it, vi } from "vitest";

import { installSettingsIpc } from "./settings-ipc";

describe("installSettingsIpc", () => {
  it("exposes only folder selection and always-on-top window actions", async () => {
    const handlers = new Map<string, (event: { sender: object }) => Promise<string | null>>();
    const listeners = new Map<string, (event: { sender: object }, value: unknown) => void>();
    const ipcMain = {
      handle: (channel: string, handler: (event: { sender: object }) => Promise<string | null>) =>
        handlers.set(channel, handler),
      on: (channel: string, listener: (event: { sender: object }, value: unknown) => void) =>
        listeners.set(channel, listener)
    };
    const window = { setAlwaysOnTop: vi.fn() };
    const dialog = {
      showOpenDialog: vi.fn().mockResolvedValue({ canceled: false, filePaths: ["/chosen/project"] })
    };

    installSettingsIpc(ipcMain as never, dialog as never, () => window as never, (path) => ({
      path,
      approval: "signed"
    }));

    expect([...handlers.keys()]).toEqual(["jotty:pick-context-directory"]);
    expect([...listeners.keys()]).toEqual(["jotty:set-always-on-top"]);
    await expect(handlers.get("jotty:pick-context-directory")!({ sender: {} })).resolves.toEqual({
      path: "/chosen/project",
      approval: "signed"
    });

    listeners.get("jotty:set-always-on-top")!({ sender: {} }, true);
    expect(window.setAlwaysOnTop).toHaveBeenCalledWith(true);
  });
});
