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
# not operating on. (dir #150: other_leaf itself dropped — it was only used by the removed default-leaf
# probe in other_mode_hint; the CONTEXT/cmd pair is still needed by the mismatch-refusal messages.)
CODEX_LEAF=".codex";  CODEX_CONTEXT="AGENTS.md"
CLAUDE_LEAF=".claude"; CLAUDE_CONTEXT="CLAUDE.md"
if [ "$CODEX" = 1 ]; then
  leaf="$CODEX_LEAF";  CONTEXT_FILE="$CODEX_CONTEXT";  other_context="$CLAUDE_CONTEXT"; other_cmd="uninstall.sh"
else
  leaf="$CLAUDE_LEAF"; CONTEXT_FILE="$CLAUDE_CONTEXT"; other_context="$CODEX_CONTEXT";  other_cmd="uninstall.sh --codex"
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

# manifest_field/manifest_usable (dir #125) — sourced from the shared tools/lib/manifest.sh (dir #363:
# previously a hand-copy here, verified output-identical to install.sh's own consumption of the same
# lib). REQUIRED, not optional — this script's whole removal decision is keyed off manifest state, so a
# checkout missing this lib cannot safely reason about ownership at all. Guarded the same way as
# tools/lib/artifact-cksum.sh just below (`[ -f ] && bash -n` pre-check, one actionable message, exit
# 1) — NOT bare like tools/lib/ledger.sh's own pre-existing, unaudited source further down: dir #362's
# own reasoning for guarding a required lib is about CORRUPTION, not about what the function's output
# feeds — a bare `.` of a present-but-corrupted file aborts at parse time under `set -e`, and no
# `if`/`&&` around the `.` command itself can catch that, so an unguarded required source hands the
# adopter a raw bash parse-error stack instead of a clean message. That reasoning applies here exactly
# as it does to artifact_cksum; matching ledger.sh's bare precedent instead would carry the same gap
# forward into two more libs rather than close it. (ledger.sh itself is untouched — out of scope here.)
if [ -f "$root/tools/lib/manifest.sh" ] && bash -n "$root/tools/lib/manifest.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/manifest.sh
  . "$root/tools/lib/manifest.sh"
else
  echo "uninstall: tools/lib/manifest.sh is missing or corrupted — refusing to remove anything without it, since an ownership decision needs a real manifest read; re-clone or re-download Keel and re-run uninstall.sh" >&2
  exit 1
