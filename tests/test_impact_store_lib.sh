#!/usr/bin/env bash
# tools/lib/impact-store.sh — direct unit coverage for the dir #251 store resolver: everything else in
# the spec depends on impact_store_root()/impact_project_id() agreeing across all four consumers, so
# this file pins those two (plus the path resolvers and impact_claim_key's independence from the
# main-checkout fallback, dir #74) directly rather than only indirectly through test_keel_impact.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/impact-store.sh"
check_file "tools/lib/impact-store.sh exists" "$lib"
# shellcheck source=/dev/null
. "$lib"

# --- A1-A4 (dir #317 S1/S2/S3c) run FIRST, before any test below overrides KEEL_IMPACT_STORE/
# KEEL_HOME/etc for its own purposes — A4 pins tests/lib.sh's own harness defaults, which only reads
# true here, at the top, before this file's own later blocks shadow them (/code-review high finding:
# A4 used to run at the bottom, after an earlier block's `export KEEL_IMPACT_STORE=...` had already
# overwritten the value it meant to check, so it could never go red for a broken harness default). ---

# --- A1: impact_isolated actually isolates every S1 variable (dir #317 S2) -------------------------
rt_lib="$REPO_ROOT/tools/lib/read-trace.sh"
check_file "tools/lib/read-trace.sh exists" "$rt_lib"

a1_h="$SANDBOX/a1-home"
a1_fixture="$(new_repo)"
# Derived from IMPACT_ISOLATION_VARS, not hand-typed — a future addition to that list is automatically
# exercised as a decoy here too, the same discipline A3/A4/A5 already follow.
a1_decoys=()
for a1_var in $IMPACT_ISOLATION_VARS; do
  a1_decoys+=("$a1_var=$SANDBOX/a1-decoy-$a1_var")
done

# a1_check_no_leak LABEL — asserts none of $a1_decoys' values appear in the just-run $OUT, one check
# per decoy (shared by the three resolver checks below instead of each repeating the same loop).
a1_check_no_leak() {
  local label="$1" a1_decoy
  for a1_decoy in "${a1_decoys[@]}"; do
    check_absent "$label's output does not leak into decoy ${a1_decoy%%=*}" "$OUT" "${a1_decoy#*=}"
  done
}

run env "${a1_decoys[@]}" bash -c ". '$lib'; impact_isolated '$a1_h' impact_store_root"
check_status "A1: impact_isolated + a decoy on every S1 var → impact_store_root still succeeds" 0 "$STATUS"
check_contains "A1: impact_store_root resolves to \$h/.claude/.keel/impact" "$OUT" "$a1_h/.claude/.keel/impact"
a1_check_no_leak "A1: impact_store_root"

run env "${a1_decoys[@]}" bash -c \
  ". '$lib'; impact_isolated '$a1_h' impact_store_enable '$a1_fixture' >/dev/null; impact_isolated '$a1_h' impact_log_path '$a1_fixture'"
check_status "A1: impact_log_path on an enabled fixture resolves under impact_isolated" 0 "$STATUS"
check_contains "A1: impact_log_path resolves inside \$h's store" "$OUT" "$a1_h/.claude/.keel/impact"
a1_check_no_leak "A1: impact_log_path"

run env "${a1_decoys[@]}" bash -c ". '$lib'; . '$rt_lib'; impact_isolated '$a1_h' read_trace_store_root"
check_status "A1: read_trace_store_root succeeds under impact_isolated" 0 "$STATUS"
check_contains "A1: read_trace_store_root resolves to \$h/.claude/.keel/read-trace" "$OUT" "$a1_h/.claude/.keel/read-trace"
a1_check_no_leak "A1: read_trace_store_root"

# --- A2: impact_isolated's own mechanics (dir #317 S2) ------------------------------------------------
run bash -c ". '$lib'; a2fn() { return 3; }; impact_isolated '$SANDBOX/a2-home' a2fn"
check_status "A2: impact_isolated returns a shell function's own exit status (3)" 3 "$STATUS"

run bash -c ". '$lib'; impact_isolated '$SANDBOX/a2-home' false"
check_status "A2: impact_isolated returns an external command's own exit status" 1 "$STATUS"

