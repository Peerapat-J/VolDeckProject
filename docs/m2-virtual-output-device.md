# M2 Virtual Output Device

M2 starts the output-only HAL path chosen in ADR 0001. The first prototype is a
small AudioServerPlugIn bundle that can be built independently from the menu bar
app.

## Covered Issues

| Issue | Implementation |
| --- | --- |
| #12 `[M2][hal] Create minimal virtual output device` | `VolDeckHALPlugin` target, `VolDeckHALPlugin.driver`, plugin/device/output-stream object model |
| #13 `[M2][hal] Publish VolDeck as output-only device` | Input scope returns no streams and no stream configuration; output scope returns one stereo stream |
| #14 `[M2][hal] Support baseline stream formats` | 32-bit float stereo PCM at 44.1 kHz and 48 kHz is exposed as supported |
| #16 `[M2][docs] Document development install and uninstall for HAL plugin` | `docs/hal-plugin-development.md` |

## Target Shape

- Product: `VolDeckHALPlugin.driver`
- Bundle id: `com.peerapatj.voldeck.halplugin`
- Install path for development: `/Library/Audio/Plug-Ins/HAL`
- CoreAudio device UID: `com.peerapatj.voldeck.output`
- Device name: `VolDeck`
- Transport type: virtual
- Streams: one output stream, no input streams

## Current Behavior

The prototype implements the minimal HAL callbacks needed for object discovery,
property reads, basic sample-rate metadata, and output IO start/stop. The output
IO operation is accepted but not forwarded to a real device yet, so selecting
VolDeck as the system output can produce silence. Real output pass-through is
reserved for M3.

## Privacy Position

The plugin has no usage-description keys and no entitlements file. It does not
use capture APIs, microphone APIs, ScreenCaptureKit, networking, or HAL client
APIs inside the plugin.

Manual OS verification is still required for #15 because privacy prompts and
menu bar indicators are macOS runtime behavior.

## Test Coverage

- `VolDeckHALPluginContractTests` exercises plugin/device discovery, input and
  output stream configuration, sample-rate negotiation, IO start/stop state,
  supported IO operations, and timestamp behavior without installing the driver.
- `scripts/check_hal_safety.sh` blocks permission keys, capture APIs,
  microphone terminal types, network declarations, Mach services, and HAL client
  API calls from the M2 output-only path.
- `docs/driver-quality-gates.md` defines the driver testing rules that continue
  through M3 to M9.

## Build Validation

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO build
sh scripts/check_hal_safety.sh
sh scripts/run_hal_contract_tests.sh
```

## Manual Verification Checklist

- [ ] Output device appears as `VolDeck`.
- [ ] Input device does not appear as `VolDeck`.
- [ ] No microphone permission prompt appears.
- [ ] No system audio recording prompt appears.
- [ ] No orange mic indicator appears.
- [ ] No system-audio recording indicator appears.
- [ ] Uninstall removes the device.
- [ ] Real output can be restored.
