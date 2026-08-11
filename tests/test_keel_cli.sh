#!/usr/bin/env bash
# keel — the thin dispatcher. These tests pin the CONTRACT, not the tools it forwards to: every verb
# reaches its own script with args intact, the child's exit code passes straight through, an unknown
# verb is usage+exit-2, and the checkout self-resolves through a PATH symlink from any cwd.
#
# The dispatch table is tested against a FAKE checkout of stub scripts (each echoes a marker + exits a
# chosen code), so a green run means "keel routed correctly", independent of what the real install.sh /
# tools/*.sh happen to do today.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# A fake checkout: a copy of the real `keel` beside stub scripts it dispatches to. Copied (not
# symlinked) so keel's self-resolution lands on THIS dir as the checkout.
fake="$SANDBOX/checkout"
mkdir -p "$fake/tools"
cp "$REPO_ROOT/keel" "$fake/keel"
chmod +x "$fake/keel"

# stub NAME EXIT — write $fake/NAME that echoes a marker (with its forwarded args) and exits EXIT.
stub() {
  local path="$fake/$1" code="$2"
  mkdir -p "$(dirname "$path")"
  printf '#!/bin/sh\necho "STUB %s args=[$*]"\nexit %s\n' "$1" "$code" > "$path"
  chmod +x "$path"
}
stub install.sh          0
stub uninstall.sh        0
stub tools/doctor.sh     0
stub tools/public-audit.sh 0
stub tools/init-project.sh 0
stub tools/keel-check.sh 7   # a non-zero, non-2 code proves genuine pass-through (not keel's own exit)

keel="$fake/keel"

# --- every verb reaches its own script, args forwarded ------------------------------------------
run "$keel" install --link
check_contains "install -> install.sh"        "$OUT" "STUB install.sh args=[--link]"
run "$keel" doctor --install
check_contains "doctor -> tools/doctor.sh"     "$OUT" "STUB tools/doctor.sh args=[--install]"
run "$keel" audit
check_contains "audit -> tools/public-audit.sh" "$OUT" "STUB tools/public-audit.sh args=[]"
run "$keel" init /some/dir
check_contains "init -> tools/init-project.sh" "$OUT" "STUB tools/init-project.sh args=[/some/dir]"
run "$keel" check make test
check_contains "check -> tools/keel-check.sh"  "$OUT" "STUB tools/keel-check.sh args=[make test]"
run "$keel" uninstall --dry-run
check_contains "uninstall -> uninstall.sh"     "$OUT" "STUB uninstall.sh args=[--dry-run]"

# --- child exit code passes straight through ----------------------------------------------------
run "$keel" check anything          # stub exits 7
check_status "check forwards the child's exit code" 7 "$STATUS"
run "$keel" install
check_status "install forwards a 0 exit code" 0 "$STATUS"

# --- usage / unknown verb -----------------------------------------------------------------------
run "$keel"
check_status "no args -> exit 2" 2 "$STATUS"
check_contains "no args prints usage" "$OUT" "Usage: keel"
run "$keel" bogus-verb
check_status "unknown verb -> exit 2" 2 "$STATUS"
check_contains "unknown verb names itself" "$OUT" "unknown command 'bogus-verb'"
run "$keel" help
check_status "help -> exit 0" 0 "$STATUS"
check_contains "help lists the verbs" "$OUT" "uninstall"

# --- version ------------------------------------------------------------------------------------
run "$keel" version
check_status "version -> exit 0" 0 "$STATUS"
check_contains "version prints a keel line" "$OUT" "keel "   # git-describe or 'unknown', both fine

# --- self-resolution: a PATH symlink from an unrelated cwd resolves the checkout ----------------
bindir="$SANDBOX/bin"; mkdir -p "$bindir"
ln -s "$fake/keel" "$bindir/keel"
run_in "$SANDBOX" "$bindir/keel" install --link
check_contains "resolves the checkout through a symlink, from another cwd" "$OUT" "STUB install.sh args=[--link]"

# invoked as a bare name found on PATH (no slash in $0) — the command -v branch
run_in "$SANDBOX" env PATH="$bindir:$PATH" keel doctor
check_contains "resolves when invoked as a bare PATH name" "$OUT" "STUB tools/doctor.sh"

# --- sanity guard: a keel with no sibling install.sh/tools errors, not a confusing ENOENT --------
orphan="$SANDBOX/orphan"; mkdir -p "$orphan"
cp "$REPO_ROOT/keel" "$orphan/keel"; chmod +x "$orphan/keel"
run "$orphan/keel" doctor
check_status "orphaned keel (no siblings) -> exit 1" 1 "$STATUS"
check_contains "orphaned keel explains itself" "$OUT" "cannot find the Keel checkout"

