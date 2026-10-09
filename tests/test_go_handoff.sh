#!/usr/bin/env bash
# test_go_handoff.sh — dir #401: tools/go-handoff.sh, the ticket-level handoff note an interrupted
# `/go` session leaves in keel's state root ($HOME/.keel/tmp/go-handoff/<repo-key>/<ticket-key>) and the
# next `/go` on the same ticket reads. Spec: docs/specs/401-ticket-handoff-note.md (gitignored, main
# checkout) — acceptance items A1-A11, A14, A16-A19; A12 (the guide wiring) lives in
# tests/test_go_guide.sh, A13 (go.md untouched) is a conform-time command, not a repo test.
#
# Every case runs the tool from a fixture repo under $SANDBOX with the sandbox $HOME that tests/lib.sh
# arms, so nothing here touches the real $HOME/.keel/tmp.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }
# shellcheck source=tools/lib/stat-portable.sh
. "$REPO_ROOT/tools/lib/stat-portable.sh"

tool="$REPO_ROOT/tools/go-handoff.sh"
check_file "go-handoff.sh exists" "$tool"

ROOT="$HOME/.keel/tmp/go-handoff"
ERRF="$SANDBOX/err"
RC=0; OUT=""; ERR=""

# hrun DIR STDIN_FILE ARGS... — run the tool from DIR; sets RC, OUT (stdout) and ERR (stderr).
# STDIN_FILE "-" = empty stdin.
hrun() {
  local dir="$1" in="$2"; shift 2
  [ "$in" = "-" ] && in=/dev/null
  OUT="$(cd "$dir" && bash "$tool" "$@" <"$in" 2>"$ERRF")"; RC=$?
  ERR="$(<"$ERRF")"
}

# body NAME DONE NEXT CARRY — write a well-formed three-field stdin file; prints its path.
body() {
  local f="$SANDBOX/in.$1"
  printf 'done: %s\nnext: %s\ncarry: %s\n' "${2:-I1 change list (file:1)}" "${3:-I2 red checks}" "${4:-none}" > "$f"
  printf '%s' "$f"
}

# last_line — the last line of OUT.
last_line() { printf '%s\n' "$OUT" | tail -n 1; }

# note_of REPO TICKETKEY — the path the tool must use for REPO's note. The repo key comes from tests/lib.sh's
# repo_key_for (an independent mirror of the gate's), so a broken `repo-key` cannot move tool and oracle together;
# REPO is always a main checkout here (the worktree case, A3, reads back through the tool itself).
note_of() { printf '%s/%s/%s' "$ROOT" "$(repo_key_for "$1")" "$2"; }

# commit REPO MSG — one empty commit.
commit() { git -C "$1" commit -q --allow-empty -m "$2"; }

sum() { cksum < "$1"; }

mkrepo() { local d; d="$(new_repo)"; commit "$d" A; printf '%s' "$d"; }

# --- A1 — round trip ------------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" - read "dir #401"
check_status "A1 read of an unwritten ticket exits 1" 1 "$RC"
check_eq "A1 read of an unwritten ticket prints nothing" "" "$OUT"
hrun "$r" "$(body a1 'step one (t1)' 'step two' 'none')" write "dir #401"
check_status "A1 write exits 0" 0 "$RC"
hrun "$r" - read "dir #401"
check_status "A1 read of a written note exits 0" 0 "$RC"
for want in 'ticket: dir #401' 'branch: main' "worktree: $(cd "$r" && git rev-parse --show-toplevel)" \
            "head: $(git -C "$r" rev-parse HEAD)" 'done: step one (t1)' 'next: step two' 'carry: none'; do
  check_contains "A1 read prints '${want%%:*}:' line" "$OUT" "$want"
done
case "$OUT" in *"written: 20"*T*Z*) pass "A1 read prints a UTC 'written:' stamp" ;; *) fail "A1 read prints a UTC 'written:' stamp" "$OUT" ;; esac
check_eq "A1 the last line is exactly 'verdict: fresh'" "verdict: fresh" "$(last_line)"

