#!/usr/bin/env bash
# test_no_pipe_sigpipe_race.sh — dir #280: a static guard against reintroducing the
# `printf "$var" | grep -q/-m/head` SIGPIPE race in any tools/*.sh or tests/*.sh file that runs
# under `pipefail`. Under pipefail, grep's (or head's) own early exit on a match/line-count can
# close the pipe before printf finishes writing, and the resulting SIGPIPE flips a real match into
# a false "not found" — the exact bug dir #280 fixed across ~20 call sites (reproduced live: a
# genuine v0.3.0 release-history heading was reported missing this way). A `<<<` here-string
# (production code) or tests/lib.sh's match() (test files) has no live writer process for the
# early-exiting reader to signal, so neither can race this way; this test keeps the fixed shape
# from silently regressing at a NEW call site. Only files that run under `pipefail` are in scope —
# the identical pipe shape was harmless in tools/pipeline-canary.sh and tools/pre-pr-gate.sh before
# either file set pipefail, and dir #280 fixed those anyway rather than leaving them as a live
# exception here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# The unsafe shape itself: a producer piped straight into a consumer that can exit before
# consuming everything — `grep` with any flag cluster or long option that includes -q/--quiet or
# -m/--max-count (both stop reading on the first qualifying match), or `head` (stops after N
# lines) — rather than draining to EOF. `-[a-zA-Z]*[qm][a-zA-Z]*` (not a fixed `-[qm]`) so a flag
# ORDERING or COMBINATION other than a bare `-q`/`-m` first — `-iq`, `-vq`, `--quiet` — still
# counts (found in review: the fixed `-[qm]` form missed all three, verified live). `grep -c`/`-l`/
# `-v` alone correctly don't match (no q/m in their cluster). Producers beyond printf/echo: this
# ticket's own fixes hit the identical bug with `sed`/`tr` as the producer instead of printf (found
# in review — an earlier draft scoped this to printf/echo only and an injected
# `sed ... | grep -q ...` sailed through undetected). The producer name needs BOTH a leading
# boundary (`^` or a non-identifier char) and trailing whitespace: a bare `(sed|tr)` substring
# match self-collides with ordinary identifiers — `tree_grep` contains `tr`, and `closed`/`used`/
# `based` end in `sed` — found in review by testing the broadened regex against the tree, where it
# flagged `tools/public-audit.sh`'s `tree_grep ... | head -1 || true` as a false "tr" hit.
# `[a-zA-Z0-9_]` (not `\<`/`\>` or `\b`) on purpose: this repo's CI runs busybox grep, which doesn't
# support those GNU/PCRE word-boundary extensions. Known, accepted gaps (a lightweight text scan,
# not a real shell parser): a producer whose OWN arguments contain a literal `|` (e.g.
# `printf "%s|%s" ...`) defeats `[^|]*`'s search for the real pipe; `-l`/`-o -m1` and other
# early-exit shapes beyond `-q`/`-m`/`head` aren't covered. The message text below deliberately
# never spells this shape with a literal producer-pipe-consumer sequence (found in review: an
# earlier draft's own pass/fail strings self-matched this exact regex, which would have made the
# test fail on its own source the moment it became in-scope of its own scan).
QMHEAD_RE='grep (-[a-zA-Z]*[qm][a-zA-Z]*|--quiet|--max-count)'
RACE_RE="(^|[^a-zA-Z0-9_])(printf|echo|sed|tr)[[:space:]][^|]*\\|[[:space:]]*($QMHEAD_RE|head)"

# A file runs under pipefail if it has its own qualifying `set` line, OR — every tests/*.sh and
# tools/lib/*.sh file, regardless of whether it sets `set -` itself — if it's SOURCED rather than
# run directly: every tests/*.sh file sources tests/lib.sh, which sets `set -uo pipefail` for the
# sourcing file too; every tools/lib/*.sh file has no `set` line of its own by design (it inherits
# whatever its caller has set), and every current caller of tools/lib/*.sh sets pipefail except the
# two files (tools/pipeline-canary.sh, tools/pre-pr-gate.sh) dir #280 already fixed defensively —
# so treating both directories as unconditionally in scope is the conservative, correct call
# (found in review — an earlier draft's per-file `set -` line check missed both directions: every
# test file that relies on lib.sh's own `set` line rather than repeating it, which is most of
# them, and every tools/lib/*.sh file, which repeats it in none of them). `set .*pipefail`
# deliberately doesn't care about flag ordering or which other flags (if any) are combined with it
# (an earlier draft also required an `e` flag alongside pipefail, missing this file's own, and
# tools/public-audit.sh's, `set -uo pipefail` form).
runs_under_pipefail() {
  case "$1" in
    "$REPO_ROOT"/tests/*.sh|"$REPO_ROOT"/tools/lib/*.sh) return 0 ;;
  esac
  grep -qE '^set .*pipefail' "$1" 2>/dev/null
}

hits=""
while IFS= read -r -d '' f; do
  runs_under_pipefail "$f" || continue
  while IFS=: read -r n line; do
    [ -n "$n" ] || continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    # Skip comment lines (this file's own explanatory comments name the pattern in prose) — trim
    # leading whitespace, then check the first real character, same idiom tests/lib.sh's own
    # legacy-line trim uses.
    case "$trimmed" in
      '#'*) continue ;;
    esac
    # A `head`-consumer line ending in `|| true` is this codebase's own established idiom for
    # "capture only, exit code discarded, content unaffected by an early consumer close" (e.g.
    # tools/doctor.sh:169, tools/lib/manifest.sh:26: `sed ... | head -n1 || true`) — `head` must
    # actually read a line before it can close, so a real match's captured value survives an early
    # close even though the pipeline's own exit status doesn't, and `|| true` is exactly this
    # codebase's own documented reason for that suffix (see tools/self/doctor.sh's own comment on
    # the identical idiom). Any `grep -q`/`grep -m` variant gets no such exception: their early
    # exit needs no output consumed at all, so the race is real regardless of a trailing `|| true`
    # — and pairing one directly with `|| true` in a boolean test would itself be a broken
    # tautology, not a safe idiom, so a line matching that shape is still worth flagging either
    # way. Reuses $QMHEAD_RE (via match(), not a bare pipe — dir #280) rather than a separate
    # literal substring list, so this stays in sync with whatever RACE_RE's own consumer group
    # considers a q/m-flagged grep (found in review: a hardcoded `grep -q`/`grep -m` substring
    # check here went stale the moment RACE_RE's own consumer alternation was broadened past a
    # bare `-q`/`-m`, silently exempting every other flag form too).
    case "$trimmed" in
      *'|| true')
        match "$trimmed" -qE "$QMHEAD_RE" || continue
        ;;
    esac
    hits="${hits:+$hits }$f:$n"
  done < <(grep -nE "$RACE_RE" "$f" 2>/dev/null)
done < <(find "$REPO_ROOT/tools" "$REPO_ROOT/tests" -name '*.sh' -print0)

if [ -z "$hits" ]; then
  pass "no unsafe pipe-into-grep/head race under pipefail"
else
  fail "no unsafe pipe-into-grep/head race under pipefail" \
    "found (SIGPIPE race, dir #280): $hits"
fi

summary
