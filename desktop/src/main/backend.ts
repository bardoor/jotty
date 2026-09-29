export function readyWebSocketUrl(line: string): string | null {
  try {
    const message = JSON.parse(line) as { type?: string; websocket_url?: string };
    return message.type === "ready" && message.websocket_url ? message.websocket_url : null;
  } catch {
    return null;
  }
}
