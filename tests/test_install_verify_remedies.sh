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
check_absent "A41: …nor does the sync step call it wired" "$OUT" "already imports the linked core"
check_contains "A41: …it says the import does not resolve" "$OUT" "CLAUDE.md imports keel/CORE.md, which does not resolve"
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
check_absent "B21 import + block: …never \"rails load twice\", in Verify or the sync step" "$OUT" "rails load twice"
check_contains "B21 import + block: …the sync step leaves the block, saying why" "$OUT" "its embedded KEEL-CORE block is what loads the rails"
run "$doctor" --install "$h"
check_contains "B21 import + block: …doctor agrees: keep the block meanwhile" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "keep it until keel/CORE.md resolves"
check_contains "B21 import + block: …and says to remove the foreign keel/CORE.md link first (a re-run alone declines it)" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "remove what sits at keel/CORE.md first"
# …and an IDENTICAL block is not removed as a duplicate either (it is the only copy of the rails that loads).
h="$SANDBOX/b21-same"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/templates/CLAUDE.md" >> "$h/CLAUDE.md"   # the shipped block
rm -f "$h/keel/CORE.md"; ln -s "$SANDBOX/b21-nowhere" "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks --link
check_absent "B21 import + identical block, keel/CORE.md dangling: the block is not removed as a duplicate" "$OUT" "removed the embedded rails block"
check_contains "B21 import + identical block: …it is still in CLAUDE.md" "$(cat "$h/CLAUDE.md")" "KEEL-CORE-BEGIN"

# …nor is an embedded block (no import) swapped for an import of a keel/CORE.md this run declined.
h="$SANDBOX/b21-swap"; mkdir -p "$h/keel/CORE.md"
sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$REPO_ROOT/templates/CLAUDE.md" > "$h/CLAUDE.md"
run "$install" --home "$h" --no-hooks --link
check_status "B21 block only, a directory at keel/CORE.md → exit 0" 0 "$STATUS"
check_absent "B21 block only: …the block is not swapped for an import that would load nothing" "$OUT" "embedded rails swapped for the import line"
check_contains "B21 block only: …it is still in CLAUDE.md" "$(cat "$h/CLAUDE.md")" "KEEL-CORE-BEGIN"
check_contains "B21 block only: …the sync step says why it stays" "$OUT" "an import of it would load nothing"
check_contains "B21 block only: …and Verify says to keep it" "$OUT" "keep"$'\n'"       the block"
check_absent "B21 block only: …never \"Migrate when ready\" (that would leave no rails)" "$OUT" "Migrate when ready"

