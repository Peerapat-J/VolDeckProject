#!/bin/sh
set -eu

build_root="${BUILD_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/VolDeckHALContractTests}"

/bin/rm -rf "$build_root"

xcodebuild \
  -quiet \
  -project VolDeck.xcodeproj \
  -scheme VolDeckHALPluginContractTests \
  -configuration Debug \
  -derivedDataPath "$build_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$build_root" \
  OBJROOT="$build_root/Intermediates" \
  SHARED_PRECOMPS_DIR="$build_root/SharedPrecompiledHeaders" \
  build

"$build_root/Debug/VolDeckHALPluginContractTests"
