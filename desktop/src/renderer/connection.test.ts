import { afterEach, describe, expect, it, vi } from "vitest";

import { createDesktopConnection } from "./connection";
import type { ServerEvent } from "./protocol";

class FakeWebSocket {
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSED = 3;
  static readonly instances: FakeWebSocket[] = [];

  readonly listeners = new Map<string, Set<(event: Event | MessageEvent) => void>>();
  readonly sent: string[] = [];
  closed = false;
  readyState = FakeWebSocket.CONNECTING;

  constructor(readonly url: string) {
    FakeWebSocket.instances.push(this);
  }

  addEventListener(type: string, listener: (event: Event | MessageEvent) => void): void {
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: (event: Event | MessageEvent) => void): void {
    this.listeners.get(type)?.delete(listener);
  }

  send(payload: string): void {
    this.sent.push(payload);
  }

  close(): void {
    this.closed = true;
    this.readyState = FakeWebSocket.CLOSED;
    this.dispatch("close", new Event("close"));
  }

  emit(event: ServerEvent): void {
    const message = { data: JSON.stringify(event) } as MessageEvent;
    this.dispatch("message", message);
  }

  open(): void {
    this.readyState = FakeWebSocket.OPEN;
    this.dispatch("open", new Event("open"));
  }

  private dispatch(type: string, event: Event | MessageEvent): void {
    this.listeners.get(type)?.forEach((listener) => listener(event));
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
    socket.open();

    socket.emit({ type: "state", status: "recording" });
    connection.send({ type: "stop_session" });

    expect(staleEvents).toEqual([]);
    expect(activeEvents).toEqual([{ type: "state", status: "recording" }]);
    expect(socket.sent).toEqual(['{"type":"stop_session"}']);
  });

  it("queues commands until open and reconnects after a disconnect", () => {
    vi.useFakeTimers();
    vi.stubGlobal("WebSocket", FakeWebSocket);
    const connection = createDesktopConnection("ws://127.0.0.1:1231/ws");
    const events: ServerEvent[] = [];
    connection.subscribe((event) => events.push(event));

    const first = FakeWebSocket.instances[0];
    connection.send({ type: "list_sessions" });
    expect(first.sent).toEqual([]);
    first.open();
    expect(first.sent).toEqual(['{"type":"list_sessions"}']);

    first.close();
    expect(events.at(-1)).toEqual({ type: "state", status: "connecting" });
    connection.send({ type: "list_microphones" });
    vi.advanceTimersByTime(250);

    expect(FakeWebSocket.instances).toHaveLength(2);
    const second = FakeWebSocket.instances[1];
    second.open();
    expect(second.sent).toEqual(['{"type":"list_microphones"}']);
    vi.useRealTimers();
  });
});