run bash -c ". '$lib'; impact_isolated '' true"
check_status "A2: an empty HOME_DIR refuses with exit 2" 2 "$STATUS"

run bash -c ". '$lib'; impact_isolated 'relative/path' true"
check_status "A2: a non-absolute HOME_DIR also refuses with exit 2" 2 "$STATUS"

run env KEEL_HOME="$SANDBOX/a2-caller-keelhome" bash -c \
  ". '$lib'; impact_isolated '$SANDBOX/a2-home2' true >/dev/null; printf '%s' \"\${KEEL_HOME:-unset}\""
check_contains "A2: the caller's own KEEL_HOME survives an impact_isolated call untouched" "$OUT" "$SANDBOX/a2-caller-keelhome"

run bash -c \
  ". '$lib'; HOME=/pretend/caller-home; impact_isolated '$SANDBOX/a2-home3' true >/dev/null; printf '%s' \"\$HOME\""
check_contains "A2: the caller's own HOME survives an impact_isolated call untouched" "$OUT" "/pretend/caller-home"

# A2 regression (found live by a cross-vendor agy/Gemini review): a caller with a customized $IFS (no
# space in it) used to make the unquoted `unset $IMPACT_ISOLATION_VARS` word-split fail silently —
# `unset` got the whole list as one invalid identifier, errored on stderr, and every S1 variable
# survived untouched. impact_isolated now forces IFS to bash's own default for that one word-split.
run env KEEL_HOME="$SANDBOX/a2-ifs-decoy" bash -c \
  ". '$lib'; IFS=\$'\n'; a2fn_ifs() { printf '%s' \"\${KEEL_HOME:-isolated}\"; }; impact_isolated '$SANDBOX/a2-home4' a2fn_ifs"
check_contains "A2: a caller with IFS=\$'\\\\n' (no space) still gets real isolation, not a silent no-op" "$OUT" "isolated"
check_absent "A2: ...the decoy KEEL_HOME never leaks through under a customized IFS" "$OUT" "a2-ifs-decoy"

# --- A3: IMPACT_ISOLATION_VARS variable-coverage pin, mutation-proven (dir #317 S1) ------------------
# Every var (besides HOME) that impact_store_root, _impact_file_path, read_trace_store_root and the
# vendored secret-scan.sh's own _impact_log_path_inline copy read must be listed in
# IMPACT_ISOLATION_VARS — a new store-resolving variable anywhere is then forced onto that list or this
# test goes red. Mutated below to prove it: a resolver gaining an unlisted var must fail, and the
# extraction itself must not be satisfiable by matching nothing (that would pass A3 vacuously).
# Scope, named honestly (found by a cross-vendor agy/Gemini review): the extraction matches only a
# LITERAL `$NAME`/`${NAME` in the source, the exact form S1/S11-A3 specify and every real resolver in
# this codebase uses today — it does NOT see indirect expansion (`${!var}`) or a name built up
# dynamically (string concatenation into `eval`). A resolver written in one of those forms would read
# an unlisted variable without A3 catching it. None of the four target functions use either form
# (verified by reading them), and neither does anything else in this codebase's store resolvers.
a3_pattern='\$\{?[A-Z][A-Z0-9_]*'
# The floor vars a3_check must actually see at least once, or its own extraction is suspect (vacuous-
# pass guard) — named ONCE here, read by both a3_check itself and the "not vacuous" loop below it.
a3_floor_vars="KEEL_HOME KEEL_IMPACT_STORE KEEL_IMPACT_LOG KEEL_READ_TRACE_STORE"

# a3_check TARGETS PATTERN — TARGETS is a newline-separated "file:func" list. Extracts every var each
# target function reads (a sed range over the function body, piped through grep -E PATTERN), prints one
# var per line, and returns non-zero if any var is neither HOME nor in IMPACT_ISOLATION_VARS — OR if the
# combined extraction never saw every $a3_floor_vars entry (the guard that stops a broken PATTERN, or a
# TARGETS list that resolves nothing, from passing on zero matches).
a3_check() {
  local targets="$1" pattern="$2" spec file func var bad=0 seen=""
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    file="${spec%%:*}"; func="${spec#*:}"
    while IFS= read -r var; do
      [ -n "$var" ] || continue
      printf '%s\n' "$var"
      case " $IMPACT_ISOLATION_VARS " in
        *" $var "*) ;;
        *) [ "$var" = "HOME" ] || bad=1 ;;
      esac
      case " $a3_floor_vars " in *" $var "*) seen="$seen $var " ;; esac
    done < <(sed -n "/^${func}() {/,/^}/p" "$file" | grep -oE "$pattern" | sed -E 's/^\$\{?//' | sort -u)
  done <<< "$targets"
  for var in $a3_floor_vars; do
    case "$seen" in *" $var "*) ;; *) bad=1 ;; esac
  done
  return "$bad"
}

