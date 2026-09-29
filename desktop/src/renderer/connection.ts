import type { ServerEvent } from "./protocol";

export type DesktopCommand = { type: "start" | "stop" };

export interface DesktopConnection {
  subscribe(listener: (event: ServerEvent) => void): () => void;
  send(command: DesktopCommand): void;
}

export function createDesktopConnection(url: string): DesktopConnection {
  let socket: WebSocket | null = null;

  return {
    subscribe(listener) {
      socket ??= new WebSocket(url);
      const handleMessage = (message: MessageEvent) => {
        listener(JSON.parse(String(message.data)) as ServerEvent);
      };
      socket.addEventListener("message", handleMessage);

      return () => {
        socket?.removeEventListener("message", handleMessage);
      };
    },
    send(command) {
      socket?.send(JSON.stringify(command));
    }
  };
}
