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
#      by construction, no separate strip needed. A qualifying arrow reached only via a citation
#      to a DIFFERENT ticket ("Supersedes dir #5 → 0.9.0") is stripped first, via the shared
#      `bb_strip_foreign_citations` — the same "whose tag is it" helper pool-report.sh already
#      calls for its own `pool` tag (code-review medium, found live: reproduced a citing ticket
#      wrongly counted under the cited sibling's tag before this strip was added).
#   2. A closed heading's own trailing arrow ("→ 10,884 lines") is never read as a tag, because
#      closed blocks are excluded before extraction ever runs (closure comes straight from
#      `backlog_ticket_blocks`'s own citation-aware detection, the same predicate `pool-report.sh`
#      and `doctor.sh` check 5 already share).
#   3. Closure is matched on the project's actual marker (`✅`/`❌`) via that same shared
#      predicate, never on a vocabulary of status words a groom might mint mid-run (a `RE-SCOPED`
#      heading is not itself a closure).
#   4. The marker is matched at a fixed position (the heading block's own closure tag, not any
#      `✅`/`❌` anywhere in absorbed body text) — again inherited from the shared predicate, not
#      reimplemented here. This mechanizes only HALF of G3's fourth rule: the other half — whether
#      the project's status vocabulary is OVERLOADED, the same glyph meaning two different things
#      in one column — is a data-authoring ambiguity invisible from any count, and no scanner can
#      resolve it. `docs/grooming.md`'s G3 still names that half as a manual check on every cycle.
#
# A `/groom` that used to apply these by hand now runs this tool instead for three-and-a-half of
# G3's four rules — once before the hygiene sweep and once after the last heading edit, per G4's
# own reconciliation step — and still checks the overloaded-glyph half of rule 4 itself.
#
# Sources tools/lib/backlog-blocks.sh (same shared scanner pool-report.sh and doctor.sh check 5
# use) and resolves BACKLOG.md the way doctor.sh check 5 does — the MAIN checkout, worktree-aware,
# via backlog_root_for. Legacy `### <n>.` headings count under their tag like any other block,
# same as backlog_ticket_blocks itself treats them. A block with no qualifying arrow counts under
# the literal tag `untagged`. Nothing is written; exit 0 always (advisory, like pool-report.sh).
#
# Usage:
#   tools/self/backlog-census.sh [--ticket-token ERE] [--list TAG] [BACKLOG_PATH]
#   tools/self/backlog-census.sh -h | --help
#
# --ticket-token ERE (dir #605): the heading token an adopter's backlog uses, as an ERE matched right
# after `### ` and before a space — `B\.[0-9]+` for `### B.N`, `KB\.[0-9]+|RL\.[0-9]+` for two forms.
# It REPLACES the default (`dir #N` and `<n>.`), which stays unchanged without the flag; an empty or
# invalid ERE exits 2. With it, --list prints each ticket's captured token (`B.12`), not a bare number.
# Out of scope: a pool kept as a SECTION (`## Pool`) rather than a `→ pool` heading tag — the flag
# yields the open set, not that pool.
#
# With no --list, prints one line per tag, `count<TAB>tag`, descending by count (ties broken by
# tag, ascending). With --list TAG, prints the ticket number of every open block under that tag,
# one per line, in the file's own order — a legacy heading's number is its bare leading numeral,
# a `dir #N` heading's is N.
#
# BACKLOG_PATH defaults to the MAIN checkout's BACKLOG.md, resolved the same way
# tools/self/pool-report.sh resolves it (dir #135) — override for a test fixture or a
# non-standard layout by passing it positionally, same as that sibling.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=tools/lib/fence-blank.sh
. "$self_dir/../lib/fence-blank.sh"
# shellcheck source=tools/lib/backlog-blocks.sh
. "$self_dir/../lib/backlog-blocks.sh"

list_tag=""
backlog_arg=""
ticket_token=""
ticket_token_set=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      [ $# -ge 2 ] || { echo "backlog-census: --list needs a tag" >&2; exit 2; }
      list_tag="$2"; shift 2 ;;
    --list=*) list_tag="${1#*=}"; shift ;;
    --ticket-token)
      [ $# -ge 2 ] || { echo "backlog-census: --ticket-token needs a regex" >&2; exit 2; }
      ticket_token="$2"; ticket_token_set=1; shift 2 ;;
    --ticket-token=*) ticket_token="${1#*=}"; ticket_token_set=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: backlog-census.sh [--ticket-token ERE] [--list TAG] [BACKLOG_PATH]

Prints one line per release tag, `count<TAB>tag`, descending by count — the last `→ pool` /
`→ next` / `→ on-demand` / `→ N.N[.N]` token on every OPEN heading block, `untagged` for a
block with no qualifying arrow. With --list TAG, prints the ticket number of every open block
under that tag, one per line, in file order.

