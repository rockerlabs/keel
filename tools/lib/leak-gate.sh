# shellcheck shell=bash
# tools/lib/leak-gate.sh — the ONE "run the leak gate, then turn its exit status into a path-only
# BLOCKED report or a scanner-failure report" shape, shared by tools/audit-packet/export.sh and
# tools/vendor-review.sh. Both independently typed out the exact same
# "invoke tools/secret-guard/secret-scan.sh -- FILE... -> on exit 1 (BLOCKED), extract only the leading
# path off each '  path:line:content' hit line via `sed -n 's/^  //p' | cut -d: -f1 | LC_ALL=C sort -u`
# -> on any other nonzero exit, carry the scanner's own stderr" shape — export.sh even had it TWICE
# internally (its own PASS 1 / PASS 2, already promoted to a local run_leak_gate() function per its own
# header, dir #495's code review) before vendor-review.sh made a third file-level copy (dir #614's own
# /polish pass, flagged independently by a "reuse" angle and an "altitude" angle). Sibling of
# tools/lib/gate-paths.sh and tools/lib/leak-patterns.sh — same reason: one definition instead of
# hand-copies kept "in sync" by convention alone, the exact class that already produced a real bug once
# (a from-the-end colon-strip leaked a content fragment; see the FIRST-colon-only comment below).
#
# Deliberately NOT the whole refusal message: each caller's own wording for why the run mattered
# differs on purpose (export.sh: "Nothing was written... re-export"; vendor-review.sh: "Nothing was
# sent... re-run"), and export.sh additionally relabels scratch/packet-internal paths into a form a
# human can still act on once that packet dir is gone (PASS 1: --disclosure-ack/--vendor scratch files;
# PASS 2: paths relative to the packet dir) via its own RELABEL_FN hook below. That's a caller stitches
# around `leak_gate_run`'s own result, not something this file can template without re-coupling the two
# callers' wording to each other.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

# leak_gate_run SCAN_SCRIPT RELABEL_FN FILE...
#
# Runs `SCAN_SCRIPT -- FILE...`, discarding its stdout and capturing its stderr straight into a shell
# variable via command substitution (`2>&1 >/dev/null` inside the `$(...)` — the same idiom
# vendor-review.sh's own pre-extraction code already used, equivalent to a plain `2>` capture since
# stdout is discarded either way). Deliberately never a temp file: a scanner's stderr on a BLOCKED run
# carries the UNREDACTED matched secret/personal-data text (only the leading path is ever extracted
# below), so writing it to disk at all — even briefly, even mode-600 — is exposure this function doesn't
# need to create. An earlier cut of this function DID write it to a `mktemp`'d file, which cost
# vendor-review.sh a scratch file with unredacted secret content that had no cleanup guarantee if the
# process was killed mid-scan (export.sh's own scratch dir at least had its own EXIT trap; vendor-review.sh
# had none) — found by this ticket's own `/code-review high` pass, angle A. Returns SCAN_SCRIPT's own
# exit status verbatim: 0 (clean), 1 (BLOCKED — secret-scan.sh's own convention), or anything else (the
# scanner itself failed to run, not a finding).
#
# On a BLOCKED (1) result, sets LEAK_GATE_HIT_PATHS to the unique, sorted, newline-separated list of
# offending paths. Extracted from the scanner's own "  path:line:content" / "  path:(binary match)"
# detail lines (secret-scan.sh's own emit_stream/emit_blob format) by splitting on the FIRST colon only
# (`cut -d: -f1`) — never a from-the-end strip: the matched content after the line number can itself
# contain colons, and a from-the-end strip (tried first, caught live) left a content fragment behind —
# a fixture line "leaked token: ghp_..." left "path:3:leaked token" in the message, the word before its
# own colon surviving. The matched-content half is never even extracted here, let alone returned.
#
# RELABEL_FN, if non-empty, is called once per raw hit path as `"$RELABEL_FN" "$path"` (its stdout
# captured as the replacement) BEFORE dedup/sort — a caller's hook for turning a scratch-file or
# packet-internal absolute path into a label a human can still act on once that scratch dir or packet
# is gone (export.sh's PASS 1/PASS 2 need this; vendor-review.sh, whose scanned paths are already the
# caller-facing --system/--bundle arguments, passes "" for none).
#
# On any other nonzero result, sets LEAK_GATE_STDERR to the scanner's own stderr text, so the caller can
# report the failure.
leak_gate_run() {
  local scan_script="$1" relabel_fn="$2"
  shift 2
  local status=0 p labeled="" err_text
  # Consumed only by callers that source this file (this shell's own run_leak_gate/leak-gate
  # invocation, read right after leak_gate_run returns) — shellcheck can't see across that boundary,
  # same reason tools/lib/leak-patterns.sh's EMAIL_RE/HOME_RE carry the same disable.
  # shellcheck disable=SC2034
  LEAK_GATE_HIT_PATHS=""
  # shellcheck disable=SC2034
  LEAK_GATE_STDERR=""
  err_text="$("$scan_script" -- "$@" 2>&1 >/dev/null)" || status=$?
  [ "$status" = 0 ] && return 0
  if [ "$status" = 1 ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ -n "$relabel_fn" ]; then
        p="$("$relabel_fn" "$p")"
      fi
      labeled="${labeled}${p}"$'\n'
    done < <(sed -n 's/^  //p' <<< "$err_text" | cut -d: -f1)
    # shellcheck disable=SC2034
    LEAK_GATE_HIT_PATHS="$(printf '%s' "$labeled" | LC_ALL=C sort -u)"
  else
    # shellcheck disable=SC2034
    LEAK_GATE_STDERR="$err_text"
  fi
  return "$status"
}
