#!/bin/sh
set -eu

failure_count=0
matches_file="$(mktemp)" || {
  printf '%s\n' 'Unable to create temporary match file for HAL safety guard.' >&2
  exit 1
}
trap 'rm -f "$matches_file"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  failure_count=$((failure_count + 1))
}

assert_no_match() {
  pattern="$1"
  path="$2"
  message="$3"

  if /usr/bin/grep -R -n -E "$pattern" "$path" >"$matches_file" 2>/dev/null; then
    /bin/cat "$matches_file" >&2
    fail "$message"
  fi
}

assert_match() {
  pattern="$1"
  path="$2"
  message="$3"

  if ! /usr/bin/grep -R -n -E "$pattern" "$path" >"$matches_file" 2>/dev/null; then
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
assert_no_match 'NS(Microphone|AudioCapture|Camera|ScreenCapture)UsageDescription' 'VolDeckOutputHelper' 'Output helper must not add capture or microphone usage-description keys.'
assert_no_match 'NS(Microphone|AudioCapture|Camera|ScreenCapture)UsageDescription' 'VolDeckHALPlugin' 'HAL plugin must not add capture or microphone usage-description keys.'
assert_no_match 'NSURLSession|NSURLConnection|dataTaskWithURL|URLSession|NSURL|CFNetwork|CFSocket|Network\.framework|Network/Network\.h|NW(Connection|Listener|Endpoint|Path|Parameters|Protocol|Browser)|nw_[[:alnum:]_]+[[:space:]]*\(|socket[[:space:]]*\(|getaddrinfo[[:space:]]*\(|connect[[:space:]]*\(|send[[:space:]]*\(|recv[[:space:]]*\(|curl_easy_[[:alnum:]_]+' 'VolDeck' 'Core app target must not use network APIs in the local-first M3 path.'
assert_no_match 'ScreenCaptureKit|AVCapture|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AudioHardwareCreate(ProcessTap|AggregateDevice)|CATapDescription' 'VolDeckOutputHelper' 'Output helper must not use capture-oriented APIs in the M3 pass-through path.'
assert_no_match 'ScreenCaptureKit|AVCapture|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AudioHardwareCreate(ProcessTap|AggregateDevice)|CATapDescription' 'VolDeckHALPlugin' 'HAL plugin must not use capture-oriented APIs in the M2 output-only path.'
assert_no_match 'AudioObject(Get|Set)PropertyData|AudioDevice(Start|Stop|CreateIOProcID)' 'VolDeckHALPlugin' 'AudioServerPlugIn code must not call HAL client APIs from inside the plugin host.'
assert_no_match 'kAudioStreamTerminalType(HeadsetMicrophone|ReceiverMicrophone|Microphone)' 'VolDeckHALPlugin' 'HAL plugin must not publish microphone terminal types.'
assert_no_match 'NSURLSession|NSURLConnection|dataTaskWithURL|URLSession|NSURL|CFNetwork|CFSocket|Network\.framework|Network/Network\.h|NW(Connection|Listener|Endpoint|Path|Parameters|Protocol|Browser)|nw_[[:alnum:]_]+[[:space:]]*\(|socket[[:space:]]*\(|getaddrinfo[[:space:]]*\(|connect[[:space:]]*\(|send[[:space:]]*\(|recv[[:space:]]*\(|curl_easy_[[:alnum:]_]+' 'VolDeckOutputHelper' 'Output helper must not use network APIs or frameworks in the M3 pass-through path.'
assert_no_match 'NSURLSession|NSURLConnection|dataTaskWithURL|URLSession|NSURL|CFNetwork|CFSocket|Network\.framework|Network/Network\.h|NW(Connection|Listener|Endpoint|Path|Parameters|Protocol|Browser)|nw_[[:alnum:]_]+[[:space:]]*\(|socket[[:space:]]*\(|getaddrinfo[[:space:]]*\(|connect[[:space:]]*\(|send[[:space:]]*\(|recv[[:space:]]*\(|curl_easy_[[:alnum:]_]+' 'VolDeckHALPlugin' 'HAL plugin must not use network APIs or frameworks in the M2 output-only path.'

assert_match 'restorePreviousOutputAfterUnexpectedTermination' 'VolDeck/Models/OutputHelperController.swift' 'Output helper controller must attempt previous-output restore after unexpected helper termination.'
assert_match 'AudioObjectSetPropertyData' 'VolDeck/Models/AppPreferences.swift' 'App output catalog must keep a CoreAudio default-output restore path.'
assert_match 'System Settings > Sound' 'VolDeck/Models/OutputHelperController.swift' 'Restore failures must include manual Sound settings recovery instructions.'
assert_match 'removeObject\(forKey: RecoveryKeys\.previousOutputDeviceID\)' 'VolDeck/Models/OutputHelperController.swift' 'Previous-output recovery state must clear stale device IDs when no real default output can be remembered.'
assert_match 'rememberPreviousOutputForRecovery\(fallbackOutputDeviceUID: outputDeviceUID\)' 'VolDeck/Models/OutputHelperController.swift' 'Output helper controller must fall back to the selected real output as the recovery target.'
assert_match 'realOutputDevice\(id: fallbackOutputDeviceUID\)' 'VolDeck/Models/OutputHelperController.swift' 'Output helper controller must resolve the selected output before clearing recovery state.'
assert_no_match 'expectedTermination[[:space:]]*\|\|[[:space:]]*terminatedProcess\.terminationStatus[[:space:]]*==[[:space:]]*0' 'VolDeck/Models/OutputHelperController.swift' 'Unexpected zero-exit helper terminations must still run output recovery.'
assert_match 'didBridgeFormatChange' 'VolDeckOutputHelper/main.swift' 'Output helper must restart playback when the bridge format changes in place.'

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
