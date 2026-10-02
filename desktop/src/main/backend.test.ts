import { describe, expect, it } from "vitest";

import { forwardBackendOutput, readyWebSocketUrl } from "./backend";

describe("readyWebSocketUrl", () => {
  it("ignores launcher output before the ready message", () => {
    expect(readyWebSocketUrl("tput: No value for $TERM")).toBeNull();
    expect(readyWebSocketUrl('{"type":"ready","websocket_url":"ws://127.0.0.1:4765/ws"}')).toBe(
      "ws://127.0.0.1:4765/ws"
    );
  });
});

describe("forwardBackendOutput", () => {
  it("keeps forwarding stdout after receiving the ready message", async () => {
    const ready: string[] = [];
    const logs: string[] = [];

    await forwardBackendOutput(
      lines([
        '{"type":"ready","websocket_url":"ws://127.0.0.1:4765/ws"}',
        '{"scope":"session","event":"starting"}'
      ]),
      (url) => ready.push(url),
      (line) => logs.push(line)
    );

    expect(ready).toEqual(["ws://127.0.0.1:4765/ws"]);
    expect(logs).toEqual(['{"scope":"session","event":"starting"}']);
  });
});

async function* lines(values: string[]) {
  yield* values;
}
