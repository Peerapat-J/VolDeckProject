#!/bin/sh
set -eu

build_parent="${BUILD_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
build_root="${build_parent%/}/VolDeckSessionIdentityBehaviorTests"

/bin/rm -rf "$build_root"
/bin/mkdir -p "$build_root"

xcrun swiftc \
  -parse-as-library \
  -module-cache-path "$build_root/ModuleCache" \
  -framework AppKit \
  -o "$build_root/VolDeckSessionIdentityBehaviorTests" \
  VolDeck/Models/AudioSessionModels.swift \
  VolDeckAppBehaviorTests/SessionIdentityBehaviorTests.swift

"$build_root/VolDeckSessionIdentityBehaviorTests"
