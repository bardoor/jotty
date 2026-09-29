# Jotty

A macOS 15+ command-line recorder for calls. Jotty captures system audio and the default microphone, transcribes the recording with Soniox, and asks the locally authenticated Codex CLI for a Markdown summary.

## Requirements

- macOS 15+
- Elixir 1.20 / Erlang/OTP 29
- FFmpeg
- just
- Node.js 22 and npm (desktop app)
- Codex CLI authenticated with ChatGPT (`codex login`)
- a Soniox API key in `config/dev.secret.exs`

## Build

```bash
just build
```

Keep the generated `jotty` executable in the repository root because it resolves the native recorder relative to its own location.

## Desktop app

Install the Electron dependencies and start the local app:

```bash
cd desktop
npm install
npm run dev
```

`npm run dev` builds the native recorder and Elixir escript, starts the Vite renderer, and launches Electron. The Electron main process starts the Elixir service on a random loopback port and gives the isolated renderer only its WebSocket URL. Recording starts only after pressing **Start recording**.

The MVP intentionally has no session history, settings, updater, signing, notarization, or production packaging.

## Record

Create the ignored local secrets file from the tracked example, then insert the Soniox credential:

```bash
cp config/dev.secret.exs.example config/dev.secret.exs
```

```elixir
config :jotty, soniox_api_key: "..."
```

Then rebuild the escript so the development configuration is included, and run it:

```bash
just build
./jotty record
```

To enable live project-context assistance, pass one or more explicit roots:

```bash
./jotty record \
  --context ~/github/backend \
  --context ~/github/frontend
```

Without `--context`, recording remains archival-only and opens no realtime Soniox connections.

Press Enter to stop recording. Jotty sends `SIGINT` to the native recorder, waits for both tracks to be finalized, then mixes, transcribes, and summarizes them.

Each run creates:

```text
~/.jotty/recordings/<UTC timestamp>/
├── system.m4a
├── microphone.m4a
├── audio.m4a
├── transcript.txt
├── summary.md
└── assistant.md  # only when record is started with --context
```

Completed local artifacts remain in place if a later stage fails.

## Enrich with project context

After a recording is transcribed, ask the locally configured Hermes agent to relate the call to one explicitly selected project directory:

```bash
./jotty enrich ~/.jotty/recordings/<timestamp> --context ~/projects/my-project
```

By default, enrichment uses `gpt-5.6-luna` with `low` reasoning effort. Override either Hermes setting per run when needed:

```bash
./jotty enrich ~/.jotty/recordings/<timestamp> \
  --context ~/projects/my-project \
  --model gpt-5.6-sol \
  --reasoning-effort medium
```

Hermes receives read-only file, skill, and memory tools. It is instructed to use the selected directory as its only local project context, avoid secrets and generated directories, make no external changes, and save no memories. The restriction is an agent contract rather than an operating-system sandbox.

The command writes `context.md` beside the existing recording artifacts. It lists relevant project context with source paths, conflicts with the discussion, uncertain matches, and facts that a person may choose to remember later.

## Assist during a conversation

Start a text-driven assistant session with one or more explicitly allowed project directories:

```bash
./jotty assist \
  --context ~/github/backend \
  --context ~/github/frontend
```

Enter one completed utterance per line. Press `Ctrl-D` to finish the session. Jotty keeps the five most recent utterances as conversational context and uses Codex structured output to decide whether the latest utterance requires current project facts.

Ordinary planning and general discussion are ignored. When a lookup is needed, Hermes searches only the selected directories and appends the answer with source file paths to:

```text
~/.jotty/sessions/<UTC timestamp>/assistant.md
```

The classifier and context search both use `gpt-5.6-luna` with low reasoning effort. The standalone command accepts text input; `record --context` obtains completed utterances from two independent realtime Soniox streams while the post-recording transcript remains canonical.
