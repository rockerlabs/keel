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
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

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
QMHEAD_RE='grep( +-[^ |]+)* +(-[a-zA-Z]*[qm][a-zA-Z]*|--quiet|--max-count)'
# dir #708 widened the q/m consumer to ANY producer. Measured @0a99412: `| grep -q/-m` after any
# command was 9 hits tree-wide (all fixed), while `| head` after any command was ~97 — nearly all
# `x="$(... | head -1)"` captures whose pipeline status nobody reads, so a SIGPIPE there changes no
# result. grep -q/-m is branched on, which is what makes the race real; `head` stays bounded to the
# fixed producer list above. `(^|[^|])` keeps `|| grep -q ...` (an OR list, not a pipe) out.
# The consumer also takes (e|f)grep as a substring and flag clusters before the q/m one (`grep -F -q`); a flag that
# takes an argument ahead of it (`grep -e pat -q`) stays a known gap, like the others in the header.
ANY_QM_RE="(^|[^|])\\|[[:space:]]*$QMHEAD_RE"
RACE_RE="(^|[^a-zA-Z0-9_])(printf|echo|sed|tr)[[:space:]][^|]*\\|[[:space:]]*($QMHEAD_RE|head)|$ANY_QM_RE"
# The rare safe case (e.g. a producer that is a single fixed short line, proven by the reason):
# a trailing `# sigpipe-ok: <reason>` on the SAME line exempts it. A reason (3+ alphanumerics) is required.
ALLOW_RE='#[[:space:]]*sigpipe-ok:[[:space:]]*[[:alnum:]]{3}'

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

# race_lines FILE — prints "N:line" for each unsafe-shape line of FILE (comments, allow-commented
# lines and the `|| true` head idiom excluded).
race_lines() {
  local n line trimmed
  while IFS=: read -r n line; do
    [ -n "$n" ] || continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    # Skip comment lines (this file's own explanatory comments name the pattern in prose) — trim
    # leading whitespace, then check the first real character, same idiom tests/lib.sh's own
    # legacy-line trim uses.
    case "$trimmed" in
      '#'*) continue ;;
    esac
    match "$trimmed" -qE "$ALLOW_RE" && continue
    # A `head`-consumer line ending in `|| true` is this codebase's own established idiom for
    # "capture only, exit code discarded, content unaffected by an early consumer close" (e.g.
    # tools/lib/manifest.sh's `manifest_field()`: `sed ... | head -n1 || true`) — `head` must
    # actually read a line before it can close, so a real match's captured value survives an early
    # close even though the pipeline's own exit status doesn't. Any `grep -q`/`grep -m` variant
    # gets no such exception: their early exit needs no output consumed at all, so the race is
    # real regardless of a trailing `|| true`. Reuses $QMHEAD_RE (via match(), not a bare pipe —
    # dir #280) so this stays in sync with RACE_RE's own consumer group.
    case "$trimmed" in
      *'|| true')
        match "$trimmed" -qE "$QMHEAD_RE" || continue
        ;;
    esac
    printf '%s:%s\n' "$n" "$trimmed"
  done < <(grep -nE "$RACE_RE" "$1" 2>/dev/null)
}

hits=""
while IFS= read -r -d '' f; do
  runs_under_pipefail "$f" || continue
  while IFS=: read -r n _; do
    [ -n "$n" ] || continue
    hits="${hits:+$hits }$f:$n"
  done < <(race_lines "$f")
done < <(find "$REPO_ROOT/tools" "$REPO_ROOT/tests" -name '*.sh' -print0)

if [ -z "$hits" ]; then
  pass "no unsafe pipe-into-grep/head race under pipefail"
else
  fail "no unsafe pipe-into-grep/head race under pipefail" \
    "found (SIGPIPE race, dir #280): $hits"
fi

# dir #708 fixtures: the guard must flag a shell-function producer (the PR #526 shape) and an awk
# producer, and must stay quiet for an allow-commented line, an OR list and a head capture. Built
# with a $P variable so this file's own source never spells the shape (it is in its own scan scope).
P='|'
fx="$SANDBOX/race-fixture.sh"
{
  echo "func_prod \"\$n\" $P grep -qF -- \"\$needle\""
  echo "awk '{print}' f $P grep -q x"
  echo "git log $P grep -m1 x"
  echo "func_prod $P grep -q x   # sigpipe-ok: one fixed short line"
  echo "false || grep -q x f"
  echo "x=\"\$(func_prod $P head -1)\""
  echo "func_prod $P grep -F -q x || true"
  echo "  $P grep -qE 'x'"
  echo "func_prod $P grep -q x   # sigpipe-ok: x"
} > "$fx"
got="$(race_lines "$fx" | cut -d: -f1 | tr '\n' ' ')"
if [ "$got" = "1 2 3 7 8 9 " ]; then
  pass "guard flags function/awk/git producers; skips allow-comment, OR list, head capture"
else
  fail "guard flags function/awk/git producers; skips allow-comment, OR list, head capture" \
    "flagged lines: '$got' (want '1 2 3 7 8 9 ')"
fi

summary
