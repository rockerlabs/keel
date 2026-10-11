#!/usr/bin/env bash
# test_install_verify_remedies.sh — spec 685 round 2, slice S5d (dir #751, #752). install.sh's Verify calls a
# declined link "not provably Keel's", never "yours", and warns that the always-on rails will NOT load whenever
# they cannot (B21; a decline still exits 0, D-14). Every remedy install.sh and tools/doctor.sh advise carries the
# home's own mode, so following it never converts a copy-mode home to linked or a Claude slot to --codex (B22).
# A FIFO at the context file is declined with one line and the run ends (dir #752).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"
doctor="$REPO_ROOT/tools/doctor.sh"
np="is not provably Keel's"
noload="the always-on rails will NOT load"

# n_lines TEXT NEEDLE — how many lines of TEXT contain NEEDLE (a fixed string).
n_lines() { match "$1" -c -F -- "$2" || true; }

# --- A41 (K38, R1-2): a link install from checkout A, the home's .keel/ lost, A moved to B, B/install.sh --link
ca="$SANDBOX/a41-A"; cb="$SANDBOX/a41-B"; h="$SANDBOX/a41-h"
tracked_tree_copy "$ca" || exit 1
mkdir -p "$h"
run "$ca/install.sh" --home "$h" --no-hooks --link
check_status "A41 setup: a link install from checkout A" 0 "$STATUS"
rm -rf "$h/.keel"
mv "$ca" "$cb"
run "$cb/install.sh" --home "$h" --no-hooks --link
check_status "A41: the lost-manifest, moved-checkout re-install exits 0 (a decline is not an error)" 0 "$STATUS"
check_eq "A41: …three keel/ links are not provably Keel's" 3 "$(n_lines "$OUT" "$np")"
check_eq "A41: …none is called yours" 0 "$(n_lines "$OUT" "is yours")"
check_contains "A41: …and Verify says the rails will NOT load" "$OUT" "$noload"
check_absent "A41: …instead of calling the dangling import OK" "$OUT" "OK   CLAUDE.md imports keel/CORE.md"
check_contains "A41: …naming the import that does not resolve" "$OUT" "keel/CORE.md does not resolve to a regular file"

# --- A42 (K39, R1-1): a dangling CLAUDE.md link, copy mode and (a guard) linked mode --------------------------
for m in copy link; do
  h="$SANDBOX/a42-$m"; mkdir -p "$h"; ln -s "$SANDBOX/a42-nowhere-$m" "$h/CLAUDE.md"
  lf=""; [ "$m" = link ] && lf=--link
  run "$install" --home "$h" --no-hooks ${lf:+"$lf"}
  check_status "A42 $m: a dangling CLAUDE.md link → exit 0" 0 "$STATUS"
  check_contains "A42 $m: …Verify says the rails will NOT load" "$OUT" "$noload"
  check_contains "A42 $m: …and declines the link" "$OUT" "CLAUDE.md $np"
done

# B21: an import that does not resolve beside an embedded KEEL-CORE block — the block alone loads the rails, so
# Verify must not call it "loads twice" (removing the block as told would leave no rails at all).
h="$SANDBOX/b21-block"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
printf '<!-- KEEL-CORE-BEGIN -->\nmy kept rails\n<!-- KEEL-CORE-END -->\n' >> "$h/CLAUDE.md"
rm -f "$h/keel/CORE.md"; ln -s "$SANDBOX/b21-nowhere" "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks --link
check_status "B21 import + block, keel/CORE.md dangling → exit 0" 0 "$STATUS"
check_contains "B21 import + block: …Verify says only the block loads the rails" "$OUT" "only its embedded"
check_absent "B21 import + block: …never \"the rails load twice\"" "$OUT" "the rails load twice"

# --- A43 (K40) install side: every Verify remedy carries the home's layout ---------------------------------------
# remedy_of TEXT REL — the Verify decline line for REL.
remedy_of() { grep -F -- "--   $2 $np" <<<"$1" || true; }
h="$SANDBOX/a43-link"; mkdir -p "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks --link
check_status "A43 linked, a directory at keel/CORE.md → exit 0" 0 "$STATUS"
check_contains "A43 linked: …the Verify remedy carries --link" "$(remedy_of "$OUT" keel/CORE.md)" "re-run 'install.sh --link --home"
h="$SANDBOX/a43-nogit"; mkdir -p "$h/keel/FRAMEWORK.md"
run "$install" --home "$h" --no-hooks --link --no-git
check_status "A43 --no-git, a directory at keel/FRAMEWORK.md → exit 0" 0 "$STATUS"
check_contains "A43 --no-git: …the Verify remedy keeps the trim" "$(remedy_of "$OUT" keel/FRAMEWORK.md)" "re-run 'install.sh --link --no-git --home"
h="$SANDBOX/a43-copy"; mkdir -p "$h/FRAMEWORK.md"
run "$install" --home "$h" --no-hooks
check_status "A43 copy, a directory at FRAMEWORK.md → exit 0" 0 "$STATUS"
check_contains "A43 copy: …the Verify remedy is a plain re-run" "$(remedy_of "$OUT" FRAMEWORK.md)" "re-run 'install.sh --home"
check_absent "A43 copy: …never --link" "$(remedy_of "$OUT" FRAMEWORK.md)" "--link"

