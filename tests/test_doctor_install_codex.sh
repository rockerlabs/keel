#!/usr/bin/env bash
# doctor.sh --install --codex (dir #134) — the install-mode audit learns the codex mode the way
# uninstall.sh learned it in dir #109: an explicit --codex flag (never auto-detected — a home holding
# BOTH context files is exactly dir #124's ambiguous shape), a healthy codex install reports OK with no
# false G-RAILS-MISSING, the commands-wired check doesn't nag about a wiring codex never does by design,
# and a mode/home mismatch redirects to the RIGHT re-run instead of advising `install.sh` in a way that
# would create a second mode in the same home.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# --- --codex is discoverable and rejected outside --install -----------------------------------------
run "$doctor" --help
check_contains "--help documents --codex under --install" "$OUT" "--codex"
run "$doctor" --codex
check_status "--codex without --install -> exit 2 (rejected)" 2 "$STATUS"
check_contains "the rejection explains --codex needs --install" "$OUT" "--install"

# --- (a) a healthy --codex install -> exit 0, no false G-RAILS-MISSING ------------------------------
cxhome="$SANDBOX/codex-healthy/.codex"
run "$install" --codex --home "$cxhome" --no-hooks
check_status "codex install for the healthy-audit fixture -> exit 0" 0 "$STATUS"

run "$doctor" --install --codex "$cxhome"
check_status "doctor --install --codex on a healthy codex install -> exit 0" 0 "$STATUS"
check_absent "no G-RAILS-MISSING on a healthy codex install" "$OUT" "G-RAILS-MISSING"
check_contains "rails are recognized (embedded copy, same as Claude copy mode)" "$OUT" "core rails"

# --- (b) commands are never wired under --codex by design -> not reported as missing ----------------
check_absent "no W-CMDS-MISSING nag under --codex (commands/ is a Claude-only mechanism)" "$OUT" "W-CMDS-MISSING"
check_contains "commands check says why, instead of just going silent" "$OUT" "codex"

# --- (c) without --codex, the SAME healthy codex install reports the OLD false gap ------------------
# This is the regression guard: prove the bug this ticket closes actually existed, so a future revert
# is caught here rather than only by the positive case above.
run "$doctor" --install "$cxhome"
check_status "doctor --install (no --codex) on a codex-only home -> exit 1 (GAP)" 1 "$STATUS"
check_contains "still names the finding" "$OUT" "G-RAILS-MISSING"

# --- (d) mode/home mismatch: doctor --install (no --codex) at a codex-only home must NOT advise the
# plain `install.sh` re-run — following that advice would create dir #124's both-modes-in-one-home.
# It must instead redirect to the correctly-moded re-run.
check_contains "the mismatch redirects to --codex" "$OUT" "doctor.sh --install --codex --home \"$cxhome\""
# (a check_absent for the plain "run install.sh --home ..." form was dropped here — with the
# cautionary clause NAMING that exact command as the thing NOT to run, the substring appears in the
# CORRECT message too, making a naive check_absent either vacuous or a false failure; the positive
# check_contains above already pins the redirect's own command exactly. Case (h) below is the real
# regression guard for a wrong/missing --home on the redirect specifically — found by fresh independent
# review to be the only one of the three that actually exercises the true-default-leaf-coincidence path.)
# Every other check is written for the WRONG mode and would otherwise cascade its own dangerous advice
# on top (found live: W-CMDS-MISSING's "re-run install.sh$ihome_flag" is exactly as dangerous, and only
# a hard stop right after the redirect keeps it from firing) — so the audit stops at the one finding.
check_absent "the audit stops there — no cascading wrong-mode findings" "$OUT" "W-CMDS-MISSING"

# --- (e) the reverse mismatch: --codex pointed at a Claude-only home ---------------------------------
clhome="$SANDBOX/claude-healthy/.claude"
run "$install" --home "$clhome" --no-hooks
check_status "claude install for the reverse-mismatch fixture -> exit 0" 0 "$STATUS"
run "$doctor" --install --codex "$clhome"
check_status "doctor --install --codex at a Claude-only home -> exit 1 (GAP)" 1 "$STATUS"
check_contains "the reverse mismatch redirects to dropping --codex" "$OUT" "doctor.sh --install --home \"$clhome\""
# (same reasoning as case (d) above for why no check_absent is added here.)

# --- (f) default home leaf: bare --codex with no positional arg resolves ~/.codex, not ~/.claude -----
cxdefault="$SANDBOX/codex-default-home"; mkdir -p "$cxdefault"
fresh_home_env "$cxdefault"; cxd_env=("${FRESH_HOME_ENV[@]}")
run env "${cxd_env[@]}" "$install" --codex --no-hooks
check_status "default-home codex install -> exit 0" 0 "$STATUS"
run env "${cxd_env[@]}" "$doctor" --install --codex
check_status "doctor --install --codex at the default codex home -> exit 0" 0 "$STATUS"
check_absent "no false G-RAILS-MISSING at the default codex home" "$OUT" "G-RAILS-MISSING"

# ...and a bare `doctor --install` (no --codex) at a machine with ONLY a codex install correctly finds
# nothing at the (separate, never-created) ~/.claude default — a distinct home dir, not a mismatch
# inside the SAME home, so the plain "run install.sh" advice is legitimate here, not dangerous.
run env "${cxd_env[@]}" "$doctor" --install
check_status "doctor --install (no --codex) finds no ~/.claude -> exit 1" 1 "$STATUS"
check_contains "correctly reports no install at the Claude default, not a false OK" "$OUT" "G-INSTALL-MISSING"

