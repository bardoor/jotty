import { contextBridge } from "electron";

const argument = process.argv.find((value) => value.startsWith("--jotty-ws-url="));

if (!argument) {
  throw new Error("Jotty WebSocket URL was not provided");
}

contextBridge.exposeInMainWorld("jotty", {
  websocketUrl: argument.slice("--jotty-ws-url=".length)
});
