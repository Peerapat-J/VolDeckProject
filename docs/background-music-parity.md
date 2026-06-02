# Background Music Feature Parity Target

VolDeck starts by matching the useful user-facing behaviors of Background Music,
then intentionally diverges where Background Music relies on virtual input or
audio-input capture.

## Parity Targets

| Feature | VolDeck target | Milestone |
| --- | --- | --- |
| Menu bar control | Native menu bar app with mixer popover | M1 |
| Per-app volume | Slider per active app | M5 |
| Per-app mute | One-click mute per app | M5 |
| Volume persistence | Remember app settings by stable app identity | M5 |
| Volume boost | Optional boost above normal level with clipping protection | M5 |
| Output device selector | Pick or follow the real output device | M3 |
| Auto-pause music | Pause music when another sustained audio source starts | M6 |
| Install without restart if feasible | Prefer no restart, but safety beats convenience | M7 |
| Safe uninstall | Remove audio components and restore output | M7 |
| Troubleshooting path | Reset audio and diagnostic bundle | M7 |

## Intentionally Redesigned

| Background Music behavior | VolDeck decision | Reason |
| --- | --- | --- |
| Virtual input for recording system audio | Rejected for core mixer | It conflicts with no virtual input and no mic-like indicator goals. |
| Record system audio through a selectable input device | Deferred to M8 | Recording is valuable but must not compromise the core privacy promise. |
| Architecture based on app reading a virtual input stream | Rejected | VolDeck should move audio through an output-only path and helper/mixer layer. |

## Deferred Features

These can be reconsidered after M2 to M5 prove the no-indicator mixer path:

- system audio recording
- EQ
- multi-output routing
- advanced presets
- per-device app rules
- cloud sync or account features

## Manual UX Benchmarks

Use Background Music and commercial competitors only to understand expected
behavior. When benchmarking UX, record observations in our own words:

- how app rows appear and disappear
- how muted apps are displayed
- how boost is communicated
- how output switching is presented
- how auto-pause avoids fighting user intent
- how uninstall and restore output are explained

## Source Notes

- Background Music README lists auto-pause, per-application volume, system audio recording, and no-restart install as core features: https://github.com/kyleneideck/BackgroundMusic
- Background Music is GPL-2.0 licensed, so VolDeck must remain clean-room.
