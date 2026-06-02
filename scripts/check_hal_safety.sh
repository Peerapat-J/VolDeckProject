#!/bin/sh
set -eu

failure_count=0

fail() {
  printf '%s\n' "$1" >&2
  failure_count=$((failure_count + 1))
}

assert_no_match() {
  pattern="$1"
  path="$2"
  message="$3"

  if /usr/bin/grep -R -n -E "$pattern" "$path" >/tmp/voldeck-hal-guard.matches 2>/dev/null; then
    /bin/cat /tmp/voldeck-hal-guard.matches >&2
    fail "$message"
  fi
}

assert_plist_key_absent() {
  key="$1"
  plist="$2"
  message="$3"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    fail "$message"
  fi
}

assert_no_match 'NS(Microphone|AudioCapture|Camera|ScreenCapture)UsageDescription' 'VolDeck' 'Core app target must not add capture or microphone usage-description keys.'
assert_no_match 'NS(Microphone|AudioCapture|Camera|ScreenCapture)UsageDescription' 'VolDeckHALPlugin' 'HAL plugin must not add capture or microphone usage-description keys.'
assert_no_match 'ScreenCaptureKit|AVCapture|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AudioHardwareCreate(ProcessTap|AggregateDevice)|CATapDescription' 'VolDeckHALPlugin' 'HAL plugin must not use capture-oriented APIs in the M2 output-only path.'
assert_no_match 'AudioObject(Get|Set)PropertyData|AudioDevice(Start|Stop|CreateIOProcID)' 'VolDeckHALPlugin' 'AudioServerPlugIn code must not call HAL client APIs from inside the plugin host.'
assert_no_match 'kAudioStreamTerminalType(HeadsetMicrophone|ReceiverMicrophone|Microphone)' 'VolDeckHALPlugin' 'HAL plugin must not publish microphone terminal types.'

assert_plist_key_absent 'AudioServerPlugIn_MachServices' 'VolDeckHALPlugin/Info.plist' 'M2 HAL plugin must not declare Mach services yet.'
assert_plist_key_absent 'AudioServerPlugIn_Network' 'VolDeckHALPlugin/Info.plist' 'M2 HAL plugin must not declare network access.'

factory_type=$(/usr/libexec/PlistBuddy -c 'Print :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0' VolDeckHALPlugin/Info.plist 2>/dev/null || true)
if [ "$factory_type" != '66D12494-2B15-4B0F-A365-8792182174C4' ]; then
  fail 'HAL plugin Info.plist must register an AudioServerPlugIn factory.'
fi

if [ "$failure_count" -ne 0 ]; then
  printf 'HAL safety guard failed with %d issue(s).\n' "$failure_count" >&2
  exit 1
fi

printf 'HAL safety guard passed\n'
