# CI

VolDeck uses GitHub Actions for pull-request and push verification.

## Current Workflow

Workflow: `.github/workflows/ci.yml`

The current CI job runs on pull requests and pushes to `dev` and `main`:

- check out the repo
- print the Xcode version
- list schemes in `VolDeck.xcodeproj`
- run source hygiene checks for trailing whitespace, final newlines, and shell
  syntax
- install SwiftLint when the runner does not already provide it
- run the repo's SwiftLint hygiene rules
- run the HAL safety guard
- build the `VolDeck` scheme in Debug with signing disabled
- analyze the `VolDeck` scheme in Debug with signing disabled
- run app recovery behavior tests
- run session identity behavior tests
- build the `VolDeckOutputHelper` target in Debug with signing disabled
- analyze the `VolDeckOutputHelper` target in Debug with signing disabled
- build the `VolDeckHALPlugin` target in Debug with signing disabled
- analyze the `VolDeckHALPlugin` target in Debug with signing disabled
- build and run the HAL contract test executable
- build and run the HAL-to-helper audio bridge tests
- build and run the output helper lifecycle tests

## Command

```sh
sh scripts/check_source_hygiene.sh
command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
sh scripts/run_swiftlint.sh
sh scripts/check_hal_safety.sh
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
sh scripts/run_app_recovery_behavior_tests.sh
sh scripts/run_session_identity_behavior_tests.sh
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckOutputHelper -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckOutputHelper -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
sh scripts/run_hal_contract_tests.sh
sh scripts/run_audio_bridge_tests.sh
sh scripts/run_output_helper_lifecycle_tests.sh
```

## Current Limitations

- CI builds the HAL plugin target but does not install or exercise it.
- CI validates the static no-capture/no-permission contract but does not
  validate OS privacy indicators, microphone permission prompts, or live output
  device publishing.
- SwiftLint currently runs a narrow hygiene rule set; full style reformatting is
  not yet enforced.
- CI does not run notarization, packaging, or release deployment.
- Live install/uninstall verification needs a real macOS test machine or self-hosted runner.

## CD Status

CD is intentionally deferred until signing, notarization, installer, and recovery
work are designed. Release automation belongs after the app has a safe
installer/uninstaller path.
