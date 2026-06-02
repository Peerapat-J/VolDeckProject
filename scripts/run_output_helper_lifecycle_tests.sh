#!/bin/sh
set -eu

build_parent="${BUILD_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
build_root="${build_parent%/}/VolDeckOutputHelperTests"

/bin/rm -rf "$build_root"

xcodebuild \
  -quiet \
  -project VolDeck.xcodeproj \
  -scheme VolDeckOutputHelper \
  -configuration Debug \
  -derivedDataPath "$build_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$build_root" \
  OBJROOT="$build_root/Intermediates" \
  SHARED_PRECOMPS_DIR="$build_root/SharedPrecompiledHeaders" \
  build

helper="$build_root/Debug/VolDeckOutputHelper"

health_output="$("$helper" --health-check)"
printf '%s\n' "$health_output" | /usr/bin/grep '"event":"health"' >/dev/null
printf '%s\n' "$health_output" | /usr/bin/grep '"state":"ok"' >/dev/null

run_output="$(printf '%s\n' '{"command":"stop"}' | "$helper" --run)"
printf '%s\n' "$run_output" | /usr/bin/grep '"state":"starting"' >/dev/null
printf '%s\n' "$run_output" | /usr/bin/grep '"state":"running"' >/dev/null
printf '%s\n' "$run_output" | /usr/bin/grep '"state":"stopping"' >/dev/null

set +e
error_output="$("$helper" --unsupported 2>/dev/null)"
error_status=$?
set -e

if [ "$error_status" -eq 0 ]; then
  printf '%s\n' 'Expected unsupported helper arguments to fail.' >&2
  exit 1
fi

printf '%s\n' "$error_output" | /usr/bin/grep '"state":"error"' >/dev/null

printf 'VolDeckOutputHelper lifecycle tests passed\n'