a3_targets="$lib:impact_store_root
$lib:_impact_file_path
$REPO_ROOT/tools/lib/read-trace.sh:read_trace_store_root
$REPO_ROOT/tools/secret-guard/secret-scan.sh:_impact_log_path_inline"

a3_vars="$(a3_check "$a3_targets" "$a3_pattern")"
check_status "A3: every var the four resolvers read is HOME or in IMPACT_ISOLATION_VARS" 0 "$?"
for a3_required in $a3_floor_vars; do
  check_contains "A3 floor: the extraction actually sees $a3_required (not vacuous)" "$a3_vars" "$a3_required"
done

# Mutation 1: a resolver reading an unlisted variable (KEEL_FOO) must go red. Only impact_store_root's
# OWN target is swapped for a mutated copy — the other three stay real (derived from $a3_targets by
# swapping just its first line, not a second hand-typed copy that could drift out of sync), so the
# floor stays satisfied and the only possible reason left for going red is the injected KEEL_FOO read.
a3_mut1="$SANDBOX/impact-store-mut1.sh"
sed 's/^impact_store_root() {/impact_store_root() { : "${KEEL_FOO:-}"/' "$lib" > "$a3_mut1"
a3_targets_mut1="$a3_mut1:impact_store_root
$(printf '%s\n' "$a3_targets" | tail -n +2)"
a3_check "$a3_targets_mut1" "$a3_pattern" >/dev/null
check_status "A3 mutation proof: a resolver reading an unlisted var (KEEL_FOO) goes red" 1 "$?"

# Mutation 2: an extraction pattern that matches nothing must ALSO go red — the floor-vars guard above
# is what stops A3 from passing vacuously if its own extraction were ever broken.
a3_check "$a3_targets" '\$NEVER_MATCHES_ANYTHING_XYZ' >/dev/null
check_status "A3 mutation proof: a broken (non-matching) extraction pattern goes red too" 1 "$?"

