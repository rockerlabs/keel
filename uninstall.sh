#!/usr/bin/env bash
# uninstall — reverse install.sh. The mirror image of what install wires, and nothing more: it
# removes ONLY Keel-owned content (the linked keel/ consumption dir, the one @import line / embedded
# rails block in the global CLAUDE.md, the command symlinks + collision aliases, the keel PATH
# symlink, and any copy-mode FRAMEWORK/PRINCIPLES it placed). It NEVER touches your own files
# (INSTANCE.md, LEARNINGS.md, IDEAS.md, or a command you authored) and NEVER silently drops the
# machine-global secret-guard (a shared safety net — removing it is a separate, announced opt-in).
#
# Backs up before it removes: everything it takes out is MOVED into a timestamped backup dir under the
# home (CLAUDE.md is copied there before its in-place edit), so an uninstall is reversible — nothing is
# hard-deleted. Refuse-to-clobber in reverse: a file that differs from what Keel shipped is treated as
# yours and left in place.
#
# Mirrors install.sh's mode flags too: --codex reverses `install.sh --codex` (default home ~/.codex, the
# always-loaded file is AGENTS.md instead of CLAUDE.md). Any one run touches ONE home, so it NAMES an
# install of the other mode it finds rather than leaving it silently behind — and REFUSES outright when
# the home it was pointed at holds the other mode, since most of what it removes is shared between the
# two and it would otherwise half-dismantle that install (dir #109).
#
# Usage:
#   uninstall.sh                 remove from ${KEEL_HOME:-$HOME/.claude} (prompts on a terminal)
#   uninstall.sh --home DIR      remove from DIR
#   uninstall.sh --codex         reverse an  install.sh --codex  (default home ~/.codex, AGENTS.md)
#   uninstall.sh --yes           don't prompt (required when not run from a terminal)
#   uninstall.sh --dry-run       show what WOULD be removed, change nothing
#   uninstall.sh -h | --help
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"   # the Keel checkout (this script lives at the top level)

usage() {
  cat <<'EOF'
uninstall — reverse install.sh: remove Keel-owned content from your harness home, backing up
everything it takes out. Leaves your own files and the machine-global secret-guard untouched.

Usage:
  uninstall.sh                 remove from ${KEEL_HOME:-$HOME/.claude} (prompts on a terminal)
  uninstall.sh --home DIR      remove from DIR
  uninstall.sh --codex         reverse an  install.sh --codex  (default home ~/.codex, AGENTS.md)
  uninstall.sh --yes           don't prompt (required when not run from a terminal)
  uninstall.sh --dry-run       show what WOULD be removed, change nothing
  uninstall.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"
ASSUME_YES=0
DRY_RUN=0
CODEX=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --codex) CODEX=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done
# Home + context-file resolution mirrors install.sh's, flag for flag: a --codex install lands in
# $HOME/.codex and writes AGENTS.md, so its reversal has to look in the same place for the same file.
# The pairs are named because the mode checks below need the OTHER mode's pair — the one this run is
# not operating on.
CODEX_LEAF=".codex";  CODEX_CONTEXT="AGENTS.md"
CLAUDE_LEAF=".claude"; CLAUDE_CONTEXT="CLAUDE.md"
if [ "$CODEX" = 1 ]; then
  leaf="$CODEX_LEAF";  CONTEXT_FILE="$CODEX_CONTEXT";  other_leaf="$CLAUDE_LEAF"; other_context="$CLAUDE_CONTEXT"; other_cmd="uninstall.sh"
else
  leaf="$CLAUDE_LEAF"; CONTEXT_FILE="$CLAUDE_CONTEXT"; other_leaf="$CODEX_LEAF";  other_context="$CODEX_CONTEXT";  other_cmd="uninstall.sh --codex"
