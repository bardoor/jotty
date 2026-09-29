import { describe, expect, it } from "vitest";

import { readyWebSocketUrl } from "./backend";

describe("readyWebSocketUrl", () => {
  it("ignores launcher output before the ready message", () => {
    expect(readyWebSocketUrl("tput: No value for $TERM")).toBeNull();
    expect(readyWebSocketUrl('{"type":"ready","websocket_url":"ws://127.0.0.1:4765/ws"}')).toBe(
      "ws://127.0.0.1:4765/ws"
    );
  });
});
