import type { ServerEvent } from "./protocol";

export type DesktopCommand =
  | { type: "start_session" }
  | { type: "stop_session" }
  | { type: "approve_task"; card_id: string }
  | { type: "deny_task"; card_id: string }
  | { type: "change_always_on_top"; enabled: boolean }
  | { type: "change_microphone"; microphone_device_id: string | null }
  | { type: "add_context"; path: string; approval: string }
  | { type: "remove_context"; id: string }
  | { type: "reorder_contexts"; context_ids: string[] }
  | { type: "list_microphones" }
  | { type: "list_sessions" }
  | { type: "open_session"; id: string }
  | { type: "rename_session"; id: string; title: string }
  | { type: "delete_session"; id: string };

export interface DesktopConnection {
  subscribe(listener: (event: ServerEvent) => void): () => void;
  send(command: DesktopCommand): void;
}

export function createDesktopConnection(url: string): DesktopConnection {
  let socket: WebSocket | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  const listeners = new Set<(event: ServerEvent) => void>();
  const pendingCommands: string[] = [];

  const publish = (event: ServerEvent) => listeners.forEach((listener) => listener(event));

  const connect = () => {
    if (socket !== null || listeners.size === 0) return;

    const nextSocket = new WebSocket(url);
    socket = nextSocket;

    nextSocket.addEventListener("open", () => {
      while (socket === nextSocket && nextSocket.readyState === WebSocket.OPEN && pendingCommands.length > 0) {
        nextSocket.send(pendingCommands.shift()!);
      }
    });
    nextSocket.addEventListener("message", (message) => {
      publish(JSON.parse(String(message.data)) as ServerEvent);
    });
    nextSocket.addEventListener("close", () => {
      if (socket !== nextSocket) return;
      socket = null;
      publish({ type: "state", status: "connecting" });
      if (listeners.size > 0) reconnectTimer = setTimeout(connect, 250);
    });
  };

  return {
    subscribe(listener) {
      listeners.add(listener);
      connect();

      return () => {
        listeners.delete(listener);
        if (listeners.size === 0 && reconnectTimer !== null) {
          clearTimeout(reconnectTimer);
          reconnectTimer = null;
        }
      };
    },
    send(command) {
      const payload = JSON.stringify(command);
      if (socket?.readyState === WebSocket.OPEN) socket.send(payload);
      else pendingCommands.push(payload);
    }
  };
}
