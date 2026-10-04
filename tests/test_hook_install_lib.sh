#!/usr/bin/env bash
# test_hook_install_lib.sh — dir #437 build PR1 (MW8): tools/lib/hook-install.sh is the ONE settings-merge
# core that tools/install-read-trace.sh and tools/install-pre-pr-gate.sh used to carry as two byte-identical
# hand copies (and that a third installer would have copied again — install-machine-watch.sh is that
# third consumer, so both installer loops below name all three). Direct coverage of the lib's own
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
for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
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

# first_status RESULT — the status column of a merge/remove result's first report line.
first_status() { jq -r '.report | split("\n")[0] | split("\t")[0]' <<<"$1"; }

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

# --- merge: a foreign command on the same event+matcher is APPENDED beside it, never replaced (dir #468) ---
foreign='{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other"}]}]}}'
merged3="$(hook_install_merge "$specs" "$foreign")"
check_status "merge: a different command on the same event+matcher → APPENDED" \
  APPENDED "$(first_status "$merged3")"
check_status "merge: …the incumbent entry is byte-untouched" \
  '{"matcher":"Bash","hooks":[{"type":"command","command":"other"}]}' "$(jq -c '.new.hooks.PostToolUse[0]' <<<"$merged3")"
check_status "merge: …ours rides in a sibling entry with the same matcher" \
  "bash '/k/x.sh' a" "$(jq -r '.new.hooks.PostToolUse[1].hooks[0].command' <<<"$merged3")"
check_status "merge: …and the sibling carries the spec's matcher" \
  Bash "$(jq -r '.new.hooks.PostToolUse[1].matcher' <<<"$merged3")"
merged3b="$(hook_install_merge "$specs" "$(jq -c '.new' <<<"$merged3")")"
check_status "merge: re-run over an APPENDED result → SAME (ours in the second entry is found, not appended again)" \
  SAME "$(first_status "$merged3b")"
check_status "merge: …entry count unchanged after the re-run" 2 "$(jq '.new.hooks.PostToolUse | length' <<<"$merged3b")"

# --- merge: the SAME hook at a DIFFERENT path is STALE; the as-if-forced result swaps just that command ---
stale='{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"keep-me"},{"type":"command","command":"bash '"'"'/old/place/x.sh'"'"' a"}]}]}}'
merged4="$(hook_install_merge "$specs" "$stale")"
check_status "merge: same script + args at another path → STALE (not APPENDED)" \
  STALE "$(first_status "$merged4")"
check_status "merge: …forced, the stale command becomes ours" \
  "bash '/k/x.sh' a" "$(jq -r '.new.hooks.PostToolUse[0].hooks[1].command' <<<"$merged4")"
check_status "merge: …forced, the sibling command in the same entry survives" \
  keep-me "$(jq -r '.new.hooks.PostToolUse[0].hooks[0].command' <<<"$merged4")"
check_status "merge: …forced, no duplicate entry is added" 1 "$(jq '.new.hooks.PostToolUse | length' <<<"$merged4")"
hookless='{"hooks":{"PostToolUse":[{"matcher":"Bash"},{"matcher":"Bash","hooks":[{"type":"command","command":"bash '"'"'/old/place/x.sh'"'"' a"}]}]}}'
merged4b="$(hook_install_merge "$specs" "$hookless" 2>&1)"
check_status "merge: a same-matcher entry with no hooks key does not crash the stale swap" \
  STALE "$(first_status "$merged4b")"
other_args='{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash '"'"'/old/x.sh'"'"' b"}]}]}}'
merged5="$(hook_install_merge "$specs" "$other_args")"
check_status "merge: same script, DIFFERENT args is a different hook → APPENDED, not STALE" \
  APPENDED "$(first_status "$merged5")"

# --- remove: our exact hook goes, a differing command on the slot is KEPT ------------------------------
rm1="$(hook_install_remove "$specs" "$cur")"
check_status "remove: both of ours → REMOVED, REMOVED" \
  "$(printf 'REMOVED\tPostToolUse\tBash\nREMOVED\tSessionEnd\t')" "$(jq -r '.report' <<<"$rm1")"
