# M3 Output Pass-through

M3 begins after the M2 HAL prototype was merged into `dev` by PR #55. M2 proved
the output-only shape far enough to continue, but the current driver still
consumes audio silently. M3 is the milestone that makes VolDeck audible by
moving output frames to a helper and playing them through the selected real
output device.

Status checked: 2026-06-03 from GitHub milestone `Milestone 3: Output Pass-through`.

## Milestone Status

| Item | Status |
| --- | --- |
| M2 prerequisite | Complete; PR #55 merged into `dev` |
| M3 milestone | Open |
| M3 due date | Not set |
| Active work | #20 Handle sample-rate and device changes, #21 Restore previous output after helper crash, #22 Add diagnostics |
| Open M3 issues | #20, #21, #22 |
| Closed M3 issues | #17, #18, #19 |

## Covered Issues

| Issue | Current Status | Role |
| --- | --- | --- |
| #17 `[M3][helper] Create output playback helper` | Done, P0 | Create a helper process that can start, stop, and report health without requesting microphone or recording permissions. |
| #18 `[M3][helper] Bridge HAL audio to helper buffer` | Done, P0 | Move HAL output frames into a helper-readable realtime-safe buffer without publishing an input device. |
| #19 `[M3][audio] Forward audio to selected real output` | Done, P0 | Play the received VolDeck stream through one selected physical output device. |
| #20 `[M3][audio] Handle sample-rate and device changes` | In progress, P1 | Keep pass-through resilient when sample rate, headphones, Bluetooth, or default output changes. |
| #21 `[M3][recovery] Restore previous output after helper crash` | In progress, P0 | Detect helper failure and attempt to restore the previously selected real output device. |
| #22 `[M3][diagnostics] Add pass-through latency and underrun diagnostics` | In progress, P1 | Track latency and buffer health without logging audio samples or content. |

## Recommended Work Order

1. Build the helper lifecycle and status surface for #17.
2. Define the HAL-to-helper audio bridge for #18 before writing playback code.
3. Forward one stereo stream to one selected real output for #19.
4. Add crash detection and previous-output restore for #21 before treating
   audible pass-through as safe.
5. Handle device and sample-rate changes for #20.
6. Add diagnostics for latency, underruns, and overruns for #22.

## Target Shape

- HAL/plugin side remains output-only.
- The helper owns playback to the selected real output device.
- The app owns helper lifecycle, selected output preference, visible status, and
  recovery messaging.
- The realtime path must avoid blocking allocations, file IO, network IO, and
  content logging.

## Helper Lifecycle Path

The first M3 implementation slice adds a bundled Swift command-line helper named
`VolDeckOutputHelper`. The app owns helper lifecycle through `Process`, and the
helper reports newline-delimited JSON status on stdout. This is a control plane
only; audio transfer remains reserved for #18.

The helper supports:

- `--health-check` for development validation
- `--run` for start/stop/status lifecycle testing
- a `{"command":"stop"}` stdin command for graceful shutdown

## HAL-to-helper Bridge Path

The second M3 implementation slice adds a fixed-version shared-memory ring
buffer for #18. The HAL side maps and initializes the bridge before realtime IO
starts, then `WriteMix` copies interleaved stereo Float32 output frames into the
ring with atomics and bounded `memcpy` only. The callback does not allocate,
perform file/network IO, log samples, or block waiting for the helper.

The default runtime bridge is a guarded owner-only file-backed mapping under the
process private temporary directory (`com.peerapatj.voldeck/audio.bridge.v1`).
The HAL rejects symlinks, non-regular files, stale owners, and group/world access
on its bridge directory. Tests can override the bridge with
`VOLDECK_AUDIO_BRIDGE_FILE_PATH`; `VOLDECK_AUDIO_BRIDGE_SHM_NAME` is available
when a POSIX shared-memory object is explicitly needed.

For test environments, `VOLDECK_AUDIO_BRIDGE_KEEP_SHM=1` keeps the
`VOLDECK_AUDIO_BRIDGE_FILE_PATH` or `VOLDECK_AUDIO_BRIDGE_SHM_NAME` bridge alive
after contract tests so helper probes can inspect post-run state.

