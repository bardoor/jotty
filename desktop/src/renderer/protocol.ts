export type Source = "system" | "microphone";
export type Status = "connecting" | "idle" | "starting" | "recording" | "stopping" | "completed" | "failed";

export interface TranscriptChunk {
  speaker: string;
  text: string;
  start_ms: number;
  end_ms: number;
}

export interface TranscriptionEvent {
  type: "transcription_previewed" | "utterance_completed";
  chunks: TranscriptChunk[];
}

export interface SnapshotEvent {
  type: "snapshot";
  status: Exclude<Status, "connecting">;
  utterances: TranscriptionEvent[];
  preview: TranscriptionEvent | null;
  realtime_error: string | null;
  summary: string | null;
  recording_directory: string | null;
}

export interface StateEvent {
  type: "state";
  status: "starting" | "recording" | "stopping";
}

export interface SummaryReadyEvent {
  type: "summary_ready";
  markdown: string;
  recording_directory: string;
}

export interface FailedEvent {
  type: "failed";
  reason: string;
}

export interface RealtimeTranscriptionFailedEvent {
  type: "realtime_transcription_failed";
  source: Source | null;
  reason: string;
}

export type ServerEvent =
  | SnapshotEvent
  | TranscriptionEvent
  | StateEvent
  | SummaryReadyEvent
  | RealtimeTranscriptionFailedEvent
  | FailedEvent;

export interface DesktopState {
  status: Status;
  utterances: TranscriptionEvent[];
  preview: TranscriptionEvent | null;
  summary: string | null;
  recordingDirectory: string | null;
  realtimeError: string | null;
  error: string | null;
}

export const initialState: DesktopState = {
  status: "connecting",
  utterances: [],
  preview: null,
  summary: null,
  recordingDirectory: null,
  realtimeError: null,
  error: null
};

export function reduceServerEvent(state: DesktopState, event: ServerEvent): DesktopState {
  switch (event.type) {
    case "snapshot":
      return {
        status: event.status,
        utterances: event.utterances,
        preview: event.preview,
        realtimeError: event.realtime_error,
        summary: event.summary,
        recordingDirectory: event.recording_directory,
        error: null
      };
    case "transcription_previewed":
      return {
        ...state,
        preview: event
      };
    case "utterance_completed":
      return {
        ...state,
        utterances: [...state.utterances, event],
        preview: null
      };
    case "state":
      return { ...state, status: event.status, error: null };
    case "summary_ready":
      return {
        ...state,
        status: "completed",
        summary: event.markdown,
        recordingDirectory: event.recording_directory
      };
    case "realtime_transcription_failed":
      return {
        ...state,
        realtimeError: `${event.source ?? "transport"}: ${event.reason}`
      };
    case "failed":
      return { ...state, status: "failed", error: event.reason };
  }
}
