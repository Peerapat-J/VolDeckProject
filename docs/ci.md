# CI

VolDeck uses GitHub Actions for early build verification.

## Current Workflow

Workflow: `.github/workflows/ci.yml`

The current CI job runs on pull requests and pushes to `dev` and `main`:

- check out the repo
- print the Xcode version
- list schemes in `VolDeck.xcodeproj`
- build the `VolDeck` scheme in Debug with signing disabled

## Command

```sh
xcodebuild -quiet -project VolDeck.xcodeproj -scheme VolDeck -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Current Limitations

- CI does not install or exercise HAL/plugin components.
- CI does not validate privacy indicators, microphone permission prompts, or output device publishing.
- CI does not run notarization, packaging, or release deployment.
- There are no unit tests yet, so this workflow is build-only for now.

## CD Status

CD is intentionally deferred until signing, notarization, installer, and recovery
work are designed. Release automation belongs after the app has a safe
installer/uninstaller path.