rm2="$(hook_install_remove "$specs" "$foreign")"
check_status "remove: a differing command on our event+matcher → KEPT, left in place" \
  KEPT "$(jq -r '.report | split("\t")[0]' <<<"$rm2")"
check_status "remove: …and still present in .new" other \
  "$(jq -r '.new.hooks.PostToolUse[0].hooks[0].command' <<<"$rm2")"

# --- remove: after an append, only OUR sibling entry goes, wherever it sits (dir #468) --------------------
rm4="$(hook_install_remove "$specs" "$(jq -c '.new' <<<"$merged3")")"
check_status "remove: our appended sibling → REMOVED" \
  REMOVED "$(first_status "$rm4")"
check_status "remove: …the incumbent entry is left exactly as it was" \
  '[{"matcher":"Bash","hooks":[{"type":"command","command":"other"}]}]' "$(jq -c '.new.hooks.PostToolUse' <<<"$rm4")"
rm5="$(hook_install_remove "$specs" "$(jq -c '.new.hooks.PostToolUse |= reverse | .new' <<<"$merged3")")"
check_status "remove: ours listed BEFORE the incumbent is found too (not just the first matcher hit)" \
  REMOVED "$(first_status "$rm5")"

# --- remove: ours INSIDE a shared entry (what a forced STALE swap leaves) comes out alone ---------------
rm6="$(hook_install_remove "$specs" "$(jq -c '.new' <<<"$merged4")")"
check_status "remove: ours inside an entry with someone else's command → REMOVED, not KEPT" \
  REMOVED "$(first_status "$rm6")"
check_status "remove: …only ours leaves; the sibling command in that entry stays" \
  '[{"type":"command","command":"keep-me"}]' "$(jq -c '.new.hooks.PostToolUse[0].hooks' <<<"$rm6")"

# --- remove: an empty array under another tool's event name survives (dir #564/#390) -------------------
withforeign="$(jq -c '.new + {hooks: (.new.hooks + {Foreign: []})}' <<<"$merged")"
rm3="$(hook_install_remove "$specs" "$withforeign")"
check_status "remove: another tool's empty hook array survives" \
  true "$(jq '.new.hooks | has("Foreign")' <<<"$rm3")"
check_status "remove: OUR now-empty arrays are pruned" \
  false "$(jq '.new.hooks | has("PostToolUse") or has("SessionEnd")' <<<"$rm3")"

# --- dir #600: the prune keys on the arrays THIS run emptied, not on our event NAMES -------------------
# An empty array under one of our event names that held nothing of ours (another tool's, or a hand
# edit's) was not emptied by us, so it is not ours to delete.
pre_empty="$(jq -c '.new | .hooks.SessionEnd = []' <<<"$merged")"
rm600="$(hook_install_remove "$specs" "$pre_empty")"
check_status "remove: an array OUR removal emptied is pruned" false "$(jq '.new.hooks | has("PostToolUse")' <<<"$rm600")"
check_status "remove: an already-empty array on one of our event names survives" \
  '[]' "$(jq -c '.new.hooks.SessionEnd' <<<"$rm600")"
rm600b="$(hook_install_remove "$specs" '{"hooks":{"PostToolUse":[],"SessionEnd":[]}}')"
check_status "remove: nothing of ours anywhere → nothing pruned" \
  '{"PostToolUse":[],"SessionEnd":[]}' "$(jq -c '.new.hooks' <<<"$rm600b")"

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

# --- dir #660: the writer keeps a file's mode and a symlink's link; backups never collide ----------------
# shellcheck source=tools/lib/stat-portable.sh
. "$REPO_ROOT/tools/lib/stat-portable.sh"

printf '{}\n' > "$SANDBOX/m.json"; chmod 600 "$SANDBOX/m.json"
hook_install_atomic_write "$SANDBOX/m.json" '{"a":1}'
check_status "atomic_write: a 0600 file stays 0600 (not the umask's 0644)" 600 "$(stat_portable_mode "$SANDBOX/m.json")"

