#!/usr/bin/env bash
# tests/test_check_run.sh — dir #855: tools/check-run.sh, the one-call check runner /polish's test steps use.
# Spec: docs/specs/855-polish-step-offload.md (gitignored, main checkout) — acceptance A1 (`run`) and A2
# (`verify`). `run` leaves its evidence as files in a directory; `verify` decides from those files alone
# whether the run counts: exit 0, same HEAD, same tracked tree, same command. A killed run leaves no `exit`.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/check-run.sh"
check_file "tools/check-run.sh exists" "$tool"

# A fixture repo with one commit; prints its path.
mkrepo() {
  local d; d="$(new_repo)"
  git -C "$d" commit --allow-empty -qm init
  printf '%s' "$d"
}
cr() { run_in "$cwd" bash "$tool" "$@"; }   # sets OUT, STATUS; $cwd is the directory the tool runs from

cwd="$(mkrepo)"
rd="$SANDBOX/rd.pass"

# --- A1 (i): pass ------------------------------------------------------------------------------------------
cr run "$rd" -- true
check_status "A1 i: a passing command → status 0" 0 "$STATUS"
check_eq "A1 i: exit file reads 0" "0" "$(cat "$rd/exit" 2>/dev/null)"
check_contains "A1 i: the summary line leads with exit=0" "$OUT" "check-run: exit=0 secs="
check_contains "A1 i: the summary line names the short head" "$OUT" "head=$(git -C "$cwd" rev-parse HEAD | cut -c1-7)"
check_contains "A1 i: the summary line names the log" "$OUT" "log=$rd/log"
check_file "A1 i: secs file written" "$rd/secs"
check_eq "A1 i: head file is the full HEAD" "$(git -C "$cwd" rev-parse HEAD)" "$(cat "$rd/head" 2>/dev/null)"
check_eq "A1 i: tree file on a clean tree is just the diff checksum line" "1" "$(wc -l < "$rd/tree" | tr -d ' ')"
cr run "$SANDBOX/rd.five" -- bash -c 'for i in 1 2 3 4 5 6 7 8; do echo line$i; done'
check_contains "A1 i: a pass shows the log's last 5 lines" "$OUT" "line8"
check_contains "A1 i: …including the fourth from last" "$OUT" "line4"
check_absent "A1 i: …and no more than 5" "$OUT" "line3"

# --- A1 (ii): fail -----------------------------------------------------------------------------------------
cr run "$SANDBOX/rd.fail" -- sh -c 'echo boom; exit 3'
check_status "A1 ii: a failing command → its status" 3 "$STATUS"
check_eq "A1 ii: exit file reads 3" "3" "$(cat "$SANDBOX/rd.fail/exit" 2>/dev/null)"
check_contains "A1 ii: the summary line says exit=3" "$OUT" "check-run: exit=3"
check_contains "A1 ii: the failing output is shown" "$OUT" "boom"
cr run "$SANDBOX/rd.fail40" -- bash -c 'for i in $(seq 1 60); do echo row$i; done; exit 1'
check_contains "A1 ii: a failure shows the last 40 lines (row60)" "$OUT" "row60"
check_contains "A1 ii: …down to row21" "$OUT" "row21"
check_absent "A1 ii: …and not row20" "$OUT" "row20"

# --- A1 (iii): one argument → bash -c; several → argv ----------------------------------------------------------
cr run "$SANDBOX/rd.one" -- 'echo a && echo b'
check_status "A1 iii: one string runs through bash -c (&& works)" 0 "$STATUS"
check_contains "A1 iii: …both halves ran" "$(cat "$SANDBOX/rd.one/log")" "b"
cr run "$SANDBOX/rd.argv" -- printf '[%s]\n' 'a b' c
check_contains "A1 iii: several arguments run as argv; a quoted space survives" "$(cat "$SANDBOX/rd.argv/log")" "[a b]"
check_eq "A1 iii: cmd records one argument per line" "printf
[%s]\n
a b
c" "$(cat "$SANDBOX/rd.argv/cmd")"

