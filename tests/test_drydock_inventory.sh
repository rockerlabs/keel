#!/usr/bin/env bash
# Tests for tools/drydock/inventory.sh — drydock phase 0's scope-as-code generator (dir #170).
# The load-bearing half is the GUARD (see the script's own header for the run-1 incident it exists to
# stop), so the refusals are pinned as hard as the output: a HEAD that isn't the baseline, a dirty
# tree, an unreadable in-scope file, an unborn HEAD, and a non-repo each refuse with an actionable
# message and a distinct exit code, and no refusal names a bypass flag — there isn't one, and a
# message hinting at one invites the workaround instead of the fix (the same discipline
# tests/test_keel_check.sh pins on the STOP banner).
#
# Two invariants here are regression pins, not hypotheticals — both shipped broken once:
#   1. CHANGED-set membership. The newline delimiters were built with "$(printf '\n')", and command
#      substitution strips trailing newlines, so both vanished and the test degenerated to a bare
#      substring match. `docs/README.md` below is the fixture that catches it: its path ends with
#      another tracked file's whole path.
#   2. Silent omission. A file git lists but awk cannot open used to drop out of the artifact with
#      the run still exiting 0 — a partial inventory being indistinguishable from a small tree is the
#      exact failure the guard exists to prevent. `docs/dangling.md` is that fixture.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

TOOL="$REPO_ROOT/tools/drydock/inventory.sh"
check_file "inventory.sh exists" "$TOOL"

TAB="$(printf '\t')"
# N lines of filler — awk, not `printf ... $(seq N)`, which needs an unquoted expansion.
lines() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "l" }'; }

# A sandbox repo pushed to a fresh bare origin (new_bare_origin(), lib.sh dir #173), so `origin/main` is
# a real ref to be at (or off); recover the bare's own path with `git -C "$d" remote get-url origin`
# (needed by the unborn-HEAD fixture below, for a second work tree on the same origin). Uses
# new_bare_origin() rather than new_repo_with_origin(): this fixture's own content has to be committed
# before the first push, so the latter's built-in empty-commit-then-push would just be a wasted round
# trip here. No explicit fetch after the push either, same reasoning as new_repo_with_origin()'s own
# comment: a successful push already updates the local origin/main tracking ref. Prints the work tree's
# path. The line counts here are asserted on below — keep them in sync.
mk_repo() {
  local d
  d="$(new_repo)"
  new_bare_origin "$d" >/dev/null
  # `scripts/`, not `tools/`: tools/self/doctor.sh's dead-reference check scans tests/*.sh for
  # repo-root-relative tools-path mentions, and a fixture path that merely looks like one reads as a
  # dead reference to a script this repo doesn't have.
  mkdir -p "$d/docs" "$d/scripts" "$d/bin"
  lines 10  > "$d/README.md"
  lines 20  > "$d/docs/guide.md"
  lines 7   > "$d/docs/README.md"        # path ends with README.md — the substring-match trap
  lines 5   > "$d/CHANGELOG.md"          # historical-prose rule: always its own batch
  lines 600 > "$d/big.md"                # over the solo threshold
  # Three lines, NO trailing newline: `wc -l` would say 2, which is why the script counts with awk.
  printf 'a\nb\nc' > "$d/docs/nonl.md"
  printf '#!/usr/bin/env bash\n# one\n# two\n# three\necho hi\n' > "$d/scripts/thing.sh"
  printf '#!/usr/bin/env bash\n# four\n# five\necho ho\n' > "$d/scripts/other.sh"
  # No extension, shell shebang: in scope B by default, invisible to a plain '*.sh' pathspec.
  printf '#!/usr/bin/env bash\n# hook one\n# hook two\necho hook\n' > "$d/bin/cli"
  chmod +x "$d/bin/cli"
  # Sorts after every other tracked path AND is not a shell script. Without it the fixture's last
  # entry is scripts/thing.sh, whose `*.sh` match returns 0 and hides a whole hazard class: the
  # scope-B selector's exit status used to be the last loop iteration's, so it reported failure on a
  # perfectly healthy repo — and both suites stayed green purely by accident of sort order.
  lines 2 > "$d/zz-notes.md"
  # awk reads a bare operand shaped `name=value` as a variable assignment, so this file was measured
  # as 0 lines — silently, at exit 0, with `[ -r ]` passing because it is perfectly readable. Only a
  # top-level path can trigger it: anything with a `/` is not a valid awk identifier.
  lines 4 > "$d/a=b.md"
  git -C "$d" add -A
  git -C "$d" commit -qm content
  git -C "$d" push -q origin main
  printf '%s' "$d"
}