fi
# manifest_recorded_home/mode FILE DEFAULT — the manifest's own recorded home=/mode=, falling back to
# DEFAULT when the field is empty (a well-formed-but-sparse manifest, in practice never hit against a
# real install.sh write, but the same "don't trust a possibly-missing field" posture manifest_field's
# own `|| true` takes). Two call sites share this shape: other_mode_hint (per ledger entry) and the
# mismatch refusal below (this run's own $other_manifest).
manifest_recorded_home() { local v; v="$(manifest_field "$1" home)"; [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"; }
manifest_recorded_mode() { local v; v="$(manifest_field "$1" mode)"; [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"; }
# this_usable/other_usable — manifest_usable "$this_manifest"/"$other_manifest" computed ONCE: both
# files are fixed for the whole run (only $HOME_DIR's ledger-loop candidates in other_mode_hint vary,
# so that call site still calls manifest_usable directly, per home). Everything below that asks
# "is THIS/THE OTHER mode's manifest here usable" reads these instead of re-deriving the same answer.
this_usable=0;  manifest_usable "$this_manifest"  && this_usable=1
other_usable=0; manifest_usable "$other_manifest" && other_usable=1
# artifact-cksum (dir #362) — REQUIRED, not optional: install.sh writes CKSUM_UNREADABLE/
# artifact_cksum's output unconditionally into a manifest `file` record, and the removal decision
# below (the `artifact_cksum "$apath" = "$extra"` comparison) trusts that value for a destructive
# choice. Refusing outright on a missing/corrupted lib — rather than degrading to a fallback stub — is
# the same "an ownership decision needs a real cksum comparison" posture install.sh's own copy of this
# guard documents; see tools/lib/artifact-cksum.sh's own header for the full reasoning. Same
# `[ -f ] && bash -n` pre-check as install.sh: a bare `.` can't be guarded against a parse-time
# syntax-error abort under `set -e`.
if [ -f "$root/tools/lib/artifact-cksum.sh" ] && bash -n "$root/tools/lib/artifact-cksum.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/artifact-cksum.sh
  . "$root/tools/lib/artifact-cksum.sh"
else
  echo "uninstall: tools/lib/artifact-cksum.sh is missing or corrupted — refusing to remove anything without it, since an ownership decision needs a real cksum comparison; re-clone or re-download Keel and re-run uninstall.sh" >&2
  exit 1
fi
# core-ownership (dir #363: keel_core_is_link/keel_core_is_nogit_trim) — REQUIRED, same
# guarded-and-required posture as tools/lib/manifest.sh above (see its own comment for why bare would
# be wrong here); see tools/lib/core-ownership.sh's own header for why install.sh's consumption
# differs (optional, with a byte-identical inline fallback).
if [ -f "$root/tools/lib/core-ownership.sh" ] && bash -n "$root/tools/lib/core-ownership.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/core-ownership.sh
  . "$root/tools/lib/core-ownership.sh"
else
  echo "uninstall: tools/lib/core-ownership.sh is missing or corrupted — refusing to remove anything without it, since an ownership decision needs a real predicate; re-clone or re-download Keel and re-run uninstall.sh" >&2
  exit 1
fi
# artifact_shared_with_other REL — dir #124's structural closure: true iff REL is ALSO a recorded
# artifact in the OTHER mode's manifest at this SAME home. Presence, not cksum agreement — the question
# is "does the other install still need this file to exist", not "do the two installs agree on its
# bytes" (they always do for a genuinely shared file: both wrote it from the same checkout).
#
# When the other manifest is UNUSABLE, this used to answer "not shared" — correct for a home where the
# other mode genuinely never ran, wrong for a MIXED-generation home where it ran once, under an OLD
# (pre-dir-125) checkout that never wrote a manifest at all (independent operator-run /code-review high
# pass: reproduced via `install.sh` + `install.sh --codex` at the same home, then deleting one mode's
# manifest to simulate its pre-migration state — the other mode's uninstall silently stripped bin/keel,
# FRAMEWORK.md and PRINCIPLES.md still needed by the un-migrated half). Falling back to "not shared"
# there means the manifest, which by the ticket's own contract may only ever narrow a removal — never
# widen it past what a filesystem check confirms — ends up authorizing exactly the blind strip that
# contract forbids, just because its evidence for the other mode happens to be missing rather than
# absent. Conservative instead: an unusable other manifest treats REL as shared whenever the other
# mode's OWN context file is present — plain existence, not "carries Keel's rails" (has_keel_rails was
# the first version of this fallback, and it read a foreign-core install as absent: install.sh's own
# foreign_core path — Keel installed over a pre-existing user CLAUDE.md/AGENTS.md — never writes a
# rails marker into that file even though the install is completely real, so the rails test answered
# "not shared" for exactly the live, unmanifested install this fallback exists to protect — dir #150
# audit, operator-run /code-review max: reproduced live via `install.sh` + `install.sh --codex` over a
# foreign CLAUDE.md, then deleting one mode's manifest — the advised `uninstall.sh --codex` stripped
# bin/keel, FRAMEWORK.md and PRINCIPLES.md still needed by the un-migrated foreign-core install).
# home_has_keel_content is NOT the right replacement here despite reading similarly, and despite being
# exactly right one call site up (the no-manifest refusal, below): that question is home-wide ("did an
# install of EITHER mode ever run against DIR"), so it is unconditionally true the moment THIS mode's
# own artifacts exist — which they always do here, since this function runs mid-removal of THIS mode's
# own manifest. That reads every removal as "shared" and uninstall becomes a permanent no-op (caught by
# this file's own baseline coverage going fully red the moment that swap was tried). The other context
# file's mere presence is the narrower, correct question: is there evidence, independent of THIS mode's
# content, that the OTHER mode's install genuinely happened here. Costs an over-wide keep whenever that
# file outlives the install it belonged to — routinely, per the scope correction below; the alternative
# costs a live install's shared files.
#
# **Named residual (dir #150 audit, operator-run /code-review max, 2nd pass), FIXED (dir #190,
# 2026-08-20 delta audit).** "Plain existence" and "carries evidence of a real install" are not the same
# question: a foreign-core install's own kept context file is, by construction (install.sh's foreign_core
# path never writes into it), indistinguishable from an unrelated user file that merely happens to share
# the name. That let every shared artifact read as "shared with the other install" and survive whenever
# `$other_context` existed for ANY reason — including the ORDINARY both-modes home (dir #124): uninstall
# never deletes the context file by design, so the first mode's removal always left a genuine
# `$other_context` behind for the second run's fallback to misread as an active sibling install (A/B-proven
# regression against v0.6.1, which completed the same sequence cleanly).
#
# S8's own widened predicate (`has_keel_rails "$other_context"` OR a surviving
# `.keel/install-manifest.<other>` OR a ledger entry for the other mode) does not actually close this
# without reopening dir #150's original bug: `has_keel_rails` is false for a foreign-core install by
# definition (that's the whole reason it exists), the surviving-manifest test is exactly what a
# manifest-deleted-to-simulate-pre-migration fixture (B22) sets to false on purpose, and the checkout-side
# ledger (tools/lib/ledger.sh) records a HOME, not a mode — it can't distinguish "the other mode ran here
# too" from "this mode's own install already added this home".
#
# Fixed instead with S8's other listed option (b): a manifest-INDEPENDENT sentinel
# (`.keel/foreign-core.<mode>`, written/cleared by install.sh's own foreign_core branch) that survives
# both the ordinary context-file survival AND a deliberately-deleted other manifest, while staying false
# for both an unrelated same-named stray file and an already-fully-uninstalled sibling mode (whose own
# uninstall clears its sentinel below, mirroring its manifest). `has_keel_rails` (via the cached
# $other_context_has_rails above) is kept in the OR as a second, independent path for a non-foreign-core
# install whose manifest was merely lost (dir #125's own pre-manifest-migration case, B18) — it still
# works there since a regular install DOES write rails.
#
# **Migration residual, named — and CONFIRMED live by an operator-run /code-review high pass, which
# also found this file's own framing of it understated the severity.** The sentinel is FORWARD-ONLY —
# it only exists for a foreign-core install placed by a checkout that already ships this change. A
# foreign-core install from an OLDER Keel, whose manifest later becomes unusable, has neither rails (by
# construction) nor a sentinel (it predates this fix), so this fallback still can't tell it apart from
# an unrelated stray file — the exact dir #150 shape, narrowed to that one population. No clean signal
# closes this without re-running `install.sh` for that mode (which records both a fresh manifest and the
# sentinel going forward).
#
# What changed after the /code-review pass: this used to fail OPEN — the ambiguous case (other_context
# exists, but neither rails nor sentinel confirm it) silently resolved to "not shared" and the artifact
# was stripped with no warning, exit 0, the ONE place in this file where an unresolved ambiguity acts
# instead of asking (contrast the no-manifest refusal and the cross-mode mismatch refusal just above,
# both of which stop and print advice rather than guess). It still CANNOT resolve to "refuse" or "keep"
# here — either breaks the dir #190 regression fix or dir #150's original one, an exhaustively-checked,
# genuine structural impossibility (no on-disk signal distinguishes "genuinely gone" from "genuinely
# still here, just old" for this one population) — but it no longer has to be SILENT about which case it
# guessed. $other_context_ambiguous, set alongside $other_context_shared_evidence below, marks exactly
# this: the removal loop further down prints a loud, distinct warning instead of a plain "removed" line
# whenever it strips an artifact on this unconfirmed guess, so an operator watching real output — not
# just this comment — sees the guess was made, same as this file's other named-but-acted-on-anyway cases
# (`"=    $rel differs from what Keel installed — kept (yours)"`,
# `"!    $rel: manifest recorded a symlink, but it's a regular file now — left in place"`).
artifact_shared_with_other() {
  if [ "$other_usable" = 1 ]; then
    awk -F'\t' -v rel="$1" '$1 ~ /^artifact=/ && $2 == rel { found=1 } END { exit !found }' "$other_manifest"
    return
  fi
  [ "$other_context_shared_evidence" = 1 ]
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

# other_context_shared_evidence — the WHOLE no-usable-other-manifest fallback answer computed ONCE, not
# re-derived per artifact (dir #190's /simplify pass hoisted has_keel_rails alone for this reason;
# an operator-run /code-review high pass found the sentinel [-f] check right next to it, added in the
# same diff, was left un-hoisted — same class of wasted syscall, same fix). $other_context, whether it
# carries rails, and the sentinel path are all invariant for the whole run, so the full OR is safe to
# fold into one flag here instead of re-stat'ing either signal once per artifact in the removal loop.
# Gated on other_usable=0, the only condition under which that fallback ever runs.
other_context_shared_evidence=0
other_context_ambiguous=0
if [ "$other_usable" = 0 ] && [ -f "$HOME_DIR/$other_context" ]; then
  # other_manifest_backed_up — dir #248: a backup dir from THIS TOOL's own prior removal
  # (_ensure_backup/take() below, "$HOME_DIR/.keel-uninstall-<ts>") that still holds the OTHER mode's
  # manifest is evidence from Keel's own bookkeeping, not a guess about the context file's current
  # shape: it means an `uninstall.sh --<other-mode>` run against THIS SAME HOME consumed that manifest
  # at some point, which is exactly dir #124's ordinary both-modes sequence (install claude, install
  # codex, uninstall claude, uninstall codex) — the surviving $other_context (never deleted, by design)
  # is a stripped-rails residual of a real completed uninstall, not an unconfirmed sibling. A manifest
  # deleted by hand rather than through this tool's own take() (dir #150's fixture) never creates this
  # backup dir. Computed here, inside the gate, rather than unconditionally above it — its only reader
  # is the elif below, so there's nothing to compute when other_usable=1 (both modes' manifests usable)
  # short-circuits this whole block anyway (/code-review high finding, this diff).
  # MONOTONIC, not a live-state check: backup dirs are never cleaned up, so once true for a mode at this
  # home it stays true forever — including after that mode is later reinstalled. Only ever consulted
  # below to narrow the AMBIGUOUS branch (neither rails nor sentinel confirm or refute); it must never
  # gate the has_keel_rails/sentinel check itself, which answers a live-state question this permanent
  # signal cannot (release-manager review, dir #248: an earlier version of this fix gated the whole block
  # on it, which skipped that check entirely whenever a stale backup dir existed and silently fell through
  # to "not shared" even for a live sibling install with intact rails — fail-open, reproduced live).
  # A stale backup dir surviving a LATER, independent loss of a reinstalled other mode's manifest (no
  # rails, no sentinel, no fresh backup — e.g. an old foreign-core reinstall whose manifest is hand-lost)
  # can still suppress this warning on that later run (/code-review high finding, this diff, CONFIRMED
  # but warning-only): reaching that population already requires dir #150's own accepted foreign-core/
  # no-sentinel gap, and removal was never gated on this warning either before or after this diff — see
  # artifact_shared_with_other's own comment and the removal loop below, which take()s regardless of
  # other_context_ambiguous. This narrows an already-accepted residual; it does not create a new one.
  other_manifest_backed_up=0
  for backup_manifest in "$HOME_DIR"/.keel-uninstall-*/.keel/install-manifest."$other_manifest_mode"; do
    [ -f "$backup_manifest" ] && other_manifest_backed_up=1 && break
  done

  if has_keel_rails "$HOME_DIR/$other_context" || [ -f "$HOME_DIR/.keel/foreign-core.$other_manifest_mode" ]; then
    other_context_shared_evidence=1
  elif [ "$other_manifest_backed_up" = 0 ]; then
    # dir #190 /code-review high (CONFIRMED, live-reproduced): other_context exists but nothing confirms
    # OR refutes a live sibling install — the removal loop below names this explicitly instead of
    # silently guessing "not shared" the way this used to. See artifact_shared_with_other's own comment
    # for why "refuse" or "keep" here isn't available either, structurally, not just as an unmade choice.
    # (see other_manifest_backed_up's own comment above for why this is reserved for the population
    # neither signal can confirm or refute.)
    other_context_ambiguous=1
  fi
fi

# is_keel_owned PATH SHIPPED — "this slot is Keel's, not yours": a symlink we wired, or a regular file
# byte-identical to what this checkout ships. A drifted copy is yours. Used by home_has_keel_content
# (dir #150: the manifest-driven removal steps no longer need this — cmp-to-checkout ownership was only
# ever the pre-manifest fallback's own test, removed along with it).
is_keel_owned() {
  [ -L "$1" ] && return 0
  [ -f "$1" ] && [ -n "${2:-}" ] && cmp -s "$1" "$2" && return 0
  return 1
}

# home_has_keel_content DIR — did an install ever run against DIR? Deliberately independent of the
# rails: an install over a pre-existing, foreign CLAUDE.md leaves that file untouched (install.sh's
# foreign_core path) while still wiring commands, bin/keel and the FRAMEWORK/PRINCIPLES copies, so
# "carries Keel's rails" is not the same question and answering it that way reads a real Keel home as
# empty (the foreign-core case hid behind a rails-only check twice before this function existed to
# close it for good). Takes the dir rather than closing over $HOME_DIR: dir #150's no-manifest refusal
# is its sole caller now, always with $HOME_DIR — the other caller this comment used to name
# (other_mode_hint's own content probe) was removed along with the pre-manifest fallback it belonged to.
# NOT a fit for artifact_shared_with_other's own no-usable-other-manifest fallback above, despite
# looking similar (operator-run /code-review max, dir #150 audit) — this question is home-wide ("did
# EITHER mode's install ever run here"), unconditionally true the moment THIS mode's own artifacts
# exist, which they always do at that call site since it runs mid-removal of THIS mode's own manifest.
# That fallback needs the narrower, other-mode-specific `[ -f "$HOME_DIR/$other_context" ]` instead.
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

# dir #228 (operator-decided 2026-08-20, ✅ DECIDED header in BACKLOG.md): a manifest-less --dry-run
# falls through to THIS heuristic listing instead of refusing — a dry run removes nothing, so the
# manifest refusal's own rationale ("can't guess what to remove") does not apply to it. Print-only
# (no take()/backup — those are only defined further down and dry-run never needs them anyway),
# mirroring the pre-dir-150 (v0.6.1) content-sniffed sweep's own candidate set. Explicitly labeled as
# heuristic (not manifest-confirmed) at both the caller and here, per the operator's decision. Runs
# before $take/$backup exist, so it can only echo, never touch disk — matches DRY_RUN's own contract.
# **Known duplication, accepted (found by /simplify's reuse+altitude passes, re-examined by an
# operator-run /code-review high pass):** this walks the same checkout-comparison candidate set as
# home_has_keel_content() above (keel/, bin/keel, FRAMEWORK.md, PRINCIPLES.md, commands/*.md) plus the
# keel-* alias slots that function omits — the two enumerations can silently drift on a future
# shipped-artifact change, and that alias rule is itself already duplicated a THIRD time by install.sh's
# own sync_product call site and a FOURTH by tools/doctor.sh's wiring check, pre-existing this diff. Not
# unified here: a callback-driven walker shared with home_has_keel_content's early-return-on-first-match
# shape, or a cross-file lib install.sh/uninstall.sh have no established sourcing convention for (see
# core_import_re/has_keel_rails's own "no established cross-sourcing convention" note above), is more
# machinery than this print-only, rarely-exercised (manifest-less --dry-run only) listing's blast radius
# earns on its own — worth a dedicated ticket if a fifth copy ever appears, not a same-round respin.
# **A FIFTH COPY APPEARED AND WAS THEN CLOSED (dir #347 added expected_symlink_source(), a
# hand-maintained mirror of this same keel-<name> alias/base-name relationship, near the
# manifest-driven removal loop further down; dir #369 replaced it with a data-driven read of the
# manifest's own recorded symlink target, so that copy no longer exists).** This function's own
# duplication (four copies) is untouched by that fix and stays exactly as described above — dir #369's
# scope was the manifest-driven removal loop, not this manifest-less dry-run heuristic, which still
# has no manifest data to read from and so still needs its own alias-mapping copy.
# **take() reuse considered and REJECTED, not just deferred** (the /code-review pass's own suggestion,
# verified empirically wrong): take() is defined far below (near the real removal loop), and this
# function is CALLED from the manifest-less branch above that definition in the script's own top-to-
# bottom execution — a bash function must be DEFINED (its `name() { … }` statement executed) before a
# call to it resolves, regardless of where in the file the two function bodies are textually written.
# Calling take() here would abort with "command not found" the first time this path runs, not silently
# reuse it — reproduced live with a minimal two-function repro mirroring this exact ordering.
dry_run_heuristic_listing() {
  local install_flag="$1" f slot cmd name alias_slot keel_dir_owned
  echo "  no usable manifest — this listing is heuristic (content-sniffed, not manifest-confirmed)."
  echo "  a REAL (non-dry) run in this same state refuses rather than removing — this listing only"
  echo "  previews what a manifest-driven removal would find, it is not a preview of what dropping"
  echo "  --dry-run here will actually do (an operator-run /code-review high pass live-reproduced the"
  echo "  two disagreeing: this listing names files a real run leaves untouched)."
  echo "  record one first, for an accurate real uninstall:  $root/install.sh$install_flag --home \"$HOME_DIR\""
  # dir #233 (found by PR #244's own /code-review high pass): existence alone (a directory or symlink
  # at this path) is not ownership — an unrelated user directory literally named `keel` at the home root
  # read as "would remove" here. Mirror install.sh's own linked-home detection instead: keel/CORE.md is
  # either a symlink (an ordinary linked install) or a regular file carrying the KEEL-NOGIT token (a
  # --no-git trim) — that is the actual ownership signal install.sh relies on to recognize its own
  # linked home (see its LINK-stickiness check near CONTEXT_FILE), not "a keel/ entry exists".
  # dir #279: CORE.md's own identity is not the ONLY evidence the keel/ dir is real — install.sh's
  # --link mode syncs keel/FRAMEWORK.md and keel/PRINCIPLES.md alongside it (sync_product, same
  # is_keel_owned test the FRAMEWORK.md/PRINCIPLES.md lines below use for the top-level copies), so a
  # home where only CORE.md was deleted or hand-edited but those siblings survive untouched still holds
  # real Keel content. NOT home_has_keel_content() — that question is home-wide (unconditionally true
  # the moment any of THIS mode's own artifacts exist) and would fold this line into the same "always
  # true" trap dry_run_heuristic_listing's own is_keel_owned-based checks below were written to avoid
  # (see artifact_shared_with_other's comment for the general shape of that trap).
  keel_dir_owned=0
  if keel_core_is_link "$HOME_DIR/keel/CORE.md" || keel_core_is_nogit_trim "$HOME_DIR/keel/CORE.md"; then
    keel_dir_owned=1
  elif is_keel_owned "$HOME_DIR/keel/FRAMEWORK.md" "$root/FRAMEWORK.md" || is_keel_owned "$HOME_DIR/keel/PRINCIPLES.md" "$root/PRINCIPLES.md"; then
    keel_dir_owned=1
  fi
  [ "$keel_dir_owned" = 1 ] && echo "  would remove  keel"
  if [ -L "$HOME_DIR/bin/keel" ]; then
    echo "  would remove  bin/keel"
  fi
  if [ -d "$root/commands" ]; then
    for cmd in "$root"/commands/*.md; do
      [ -f "$cmd" ] || continue
      name="$(basename "$cmd")"
      slot="$HOME_DIR/commands/$name"
      if is_keel_owned "$slot" "$cmd"; then echo "  would remove  commands/$name"; fi
      case "$name" in
        keel-*) ;;   # keel-* commands never get an alias
        *)
          if [ ! -f "$root/commands/keel-$name" ]; then
            alias_slot="$HOME_DIR/commands/keel-$name"
            if is_keel_owned "$alias_slot" "$cmd"; then echo "  would remove  commands/keel-$name"; fi
          fi ;;
      esac
    done
  fi
  for f in FRAMEWORK.md PRINCIPLES.md; do
    if is_keel_owned "$HOME_DIR/$f" "$root/$f"; then echo "  would remove  $f"; fi
  done
  if [ "$this_has_rails" = 1 ]; then
    echo "  would strip the Keel rails (import line / KEEL-CORE block) from $CONTEXT_FILE"
  fi
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
#
# dir #150: this used to ALSO probe the conventional default leaf ($HOME/$other_leaf) directly,
# independent of the ledger, because a pre-dir-125 install there could never be ledger-recorded. That
# probe is gone — the ledger (verified against a live, usable manifest) is now the only source, so a
# leftover other-mode install that has never recorded a manifest gets no hint here; re-running its own
# install.sh records one going forward.
other_mode_hint() {
  local h om rh rm
  [ -f "$ledger_file" ] || return 0
  while IFS= read -r h; do
    [ -n "$h" ] && [ "$h" != "$home_canon" ] || continue
    om="$h/.keel/install-manifest.$other_manifest_mode"
    manifest_usable "$om" || continue
    rh="$(manifest_recorded_home "$om" "$h")"
    rm="$(manifest_recorded_mode "$om" "$other_manifest_mode")"
    echo "  • A Keel install ($rm mode) is still in place at $rh — this run did not touch it."
    echo "    Remove it too:  $other_cmd --home \"$rh\""
  done < "$ledger_file"
}

# The /polish pre-PR gate's hooks, if wired machine-global at THIS home (tools/install-pre-pr-gate.sh
# --global / --home, a separate opt-in step install.sh never runs itself), are shared, deliberately-not-
# removed content: this uninstall doesn't know whether other repos still rely on the checkout's
# tools/pre-pr-gate.sh existing, so it leaves the hooks in place rather than guessing — but says so, with
# a tested removal path, instead of silently leaving 6 settings.json entries pointing at a script that
# may no longer exist once the checkout itself is deleted (dir #136).
#
# Called at every summary/reporting exit (removed=0, dry-run, done, and — dir #190's /simplify pass — the
# manifest-less --dry-run heuristic listing below), the same way other_mode_hint is: the hooks don't
# depend on whether THIS run found anything else to remove, so a plain "did it work?" re-run must still
# see them — code-review found that gating this on `removed > 0` silently dropped the note on exactly
# that check-in (operator-run /code-review).
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
# dir #125: a usable gate manifest supplies the precise PATH now — its own settings= is quoted verbatim
# (ground truth from the wire itself, not a re-derived $HOME_DIR/settings.json guess) — but the manifest
# is never trusted for the WIRED fact itself: it's owned by a separate installer this uninstall never
# touches, so it can go stale (hooks stripped by hand, or settings.json deleted outright) while the
# manifest lingers (independent operator-run /code-review high pass: a stale gate manifest made this
# print "still wired" — and the removal command it then advised — for hooks that were already gone).
# The structural jq/grep check below still runs against whichever settings= this resolves to, manifest
# or the deterministic default dir #150 kept on purpose (not a legacy fallback), so the hint is
# precise about WHERE but never blind about WHETHER. The gate manifest itself is untouched by ANY
# uninstall run (a separate opt-in installer owns it), so it's readable at every call site regardless of
# whether this run's own manifest housekeeping (further down) ran before or after this call.
gate_hooks_hint() {
  local settings
  if manifest_usable "$gate_manifest"; then
    settings="$(manifest_field "$gate_manifest" settings)"
    [ -n "$settings" ] || settings="$HOME_DIR/settings.json"
  else
    # dir #150 audit (kept, not a heuristic): without a usable gate manifest there is still only one
    # possible settings path for THIS home — install-pre-pr-gate.sh --global/--home always writes
    # exactly $HOME_DIR/settings.json, never anywhere else, so this isn't a guess among candidates the
    # way the removed pre-manifest removal sweep was.
    settings="$HOME_DIR/settings.json"
  fi
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
# dir #125: the evidence is the manifest SET, not a context-file heuristic — THIS mode's manifest
# absent + the OTHER mode's manifest present (and usable) at the same home is exactly the mismatch
# shape, and its advice quotes the OTHER manifest's own recorded home/mode: ground truth, immune to a
# cosmetic path spelling (a trailing slash, KEEL_HOME vs --home) fooling a string compare. When THIS
# mode's manifest IS usable there is no mismatch regardless of the other manifest (that's dir #124's
# coherent both-modes home) — the removal loop below leans on cross-manifest refcount to keep the
# shared half instead of a bare refusal.
#
# `[ "$this_has_rails" = 0 ]` guards a MIXED-generation home the manifest-only test alone reads wrong
# (independent operator-run /code-review high pass): one mode installed by an OLD (pre-dir-125)
# checkout — real content, no manifest — the other by the current one. Manifest-only would refuse here
# and advise the OTHER mode's uninstall, which is equally wrong — but since dir #150 removed the
# unmanifested-removal fallback this used to fall through to, a mixed-generation home now hits the
# generic "no usable manifest" refusal just below instead: re-run install.sh for THIS mode to record
# one, same as any other manifest-less install. Neither refusal branch itself removes anything — this
# branch and the "no usable manifest" one below only print advice and exit 2, so an unmanifested,
# foreign-core THIS mode (install.sh's foreign_core path: no rails marker ever written even though the
# install is genuinely real) landing here just gets pointed at the OTHER mode's uninstall, same as any
# other mismatch. The actual removal happens in THAT follow-up invocation, once its own manifest makes
# it $this_usable=1 and it reaches the removal loop below — which is where a foreign-core home used to
# get misread (artifact_shared_with_other's no-usable-other-manifest fallback tested has_keel_rails,
# always false for foreign-core, until it was fixed to use home_has_keel_content instead: dir #150
# audit, operator-run /code-review max reproduced the resulting strip live). Computed once here, not
# re-checked per branch below (found by /simplify's efficiency pass — the second branch used to call
# has_keel_rails on this same file a second time) — and only when $this_usable=0 at all: the common case
# (a usable manifest) never reaches either branch below, so computing it unconditionally would
# reintroduce a wasted call on every ordinary uninstall, just a different one than before.
this_has_rails=0
[ "$this_usable" = 0 ] && has_keel_rails "$HOME_DIR/$CONTEXT_FILE" && this_has_rails=1
if [ "$other_usable" = 1 ] && [ "$this_usable" = 0 ] && [ "$this_has_rails" = 0 ]; then
  other_home_recorded="$(manifest_recorded_home "$other_manifest" "$HOME_DIR")"
  other_mode_recorded="$(manifest_recorded_mode "$other_manifest" "$other_manifest_mode")"
  # dir #234: --dry-run falls through here too (exit 0, advisory) rather than refusing (exit 2), same
  # rationale as dir #228's neighboring "no usable manifest" fallthrough below — a dry run removes
  # nothing, so the refusal's rationale doesn't apply. Narrower than that fallthrough on purpose
  # (operator decision 2026-08-27): dry_run_heuristic_listing() is deliberately NOT called here — it
  # lists content-sniffed files in THIS home, and a mismatch is exactly the case where this is probably
  # not the home the caller meant, so a listing scoped to it would describe the wrong home rather than a
  # weaker answer. other_mode_hint()/gate_hooks_hint() still run, matching every other reporting exit.
  # The reason line stays mismatch-specific (not the "no usable manifest" text) regardless of branch.
  if [ "$DRY_RUN" = 1 ]; then
    echo "uninstall: $HOME_DIR holds a Keel install, but its recorded manifest is $other_mode_recorded mode, not $manifest_mode."
    echo "        (dry run — nothing will be changed)"
    echo "  That looks like the other install mode. Removing it from HERE would take the shared half"
    echo "  (commands, the CLI symlink, FRAMEWORK/PRINCIPLES) and leave the $other_mode_recorded rails sitting there."
    echo "  Reverse it with:  $other_cmd --home \"$other_home_recorded\""
    other_mode_hint
    gate_hooks_hint
    exit 0
  fi
  echo "uninstall: $HOME_DIR holds a Keel install, but its recorded manifest is $other_mode_recorded mode, not $manifest_mode." >&2
  echo "  That looks like the other install mode. Removing it from HERE would take the shared half" >&2
  echo "  (commands, the CLI symlink, FRAMEWORK/PRINCIPLES) and leave the $other_mode_recorded rails sitting there." >&2
  echo "  Nothing was changed. Reverse it with:  $other_cmd --home \"$other_home_recorded\"" >&2
  exit 2
elif [ "$this_usable" = 0 ]; then
  # dir #150: uninstall now REQUIRES this mode's own manifest to remove anything — the pre-manifest
  # content-sniffed removal sweep is gone. Still distinguish "no manifest, but a real install genuinely
  # lives here" (refuse with an actionable fix) from "nothing here at all" (an ordinary empty/foreign
  # dir, or a Keel home whose own context file was deleted — no error, falls through to the honest
  # no-op below). home_has_keel_content is also computed once, not per-branch: it does a cmp(1) per
  # shipped command/product file, so evaluating it twice would double that work for no reason.
  this_has_content=0
  home_has_keel_content "$HOME_DIR" && this_has_content=1
  if [ ! -f "$HOME_DIR/$CONTEXT_FILE" ] && [ -f "$HOME_DIR/$other_context" ] && [ "$this_has_content" = 1 ]; then
    echo "uninstall: $HOME_DIR holds a Keel install, but no $CONTEXT_FILE — it has $other_context instead." >&2
    echo "  That looks like the other install mode. Removing it from HERE would take the shared half" >&2
    echo "  (commands, the CLI symlink, FRAMEWORK/PRINCIPLES) and leave $other_context sitting there." >&2
    echo "  Nothing was changed. Reverse it with:  $other_cmd --home \"$HOME_DIR\"" >&2
    echo "  (If that $other_context is your own file and not Keel's, this run is what you wanted —" >&2
    echo "   rename it, or point --home at the right home.)" >&2
    exit 2
  elif [ "$this_has_content" = 1 ] || [ "$this_has_rails" = 1 ]; then
    this_mode_flag=""; [ "$manifest_mode" = "codex" ] && this_mode_flag=" --codex"
    # dir #228: --dry-run falls through to the heuristic listing (below) instead of refusing — the
    # refusal's own rationale is about REMOVING, and a dry run removes nothing. The real uninstall's
    # refusal (exit 2) is untouched. This is a REPORTING exit, not a refusal, so it carries the same two
    # hints every other reporting exit does (/simplify pass on dir #190/#228, matching gate_hooks_hint's
    # own "called at every summary/reporting exit" contract) — a refusal above stays hint-free on
    # purpose, but this path no longer is one.
    if [ "$DRY_RUN" = 1 ]; then
      echo "uninstall: $HOME_DIR holds a Keel install, but no usable install manifest is recorded at $this_manifest."
      echo "        (dry run — nothing will be changed)"
      dry_run_heuristic_listing "$this_mode_flag"
      other_mode_hint
      gate_hooks_hint
      exit 0
    fi
    echo "uninstall: $HOME_DIR holds a Keel install, but no usable install manifest is recorded at $this_manifest." >&2
    echo "  This install predates Keel's install manifest, or hasn't been re-run since — uninstall can no" >&2
    echo "  longer fall back to guessing what it owns here." >&2
    echo "  Record a manifest first, then re-run this uninstall:  $root/install.sh$this_mode_flag --home \"$HOME_DIR\"" >&2
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

# symlink ownership (dir #369, replacing dir #347 route 3's expected_symlink_source() table): a
# manifest `symlink` record's third field is now the TARGET install.sh actually wired at record time
# (dir #369's change to record_placed — `readlink DEST`, always an absolute path into that run's own
# $root), not the empty `-` placeholder it used to be. The removal loop below compares the live link's
# CURRENT target against that RECORDED one directly — no re-derivation of "what install.sh would wire
# TODAY" (which is what the deleted table did, hand-mirroring install.sh's own wiring with nothing
# enforcing the two stay in sync — exactly the hand-copy class dir #362 removed between these two files
# for artifact_cksum, and dir #363 removed more of for manifest_field/the CORE.md ownership predicate).
# The manifest is already the contract between the two scripts; this makes it the ONLY one for symlink
# provenance, with no separate table to fall out of sync.
#
# OLD-MANIFEST FAIL-CLOSED (dir #369's own compatibility decision, not left to fall out of the code):
# a manifest written by a PRE-dir-369 install.sh still carries the literal `-` placeholder in this
# field forever (nothing rewrites an old record until its own artifact is re-placed) — no manifest
# version bump for this, since the line format/arity is unchanged and neither script's parser cared
# what this field held before now. `-` can never equal a real `readlink` target, so the plain string
# comparison below already declines ownership for it without a special case — fail-closed, matching
# route 3's own original direction, just for a wider reason (no data recorded at all, not merely "no
# rule matched a fixed table"). The adopter regains auto-removal for that one artifact the next time
# install.sh re-places it (any drift-refresh or a plain re-run that still confirms the file, since
# record_placed re-derives EXTRA from the live symlink every time it's called) — until then it is kept,
# never removed, which costs nothing since removal is the destructive direction.
#
# kind_mismatch REL WAS NOW — the one wording for a manifest/filesystem kind disagreement, shared by
# the removal loop's three call sites (symlink recorded, now some other kind; file recorded, now a
# symlink; file recorded, now neither). Extracted by /code-review max's delta round (dir #347) once this
# diff's own new third call site made the pattern cross from coincidence to pattern — the same
# "worth doing once a copy count crosses that line" bar this file already applies to the keel-<name>
# alias-mapping duplication above. String-only: reproduces each of the three call sites' existing text
# byte-for-byte, and does not touch any of their own if/elif conditions — only what they print.
kind_mismatch() {
  echo "  !    $1: manifest recorded a $2, but it's $3 now — left in place (manifest/filesystem disagree)"
}

# 1-4 (dir #125, manifest-driven): the manifest IS the removal-candidate set — walk every artifact IT
# recorded, never the checkout's current file list (which is blind to what a later release added or an
# older release actually delivered — cmp-to-current-checkout wrongly kept an old release's untouched
# file the moment the checkout itself moved on). Ownership per recorded artifact:
#   symlink -> Keel's iff it's STILL a symlink on disk AND its CURRENT target matches the RECORDED one
#              (dir #369 — a fs/manifest KIND disagreement, or a symlink pointing somewhere else now,
#              is named, never acted on — the manifest never authorizes a blind rm; a pre-dir-369
#              record's `-` placeholder never matches a real target, so an old manifest fails closed)
#   file    -> Keel's iff it's STILL a regular file (not re-formed as a symlink, dir #347 route 1, nor
#              re-formed as anything else non-regular — both kind disagreements are named, never acted
#              on, same as the symlink arm's own two-way kind check) AND its CURRENT bytes match the
#              RECORDED cksum, with the RECORDED cksum itself never allowed to be the unreadable
#              sentinel (dir #347 route 2 — see tools/lib/artifact-cksum.sh's own header for why a
#              self-equal sentinel match must never authorize a removal)
# Cross-manifest refcount (dir #124's structural closure): an artifact ALSO listed in the OTHER mode's
# manifest at this same home is shared — kept and named, never silently stripped from under a rail the
# other install still loads.
#
# dir #150: this only ever runs when $this_usable=1 now — the refusal block above already exits when a
# real (but unmanifested) install is found, so there is no `else` heuristic sweep to fall to any more.
# When $this_usable=0 and execution reaches here at all, that refusal already established the home has
# no Keel content for this mode, so there is nothing to walk.
if [ "$this_usable" = 1 ]; then
  while IFS=$'\t' read -r akind rel extra; do
    [ -n "$rel" ] || continue
    apath="$HOME_DIR/$rel"
    owned=0
    if [ "$akind" = "symlink" ]; then
      if [ -L "$apath" ]; then
        if [ -n "$extra" ] && [ "$extra" != "-" ] && [ "$(readlink "$apath" 2>/dev/null)" = "$extra" ]; then
          owned=1
        else
          echo "  !    $rel: symlink no longer points where Keel would have wired it — left in place (kept, may be yours now)"
        fi
      elif [ -e "$apath" ]; then
        kind_mismatch "$rel" symlink "a regular file"
      fi
    elif [ "$akind" = "file" ]; then
      if [ -L "$apath" ]; then
        kind_mismatch "$rel" file "a symlink"
      elif [ -f "$apath" ]; then
        if [ "$extra" != "$CKSUM_UNREADABLE" ] && [ "$(artifact_cksum "$apath")" = "$extra" ]; then
          owned=1
        else
          echo "  =    $rel differs from what Keel installed — kept (yours)"
        fi
      elif [ -e "$apath" ]; then
        # The file-arm mirror of the symlink arm's own `-e` catch-all above (dir #347 /code-review max
        # finding): without this, a manifest `file` record whose slot is now a directory/fifo/device
        # falls through both `-L` and `-f` silently — fails closed (no owned=1, so still never removed)
        # but with no diagnostic at all, unlike the symlink arm's equivalent case. Worded to say what it
        # actually knows (neither a file nor a symlink), not "a regular file now" — the symlink arm's own
        # `-e` message says that, which is imprecise for a directory too, but that line predates this
        # diff and is left alone here.
        kind_mismatch "$rel" file "neither a file nor a symlink"
      fi
    fi
    [ "$owned" = 1 ] || continue
    if artifact_shared_with_other "$rel"; then
      echo "  =    $rel is shared with the $other_manifest_mode install — left in place"
    else
      if [ "$other_context_ambiguous" = 1 ]; then
        # dir #190 /code-review high (CONFIRMED, live-reproduced): nothing here confirms OR refutes a
        # live $other_manifest_mode install — removing on an unconfirmed guess, named loudly instead of
        # the silent exit-0 strip this used to be. If $other_context is a real, still-live install (the
        # residual this warns about), re-recording its manifest BEFORE this point would have avoided it.
        other_mode_install_flag=""; [ "$other_manifest_mode" = "codex" ] && other_mode_install_flag=" --codex"
        echo "  !    $rel: no evidence $other_context is gone (unconfirmed, no manifest/rails/sentinel) — removing anyway." >&2
        echo "       If that install is still real, restore it:  $root/install.sh$other_mode_install_flag --home \"$HOME_DIR\"" >&2
      fi
      take "$apath"
    fi
  done < <(awk -F'\t' '$1 ~ /^artifact=/ && $1 != "artifact=edit" { k = $1; sub(/^artifact=/, "", k); print k"\t"$2"\t"$3 }' "$this_manifest")

  # Empty-dir pruning: only ever removes a dir install itself may have created, and only once every
  # artifact that lived in it is gone (a symlink-mismatch or cksum-drift leftover keeps it non-empty).
  for d in keel bin commands; do
    [ -d "$HOME_DIR/$d" ] && [ "$DRY_RUN" = 0 ] && rmdir "$HOME_DIR/$d" 2>/dev/null || true
  done
fi

# 5. The global always-loaded file (CLAUDE.md; AGENTS.md under --codex) — never deleted (it may hold
# your edits): only the Keel-delivered rails come out, i.e. the @import line and/or the embedded
# KEEL-CORE block. Backed up before the edit.
# (core_import_re / has_keel_rails — and why the boundaries matter — are defined near the top.)
#
# $this_has_rails already holds the right answer here when $this_usable=0: either a refusal branch
# above already exited on it being 1, or execution fell through with it still 0 — nothing between its
# computation and here mutates $gclaude. Only $this_usable=1 (which never sets it at all, that whole
# `if`/`elif` block being scoped to $this_usable=0) needs a fresh call (found by an operator-run
# /code-review max pass: without this, the this_usable=0 no-op fall-through called has_keel_rails on
# the identical path twice).
gclaude="$HOME_DIR/$CONTEXT_FILE"
[ "$this_usable" = 1 ] && has_keel_rails "$gclaude" && this_has_rails=1
if [ "$this_has_rails" = 1 ]; then
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
#
# Gated on $this_usable, NOT bare file existence (independent operator-run /code-review high pass): a
# manifest this run itself treated as ABSENT — an unknown/future keel_manifest_version, per the
# versioning contract — was still being backed up and its home pruned from the ledger, silently
# destroying a newer install's own record the moment an OLDER uninstall.sh ran against it. "Treated as
# absent" has to mean untouched, not "ignored for reads, consumed for writes": leaving it in place also
# correctly keeps it counted by the $manifests_left glob just below, so the ledger entry and .keel/
# survive right along with it.
[ "$this_usable" = 1 ] && take "$this_manifest"
# dir #190: THIS mode's own foreign-core sentinel (install.sh's counterpart to $this_manifest, same
# gating) — mirrors the manifest's own lifecycle so a fully-uninstalled mode never leaves a stale
# sentinel behind for a later sibling-mode uninstall's artifact_shared_with_other to misread as "still
# installed here". take() is a silent no-op when the sentinel never existed (this mode wasn't foreign-core).
[ "$this_usable" = 1 ] && take "$HOME_DIR/.keel/foreign-core.$manifest_mode"
if [ "$DRY_RUN" = 0 ]; then
  # dir #190 /code-review high finding (CONFIRMED, live-reproduced): this glob used to only ever see
  # install-manifest.* — a still-live foreign-core install protected ONLY by its sentinel (no manifest,
  # no rails) left NOTHING in this glob once the sibling mode's own manifest was taken, so the ledger
  # entry for a home with a genuinely still-installed mode was pruned right out from under it. A
  # surviving foreign-core.* sentinel now counts exactly like a surviving manifest does.
  manifests_left=0
  for m in "$HOME_DIR"/.keel/install-manifest.* "$HOME_DIR"/.keel/foreign-core.*; do
    [ -e "$m" ] && manifests_left=1
  done
  if [ "$manifests_left" = 0 ]; then
    # shellcheck source=tools/lib/ledger.sh
    . "$root/tools/lib/ledger.sh"
    ledger_remove "$ledger_file" "$home_canon"
    rmdir "$HOME_DIR/.keel" 2>/dev/null || true
  fi
fi

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
# Explicit, not a fall-off-the-end: every OTHER exit in this script (0 and 2 alike) says so with an
# `exit N`; this success path is the one that didn't, leaving its reported code to whatever
# gate_hooks_hint's own last statement happens to return (currently always 0, but silently at the
# mercy of a future edit to that function) — found by an operator-run /code-review max pass, pre-existing
# and unrelated to dir #150's own changes, hardened here since this file was already open.
exit 0