# --- A4: harness hygiene — every S1 variable is unset or points inside $SANDBOX (dir #317 S3c) -------
# Runs here, at the top of the file, before anything below gets a chance to override one of these for
# its own test purposes — see this section's own opening comment.
for a4_var in $IMPACT_ISOLATION_VARS; do
  a4_val="${!a4_var:-}"
  if [ -z "$a4_val" ]; then
    pass "A4: \$$a4_var is unset under the harness"
  else
    case "$a4_val" in
      "$SANDBOX"/*) pass "A4: \$$a4_var points inside \$SANDBOX ($a4_val)" ;;
      *) fail "A4: \$$a4_var points outside \$SANDBOX" "$a4_val" ;;
    esac
  fi
done

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

# ==== dir #630: keel_store_record/keel_store_recorded/keel_store_state, impact_store_create,
# impact_entry_state, impact_recorded_entries — the S4/S5/S6 generic pair + impact's own wrappers ====

# --- keel_store_record / keel_store_recorded ---------------------------------------------------
ksr_repo="$(new_repo)"
ksr_top="$(cd "$ksr_repo" && pwd -P)"
run bash -c ". '$lib'; keel_store_record k.test '/some/entry' '$ksr_top'; git -C '$ksr_top' config --local --get-all k.test"
check_status "keel_store_record writes a retrievable value" 0 "$STATUS"
check_contains "keel_store_record's value round-trips" "$OUT" "/some/entry"

run bash -c ". '$lib'; keel_store_record k.test '/some/entry' '$ksr_top'; keel_store_record k.test '/some/entry' '$ksr_top'; git -C '$ksr_top' config --local --get-all k.test | wc -l | tr -d ' '"
check_contains "keel_store_record is idempotent (no duplicate value)" "$OUT" "1"

run bash -c ". '$lib'; keel_store_recorded k.nosuch '$ksr_top'; echo \"rc=\$?\""
check_contains "keel_store_recorded on a missing key never fails the caller (rc 1 swallowed)" "$OUT" "rc=0"
check_contains "keel_store_recorded prints nothing for a missing key" "|$OUT|" "|rc=0|"

run bash -c ". '$lib'; keel_store_record k.test '/some/entry' /nonexistent/not-a-repo; echo done"
check_status "keel_store_record on a non-repo TOP is a silent no-op, never fails" 0 "$STATUS"
check_contains "keel_store_record on a non-repo TOP still reports done" "$OUT" "done"

# --- dir #630 F1: an inherited GIT_DIR/GIT_COMMON_DIR must not hijack `-C "$top"` (S4 finding) ---
# A caller process started with GIT_DIR/GIT_COMMON_DIR already set (a hook, a tool invoked from
# inside another repo's git machinery) makes git honor those over `-C "$top"` — before this fix,
# `keel_store_record`/`keel_store_recorded` silently operated on the HIJACKED repo instead of TOP.
gd_decoy="$(new_repo)"
gd_decoy_top="$(cd "$gd_decoy" && pwd -P)"
gd_top_repo="$(new_repo)"
gd_top="$(cd "$gd_top_repo" && pwd -P)"
gd_decoy_git="$gd_decoy_top/.git"

gd_cfg_before="$(cat "$gd_decoy_git/config")"
run env GIT_DIR="$gd_decoy_git" GIT_COMMON_DIR="$gd_decoy_git" bash -c \
  ". '$lib'; keel_store_record k.gd '$SANDBOX/gd-entry' '$gd_top'; echo done"
check_status "GIT_DIR hijack: keel_store_record under a decoy GIT_DIR still completes" 0 "$STATUS"
check_contains "GIT_DIR hijack: keel_store_record's caller still reports done" "$OUT" "done"
gd_cfg_after="$(cat "$gd_decoy_git/config")"
if [ "$gd_cfg_before" = "$gd_cfg_after" ]; then
  pass "GIT_DIR hijack: the decoy's .git/config is byte-identical before/after"
else
  fail "GIT_DIR hijack: the decoy's .git/config is byte-identical before/after" \
    "before=[$gd_cfg_before] after=[$gd_cfg_after]"
fi
run bash -c "git -C '$gd_top' config --local --get-all k.gd"
check_status "GIT_DIR hijack: the value landed in the real TOP's own config" 0 "$STATUS"
check_contains "GIT_DIR hijack: TOP's config holds the recorded entry" "$OUT" "$SANDBOX/gd-entry"

# --- GIT_DIR hijack with a TOP that EXISTS but is not (yet) a git repository: this, not a TOP
# missing from disk outright, is the live failure mode — `-C "$top"` only needs `chdir` to succeed
# for git to then resolve the repo from the hijacked GIT_DIR instead of $top's own (nonexistent)
# .git, regardless of what $top itself contains. A genuinely nonexistent $top is NOT an equivalent
# case and is deliberately not pinned here: verified live (git 2.52.0) that `-C` fails outright on
# the `chdir` before git ever consults GIT_DIR, hijacked or not — a mutation proof confirmed that
# variant's assertions stayed green whether or not the fix was applied, so it pinned nothing. -------
gd_notrepo="$SANDBOX/gd-not-a-repo-$$"
mkdir -p "$gd_notrepo"
gd_cfg_before2="$(cat "$gd_decoy_git/config")"
run env GIT_DIR="$gd_decoy_git" GIT_COMMON_DIR="$gd_decoy_git" bash -c \
  ". '$lib'; keel_store_record k.gd-notrepo '$SANDBOX/gd-notrepo-entry' '$gd_notrepo'; echo done"
check_status "GIT_DIR hijack + existing non-repo TOP: still completes without failing the caller" 0 "$STATUS"
gd_cfg_after2="$(cat "$gd_decoy_git/config")"
if [ "$gd_cfg_before2" = "$gd_cfg_after2" ]; then
  pass "GIT_DIR hijack + existing non-repo TOP: the decoy's .git/config stays untouched"
else
  fail "GIT_DIR hijack + existing non-repo TOP: the decoy's .git/config stays untouched" \
    "before=[$gd_cfg_before2] after=[$gd_cfg_after2]"
fi
check_nodir "GIT_DIR hijack + existing non-repo TOP: no .git materialized at TOP either" "$gd_notrepo/.git"

# --- keel_store_recorded under the same hijack: reads TOP's own value, never the decoy's ---------
run bash -c "git -C '$gd_decoy_top' config --local --add k.gd decoys-own-value"
run env GIT_DIR="$gd_decoy_git" GIT_COMMON_DIR="$gd_decoy_git" bash -c ". '$lib'; keel_store_recorded k.gd '$gd_top'"
check_contains "GIT_DIR hijack: keel_store_recorded reads TOP's recorded value" "$OUT" "$SANDBOX/gd-entry"
check_absent "GIT_DIR hijack: keel_store_recorded does not read the decoy's own value" "$OUT" "decoys-own-value"

# --- keel_store_state: enabled / lost / moved / never (the generic rungs 3-6) --------------------
kss_dir="$SANDBOX/kss-entry"
run bash -c ". '$lib'; mkdir -p '$kss_dir'; keel_store_state k.test '$kss_dir' '$ksr_top'"
check_contains "keel_store_state: entry dir exists -> enabled" "$OUT" "enabled"

run bash -c ". '$lib'; keel_store_record k.moved '$SANDBOX/kss-gone' '$ksr_top'; keel_store_state k.moved '$SANDBOX/kss-gone' '$ksr_top'"
check_contains "keel_store_state: recorded, dir absent -> lost" "$OUT" "lost"

kss_other="$SANDBOX/kss-other-entry"; mkdir -p "$kss_other"
# ENTRY ('kss-gone2') is never itself recorded here — only $kss_other is — so it can't hit `lost`
# (that rung requires ENTRY itself to be a recorded value); the only recorded value existing as a
# directory (kss_other) is what makes this `moved`, not `lost`.
run bash -c ". '$lib'; keel_store_record k.moved2 '$kss_other' '$ksr_top'; keel_store_state k.moved2 '$SANDBOX/kss-gone2' '$ksr_top'"
check_contains "keel_store_state: unrecorded entry, but another recorded value exists -> moved" "$OUT" "moved"

run bash -c ". '$lib'; keel_store_state k.nothing-recorded '$SANDBOX/kss-never' '$ksr_top'"
check_contains "keel_store_state: nothing recorded at all -> never" "$OUT" "never"

# --- impact_store_create: mkdir + the S4 record, skipped under a per-file override ---------------
isc_repo="$(new_repo)"
isc_top="$(cd "$isc_repo" && pwd -P)"
isc_store="$SANDBOX/isc-store"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$isc_store" \
  bash -c ". '$lib'; impact_store_create '$isc_repo'"
isc_id="$(printf '%s' "$isc_top" | tr '/' '-')"
check_status "impact_store_create succeeds" 0 "$STATUS"
check_dir "impact_store_create creates the entry dir" "$isc_store/$isc_id"
check_contains "impact_store_create prints the entry path" "$OUT" "$isc_store/$isc_id"
run bash -c "git -C '$isc_top' config --local --get-all keel.impactStore"
check_contains "impact_store_create records the S4 provenance value" "$OUT" "$isc_store/$isc_id"

isc_repo2="$(new_repo)"
isc_top2="$(cd "$isc_repo2" && pwd -P)"
run env -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/isc-store-2" KEEL_IMPACT_LEDGER="$SANDBOX/isc-override-ledger.md" \
  bash -c ". '$lib'; impact_store_create '$isc_repo2'"
check_status "impact_store_create still mkdir's under a per-file override" 0 "$STATUS"
run bash -c "git -C '$isc_top2' config --local --get-all keel.impactStore"
check_status "impact_store_create records NOTHING under a per-file override (S4 scope)" 1 "$STATUS"

# --- impact_entry_state: rungs 0-2 (unresolved / override / legacy) ------------------------------
ies_repo="$(new_repo)"
run env -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME bash -c ". '$lib'; impact_entry_state '$ies_repo' 2>/tmp/ies-stderr-\$\$; echo \"[stderr:\$(cat /tmp/ies-stderr-\$\$)]\"; rm -f /tmp/ies-stderr-\$\$"
check_contains "impact_entry_state rung 0: everything unset -> unresolved" "$OUT" "unresolved"
check_contains "impact_entry_state rung 0: stderr stays empty (suppressed, per S6)" "$OUT" "[stderr:]"

run env KEEL_IMPACT_STORE="$SANDBOX/ies-store" KEEL_IMPACT_LEDGER="$SANDBOX/ies-ledger.md" \
  bash -c ". '$lib'; impact_entry_state '$ies_repo'"
check_contains "impact_entry_state rung 1: a per-file override -> override" "$OUT" "override"

ies_legacy="$(new_repo)"
mkdir -p "$ies_legacy/.keel"
: > "$ies_legacy/.keel/evidence.md"
run env -u KEEL_IMPACT_LEDGER -u KEEL_IMPACT_EVIDENCE -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$SANDBOX/ies-store-2" \
  bash -c ". '$lib'; impact_entry_state '$ies_legacy'"
check_contains "impact_entry_state rung 2: an in-tree legacy file -> legacy" "$OUT" "legacy"

# --- impact_recorded_entries: prints recorded values, one per line -------------------------------
ire_repo="$(new_repo)"
ire_top="$(cd "$ire_repo" && pwd -P)"
run bash -c ". '$lib'; keel_store_record keel.impactStore '$SANDBOX/ire-1' '$ire_top'; keel_store_record keel.impactStore '$SANDBOX/ire-2' '$ire_top'; impact_recorded_entries '$ire_repo'"
check_contains "impact_recorded_entries lists the first recorded value" "$OUT" "$SANDBOX/ire-1"
check_contains "impact_recorded_entries lists the second recorded value" "$OUT" "$SANDBOX/ire-2"

# --- spec §9 V4: a read-only .git/config degrades to "no record", never a hard failure (S4: "any
# failure is ignored"). Skipped on a root CI runner, where chmod is a no-op for the root reader (the
# project's own documented Linux-leg trap 2) — the platform-independent half (no crash, rc 0 either
# way) still runs unconditionally below. ------------------------------------------------------------
v4_repo="$(new_repo)"
v4_top="$(cd "$v4_repo" && pwd -P)"
run bash -c ". '$lib'; keel_store_record k.v4 '/some/entry' '$v4_top'; echo done"
check_status "V4: keel_store_record never fails the caller, even a healthy write" 0 "$STATUS"
check_contains "V4: keel_store_record's caller still completes" "$OUT" "done"

if [ "$(id -u 2>/dev/null)" != 0 ]; then
  # V4 escape, found live: `chmod 444` on the FILE alone does NOT reproduce "read-only .git/config" —
  # `git config --add` writes via a lock file (`config.lock`) then renames it over `config`, and a
  # rename only needs WRITE permission on the containing DIRECTORY, never the target file's own bits
  # (reproduced live: a 444 `.git/config` still accepted a new value). The read-only DIRECTORY is what
  # actually blocks it (`error: could not lock config file .git/config: Permission denied`, rc 255).
  v4_cfg="$v4_top/.git/config"
  v4_before="$(cat "$v4_cfg")"
  chmod 555 "$v4_top/.git"
  run bash -c ". '$lib'; keel_store_record k.v4ro '/some/other/entry' '$v4_top'; echo done"
  chmod 755 "$v4_top/.git"   # restore so cleanup can remove the sandbox
  check_status "V4: a read-only .git/ dir never fails the caller" 0 "$STATUS"
  check_contains "V4: the caller still completes despite the write failing" "$OUT" "done"
  run bash -c "git -C '$v4_top' config --local --get-all k.v4ro 2>&1"
  check_status "V4: nothing was recorded through the read-only .git/ dir" 1 "$STATUS"
  v4_after="$(cat "$v4_cfg")"
  if [ "$v4_before" = "$v4_after" ]; then
    pass "V4: the read-only config's own content is unchanged"
  else
    fail "V4: the read-only config's own content is unchanged" "before=[$v4_before] after=[$v4_after]"
  fi
fi

summary