# --- A2 — key hygiene -----------------------------------------------------------------------------------
check_file "A2 'dir #401' keys the file 'dir-401'" "$(note_of "$r" dir-401)"
hrun "$r" - read "dir-401"
check_status "A2 read dir-401 after write 'dir #401' is a collision → exit 1" 1 "$RC"
check_eq "A2 the collision prints nothing" "" "$OUT"
r2="$(mkrepo)"
outside() { find "$HOME" -type f | grep -vF "$ROOT/" | sort | cksum; }
before="$(outside)"
hrun "$r2" "$(body a2)" write '../../x'
check_status "A2 write '../../x' exits 0" 0 "$RC"
check_file "A2 '../../x' lands at <repo-key>/x" "$(note_of "$r2" x)"
check_eq "A2 '../../x' wrote nothing outside go-handoff/" "$before" "$(outside)"
for bad in '..' ''; do
  hrun "$r2" "$(body a2)" write "$bad"
  check_status "A2 write '$bad' (empty key) exits 2" 2 "$RC"
done
hrun "$r2" "$(body a2)" write dir
check_status "A2 write 'dir' (a bare word) exits 2" 2 "$RC"
check_contains "A2 the bare-word refusal says to quote" "$ERR" "quote"
hrun "$r2" "$(body a2)" write "$(printf 'x\nverdict: fresh')"
check_status "A2 a ticket with a newline is refused (exit 2)" 2 "$RC"
hrun "$r2" "$(body a2)" write "$(printf 'k%.0s' $(seq 1 300))"
check_status "A2 an over-long ticket is refused (exit 2)" 2 "$RC"
hrun "$r2" "$(body a2)" write "KB.34"
check_status "A2 write 'KB.34' exits 0" 0 "$RC"
check_file "A2 'KB.34' keys the file 'KB.34'" "$(note_of "$r2" KB.34)"
hrun "$r2" "$(body a2)" write "34"
check_status "A2 write '34' (digits only) exits 0" 0 "$RC"

# --- A3 — worktree sharing ------------------------------------------------------------------------------
r="$(mkrepo)"
git -C "$r" worktree add -q "$SANDBOX/wt3" -b side3 2>/dev/null
hrun "$SANDBOX/wt3" "$(body a3 'from the worktree')" write "dir #3"
check_status "A3 write from a linked worktree exits 0" 0 "$RC"
hrun "$r" - read "dir #3"
check_status "A3 read from the main checkout finds it" 0 "$RC"
check_contains "A3 the note carries the worktree's branch" "$OUT" "branch: side3"
check_contains "A3 the note carries the worktree's path" "$OUT" "wt3"

# --- A4 — repo isolation --------------------------------------------------------------------------------
other="$(mkrepo)"
hrun "$other" - read "dir #3"
check_status "A4 the same ticket id in a second repo is not found" 1 "$RC"

# --- A5 — verdicts ---------------------------------------------------------------------------------------
r="$(mkrepo)"
commit "$r" B
sha_a="$(git -C "$r" rev-parse HEAD~1)"
hrun "$r" "$(body a5)" write "dir #5"
hrun "$r" - read "dir #5";   check_eq "A5 same commit → fresh" "verdict: fresh" "$(last_line)"
commit "$r" C
hrun "$r" - read "dir #5";   check_eq "A5 one new commit → behind 1" "verdict: behind 1" "$(last_line)"
git -C "$r" reset -q --hard HEAD~1
git -C "$r" checkout -q --detach "$sha_a"
hrun "$r" - read "dir #5";   check_eq "A5 detached at the note's parent → ahead 1" "verdict: ahead 1" "$(last_line)"
git -C "$r" checkout -q main
git -C "$r" commit -q --amend --allow-empty -m "B amended"
hrun "$r" - read "dir #5";   check_eq "A5 amended head → unrelated" "verdict: unrelated" "$(last_line)"
n5="$(note_of "$r" dir-5)"
sed 's/^head: .*/head: 0123456789abcdef0123456789abcdef01234567/' "$n5" > "$n5.new" && mv "$n5.new" "$n5"
hrun "$r" - read "dir #5";   check_eq "A5 a head that does not exist → unrelated (rc 128)" "verdict: unrelated" "$(last_line)"
sed 's/^head: .*/head: --not-a-sha/' "$n5" > "$n5.new" && mv "$n5.new" "$n5"
hrun "$r" - read "dir #5";   check_eq "A5 a head that is not a sha → unrelated, never an option" "verdict: unrelated" "$(last_line)"
plain="$SANDBOX/plain5"; mkdir -p "$plain"
hrun "$plain" "$(body a5p)" write "dir #5"
check_status "A5 write in a non-git directory exits 0" 0 "$RC"
hrun "$plain" - read "dir #5"
check_contains "A5 non-git: head none" "$OUT" "head: none"
check_contains "A5 non-git: branch none" "$OUT" "branch: none"
check_contains "A5 non-git: worktree none" "$OUT" "worktree: none"
check_eq "A5 non-git → unknown" "verdict: unknown" "$(last_line)"
# a note written outside git, read inside a repo → unknown too
hrun "$plain" "$(body a5q)" write "dir #55"
cp "$(note_of "$plain" dir-55)" "$SANDBOX/n55"
r5="$(mkrepo)"
mkdir -p "$(dirname "$(note_of "$r5" dir-55)")" && cp "$SANDBOX/n55" "$(note_of "$r5" dir-55)"
hrun "$r5" - read "dir #55"
check_eq "A5 a 'head: none' note read inside git → unknown" "verdict: unknown" "$(last_line)"

