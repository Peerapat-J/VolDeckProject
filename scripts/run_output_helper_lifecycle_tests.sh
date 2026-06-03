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
helper_timeout_seconds="${HELPER_TEST_TIMEOUT_SECONDS:-5}"

health_output="$("$helper" --health-check)"
printf '%s\n' "$health_output" | /usr/bin/grep '"event":"health"' >/dev/null
printf '%s\n' "$health_output" | /usr/bin/grep '"state":"ok"' >/dev/null

device_output="$("$helper" --list-output-devices)"
printf '%s\n' "$device_output" | /usr/bin/grep '"event":"outputDevices"' >/dev/null
printf '%s\n' "$device_output" | /usr/bin/grep '"state":"ok"' >/dev/null
printf '%s\n' "$device_output" | /usr/bin/grep '"devices":\[' >/dev/null

run_input="$build_root/run-input.jsonl"
run_output_file="$build_root/run-output.jsonl"
run_timeout_marker="$build_root/run-output.timeout"
printf '%s\n' '{"command":"stop"}' >"$run_input"

"$helper" --run <"$run_input" >"$run_output_file" &
run_pid=$!

(
  sleep "$helper_timeout_seconds"
  if kill -0 "$run_pid" 2>/dev/null; then
    : >"$run_timeout_marker"
    kill "$run_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

set +e
wait "$run_pid"
run_status=$?
set -e

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

if [ -f "$run_timeout_marker" ]; then
  printf 'VolDeckOutputHelper did not exit within %s seconds.\n' "$helper_timeout_seconds" >&2
  exit 1
fi

if [ "$run_status" -ne 0 ]; then
  printf 'VolDeckOutputHelper exited with status %s.\n' "$run_status" >&2
  exit "$run_status"
fi

run_output="$(/bin/cat "$run_output_file")"
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
