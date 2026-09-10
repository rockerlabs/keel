#!/usr/bin/env bash
# tools/self/line-citations.sh (dir #382): the forbid ratchet on `<tracked-file>:<line>` citations —
# detection of the exact/basename/range/approximate forms, the tracked-path discriminator that keeps
# a test fixture's `doc.md:5` assertion string from reading as a citation, the fenced-block and
# CHANGELOG.md exclusions, the allowlist (with a mutation-proof pair), and a live leg asserting keel's
# OWN tree is clean so a new citation fails `tests/run.sh` locally, not just CI.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

lc="$REPO_ROOT/tools/self/line-citations.sh"

# --- --help / bad args -------------------------------------------------------------------------
run "$lc" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$lc" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$lc" /no/such/dir
check_status "missing REPO_DIR -> exit 2" 2 "$STATUS"

# --- fixture builder ---------------------------------------------------------------------------
# mk_repo TEXT — a git repo carrying src/widget.sh and notes/plan.md, plus notes/guide.md whose body
# is TEXT. Every citing case below differs only in that body, so each check names one variable.
#
# None of those fixture paths exists in keel itself, and that is load-bearing rather than incidental:
# an assertion string naming a path this repo DOES track is indistinguishable from a real citation,
# so this file would trip the very ratchet it tests. It did, on the first run: the fixture's citing
# file was named for keel's own top-level readme, and the expectation string naming it read as a live
# citation — which is also the cleanest demonstration there is that the check works.
mk_repo() {
  local d; d="$(new_repo)"
  mkdir -p "$d/src" "$d/notes"
  printf '#!/bin/sh\necho widget\n' > "$d/src/widget.sh"
  printf '# plan\n\nbody\n' > "$d/notes/plan.md"
  printf '%s' "$1" > "$d/notes/guide.md"
  ( cd "$d" && git add -A && git commit -q -m fixture )
  printf '%s' "$d"
}

# --- a citation naming a TRACKED file is forbidden ----------------------------------------------
d="$(mk_repo 'See src/widget.sh:2 for the echo.')"
run "$lc" "$d"
check_status "a citation into a tracked file -> exit 1" 1 "$STATUS"
check_contains "names the citing file and the token" "$OUT" "notes/guide.md:1 cites src/widget.sh:2"
check_contains "points the author at the replacement" "$OUT" "cite a stable anchor in src/widget.sh"

# --- the tracked-path discriminator -------------------------------------------------------------
# The same SHAPE, naming a path this repo does not track, is a test fixture's assertion string or an
# illustration — it cannot drift, because there is nothing here for it to drift against. This one
# distinction is what keeps the check off tests/test_self_prose_drift.sh's own `doc.md:5` pins.
d="$(mk_repo 'The tool prints ghost/missing.sh:42 on failure.')"
run "$lc" "$d"
check_status "a citation naming an untracked path -> exit 0" 0 "$STATUS"
check_contains "and is not counted as in scope at all" "$OUT" "0 citation(s) in scope"

# --- basename resolution, and its ambiguity guard -----------------------------------------------
d="$(mk_repo 'See widget.sh:2 — bare basename.')"
run "$lc" "$d"
check_status "a unique tracked basename resolves -> exit 1" 1 "$STATUS"
check_contains "and reports the path it resolved to" "$OUT" "cite a stable anchor in src/widget.sh"

d="$(mk_repo 'See widget.sh:2 — but two files carry that basename.')"
mkdir -p "$d/notes"
printf '#!/bin/sh\necho other\n' > "$d/notes/widget.sh"
( cd "$d" && git add -A && git commit -q -m ambiguous )
run "$lc" "$d"
check_status "an AMBIGUOUS basename resolves to nothing -> exit 0" 0 "$STATUS"

# --- range and approximate forms ----------------------------------------------------------------
d="$(mk_repo 'Contract at src/widget.sh:1-2 and roughly notes/plan.md:~3.')"
run "$lc" "$d"
check_status "range and ~approximate forms are caught -> exit 1" 1 "$STATUS"
check_contains "the range form" "$OUT" "cites src/widget.sh:1-2"
check_contains "the ~approximate form" "$OUT" "cites notes/plan.md:~3"

# --- noise that merely looks like a citation ----------------------------------------------------
d="$(mk_repo 'Serve on http://localhost:8080 at 09:30; print with sed -n 12,20p — widget.sh is fine.')"
run "$lc" "$d"
check_status "ports, clock times and bare filenames are not citations -> exit 0" 0 "$STATUS"