# an unborn HEAD (a repo with no commit yet): branch known, head none → verdict unknown
unborn="$(new_repo)"
hrun "$unborn" "$(body a5u)" write "dir #5u"
check_status "A5 write in a repo with no commit exits 0" 0 "$RC"
hrun "$unborn" - read "dir #5u"
check_contains "A5 unborn HEAD: head none (never the literal 'HEAD')" "$OUT" "head: none"
check_eq "A5 unborn HEAD → unknown" "verdict: unknown" "$(last_line)"

# --- A6 — field validation -------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" "$(body a6 'keep me')" write "dir #6"
keep="$(sum "$(note_of "$r" dir-6)")"
bad_case() {  # LABEL CONTENT
  local f="$SANDBOX/in.bad"
  printf '%b' "$2" > "$f"
  hrun "$r" "$f" write "dir #6"
  check_status "A6 $1 → exit 2" 2 "$RC"
  check_eq "A6 $1 leaves the previous note byte-identical" "$keep" "$(sum "$(note_of "$r" dir-6)")"
}
bad_case "a missing field"      'done: a\nnext: b\n'
bad_case "an empty field"       'done: a\nnext:\ncarry: c\n'
bad_case "a blank-only field"   'done: a\nnext: b\ncarry:   \n\n'
bad_case "out-of-order keys"    'next: b\ndone: a\ncarry: c\n'
bad_case "a duplicated key"     'done: a\ndone: a2\nnext: b\ncarry: c\n'
bad_case "text before done:"    'preamble\ndone: a\nnext: b\ncarry: c\n'
bad_case "empty stdin"          ''
hrun "$r" - frobnicate "dir #6"
check_status "A6 an unknown verb → exit 2" 2 "$RC"
hrun "$r" - write
check_status "A6 write with no ticket → exit 2" 2 "$RC"
hrun "$r" - read "dir #6" extra
check_status "A6 an extra argument → exit 2" 2 "$RC"
check_eq "A6 the usage failures left the note byte-identical" "$keep" "$(sum "$(note_of "$r" dir-6)")"
f="$SANDBOX/in.multi"
printf 'done: line one\n  more text\nnext: n\nstill n\ncarry: c\n' > "$f"
hrun "$r" "$f" write "dir #6m"
check_status "A6 a multi-line field is accepted" 0 "$RC"
hrun "$r" - read "dir #6m"
check_contains "A6 the multi-line text survives" "$OUT" "  more text"

# --- A7 — size bound ------------------------------------------------------------------------------------
r="$(mkrepo)"
sized() {  # N — a well-formed stdin of exactly N bytes
  local n="$1" f="$SANDBOX/in.size.$1"
  { printf 'done: a\nnext: b\ncarry: '; printf 'x%.0s' $(seq 1 $((n - 24))); printf '\n'; } > "$f"
  printf '%s' "$f"
}
check_eq "A7 fixture is exactly 100 bytes" "100" "$(wc -c < "$(sized 100)" | tr -d ' ')"
export KEEL_GO_HANDOFF_MAX_BYTES=100
hrun "$r" "$(sized 100)" write "dir #7"
check_status "A7 exactly the bound is accepted" 0 "$RC"
keep="$(sum "$(note_of "$r" dir-7)")"
hrun "$r" "$(sized 101)" write "dir #7"
check_status "A7 one byte over the bound → exit 2" 2 "$RC"
check_eq "A7 the oversize write left the previous note intact" "$keep" "$(sum "$(note_of "$r" dir-7)")"
unset KEEL_GO_HANDOFF_MAX_BYTES
hrun "$r" "$(sized 4096)" write "dir #7b"
check_status "A7 the default bound (4096) accepts 4096 bytes" 0 "$RC"
hrun "$r" "$(sized 4097)" write "dir #7b"
check_status "A7 the default bound refuses 4097 bytes" 2 "$RC"

