#!/usr/bin/env bash
# Keel test runner — execute every tests/test_*.sh in its own process and aggregate.
# Each test file sets up (and tears down) its own isolated sandbox HOME (tests/lib.sh), so files
# run independently of each other — that's what makes concurrent execution below safe. The one
# externally-shared resource any file touches, tools/pre-pr-gate.sh's /tmp sentinel (dir #80), is
# keyed off a repo basename that every fixture mints via `mktemp -d "$SANDBOX/repo.XXXXXX"`
# (tests/lib.sh's new_repo(), and pipeline-canary.sh's own toy-repo setup) — randomized per
# process, so two files running at once cannot collide on it either (dir #130).
#
# Portable to bash 3.2 (macOS's shipped /bin/bash) on purpose — no `wait -n`, no associative
# arrays: a poll loop over tracked PIDs stands in for both.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# dir #627: every tests/test_*.sh sources tests/lib.sh, which is what redirects HOME into a
# disposable sandbox before any fixture runs. Each test file's own source line now fails closed too
# (`|| exit`, same ticket), but refusing HERE, before any test file even starts, catches it earlier
# and names the remedy in one place instead of 82 near-identical stderr lines. The adopter shape
# (claude-kb) consumes both this file and lib.sh as gitignored symlinks into this checkout, which
# `git worktree add` does not materialise (KB.100) — the felt incident this ticket exists for.
if [ ! -f "$here/lib.sh" ]; then
  printf 'FATAL: %s/lib.sh is missing — refusing to run the suite outside its sandbox (dir #627).\n' "$here" >&2
  printf '       every test file depends on it to redirect HOME; without it, fixtures run against\n' >&2
  printf '       the real machine. If tests/lib.sh is a symlink in your checkout, re-run whatever\n' >&2
  printf '       bootstrap step creates it (a fresh worktree omits gitignored symlinks).\n' >&2
  exit 1
fi

# dir #318: a corruption canary for the checkout this suite itself runs from — every test file's
# fixtures are supposed to mutate only their own tests/lib.sh sandbox (mktemp'd HOME/repo dirs), never
# the real repo the process happened to start in. A rare, non-deterministic leak of that kind was found
# once via `git reflog` (fixture commit messages and branch names from test_pre_pr_gate.sh's own
# crossfork-PR fixtures, appended to a real feature branch) but was not reproduced under repeated single-
# file and full concurrent runs against a real worktree. Record this real checkout's branch/HEAD/working-
# tree status before the suite runs so a recurrence is caught loudly instead of silently, whether or not
# the individual test files themselves report a failure. The status snapshot is a before/after COMPARE,
# not an assert-clean — a developer may genuinely run this suite with uncommitted changes already
# present, and only a change in that snapshot (not its mere non-emptiness) means something moved.
guard_repo_root="$(cd "$here/.." && pwd)"
guard_before_branch="" guard_before_head="" guard_before_status=""
guard_before_reflog=""
guard_before_config=""
guard_ref_scope_available=0

# dir #630 S4 tripwire, widened (T1, delta-audit 0.11.0-0.12.0 fix round): the original tripwire
# snapshotted exactly two named keys (keel.impactStore / keel.readTraceStore), so any OTHER config
# write a fixture leaked into the real checkout — a stray `git config --local --add` outside those
# two keys — went unreported (live-verified: `git -C "$guard_repo_root" config --local --add
# zz.probeKey x` exits 0 and trips nothing under the old two-key snapshot). Snapshot the WHOLE local
# config instead and diff it before/after. `branch.<name>.merge`/`branch.<name>.remote` are EXCLUDED,
# on evidence, not by default: local config is shared by every worktree of this repo, and ordinary
# concurrent work outside this suite writes these constantly — `git push -u` / `branch
# --set-upstream-to`. Measured live on this checkout: 128 of 139 local config keys are exactly this
# per-branch tracking shape (`git config --local --name-only --list | grep '^branch\.' | sed -E
# 's/.*\.([^.]+)$/\1/' | sort | uniq -c` → all `merge`/`remote`), and this canary already tripped on
# exactly that noise 8x this release. The exclusion is scoped to that shape specifically — three or
# more dot-separated segments under `branch.` — NOT the whole `branch.*` namespace: a bare top-level
# `[branch]` setting (`branch.autoSetupMerge`, `branch.sort` — real git-config(1) keys, unrelated to
# per-branch tracking) still trips, since `^branch\.` alone would have silently swallowed those too
# (found live by this ticket's own `/code-review high` pass). Everything else this suite watches
# (core.*, extensions.*, remote.*, keel.*, …) changes rarely enough in ordinary operation that a
# change there still deserves the loud trip below — this is the one disclosed, named residual, not a
# silent blanket allowance for every namespace.
guard_config_snapshot() {
  git -C "$1" config --local --list 2>/dev/null | grep -vE '^branch\.[^.=]+\.[^.=]+=' | LC_ALL=C sort || true
}

