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

# The timestamped backup dir uninstall creates under a home, for asserting what it moved there.
latest_backup() { find "$1" -maxdepth 1 -type d -name '.keel-uninstall-*' | sort | tail -1; }

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
backup="$(latest_backup "$H")"
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
# Asserted against the literal import install wrote (@$H4/keel/CORE.md), NOT by re-running the
# production regex here: a test that validates the pattern with the pattern passes just as happily
# when both are wrong. The surviving prose names a different path (~/.claude/...), so a plain
# substring check separates the two.
check_absent "the real import line is still stripped" "$c4" "@$H4/keel/CORE.md"

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
check_nofile "codex FRAMEWORK.md copy removed" "$CX/FRAMEWORK.md"
check_file "codex INSTANCE.md (user data) kept" "$CX/INSTANCE.md"
check_file "AGENTS.md backed up before the edit" "$(latest_backup "$CX")/AGENTS.md"

# --codex is discoverable and its default home is ~/.codex, not ~/.claude
unin --help
check_contains "--help documents --codex" "$OUT" "--codex"

# A plain (Claude) uninstall must at least NAME a Codex install it isn't touching — the silent
# leftover is exactly dir #109's complaint.
rails() { sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/templates/CLAUDE.md" > "$1"; }
mkdir -p "$HOME/.codex"
rails "$HOME/.codex/AGENTS.md"
unin --yes
check_contains "a Claude-scope uninstall names the leftover Codex install" "$OUT" "--codex"
check_file "and does not touch it" "$HOME/.codex/AGENTS.md"

# ...and symmetrically: a --codex run must name a leftover CLAUDE.md install. The guard used to
# short-circuit on CODEX=1, so dir #109's silent-leftover fix worked in one direction only — and that
# asymmetry is what let the mis-target below report a clean "done" (operator-run /code-review).
rails "$HOME/.claude/CLAUDE.md"
unin --codex --yes
check_contains "a --codex uninstall names the leftover Claude install" "$OUT" "$HOME/.claude"
check_contains "and points at the command that removes it" "$OUT" "Remove it too:  uninstall.sh"
# The advised command must carry --home naming that home. A bare `uninstall.sh --codex` re-resolves
# from scratch, and an explicit target outranks the mode leaf — so under KEEL_HOME the advice sent the
# operator BACK to the home they just uninstalled, where it finds nothing, exits 0 and prints no hint
# of its own (its own `other` is now that home), leaving the named install fully wired
# (operator-run /code-review, 4th pass).
check_contains "the advised command names the home it is about" "$OUT" "--home \"$HOME/.claude\""

# The same, reproduced through KEEL_HOME rather than asserted on wording alone: with a Codex install in
# place and KEEL_HOME pointing at the Claude home, the hint's command must actually reach ~/.codex.
KH="$SANDBOX/keel-home-hint"
mkdir -p "$KH/.claude" "$KH/.codex"
fresh_home_env "$KH"; kh_env=("${FRESH_HOME_ENV[@]}")
run env "${kh_env[@]}" "$INSTALL" --no-hooks
run env "${kh_env[@]}" "$INSTALL" --codex --no-hooks
check_file "codex home wired alongside the claude one" "$KH/.codex/AGENTS.md"
run env "${kh_env[@]}" KEEL_HOME="$KH/.claude" "$UNINSTALL" --yes
check_status "uninstall under KEEL_HOME exits 0" 0 "$STATUS"
check_contains "it names the untouched codex home" "$OUT" "$KH/.codex"
# Take the advised command at its word: the --home it prints must remove the codex install for real.
run env "${kh_env[@]}" KEEL_HOME="$KH/.claude" "$UNINSTALL" --codex --home "$KH/.codex" --yes
check_status "the advised command exits 0" 0 "$STATUS"
check_contains "and actually removes it" "$OUT" "item(s) removed"
check_absent "the codex rails are gone" "$(cat "$KH/.codex/AGENTS.md")" "KEEL-CORE-BEGIN"
check_file "and does not touch it" "$HOME/.claude/CLAUDE.md"

# ...and the hint must fire on a FOREIGN-CORE install too, where the kept CLAUDE.md carries no rails
# at all. Keying the hint on rails repeated, here, the exact miss the mismatch refusal below had already
# been re-keyed away from: a Claude home holding bin/keel, commands/ and both product copies went
# unmentioned entirely (operator-run /code-review, 3rd pass). Uses a HOME of its own so the rails
# fixtures written above can't supply the answer.
FH="$SANDBOX/foreign-hint"
mkdir -p "$FH/.claude" "$FH/.codex"
printf '# My own global notes\nnothing keel here\n' > "$FH/.claude/CLAUDE.md"
fresh_home_env "$FH"; fh_env=("${FRESH_HOME_ENV[@]}")
run env "${fh_env[@]}" "$INSTALL" --no-hooks
check_status "foreign-core install into a fresh HOME succeeds" 0 "$STATUS"
check_absent "it wrote no rails into the kept CLAUDE.md" "$(cat "$FH/.claude/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_link "but it did wire the CLI there" "$FH/.claude/bin/keel"
run env "${fh_env[@]}" "$INSTALL" --codex --no-hooks
check_status "codex install into the same HOME succeeds" 0 "$STATUS"
run env "${fh_env[@]}" "$UNINSTALL" --codex --yes
check_status "codex uninstall exits 0" 0 "$STATUS"
check_contains "and names the rails-less Claude install it left behind" "$OUT" "$FH/.claude"
check_link "which is indeed still wired" "$FH/.claude/bin/keel"

# The SAME hint on the no-such-home exit — the earliest one, and the run a Codex-only adopter makes
# first. Covered separately because that exit runs before everything else: a regression that moved the
# helpers back below it would leave the hint calling an undefined function, whose 127 the `||` swallows
# silently (exit stays 0, only a stray "command not found" on stderr), degrading this path back to
# rails-only with the suite still green. Hence the second assertion.
NH="$SANDBOX/no-codex-home"
mkdir -p "$NH/.claude"
printf '# My own global notes\nnothing keel here\n' > "$NH/.claude/CLAUDE.md"
fresh_home_env "$NH"; nh_env=("${FRESH_HOME_ENV[@]}")
run env "${nh_env[@]}" "$INSTALL" --no-hooks
check_status "foreign-core install for the no-such-home case succeeds" 0 "$STATUS"
run env "${nh_env[@]}" "$UNINSTALL" --codex --yes
check_status "--codex with no ~/.codex at all → exit 0" 0 "$STATUS"
check_contains "says there is nothing to do" "$OUT" "nothing to do"
check_contains "and still names the Claude install left behind" "$OUT" "$NH/.claude"
check_absent "with no undefined-function fallout" "$OUT" "command not found"

# --- a mode aimed at the OTHER mode's home: refuse, don't half-dismantle -------------------------
# An explicit target outranks the mode's default leaf (mirroring install.sh), so
# `KEEL_HOME=<claude-home> uninstall.sh --codex` resolves a CLAUDE.md home while looking for AGENTS.md.
# Steps 1-4 are mode-agnostic and would strip the shared half — commands, bin/keel, FRAMEWORK/
# PRINCIPLES — while CLAUDE.md's rails kept loading forever, all reported as success.
MM="$SANDBOX/mismatch/.claude"
inst --home "$MM" --no-hooks
check_status "install for the mode-mismatch case succeeds" 0 "$STATUS"
run env KEEL_HOME="$MM" "$UNINSTALL" --codex --yes
check_status "--codex aimed at a Claude home → exit 2 (refused)" 2 "$STATUS"
check_contains "the refusal names the file it did not find" "$OUT" "no AGENTS.md"
check_contains "the refusal points at the right command" "$OUT" "uninstall.sh --home"
check_file "nothing was removed — the CLI symlink survives" "$MM/bin/keel"
check_file "nothing was removed — a shipped command survives" "$MM/commands/go.md"
check_contains "and CLAUDE.md's rails are still there" "$(cat "$MM/CLAUDE.md")" "KEEL-CORE-BEGIN"
# The signal is "an install ran here", NOT "this file carries Keel's rails". An install over someone's
# own pre-Keel CLAUDE.md leaves that file untouched (install.sh's foreign_core path) while still wiring
# commands, bin/keel and the product copies — so a rails-based guard read a real Keel home as empty and
# let the whole foreign-core case through (operator-run /code-review, 2nd pass).
FC="$SANDBOX/mismatch-foreign/.claude"; mkdir -p "$FC"
printf '# My own global notes\nnothing keel here\n' > "$FC/CLAUDE.md"
inst --home "$FC" --no-hooks
check_status "install over a foreign CLAUDE.md succeeds" 0 "$STATUS"
check_absent "and never writes rails into it" "$(cat "$FC/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_link "but it did wire the CLI" "$FC/bin/keel"
run env KEEL_HOME="$FC" "$UNINSTALL" --codex --yes
check_status "--codex aimed at a foreign-core Claude home → exit 2 (refused)" 2 "$STATUS"
check_contains "the refusal says the home holds an install" "$OUT" "holds a Keel install"
check_link "the CLI symlink survives" "$FC/bin/keel"
check_file "the shipped commands survive" "$FC/commands/go.md"
check_contains "and the user's own CLAUDE.md is untouched" "$(cat "$FC/CLAUDE.md")" "My own global notes"
# ...while a home that is NOT Keel's at all is not refused — it falls through to the honest no-op,
# rather than sending the user round to a --codex run that would also find nothing.
NK="$SANDBOX/not-keel-at-all/.claude"; mkdir -p "$NK"
printf '# just my notes\n' > "$NK/CLAUDE.md"
unin --codex --home "$NK" --yes
check_status "a non-Keel dir holding only your own CLAUDE.md → exit 0, not a refusal" 0 "$STATUS"
check_contains "and says there was nothing of Keel's to remove" "$OUT" "no Keel-owned content"

# ...and a real Keel home holding NEITHER context file must still uninstall. Without the "other mode's
# file is present" condition this deadlocks: each mode refuses and points at the other, so the install
# can never be removed at all. Reachable by deleting your own CLAUDE.md, which is yours to delete.
NC="$SANDBOX/no-context-file/.claude"
inst --home "$NC" --no-hooks
rm -f "$NC/CLAUDE.md"
unin --home "$NC" --yes
check_status "a Keel home with no context file at all → exit 0, not a refusal" 0 "$STATUS"
# "item(s) removed", not a bare "removed": the no-op summary reads "nothing removed.", so the loose
# substring would survive exactly the fall-through-to-no-op regression this asserts against.
check_contains "and actually removes Keel's content" "$OUT" "item(s) removed"
check_nolink "the CLI symlink is gone" "$NC/bin/keel"

# The reverse aim is refused the same way: a plain run pointed at a Codex home.
CM="$SANDBOX/mismatch-codex/.codex"
inst --codex --home "$CM" --no-hooks
unin --home "$CM" --yes
check_status "a plain run aimed at a Codex home → exit 2 (refused)" 2 "$STATUS"
check_contains "the reverse refusal points at --codex" "$OUT" "uninstall.sh --codex --home"
check_file "and the Codex home is untouched" "$CM/AGENTS.md"

summary