# --- A43 (K40) install side: every Verify remedy carries the home's layout ---------------------------------------
# remedy_of TEXT REL — the Verify decline line for REL.
remedy_of() { grep -F -- "--   $2 $np" <<<"$1" || true; }
h="$SANDBOX/a43-link"; mkdir -p "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks --link
check_status "A43 linked, a directory at keel/CORE.md → exit 0" 0 "$STATUS"
check_contains "A43 linked: …the Verify remedy carries --link" "$(remedy_of "$OUT" keel/CORE.md)" "re-run 'install.sh --link --home"
# …and doctor, over the same home (manifest layout=link): every install.sh remedy keeps --link, and the import GAP
# says the directory has to go first (a re-run declines it).
run "$doctor" --install "$h"
check_contains "A43 doctor, a directory at keel/CORE.md: G-RAILS-IMPORT-BROKEN says to remove it first" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "remove what sits at keel/CORE.md first"
check_contains "A43 doctor: …W-MANIFEST-DRIFT's re-run keeps the manifest's --link" "$(grep -F W-MANIFEST-DRIFT <<<"$OUT")" "re-run install.sh --link --home"
check_contains "A43 doctor: …after removing the directory install would decline" "$(grep -F W-MANIFEST-DRIFT <<<"$OUT")" "remove what sits at keel/CORE.md first"
check_absent "A43 doctor: …no bare re-run anywhere in the report (it would land in copy mode)" "$OUT" "install.sh --home"
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
# A copy home whose CLAUDE.md carries a core import: the slot keeps the manifest's copy mode, and the import GAP
# keeps --link, as on origin/main — the accepted two-modes-in-one-report cost until dir #789 decides what a core
# import means.
cp "$h/CLAUDE.md" "$h/CLAUDE.md.keep"
printf '@%s/elsewhere/keel/CORE.md\n' "$SANDBOX" >> "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_contains "A43 doctor copy + a core import: the import GAP advises --link" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "re-run install.sh --link"
check_absent "A43 doctor copy + a core import: …the slot keeps the manifest's copy mode (no --link; dir #789)" "$(gap_of "$OUT" commands/$foreign_cmd)" "--link"
cat "$h/CLAUDE.md.keep" > "$h/CLAUDE.md"
# A codex home: bin/keel, the audited mode's slot, is advised the --codex re-run.
h="$SANDBOX/a43-dcodex"; mkdir -p "$h"
run "$install" --codex --home "$h" --no-hooks
rm -f "$h/bin/keel"; ln -s "$SANDBOX/a43-nowhere-cli" "$h/bin/keel"
run "$doctor" --install --codex "$h"
check_contains "A43 doctor --codex: a codex home's dangling bin/keel is advised the --codex re-run" "$(gap_of "$OUT" bin/keel)" "re-run install.sh --codex --home"
# …and so is a top-level file both modes place (a codex install seeds LEARNINGS.md too).
rm -f "$h/LEARNINGS.md"; ln -s "$SANDBOX/a43-nowhere-learn" "$h/LEARNINGS.md"
run "$doctor" --install --codex "$h"
check_contains "A43 doctor --codex: a codex home's dangling top-level LEARNINGS.md keeps --codex" "$(gap_of "$OUT" LEARNINGS.md)" "re-run install.sh --codex --home"
# …but a dangling CLAUDE.md there belongs to a Claude-mode install (a --codex run never seeds it), while AGENTS.md
# under a Claude audit is an adopter's own file: the audited mode's re-run, never --codex.
ln -s "$SANDBOX/a43-nowhere-claude" "$h/CLAUDE.md"
run "$doctor" --install --codex "$h"
check_absent "A43 doctor --codex: a dangling CLAUDE.md is never advised --codex" "$(gap_of "$OUT" CLAUDE.md)" "--codex"
rm -f "$h/CLAUDE.md" "$h/AGENTS.md"; ln -s "$SANDBOX/a43-nowhere-agents" "$h/AGENTS.md"
run "$doctor" --install "$h"
check_contains "A43 doctor: a dangling AGENTS.md under a Claude audit is a GAP" "$(gap_of "$OUT" AGENTS.md)" "dangling symlink"
check_absent "A43 doctor: …advised the audited (Claude) mode's re-run, never --codex" "$(gap_of "$OUT" AGENTS.md)" "--codex"
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
cat "$h/CLAUDE.md.keep" > "$h/CLAUDE.md"
rm -f "$h/keel/CORE.md"
run "$doctor" --install "$h"
check_absent "A43 doctor linked, no manifest, keel/CORE.md gone: detection finds no link, so the slot is copy (an import does not count; dir #789)" "$(gap_of "$OUT" commands/$foreign_cmd)" "--link"
check_contains "A43 doctor: …while the import GAP keeps --link (the accepted two-modes cost)" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "re-run install.sh --link"
# The rails checks fire only on a context file that IMPORTS keel/CORE.md — the linked layout's own wiring — so
# they keep --link even when a plain re-run has since recorded layout=copy (keel/CORE.md gone → copy mode).
h="$SANDBOX/a43-import"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
rm -f "$h/keel/CORE.md"
run "$install" --home "$h" --no-hooks
check_eq "A43 import setup: the plain re-run recorded layout=copy" "copy" "$(sed -n 's/^layout=//p' "$h/.keel/install-manifest.claude")"
run "$doctor" --install "$h"
check_contains "A43 doctor: G-RAILS-IMPORT-BROKEN still advises --link over a layout=copy manifest" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "re-run install.sh --link --home"
# A --no-git home whose trim is gone keeps --no-git in that advice (its manifest says link-nogit).
h="$SANDBOX/a43-import-nogit"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link --no-git
rm -f "$h/keel/CORE.md"
run "$doctor" --install "$h"
check_contains "A43 doctor: …and a layout=link-nogit home keeps --no-git in it" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "re-run install.sh --link --no-git --home"
h="$SANDBOX/a43-dnogit"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link --no-git
ln -s "$SANDBOX/a43-nowhere" "$h/commands/$foreign_cmd"
run "$doctor" --install "$h"
check_contains "A43 doctor --no-git: the remedy keeps the trim (layout=link-nogit)" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link --no-git"
mv "$h/.keel/install-manifest.claude" "$h/.keel/install-manifest.claude.away"
run "$doctor" --install "$h"
check_contains "A43 doctor --no-git, no manifest: the trim is detected (--link --no-git)" "$(gap_of "$OUT" commands/$foreign_cmd)" "re-run install.sh --link --no-git"
mv "$h/.keel/install-manifest.claude.away" "$h/.keel/install-manifest.claude"
# W-MANIFEST-DRIFT's own remedy reads the disk, not the manifest it calls stale: the git rails restored by hand
# (keel/CORE.md a link again under layout=link-nogit) must not be re-trimmed by following it.
rm -f "$h/keel/CORE.md"; ln -s "$REPO_ROOT/CORE.md" "$h/keel/CORE.md"
run "$doctor" --install "$h"
dl="$(grep -F W-MANIFEST-DRIFT <<<"$OUT")"
check_contains "A43 doctor: a restored trim's W-MANIFEST-DRIFT advises the linked re-run" "$dl" "re-run install.sh --link --home"
check_absent "A43 doctor: …never --no-git from the stale manifest" "$dl" "--no-git --home"
rm -f "$h/commands/polish.md"
run "$doctor" --install "$h"
check_contains "A43 doctor: …and a slot remedy in the same report agrees (plain --link)" "$(grep -F W-CMDS-MISSING <<<"$OUT")" "re-run install.sh --link --home"
check_absent "A43 doctor: …never re-trimming the restored rails" "$(grep -F W-CMDS-MISSING <<<"$OUT")" "--no-git"
# A keel that is not a directory blocks keel/CORE.md as surely as an object at it: the import GAP says so.
h="$SANDBOX/a43-keelfile"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
mv "$h/keel" "$h/keel.away"; printf 'not a dir\n' > "$h/keel"
run "$doctor" --install "$h"
check_contains "A43 doctor, a file at keel: G-RAILS-IMPORT-BROKEN names keel itself as what to remove first" "$(grep -F G-RAILS-IMPORT-BROKEN <<<"$OUT")" "remove what sits at keel (it is not a directory) first"
# A context file that is there but not a regular file: G-RAILS-MISSING says it has to go first (install declines it).
h="$SANDBOX/a43-ctxlink"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks
rm -f "$h/CLAUDE.md"; ln -s "$SANDBOX/a43-nowhere-ctx" "$h/CLAUDE.md"
run "$doctor" --install "$h"
check_contains "A43 doctor, a dangling CLAUDE.md: G-RAILS-MISSING says to remove it first" "$(grep -F G-RAILS-MISSING <<<"$OUT")" "remove what sits there first"
# W-RAILS-UNWIRED on a copy home offers the migrate alternative — built so bash 3.2 (macOS /bin/bash) parses it.
rm -f "$h/CLAUDE.md"; printf '# mine\n' > "$h/CLAUDE.md"
if [ -x /bin/bash ]; then run /bin/bash "$doctor" --install "$h"; else run "$doctor" --install "$h"; fi
check_contains "A43 doctor, a copy home with no rails: W-RAILS-UNWIRED offers the migrate alternative, with the home" "$(grep -F W-RAILS-UNWIRED <<<"$OUT")" ", or migrate: install.sh --link --home"
check_absent "A43 doctor: …and the message is not garbled (no stray case syntax)" "$OUT" ";; esac"

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