# guard_redact_diff_values — the widened snapshot above compares full `key=value` lines (a value-only
# change on an existing key must still trip), but a CHANGED VALUE is exactly what must never reach the
# trip report's own printed output: some config namespaces this snapshot now also watches CAN
# legitimately carry a credential (`actions/checkout` persists one into `http.<url>.extraHeader` by
# default; a `remote.*.url` sometimes embeds a token) — manager-flagged, dir #630 S4/T1 (delta-audit
# 0.11.0-0.12.0 fix round), the old two-key snapshot never had this exposure since it only ever
# watched two path-like keel.* keys. Does NOT key off `diff`'s own line-prefix convention (an earlier
# version of this filter matched a literal `< `/`> ` two-byte prefix and shipped believing that was
# universal — found live by this ticket's own /code-review high pass, run against a real alpine:3.21
# container: busybox `diff` defaults to UNIFIED format with no such prefix at all, `-`/`+`/`---`/`+++`/
# `@@`, so that version's redaction silently no-opped on the one CI leg this exists to protect,
# printing the raw credential straight through). Instead: any line containing `=` gets everything from
# its FIRST `=` onward cut, keeping only what precedes it (a key name, plus whatever diff's own
# leading marker character(s) already are — `<`/`>`/`-`/`+`, unaffected either way); a line with no `=`
# at all (a hunk header, a `---`/`+++`/`@@` divider) passes through untouched. This works identically
# under GNU/BSD diff's normal format and busybox's unified format, verified against both. Known,
# accepted residual (disclosed, not silently accepted): a MULTI-LINE config value's own continuation
# line carries no `key=` prefix of its own, so it isn't cut by this filter — git-config values with an
# embedded literal newline are exceedingly rare in practice (neither of this fix's two motivating
# shapes, `http.*.extraHeader` or an inline-token URL, is ever multi-line) and are left as a stated gap
# rather than a stateful multi-line-aware parser this fix's scope doesn't call for. Pure bash (no
# `sed -E`/`-r`): a GNU-only sed flag is the exact live portability trap category this replaces
# (CLAUDE.md's Linux-leg traps), and this filter needs none.
guard_redact_diff_values() {
  local line
  while IFS= read -r line; do
    case "$line" in
      *=*) printf '%s\n' "${line%%=*}" ;;
      *)   printf '%s\n' "$line" ;;
    esac
  done
}

