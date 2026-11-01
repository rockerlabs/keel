#!/usr/bin/env bash
# Cross-check for the two "which files are safety rails" default lists (dir #261):
#   tools/drydock/inventory.sh      DRYDOCK_INVARIANT_PATHS  exact repo-relative paths
#   tools/delta-audit/derive.sh     DELTA_INVARIANT_PATHS    substrings
# The match semantics differ on purpose (exact vs substring) and stay different; this test only pins that
# the two lists describe the same file set, so adding a rail to one list without the other fails here.
# Legitimate divergences are named below and must still be real (a stale exception fails too).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

DRY="$REPO_ROOT/tools/drydock/inventory.sh"
DELTA="$REPO_ROOT/tools/delta-audit/derive.sh"

# Drydock paths with no delta-audit substring, and delta-audit substrings with no drydock path.
DRY_ONLY="keel"                 # the launcher binary: a rail, but no substring entry covers its bare name
DELTA_ONLY=".github/workflows/" # CI config: swept by delta-audit, not a per-file drydock marker

# The default list is the word list after `:-` in the `read -r -a <array> <<< "${VAR:-…}"` assignment;
# drydock's spans continuation lines, so join from the assignment to the closing `}"`.
drydock_defaults="$(awk '/^read -r -a invariant_paths <<< "\$\{DRYDOCK_INVARIANT_PATHS:-/ {p=1}
  p {print} p && /\}"/ {exit}' "$DRY" | tr '\n' ' ' | sed -e 's/.*DRYDOCK_INVARIANT_PATHS:-//' -e 's/}".*//' -e 's/\\//g')"
delta_defaults="$(sed -n 's/^read -r -a invariant <<< "\${DELTA_INVARIANT_PATHS:-\(.*\)}".*/\1/p' "$DELTA")"

read -r -a dry <<< "$drydock_defaults"
read -r -a delta <<< "$delta_defaults"

check_ne "drydock default list was extracted (extraction pattern still matches the script)" "${#dry[@]}" 0
check_ne "delta-audit default list was extracted (extraction pattern still matches the script)" "${#delta[@]}" 0

in_list() { local n="$1" x; shift; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

for p in "${dry[@]}"; do
  [ -e "$REPO_ROOT/$p" ] && pass "drydock default '$p' is a real file" || fail "drydock default '$p' is a real file" "no such path in the repo"
  if in_list "$p" $DRY_ONLY; then continue; fi
  hit=0
  for s in "${delta[@]}"; do case "$p" in *"$s"*) hit=1 ;; esac; done
  [ "$hit" = 1 ] && pass "drydock '$p' is covered by a DELTA_INVARIANT_PATHS substring" \
    || fail "drydock '$p' is covered by a DELTA_INVARIANT_PATHS substring" \
         "add a matching substring to derive.sh's default, or name it in DRY_ONLY here with a reason"
done

for s in "${delta[@]}"; do
  if in_list "$s" $DELTA_ONLY; then continue; fi
  hit=0
  for p in "${dry[@]}"; do case "$p" in *"$s"*) hit=1 ;; esac; done
  [ "$hit" = 1 ] && pass "delta-audit '$s' matches at least one DRYDOCK_INVARIANT_PATHS entry" \
    || fail "delta-audit '$s' matches at least one DRYDOCK_INVARIANT_PATHS entry" \
         "add the exact path(s) to inventory.sh's default, or name it in DELTA_ONLY here with a reason"
done

# A named exception must still be true, or it silently stops guarding anything.
in_list "keel" "${dry[@]}" && pass "DRY_ONLY 'keel' is still in the drydock list" || fail "DRY_ONLY 'keel' is still in the drydock list" "stale exception"
for x in $DRY_ONLY; do
  hit=0; for s in "${delta[@]}"; do case "$x" in *"$s"*) hit=1 ;; esac; done
  [ "$hit" = 0 ] && pass "DRY_ONLY '$x' really has no delta-audit substring" || fail "DRY_ONLY '$x' really has no delta-audit substring" "now covered; drop the exception"
done
for x in $DELTA_ONLY; do
  in_list "$x" "${delta[@]}" && pass "DELTA_ONLY '$x' is still in the delta-audit list" || fail "DELTA_ONLY '$x' is still in the delta-audit list" "stale exception"
  hit=0; for p in "${dry[@]}"; do case "$p" in *"$x"*) hit=1 ;; esac; done
  [ "$hit" = 0 ] && pass "DELTA_ONLY '$x' really matches no drydock path" || fail "DELTA_ONLY '$x' really matches no drydock path" "now covered; drop the exception"
done

summary
