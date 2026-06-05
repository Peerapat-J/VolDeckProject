#!/bin/sh
set -eu

if ! command -v swiftlint >/dev/null 2>&1; then
  printf '%s\n' 'error: swiftlint is required. Install it with `brew install swiftlint`.' >&2
  exit 1
fi

swiftlint lint --quiet --no-cache --strict --config .swiftlint.yml
