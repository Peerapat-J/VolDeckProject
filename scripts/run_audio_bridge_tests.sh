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

cleanup() {
  VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-unlink >/dev/null 2>&1 || true
}
trap cleanup EXIT

VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" \
  VOLDECK_AUDIO_BRIDGE_KEEP_SHM=1 \
  "$contract_tests"

status_output="$(VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-status)"
printf '%s\n' "$status_output" | /usr/bin/grep '"event":"buffer"' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"state":"ok"' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"capacityFrames":8192' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"framesWritten":8192' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"framesAvailable":8192' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"writeCalls":3' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"overrunFrames":24' >/dev/null
printf '%s\n' "$status_output" | /usr/bin/grep '"underrunFrames":4' >/dev/null

read_output="$(VOLDECK_AUDIO_BRIDGE_FILE_PATH="$bridge_file" "$helper" --buffer-read-once 256)"
printf '%s\n' "$read_output" | /usr/bin/grep '"event":"buffer"' >/dev/null
printf '%s\n' "$read_output" | /usr/bin/grep '"state":"ok"' >/dev/null
printf '%s\n' "$read_output" | /usr/bin/grep '"framesRead":256' >/dev/null
printf '%s\n' "$read_output" | /usr/bin/grep '"readCalls":1' >/dev/null
printf '%s\n' "$read_output" | /usr/bin/grep '"lastReadFrames":256' >/dev/null
printf '%s\n' "$read_output" | /usr/bin/grep '"framesAvailable":7936' >/dev/null

printf 'VolDeck audio bridge tests passed\n'