mkdir -p "$SANDBOX/dots" "$SANDBOX/proj"
printf '{}\n' > "$SANDBOX/dots/settings.json"; chmod 600 "$SANDBOX/dots/settings.json"
ln -s ../dots/settings.json "$SANDBOX/proj/settings.json"
hook_install_atomic_write "$SANDBOX/proj/settings.json" '{"b":2}'
check_link "atomic_write: a symlinked file stays a symlink" "$SANDBOX/proj/settings.json"
check_status "atomic_write: …the write lands in the link's (relative, other-dir) target" \
  '{"b":2}' "$(cat "$SANDBOX/dots/settings.json")"
check_status "atomic_write: …whose 0600 mode is kept" 600 "$(stat_portable_mode "$SANDBOX/dots/settings.json")"
check_status "atomic_write: …and no temp is left in either dir" 0 \
  "$(find "$SANDBOX/dots" "$SANDBOX/proj" -name '*.keeltmp.*' | grep -c . || true)"
ln -s "$SANDBOX/proj/settings.json" "$SANDBOX/chain.json"
hook_install_atomic_write "$SANDBOX/chain.json" '{"c":3}'
check_link "atomic_write: a link to a link stays a link" "$SANDBOX/chain.json"
check_status "atomic_write: …the write follows every hop to the real file" '{"c":3}' "$(cat "$SANDBOX/dots/settings.json")"
ln -s loopb "$SANDBOX/loopa"; ln -s loopa "$SANDBOX/loopb"
run hook_install_atomic_write "$SANDBOX/loopa" '{}'
check_status "atomic_write: a symlink loop → return 1" 1 "$STATUS"
check_link "atomic_write: …and the loop is not replaced by a file" "$SANDBOX/loopa"
mkdir -p "$SANDBOX/adir"; ln -s adir "$SANDBOX/dirlink.json"
for t in adir dirlink.json; do
  run hook_install_atomic_write "$SANDBOX/$t" '{}'
  check_status "atomic_write: $t (a directory) → return 1" 1 "$STATUS"
  check_contains "atomic_write: …$t refused as not a regular file" "$OUT" "is not a regular file"
done
check_status "atomic_write: …and no temp was nested inside the directory" 0 "$(find "$SANDBOX/adir" -type f | grep -c . || true)"
ln -s "$SANDBOX/no-such-dir/s.json" "$SANDBOX/dangling.json"
run hook_install_atomic_write "$SANDBOX/dangling.json" '{}'
check_status "atomic_write: a link into a missing directory → return 1" 1 "$STATUS"
check_contains "atomic_write: …with the installer's own refusal, not a raw shell error" "$OUT" "could not write"
check_link "atomic_write: …and the link is left as it was" "$SANDBOX/dangling.json"
# A read-only target refuses for a non-root user; root writes through 0444, so only the content
# assertions are guarded (CLAUDE.md "Linux-leg traps" 2).
printf 'ro\n' > "$SANDBOX/ro.json"; chmod 444 "$SANDBOX/ro.json"
run hook_install_atomic_write "$SANDBOX/ro.json" '{}'
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_status "atomic_write: a read-only target → return 1" 1 "$STATUS"
  check_contains "atomic_write: …with the installer's own refusal" "$OUT" "could not write"
  check_status "atomic_write: …and its content is untouched" ro "$(cat "$SANDBOX/ro.json")"
fi
check_status "atomic_write: …and no temp is left beside it" 0 \
  "$(find "$SANDBOX" -maxdepth 1 -name 'ro.json.keeltmp.*' | grep -c . || true)"

