# Native acoustic echo cancellation

Jotty builds `pulseaudio/webrtc-audio-processing` from pinned source and loads the resulting `libJottyAEC.dylib` beside `jotty-recorder`. Live recording always routes microphone audio through AEC before mixing it with system audio for the single realtime transcription stream.

## Dependency

- Repository: `https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git`
- Tag: `v2.1`
- Commit: `846fe90a289f58b7c9303a635142aa2c7caa93e5`
- WebRTC license: BSD-3-Clause; see `LICENSE.webrtc-audio-processing`
- Abseil fallback: `20240722.0`, Apache-2.0; see `LICENSE.abseil-cpp`
- Downloaded dependency archives are verified by SHA-256 in `build.sh`

## Runtime contract

The bridge owns one stateful WebRTC Audio Processing Module instance. Calls are serialized by `AECCoordinator`:

1. `ProcessReverseStream` receives each system/render frame.
2. Capture waits until the render timeline reaches its presentation timestamp.
3. `set_stream_delay_ms(0)` reports that application-level alignment is complete.
4. `ProcessStream` returns the cleaned microphone frame.
5. Raw system and cleaned microphone PCM are aligned by timestamp and mixed once for realtime transcription.

Frames are mono signed Int16 PCM at 16 kHz with exactly 160 samples (320 bytes, 10 ms). The raw `system.m4a` and `microphone.m4a` archives are written before realtime conversion and remain unchanged. Cleaned microphone frames are also saved to `microphone-aec.wav` before they enter the realtime mixer.

Capture that predates the first render reference or remains after the final render frame is dropped because no reference exists for those boundary samples. Raw microphone PCM is never sent to the realtime mixer. Processing errors fail the live transport; Jotty does not silently disable AEC for an active recording.

## Build

Run from the repository root:

```sh
just build
```

`native/aec/build.sh` verifies the pinned upstream revision and dependency archives, builds the static upstream library when absent, links `libJottyAEC.dylib`, and executes the Swift ABI smoke test. `just build` then builds `jotty-recorder` and copies the dylib beside the release executable.

The bridge is linked demand-first against `libwebrtc-audio-processing-2.a`. Do not use `-all_load`: it pulls unused Abseil support and produces unresolved or duplicate symbols.

## Deferred distribution work

The current build is macOS arm64. Universal binaries, signing, notarization, and installer packaging require a separate distribution stage.
