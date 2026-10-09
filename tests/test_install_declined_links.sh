#!/usr/bin/env bash
# test_install_declined_links.sh — dir #685 follow-up (0.15.0 RC fix round, FIX-1): a link or non-regular file
# that install.sh DECLINED is not a failed install. docs/specs/685-symlink-policy.md B3, T4: "A decline is not an
# error: the run continues and exits 0." Before this fix a declined dangling link at a Verify-listed path
# (INSTANCE.md, LEARNINGS.md, IDEAS.md, CLAUDE.md/AGENTS.md, FRAMEWORK.md, PRINCIPLES.md, linked keel/*) made
# Verify print `MISS … re-run install.sh --link … from its new home`, exit 1 BEFORE the manifest write and leave
# `.install.lock` behind, so `uninstall.sh` then refused the unrecorded install. Also pinned here: the doctor's
# G-LINK-DANGLING remedy for a link Keel cannot prove its own (S3-3).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"
doctor="$REPO_ROOT/tools/doctor.sh"

# --- acceptance 1+2: each declined path, copy and linked mode ------------------------------------------------
# decl MODE KIND REL — MODE copy|link|codex; KIND dangling|live (a live link to a differing dotfile). The link
# is planted at $h/REL before the install.
decl() {
  local mode="$1" kind="$2" rel="$3" uninst="${4:-0}" h flag="" uflag="" tgt tag first=""
  tag="$mode-$kind-$(printf '%s' "$rel" | tr '/.' '--')"
  h="$SANDBOX/d-$tag"; tgt="$SANDBOX/d-$tag-target"
  mkdir -p "$h/$(dirname "$rel")"
  case "$mode" in link) flag="--link" ;; codex) flag="--codex"; uflag="--codex" ;; esac
  if [ "$kind" = live ]; then printf 'my own %s\n' "$rel" > "$tgt"; fi
  ln -s "$tgt" "$h/$rel"
  run "$install" --home "$h" --no-hooks $flag
  check_status "$tag: install exits 0" 0 "$STATUS"
  check_file "$tag: the manifest is written" "$h/.keel/install-manifest.$([ "$mode" = codex ] && echo codex || echo claude)"
  check_nodir "$tag: .install.lock is released" "$h/.install.lock"
  check_eq "$tag: the link is untouched" "$tgt" "$(readlink "$h/$rel")"
  if [ "$kind" = dangling ]; then
    check_nofile "$tag: its target was not created" "$tgt"
    check_absent "$tag: Verify does not print MISS" "$OUT" "MISS "
    check_contains "$tag: Verify prints a declined line naming it" "$OUT" "$rel is yours"
    check_contains "$tag: …with the remove-then-re-run remedy" "$OUT" "remove it, then re-run"
    if [ "$mode" = copy ]; then check_absent "$tag: …and never 'from its new home' for a copy-mode install" "$OUT" "from its new home"; fi
  else
    # (an EDIT target — linked CLAUDE.md — legitimately gets the import line appended THROUGH the link, so the
    # first line is the invariant, not the whole file)
    read -r first < "$tgt" || true
    check_eq "$tag: the dotfile target still starts with the adopter's own line" "my own $rel" "$first"
  fi
  if [ "$uninst" = 1 ]; then   # the uninstall reads the manifest, not the path: once per mode is enough
    run "$uninstall" --home "$h" --yes $uflag
    check_status "$tag: uninstall works from the manifest (exit 0)" 0 "$STATUS"
    check_eq "$tag: …and leaves the declined link alone" "$tgt" "$(readlink "$h/$rel")"
  fi
}
# dangling: every Verify-listed path (one OUT assertion set each); live: one row per decline class.
for rel in INSTANCE.md LEARNINGS.md IDEAS.md CLAUDE.md FRAMEWORK.md PRINCIPLES.md; do
  if [ "$rel" = INSTANCE.md ] || [ "$rel" = FRAMEWORK.md ]; then u=1; else u=0; fi
  decl copy dangling "$rel" "$u"
done
for rel in INSTANCE.md LEARNINGS.md IDEAS.md CLAUDE.md keel/CORE.md keel/FRAMEWORK.md keel/PRINCIPLES.md; do
  if [ "$rel" = INSTANCE.md ] || [ "$rel" = keel/CORE.md ]; then u=1; else u=0; fi
  decl link dangling "$rel" "$u"
done
decl codex dangling AGENTS.md 1
decl copy live INSTANCE.md 1
decl copy live FRAMEWORK.md 1
decl link live CLAUDE.md 1
decl link live keel/FRAMEWORK.md 0
decl codex live AGENTS.md 0

# A non-regular file (a folder) at a Verify-listed path is the same decline (T6), not a missing file.
h="$SANDBOX/d-dir"; mkdir -p "$h/FRAMEWORK.md"
run "$install" --home "$h" --no-hooks
check_status "a folder at FRAMEWORK.md: install exits 0" 0 "$STATUS"
check_file "…and writes its manifest" "$h/.keel/install-manifest.claude"
check_contains "…Verify reports it as yours, not MISS" "$OUT" "FRAMEWORK.md is yours"
check_absent "…no MISS line" "$OUT" "MISS "

# --- acceptance 3: a genuinely ABSENT core file still fails Verify -----------------------------------------------
h="$SANDBOX/absent-h"; mkdir -p "$h"
KEEL_TEST_REMOVE_BEFORE_VERIFY=FRAMEWORK.md run "$install" --home "$h" --no-hooks
check_status "an absent core file still fails the install (exit 1)" 1 "$STATUS"
check_contains "…naming it as MISS" "$OUT" "MISS FRAMEWORK.md"
check_contains "…and saying verification failed" "$OUT" "verification FAILED"

# --- acceptance 4: doctor's G-LINK-DANGLING remedy ------------------------------------------------------------
# (1) a dangling link Keel cannot prove its own (an adopter's wiring): remove it first.
h="$SANDBOX/dl-foreign"; mkdir -p "$h"
run "$install" --home "$h" --no-hooks --link
rm -f "$h/keel/PRINCIPLES.md"; ln -s "$SANDBOX/dl-nowhere" "$h/keel/PRINCIPLES.md"
run "$doctor" --install "$h"
gl="$(grep -F 'G-LINK-DANGLING' <<<"$OUT" | grep -F 'keel/PRINCIPLES.md')"
check_contains "doctor: a dangling link Keel cannot prove its own is a GAP" "$gl" "dangling symlink"
check_contains "doctor: …whose remedy is to remove the link first" "$gl" "remove the link first"
check_contains "doctor: …saying install never replaces a link Keel did not make" "$gl" "a link Keel did not make"
# (2) Keel's own link whose checkout moved (the manifest records exactly this target, inside its checkout):
# the relink advice stays.
gone="$REPO_ROOT/commands/moved-away-go.md"
ln -sfn "$gone" "$h/commands/go.md"
awk -F'\t' -v OFS='\t' -v t="$gone" '$1 == "artifact=symlink" && $2 == "commands/go.md" { $3 = t } { print }' \
  "$h/.keel/install-manifest.claude" > "$SANDBOX/dl-manifest.new" && cat "$SANDBOX/dl-manifest.new" > "$h/.keel/install-manifest.claude"
run "$doctor" --install "$h"
gl="$(grep -F 'G-LINK-DANGLING' <<<"$OUT" | grep -F 'commands/go.md')"
check_contains "doctor: a moved checkout's own link is still a GAP" "$gl" "dangling symlink"
check_contains "doctor: …and keeps the relink advice" "$gl" "re-run install.sh --link"
check_absent "doctor: …without telling you to remove it" "$gl" "remove the link first"

summary
