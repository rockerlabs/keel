#!/usr/bin/env bash
# tools/self/citation-resolvability.sh: dead/ambiguous `dir #N` detection against a synthetic
# BACKLOG.md + archive, --help/bad-args, the no-BACKLOG.md skip, and a mutation-proof pair for the
# ambiguity signal (dir #266 subsumes dir #259's duplicate-heading check, so this pair stands in for
# both) — introduce a genuinely ambiguous heading, confirm red; remove it, confirm green.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

cr="$REPO_ROOT/tools/self/citation-resolvability.sh"

# --- --help / bad args -----------------------------------------------------------------------
run "$cr" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$cr" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$cr" /no/such/dir
check_status "missing REPO_DIR -> exit 2" 2 "$STATUS"

# --- no BACKLOG.md -> silent skip, exit 0 -----------------------------------------------------
d="$(new_repo)"
mkdir -p "$d/docs"
printf '# doc\n\nCites dir #7 here.\n' > "$d/docs/doc.md"
( cd "$d" && git add -A && git commit -q -m fixture )
run "$cr" "$d"
check_status "no BACKLOG.md -> exit 0 (skip, not an error)" 0 "$STATUS"
check_contains "prints a SKIP line" "$OUT" "SKIP"

# --- fixture builder: a repo with BACKLOG.md + docs/*.md, git-committed ------------------------
mk_repo() {   # mk_repo BACKLOG_CONTENT DOC_CONTENT
  local d; d="$(new_repo)"
  mkdir -p "$d/docs"
  printf '%s' "$1" > "$d/BACKLOG.md"
  printf '%s' "$2" > "$d/docs/doc.md"
  ( cd "$d" && git add -A && git commit -q -m fixture )
  printf '%s' "$d"
}

backlog_ok="### dir #5 — some ticket — R2 — open
### dir #9 — another ticket — R1 — open
"
doc_ok="# doc

Cites dir #5 and dir #9, both live.
"
d="$(mk_repo "$backlog_ok" "$doc_ok")"
run "$cr" "$d" --quiet
check_status "every citation resolves via a live heading -> exit 0" 0 "$STATUS"

# --- dead citation: no live heading, no archive -------------------------------------------------
doc_dead="# doc

Cites dir #202, which nothing defines.
"
d="$(mk_repo "$backlog_ok" "$doc_dead")"
run "$cr" "$d" --quiet
check_status "citation with no heading and no archive -> exit 1" 1 "$STATUS"
check_contains "reports it DEAD" "$OUT" "DEAD dir #202"

# --- the dir #202 shape: absent from BACKLOG.md, present in the archive -> resolved, not dead ---
archive_dir="$(mktemp -d)"
archive_file="$archive_dir/CLAUDE-archive.md"
printf -- '- 2026-08-21 dir #202 CLOSED — moved out of the live backlog\n' > "$archive_file"
d="$(mk_repo "$backlog_ok" "$doc_dead")"
KEEL_CITATION_ARCHIVE_FILE="$archive_file" run "$cr" "$d" --quiet
check_status "archived (not live) ticket resolves via the archive -> exit 0" 0 "$STATUS"
check_absent "no DEAD line once the archive covers it" "$OUT" "DEAD"
rm -rf "$archive_dir"

# --- mutation pair: duplicate heading makes a previously-clean citation ambiguous ---------------
d="$(mk_repo "$backlog_ok" "$doc_ok")"
run "$cr" "$d" --quiet
check_status "baseline: two distinct live headings, no ambiguity -> exit 0" 0 "$STATUS"

backlog_dup="### dir #5 — some ticket — R2 — open
### dir #9 — another ticket — R1 — open
### dir #5 — a SECOND ticket claiming the same number — R1 — open
"
d2="$(mk_repo "$backlog_dup" "$doc_ok")"
run "$cr" "$d2" --quiet
check_status "MUTATION: a duplicate ### dir #5 heading -> exit 1 (red)" 1 "$STATUS"
check_contains "reports it AMBIGUOUS" "$OUT" "AMBIGUOUS dir #5"

# Remove the mutation (back to the single-heading fixture) -> green again.
run "$cr" "$d" --quiet
check_status "removing the duplicate heading -> exit 0 (green again)" 0 "$STATUS"

# --- smoke test: the real keel checkout runs without crashing -------------------------------------
# Not asserting exit 0 here: HOME is sandboxed (tests/lib.sh), so the real, personal
# ~/.claude/projects/.../CLAUDE-archive.md is invisible to this run regardless of REPO_DIR, and a
# ticket genuinely moved to the archive would read as DEAD under that sandboxing — a fact about test
# isolation, not about the script. Only rule out the "unknown flag" exit 2 (a real crash/misuse).
run "$cr" "$REPO_ROOT"
case "$STATUS" in
  0|1) pass "the real keel checkout runs to completion (exit $STATUS)" ;;
  *) fail "the real keel checkout runs to completion" "unexpected exit $STATUS" ;;
esac
