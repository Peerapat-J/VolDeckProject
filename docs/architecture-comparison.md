# No-indicator Architecture Comparison

Current as of 2026-06-02.

## Recommendation

Prototype the output-only HAL / driver-level path in M2.

This is the only candidate that directly targets the VolDeck promise: no virtual
input, no microphone permission, and no system-audio recording indicator for the
core mixer. It is also the hardest path, so M2 must be treated as a proof gate,
not a foregone conclusion.

## Options

### Option A: Background Music-style virtual input

```text
Apps -> virtual output -> driver/ring buffer -> virtual input -> app reads input -> real output
```

Decision: rejected for core VolDeck.

Why:

- Publishes an input-style device.
- Enables recording apps to select the virtual input.
- Conflicts with the no virtual input goal.
- Conflicts with the user's reason for starting VolDeck.
- Background Music is GPL, so implementation reuse is not acceptable.

Use only as:

- feature behavior reference
- user expectation reference
- list of edge cases to test

### Option B: Audio Tap / Process Tap

```text
Apps -> Core Audio process taps -> mixer IOProc -> real output
```

Decision: useful research path, not preferred core path.

Pros:

- Apple-native API on newer macOS versions.
- No third-party driver install.
- Strong fit for per-process/app volume.
- Existing apps use it for per-app sliders, EQ, ducking, and meters.

Cons:

- Can require system audio capture permission.
- May show OS-controlled capture indicators on some macOS versions.
- Does not meet the strict no-indicator goal unless proven otherwise.
- Requires macOS 14.2+ for many examples.

Use only if:

- M2 output-only HAL cannot support per-app mapping, or
- an ADR accepts capture permission for a clearly optional feature.

### Option C: ScreenCaptureKit audio-only capture

```text
Apps/system -> ScreenCaptureKit capture -> mixer -> real output
```

Decision: rejected for core mixer, possible M8 recording research only.

Pros:

- Apple-supported capture stack.
- Useful for recording or screen/audio workflows.

Cons:

- It is capture-oriented.
- It can require privacy permissions and indicators.
- It is conceptually misaligned with output-only per-app volume.

### Option D: Output-only HAL / driver-level mixer

```text
Apps -> VolDeck virtual output only -> driver-level mixer/shared buffer -> helper -> real output
```

Decision: preferred M2 prototype.

Pros:

- Best fit for no virtual input.
- Best fit for no microphone permission.
- Best chance of avoiding system-audio capture indicators.
- Similar market direction to AppVolume's public no-indicator positioning.
- Makes VolDeck meaningfully different from Audio Tap products.

Cons:

- Highest implementation complexity.
- Requires serious HAL/plugin or driver-level engineering.
- Install/uninstall and recovery risk are higher.
- macOS updates may break behavior.
- Debugging audio silence, latency, underruns, and crashes is harder.
- Per-app mapping may be the decisive unknown.

## Required M2 Proofs

- VolDeck can publish an output-only device.
- VolDeck does not publish input streams or input devices.
- The app/helper does not request microphone permission.
- The app/helper does not request system audio capture permission.
- No mic or system-audio recording indicator appears during core operation.
- Audio frames can be transported toward the helper without a virtual input.
- Development uninstall can restore the user's real output.

## Unknowns To Resolve

- Can the chosen HAL/plugin boundary identify clients well enough for per-app gain?
- Can audio be moved to a helper without blocking realtime callbacks?
- Is shared memory/ring buffer transport stable enough for consumer use?
- What install location and signing model are required for supported macOS versions?
- Can we keep the driver surface small while moving logic into helper/app code?
- Can the app recover output after helper crash or plugin failure?

## Source Notes

- Apple documents Audio Server Driver Plug-ins for supporting audio devices in macOS: https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in
- Apple documents Core Audio taps for system audio capture: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- VolumeHub publicly describes an Audio Tap approach with no third-party drivers: https://volumehub.app/
- SonicFlow publicly describes Process Tap, IOProc, and real output playback behavior: https://altuzar.github.io/sonicflow/
- AppVolume publicly claims no recording indicator and driver-level CoreAudio capture/mix: https://appvolume.app/
