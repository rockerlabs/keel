#!/usr/bin/env bash
# tools/lib/impact-store.sh — direct unit coverage for the dir #251 store resolver: everything else in
# the spec depends on impact_store_root()/impact_project_id() agreeing across all four consumers, so
# this file pins those two (plus the path resolvers and impact_claim_key's independence from the
# main-checkout fallback, dir #74) directly rather than only indirectly through test_keel_impact.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lib="$REPO_ROOT/tools/lib/impact-store.sh"
check_file "tools/lib/impact-store.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# --- impact_store_root: KEEL_IMPACT_STORE wins outright; else $KEEL_HOME/.keel/impact -------------
store_home="$SANDBOX/store-home"
run env -u KEEL_IMPACT_STORE KEEL_HOME="$store_home" bash -c ". '$lib'; impact_store_root"
check_status "impact_store_root uses KEEL_HOME/.keel/impact by default" 0 "$STATUS"
check_contains "impact_store_root uses KEEL_HOME/.keel/impact by default" "$OUT" "$store_home/.keel/impact"

run env KEEL_IMPACT_STORE="$SANDBOX/explicit-store" bash -c ". '$lib'; impact_store_root"
check_contains "KEEL_IMPACT_STORE overrides the store root outright" "$OUT" "$SANDBOX/explicit-store"

# --- impact_project_id: path-slug of the MAIN checkout's physical top, '/' -> '-' -----------------
proj="$(new_repo)"
proj_p="$(cd "$proj" && pwd -P)"
want_id="$(printf '%s' "$proj_p" | tr '/' '-')"
run bash -c ". '$lib'; impact_project_id '$proj'"
check_status "impact_project_id succeeds on a plain repo" 0 "$STATUS"
check_contains "impact_project_id is the physical-path slug ('/' -> '-')" "$OUT" "$want_id"

# not-yet-git dir: falls back to the dir's own physical path (same fallback cmd_enable always had)
ngdir="$(mktemp -d "$SANDBOX/nogit.XXXXXX")"
ngdir_p="$(cd "$ngdir" && pwd -P)"
want_ng_id="$(printf '%s' "$ngdir_p" | tr '/' '-')"
run bash -c ". '$lib'; impact_project_id '$ngdir'"
check_contains "impact_project_id on a not-yet-git dir falls back to its own physical path" "$OUT" "$want_ng_id"

# a linked worktree resolves to the SAME id as its main checkout (the whole point of D2/D1: no more
# per-tree divergence, dir #181's bug class becomes unrepresentable)
wrepo="$(new_repo)"
git -C "$wrepo" commit -q --allow-empty -m init
wwt="$SANDBOX/linked-wt"
git -C "$wrepo" worktree add -q -b wt-branch "$wwt" >/dev/null 2>&1
run bash -c ". '$lib'; impact_project_id '$wrepo'"
main_id="$OUT"
run bash -c ". '$lib'; impact_project_id '$wwt'"
check_contains "a linked worktree resolves to the SAME project id as its main checkout" "$OUT" "$main_id"

# --- impact_claim_key: dir #74 — the CALLER's own worktree top, never main-top'd ------------------
run bash -c ". '$lib'; impact_claim_key '$wwt'"
wwt_p="$(cd "$wwt" && pwd -P)"
check_contains "impact_claim_key returns the worktree's OWN top, not the main checkout's" "$OUT" "$wwt_p"
wrepo_p="$(cd "$wrepo" && pwd -P)"
run bash -c ". '$lib'; impact_claim_key '$wrepo'"
check_contains "impact_claim_key on the main checkout returns its own top" "$OUT" "$wrepo_p"

# --- impact_enabled / impact_store_dir / impact_store_enable ---------------------------------------
store_root="$SANDBOX/claim-store"
export KEEL_IMPACT_STORE="$store_root"
erepo="$(new_repo)"
run bash -c ". '$lib'; impact_enabled '$erepo'; echo \$?"
check_contains "a fresh repo is not enabled" "$OUT" "1"

