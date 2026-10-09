# Jotty roadmap

This roadmap records product direction, not release commitments. Items move into issues and milestones when their scope is ready for implementation.

## Done

### Acoustic echo cancellation

**Status:** Done

Jotty uses timestamp-aware WebRTC AEC with system audio as the render reference and the microphone as the capture input. The cleaned microphone is mixed with system audio into the one mono realtime stream sent to Soniox. Raw system and microphone recordings, the cleaned microphone, and the exact mixed playback audio are preserved as session artifacts.

### Compact fixed window and native title-bar spacing

**Status:** Done

The desktop app uses a compact fixed-width window with explicit spacing for the macOS window controls and a centered Jotty mark. Transcript and detail content scroll inside their own bounded regions rather than expanding the window.

### Always on top and settings

**Status:** Done

The backend-authoritative settings surface persists Always on top, microphone selection, and an ordered global list of context directories in SQLite. Unavailable selected resources block recording startup instead of silently falling back.

### Session management

**Status:** In progress

SQLite-backed history can list, open, play, rename, and permanently delete completed sessions. Historical sessions expose transcript, summary, metadata, context snapshots, and the exact mixed `audio.m4a`. The current work includes repairing the desktop rename interaction and removing whole-window overflow from the historical detail view.

## Now

### Hermes-only agent runtime and transparent progress

**Status:** In progress

Move classification, context retrieval, and summary generation onto Hermes. Consume Hermes JSONL events as a typed stream and expose meaningful progress in the desktop UI instead of leaving a static “Finalizing recording…” message on screen. Show which bounded operation is starting, which tool is running, what safe target it is inspecting, whether it completed, and when Hermes begins writing the response. Do not expose file contents, credentials, raw tool output, or hidden reasoning.

## Next

### Session title templates

**Status:** Idea

Let each user configure a default recording-title template in Settings. Templates may contain documented placeholders such as `$weekday`, `$date`, and `$time`, which are resolved when a session is created. The settings UI should preview the resulting title and reject unknown or malformed placeholders. Escaping literal `$` characters and locale/time-zone behavior must be defined before implementation.

### Speaker names during a call

**Status:** Idea

Once stable diarized speaker identifiers appear, let the live UI ask for optional names with a small unobtrusive prompt such as “Who is Speaker 1?”. Persist labels separately from provider speaker identifiers and apply them consistently to live transcript, history, summary, and insights. Labels remain editable during and after the call; raw transcription evidence is not rewritten.

### Suggested speaker identification

**Status:** Idea

Add a background analyzer that detects explicit conversational evidence such as one participant addressing “Oleg” followed by another participant replying. It may suggest a mapping from a diarized speaker identifier to a human name, together with the supporting utterances. Inferred mappings must remain distinguishable from user-confirmed labels and must not silently assign identities when evidence is ambiguous.

### Unified live and historical session view

**Status:** Idea

Use the same session-detail design during recording and in history. Both modes should expose **Transcript**, **Summary**, and **Insights** tabs. Historical sessions additionally expose audio playback; live sessions do not.

### Incremental summary

**Status:** Idea

Generate and refine the summary while recording rather than starting all summary work only after Stop. The live Summary tab should update incrementally, make analyzer progress visible, and clearly distinguish provisional content from the final post-stop reconciliation. Accepted decisions, tasks, owners, deadlines, qualifications, and unresolved questions must not be promoted from proposals without evidence.

### Live insights with context and web research

**Status:** Idea

Extend the existing background context lookup into a visible Insights pipeline:

1. A routing analyzer decides whether a completed conversational fact or request warrants research.
2. When research is warranted, it selects the bounded source: configured project context, the web, or both.
3. It emits one self-contained search query containing the conversational context needed by the search worker.
4. The insight remains visually anchored to the triggering utterance or fact rather than appearing at an unrelated point in time.
5. The UI shows the proposed query, current source and operation, tool progress, result, uncertainty, and concrete provenance.

Research runs in the background without blocking recording or transcription. Project searches remain limited to explicitly configured directories. Web findings must identify their external sources. The analyzer and workers treat transcript text, project files, and web pages as untrusted data rather than instructions.

## Later

### Insight review and retention

**Status:** Idea

Define which provisional summaries, searches, sources, and inferred speaker mappings are retained with a session. Users should be able to distinguish generated suggestions from confirmed facts, dismiss irrelevant insights, and understand why each retained insight exists.