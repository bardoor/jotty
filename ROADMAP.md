# Jotty roadmap

This roadmap records product direction, not release commitments. Items move into issues and milestones when their scope is ready for implementation.

## Now

### Acoustic echo cancellation

**Status:** Discovery

**Problem:** When system audio is played through speakers, the microphone captures an acoustic copy. Sending both sources without echo cancellation duplicates remote speech in the transcript and degrades diarization and summaries.

**Outcome:** System speech appears once while local microphone speech remains clear during speaker playback, headphone use, and double-talk.

**Proposed signal path:** Use the WebRTC Audio Processing Module for acoustic echo cancellation. Feed system audio into its render/reverse path as the far-end reference and microphone audio into its capture path. The useful outputs are the original system track and the echo-cancelled microphone track; WebRTC AEC does not process both tracks symmetrically.

Evaluate merging those two outputs into one realtime stream before Soniox against keeping the current two Soniox streams. A merged stream is simpler, but it discards guaranteed source separation and may make later speaker labelling less reliable. Preserve `system.m4a` and `microphone.m4a` unchanged regardless of the realtime topology so failed or over-aggressive echo cancellation can be corrected after recording.

**Constraints:**

- AEC failure must not stop or corrupt archival recording.
- Preserve the original system and microphone recordings.
- Support speakers, headphones, near-end speech, far-end speech, and double-talk.
- Measure alignment and echo suppression before choosing the final WebRTC integration.

### Compact fixed window

**Status:** Planned

Replace the current resizable `1080 × 760` window with a compact fixed-size window approximately `360 × 520` device-independent pixels. Electron device-independent dimensions should continue to respect display scaling.

The transcript, recording controls, errors, and summary must remain usable within this fixed footprint.

### Native title-bar spacing

**Status:** Planned

Reserve explicit space for the macOS close, minimize, and zoom controls when using the inset hidden title bar. The controls must not overlap the Jotty mark or title.

### Always on top

**Status:** Planned

Add an optional **Always on top** mode so the compact recording window can remain visible above call and work applications. The mode must be user-controlled rather than permanently enabled.

## Next

### Settings

**Status:** Planned

Add a settings surface. The first setting is microphone selection so a user can choose which input device is recorded instead of always using the current default microphone.

Later audio settings may expose only choices that have a clear user-facing purpose; internal DSP tuning does not belong in the initial settings UI.

### Session management

**Status:** Planned

Add persistent session browsing similar to chat history:

- list completed recording sessions;
- open a session's transcript and summary;
- rename and delete sessions;
- show recording time and useful session metadata.

A permanent ChatGPT-style sidebar conflicts with the compact fixed window. In the compact layout, session history should use a drawer or a separate view rather than permanently consuming horizontal space.

## Later

### Speaker labels

**Status:** Planned

Allow diarized speakers to be assigned human-readable labels, usually names. Labels should be editable during or after a call, stored with the session, and used consistently in the transcript and summary instead of generic names such as “Participant 1”.

The data model must keep provider speaker identifiers separate from user labels so labels can be changed without rewriting raw transcription evidence.