if git -C "$guard_repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  guard_before_branch="$(git -C "$guard_repo_root" branch --show-current 2>/dev/null || true)"
  guard_before_head="$(git -C "$guard_repo_root" rev-parse HEAD 2>/dev/null || true)"
  guard_before_status="$(git -C "$guard_repo_root" status --porcelain 2>/dev/null || true)"
  # dir #630 S4: this suite must never write the real checkout's own provenance record (multi-valued
  # keel.impactStore / keel.readTraceStore, or any other key, in ITS local git config) — every B-test
  # that exercises S4 writes that key only inside a $SANDBOX-cloned repo (new_repo()), never against
  # $guard_repo_root itself. `--list` returns rc 1 (no local config) or rc 128 (not a repo); both are
  # swallowed by `|| true`, same as the rest of this canary. Captured here, compared after the run
  # below. The old two named-key snapshot is a subset of this one, so keel.impactStore /
  # keel.readTraceStore still trip exactly as before — deliberately not excluded, unlike branch.*
  # above: this is the exact leak class dir #630 S4 exists to catch (the #466 incident wrote
  # keel.readTraceStore into the real checkout). Known, accepted residual (manager-flagged): a value
  # found here is AMBIGUOUS, not necessarily a leak — dir #630 S4/S13 record provenance in the
  # project's own local config by design, so when an operator works in the keel checkout itself, the
  # read-trace hook / keel-impact's backfill legitimately write these same two keys into it on their
  # first-ever write, and that can land while an unrelated suite run happens to be in flight. This
  # canary deliberately errs toward reporting anyway — a missed leak (#466) is the expensive failure
  # mode, a one-time false trip is cheap to reconcile by hand, which the two-way attribution it prints
  # either way ("either a test escaped its sandbox, or something outside the suite changed this
  # checkout during the run") already covers correctly for this case too.
  guard_before_config="$(guard_config_snapshot "$guard_repo_root")"

  # dir #333: the compare above cannot see the two channels dir #320's own leak was actually found
  # through — a stray BRANCH left in the real repo, or a REFLOG entry appended without moving HEAD.
  # tools/lib/ref-guard.sh has the full rationale and the ownership-scoping helpers this needs (a
  # naive whole-namespace refs/heads compare trips on every sibling worktree's own branch churn).
  #
  # Sourced from guard_repo_root (the WATCHED checkout), not $here — deliberately, since the two can
  # differ: the claude-kb adopter shape symlinks only tests/run.sh and tests/lib.sh (dir #627) into a
  # DIFFERENT real checkout (~/.keel/kb) than the one this file's own code lives in
  # (~/.keel/engine) — `$here` there is the symlink's directory, and `guard_repo_root` is one level up
  # from that, i.e. the KB checkout, which carries no tools/lib/ of its own. Optional, not fail-closed
  # like tests/lib.sh's own presence check at the top of this file (dir #627): a MISSING helper here
  # degrades to the pre-#333 branch/HEAD/status-only compare with a one-line notice, rather than
  # killing a suite this ticket was never meant to touch (release-manager-verified seam).
  guard_lib="$guard_repo_root/tools/lib/ref-guard.sh"
  # shellcheck source=/dev/null
  if [ ! -f "$guard_lib" ]; then
    printf 'NOTE: %s not found here — the refs/heads + reflog half of the corruption canary\n' "$guard_lib" >&2
    printf '      (dir #333) is skipped; the branch/HEAD/status compare (dir #318) still runs.\n' >&2
  elif ! source "$guard_lib"; then
    # A distinct message from the "not found" case above (dir #333, review-caught): the file EXISTS
    # but failed to source — a syntax error, a permissions problem, a partial checkout — which is a
    # different, more alarming signal than "this adopter simply doesn't carry tools/lib/" and should
    # not be reported as if it were that ordinary case.
    printf 'NOTE: %s exists but failed to source — the refs/heads + reflog half of the corruption\n' "$guard_lib" >&2
    printf '      canary (dir #333) is skipped; the branch/HEAD/status compare (dir #318) still runs.\n' >&2
  else
    guard_ref_scope_available=1
    guard_before_owned="$(guard_owned_branches "$guard_repo_root")"
    guard_before_refs="$(guard_refs_snapshot "$guard_repo_root")"
    # Bounded reflog-HEAD compare: unlike refs/heads, HEAD's reflog is PRIVATE per worktree (logs/HEAD
    # lives under .git/worktrees/<name>, never the common dir), so there is no sibling-session noise
    # to filter here. Count entries, not content — a developer legitimately committing mid-run also
    # grows this count, but that already trips the HEAD compare above, so growth here alongside an
    # UNCHANGED HEAD is the specific gap this ticket exists to close (a checkout-and-return, or a
    # create-then-delete, that appends to the reflog but leaves `rev-parse HEAD` as if nothing
    # happened).
    guard_before_reflog="$(guard_reflog_count "$guard_repo_root")"
  fi
fi

