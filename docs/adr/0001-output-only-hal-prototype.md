# ADR 0001: Prototype Output-only HAL Path First

## Status

Accepted

## Date

2026-06-02

## Decision Owner

VolDeck project

## Context

VolDeck exists because existing per-app volume approaches can require input-like
audio paths, microphone permission, system audio capture permission, or visible
privacy indicators. The project needs a clear M0 architecture direction before
writing driver or helper code.

Background Music validates the feature set, but its recording/input-device
behavior conflicts with the VolDeck privacy goal. Audio Tap / Process Tap apps
show that per-app volume is possible with modern Apple APIs, but that path can
require system audio capture permission and may show OS-controlled indicators.

## Decision

VolDeck will prototype an output-only HAL / driver-level path first in M2.

The M2 prototype must publish only an output device, avoid microphone permission,
avoid system audio capture permission for the core mixer, and verify that no mic
or recording indicator appears during core operation.

Audio Tap / Process Tap remains a research path and possible fallback only after
M2 proves that the preferred path is infeasible or too risky.

## Options Considered

| Option | Pros | Cons |
| --- | --- | --- |
| Background Music-style virtual input | Known product behavior; supports recording workflows | Conflicts with no virtual input and no mic-like indicator goals; GPL implementation cannot be reused |
| Audio Tap / Process Tap | Apple-native; strong fit for per-app volume; no third-party driver | Can require system audio capture permission and OS indicators; weaker fit for strict no-indicator goal |
| ScreenCaptureKit capture | Apple-supported capture stack; useful for recording | Capture-oriented and privacy-permission heavy for a core output mixer |
| Output-only HAL / driver-level path | Best fit for no virtual input, no mic permission, and no recording indicator | Highest engineering risk; install/uninstall and per-app mapping are hard |

## Privacy Impact

- Does this add microphone permission? No.
- Does this add system audio recording permission? No for the M2 core prototype.
- Does this publish an input device? No.
- Does this create any visible privacy indicator? It must not; M2 verification is required.
- Does this introduce network behavior? No.

## Safety And Recovery Impact

- M2 must include development uninstall instructions.
- M3 must restore or clearly recover the previous real output after helper failure.
- M7 must make install, uninstall, safe mode, and diagnostics product-grade.

## Compatibility Impact

- Supported macOS versions remain undecided until the HAL/plugin approach is tested.
- App/client identity mapping is the main unknown for per-app gain.
- Signing and notarization requirements must be resolved before alpha release.

## Consequences

VolDeck accepts a harder M2 in exchange for a stronger privacy and market
position. If M2 cannot prove output-only, no-input, no-indicator behavior, the
project must write a new ADR before switching to Audio Tap or another capture
path.

## Follow-up Work

- [ ] #12 Create minimal virtual output device
- [ ] #13 Publish VolDeck as output-only device
- [ ] #15 Verify no virtual input, no mic permission, no indicator
- [ ] #16 Document development install and uninstall for HAL plugin

## References

- docs/architecture-comparison.md
- docs/privacy-principles.md
- docs/market-benchmark.md