--ticket-token ERE names an adopter's heading token (`B\.[0-9]+` for `### B.N`); it replaces the
default `dir #N` / `<n>.`, and --list then prints the captured token. A pool kept as a `## Pool`
section is not read: the flag yields the open set only.
EOF
      exit 0 ;;
    -*)
      echo "backlog-census: unknown flag: $1" >&2
      exit 2 ;;
    *)
      backlog_arg="$1"; shift ;;
  esac
done

# dir #605: validate the token under BOTH engines that will run it (grep -E in the scanner's heading
# pass, bash's own `=~` right after) — a match or none is fine, status 2 is a malformed ERE.
if [ -n "$ticket_token_set" ]; then
  if [ -z "$ticket_token" ]; then
    echo "backlog-census: --ticket-token needs a non-empty regex" >&2
    exit 2
  fi
  grep_rc=0
  printf '' | grep -E -- "$ticket_token" >/dev/null 2>&1 || grep_rc=$?
  bash_rc="$([[ "" =~ $ticket_token ]]; echo $?)"
  if [ "$grep_rc" -ge 2 ] || [ "$bash_rc" -ge 2 ]; then
    echo "backlog-census: --ticket-token is not a valid extended regex: $ticket_token" >&2
    exit 2
  fi
fi

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

  id="$(bb_own_ticket_num "$heading_block")"

  # code-review medium (found live): a qualifying arrow reached only via a citation to a
  # DIFFERENT ticket ("Supersedes dir #5 → 0.9.0") was read as THIS heading's own tag — the
  # exact "whose tag is it" bug bb_strip_foreign_citations already exists to close (dir #426),
  # and pool-report.sh already calls it for its own `pool` tag. Strip foreign-citation clauses
  # before extracting, same as pool-report.sh does. The vocabulary here carries NO `\b` — unlike
  # the grep -oE extraction below (a real grep -E, where \b is confirmed portable, alpine
  # included), this pattern feeds bash's OWN `[[ =~ ]]` engine inside bb_strip_foreign_citations,
  # which doesn't support `\b` on macOS's stock bash 3.2 (BSD regex) — reproduced live: with
  # \b left in, the strip silently never matched. bb_strip_foreign_citations appends the
  # project's own portable substitute, `([^a-zA-Z]|$)`, after the pattern itself.
  stripped_block="$(bb_strip_foreign_citations "$heading_block" "$id" \
    '(pool|next|on-demand|[0-9]+\.[0-9]+(\.[0-9]+)?)')"

  # dir #360's own memory lesson, one more time: `set -e` inside a `while read` loop is killed
  # by ANY failing command in it, including a `grep` that legitimately finds nothing — every
  # extraction below either sits in a pipeline ending in a command that always exits 0, or is
  # explicitly guarded with `|| true`, so a non-matching heading can never abort the census.
  tag="$(grep -oE '→[[:space:]]*(pool\b|next\b|on-demand\b|[0-9]+\.[0-9]+(\.[0-9]+)?\b)' \
    <<< "$stripped_block" | tail -1 | sed -E 's/^→[[:space:]]*//' || true)"
  [ -n "$tag" ] || tag="untagged"

  if [ -n "$ticket_token_set" ]; then
    # dir #605: an adopter's own token — the id IS the captured token (`B.12`), not a bare number.
    id=""
    [[ "$heading_block" =~ ^###\ (${ticket_token})\  ]] && id="${BASH_REMATCH[1]}"
  elif [ -z "$id" ]; then
    # A legacy `### <n>.` heading has no `dir #N` of its own (bb_own_ticket_num's own documented
    # contract) — one native bash regex test for its bare leading numeral, same style as
    # bb_own_ticket_num itself, instead of a two-stage grep pipeline.
    [[ "$heading_block" =~ ^###\ ([0-9]+)\. ]] && id="${BASH_REMATCH[1]}"
  fi
  [ -n "$id" ] || id="?"

  tag_id_pairs+=("$tag"$'\t'"$id")
done < <(backlog_ticket_blocks "$backlog_file" ${ticket_token_set:+"$ticket_token"})

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

# code-review medium (found live): a plain lexicographic tie-break on the tag STRING sorts
# "0.10.0" before "0.9.0" ('1' < '9' as characters) — the wrong order for a version tag once a
# release reaches double digits. Zero-pad each dot-separated numeral of an all-numeric tag into a
# sort key (pool/next/on-demand/untagged pass through unchanged, since they carry no digits to
# pad), sort on that key, then print the ORIGINAL tag.
printf '%s\n' "${tag_id_pairs[@]}" | cut -f1 | sort | uniq -c | awk '
  {
    count = $1; tag = $2
    n = split(tag, parts, ".")
    all_numeric = 1
    for (i = 1; i <= n; i++) { if (parts[i] !~ /^[0-9]+$/) { all_numeric = 0; break } }
    key = tag
    if (all_numeric) {
      key = ""
      for (i = 1; i <= n; i++) { key = key sprintf("%05d.", parts[i]) }
    }
    printf "%s\t%s\t%s\n", count, key, tag
  }' | sort -t $'\t' -k1,1rn -k2,2 | cut -f1,3

exit 0