# Same-second collision (S3-5), made deterministic: a `date` function shadows the binary inside the lib's
# $(date …), so both backups read one clock second — without the fix the second cp overwrote the first.
date() { echo 20260101T000000Z; }
printf 'first\n' > "$SANDBOX/c.json"; chmod 600 "$SANDBOX/c.json"
hook_install_backup "$SANDBOX/c.json"; b1="$HOOK_INSTALL_BACKUP"
printf 'second\n' > "$SANDBOX/c.json"
hook_install_backup "$SANDBOX/c.json"; b2="$HOOK_INSTALL_BACKUP"
unset -f date
check_ne "backup: a second backup in the same second gets its own name" "$b1" "$b2"
check_status "backup: …the first backup still holds the first content" first "$(cat "$b1")"
check_status "backup: …the second holds the second" second "$(cat "$b2")"
check_status "backup: …named <file>.<ts>.2.bak" "$SANDBOX/c.json.20260101T000000Z.2.bak" "$b2"
check_status "backup: a 0600 file's backup is 0600 too" 600 "$(stat_portable_mode "$b1")"
run hook_install_backup "$SANDBOX/no-such.json"
check_status "backup: a failed copy → return 1" 1 "$STATUS"
check_status "backup: …and leaves no claimed empty .bak behind" 0 \
  "$(find "$SANDBOX" -maxdepth 1 -name 'no-such.json.*' | grep -c . || true)"
mkdir -p "$SANDBOX/rodir"; printf 'x\n' > "$SANDBOX/rodir/s.json"; chmod 555 "$SANDBOX/rodir"
run hook_install_backup "$SANDBOX/rodir/s.json"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_status "backup: an unwritable directory → return 1" 1 "$STATUS"
  check_contains "backup: …says why, instead of exiting silently" "$OUT" "cannot create a backup"
fi
chmod 755 "$SANDBOX/rodir"

# --- dir #660 (R2-5): a malformed NESTED shape gets the clean refusal, not a raw jq error ---------------
for bad in '["x"]' '{"hooks":{"PostToolUse":["str"]}}' \
  '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":"x"}]}}' \
  '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":["s"]}]}}'; do
  run hook_install_check_shape "install-x" "/p/settings.json" "$specs" "$bad"
  check_status "check_shape: $bad → return 2" 2 "$STATUS"
  check_absent "check_shape: …$bad refused with no raw jq error" "$OUT" "jq: error"
done
run hook_install_check_shape "install-x" "/p/settings.json" "$specs" \
  '{"hooks":{"PostToolUse":[{"matcher":"Bash"},{"matcher":"Bash","hooks":[{"type":"command","command":"x"}]}],"Other":["not ours"]}}'
check_status "check_shape: a hookless entry, and an odd shape on an event that is not ours → return 0" 0 "$STATUS"

# --- dir #92: a match-all entry already holding ours is SAME, not a second entry -------------------------
ours_cmd="bash '/k/x.sh' a"
for m in absent null '""' '"*"'; do
  if [ "$m" = absent ]; then ent='{}'; else ent="{\"matcher\":$m}"; fi
  cur92="$(jq -c --arg c "$ours_cmd" '{hooks: {PostToolUse: [. + {hooks: [{type: "command", command: "keep"}, {type: "command", command: $c}]}]}}' <<<"$ent")"
  m92="$(hook_install_merge "$specs" "$cur92")"
  check_status "merge: ours inside a matcher=$m entry → SAME" \
    SAME "$(first_status "$m92")"
  check_status "merge: …no second entry is added" 1 "$(jq '.new.hooks.PostToolUse | length' <<<"$m92")"
  r92="$(hook_install_remove "$specs" "$cur92")"
  check_status "remove: ours inside a matcher=$m entry → REMOVED" \
    REMOVED "$(first_status "$r92")"
  check_status "remove: …only ours leaves; the entry's other command stays" \
    '[{"type":"command","command":"keep"}]' "$(jq -c '.new.hooks.PostToolUse[0].hooks' <<<"$r92")"
done
only_ours="$(jq -nc --arg c "$ours_cmd" '{hooks: {PostToolUse: [{hooks: [{type: "command", command: $c}]}]}}')"
r92b="$(hook_install_remove "$specs" "$only_ours")"
check_status "remove: a matcher-less entry left empty goes, and so does our emptied event" \
  false "$(jq '.new.hooks | has("PostToolUse")' <<<"$r92b")"