# --- the happy path: a clean tree at origin/main --------------------------------------------------
r="$(mk_repo)"
bare="$(git -C "$r" remote get-url origin)"
base="$(git -C "$r" rev-parse HEAD)"
run_in "$r" "$TOOL"
check_status "clean tree at origin/main -> exit 0" 0 "$STATUS"
check_contains "header names the measured baseline" "$OUT" "# drydock inventory @ $base"
check_contains "scope A lists a tracked markdown file" "$OUT" "docs/guide.md"
check_contains "scope A reports its line count" "$OUT" "20 ln"
check_contains "a file with no trailing newline counts its last line" "$OUT" "docs/nonl.md${TAB}3 ln"
check_contains "scope A totals every tracked .md" "$OUT" "scope A total: 8 files, 651 lines"
check_contains "the historical file is still inventoried in scope A" "$OUT" "CHANGELOG.md${TAB}5 ln"
check_contains "a path awk would read as an assignment is measured, not reported empty" \
  "$OUT" "a=b.md${TAB}4 ln"
check_contains "scope B counts comment lines only" "$OUT" "scripts/thing.sh${TAB}4 comment-ln"
check_contains "scope B picks up a shebang-detected extensionless script" \
  "$OUT" "bin/cli${TAB}3 comment-ln"
check_contains "scope B totals comment lines" "$OUT" "scope B total: 3 files, 10 comment lines"
check_contains "an over-threshold file batches SOLO" "$OUT" "big.md SOLO"
check_contains "the historical-prose file is its own batch" "$OUT" "CHANGELOG.md SPECIAL"
check_contains "ordinary files pack by directory" "$OUT" "batch 2: docs/guide.md (20 ln)"
check_contains "a directory's files ride in one batch under the cap" "$OUT" "batch 2: docs/README.md"
check_contains "scope B packs under its own cap" "$OUT" "batch B2: scripts/other.sh (3 comment-ln)"
check_contains "scope C counts whole-file lines, not just comments" "$OUT" "scripts/thing.sh${TAB}5 ln"
check_contains "scope C picks up the same shebang-detected extensionless script as scope B" \
  "$OUT" "bin/cli${TAB}4 ln"
check_contains "scope C's default selection is identical to scope B's" \
  "$OUT" "scope C total: 3 files, 13 lines (0 invariant)"
check_contains "scope C packs under its own cap, in its own C-prefixed batches" \
  "$OUT" "batch C2: scripts/thing.sh (5 ln)"
check_absent "an unmarked scope-C file carries no INVARIANT flag" "$OUT" "scripts/thing.sh${TAB}5 ln INVARIANT"
check_absent "no previous-baseline line without --prev" "$OUT" "previous baseline"
check_absent "nothing is flagged CHANGED on a full run" "$OUT" "CHANGED"

# Runs from a subdirectory: the tool resolves its own repo root rather than measuring the cwd.
run_in "$r/docs" "$TOOL"
check_status "runs from a subdirectory -> exit 0" 0 "$STATUS"
check_contains "a subdirectory run still measures the whole tree" "$OUT" "scope A total: 8 files"

# --- the run-1 guard: HEAD is not the baseline ----------------------------------------------------
git -C "$r" checkout -q -b peer-session
lines 1 >> "$r/docs/guide.md"
git -C "$r" commit -qam "a peer session's commit"
foreign="$(git -C "$r" rev-parse HEAD)"
run_in "$r" "$TOOL"
check_status "HEAD off the baseline -> exit 3" 3 "$STATUS"
check_contains "the refusal names the HEAD it found" "$OUT" "$foreign"
check_contains "the refusal names the baseline it expected" "$OUT" "$base"
check_contains "the refusal suggests a frozen worktree" "$OUT" "git worktree add"
check_absent "the refusal names no bypass flag" "$OUT" "--force"
check_absent "no inventory is emitted on a refusal" "$OUT" "scope A total"

# ...and the escape hatch is explicit intent, not a bypass: naming the rev is what measures it.
run_in "$r" "$TOOL" --baseline "$foreign"
check_status "an explicitly named baseline is measured -> exit 0" 0 "$STATUS"
check_contains "the explicit baseline is the measured one" "$OUT" "# drydock inventory @ $foreign"

git -C "$r" checkout -q main

