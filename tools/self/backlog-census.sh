#!/usr/bin/env bash
# tools/self/backlog-census.sh — keel-self-maintenance (dir #68: never installed by install.sh;
# dir #496): the shipped remover `docs/grooming.md`'s G3 names for its own four hand-derivation
# rules. Nothing shipped reported the slate lanes before this (`pool-report.sh` counts the pool
# lane only), so every `/groom` re-derived its open-ticket census by hand — which is exactly
# where G3's four documented defects were minted (a phantom-release extractor, a closure note's
# own trailing arrow, a re-scope status word read as a closure, a mid-cell/overloaded marker).
# This tool is their remover, not a fifth hand-derivation to audit against the other four:
#
#   1. A heading's release tag is the LAST `→` token on the heading block whose token is
#      literally `pool`, `next`, `on-demand`, or a release version (`N.N` or `N.N.N`) — headings
#      carry prose arrows too ("→ ask", "→ a release of its own") and a grade re-tag arrow
#      ("R2 → R3") is not a release tag either; restricting the accepted vocabulary excludes both
#      by construction, no separate strip needed.
#   2. A closed heading's own trailing arrow ("→ 10,884 lines") is never read as a tag, because
#      closed blocks are excluded before extraction ever runs (closure comes straight from
#      `backlog_ticket_blocks`'s own citation-aware detection, the same predicate `pool-report.sh`
#      and `doctor.sh` check 5 already share).
#   3. Closure is matched on the project's actual marker (`✅`/`❌`) via that same shared
#      predicate, never on a vocabulary of status words a groom might mint mid-run (a `RE-SCOPED`
#      heading is not itself a closure).
#   4. The marker is matched at a fixed position (the heading block's own closure tag, not any
#      `✅`/`❌` anywhere in absorbed body text) — again inherited from the shared predicate, not
#      reimplemented here.
#
# A `/groom` that used to apply these four by hand now runs this tool instead — once before the
# hygiene sweep and once after the last heading edit, per G4's own reconciliation step.
#
# Sources tools/lib/backlog-blocks.sh (same shared scanner pool-report.sh and doctor.sh check 5
# use) and resolves BACKLOG.md the way doctor.sh check 5 does — the MAIN checkout, worktree-aware,
# via backlog_root_for. Legacy `### <n>.` headings count under their tag like any other block,
# same as backlog_ticket_blocks itself treats them. A block with no qualifying arrow counts under
# the literal tag `untagged`. Nothing is written; exit 0 always (advisory, like pool-report.sh).
#
# Usage:
#   tools/self/backlog-census.sh [--list TAG] [BACKLOG_PATH]
#   tools/self/backlog-census.sh -h | --help
#
# With no --list, prints one line per tag, `count<TAB>tag`, descending by count (ties broken by
# tag, ascending). With --list TAG, prints the ticket number of every open block under that tag,
# one per line, in the file's own order — a legacy heading's number is its bare leading numeral,
# a `dir #N` heading's is N.
#
# BACKLOG_PATH defaults to the MAIN checkout's BACKLOG.md, resolved the same way
# tools/self/pool-report.sh resolves it (dir #135) — override for a test fixture or a
# non-standard layout by passing it positionally, same as that sibling.
#
# Known, accepted limitation (same shape pool-report.sh's own header documents for RETRACTED): a
# qualifying arrow reached only via a citation to a DIFFERENT ticket ("Supersedes dir #5 → 0.9.0")
# is read as this heading's own tag — not chased here; no such shape exists in this project's own
# live BACKLOG.md today, and closure itself (the one place a foreign-citation strip genuinely
# matters) already goes through the shared, citation-aware predicate.
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

list_tag=""
backlog_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      [ $# -ge 2 ] || { echo "backlog-census: --list needs a tag" >&2; exit 2; }
      list_tag="$2"; shift 2 ;;
    --list=*) list_tag="${1#*=}"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: backlog-census.sh [--list TAG] [BACKLOG_PATH]

