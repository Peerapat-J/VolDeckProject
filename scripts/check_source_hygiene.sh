#!/bin/sh
set -eu

failure_count=0
tracked_files="$(mktemp)" || {
  printf '%s\n' 'Unable to create temporary file list for source hygiene checks.' >&2
  exit 1
}
trap 'rm -f "$tracked_files"' EXIT

git ls-files \
  '*.c' \
  '*.h' \
  '*.md' \
  '*.plist' \
  '*.pbxproj' \
  '*.sh' \
  '*.swift' \
  '*.xcscheme' \
  '*.yaml' \
  '*.yml' >"$tracked_files"

while IFS= read -r file_path; do
  if /usr/bin/grep -n -E '[[:blank:]]$' "$file_path" >/dev/null 2>&1; then
    /usr/bin/grep -n -E '[[:blank:]]$' "$file_path" >&2
    printf 'error: trailing whitespace found in %s\n' "$file_path" >&2
    failure_count=$((failure_count + 1))
  fi

  if [ -s "$file_path" ]; then
    last_byte="$(tail -c 1 "$file_path" | od -An -t x1 | tr -d ' \n')"
    if [ "$last_byte" != "0a" ]; then
      printf 'error: missing final newline in %s\n' "$file_path" >&2
      failure_count=$((failure_count + 1))
    fi
  fi
done <"$tracked_files"

for script_path in scripts/*.sh; do
  sh -n "$script_path"
done

if [ "$failure_count" -ne 0 ]; then
  printf 'Source hygiene checks failed with %d issue(s).\n' "$failure_count" >&2
  exit 1
fi

printf 'Source hygiene checks passed\n'
