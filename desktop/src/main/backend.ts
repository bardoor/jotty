export function readyWebSocketUrl(line: string): string | null {
  try {
    const message = JSON.parse(line) as { type?: string; websocket_url?: string };
    return message.type === "ready" && message.websocket_url ? message.websocket_url : null;
  } catch {
    return null;
  }
}

export async function forwardBackendOutput(
  lines: AsyncIterable<string>,
  onReady: (url: string) => void,
  onLog: (line: string) => void
): Promise<void> {
  let ready = false;

  for await (const line of lines) {
    const websocketUrl = ready ? null : readyWebSocketUrl(line);

    if (websocketUrl) {
      ready = true;
      onReady(websocketUrl);
    } else {
      onLog(line);
    }
  }
}
