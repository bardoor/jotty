import { app, BrowserWindow, dialog } from "electron";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import net from "node:net";
import path from "node:path";
import readline from "node:readline";

import { readyWebSocketUrl } from "./backend";

let backend: ChildProcessWithoutNullStreams | null = null;

async function reservePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : null;
      server.close(() => {
        if (port === null) {
          reject(new Error("Could not reserve a loopback port"));
        } else {
          resolve(port);
        }
      });
    });
  });
}

async function startBackend(): Promise<string> {
  const port = await reservePort();
  const executable = app.isPackaged
    ? path.join(process.resourcesPath, "jotty")
    : path.resolve(__dirname, "../../../jotty");

  backend = spawn(executable, ["serve", "--port", String(port)], {
    cwd: path.dirname(executable),
    stdio: "pipe"
  });
  backend.stdin.end();

  return new Promise((resolve, reject) => {
    const lines = readline.createInterface({ input: backend!.stdout });
    const timeout = setTimeout(() => reject(new Error("Jotty service did not start in time")), 15_000);

    backend!.once("error", reject);
    backend!.once("exit", (code) => reject(new Error(`Jotty service exited with status ${code}`)));
    backend!.stderr.on("data", (data) => process.stderr.write(data));

    lines.on("line", (line) => {
      const websocketUrl = readyWebSocketUrl(line);

      if (websocketUrl) {
        clearTimeout(timeout);
        lines.close();
        resolve(websocketUrl);
      }
    });
  });
}

async function createWindow() {
  const websocketUrl = await startBackend();
  const window = new BrowserWindow({
    width: 1080,
    height: 760,
    minWidth: 720,
    minHeight: 520,
    title: "Jotty",
    titleBarStyle: "hiddenInset",
    backgroundColor: "#f4ede2",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      additionalArguments: [`--jotty-ws-url=${websocketUrl}`],
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event) => event.preventDefault());

  if (process.env.VITE_DEV_SERVER_URL) {
    await window.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    await window.loadFile(path.join(__dirname, "../renderer/index.html"));
  }
}

app.whenReady().then(async () => {
  try {
    await createWindow();
  } catch (error) {
    dialog.showErrorBox("Jotty could not start", error instanceof Error ? error.message : String(error));
    app.quit();
  }
});

app.on("window-all-closed", () => app.quit());

app.on("before-quit", () => {
  backend?.kill();
  backend = null;
});
