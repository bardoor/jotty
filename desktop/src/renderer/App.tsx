import { useEffect, useReducer, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";

import type { DesktopConnection } from "./connection";
import { initialState, reduceServerEvent, type TranscriptionEvent } from "./protocol";

interface AppProps {
  connection: DesktopConnection;
}

export function App({ connection }: AppProps) {
  const [state, dispatch] = useReducer(reduceServerEvent, initialState);
  const [summaryVisible, setSummaryVisible] = useState(true);
  const conversation = useRef<HTMLElement>(null);

  useEffect(() => connection.subscribe(dispatch), [connection]);

  useEffect(() => {
    if (state.status === "stopping" || state.status === "completed") {
      setSummaryVisible(true);
    }
  }, [state.status]);

  useEffect(() => {
    conversation.current!.scrollTop = conversation.current!.scrollHeight;
  }, [state.previews, state.utterances]);

  const previews = [state.previews.system, state.previews.microphone].filter(
    (event): event is TranscriptionEvent => event !== null
  );
  const summaryOpen = summaryVisible && (state.status === "stopping" || state.summary !== null);

  return (
    <div className={`app${summaryOpen ? " summary-open" : ""}`}>
      <header>
        <div className="brand">
          <span className="mark">j</span>
          Jotty
        </div>
        <div className="title">
          <strong>Live transcript</strong>
          <span>{state.status === "recording" ? "Recording" : "Meeting notes"}</span>
        </div>
        <div className="status">
          {state.status === "recording" && <span className="recording-dot" />}
          <span>{state.status}</span>
        </div>
      </header>
      <main>
        <section className="conversation" aria-label="Transcript" ref={conversation}>
          {state.status === "connecting" && <div className="empty-state">Connecting to Jotty…</div>}
          {state.status === "idle" && state.utterances.length === 0 && (
            <div className="empty-state">
              <span className="empty-mark">j</span>
              <h1>Ready when you are</h1>
              <p>Capture system audio and your microphone in one private local session.</p>
              <button
                className="primary start"
                type="button"
                onClick={() => connection.send({ type: "start" })}
              >
                <span className="record-icon" />
                Start recording
              </button>
            </div>
          )}
          {state.status === "starting" && (
            <div className="empty-state">
              <span className="empty-mark">j</span>
              <h1>Starting recording…</h1>
              <p>Waiting for system audio and microphone capture to become ready.</p>
            </div>
          )}

          {state.utterances.map((event, index) => (
            <TranscriptMessage event={event} key={`${event.source}-${index}`} />
          ))}
          {previews.map((event) => (
            <TranscriptMessage event={event} key={`preview-${event.source}`} provisional />
          ))}

          {state.realtimeError && (
            <div className="error-banner">Live transcription stopped: {state.realtimeError}</div>
          )}
          {state.error && <div className="error-banner">{state.error}</div>}
        </section>

        {state.status === "recording" && (
          <div className="controls">
            <button
              className="primary stop"
              type="button"
              onClick={() => connection.send({ type: "stop" })}
            >
              <span className="stop-icon" />
              Stop recording
            </button>
          </div>
        )}

        <button
          className="scrim"
          aria-label="Close summary"
          type="button"
          onClick={() => setSummaryVisible(false)}
        />
        <aside className={`summary${state.status === "stopping" ? " pending" : ""}`}>
          {state.status === "stopping" ? (
            <div className="loading">Generating summary…</div>
          ) : (
            state.summary && (
              <div className="summary-content">
                <div className="summary-head">
                  <div>
                    <div className="eyebrow">Meeting complete</div>
                  </div>
                  <button
                    className="close"
                    type="button"
                    aria-label="Close summary"
                    onClick={() => setSummaryVisible(false)}
                  >
                    ×
                  </button>
                </div>
                <ReactMarkdown>{state.summary}</ReactMarkdown>
                <div className="complete">
                  <span className="check">✓</span>
                  Transcript and summary saved
                </div>
              </div>
            )
          )}
        </aside>
      </main>
    </div>
  );
}

function TranscriptMessage({
  event,
  provisional = false
}: {
  event: TranscriptionEvent;
  provisional?: boolean;
}) {
  const microphone = event.source === "microphone";

  return (
    <article className={`message ${microphone ? "right" : "left"}${provisional ? " provisional" : ""}`}>
      <div className="meta">{microphone ? "You · Microphone" : "System audio"}</div>
      <div className="bubble">
        {event.chunks.map((chunk) => chunk.text).join(" ")}
        {provisional && (
          <span className="typing" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
        )}
      </div>
    </article>
  );
}
