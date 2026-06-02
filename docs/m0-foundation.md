# M0 Foundation Index

This milestone locks down the rules and research gates before VolDeck touches
macOS audio infrastructure.

## Covered Issues

| Issue | Document |
| --- | --- |
| #1 `[M0][docs] Define clean-room contribution rules` | [clean-room-rules.md](clean-room-rules.md) |
| #2 `[M0][docs] Document Background Music feature-parity target` | [background-music-parity.md](background-music-parity.md) |
| #3 `[M0][privacy] Define no-mic and no-indicator privacy principles` | [privacy-principles.md](privacy-principles.md) |
| #4 `[M0][research] Compare no-indicator audio architectures` | [architecture-comparison.md](architecture-comparison.md) |
| #5 `[M0][research] Benchmark AppVolume, SoundSource, and Audio Tap apps` | [market-benchmark.md](market-benchmark.md) |
| #6 `[M0][docs] Define architecture safety gates and ADR format` | [milestone-safety-gates.md](milestone-safety-gates.md), [adr/0000-template.md](adr/0000-template.md), [adr/0001-output-only-hal-prototype.md](adr/0001-output-only-hal-prototype.md) |

## M0 Decision

VolDeck should prototype an output-only HAL / driver-level architecture in M2.
The core product must not use Background Music-style virtual input, microphone
permission, or system-audio capture permission as the default mixer path.

Audio Tap / Process Tap remains useful for research and optional recording or
metering experiments, but it is not the preferred core path because it can
require system audio capture permission and may show OS-controlled indicators.

## M2 Must Prove

- VolDeck publishes an output device only.
- VolDeck does not publish any virtual input device.
- VolDeck does not request microphone permission.
- VolDeck does not request system audio recording permission for the core path.
- VolDeck does not show the orange mic indicator or a system-audio recording indicator.
- VolDeck can be removed and the user's real output device can be restored.

## Acceptance Audit

- #1: Clean-room allowed/prohibited rules and contributor checklist are in `clean-room-rules.md`.
- #2: Background Music parity targets are mapped to M1-M8 in `background-music-parity.md`.
- #3: Permission, indicator, and verification rules are in `privacy-principles.md`.
- #4: Architecture options, recommendation, and M2 unknowns are in `architecture-comparison.md`.
- #5: Competitor feature/permission benchmark and VolDeck differentiation are in `market-benchmark.md`.
- #6: Safety gates and ADR format are in `milestone-safety-gates.md` and `docs/adr/`.