# --- A1 (iv): a rerun in the same dir removes the old exit while the new run is alive -----------------------------
rd4="$SANDBOX/rd.rerun"
cr run "$rd4" -- true
check_file "A1 iv: first run left an exit" "$rd4/exit"
( cd "$cwd" && bash "$tool" run "$rd4" -- bash -c "touch '$SANDBOX/rerun.ready'; sleep 2" >/dev/null 2>&1 ) &
rerun_pid=$!
wait_ready "$SANDBOX/rerun" "$rerun_pid"
check_nofile "A1 iv: the old exit is gone while the new run is in flight" "$rd4/exit"
check_nofile "A1 iv: the old secs is gone too" "$rd4/secs"
wait "$rerun_pid" 2>/dev/null
check_eq "A1 iv: the rerun then writes its own exit" "0" "$(cat "$rd4/exit" 2>/dev/null)"

# --- A1 (v): a SIGTERM'd run leaves no exit --------------------------------------------------------------------
rd5="$SANDBOX/rd.killed"
( cd "$cwd" && exec bash "$tool" run "$rd5" -- bash -c "touch '$SANDBOX/kill.ready'; sleep 2" >/dev/null 2>&1 ) &
kill_pid=$!
wait_ready "$SANDBOX/kill" "$kill_pid"
kill -TERM "$kill_pid" 2>/dev/null
wait "$kill_pid" 2>/dev/null
sleep 3   # past the orphaned command's own end: nothing may write an exit afterwards either
check_nofile "A1 v: a killed run leaves no exit" "$rd5/exit"
check_nofile "A1 v: …and no secs" "$rd5/secs"

# --- A1 (vi): two dirs, two concurrent runs, no cross-talk ------------------------------------------------------
( cd "$cwd" && bash "$tool" run "$SANDBOX/rd.A" -- bash -c 'sleep 1; echo from-A' >/dev/null 2>&1 ) &
pa=$!
( cd "$cwd" && bash "$tool" run "$SANDBOX/rd.B" -- bash -c 'sleep 1; echo from-B; exit 4' >/dev/null 2>&1 ) &
pb=$!
wait "$pa" 2>/dev/null; wait "$pb" 2>/dev/null
check_eq "A1 vi: run A's exit" "0" "$(cat "$SANDBOX/rd.A/exit" 2>/dev/null)"
check_eq "A1 vi: run B's exit" "4" "$(cat "$SANDBOX/rd.B/exit" 2>/dev/null)"
check_contains "A1 vi: run A's log is its own" "$(cat "$SANDBOX/rd.A/log" 2>/dev/null)" "from-A"
check_absent "A1 vi: …without B's output" "$(cat "$SANDBOX/rd.A/log" 2>/dev/null)" "from-B"
check_absent "A1 vi: run B's log is without A's output" "$(cat "$SANDBOX/rd.B/log" 2>/dev/null)" "from-A"

# --- A1 (vii): bad input → 2 -----------------------------------------------------------------------------------
cr run "$SANDBOX/rd.bad1" true
check_status "A1 vii: no -- → 2" 2 "$STATUS"
check_contains "A1 vii: …with usage" "$OUT" "usage"
cr run "$SANDBOX/rd.bad2" --
check_status "A1 vii: no command → 2" 2 "$STATUS"
cr run "$SANDBOX/rd.bad3" -- ""
check_status "A1 vii: an empty command → 2" 2 "$STATUS"
cr run
check_status "A1 vii: no dir → 2" 2 "$STATUS"
cr frobnicate "$SANDBOX/rd.bad4" -- true
check_status "A1 vii: an unknown subcommand → 2" 2 "$STATUS"
cr verify "$SANDBOX/rd.bad5" true
check_status "A1 vii: verify without -- → 2" 2 "$STATUS"
check_nodir "A1 vii: a refused run created no dir" "$SANDBOX/rd.bad1"