# --- A8 — atomic replace --------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" "$(body a8 first)" write "dir #8"
hrun "$r" "$(body a8 second)" write "dir #8"
d8="$(dirname "$(note_of "$r" dir-8)")"
check_eq "A8 two writes leave one file" "1" "$(find "$d8" -type f | wc -l | tr -d ' ')"
hrun "$r" - read "dir #8"
check_contains "A8 the file holds the second write" "$OUT" "done: second"
check_absent "A8 and none of the first" "$OUT" "done: first"
check_eq "A8 no .tmp. residue after a clean write" "0" "$(find "$d8" -name '*.tmp.*' | wc -l | tr -d ' ')"
touch -t 202001010000 "$d8/old.tmp.999"
hrun "$r" "$(body a8 third)" write "dir #8"
check_nofile "A8 a stale .tmp. file is removed by the next write" "$d8/old.tmp.999"
keep="$(sum "$(note_of "$r" dir-8)")"
shim="$SANDBOX/shim8"; mkdir -p "$shim"
printf '#!/bin/sh\nexit 1\n' > "$shim/mv"; chmod +x "$shim/mv"
OUT="$(cd "$r" && PATH="$shim:$PATH" bash "$tool" write "dir #8" < "$(body a8 fourth)" 2>"$ERRF")"; RC=$?
check_ne "A8 with mv failing the write reports failure" "0" "$RC"
check_eq "A8 with mv failing the previous note is byte-identical" "$keep" "$(sum "$(note_of "$r" dir-8)")"
check_eq "A8 with mv failing no partial file sits beside it" "1" "$(find "$d8" -type f | wc -l | tr -d ' ')"

mkdir "$d8/dir-8x"
hrun "$r" "$(body a8 x)" write "dir #8x"
check_status "A8 a directory at the note path → exit 3, nothing nested" 3 "$RC"
check_eq "A8 …and nothing was nested inside it" "0" "$(find "$d8/dir-8x" -type f | wc -l | tr -d ' ')"

# --- A9 — clear -----------------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" "$(body a9 one)" write "dir #9"
hrun "$r" "$(body a9 two)" write "dir #90"
keep="$(sum "$(note_of "$r" dir-90)")"
hrun "$r" - clear "dir #9"
check_status "A9 clear of a present note exits 0" 0 "$RC"
check_nofile "A9 the note is gone" "$(note_of "$r" dir-9)"
check_eq "A9 the other ticket's note is byte-identical" "$keep" "$(sum "$(note_of "$r" dir-90)")"
hrun "$r" - clear "dir #9"
check_status "A9 clear of an absent note exits 0" 0 "$RC"
hrun "$r" "$(body a9 x)" write '../../x'
mkdir -p "$HOME/.keel/tmp/go-handoff-sibling"; : > "$HOME/.keel/tmp/go-handoff-sibling/f"
: > "$HOME/.keel/tmp/x"
hrun "$r" - clear '../../x'
check_status "A9 clear of a path-like ticket exits 0" 0 "$RC"
check_nofile "A9 the path-like note under <repo-key>/ is gone" "$(note_of "$r" x)"
check_file "A9 a file at \$HOME/.keel/tmp/x survives" "$HOME/.keel/tmp/x"
check_file "A9 a sibling subtree's file survives" "$HOME/.keel/tmp/go-handoff-sibling/f"
check_file "A9 the other ticket's note still exists" "$(note_of "$r" dir-90)"

