# AEC build and API spike

This spike proves that `pulseaudio/webrtc-audio-processing` can be built and called from Swift on macOS arm64. The generated library is used only by the recorder's explicit `--aec-spike` mode; it does not demonstrate echo-cancellation quality or affect the production desktop path.

## Pinned source

- Repository: `https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git`
- Tag: `v2.1`
- Peeled commit: `846fe90a289f58b7c9303a635142aa2c7caa93e5`
- Abseil fallback: `20240722.0`, with downloaded archives verified by SHA-256 in `build.sh`

## Proven contract

The bridge exposes an opaque C handle and separate serialized render and capture operations:

1. `ProcessReverseStream` receives the system/render frame.
2. `set_stream_delay_ms` receives the application-known stream delay before each capture frame.
3. `ProcessStream` receives the microphone/capture frame.
4. The cleaned capture frame is returned through the output buffer.

Every frame is mono signed Int16 PCM at 16 kHz with exactly 160 samples (320 bytes, 10 ms). Invalid pointers and frame sizes return stable bridge error codes; WebRTC processing errors are passed through unchanged.

## Reproduce

Run from the repository root:

```sh
spikes/001-aec-build-api/build.sh
```

The script clones the pinned source into the ignored local `.build` directory, verifies the revision and fallback archives, creates a release static build, links it into an arm64 `libJottyAEC.dylib`, compiles the Swift smoke runner through `module.modulemap`, and executes it.

The verified run printed:

```text
AEC bridge smoke passed: 160 samples at 16000 Hz
```

Both the bridge and Swift executable were verified as Mach-O arm64. `otool -L` showed that the bridge depends only on macOS system frameworks/libraries (`Foundation`, `CoreFoundation`, `libc++`, and `libSystem`), not a separately shipped WebRTC or Abseil dylib.

## Findings and limits

- The upstream static archive contains the required WebRTC and Abseil objects for normal demand-driven linking. Counting unresolved symbols in the archive alone is not a valid packaging failure: archive members are resolved when the final image is linked.
- Forcing every archive member into the image with `-all_load` is incorrect here. It pulls unused Abseil test support and produces unresolved or duplicate symbols.
- The Swift proof processes silence and a deterministic non-zero synthetic frame, then verifies invalid-size and null-pointer failures. It proves API/import/link/runtime compatibility, not acoustic performance.
- `JottyAEC` is stateful and not thread-safe by this bridge contract. Integration must serialize render/capture calls in one coordinator because the ScreenCaptureKit callbacks arrive on different queues.
- The production insertion point remains after canonical PCM conversion and before `LiveAudioMixer`: raw system PCM is the render reference, raw microphone PCM is capture, and cleaned microphone PCM is mixed with system audio for the existing single Soniox stream.
- Raw `system.m4a` and `microphone.m4a` archives must remain unchanged.
- A production packaging mechanism is still undecided. This spike intentionally does not add the dependency or generated binary to the Swift package.
- Timestamp-based software alignment is implemented by the live quality spike, but its acoustic result remains unproven. Drift handling, failure fallback, binary signing, and production packaging remain unresolved. Do not add a custom delay tracker before measurements demonstrate that AEC3's estimator is insufficient.

## Next gate

The next gate is rerunning the timestamp-aligned live quality spike. It must compare speakers, headphones, local speech, far-end-only audio, and double-talk before production integration is accepted.
