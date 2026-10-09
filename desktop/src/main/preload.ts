import { contextBridge, ipcRenderer } from "electron";

const argument = process.argv.find((value) => value.startsWith("--jotty-ws-url="));

if (!argument) {
  throw new Error("Jotty WebSocket URL was not provided");
}

contextBridge.exposeInMainWorld("jotty", {
  websocketUrl: argument.slice("--jotty-ws-url=".length),
  pickContextDirectory: () =>
    ipcRenderer.invoke("jotty:pick-context-directory") as Promise<{ path: string; approval: string } | null>,
  setAlwaysOnTop: (enabled: boolean) => ipcRenderer.send("jotty:set-always-on-top", enabled)
});
