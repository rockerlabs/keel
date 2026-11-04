#!/usr/bin/env bash
# tools/effort-share.sh — dir #635 PR2: the meta-share thermostat's instrument. Counts commits in two
# sets of repositories the CALLER names (a "meta" set: the project that is infrastructure for others,
# and a "product" set: the projects it serves) since a date or a ref, and prints each repo's count and
# the meta share. Adopter-usable: nothing about any project is hard-coded; the caller passes every list.
#
# Usage:
#   effort-share.sh --meta REPO... --product REPO... --since DATE|REF [--json]
#   effort-share.sh --help
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

usage() {
  cat <<'EOF'
effort-share.sh --meta REPO... --product REPO... --since DATE|REF [--json]

Prints the commits per repository and the meta share: the percentage of all counted commits that
landed in the --meta set. Read-only. The caller passes every repository list; nothing is hard-coded.

  --meta REPO...     one or more repositories (paths) of the project that is infrastructure
  --product REPO...  one or more repositories of the projects it serves
  --since X          a date, YYYY-MM-DD from 1970 on (UTC midnight, committer date), or a ref (branch, tag, sha)
                     resolved in EACH repository: commits not reachable from that ref count. A
                     ref missing from any repository refuses, naming it; a value that is neither a
                     valid date nor a ref there refuses too (git itself would read it as "now" and
                     report an empty period). A date-shaped ref name is read as a date.
  --json             print one JSON object instead of the table
  --help             this text

Counting definition (one, fixed): the unique commits per repository reachable from any ref
(git rev-list --all, less refs/stash and refs/notes/*, which hold no
work), merge commits excluded (--no-merges), committed on or after the date, or not
reachable from the ref. The same commit is never counted twice. A merge commit is never counted.
A repository given twice (the same repository, in either set, also through a linked worktree or
its .git directory) refuses.

Share = meta commits / (meta + product commits), one decimal. With zero commits in total the share
is printed as n/a (JSON: null), never 0%.

Honest limit: commits are a proxy for effort, and commit granularity differs across projects: a
project that commits small and often reads as more effort than one that commits in large batches. Read
the share as a trend across grooms counted the same way, not as a measurement. No token figure is
printed here.

Exit: 0 printed; 2 usage error or a refused input (not a git repo, bad --since, missing ref,
duplicate repo).
EOF
}

die() { printf 'effort-share: %s\n' "$1" >&2; exit 2; }

meta_list="" prod_list="" since="" json=0 mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --json) json=1; shift ;;
    --since)
      [ $# -ge 2 ] || die "--since needs a value"
      since="$2"; shift 2 ;;
    --meta|--product)
      mode="$1"; shift
      [ $# -gt 0 ] && case "$1" in --*) false ;; *) true ;; esac || die "$mode needs at least one repository"
      while [ $# -gt 0 ]; do
        case "$1" in --*) break ;; esac
        case "$1" in *[[:cntrl:]]*) die "a repository path with a control character (tab, newline) is refused" ;; esac
        if [ "$mode" = --meta ]; then meta_list="${meta_list:+$meta_list
}$1"; else prod_list="${prod_list:+$prod_list
}$1"; fi
        shift
      done ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[ -n "$meta_list" ] || die "--meta is required (see --help)"
[ -n "$prod_list" ] || die "--product is required (see --help)"
[ -n "$since" ] || die "--since is required (see --help)"

# A strict date: YYYY-MM-DD with a real month and day. Sets cutoff to its UTC-midnight epoch seconds.
# Days-from-civil arithmetic in awk, so git's own date parser (which turns garbage into "now") is never used.
cutoff=""
case "$since" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    cutoff="$(LC_ALL=C awk -v d="$since" 'BEGIN {
      y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
      if (y < 1970 || m < 1 || m > 12 || dd < 1) { print "bad"; exit }
      dim = (m == 2) ? ((y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
      if (dd > dim) { print "bad"; exit }
      if (m <= 2) y -= 1
      era = int(y / 400); yoe = y - era * 400
      mp = (m + 9) % 12
      doy = int((153 * mp + 2) / 5) + dd - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      printf "%.0f\n", (era * 146097 + doe - 719468) * 86400 }')"
    [ "$cutoff" != bad ] || cutoff="notadate"
    ;;
esac
[ "$cutoff" != notadate ] || die "--since '$since' is not a valid date"

seen_paths=""
repo_check() { # repo_check PATH -> prints the physical path, or dies
  local p="$1" phys
  [ -d "$p" ] || die "not a directory: $p"
  git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $p"
  if [ "$(git -C "$p" rev-parse --is-bare-repository 2>/dev/null)" != true ]; then
    [ -z "$(git -C "$p" rev-parse --show-cdup 2>/dev/null)" ] || die "not the top of a git repository: $p"
  fi
  phys="$(cd -P "$p" && cd -P "$(git rev-parse --git-common-dir)" && pwd -P)"
  case "
$seen_paths
" in *"
$phys
"*) die "repository given twice: $p" ;; esac
  seen_paths="${seen_paths:+$seen_paths
}$phys"
  printf '%s' "$phys"
}

count_repo() { # count_repo PATH -> prints the commit count, or dies
  local p="$1" ref
  if [ -n "$cutoff" ]; then
    git -C "$p" log --exclude=refs/stash --exclude='refs/notes/*' --all --no-merges --format='%ct' |
      LC_ALL=C awk -v c="$cutoff" '$1 + 0 >= c + 0 { n++ } END { print n + 0 }'
  else
    ref="$(git -C "$p" rev-parse --verify --quiet "$since^{commit}" 2>/dev/null)" ||
      die "--since '$since' is neither a valid date (YYYY-MM-DD) nor a ref in repository: $p"
    git -C "$p" rev-list --exclude=refs/stash --exclude='refs/notes/*' --all --no-merges --not "$ref" |
      LC_ALL=C awk 'END { print NR + 0 }'
  fi
}

# Validate every repo and count it before printing anything, so a refusal never leaves partial output.
rows="" meta_total=0 prod_total=0
for set in meta prod; do
  if [ "$set" = meta ]; then list="$meta_list"; else list="$prod_list"; fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    repo_check "$p" >/dev/null
    n="$(count_repo "$p")"
    rows="${rows:+$rows
}$set	$p	$n"
    if [ "$set" = meta ]; then meta_total=$((meta_total + n)); else prod_total=$((prod_total + n)); fi
  done <<EOF
$list
EOF
done

total=$((meta_total + prod_total))
if [ "$total" -eq 0 ]; then
  share="n/a"; share_json="null"
else
  share="$(LC_ALL=C awk -v m="$meta_total" -v t="$total" 'BEGIN { printf "%.1f", m * 100 / t }')"
  share_json="$share"; share="$share%"
fi

json_str() { printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

if [ "$json" -eq 1 ]; then
  printf '{"since":"%s","definition":"unique commits reachable from any ref, merge commits excluded"' "$(json_str "$since")"
  for set in meta prod; do
    if [ "$set" = meta ]; then key=meta; else key=product; fi
    printf ',"%s":[' "$key"
    first=1
    while IFS="	" read -r s p n; do
      [ "$s" = "$set" ] || continue
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{"repo":"%s","commits":%s}' "$(json_str "$p")" "$n"
    done <<EOF
$rows
EOF
    printf ']'
  done
  printf ',"meta_commits":%s,"product_commits":%s,"meta_share_percent":%s}\n' "$meta_total" "$prod_total" "$share_json"
else
  printf 'since %s (unique --all --no-merges commits per repository)\n' "$since"
  while IFS="	" read -r s p n; do
    if [ "$s" = meta ]; then label=meta; else label=product; fi
    printf '  %-8s %6s  %s\n' "$label" "$n" "$p"
  done <<EOF
$rows
EOF
  printf 'meta %s, product %s, meta share %s\n' "$meta_total" "$prod_total" "$share"
fi
