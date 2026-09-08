#!/usr/bin/env bash
# tools/self/archive-sweep-check.sh: --help/bad-args, the no-BACKLOG.md skip, the closed-ticket
# line-share threshold (warn above, silent below), the undated-closure count (trap 1's
# datability half), and a mutation-proof pair for the wrapped-heading trap (dir #255/#352) —
# a heading whose closure tag sits on a continuation line must still count as closed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

sc="$REPO_ROOT/tools/self/archive-sweep-check.sh"

# --- --help / bad args -----------------------------------------------------------------------
run "$sc" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$sc" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"

# --- no BACKLOG.md -> silent skip, exit 0 -----------------------------------------------------
run "$sc" "$SANDBOX/no-such-backlog.md"
check_status "missing BACKLOG.md -> exit 0 (skip, not an error)" 0 "$STATUS"
check_contains "prints a skip line" "$OUT" "no readable BACKLOG.md"

# --- fixture builder ----------------------------------------------------------------------------
mk_backlog() {
  local d f
  d="$(mktemp -d "$SANDBOX/bl.XXXXXX")"
  f="$d/BACKLOG.md"
  printf '%s' "$1" > "$f"
  printf '%s' "$f"
}

# A closed ticket with a body long enough to dominate line share, plus one open ticket.
closed_body_lines="$(for i in $(seq 1 80); do echo "line $i"; done)"

backlog_mostly_closed="### dir #1 — a big closed ticket — R2 — ✅ DONE (2026-08-01, done)

$closed_body_lines

### dir #2 — a small open ticket — R2 — → 0.9.0

still open
"

f="$(mk_backlog "$backlog_mostly_closed")"
run "$sc" --threshold 40 "$f"
check_status "well above threshold -> still exit 0 (advisory only)" 0 "$STATUS"
check_contains "WARN fires above threshold" "$OUT" "WARN"
check_contains "reports closed ticket count" "$OUT" "closed tickets:    1"

run "$sc" --threshold 99 "$f"
check_status "below a very high threshold -> exit 0" 0 "$STATUS"
check_absent "no WARN below threshold" "$OUT" "WARN"

# --- undated closure counted separately (trap 1's datability half) -----------------------------
backlog_undated="### dir #3 — closed but no readable date — R2 — ✅ DONE (see PR)

body
"
f="$(mk_backlog "$backlog_undated")"
run "$sc" "$f"
check_status "undated closure -> exit 0" 0 "$STATUS"
check_contains "counts it as an undated closure" "$OUT" "undated closures:  1"

# --- dir #420: a ticket whose OWN tag is undated but whose body cites a different, dated closed
# ticket must still be counted as undated — the sibling's date must not mask this ticket's own
# missing one. MUTATION-PROOF pair: dir #10 (own tag undated, cites a dated sibling) counts
# undated; dir #11 (own tag genuinely dated) does not. -------------------------------------------
backlog_masked_undated="### dir #10 — closed, own tag undated — R2 — ✅ CLOSED, superseded by dir #11 — ✅ CLOSED (2026-08-01, done)

body

### dir #11 — closed with its own real date — R2 — ✅ CLOSED (2026-08-01, done)

body
"
f="$(mk_backlog "$backlog_masked_undated")"
run "$sc" --threshold 1 "$f"
check_contains "MUTATION-PROOF (dir #420): a sibling's date does not mask this ticket's own missing one (undated=1)" \
  "$OUT" "undated closures:  1"

# --- mutation pair: wrapped-heading trap (dir #255) ---------------------------------------------
# A heading whose title text wraps across physical lines and carries its closure tag on a
# CONTINUATION line, not the `### dir #N` line itself — must still be counted as closed.
backlog_wrapped="### dir #9 — a heading whose title runs long enough to wrap across more than one
physical source line before its own closure tag — R2 — ✅ DONE (2026-08-01, done)

body
"
f="$(mk_backlog "$backlog_wrapped")"
run "$sc" --threshold 1 "$f"
check_status "wrapped heading with tag on continuation line -> exit 0" 0 "$STATUS"
check_contains "MUTATION-PROOF: wrapped closure tag still counted closed" "$OUT" "closed tickets:    1"

# Remove the tag entirely (still wrapped, but genuinely open) -> no longer counted closed.
backlog_wrapped_open="### dir #9 — a heading whose title runs long enough to wrap across more than one
physical source line before its own release tag — R2 — → 0.9.0

body
"
f="$(mk_backlog "$backlog_wrapped_open")"
run "$sc" --threshold 1 "$f"
check_contains "an open wrapped heading is not counted closed" "$OUT" "closed tickets:    0"

# --- legacy numbered heading (dir #403's residual shape) is still scanned ----------------------
backlog_legacy="### 6. A legacy numbered ticket — ✅ DONE (2026-08-01, done)

body
"
f="$(mk_backlog "$backlog_legacy")"
run "$sc" --threshold 1 "$f"
check_contains "legacy numbered heading counted closed too" "$OUT" "closed tickets:    1"