# --- dir #883: <dir> must not be the work-tree root, nor hold a tracked file named like a record -----------------
# `run` writes and removes head/tree/cmd/log/secs/exit in <dir>; in a repo root that is six untracked records
# (or four tracked files replaced). Refuse with 2 and touch nothing.
rootrepo="$(mkrepo)"
run_in "$rootrepo" bash "$tool" run . -- true
check_status "dir #883: run . at the work-tree root → 2" 2 "$STATUS"
check_contains "dir #883: …says why" "$OUT" "work-tree root"
check_eq "dir #883: …and wrote no record in the root" "" "$(ls "$rootrepo")"
run_in "$rootrepo" bash "$tool" run "$rootrepo" -- true
check_status "dir #883: run <absolute root> → 2" 2 "$STATUS"
run_in "$SANDBOX" bash "$tool" run "$rootrepo" -- true
check_status "dir #883: run <root> from another directory → 2" 2 "$STATUS"
mkdir "$rootrepo/sub"
run_in "$rootrepo" bash "$tool" run sub/../ -- true
check_status "dir #883: a root spelled sub/../ → 2" 2 "$STATUS"
run_in "$rootrepo" bash "$tool" run sub -- true
check_status "dir #883: a subdirectory of the work tree is allowed" 0 "$STATUS"
for n in log cmd exit secs; do printf 'x\n' > "$rootrepo/sub/$n"; done
git -C "$rootrepo" add sub && git -C "$rootrepo" commit -qm tracked
before="$(cat "$rootrepo/sub/log")"
run_in "$rootrepo" bash "$tool" run sub -- true
check_status "dir #883: a <dir> holding TRACKED log/cmd/exit/secs → 2" 2 "$STATUS"
check_contains "dir #883: …names the file" "$OUT" "tracked"
check_eq "dir #883: …and left the tracked file as it was" "$before" "$(cat "$rootrepo/sub/log")"
mkdir -p "$SANDBOX/rd.dirlog/log"
cr run "$SANDBOX/rd.dirlog" -- true
check_status "dir #883: a directory named like a record → 2" 2 "$STATUS"
ln -s "$rootrepo/sub" "$SANDBOX/rd.link"
run_in "$rootrepo" bash "$tool" run "$SANDBOX/rd.link/.." -- true
check_status "dir #883: a root reached through a symlink and .. → 2" 2 "$STATUS"
run_in "$rootrepo" bash "$tool" run nonexistent/.. -- true
check_status "dir #883: .. through a missing directory → 2" 2 "$STATUS"
check_nodir "dir #883: …and created nothing" "$rootrepo/nonexistent"
cr run "$SANDBOX/rd.pass" -- true
check_status "dir #883: a rerun over its own records is still fine" 0 "$STATUS"

# --- A2 (i): green, same HEAD / tree / command → 0 ------------------------------------------------------------
vd="$SANDBOX/vd.green"
cr run "$vd" -- bash -c 'echo ok'
cr verify "$vd" -- bash -c 'echo ok'
check_status "A2 i: unchanged HEAD, tree and argv → 0" 0 "$STATUS"
cr verify "$rd" -- true
check_status "A2 i: …also for the first dir (argv form)" 0 "$STATUS"

# --- A2 (ii): no exit → 1 incomplete ---------------------------------------------------------------------------
cr verify "$rd5" -- bash -c "touch '$SANDBOX/kill.ready'; sleep 2"
check_status "A2 ii: a killed run (no exit) → 1" 1 "$STATUS"
check_contains "A2 ii: …reason incomplete" "$OUT" "incomplete"

# --- A2 (iii): exit 3 → 1 exit=3 -------------------------------------------------------------------------------
cr verify "$SANDBOX/rd.fail" -- sh -c 'echo boom; exit 3'
check_status "A2 iii: a red run → 1" 1 "$STATUS"
check_contains "A2 iii: …reason exit=3" "$OUT" "exit=3"

# --- A2 (iv): a commit after the run → head moved -------------------------------------------------------------
w="$(mkrepo)"
cwd="$w"
cr run "$SANDBOX/vd.head" -- true
git -C "$w" commit --allow-empty -qm second
cr verify "$SANDBOX/vd.head" -- true
check_status "A2 iv: HEAD moved after the run → 1" 1 "$STATUS"
check_contains "A2 iv: …reason head moved" "$OUT" "head moved"