# --- the guard's second half: a dirty tree --------------------------------------------------------
lines 1 >> "$r/README.md"
run_in "$r" "$TOOL"
check_status "dirty tree -> exit 3" 3 "$STATUS"
check_contains "the refusal names the dirty path" "$OUT" "README.md"
check_absent "no inventory is emitted on a dirty tree" "$OUT" "scope A total"
git -C "$r" checkout -q -- README.md

# An ignored file is not dirt — the audit's own output directory lives in the tree while it runs.
printf 'audit/\n' > "$r/.gitignore"
git -C "$r" add .gitignore
git -C "$r" commit -qm gitignore
git -C "$r" push -q origin main
git -C "$r" fetch -q origin
mkdir -p "$r/audit"
printf 'scratch\n' > "$r/audit/notes.md"
run_in "$r" "$TOOL"
check_status "an ignored file is not a dirty tree -> exit 0" 0 "$STATUS"
check_absent "an ignored file is not inventoried" "$OUT" "audit/notes.md"

# --- the tuning knobs -----------------------------------------------------------------------------
# Each knob is the only thing that makes this script runnable on a repo shaped unlike this one, so
# each of the nine gets a case: unexercised knobs rot green.
run_in "$r" env "DRYDOCK_SCOPE_B=*.sh" "$TOOL"
check_contains "an explicit scope-B pathspec still finds the .sh file" "$OUT" "scripts/thing.sh"
# Not a bare "bin/cli" absence check: scope C (unaffected by this scope-B-only override) still lists
# it, via its own default shebang detection — the comment-ln unit is what makes this scope-B-specific.
check_absent "an explicit scope-B pathspec drops the shebang-only script" "$OUT" "bin/cli${TAB}3 comment-ln"

run_in "$r" env "DRYDOCK_SCOPE_C=scripts/*.sh" "$TOOL"
check_contains "an explicit scope-C pathspec still finds the .sh file" "$OUT" "scripts/thing.sh${TAB}5 ln"
check_absent "an explicit scope-C pathspec drops the shebang-only script" "$OUT" "bin/cli${TAB}4 ln"
check_contains "a narrowed scope C totals only its own files" "$OUT" "scope C total: 2 files, 9 lines"

# The canonical disable spelling: a pathspec matching nothing yields an empty scope at exit 0, never
# a refusal — docs/drydock.md's scope-C section states this exact spelling for a prose-only run.
run_in "$r" env "DRYDOCK_SCOPE_C=:!*" "$TOOL"
check_status "the ':!*' disable spelling -> exit 0" 0 "$STATUS"
check_contains "':!*' yields an empty scope C" "$OUT" "scope C total: 0 files, 0 lines"

# An empty-but-set value is UNSET too, per the same convention scope B already uses — it must NOT be
# read as "match nothing" (that would silently disable scope C on `DRYDOCK_SCOPE_C=` rather than on
# the documented ':!*' spelling).
run_in "$r" env "DRYDOCK_SCOPE_C=" "$TOOL"
check_contains "an empty DRYDOCK_SCOPE_C is the full default selection, not a disable" \
  "$OUT" "scope C total: 3 files, 13 lines"

# Regression pin: an all-whitespace value passes `[ -n ]` (non-empty string — unlike a truly empty
# one, this does NOT fall through to the default-selection branch), but `read -a` still parses it
# into zero array elements — a real crash this repo shipped and reverted mid-review. Passing that
# empty array as *function-call arguments* (a since-reverted scope_b_files/scope_c_files unification
# attempt) expands "${arr[@]}" before the callee's own length guard ever runs, and this repo's target
# bash (3.2, macOS's shipped version) throws "unbound variable" on an EMPTY array's "${arr[@]}"
# expansion under `set -u`, no matter the context. Same class of hazard the guard comment on
# `scan_files` in tools/self/doctor.sh's dead-reference scan documents for this exact expansion.
#
# `check_status ... 0` below is NOT what actually catches this — verified live: this script's own
# `trap 'rm -rf "$scratch"' EXIT` runs (and succeeds) on the nounset abort too, so bash reports the
# process's FINAL exit status as the trap's own (0), silently masking the abort's real status.
# `check_absent` on the literal error text is what actually proves no crash happened; `check_contains`
# on the expected content is the second, independent proof (a crash's captured stderr, via run()'s
# `2>&1`, would starve this assertion of the real output either way).
#
# CI-BLIND, ON PURPOSE, NOT A GAP TO CLOSE: this bug is bash-3.2-specific (macOS's shipped version) —
# reproduced clean (no crash) on Debian bash 5.2 and Alpine bash 5.3, the two platforms this repo's CI
# actually runs. This pin only has teeth on a local macOS run; a green CI leg proves nothing about it,
# same shape as this repo's other platform-conditional traps (project CLAUDE.md's Alpine-only-trap
# entries), just the mirror-image case — macOS-only, not Alpine-only.
run_in "$r" env "DRYDOCK_SCOPE_C= " "$TOOL"
check_status "an all-whitespace DRYDOCK_SCOPE_C exits 0 either way (not the discriminator — see below)" \
  0 "$STATUS"
