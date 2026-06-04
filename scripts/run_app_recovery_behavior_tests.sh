#!/bin/sh
set -eu

build_parent="${BUILD_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
build_root="${build_parent%/}/VolDeckAppRecoveryBehaviorTests"

/bin/rm -rf "$build_root"
/bin/mkdir -p "$build_root"

xcrun swiftc \
  -parse-as-library \
  -module-cache-path "$build_root/ModuleCache" \
  -framework AppKit \
  -framework Combine \
  -framework CoreAudio \
  -framework ServiceManagement \
  -o "$build_root/VolDeckAppRecoveryBehaviorTests" \
  VolDeck/Models/AppPreferences.swift \
  VolDeck/Models/OutputHelperController.swift \
  VolDeckAppBehaviorTests/RecoveryTargetBehaviorTests.swift

"$build_root/VolDeckAppRecoveryBehaviorTests"
