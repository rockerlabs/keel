#!/usr/bin/env bash
# tools/self/alpine-clone.sh — keel-self-maintenance (dir #68: never installed by install.sh; dir #728):
# cuts, or refreshes in place, the Alpine-leg clone `CLAUDE.md`'s "Run the real leg locally" recipe
# mounts into Docker, with the three traps that each cost a false red in the 0.14.0 release built in:
#   1. hard-linked packs — a plain local `git clone` hard-links the source's objects, so the container
#      (running as another uid) mutates files the source shares: the clone uses `--no-hardlinks`;
#   2. a copied `.DS_Store` under `.git/objects` — `git clone` inside the container then exits 128 and
#      the bootstrap legs of test_install.sh go red: every `.DS_Store` under the clone's `.git` is
#      removed after the clone, the fetch and the checkout;
#   3. a detached HEAD after `checkout FETCH_HEAD` — `bootstrap --link` exits 128: the clone is always
#      left ON the branch `keel-alpine-leg`, reset to the requested commit.
#
# Usage: tools/self/alpine-clone.sh <Wn|solo> <sha> [--source DIR] [--run]
#   <Wn>      a worker id (letters, digits, `_`, `-`): the clone lives at $HOME/.keel/tmp/alpine-clone-<Wn>,
#             so parallel workers never share one (docs/parallel-sessions.md F7). `solo` = the shared
#             solo path $HOME/.keel/tmp/alpine-clone.
#   <sha>     a commit of the source (any ref `git rev-parse` accepts there).
#   --source  the repository to clone; default is the MAIN checkout (first entry of `git worktree list`),
#             never the current worktree and never an inherited remote — a scratch clone has inherited a
#             stale origin before. An existing clone is reused only if its `origin` is exactly this path.
#   --run     after preparing the clone, run the Alpine docker leg on it (the CLAUDE.md one-liner).
# Prints the clone path on stdout (last line). Exit: 0 ok; 2 usage; 1 any refusal.
#
# Refusals (nothing is touched): a target that exists but is neither empty nor a clone of --source
# (its `.git` is not at its root, or its origin differs); an unknown <sha>. This tool never deletes
# anything — a session cannot `rm -rf` — so removing a clone stays the release manager's wrap or the
# operator's. The path is under $HOME/.keel/tmp (Docker cannot mount the scratchpad), outside the
# `$HOME/keel*alpine*` shape tools/self/doctor.sh's stray-clone advisory looks for.
set -euo pipefail
# drop an inherited repo selector before any git call (the dir #647 convention shared by tools/).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

usage() { printf 'usage: alpine-clone.sh <Wn|solo> <sha> [--source DIR] [--run]\n' >&2; exit 2; }
die() { printf 'alpine-clone: %s\n' "$*" >&2; exit 1; }

id=""; rev=""; source_dir=""; run_leg=0
while [ $# -gt 0 ]; do
  case "$1" in
    --source) [ $# -ge 2 ] || usage; source_dir="$2"; shift 2 ;;
    --run) run_leg=1; shift ;;
    -*) usage ;;
    *) if [ -z "$id" ]; then id="$1"; elif [ -z "$rev" ]; then rev="$1"; else usage; fi; shift ;;
  esac
done
[ -n "$id" ] && [ -n "$rev" ] || usage
case "$id" in
  [A-Za-z0-9]*) case "$id" in *[!A-Za-z0-9_-]*) usage ;; esac ;;
  *) usage ;;
esac
[ -n "${HOME:-}" ] || die "HOME is not set"

if [ -z "$source_dir" ]; then
  source_dir="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$source_dir" ] || die "not inside a git checkout — pass --source DIR"
fi
source_dir="$(cd "$source_dir" 2>/dev/null && pwd)" || die "--source is not a directory"
git -C "$source_dir" rev-parse --git-dir >/dev/null 2>&1 || die "--source $source_dir is not a git repository"
full="$(git -C "$source_dir" rev-parse --verify --quiet "$rev^{commit}")" || die "$rev is not a commit of $source_dir"

if [ "$id" = solo ]; then name=alpine-clone; else name="alpine-clone-$id"; fi
clone="$HOME/.keel/tmp/$name"
mkdir -p "$HOME/.keel/tmp"

strip_ds_store() { find "$clone/.git" -name .DS_Store -type f -delete; }

if [ -e "$clone" ] && [ -n "$(ls -A "$clone" 2>/dev/null)" ]; then
  [ "$(git -C "$clone" rev-parse --git-dir 2>/dev/null || true)" = .git ] \
    || die "$clone exists and is not a git clone — refusing to reuse it (remove it by hand)"
  have="$(git -C "$clone" config --get remote.origin.url || true)"
  [ "$have" = "$source_dir" ] \
    || die "$clone has origin '$have', not the source '$source_dir' — a stale clone; refusing to reuse it"
  strip_ds_store
  git -C "$clone" fetch -q --no-tags origin '+refs/heads/*:refs/remotes/origin/*' \
    || die "fetch from $source_dir failed"
else
  git clone -q --no-hardlinks --no-checkout "$source_dir" "$clone" || die "clone of $source_dir failed"
fi
git -C "$clone" cat-file -e "$full^{commit}" 2>/dev/null \
  || git -C "$clone" fetch -q --no-tags origin "$full" 2>/dev/null \
  || die "$full is not reachable from the branches of $source_dir"
git -C "$clone" checkout -q -f -B keel-alpine-leg "$full"
strip_ds_store

printf '%s\n' "$clone"
if [ "$run_leg" = 1 ]; then
  exec docker run --rm -e CI=true -v "$clone:/keel" -w /keel alpine:3.21 sh -c \
    'apk add --no-cache bash git jq && git config --system --add safe.directory "*" && bash tests/run.sh'
fi