check_absent "...and does NOT crash: no unbound-variable error in the captured output" \
  "$OUT" "unbound variable"
check_contains "...and yields an empty scope C (an explicit pathspec that parses to nothing), not the default" \
  "$OUT" "scope C total: 0 files, 0 lines"

run_in "$r" env "DRYDOCK_SOLO_LINES=10" "$TOOL"
check_contains "a lowered solo threshold sends a smaller file solo" "$OUT" "docs/guide.md SOLO"

run_in "$r" env "DRYDOCK_BATCH_LINES=20" "$TOOL"
check_contains "a lowered scope-A cap splits a directory across batches" \
  "$OUT" "batch 3: docs/README.md"

run_in "$r" env "DRYDOCK_COMMENT_BATCH_LINES=4" "$TOOL"
check_contains "a lowered scope-B cap splits a directory across batches" \
  "$OUT" "batch B3: scripts/other.sh"

run_in "$r" env "DRYDOCK_CODE_BATCH_LINES=5" "$TOOL"
check_contains "a lowered scope-C cap splits a directory across batches" \
  "$OUT" "batch C3: scripts/other.sh (4 ln)"

run_in "$r" env "DRYDOCK_HISTORICAL=big.md" "$TOOL"
check_contains "the historical knob moves the SPECIAL batch" "$OUT" "big.md SPECIAL"
check_absent "and the default historical file is no longer special-cased" "$OUT" "CHANGELOG.md SPECIAL"

# The invariant knob marks a DIFFERENT file than the default list would, proving it is read at all —
# the default list itself is pinned separately below, on a fixture actually named for it.
run_in "$r" env "DRYDOCK_INVARIANT_PATHS=scripts/thing.sh" "$TOOL"
check_contains "the invariant knob marks the named file" "$OUT" "scripts/thing.sh${TAB}5 ln INVARIANT"
check_contains "...and its batch line too — the marker is per-file, not per-batch-summary" \
  "$OUT" "batch C2: scripts/thing.sh (5 ln) INVARIANT"
check_contains "...and the scope-C total counts it, so deleting the counter increment reds this" \
  "$OUT" "scope C total: 3 files, 13 lines (1 invariant)"

# --- the DEFAULT invariant list, unexercised by the override test above ----------------------------
r5="$(new_repo_with_origin)"
printf '#!/usr/bin/env bash\necho installing\n' > "$r5/install.sh"
git -C "$r5" add -A
git -C "$r5" commit -qm "add install.sh"
git -C "$r5" push -q origin main
run_in "$r5" "$TOOL"
check_status "a repo whose only file is a default-invariant path -> exit 0" 0 "$STATUS"
check_contains "the default DRYDOCK_INVARIANT_PATHS marks install.sh with no override at all" \
  "$OUT" "install.sh${TAB}2 ln INVARIANT"
check_contains "...and the scope-C total's own invariant count reflects it" \
  "$OUT" "scope C total: 1 files, 2 lines (1 invariant)"

# A file outside scope A can never be emitted as a scope-A batch, historical or not.
run_in "$r" env "DRYDOCK_SCOPE_A=docs/*.md" "$TOOL"
check_status "a narrowed scope A -> exit 0" 0 "$STATUS"
check_contains "the narrowed scope A totals only its own files" "$OUT" "scope A total: 3 files, 30 lines"
check_absent "an out-of-scope historical file gets no batch line" "$OUT" "CHANGELOG.md SPECIAL"

# --- the incremental mechanism: --prev flags what changed since a prior run's baseline ------------
lines 1 >> "$r/docs/guide.md"
lines 1 >> "$r/docs/README.md"
git -C "$r" commit -qam "change two files since the previous baseline"
git -C "$r" push -q origin main
git -C "$r" fetch -q origin
run_in "$r" "$TOOL" --prev "$base"
check_status "--prev on a clean tree at origin/main -> exit 0" 0 "$STATUS"
check_contains "the header records the previous baseline" "$OUT" "previous baseline: $base"
check_contains "a file changed since the previous baseline is flagged" \
  "$OUT" "docs/guide.md${TAB}21 ln CHANGED"
