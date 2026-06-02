# Market Benchmark

Current as of 2026-06-02. This is a product-level benchmark only. Do not copy
code, assets, names, copywriting, or implementation details.

## Summary

VolDeck can compete if it proves a trustworthy no-indicator core path and keeps
install/uninstall recovery unusually clear.

The market already validates demand for per-app volume. The gap is trust:
users want app volume control without mic permission, virtual input confusion,
or a persistent privacy dot.

## References

| App | Publicly visible approach | Indicator / permission notes | Useful behavior reference |
| --- | --- | --- | --- |
| Background Music | Virtual output plus virtual input style workflow | Recording feature exposes Background Music as an input device; GPL project | per-app volume, boost, auto-pause, install/uninstall expectations |
| SoundSource | Rogue Amoeba ARK audio handling | Official docs say ARK needs System Audio Access and Microphone Access, and macOS may show a purple system-audio indicator | mature UX, routing, effects, support docs |
| AppVolume | Claims CoreAudio driver-level capture/mix | Claims no purple recording dot and no recording | no-indicator positioning, 0-200 percent volume, persistence, device switching |
| VolumeHub | Claims Apple Audio Tap API, no drivers | Audio Tap architecture may involve system audio capture behavior depending on OS and implementation | native UI, density modes, EQ, focus audio |
| SonicFlow | Claims CoreAudio Process Taps and realtime IOProc | Says no microphone permission; also notes macOS 14.4+ may briefly show an audio-capture indicator | open architecture explanation, ring buffer, ducking |
| FineTune | Open-source per-app volume and routing app | README quick start asks users to grant Screen & System Audio Recording permission | rich feature set: boost, routing, EQ, hotkeys |

## VolDeck Differentiation

1. No virtual input as a product promise.
2. No microphone permission for the core mixer.
3. No system audio capture permission for the core mixer if M2 proves feasible.
4. Safety-first installer, uninstaller, safe mode, and reset path.
5. Background Music-style auto-pause parity after per-app volume works.
6. Transparent architecture and privacy docs before alpha release.

## UX Patterns Worth Studying

- App rows should appear only when useful, but pinned apps should be possible later.
- Mute must be one-click and visually obvious.
- Boost above 100 percent needs clipping protection and clear UI.
- Output device switching must not strand users without audio.
- Auto-pause must track ownership so VolDeck does not resume music the user paused manually.
- Troubleshooting docs must be visible before users need them.

## Safety Notes For Future Live Testing

Live testing of competitors is optional and should happen only on a reversible
setup. If tested, record:

- macOS version and hardware
- requested permissions
- visible menu bar or Control Center indicators
- created output/input devices
- install and uninstall behavior
- whether audio returns to the original device after quit/uninstall

## Source Notes

- Background Music README: https://github.com/kyleneideck/BackgroundMusic
- Rogue Amoeba SoundSource ARK details: https://www.rogueamoeba.com/support/knowledgebase/?product=SoundSource&showArticle=Misc-ARK-Plugin-Audio-Capture-Details
- AppVolume: https://appvolume.app/
- VolumeHub: https://volumehub.app/
- SonicFlow: https://altuzar.github.io/sonicflow/
- FineTune: https://github.com/ronitsingh10/FineTune
