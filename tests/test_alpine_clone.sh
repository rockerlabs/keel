#!/usr/bin/env bash
# Tests for tools/self/alpine-clone.sh (dir #728) — the per-worker Alpine-leg clone helper. One test
# group per trap that cost a false red in 0.14.0: hard-linked packs (--no-hardlinks), a copied
# .DS_Store under .git (git clone exits 128 inside the container), and a detached HEAD (bootstrap
# --link exits 128). Plus the reuse guards: a path whose .git is not the expected clone is refused,
# and the tool never removes a clone directory (a reused clone is reset and cleaned back to the requested
# commit, which the reuse group below pins). Every clone here comes from a sandbox repo via --source, never
# from the real checkout; HOME is the sandbox HOME lib.sh pins, so the canonical $HOME/.keel/tmp path is
# sandboxed. dir #750 adds the symlink group: a clone path that is a symlink, that resolves to the source
# (same device+inode, also through a symlinked ancestor) or whose .git is a symlink is refused before any git
# write, and the .git-not-at-its-root refusal is pinned with an enclosing-repository fixture; every decoy lives
# under its own sandbox HOME.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/self/alpine-clone.sh"
check_file "tool exists" "$tool"

src="$(new_repo)"
git -C "$src" symbolic-ref HEAD refs/heads/main
echo one > "$src/f"; git -C "$src" add f; git -C "$src" commit -q -m one
sha1="$(git -C "$src" rev-parse HEAD)"
echo two > "$src/f"; git -C "$src" commit -q -am two
sha2="$(git -C "$src" rev-parse HEAD)"
# the incident's DS_Store, planted in the SOURCE .git so a plain copying clone carries it over
: > "$src/.git/objects/.DS_Store"

want="$HOME/.keel/tmp/alpine-clone-W5"

run "$tool" W5 "$sha1" --source "$src"
check_status "a first run exits 0" 0 "$STATUS"
check_contains "prints the clone path" "$OUT" "$want"
check_dir "creates the per-worker clone under \$HOME/.keel/tmp" "$want/.git"

# trap 1 — hard links: no object file in the clone shares an inode with the source
links="$(find "$want/.git/objects" -type f -links +1 | head -1)"
check_eq "no hard-linked object file (--no-hardlinks)" "" "$links"

# trap 2 — a .DS_Store anywhere under the clone's .git
ds="$(find "$want/.git" -name .DS_Store | head -1)"
check_eq "no .DS_Store under .git" "" "$ds"

# trap 3 — on a branch, not detached, at the requested sha
br="$(git -C "$want" symbolic-ref -q --short HEAD || true)"
check_ne "HEAD is on a branch (not detached)" "" "$br"
check_eq "checked out at the requested sha" "$sha1" "$(git -C "$want" rev-parse HEAD)"
check_eq "the clone's origin is the source" "$src" "$(git -C "$want" config remote.origin.url)"

# reuse: untracked and ignored leftovers of a previous run are cleaned too
echo junk > "$want/leftover"; mkdir -p "$want/scratchdir"; echo junk > "$want/scratchdir/x"
git init -q "$want/nestedrepo"   # a nested repo survives a single -f
# reuse: moves to the new sha, and re-cleans a .DS_Store that appeared since
: > "$want/.git/objects/.DS_Store"
run "$tool" W5 "$sha2" --source "$src"
check_status "a reuse run exits 0" 0 "$STATUS"
check_eq "reuse moves the branch to the new sha" "$sha2" "$(git -C "$want" rev-parse HEAD)"
check_nofile "reuse drops an untracked leftover file" "$want/leftover"
check_nodir "reuse drops an untracked leftover dir" "$want/scratchdir"
check_nodir "reuse drops a leftover nested repo" "$want/nestedrepo"
check_eq "reuse stays on a branch" "$br" "$(git -C "$want" symbolic-ref -q --short HEAD || true)"
check_eq "reuse removes a fresh .DS_Store" "" "$(find "$want/.git" -name .DS_Store | head -1)"
check_eq "reuse leaves no hard-linked object file" "" "$(find "$want/.git/objects" -type f -links +1 | head -1)"

# the solo path
run "$tool" solo "$sha1" --source "$src"
check_status "solo exits 0" 0 "$STATUS"
check_dir "solo uses the canonical shared path" "$HOME/.keel/tmp/alpine-clone/.git"

# refusals — nothing is deleted or overwritten
mkdir -p "$HOME/.keel/tmp/alpine-clone-W6"; echo keep > "$HOME/.keel/tmp/alpine-clone-W6/data"
run "$tool" W6 "$sha1" --source "$src"
check_ne "a non-empty non-git dir is refused" 0 "$STATUS"
check_eq "a refused dir keeps its content" "keep" "$(cat "$HOME/.keel/tmp/alpine-clone-W6/data")"

