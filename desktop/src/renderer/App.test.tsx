import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { App } from "./App";
import type { DesktopConnection } from "./connection";
import type { ServerEvent } from "./protocol";

afterEach(cleanup);

class FakeConnection implements DesktopConnection {
  private listener: ((event: ServerEvent) => void) | null = null;
  readonly commands: Array<{ type: "start" | "stop" }> = [];

  subscribe(listener: (event: ServerEvent) => void): () => void {
    this.listener = listener;
    return () => {
      this.listener = null;
    };
  }

  send(command: { type: "start" | "stop" }): void {
    this.commands.push(command);
  }

  emit(event: ServerEvent): void {
    this.listener?.(event);
  }
}

describe("App", () => {
  it("sends explicit start and stop commands for the recording lifecycle", () => {
    const connection = new FakeConnection();
    render(<App connection={connection} />);

    act(() => {
      connection.emit({
        type: "snapshot",
        status: "idle",
        utterances: [],
        preview: null,
        realtime_error: null,
        summary: null,
        recording_directory: null
      });
    });

    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    expect(connection.commands).toEqual([{ type: "start" }]);

    act(() => connection.emit({ type: "state", status: "starting" }));
    expect(screen.getByText("Starting recording…")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Stop recording" })).toBeNull();

    act(() => connection.emit({ type: "state", status: "recording" }));
    fireEvent.click(screen.getByRole("button", { name: "Stop recording" }));
    expect(connection.commands).toEqual([{ type: "start" }, { type: "stop" }]);
  });

  it("renders live transcript updates and the completed Markdown summary", () => {
    const connection = new FakeConnection();
    render(<App connection={connection} />);

    act(() => {
      connection.emit({
        type: "snapshot",
        status: "recording",
        utterances: [],
        preview: null,
        realtime_error: null,
        summary: null,
        recording_directory: null
      });
      connection.emit({
        type: "utterance_completed",
        chunks: [{ speaker: "1", text: "System message", start_ms: 0, end_ms: 10 }]
      });
      connection.emit({
        type: "transcription_previewed",
        chunks: [{ speaker: "2", text: "Draft reply", start_ms: 10, end_ms: 20 }]
      });
    });

    expect(screen.getByText("System message")).toBeTruthy();
    expect(screen.getByText("Draft reply")).toBeTruthy();

    act(() => {
      connection.emit({
        type: "realtime_transcription_failed",
        source: "system",
        reason: ":premature_close"
      });
    });

    expect(screen.getByText("Live transcription stopped: system: :premature_close")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Stop recording" })).toBeTruthy();

    act(() => connection.emit({ type: "state", status: "stopping" }));
    expect(screen.getByText("Generating summary…")).toBeTruthy();

    act(() => {
      connection.emit({
        type: "summary_ready",
        markdown: "# Summary\n\n- Decision",
        recording_directory: "/recording"
      });
    });

    expect(screen.getByRole("heading", { name: "Summary" })).toBeTruthy();
    expect(screen.getByText("Decision")).toBeTruthy();
  });

  it("keeps the newest transcript message visible", () => {
    const connection = new FakeConnection();
    render(<App connection={connection} />);
    const transcript = screen.getByLabelText("Transcript");
    Object.defineProperty(transcript, "scrollHeight", { value: 480 });

    act(() => {
      connection.emit({
        type: "utterance_completed",
        chunks: [{ speaker: "1", text: "Newest message", start_ms: 20, end_ms: 30 }]
      });
    });

    expect(transcript.scrollTop).toBe(480);
  });
});