# --- A43 (K40) doctor side: a copy-mode home with a dangling foreign link ---------------------------------------
# foreign_cmd — an adopter's own command name, planted as a dangling link (a variable, so the self-doctor's
# dead-reference check does not read the planted path as a reference).
foreign_cmd=mine.md
# gap_of TEXT PATH-SUFFIX — doctor's G-LINK-DANGLING line for the link ending in PATH-SUFFIX.
gap_of() { grep -F 'G-LINK-DANGLING' <<<"$1" | grep -F -- "$2 →" || true; }
h="$SANDBOX/a43-dcopy"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks
check_status "A43 doctor setup: a copy-mode install" 0 "$STATUS"
ln -s "$SANDBOX/a43-nowhere" "$h/commands/$foreign_cmd"
run "$doctor" --install "$h"
gl="$(gap_of "$OUT" commands/$foreign_cmd)"
check_contains "A43 doctor copy: a dangling foreign commands/ link is a GAP" "$gl" "dangling symlink"
check_absent "A43 doctor copy: …whose remedy has no --link" "$gl" "--link"
# Follow the advice as written: remove the link, then run the advised command.
advised="$(sed -n "s/.*then re-run \(install\.sh[^()]*\) from its home.*/\1/p" <<<"$gl")"
check_contains "A43 doctor copy: …the advised command reaches this home" "$advised" "install.sh --home \"$h\""
rm -f "$h/commands/$foreign_cmd"
eval "run \"\$REPO_ROOT\"/$advised --no-hooks"
check_status "A43 doctor copy: following the advice → exit 0" 0 "$STATUS"
run "$doctor" --install "$h"
check_eq "A43 doctor copy: …0 GAP lines for that path afterwards" "" "$(gap_of "$OUT" commands/$foreign_cmd)"
check_eq "A43 doctor copy: …and the home is still copy mode" "copy" "$(sed -n 's/^layout=//p' "$h/.keel/install-manifest.claude")"
check_nolink "A43 doctor copy: …keel/CORE.md was not made a link" "$h/keel/CORE.md"
# bin/keel, the slot wired in both modes: a copy home's remedy has no --link either.
rm -f "$h/bin/keel"; ln -s "$SANDBOX/a43-nowhere-cli" "$h/bin/keel"
run "$doctor" --install "$h"
gl="$(gap_of "$OUT" bin/keel)"
check_contains "A43 doctor copy: a dangling foreign bin/keel is a GAP" "$gl" "dangling symlink"
check_absent "A43 doctor copy: …whose remedy has no --link" "$gl" "--link"
# A Claude-mode copy home audited --codex: a Claude slot's remedy carries neither --codex nor --link.
ln -s "$SANDBOX/a43-nowhere" "$h/commands/$foreign_cmd"
run "$doctor" --install --codex "$h"
gl="$(gap_of "$OUT" commands/$foreign_cmd)"
check_contains "A43 doctor --codex on a Claude copy home: the Claude slot's dangling link is a GAP" "$gl" "dangling symlink"
check_absent "A43 doctor --codex: …its remedy has no --codex" "$gl" "--codex"
check_absent "A43 doctor --codex: …nor --link" "$gl" "--link"
# The manifest outranks detection: a link planted at keel/CORE.md does not make a layout=copy home linked.
mkdir -p "$h/keel"; ln -s "$SANDBOX/a43-nowhere-core" "$h/keel/CORE.md"
run "$doctor" --install "$h"
check_absent "A43 doctor copy, a link at keel/CORE.md: the manifest's layout=copy wins (no --link)" "$(gap_of "$OUT" commands/$foreign_cmd)" "--link"
rm -f "$h/keel/CORE.md"
# A codex home: bin/keel, the audited mode's slot, is advised the --codex re-run.
h="$SANDBOX/a43-dcodex"; mkdir -p "$h"
run "$install" --codex --home "$h" --no-hooks
rm -f "$h/bin/keel"; ln -s "$SANDBOX/a43-nowhere-cli" "$h/bin/keel"
run "$doctor" --install --codex "$h"
check_contains "A43 doctor --codex: a codex home's dangling bin/keel is advised the --codex re-run" "$(gap_of "$OUT" bin/keel)" "re-run install.sh --codex --home"
# A linked home keeps --link (the manifest's layout=link), with and without a usable manifest (detection).
h="$SANDBOX/a43-dlink"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
ln -s "$SANDBOX/a43-nowhere" "$h/commands/$foreign_cmd"
run "$doctor" --install "$h"
check_contains "A43 doctor linked: the remedy carries --link" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link"
mv "$h/.keel/install-manifest.claude" "$h/.keel/install-manifest.claude.away"
run "$doctor" --install "$h"
check_contains "A43 doctor linked, no manifest: --link from detection (keel/CORE.md is a link)" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link"
cp "$h/CLAUDE.md" "$h/CLAUDE.md.keep"; printf '# mine\n' > "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_contains "A43 doctor linked, no manifest, no import: --link from keel/CORE.md's link alone" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link"
# The rails checks fire only on a context file that IMPORTS keel/CORE.md — the linked layout's own wiring — so
# they keep --link even when a plain re-run has since recorded layout=copy (keel/CORE.md gone → copy mode).
h="$SANDBOX/a43-import"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
rm -f "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks
check_eq "A43 import setup: the plain re-run recorded layout=copy" "copy" "$(sed -n 's/^layout=//p' "$h/.keel/install-manifest.claude")"
run "$doctor" --install "$h"
check_contains "A43 doctor: G-RAILS-IMPORT-BROKEN still advises --link over a layout=copy manifest" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "re-run install.sh --link --home"
h="$SANDBOX/a43-dnogit"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link --no-git
ln -s "$SANDBOX/a43-nowhere" "$h/commands/$foreign_cmd"
run "$doctor" --install "$h"
check_contains "A43 doctor --no-git: the remedy keeps the trim (layout=link-nogit)" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link --no-git"
mv "$h/.keel/install-manifest.claude" "$h/.keel/install-manifest.claude.away"
run "$doctor" --install "$h"
check_contains "A43 doctor --no-git, no manifest: the trim is detected (--link --no-git)" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link --no-git"

