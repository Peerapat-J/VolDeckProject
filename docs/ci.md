# CI

VolDeck uses GitHub Actions for early build verification.

## Current Workflow

Workflow: `.github/workflows/ci.yml`

The current CI job runs on pull requests and pushes to `dev` and `main`:

- check out the repo
- print the Xcode version
- list schemes in `VolDeck.xcodeproj`
- run the HAL safety guard
- build the `VolDeck` scheme in Debug with signing disabled
- analyze the `VolDeck` scheme in Debug with signing disabled
- build the `VolDeckHALPlugin` target in Debug with signing disabled
- analyze the `VolDeckHALPlugin` target in Debug with signing disabled
- build and run the HAL contract test executable

## Command

```sh
sh scripts/check_hal_safety.sh
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project VolDeck.xcodeproj -target VolDeckHALPlugin -configuration Debug CODE_SIGNING_ALLOWED=NO analyze
sh scripts/run_hal_contract_tests.sh
```

## Current Limitations

- CI builds the HAL plugin target but does not install or exercise it.
- CI validates the static no-capture/no-permission contract but does not validate OS privacy indicators, microphone permission prompts, or live output device publishing.
- CI does not run notarization, packaging, or release deployment.
- Live install/uninstall verification needs a real macOS test machine or self-hosted runner.

## CD Status

CD is intentionally deferred until signing, notarization, installer, and recovery
work are designed. Release automation belongs after the app has a safe
installer/uninstaller path.