fi
# Exactly install.sh's precedence: an explicit target (--home, else $KEEL_HOME) outranks the mode's
# default leaf, so an install placed with `KEEL_HOME=X install.sh --codex` is reversed by
# `KEEL_HOME=X uninstall.sh --codex`. The mode/home mismatch that precedence makes possible is caught
# below rather than papered over here — see the refusal.
: "${HOME_DIR:=${HOME:?uninstall: set HOME, or pass --home DIR}/$leaf}"

# Install-manifest paths (dir #125) — one recorded state this script reads instead of re-deriving
# ownership heuristically at every site. manifest_mode/other_manifest_mode mirror install.sh's own
# $manifest_mode; the mismatch guard and the removal loop below both need BOTH names, since dir #124's
# coherent both-modes home can carry either manifest or both.
manifest_mode="claude"; other_manifest_mode="codex"
[ "$CODEX" = 1 ] && { manifest_mode="codex"; other_manifest_mode="claude"; }
this_manifest="$HOME_DIR/.keel/install-manifest.$manifest_mode"
other_manifest="$HOME_DIR/.keel/install-manifest.$other_manifest_mode"
gate_manifest="$HOME_DIR/.keel/install-manifest.gate"
# Same override install.sh/install-pre-pr-gate.sh honor (tools/lib/ledger.sh's own convention), so a
# test run never touches the real checkout's ledger.
ledger_file="${KEEL_LEDGER_FILE:-$root/.keel/installed-homes}"
# Canonicalized once for the two places below that compare $HOME_DIR against a ledger-recorded home=
# (itself always canonical — install.sh's own home_resolved): a cosmetic difference (trailing slash)
# must not miss a self-match. Falls back to the raw string when $HOME_DIR doesn't exist (yet) — the
# "no such home" early exit below is exactly that case, and there's nothing to canonicalize against.
home_canon="$(cd "$HOME_DIR" 2>/dev/null && pwd || printf '%s' "$HOME_DIR")"

# manifest_field FILE KEY — mirror of tools/doctor.sh's own copy (no established cross-sourcing
# convention between the two files — keep them in sync on drift, same note as core_import_re/
# has_keel_rails below). `|| true`: an existing-but-unreadable manifest must degrade to absent, never
# abort this script under set -euo pipefail.
manifest_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1 || true; }
# manifest_usable FILE — the versioning contract: present, readable, AND a keel_manifest_version this
# script knows how to read. Anything else (absent, corrupt, a future major version) is ABSENT — the
# KEEL-LEGACY-NOMANIFEST fallback fires, never a crash.
manifest_usable() {
  [ -f "$1" ] || return 1
  [ "$(manifest_field "$1" keel_manifest_version)" = "1" ]
}
# artifact_cksum FILE — mirror of install.sh's own (must stay byte-identical: its output is compared
# against what install.sh itself recorded, not re-derived independently).
artifact_cksum() {
  local sum size
  read -r sum size _ < <(cksum "$1" 2>/dev/null) || { printf 'cksum:0:0'; return; }
  printf 'cksum:%s:%s' "$sum" "$size"
}
# artifact_shared_with_other REL — dir #124's structural closure: true iff REL is ALSO a recorded
# artifact in the OTHER mode's manifest at this SAME home. Presence, not cksum agreement — the question
# is "does the other install still need this file to exist", not "do the two installs agree on its
# bytes" (they always do for a genuinely shared file: both wrote it from the same checkout).
artifact_shared_with_other() {
  manifest_usable "$other_manifest" || return 1
  awk -F'\t' -v rel="$1" '$1 ~ /^artifact=/ && $2 == rel { found=1 } END { exit !found }' "$other_manifest"
}

# core_import_re — THE definition of "this line IS the core @import", byte-identical to install.sh's
# has_core_import (which tools/doctor.sh --install mirrors too); tools/self/doctor.sh's check 1b holds
# the three to it. The boundaries are load-bearing, not decoration: matching by bare substring, as this
# used to, also hits a line that merely MENTIONS the path in prose — a backtick-quoted
# `@~/.claude/keel/CORE.md` in someone's own notes — and silently deletes it, contradicting the promise
# printed with the strip below, that the rest of your file is untouched (dir #108).
core_import_re='(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)'

