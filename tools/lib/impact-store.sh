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
# A project is "enabled" iff a store dir already exists for its id. Every path resolver below is
# read-only (no writes, no mutation) and never errors: empty output means "no explicit override, and
# this project isn't enabled" — refusing on that (keel-impact.sh's `add`/`rollup`) vs. silently doing
# nothing (a guardrail hook recording a fire) is each caller's own decision, not this file's.

# _impact_main_top [DIR] — the MAIN checkout's top for DIR (default cwd): the first `git worktree
# list` entry, empty if DIR is not a repo or that entry is bare (no working tree). Equals DIR's own
# top in a plain (non-worktree) repo. `|| true`: outside a repo git exits 128, which would trip the
# caller's `set -e` if this ran unguarded; the awk reads its whole input on purpose (no early exit, no
# SIGPIPE).
_impact_main_top() {
  git -C "${1:-.}" worktree list --porcelain 2>/dev/null |
    awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true
}

# _impact_resolve_top [DIR] — the physical path a project's id is derived from: the main checkout's
# top; else (a bare-main topology) DIR's own toplevel; else (DIR is not a git repo yet) DIR's own
# physical path. Mirrors keel-impact.sh's pre-store `cmd_enable` fallback chain exactly, so a project
# that could `enable` before this ticket can still `enable` now.
#
# NOT memoized, on purpose (an earlier version tried a single-slot cache here and it was dead on
# arrival — found live by an operator-run max-depth review, empirically verified): every call site
# invokes this via `top="$(_impact_resolve_top "$dir")"`, and command substitution forks a subshell —
# any cache variable this function writes lives only in that throwaway child and vanishes when it
# exits, so the parent's "cache" never actually gets populated. A real fix needs the caller to avoid
# command substitution entirely (an output-variable convention, rewriting every call site across this
# file and its consumers) — a bigger, separate change, not a quick fix; filed as a follow-up. The
# actual redundant-fork cost this was meant to address is now addressed differently: see
# _impact_file_path below, which resolves `top` ONCE per call and reuses it, instead of resolving it
# twice (once directly, once again inside impact_store_dir) the way the pre-fix code did.
_impact_resolve_top() {
  local dir="${1:-.}" top
  top="$(_impact_main_top "$dir")"
  [ -n "$top" ] || top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || top="$(cd "$dir" 2>/dev/null && pwd -P)" || top="$dir"
  printf '%s' "$top"
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
# that always sets KEEL_HOME or KEEL_IMPACT_STORE never needs $HOME under `set -u`.
impact_store_root() {
  if [ -n "${KEEL_IMPACT_STORE:-}" ]; then printf '%s' "$KEEL_IMPACT_STORE"; return; fi
  printf '%s/.keel/impact' "${KEEL_HOME:-${HOME:?impact-store: set HOME, or export KEEL_HOME}/.claude}"
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
  store="$(impact_store_dir "$dir")"
  mkdir -p "$store"
  impact_has_legacy_files "$dir" "$top" || impact_store_mark_migrated "$store" "$top"
  printf '%s' "$store"
}
