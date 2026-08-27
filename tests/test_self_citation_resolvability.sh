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

# --- worktree invocation resolves the MAIN checkout's BACKLOG.md (dir #135's fix, reused) -----------
# BACKLOG.md is gitignored and lives ONLY at the main checkout root — a linked worktree never gets its
# own copy. `git worktree add` only checks out TRACKED content, so BACKLOG.md must never be committed
# in this fixture (unlike `mk_repo`'s other callers, where tracked-vs-untracked doesn't matter) — a
# TRACKED BACKLOG.md would ride along into the worktree via git's own normal checkout, and this test
# would then pass without ever exercising the main-checkout resolution it claims to (found live: an
# earlier version of this fixture used `mk_repo`, which commits BACKLOG.md via `git add -A`, and
# gutting the resolution to a bare `backlog_root="$repo_dir"` still passed against it). $d has
# BACKLOG.md, $wt does not.
d="$(new_repo)"
mkdir -p "$d/docs"
printf '%s' "$doc_ok" > "$d/docs/doc.md"
( cd "$d" && git add -A && git commit -q -m fixture )   # BACKLOG.md deliberately not part of this commit
wt="$SANDBOX/wt266"
( cd "$d" && git worktree add -q -b wt266-branch "$wt" )
printf '%s' "$backlog_ok" > "$d/BACKLOG.md"   # untracked, written after the worktree already exists
check_nofile "the worktree never received the untracked BACKLOG.md" "$wt/BACKLOG.md"
run "$cr" "$wt" --quiet
check_status "a worktree invocation finds the main checkout's untracked BACKLOG.md, not silently skipped" 0 "$STATUS"

# --- a `dir #N` inside a fenced code example is not a real citation ---------------------------------
doc_fenced="# doc

\`\`\`
Cites dir #202 inside a fenced example — not a real citation.
\`\`\`
"
d="$(mk_repo "$backlog_ok" "$doc_fenced")"
run "$cr" "$d" --quiet
check_status "a fenced-code dir #N is not treated as a citation -> exit 0" 0 "$STATUS"

# --- a backtick-quoted `dir #N` in prose is not a real citation -------------------------------------
doc_backtick="# doc

An illustrative example: \`dir #202\` is not a real citation here.
"
d="$(mk_repo "$backlog_ok" "$doc_backtick")"
run "$cr" "$d" --quiet
check_status "a backtick-quoted dir #N is not treated as a citation -> exit 0" 0 "$STATUS"

# --- a slash-separated shorthand citation list is fully extracted, not just its first number --------
# A bare `grep -oE 'dir #[0-9]+'` only matches a fully-spelled reference and silently drops every bare
# `#N` in a shorthand list like "dir #201/#214" — a real shape already shipped in this repo's own
# docs/delegation.md:221, found live by this ticket's own review reproducing the exact bug class
# tools/lib/dir-tickets.sh's `extract_dir_tickets` (promoted from tools/self/doctor.sh, dir #274) was
# hardened against. #214 here is dead; if only #201 were extracted, this would wrongly read as clean.
doc_shorthand="# doc

Cites dir #5/#214 as a slash-separated shorthand list.
"
d="$(mk_repo "$backlog_ok" "$doc_shorthand")"
run "$cr" "$d" --quiet
check_status "the second, shorthand-form number in a slash list is caught as dead -> exit 1" 1 "$STATUS"
check_contains "the shorthand-form number is individually extracted and reported" "$OUT" "DEAD dir #214"

# --- an unreadable (not just absent) BACKLOG.md degrades the same silent way, never a false DEAD -----
# `chmod 000` is a no-op for a root reader (this project's own known CI trap — the alpine-busybox CI
# leg runs as root), so this assertion only means what it says when this test itself is run as a
# non-root user; guarded accordingly, matching the project's own documented pattern for this exact
# trap. Without the `-r` check, `blank_fenced_blocks` failing to open the file inside a `< <(...)`
# process substitution is invisible to `set -e`/`pipefail`, so the script would silently treat the
# file as having zero headings and report DEAD for every citation instead of skipping.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d="$(mk_repo "$backlog_ok" "$doc_ok")"
  chmod 000 "$d/BACKLOG.md"
  run "$cr" "$d" --quiet
  check_status "an unreadable BACKLOG.md degrades to a skip, not a false DEAD -> exit 0" 0 "$STATUS"
  chmod 644 "$d/BACKLOG.md"
fi

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

summary