# KEEL_TEST_JOBS overrides the concurrency cap (e.g. `KEEL_TEST_JOBS=1 ./tests/run.sh` to force the
# old fully-sequential behavior for debugging a suspected cross-file interaction).
#
# Default: host CPU count, EXCEPT under CI ($CI, set by GitHub Actions and effectively every other
# CI provider) where it's capped at 2 regardless of the reported count. dir #153 found the
# alpine-in-docker leg's nproc-reported count didn't reflect the container's real share of the
# runner, and dir #154 confirmed the same fork-contention flake on a plain ubuntu-24.04 leg too —
# no file the flaking check reads is ever mutated during the suite, so it isn't a content race; it's
# many test files' own subprocess forking (git/awk/grep) stacking up under this runner's own
# concurrency, enough to starve a fork on a small hosted runner regardless of OS or container. One
# CI-wide default here means a future CI leg gets the safe cap for free instead of needing its own
# copy of this fix in .github/workflows/ci.yml (KEEL_TEST_JOBS stays available as the manual
# override for a local repro).
jobs_cap="${KEEL_TEST_JOBS:-}"
if [ -z "$jobs_cap" ]; then
  if [ -n "${CI:-}" ]; then
    jobs_cap=2
  else
    jobs_cap="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  fi
fi
case "$jobs_cap" in (*[!0-9]*|'') jobs_cap=4 ;; esac
[ "$jobs_cap" -ge 1 ] || jobs_cap=1

logdir="$(mktemp -d)"
trap 'rm -rf "$logdir"' EXIT

failed=0
active_pids=()
active_files=()
active_logs=()

# Concurrency amplifies the blast radius of an interrupt: an orphaned `bash "$t"` leaves its own
# sandbox HOME (tests/lib.sh) behind uncleaned, AND — unlike the old sequential runner, which
# streamed each test's output straight to the terminal as it ran — an interrupted test's already-
# buffered-but-not-yet-printed log would otherwise be silently lost (killed before reap_finished
# ever cats it, then the EXIT trap deletes $logdir on the way out). Print every still-active test's
# log before killing it, so an operator interrupting a hung run still gets the same diagnostic
# trail the old runner gave for free (found by an operator-run /code-review high pass, dir #130).
# Doesn't reach a grandchild subprocess a test file itself spawned (no process-group kill) — a
# known, currently-unreachable gap: every test's git/gh/curl usage today is local-only or stubbed.
on_interrupt() {
  local i
  for i in "${!active_pids[@]}"; do
    printf '\n=== %s (interrupted) ===\n' "${active_files[$i]}"
    cat "${active_logs[$i]}" 2>/dev/null
  done
  # ${active_pids[@]+...} guards an empty array under `set -u` (bash 3.2 treats an empty array's
  # [@] expansion as unbound), same idiom reap_finished uses below.
  kill "${active_pids[@]+"${active_pids[@]}"}" 2>/dev/null
  exit 130
}
trap on_interrupt INT TERM