# has_keel_rails FILE — the file carries Keel's always-on rails, embedded or imported.
has_keel_rails() {
  [ -f "$1" ] || return 1
  grep -q 'KEEL-CORE-BEGIN' "$1" 2>/dev/null || grep -qE "$core_import_re" "$1" 2>/dev/null
}

# is_keel_owned PATH SHIPPED — the removal steps' own rule for "this slot is Keel's, not yours": a
# symlink we wired, or a regular file byte-identical to what this checkout ships. A drifted copy is
# yours. Factored out here because home_has_keel_content asks the same question the steps do.
is_keel_owned() {
  [ -L "$1" ] && return 0
  [ -f "$1" ] && [ -n "${2:-}" ] && cmp -s "$1" "$2" && return 0
  return 1
}

# home_has_keel_content DIR — did an install ever run against DIR? Deliberately independent of the
# rails: an install over a pre-existing, foreign CLAUDE.md leaves that file untouched (install.sh's
# foreign_core path) while still wiring commands, bin/keel and the FRAMEWORK/PRINCIPLES copies, so
# "carries Keel's rails" is not the same question and answering it that way reads a real Keel home as
# empty. Takes the dir rather than closing over $HOME_DIR: BOTH callers below ask this about a home —
# the mismatch guard about the one being uninstalled, other_mode_hint about the one it is leaving
# alone — and the second is where keying on rails hid the same foreign-core case a THIRD time.
home_has_keel_content() {
  local home="$1" f slot
  if [ -d "$home/keel" ] || [ -L "$home/bin/keel" ]; then return 0; fi
  for f in FRAMEWORK.md PRINCIPLES.md; do
    if is_keel_owned "$home/$f" "$root/$f"; then return 0; fi
  done
  if [ -d "$root/commands" ] && [ -d "$home/commands" ]; then
    for f in "$root"/commands/*.md; do
      [ -f "$f" ] || continue
      slot="$home/commands/$(basename "$f")"
      if is_keel_owned "$slot" "$f"; then return 0; fi
    done
  fi
  return 1
}

# other_mode_hint — this run only ever touches ONE home, and the two install modes live in different
# ones. Without this an adopter who ran both is told "done"/"nothing to do" with a full set of Keel
# rails still loading into every session of the other harness. Symmetric on purpose: a --codex run
# names a leftover Claude install exactly as a plain run names a leftover Codex one (an asymmetric
# version of this was what let the mis-target refused below print a clean "done").
#
# dir #125: the primary source is now the checkout-side ledger — every home install.sh or
# install-pre-pr-gate.sh has EVER recorded, regardless of where it sits (impossible for the old
# $HOME/<leaf>-only probe to see a retargeted --home). Per the ledger's own read contract, a listed
# home is verified against a live manifest, never trusted blindly: a since-uninstalled entry (manifest
# gone) silently yields no hint, not a stale/wrong one. Excludes $home_canon (this run's own home) —
# the shared half of a coherent both-modes home is named in the removal summary itself, not here.
#
# Called explicitly at each of the three reporting exits rather than from an EXIT trap: the trap would
# also fire on the refusal paths (no --yes on a non-terminal, an unknown flag, the mismatch below),
# where a leftover-install hint is noise attached to a run that did nothing. The exit that matters most
# is the earliest — "no Keel home at ~/.claude" is exactly the run a Codex-only adopter makes first
# (dir #109).
#
# The advised command always carries --home, naming the OTHER manifest's own recorded home — ground
# truth, not a re-derived guess: a bare `$other_cmd` re-resolves the home from scratch, and an explicit
# target outranks the mode leaf (see the precedence above), so under KEEL_HOME the advice would
# otherwise send the operator BACK to the home they just uninstalled (reproduced by the operator's
# fourth /code-review pass, pre-dir-125).
other_mode_hint() {
  local hinted=0 h om rh rm
  if [ -f "$ledger_file" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] && [ "$h" != "$home_canon" ] || continue
      om="$h/.keel/install-manifest.$other_manifest_mode"
      manifest_usable "$om" || continue
      rh="$(manifest_field "$om" home)"; [ -n "$rh" ] || rh="$h"
      rm="$(manifest_field "$om" mode)"; [ -n "$rm" ] || rm="$other_manifest_mode"
      echo "  • A Keel install ($rm mode) is still in place at $rh — this run did not touch it."
      echo "    Remove it too:  $other_cmd --home \"$rh\""
      hinted=1
    done < "$ledger_file"
  fi
  [ "$hinted" = 1 ] && return 0
  # KEEL-LEGACY-NOMANIFEST: no ledger entry named the other mode (a home that predates any manifest,
  # or was hand-migrated) — fall back to today's $HOME/<leaf> probe, unchanged.
  [ -n "${HOME:-}" ] || return 0
  local other="$HOME/$other_leaf"
  [ "$other" != "$HOME_DIR" ] || return 0
  home_has_keel_content "$other" || has_keel_rails "$other/$other_context" || return 0
  echo "  • A Keel install is still in place at $other — this run did not touch it."
  echo "    Remove it too:  $other_cmd --home \"$other\""
}

if [ ! -d "$HOME_DIR" ]; then
  echo "uninstall: nothing to do — no Keel home at $HOME_DIR"
  other_mode_hint
  exit 0
fi

# Mode/home mismatch — refuse rather than half-dismantle. Steps 1-4 below (the linked keel/ dir, the
# CLI symlink, the commands, the FRAMEWORK/PRINCIPLES copies) are mode-AGNOSTIC and would fire happily
# on any Keel home, while only step 5 is mode-specific. So a --codex run aimed at a Claude home strips
# the shared half and leaves CLAUDE.md loading its rails forever — a half-dismantled install reported
# as a clean success. Reachable because an explicit target outranks the mode leaf (above):
# `KEEL_HOME=<claude-home> uninstall.sh --codex` is the felt case, and the reverse is just as possible.
#
# The three conditions are each load-bearing:
#   - this mode's context file ABSENT — its presence is what says an install of THIS mode ran here
#     (install always leaves one, whether it wrote the file or kept yours);
#   - the other mode's context file PRESENT — plain existence, NOT "carries Keel's rails". Requiring
#     rails was the first version of this guard and it let the whole foreign-core case through: an
#     install over someone's own pre-Keel CLAUDE.md never writes rails into it, so a --codex run aimed
#     there sailed past the guard and removed the commands, the CLI and both product copies of an
#     install nobody asked it to touch (found by the operator's second /code-review pass). The cost of
#     dropping the rails test is that this arm can't tell the other mode's context file from a file of
#     yours that happens to share its name — hence the hedge in the message below. Removing this
#     condition instead would DEADLOCK a Keel home with neither context file: each mode would refuse and
#     point at the other, leaving the install unremovable;
#   - the home holding Keel content — without it, a bare dir containing only the user's own AGENTS.md
#     would be refused with advice to re-run under --codex, which would then find nothing to do. With
#     it, that case falls through to the honest "no Keel-owned content" no-op below.
# A home with NEITHER context file is an ordinary empty/foreign dir, or a Keel home whose own context
# file you deleted — neither is a mismatch, and both go on to uninstall (or no-op) normally.
#
# dir #125: the evidence is now the manifest SET, not the context-file heuristic above — THIS mode's
# manifest absent + the OTHER mode's manifest present (and usable) at the same home is exactly the
# mismatch shape, and its advice quotes the OTHER manifest's own recorded home/mode: ground truth,
# immune to a cosmetic path spelling (a trailing slash, KEEL_HOME vs --home) fooling a string compare.
# When THIS mode's manifest IS usable there is no mismatch regardless of the other manifest (that's
# dir #124's coherent both-modes home) — the removal loop below leans on cross-manifest refcount to
# keep the shared half instead of a bare refusal. Only when NEITHER mode has ever recorded a manifest
# here does this fall to the KEEL-LEGACY-NOMANIFEST block: today's context-file heuristic, unchanged.
if manifest_usable "$other_manifest" && ! manifest_usable "$this_manifest"; then
  other_home_recorded="$(manifest_field "$other_manifest" home)"
  other_mode_recorded="$(manifest_field "$other_manifest" mode)"
  [ -n "$other_home_recorded" ] || other_home_recorded="$HOME_DIR"
  [ -n "$other_mode_recorded" ] || other_mode_recorded="$other_manifest_mode"
  echo "uninstall: $HOME_DIR holds a Keel install, but its recorded manifest is $other_mode_recorded mode, not $manifest_mode." >&2
  echo "  That looks like the other install mode. Removing it from HERE would take the shared half" >&2
  echo "  (commands, the CLI symlink, FRAMEWORK/PRINCIPLES) and leave the $other_mode_recorded rails sitting there." >&2
  echo "  Nothing was changed. Reverse it with:  $other_cmd --home \"$other_home_recorded\"" >&2
  exit 2
elif ! manifest_usable "$this_manifest" && ! manifest_usable "$other_manifest"; then
  # KEEL-LEGACY-NOMANIFEST: neither mode has ever recorded a manifest at this home.
  if [ ! -f "$HOME_DIR/$CONTEXT_FILE" ] && [ -f "$HOME_DIR/$other_context" ] && home_has_keel_content "$HOME_DIR"; then
    echo "uninstall: $HOME_DIR holds a Keel install, but no $CONTEXT_FILE — it has $other_context instead." >&2
    echo "  That looks like the other install mode. Removing it from HERE would take the shared half" >&2
    echo "  (commands, the CLI symlink, FRAMEWORK/PRINCIPLES) and leave $other_context sitting there." >&2
    echo "  Nothing was changed. Reverse it with:  $other_cmd --home \"$HOME_DIR\"" >&2
    echo "  (If that $other_context is your own file and not Keel's, this run is what you wanted —" >&2
    echo "   rename it, or point --home at the right home.)" >&2
    exit 2
  fi
fi

echo "Keel uninstall ← $HOME_DIR"
echo "        checkout $root"
if [ "$DRY_RUN" = 1 ]; then
  echo "        (dry run — nothing will be changed)"
elif [ "$ASSUME_YES" = 0 ]; then
  if [ -t 0 ]; then
    printf "Remove Keel-owned content from %s? Your own files are kept and everything is backed up. [y/N] " "$HOME_DIR"
    read -r reply || reply=""
    case "$reply" in [yY]|[yY][eE][sS]) : ;; *) echo "uninstall: aborted."; exit 0 ;; esac
  else
    echo "uninstall: not a terminal — pass --yes to confirm (or --dry-run to preview)." >&2
    exit 2
  fi
fi

# Backup dir, created lazily on the first real removal so a dry run (or a no-op uninstall) leaves no
# trace. Timestamped UTC so repeated runs never collide.
backup=""
removed=0
_ensure_backup() {
  [ -n "$backup" ] && return 0
  backup="$HOME_DIR/.keel-uninstall-$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  echo "  backup → $backup"
}

# take PATH — back up (preserving its path under the home) then remove. Symlinks are moved as-is
# (mv doesn't follow them), so the backup records exactly what was wired.
take() {
  local p="$1" rel dest
  [ -e "$p" ] || [ -L "$p" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "  would remove  ${p#"$HOME_DIR"/}"; removed=$((removed + 1)); return 0; fi
  _ensure_backup
  case "$p" in "$HOME_DIR"/*) rel="${p#"$HOME_DIR"/}" ;; *) rel="$(basename "$p")" ;; esac
  dest="$backup/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$p" "$dest"
  echo "  removed  $rel"
  removed=$((removed + 1))
}

# 1-4 (dir #125, manifest-driven): the manifest IS the removal-candidate set — walk every artifact IT
# recorded, never the checkout's current file list (which is blind to what a later release added or an
# older release actually delivered — cmp-to-current-checkout wrongly kept an old release's untouched
# file the moment the checkout itself moved on). Ownership per recorded artifact:
#   symlink -> Keel's iff it's STILL a symlink on disk (a fs/manifest disagreement is named, never
#              acted on — the manifest never authorizes a blind rm)
#   file    -> Keel's iff its CURRENT bytes match the RECORDED cksum (upgrade-precision replacement for
#              is_keel_owned's cmp-to-checkout, used below only by the legacy fallback)
# Cross-manifest refcount (dir #124's structural closure): an artifact ALSO listed in the OTHER mode's
# manifest at this same home is shared — kept and named, never silently stripped from under a rail the
# other install still loads.
if manifest_usable "$this_manifest"; then
  while IFS=$'\t' read -r akind rel extra; do
    [ -n "$rel" ] || continue
    apath="$HOME_DIR/$rel"
    owned=0
    if [ "$akind" = "symlink" ]; then
      if [ -L "$apath" ]; then
        owned=1
      elif [ -e "$apath" ]; then
        echo "  !    $rel: manifest recorded a symlink, but it's a regular file now — left in place (manifest/filesystem disagree)"
      fi
    elif [ "$akind" = "file" ]; then
      if [ -f "$apath" ]; then
        if [ "$(artifact_cksum "$apath")" = "$extra" ]; then
          owned=1
        else
          echo "  =    $rel differs from what Keel installed — kept (yours)"
        fi
      fi
    fi
    [ "$owned" = 1 ] || continue
    if artifact_shared_with_other "$rel"; then
      echo "  =    $rel is shared with the $other_manifest_mode install — left in place"
    else
      take "$apath"
    fi
  done < <(awk -F'\t' '$1 ~ /^artifact=/ && $1 != "artifact=edit" { k = $1; sub(/^artifact=/, "", k); print k"\t"$2"\t"$3 }' "$this_manifest")

  # Empty-dir pruning: only ever removes a dir install itself may have created, and only once every
  # artifact that lived in it is gone (a symlink-mismatch or cksum-drift leftover keeps it non-empty).
  for d in keel bin commands; do
    [ -d "$HOME_DIR/$d" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/$d" 2>/dev/null || true
  done
else
  # KEEL-LEGACY-NOMANIFEST: this mode never recorded a manifest at this home — today's heuristics,
  # unchanged: iterate what the CURRENT checkout ships and test each slot with is_keel_owned's cmp.
  take "$HOME_DIR/keel"

  if [ -L "$HOME_DIR/bin/keel" ]; then
    take "$HOME_DIR/bin/keel"
  elif [ -e "$HOME_DIR/bin/keel" ]; then
    echo "  =    bin/keel is not a symlink — left in place (not something install wired)"
  fi
  [ -d "$HOME_DIR/bin" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/bin" 2>/dev/null || true

  if [ -d "$root/commands" ]; then
    for cmd in "$root"/commands/*.md; do
      [ -f "$cmd" ] || continue
      name="$(basename "$cmd")"
      slot="$HOME_DIR/commands/$name"
      if is_keel_owned "$slot" "$cmd"; then
        take "$slot"
      elif [ -e "$slot" ]; then
        echo "  =    commands/$name differs from Keel's — kept (yours)"
      fi
      case "$name" in
        keel-*) ;;   # keel-* commands never get an alias
        *)
          if [ ! -f "$root/commands/keel-$name" ]; then
            alias_slot="$HOME_DIR/commands/keel-$name"
            if is_keel_owned "$alias_slot" "$cmd"; then
              take "$alias_slot"
            fi
          fi ;;
      esac
    done
    [ -d "$HOME_DIR/commands" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/commands" 2>/dev/null || true
  fi

  for f in FRAMEWORK.md PRINCIPLES.md; do
    slot="$HOME_DIR/$f"
    if is_keel_owned "$slot" "$root/$f"; then
      take "$slot"
    elif [ -e "$slot" ]; then
      echo "  =    $f differs from Keel's — kept (yours)"
    fi
  done
fi

# 5. The global always-loaded file (CLAUDE.md; AGENTS.md under --codex) — never deleted (it may hold
# your edits): only the Keel-delivered rails come out, i.e. the @import line and/or the embedded
# KEEL-CORE block. Backed up before the edit.
# (core_import_re / has_keel_rails — and why the boundaries matter — are defined near the top.)
gclaude="$HOME_DIR/$CONTEXT_FILE"
if has_keel_rails "$gclaude"; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "  would strip the Keel rails (import line / KEEL-CORE block) from $CONTEXT_FILE"
    removed=$((removed + 1))
  else
    _ensure_backup
    mkdir -p "$backup"
    cp "$gclaude" "$backup/$CONTEXT_FILE"
    # Drop the embedded block (markers inclusive) and any line carrying the core import. The regex
    # arrives through ENVIRON, not -v: awk applies escape processing to a -v assignment, which would
    # eat the `\.` and quietly widen the pattern — the exact class of drift this shared definition exists
    # to prevent.
    KEEL_IMPORT_RE="$core_import_re" awk '
      BEGIN             { re = ENVIRON["KEEL_IMPORT_RE"] }
      /KEEL-CORE-BEGIN/ { skip=1; next }
      /KEEL-CORE-END/   { skip=0; next }
      skip              { next }
      $0 ~ re           { next }
      { print }
    ' "$gclaude" > "$gclaude.keeltmp.$$" && mv -f "$gclaude.keeltmp.$$" "$gclaude"
    echo "  stripped the Keel rails from $CONTEXT_FILE (backup: $backup/$CONTEXT_FILE; the rest of your file is untouched)"
    removed=$((removed + 1))
  fi
fi

# 6. Install-manifest housekeeping (dir #125): the manifest is itself an artifact of the install being
# reversed, so it's backed up like anything else this run takes (take() handles dry-run for free).
# Once no install-manifest.* remains at this home (this mode's own, the other mode's, and the gate's —
# the same glob install-pre-pr-gate.sh's own uninstall path prunes on), the checkout ledger entry is
# stale and pruned, and .keel/ comes out too, but ONLY if nothing else lives there (a doctor-accept
# file, or a surviving manifest, keeps it).
[ -f "$this_manifest" ] && take "$this_manifest"
if [ "$DRY_RUN" = 0 ]; then
  manifests_left=0
  for m in "$HOME_DIR"/.keel/install-manifest.*; do
    [ -e "$m" ] && manifests_left=1
  done
  if [ "$manifests_left" = 0 ]; then
    if [ -f "$ledger_file" ]; then
      ledger_tmp="$ledger_file.keeltmp.$$"
      grep -vxF "$home_canon" "$ledger_file" > "$ledger_tmp" 2>/dev/null || : > "$ledger_tmp"
      mv -f "$ledger_tmp" "$ledger_file"
    fi
    rmdir "$HOME_DIR/.keel" 2>/dev/null || true
  fi
fi

# The /polish pre-PR gate's hooks, if wired machine-global at THIS home (tools/install-pre-pr-gate.sh
# --global / --home, a separate opt-in step install.sh never runs itself), are shared, deliberately-not-
# removed content: this uninstall doesn't know whether other repos still rely on the checkout's
# tools/pre-pr-gate.sh existing, so it leaves the hooks in place rather than guessing — but says so, with
# a tested removal path, instead of silently leaving 6 settings.json entries pointing at a script that
# may no longer exist once the checkout itself is deleted (dir #136).
#
# Called at every summary exit (removed=0, dry-run, done), the same way other_mode_hint is: the hooks
# don't depend on whether THIS run found anything else to remove, so a plain "did it work?" re-run must
# still see them — code-review found that gating this on `removed > 0` silently dropped the note on
# exactly that check-in (operator-run /code-review).
#
# A bare `grep -q 'pre-pr-gate.sh'` (the first version of this check) would false-fire on ANY mention —
# a permissions rule allowlisting `bash …/tools/pre-pr-gate.sh:*`, a comment, some unrelated value —
# not just an actually-wired hook (a second operator-run /code-review pass). Mirrors
# tools/doctor.sh's own `gate_hook_wired` structural jq query byte-for-byte (independent copy, not
# sourced — this file has no established cross-sourcing convention with tools/doctor.sh, same as
# core_import_re/has_keel_rails just above; keep the two in sync on drift), with the same fail-open
# fallback when jq isn't on PATH: a missing jq means "wired but inert" either way for the REAL gate, so
# this advisory hint degrading to the loose grep there is no worse than doctor's own posture.
#
# dir #125: a usable gate manifest is the precise source now — its own settings= is quoted verbatim
# (ground truth from the wire itself, not a re-derived $HOME_DIR/settings.json guess). Note this runs
# AFTER the manifest housekeeping step above moves $gate_manifest's SIBLING (this mode's own
# install-manifest) into the backup — the gate manifest itself is untouched by this uninstall (a
# separate opt-in installer owns it), so it's still there to read.
gate_hooks_hint() {
  if manifest_usable "$gate_manifest"; then
    local gset
    gset="$(manifest_field "$gate_manifest" settings)"
    [ -n "$gset" ] || gset="$HOME_DIR/settings.json"
    echo "  • The /polish pre-PR gate hooks are still wired in $gset — kept on purpose."
    echo "    To remove them too:  $root/tools/install-pre-pr-gate.sh --uninstall --home \"$HOME_DIR\""
    return 0
  fi
  # KEEL-LEGACY-NOMANIFEST: no gate manifest recorded — probe settings.json directly, unchanged.
  local settings="$HOME_DIR/settings.json"
  [ -f "$settings" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -e '.hooks.PreToolUse // [] | any(.matcher == "Bash" and (.hooks // [] | any(.command // "" | contains("pre-pr-gate.sh"))))' \
      "$settings" >/dev/null 2>&1 || return 0
  else
    grep -q 'pre-pr-gate.sh' "$settings" 2>/dev/null || return 0
  fi
  echo "  • The /polish pre-PR gate hooks are still wired in $settings — kept on purpose."
  echo "    To remove them too:  $root/tools/install-pre-pr-gate.sh --uninstall --home \"$HOME_DIR\""
}

# --- summary ------------------------------------------------------------------------------------
echo
if [ "$removed" = 0 ]; then
  echo "uninstall: found no Keel-owned content at $HOME_DIR — nothing removed."
  other_mode_hint
  gate_hooks_hint
  exit 0
fi
if [ "$DRY_RUN" = 1 ]; then
  echo "uninstall: dry run — $removed item(s) would be removed. Re-run without --dry-run to apply."
  other_mode_hint
  gate_hooks_hint
  exit 0
fi
echo "uninstall: done — $removed item(s) removed (backed up in $backup)."
echo "  • Your INSTANCE.md / LEARNINGS.md / IDEAS.md and any command you authored were left in place."
other_mode_hint

# The machine-global secret-guard is deliberately NOT removed: it's a shared safety net that may guard
# repos beyond Keel, and dropping it silently would weaken protection. Report it as an opt-in manual step.
hp="$(git config --global core.hooksPath 2>/dev/null || true)"
case "$hp" in
  *keel-hooks)
    echo "  • The machine-global secret-guard is still wired (core.hooksPath=$hp) — kept on purpose."
    echo "    To remove it too:  git config --global --unset core.hooksPath && rm -rf \"$hp\""
    ;;
esac

gate_hooks_hint
