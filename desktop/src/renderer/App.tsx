import { useEffect, useReducer, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";

import type { DesktopConnection } from "./connection";
import {
  initialState, reduceServerEvent, type DesktopSettings, type GlobalContext,
  type HermesActivity, type HistoricalSession, type SessionMetadata, type TranscriptionEvent
} from "./protocol";

interface AppProps { connection: DesktopConnection; }

export function App({ connection }: AppProps) {
  const [state, dispatch] = useReducer(reduceServerEvent, initialState);
  const [settingsVisible, setSettingsVisible] = useState(false);
  const [historyVisible, setHistoryVisible] = useState(false);
  const [detailTab, setDetailTab] = useState<"transcript" | "summary">("transcript");
  const conversation = useRef<HTMLElement>(null);
  const active = ["starting", "recording", "stopping"].includes(state.status);

  useEffect(() => connection.subscribe(dispatch), [connection]);
  useEffect(() => { if (state.settings) window.jotty?.setAlwaysOnTop(state.settings.alwaysOnTop); }, [state.settings?.alwaysOnTop]);
  useEffect(() => {
    if (conversation.current && !state.selectedSession) conversation.current.scrollTop = conversation.current.scrollHeight;
  }, [state.preview, state.utterances, state.selectedSession]);

  const openHistory = () => {
    if (active) return;
    if (historyVisible) {
      setHistoryVisible(false);
    } else {
      setSettingsVisible(false);
      setHistoryVisible(true);
      connection.send({ type: "list_sessions" });
    }
  };

  const toggleSettings = () => {
    setHistoryVisible(false);
    setSettingsVisible((visible) => !visible);
  };

  return (
    <div className="app">
      <header>
        <span className="titlebar-space" aria-hidden="true" />
        <span className="header-logo" role="img" aria-label="Jotty logo" />
        <div className="header-actions">
          <button className="header-button history-button" type="button" disabled={active} onClick={openHistory}>History</button>
          <button className="header-button settings-button" type="button" aria-label="Settings" onClick={toggleSettings}>⚙</button>
        </div>
      </header>
      <main>
        {state.selectedSession ? (
          <SessionDetail session={state.selectedSession} tab={detailTab} setTab={setDetailTab}
            connection={connection} />
        ) : (
          <LiveView state={state} connection={connection} conversation={conversation} />
        )}

        {historyVisible && !active && (
          <HistoryDrawer sessions={state.sessions} connection={connection}
            onClose={() => setHistoryVisible(false)} onOpen={() => { setHistoryVisible(false); setDetailTab("transcript"); }} />
        )}
        {settingsVisible && (
          <SettingsPanel settings={state.settings} error={state.settingsError} connection={connection}
            onClose={() => setSettingsVisible(false)} />
        )}
        {state.commandError && <div className="command-error">{state.commandError}</div>}
      </main>
    </div>
  );
}

function LiveView({ state, connection, conversation }: {
  state: typeof initialState; connection: DesktopConnection; conversation: React.RefObject<HTMLElement | null>;
}) {
  const blocker = settingsBlocker(state.settings);
  return <>
    <section className="conversation" aria-label="Transcript" ref={conversation}>
      {state.status === "connecting" && <div className="empty-state">Connecting to Jotty…</div>}
      {["idle", "completed", "failed"].includes(state.status) && state.utterances.length === 0 && (
        <div className="empty-state"><h1>Ready when you are</h1>
          <p>Capture system audio and your microphone in one private local session.</p>
          {blocker && <div className="settings-status">{blocker}</div>}
          <button className="primary start" type="button" disabled={blocker !== null}
            onClick={() => connection.send({ type: "start_session" })}><span className="record-icon" />Start recording</button>
        </div>
      )}
      {state.status === "starting" && <div className="empty-state"><h1>Starting recording…</h1><p>Waiting for audio capture.</p></div>}
      {state.utterances.map((event, index) => <TranscriptMessage event={event} key={index} />)}
      {state.preview && <TranscriptMessage event={state.preview} provisional />}
      {state.realtimeError && <div className="error-banner">Live transcription stopped: {state.realtimeError}</div>}
      {state.error && <div className="error-banner">{state.error}</div>}
    </section>
    {state.status === "recording" && <div className="controls"><button className="primary stop" type="button"
      onClick={() => connection.send({ type: "stop_session" })}><span className="stop-icon" />Stop recording</button></div>}
    {state.status === "stopping" && <HermesProgress activities={state.activities} />}
  </>;
}

function HermesProgress({ activities }: { activities: HermesActivity[] }) {
  return <div className="working" aria-live="polite">
    {activities.length === 0 ? <span>Preparing recording artifacts…</span> : (
      <ol>{activities.map((activity, index) =>
        <li className={activity.status} key={`${index}-${activity.stage}-${activity.message}`}>
          <span>{activity.message}</span>
        </li>)}</ol>
    )}
  </div>;
}

function HistoryDrawer({ sessions, connection, onClose, onOpen }: {
  sessions: SessionMetadata[]; connection: DesktopConnection; onClose: () => void; onOpen: () => void;
}) {
  return <aside className="history-drawer" aria-label="Recording history">
    <div className="panel-head"><h2>History</h2><button className="close" type="button" onClick={onClose}>×</button></div>
    {sessions.length === 0 && <div className="unavailable">No recordings yet.</div>}
    {sessions.map((session) => <button className="history-row" type="button" key={session.id} onClick={() => {
      connection.send({ type: "open_session", id: session.id }); onOpen();
    }}><strong>{session.title}</strong><span>{formatDate(session.started_at)} · {formatDuration(session.duration_ms)}</span>
      <em className={`session-status ${session.status}`}>{session.status}</em></button>)}
  </aside>;
}

function SessionDetail({ session, tab, setTab, connection }: {
  session: HistoricalSession; tab: "transcript" | "summary"; setTab: (tab: "transcript" | "summary") => void;
  connection: DesktopConnection;
}) {
  const [renaming, setRenaming] = useState(false);
  const [title, setTitle] = useState(session.title);

  useEffect(() => {
    setTitle(session.title);
    setRenaming(false);
  }, [session.id, session.title]);

  const rename = () => {
    const nextTitle = title.trim();
    if (nextTitle === "") return;
    connection.send({ type: "rename_session", id: session.id, title: nextTitle });
    setRenaming(false);
  };
  const remove = () => {
    if (window.confirm("Delete this recording? This permanently removes its local recording files.")) {
      connection.send({ type: "delete_session", id: session.id });
    }
  };

  return <section className="session-detail">
    <div className="session-heading"><div className="session-title">
      {renaming ? <form className="rename-form" onSubmit={(event) => { event.preventDefault(); rename(); }}>
        <input aria-label="Recording title" autoFocus value={title} onChange={(event) => setTitle(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") { event.preventDefault(); rename(); }
            if (event.key === "Escape") { setTitle(session.title); setRenaming(false); }
          }} />
        <button type="submit" disabled={title.trim() === ""}>Save</button>
        <button type="button" onClick={() => { setTitle(session.title); setRenaming(false); }}>Cancel</button>
      </form> : <h1>{session.title}</h1>}
      <p>{formatDate(session.started_at)} · {session.status} · {formatDuration(session.duration_ms)}</p></div>
      <div className="detail-actions">{!renaming && <button type="button" onClick={() => setRenaming(true)}>Rename</button>}
        <button type="button" onClick={remove}>Delete</button></div></div>
    {session.playback_url ? <AudioPlayer src={session.playback_url} /> : <div className="unavailable">Playback unavailable</div>}
    <div className="tabs"><button className={tab === "transcript" ? "active" : ""} type="button" onClick={() => setTab("transcript")}>Transcript</button>
      <button className={tab === "summary" ? "active" : ""} type="button" onClick={() => setTab("summary")}>Summary</button></div>
    <div className="detail-body">{tab === "transcript" ? (
      session.transcript_chunks.length > 0 ? session.transcript_chunks.map((chunk, index) =>
        <article className="historical-chunk" key={`${chunk.position ?? index}`}><b>Speaker {chunk.speaker}</b><p>{chunk.text}</p></article>)
        : <div className="unavailable">Transcript unavailable</div>
    ) : session.summary_markdown ? <ReactMarkdown>{session.summary_markdown}</ReactMarkdown>
      : <div className="unavailable">Summary unavailable</div>}</div>
    <button className="primary new-recording" type="button" onClick={() => connection.send({ type: "start_session" })}>Start a new recording</button>
  </section>;
}

function AudioPlayer({ src }: { src: string }) {
  const audio = useRef<HTMLAudioElement>(null);
  const progressTrack = useRef<HTMLDivElement>(null);
  const progressFill = useRef<HTMLDivElement>(null);
  const progressThumb = useRef<HTMLSpanElement>(null);
  const progressAnimations = useRef<Animation[]>([]);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);

  useEffect(() => {
    return () => progressAnimations.current.forEach((animation) => animation.cancel());
  }, []);

  const cancelProgressAnimation = () => {
    progressAnimations.current.forEach((animation) => animation.cancel());
    progressAnimations.current = [];
  };

  const setVisualPosition = (element: HTMLAudioElement, time = element.currentTime) => {
    const safeDuration = Number.isFinite(element.duration) ? element.duration : 0;
    const ratio = safeDuration > 0 ? Math.min(Math.max(time / safeDuration, 0), 1) : 0;
    if (progressFill.current) progressFill.current.style.transform = `scaleX(${ratio})`;
    if (progressThumb.current && progressTrack.current) {
      progressThumb.current.style.transform = `translate3d(${ratio * progressTrack.current.clientWidth}px, 0, 0)`;
    }
  };

  const stopProgressAnimation = (element: HTMLAudioElement) => {
    cancelProgressAnimation();
    setVisualPosition(element);
  };

  const pauseProgressAnimation = () => {
    progressAnimations.current.forEach((animation) => animation.pause());
  };

  const resumeProgressAnimation = (element: HTMLAudioElement) => {
    if (progressAnimations.current.length === 0) startProgressAnimation(element);
    else progressAnimations.current.forEach((animation) => animation.play());
  };

  const startProgressAnimation = (element: HTMLAudioElement) => {
    stopProgressAnimation(element);
    const safeDuration = Number.isFinite(element.duration) ? element.duration : 0;
    const trackWidth = progressTrack.current?.clientWidth ?? 0;
    const startRatio = safeDuration > 0 ? Math.min(Math.max(element.currentTime / safeDuration, 0), 1) : 0;
    const remainingMilliseconds = safeDuration > element.currentTime
      ? ((safeDuration - element.currentTime) / element.playbackRate) * 1_000
      : 0;
    if (!progressFill.current || !progressThumb.current || trackWidth === 0 || remainingMilliseconds === 0) return;

    const timing: KeyframeAnimationOptions = { duration: remainingMilliseconds, easing: "linear", fill: "forwards" };
    progressAnimations.current = [
      progressFill.current.animate([
        { transform: `scaleX(${startRatio})` },
        { transform: "scaleX(1)" }
      ], timing),
      progressThumb.current.animate([
        { transform: `translate3d(${startRatio * trackWidth}px, 0, 0)` },
        { transform: `translate3d(${trackWidth}px, 0, 0)` }
      ], timing)
    ];
  };

  const togglePlayback = () => {
    if (!audio.current) return;

    if (!playing) {
      void audio.current.play().catch(() => setPlaying(false));
    } else {
      audio.current.pause();
    }
  };

  const seek = (value: number) => {
    if (!audio.current) return;
    audio.current.currentTime = value;
    setCurrentTime(value);
    setVisualPosition(audio.current, value);
  };

  const playbackPaused = (element: HTMLAudioElement) => {
    pauseProgressAnimation();
    setCurrentTime(element.currentTime);
    setPlaying(false);
  };

  const playbackEnded = (element: HTMLAudioElement) => {
    stopProgressAnimation(element);
    setCurrentTime(element.currentTime);
    setPlaying(false);
  };

  return <div className="audio-player">
    <audio ref={audio} preload="metadata" src={src} onPlay={() => setPlaying(true)}
      onPlaying={(event) => resumeProgressAnimation(event.currentTarget)}
      onWaiting={pauseProgressAnimation}
      onSeeking={(event) => stopProgressAnimation(event.currentTarget)}
      onSeeked={(event) => { if (!event.currentTarget.paused) startProgressAnimation(event.currentTarget); }}
      onRateChange={(event) => { if (!event.currentTarget.paused) startProgressAnimation(event.currentTarget); }}
      onPause={(event) => playbackPaused(event.currentTarget)} onEnded={(event) => playbackEnded(event.currentTarget)}
      onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
      onLoadedMetadata={(event) => { setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0); setVisualPosition(event.currentTarget); }} />
    <button className={`playback-toggle${playing ? " playing" : ""}`} type="button"
      aria-label={playing ? "Pause recording" : "Play recording"} onClick={togglePlayback}>
      <span aria-hidden="true" />
    </button>
    <div className="playback-track">
      <div className="playback-scrubber">
        <div className="playback-progress" ref={progressTrack} aria-hidden="true">
          <div className="playback-fill" ref={progressFill} />
          <span className="playback-thumb" ref={progressThumb} />
        </div>
        <input aria-label="Playback position" type="range" min="0" max={duration || 0} step="any" value={currentTime}
          onChange={(event) => seek(Number(event.target.value))} />
      </div>
      <div className="playback-time"><span>{formatPlaybackTime(currentTime)}</span><span>{duration ? formatPlaybackTime(duration) : "—:—"}</span></div>
    </div>
  </div>;
}

