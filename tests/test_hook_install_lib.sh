#!/usr/bin/env bash
# test_hook_install_lib.sh — dir #437 build PR1 (MW8): tools/lib/hook-install.sh is the ONE settings-merge
# core that tools/install-read-trace.sh and tools/install-pre-pr-gate.sh used to carry as two byte-identical
# hand copies (and that a third installer would have copied again). Direct coverage of the lib's own
# contract, so a future edit to the merge/remove programs is caught here and not only through the two
# installers' end-to-end fixtures (tests/test_install_read_trace.sh, tests/test_install_pre_pr_gate.sh —
# which this PR leaves byte-unmodified, the spec's proof of behaviour preservation).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/hook-install.sh"
check_file "tools/lib/hook-install.sh exists" "$lib"
[ -f "$lib" ] || { summary; exit 1; }

run bash -n "$lib"
check_status "hook-install.sh parses (bash -n)" 0 "$STATUS"

# --- the spec's PR1 acceptance: the programs live ONLY in the lib ------------------------------------
for inst in install-read-trace.sh install-pre-pr-gate.sh; do
  n="$(grep -c 'merge_prog=' "$REPO_ROOT/tools/$inst" || true)"
  check_status "$inst carries no merge_prog= (the program lives only in the lib)" 0 "$n"
  n="$(grep -c 'remove_prog=' "$REPO_ROOT/tools/$inst" || true)"
  check_status "$inst carries no remove_prog= (the program lives only in the lib)" 0 "$n"
  pin "$inst sources the lib" "$REPO_ROOT/tools/$inst" 'lib/hook-install.sh' \
    "$inst must source tools/lib/hook-install.sh"
done
n="$(grep -c 'merge_prog=\|remove_prog=' "$lib" || true)"
check_status "the lib holds both programs (one merge_prog=, one remove_prog=)" 2 "$n"

# shellcheck source=/dev/null
. "$lib"

specs='[
  {"event":"PostToolUse","matcher":"Bash","command":"bash '"'"'/k/x.sh'"'"' a"},
  {"event":"SessionEnd","matcher":"","command":"bash '"'"'/k/x.sh'"'"' end"}
]'

# --- merge: MISSING on an empty settings, with the hooks written in -----------------------------------
merged="$(hook_install_merge "$specs" '{}')"
check_status "merge: empty settings → both specs MISSING" \
  "$(printf 'MISSING\tPostToolUse\tBash\nMISSING\tSessionEnd\t')" "$(jq -r '.report' <<<"$merged")"
check_status "merge: the command lands under hooks.PostToolUse[0].hooks[0]" \
  "bash '/k/x.sh' a" "$(jq -r '.new.hooks.PostToolUse[0].hooks[0].command' <<<"$merged")"

# --- merge: SAME on a re-run, and foreign data is untouched ---------------------------------------------
cur="$(jq -c '.new + {theme: "dark"}' <<<"$merged")"
merged2="$(hook_install_merge "$specs" "$cur")"
check_status "merge: re-run → SAME, SAME" \
  "$(printf 'SAME\tPostToolUse\tBash\nSAME\tSessionEnd\t')" "$(jq -r '.report' <<<"$merged2")"
check_status "merge: a foreign top-level key survives" dark "$(jq -r '.new.theme' <<<"$merged2")"

# --- merge: CONFLICT on the same event+matcher running a different command, replaced in .new ----------
foreign='{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other"}]}]}}'
merged3="$(hook_install_merge "$specs" "$foreign")"
check_status "merge: a different command on the same event+matcher → CONFLICT" \
  CONFLICT "$(jq -r '.report | split("\n")[0] | split("\t")[0]' <<<"$merged3")"
check_status "merge: …and the as-if-forced result carries ours" \
  "bash '/k/x.sh' a" "$(jq -r '.new.hooks.PostToolUse[0].hooks[0].command' <<<"$merged3")"

