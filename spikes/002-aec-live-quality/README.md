# AEC live quality spike

This spike feeds canonical realtime system PCM into WebRTC APM as the render reference and canonical microphone PCM as capture. It writes the cleaned microphone to `microphone-aec.wav` while preserving the existing raw `system.m4a` and `microphone.m4a` archives.

It does not open Soniox or modify the desktop path.

## Run

Use a new output directory for every recording:

```sh
spikes/002-aec-live-quality/run.sh "$HOME/Desktop/jotty-aec-speakers"
```

Press Control-C to stop. The first run builds the pinned AEC dependency and native recorder; later runs reuse the AEC library unless the bridge sources changed.

The output directory contains:

- `system.m4a` — raw system audio;
- `microphone.m4a` — raw microphone audio;
- `microphone-aec.wav` — AEC-processed microphone at 16 kHz mono Int16.

## Test matrix

Keep system volume and microphone position fixed within each comparison. Use distinct output directories.

1. **Speakers, far-end only:** play clear spoken audio for 15–20 seconds and stay silent. The raw microphone should contain audible speaker leakage; the cleaned microphone should suppress it substantially.
2. **Speakers, near-end only:** pause system audio and speak for 15–20 seconds. The cleaned microphone should preserve intelligibility without pumping or severe distortion.
3. **Speakers, double-talk:** play spoken system audio and speak over it. The cleaned microphone should retain the local voice while reducing the system voice.
4. **Headphones, near-end only:** speak with no acoustic system leakage. The cleaned microphone should not materially degrade the local voice.

Listen to `microphone.m4a` and `microphone-aec.wav` back to back. Do not compare their absolute loudness alone; evaluate remaining far-end speech, local voice intelligibility, dropouts, pumping, and metallic artifacts.

## Interpretation

- Passing far-end-only but failing double-talk means the integration runs, but quality is not acceptable.
- Similar raw and cleaned speaker leakage suggests render/capture alignment is insufficient or AEC is not converging.
- Missing or damaged local speech is a rejection even if echo is suppressed.
- This spike preserves each source's initial ScreenCaptureKit presentation timestamp and advances its canonical 16 kHz timeline by emitted sample count.
- Render frames are submitted as soon as they arrive. Capture frames wait until the render timeline reaches their presentation timestamp, so callback arrival order is not treated as temporal alignment.
- Capture preceding the first available render frame is discarded from the diagnostic output because no reference exists for it.
- The application-known stream delay is zero after this software alignment. AEC3 remains responsible for estimating the acoustic/render-path delay; there is no custom delay estimator or drift correction.