other="$(new_repo)"; git -C "$other" commit -q --allow-empty -m x
git clone -q "$other" "$HOME/.keel/tmp/alpine-clone-W7"
run "$tool" W7 "$sha1" --source "$src"
check_ne "a clone whose origin is not the source is refused (stale origin)" 0 "$STATUS"
check_contains "the refusal names the origin" "$OUT" "origin"

run "$tool" W5 0123456789012345678901234567890123456789 --source "$src"
check_ne "an unknown sha is refused" 0 "$STATUS"
run "$tool" 'W5/../x' "$sha1" --source "$src"
check_status "a path-shaped worker id is a usage error" 2 "$STATUS"
run "$tool"
check_status "no arguments is a usage error" 2 "$STATUS"
run "$tool" W5 "$sha1" --source "$SANDBOX/nope"
check_ne "a --source that is not a repo is refused" 0 "$STATUS"

# --- dir #750: the clone path is resolved physically; nothing is reset or cleaned through a symlink ---------
# Each fixture is a DECOY that looks like a clone of the source (origin = the source, as the reuse guard
# requires) or the source itself with origin pointing at itself, planted with an untracked file. Before the
# fix the tool followed the link and ran `checkout -f -B keel-alpine-leg` + `clean -ffdx` on the target
# (S9-2, reproduced on an operator clone and on the source checkout). Everything lives under $SANDBOX; a
# separate HOME per case keeps the canonical clone paths of the groups above untouched.
# decoy_untouched DECOY LABEL — the planted file survives, the branch is the one it started on, and no
# keel-alpine-leg branch was created in it.
decoy_untouched() {
  check_file "$2: the planted untracked file survives" "$1/keep-me"
  check_eq "$2: HEAD still on its original branch" "$3" "$(git -C "$1" symbolic-ref -q --short HEAD || true)"
  check_eq "$2: no keel-alpine-leg branch was created in it" "" \
    "$(git -C "$1" for-each-ref --format='%(refname)' refs/heads/keel-alpine-leg)"
}

# self_origin_repo DIR — a repository at DIR with one commit, origin = itself (so the tool's origin check
# passes when DIR is the source) and an untracked keep-me file for decoy_untouched to find again.
self_origin_repo() {
  mkdir -p "$1"; git -C "$1" init -q
  echo s > "$1/f"; git -C "$1" add f; git -C "$1" commit -q -m s
  git -C "$1" remote add origin "$1"
  echo precious > "$1/keep-me"
}

# (a) the clone path IS a symlink to a plausible clone of the source
h1="$SANDBOX/h-symlink"; mkdir -p "$h1/.keel/tmp"
git clone -q "$src" "$SANDBOX/decoy-clone"
echo precious > "$SANDBOX/decoy-clone/keep-me"
decoy_branch="$(git -C "$SANDBOX/decoy-clone" symbolic-ref -q --short HEAD)"
ln -s "$SANDBOX/decoy-clone" "$h1/.keel/tmp/alpine-clone-W8"
run env HOME="$h1" "$tool" W8 "$sha1" --source "$src"
check_ne "750: a clone path that is a symlink is refused" 0 "$STATUS"
check_contains "750: …and the refusal names the symlink" "$OUT" "symlink"
decoy_untouched "$SANDBOX/decoy-clone" "750 symlink to a clone" "$decoy_branch"
check_eq "750: the link itself is left in place" "$SANDBOX/decoy-clone" "$(readlink "$h1/.keel/tmp/alpine-clone-W8")"

# (b) the symlink points at the source checkout itself, whose origin is itself
srcself="$(new_repo)"; self_origin_repo "$srcself"
self_branch="$(git -C "$srcself" symbolic-ref -q --short HEAD)"
self_sha="$(git -C "$srcself" rev-parse HEAD)"
ln -s "$srcself" "$h1/.keel/tmp/alpine-clone-W9"
run env HOME="$h1" "$tool" W9 "$self_sha" --source "$srcself"
check_ne "750: a symlink to the source checkout is refused" 0 "$STATUS"
decoy_untouched "$srcself" "750 symlink to the source" "$self_branch"

