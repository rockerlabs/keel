#!/usr/bin/env bash
# stamp-release-bootstrap.sh — the version-stamp mechanism behind the release-pinned
# `releases/latest/download/bootstrap.sh` one-liner (dir #56). Two halves:
#  (a) the stamping tool itself: validates its tag arg, rewrites KEEL_DEFAULT_REF="" only, never
#      touches the tracked bootstrap.sh, refuses to double-stamp;
#  (b) the stamped copy actually changes bootstrap.sh's behaviour: it clones its OWN tag by
#      default, and KEEL_REF still overrides it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

stamp="$REPO_ROOT/tools/stamp-release-bootstrap.sh"

# --- (a) the stamping tool ------------------------------------------------------------------------

run "$stamp"
check_status "no tag arg -> exit 1" 1 "$STATUS"

run "$stamp" ""
check_status "empty tag -> exit 1" 1 "$STATUS"

run "$stamp" 'bad"tag'
check_status "tag with an embedded quote -> exit 1" 1 "$STATUS"

run "$stamp" "$(printf 'bad\ntag')"
check_status "tag with an embedded newline -> exit 1" 1 "$STATUS"

run "$stamp" 'bad\tag'
check_status "tag with an embedded backslash -> exit 1" 1 "$STATUS"

run "$stamp" v1.2.3
check_status "stamp to stdout -> exit 0" 0 "$STATUS"
check_contains "stdout carries the stamped default ref" "$OUT" 'KEEL_DEFAULT_REF="v1.2.3"'

# regression: a tag containing a character that's special to sed's s/// (/, &) must be substituted
# in literally, not reinterpreted as a delimiter or a whole-match backreference.
run "$stamp" "release/1.0"
check_status "stamp a tag with a slash -> exit 0" 0 "$STATUS"
check_contains "slash in the tag is copied through literally" "$OUT" 'KEEL_DEFAULT_REF="release/1.0"'

run "$stamp" "a&b"
check_status "stamp a tag with an ampersand -> exit 0" 0 "$STATUS"
check_contains "ampersand in the tag is copied through literally, not expanded to the whole match" \
  "$OUT" 'KEEL_DEFAULT_REF="a&b"'

outfile="$SANDBOX/bootstrap-stamped.sh"
run "$stamp" v1.2.3 "$outfile"
check_status "stamp to a file -> exit 0" 0 "$STATUS"
check_file "stamped file created" "$outfile"
check_contains "stamped file carries the tag" "$(cat "$outfile")" 'KEEL_DEFAULT_REF="v1.2.3"'
run sh -n "$outfile"
check_status "stamped file is still valid POSIX sh" 0 "$STATUS"

check_contains "tracked bootstrap.sh always ships an empty default ref" \
  "$(cat "$REPO_ROOT/bootstrap.sh")" 'KEEL_DEFAULT_REF=""'

# a source file with no KEEL_DEFAULT_REF="" line (already stamped, or drifted) must refuse rather
# than silently no-op or stamp twice. stamp-release-bootstrap.sh always reads its OWN repo's
# bootstrap.sh (../bootstrap.sh relative to the tool), so exercise the guard by copying the tool into
# a throwaway "repo" whose bootstrap.sh is already stamped/drifted.
drifted_tools="$SANDBOX/drifted-repo/tools"
mkdir -p "$drifted_tools"
cp "$stamp" "$drifted_tools/stamp-release-bootstrap.sh"
sed 's/KEEL_DEFAULT_REF=""/KEEL_DEFAULT_REF="v0.0.0"/' "$REPO_ROOT/bootstrap.sh" > "$SANDBOX/drifted-repo/bootstrap.sh"
run "$drifted_tools/stamp-release-bootstrap.sh" v2.0.0
check_status "refuses to stamp a source with no bare KEEL_DEFAULT_REF=\"\" line" 1 "$STATUS"
check_contains "explains the refusal" "$OUT" "already-stamped"