Prints one line per release tag, `count<TAB>tag`, descending by count — the last `→ pool` /
`→ next` / `→ on-demand` / `→ N.N[.N]` token on every OPEN heading block, `untagged` for a
block with no qualifying arrow. With --list TAG, prints the ticket number of every open block
under that tag, one per line, in file order.
EOF
      exit 0 ;;
    -*)
      echo "backlog-census: unknown flag: $1" >&2
      exit 2 ;;
    *)
      backlog_arg="$1"; shift ;;
  esac
done

if [ -n "$backlog_arg" ]; then
  backlog_file="$backlog_arg"
else
  backlog_root="$(backlog_root_for "$repo_root")"
  backlog_file="$backlog_root/BACKLOG.md"
fi

# Same guard pool-report.sh's own v0.9.0 RC-audit fix note explains: must run BEFORE any `cd`
# derived from backlog_file's dirname, or a nonexistent BACKLOG_PATH directory aborts under
# `set -e` instead of hitting this tool's own documented silent skip.
if [ ! -f "$backlog_file" ] || [ ! -r "$backlog_file" ]; then
  echo "backlog-census: no readable BACKLOG.md at $backlog_file — skipped, not a failure"
  exit 0
fi

# tag_id_pairs holds one "TAG<TAB>ID" entry per open, tagged-or-untagged block, in file order —
# a plain indexed array, not `declare -A`: this repo's tools target bash 3.2 (macOS's shipped
# /bin/bash), which has no associative arrays (same reason citation-resolvability.sh and
# session-cost.sh avoid them). Grouping and sorting by tag is done downstream with sort/uniq,
# not a hand-rolled bash accumulator keyed by a dynamic tag string.
tag_id_pairs=()

while IFS=$'\t' read -r start end closed heading_block; do
  : "$start" "$end"  # body span unused; block detection alone gives the heading
  [ "$closed" = "1" ] && continue

  # dir #360's own memory lesson, one more time: `set -e` inside a `while read` loop is killed
  # by ANY failing command in it, including a `grep` that legitimately finds nothing — every
  # extraction below either sits in a pipeline ending in a command that always exits 0, or is
  # explicitly guarded with `|| true`, so a non-matching heading can never abort the census.
  tag="$(grep -oE '→[[:space:]]*(pool\b|next\b|on-demand\b|[0-9]+\.[0-9]+(\.[0-9]+)?\b)' \
    <<< "$heading_block" | tail -1 | sed -E 's/^→[[:space:]]*//' || true)"
  [ -n "$tag" ] || tag="untagged"

  id="$(bb_own_ticket_num "$heading_block")"
  if [ -z "$id" ]; then
    # A legacy `### <n>.` heading has no `dir #N` of its own (bb_own_ticket_num's own documented
    # contract) — one native bash regex test for its bare leading numeral, same style as
    # bb_own_ticket_num itself, instead of a two-stage grep pipeline.
    [[ "$heading_block" =~ ^###\ ([0-9]+)\. ]] && id="${BASH_REMATCH[1]}"
  fi
  [ -n "$id" ] || id="?"

  tag_id_pairs+=("$tag"$'\t'"$id")
done < <(backlog_ticket_blocks "$backlog_file")

# bash 3.2 empty-array guard (dir #204's own trap): expanding "${arr[@]}" on a still-empty array
# throws "unbound variable" under `set -u` instead of iterating zero times. One guard covers both
# branches below rather than each repeating it.
if [ "${#tag_id_pairs[@]}" -eq 0 ]; then
  exit 0
fi

if [ -n "$list_tag" ]; then
  for pair in "${tag_id_pairs[@]}"; do
    [ "${pair%%$'\t'*}" = "$list_tag" ] && printf '%s\n' "${pair#*$'\t'}"
  done
  exit 0
fi

printf '%s\n' "${tag_id_pairs[@]}" | cut -f1 | sort | uniq -c \
  | sort -k1,1rn -k2,2 | awk '{print $1"\t"$2}'

exit 0