# --- (g) regression (operator-run /code-review, round 1): a dangling bin/keel under --codex must NOT
# advise `install.sh --link` — bin/keel is symlinked in BOTH modes (install.sh's own doc comment), so
# this IS reachable under --codex, and --codex + --link is a hard usage error install.sh itself rejects.
# Following the old advice would wire a full second, Claude-mode install (CLAUDE.md, keel/, commands/)
# into the same codex home — exactly dir #124's shape, from the ONE finding this whole ticket exists to
# make safe.
dlhome="$SANDBOX/codex-dangling-link"
run "$install" --codex --home "$dlhome" --no-hooks
check_status "codex install for the dangling-link fixture -> exit 0" 0 "$STATUS"
rm -f "$dlhome/bin/keel"
ln -s "$SANDBOX/nonexistent-checkout/keel" "$dlhome/bin/keel"
run "$doctor" --install --codex "$dlhome"
check_status "doctor --install --codex over a dangling bin/keel -> exit 1 (GAP)" 1 "$STATUS"
check_contains "names the dangling symlink" "$OUT" "G-LINK-DANGLING"
check_contains "the fix advises a bare --codex re-run" "$OUT" "install.sh --codex --home \"$dlhome\""
check_absent "and never advises --link, which --codex can't combine with" "$OUT" "install.sh --link"

# --- (h) regression (operator-run /code-review, step 5 of /polish): the mismatch redirect's advised
# --home flag must be computed against the OTHER mode's default, not this mode's — a Claude-mode install
# placed (via an explicit --home, forgetting --codex) at exactly the .codex DEFAULT leaf makes THIS
# mode's own ihome_flag come out empty (ihome == idefault for --codex), but the redirect recommends
# DROPPING --codex, and a bare `doctor.sh --install` (no --codex, no --home) resolves to ~/.claude, not
# ~/.codex — so the un-suffixed advice would point at the wrong, unrelated (likely empty) directory.
mismatch_home="$SANDBOX/mode-coincidence-home"
mkdir -p "$mismatch_home"
fresh_home_env "$mismatch_home"; mc_env=("${FRESH_HOME_ENV[@]}")
run env "${mc_env[@]}" "$install" --home "$mismatch_home/.codex" --no-hooks
check_status "Claude-mode install placed at the .codex default leaf -> exit 0" 0 "$STATUS"
run env "${mc_env[@]}" "$doctor" --install --codex
check_status "doctor --install --codex (bare) finds the Claude install sitting at ~/.codex -> exit 1" 1 "$STATUS"
check_contains "the redirect carries --home naming the actual home" "$OUT" "doctor.sh --install --home \"$mismatch_home/.codex\""
check_absent "not the bare, home-less form that would land at the wrong (unrelated) ~/.claude" \
  "$OUT" "doctor.sh --install (running"

# --- (i) regression (2nd independent /code-review pass): the always-on-rails branch that fires when
# the context file carries a real @import line still hardcoded "CLAUDE.md" and "install.sh --link" in
# 4 sibling messages (G-RAILS-IMPORT-BROKEN and 3 --no-git-trim WARNs) — unlike the neighboring branch
# already fixed for --codex. Unreachable via a NORMAL install.sh --codex run (copy mode never writes an
# @import line), but reachable if AGENTS.md is hand-edited to include one — the check keys on file
# CONTENT, not provenance. Following the old advice would recommend `install.sh --link` under --codex,
# a hard usage error, or drop --codex entirely and recreate dir #124's shape.
irhome="$SANDBOX/codex-import-broken/.codex"
run "$install" --codex --home "$irhome" --no-hooks
check_status "codex install for the import-broken fixture -> exit 0" 0 "$STATUS"
printf '\n@%s/keel/CORE.md\n' "$irhome" >> "$irhome/AGENTS.md"
run "$doctor" --install --codex "$irhome"
check_status "doctor --install --codex over a hand-added (broken) import line -> exit 1 (GAP)" 1 "$STATUS"
check_contains "names the finding" "$OUT" "G-RAILS-IMPORT-BROKEN"
check_contains "names AGENTS.md, not CLAUDE.md" "$OUT" "AGENTS.md imports keel/CORE.md"
check_contains "advises a bare --codex re-run" "$OUT" "install.sh --codex --home \"$irhome\""
check_absent "never advises --link, which --codex can't combine with" "$OUT" "install.sh --link"

# --- (j) regression (2nd independent /code-review pass): a dangling symlink at a slot install.sh
# --codex never wires at all (commands/*, keel/*, top-level FRAMEWORK/PRINCIPLES) — reachable only as a
# leftover from an UNRELATED Claude-mode install sharing this same home (dir #124's shape) — must keep
# advising `--link` (the slot's real fix), never the bare `--codex` re-run irelink_mode uses for
# bin/keel specifically: a --codex re-run never touches commands/ at all, so that advice would be
# actively useless for this slot.
dlcmd_home="$SANDBOX/codex-dangling-commands/.codex"
run "$install" --codex --home "$dlcmd_home" --no-hooks
check_status "codex install for the dangling-commands fixture -> exit 0" 0 "$STATUS"
mkdir -p "$dlcmd_home/commands"
ln -s "$SANDBOX/nonexistent-checkout/commands/go.md" "$dlcmd_home/commands/go.md"
run "$doctor" --install --codex "$dlcmd_home"
check_status "doctor --install --codex over a dangling commands/* leftover -> exit 1 (GAP)" 1 "$STATUS"
check_contains "names the dangling symlink" "$OUT" "G-LINK-DANGLING"
check_contains "still advises --link for a Claude-only slot, not --codex" "$OUT" "install.sh --link --home \"$dlcmd_home\""
check_absent "never advises a bare --codex re-run, which can't fix commands/ at all" \
  "$OUT" "install.sh --codex --home \"$dlcmd_home\" from its home"

summary
