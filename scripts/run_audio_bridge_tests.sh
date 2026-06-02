#!/bin/sh
set -eu

build_parent="${BUILD_ROOT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
build_root="${build_parent%/}/VolDeckAudioBridgeTests"
bridge_file="$build_root/audio-bridge.bin"

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

xcodebuild \
  -quiet \
  -project VolDeck.xcodeproj \
  -scheme VolDeckOutputHelper \
  -configuration Debug \
  -derivedDataPath "$build_root/HelperDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$build_root" \
  OBJROOT="$build_root/HelperIntermediates" \
  SHARED_PRECOMPS_DIR="$build_root/HelperSharedPrecompiledHeaders" \
  build

helper="$build_root/Debug/VolDeckOutputHelper"
contract_tests="$build_root/Debug/VolDeckHALPluginContractTests"

require_executable() {
  executable_path="$1"
  executable_name="$2"
  if [ ! -f "$executable_path" ] || [ ! -x "$executable_path" ]; then
    printf 'error: expected executable %s at %s; re-run the build or inspect xcodebuild output.\n' "$executable_name" "$executable_path" >&2
    exit 1
  fi
}

assert_json_field() {
  json_payload="$1"
  field_name="$2"
  expected_value="$3"

  if command -v jq >/dev/null 2>&1; then
    actual_value="$(printf '%s\n' "$json_payload" | jq -r --arg field "$field_name" '.[$field]')"
  else
    if ! command -v python3 >/dev/null 2>&1; then
      printf 'error: jq or python3 is required to validate JSON output.\n' >&2
      exit 1
    fi

    actual_value="$(JSON_PAYLOAD="$json_payload" JSON_FIELD="$field_name" python3 -c 'import json, os; data = json.loads(os.environ["JSON_PAYLOAD"]); print(data[os.environ["JSON_FIELD"]])' 2>/dev/null)" || {
      printf 'error: could not parse JSON field %s from payload: %s\n' "$field_name" "$json_payload" >&2
      exit 1
    }
  fi

  if [ "$actual_value" != "$expected_value" ]; then
    printf 'error: expected JSON field %s=%s but got %s\npayload: %s\n' "$field_name" "$expected_value" "$actual_value" "$json_payload" >&2
    exit 1
  fi
}

require_executable "$helper" "VolDeckOutputHelper"
require_executable "$contract_tests" "VolDeckHALPluginContractTests"

cleanup() {
  VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-unlink >/dev/null 2>&1 || true
}
trap cleanup EXIT

VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" \
  VOLDECK_AUDIO_BRIDGE_KEEP_SHM=1 \
  "$contract_tests"

status_output="$(VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-status)"
assert_json_field "$status_output" event buffer
assert_json_field "$status_output" state ok
assert_json_field "$status_output" capacityFrames 8192
assert_json_field "$status_output" framesWritten 8192
assert_json_field "$status_output" framesAvailable 8192
assert_json_field "$status_output" writeCalls 3
assert_json_field "$status_output" overrunFrames 24
assert_json_field "$status_output" underrunFrames 4
assert_json_field "$status_output" indexAnomalies 0

read_output="$(VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-read-once 256)"
assert_json_field "$read_output" event buffer
assert_json_field "$read_output" state ok
assert_json_field "$read_output" framesRead 256
assert_json_field "$read_output" readCalls 1
assert_json_field "$read_output" lastReadFrames 256
assert_json_field "$read_output" framesAvailable 7936

printf 'VolDeck audio bridge tests passed\n'
