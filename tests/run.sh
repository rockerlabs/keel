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
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

# dir #653: the WHOLE runner body lives in main(), called by the last line. bash reads a script
# incrementally, from a file offset, as it runs — so a test that overwrites this very file in place
# (a fixture write through a symlink into the checkout; the 2026-09-22 claude-kb incident) used to
# make the runner resume at a stale offset in the NEW bytes: its canary below never ran and the exit
# status was whatever the last command happened to return, with no message. A function body is parsed
# in full before main() runs, and the final `main "$@"; exit $?` is ONE line parsed before it
# executes, so nothing after it is ever read from the file. Keep every statement below inside main().
main() {
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

  # dir #653: fingerprint the two files this whole suite's safety rests on — this runner and lib.sh —
  # and compare at the end. main() above keeps an overwritten run.sh from silencing the canary; this
  # half REPORTS the overwrite. It needs no git, so it also covers a checkout the suite does not own
  # (claude-kb consumes both files as symlinks into this one; cksum follows the link to the real bytes).
  guard_run_before="$(cksum < "$0" 2>/dev/null)"
  guard_lib_before="$(cksum < "$here/lib.sh" 2>/dev/null)"

  # dir #664: `git status --porcelain` is a before/after compare of STATUS CODES, so a leak that rewrites a
  # tracked file the operator already had uncommitted edits in (` M f` before, ` M f` after) moves nothing it
  # can see (found by the 0.13.0 delta audit: a clean file's overwrite exits 1, the same overwrite over an
  # uncommitted edit exits 0 and prints ALL TEST FILES PASSED). This is the second snapshot beside it: one
  # line per tracked path that differs from HEAD (staged or not) — `path`, a TAB, the `cksum` of its
  # working-tree bytes (`<crc> <bytes>`; `(unreadable)` for a deleted path or a directory). Like
  # guard_config_snapshot, the raw bytes are never held past the `cksum` and never printed, so the
  # dir #318 redaction rule holds by construction; a content change under an unchanged status changes the
  # fingerprint, so the trip still fires. `--no-optional-locks` (a read-only canary must not take the index
  # lock a peer's own git command may hold) and `--no-renames` (list both sides of a rename); `-z` keeps a
  # path with a newline one record (shown with a literal \n). The git call's own failure (an unborn HEAD,
  # an unreadable index) yields an empty snapshot, the same on both sides, so it can only under-report —
  # the status compare it sits beside still runs. Axis, named: it sees tracked paths that differ from
  # HEAD; an untracked file's overwrite is invisible here (its name is, via the status compare, when it
  # first appears) — that is the unchanged `-uno` / untracked scope of the compares it sits beside.
  # Defined up here, before the first snapshot of either half, so both take theirs through it.
  guard_dirty_fingerprint() {
    local repo="$1" path sum
    while IFS= read -r -d '' path; do
      sum="$(cksum < "$repo/$path" 2>/dev/null)" || sum="(unreadable)"
      printf '%s\t%s\n' "${path//$'\n'/\\n}" "$sum"
    done < <(git --no-optional-locks -C "$repo" diff --name-only --no-renames -z HEAD -- 2>/dev/null) | LC_ALL=C sort
  }

  # guard_unique_lines A B — the lines found in only one of two snapshots (`comm -3`: POSIX, present on
  # alpine's busybox), its column-2 TAB indent and blank lines removed.
  guard_unique_lines() {
    local tab=$'\t'
    LC_ALL=C comm -3 <(printf '%s\n' "$1" | LC_ALL=C sort) <(printf '%s\n' "$2" | LC_ALL=C sort) \
      | sed -e "s/^${tab}*//" -e '/^$/d'
  }

  # guard_changed_paths STATUS_BEFORE STATUS_AFTER FP_BEFORE FP_AFTER — dir #656 half 2: the NAMES of the
  # paths that differ between the two `git status --porcelain` snapshots (a porcelain line is `XY path`, so
  # the name is everything from column 4; an untracked directory is its own `?? dir/` entry) and between the
  # two guard_dirty_fingerprint snapshots (everything before the last TAB), sorted, one per line. Names only:
  # a status line is already `XY name`, and a fingerprint line is cut at its TAB before it is printed, so no
  # content and no checksum can reach the report.
  guard_changed_paths() {
    local tab=$'\t'
    {
      guard_unique_lines "$1" "$2" | cut -c4-
      guard_unique_lines "$3" "$4" | sed "s/${tab}[^${tab}]*\$//"
    } | LC_ALL=C sort -u
  }

  # guard_print_changed_paths NAMES — print guard_changed_paths' output as the trip block's names list, the
  # first 25 only (a trip over a wide tree must not bury the verdict; the count says how many were cut).
  guard_print_changed_paths() {
    printf '  paths that differ between the before and after snapshots (names only, never content):\n'
    printf '%s\n' "$1" | awk '
      $0 == "" { next }
      { n++ }
      n <= 25 { print "    " $0 }
      END {
        if (n > 25) printf "    ... and %d more\n", n - 25
        if (n == 0) print "    (none to name — the difference is not a path)"
      }'
  }

  # guard_print_fp_note — the trip line both halves print when only a content fingerprint moved.
  guard_print_fp_note() {
    printf '  content of a tracked file that already had uncommitted changes differs from before the run\n'
    printf '  (a working-tree fingerprint of every tracked file differing from HEAD; the content itself is never printed)\n'
  }

  # dir #653 widening (0.13.0 groom G6): the dir #318 git canary watches guard_repo_root — in the
  # claude-kb shape the KB checkout, not the engine checkout a leaking test actually wrote into (4 of
  # the 6 files overwritten on 2026-09-22 were neither run.sh nor lib.sh). When $HOME/.keel/engine
  # resolves to a DIFFERENT git checkout than the watched one, snapshot its tracked-file status too.
  # `-uno`: a peer session's new untracked scratch file is not a leak. `--no-optional-locks`: a
  # read-only canary must not take the index lock a concurrent session's own git command may be holding.
  # No $HOME/.keel/engine at all, neither a directory nor a link (an adopter without the engine link, or
  # CI) -> the half is skipped without a word.
  #
  # delta-audit 0.13.0 S6-1 / R1 F1: an engine path that IS there but git cannot read used to skip the
  # half silently, at either step: resolving it (a dangling link — the checkout moved — a directory `cd`
  # cannot enter, another uid's checkout — "dubious ownership" — or not a checkout at all) or `status`
  # (a corrupted index, a git too old for `--no-optional-locks`). Either now prints a NOTE, repeated
  # beside the verdict. Neither fails the run: an unreadable checkout is an environment condition, not
  # evidence of a leak (dir #505 / dir #656: no existing trip changes meaning). Readable before the run
  # but not after IS a trip — see the compare below.
  guard_engine_root="" guard_engine_before="" guard_engine_fp_before="" guard_engine_ran=0 guard_engine_skipped=0 guard_repo_skipped=0
  guard_engine_skip() {
    printf 'NOTE: %s — the engine half of the corruption\n' "$1" >&2
    printf '      canary (dir #653) did NOT run this time; the suite is not watching that checkout.\n' >&2
    guard_engine_skipped=1
  }
  if [ -d "${HOME:-}/.keel/engine" ] || [ -L "${HOME:-}/.keel/engine" ]; then
    guard_engine_root="$(cd -P "${HOME:-}/.keel/engine" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "$guard_engine_root" ]; then
      guard_engine_skip "${HOME:-}/.keel/engine does not resolve to a checkout git can read"
    elif [ "$guard_engine_root" = "$(cd -P "$here/.." 2>/dev/null && pwd -P)" ]; then
      guard_engine_root=""               # the watched checkout itself — the dir #318 half already covers it
    fi
  fi
  if [ -n "$guard_engine_root" ]; then
    if guard_engine_before="$(git --no-optional-locks -C "$guard_engine_root" status --porcelain -uno 2>/dev/null)"; then
      guard_engine_ran=1
      guard_engine_fp_before="$(guard_dirty_fingerprint "$guard_engine_root")"   # dir #664
    else
      guard_engine_skip "\`git status\` of the engine checkout $guard_engine_root failed"
    fi
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
  guard_before_branch="" guard_before_head="" guard_before_status="" guard_before_fp=""
  guard_before_reflog=""
  guard_before_config=""
  guard_ref_scope_available=0

  # dir #630 S4 tripwire, widened (T1, delta-audit 0.11.0-0.12.0 fix round): the original tripwire
  # snapshotted exactly two named keys (keel.impactStore / keel.readTraceStore), so any OTHER config
  # write a fixture leaked into the real checkout — a stray `git config --local --add` outside those
  # two keys — went unreported (live-verified: `git -C "$guard_repo_root" config --local --add
  # zz.probeKey x` exits 0 and trips nothing under the old two-key snapshot). Snapshot the WHOLE local
  # config instead and diff it before/after. Every per-branch key (`branch.<name>.<key>` — `.merge` and
  # `.remote` are the two that actually churn, but this also covers `.description`, `.pushRemote`,
  # `.rebase`, `.vscode-merge-base`, any other subkey under a `[branch "<name>"]` section) is EXCLUDED,
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
  # F4b (S-fix F2-T1, delta-audit 0.11.0-0.12.0 fix round): the version above kept raw `key=value`
  # lines from `--list`, and guard_redact_diff_values (below) cut each DIFF line at its first `=` —
  # but `--list` prints a MULTI-LINE config value with a literal embedded newline, so that value's own
  # continuation line carries no `key=` prefix and passed the cut filter through untouched: a trip on a
  # changed multi-line value printed the key name AND its raw second (and any further) line, unredacted
  # (live-reproduced, macOS + alpine, git 2.52.0 — the exact gap the paragraph this replaces disclosed
  # as accepted). Fixed at the SOURCE, not by patching the filter a third time: `git config --local
  # --list -z` emits one NUL-terminated RECORD per entry, `key` LF `value` (a valueless boolean key's
  # record has no LF at all) — a multi-line value's own embedded newlines stay INSIDE that one record,
  # so no continuation line can ever exist to leak past a downstream filter. The raw value is never held
  # in a variable at all past the read: each line below is `key <fingerprint>`, fingerprint =
  # `printf '%s' "$value" | cksum` (POSIX; present on alpine's busybox) — a value-only change (including
  # a multi-line one) still changes the fingerprint, so the trip still fires, but nothing that could BE
  # a credential ever reaches a variable this file might print. Multi-valued keys (e.g. two
  # `keel.impactStore` entries) are two separate `-z` records — two separate lines here — and the
  # trailing `LC_ALL=C sort` keeps their relative order stable regardless of git's own listing order.
  # The per-branch-tracking exclusion above (dir #630 T1's own rationale: `.merge`/`.remote` churn on
  # every ordinary `git push -u`) is now applied to the KEY NAME directly instead of a `key=` line
  # prefix — same exact shape as before, exactly THREE dot-separated segments
  # (`branch.<name>.<subkey>`; a bare top-level `branch.autoSetupMerge` still trips, pinned by
  # tests/test_run_sh.sh). Pure bash — no `sed -E`/`-r`, and deliberately NOT `awk` with `RS="\0"`
  # (a known trap in this repo: busybox awk splits NULs into newlines, and BSD awk is unreliable on NUL
  # too) — verified on macOS bash 3.2 and the alpine leg's bash.
  guard_config_snapshot() {
    local repo="$1" rec key value rest fp lines=()
    while IFS= read -r -d '' rec; do
      key="${rec%%$'\n'*}"
      if [ "$rec" = "$key" ]; then
        value=""                       # a valueless boolean key's -z record has no embedded LF at all
      else
        value="${rec#*$'\n'}"
      fi
      case "$key" in
        branch.*.*)
          rest="${key#branch.}"
          case "$rest" in
            *.*.*) ;;                  # 3+ segments after "branch." — a real key, not per-branch tracking
            *) continue ;;             # exactly "name.subkey" — branch.<name>.<merge|remote|...>, excluded
          esac
          ;;
      esac
      fp="$(printf '%s' "$value" | cksum)"
      lines+=("$key $fp")
    done < <(git -C "$repo" config --local --list -z 2>/dev/null)
    printf '%s\n' "${lines[@]+"${lines[@]}"}" | LC_ALL=C sort
  }

  # guard_diff_keys_only — F4b: the ONE remaining redaction mechanism (the old guard_redact_diff_values
  # it replaces is retired — two mechanisms doing the same job is one too many). guard_config_snapshot
  # above never holds a raw value at all, only a `key <checksum> <bytecount>` line (cksum's own two-
  # field output), so nothing here is technically a "value" — but the trip report still has no business
  # printing anything past the key name, so this strips the fingerprint's own two trailing fields before
  # printing. Does NOT key off `diff`'s own line-prefix convention (found live against a real
  # alpine:3.21 container by an earlier version of this file's redaction: busybox `diff` defaults to
  # UNIFIED format, no `< `/`> ` prefix at all, just `-`/`+`/`---`/`+++`/`@@`): a hunk/file-header line
  # (`---`/`+++`/`@@`, either format) is named explicitly and passed through untouched; any other line
  # has its last two space-separated fields stripped via shortest-suffix removal (`${line% *}` twice —
  # matches the LAST space each time, unlike `%%` which would match the first), which is exactly the
  # checksum + byte-count fields `cksum` appends, however many characters the key name itself is or
  # whichever marker style (`< `/`> ` with a space, or busybox's bare `-`/`+`) precedes it. A line with
  # fewer than two spaces (nothing to strip) passes through unchanged either way, since the pattern
  # simply fails to match. Verified against both diff formats.
  guard_diff_keys_only() {
    local line rest
    while IFS= read -r line; do
      case "$line" in
        ---*|+++*|@@*) printf '%s\n' "$line" ;;
        *' '*' '*)
          rest="${line% *}"
          rest="${rest% *}"
          printf '%s\n' "$rest"
          ;;
        *) printf '%s\n' "$line" ;;
      esac
    done
  }

  # delta-audit 0.13.0 R2-2: the engine half's skip-with-a-NOTE, applied to the PRIMARY half. The dir #318 canary below used to be
  # skipped without a word whenever `git rev-parse --git-dir` failed for any reason — including the ones
  # that are not "this is not a repo": a checkout owned by another uid ("dubious ownership"), a corrupted
  # `.git`. A watched path that carries a `.git` yet cannot be read now prints the same NOTE, repeated
  # beside the verdict, with the same decision (reported, not failed). No `.git` at all stays the quiet,
  # ordinary skip (a git-less tree is not an environment fault).
  if git -C "$guard_repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    guard_before_branch="$(git -C "$guard_repo_root" branch --show-current 2>/dev/null || true)"
    guard_before_head="$(git -C "$guard_repo_root" rev-parse HEAD 2>/dev/null || true)"
    guard_before_status="$(git -C "$guard_repo_root" status --porcelain 2>/dev/null || true)"
    guard_before_fp="$(guard_dirty_fingerprint "$guard_repo_root")"   # dir #664
    # dir #630 S4: this suite must never write the real checkout's own provenance record (multi-valued
    # keel.impactStore / keel.readTraceStore, or any other key, in ITS local git config) — every B-test
    # that exercises S4 writes that key only inside a $SANDBOX-cloned repo (new_repo()), never against
    # $guard_repo_root itself. `--list -z` returns rc 1 (no local config) or rc 128 (not a repo); both
    # are swallowed — the `while read` loop inside guard_config_snapshot (F4b) simply sees zero `-z`
    # records either way, same net effect as the explicit `|| true` the rest of this canary uses, since
    # bash never checks a process substitution's own exit status. Captured here, compared after the run
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
  elif [ -e "$guard_repo_root/.git" ]; then
    printf 'NOTE: %s carries a .git that git cannot read — the dir #318 half of the corruption\n' "$guard_repo_root" >&2
    printf '      canary did NOT run this time; the suite is not watching the checkout it runs from.\n' >&2
    guard_repo_skipped=1
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

  # delta-audit 0.13.0 R2-1 / R2-4: the per-file logs live in a directory minted from a TEMPLATE rooted at
  # $TMPDIR — a bare `mktemp -d` ignores $TMPDIR on macOS, so the preserved-on-failure directory below
  # (dir #480) could not be redirected, and tests/test_run_sh.sh's failing fixtures left one in the real
  # temp dir on every run. And the result is checked, not trusted (the dir #627 class tests/lib.sh closed
  # for $SANDBOX): under `set -uo pipefail` with no `-e`, a failing `mktemp` yields an empty name, every
  # log path then resolves to `/<file>.log`, and as root the run could still print ALL TEST FILES PASSED.
  # A failed mint FAILS the run, loudly, before any test file starts.
  tmp_base="${TMPDIR:-/tmp}"
  tmp_base="${tmp_base%/}"
  logdir="$(mktemp -d "$tmp_base/keel-run.XXXXXX" 2>/dev/null)" || logdir=""
  if [ -z "$logdir" ] || [ "$logdir" = / ] || [ ! -d "$logdir" ]; then
    printf 'FATAL: mktemp -d did not return a usable log dir under %s (got %s) — refusing to run: the per-file logs would land outside a throwaway directory (delta-audit 0.13.0 R2-4).\n' "$tmp_base" "$logdir" >&2
    exit 1
  fi
  trap 'rm -rf "$logdir"' EXIT

  # dir #663 (b): the residue gate. The grep census (tests/test_no_bare_mktemp.sh) sees one call shape in
  # the test files; it did not see a bare logdir, a `trap - EXIT` that strands a sandbox, or a scratch
  # directory a TOOL keeps on purpose — the three mechanisms the 0.13.0 delta audit found only by counting
  # the real temp dir by hand around a run. This measures it. A `mktemp` shim ahead on PATH (every test
  # file and every tool it spawns inherits it) records each path the real mktemp hands back; after the last
  # file finishes, a recorded path that still exists is residue and fails the run. Why a trace and not a
  # before/after listing of the temp dir: the real temp dir is noisy — a sibling suite's live sandboxes
  # (`tmp.*`) and its own logdir (`keel-run.*`) sit there too, and a bare `mktemp` ignores $TMPDIR on macOS,
  # so no directory of ours can be named in advance. A path this run minted is its own, by construction.
  # The shim changes nothing a test sees: same output, same status, same stderr.
  # Axis, named: this sees mktemp called by name through PATH. It does not see a path made by `mkdir`, an
  # absolute /usr/bin/mktemp, or a process that resets PATH first. A test that clears the sandbox's removal
  # trap is still caught (the path was minted, and it survives), which a trap-side check could not see.
  resid_dir="$logdir/residue"
  resid_trace="$resid_dir/mktemp.trace"
  resid_real_mktemp="$(type -P mktemp 2>/dev/null || true)"
  # resid_write_shim FILE REAL TRACE — a POSIX-sh wrapper around REAL that appends the path it prints to TRACE
  # when that path exists afterwards (a `-u` dry run prints a name and makes nothing, so it is never
  # recorded; no option parsing to get wrong). A relative result is recorded absolute.
  resid_write_shim() {
    {
      printf '#!/bin/sh\n'
      printf 'real=%q\ntrace=%q\n' "$2" "$3"
      cat <<'SHIM'
out="$("$real" "$@")" || exit $?
printf '%s\n' "$out"
if [ -n "$out" ] && [ -e "$out" ]; then
  case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
  printf '%s\n' "$out" >> "$trace" 2>/dev/null
fi
exit 0
SHIM
    } > "$1" && chmod 755 "$1"
  }
  # Fail closed, like the logdir mint above: a gate that cannot watch must not report a clean run.
  resid_fatal() {
    printf 'FATAL: the residue gate (dir #663) could not be armed: %s — refusing to run: a leak into the real temp dir would go unseen.\n' "$1" >&2
    exit 1
  }
  [ -n "$resid_real_mktemp" ] || resid_fatal "no mktemp on PATH"
  mkdir "$resid_dir" 2>/dev/null && : > "$resid_trace" || resid_fatal "cannot create $resid_dir"
  resid_write_shim "$resid_dir/mktemp" "$resid_real_mktemp" "$resid_trace" || resid_fatal "cannot write the mktemp shim"
  # Non-vacuity: drive a second shim, whose "real" mktemp is a stub that makes its last argument a directory
  # and echoes it, and require the path to land in the trace. Proves the shim records without calling the
  # real mktemp (a test that watches the real one's calls must not see a probe).
  printf '#!/bin/sh\nfor a in "$@"; do :; done\nmkdir "$a" && printf "%%s\\n" "$a"\n' > "$resid_dir/probe-real" && chmod 755 "$resid_dir/probe-real" \
    || resid_fatal "cannot write the probe stub"
  resid_write_shim "$resid_dir/probe-shim" "$resid_dir/probe-real" "$resid_trace" || resid_fatal "cannot write the probe shim"
  resid_probe="$resid_dir/probe-marker.$$"
  "$resid_dir/probe-shim" -d "$resid_probe" >/dev/null 2>&1
  grep -qxF -- "$resid_probe" "$resid_trace" 2>/dev/null || resid_fatal "the shim did not record a probe path"
  PATH="$resid_dir:$PATH"
  export PATH
  [ "$(type -P mktemp 2>/dev/null)" = "$resid_dir/mktemp" ] || resid_fatal "the shim is not first on PATH"

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
    guard_after_fp="$(guard_dirty_fingerprint "$guard_repo_root")"   # dir #664
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
        || [ "$guard_after_fp" != "$guard_before_fp" ] \
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
        printf '  check (dir #505): git -C %s reflog -3 — a fresh entry of yours (commit/amend) made since the suite started\n' "$guard_repo_root"
        printf '  = your own commit; an entry you do not recognize = look for a leak.\n'
      fi
      if [ "$guard_after_status" != "$guard_before_status" ]; then
        printf '  working-tree/index status also changed (git status --porcelain differs from before the run)\n'
      fi
      # dir #664: the status codes can be IDENTICAL while a tracked file the operator already had dirty was
      # rewritten — say so in its own words, and (below) name the file.
      if [ "$guard_after_fp" != "$guard_before_fp" ]; then
        guard_print_fp_note
      fi
      if [ "$guard_after_status" != "$guard_before_status" ] || [ "$guard_after_fp" != "$guard_before_fp" ]; then
        # dir #656 half 2: WHICH paths — names only, from the two snapshots already in hand.
        guard_print_changed_paths "$(guard_changed_paths "$guard_before_status" "$guard_after_status" "$guard_before_fp" "$guard_after_fp")"
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
        printf '  comment above). Key(s) that changed (fingerprints only — this snapshot (F4b) never holds\n'
        printf '  a raw value at all, multi-line or not; see guard_config_snapshot'"'"'s own comment):\n'
        printf '%s\n' "$(diff <(printf '%s\n' "$guard_before_config") <(printf '%s\n' "$guard_after_config") | guard_diff_keys_only)"
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

  # dir #653: the compares that need no watched git repo — this runner's and lib.sh's own content, and
  # the engine checkout's tracked-file status. Independent of the dir #318 block above on purpose:
  # it must fire for a git-less tree too.
  guard_run_changed=0 guard_lib_changed=0 guard_engine_changed=0
  [ "$(cksum < "$0" 2>/dev/null)" = "$guard_run_before" ] || guard_run_changed=1
  [ "$(cksum < "$here/lib.sh" 2>/dev/null)" = "$guard_lib_before" ] || guard_lib_changed=1
  if [ "$guard_engine_ran" = 1 ]; then
    # Armed (readable before). `status` failing NOW is a change, never an empty "unchanged" compare: the
    # sentinel differs from any snapshot, so the diff below shows the failure.
    guard_engine_after="$(git --no-optional-locks -C "$guard_engine_root" status --porcelain -uno 2>/dev/null)" \
      || guard_engine_after='(git status failed)'
    [ "$guard_engine_after" = "$guard_engine_before" ] || guard_engine_changed=1
    # dir #664: the same fingerprint compare as the dir #318 half — an engine file the operator already had
    # dirty (` M` before and after) and a leak rewrote is invisible to the status codes above.
    guard_engine_fp_after="$(guard_dirty_fingerprint "$guard_engine_root")"
    [ "$guard_engine_fp_after" = "$guard_engine_fp_before" ] || guard_engine_changed=1
  fi
  if [ "$guard_run_changed" = 1 ] || [ "$guard_lib_changed" = 1 ] || [ "$guard_engine_changed" = 1 ]; then
    printf '\n!!! TEST-SUITE SELF-CORRUPTION GUARD TRIPPED (dir #653) !!!\n'
    if [ "$guard_run_changed" = 1 ]; then
      printf '  %s changed during the run: %s\n' "$(basename "$0")" "$0"
    fi
    if [ "$guard_lib_changed" = 1 ]; then
      printf '  %s changed during the run: %s\n' "lib.sh" "$here/lib.sh"
    fi
    if [ "$guard_engine_changed" = 1 ]; then
      printf '  the engine checkout changed during the run (tracked files only; `git status --porcelain -uno`\n'
      printf '  of %s, before -> after):\n%s\n' "$guard_engine_root" \
        "$(diff <(printf '%s\n' "$guard_engine_before") <(printf '%s\n' "$guard_engine_after"))"
      if [ "$guard_engine_fp_after" != "$guard_engine_fp_before" ]; then
        guard_print_fp_note
      fi
      # dir #656 half 2: the names, from the snapshots in hand — unless `status` itself failed after the run (its
      # sentinel is not a porcelain line, so there is nothing to name; the diff above shows the failure).
      if [ "$guard_engine_after" != '(git status failed)' ]; then
        guard_print_changed_paths "$(guard_changed_paths "$guard_engine_before" "$guard_engine_after" "$guard_engine_fp_before" "$guard_engine_fp_after")"
      fi
    fi
    printf 'either a test wrote into files it does not own, or something outside the suite did (your own edit\n'
    printf 'of one of these files while this run was alive counts — never edit a checkout while its own suite\n'
    printf 'run is still running). Do not push until the real contents are reconciled by hand.\n'
    failed=$((failed + 1))
  fi

  # dir #663 (b): the residue verdict (arming and rationale above). Every path the shim recorded that still
  # exists now is residue. The arming probe's own marker is the one recorded line that is not a test's.
  resid_paths=0 resid_left="" resid_left_n=0
  while IFS= read -r resid_p; do
    [ -n "$resid_p" ] || continue
    [ "$resid_p" != "$resid_probe" ] || continue
    resid_paths=$((resid_paths + 1))
    if [ -e "$resid_p" ] || [ -L "$resid_p" ]; then
      resid_left_n=$((resid_left_n + 1))
      [ "$resid_left_n" -gt 25 ] || resid_left="$resid_left  $resid_p"$'\n'
    fi
  done < <(LC_ALL=C sort -u "$resid_trace" 2>/dev/null)
  if [ "$resid_left_n" -gt 0 ]; then
    printf '\n!!! TEST-SUITE RESIDUE GATE TRIPPED (dir #663) !!!\n'
    printf '%d path(s) that mktemp minted during this run still exist (first 25):\n%s' "$resid_left_n" "$resid_left"
    printf 'a test, or a tool it ran, made scratch outside its sandbox, or cleared the trap that removes it\n'
    printf '(a bare `mktemp`, a `trap - EXIT`, a scratch file a tool keeps on purpose). Mint it under $SANDBOX, or\n'
    printf 'remove it where it is made. Trace of every path minted: %s\n' "$resid_trace"
    failed=$((failed + 1))  # residue gate verdict
  fi

  printf '\n========================================\n'
  printf 'residue gate (dir #663): %d mktemp-minted path(s) traced, %d left behind\n' "$resid_paths" "$resid_left_n"
  # dir #333, review-caught: the NOTE above ran once, near the top, on stderr — easy to miss in a long
  # scrollback or a CI harness that only tails stdout. Repeat it once more, right next to the pass/fail
  # verdict a reader actually looks at, so a checkout missing tools/lib/ref-guard.sh doesn't read as
  # silently equivalent to one with the full canary.
  if [ "$guard_ref_scope_available" != 1 ] && [ -n "$guard_before_head" ]; then
    printf 'NOTE: the refs/heads + reflog half of the corruption canary (dir #333) did not run this\n' >&2
    printf '      time — see the NOTE near the top of this output for why.\n' >&2
  fi
  # delta-audit 0.13.0 S6-1: the same repeat for the engine half (its NOTE ran near the top).
  if [ "$guard_engine_skipped" = 1 ]; then
    printf 'NOTE: the engine half of the corruption canary (dir #653) did not run this time — see the NOTE\n' >&2
    printf '      near the top of this output for why.\n' >&2
  fi
  # delta-audit 0.13.0 R2-2: and for the dir #318 half.
  if [ "$guard_repo_skipped" = 1 ]; then
    printf 'NOTE: the dir #318 half of the corruption canary did not run this time — see the NOTE near\n' >&2
    printf '      the top of this output for why.\n' >&2
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
}

main "$@"; exit $?