run bash -c ". '$lib'; impact_store_enable '$erepo'"
check_status "impact_store_enable succeeds" 0 "$STATUS"
erepo_p="$(cd "$erepo" && pwd -P)"
erepo_id="$(printf '%s' "$erepo_p" | tr '/' '-')"
check_dir "impact_store_enable creates the store dir" "$store_root/$erepo_id"
check_file "impact_store_enable writes an origin file" "$store_root/$erepo_id/origin"
check_contains "origin names the project's physical top" "$(cat "$store_root/$erepo_id/origin")" "$erepo_p"
check_nofile "impact_store_enable writes NOTHING inside the project tree" "$erepo/.keel/ledger.md"
run bash -c ". '$lib'; impact_enabled '$erepo'; echo \$?"
check_contains "the project is enabled after impact_store_enable" "$OUT" "0"

# idempotent: a second enable does not error and refreshes origin
run bash -c ". '$lib'; impact_store_enable '$erepo'"
check_status "impact_store_enable is idempotent" 0 "$STATUS"

# --- impact_store_dir fails CLOSED when impact_store_root can't resolve, never a bogus root path ---
# regression (dir #251 review): impact_store_root's `${HOME:?...}` used to fire inside a nested command
# substitution embedded directly in impact_store_dir's own printf args — a failure there did NOT stop
# the printf from running, so impact_store_dir silently returned "/<project-id>" (empty root + '/' +
# slug) instead of failing. A caller doing `mkdir -p "$(impact_store_dir ...)"` (impact_store_enable
# itself, keel-impact.sh's `migrate`) would then create a directory at the filesystem root.
noroot_repo="$(new_repo)"
run env -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME bash -c "set -e; . '$lib'; impact_store_dir '$noroot_repo'"
check_status "impact_store_dir fails (nonzero) when HOME can't resolve, not silently" 1 "$STATUS"
check_contains "impact_store_dir's failure names the real cause (unset HOME), not a bogus path" "$OUT" "set HOME, or export KEEL_HOME"
noroot_p="$(cd "$noroot_repo" && pwd -P)"
noroot_id="$(printf '%s' "$noroot_p" | tr '/' '-')"
check_nodir "no bogus root-level directory was created for the failed resolution" "/$noroot_id"

# impact_store_enable itself: the bare `store="$(impact_store_dir "$dir")"` assignment now correctly
# propagates the failure under keel-impact.sh's own `set -e` instead of masking it (verified at the
# lib level here since impact_store_enable is a direct, unguarded call in keel-impact.sh's cmd_enable).
run env -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME bash -c "set -e; . '$lib'; impact_store_enable '$noroot_repo'"
check_status "impact_store_enable fails (nonzero) when HOME can't resolve" 1 "$STATUS"
check_nodir "impact_store_enable creates no bogus root-level directory either" "/$noroot_id"

# --- impact_ledger_path / impact_evidence_path / impact_log_path -----------------------------------
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$store_root" \
  bash -c ". '$lib'; impact_ledger_path '$erepo'"
check_contains "impact_ledger_path resolves into the store once enabled" "$OUT" "$store_root/$erepo_id/ledger.md"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$store_root" \
  bash -c ". '$lib'; impact_evidence_path '$erepo'"
check_contains "impact_evidence_path resolves into the store once enabled" "$OUT" "$store_root/$erepo_id/evidence.md"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$store_root" \
  bash -c ". '$lib'; impact_log_path '$erepo'"
check_contains "impact_log_path resolves into the store once enabled" "$OUT" "$store_root/$erepo_id/impact-events.log"

# a NOT-enabled repo resolves to empty (never Keel's own docs/keel-impact.md — that fallback is gone)
frepo="$(new_repo)"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$store_root" \
  bash -c ". '$lib'; impact_ledger_path '$frepo'"
check_status "impact_ledger_path on a not-enabled repo exits 0 (never errors)" 0 "$STATUS"
check_contains "impact_ledger_path on a not-enabled repo prints nothing" "|$OUT|" "||"

# explicit env override always wins, even when the project IS enabled
run env KEEL_IMPACT_LEDGER="$SANDBOX/explicit-ledger.md" KEEL_IMPACT_STORE="$store_root" \
  bash -c ". '$lib'; impact_ledger_path '$erepo'"
check_contains "KEEL_IMPACT_LEDGER overrides the store path outright" "$OUT" "$SANDBOX/explicit-ledger.md"

# a legacy in-tree marker (pre-migration) still resolves the LOG so a guard hook's behaviour doesn't
# change mid-transition, before enable/migrate/auto-migrate has moved it (dir #251 D4). The gitignore
# line is what makes this a GENUINE old-style `enable` marker, not just a bare `.keel/` dir — see the
# next block for why that distinction is load-bearing.
lrepo="$(new_repo)"
mkdir -p "$lrepo/.keel"
printf '/.keel/impact-events.log\n' >> "$lrepo/.gitignore"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/unused-store" \
  bash -c ". '$lib'; impact_log_path '$lrepo'"
