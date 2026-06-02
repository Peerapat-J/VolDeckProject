# Driver Quality Gates

VolDeck treats HAL and driver-like code as safety-critical infrastructure. A
successful build is not enough to merge driver behavior.

## Always-on CI Gates

- Build the SwiftUI app target.
- Build the HAL plugin target.
- Build and run HAL contract tests.
- Run Xcode static analysis for driver-related targets.
- Run the HAL safety guard script.
- Keep warning-as-error settings enabled for the HAL plugin and contract test
  targets.

## HAL Contract Tests

The contract test executable exercises the AudioServerPlugIn callbacks without
installing the driver into `/Library/Audio/Plug-Ins/HAL`. It must cover the
driver property model whenever the HAL surface changes:

- plugin-to-device discovery
- device UID translation
- output stream list
- empty input stream list
- input and output stream configuration
- default-device flags by scope
- stream direction and terminal type
- supported sample rates and rejection of unsupported formats
- IO start/stop state
- allowed and rejected IO operations
- timestamp contract

## Static Safety Guard

`scripts/check_hal_safety.sh` prevents accidental drift away from the M2 privacy
contract. It fails if core HAL/plugin code adds microphone or capture permission
keys, capture APIs, microphone terminal types, network access, Mach services, or
HAL client API calls from inside the AudioServerPlugIn host.

## Runtime Gates

Runtime behavior still needs manual or self-hosted macOS verification because
System Settings, privacy prompts, and menu bar indicators are OS behavior. Before
release-quality milestones, test on real macOS hardware:

- install the `.driver`
- restart `coreaudiod`
- confirm VolDeck appears in Sound Output
- confirm VolDeck does not appear in Sound Input
- confirm no microphone prompt appears
- confirm no orange microphone indicator appears
- confirm no system-audio recording indicator appears
- uninstall the `.driver`
- confirm the device disappears
- restore a real output device

## Milestone Expectations

- M2: contract tests and static guard are required; runtime privacy checks are
  recorded manually.
- M3: helper lifecycle, HAL-to-helper buffering, output restore, and buffer
  diagnostics must be tested or explicitly deferred before pass-through is
  treated as safe.
- M4-M5: session mapping and mixer changes must extend contract tests before
  changing driver behavior.
- M7: installer, uninstaller, reset, and recovery flows need runtime integration
  tests on real macOS hardware or a self-hosted runner.
- M9: private alpha cannot proceed until all manual runtime gates have dated
  evidence for the supported macOS/hardware matrix.
