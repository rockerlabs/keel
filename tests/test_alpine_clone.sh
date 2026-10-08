#!/usr/bin/env bash
# Tests for tools/self/alpine-clone.sh (dir #728) — the per-worker Alpine-leg clone helper. One test
# group per trap that cost a false red in 0.14.0: hard-linked packs (--no-hardlinks), a copied
# .DS_Store under .git (git clone exits 128 inside the container), and a detached HEAD (bootstrap
# --link exits 128). Plus the reuse guards: a path whose .git is not the expected clone is refused,
# and the tool never deletes. Every clone here comes from a sandbox repo via --source, never from the
# real checkout; HOME is the sandbox HOME lib.sh pins, so the canonical $HOME/.keel/tmp path is sandboxed.
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
# reuse: moves to the new sha, and re-cleans a .DS_Store that appeared since
: > "$want/.git/objects/.DS_Store"
run "$tool" W5 "$sha2" --source "$src"
check_status "a reuse run exits 0" 0 "$STATUS"
check_eq "reuse moves the branch to the new sha" "$sha2" "$(git -C "$want" rev-parse HEAD)"
check_nofile "reuse drops an untracked leftover file" "$want/leftover"
check_nodir "reuse drops an untracked leftover dir" "$want/scratchdir"
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

# --run hands the clone to docker (a PATH shim records argv; no real docker is needed)
shim="$SANDBOX/shim"; mkdir -p "$shim"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/docker.args"\n' "$SANDBOX" > "$shim/docker"; chmod +x "$shim/docker"
run env PATH="$shim:$PATH" "$tool" W5 "$sha2" --source "$src" --run
check_status "--run exits like docker (0 from the shim)" 0 "$STATUS"
check_contains "--run mounts the clone" "$(cat "$SANDBOX/docker.args")" "-v $want:/keel"
check_contains "--run runs the suite on alpine" "$(cat "$SANDBOX/docker.args")" "alpine:3.21"

# the tool must never delete: sessions are denied rm -rf, and a helper that needs it is the wrong shape
rm_hits="$(grep -nE '(^|[^[:alnum:]_-])rm[[:space:]]' "$tool" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
check_eq "the tool never calls rm" "" "$rm_hits"

summary
