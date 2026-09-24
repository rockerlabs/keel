# shellcheck shell=bash
# tools/lib/impact-store.sh — resolves WHERE the impact-score triple (ledger.md, evidence.md,
# impact-events.log) lives for a given project (dir #251).
#
# Before this file, that triple lived inside the project's OWN working tree (a `.keel/` marker every
# consuming repo had to know about, gitignore, and avoid committing — two adopter repos committed it
# into git history by mistake, following this tool's own OLD advice to do so). Now the triple lives
# at an external store, keyed by the project's MAIN checkout's physical path — the same shape KB.16
# already used to fix the identical failure for `kb-memory`.
#
# Sourced, not executed — no shebang requirement, no `set -e` (inherits the caller's).
#
# Store layout: $(impact_store_root)/<project-id>/{ledger.md,evidence.md,impact-events.log,origin}.
# <project-id> = the path-slug of the project's main-checkout top (D2): physical path, every '/' ->
# '-' — the same transform ~/.claude/projects/ already uses. `origin` holds the one physical path the
# id was derived from, for orphan detection (a store entry whose origin no longer exists on disk).
#
# Env overrides:
#   KEEL_IMPACT_STORE    overrides the store ROOT outright — required for test isolation.
#   KEEL_HOME             overrides $HOME_DIR the same way install.sh's own resolution does
#                          (${KEEL_HOME:-$HOME/.claude}) — mirrored here, not reinvented. keel-impact.sh
#                          gains no `--home` of its own; KEEL_HOME/KEEL_IMPACT_STORE cover every case.
#   KEEL_IMPACT_LEDGER / KEEL_IMPACT_EVIDENCE / KEEL_IMPACT_LOG   explicit per-file overrides, unchanged
#                          from before this ticket — still win over the store outright.
#
# Both KEEL_IMPACT_STORE and KEEL_HOME outrank $HOME outright: a caller that sets $HOME alone is NOT
# isolated from either one (dir #290 found this the hard way — a sandbox that only pointed $HOME
# elsewhere still had its impact events land in the real store). dir #317's impact_isolated (below) is
# the one supported way to isolate a call: it unsets every variable this file's resolvers read, not
# just these two.
#
# A project is "enabled" iff a store dir already exists for its id. Every path resolver below is
# read-only (no writes, no mutation) and never errors: empty output means "no explicit override, and
# this project isn't enabled" — refusing on that (keel-impact.sh's `add`/`rollup`) vs. silently doing
# nothing (a guardrail hook recording a fire) is each caller's own decision, not this file's.

# dir #415: _impact_main_top/_impact_resolve_top (below) delegate to tools/lib/repo-top.sh's
# keel_repo_main_top/keel_repo_top instead of each carrying its own copy of the fallback chain — see
# repo-top.sh's own header for why (and why NOT onto tools/lib/transcript-usage.sh's tu_repo_top
# directly, an earlier version of this fix's own rejected approach).
# shellcheck source=tools/lib/repo-top.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repo-top.sh"

# _impact_main_top [DIR] — the MAIN checkout's top for DIR (default cwd), delegating to
# tools/lib/repo-top.sh's keel_repo_main_top (dir #415) — kept under this name since
# tools/self/citation-resolvability.sh still calls it directly.
_impact_main_top() {
  keel_repo_main_top "${1:-.}"
}

# _impact_resolve_top [DIR] — the physical path a project's id is derived from, delegating to
# tools/lib/repo-top.sh's keel_repo_top (dir #415): the main checkout's top; else (a bare-main
# topology) DIR's own toplevel; else (DIR is not a git repo yet) DIR's own physical path. Mirrors
# keel-impact.sh's pre-store `cmd_enable` fallback chain exactly, so a project that could `enable`
# before dir #251 can still `enable` now. See keel_repo_top's own comment for why this isn't memoized.
_impact_resolve_top() {
  keel_repo_top "${1:-.}"
}

# impact_project_id [DIR] — D2: the path-slug of DIR's resolved top (physical path, every '/' -> '-').
# Deterministic, reversible, needs no registry and no hashing utility — the tradeoff D2 accepted over
# those: a `-` in a real directory NAME is indistinguishable from a converted `/`, so two projects at
# genuinely ambiguous paths (e.g. `/a/b-c` and `/a-b/c`, both slugging to `-a-b-c`) collide. Narrow in
# practice (it needs two real repos at exactly that shape), not worth a heavier scheme for.
impact_project_id() {
  printf '%s' "$(_impact_resolve_top "${1:-.}")" | tr '/' '-'
}