# --- A10 — prune ----------------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" "$(body a10 old)" write "dir #10"
hrun "$r" "$(body a10 fresh)" write "dir #11"
mkdir -p "$HOME/.keel/tmp/alpine-clone"
: > "$HOME/.keel/tmp/aged-sentinel"; : > "$HOME/.keel/tmp/alpine-clone/f"
touch -t 202001010000 "$(note_of "$r" dir-10)" "$HOME/.keel/tmp/aged-sentinel" "$HOME/.keel/tmp/alpine-clone/f"
hrun "$r" - read "dir #10"
check_status "A10 the read that finds an aged note delivers it" 0 "$RC"
check_contains "A10 …with its content" "$OUT" "done: old"
check_nofile "A10 …and the note is gone after that call" "$(note_of "$r" dir-10)"
hrun "$r" - read "dir #10"
check_status "A10 the next read finds nothing" 1 "$RC"
check_file "A10 a fresh note is untouched" "$(note_of "$r" dir-11)"
check_file "A10 an aged file at \$HOME/.keel/tmp/<x> is untouched" "$HOME/.keel/tmp/aged-sentinel"
check_file "A10 an aged file in a sibling subtree is untouched" "$HOME/.keel/tmp/alpine-clone/f"
# a read that finds nothing prunes too (B3: "after it has answered")
hrun "$r" "$(body a10 z)" write "dir #14"
touch -t 202001010000 "$(note_of "$r" dir-14)"
hrun "$r" - read "dir #nonesuch"
check_status "A10 a read of an absent ticket exits 1" 1 "$RC"
check_nofile "A10 …and still prunes an aged note of another ticket" "$(note_of "$r" dir-14)"
# write prunes too: age the fresh note, write another ticket
touch -t 202001010000 "$(note_of "$r" dir-11)"
hrun "$r" "$(body a10 w)" write "dir #12"
check_nofile "A10 a write prunes an aged note" "$(note_of "$r" dir-11)"
export KEEL_GO_HANDOFF_PRUNE_DAYS=100000
hrun "$r" "$(body a10 w)" write "dir #13"
touch -t 202001010000 "$(note_of "$r" dir-13)"
hrun "$r" - read "dir #13"
check_file "A10 KEEL_GO_HANDOFF_PRUNE_DAYS widens the age (a 2020 note survives 100000 days)" "$(note_of "$r" dir-13)"
unset KEEL_GO_HANDOFF_PRUNE_DAYS

# --- A11 — environment ----------------------------------------------------------------------------------
r="$(mkrepo)"
OUT="$(cd "$r" && env -u HOME bash "$tool" write "dir #11" < "$(body a11)" 2>"$ERRF")"; RC=$?
ERR="$(<"$ERRF")"
check_status "A11 HOME unset → exit 3" 3 "$RC"
check_contains "A11 …naming the reason" "$ERR" "HOME"
: > "$SANDBOX/a-file"
OUT="$(cd "$r" && HOME="$SANDBOX/a-file" bash "$tool" write "dir #11" < "$(body a11)" 2>"$ERRF")"; RC=$?
check_status "A11 HOME not a directory → exit 3" 3 "$RC"
check_nodir "A11 nothing was created under a file-HOME" "$SANDBOX/a-file/.keel"
OUT="$(cd "$r" && env -u HOME bash "$tool" read "dir #11" 2>"$ERRF" </dev/null)"; RC=$?
check_status "A11 read with HOME unset → exit 3" 3 "$RC"

