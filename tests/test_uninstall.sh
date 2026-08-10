#!/usr/bin/env bash
# uninstall.sh — the mirror image of install.sh. These tests do a REAL install into the sandbox home,
# then assert uninstall returns it to pre-install state: Keel-owned content gone and backed up, the
# user's own files (INSTANCE.md, a command they authored) untouched, and the whole thing idempotent.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# Defensive: install.sh / uninstall.sh may run git against this checkout; the alpine CI leg mounts the
# repo under a different uid, so without this git aborts with "dubious ownership" (see CLAUDE.md).
git config --global --add safe.directory '*'

INSTALL="$REPO_ROOT/install.sh"
UNINSTALL="$REPO_ROOT/uninstall.sh"
H="$HOME/.claude"                       # install's default home under the sandbox HOME (from lib.sh)

# Thin names over lib.sh's run() — which since dir #85 redirects stdin from /dev/null for every test
# file, so neither script blocks on a prompt when the suite runs in a terminal. These used to hand-roll
# that redirect (and run()'s whole capture body) here; they now inherit it.
inst()  { run "$INSTALL"   "$@"; }
unin()  { run "$UNINSTALL" "$@"; }

# =================================================================================================
# Linked mode
# =================================================================================================
inst --link --no-hooks
check_status "install --link succeeds" 0 "$STATUS"
check_dir  "install wired keel/"        "$H/keel"
check_link "install wired bin/keel"     "$H/bin/keel"
check_contains "CLAUDE.md imports the core" "$(cat "$H/CLAUDE.md")" "keel/CORE.md"

# A file the USER owns (a command they wrote) must survive uninstall — refuse-to-clobber in reverse.
printf 'my own tool, not Keel\n' > "$H/commands/mytool.md"

# --- dry-run changes nothing --------------------------------------------------------------------
unin --dry-run
check_status "dry-run exits 0" 0 "$STATUS"
check_contains "dry-run says would remove" "$OUT" "would remove  keel"
check_dir "dry-run left keel/ in place" "$H/keel"
check_link "dry-run left bin/keel in place" "$H/bin/keel"
check_nofile "dry-run created no backup" "$H/.keel-uninstall-nonexistent"

# --- refuse when not a terminal and no --yes ----------------------------------------------------
unin
check_status "refuses without --yes when non-interactive" 2 "$STATUS"
check_contains "refusal explains --yes" "$OUT" "pass --yes"
check_dir "refusal changed nothing" "$H/keel"

# --- real uninstall -----------------------------------------------------------------------------
unin --yes
check_status "uninstall --yes exits 0" 0 "$STATUS"
check_dir  "keel/ removed"        "$H"          # sanity: home itself stays
if [ -e "$H/keel" ]; then fail "linked keel/ dir removed" "still present"; else pass "linked keel/ dir removed"; fi
check_nolink "bin/keel symlink removed" "$H/bin/keel"
if [ -e "$H/bin" ]; then fail "empty bin/ pruned" "bin/ still present"; else pass "empty bin/ pruned"; fi
check_absent "import line stripped from CLAUDE.md" "$(cat "$H/CLAUDE.md")" "keel/CORE.md"
check_file "user's own command kept" "$H/commands/mytool.md"
check_file "INSTANCE.md (user data) kept" "$H/INSTANCE.md"
check_file "LEARNINGS.md (user data) kept" "$H/LEARNINGS.md"

# a Keel command is gone, and its backup exists
if [ -e "$H/commands/go.md" ]; then fail "Keel command go.md removed" "still present"; else pass "Keel command go.md removed"; fi
backup="$(find "$H" -maxdepth 1 -type d -name '.keel-uninstall-*' | head -1)"
check_dir "a backup dir was created" "$backup"
check_file "keel command backed up" "$backup/commands/go.md"
check_file "CLAUDE.md backed up before edit" "$backup/CLAUDE.md"
# regression (dir #68 code-review): polish.md ships like every other command now — uninstall must not
# leave it behind as an orphan (it used to carry its own skip-list arm from when install.sh skipped it).
if [ -e "$H/commands/polish.md" ]; then fail "polish.md removed too, not orphaned" "still present"; else pass "polish.md removed too, not orphaned"; fi
check_file "polish.md backed up like any other shipped command" "$backup/commands/polish.md"

# --- idempotent: a second run finds nothing -----------------------------------------------------
unin --yes
check_status "second uninstall exits 0" 0 "$STATUS"
check_contains "second run reports nothing to remove" "$OUT" "no Keel-owned content"

# =================================================================================================
# Copy mode — a drifted (user-edited) FRAMEWORK copy is kept, an untouched one is removed
# =================================================================================================
H2="$SANDBOX/home2/.claude"
inst --home "$H2" --no-hooks
check_status "copy-mode install succeeds" 0 "$STATUS"
check_file "copy-mode placed FRAMEWORK.md" "$H2/FRAMEWORK.md"
check_file "copy-mode placed PRINCIPLES.md" "$H2/PRINCIPLES.md"

# Drift PRINCIPLES.md so it reads as the user's; leave FRAMEWORK.md pristine.
printf '\nmy own edit\n' >> "$H2/PRINCIPLES.md"

