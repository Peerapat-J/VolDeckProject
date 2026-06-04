# M4 App Detection / Session Model

M4 starts after the M3 output pass-through work was merged into `dev` by PR #59.
M3 made the VolDeck output path audible through a selected real output device.
M4 adds a metadata-only session model so the app can show which apps are actively
using the VolDeck output device without adding capture permissions, process
taps, or audio-content logging.

Status checked: 2026-06-04 from GitHub milestone `Milestone 4: App Detection / Session Model`.

## Milestone Status

| Item | Status |
| --- | --- |
| M3 prerequisite | Complete; PR #59 merged into `dev` |
| M4 milestone | Open |
| M4 due date | Not set |
| Active work | PR for #23, #24, #25, #26, #27 |
| Open M4 issues | #23, #24, #25, #26, #27 |

## Covered Issues

| Issue | Role |
| --- | --- |
| #23 `[M4][session] Research client-to-process mapping` | Choose a no-indicator metadata source for active audio clients. |
| #24 `[M4][session] Track active audio clients` | Maintain an in-memory model of active clients using the VolDeck output. |
| #25 `[M4][session] Map clients to app name, icon, and bundle id` | Resolve low-level process identity into UI-ready app identity. |
| #26 `[M4][app] Show active apps in mixer list` | Replace placeholder mixer rows with the live session model. |
| #27 `[M4][session] Persist app identity and edge-case handling` | Define durable keys for M5 mixer settings and document fallbacks. |

## Research Decision

The first M4 implementation uses CoreAudio Process objects from the app process:

- `kAudioHardwarePropertyProcessObjectList` lists HAL client process objects.
- `kAudioProcessPropertyPID` resolves a process object to a pid.
- `kAudioProcessPropertyBundleID` provides the bundle id when the HAL knows it.
- `kAudioProcessPropertyDevices` scoped to output identifies the output devices
  currently used by a process.
- `kAudioProcessPropertyIsRunningOutput` identifies active output IO.

The app filters this metadata to processes whose output device list includes the
VolDeck output UID `com.peerapatj.voldeck.output`. This is a metadata query from
the app, not a call from inside the AudioServerPlugIn host, so it preserves the
existing HAL safety rule against HAL client APIs inside plugin code.

This resolves M4's first feasibility question: VolDeck can identify active
apps/clients in the no-indicator path well enough to populate the menu bar mixer
list. It does not yet prove per-app gain/mute inside the audio callback. M5 must
still prove the mixer routing/gain model without cross-app leakage.

## Session Model

The runtime model is intentionally small:

- `AudioProcessSessionCatalog` polls CoreAudio process objects.
- `AudioSessionController` owns the in-memory active session list.
- `AudioSessionIdentityResolver` maps process metadata to app identity.
- `MenuBarRootView` renders rows from live session data and keeps gain/mute
  controls disabled until M5.

The app refreshes the session list while the menu bar window is open. Starting
audio through the VolDeck output should add a row; stopping playback, switching
away from VolDeck, or quitting the app should remove the row on the next refresh.

## Identity Rules

VolDeck uses identity keys in this order so M5 can persist mixer settings
against the same model:

1. `bundle:<bundle id>` when a bundle id is available.
2. `path:<hash>:<basename>` for non-bundled executables with a stable path.
3. `client:<client id>` only as a temporary fallback when no bundle id or path
   is available.

PID is deliberately not a persistence key because it changes across relaunches.
Helper and renderer processes should collapse to the bundle id when CoreAudio or
LaunchServices can identify their owning app. If only an executable path is
known, the raw path is hashed before it becomes an identity key.

Known edge cases:

- Browser renderers and helper processes may appear as the browser bundle when
  macOS exposes a parent bundle id.
- Non-bundled command-line tools can be stable by executable path, but moving the
  executable creates a new identity.
- If CoreAudio exposes neither bundle id nor path, the fallback is useful for the
  current run only and should not be used for durable M5 settings.
- Apps using aggregate devices or nonstandard audio stacks may not list VolDeck
  as an output device until they actually start output IO.

## Privacy Position

M4 preserves the M2/M3 privacy contract:

- no process taps
- no ScreenCaptureKit
- no virtual input device
- no microphone permission
- no system-audio recording permission
- no microphone or system-audio recording indicator
- no audio sample or content logging
- no network behavior in the driver/helper/session path

Any move from metadata-only process queries to capture APIs, taps, input devices,
or permission prompts requires an ADR before implementation.

## Validation Commands

Keep the existing driver gates running while M4 changes the session surface:

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
sh scripts/check_hal_safety.sh
sh scripts/run_session_identity_behavior_tests.sh
sh scripts/run_app_recovery_behavior_tests.sh
sh scripts/run_hal_contract_tests.sh
sh scripts/run_audio_bridge_tests.sh
sh scripts/run_output_helper_lifecycle_tests.sh
```
