#!/usr/bin/env bash
# tools/doctor.sh --install audits the shipped docs (dir #650 D5): W-DOCS-MISSING when fewer docs
# than the checkout ships are present beside the installed FRAMEWORK.md — in every mode, --codex
# included, the advice carrying the mode flag — and the symlink-liveness loop walks a linked home's
# keel/docs/ (and keel/docs/drydock/), so a dangling doc link is G-LINK-DANGLING and one pointing into
# another checkout is W-LINK-FOREIGN. Doctor takes the home as a POSITIONAL argument (it has no --home
# flag — dir #513).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

c_home="$SANDBOX/copy-home"
run "$install" --home "$c_home" --no-hooks
check_status "copy install for the doctor fixture exits 0" 0 "$STATUS"
l_home="$SANDBOX/link-home"
run "$install" --link --home "$l_home" --no-hooks
check_status "linked install for the doctor fixture exits 0" 0 "$STATUS"
x_home="$SANDBOX/codex-home"
run "$install" --codex --home "$x_home" --no-hooks
check_status "codex install for the doctor fixture exits 0" 0 "$STATUS"

# --- fresh homes: no W-DOCS-MISSING, and the OK line says where it looked ------------------------
run "$doctor" --install "$c_home"
check_absent "A8: fresh copy home → no W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: fresh copy home → docs OK line names docs/" "$OUT" "OK   docs:"
run "$doctor" --install "$l_home"
check_absent "A8: fresh linked home → no W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: fresh linked home → docs OK line names keel/docs/" "$OUT" "present in keel/docs/"
run "$doctor" --install --codex "$x_home"
check_absent "A8: fresh codex home → no W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: fresh codex home → docs OK line names docs/" "$OUT" "present in docs/"

# --- remove one doc from each → W-DOCS-MISSING naming it ------------------------------------------
rm "$c_home/docs/grooming.md"
run "$doctor" --install "$c_home"
check_contains "A8: copy home missing a doc → W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: …names the missing doc" "$OUT" "grooming.md"
check_contains "A8: …advises a re-run of install.sh" "$OUT" "install.sh"
cp "$REPO_ROOT/docs/grooming.md" "$c_home/docs/grooming.md"

rm "$l_home/keel/docs/drydock/verifier.md"
run "$doctor" --install "$l_home"
check_contains "A8: linked home missing a doc → W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: …names the missing drydock doc" "$OUT" "drydock/verifier.md"
ln -s "$REPO_ROOT/docs/drydock/verifier.md" "$l_home/keel/docs/drydock/verifier.md"

rm "$x_home/docs/delegation.md"
run "$doctor" --install --codex "$x_home"
check_contains "A8: codex home missing a doc → W-DOCS-MISSING" "$OUT" "W-DOCS-MISSING"
check_contains "A8: …names the missing doc" "$OUT" "delegation.md"
wl="$(match "$OUT" -E 'W-DOCS-MISSING')"
check_contains "A8: under --codex the advice carries --codex (a bare re-run builds a second install)" "$wl" "--codex"
cp "$REPO_ROOT/docs/delegation.md" "$x_home/docs/delegation.md"

# --- the linked liveness loop walks keel/docs/ ----------------------------------------------------
# A doc link pointed at a missing target → G-LINK-DANGLING naming it.
ln -sfn "$SANDBOX/no-such-target.md" "$l_home/keel/docs/drydock/auditor.md"
run "$doctor" --install "$l_home"
check_contains "A8: a dangling keel/docs/drydock link → G-LINK-DANGLING" "$OUT" "G-LINK-DANGLING"
check_contains "A8: …naming the link" "$OUT" "drydock/auditor.md"
ln -sfn "$REPO_ROOT/docs/drydock/auditor.md" "$l_home/keel/docs/drydock/auditor.md"

# A doc link re-pointed at an IDENTICAL copy outside this checkout → W-LINK-FOREIGN naming it (the
# docs arm must precede the generic keel/ arm in doctor's `case`, or this never fires — D5(b)).
mkdir -p "$SANDBOX/other-checkout"
cp "$REPO_ROOT/docs/drydock/auditor.md" "$SANDBOX/other-checkout/auditor.md"
ln -sfn "$SANDBOX/other-checkout/auditor.md" "$l_home/keel/docs/drydock/auditor.md"
run "$doctor" --install "$l_home"
check_contains "A8: a keel/docs link into another checkout → W-LINK-FOREIGN" "$OUT" "W-LINK-FOREIGN"
check_contains "A8: …naming it" "$OUT" "auditor.md resolves outside this checkout"
ln -sfn "$REPO_ROOT/docs/drydock/auditor.md" "$l_home/keel/docs/drydock/auditor.md"
run "$doctor" --install "$l_home"
check_absent "A8: restored link → healthy again (no foreign/dangling)" "$OUT" "auditor.md"

summary
