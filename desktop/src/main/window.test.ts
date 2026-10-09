import { describe, expect, it } from "vitest";

import { windowFrameOptions } from "./window";

describe("windowFrameOptions", () => {
  it("uses a compact fixed frame with an inset macOS title bar", () => {
    expect(windowFrameOptions).toEqual({
      width: 440,
      height: 552,
      resizable: false,
      maximizable: false,
      titleBarStyle: "hiddenInset"
    });
  });
});