# --- dir #752: a FIFO at the context file is declined and the run ends ------------------------------------------
# run_fifo_bounded FIFO CMD… — `run`, backgrounded with a bounded wait (macOS has no `timeout`); a hang releases
# the blocked reader through the FIFO before killing (tests/test_install.sh T14f's reaping, for the same reason).
run_fifo_bounded() {
  local fifo="$1" out="$SANDBOX/fifo-run.out" pid waited=0 wr; shift
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "${KEEL_TEST_HANG_BOUND:-120}" ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    : > "$fifo" 2>/dev/null &
    wr=$!
    pkill -P "$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    kill -9 "$wr" 2>/dev/null || true
    wait "$wr" 2>/dev/null || true
    STATUS=124; OUT="(still running after ${waited} s — killed)"; return 0
  fi
  STATUS=0; wait "$pid" || STATUS=$?
  OUT="$(cat "$out")"
}
if command -v mkfifo >/dev/null 2>&1; then
  for m in link copy; do
    h="$SANDBOX/fifo-$m"; mkdir -p "$h"; mkfifo "$h/CLAUDE.md" 2>/dev/null || true
    if [ ! -p "$h/CLAUDE.md" ]; then fail "#752 $m: the FIFO fixture was actually created" "mkfifo produced no FIFO"; continue; fi
    lf=""; [ "$m" = link ] && lf=--link
    run_fifo_bounded "$h/CLAUDE.md" "$install" --home "$h" --no-hooks ${lf:+"$lf"}
    check_status "#752 $m: a FIFO at CLAUDE.md does not hang install (exit 0)" 0 "$STATUS"
    check_eq "#752 $m: …one line declines it at the seed" 1 "$(n_lines "$OUT" "CLAUDE.md is not a regular file (left untouched")"
    check_contains "#752 $m: …Verify says the rails will NOT load" "$OUT" "$noload"
    check_file "#752 $m: …and the manifest is written" "$h/.keel/install-manifest.claude"
    if [ -p "$h/CLAUDE.md" ]; then pass "#752 $m: …the FIFO is left in place"; else fail "#752 $m: …the FIFO is left in place" "it is gone"; fi
    run_fifo_bounded "$h/CLAUDE.md" "$uninstall" --home "$h" --yes
    check_status "#752 $m: …and uninstall does not hang on it either (exit 0)" 0 "$STATUS"
    rm -f "$h/CLAUDE.md"
  done
  # The lib's own block reader refuses a FIFO too (defence in depth: every caller tests -f first today).
  h="$SANDBOX/fifo-lib"; mkdir -p "$h"; mkfifo "$h/CLAUDE.md" 2>/dev/null || true
  # shellcheck disable=SC2016  # $1/$2 belong to the inner bash
  run_fifo_bounded "$h/CLAUDE.md" bash -c '. "$1" && keel_core_has_block "$2"' _ "$REPO_ROOT/tools/lib/core-ownership.sh" "$h/CLAUDE.md"
  check_status "#752 lib: keel_core_has_block on a FIFO returns 1 without reading it" 1 "$STATUS"
  rm -f "$h/CLAUDE.md"
else
  pass "#752 mkfifo unavailable — the FIFO context-file guard is not exercised here"
fi

summary