unin --home "$H2" --yes
check_status "copy-mode uninstall exits 0" 0 "$STATUS"
if [ -e "$H2/FRAMEWORK.md" ]; then fail "untouched FRAMEWORK copy removed" "still present"; else pass "untouched FRAMEWORK copy removed"; fi
check_file "drifted PRINCIPLES copy kept (yours)" "$H2/PRINCIPLES.md"
check_file "copy-mode INSTANCE.md kept" "$H2/INSTANCE.md"

# =================================================================================================
# dir #85 (code audit, finding 24): uninstall.sh's own usage + no-Keel-home paths
# =================================================================================================
# None of -h/--help, the unknown-argument exit-2 arm, or the very first branch (no $HOME_DIR at all)
# were covered anywhere — including the one branch that decides whether the script does ANYTHING.
unin --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help names the script" "$OUT" "uninstall"
check_contains "--help lists --dry-run" "$OUT" "--dry-run"
unin -h
check_status "-h → exit 0" 0 "$STATUS"

unin --not-a-real-flag
check_status "unknown argument → exit 2" 2 "$STATUS"
check_contains "unknown argument names the offending flag" "$OUT" "--not-a-real-flag"
check_contains "unknown argument points at --help" "$OUT" "--help"

# no Keel home at all → a clean, explicit no-op (exit 0), never an error and never a partial removal
absent="$SANDBOX/no-keel-home-here"
unin --home "$absent" --yes
check_status "no Keel home → exit 0 (nothing to do)" 0 "$STATUS"
check_contains "no Keel home says so explicitly" "$OUT" "nothing to do"
check_contains "no Keel home names the path it looked at" "$OUT" "$absent"
if [ -e "$absent" ]; then fail "no Keel home creates nothing" "path was created: $absent"; else pass "no Keel home creates nothing"; fi

# =================================================================================================
# dir #108: what counts as a real core @import must be the SAME definition install.sh uses
# =================================================================================================
# install.sh's has_core_import requires whitespace/start/end boundaries around the token; uninstall
# used to match by bare substring, so a line that merely MENTIONS the path in prose — the classic
# markdown backtick-quoted `@~/.claude/keel/CORE.md` — was deleted along with the real import line,
# contradicting uninstall's own promise that the rest of your file is untouched.
H4="$SANDBOX/home4/.claude"
inst --link --home "$H4" --no-hooks
check_status "link install for the import-boundary case succeeds" 0 "$STATUS"
prose='Note: the rails arrive via `@~/.claude/keel/CORE.md` — keep this line.'
printf '%s\n' "$prose" >> "$H4/CLAUDE.md"

unin --home "$H4" --yes
check_status "uninstall over the prose mention exits 0" 0 "$STATUS"
c4="$(cat "$H4/CLAUDE.md")"
check_contains "a prose mention of the core path survives (not an import)" "$c4" "keep this line."
# The REAL import line is still gone — the boundary fix must not turn into "never strip anything".
n_import="$(grep -cE '(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)' "$H4/CLAUDE.md" || true)"
check_status "the real import line is still stripped" 0 "$n_import"

# =================================================================================================
# dir #109: --codex / AGENTS.md — install.sh --codex has a mirror image
# =================================================================================================
CX="$SANDBOX/codex-home/.codex"
inst --codex --home "$CX" --no-hooks
check_status "codex install succeeds" 0 "$STATUS"
check_file "codex install placed AGENTS.md" "$CX/AGENTS.md"
check_file "codex install placed FRAMEWORK.md" "$CX/FRAMEWORK.md"
printf 'MY-OWN-CODEX-NOTE\n' >> "$CX/AGENTS.md"

unin --codex --home "$CX" --dry-run
check_status "codex dry-run exits 0" 0 "$STATUS"
check_contains "codex dry-run names AGENTS.md, not CLAUDE.md" "$OUT" "AGENTS.md"

unin --codex --home "$CX" --yes
check_status "codex uninstall exits 0" 0 "$STATUS"
check_file "AGENTS.md itself is kept (user-owned outside the block)" "$CX/AGENTS.md"
cx_txt="$(cat "$CX/AGENTS.md")"
check_absent "the KEEL-CORE rails block is stripped from AGENTS.md" "$cx_txt" "KEEL-CORE-BEGIN"
check_contains "the user's own note outside the block survives" "$cx_txt" "MY-OWN-CODEX-NOTE"
if [ -e "$CX/FRAMEWORK.md" ]; then fail "codex FRAMEWORK.md copy removed" "still present"; else pass "codex FRAMEWORK.md copy removed"; fi
check_file "codex INSTANCE.md (user data) kept" "$CX/INSTANCE.md"
cxbak="$(find "$CX" -maxdepth 1 -type d -name '.keel-uninstall-*' | head -1)"
check_file "AGENTS.md backed up before the edit" "$cxbak/AGENTS.md"

# --codex is discoverable and its default home is ~/.codex, not ~/.claude
unin --help
check_contains "--help documents --codex" "$OUT" "--codex"

# A plain (Claude) uninstall must at least NAME a Codex install it isn't touching — the silent
# leftover is exactly dir #109's complaint.
mkdir -p "$HOME/.codex"
sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/templates/CLAUDE.md" > "$HOME/.codex/AGENTS.md"
unin --yes
check_contains "a Claude-scope uninstall names the leftover Codex install" "$OUT" "--codex"
check_file "and does not touch it" "$HOME/.codex/AGENTS.md"

summary