stale92="$(jq -nc --arg c "bash '/old/x.sh' a" '{hooks: {PostToolUse: [{hooks: [{type: "command", command: $c}]}]}}')"
m92s="$(hook_install_merge "$specs" "$stale92")"
check_status "merge: our hook at an old path inside a matcher-less entry → STALE" \
  STALE "$(first_status "$m92s")"
check_status "merge: …forced, swapped in place — no second entry" \
  "[{\"hooks\":[{\"type\":\"command\",\"command\":\"$ours_cmd\"}]}]" "$(jq -c '.new.hooks.PostToolUse' <<<"$m92s")"
other_m="$(jq -nc --arg c "$ours_cmd" '{hooks: {PostToolUse: [{matcher: "Edit", hooks: [{type: "command", command: $c}]}]}}')"
m92o="$(hook_install_merge "$specs" "$other_m")"
check_status "merge: ours under a DIFFERENT specific matcher still reads MISSING (a matcher migration is unchanged)" \
  MISSING "$(first_status "$m92o")"

# --- dir #660 end to end: every installer keeps a symlinked 0600 settings.json linked and 0600 ---------
# through install AND --uninstall (memory: a new write shape needs the uninstall round-trip too), and a
# malformed nested shape on an event every installer owns refuses cleanly with the file untouched.
r2="$(new_repo)"; mkdir -p "$r2/.claude"
printf '{"hooks":{"SessionStart":["str"]}}\n' > "$r2/.claude/settings.json"
for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
  r="$(new_repo)"; d="$SANDBOX/dots-$inst"
  mkdir -p "$r/.claude" "$d"
  printf '{"theme":"dark"}\n' > "$d/settings.json"; chmod 600 "$d/settings.json"
  ln -s "$d/settings.json" "$r/.claude/settings.json"
  run bash "$REPO_ROOT/tools/$inst" "$r"
  check_status "$inst over a symlinked settings.json → exit 0" 0 "$STATUS"
  check_link "$inst: …settings.json is still a symlink" "$r/.claude/settings.json"
  check_status "$inst: …the hooks landed in the link's target" true "$(jq '(.hooks | length) > 0' "$d/settings.json")"
  check_status "$inst: …the target is still 0600" 600 "$(stat_portable_mode "$d/settings.json")"
  run bash "$REPO_ROOT/tools/$inst" --uninstall "$r"
  check_status "$inst --uninstall over the symlink → exit 0" 0 "$STATUS"
  check_link "$inst: …settings.json is still a symlink after --uninstall" "$r/.claude/settings.json"
  check_status "$inst: …our hooks left the target, the foreign key stayed" 'dark 0' \
    "$(jq -r '"\(.theme) \(.hooks // {} | length)"' "$d/settings.json")"
  check_status "$inst: …and the target is still 0600" 600 "$(stat_portable_mode "$d/settings.json")"
  bak="$(find "$r/.claude" -name 'settings.json.*.bak' | head -n1)"
  check_status "$inst: …the --uninstall backup is 0600 too" 600 "$(stat_portable_mode "${bak:-/dev/null}")"

  for flag in "" --uninstall; do
    lbl="$inst ${flag:-install}"
    run bash "$REPO_ROOT/tools/$inst" ${flag:+"$flag"} "$r2"
    check_status "$lbl over a malformed nested entry → exit 2" 2 "$STATUS"
    check_contains "$lbl: …the clean refusal" "$OUT" "unexpected shape"
    check_absent "$lbl: …no raw jq error" "$OUT" "jq: error"
    check_status "$lbl: …the file is untouched" '{"hooks":{"SessionStart":["str"]}}' \
      "$(cat "$r2/.claude/settings.json")"
  done
done

# --- fail-closed sourcing: a checkout missing the lib refuses, with one actionable message --------------
for inst in install-read-trace.sh install-pre-pr-gate.sh install-machine-watch.sh; do
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
    "$(printf '%s' "$OUT" | grep -c 'tools/lib/hook-install (the settings-merge lib) is missing or corrupted')"
  check_status "$inst: …and wrote no settings.json" 0 "$(find "$fx/repo" -name settings.json | grep -c .)"
done

summary