check_contains "the changed count covers the whole changed set" \
  "$OUT" "scope A total: 8 files, 653 lines (2 changed since the previous baseline)"
# The membership test is delimited, not a substring match: `docs/README.md` changed, plain
# `README.md` did not, and one path ends with the other.
check_contains "a changed nested file is flagged" "$OUT" "docs/README.md${TAB}8 ln CHANGED"
check_absent "an unchanged file whose path is a suffix of a changed one carries no flag" \
  "$OUT" "README.md${TAB}10 ln CHANGED"
check_contains "the batch section is scoped to the changed subset" "$OUT" "batch 1: docs/guide.md"
check_absent "an unchanged file is not batched on an incremental run" "$OUT" "batch 1: README.md"
check_absent "...in any batch, not just the first" "$OUT" "batch 2: README.md"
check_absent "an unchanged historical file gets no SPECIAL batch" "$OUT" "CHANGELOG.md SPECIAL"

# --- an in-scope file that cannot be read is a refusal, never a silent omission -------------------
# A broken symlink, not `chmod 000`: chmod is a no-op for the root reader the Alpine CI leg runs as
# (project CLAUDE.md), so that fixture would pass the exit-code half and silently skip the real
# assertion on exactly one platform. `-r` on a dangling link is false for every user.
r2="$(mk_repo)"
ln -s nowhere-at-all "$r2/docs/dangling.md"
git -C "$r2" add -A
git -C "$r2" commit -qm "a tracked broken symlink"
git -C "$r2" push -q origin main
git -C "$r2" fetch -q origin
run_in "$r2" "$TOOL"
check_status "an unreadable in-scope file -> exit 3" 3 "$STATUS"
check_contains "the refusal names the file it could not read" "$OUT" "docs/dangling.md"
check_absent "no partial inventory is emitted" "$OUT" "scope A total"

# --- a failed enumeration refuses; it never reports an empty tree at exit 0 -----------------------
# The scope-B branches used to end in a blanket `return 0`, which discarded the very status the
# caller's `|| refuse` exists to read: a failing enumeration became "0 files" at exit 0. A malformed
# pathspec is the cheapest way to make git fail for real.
run_in "$r" env "DRYDOCK_SCOPE_B=:(attr:" "$TOOL"
check_status "a failing scope-B enumeration -> exit 3" 3 "$STATUS"
check_contains "the refusal says nothing was measured" "$OUT" "Nothing was"
check_absent "no empty inventory is emitted" "$OUT" "scope B total"

# Scope C's own `|| refuse` is unexercised without this — it is wired the same way as scope B's
# (git ls-files failing on a malformed pathspec), not the shebang-fallback branch's own return-0 bug,
# but nothing else in this suite proves the wiring still holds.
run_in "$r" env "DRYDOCK_SCOPE_C=:(attr:" "$TOOL"
check_status "a failing scope-C enumeration -> exit 3" 3 "$STATUS"
check_contains "the refusal says nothing was measured" "$OUT" "Nothing was"
check_absent "no empty inventory is emitted" "$OUT" "scope C total"

run_in "$r" env "DRYDOCK_SCOPE_A=:(attr:" "$TOOL"
check_status "a failing scope-A enumeration -> exit 3" 3 "$STATUS"
check_absent "no empty scope-A inventory is emitted" "$OUT" "scope A total"

# The changed-set enumeration is the third of three and gets the same guard. A malformed pathspec
# can't reach it (it takes revs, already validated), so this shims `git` on PATH to fail on `diff`
# alone — an empty changed set would otherwise read as "nothing drifted since the last run", and an
# incremental run would silently audit nothing.
fakebin="$(mktemp -d "$SANDBOX/fakebin.XXXXXX")"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = diff ] && exit 9; done\nexec %s "$@"\n' \
  "$(command -v git)" > "$fakebin/git"
chmod +x "$fakebin/git"
run_in "$r" env "PATH=$fakebin:$PATH" "$TOOL" --prev "$base"
check_status "a failing git diff -> exit 3" 3 "$STATUS"
check_contains "the refusal says the incremental scope is unknown" "$OUT" "incremental scope is unknown"
check_absent "no inventory is emitted when the changed set is unknown" "$OUT" "scope A total"

