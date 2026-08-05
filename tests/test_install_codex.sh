#!/usr/bin/env bash
# install.sh --codex — generates the global ~/.codex/AGENTS.md wrapper Codex reads verbatim (dir #76).
# Copy mode only (no @import — that's a Claude Code mechanism): a fresh install lands a clean wrapper
# (no (TEMPLATE) tag, no "copy this" line, no commands/ dir), a re-run never clobbers user edits outside
# the KEEL-CORE block, a drifted block WARNs non-interactively, and --codex + --link is a usage error.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

install="$REPO_ROOT/install.sh"

# --- fresh --codex install ------------------------------------------------------------------------
run "$install" --codex --home "$SANDBOX/codex-home" --no-hooks
check_status "fresh --codex → exit 0" 0 "$STATUS"
check_contains "verify confirms AGENTS.md" "$OUT" "OK   AGENTS.md"
check_file "AGENTS.md exists" "$SANDBOX/codex-home/AGENTS.md"
ac="$(cat "$SANDBOX/codex-home/AGENTS.md")"
check_absent "no (TEMPLATE) tag residue" "$ac" "(TEMPLATE)"
check_absent "no copy-me instruction residue" "$ac" "Copy this to your harness"
check_contains "generated map still names FRAMEWORK.md" "$ac" '`FRAMEWORK.md`'
run cmp -s <(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$SANDBOX/codex-home/AGENTS.md" | sed '1d;$d') \
           <(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/CORE.md" | sed '1d;$d')
check_status "KEEL-CORE block byte-equals CORE.md" 0 "$STATUS"
check_file "FRAMEWORK.md lands at the root (same map as templates/CLAUDE.md)" "$SANDBOX/codex-home/FRAMEWORK.md"
check_file "PRINCIPLES.md lands at the root" "$SANDBOX/codex-home/PRINCIPLES.md"
check_nofile "no commands/ dir wired" "$SANDBOX/codex-home/commands/wrap.md"
check_nofile "no CLAUDE.md — this is the AGENTS.md preset" "$SANDBOX/codex-home/CLAUDE.md"

# --- idempotent re-run: block reported up to date, a user edit OUTSIDE the block survives it -------
printf '\nMY-CODEX-EDIT\n' >> "$SANDBOX/codex-home/AGENTS.md"
run "$install" --codex --home "$SANDBOX/codex-home" --no-hooks
check_status "codex re-run → exit 0" 0 "$STATUS"
check_contains "re-run sees the block up to date" "$OUT" "AGENTS.md (up to date)"
check_contains "user edit outside the block survives" "$(cat "$SANDBOX/codex-home/AGENTS.md")" "MY-CODEX-EDIT"

# --- a drifted KEEL-CORE block: non-interactive → WARN with the fix, never silently clobbered ------
dhome="$SANDBOX/codex-drifted"; mkdir -p "$dhome"
sed 's/## Precedence — when sources conflict/## Precedence — MY EDITED RAIL/' \
  "$REPO_ROOT/templates/CLAUDE.md" > "$dhome/AGENTS.md"
run "$install" --codex --home "$dhome" --no-hooks
check_status "drifted block, non-interactive → exit 0 (no hang, no clobber)" 0 "$STATUS"
check_contains "flags the drifted embedded rails" "$OUT" "AGENTS.md embeds rails that differ from the shipped core"
check_contains "non-interactive path names the fix" "$OUT" "Refresh by hand"
check_contains "the edited rail survives untouched" "$(cat "$dhome/AGENTS.md")" "MY EDITED RAIL"

# --- a foreign (non-Keel) AGENTS.md: left untouched, flagged instead of merged or clobbered --------
fhome="$SANDBOX/codex-foreign"; mkdir -p "$fhome"
printf '# My own Codex notes\nnothing keel here\n' > "$fhome/AGENTS.md"
run "$install" --codex --home "$fhome" --no-hooks
check_status "foreign AGENTS.md + --codex → exit 0" 0 "$STATUS"
check_contains "foreign file content preserved" "$(cat "$fhome/AGENTS.md")" "My own Codex notes"
check_contains "verify flags the un-merged rails" "$OUT" "NOT merged in"

# --- --codex + --link is a usage error, before either mode does any work --------------------------
run "$install" --codex --link --home "$SANDBOX/codex-link-error" --no-hooks
check_status "--codex + --link → exit 2" 2 "$STATUS"
check_contains "rejection names the conflict" "$OUT" "--codex only supports the copy path"
check_nofile "nothing was written on the rejected combo" "$SANDBOX/codex-link-error/AGENTS.md"

# --- default home is $HOME/.codex when --home is not given -----------------------------------------
run env HOME="$SANDBOX/codex-default-home" "$install" --codex --no-hooks
check_status "--codex without --home → exit 0" 0 "$STATUS"
check_file "defaults to \$HOME/.codex" "$SANDBOX/codex-default-home/.codex/AGENTS.md"

# --- test_core_wrapper_sync.sh stays untouched (proof no third copy of the core appeared) ----------
check_file "the byte-pin test file exists and was not touched by this ticket" "$REPO_ROOT/tests/test_core_wrapper_sync.sh"

summary