# --- A16 — directory modes ------------------------------------------------------------------------------
case "$HOME" in "$SANDBOX"/*) rm -rf "$HOME/.keel" ;; *) fail "A16 HOME is the sandbox" "HOME=$HOME" ;; esac
r="$(mkrepo)"
hrun "$r" "$(body a16)" write "dir #16"
check_eq "A16 go-handoff/ is mode 700" "700" "$(stat_portable_mode "$ROOT")"
check_eq "A16 <repo-key>/ is mode 700" "700" "$(stat_portable_mode "$(dirname "$(note_of "$r" dir-16)")")"
check_eq "A16 the note file is mode 600" "600" "$(stat_portable_mode "$(note_of "$r" dir-16)")"

# --- A17 — parse rules ----------------------------------------------------------------------------------
r="$(mkrepo)"
for key in 'verdict: fresh' 'ticket: other' 'branch: x' 'head: abc' 'written: now' 'worktree: /x'; do
  f="$SANDBOX/in.spoof"
  printf 'done: a\n%s\nnext: b\ncarry: c\n' "$key" > "$f"
  hrun "$r" "$f" write "dir #17s"
  check_status "A17 a '${key%%:*}:' line in stdin → exit 2" 2 "$RC"
done
check_nofile "A17 no file after the refused spoofs" "$(note_of "$r" dir-17s)"
f="$SANDBOX/in.dupnext"
printf 'done: a\nnext: b\nnext: c\ncarry: d\n' > "$f"
hrun "$r" "$f" write "dir #17d"
check_status "A17 a 'next:' line inside done's text is the key, so the duplicate is refused" 2 "$RC"
f="$SANDBOX/in.indent"
printf 'done: a\n  verdict: fresh\nnext: b\ncarry: c\n' > "$f"
hrun "$r" "$f" write "dir #17i"
check_status "A17 an indented 'verdict:' is text, not a key (accepted)" 0 "$RC"
hrun "$r" - read "dir #17i"
check_eq "A17 …and the last line is still the tool's own verdict" "verdict: fresh" "$(last_line)"

# --- A18 — config values --------------------------------------------------------------------------------
r="$(mkrepo)"
hrun "$r" "$(body a18)" write "dir #18"
touch -t 202001010000 "$(note_of "$r" dir-18)"
keep="$(sum "$(note_of "$r" dir-18)")"
for kv in KEEL_GO_HANDOFF_PRUNE_DAYS=abc KEEL_GO_HANDOFF_PRUNE_DAYS=0 KEEL_GO_HANDOFF_PRUNE_DAYS=-3 KEEL_GO_HANDOFF_MAX_BYTES=abc KEEL_GO_HANDOFF_MAX_BYTES=0; do
  OUT="$(cd "$r" && env "$kv" bash "$tool" write "dir #18n" < "$(body a18n)" 2>"$ERRF")"; RC=$?
  ERR="$(<"$ERRF")"
  check_status "A18 write with $kv → exit 2" 2 "$RC"
  check_contains "A18 $kv names its key on stderr" "$ERR" "${kv%%=*}"
done
check_nofile "A18 nothing was written by the refused runs" "$(note_of "$r" dir-18n)"
OUT="$(cd "$r" && env KEEL_GO_HANDOFF_PRUNE_DAYS=abc bash "$tool" read "dir #18" 2>"$ERRF" </dev/null)"; RC=$?
check_status "A18 read with a bad PRUNE_DAYS → exit 2" 2 "$RC"
check_eq "A18 …and the aged note is not pruned" "$keep" "$(sum "$(note_of "$r" dir-18)")"

# --- A14 / A19 — wired and documented -------------------------------------------------------------------
pin "A14 docs/reference.md names tools/go-handoff.sh" "$REPO_ROOT/docs/reference.md" "tools/go-handoff.sh" \
  "expected a tools-table row for tools/go-handoff.sh"
fw="$REPO_ROOT/FRAMEWORK.md"
if grep -qF 'L4 has no mid-task checkpoint, so' "$fw"; then
  fail "A14 FRAMEWORK.md no longer states the L4 gap as open" "still contains 'L4 has no mid-task checkpoint, so'"
else
  pass "A14 FRAMEWORK.md no longer states the L4 gap as open"
fi
l4_bullet="$(awk '/^- \*\*L4 — Dev/{p=1;print;next} p&&/^[[:space:]]*$/{exit} p&&/^- \*\*/{exit} p{print}' "$fw")"
check_contains "A14 L4's bullet (Observability) names go-handoff" "$l4_bullet" "go-handoff"
coupling="$(awk '/^\*\*Coupling:\*\*/{p=1} p&&/^[[:space:]]*$/{exit} p{print}' "$fw")"
check_contains "A14 the Shared-state clause names go-handoff" "$coupling" "go-handoff"
gap="$(awk '/^- L4/{p=1} p&&/^[[:space:]]*$/{exit} p{print}' "$fw")"
check_contains "A14 the reworded known-gap bullet still names copy mode" "$gap" "copy mode"
check_contains "A14 …and names go-handoff" "$gap" "go-handoff"
for lib in gate-paths state-root; do
  n="$(grep -c 'go-handoff' "$REPO_ROOT/tools/lib/$lib.sh")"
  if [ "$n" -ge 1 ]; then pass "A19 tools/lib/$lib.sh names go-handoff"; else fail "A19 tools/lib/$lib.sh names go-handoff" "0 mentions"; fi
done
# The whole file PLUS the changelog.d/ fragments (dir #744), never the live [Unreleased] section and never
# one fragment: the release cut empties that section and deletes the fragments, and a cite that moves to
# the dated section below must still be found.
clog="$(cat "$REPO_ROOT/CHANGELOG.md"; "$REPO_ROOT/tools/self/changelog-fragments.sh" --repo "$REPO_ROOT")"
check_contains "A19 CHANGELOG names dir #401 in full" "$clog" "dir #401"
check_absent "A19 …not backtick-wrapped" "$clog" '`dir #401`'

summary
