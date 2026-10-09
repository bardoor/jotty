import { app, BrowserWindow, dialog, ipcMain } from "electron";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createHmac, randomBytes } from "node:crypto";
import net from "node:net";
import path from "node:path";
import readline from "node:readline";

import { forwardBackendOutput } from "./backend";
import { installSettingsIpc } from "./settings-ipc";
import { windowFrameOptions } from "./window";

let backend: ChildProcessWithoutNullStreams | null = null;
const contextApprovalSecret = randomBytes(32).toString("hex");

installSettingsIpc(
  ipcMain,
  dialog,
  (sender) => BrowserWindow.fromWebContents(sender),
  (directory) => ({
    path: directory,
    approval: createHmac("sha256", contextApprovalSecret).update(directory).digest("hex")
  })
);

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

function backendExecutable(): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, "jotty")
    : path.resolve(__dirname, "../../../jotty");
}

async function migrate(executable: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const migration = spawn(executable, ["migrate"], {
      cwd: path.dirname(executable),
      env: process.env,
      stdio: ["ignore", "ignore", "pipe"]
    });
    let error = "";

    migration.stderr.on("data", (data) => { error += data.toString(); });
    migration.once("error", reject);
    migration.once("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(error.trim() || `Jotty migration exited with status ${code}`));
    });
  });
}

async function startBackend(): Promise<string> {
  const port = await reservePort();
  const executable = backendExecutable();

  await migrate(executable);

  backend = spawn(executable, ["serve", "--port", String(port)], {
    cwd: path.dirname(executable),
    env: { ...process.env, JOTTY_CONTEXT_APPROVAL_SECRET: contextApprovalSecret },
    stdio: "pipe"
  });
  backend.stdin.end();

  return new Promise((resolve, reject) => {
    const lines = readline.createInterface({ input: backend!.stdout });
    const timeout = setTimeout(() => reject(new Error("Jotty service did not start in time")), 15_000);

    backend!.once("error", reject);
    backend!.once("exit", (code) => reject(new Error(`Jotty service exited with status ${code}`)));
    backend!.stderr.on("data", (data) => process.stderr.write(data));

    void forwardBackendOutput(
      lines,
      (websocketUrl) => {
        clearTimeout(timeout);
        resolve(websocketUrl);
      },
      (line) => console.log(`[backend] ${line}`)
    ).catch(reject);
  });
}

async function createWindow() {
  const websocketUrl = await startBackend();
  const window = new BrowserWindow({
    ...windowFrameOptions,
    title: "Jotty",
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