# --- (b) the stamped copy changes bootstrap.sh's own behaviour -----------------------------------
# Build a tiny fixture repo with the real templates/CORE files (so install.sh runs end to end), tag
# one commit, then roll the default branch BACK before that commit — so the tag is reachable only by
# naming it, never by cloning the branch tip. That isolates "did KEEL_DEFAULT_REF's tag actually get
# used" from "the branch tip happened to already have the marker".
fixture="$SANDBOX/fixture-repo"
mkdir -p "$fixture/templates" "$fixture/tools/lib"
cp "$REPO_ROOT/install.sh" "$fixture/install.sh"
# tools/lib/artifact-cksum.sh (dir #362) is REQUIRED, not optional, unlike manifest.sh/stat-portable.sh
# — install.sh refuses outright without it, so this fixture (otherwise deliberately tools/-lib-less)
# must carry this one file for the end-to-end install below to succeed at all.
cp "$REPO_ROOT/tools/lib/artifact-cksum.sh" "$fixture/tools/lib/artifact-cksum.sh"
cp "$REPO_ROOT/CORE.md" "$REPO_ROOT/FRAMEWORK.md" "$REPO_ROOT/PRINCIPLES.md" "$fixture/"
cp "$REPO_ROOT/templates/CLAUDE.md" "$REPO_ROOT/templates/INSTANCE.md" \
   "$REPO_ROOT/templates/LEARNINGS.md" "$REPO_ROOT/templates/IDEAS.md" "$fixture/templates/"
git -C "$fixture" init -q
git -C "$fixture" checkout -q -b main
git -C "$fixture" add -A
git -C "$fixture" commit -q -m "fixture: base"
base_sha="$(git -C "$fixture" rev-parse HEAD)"

printf '\nTAG-ONLY-MARKER\n' >> "$fixture/FRAMEWORK.md"
git -C "$fixture" commit -q -am "fixture: tag-only change"
git -C "$fixture" tag vtest
git -C "$fixture" reset -q --hard "$base_sha"   # main tip no longer has the marker

git config --global --add safe.directory '*'    # mirrors test_install.sh: CI containers clone as a different uid

stamped_boot="$SANDBOX/bootstrap-vtest.sh"
run "$stamp" vtest "$stamped_boot"
check_status "stamp vtest -> exit 0" 0 "$STATUS"

# unstamped bootstrap.sh, no KEEL_REF: clones main tip -> no marker (control)
plainhome="$SANDBOX/plain-home"
run env KEEL_REPO="$fixture" sh "$REPO_ROOT/bootstrap.sh" --home "$plainhome" --no-hooks
check_status "unstamped bootstrap -> exit 0" 0 "$STATUS"
check_absent "unstamped bootstrap installs main tip (no marker)" "$(cat "$plainhome/FRAMEWORK.md")" "TAG-ONLY-MARKER"

# stamped copy, no KEEL_REF: defaults to ITS OWN tag -> marker present
staghome="$SANDBOX/stamped-home"
run env KEEL_REPO="$fixture" sh "$stamped_boot" --home "$staghome" --no-hooks
check_status "stamped bootstrap (no KEEL_REF) -> exit 0" 0 "$STATUS"
check_contains "stamped bootstrap installs its own tag by default" "$(cat "$staghome/FRAMEWORK.md")" "TAG-ONLY-MARKER"

# stamped copy, KEEL_REF=main: the env var still overrides the baked-in default -> no marker
overridehome="$SANDBOX/override-home"
run env KEEL_REPO="$fixture" KEEL_REF=main sh "$stamped_boot" --home "$overridehome" --no-hooks
check_status "stamped bootstrap with KEEL_REF=main -> exit 0" 0 "$STATUS"
check_absent "KEEL_REF overrides the stamped default ref" "$(cat "$overridehome/FRAMEWORK.md")" "TAG-ONLY-MARKER"

summary
