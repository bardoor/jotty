import { afterEach, describe, expect, it, vi } from "vitest";

const exposeInMainWorld = vi.fn();
const invoke = vi.fn();
const send = vi.fn();

vi.mock("electron", () => ({
  contextBridge: { exposeInMainWorld },
  ipcRenderer: { invoke, send }
}));

afterEach(() => {
  vi.resetModules();
  exposeInMainWorld.mockClear();
  invoke.mockClear();
  send.mockClear();
});

describe("preload", () => {
  it("exposes the WebSocket URL and only narrow settings operations", async () => {
    const originalArgv = process.argv;
    process.argv = [...originalArgv, "--jotty-ws-url=ws://127.0.0.1:4321/ws"];

    try {
      await import("./preload");
      const api = exposeInMainWorld.mock.calls[0][1] as {
        websocketUrl: string;
        pickContextDirectory(): Promise<{ path: string; approval: string } | null>;
        setAlwaysOnTop(enabled: boolean): void;
      };

      expect(Object.keys(api).sort()).toEqual(["pickContextDirectory", "setAlwaysOnTop", "websocketUrl"]);
      expect(api.websocketUrl).toBe("ws://127.0.0.1:4321/ws");

      void api.pickContextDirectory();
      api.setAlwaysOnTop(true);
      expect(invoke).toHaveBeenCalledWith("jotty:pick-context-directory");
      expect(send).toHaveBeenCalledWith("jotty:set-always-on-top", true);
    } finally {
      process.argv = originalArgv;
    }
  });
});
