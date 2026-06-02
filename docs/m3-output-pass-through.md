# M3 Output Pass-through

M3 begins after the M2 HAL prototype was merged into `dev` by PR #55. M2 proved
the output-only shape far enough to continue, but the current driver still
consumes audio silently. M3 is the milestone that makes VolDeck audible by
moving output frames to a helper and playing them through the selected real
output device.

Status checked: 2026-06-02 from GitHub milestone `Milestone 3: Output Pass-through`.

## Milestone Status

| Item | Status |
| --- | --- |
| M2 prerequisite | Complete; PR #55 merged into `dev` |
| M3 milestone | Open |
| M3 due date | Not set |
| Active work | #17 output playback helper lifecycle |
| Open M3 issues | #17, #18, #19, #20, #21, #22 |
| Closed M3 issues | None |

## Covered Issues

| Issue | Current Status | Role |
| --- | --- | --- |
| #17 `[M3][helper] Create output playback helper` | In progress, P0 | Create a helper process that can start, stop, and report health without requesting microphone or recording permissions. |
| #18 `[M3][helper] Bridge HAL audio to helper buffer` | Open, P0 | Move HAL output frames into a helper-readable realtime-safe buffer without publishing an input device. |
| #19 `[M3][audio] Forward audio to selected real output` | Open, P0 | Play the received VolDeck stream through one selected physical output device. |
| #20 `[M3][audio] Handle sample-rate and device changes` | Open, P1 | Keep pass-through resilient when sample rate, headphones, Bluetooth, or default output changes. |
| #21 `[M3][recovery] Restore previous output after helper crash` | Open, P0 | Detect helper failure and attempt to restore the previously selected real output device. |
| #22 `[M3][diagnostics] Add pass-through latency and underrun diagnostics` | Open, P1 | Track latency and buffer health without logging audio samples or content. |

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
- [ ] Helper crash or failed health check is detected.
- [ ] Previous real output is stored before routing through VolDeck.
- [ ] The app attempts to restore the previous real output after helper failure.
- [ ] Failure to restore is visible with manual recovery instructions.
- [ ] Buffer underrun/overrun counters exist.
- [ ] Diagnostics do not log audio samples or content.
- [ ] Device change and sample-rate limitations are documented.

## Validation Commands

Keep the M2 gates running while M3 changes the driver/helper path:

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO build
sh scripts/check_hal_safety.sh
sh scripts/run_hal_contract_tests.sh
sh scripts/run_output_helper_lifecycle_tests.sh
```

M3 implementation should add helper and bridge-specific tests before changing
the runtime audio path.