# Wait for and report every job in active_* whose process has already exited, compacting the
# arrays down to only the ones still running. Prints how many it reaped (as $?) so a caller can
# skip the poll sleep on a pass that just freed a slot instead of idling out the rest of it.
reap_finished() {
  local new_pids=() new_files=() new_logs=()
  local i pid rc reaped=0 log_content
  for i in "${!active_pids[@]}"; do
    pid="${active_pids[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      new_pids+=("$pid")
      new_files+=("${active_files[$i]}")
      new_logs+=("${active_logs[$i]}")
      continue
    fi
    wait "$pid"
    rc=$?
    # Read the log ONCE into a variable — it's about to be both printed and pattern-matched below,
    # and this loop runs once per completed test file (~83 times a full suite run), so a second read
    # + an external `grep` fork per file is avoidable work. The trailing `printf x` + `%x` strip is
    # NOT decorative: bare `$(<file)`/`$(cat file)` command substitution strips ALL trailing
    # newlines, so a log that is empty, or ends in multiple blank lines, or has no trailing newline
    # at all, would no longer print identically to what the old bare `cat` printed (verified live:
    # an empty log used to print nothing and would otherwise gain a spurious blank line). Appending a
    # sentinel byte defeats the stripping; stripping the sentinel back off afterward restores the
    # log's exact original bytes for any log this suite actually produces. One narrower caveat a
    # bare `cat` didn't have (found live by an independent /code-review high delta pass): bash
    # strings can't hold NUL, so `$(...)` silently drops any embedded NUL byte, unlike a bare `cat`
    # writing raw bytes straight to stdout — currently latent, since every test file in this suite
    # writes NUL-bearing content (e.g. `utf16le()` fixtures) to a FILE a scanned tool reports on by
    # name, never to its own stdout that this loop captures.
    log_content="$(cat "${active_logs[$i]}"; printf x)"
    log_content="${log_content%x}"
    printf '\n=== %s ===\n' "${active_files[$i]}"
    printf '%s' "$log_content"
    # dir #627, second fail-open: a test file calling an assertion lib.sh does not define loses that
    # assertion SILENTLY (bash prints its own "command not found" and, under lib.sh's `set -uo
    # pipefail` with no `-e`, keeps going) — the file can still exit 0 with fewer checks than it meant
    # to run. lib.sh's own command_not_found_handle (same ticket) closes this on bash >= 4 (CI's Linux
    # legs, where it also means the literal string below is never bash's own — that handler's own FATAL
    # message runs instead, and kills the file outright, so $rc is already nonzero there); this scan is
    # the portable backstop for bash 3.2 (this project's own dev machine), where the handler never fires
    # and bash prints its own message and returns 127. Anchored to bash's own exact message SUFFIX
    # (`: command not found` at a line's end — verified live, identical on macOS bash 3.2 and GNU bash,
    # only the leading `bash:`/`bash: line N:` prefix differs), not a bare substring: a future test's
    # own PASS-labeled string that happens to mention the phrase in some other shape won't false-fire
    # this (found by an independent /code-review high pass on this ticket's own diff). Two bash pattern
    # alternatives, no subprocess: mid-content (followed by a newline) or the very last line (string
    # end, no trailing newline). Only escalates an otherwise-green ($rc -eq 0) file: one that already
    # failed is already counted below.
    if [ "$rc" -eq 0 ] && { [[ "$log_content" == *': command not found'$'\n'* ]] || [[ "$log_content" == *': command not found' ]]; }; then
      printf '!!! %s exited 0 but its log shows "command not found" — an unknown assertion likely vanished silently (dir #627)\n' "${active_files[$i]}"
      rc=1
    fi
    [ "$rc" -eq 0 ] || failed=$((failed + 1))
    reaped=$((reaped + 1))
  done
  active_pids=("${new_pids[@]+"${new_pids[@]}"}")
  active_files=("${new_files[@]+"${new_files[@]}"}")
  active_logs=("${new_logs[@]+"${new_logs[@]}"}")
  return "$reaped"
}

# Block until at most $1 jobs remain active, reaping (and printing) each as it finishes. Used both
# to throttle launches (wait for a free slot) and, with 0, to drain everything at the end.
wait_until_at_most() {
  while [ "${#active_pids[@]}" -gt "$1" ]; do
    reap_finished && sleep 0.1  # reap_finished's $? is how many it reaped — 0 means still full, poll again
  done
}

# Room to keep for the job about to launch, so the loop below caps steady-state concurrency at
# jobs_cap rather than jobs_cap+1: throttling post-launch (the original shape) let one extra job
# run for the instant between a launch and its own throttle check — with KEEL_TEST_JOBS=1 that
# meant two jobs overlapping instead of the true one-at-a-time the env var promises (found by an
# operator-run /code-review high pass, dir #130).
launch_cap=$((jobs_cap - 1))
for t in "$here"/test_*.sh; do
  wait_until_at_most "$launch_cap"
  base="$(basename "$t")"
  log="$logdir/$base.log"
  bash "$t" >"$log" 2>&1 &
  active_pids+=("$!")
  active_files+=("$base")
  active_logs+=("$log")
done
wait_until_at_most 0

