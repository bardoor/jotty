export type Source = "system" | "microphone";
export type Status = "connecting" | "idle" | "starting" | "recording" | "stopping" | "completed" | "failed";
export type SessionStatus = "recording" | "completed" | "failed";

export interface TranscriptChunk {
  position?: number;
  speaker: string;
  text: string;
  start_ms: number;
  end_ms: number;
}

export interface TranscriptionEvent {
  type: "transcription_previewed" | "utterance_completed";
  chunks: TranscriptChunk[];
}

export interface SessionMetadata {
  id: string;
  title: string;
  status: SessionStatus;
  failure: string | null;
  started_at: string;
  completed_at: string | null;
  duration_ms: number | null;
}

export interface HistoricalSession extends SessionMetadata {
  transcript_chunks: TranscriptChunk[];
  transcript_available: boolean;
  summary_markdown: string | null;
  playback_url: string | null;
  contexts: Array<{ context_id: string | null; position: number; name: string; path: string }>;
}

export interface SnapshotEvent {
  type: "snapshot";
  status: Exclude<Status, "connecting">;
  utterances: TranscriptionEvent[];
  preview: TranscriptionEvent | null;
  realtime_error: string | null;
  summary: string | null;
  activities: HermesActivity[];
  recording_directory?: string | null;
}

export interface StateEvent { type: "state"; status: "connecting" | "starting" | "recording" | "stopping"; }
export interface HermesActivity {
  stage: "insight_classification" | "insight_search" | "summary";
  status: "started" | "running" | "completed" | "failed";
  message: string;
}
export interface HermesActivityEvent extends HermesActivity { type: "hermes_activity"; }
export interface SummaryReadyEvent { type: "summary_ready"; markdown: string; recording_directory: string; }
export interface FailedEvent { type: "failed"; reason: string; }
export interface RealtimeTranscriptionFailedEvent { type: "realtime_transcription_failed"; source: Source | null; reason: string; }
export interface SessionsListedEvent { type: "sessions_listed"; sessions: SessionMetadata[]; }
export interface SessionOpenedEvent { type: "session_opened"; session: HistoricalSession; }
export interface SessionRenamedEvent { type: "session_renamed"; session: SessionMetadata; }
export interface SessionDeletedEvent { type: "session_deleted"; id: string; }
export interface CommandRejectedEvent { type: "command_rejected"; command: string; reason: string; }

export interface Microphone { id: string; name: string; }
export interface GlobalContext { id: string; name: string; path: string; position: number; available: boolean; }
export interface SettingsChangedEvent {
  type: "settings_changed";
  always_on_top: boolean;
  microphone_device_id: string | null;
  microphone_available: boolean;
  microphones: Microphone[];
  contexts: GlobalContext[];
  error: string | null;
}
export interface SettingsInvalidEvent { type: "settings_invalid"; reason: string; }
export interface DesktopSettings {
  alwaysOnTop: boolean;
  microphoneDeviceId: string | null;
  microphoneAvailable: boolean;
  microphones: Microphone[];
  contexts: GlobalContext[];
}

export type ServerEvent = SnapshotEvent | TranscriptionEvent | StateEvent | SummaryReadyEvent |
  HermesActivityEvent | RealtimeTranscriptionFailedEvent | FailedEvent | SettingsChangedEvent | SettingsInvalidEvent |
  SessionsListedEvent | SessionOpenedEvent | SessionRenamedEvent | SessionDeletedEvent | CommandRejectedEvent;

export interface DesktopState {
  status: Status;
  utterances: TranscriptionEvent[];
  preview: TranscriptionEvent | null;
  summary: string | null;
  activities: HermesActivity[];
  realtimeError: string | null;
  error: string | null;
  settings: DesktopSettings | null;
  settingsError: string | null;
  sessions: SessionMetadata[];
  selectedSession: HistoricalSession | null;
  commandError: string | null;
}

export const initialState: DesktopState = {
  status: "connecting", utterances: [], preview: null, summary: null, activities: [], realtimeError: null,
  error: null, settings: null, settingsError: null, sessions: [], selectedSession: null, commandError: null
};

export function reduceServerEvent(state: DesktopState, event: ServerEvent): DesktopState {
  switch (event.type) {
    case "snapshot":
      return { ...state, status: event.status, utterances: event.utterances, preview: event.preview,
        realtimeError: event.realtime_error, summary: event.summary, activities: event.activities, error: null };
    case "transcription_previewed": return { ...state, preview: event };
    case "utterance_completed": return { ...state, utterances: [...state.utterances, event], preview: null };
    case "state":
      return event.status === "connecting"
        ? { ...state, status: "connecting" }
        : event.status === "starting"
        ? { ...state, status: event.status, selectedSession: null, utterances: [], preview: null,
          summary: null, activities: [], realtimeError: null, error: null, commandError: null }
        : event.status === "stopping"
        ? { ...state, status: event.status, selectedSession: null, activities: [], error: null, commandError: null }
        : { ...state, status: event.status, selectedSession: null, error: null, commandError: null };
    case "hermes_activity":
      return { ...state, activities: [...state.activities, event].slice(-20) };
    case "summary_ready": return { ...state, summary: event.markdown };
    case "realtime_transcription_failed": return { ...state, realtimeError: `${event.source ?? "transport"}: ${event.reason}` };
    case "failed": return { ...state, status: "failed", error: event.reason };
    case "settings_changed":
      return { ...state, settings: { alwaysOnTop: event.always_on_top,
        microphoneDeviceId: event.microphone_device_id, microphoneAvailable: event.microphone_available,
        microphones: event.microphones, contexts: event.contexts }, settingsError: event.error };
    case "settings_invalid": return { ...state, settingsError: event.reason };
    case "sessions_listed": return { ...state, sessions: event.sessions, commandError: null };
    case "session_opened":
      return { ...state, selectedSession: event.session,
        sessions: replaceSession(state.sessions, event.session),
        status: state.status === "stopping" ? event.session.status : state.status, commandError: null };
    case "session_renamed":
      return { ...state, sessions: replaceSession(state.sessions, event.session),
        selectedSession: state.selectedSession?.id === event.session.id
          ? { ...state.selectedSession, ...event.session } : state.selectedSession, commandError: null };
    case "session_deleted": {
      const selectedDeleted = state.selectedSession?.id === event.id;
      return { ...state, sessions: state.sessions.filter((session) => session.id !== event.id),
        selectedSession: selectedDeleted ? null : state.selectedSession,
        status: selectedDeleted ? "idle" : state.status,
        utterances: selectedDeleted ? [] : state.utterances,
        preview: selectedDeleted ? null : state.preview,
        commandError: null };
    }
    case "command_rejected": return { ...state, commandError: event.reason };
  }
}

function replaceSession(sessions: SessionMetadata[], session: SessionMetadata): SessionMetadata[] {
  return [session, ...sessions.filter((item) => item.id !== session.id)]
    .sort((left, right) => right.started_at.localeCompare(left.started_at));
}