The helper can inspect the bridge with development commands:

- `--buffer-status` reports metadata and counters only.
- `--buffer-read-once <frames>` advances the read cursor for test/probe use
  without printing audio sample contents.
- `--buffer-unlink` removes a development/test bridge object.

## Selected Output Playback Path

The #19 slice adds real output enumeration and playback startup in the helper:

- `--list-output-devices` emits output-capable physical devices, excluding the
  VolDeck virtual output UID.
- `--run --play-through` opens the current default real output device.
- `--run --play-through --output-device-uid <uid>` opens a specific output
  device. The app stores the selected UID and passes it to the helper.

The helper maps the existing bridge once, feeds interleaved stereo Float32 frames
into an output `AudioQueue`, and fills underruns with silence. This keeps the
HAL side output-only and avoids logging audio sample contents. Device-change and
sample-rate recovery remain #20 follow-up work.

## Device Change and Recovery Path

The #20/#21 slice keeps the helper alive while common output changes settle:

- `--run --play-through` re-checks the selected output device while playback is
  active.
- If System Default moves to a different real output, if the active output's
  sample rate, channel count, or buffer size changes, or if the VolDeck bridge
  sample rate changes in place, the helper tears down and recreates playback
  instead of continuing against stale device state.
- If an explicitly selected device disappears, the helper stops playback,
  reports a waiting status, and retries until the device returns or the user
  stops the helper.
- AudioQueue enqueue failure is treated as a recoverable output disruption for
  this M3 slice; the helper goes back to waiting rather than exiting fatal.

The app records the current real default output before starting the helper. If no
real default output is available, it clears any stale restore target. If the
helper exits unexpectedly, the app attempts to set that previous output UID back
as the macOS default output and shows the restore result in diagnostics. When
restore fails or no previous real output was available, diagnostics tell the user
to choose a real device in System Settings > Sound.

Sample-rate handling is intentionally conservative for M3: the helper recreates
playback when device metadata changes and reports bridge/output sample-rate
differences, while relying on `AudioQueue` format conversion for common
mismatches. A custom resampler and hardware-matrix verification remain M9 QA
follow-up work.

## Pass-through Diagnostics

The #22 slice exposes bridge counters and rough latency estimates without
copying or logging audio sample contents:

- Helper status events include buffered frames, underrun frames, overrun frames,
  bridge sample rate, output sample rate, and estimated buffer latency in
  milliseconds.
- The latency estimate is metadata-only: `framesAvailable / sampleRate`.
- App diagnostics summarize the latest helper event so silence, crackle, or
  delay can be explained during development and later included in support bundle
  work.

## Privacy Position

M3 must preserve the M2 privacy contract:

- no virtual input device
- no microphone permission
- no system audio recording permission for the core path
- no microphone or system-audio recording indicator
- no audio sample or content logging
- no network behavior in the driver/helper path

Any permission, capture API, virtual input behavior, or network requirement must
be handled as an ADR change before implementation.

## Safety Gate

M3 is not complete until these checks are true or explicitly deferred with a
dated rationale:

- [ ] Audio plays through the selected real output.
- [ ] Helper health is visible from the app or development command.
- [x] Helper crash or failed health check is detected.
- [x] Previous real output is stored before routing through VolDeck.
- [x] The app attempts to restore the previous real output after helper failure.
- [x] Failure to restore is visible with manual recovery instructions.
- [x] Buffer underrun/overrun counters exist.
- [x] Diagnostics do not log audio samples or content.
- [x] Device change and sample-rate limitations are documented.

## Validation Commands

Keep the M2 gates running while M3 changes the driver/helper path:

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO build
sh scripts/check_hal_safety.sh
sh scripts/run_hal_contract_tests.sh
sh scripts/run_audio_bridge_tests.sh
sh scripts/run_output_helper_lifecycle_tests.sh
/path/to/VolDeckOutputHelper --list-output-devices
```

M3 implementation should add helper and bridge-specific tests before changing
the runtime audio path.
