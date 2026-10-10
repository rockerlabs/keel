#!/usr/bin/env bash
# test_mutation_lists.sh — every checked-in mutant list is current (dir #745, B20): each row of
# tests/mutants/*.tsv has five fields, an id unique in its file, a needle that still occurs exactly once (substring
# occurrences) in the file it names in the working tree, and a replacement that differs from the needle. A code edit
# that moves a needle turns this suite red until the list is updated, so a list cannot rot silently between sweeps
# (the S7-2 class: a proof that was true once). The parsing is tools/self/mutation-sweep.sh's own `--check`, so the
# sweep and this check cannot disagree on a row. KEEL_MUTANT_LISTS_DIR overrides the directory — the red samples
# below drive it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

sweep="$REPO_ROOT/tools/self/mutation-sweep.sh"
check_file "tools/self/mutation-sweep.sh exists" "$sweep"
TAB="$(printf '\t')"

# check_lists ROOT → OUT (every problem, prefixed by its list) and STATUS (0 only when every list in
# ${KEEL_MUTANT_LISTS_DIR:-tests/mutants} is sound and there is at least one). ROOT is the checkout the needles are
# resolved in (the sweep's top level = its cwd's).
check_lists() {
  local root="$1" dir="${KEEL_MUTANT_LISTS_DIR:-$REPO_ROOT/tests/mutants}" f rc p n=0
  OUT=""; STATUS=0
  for f in "$dir"/*.tsv; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    rc=0
    p="$(cd "$root" && bash "$sweep" --check "$f" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
      STATUS=1
      OUT="$OUT$(basename "$f"): $p
"
    fi
  done
  if [ "$n" -eq 0 ]; then STATUS=1; OUT="no *.tsv list in $dir"; fi
}

# --- the lists as shipped, against this working tree ---------------------------------------------------------------------
check_lists "$REPO_ROOT"
check_status "every checked-in mutant list is current (each needle occurs exactly once)" 0 "$STATUS"
[ "$STATUS" -eq 0 ] || printf '%s\n' "$OUT"
rows="$(cat "${KEEL_MUTANT_LISTS_DIR:-$REPO_ROOT/tests/mutants}"/*.tsv | grep -cv -e '^#' -e '^[[:space:]]*$' || true)"
check_ne "the shipped lists carry at least one mutant row" 0 "$rows"

# --- the red samples: a scratch repo, one file, one good list, then one defect at a time -------------------------------
fx="$(new_repo)"
printf 'alpha beta\nfoo foo\ngamma\n' >"$fx/f.txt"
mkdir -p "$SANDBOX/good" "$SANDBOX/bad"
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
{ echo '# a header'; echo; row m1 f.txt alpha ALPHA 'one'; row m2 f.txt gamma '' 'a deletion mutant'; } >"$SANDBOX/good/l.tsv"
KEEL_MUTANT_LISTS_DIR="$SANDBOX/good" check_lists "$fx"
check_status "good sample: a sound list passes" 0 "$STATUS"

bad_case() {   # bad_case LABEL EXPECTED-TEXT ROW… — one list holding the good header plus the rows given
  local label="$1" want="$2"; shift 2
  rm -f "$SANDBOX/bad"/*.tsv
  { echo '# header'; row m1 f.txt alpha ALPHA 'good row'; for r in "$@"; do printf '%s\n' "$r"; done; } >"$SANDBOX/bad/l.tsv"
  KEEL_MUTANT_LISTS_DIR="$SANDBOX/bad" check_lists "$fx"
  check_status "bad sample — $label: reported as failure" 1 "$STATUS"
  check_contains "bad sample — $label: says why" "$OUT" "$want"
}
bad_case "a needle that no longer occurs" "m9: needle occurs 0 times in f.txt, want 1" "$(row m9 f.txt 'moved away' x n)"
bad_case "two rows sharing an id" "m1: id repeated" "$(row m1 f.txt gamma G 'again')"
bad_case "a needle occurring twice on one line" "m9: needle occurs 2 times in f.txt, want 1" "$(row m9 f.txt foo FOO n)"
bad_case "a four-field row" "m9: 4 fields, want 5" "$(printf 'm9\tf.txt\tgamma\tG')"
bad_case "a replacement equal to its needle" "m9: replacement equals needle" "$(row m9 f.txt gamma gamma n)"
bad_case "a file that does not exist" "m9: file nofile.txt not found" "$(row m9 nofile.txt a b n)"
rm -f "$SANDBOX/bad"/*.tsv
KEEL_MUTANT_LISTS_DIR="$SANDBOX/bad" check_lists "$fx"
check_status "bad sample — a directory with no list: failure, not a vacuous pass" 1 "$STATUS"

# an escaped needle: \t in the list is a real TAB in the file
printf 'a\tb\n' >"$fx/t.txt"
{ row m1 t.txt 'a\tb' 'a b' 'tab'; } >"$SANDBOX/good/l.tsv"
KEEL_MUTANT_LISTS_DIR="$SANDBOX/good" check_lists "$fx"
check_status "a needle written with \\t matches a real TAB (same decoding as the sweep)" 0 "$STATUS"
check_ne "(the TAB fixture really holds a TAB)" "" "$(grep -c "a${TAB}b" "$fx/t.txt")"

summary