# --- remove: byte-identical entries go, a differing one is KEPT -----------------------------------------
rm1="$(hook_install_remove "$specs" "$cur")"
check_status "remove: both of ours → REMOVED, REMOVED" \
  "$(printf 'REMOVED\tPostToolUse\tBash\nREMOVED\tSessionEnd\t')" "$(jq -r '.report' <<<"$rm1")"
rm2="$(hook_install_remove "$specs" "$foreign")"
check_status "remove: a differing command on our event+matcher → KEPT, left in place" \
  KEPT "$(jq -r '.report | split("\t")[0]' <<<"$rm2")"
check_status "remove: …and still present in .new" other \
  "$(jq -r '.new.hooks.PostToolUse[0].hooks[0].command' <<<"$rm2")"

# --- remove: the empty-array prune is scoped to OUR events (dir #564/#390) ------------------------------
withforeign="$(jq -c '.new + {hooks: (.new.hooks + {Foreign: []})}' <<<"$merged")"
rm3="$(hook_install_remove "$specs" "$withforeign")"
check_status "remove: another tool's empty hook array survives" \
  true "$(jq '.new.hooks | has("Foreign")' <<<"$rm3")"
check_status "remove: OUR now-empty arrays are pruned" \
  false "$(jq '.new.hooks | has("PostToolUse") or has("SessionEnd")' <<<"$rm3")"

# --- the shape check ------------------------------------------------------------------------------------
run hook_install_check_shape "install-x" "/p/settings.json" "$specs" '{"hooks":[]}'
check_status "check_shape: .hooks as an array → return 2" 2 "$STATUS"
check_status "check_shape: …named with the caller's prefix" 1 \
  "$(printf '%s' "$OUT" | grep -c '^install-x: /p/settings.json')"
run hook_install_check_shape "install-x" "/p/settings.json" "$specs" '{"hooks":{"PostToolUse":"str"}}'
check_status "check_shape: an event that is not an array → return 2" 2 "$STATUS"
run hook_install_check_shape "install-x" "/p/settings.json" "$specs" '{"hooks":{"PostToolUse":[]}}'
check_status "check_shape: a well-formed settings → return 0" 0 "$STATUS"
run hook_install_check_shape "install-x" "/p/settings.json" "$specs" '{}'
check_status "check_shape: empty settings → return 0" 0 "$STATUS"

# --- backup + atomic write ------------------------------------------------------------------------------
printf 'one\n' > "$SANDBOX/s.json"
hook_install_backup "$SANDBOX/s.json"
check_file "backup: a timestamped .bak sibling is written" "$HOOK_INSTALL_BACKUP"
check_status "backup: …with the original content" one "$(cat "$HOOK_INSTALL_BACKUP")"
hook_install_atomic_write "$SANDBOX/s.json" two
check_status "atomic_write: replaces the content" two "$(cat "$SANDBOX/s.json")"
check_status "atomic_write: leaves no temp sibling behind" 0 \
  "$(find "$SANDBOX" -maxdepth 1 -name 's.json.keeltmp.*' | grep -c . || true)"

# --- fail-closed sourcing: a checkout missing the lib refuses, with one actionable message --------------
for inst in install-read-trace.sh install-pre-pr-gate.sh; do
  fx="$SANDBOX/incomplete-$inst"
  rm -rf "$fx"; mkdir -p "$fx/tools/lib"
  cp "$REPO_ROOT/tools/$inst" "$fx/tools/$inst"
  for l in sh-quote.sh repo-arg-guard.sh gate-paths.sh ledger.sh; do
    [ -f "$REPO_ROOT/tools/lib/$l" ] && cp "$REPO_ROOT/tools/lib/$l" "$fx/tools/lib/$l"
  done
  mkdir -p "$fx/repo"
  run bash "$fx/tools/$inst" "$fx/repo"
  check_status "$inst: lib missing → exit 1 (refuses, writes nothing)" 1 "$STATUS"
  check_status "$inst: …names tools/lib/hook-install.sh" 1 \
    "$(printf '%s' "$OUT" | grep -c 'tools/lib/hook-install.sh is missing or corrupted')"
  check_status "$inst: …and wrote no settings.json" 0 "$(find "$fx/repo" -name settings.json | grep -c .)"
done

summary
