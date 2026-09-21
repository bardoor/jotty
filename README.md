# Jotty

A macOS 15+ command-line recorder for calls. Jotty captures system audio and the default microphone, transcribes the recording with Soniox, and asks the locally authenticated Codex CLI for a Markdown summary.

## Requirements

- macOS 15+
- Elixir 1.20 / Erlang/OTP 29
- FFmpeg
- just
- Codex CLI authenticated with ChatGPT (`codex login`)
- a Soniox API key in `config/dev.secret.exs`

## Build

```bash
just build
```

Keep the generated `jotty` executable in the repository root because it resolves the native recorder relative to its own location.

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

Press Enter to stop recording. Jotty sends `SIGINT` to the native recorder, waits for both tracks to be finalized, then mixes, transcribes, and summarizes them.

Each run creates:

```text
~/.jotty/recordings/<UTC timestamp>/
├── system.m4a
├── microphone.m4a
├── audio.m4a
├── transcript.txt
└── summary.md
```

Completed local artifacts remain in place if a later stage fails.
