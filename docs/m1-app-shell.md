# M1 App Shell

This milestone creates the first runnable macOS app shell as an Xcode project.
It intentionally does not activate any audio driver, helper process, audio
capture API, or network behavior.

## Covered Issues

| Issue | Implementation |
| --- | --- |
| #7 `[M1][app] Create macOS menu bar app skeleton` | `VolDeck.xcodeproj`, `VolDeck/VolDeckApp.swift`, `MenuBarExtra`, quit action |
| #8 `[M1][app] Add menu bar mixer popover shell` | `MenuBarRootView`, `AppVolumeRow`, eight disabled placeholder app rows, output selector placeholder |
| #9 `[M1][app] Add settings window and local preferences` | `SettingsView`, `AppPreferences`, local `UserDefaults` wrapper |
| #10 `[M1][app] Add launch-at-login preference` | `AppPreferences.setLaunchAtLoginEnabled(_:)` using `SMAppService.mainApp` |
| #11 `[M1][privacy] Add local-first privacy copy and diagnostics switch` | Privacy and diagnostics tabs in `SettingsView` |

## App Shape

- macOS SwiftUI app inside `VolDeck.xcodeproj`.
- Shared scheme: `VolDeck`.
- Menu bar only via `MenuBarExtra`.
- Generated Info.plist includes `LSUIElement = true`.
- Deployment target: macOS 14.0.
- Bundle id: `com.peerapatj.voldeck`.

## Placeholder Rules

The M1 mixer rows are disabled preview controls. They show expected layout and
information density without pretending to control real audio.

## Privacy Validation

The built app's Info.plist contains no usage-description keys for:

- microphone
- system audio capture
- screen recording
- camera
- Apple Events

The app has no entitlements file, no network code, and no audio backend in M1.

## Build Validation

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Result: passed on Xcode 26.5.

## Launch Validation

The Debug build launched locally from DerivedData and was then stopped:

```sh
open -n ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/VolDeck.app
```

The app process started successfully. No driver, helper, audio permission, or
network behavior was activated.
