import { describe, expect, it } from "vitest";

import { initialState, reduceServerEvent } from "./protocol";

describe("desktop protocol state", () => {
  it("hydrates the renderer from the server snapshot", () => {
    const state = reduceServerEvent(initialState, {
      type: "snapshot",
      status: "recording",
      utterances: [
        {
          type: "utterance_completed",
          chunks: [{ speaker: "1", text: "Welcome", start_ms: 0, end_ms: 10 }]
        }
      ],
      preview: {
        type: "transcription_previewed",
        chunks: [{ speaker: "2", text: "Hello", start_ms: 10, end_ms: 20 }]
      },
      realtime_error: null,
      summary: null,
      activities: [
        { stage: "summary", status: "running", message: "Writing summary" }
      ],
      recording_directory: null
    });

    expect(state.status).toBe("recording");
    expect(state.utterances[0].chunks[0].text).toBe("Welcome");
    expect(state.preview?.chunks[0].text).toBe("Hello");
    expect(state.activities.at(-1)?.message).toBe("Writing summary");
  });

  it("replaces provisional text with the completed utterance", () => {
    const previewed = reduceServerEvent(initialState, {
      type: "transcription_previewed",
      chunks: [{ speaker: "1", text: "Draft", start_ms: 0, end_ms: 10 }]
    });

    const completed = reduceServerEvent(previewed, {
      type: "utterance_completed",
      chunks: [{ speaker: "1", text: "Final", start_ms: 0, end_ms: 12 }]
    });

    expect(completed.preview).toBeNull();
    expect(completed.utterances.at(-1)?.chunks[0].text).toBe("Final");
  });

  it("appends Hermes activity and resets it for a new session", () => {
    const active = reduceServerEvent(initialState, {
      type: "hermes_activity",
      stage: "summary",
      status: "running",
      message: "Reading transcript.txt"
    });

    expect(active.activities).toHaveLength(1);

    const starting = reduceServerEvent(active, { type: "state", status: "starting" });
    expect(starting.activities).toEqual([]);
  });

  it("tracks recording lifecycle, summary, and failure events", () => {
    const starting = reduceServerEvent(initialState, { type: "state", status: "starting" });
    const recording = reduceServerEvent(starting, { type: "state", status: "recording" });
    const completed = reduceServerEvent(recording, {
      type: "session_opened",
      session: {
        id: "4b119ce6-d02b-41f7-9368-433f59db56a7",
        title: "Planning",
        status: "completed",
        failure: null,
        started_at: "2026-10-03T09:00:00Z",
        completed_at: "2026-10-03T09:01:00Z",
        duration_ms: 60_000,
        transcript_chunks: [],
        transcript_available: true,
        summary_markdown: "# Summary",
        playback_url: "/sessions/id/audio",
        contexts: []
      }
    });
    const failed = reduceServerEvent(initialState, { type: "failed", reason: "capture stopped" });

    expect(starting.status).toBe("starting");
    expect(recording.status).toBe("recording");
    expect(completed).toMatchObject({
      status: "recording",
      selectedSession: { title: "Planning", summary_markdown: "# Summary" }
    });
    expect(failed).toMatchObject({ status: "failed", error: "capture stopped" });
  });

  it("retains a non-fatal realtime transcription failure while recording continues", () => {
    const recording = reduceServerEvent(initialState, { type: "state", status: "recording" });
    const degraded = reduceServerEvent(recording, {
      type: "realtime_transcription_failed",
      source: "microphone",
      reason: ":premature_close"
    });

    expect(degraded).toMatchObject({
      status: "recording",
      realtimeError: "microphone: :premature_close"
    });
  });

  it("loads persisted settings and unavailable resources", () => {
    const state = reduceServerEvent(initialState, {
      type: "settings_changed",
      always_on_top: true,
      microphone_device_id: "missing",
      microphone_available: false,
      microphones: [],
      contexts: [{ id: "70bba3d8-cb9f-488a-b62e-da6247fc51b5", name: "gone", path: "/gone", position: 0, available: false }],
      error: null
    });

    expect(state.settings).toMatchObject({
      alwaysOnTop: true,
      microphoneDeviceId: "missing",
      microphoneAvailable: false
    });
    expect(state.settings?.contexts[0].available).toBe(false);
  });
});
