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
# leftover is exactly dir #109's complaint. dir #150: other_mode_hint is ledger-only now (the
# default-leaf probe that used to find a hand-built, manifest-less leftover is gone) — a REAL install
# via install.sh (not the old rails()-only fixture) is what covers this going forward, since install.sh
# always ledger-appends regardless of --home/--global/default (barring --ephemeral). $HOME/.claude was
# fully uninstalled above (nothing left, including its manifest/ledger entry), so this is a clean base.
rails() { sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/templates/CLAUDE.md" > "$1"; }
inst --codex --no-hooks
check_status "codex install at the default leaf succeeds" 0 "$STATUS"
unin --yes
check_contains "a Claude-scope uninstall names the leftover Codex install" "$OUT" "--codex"
check_file "and does not touch it" "$HOME/.codex/AGENTS.md"

# ...and symmetrically: a --codex run must name a leftover CLAUDE.md install. The guard used to
# short-circuit on CODEX=1, so dir #109's silent-leftover fix worked in one direction only — and that
# asymmetry is what let the mis-target below report a clean "done" (operator-run /code-review). Also a
# REAL install now, for the same dir #150 reason as above — the codex install from just above is still
# there, untouched, so this uninstalls IT while hinting about this newly-installed claude leftover.
inst --home "$HOME/.claude" --no-hooks
check_status "claude install at the default leaf succeeds" 0 "$STATUS"
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
check_file "AGENTS.md is kept, not deleted" "$KH/.codex/AGENTS.md"   # else the next check is vacuous
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
check_contains "the refusal names the recorded mode (dir #125: manifest-driven)" "$OUT" "claude mode, not codex"
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

# =================================================================================================
# dir #136: the closing summary names any leftover /polish pre-PR gate hooks, same treatment the
# machine-global secret-guard already gets — no more silently dangling settings.json entries pointing
# at a tools/pre-pr-gate.sh that may no longer exist once the checkout itself is deleted.
# =================================================================================================
if command -v jq >/dev/null 2>&1; then
  gate_installer="$REPO_ROOT/tools/install-pre-pr-gate.sh"

  GH="$SANDBOX/gate-leftover/.claude"
  inst --home "$GH" --no-hooks
  check_status "install for the gate-leftover fixture succeeds" 0 "$STATUS"
  run env KEEL_HOME="$GH" "$gate_installer" --global
  check_status "wiring the gate at this home succeeds" 0 "$STATUS"
  check_file "gate hooks are wired at this home" "$GH/settings.json"

  unin --home "$GH" --yes
  check_status "uninstall over a home with a wired gate exits 0" 0 "$STATUS"
  check_contains "the summary names the leftover gate hooks" "$OUT" "pre-PR gate hooks are still wired"
  check_contains "and points at the tested removal path" "$OUT" "install-pre-pr-gate.sh --uninstall"
  check_file "settings.json itself is left in place (uninstall.sh doesn't touch it)" "$GH/settings.json"
  check_contains "and the hooks are still really there (nothing silently stripped)" "$(cat "$GH/settings.json")" "pre-pr-gate.sh"

  # regression (operator-run /code-review, round 1): the note must fire on EVERY summary exit, not just
  # the "did something else" path — a bare re-run (nothing left of the REST of the install to remove) is
  # exactly the "did it work?" check-in where a user would want to be reminded the gate hooks are still
  # there, and gating the note on `removed > 0` silently dropped it right there.
  unin --home "$GH" --yes
  check_status "second uninstall over the same home exits 0" 0 "$STATUS"
  check_contains "second run still reports nothing (else) to remove" "$OUT" "nothing removed"
  check_contains "and STILL names the leftover gate hooks" "$OUT" "pre-PR gate hooks are still wired"

  GH2="$SANDBOX/gate-leftover-dryrun/.claude"
  inst --home "$GH2" --no-hooks
  run env KEEL_HOME="$GH2" "$gate_installer" --global
  check_status "wiring the gate for the dry-run fixture succeeds" 0 "$STATUS"
  unin --home "$GH2" --dry-run
  check_status "dry-run over a home with a wired gate exits 0" 0 "$STATUS"
  check_contains "a dry-run preview also names the leftover gate hooks" "$OUT" "pre-PR gate hooks are still wired"

  # No gate ever wired at this home → no leftover-hooks note (nothing to report).
  NG="$SANDBOX/no-gate-leftover/.claude"
  inst --home "$NG" --no-hooks
  unin --home "$NG" --yes
  check_status "uninstall over a home with no gate exits 0" 0 "$STATUS"
  check_absent "no leftover-hooks note when nothing was ever wired" "$OUT" "pre-PR gate hooks are still wired"

  # regression (2nd operator-run /code-review pass): an UNRELATED mention of "pre-pr-gate.sh" (e.g. a
  # permissions rule allowlisting it) must NOT trigger the leftover-hooks note — only a real wired
  # PreToolUse/Bash hook should. A bare grep can't tell the two apart; the structural jq check can.
  FP="$SANDBOX/gate-false-positive/.claude"
  inst --home "$FP" --no-hooks
  mkdir -p "$FP"
  cat > "$FP/settings.json" <<EOF
{"permissions":{"allow":["Bash(bash $FP/../keel/tools/pre-pr-gate.sh:*)"]}}
EOF
  unin --home "$FP" --yes
  check_status "uninstall over a settings.json that only MENTIONS pre-pr-gate.sh exits 0" 0 "$STATUS"
  check_absent "no false leftover-hooks note from an unrelated mention (permissions rule, not a hook)" \
    "$OUT" "pre-PR gate hooks are still wired"
else
  pass "jq not available — gate-leftover summary tests skipped (install-pre-pr-gate.sh requires jq)"
fi

# =================================================================================================
# dir #125 PR2 — uninstall consumes the install manifest (acceptance tests B7-B14). install.sh now
# always writes a manifest (PR1), so most fixtures above already exercise the manifest-driven paths
# below implicitly; these tests pin the NEW capabilities directly and by name.
# =================================================================================================

# --- B7: the manifest itself is backed up on removal; the checkout ledger is pruned once no
# install-manifest.* remains; .keel/ is removed only when nothing else lives there [0a1e15b, dir #125] -
B7="$SANDBOX/b7-manifest-backup/.claude"
inst --home "$B7" --no-hooks
check_status "B7 install succeeds" 0 "$STATUS"
b7man="$B7/.keel/install-manifest.claude"
check_file "B7 manifest recorded" "$b7man"
check_contains "B7 home is in the ledger before uninstall" "$(cat "$KEEL_LEDGER_FILE")" "$B7"

unin --home "$B7" --yes
check_status "B7 uninstall exits 0" 0 "$STATUS"
b7backup="$(latest_backup "$B7")"
check_file "B7 manifest moved into the backup dir" "$b7backup/.keel/install-manifest.claude"
check_nofile "B7 manifest gone from its live location" "$b7man"
check_absent "B7 home pruned from the ledger (no manifest left)" "$(cat "$KEEL_LEDGER_FILE" 2>/dev/null)" "$B7"
if [ -e "$B7/.keel" ]; then fail "B7 .keel/ removed (nothing else lived there)" "still present"; else pass "B7 .keel/ removed (nothing else lived there)"; fi

# .keel/ survives uninstall when something else (e.g. a doctor-accept file) still lives there.
B7B="$SANDBOX/b7b-keel-survives/.claude"
inst --home "$B7B" --no-hooks
printf 'W-SOME-FINDING\n' > "$B7B/.keel/doctor-accept"
unin --home "$B7B" --yes
check_status "B7b uninstall exits 0" 0 "$STATUS"
check_dir "B7b .keel/ survives (doctor-accept file still there)" "$B7B/.keel"
check_file "B7b doctor-accept file untouched" "$B7B/.keel/doctor-accept"

# --- B8: dir #124 reproduction — THE headline test -------------------------------------------------
B8="$SANDBOX/b8-dir124/.claude"
inst --home "$B8" --no-hooks
check_status "B8 claude install succeeds" 0 "$STATUS"
run env KEEL_HOME="$B8" "$INSTALL" --codex --no-hooks
check_status "B8 codex install over the SAME home succeeds (dir #124's coherent both-modes shape)" 0 "$STATUS"
b8_claude_man="$B8/.keel/install-manifest.claude"
b8_codex_man="$B8/.keel/install-manifest.codex"
check_file "B8 both manifests coexist (claude)" "$b8_claude_man"
check_file "B8 both manifests coexist (codex)" "$b8_codex_man"

run env KEEL_HOME="$B8" "$UNINSTALL" --codex --yes
check_status "B8 codex uninstall exits 0" 0 "$STATUS"
check_nofile "B8 codex manifest gone" "$b8_codex_man"
if [ -e "$B8/AGENTS.md" ]; then
  check_absent "B8 codex AGENTS.md rails gone" "$(cat "$B8/AGENTS.md")" "KEEL-CORE-BEGIN"
else
  pass "B8 AGENTS.md itself absent (nothing left to keep)"
fi
check_file "B8 shared bin/keel survives (claude install still needs it)" "$B8/bin/keel"
check_link "B8 shared bin/keel is still the real symlink" "$B8/bin/keel"
check_file "B8 shared FRAMEWORK.md survives" "$B8/FRAMEWORK.md"
check_file "B8 shared PRINCIPLES.md survives" "$B8/PRINCIPLES.md"
check_dir "B8 commands/ (claude-only; codex manifest never listed it) survives" "$B8/commands"
check_file "B8 a shipped command survives" "$B8/commands/go.md"
check_file "B8 claude manifest still there" "$b8_claude_man"
check_contains "B8 CLAUDE.md rails intact" "$(cat "$B8/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_contains "B8 summary names bin/keel as shared" "$OUT" "bin/keel is shared with the claude install"
check_contains "B8 summary names FRAMEWORK.md as shared" "$OUT" "FRAMEWORK.md is shared with the claude install"
# other_mode_hint's ledger-loop must exclude THIS run's own (just-touched) home — the shared half is
# already named above via the removal summary; a self-referential hint would confusingly point the
# operator back at the home they're standing in (independent operator-run /code-review high pass).
check_absent "B8 no confusing self-referential hint about its own home" "$OUT" "still in place at $B8 —"

# Symmetric: uninstalling claude FIRST from a fresh both-modes home must equally spare what the
# surviving codex install still needs — not a one-direction fix.
B8R="$SANDBOX/b8-dir124-reverse/.claude"
inst --home "$B8R" --no-hooks
run env KEEL_HOME="$B8R" "$INSTALL" --codex --no-hooks
check_status "B8R codex install succeeds" 0 "$STATUS"
run env KEEL_HOME="$B8R" "$UNINSTALL" --yes
check_status "B8R claude uninstall exits 0" 0 "$STATUS"
check_file "B8R shared bin/keel survives (codex still needs it)" "$B8R/bin/keel"
check_file "B8R shared FRAMEWORK.md survives" "$B8R/FRAMEWORK.md"
check_file "B8R codex manifest still there" "$B8R/.keel/install-manifest.codex"
check_contains "B8R AGENTS.md rails intact" "$(cat "$B8R/AGENTS.md")" "KEEL-CORE-BEGIN"
check_absent "B8R no confusing self-referential hint about its own home" "$OUT" "still in place at $B8R —"

# --- B9: mode/home mismatch — manifest-driven refusal, exit 2, nothing touched, advice quotes the
# recorded home [e399d16] ----------------------------------------------------------------------------
B9="$SANDBOX/b9-mismatch/.claude"
inst --home "$B9" --no-hooks
check_status "B9 install succeeds" 0 "$STATUS"
run env KEEL_HOME="$B9" "$UNINSTALL" --codex --yes
check_status "B9 --codex aimed at a claude-manifested home -> exit 2" 2 "$STATUS"
check_contains "B9 refusal names the recorded mode" "$OUT" "claude mode, not codex"
check_contains "B9 refusal quotes the recorded home" "$OUT" "--home \"$B9\""
check_file "B9 nothing removed — CLI symlink survives" "$B9/bin/keel"
check_file "B9 nothing removed — a shipped command survives" "$B9/commands/go.md"
check_contains "B9 CLAUDE.md rails untouched" "$(cat "$B9/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_file "B9 the manifest itself is untouched" "$B9/.keel/install-manifest.claude"

# --- B9D: dir #234 (operator-decided) — --dry-run over the SAME mismatched home as B9 falls through to
# exit 0 advisory output instead of B9's exit 2 refusal, names the mismatch (not the unrelated
# "no usable manifest" text), and does NOT print the heuristic file listing (it would describe the wrong
# home) --------------------------------------------------------------------------------------------
run env KEEL_HOME="$B9" "$UNINSTALL" --codex --dry-run
check_status "B9D --codex --dry-run aimed at a claude-manifested home -> exit 0" 0 "$STATUS"
check_contains "B9D dry-run names the recorded mode" "$OUT" "claude mode, not codex"
check_contains "B9D dry-run marks itself as a dry run" "$OUT" "dry run — nothing will be changed"
check_contains "B9D dry-run still quotes the recorded home" "$OUT" "--home \"$B9\""
check_absent "B9D dry-run does NOT print the heuristic-listing disclaimer" "$OUT" "heuristic"
check_absent "B9D dry-run does NOT claim any specific file would be removed" "$OUT" "would remove"
check_file "B9D nothing removed — CLI symlink survives" "$B9/bin/keel"
check_file "B9D the manifest itself is untouched" "$B9/.keel/install-manifest.claude"

# --- B10: user-deleted context file on a manifested home — uninstall still works, no two-mode
# deadlock [287642e] ---------------------------------------------------------------------------------
B10="$SANDBOX/b10-no-context/.claude"
inst --home "$B10" --no-hooks
check_status "B10 install succeeds" 0 "$STATUS"
rm -f "$B10/CLAUDE.md"
unin --home "$B10" --yes
check_status "B10 uninstall over a manifested home with no context file at all -> exit 0" 0 "$STATUS"
check_contains "B10 actually removes Keel's content" "$OUT" "item(s) removed"
check_nolink "B10 the CLI symlink is gone" "$B10/bin/keel"

# --- B11: upgrade precision, both directions — an old-release file matching the RECORDED cksum is
# removed even though it no longer matches the CURRENT checkout; a user-edited file mismatching the
# recorded cksum is kept [never-clobber; new capability; replaces cmp-to-current-checkout] ------------
B11="$SANDBOX/b11-upgrade-precision/.claude"
inst --home "$B11" --no-hooks
check_status "B11 install succeeds" 0 "$STATUS"
b11man="$B11/.keel/install-manifest.claude"
# Simulate an OLDER release: FRAMEWORK.md on disk becomes some other content — no longer identical to
# $REPO_ROOT/FRAMEWORK.md (today's checkout) — but the manifest's recorded cksum is rewritten to match
# it, exactly as if install.sh itself had written this content (an earlier release's bytes).
printf 'old-release FRAMEWORK.md content, not this checkout at all\n' > "$B11/FRAMEWORK.md"
read -r b11_sum b11_size _ < <(cksum "$B11/FRAMEWORK.md")
awk -F'\t' -v sum="$b11_sum" -v size="$b11_size" 'BEGIN{OFS="\t"} $1=="artifact=file" && $2=="FRAMEWORK.md" {$3="cksum:"sum":"size} {print}' \
  "$b11man" > "$b11man.testtmp" && mv "$b11man.testtmp" "$b11man"

unin --home "$B11" --yes
check_status "B11 uninstall exits 0" 0 "$STATUS"
if [ -e "$B11/FRAMEWORK.md" ]; then
  fail "B11 old-release file removed (cksum precision)" "still present — cmp-to-checkout would have wrongly kept it"
else
  pass "B11 old-release file removed (cksum precision)"
fi

# Reverse direction: a user-edited file whose bytes now differ from the RECORDED cksum is kept.
B11B="$SANDBOX/b11b-user-edit/.claude"
inst --home "$B11B" --no-hooks
printf '\nmy own edit at the end\n' >> "$B11B/PRINCIPLES.md"
unin --home "$B11B" --yes
check_status "B11b uninstall exits 0" 0 "$STATUS"
check_file "B11b user-edited PRINCIPLES.md kept (cksum mismatch)" "$B11B/PRINCIPLES.md"
check_contains "B11b the edit survives" "$(cat "$B11B/PRINCIPLES.md")" "my own edit at the end"

# --- B11C: dir #323's own test 9 — a `.bak` an install.sh --force run left behind survives uninstall.
# Holds BY CONSTRUCTION, same guarantee B11 above just pinned from the other end: uninstall removes by
# MANIFEST (this file's own header — "one recorded state this script reads instead of re-deriving
# ownership heuristically at every site", dir #125), and install.sh --force never records a backup as a
# manifest artifact (dir #323 Part 2) — so uninstall has no record of the .bak to act on either way. -----
B11C="$SANDBOX/b11c-force-backup-survives/.claude"
inst --home "$B11C" --no-hooks
printf '\nmy own edit\n' >> "$B11C/FRAMEWORK.md"
inst --home "$B11C" --no-hooks --force
b11c_bak="$(ls "$B11C"/FRAMEWORK.md.*.bak 2>/dev/null | head -1)"
check_contains "B11c a --force backup exists before uninstall" "$b11c_bak" ".bak"
check_absent "B11c the backup is not itself a manifest artifact" "$(cat "$B11C/.keel/install-manifest.claude")" ".bak"
unin --home "$B11C" --yes
check_status "B11c uninstall exits 0" 0 "$STATUS"
check_file "B11c the .bak file survives uninstall" "$b11c_bak"

# --- B12: ledger-driven other_mode_hint names an other-mode install at a NON-DEFAULT home
# (impossible under the old $HOME/<leaf>-only probe); a foreign-core other-mode install is still
# named too; and it fires cleanly on the earliest "no such home" exit, with no undefined-function
# fallout on stderr [e3ca502, a87381a] -----------------------------------------------------------
B12H="$SANDBOX/b12-home"
mkdir -p "$B12H/.claude"
B12_ODD="$SANDBOX/b12-somewhere-else/.codex"   # NOT the conventional $HOME/.codex leaf
fresh_home_env "$B12H"; b12_env=("${FRESH_HOME_ENV[@]}")
run env "${b12_env[@]}" "$INSTALL" --no-hooks
check_status "B12 claude install at the conventional home succeeds" 0 "$STATUS"
run "$INSTALL" --codex --home "$B12_ODD" --no-hooks
check_status "B12 codex install at a NON-default home succeeds" 0 "$STATUS"

run env "${b12_env[@]}" "$UNINSTALL" --yes
check_status "B12 claude uninstall exits 0" 0 "$STATUS"
check_contains "B12 names the non-default codex home exactly" "$OUT" "$B12_ODD"
check_absent "B12 no undefined-function fallout" "$OUT" "command not found"

# Foreign-core other-mode install (no rails written, but a manifest IS recorded — dir #125 A3) must
# still be named, same as before this PR.
B12F="$SANDBOX/b12-foreign"
mkdir -p "$B12F/.claude" "$B12F/.codex"
printf '# My own global notes\nnothing keel here\n' > "$B12F/.codex/AGENTS.md"
fresh_home_env "$B12F"; b12f_env=("${FRESH_HOME_ENV[@]}")
run env "${b12f_env[@]}" "$INSTALL" --no-hooks
check_status "B12F claude install succeeds" 0 "$STATUS"
run env "${b12f_env[@]}" "$INSTALL" --codex --no-hooks
check_status "B12F foreign-core codex install succeeds" 0 "$STATUS"
check_absent "B12F it wrote no rails into the kept AGENTS.md" "$(cat "$B12F/.codex/AGENTS.md")" "KEEL-CORE-BEGIN"
run env "${b12f_env[@]}" "$UNINSTALL" --yes
check_status "B12F claude uninstall exits 0" 0 "$STATUS"
check_contains "B12F still names the rails-less (foreign-core) codex install" "$OUT" "$B12F/.codex"

# The SAME hint fires on the earliest exit — "no Keel home at all" — the run a Codex-only adopter
# makes first.
B12N="$SANDBOX/b12-no-such-home"
run "$INSTALL" --codex --home "$SANDBOX/b12-noexist-codex" --no-hooks
check_status "B12N codex install (for the hint to find) succeeds" 0 "$STATUS"
run "$UNINSTALL" --home "$B12N" --yes
check_status "B12N no-such-home -> exit 0" 0 "$STATUS"
check_contains "B12N says nothing to do" "$OUT" "nothing to do"
check_contains "B12N still names the ledger-recorded codex install" "$OUT" "$SANDBOX/b12-noexist-codex"
check_absent "B12N no undefined-function fallout" "$OUT" "command not found"

# --- B13: gate hint quotes the gate manifest's RECORDED settings path, not a re-derived one
# [dir #136] --------------------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  B13="$SANDBOX/b13-gate-hint/.claude"
  inst --home "$B13" --no-hooks
  run env KEEL_HOME="$B13" "$REPO_ROOT/tools/install-pre-pr-gate.sh" --global
  check_status "B13 gate wire succeeds" 0 "$STATUS"
  b13gman="$B13/.keel/install-manifest.gate"
  check_file "B13 gate manifest recorded" "$b13gman"

  # Prove the hint reads settings= from the manifest, not a re-derived $HOME_DIR/settings.json: point
  # the recorded field at a distinguishing (still-real) copy and confirm the printed hint follows it.
  cp "$B13/settings.json" "$B13/settings-recorded.json"
  sed "s|^settings=.*|settings=$B13/settings-recorded.json|" "$b13gman" > "$b13gman.testtmp" && mv "$b13gman.testtmp" "$b13gman"

  unin --home "$B13" --yes
  check_status "B13 uninstall exits 0" 0 "$STATUS"
  check_contains "B13 hint quotes the manifest's RECORDED settings path" "$OUT" "settings-recorded.json"
  check_contains "B13 hint points at the tested removal command" "$OUT" "install-pre-pr-gate.sh --uninstall"
else
  pass "jq not available — B13 gate-hint test skipped (installer requires jq)"
fi

# --- B14: dir #108 regression guard, reconfirmed under a manifested link install — only the real
# token-bounded import line is stripped, a prose mention survives [existing tests stay green] --------
B14="$SANDBOX/b14-import-boundary/.claude"
inst --link --home "$B14" --no-hooks
check_status "B14 link install succeeds" 0 "$STATUS"
b14_prose='Note: the rails arrive via `@~/.claude/keel/CORE.md` — keep this line.'
printf '%s\n' "$b14_prose" >> "$B14/CLAUDE.md"
unin --home "$B14" --yes
check_status "B14 uninstall exits 0" 0 "$STATUS"
b14_txt="$(cat "$B14/CLAUDE.md")"
check_contains "B14 a prose mention of the core path survives" "$b14_txt" "keep this line."
check_absent "B14 the real import line is stripped" "$b14_txt" "@$B14/keel/CORE.md"

# =================================================================================================
# dir #150 (0.7): uninstall no longer removes anything for a mode with no usable manifest — B15/B16
# now pin the REFUSAL, replacing the old B15/B16 that pinned a heuristic removal sweep since retired.
# B17's deterministic gate-settings default path is unaffected (dir #150 kept it — see its own header).
# =================================================================================================

# --- B15: no usable manifest for THIS mode -> refuse with an actionable install.sh fix, remove
# nothing (dir #150; was "the legacy artifact-removal branch... removes real Keel content", now the
# opposite: uninstall requires a manifest and no longer has a heuristic removal path to fall to) -----
B15="$SANDBOX/b15-no-manifest-refusal/.claude"
inst --home "$B15" --no-hooks
check_status "B15 install succeeds" 0 "$STATUS"
rm -f "$B15/.keel/install-manifest.claude"   # simulate a pre-0.7 (manifest-less) home
check_nofile "B15 fixture: no manifest for this mode" "$B15/.keel/install-manifest.claude"

unin --home "$B15" --yes
check_status "B15 uninstall over a manifest-less home refuses -> exit 2" 2 "$STATUS"
check_contains "B15 refusal explains why" "$OUT" "no usable install manifest is recorded"
check_contains "B15 refusal names the fix" "$OUT" "install.sh --home"
check_link "B15 nothing removed — the CLI symlink survives" "$B15/bin/keel"
check_file "B15 nothing removed — a shipped command survives" "$B15/commands/go.md"
check_file "B15 nothing removed — FRAMEWORK.md survives" "$B15/FRAMEWORK.md"
check_file "B15 INSTANCE.md (user data) untouched" "$B15/INSTANCE.md"

# --- B15C: the same refusal under --codex — an independent operator-run /code-review high pass found
# this exact branch (uninstall.sh's `this_mode_flag=" --codex"` line) had zero automated coverage; every
# other no-manifest-refusal test only ever exercised plain mode ---------------------------------------
B15C="$SANDBOX/b15c-no-manifest-refusal-codex/.codex"
inst --codex --home "$B15C" --no-hooks
check_status "B15C codex install succeeds" 0 "$STATUS"
rm -f "$B15C/.keel/install-manifest.codex"   # simulate a pre-0.7 (manifest-less) codex home
check_nofile "B15C fixture: no manifest for this mode" "$B15C/.keel/install-manifest.codex"

unin --codex --home "$B15C" --yes
check_status "B15C codex uninstall over a manifest-less home refuses -> exit 2" 2 "$STATUS"
check_contains "B15C refusal explains why" "$OUT" "no usable install manifest is recorded"
check_contains "B15C refusal names the fix, with --codex" "$OUT" "install.sh --codex --home"
check_link "B15C nothing removed — the CLI symlink survives" "$B15C/bin/keel"
check_file "B15C nothing removed — FRAMEWORK.md survives" "$B15C/FRAMEWORK.md"
check_file "B15C INSTANCE.md (user data) untouched" "$B15C/INSTANCE.md"

# --- B15D: dir #228 (operator-decided) — --dry-run over the SAME manifest-less home as B15 falls
# through to a heuristic advisory listing instead of refusing: a dry run removes nothing, so B15's own
# refusal rationale ("can't guess what to remove") doesn't apply to it. Pins both halves the decision
# calls for: the listing prints, and it is explicitly labeled as heuristic/guessed, not manifest-backed.
# The real (non-dry) refusal (B15 above) is untouched. -------------------------------------------------
B15D="$SANDBOX/b15d-no-manifest-dry-run/.claude"
inst --home "$B15D" --no-hooks
check_status "B15D install succeeds" 0 "$STATUS"
rm -f "$B15D/.keel/install-manifest.claude"   # simulate a pre-0.7 (manifest-less) home
check_nofile "B15D fixture: no manifest for this mode" "$B15D/.keel/install-manifest.claude"

unin --home "$B15D" --dry-run
check_status "B15D dry-run over a manifest-less home falls through -> exit 0" 0 "$STATUS"
check_contains "B15D dry-run labels the listing as heuristic" "$OUT" "heuristic"
check_contains "B15D dry-run lists a would-remove line" "$OUT" "would remove"
check_contains "B15D dry-run states a real run refuses instead of removing (code-review high finding)" "$OUT" "a REAL (non-dry) run in this same state refuses"
check_link "B15D nothing removed — the CLI symlink survives" "$B15D/bin/keel"
check_file "B15D nothing removed — FRAMEWORK.md survives" "$B15D/FRAMEWORK.md"
check_file "B15D INSTANCE.md (user data) untouched" "$B15D/INSTANCE.md"

# --- B15E: dir #233 (found by PR #244's own /code-review high pass) — the SAME manifest-less
# heuristic listing must not read an unrelated user directory literally named `keel` at the home root
# as Keel-owned. Same fixture shape as B15D, but keel/ is replaced with a foreign directory before the
# dry-run: ownership is CORE.md being a symlink (or a KEEL-NOGIT trim), not the keel/ entry's mere
# existence. CLAUDE.md still carries the rails import line, so the heuristic-listing branch is still
# reached the same way B15D reaches it — only the keel/ ownership evidence itself is swapped out. ------
B15E="$SANDBOX/b15e-foreign-keel-dir/.claude"
inst --home "$B15E" --no-hooks
check_status "B15E install succeeds" 0 "$STATUS"
rm -f "$B15E/.keel/install-manifest.claude"   # simulate a pre-0.7 (manifest-less) home
rm -rf "$B15E/keel"
mkdir -p "$B15E/keel"
printf 'my own stuff, not Keel\n' > "$B15E/keel/notes.txt"   # unrelated dir, same name, not Keel-owned

unin --home "$B15E" --dry-run
check_status "B15E dry-run over a manifest-less home falls through -> exit 0" 0 "$STATUS"
check_absent "B15E dry-run does NOT claim the foreign keel/ dir would be removed" "$OUT" "would remove  keel"
check_dir "B15E foreign keel/ dir untouched" "$B15E/keel"
check_file "B15E foreign keel/notes.txt untouched" "$B15E/keel/notes.txt"

# --- B16: the mode/home mismatch refusal for a home where NEITHER mode ever recorded a manifest
# still fires, using the same context-file evidence — built entirely by hand, with install.sh never
# invoked, so no manifest exists anywhere at this home. dir #150 folded this into the general
# this_usable=0 refusal (it no longer needs other_usable=0 too — see uninstall.sh's own comment) -----
B16="$SANDBOX/b16-mismatch-no-manifest/.claude"
mkdir -p "$B16/bin"
ln -s "$REPO_ROOT/keel" "$B16/bin/keel"
printf '# Just a personal AGENTS.md, no install.sh involved\n' > "$B16/AGENTS.md"
run env KEEL_HOME="$B16" "$UNINSTALL" --yes
check_status "B16 mismatch refusal fires -> exit 2" 2 "$STATUS"
check_contains "B16 refusal uses the context-file wording" "$OUT" "no CLAUDE.md — it has AGENTS.md instead"
check_link "B16 nothing removed — the hand-built CLI symlink survives" "$B16/bin/keel"

# --- B17: gate_hooks_hint's default settings.json path still fires when settings.json is genuinely
# wired but no gate manifest was ever recorded (a pre-0.7 gate wire, or one whose manifest was lost) —
# dir #150 kept this one deliberately: unlike the install-manifest fallbacks, there is only ONE
# possible settings path for a global/home-scope gate install, so this was never a multi-candidate
# guess (see uninstall.sh's own gate_hooks_hint comment) ----------------------------------------------
if command -v jq >/dev/null 2>&1; then
  B17="$SANDBOX/b17-gate-hint-no-manifest/.claude"
  inst --home "$B17" --no-hooks
  run env KEEL_HOME="$B17" "$REPO_ROOT/tools/install-pre-pr-gate.sh" --global
  check_status "B17 gate wire succeeds" 0 "$STATUS"
  rm -f "$B17/.keel/install-manifest.gate"
  check_nofile "B17 fixture: no gate manifest recorded" "$B17/.keel/install-manifest.gate"
  check_file "B17 fixture: settings.json really is wired" "$B17/settings.json"

  unin --home "$B17" --yes
  check_status "B17 uninstall exits 0" 0 "$STATUS"
  check_contains "B17 default-path probe still names the wired settings.json" "$OUT" "$B17/settings.json"
  check_contains "B17 default-path probe points at the removal command" "$OUT" "install-pre-pr-gate.sh --uninstall"
else
  pass "jq not available — B17 gate-hint test skipped (installer requires jq)"
fi

# =================================================================================================
# dir #125 PR2 — mixed-generation / staleness coverage (B18-B21), pinning 4 findings from an
# operator-run /code-review high pass on the manifest-consumer diff.
# =================================================================================================

# --- B18: a MIXED-generation both-modes home (one mode installed by an old, pre-dir-125 checkout —
# real content, no manifest — the other by the current one). Uninstalling the MANIFESTED mode (codex,
# here) must neither falsely refuse, nor let its own removal strip content the unmanifested mode still
# needs (the refcount can't see a manifest that was never written). Unaffected by dir #150: this_usable
# is 1 for the mode actually being uninstalled here (its own manifest is present), so it was always on
# the ordinary manifest-driven removal path — artifact_shared_with_other's own conservative fallback
# (unchanged) is what protects the other, unmanifested mode's shared content, not anything dir #150
# touched. Contrast B18B just below, which uninstalls the UNMANIFESTED mode instead. -----------------
B18="$SANDBOX/b18-mixed-gen/.claude"
inst --home "$B18" --no-hooks
run env KEEL_HOME="$B18" "$INSTALL" --codex --no-hooks
check_status "B18 codex install over the same home succeeds" 0 "$STATUS"
rm -f "$B18/.keel/install-manifest.claude"   # simulate a pre-dir-125 claude half: real content, no manifest
check_nofile "B18 fixture: claude manifest absent (simulated pre-dir-125 half)" "$B18/.keel/install-manifest.claude"
check_file "B18 fixture: codex manifest present" "$B18/.keel/install-manifest.codex"
check_contains "B18 fixture: claude content still carries rails" "$(cat "$B18/CLAUDE.md")" "KEEL-CORE-BEGIN"

run env KEEL_HOME="$B18" "$UNINSTALL" --codex --yes
check_status "B18 codex uninstall on a mixed-generation home does not falsely refuse" 0 "$STATUS"
check_absent "B18 no mode-mismatch refusal printed" "$OUT" "recorded manifest is"
check_file "B18 shared bin/keel survives (the un-migrated claude half still needs it)" "$B18/bin/keel"
check_link "B18 shared bin/keel is still the real symlink" "$B18/bin/keel"
check_file "B18 shared FRAMEWORK.md survives" "$B18/FRAMEWORK.md"
check_file "B18 shared PRINCIPLES.md survives" "$B18/PRINCIPLES.md"
check_contains "B18 CLAUDE.md rails (the un-migrated half) still intact" "$(cat "$B18/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_nofile "B18 codex manifest removed" "$B18/.keel/install-manifest.codex"

# The reverse direction: a plain (claude) uninstall on this SAME mixed-generation home — claude is the
# UNMANIFESTED half here. Before dir #150 this fell through to the (now-removed) heuristic sweep and
# succeeded; claude's own rails were independent evidence it was genuinely (if unmanifested) installed,
# "not a mismatch". Post dir #150, uninstall requires a manifest for the mode being uninstalled
# regardless — so this must now get the SAME no-manifest refusal B15 does, specifically NOT the
# cross-mode mismatch refusal (which would incorrectly send the operator to the other mode's uninstall
# even though claude really is installed here too).
B18B="$SANDBOX/b18b-mixed-gen-reverse/.claude"
inst --home "$B18B" --no-hooks
run env KEEL_HOME="$B18B" "$INSTALL" --codex --no-hooks
rm -f "$B18B/.keel/install-manifest.claude"
run env KEEL_HOME="$B18B" "$UNINSTALL" --yes
check_status "B18B a plain (claude) uninstall on a mixed-generation home refuses -> exit 2" 2 "$STATUS"
check_contains "B18B gets the no-manifest refusal" "$OUT" "no usable install manifest is recorded"
check_absent "B18B does NOT print the cross-mode mismatch refusal" "$OUT" "recorded manifest is"
check_file "B18B nothing removed — codex manifest survives" "$B18B/.keel/install-manifest.codex"
check_file "B18B nothing removed — FRAMEWORK.md survives" "$B18B/FRAMEWORK.md"

# --- B19: dir #150 removed other_mode_hint's legacy default-leaf probe — the ledger scan (verified
# against a live, usable manifest) is now the ONLY source. A pre-0.7 other-mode install at the
# conventional default leaf, with no manifest and never ledger-recorded, gets no hint at all; a
# SEPARATE, ledger-recorded other-mode install elsewhere still does. (Was "B19: other_mode_hint is a
# UNION of the ledger scan and the legacy default-leaf probe" — the union is gone along with the probe;
# this now pins that the default-leaf half is silently skipped, not silently double-counted.) ---------
B19H="$SANDBOX/b19-home"
mkdir -p "$B19H/.claude"
fresh_home_env "$B19H"; b19_env=("${FRESH_HOME_ENV[@]}")
run env "${b19_env[@]}" "$INSTALL" --no-hooks
check_status "B19 claude install at the conventional home succeeds" 0 "$STATUS"
mkdir -p "$B19H/.codex"
rails "$B19H/.codex/AGENTS.md"   # a pre-0.7 codex install AT the conventional default leaf: no manifest
run "$INSTALL" --codex --home "$SANDBOX/b19-elsewhere-codex" --no-hooks
check_status "B19 a SEPARATE, ledger-recorded codex install elsewhere succeeds" 0 "$STATUS"

run env "${b19_env[@]}" "$UNINSTALL" --yes
check_status "B19 claude uninstall exits 0" 0 "$STATUS"
check_contains "B19 names the ledger-recorded elsewhere codex install" "$OUT" "$SANDBOX/b19-elsewhere-codex"
check_absent "B19 does NOT name the manifest-less codex install at the default leaf" "$OUT" "$B19H/.codex"

# --- B20: gate_hooks_hint must not trust a stale gate manifest — if the hooks were actually removed
# (or settings.json deleted) without going through install-pre-pr-gate.sh --uninstall, the hint must
# say nothing, not repeat what the manifest alone claims [dir #136] ---------------------------------
if command -v jq >/dev/null 2>&1; then
  B20="$SANDBOX/b20-stale-gate/.claude"
  inst --home "$B20" --no-hooks
  run env KEEL_HOME="$B20" "$REPO_ROOT/tools/install-pre-pr-gate.sh" --global
  check_status "B20 gate wire succeeds" 0 "$STATUS"
  check_file "B20 gate manifest recorded" "$B20/.keel/install-manifest.gate"
  rm -f "$B20/settings.json"   # hooks removed by hand, manifest left behind — now stale
  check_file "B20 fixture: gate manifest still there (stale)" "$B20/.keel/install-manifest.gate"

  unin --home "$B20" --yes
  check_status "B20 uninstall exits 0" 0 "$STATUS"
  check_absent "B20 no false gate hint for hooks that are actually gone" "$OUT" "pre-PR gate hooks are still wired"
else
  pass "jq not available — B20 stale-gate-hint test skipped (installer requires jq)"
fi

# --- B21: a manifest whose version this script doesn't understand is treated as ABSENT for every
# read — and must ALSO be left completely untouched, not backed up/consumed, which would silently
# destroy a newer install's own record. dir #150: "absent" no longer means "fall back to a heuristic
# removal but leave the manifest alone" — there is no heuristic removal path any more, so it means the
# SAME no-manifest refusal as B15 (nothing removed, full stop), which happens to also leave the
# future-version manifest untouched, same as before -------------------------------------------------
B21="$SANDBOX/b21-future-manifest/.claude"
inst --home "$B21" --no-hooks
check_status "B21 install succeeds" 0 "$STATUS"
b21man="$B21/.keel/install-manifest.claude"
awk '{sub(/^keel_manifest_version=1$/, "keel_manifest_version=2")}1' "$b21man" > "$b21man.testtmp" && mv "$b21man.testtmp" "$b21man"
check_contains "B21 fixture: manifest carries an unknown future version" "$(cat "$b21man")" "keel_manifest_version=2"

unin --home "$B21" --yes
check_status "B21 uninstall over a future-version manifest refuses -> exit 2" 2 "$STATUS"
check_contains "B21 gets the no-manifest refusal" "$OUT" "no usable install manifest is recorded"
check_file "B21 the future-version manifest survives, untouched" "$b21man"
check_contains "B21 its content is unchanged" "$(cat "$b21man")" "keel_manifest_version=2"
check_contains "B21 the ledger entry survives (nothing was pruned)" "$(cat "$KEEL_LEDGER_FILE")" "$B21"
check_dir "B21 .keel/ survives (the manifest still lives there)" "$B21/.keel"
check_link "B21 nothing removed — the CLI symlink survives" "$B21/bin/keel"

# --- B22: a mixed-generation home where the UNMANIFESTED half is FOREIGN-CORE. B18/B18B's mixed-
# generation coverage always used a rails-carrying claude half (rails(), not a foreign CLAUDE.md), so
# artifact_shared_with_other's own no-usable-other-manifest fallback — has_keel_rails on the other
# mode's context file — never got exercised against the one case where that signal is always false even
# though the install is completely real (install.sh's foreign_core path never writes a rails marker).
# Found live by an operator-run /code-review max pass on dir #150: `install.sh` over a foreign CLAUDE.md,
# then `install.sh --codex` over the same home, then delete the claude manifest (simulating a
# pre-dir-125 install, or simply a lost/corrupted one). The plain (claude) uninstall correctly refuses
# at the cross-mode mismatch check and advises `uninstall.sh --codex --home ...` — but running that
# EXACT advised command used to strip bin/keel, FRAMEWORK.md and PRINCIPLES.md out from under the
# still-real, unmanifested foreign-core claude half, because the fallback read "no rails" as "not
# shared". Fixed by swapping that fallback to plain existence of the other mode's context file — same
# "did the other mode's install genuinely happen here" question the mismatch-refusal guard above asks,
# not "does this file carry rails". ------------------------------------------------------------------
B22="$SANDBOX/b22-mixed-gen-foreign/.claude"; mkdir -p "$B22"
printf '# My own global notes\nnothing keel here\n' > "$B22/CLAUDE.md"
inst --home "$B22" --no-hooks
check_status "B22 install over a foreign CLAUDE.md succeeds" 0 "$STATUS"
check_absent "B22 fixture: no rails written into the foreign CLAUDE.md" "$(cat "$B22/CLAUDE.md")" "KEEL-CORE-BEGIN"
run env KEEL_HOME="$B22" "$INSTALL" --codex --no-hooks
check_status "B22 codex install over the same home succeeds" 0 "$STATUS"
rm -f "$B22/.keel/install-manifest.claude"   # simulate a lost/pre-dir-125 claude manifest
check_nofile "B22 fixture: claude manifest absent" "$B22/.keel/install-manifest.claude"
check_file "B22 fixture: codex manifest present" "$B22/.keel/install-manifest.codex"

run env KEEL_HOME="$B22" "$UNINSTALL" --yes
check_status "B22 plain uninstall on the mixed foreign-core home refuses -> exit 2" 2 "$STATUS"
check_contains "B22 refusal advises the codex uninstall" "$OUT" "uninstall.sh --codex --home"

run env KEEL_HOME="$B22" "$UNINSTALL" --codex --yes
check_status "B22 following the advised codex uninstall exits 0" 0 "$STATUS"
check_file "B22 shared bin/keel survives (the foreign-core claude half still needs it)" "$B22/bin/keel"
check_link "B22 shared bin/keel is still the real symlink" "$B22/bin/keel"
check_file "B22 shared FRAMEWORK.md survives" "$B22/FRAMEWORK.md"
check_file "B22 shared PRINCIPLES.md survives" "$B22/PRINCIPLES.md"
check_file "B22 shared commands survive" "$B22/commands/go.md"
check_contains "B22 the foreign CLAUDE.md is untouched" "$(cat "$B22/CLAUDE.md")" "My own global notes"
check_nofile "B22 codex manifest removed" "$B22/.keel/install-manifest.codex"
check_contains "B22 the ledger entry survives — the still-live claude install is sentinel-protected (code-review high finding)" "$(cat "$KEEL_LEDGER_FILE")" "$B22"

# assert_shared_half_removed LABEL HOME — the common tail asserted after a dual-mode sequence's SECOND
# uninstall, expected to fully clean up the shared half now that no sibling-mode evidence protects it.
# B23/B25B/B26 below all repeat this identical block; factored here once a fourth copy (B26) made it
# past this project's own "3rd copy" convention (an operator-run /code-review high pass on this same
# branch flagged the fixture-scaffold triplication as its own finding).
assert_shared_half_removed() {
  local label="$1" home="$2"
  check_nofile "$label shared bin/keel finally removed" "$home/bin/keel"
  check_nofile "$label shared FRAMEWORK.md finally removed" "$home/FRAMEWORK.md"
  check_nofile "$label shared PRINCIPLES.md finally removed" "$home/PRINCIPLES.md"
}

# --- B23: dir #190's PRIMARY regression fixture — an ordinary, non-foreign-core both-modes home
# (dir #124, a supported and tested shape), uninstalled in sequence. The first uninstall strips this
# mode's rails from CLAUDE.md (has_keel_rails now false) and consumes ITS OWN manifest, but the context
# file itself survives by design (uninstall never deletes it) — exactly what the old fallback
# (bare `[ -f "$other_context" ]`) misread as "the other mode is still installed here" forever, on the
# SECOND run's normal — not foreign-core — sequence. v0.6.1 completed this cleanly; this pins the same
# outcome against the fix (a manifest-independent foreign-core sentinel, absent here since neither half
# is foreign-core). ------------------------------------------------------------------------------------
B23="$SANDBOX/b23-dir190-regression/.claude"
inst --home "$B23" --no-hooks
check_status "B23 install succeeds" 0 "$STATUS"
run env KEEL_HOME="$B23" "$INSTALL" --codex --no-hooks
check_status "B23 codex install over the same home succeeds" 0 "$STATUS"

unin --home "$B23" --yes
check_status "B23 first (claude) uninstall exits 0" 0 "$STATUS"
check_nofile "B23 claude manifest removed" "$B23/.keel/install-manifest.claude"
check_file "B23 codex manifest still present" "$B23/.keel/install-manifest.codex"
check_file "B23 shared bin/keel survives the first uninstall (codex still needs it)" "$B23/bin/keel"

unin --codex --home "$B23" --yes
check_status "B23 second (codex) uninstall exits 0" 0 "$STATUS"
check_absent "B23 second uninstall no longer misreports a claude sharer" "$OUT" "shared with the claude install"
check_contains "B23 the strip is announced as an unconfirmed guess, not silent (code-review high finding)" "$OUT" "no evidence CLAUDE.md is gone"
# no orphaned shared half:
assert_shared_half_removed B23 "$B23"
check_nofile "B23 codex manifest removed" "$B23/.keel/install-manifest.codex"

# --- B24: dir #190's original scenario — a single real (claude-only) install, with an ordinary,
# unrelated file dropped at the OTHER mode's context-file path (never a real codex install: no
# install.sh --codex ever ran, no foreign-core sentinel exists). Must uninstall cleanly — shared
# artifacts removed, not falsely kept because of the name collision alone. ------------------------------
B24="$SANDBOX/b24-dir190-stray-file/.claude"
inst --home "$B24" --no-hooks
check_status "B24 install succeeds" 0 "$STATUS"
printf '# not a codex install\njust a stray file with the same name\n' > "$B24/AGENTS.md"
check_nofile "B24 fixture: no codex manifest ever recorded" "$B24/.keel/install-manifest.codex"

unin --home "$B24" --yes
check_status "B24 uninstall over a home with a stray AGENTS.md exits 0" 0 "$STATUS"
check_absent "B24 does not falsely report AGENTS.md as a shared codex install" "$OUT" "shared with the codex install"
check_contains "B24 the strip is announced as an unconfirmed guess, not silent (code-review high finding)" "$OUT" "no evidence AGENTS.md is gone"
check_nofile "B24 shared bin/keel correctly removed (no real codex install to protect)" "$B24/bin/keel"
check_nofile "B24 shared FRAMEWORK.md correctly removed" "$B24/FRAMEWORK.md"
check_nofile "B24 shared PRINCIPLES.md correctly removed" "$B24/PRINCIPLES.md"
check_file "B24 the stray AGENTS.md itself is left alone (not Keel's to touch)" "$B24/AGENTS.md"

# --- B25A: the foreign-core sentinel's CLEAR branch (install.sh's `rm -f "$foreign_core_marker"`) —
# never exercised by B22 (which only ever writes the sentinel, once). Install claude over a foreign
# CLAUDE.md (sentinel written), then delete that CLAUDE.md and re-run install.sh fresh: the new run is
# NOT foreign-core (no pre-existing file to collide with), so the sentinel must be cleared. ------------
B25A="$SANDBOX/b25a-sentinel-clear/.claude"; mkdir -p "$B25A"
printf '# My own global notes\nnothing keel here\n' > "$B25A/CLAUDE.md"
inst --home "$B25A" --no-hooks
check_status "B25A install over a foreign CLAUDE.md succeeds" 0 "$STATUS"
check_file "B25A fixture: the foreign-core sentinel was written" "$B25A/.keel/foreign-core.claude"
rm -f "$B25A/CLAUDE.md"
inst --home "$B25A" --no-hooks
check_status "B25A re-install after removing the foreign file succeeds" 0 "$STATUS"
check_contains "B25A fixture: the fresh CLAUDE.md now carries rails" "$(cat "$B25A/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_nofile "B25A the foreign-core sentinel is cleared" "$B25A/.keel/foreign-core.claude"

# --- B25B: BOTH modes foreign-core, uninstalled in sequence — the closest analogue to B23 for the
# sentinel path. Exercises uninstall's own self-take of ITS sentinel (the claude uninstall below takes
# foreign-core.claude) and confirms the SECOND uninstall still cleans up the shared half even though
# both context files were foreign-core, not just one (B22's shape). -------------------------------------
B25B="$SANDBOX/b25b-both-foreign/.claude"; mkdir -p "$B25B"
printf '# My own global notes (claude)\nnothing keel here\n' > "$B25B/CLAUDE.md"
inst --home "$B25B" --no-hooks
check_status "B25B claude install over a foreign CLAUDE.md succeeds" 0 "$STATUS"
printf '# My own global notes (codex)\nnothing keel here\n' > "$B25B/AGENTS.md"
run env KEEL_HOME="$B25B" "$INSTALL" --codex --no-hooks
check_status "B25B codex install over the same home, also foreign, succeeds" 0 "$STATUS"
check_file "B25B fixture: both sentinels written" "$B25B/.keel/foreign-core.claude"
check_file "B25B fixture: both sentinels written (codex)" "$B25B/.keel/foreign-core.codex"

unin --home "$B25B" --yes
check_status "B25B first (claude) uninstall exits 0" 0 "$STATUS"
check_file "B25B shared bin/keel survives the first uninstall (codex still needs it)" "$B25B/bin/keel"
check_nofile "B25B claude's own sentinel is taken by its own uninstall" "$B25B/.keel/foreign-core.claude"
check_file "B25B codex's sentinel is untouched by the claude uninstall" "$B25B/.keel/foreign-core.codex"

unin --codex --home "$B25B" --yes
check_status "B25B second (codex) uninstall exits 0" 0 "$STATUS"
check_absent "B25B second uninstall does not misreport a claude sharer" "$OUT" "shared with the claude install"
assert_shared_half_removed B25B "$B25B"
check_nofile "B25B codex's own sentinel is taken by its own uninstall" "$B25B/.keel/foreign-core.codex"
check_contains "B25B the foreign CLAUDE.md is untouched throughout" "$(cat "$B25B/CLAUDE.md")" "My own global notes (claude)"
check_contains "B25B the foreign AGENTS.md is untouched throughout" "$(cat "$B25B/AGENTS.md")" "My own global notes (codex)"

# --- B26: dir #190's named migration residual, pinned live — an /code-review high pass live-reproduced
# a foreign-core install placed by a PRE-fix checkout (no sentinel ever written) whose manifest is later
# lost: neither rails nor sentinel confirm it, so this fallback still can't tell it apart from B24's
# stray file and strips its shared half — the one structural trade-off this diff's own comments name as
# unclosable without new evidence. What CAN be pinned: the strip is no longer silent (the review's other
# finding, now fixed) — it prints the same unconfirmed-guess warning B23/B24 do, naming the survivor and
# the recovery command, instead of exiting 0 with no trace of the guess it made. ---------------------
B26="$SANDBOX/b26-dir190-residual/.claude"; mkdir -p "$B26"
printf '# My own global notes\nnothing keel here\n' > "$B26/CLAUDE.md"
inst --home "$B26" --no-hooks
check_status "B26 install over a foreign CLAUDE.md succeeds" 0 "$STATUS"
check_file "B26 fixture: the foreign-core sentinel was written" "$B26/.keel/foreign-core.claude"
run env KEEL_HOME="$B26" "$INSTALL" --codex --no-hooks
check_status "B26 codex install over the same home succeeds" 0 "$STATUS"
rm -f "$B26/.keel/install-manifest.claude" "$B26/.keel/foreign-core.claude"   # simulate a pre-dir-190 install
check_nofile "B26 fixture: claude manifest absent" "$B26/.keel/install-manifest.claude"
check_nofile "B26 fixture: no sentinel (simulating a pre-fix install)" "$B26/.keel/foreign-core.claude"

unin --codex --home "$B26" --yes
check_status "B26 the advised codex uninstall exits 0 — the residual is not a new refusal" 0 "$STATUS"
check_contains "B26 the strip is announced as an unconfirmed guess (the residual is disclosed at runtime, not silent)" "$OUT" "no evidence CLAUDE.md is gone"
check_contains "B26 names the exact recovery command" "$OUT" "install.sh --home"
# the known, disclosed residual — not this ticket's fix:
assert_shared_half_removed B26 "$B26"
check_contains "B26 the foreign CLAUDE.md itself is untouched" "$(cat "$B26/CLAUDE.md")" "My own global notes"

# --- B27: dir #362 — a missing/corrupted tools/lib/artifact-cksum.sh must make uninstall REFUSE
# outright (non-zero exit, one actionable stderr line), not degrade like manifest.sh/stat-portable.sh
# do. Unlike those two optional libs, this one is required: uninstall's own removal decision at its
# cksum-comparison call site trusts install.sh's recorded value, so a stub/degraded answer there would
# risk a silent wrong removal choice rather than a merely-slower one. A disposable copy of the checkout
# (never the real $REPO_ROOT) is used so corrupting the lib for this test can't affect any other test
# file — a real install is done first (this checkout's own install.sh, uncorrupted), then the lib is
# corrupted/removed only for the uninstall half.
b27ck="$SANDBOX/force-checkout-uninstall-cksum"
cp -r "$REPO_ROOT" "$b27ck"
rm -rf "$b27ck/.git"
B27="$SANDBOX/b27-corrupt-cksum-lib/.claude"; mkdir -p "$B27"
fresh_home_env "$SANDBOX/b27-corrupt-cksum-lib"
run env "${FRESH_HOME_ENV[@]}" "$b27ck/install.sh" --home "$B27" --no-hooks
check_status "B27 fixture: install succeeds before corruption" 0 "$STATUS"

printf 'this is not valid bash (\n' > "$b27ck/tools/lib/artifact-cksum.sh"
run env "${FRESH_HOME_ENV[@]}" "$b27ck/uninstall.sh" --home "$B27" --yes
check_status "B27 corrupted tools/lib/artifact-cksum.sh → non-zero exit" 1 "$STATUS"
check_contains "B27 one actionable message naming the incomplete checkout" "$OUT" "tools/lib/artifact-cksum.sh is missing or corrupted"
# No separate "not a raw bash parse-error dump" assertion — see tests/test_install.sh's T9c for why:
# uninstall.sh's own `bash -n ... 2>/dev/null` already discards that text at the source, so a runtime
# check for its absence in $OUT would be tautological. check_contains above is the real assertion.
check_file "B27 corrupted-lib refusal removed nothing" "$B27/FRAMEWORK.md"

rm -f "$b27ck/tools/lib/artifact-cksum.sh"
run env "${FRESH_HOME_ENV[@]}" "$b27ck/uninstall.sh" --home "$B27" --yes
check_status "B27 missing tools/lib/artifact-cksum.sh → non-zero exit" 1 "$STATUS"
check_contains "B27 one actionable message naming the incomplete checkout (missing case)" "$OUT" "tools/lib/artifact-cksum.sh is missing or corrupted"
check_file "B27 missing-lib refusal removed nothing" "$B27/FRAMEWORK.md"

# --- B28: dir #347 route 1 — the `artifact=file` arm followed a symlink through `[ -f "$apath" ]` and
# read a cksum through it, so a Keel-placed copy an adopter later moved into their dotfiles and linked
# back (byte-identical content, but the CURRENT FORM disagrees with the RECORDED kind) got swept. This
# is the mirror image of the "manifest recorded a symlink, but it's a regular file now" guard the
# `artifact=symlink` arm already had — that guard now exists on both sides. --------------------------
B28="$SANDBOX/b28-route1-file-becomes-symlink/.claude"
inst --home "$B28" --no-hooks
check_status "B28 install succeeds" 0 "$STATUS"
b28_target="$SANDBOX/b28-dotfiles-framework.md"
cp "$B28/FRAMEWORK.md" "$b28_target"
rm -f "$B28/FRAMEWORK.md"
ln -s "$b28_target" "$B28/FRAMEWORK.md"

unin --home "$B28" --yes
check_status "B28 uninstall exits 0" 0 "$STATUS"
check_link "B28 the re-formed symlink survives (kind disagreement, never swept)" "$B28/FRAMEWORK.md"
check_contains "B28 the disagreement is named" "$OUT" "manifest recorded a file, but it's a symlink now"
check_file "B28 the dotfiles-managed target itself is untouched" "$b28_target"

# --- B29: dir #347 route 2 — the recorded cksum must never be trusted as ownership evidence when it
# equals the unreadable sentinel (tools/lib/artifact-cksum.sh's CKSUM_UNREADABLE, "cksum:0:0"), even if
# the file's CURRENT bytes also happen to be unreadable right now and so also compute to that same
# sentinel. Before this fix, a bare `[ "$(artifact_cksum "$apath")" = "$extra" ]` read that as a match
# and removed a file neither install time nor uninstall time had ever actually read a byte of.
# Root-guarded: a root reader ignores chmod 000 (see CLAUDE.md's own note on this), so the live cksum
# would come back real, not the sentinel, and the scenario this test targets never arises there. -------
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  B29="$SANDBOX/b29-route2-sentinel/.claude"
  inst --home "$B29" --no-hooks
  check_status "B29 install succeeds" 0 "$STATUS"
  b29man="$B29/.keel/install-manifest.claude"
  # Rewrite the recorded cksum for FRAMEWORK.md to the sentinel, as if install.sh itself had recorded
  # it unreadable at placement time.
  awk -F'\t' 'BEGIN{OFS="\t"} $1=="artifact=file" && $2=="FRAMEWORK.md" {$3="cksum:0:0"} {print}' \
    "$b29man" > "$b29man.testtmp" && mv "$b29man.testtmp" "$b29man"
  chmod 000 "$B29/FRAMEWORK.md"
  unin --home "$B29" --yes
  st29="$STATUS"; out29="$OUT"
  chmod 644 "$B29/FRAMEWORK.md"
  check_status "B29 uninstall exits 0" 0 "$st29"
  check_file "B29 the unreadable file survives — self-equal sentinel never authorizes removal" "$B29/FRAMEWORK.md"
  check_contains "B29 named as differing, not silently swept" "$out29" "FRAMEWORK.md differs from what Keel installed"
fi

# --- B30: dir #347 route 3 — a manifest `artifact=symlink` record carries no target of its own
# (record_placed classifies purely by current FORM), so the removal loop's symlink arm had no way to
# tell a genuinely Keel-wired link from one an adopter later re-pointed at their own file. Before this
# fix, `[ -L "$apath" ] && owned=1` accepted ANY symlink at the recorded path, regardless of where it
# led. Same REL, same recorded KIND (symlink) as the real thing, so routes 1/2's kind-agreement checks
# see no disagreement at all here — this is a genuinely different gap. -------------------------------
B30="$SANDBOX/b30-route3-symlink-drift/.claude"
inst --home "$B30" --link --no-hooks
check_status "B30 linked install succeeds" 0 "$STATUS"
check_link "B30 fixture: go.md installed as a symlink" "$B30/commands/go.md"

b30_target="$SANDBOX/b30-not-keels-own.md"
printf "adopter's own script, not Keel's\n" > "$b30_target"
rm -f "$B30/commands/go.md"
ln -s "$b30_target" "$B30/commands/go.md"

unin --home "$B30" --yes
check_status "B30 uninstall exits 0" 0 "$STATUS"
check_link "B30 the re-pointed symlink survives (provenance check fails closed)" "$B30/commands/go.md"
check_contains "B30 it still points at the adopter's own file" "$(readlink "$B30/commands/go.md")" "$b30_target"
check_contains "B30 the drift is named, not silently swept" "$OUT" "symlink no longer points where Keel would have wired it"
check_file "B30 the adopter's own target file is itself untouched" "$b30_target"
# A sibling symlink this run never touched is still correctly identified and removed — the fix narrows
# ownership, it doesn't blanket-refuse every symlink in the manifest.
if [ -e "$B30/bin/keel" ]; then fail "B30 an untouched sibling symlink is still correctly removed" "still present"; else pass "B30 an untouched sibling symlink is still correctly removed"; fi

summary