# (c) the clone path is a real directory name but resolves to the source through a symlinked ancestor
h2="$SANDBOX/h-ancestor"; mkdir -p "$h2/.keel" "$SANDBOX/real-tmp"
ln -s "$SANDBOX/real-tmp" "$h2/.keel/tmp"
srcanc="$SANDBOX/real-tmp/alpine-clone-W10"; self_origin_repo "$srcanc"
anc_branch="$(git -C "$srcanc" symbolic-ref -q --short HEAD)"
run env HOME="$h2" "$tool" W10 "$(git -C "$srcanc" rev-parse HEAD)" --source "$srcanc"
check_ne "750: a clone path that resolves to the source is refused" 0 "$STATUS"
check_contains "750: …and the refusal says it resolves to the source checkout" "$OUT" "resolves to the source checkout"
decoy_untouched "$srcanc" "750 ancestor link to the source" "$anc_branch"

# (d) a symlinked ANCESTOR that does not reach the source is fine: the clone is cut under the real directory
h3="$SANDBOX/h-ancestor-ok"; mkdir -p "$h3/.keel" "$SANDBOX/real-tmp-ok"
ln -s "$SANDBOX/real-tmp-ok" "$h3/.keel/tmp"
run env HOME="$h3" "$tool" W11 "$sha1" --source "$src"
check_status "750: a symlinked \$HOME/.keel/tmp is still usable" 0 "$STATUS"
check_dir "750: …and the clone lands under its real directory" "$SANDBOX/real-tmp-ok/alpine-clone-W11/.git"

# (e) the clone's `.git` is a symlink to another repository's git dir (the root test sees `.git`)
h4="$SANDBOX/h-gitlink"; mkdir -p "$h4/.keel/tmp/alpine-clone-W12"
git clone -q "$src" "$SANDBOX/decoy-gitdir"
echo precious > "$SANDBOX/decoy-gitdir/keep-me"
gl_branch="$(git -C "$SANDBOX/decoy-gitdir" symbolic-ref -q --short HEAD)"
ln -s "$SANDBOX/decoy-gitdir/.git" "$h4/.keel/tmp/alpine-clone-W12/.git"
run env HOME="$h4" "$tool" W12 "$sha1" --source "$src"
check_ne "750: a clone whose .git is a symlink is refused" 0 "$STATUS"
decoy_untouched "$SANDBOX/decoy-gitdir" "750 .git symlinked to another repo" "$gl_branch"

# --- dir #750 (S9-9): the "`.git` not at its root" refusal is pinned ----------------------------------------
# A non-empty target INSIDE another repository (which has origin = the source) answers `rev-parse --git-dir`
# with a path that is not `.git`. Without the root check the tool would fetch, `checkout -f -B` and
# `clean -ffdx` the ENCLOSING repository; it was saved only by an incidental `find` abort.
h5="$SANDBOX/h-nested"; mkdir -p "$h5/.keel/tmp/alpine-clone-W13"
git -C "$h5/.keel" init -q
git -C "$h5/.keel" remote add origin "$src"
git -C "$h5/.keel" commit -q --allow-empty -m enclosing
echo data > "$h5/.keel/tmp/alpine-clone-W13/data"
enc_branch="$(git -C "$h5/.keel" symbolic-ref -q --short HEAD)"
run env HOME="$h5" "$tool" W13 "$sha1" --source "$src"
check_ne "750: a target whose .git is not at its root is refused" 0 "$STATUS"
check_contains "750: …and the refusal says it is not a git clone" "$OUT" "not a git clone"
check_eq "750: …the target's content is kept" "data" "$(cat "$h5/.keel/tmp/alpine-clone-W13/data")"
check_eq "750: …the enclosing repository stays on its branch" "$enc_branch" "$(git -C "$h5/.keel" symbolic-ref -q --short HEAD || true)"
check_eq "750: …and no keel-alpine-leg branch was created in it" "" \
  "$(git -C "$h5/.keel" for-each-ref --format='%(refname)' refs/heads/keel-alpine-leg)"

# --run hands the clone to docker (a PATH shim records argv; no real docker is needed)
shim="$SANDBOX/shim"; mkdir -p "$shim"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/docker.args"\n' "$SANDBOX" > "$shim/docker"; chmod +x "$shim/docker"
run env PATH="$shim:$PATH" "$tool" W5 "$sha2" --source "$src" --run
check_status "--run exits like docker (0 from the shim)" 0 "$STATUS"
check_contains "--run mounts the clone" "$(cat "$SANDBOX/docker.args")" "-v $want:/keel"
check_contains "--run runs the suite on alpine" "$(cat "$SANDBOX/docker.args")" "alpine:3.21"

# the tool must never call rm: sessions are denied rm -rf, and a helper that needs it is the wrong shape
rm_hits="$(grep -nE '(^|[^[:alnum:]_-])rm[[:space:]]' "$tool" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
check_eq "the tool never calls rm" "" "$rm_hits"

summary