# impact_claim_key [DIR] — dir #74: THIS producer's own worktree top, NEVER main-top'd. Decides WHO
# fired an event, not where the file lives — must stay independent of every fallback above.
impact_claim_key() {
  git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || true
}

# impact_store_root — D1: $HOME_DIR/.keel/impact, or $KEEL_IMPACT_STORE verbatim when set. $HOME is
# required only on the fallback path (mirrors install.sh's own `${HOME:?...}` placement) so a caller
# that always sets KEEL_HOME or KEEL_IMPACT_STORE never needs $HOME under `set -u`. KEEL_IMPACT_STORE
# and KEEL_HOME both outrank HOME outright (dir #290: setting HOME alone does NOT isolate a caller from
# either) — impact_isolated (below) is the one supported way to isolate a call from every override this
# file's resolvers read, not just these two.
impact_store_root() {
  if [ -n "${KEEL_IMPACT_STORE:-}" ]; then printf '%s' "$KEEL_IMPACT_STORE"; return; fi
  printf '%s/.keel/impact' "${KEEL_HOME:-${HOME:?impact-store: set HOME, or export KEEL_HOME}/.claude}"
}

# IMPACT_ISOLATION_VARS — every environment variable, other than HOME, that any keel store resolver
# reads: impact_store_root above, _impact_file_path below, tools/lib/read-trace.sh's
# read_trace_store_root, and the vendored tools/secret-guard/secret-scan.sh's own
# _impact_log_path_inline copy. Named in this ONE place (dir #317) so impact_isolated (below) — and any
# future caller that wants a truly sandboxed store root — unsets the whole list, not just whichever two
# variables a fix happens to know about at the time: the exact class of miss that let dir #290's own
# canary leak (E11: KEEL_IMPACT_LOG stayed unblanked in its printed command). A new store-resolving
# variable anywhere must be added here; tests/test_impact_store_lib.sh's A3 pins that with a mutation
# proof, so a resolver that starts reading an unlisted variable fails the suite.
IMPACT_ISOLATION_VARS="KEEL_HOME KEEL_IMPACT_STORE KEEL_IMPACT_LEDGER KEEL_IMPACT_EVIDENCE KEEL_IMPACT_LOG KEEL_READ_TRACE_STORE"