check_contains "impact_log_path falls back to a legacy in-tree marker when not yet migrated" "$OUT" "$lrepo/.keel/impact-events.log"

# dir #251 review finding: a `.keel/` holding ONLY a D3 role-3 file (doctor-accept/map-drift-baseline —
# legitimate for a project that never ran impact tracking, e.g. scaffolded with --no-impact) must NOT
# be mistaken for an old-style marker — resolving `ledger.md` there would make `add` write a brand-new
# impact ledger INTO the project's own tree, the exact leak this ticket exists to close.
rrepo="$(new_repo)"
mkdir -p "$rrepo/.keel"
printf 'H-DEP-FLOATING\n' > "$rrepo/.keel/doctor-accept"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/unused-store-2" \
  bash -c ". '$lib'; impact_ledger_path '$rrepo'"
check_contains "a role-3-only .keel/ (no gitignore line) never resolves as a legacy impact marker" "|$OUT|" "||"

# dir #251 review round 2 (opus second opinion): an UNRELATED broad gitignore pattern (`*.log`, common
# in real adopter repos) must NOT be mistaken for the EXACT line `enable` writes — `git check-ignore`
# answers "is this path ignored by ANYTHING" and would wrongly say yes here, reopening the same leak
# with no `enable` involved at all. Only the literal `/.keel/impact-events.log` line counts.
grepo="$(new_repo)"
mkdir -p "$grepo/.keel"
printf 'H-DEP-FLOATING\n' > "$grepo/.keel/doctor-accept"
printf '*.log\n' > "$grepo/.gitignore"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/unused-store-3" \
  bash -c ". '$lib'; impact_ledger_path '$grepo'"
check_contains "an unrelated broad ignore pattern (*.log) does not fool the legacy-marker discriminator" "|$OUT|" "||"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/unused-store-3" \
  bash -c ". '$lib'; impact_log_path '$grepo'"
check_contains "...same for impact_log_path (the one guardrail hooks actually use)" "|$OUT|" "||"

# --- impact_has_legacy_files / IMPACT_LEGACY_NAMES (shared by doctor.sh's W-KEEL-LEGACY and migrate) --
run bash -c ". '$lib'; printf '%s' \"\$IMPACT_LEGACY_NAMES\""
check_contains "IMPACT_LEGACY_NAMES names all three impact files" "$OUT" "ledger.md"
check_contains "IMPACT_LEGACY_NAMES names all three impact files" "$OUT" "evidence.md"
check_contains "IMPACT_LEGACY_NAMES names all three impact files" "$OUT" "impact-events.log"

run bash -c ". '$lib'; impact_has_legacy_files '$lrepo'; echo \$?"
check_contains "impact_has_legacy_files is false on an empty .keel/" "$OUT" "1"
: > "$lrepo/.keel/evidence.md"
run bash -c ". '$lib'; impact_has_legacy_files '$lrepo'; echo \$?"
check_contains "impact_has_legacy_files is true once one legacy file exists" "$OUT" "0"
rm -f "$lrepo/.keel/evidence.md"

# --- _impact_resolve_top: repeated calls with the SAME dir return the SAME value, and a DIFFERENT
# dir resolves independently (dir #251 review: an earlier version tried a single-slot memoization
# cache here — it was dead code, since every call goes through `$(...)` command substitution, whose
# subshell discards any cache-variable write before the parent ever sees it; removed rather than
# fixed, see the function's own comment for why a real fix is a bigger, separate change). This test
# only pins CORRECTNESS (repeat = same answer, different dir = different answer), not caching. ------
other_repo="$(new_repo)"
run bash -c ". '$lib'
  a=\"\$(_impact_resolve_top '$erepo')\"
  b=\"\$(_impact_resolve_top '$erepo')\"
  c=\"\$(_impact_resolve_top '$other_repo')\"
  [ \"\$a\" = \"\$b\" ] || { echo 'MISMATCH a!=b'; exit 1; }
  [ \"\$a\" = \"\$c\" ] && { echo 'MISMATCH c matches a'; exit 1; }
  echo ok"
check_contains "_impact_resolve_top is correct across repeat and different-dir calls" "$OUT" "ok"
unset KEEL_IMPACT_STORE

summary
