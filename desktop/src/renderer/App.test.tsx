import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { App } from "./App";
import type { DesktopCommand, DesktopConnection } from "./connection";
import type { HistoricalSession, ServerEvent } from "./protocol";

const nativeAnimate = Object.getOwnPropertyDescriptor(Element.prototype, "animate");

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  if (nativeAnimate) Object.defineProperty(Element.prototype, "animate", nativeAnimate);
  else delete (Element.prototype as Partial<Element>).animate;
});

class FakeConnection implements DesktopConnection {
  private listener: ((event: ServerEvent) => void) | null = null;
  readonly commands: DesktopCommand[] = [];

  subscribe(listener: (event: ServerEvent) => void): () => void {
    this.listener = listener;
    return () => {
      this.listener = null;
    };
  }

  send(command: DesktopCommand): void {
    this.commands.push(command);
  }

  emit(event: ServerEvent): void {
    this.listener?.(event);
  }
}

describe("App", () => {
  it("shows the centered standalone Jotty mark", () => {
    const connection = new FakeConnection();
    render(<App connection={connection} />);

    expect(screen.getByRole("img", { name: "Jotty logo" })).toBeTruthy();
    expect(screen.getAllByRole("img")).toHaveLength(1);
    expect(screen.queryByText("Jotty")).toBeNull();
    expect(screen.queryByText("Live transcript")).toBeNull();
    expect(screen.queryByText("idle")).toBeNull();
  });

  it("sends explicit start and stop commands for the recording lifecycle", () => {
    const connection = new FakeConnection();
    const { container } = render(<App connection={connection} />);

    act(() => {
      connection.emit({
        type: "snapshot",
        status: "idle",
        utterances: [],
        preview: null,
        realtime_error: null,
        summary: null,
        activities: [],
        recording_directory: null
      });
      connection.emit(settingsChanged());
    });

    expect(container.querySelector(".empty-mark")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    expect(connection.commands).toEqual([{ type: "start_session" }]);

    act(() => connection.emit({ type: "state", status: "starting" }));
    expect(screen.getByText("Starting recording…")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Stop recording" })).toBeNull();

    act(() => connection.emit({ type: "state", status: "recording" }));
    fireEvent.click(screen.getByRole("button", { name: "Stop recording" }));
    expect(connection.commands).toEqual([{ type: "start_session" }, { type: "stop_session" }]);
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
        activities: [],
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
    expect(screen.getByText("Preparing recording artifacts…")).toBeTruthy();

    act(() => {
      connection.emit({
        type: "hermes_activity",
        stage: "summary",
        status: "running",
        message: "Reading transcript.txt"
      });
      connection.emit({
        type: "hermes_activity",
        stage: "summary",
        status: "running",
        message: "Writing summary"
      });
    });

    expect(screen.getByText("Reading transcript.txt")).toBeTruthy();
    expect(screen.getByText("Writing summary")).toBeTruthy();

    act(() => {
      connection.emit({
        type: "session_opened",
        session: historicalSession({ summary_markdown: "# Summary\n\n- Decision" })
      });
    });

    fireEvent.click(screen.getByRole("button", { name: "Summary" }));
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

  it("controls historical playback through the custom player", () => {
    const connection = new FakeConnection();
    const play = vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue();
    const pause = vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => undefined);
    render(<App connection={connection} />);

    act(() => connection.emit({ type: "session_opened", session: historicalSession() }));
    const audio = document.querySelector("audio")!;

    fireEvent.click(screen.getByRole("button", { name: "Play recording" }));
    expect(play).toHaveBeenCalledOnce();
    fireEvent.play(audio);
    fireEvent.click(screen.getByRole("button", { name: "Pause recording" }));
    expect(pause).toHaveBeenCalledOnce();
  });

  it("freezes the animated playback position without snapping back on pause", () => {
    const connection = new FakeConnection();
    const animations = [
      { cancel: vi.fn(), pause: vi.fn(), play: vi.fn() },
      { cancel: vi.fn(), pause: vi.fn(), play: vi.fn() }
    ];
    const animate = vi.fn()
      .mockReturnValueOnce(animations[0] as unknown as Animation)
      .mockReturnValueOnce(animations[1] as unknown as Animation);
    Object.defineProperty(Element.prototype, "animate", { configurable: true, value: animate });
    render(<App connection={connection} />);

    act(() => connection.emit({ type: "session_opened", session: historicalSession() }));
    const audio = document.querySelector("audio")!;
    const progress = document.querySelector<HTMLElement>(".playback-progress")!;
    Object.defineProperty(audio, "duration", { configurable: true, value: 60 });
    Object.defineProperty(audio, "currentTime", { configurable: true, value: 10 });
    Object.defineProperty(progress, "clientWidth", { configurable: true, value: 200 });

    fireEvent.playing(audio);
    expect(animate).toHaveBeenCalledTimes(2);
    fireEvent.pause(audio);

    expect(animations.every((animation) => animation.pause.mock.calls.length === 1)).toBe(true);
    expect(animations.every((animation) => animation.cancel.mock.calls.length === 0)).toBe(true);
  });

  it("blocks start for unavailable persisted settings and exposes compact controls", () => {
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
        activities: [],
        recording_directory: null
      });
      connection.emit({
        ...settingsChanged(),
        microphone_device_id: "missing-mic",
        microphone_available: false
      });
    });

    expect(screen.getByRole("button", { name: "Start recording" })).toHaveProperty("disabled", true);
    expect(screen.getByText("Selected microphone is unavailable: missing-mic")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    expect(screen.getByRole("option", { name: "Unavailable: missing-mic" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    expect(screen.queryByLabelText("Settings panel")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Settings" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "Always on top" }));
    expect(connection.commands.at(-1)).toEqual({ type: "change_always_on_top", enabled: true });
  });
  it("opens history, historical playback and tabs, and confirms destructive deletion", () => {
    const connection = new FakeConnection();
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(true);
    render(<App connection={connection} />);

    act(() => {
      connection.emit({ type: "snapshot", status: "idle", utterances: [], preview: null,
        realtime_error: null, summary: null, activities: [] });
      connection.emit(settingsChanged());
    });
    fireEvent.click(screen.getByRole("button", { name: "History" }));
    expect(connection.commands.at(-1)).toEqual({ type: "list_sessions" });

    act(() => connection.emit({ type: "sessions_listed", sessions: [historicalSession()] }));
    fireEvent.click(screen.getByRole("button", { name: "History" }));
    expect(screen.queryByLabelText("Recording history")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "History" }));
    fireEvent.click(screen.getByRole("button", { name: /Planning/ }));
    expect(connection.commands.at(-1)).toEqual({ type: "open_session", id: "4b119ce6-d02b-41f7-9368-433f59db56a7" });

    act(() => connection.emit({ type: "session_opened", session: historicalSession() }));
    expect(screen.getByText("Discuss roadmap")).toBeTruthy();
    expect(document.querySelector("audio")?.getAttribute("src")).toContain("/audio");
    expect(screen.getByRole("button", { name: "Play recording" })).toBeTruthy();
    expect(screen.getByRole("slider", { name: "Playback position" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Rename" }));
    const title = screen.getByRole("textbox", { name: "Recording title" });
    fireEvent.change(title, { target: { value: "Roadmap review" } });
    fireEvent.keyDown(title, { key: "Enter" });
    expect(connection.commands.at(-1)).toEqual({
      type: "rename_session",
      id: "4b119ce6-d02b-41f7-9368-433f59db56a7",
      title: "Roadmap review"
    });
    fireEvent.click(screen.getByRole("button", { name: "Start a new recording" }));
    expect(connection.commands.at(-1)).toEqual({ type: "start_session" });
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(confirm).toHaveBeenCalledWith(expect.stringContaining("local recording files"));
    expect(connection.commands.at(-1)).toEqual({ type: "delete_session", id: "4b119ce6-d02b-41f7-9368-433f59db56a7" });
  });

  it("blocks history navigation while a session is active", () => {
    const connection = new FakeConnection();
    render(<App connection={connection} />);
    act(() => connection.emit({ type: "state", status: "recording" }));
    expect(screen.getByRole("button", { name: "History" })).toHaveProperty("disabled", true);
  });
});

function historicalSession(overrides: Partial<HistoricalSession> = {}): HistoricalSession {
  return {
    id: "4b119ce6-d02b-41f7-9368-433f59db56a7",
    title: "Planning",
    status: "completed",
    failure: null,
    started_at: "2026-10-03T09:00:00Z",
    completed_at: "2026-10-03T09:01:00Z",
    duration_ms: 60_000,
    transcript_chunks: [{ position: 0, speaker: "1", text: "Discuss roadmap", start_ms: 0, end_ms: 10 }],
    transcript_available: true,
    summary_markdown: "# Summary",
    playback_url: "http://127.0.0.1:4765/sessions/4b119ce6-d02b-41f7-9368-433f59db56a7/audio",
    contexts: [],
    ...overrides
  };
}

function settingsChanged(): ServerEvent & { type: "settings_changed" } {
  return {
    type: "settings_changed",
    always_on_top: false,
    microphone_device_id: null,
    microphone_available: true,
    microphones: [{ id: "mic-1", name: "Desk Mic" }],
    contexts: [],
    error: null
  };
}