# --- paths git cannot print literally ---------------------------------------------------------------
# git C-quotes any path it can't print as-is, and `core.quotePath=false` only covers the non-ASCII
# half of that: a backslash or a double quote is quoted regardless. A quoted string is not a path
# anyone can open, so the run used to refuse a perfectly healthy tree and blame a sparse checkout.
# `-z` is what actually fixes it, which is why these fixtures use a backslash and not an accent.
r3="$(mk_repo)"
printf 'x\ny\n' > "$r3/a\\tb.md"                                   # literal backslash-t in the name
printf '#!/usr/bin/env bash\n# c\necho hi\n' > "$r3/w\\eird.sh"
git -C "$r3" add -A
git -C "$r3" commit -qm "paths git has to quote"
git -C "$r3" push -q origin main
git -C "$r3" fetch -q origin
base3="$(git -C "$r3" rev-parse HEAD)"
run_in "$r3" "$TOOL"
check_status "a backslash in a tracked path is measured, not refused -> exit 0" 0 "$STATUS"
check_contains "the backslash path is listed unquoted, with its real line count" \
  "$OUT" "a\\tb.md${TAB}2 ln"
check_contains "a backslash-named script still reaches scope B" "$OUT" "w\\eird.sh${TAB}2 comment-ln"
check_absent "no path is emitted in git's C-quoted form" "$OUT" '\\t'

# ...and the changed-set enumeration matches those same bytes, so an incremental run flags it.
printf 'more\n' >> "$r3/a\\tb.md"
git -C "$r3" commit -qam "change the backslash path"
git -C "$r3" push -q origin main
git -C "$r3" fetch -q origin
run_in "$r3" "$TOOL" --prev "$base3"
check_status "--prev over a backslash path -> exit 0" 0 "$STATUS"
check_contains "a changed backslash path is flagged CHANGED" "$OUT" "a\\tb.md${TAB}3 ln CHANGED"

# A tab or newline in a path cannot be represented in this script's own TSV record, so it refuses
# rather than emitting a corrupt artifact.
r4="$(mk_repo)"
printf 'x\n' > "$r4/$(printf 'has\ttab').md"
git -C "$r4" add -A
git -C "$r4" commit -qm "a tab in a path"
git -C "$r4" push -q origin main
git -C "$r4" fetch -q origin
run_in "$r4" "$TOOL"
check_status "a tab in a tracked path -> exit 3" 3 "$STATUS"
check_contains "the refusal explains the record format cannot represent it" "$OUT" "cannot
represent"
check_absent "no partial inventory is emitted for an unrepresentable path" "$OUT" "scope A total"

# --- a repository with no commits at all -----------------------------------------------------------
# origin/main resolves (it was fetched), but HEAD is unborn — without its own guard this exits 128
# with git's raw error rather than the documented 0/2/3.
u="$(new_repo)"
git -C "$u" remote add origin "$bare"
git -C "$u" fetch -q origin
run_in "$u" "$TOOL"
check_status "an unborn HEAD -> exit 3" 3 "$STATUS"
check_contains "the unborn-HEAD refusal says so" "$OUT" "no commits yet"

# --- argument handling ----------------------------------------------------------------------------
run_in "$r" "$TOOL" --prev deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
check_status "an unresolvable --prev is an argument error -> exit 2" 2 "$STATUS"
check_contains "the unresolvable --prev is named" "$OUT" "deadbeef"

run_in "$r" "$TOOL" --baseline refs/remotes/origin/nonexistent
check_status "an unresolvable --baseline is an argument error -> exit 2" 2 "$STATUS"
check_contains "an unresolvable baseline points back at --baseline" "$OUT" "--baseline"

run_in "$r" "$TOOL" --nonsense
check_status "an unknown option -> exit 2" 2 "$STATUS"

run_in "$r" "$TOOL" stray-positional
check_status "a stray positional argument -> exit 2" 2 "$STATUS"
check_contains "the stray positional points at --prev" "$OUT" "--prev"

run_in "$r" "$TOOL" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "usage"

# --- outside a repository --------------------------------------------------------------------------
notrepo="$(mktemp -d "$SANDBOX/notrepo.XXXXXX")"
run_in "$notrepo" "$TOOL"
check_status "outside a git repository -> exit 3" 3 "$STATUS"
check_contains "the non-repo refusal says so" "$OUT" "git repository"

summary
