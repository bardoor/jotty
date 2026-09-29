import { afterEach, describe, expect, it, vi } from "vitest";

import { createDesktopConnection } from "./connection";
import type { ServerEvent } from "./protocol";

class FakeWebSocket {
  static readonly instances: FakeWebSocket[] = [];

  readonly listeners = new Set<(event: MessageEvent) => void>();
  readonly sent: string[] = [];
  closed = false;

  constructor(readonly url: string) {
    FakeWebSocket.instances.push(this);
  }

  addEventListener(type: string, listener: (event: MessageEvent) => void): void {
    if (type === "message") this.listeners.add(listener);
  }

  removeEventListener(type: string, listener: (event: MessageEvent) => void): void {
    if (type === "message") this.listeners.delete(listener);
  }

  send(payload: string): void {
    this.sent.push(payload);
  }

  close(): void {
    this.closed = true;
  }

  emit(event: ServerEvent): void {
    const message = { data: JSON.stringify(event) } as MessageEvent;
    this.listeners.forEach((listener) => listener(message));
  }
}

afterEach(() => {
  FakeWebSocket.instances.length = 0;
  vi.unstubAllGlobals();
});

describe("createDesktopConnection", () => {
  it("reuses one socket when React remounts the subscription", () => {
    vi.stubGlobal("WebSocket", FakeWebSocket);
    const connection = createDesktopConnection("ws://127.0.0.1:1231/ws");
    const staleEvents: ServerEvent[] = [];
    const activeEvents: ServerEvent[] = [];

    const unsubscribe = connection.subscribe((event) => staleEvents.push(event));
    unsubscribe();
    connection.subscribe((event) => activeEvents.push(event));

    expect(FakeWebSocket.instances).toHaveLength(1);
    const socket = FakeWebSocket.instances[0];
    expect(socket.closed).toBe(false);

    socket.emit({ type: "state", status: "recording" });
    connection.send({ type: "stop" });

    expect(staleEvents).toEqual([]);
    expect(activeEvents).toEqual([{ type: "state", status: "recording" }]);
    expect(socket.sent).toEqual(['{"type":"stop"}']);
  });
});