# dir #98: the re-wire it advises must reach the home this CLI was installed into, not wherever a
# bare re-run would land — bin/keel sits one level under that home, so $0's grandparent names it.
rehome="$SANDBOX/rewire-home"; mkdir -p "$rehome/bin"
cp "$REPO_ROOT/keel" "$rehome/bin/keel"; chmod +x "$rehome/bin/keel"
printf '# ctx\n' > "$rehome/CLAUDE.md"
rehome_p="$(cd "$rehome" && pwd -P)"   # keel resolves the home physically; /tmp is a symlink on macOS
run "$rehome/bin/keel" doctor
check_status "severed keel in a retargeted home -> exit 1" 1 "$STATUS"
check_contains "and its re-wire advice names that home" "$OUT" "install.sh --home \"$rehome_p\""
check_absent "no --codex on a CLAUDE.md home" "$OUT" "--codex"

# ...and the MODE travels with it: bin/keel is wired in both modes, so a Codex home must not be told
# to re-run Claude copy mode into itself. The mode is read off the home's own always-loaded file.
cxhome="$SANDBOX/rewire-codex"; mkdir -p "$cxhome/bin"
cp "$REPO_ROOT/keel" "$cxhome/bin/keel"; chmod +x "$cxhome/bin/keel"
printf '# ctx\n' > "$cxhome/AGENTS.md"
cxhome_p="$(cd "$cxhome" && pwd -P)"
run "$cxhome/bin/keel" doctor
check_contains "a Codex home gets --codex too" "$OUT" "install.sh --codex --home \"$cxhome_p\""

# --- dir #104: the verb list docs quote must not drift from the dispatcher's own case arms ------
# The dispatcher's `case "$cmd" in ... esac` block is the one source of truth for what verbs exist
# (dir #85 found docs/reference.md and README.md each missing 2 of 9 verbs, undetected). Enumerate
# the arms from the REAL keel script (not the fake stub), then assert every verb is still quoted in
# both docs — same shape as test_doc_figures.sh pinning doc prose against template headings.
case_block="$(awk '/^case "\$cmd" in/,/^esac/' "$REPO_ROOT/keel")"
# Leading whitespace is `[[:space:]]+`, not a fixed two spaces — a case arm re-indented with a tab
# or a different width wouldn't match a fixed prefix, silently dropping that ONE verb from the list
# below (a false PASS, since a never-extracted verb is never checked against the docs at all; found
# in review). A total-arm cross-check catches that class even when the specific-arm regex still
# fails to future drift: count case arms independently via a much looser pattern (any non-comment,
# non-blank line ending in `)`, minus the `*)` catch-all) and assert it matches how many verbs were
# actually extracted.
verbs="$(printf '%s' "$case_block" | grep -oE '^[[:space:]]+[a-zA-Z][a-zA-Z0-9_|-]*\)' | sed 's/^[[:space:]]*//;s/)$//' | cut -d'|' -f1)"
[ -n "$verbs" ] || fail "extracted verb list from keel's case block" "no arms found — did the case syntax change?"
arm_count="$(printf '%s' "$case_block" | grep -vE '^[[:space:]]*(#|case|esac|$)' | grep -cE '^[[:space:]]*[^[:space:]#]*\)')"
verb_count="$(printf '%s\n' $verbs | wc -w | tr -d ' ')"
if [ "$arm_count" -eq $(( verb_count + 1 )) ]; then   # +1 for the `*)` catch-all, never a real verb
  pass "every case arm was extracted as a verb ($verb_count verbs + 1 catch-all = $arm_count arms)"
else
  fail "every case arm was extracted as a verb" "found $arm_count total arms but only extracted $verb_count verbs — one was silently dropped (non-standard indentation?)"
fi

ref_line="$(grep -F '](../keel)' "$REPO_ROOT/docs/reference.md")"
readme_block="$(awk '/lists the verbs:/{f=1} f{print; if (/`keel help`\./) exit}' "$REPO_ROOT/README.md")"
[ -n "$ref_line" ] || fail "found the keel row in docs/reference.md" "no line links to ../keel"
[ -n "$readme_block" ] || fail "found the verb-list paragraph in README.md" "no line matches 'lists the verbs:'"

for v in $verbs; do
  if printf '%s' "$ref_line" | grep -qw "$v"; then
    pass "docs/reference.md quotes verb: $v"
  else
    fail "docs/reference.md quotes verb: $v" "missing from the keel row — dispatcher has it, doc doesn't"
  fi
  if printf '%s' "$readme_block" | grep -qw "$v"; then
    pass "README.md quotes verb: $v"
  else
    fail "README.md quotes verb: $v" "missing from the verb-list paragraph — dispatcher has it, doc doesn't"
  fi
done

summary