# Trip the canary set up above: if the real checkout's branch, HEAD, or working-tree status changed
# during the run, a test fixture leaked a real git mutation outside its sandbox — flag it loudly
# regardless of whether any individual test file reported a failure of its own. The status half catches
# a leak that dirties the tree/index without moving HEAD (a stray file write, a staged-but-uncommitted
# change) that the branch/HEAD compare alone would miss.
if [ -n "$guard_before_head" ]; then
  guard_after_branch="$(git -C "$guard_repo_root" branch --show-current 2>/dev/null || true)"
  guard_after_head="$(git -C "$guard_repo_root" rev-parse HEAD 2>/dev/null || true)"
  guard_after_status="$(git -C "$guard_repo_root" status --porcelain 2>/dev/null || true)"
  guard_after_config="$(guard_config_snapshot "$guard_repo_root")"
  guard_before_refs_unowned="" guard_after_refs_unowned="" guard_after_reflog=""
  if [ "$guard_ref_scope_available" = 1 ]; then
    guard_after_owned="$(guard_owned_branches "$guard_repo_root")"
    guard_after_refs="$(guard_refs_snapshot "$guard_repo_root")"
    guard_after_reflog="$(guard_reflog_count "$guard_repo_root")"

    # Union of both snapshots' owned branches: one that stopped (or started) being owned mid-run is
    # still explained by that peer's own worktree lifecycle, not by this suite's fixtures.
    guard_owned_union="$(guard_union "$guard_before_owned" "$guard_after_owned")"
    guard_before_refs_unowned="$(guard_filter_unowned "$guard_owned_union" "$guard_before_refs")"
    guard_after_refs_unowned="$(guard_filter_unowned "$guard_owned_union" "$guard_after_refs")"
  fi

  if [ "$guard_after_branch" != "$guard_before_branch" ] || [ "$guard_after_head" != "$guard_before_head" ] \
      || [ "$guard_after_status" != "$guard_before_status" ] \
      || [ "$guard_before_refs_unowned" != "$guard_after_refs_unowned" ] \
      || [ "$guard_after_reflog" != "$guard_before_reflog" ] \
      || [ "$guard_after_config" != "$guard_before_config" ]; then
    printf '\n!!! TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #318) !!!\n'
    printf 'the real checkout this suite ran from changed during the run:\n'
    printf '  before: branch=%s head=%s\n' "$guard_before_branch" "$guard_before_head"
    printf '  after:  branch=%s head=%s\n' "$guard_after_branch" "$guard_after_head"
    # dir #333 (release-manager amendment, W10's reproduction): the likeliest innocent cause is the
    # worker's OWN commit landing while a background `./tests/run.sh` was still alive against this
    # same checkout — the branch/HEAD compare above cannot tell that apart from a real leak, but it
    # CAN tell whether after-HEAD is a plain fast-forward of before-HEAD on the same branch, which a
    # fixture's stray mutation would not typically be. Name the likely cause without downgrading the
    # trip — still a real "do not push until reconciled" until a human confirms which it was.
    if [ "$guard_after_branch" = "$guard_before_branch" ] && [ "$guard_after_head" != "$guard_before_head" ] \
        && git -C "$guard_repo_root" merge-base --is-ancestor "$guard_before_head" "$guard_after_head" 2>/dev/null; then
      printf '  HEAD moved FORWARD on the same branch — possibly your own commit landing while this\n'
      printf '  same ./tests/run.sh was still running in the background against this checkout (never\n'
      printf '  commit against a checkout while its own suite run is still alive), or another ordinary\n'
      printf '  fast-forward (a pull, a fetch+merge) — rather than a leak. Reconcile by hand either way —\n'
      printf '  a moved HEAD is not automatically safe just because it fast-forwards.\n'
    fi
    if [ "$guard_after_status" != "$guard_before_status" ]; then
      printf '  working-tree/index status also changed (git status --porcelain differs from before the run)\n'
      # T3 (delta-audit 0.11.0-0.12.0 fix round, S2 lead L3 / manager lead 3): the HEAD-moved shape
      # above already gets a dedicated "possibly your own commit" hint; the status-only shape (HEAD
      # unmoved, felt live by a worker whose own uncommitted edit landed on this checkout while its
      # own background ./tests/run.sh was still alive) had none — just the generic line above. Mirror
      # the HEAD-moved hint here without downgrading the trip: still "do not push" either way.
      if [ "$guard_after_head" = "$guard_before_head" ]; then
        printf '  HEAD did not move — possibly your own uncommitted edit (or a concurrent session'"'"'s) to\n'
        printf '  this checkout while this same ./tests/run.sh was still running in the background (never\n'
        printf '  edit a checkout while its own suite run is still alive). Reconcile by hand either way.\n'
      fi
    fi
    if [ "$guard_before_refs_unowned" != "$guard_after_refs_unowned" ]; then
      printf '  an unowned branch (in refs/heads, checked out by no worktree) appeared, moved, or\n'
      printf '  disappeared during the run (dir #333):\n%s\n' \
        "$(diff <(printf '%s\n' "$guard_before_refs_unowned") <(printf '%s\n' "$guard_after_refs_unowned"))"
      printf '  an ordinary test file cannot have done this on its own — tests/lib.sh guard (dir #318) refuses every test ref write it makes — so look outside the suite first (dir #318 residual N8, an inherited GIT_DIR+GIT_COMMON_DIR pair, was the one narrow exception; dir #644 closed it, so this trip has no known exception left to hedge for).\n'
    fi
    if [ "$guard_after_reflog" != "$guard_before_reflog" ]; then
      printf '  HEAD reflog entry count changed during the run (%s -> %s) (dir #333)\n' \
        "$guard_before_reflog" "$guard_after_reflog"
    fi
    if [ "$guard_after_config" != "$guard_before_config" ]; then
      printf '  this checkout'"'"'s own local git config changed during the run (dir #630 S4 tripwire,\n'
      printf '  widened to the whole local config — per-branch tracking keys excluded, see tests/run.sh\n'
      printf '  comment above). Key(s) that changed (values withheld — see guard_redact_diff_values'"'"'s\n'
      printf '  own comment: some namespaces this snapshot now also watches can legitimately carry a\n'
      printf '  credential, e.g. actions/checkout'"'"'s own http.*.extraHeader):\n'
      printf '%s\n' "$(diff <(printf '%s\n' "$guard_before_config") <(printf '%s\n' "$guard_after_config") | guard_redact_diff_values)"
      printf '  a test wrote to the real repo'"'"'s own local git config instead of a $SANDBOX-cloned one — fix the fixture, never disable this check.\n'
    fi
    # dir #318: this used to name only "a fixture helper" as the cause. tests/lib.sh's guard now
    # refuses every ref write a test makes against this checkout, so an unowned-branch change can no
    # longer come from a test file — the two-way attribution below reflects that (either a test
    # somehow escaped its sandbox, or something outside the suite changed the checkout mid-run).
    printf 'either a test escaped its sandbox, or something outside the suite changed this checkout during the run:\n'
    printf 'do not push this branch until the real history is reconciled by hand.\n'
    failed=$((failed + 1))
  fi