function SettingsPanel({ settings, error, connection, onClose }: {
  settings: DesktopSettings | null; error: string | null; connection: DesktopConnection; onClose: () => void;
}) {
  if (!settings) return <aside className="settings-panel"><div className="loading">Loading settings…</div></aside>;
  const addContext = async () => { const directory = await window.jotty.pickContextDirectory(); if (directory) connection.send({ type: "add_context", ...directory }); };
  const moveContext = (context: GlobalContext, offset: number) => {
    const ids = settings.contexts.map((item) => item.id); const index = ids.indexOf(context.id); const target = index + offset;
    if (target < 0 || target >= ids.length) return; [ids[index], ids[target]] = [ids[target], ids[index]];
    connection.send({ type: "reorder_contexts", context_ids: ids });
  };
  const missing = settings.microphoneDeviceId !== null && !settings.microphoneAvailable ? settings.microphoneDeviceId : null;
  return <aside className="settings-panel" aria-label="Settings panel"><div className="panel-head"><h2>Settings</h2><button className="close" type="button" onClick={onClose}>×</button></div>
    {error && <div className="settings-error">{error}</div>}
    <label className="toggle-row"><span>Always on top</span><input type="checkbox" checked={settings.alwaysOnTop}
      onChange={(event) => connection.send({ type: "change_always_on_top", enabled: event.target.checked })} /></label>
    <label className="field-label" htmlFor="microphone">Microphone</label><div className="select-row"><select id="microphone" value={settings.microphoneDeviceId ?? ""}
      onChange={(event) => connection.send({ type: "change_microphone", microphone_device_id: event.target.value || null })}>
      <option value="">System Default</option>{missing && <option value={missing}>Unavailable: {missing}</option>}
      {settings.microphones.map((microphone) => <option value={microphone.id} key={microphone.id}>{microphone.name}</option>)}</select>
      <button type="button" className="icon-button" aria-label="Refresh microphones" onClick={() => connection.send({ type: "list_microphones" })}>↻</button></div>
    <div className="contexts-head"><span>Contexts</span><button type="button" onClick={() => void addContext()}>Add folder</button></div>
    {settings.contexts.map((context, index) => <div className={`context-row${context.available ? "" : " unavailable"}`} key={context.id}>
      <div className="context-name" title={context.path}>{context.name}{!context.available && <span>Unavailable</span>}</div><div className="context-actions">
      <button type="button" disabled={index === 0} onClick={() => moveContext(context, -1)}>↑</button><button type="button" disabled={index === settings.contexts.length - 1} onClick={() => moveContext(context, 1)}>↓</button>
      <button type="button" onClick={() => connection.send({ type: "remove_context", id: context.id })}>×</button></div></div>)}
  </aside>;
}

function TranscriptMessage({ event, provisional = false }: { event: TranscriptionEvent; provisional?: boolean }) {
  return <>{event.chunks.map((chunk, index) => <article className={`message left${provisional ? " provisional" : ""}`} key={`${chunk.speaker}-${index}`}>
    <div className="meta">Speaker {chunk.speaker}</div><div className="bubble">{chunk.text}</div></article>)}</>;
}
function settingsBlocker(settings: DesktopSettings | null): string | null {
  if (!settings) return "Loading settings…"; if (!settings.microphoneAvailable) return `Selected microphone is unavailable: ${settings.microphoneDeviceId}`;
  const context = settings.contexts.find((item) => !item.available); return context ? `Context folder is unavailable: ${context.path}` : null;
}
function formatDate(value: string): string { return new Date(value).toLocaleString(); }
function formatPlaybackTime(value: number): string {
  const seconds = Math.max(0, Math.floor(value));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
function formatDuration(value: number | null): string {
  if (value === null) return "—"; const total = Math.floor(value / 1000); return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}
