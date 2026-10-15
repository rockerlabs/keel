#!/usr/bin/env bash
# check-run — dir #855: run a check in ONE call and leave the evidence as files, so a later `verify` can
# decide from the files alone whether the run counts. /polish's test steps (3 and 6) use it: a receipt is
# written only behind a green `verify`, never because a model read the output as green.
#
# Usage:
#   tools/check-run.sh run    <dir> -- <cmd…>   run the command; evidence goes to <dir>
#   tools/check-run.sh verify <dir> -- <cmd…>   exit 0 only if <dir> holds a green run of THIS command at THIS state
#
# One argument after `--` runs as `bash -c "$1"` (a compound gate line); several run as argv.
#
# `run` creates <dir> if absent, removes any old exit/log/secs in it first, then writes:
#   head   `git rev-parse HEAD` (`none` outside git)
#   tree   `git status --porcelain --untracked-files=no` — tracked edits count, untracked scratch does not
#   cmd    the command exactly as given, one argument per line
#   log    the command's stdout + stderr
#   secs   wall-clock seconds
#   exit   the command's status — written LAST, via a temp file and `mv`. A run that is killed at any point
#          leaves no `exit`, and nothing here traps a signal to write one: no `exit` file means not green.
# It prints `check-run: exit=<n> secs=<s> head=<sha7> log=<dir>/log`, then the log's last 40 lines on a
# non-zero exit or the last 5 on zero, and exits with the command's own status.
#
# `verify` exits 0 only when all four hold: exit reads 0; head equals the current HEAD; tree equals the
# current porcelain status; cmd equals the given command argv-exact (so `-- 'a b'` is not `-- a b`).
# Otherwise it prints one reason line and exits 1: `not run` (no dir), `incomplete` (no exit), `exit=<n>`,
# `not a git repository`, `head moved <a> → <b>`, `tree changed`, `command differs`.
#
# Exit codes: 0 ok · 1 verify refused · 2 bad usage (a missing `--`, dir or command, an unknown subcommand)
# · otherwise `run` returns the command's status. Reads and writes no gate state; only the dir it is given.
set -u
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

usage() {
  printf 'usage: check-run.sh run|verify <dir> -- <cmd…>\n' >&2
  exit 2
}

[ $# -ge 2 ] || usage
sub="$1"; dir="$2"
shift 2
case "$sub" in run | verify) ;; *) usage ;; esac
[ -n "$dir" ] || usage
[ "${1:-}" = "--" ] || usage
shift
[ $# -ge 1 ] && [ -n "$1" ] || usage

case "$sub" in
  run)
    mkdir -p "$dir" || exit 2
    rm -f "$dir/exit" "$dir/log" "$dir/secs"
    head="$(git rev-parse HEAD 2>/dev/null)" || head=none
    printf '%s\n' "$head" > "$dir/head"
    git status --porcelain --untracked-files=no > "$dir/tree" 2>/dev/null
    printf '%s\n' "$@" > "$dir/cmd"
    start="$(date +%s)"
    if [ $# -eq 1 ]; then
      bash -c "$1" > "$dir/log" 2>&1
    else
      "$@" > "$dir/log" 2>&1
    fi
    rc=$?
    secs=$(( $(date +%s) - start ))
    printf '%s\n' "$secs" > "$dir/.secs.$$" && mv "$dir/.secs.$$" "$dir/secs"
    printf '%s\n' "$rc" > "$dir/.exit.$$" && mv "$dir/.exit.$$" "$dir/exit"
    printf 'check-run: exit=%s secs=%s head=%s log=%s/log\n' "$rc" "$secs" "$(printf '%s' "$head" | cut -c1-7)" "$dir"
    if [ "$rc" -ne 0 ]; then tail -n 40 "$dir/log"; else tail -n 5 "$dir/log"; fi
    exit "$rc"
    ;;
  verify)
    refuse() { printf 'check-run: verify refused: %s\n' "$1"; exit 1; }
    [ -d "$dir" ] || refuse "not run"
    [ -f "$dir/exit" ] || refuse "incomplete"
    code="$(cat "$dir/exit")"
    [ "$code" = 0 ] || refuse "exit=$code"
    cur_head="$(git rev-parse HEAD 2>/dev/null)" || refuse "not a git repository"
    old_head="$(cat "$dir/head" 2>/dev/null)"
    [ "$old_head" = "$cur_head" ] || refuse "head moved $(printf '%s' "$old_head" | cut -c1-7) → $(printf '%s' "$cur_head" | cut -c1-7)"
    [ "$(cat "$dir/tree" 2>/dev/null)" = "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] || refuse "tree changed"
    given="$(mktemp "${TMPDIR:-/tmp}/check-run-cmd.XXXXXX")" || refuse "no scratch file"
    printf '%s\n' "$@" > "$given"
    if cmp -s "$given" "$dir/cmd"; then same=1; else same=0; fi
    rm -f "$given"
    [ "$same" = 1 ] || refuse "command differs"
    exit 0
    ;;
esac
