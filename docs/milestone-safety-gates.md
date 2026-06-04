# Milestone Safety Gates

VolDeck is audio infrastructure, not only a menu bar UI. A broken build can
leave the user with no sound, so every milestone has a safety gate.

## Gate Rules

- A milestone is not done until its safety gate is documented.
- Privacy indicators are pass/fail checks, not cosmetic issues.
- Install, uninstall, and crash recovery must be designed before alpha release.
- Driver/helper logs must help debug state without recording audio content.
- Any permission added to the app requires an ADR.
- Driver/HAL changes must keep the quality gates in `driver-quality-gates.md`
  current; build-only validation is not enough for driver work.

## Milestone Gates

| Milestone | Gate |
| --- | --- |
| M0 Foundation | Architecture, clean-room, privacy, benchmark, and safety docs exist. |
| M1 App Shell | App launches without microphone, screen recording, system audio recording, network, or driver activation. |
| M2 Virtual Output | VolDeck appears as output only, no input device, no mic prompt, no recording indicator, removable in development. |
| M3 Pass-through | Audio reaches selected real output, helper crash is detected, previous output can be restored. |
| M4 Session Model | App/client identity works without capture permission and edge cases are documented. |
| M5 Mixer | Per-app gain/mute works without cross-app leakage, clipping is controlled, tests cover core logic. |
| M6 Auto-pause | VolDeck only resumes music it paused, and short transient sounds do not cause annoying pauses. |
| M7 Installer/Recovery | Install, uninstall, safe mode, reset, and diagnostic bundle are available and documented. |
| M8 Recording Decision | Recording is rejected, deferred, or isolated as optional with honest permission copy. |
| M9 Product Hardening | Signing, notarization, QA matrix, privacy policy, and alpha rollback notes are complete. |

## M2 Required Pass/Fail Checks

- [ ] HAL plugin contract tests pass.
- [ ] HAL safety guard passes.
- [ ] Xcode static analysis passes for driver-related targets.
- [ ] Output device appears.
- [ ] No input device appears.
- [ ] No microphone permission prompt appears.
- [ ] No system audio recording prompt appears for the core path.
- [ ] No orange mic indicator appears.
- [ ] No system-audio recording indicator appears.
- [ ] Uninstall removes the device.
- [ ] Real output can be restored.

## M3 Required Pass/Fail Checks

Track the active M3 issue set and detailed pass-through checklist in
`m3-output-pass-through.md`.

- [ ] Audio plays through the selected real output.
- [ ] Helper health is visible.
- [ ] Helper crash does not strand the user silently.
- [ ] Previous real output is stored before switching.
- [ ] Quit and crash recovery paths are documented.
- [ ] Buffer underrun/overrun counters exist or are explicitly deferred with rationale.

## M4 Required Pass/Fail Checks

Track the active M4 issue set and detailed session-model checklist in
`m4-app-detection-session-model.md`.

- [ ] Active output clients can be discovered without capture APIs.
- [ ] Session identity uses bundle id before fallback keys.
- [ ] PID is not used as a durable app identity key.
- [ ] Mixer rows are driven by live session metadata, not placeholders.
- [ ] Empty and unavailable session states are visible.
- [ ] Browser, helper, non-bundled, and unknown-client edge cases are documented.

## Install And Uninstall Checks

- [ ] Installer records previous output device.
- [ ] Installer verifies VolDeck device after install.
- [ ] Uninstaller stops helper/app services.
- [ ] Uninstaller restores real output when possible.
- [ ] Uninstaller removes HAL/plugin components.
- [ ] Manual recovery steps exist if automation fails.

## ADR Requirement

Write or update an ADR when:

- adding a permission
- changing core audio architecture
- adding a virtual device type
- changing installer/uninstaller behavior
- accepting a visible privacy indicator
- introducing network behavior
- choosing a third-party dependency