# --- A2 (v): outside git → 1 -----------------------------------------------------------------------------------
ng="$SANDBOX/not-a-repo"; mkdir -p "$ng"
cwd="$ng"
cr run "$SANDBOX/vd.nogit" -- true
check_status "A2 v: run outside git still works → 0" 0 "$STATUS"
check_eq "A2 v: head file reads none" "none" "$(cat "$SANDBOX/vd.nogit/head" 2>/dev/null)"
cr verify "$SANDBOX/vd.nogit" -- true
check_status "A2 v: verify outside git → 1" 1 "$STATUS"
check_contains "A2 v: …reason not a git repository" "$OUT" "not a git repository"

# --- A2 (vi): a missing dir → not run ------------------------------------------------------------------------
cwd="$(mkrepo)"
cr verify "$SANDBOX/vd.never" -- true
check_status "A2 vi: a missing dir → 1" 1 "$STATUS"
check_contains "A2 vi: …reason not run" "$OUT" "not run"

# --- A2 (vii): a tracked edit after the run → tree changed -----------------------------------------------------
printf 'one\n' > "$cwd/tracked.txt"; git -C "$cwd" add tracked.txt; git -C "$cwd" commit -qm add
cr run "$SANDBOX/vd.tree" -- true
printf 'two\n' > "$cwd/tracked.txt"
cr verify "$SANDBOX/vd.tree" -- true
check_status "A2 vii: a tracked edit after the run → 1" 1 "$STATUS"
check_contains "A2 vii: …reason tree changed" "$OUT" "tree changed"
git -C "$cwd" checkout -q -- tracked.txt
cr verify "$SANDBOX/vd.tree" -- true
check_status "A2 vii: …and back to clean → 0 again" 0 "$STATUS"
printf 'scratch\n' > "$cwd/untracked.txt"
cr verify "$SANDBOX/vd.tree" -- true
check_status "A2 vii: an untracked scratch file does not count → 0" 0 "$STATUS"

# A second edit to a file that was ALREADY dirty when the run started leaves the porcelain text unchanged.
printf 'three\n' > "$cwd/tracked.txt"
cr run "$SANDBOX/vd.dirty" -- true
printf 'four\n' > "$cwd/tracked.txt"
cr verify "$SANDBOX/vd.dirty" -- true
check_status "A2 vii: a second edit to an already-dirty tracked file → 1" 1 "$STATUS"
check_contains "A2 vii: …reason tree changed" "$OUT" "tree changed"
git -C "$cwd" checkout -q -- tracked.txt

# --- A2 (viii): a different command → command differs ----------------------------------------------------------
cr run "$SANDBOX/vd.cmd" -- bash -c 'echo ok'
cr verify "$SANDBOX/vd.cmd" -- bash -c 'echo other'
check_status "A2 viii: a different command → 1" 1 "$STATUS"
check_contains "A2 viii: …reason command differs" "$OUT" "command differs"
cr verify "$SANDBOX/vd.cmd" -- bash -c 'echo ok' extra
check_status "A2 viii: an extra argument → 1" 1 "$STATUS"
cr verify "$SANDBOX/vd.cmd" -- 'bash -c echo ok'
check_status "A2 viii: the same words as one string → 1 (argv-exact)" 1 "$STATUS"

# --- A2 (ix): one string given to both run and verify → 0 ----------------------------------------------------
cr run "$SANDBOX/vd.str" -- 'echo one && echo two'
cr verify "$SANDBOX/vd.str" -- 'echo one && echo two'
check_status "A2 ix: the same one-string command on both sides → 0" 0 "$STATUS"

# --- wrong-pass guard: each of (iv) (vii) (viii) fails a build that checks only `exit` ------------------------------
# The three cases above already require a non-zero verify while exit=0 is on disk; assert the premise directly.
check_eq "guard: the head-moved dir's exit file is 0" "0" "$(cat "$SANDBOX/vd.head/exit")"
check_eq "guard: the tree dir's exit file is 0" "0" "$(cat "$SANDBOX/vd.tree/exit")"
check_eq "guard: the command dir's exit file is 0" "0" "$(cat "$SANDBOX/vd.cmd/exit")"

summary
