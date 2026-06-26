#!/usr/bin/env bash
# Keel test runner — execute every tests/test_*.sh in its own process and aggregate.
# Each test file sets up (and tears down) its own isolated sandbox HOME, so files run
# independently. Exit non-zero if any file reports a failure.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

failed=0
for t in "$here"/test_*.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || failed=$((failed + 1))
done

printf '\n========================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'ALL TEST FILES PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$failed"
exit 1
