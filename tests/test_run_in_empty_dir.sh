#!/usr/bin/env bash
# test_run_in_empty_dir.sh — dir #478 regression: tests/lib.sh's run_in() guards a bad/nonexistent
# path with `cd "$dir" || {...}`, but `cd ""` is a silent bash no-op that returns 0 and leaves $PWD
# unchanged — reproduced live: `bash -c 'cd ""; echo $?; pwd'` prints 0 and the invocation directory.
# So an empty $dir never trips the guard, and `run_in` silently executes the command wherever the
# suite itself was invoked from — the real checkout when iterating locally. This file proves the
# fix fails LOUDLY on an empty dir instead of running the command in the invocation directory.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

before="$PWD"
run_in "" pwd

check_status "run_in(\"\") fails loudly instead of succeeding" 99 "$STATUS"
check_absent "run_in(\"\") must not execute the command in the invocation directory" "$OUT" "$before"

summary
