# Privacy Principles

VolDeck's core promise is simple: control app output volume without making the
user feel like the app is listening.

## Core Rules

- Do not request microphone permission for the core mixer.
- Do not publish a virtual input device.
- Do not use audio-input capture APIs for the core mixer.
- Do not use system audio recording permission for the core mixer.
- Do not hide or work around privacy indicators.
- Avoid the APIs and device shapes that trigger those indicators.
- Do not send analytics, telemetry, or audio metadata by default.
- Never log audio samples or audio content.

## Disallowed For Core Mixer

| Item | Status | Reason |
| --- | --- | --- |
| Virtual microphone / virtual input device | Disallowed | macOS can treat it like input access and it enables recording-style workflows. |
| Microphone permission | Disallowed | The app does not need microphone input to control output volume. |
| `NSMicrophoneUsageDescription` | Disallowed unless a future ADR approves a real mic feature | Including it can normalize a permission VolDeck should not need. |
| `NSAudioCaptureUsageDescription` | Disallowed for core mixer | This belongs to system audio capture, not output-only mixing. |
| Screen recording permission | Disallowed for core mixer | Screen/audio capture is not needed for per-app output volume. |
| Network telemetry | Disallowed by default | VolDeck should be local-first. |

## Allowed With Review

| Item | Conditions |
| --- | --- |
| Local diagnostic logs | Must not include audio content, private filenames, URLs, or app usage timelines beyond what is needed for support. |
| Crash reporting | Future opt-in only, with a privacy policy update and ADR. |
| System audio recording | M8 only, optional, isolated from core mixer, with honest permission copy. |
| Audio Tap experiments | Research only unless an ADR changes the architecture. |

## Failure Signals

Any of these fail the current architecture gate:

- microphone permission prompt
- orange microphone indicator
- purple or other system-audio recording indicator during core mixing
- VolDeck appearing as an input device
- a recording app being able to select VolDeck as an input source
- always-on audio capture permission for the core mixer
- network requests from the app without an explicit opt-in feature

## Verification Checklist

Run this checklist at the end of M2 and again at the end of M3:

- [ ] Record macOS version, hardware, and date.
- [ ] Check System Settings privacy panes before install.
- [ ] Install or activate the prototype.
- [ ] Confirm VolDeck appears under Sound > Output.
- [ ] Confirm VolDeck does not appear under Sound > Input.
- [ ] Confirm no microphone prompt appears.
- [ ] Confirm no system audio recording prompt appears for the core path.
- [ ] Play audio for at least five minutes.
- [ ] Check menu bar and Control Center for mic or recording indicators.
- [ ] Quit helper/app and confirm output is restored or documented.
- [ ] Uninstall prototype and confirm VolDeck disappears.

## Principle For Future Features

If a feature needs capture permission, it must be optional, isolated, and named
honestly. It must not be bundled into the default path for per-app volume.

## Source Notes

- Apple documents a separate usage description key for system audio capture: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
- Rogue Amoeba documents that SoundSource/ARK requires System Audio Access and Microphone Access and may show a macOS-controlled system audio capture indicator: https://www.rogueamoeba.com/support/knowledgebase/?product=SoundSource&showArticle=Misc-ARK-Plugin-Audio-Capture-Details