# --- exclusions ---------------------------------------------------------------------------------
d="$(mk_repo 'Clean prose.')"
printf 'History: src/widget.sh:2 was fixed in v1.\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -q -m changelog )
run "$lc" "$d"
check_status "CHANGELOG.md is history text, not scanned -> exit 0" 0 "$STATUS"

d="$(mk_repo 'Example output:

```
src/widget.sh:2: matched
```
')"
run "$lc" "$d"
check_status "a citation inside a fenced block is an example -> exit 0" 0 "$STATUS"

# --- the allowlist, with a mutation-proof pair --------------------------------------------------
# The pair is the point: the same tree reads red with the entry removed and green with it present, so
# a future refactor that silently stopped consulting the allowlist cannot pass this file.
d="$(mk_repo 'See src/widget.sh:2 for the echo.')"
mkdir -p "$d/tools/self"
printf '# comment only, no entries\n' > "$d/tools/self/line-citations-allow.txt"
( cd "$d" && git add -A && git commit -q -m allow-empty )
run "$lc" "$d"
check_status "an allowlist with no entries leaves the citation forbidden" 1 "$STATUS"

printf '# reason: covered by ticket dir #999\nnotes/guide.md src/widget.sh:2\n' > "$d/tools/self/line-citations-allow.txt"
( cd "$d" && git add -A && git commit -q -m allow-entry )
run "$lc" "$d"
check_status "the matching entry suppresses it -> exit 0" 0 "$STATUS"
check_contains "and the count reports it as allowlisted, not as absent" "$OUT" "1 allowlisted, 0 forbidden"

# An entry is keyed on the CITING file too, not on the token alone: the same citation from a
# different file is a different exemption and must still fire.
printf 'Also src/widget.sh:2 here.\n' > "$d/notes/plan.md"
( cd "$d" && git add -A && git commit -q -m second-citer )
run "$lc" "$d"
check_status "the same token from an unlisted citing file still fires" 1 "$STATUS"
check_contains "and it is the second citer that is named" "$OUT" "notes/plan.md:1 cites src/widget.sh:2"

# --- the allowlist file is not scanned as a citing file -----------------------------------------
# It names forbidden tokens by construction; scanning it would make every entry re-fire from inside
# its own exemption, and the check could never go green.
d="$(mk_repo 'Clean prose.')"
mkdir -p "$d/tools/self"
printf 'notes/guide.md src/widget.sh:2\n' > "$d/tools/self/line-citations-allow.txt"
( cd "$d" && git add -A && git commit -q -m allow-only )
run "$lc" "$d"
check_status "the allowlist's own entries do not fire against itself -> exit 0" 0 "$STATUS"

# --- KEEL_LINE_CITATIONS_ALLOW override ---------------------------------------------------------
d="$(mk_repo 'See src/widget.sh:2 for the echo.')"
alt="$d/../alt-allow.txt"
printf 'notes/guide.md src/widget.sh:2\n' > "$alt"
run env KEEL_LINE_CITATIONS_ALLOW="$alt" "$lc" "$d"
check_status "an out-of-tree allowlist path is honoured -> exit 0" 0 "$STATUS"

# An IN-TREE custom-named override must be self-excluded too, not just the default
# tools/self/line-citations-allow.txt name — the exclusion has to key on the path the allowlist
# actually resolved to, not on a hard-coded literal, or a custom in-tree path would scan (and
# re-fire against) its own exemption lines.
d="$(mk_repo 'Clean prose.')"
mkdir -p "$d/config"
printf 'README-not-used src/widget.sh:2\n' > "$d/config/custom-allow.txt"
( cd "$d" && git add -A && git commit -q -m custom-allow-in-tree )
run env KEEL_LINE_CITATIONS_ALLOW="$d/config/custom-allow.txt" "$lc" "$d"
check_status "a custom in-tree allowlist path does not fire against itself -> exit 0" 0 "$STATUS"

# --- the live ratchet ---------------------------------------------------------------------------
# Against keel's OWN tree, not a fixture. This is what makes `tests/run.sh` — half of this project's
# pre-push gate — reject a newly introduced line citation locally, at the one moment it is still
# cheap to replace with a stable anchor, rather than leaving that to CI a round-trip later.
run "$lc" "$REPO_ROOT" --quiet
check_status "keel's own tree carries no unlisted line citation" 0 "$STATUS"

summary
