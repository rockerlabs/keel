#!/usr/bin/env bash
# tests/test_keel_ab_seed.sh — dir #424: regression coverage for docs/keel-ab/seed.sh's re-land,
# pinning the four S8-ab-extension findings (FINDING-S8-1..4) plus CA2-blind's FINDING-3, none of
# which had any test coverage before this ticket. Each case below reproduces the exact live
# repro used to find the bug (see private/audit/delta-0.8.3-0.9.0/reports/{CA2-blind,
# S8-ab-extension}.md) and checks the FIXED behavior, not just "doesn't crash".
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

seed="$REPO_ROOT/docs/keel-ab/seed.sh"
check_file "docs/keel-ab/seed.sh exists" "$seed"

# --- FINDING-3: a bad --with-keel path must fail BEFORE any mutation lands on disk --------------
tgt="$SANDBOX/f3-target"
run bash "$seed" "$tgt" --with-keel "$SANDBOX/does-not-exist-CORE.md"
check_status "bad --with-keel path exits nonzero" 2 "$STATUS"
check_nodir "bad --with-keel path leaves no target directory at all (no mkdir/git init happened)" "$tgt"

# --- FINDING-S8-2: a non-empty target must be refused, not silently folded into the seed commit -
tgt="$SANDBOX/dirty-target"
mkdir -p "$tgt"
echo "PRE-EXISTING UNCOMMITTED WORK" > "$tgt/wip-secret.txt"
run bash "$seed" "$tgt"
check_status "non-empty target exits nonzero" 2 "$STATUS"
check_nodir "non-empty target is never git-init'd" "$tgt/.git"
check_file "non-empty target's pre-existing file is untouched" "$tgt/wip-secret.txt"

# --- exit-code consistency: a missing <target-dir> must fail the same way (exit 2) as every other
# validation error below, not bash's own ${1:?msg} exit 1 (found by an independent reviewer during
# this same round) ---------------------------------------------------------------------------------
run bash "$seed"
check_status "missing target-dir exits 2, same as every other validation error" 2 "$STATUS"

# --- --with-keel pointing at a directory (not a regular file) must error with a clear message,
# not an uncaught `cp` failure under set -e (found by an independent reviewer during this round) ---
tgt="$SANDBOX/dir-as-core-target"
run bash "$seed" "$tgt" --with-keel "$SANDBOX"
check_status "--with-keel pointing at a directory exits nonzero" 2 "$STATUS"
check_contains "the error names it as not a regular file, not a raw cp failure" "$OUT" "not a regular file"

# --- FINDING-S8-3: an unrecognized second argument must error, never silently produce a cold arm
tgt="$SANDBOX/typo-target"
core="$SANDBOX/CORE.md"
echo "# fake core" > "$core"
run bash "$seed" "$tgt" --with-keeel "$core"
check_status "typo'd flag exits nonzero" 2 "$STATUS"
check_nofile "typo'd flag never produces a CLAUDE.md (would silently be a cold arm)" "$tgt/CLAUDE.md"

# --- FINDING-S8-4: --help/-h must print real usage naming seed.sh, not fall through to mkdir ----
run bash "$seed" --help
check_status "--help exits 0" 0 "$STATUS"
check_contains "--help output names seed.sh's own usage" "$OUT" "Usage: seed.sh"
run bash "$seed" -h
check_status "-h exits 0" 0 "$STATUS"
check_contains "-h output names seed.sh's own usage" "$OUT" "Usage: seed.sh"

# --- FINDING-S8-1: the sibling `.origin.git` write must be disclosed AND covered by the same
# non-empty-target guard as the primary target — occupying only the sibling path must still refuse,
# before either path is mutated ------------------------------------------------------------------
tgt="$SANDBOX/sibling-occupied-target"
mkdir -p "$tgt.origin.git"
echo "unrelated pre-existing content" > "$tgt.origin.git/not-a-clone.txt"
run bash "$seed" "$tgt"
check_status "occupied sibling .origin.git path exits nonzero" 2 "$STATUS"
check_nodir "primary target is never created when only its sibling is occupied" "$tgt"
check_file "the sibling's pre-existing content is untouched" "$tgt.origin.git/not-a-clone.txt"

# --- sanity: a correct run still works end-to-end, --with-keel included -------------------------
tgt="$SANDBOX/good-target"
run bash "$seed" "$tgt" --with-keel "$core"
check_status "good run exits 0" 0 "$STATUS"
check_file "good run writes CLAUDE.md from --with-keel" "$tgt/CLAUDE.md"
check_file "good run writes the relmon skeleton (config.sh)" "$tgt/config.sh"
check_dir "good run's sibling bare origin lands next to (not inside) the target (FINDING-S8-1)" "$tgt.origin.git"

summary