fi

printf '\n========================================\n'
# dir #333, review-caught: the NOTE above ran once, near the top, on stderr — easy to miss in a long
# scrollback or a CI harness that only tails stdout. Repeat it once more, right next to the pass/fail
# verdict a reader actually looks at, so a checkout missing tools/lib/ref-guard.sh doesn't read as
# silently equivalent to one with the full canary.
if [ "$guard_ref_scope_available" != 1 ] && [ -n "$guard_before_head" ]; then
  printf 'NOTE: the refs/heads + reflog half of the corruption canary (dir #333) did not run this\n' >&2
  printf '      time — see the NOTE near the top of this output for why.\n' >&2
fi
if [ "$failed" -eq 0 ]; then
  printf 'ALL TEST FILES PASSED\n'
  exit 0
fi
printf '%d TEST FILE(S) FAILED\n' "$failed"
# dir #480: a failing run's per-file logs (each test file's full, non-truncated stdout+stderr,
# already `cat`'d above but about to be deleted by the EXIT trap regardless) are the one thing that
# turns a one-off local failure into checkable evidence instead of an anecdote — the shape dir #480
# itself was filed from. Disarm the cleanup trap and name the surviving dir; a passing run is
# unaffected and still cleans up via the trap as before.
trap - EXIT
printf 'per-file logs preserved for inspection: %s\n' "$logdir"
exit 1
