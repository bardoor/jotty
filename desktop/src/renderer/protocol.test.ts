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
          source: "system",
          chunks: [{ speaker: "1", text: "Welcome", start_ms: 0, end_ms: 10 }]
        }
      ],
      previews: {
        system: null,
        microphone: {
          type: "transcription_previewed",
          source: "microphone",
          chunks: [{ speaker: "1", text: "Hello", start_ms: 10, end_ms: 20 }]
        }
      },
      realtime_error: null,
      summary: null,
      recording_directory: null
    });

    expect(state.status).toBe("recording");
    expect(state.utterances[0].chunks[0].text).toBe("Welcome");
    expect(state.previews.microphone?.chunks[0].text).toBe("Hello");
  });

  it("replaces provisional text with the completed utterance", () => {
    const previewed = reduceServerEvent(initialState, {
      type: "transcription_previewed",
      source: "system",
      chunks: [{ speaker: "1", text: "Draft", start_ms: 0, end_ms: 10 }]
    });

    const completed = reduceServerEvent(previewed, {
      type: "utterance_completed",
      source: "system",
      chunks: [{ speaker: "1", text: "Final", start_ms: 0, end_ms: 12 }]
    });

    expect(completed.previews.system).toBeNull();
    expect(completed.utterances.at(-1)?.chunks[0].text).toBe("Final");
  });

  it("tracks recording lifecycle, summary, and failure events", () => {
    const starting = reduceServerEvent(initialState, { type: "state", status: "starting" });
    const recording = reduceServerEvent(starting, { type: "state", status: "recording" });
    const completed = reduceServerEvent(recording, {
      type: "summary_ready",
      markdown: "# Summary",
      recording_directory: "/recording"
    });
    const failed = reduceServerEvent(initialState, { type: "failed", reason: "capture stopped" });

    expect(starting.status).toBe("starting");
    expect(recording.status).toBe("recording");
    expect(completed).toMatchObject({
      status: "completed",
      summary: "# Summary",
      recordingDirectory: "/recording"
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
});