# impact_isolated HOME_DIR CMD [ARG…] — dir #317: the ONE way to run CMD (a shell function or an
# external command) fully isolated from every ambient keel store override, without a caller having to
# remember which variables that means. Runs CMD in a subshell with HOME=HOME_DIR exported and every
# IMPACT_ISOLATION_VARS variable unset (not merely blanked — every resolver's `${VAR:-}` form treats an
# empty value the same as unset, but unsetting is the more explicit contract and costs nothing here).
# The subshell already keeps the caller's own environment untouched afterwards, so there is nothing to
# save and restore. Refuses with return 2 and one stderr line when HOME_DIR is empty or not absolute,
# rather than silently isolating into a relative path whose meaning would depend on the caller's cwd.
impact_isolated() {
  local home_dir="$1"
  case "$home_dir" in
    /*) : ;;
    *) printf 'impact_isolated: HOME_DIR must be a non-empty absolute path (got %s)\n' "$home_dir" >&2; return 2 ;;
  esac
  shift
  # shellcheck disable=SC2086  # IMPACT_ISOLATION_VARS is deliberately word-split here: a space-
  # separated list of variable NAMES, exactly the form `unset` itself takes (same convention
  # IMPACT_LEGACY_NAMES below uses for `impact_has_legacy_files`'s file-name list). IFS is forced to
  # bash's own default (space/tab/newline) for that split — found live by a cross-vendor review
  # (agy/Gemini): a caller with a customized $IFS (e.g. a line-based parser doing IFS=$'\n' right
  # before calling this) would otherwise hand `unset` the WHOLE list as one invalid identifier —
  # `unset` errors on stderr but does not abort (no `set -e` here), so every S1 variable then survives
  # UNTOUCHED, silently defeating the one guarantee this function exists to make. Scoped to the
  # subshell only, so it cannot itself change the caller's own $IFS (see A2's own test for this).
  ( IFS=$' \t\n'; unset $IMPACT_ISOLATION_VARS; export HOME="$home_dir"; "$@" )
}

# impact_store_dir [DIR] — the store directory for DIR's project (computed; existence not checked).
# `root="$(impact_store_root)" || return 1` (dir #251 review): impact_store_root's `${HOME:?...}` fires
# inside that nested command substitution's own subshell, which does NOT abort a printf that merely
# embeds the substitution as one of several arguments — the printf's own exit status is what a caller's
# `set -e` sees, and printf succeeds regardless. Capturing the substitution as its own statement first
# lets its failure propagate explicitly, instead of this function silently returning the malformed
# "/<project-id>" (empty root + "/" + slug) that a caller doing `mkdir -p "$(impact_store_dir ...)"`
# (e.g. impact_store_enable below, keel-impact.sh's own `migrate`) would otherwise create at the
# filesystem root.
impact_store_dir() {
  local root
  root="$(impact_store_root)" || return 1
  printf '%s/%s' "$root" "$(impact_project_id "${1:-.}")"
}

# impact_enabled [DIR] — true iff a store entry already exists for DIR's project.
impact_enabled() {
  [ -d "$(impact_store_dir "${1:-.}")" ]
}

# impact_ledger_path / impact_evidence_path / impact_log_path [DIR] — resolve one file. Precedence:
# (1) the matching env override, always; (2) a legacy in-tree `.keel/<file>` when THAT SPECIFIC FILE is
# still physically there — a repo D4 deliberately leaves untouched (a TRACKED legacy ledger/evidence,
# e.g. social-media/affiliate-lab) must keep resolving and working exactly as it did before this
# ticket, not go dark; (3) the store path, if the project is enabled; (4) a legacy in-tree `.keel/<file>`
# when a marker exists but neither the file nor a store entry does yet — a marker-enabled-but-not-yet-
# scored repo must still resolve a not-yet-created ledger.md to its would-be legacy path (ensure_ledger
# creates it on first write); (5) empty. Never errors — an empty result IS the "not enabled at all"
# signal (no store, no legacy marker either), which is the one case keel-impact.sh's `add`/`rollup`
# refuse on.
#
# Checking THE FILE's own presence (2) BEFORE the store (3) — not just whether the project's store
# DIRECTORY exists — matters because `migrate`/keel-impact.sh's own auto-migration support PARTIAL
# migration: one file (say, the untracked log) can move into the store while another (a tracked
# ledger/evidence, left in place on purpose) stays at its legacy path. Once ANY file moves, the store
# directory exists — so a precedence that only asked "does the store dir exist" would flip EVERY file's
# resolution to the store the moment ANY one of them moved, silently orphaning the still-tracked file's
# real history in a brand-new, empty store copy instead. Found live by an operator-run max-depth review
# reproducing exactly that: `add` after a partial migrate wrote into an empty store ledger while the
# tracked in-tree ledger.md — the one `migrate`'s own message promised would keep working — never
# received another row.
impact_ledger_path() { _impact_file_path ledger.md "${1:-.}"; }
impact_evidence_path() { _impact_file_path evidence.md "${1:-.}"; }
impact_log_path() { _impact_file_path impact-events.log "${1:-.}"; }
_impact_file_path() {
  local name="$1" dir="$2" override_var store top
  case "$name" in
    ledger.md) override_var="${KEEL_IMPACT_LEDGER:-}" ;;
    evidence.md) override_var="${KEEL_IMPACT_EVIDENCE:-}" ;;
    impact-events.log) override_var="${KEEL_IMPACT_LOG:-}" ;;
  esac
  if [ -n "$override_var" ]; then printf '%s' "$override_var"; return; fi
  top="$(_impact_resolve_top "$dir")"
  if [ -n "$top" ] && [ -f "$top/.keel/$name" ]; then printf '%s/.keel/%s' "$top" "$name"; return; fi
  store="$(impact_store_dir "$dir")"
  if [ -d "$store" ]; then printf '%s/%s' "$store" "$name"; return; fi
  # Step 4's marker-but-not-yet-scored fallback must NOT fire on a bare `[ -d "$top/.keel" ]` — D3's own
  # `.keel/doctor-accept`/`map-drift-baseline` are project-local by design and can legitimately be the
  # ONLY thing in `.keel/` for a project that never ran impact tracking at all (including one scaffolded
  # with `--no-impact`). Treating that directory's mere existence as "an old-style marker" would make
  # `add`/a guardrail hook write a brand-new ledger.md/evidence.md/impact-events.log INTO the project's
  # own tree — precisely the leak this ticket exists to close, just via a different trigger. The
  # positive, reliable signal that a repo genuinely ran the PRE-#251 `enable` is that EXACT ignore line
  # it always appended, byte-for-byte — found live by an operator-run max-depth review, reproduced
  # against a `.keel/` holding only `map-drift-baseline`. NOT `git check-ignore` (a SECOND review round
  # caught this): that asks "is this path ignored by ANYTHING", which a common, unrelated pattern like
  # `*.log` in the adopter's own `.gitignore` would also satisfy, reopening the exact leak with no
  # `enable` involved at all. `grep -qxF` matches only the literal line `enable` itself wrote, mirroring
  # the exact idempotency check its own old `cmd_enable` used before this ticket removed it.
  [ -n "$top" ] && [ -f "$top/.gitignore" ] && grep -qxF '/.keel/impact-events.log' "$top/.gitignore" 2>/dev/null && \
    printf '%s/.keel/%s' "$top" "$name"
  return 0
}

# IMPACT_LEGACY_NAMES — the impact-triple's filenames, relative to a project's `.keel/`, named in this
# ONE place so `doctor.sh`'s W-KEEL-LEGACY check and keel-impact.sh's `migrate`/auto-migrate don't each
# hand-list the same three strings independently.
IMPACT_LEGACY_NAMES="ledger.md evidence.md impact-events.log"

# impact_has_legacy_files [DIR] [TOP] — true iff DIR's project has at least one in-tree
# .keel/{ledger.md,evidence.md,impact-events.log} left over from before the external store existed.
# TOP, when given, is used as-is instead of re-resolving it — the same avoid-a-redundant-fork
# convention _impact_file_path already follows (see _impact_resolve_top's own header comment): a
# caller that already has DIR's resolved top in hand (impact_store_enable does) should pass it
# through rather than pay for a second `_impact_resolve_top` subshell to re-derive the same value.
impact_has_legacy_files() {
  local dir="${1:-.}" top="${2:-}" name
  [ -n "$top" ] || top="$(_impact_resolve_top "$dir")"
  [ -n "$top" ] || return 1
  for name in $IMPACT_LEGACY_NAMES; do
    [ -f "$top/.keel/$name" ] && return 0
  done
  return 1
}

# impact_store_mark_migrated STORE TOP — dir #304: the ONE place that writes $STORE/origin, the
# signal `_impact_auto_migrate`, `cmd_migrate`, and `impact_store_enable` all use to mean "this store
# entry is fully migrated" (and, per D1's own comment at the top of this file, the provenance record
# orphan-detection reads). Before this ticket the three call sites each wrote the file directly and
# unconditionally, which is how two of them (cmd_migrate, impact_store_enable) ended up writing it
# BEFORE confirming the merge it is supposed to attest to actually succeeded — a genuine merge failure
# then permanently satisfied _impact_auto_migrate's own idempotency guard ([-f "$store/origin"], dir
# #289) and killed automatic retry for that project. This function does not decide success; it is a
# pure writer. Every caller is responsible for calling it only once IT has confirmed there is nothing
# left un-migrated (or, for impact_store_enable, that there was never anything to migrate in the first
# place) — see each call site's own comment.
impact_store_mark_migrated() {
  local store="$1" top="$2"
  printf '%s\n' "$top" > "$store/origin"
}

# impact_store_enable [DIR] — idempotently create/refresh the store entry for DIR's project (the
# opt-in marker itself) and print its path. Nothing is ever written inside DIR's own working tree.
#
# dir #304: `origin` is written only when DIR carries no in-tree legacy file at all — i.e. either this
# project never had one, or `_impact_begin` (which cmd_enable always calls first — see the ordering
# rule in keel-impact.sh) already swept every untracked one in successfully. If a legacy file is still
# there — a genuine auto-migrate failure (unreadable/unwritable target), or a TRACKED file D4
# deliberately leaves in place forever — writing `origin` anyway would falsely claim "fully migrated"
# and permanently block `_impact_auto_migrate`'s own retry (the failure case), or claim a completion
# that D4's supported partial-migration state never reaches by design (the tracked case; auto-migrate
# itself never writes `origin` for that repo either — see its own `all_untracked` guard). `enable`
# itself is unaffected either way: `impact_enabled()`/`_impact_file_path` key off the store DIRECTORY
# existing, not this file (the LEANING recorded at dir #304, kept deliberately narrow because
# tests/test_keel_impact.sh's "PARTIAL migration regression" pin depends on it) — so a repo missing
# `origin` still reports itself enabled, and a legacy file left behind is not silent: doctor.sh's
# W-KEEL-LEGACY names `migrate` for the tracked case, and any later automatic resolve retries the
# untracked-failure case on its own.
impact_store_enable() {
  local dir="${1:-.}" top store
  top="$(_impact_resolve_top "$dir")"
  # dir #630 S5: the mkdir moved into impact_store_create, the ONE entry creator — it also writes the
  # S4 provenance record (keel.impactStore in the repo's local git config), which every site that
  # brings a store entry into existence must do, not just this one.
  store="$(impact_store_create "$dir")" || return 1
  impact_has_legacy_files "$dir" "$top" || impact_store_mark_migrated "$store" "$top"
  printf '%s' "$store"
}

# ==== dir #630: provenance (S4), one entry creator (S5), state machine (S6) ========================
#
# S0 vocabulary (stated once, read by every function below):
#   lost  — this repo recorded an entry (S4) and its directory is absent now. The tool cannot tell
#           *destroyed* from *moved away*, and says so.
#   never — no record exists on this clone. A fresh clone of a once-enabled repo reads `never`; that
#           limit is accepted.
#   moved — this repo recorded some OTHER entry that still exists (KEEL_HOME changed, or the repo's own
#           path changed and so did its id).
# The read-trace half (S13, PR-C) reuses the same three words and the same generic pair below.

# IMPACT_STORE_RECORD_KEY — S4: the git-config key the impact half's provenance record lives under.
# Named once so keel-impact.sh and this file never hand-type the string independently.
IMPACT_STORE_RECORD_KEY="keel.impactStore"

# _impact_override_active — true iff any per-file override (KEEL_IMPACT_LEDGER/_EVIDENCE/_LOG) is set,
# the ONE place this three-variable check lives (found by a cross-vendor-style review round: it was
# hand-typed three times — impact_store_create, impact_entry_state's rung 1, and _impact_begin's S5
# backfill — twice as a negated-AND and once as a positive-OR). A future 4th per-file override (or the
# removal of one of the three) now needs updating in exactly one place, the same discipline
# IMPACT_ISOLATION_VARS above exists for on the isolation side (dir #317's own history).
_impact_override_active() {
  [ -n "${KEEL_IMPACT_LEDGER:-}" ] || [ -n "${KEEL_IMPACT_EVIDENCE:-}" ] || [ -n "${KEEL_IMPACT_LOG:-}" ]
}

# _keel_store_git ARGS… — dir #630 fix round (F1): run `git ARGS…` with GIT_DIR/GIT_COMMON_DIR/
# GIT_WORK_TREE/GIT_INDEX_FILE cleared, for the one-off `-C "$top"` calls keel_store_record and
# keel_store_recorded make. A caller process started with one of those already set (a hook, a tool
# invoked from inside another repo's git machinery) otherwise hijacks `-C`: git honors an inherited
# GIT_DIR over it, so e.g. `rev-parse --show-toplevel` silently succeeds against the HIJACKED repo
# (not `$top`) and a `--add` lands in ITS .git/config — as long as `$top` exists as SOME directory on
# disk (a project not yet git-initialized is enough: `-C` only needs a `chdir` to succeed, and git
# resolves the repo from `GIT_DIR` from there, never from `$top`'s own contents). A `$top` that
# doesn't exist on disk at all was already safe before this fix, verified live (git 2.52.0): `-C`
# fails outright on the `chdir` before git ever consults `GIT_DIR`, hijacked or not — tests below
# cover the exists-but-not-a-repo case, the one that actually reproduces the hijack. `env -u` clears
# the four variables for this one exec without a subshell fork (`( unset …; git … )` forks
# once for the subshell and once for git; `env -u … git …` execs git directly). Scoped to these two
# functions' own calls, not a lib-level unset (this file is sourced by tools/pre-pr-gate.sh,
# public-audit.sh, doctor.sh, citation-resolvability.sh, pipeline-canary.sh, keel-impact.sh and
# read-trace — a process-wide unset would change their own git calls too; dir #647 covers that class
# for the rest of the codebase). Not `tools/lib/repo-arg-guard.sh`'s own unset: that one is
# unconditional at SOURCE time for the whole process (its own header explains why), which is exactly
# the process-wide effect dir #647 is scoped to avoid here. `impact_claim_key` (:71-73) is
# deliberately left alone — it is baseline v0.11.0 behavior, not part of this fix's scope.
_keel_store_git() {
  env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git "$@"
}

# keel_store_record KEY ENTRY TOP — S4: record that TOP's project has (or had) a store entry at ENTRY,
# under the LOCAL git config key KEY (`git -C "$TOP" config --local`), multi-valued. Generic — read-
# trace's own S13 record (key `keel.readTraceStore`) reuses this unchanged rather than a second
# hand-rolled writer. A TOP that is not a git repo, or a value already present, is a silent no-op;
# ANY failure is ignored (S4: "never fails the verb") — this function always returns 0. Precedent for
# writing into an adopter's own git dir: install-secret-guard.sh vendors into the repo's hooks dir (S4).
keel_store_record() {
  local key="$1" entry="$2" top="$3"
  [ -n "$top" ] && [ -n "$entry" ] || return 0
  _keel_store_git -C "$top" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  _keel_store_has_entry "$key" "$entry" "$top" && return 0
  _keel_store_git -C "$top" config --local --add "$key" "$entry" >/dev/null 2>&1 || true
  return 0
}

# keel_store_recorded KEY TOP — S4 reads: print each value recorded under KEY at TOP, one per line.
# `--get-all` returns rc 1 (no values) or rc 128 (TOP is not a repo) — S4: "both mean 'no record'", so
# both are swallowed here rather than surfaced as an error. dir #630 F1: same inherited-GIT_DIR guard
# (_keel_store_git above) as keel_store_record, so a read never reports a HIJACKED repo's values as
# TOP's own.
keel_store_recorded() {
  local key="$1" top="$2"
  [ -n "$top" ] || return 0
  _keel_store_git -C "$top" config --local --get-all "$key" 2>/dev/null || true
  return 0
}

# _keel_store_has_entry KEY ENTRY TOP — true iff ENTRY is among the values recorded under KEY at TOP.
# The ONE membership test both `keel_store_record` (idempotency: don't --add a value already there)
# and `keel_store_state` (the `lost` rung: ENTRY itself is recorded) need — factored here so the
# SIGPIPE-safe here-string form (dir #280 — a `printf | grep -q` race) exists in one place, not two.
_keel_store_has_entry() {
  local key="$1" entry="$2" top="$3" recorded
  recorded="$(keel_store_recorded "$key" "$top")"
  [ -n "$recorded" ] && grep -qxF "$entry" <<<"$recorded"
}

# keel_store_state KEY ENTRY TOP — the S6 rungs that do NOT depend on anything impact-specific
# (override/legacy have no read-trace equivalent — S13 has neither): rung 3 `enabled` (ENTRY exists),
# rung 4 `lost` (ENTRY is recorded but absent), rung 5 `moved` (unrecorded, but some OTHER recorded
# value still exists as a directory), rung 6 `never`. impact_entry_state (below) wraps this after its
# own rungs 0-2; S13's read-trace half calls it directly, since it has no rungs 0-2 of its own.
keel_store_state() {
  local key="$1" entry="$2" top="$3"
  if [ -n "$entry" ] && [ -d "$entry" ]; then printf 'enabled'; return 0; fi
  if _keel_store_has_entry "$key" "$entry" "$top"; then
    printf 'lost'; return 0
  fi
  local recorded r
  recorded="$(keel_store_recorded "$key" "$top")"
  while IFS= read -r r; do
    [ -n "$r" ] && [ -d "$r" ] && { printf 'moved'; return 0; }
  done <<<"$recorded"
  printf 'never'
}

# impact_store_create [DIR] — S5: the ONE entry creator. `mkdir -p` of DIR's project's store entry plus
# the S4 record — every site that brings a store entry into existence calls this (impact_store_enable
# above; _impact_auto_migrate, cmd_migrate and cmd_restore in keel-impact.sh; the canary's pre-create).
# Prints the store dir. S4's scope note ("never written when a per-file override is set...") is honoured
# here: a caller running under KEEL_IMPACT_LEDGER/_EVIDENCE/_LOG still gets its mkdir (unaffected
# behaviour — those overrides bypass the store outright, but nothing here depends on that), just no
# provenance record, since that triple isn't resolving through the store at all.
impact_store_create() {
  local dir="${1:-.}" top store
  top="$(_impact_resolve_top "$dir")"
  store="$(impact_store_dir "$dir")" || return 1
  # `|| return 1` (found by a final review round): a non-final failing command inside a function does
  # NOT propagate as the function's own exit status in bash — only the LAST command's status does
  # (here, the trailing `printf`, which always succeeds). Without this guard, a genuine mkdir failure
  # (permission denied, disk full, a deleted parent mid-race) was silently swallowed: every caller's
  # own `|| return 1`/`|| return 0` guard around this function never fired, and the very next line at
  # most call sites (impact_store_mark_migrated's `printf ... > "$store/origin"`) would then hit the
  # missing directory as a raw, uncaught shell error under `set -e` instead of a clean, named failure.
  mkdir -p "$store" || return 1
  _impact_override_active || keel_store_record "$IMPACT_STORE_RECORD_KEY" "$store" "$top"
  printf '%s' "$store"
}

# _impact_is_legacy_state DIR TOP — S6 rung 2's two conditions, both read-only: (a) a legacy in-tree
# file is PHYSICALLY present (impact_has_legacy_files, including a partial migration — one file moved,
# another tracked one left behind); (b) no physical file yet, but the marker-but-not-yet-scored
# fallback (_impact_file_path's own rung 4 — a genuine old-style `enable` gitignore line, no store entry
# and no file written yet) would still resolve one of the three names in-tree. Either counts as `legacy`.
_impact_is_legacy_state() {
  local dir="$1" top="$2" name f
  impact_has_legacy_files "$dir" "$top" && return 0
  [ -n "$top" ] || return 1
  for name in $IMPACT_LEGACY_NAMES; do
    f="$(_impact_file_path "$name" "$dir")"
    case "$f" in "$top/.keel/"*) return 0 ;; esac
  done
  return 1
}

# impact_entry_state [DIR] — S6: prints exactly one word — unresolved/override/legacy/enabled/lost/
# moved/never — read-only, never errors (rung 0's own resolution failure is swallowed, not propagated).
# Rungs 0-2 are impact-specific (a per-file override, or an unmigrated legacy marker, both bypass the
# store outright); rungs 3-6 delegate to keel_store_state, shared with S13's read-trace half.
impact_entry_state() {
  local dir="${1:-.}" entry top
  # rung 0: unresolved — impact_store_dir fails when HOME, KEEL_HOME and KEEL_IMPACT_STORE are all
  # unset (impact_store_root's own `${HOME:?...}`); stderr is suppressed, per S6's own wording.
  if ! entry="$(impact_store_dir "$dir" 2>/dev/null)"; then
    printf 'unresolved'; return 0
  fi
  # rung 1: override — any per-file override is set, regardless of whether it happens to resolve.
  if _impact_override_active; then
    printf 'override'; return 0
  fi
  top="$(_impact_resolve_top "$dir")"
  # rung 2: legacy
  if _impact_is_legacy_state "$dir" "$top"; then
    printf 'legacy'; return 0
  fi
  keel_store_state "$IMPACT_STORE_RECORD_KEY" "$entry" "$top"
}

# impact_recorded_entries [DIR] — S6's companion: print DIR's project's recorded store entries (S4),
# one per line, for a `lost`/`moved` message to list. Read-only.
impact_recorded_entries() {
  local dir="${1:-.}" top
  top="$(_impact_resolve_top "$dir")"
  keel_store_recorded "$IMPACT_STORE_RECORD_KEY" "$top"
}
