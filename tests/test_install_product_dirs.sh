#!/usr/bin/env bash
# test_install_product_dirs.sh — dir #716 (docs/specs/685-symlink-policy.md slice 2, B7 + B8): the
# installer never writes into, and the uninstaller never takes files out of, a product directory that
# is really the Keel checkout's own. A19 is S4-4 (`<home>/docs` or `agents` symlinked INTO the checkout:
# install used to record the checkout's own files and uninstall moved them out, 25 -> 0). A20 is S4-1
# (a product directory that is a file or a dangling link aborted the install before it wrote a manifest).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

# mk_ck NAME — a scratch Keel checkout under $SANDBOX (a copy of this tree, committed as its own git
# repo so `git status` can prove the checkout is untouched); prints its path. The copy's .git is dropped
# first: in a worktree it is a pointer file to the real repository.
mk_ck() {
  local ck="$SANDBOX/$1"
  cp -R "$REPO_ROOT" "$ck" && rm -rf "$ck/.git"
  git -C "$ck" init -q
  git -C "$ck" add -A
  git -C "$ck" -c user.name=Alice -c user.email=alice@example.com commit -q -m fixture
  printf '%s' "$ck"
}
md_count() { find "$1" -maxdepth 1 -name '*.md' | wc -l | tr -d ' '; }
porcelain() { git -C "$1" status --porcelain -- "$2"; }

# --- A19: S4-4 round-trip, docs and agents ------------------------------------------------------------
for d in docs agents; do
  ck="$(mk_ck "a19-ck-$d")"; h="$SANDBOX/a19-h-$d"; mkdir -p "$h"
  ln -s "$ck/$d" "$h/$d"
  n0="$(md_count "$ck/$d")"
  run "$ck/install.sh" --home "$h" --no-hooks
  check_status "A19 $d: install with <home>/$d linked into the checkout exits 0" 0 "$STATUS"
  check_contains "A19 $d: the install output says $d was skipped" "$OUT" "$h/$d"
  check_contains "A19 $d: …because it lands inside the Keel checkout" "$OUT" "inside the Keel checkout"
  check_eq "A19 $d: install left the checkout's $d untouched" "$n0" "$(md_count "$ck/$d")"
  manifest="$h/.keel/install-manifest.claude"
  check_file "A19 $d: a manifest was written" "$manifest"
  check_eq "A19 $d: nothing under $d/ was recorded" 0 "$(grep -c -F "$(printf '\t%s/' "$d")" "$manifest" || true)"
  run "$ck/uninstall.sh" --home "$h" --yes
  check_status "A19 $d: uninstall exits 0" 0 "$STATUS"
  check_eq "A19 $d: uninstall left the checkout's $d/*.md count unchanged" "$n0" "$(md_count "$ck/$d")"
  check_eq "A19 $d: git status of the checkout's $d is empty" "" "$(porcelain "$ck" "$d")"
done

# --- A19 (K14): an uninstall over a manifest the baseline wrote -----------------------------------------
# The baseline recorded the checkout's own docs when <home>/docs was linked into it. Reproduce that
# manifest: install normally (docs recorded), then swap the real docs dir for a link into the checkout.
ck="$(mk_ck a19-ck-k14)"; h="$SANDBOX/a19-h-k14"; mkdir -p "$h"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A19 K14: fixture install exits 0" 0 "$STATUS"
check_contains "A19 K14: the fixture manifest records docs" "$(cat "$h/.keel/install-manifest.claude")" "docs/delegation.md"
n0="$(md_count "$ck/docs")"
mv "$h/docs" "$h/docs.moved"
ln -s "$ck/docs" "$h/docs"
run "$ck/uninstall.sh" --home "$h" --yes
check_status "A19 K14: uninstall exits 0" 0 "$STATUS"
check_eq "A19 K14: the checkout's docs/*.md count is unchanged" "$n0" "$(md_count "$ck/docs")"
check_eq "A19 K14: git status of the checkout's docs is empty" "" "$(porcelain "$ck" docs)"
check_contains "A19 K14: the skipped file is named, with the reason" "$OUT" "lies inside the Keel checkout"

# --- A19: the boundary — a SIBLING directory whose name starts with the checkout's name is followed ------
ck="$(mk_ck a19-ck-sib)"; h="$SANDBOX/a19-h-sib"; mkdir -p "$h"
mkdir -p "$ck-dots"
ln -s "$ck-dots" "$h/docs"
run "$ck/install.sh" --home "$h" --no-hooks
check_status "A19 sibling: install exits 0" 0 "$STATUS"
check_absent "A19 sibling: <checkout>-dots is NOT treated as inside the checkout" "$OUT" "inside the Keel checkout"
check_file "A19 sibling: the docs were installed through the link into the sibling" "$ck-dots/delegation.md"

# --- A20: S4-1 — a product directory that is a file or a dangling link never aborts the install -----------
a20() {  # a20 NAME DIR KIND — KIND is file | dangling
  local name="$1" dir="$2" kind="$3" ck h
  ck="$(mk_ck "a20-ck-$name")"; h="$SANDBOX/a20-h-$name"; mkdir -p "$h"
  if [ "$kind" = file ]; then printf 'mine\n' > "$h/$dir"; else ln -s "$SANDBOX/a20-nowhere-$name" "$h/$dir"; fi
  run "$ck/install.sh" --home "$h" --no-hooks
  check_status "A20 $name: install exits 0" 0 "$STATUS"
  check_file "A20 $name: the manifest was written" "$h/.keel/install-manifest.claude"
  check_contains "A20 $name: one skip line names the path" "$OUT" "$h/$dir"
  check_contains "A20 $name: …and says it is not a directory" "$OUT" "not a directory"
  case "$kind" in
    file)     check_eq "A20 $name: the adopter's file is untouched" "mine" "$(cat "$h/$dir")" ;;
    dangling) check_link "A20 $name: the dangling link is still a link" "$h/$dir"
              check_nofile "A20 $name: its target was not created" "$SANDBOX/a20-nowhere-$name" ;;
  esac
}
a20 agents-file agents file
a20 agents-dangling agents dangling
a20 commands-file commands file

summary
