# HAL Plugin Development

VolDeck's M2 prototype builds a CoreAudio AudioServerPlugIn bundle named
`VolDeckHALPlugin.driver`.

This is a development-only flow. Do not install the driver while active calls,
recording sessions, screen shares, or important playback sessions are running.
The M2 target is output-only and does not pass audio through to the real output
yet; selecting it as the current output can make audio silent until you switch
back to a real device.

## Build

```sh
xcodebuild \
  -project VolDeck.xcodeproj \
  -target VolDeckHALPlugin \
  -configuration Debug \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  SYMROOT="$PWD/build" \
  build
```

The built bundle should be at:

```text
build/Debug/VolDeckHALPlugin.driver
```

## Install

```sh
sudo mkdir -p /Library/Audio/Plug-Ins/HAL
sudo ditto build/Debug/VolDeckHALPlugin.driver /Library/Audio/Plug-Ins/HAL/VolDeckHALPlugin.driver
sudo killall coreaudiod
```

`coreaudiod` is restarted so the HAL host reloads available drivers. Audio may
drop briefly while it restarts.

## Inspect

Open System Settings > Sound and check both tabs:

- Output should list `VolDeck`.
- Input should not list `VolDeck`.

You can also inspect the system audio report:

```sh
system_profiler SPAudioDataType
```

For M2 privacy validation, record the macOS version, install time, Sound output
list, Sound input list, microphone permission state, and Control Center/menu bar
indicator state in a dated note under `docs/`.

## Restore Output

Before uninstalling, switch the current output device back to a real device in
System Settings > Sound > Output. If sound is already silent, use the built-in
speakers, headphones, HDMI/display audio, or another known-good device.

## Uninstall

```sh
sudo rm -rf /Library/Audio/Plug-Ins/HAL/VolDeckHALPlugin.driver
sudo killall coreaudiod
```

After `coreaudiod` restarts, confirm that `VolDeck` is gone from both Sound
Output and Sound Input.

## M2 Boundaries

- This target publishes one virtual output device and one output stream.
- It publishes no input stream.
- It does not request microphone, screen recording, system audio recording, or
  network access.
- It consumes output audio silently. Pass-through to the selected real output is
  M3 work.
