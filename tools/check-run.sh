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
#   tree   `git status --porcelain --untracked-files=no`, then a checksum of `git diff HEAD` — tracked edits count
#          (a second edit to an already-dirty file too: the status text alone would not change), untracked scratch
#          does not
#   cmd    the command exactly as given, one argument per line
#   log    the command's stdout + stderr
#   secs   wall-clock seconds
#   exit   the command's status — written LAST, via a temp file and `mv`. A run that is killed at any point
#          leaves no `exit`, and nothing here traps a signal to write one: no `exit` file means not green.
# It prints `check-run: exit=<n> secs=<s> head=<sha7> log=<dir>/log`, then the log's last 40 lines on a
# non-zero exit or the last 5 on zero, and exits with the command's own status.
#
# `verify` exits 0 only when all four hold: exit reads 0; head equals the current HEAD; tree equals the
# current tree state; cmd equals the given command argv-exact (so `-- 'a b'` is not `-- a b`).
# Otherwise it prints one reason line and exits 1: `not run` (no dir), `incomplete` (no exit), `exit=<n>`,
# `not a git repository`, `head moved <a> → <b>`, `tree changed`, `command differs`.
#
# Exit codes: 0 ok · 1 verify refused · 2 bad usage (a missing `--`, dir or command, an unknown subcommand,
# or a `run` <dir> that is the work-tree root or holds a tracked/directory entry named like a record, dir #883)
# · otherwise `run` returns the command's status. Reads and writes no gate state; only the dir it is given.
# `verify` is deliberately stricter than the gate's own test-relevance rule (`_test_relevant_tree_hash`, dir #123):
# any tracked edit after the run refuses, a documentation-only one included. Residuals, accepted (dir #855):
#   - cmd is one argument per line, so one argument holding a newline equals the same words as separate arguments;
#   - one run per <dir> at a time — two runs sharing a dir can leave one's exit beside the other's head/tree/cmd;
#   - tree is taken before the command runs, so a command that rewrites a tracked file refuses its own verify.
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

# The tracked-tree state `run` records and `verify` compares.
tree_state() {
  git status --porcelain --untracked-files=no 2>/dev/null
  git diff --no-ext-diff HEAD 2>/dev/null | cksum
}

case "$sub" in
  run)
    # dir #883: refuse the work-tree root and a <dir> whose record names are tracked files or directories.
    if [ -d "$dir" ]; then
      phys="$(cd "$dir" 2>/dev/null && pwd -P)" || exit 2
      top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || top=
      if [ -n "$top" ] && [ "$phys" = "$(cd "$top" && pwd -P)" ]; then
        printf 'check-run: refused: <dir> %s is the work-tree root; use a fresh mktemp -d\n' "$dir" >&2
        exit 2
      fi
      for f in head tree cmd log secs exit; do
        if [ -d "$dir/$f" ] || [ -L "$dir/$f" ] || git -C "$dir" ls-files --error-unmatch -- "$f" > /dev/null 2>&1; then
          printf 'check-run: refused: <dir>/%s is a tracked file or a directory, not a record; use a fresh mktemp -d\n' "$f" >&2
          exit 2
        fi
      done
    fi
    mkdir -p "$dir" || exit 2
    rm -f "$dir/exit" "$dir/log" "$dir/secs"
    head="$(git rev-parse HEAD 2>/dev/null)" || head=none
    printf '%s\n' "$head" > "$dir/head"
    tree_state > "$dir/tree"
    printf '%s\n' "$@" > "$dir/cmd"
    SECONDS=0
    if [ $# -eq 1 ]; then
      bash -c "$1" > "$dir/log" 2>&1
    else
      "$@" > "$dir/log" 2>&1
    fi
    rc=$?
    secs=$SECONDS
    printf '%s\n' "$secs" > "$dir/secs"
    printf '%s\n' "$rc" > "$dir/.exit.$$" && mv "$dir/.exit.$$" "$dir/exit"
    printf 'check-run: exit=%s secs=%s head=%s log=%s/log\n' "$rc" "$secs" "${head:0:7}" "$dir"
    if [ "$rc" -ne 0 ]; then tail -n 40 "$dir/log"; else tail -n 5 "$dir/log"; fi
    exit "$rc"
    ;;
  verify)
    refuse() { printf 'check-run: verify refused: %s\n' "$1"; exit 1; }
    [ -d "$dir" ] || refuse "not run"
    [ -f "$dir/exit" ] || refuse "incomplete"
    code="$(<"$dir/exit")"
    [ "$code" = 0 ] || refuse "exit=$code"
    cur_head="$(git rev-parse HEAD 2>/dev/null)" || refuse "not a git repository"
    old_head="$(<"$dir/head")"
    [ "$old_head" = "$cur_head" ] || refuse "head moved ${old_head:0:7} → ${cur_head:0:7}"
    [ "$(<"$dir/tree")" = "$(tree_state)" ] || refuse "tree changed"
    printf '%s\n' "$@" | cmp -s - "$dir/cmd" || refuse "command differs"
    exit 0
    ;;
esac
