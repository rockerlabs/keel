#!/usr/bin/env bash
# install — one-command bootstrap for Keel into your harness home.
#
# Copies the durable core into the harness home. Your own files (CLAUDE.md, INSTANCE.md, LEARNINGS.md,
# IDEAS.md) are never clobbered; Keel's own core (FRAMEWORK, PRINCIPLES, the commands) is offered for
# update on a re-run when the installed copy has drifted. A drifted copy whose BYTES are provably
# Keel's own older release — see keel_own_untouched below for what that does and does not establish;
# it is a content check, not a "nobody touched it" one — is refreshed automatically, in every mode; a
# copy that might be yours is offered interactively ([u]pdate for commands, y/N elsewhere; default no)
# or flagged non-interactively — pass --force to take it over anyway (a real backup first, always). On
# a command-name collision with your OWN command (a pre-existing
# /go), Keel's version goes alongside as keel-<name> instead of overwrite-or-nothing — offered on a
# terminal, automatic when non-interactive (creating the alias touches nothing you own). Wires the
# secret-guard git hook machine-global (never over an existing hooksPath), seeds a private INSTANCE.md,
# and verifies the result.
#
# Linked mode (--link): instead of copying, wire Keel-owned content BY REFERENCE — a `<home>/keel/`
# consumption dir of symlinks into this checkout (CORE, FRAMEWORK, PRINCIPLES), one `@import` line in
# the global CLAUDE.md, and command symlinks. `git pull` here then refreshes every consumer at once;
# re-run `install.sh --link` after a pull to wire files a release ADDED (pull refreshes content, not
# composition). Requires a checkout you keep (not bootstrap's temp clone). The `@import` line is a
# Claude Code mechanism — other harnesses should stay on the copy path (see ADAPTING.md).
#
# Usage:
#   install.sh                 bootstrap into ${KEEL_HOME:-$HOME/.claude}
#   install.sh --link          linked mode: symlinks + one @import line (Claude Code; keep this clone)
#   install.sh --home DIR      bootstrap into DIR (for a non-Claude-Code harness)
#   install.sh --codex         generate ~/.codex/AGENTS.md (copy mode; --home overrides the default
#                              home; errors combined with --link — Codex reads no @import mechanism)
#   install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
#   install.sh --no-git        linked mode: trim the code/git rails from the always-on core (for a
#                              machine with NO git projects; sticky — plain re-runs keep the trim)
#   install.sh --with-git      linked mode: restore the full rails after a --no-git install
#   install.sh --force         take over a drifted/refused Keel-owned file (backed up first). Never
#                              reaches CLAUDE.md/AGENTS.md/INSTANCE.md/LEARNINGS.md/IDEAS.md, hooks, or
#                              settings.json — those have their own opt-in overwrites, or none at all.
#   install.sh -h | --help
#
# KEEL_EPHEMERAL=1 (env, set by bootstrap's copy mode): this checkout is a temp clone reaped right
# after the run — skip the bin/keel symlink and the checkout-backed promises in the summary (a link
# into a reaped clone would dangle; the closing text must not promise `keel …` verbs it can't keep).
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"          # repo root (this script lives at the top level)

usage() {
  cat <<'EOF'
install — one-command bootstrap for Keel into your harness home.

Copies the durable core into the harness home. Your own files (CLAUDE.md, INSTANCE.md,
LEARNINGS.md, IDEAS.md) are never clobbered; Keel's own core (FRAMEWORK, PRINCIPLES, commands) is
offered for update on a re-run when it has drifted. A drifted copy that provably is Keel's own
older release is refreshed automatically; a copy that might be yours is offered interactively
([u]pdate for commands, y/N elsewhere; default no) or flagged non-interactively — pass --force to
take it over anyway (backed up first; never reaches your own files, hooks, or settings.json). If a
command name is already taken by your OWN command (say, /go), Keel's version goes alongside as
keel-<name> instead — offered on a terminal, automatic when non-interactive. Wires the
secret-guard git hook machine-global (never over an existing hooksPath), seeds a private INSTANCE.md,
and verifies the result.

Linked mode (--link, Claude Code): wires by reference instead of copying — <home>/keel/
symlinks into this checkout + ONE @import line in your global CLAUDE.md + command
symlinks. `git pull` here refreshes everything; re-run `install.sh --link` after a pull
to wire newly shipped files. Keep this clone — it IS the installation. Removal is the
mirror image: delete <home>/keel/, the import line, and the command symlinks.

Usage:
  install.sh                 bootstrap into ${KEEL_HOME:-$HOME/.claude}
  install.sh --link          linked mode: symlinks + one @import line (Claude Code; keep this clone)
  install.sh --home DIR      bootstrap into DIR (for a non-Claude-Code harness)
  install.sh --codex         generate ~/.codex/AGENTS.md — the global always-on file Codex reads
                             verbatim (copy mode; --home overrides the default; --codex + --link errors)
  install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
  install.sh --no-git        linked mode: trim the code/git rails from the always-on core (for a
                             machine with NO git projects; sticky — plain re-runs keep the trim)
  install.sh --with-git      linked mode: restore the full rails after a --no-git install
  install.sh --force         take over a drifted/refused Keel-owned file (backed up first). Never
                             touches CLAUDE.md/AGENTS.md/INSTANCE.md/LEARNINGS.md/IDEAS.md, hooks, or
                             settings.json — those have their own opt-in overwrites, or none at all.
  install.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"          # --home overrides; the $HOME default is resolved AFTER parsing
DO_HOOKS=1
LINK=0
NOGIT=0
WITHGIT=0
CODEX=0
# FORCE propagates into sync_product's own recursive alias calls (resolved-collision, the [a] tty
# choice) with no extra plumbing — it's a plain global, read fresh at each call. Deliberate, not an
# accident of scope: the alias (keel-<name>.md) is Keel's OWN file, never adopter data, so forcing its
# sync too is the same "take over what's provably ours" policy as the rest of --force, not a widening
# of it. Tests scope their `.bak` counts to the specific file under test (never a bare `*.bak` glob)
# precisely because of this — an alias refresh can legitimately produce its own backup too.
FORCE=0
EPHEMERAL="${KEEL_EPHEMERAL:-0}"   # env, not a flag: an internal bootstrap→install signal (see header)
# NON_REGULAR_MSG — the one decline wording for "a FIFO/device/socket/directory sits where a Keel-
# owned file belongs" (dir #351's own two sync_product call sites, and force_backup's matching guard,
# dir #349 — three readers in total, all in this same shared constant now). The duplication dir #351
# already eliminated once (two sync_product call sites, same function) would otherwise reappear one
# level up (two separate FUNCTIONS), which is exactly what a /simplify pass on this ticket found. Named
# for the STATEMENT it makes ("a non-regular file is there, we left it, remove it and re-run" — true
# whether the caller was about to place a fresh copy or take a backup first), not for any one call
# site — if they ever need to say something genuinely different, un-share them rather than bending one
# message to cover both; sharing is only correct while every reader means the same thing.
NON_REGULAR_MSG="a non-regular file already exists there — left in place; remove or move it by hand, then re-run"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --home)
      shift
      # A leading dash is a swallowed flag, not a path — refuse before any write, same guard
      # install-pre-pr-gate.sh's own --home already carries (dir #125 test A5).
      case "${1:-}" in
        -*) echo "install: --home needs a DIR, got the flag '${1:-}'" >&2; exit 2 ;;
      esac
      HOME_DIR="${1:?--home needs a DIR}" ;;
    --no-hooks) DO_HOOKS=0 ;;
    --link) LINK=1 ;;
    --no-git) NOGIT=1 ;;
    --with-git) WITHGIT=1 ;;
    --codex) CODEX=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# --codex is copy-mode only — the @import line is a Claude Code mechanism (see header), and Codex
# has no equivalent. Check the RAW flags here, before the linked-home auto-detect below can flip LINK.
if [ "$CODEX" = 1 ] && [ "$LINK" = 1 ]; then
  echo "install: --codex only supports the copy path (Codex reads no @import mechanism) — drop --link" >&2
  exit 2
fi

# Default to $HOME/.claude ($HOME/.codex under --codex) only if neither KEEL_HOME nor --home was
# given — so those callers never need $HOME (and `set -u` won't abort when it's unset). Require
# $HOME only when we actually fall back.
default_home_leaf=".claude"
[ "$CODEX" = 1 ] && default_home_leaf=".codex"
: "${HOME_DIR:=${HOME:?install: set HOME, or pass --home DIR}/$default_home_leaf}"

# home_flag — the ` --home "DIR"` suffix every command this script ADVISES has to carry when this
# install is retargeted, and nothing when it isn't. dir #98 turned out to be a class, not a site: five
# separate places across install.sh/uninstall.sh/doctor.sh/install-pre-pr-gate.sh told the operator to
# run a command that re-resolves the home from scratch and therefore could not reach the install being
# talked about. Deriving the suffix ONCE, from the same expression a bare re-run would evaluate, is what
# stops the next advice string from re-opening it: if the two agree the flag is empty, so the friendly
# short form survives for the ordinary install, and it appears exactly when it is load-bearing.
if [ "$HOME_DIR" = "${KEEL_HOME:-${HOME:-}/$default_home_leaf}" ]; then home_flag=""; doctor_arg=""
else home_flag=" --home \"$HOME_DIR\""; doctor_arg=" \"$HOME_DIR\""; fi   # doctor takes the home positionally
# The MODE is half of "can this command reach the install", and the half home_flag can't see: a bare
# re-run is Claude copy mode, so a --codex install needs --codex on every advised command even when the
# home is the default one (there, home_flag is correctly empty and would have left the advice pointing
# at ~/.claude). Kept a separate variable rather than folded into home_flag because the two answer
# different questions and a --codex install can be retargeted as well, needing both.
mode_flag=""
[ "$CODEX" = 1 ] && mode_flag=" --codex"
advise_install="install.sh$mode_flag$home_flag"      # re-run THIS install
advise_uninstall="keel uninstall$mode_flag$home_flag" # reverse THIS install

# CONTEXT_FILE — the harness's global always-loaded file name. Everywhere copy mode below writes or
# mentions "the global context file", it routes through this instead of a hardcoded CLAUDE.md.
CONTEXT_FILE="CLAUDE.md"
[ "$CODEX" = 1 ] && CONTEXT_FILE="AGENTS.md"

# core-ownership (dir #363: keel_core_is_link/keel_core_is_nogit_trim), hoisted here — before the
# linked-mode sticky-detect just below, this file's first call site — same reasoning as the self-link
# guard further down: the earliest sane point either way, so the sticky-detect still fires from a
# checkout that hasn't got a tools/ dir at all. OPTIONAL, unlike tools/lib/manifest.sh's REQUIRED
# treatment for uninstall.sh/tools/doctor.sh: every call site below is a pure filesystem check with
# zero tools/ dependency today, driving only this run's own LINK/NOGIT control flow and a printed
# message — never a manifest record another script later trusts for a destructive decision, so there's
# no cross-script poisoning risk to refuse outright over (contrast tools/lib/artifact-cksum.sh below).
# Same `[ -f ] && bash -n` pre-check as the libs below (a bare `.` can't be guarded against a
# parse-time syntax-error abort under `set -e`); the fallback is today's inline logic moved verbatim —
# byte-identical to tools/lib/core-ownership.sh's own copy, not a stub, so a tools/-less checkout keeps
# today's exact behaviour.
if [ -f "$root/tools/lib/core-ownership.sh" ] && bash -n "$root/tools/lib/core-ownership.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/core-ownership.sh
  . "$root/tools/lib/core-ownership.sh"
else
  keel_core_is_link() {
    [ -L "$1" ]
  }
  keel_core_is_nogit_trim() {
    [ -f "$1" ] && [ ! -L "$1" ] && grep -q 'KEEL-NOGIT' "$1" 2>/dev/null
  }
fi

# Mode is sticky: a plain re-run over a LINKED home must not quietly copy root FRAMEWORK/PRINCIPLES
# back in as stale shadows — "git pull && ./install.sh" is exactly the muscle-memory the copy-mode
# docs teach, so detect the linked layout and stay in linked mode. (keel_core_is_link, not -f: even a
# dangling CORE.md link marks the home as linked — the re-run then heals it.)
if [ "$CODEX" = 0 ] && [ "$LINK" = 0 ] && keel_core_is_link "$HOME_DIR/keel/CORE.md"; then
  LINK=1
  echo "install: this home is a LINKED install — continuing in linked mode (as if --link was passed)"
fi

# A --no-git home is linked too, but its keel/CORE.md is a generated REGULAR file (carrying the
# KEEL-NOGIT token), which the -L stickiness above can't see — recognize it here, and make the trim
# itself sticky: a plain re-run KEEPS the trim and refreshes it from the current CORE.md, so the
# muscle-memory "git pull && install.sh --link" heals a stale trim instead of silently restoring the
# git rails. Restoring is explicit: --with-git.
if [ "$CODEX" = 0 ] && keel_core_is_nogit_trim "$HOME_DIR/keel/CORE.md"; then
  [ "$LINK" = 1 ] || echo "install: this home is a LINKED install — continuing in linked mode (as if --link was passed)"
  LINK=1
  if [ "$NOGIT" = 0 ] && [ "$WITHGIT" = 0 ]; then
    NOGIT=1
    echo "install: this home is a --no-git install — keeping the trim (restore the git rails: install.sh --link$home_flag --with-git)"
  fi
fi

# advise_refresh_force — the one remedy that actually reaches a refused/aliased Keel-owned file from
# THIS run's own context (dir #323/#324): a kept checkout re-runs install.sh --force directly; a linked
# install prefers `keel sync`; an EPHEMERAL bootstrap run's $root is a temp clone reaped on exit, so
# neither a bare re-run nor a $FIX cp/ln hint can ever reach it again — only the piped bootstrap form
# can (verified against README.md:84 / docs/getting-started.md:116).
# BOTH of those forward their args straight through to install.sh and add no ARGUMENTS of their own
# (keel:128, bootstrap.sh:141 — each does add something else: `keel sync` pulls the checkout first,
# bootstrap sets KEEL_EPHEMERAL=1) — which is precisely why each has to carry the retargeting suffix
# here rather than inherit it: without it, `keel sync --force` becomes a bare `install.sh --force` whose
# home re-resolves to ${KEEL_HOME:-$HOME/.claude}, so a `--link --home DIR` adopter following the
# advice builds a SECOND Keel at the default home and never touches the file it was about.
# Computed here, AFTER both sticky linked-mode auto-detect blocks above have finalized $LINK (dir #349
# — an earlier draft computed this ~16 lines above the sticky detect, so `keel sync` and every plain
# `./install.sh` re-run over a linked home fell to the copy-mode form below even though the home is
# linked; not data loss, since $home_flag still points at the right home, but the adopter was handed
# the cwd-dependent form in exactly the case `keel sync` exists to avoid).
if [ "$EPHEMERAL" = 1 ]; then
  advise_refresh_force="curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh -s --$mode_flag$home_flag --force"
elif [ "$LINK" = 1 ]; then
  # $mode_flag is structurally empty here — --codex + --link is refused at the top of this script.
  advise_refresh_force="keel sync$home_flag --force"
else
  advise_refresh_force="$advise_install --force"
fi

# --no-git / --with-git are linked-mode verbs: the trim lives in a generated keel/CORE.md, which only
# exists in linked composition. The copy path has its own trim (/keel-setup edits the user's own copy).
if [ "$NOGIT" = 1 ] && [ "$WITHGIT" = 1 ]; then
  echo "install: --no-git and --with-git contradict each other — pass one" >&2; exit 2
fi
if { [ "$NOGIT" = 1 ] || [ "$WITHGIT" = 1 ]; } && [ "$LINK" = 0 ]; then
  echo "install: --no-git/--with-git need a linked install (--link). On the copy path, /keel-setup" >&2
  echo "         offers the same trim on your own CLAUDE.md copy instead." >&2
  exit 2
fi

echo "Keel → $HOME_DIR"
mkdir -p "$HOME_DIR"

# Self-link guard (linked mode only), hoisted here — before anything below sources tools/lib/manifest.sh
# (dir #323) — so the refusal still fires from a checkout that hasn't got a tools/ dir at all (this is
# the earliest sane point either way: if the consumption dir IS this checkout — e.g. --home "$HOME"
# while the checkout sits at $HOME/keel, bootstrap's default — sync_product would see src -ef dest and
# "upgrade" the checkout's own CORE/FRAMEWORK/PRINCIPLES into symlinks pointing at themselves,
# corrupting every file the links resolve to). -ef, not a string compare: different spellings of the
# same dir still collide. Refuse rather than no-op — the invocation is nonsensical (home is ~/.claude,
# not the checkout). $link_dir is referenced again inside the LINK-mode block further down.
if [ "$LINK" = 1 ]; then
  link_dir="$HOME_DIR/keel"
  if [ "$link_dir" -ef "$root" ] 2>/dev/null; then
    echo "install: --link consumption dir ($link_dir) is the Keel checkout itself — refusing (it would" >&2
    echo "         replace the checkout's own core files with self-referential symlinks). Point --home at" >&2
    echo "         your Claude home (e.g. ~/.claude), not the checkout." >&2
    exit 2
  fi
fi

# manifest_mode / manifest_dir / manifest_file (dir #125) — hoisted here from their original spot near
# the manifest-write step below (dir #323): the provenance check the sync block needs (keel_own_untouched,
# defined below) has to read a PRIOR run's manifest before this run places anything, not after. Each
# depends only on $CODEX/$HOME_DIR, already resolved above; manifest_layout stays at the write step
# further down since it also depends on $LINK/$NOGIT and is never needed by the provenance check.
manifest_mode="claude"
[ "$CODEX" = 1 ] && manifest_mode="codex"
manifest_dir="$HOME_DIR/.keel"
manifest_file="$manifest_dir/install-manifest.$manifest_mode"
mkdir -p "$manifest_dir"

# A checkout this minimal (a test fixture, or a corrupted install) may not ship tools/ at all — degrade
# to "provenance unavailable" rather than aborting the whole install over an optional refinement; every
# other real gap in a broken checkout (e.g. the secret-guard step below) still surfaces its own error.
# `bash -n` syntax-checks the file BEFORE sourcing it (found by this ticket's own /code-review high
# pass, reproduced live): under `set -e`, a `.`/source of a file with a genuine syntax error aborts the
# WHOLE script immediately — no `if`/`&&` guard around the `.` command itself can catch that, since it's
# a parse-time failure, not a runtime one — which would silently break the "optional refinement" promise
# this comment makes for a present-but-corrupted file (a partial write, a disk error), not just a
# missing one.
if [ -f "$root/tools/lib/manifest.sh" ] && bash -n "$root/tools/lib/manifest.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/manifest.sh
  . "$root/tools/lib/manifest.sh"
else
  # Only manifest_usable — the one function keel_own_untouched below actually calls; install.sh never
  # calls manifest_field.
  manifest_usable() { return 1; }
fi

# stat-portable, sourced the same conditional way and for the same reason: keel_own_untouched needs a
# hard-link count, and that is the one thing POSIX gives no portable spelling for (GNU/busybox
# `stat -c '%h'` vs BSD `stat -f '%l'`). Reused rather than re-inlined — the flavor probe already ships
# here with its own tests. If the lib is missing or corrupt the fallback answers empty, and the
# predicate below treats an empty count as UNKNOWN and refuses, which is the fail-closed direction:
# a checkout too broken to carry tools/ is not one to auto-refresh an adopter's files from.
if [ -f "$root/tools/lib/stat-portable.sh" ] && bash -n "$root/tools/lib/stat-portable.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/stat-portable.sh
  . "$root/tools/lib/stat-portable.sh"
  # Prime the flavor cache HERE, once, as that lib's own header instructs for a hot loop: the predicate
  # calls stat_portable_nlink inside a `$( )`, so a lazily-probed flavor would be cached in a subshell
  # that dies immediately and re-probed — one extra `stat` exec per synced file, every run.
  _stat_portable_ensure_flavor
else
  stat_portable_nlink() { :; }
fi

# artifact-cksum (dir #362) — REQUIRED, not optional, unlike the two libs above: its output
# (CKSUM_UNREADABLE/artifact_cksum) is written unconditionally into a manifest `file` record below,
# which uninstall.sh later trusts for a destructive (removal) decision. A same-shape "degrade and
# continue" fallback here would write the unreadable-sentinel into every record for a tools/-less
# checkout instead of only the rare truly-unreadable file, and uninstall.sh's own comparison has no
# sentinel guard on either side (dir #347's gap) — so a stubbed fallback would make every artifact
# compare as a self-equal match. Same `[ -f ] && bash -n` pre-check as the two libs above (a bare `.`
# can't be guarded against a parse-time syntax-error abort under `set -e`), but the else branch refuses
# outright instead of degrading.
if [ -f "$root/tools/lib/artifact-cksum.sh" ] && bash -n "$root/tools/lib/artifact-cksum.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/artifact-cksum.sh
  . "$root/tools/lib/artifact-cksum.sh"
else
  echo "install: tools/lib/artifact-cksum.sh is missing or corrupted — this checkout is incomplete and cannot safely record what it installs; re-clone or re-download Keel and re-run '$advise_install'" >&2
  exit 1
fi

# prior_manifest — a snapshot of the manifest as it stood before this run touches anything. keel_own_untouched
# reads THIS, never $manifest_file directly, so a future reordering of the write block below can never
# make the provenance check observe this run's own placement instead of the run before it.
# Sweep any stray snapshot a PRIOR run's crash/abort left behind before creating this run's own (found
# by this ticket's own /code-review high pass, reproduced live: any failure between here and this run's
# own cleanup near the manifest-write step — e.g. a corrupted checkout missing a shipped source file —
# leaves a `.prior-manifest.<pid>` behind with nothing to sweep it, since each run's own is uniquely
# named by that run's PID). A `trap ... EXIT` was considered and rejected: verified live on this
# machine's bash (3.2.57) that a bare EXIT trap masks a genuine crash — e.g. an unset-variable abort
# under `set -u` — into a false exit 0, which is a far worse failure mode than a leftover scratch file.
# This sweep instead just bounds the litter to at most the PREVIOUS run's leftover, cleaned up by the
# NEXT run regardless of how that run itself ends.
# `.artifacts.*` joins the sweep with this batch's fix below: before it, an unreadable manifest killed
# the run at the snapshot read, so the merge step's own `.artifacts.<pid>` scratch was never created.
# Now the run survives to reach it, and the merge step can still fail there (its `awk` reads
# $manifest_file directly — a separate, pre-existing site outside this batch's findings), leaving one
# scratch file per failed run in the adopter's home with nothing to reap it. Same bounded-litter
# contract the .prior-manifest sweep already provides: at most the previous run's leftover.
rm -f "$manifest_dir"/.prior-manifest.* "$manifest_dir"/.artifacts.* 2>/dev/null || true
# Concurrent-install disclosure (BACKLOG.md dir #350 carries the real fix): this script has never
# supported two concurrent installs into the same $HOME_DIR, and until now nothing in the tree said so.
# The ASSUMPTION is not new — it predates this release: the manifest-merge step below reads
# $manifest_file with a plain `awk` pass immediately before its own atomic_write, no lock, so two
# concurrent installs into the same home have always been able to race on whose artifact records
# survive (last writer wins, silently). This has been present unchanged since v0.8.0 (`git show
# v0.8.0^{commit}:install.sh`: the same unguarded read-then-atomic_write shape).
# What v0.8.1 changed is the ENFORCEMENT, not the assumption, and it did not predate the release either.
# The prior_manifest snapshot below and the .prior-manifest.* sweep on the line above it were introduced
# together, mid-cycle, well after v0.8.0 (neither existed at v0.8.0^{commit}). The .artifacts.* half of
# the same sweep line was added shortly after, in the same v0.8.1 cycle. The sweep's glob matches ANY
# pid's scratch file, so a second concurrent install can now delete a first, still-running install's own
# scratch — two different collisions. Deleting the live `.prior-manifest.<pid>` snapshot (open nearly the
# whole run) doesn't abort this run (dir #356: the later provenance check's `awk` read runs inside an
# `elif` condition, `set -e`-exempt); for a drifted artifact that still reaches that check, it leaks a
# raw `awk: can't open file` error to stderr before falling through to the ordinary decline, with none
# of the guard's own message. Deleting the merge step's `.artifacts.<pid>` scratch instead (open only in
# the guard's own narrow window, below) is what actually trips its loud `exit 1` ("manifest merge scratch
# vanished … — another install into this home?"). The wide-window case is the likelier one, and it's
# the unguarded one — but it never fails the run, only the narrow-window `exit 1` does, and only that
# one needs a re-run to recover. Adopter-facing
# framing: CHANGELOG.md's [Unreleased] known-issue line.
prior_manifest="$manifest_dir/.prior-manifest.$$"
# The `cp` is the CONDITION, never the body: a manifest that exists but cannot be READ (bad perms, a
# disk error) would otherwise kill the whole run right here, under `set -euo pipefail`, before a single
# file is placed — upstream of the degradation logic in manifest_field/manifest_usable that the
# versioning contract points at (tools/lib/manifest.sh:23-26 and keel_own_untouched's own docstring
# below both promise this case "degrades to treated-as-absent, never a crash"). An unreadable manifest
# takes the same path an absent one does: an empty snapshot, prior_manifest_usable=0, provenance
# unavailable. Deliberately NOT swallowed: `: > "$prior_manifest"` stays in the body, so a genuinely
# unwritable $manifest_dir — a different condition, and one no degradation contract covers — still
# aborts loudly instead of silently installing with a snapshot that was never created.
# `[ -f ]` is KEPT, inside the condition: it is not redundant with `cp`'s own failure. It is what
# confines the read to a REGULAR file, and dropping it is not merely noisier — a FIFO at this path
# makes `cp` block forever in open(), hanging the whole install before it places anything (found by
# this batch's own /code-review max pass, reproduced live: the run had to be killed at 10s, while
# v0.8.0 installed normally in 2s because `[ -f fifo ]` was false). A char device would read unbounded.
if ! { [ -f "$manifest_file" ] && cp "$manifest_file" "$prior_manifest" 2>/dev/null; }; then
  : > "$prior_manifest"
fi
# Computed ONCE here rather than inside keel_own_untouched's own per-call body: the snapshot above is
# frozen for the rest of the run, so this can't change between calls, and re-checking it per synced
# file (one fork of manifest_field's sed|head pipeline each time) would be pure waste.
prior_manifest_usable=0
manifest_usable "$prior_manifest" && prior_manifest_usable=1
# Test-only fault injection (dir #351/#356): deletes $prior_manifest when
# KEEL_TEST_DROP_PRIOR_MANIFEST=1, right after prior_manifest_usable is cached, so the regression test
# can reproduce dir #350's sibling-sweep race deterministically instead of racing a real concurrent
# install. No-op (empty effect) in every real run. A single-call-site, single-caller check like this
# one needs no function wrapper — unlike _keel_test_checkpoint below, which earns its function form by
# being generic (parameterized by checkpoint NAME) and called from many sites. Same top-level `&&`-list
# idiom as the `manifest_usable` line right above: exempt from `set -e` the same way.
[ "${KEEL_TEST_DROP_PRIOR_MANIFEST:-}" = 1 ] && rm -f "$prior_manifest"

# force_backup DEST — DEST's current bytes to DEST.<UTC>.bak via plain cp (follows a symlink, so what's
# preserved is the content the adopter actually saw at that path). A fresh timestamp every call — never
# a fixed name — so a LATER --force run can't clobber an EARLIER run's backup (dir #323's idempotence
# requirement). The guarantee is second-granularity and nothing finer: `ts` is `%Y%m%dT%H%M%SZ` and the
# write is a plain `cp`, so two backups of the same dest within one second would collide. That is not
# reachable today and no counter suffix is warranted for it — after run 1's `place`, DEST matches the
# source, so run 2 takes the in_sync branch and backs nothing up; within a single run the three call
# sites and the alias recursion each address a distinct path. Second-granularity is a claim about
# SEPARATE runs, which is the case dir #323 actually needed. Never recorded in the manifest: a backup is
# adopter data, so uninstall.sh (which removes by manifest, never by heuristic) must leave it behind —
# a backup uninstall removes is not a backup.
# Guarded against a non-regular DEST (dir #349): a plain `cp` hangs on a FIFO and fails outright on a
# directory/device/socket — reached live at the bin/keel call site below (a directory there + --force
# used to abort the whole run under `set -euo pipefail`, verified). One guard here covers all three call
# sites, present and future, instead of asking each to re-derive it — same reasoning, and the same
# $NON_REGULAR_MSG wording, as sync_product's own $dest_nonregular (dir #351). Declines, prints why, and
# returns 1 rather than letting `cp` abort.
#
# CALLER CONTRACT — this only protects a caller that either tests the return value, or is upstream-gated
# to never see a non-regular dest in the first place. `return 1` from a BARE statement still aborts the
# whole script under `set -euo pipefail`; this function cannot change that for a caller that doesn't
# account for it. The three call sites split across both worlds today:
#   - bin/keel (below) tests the return value directly (`elif force_backup "$keel_link"; then`), so a
#     decline is the tested command of that `elif` — exempt from `set -e` — and falls through with
#     nothing further to print, since this function's own message above already explained why. This is
#     the one site that can actually reach a decline today.
#   - sync_product's two call sites are bare statements and rely entirely on an upstream gate instead:
#     the first is reached only when `dest_differs=1`, which itself requires `[ -f "$dest" ]`; the
#     second sits below dir #351's own `dest_nonregular` decline branch, which already intercepts and
#     returns before this call is ever reached. Neither site checks this function's return value, so a
#     decline there is unreachable ONLY as long as its one upstream gate keeps holding.
# A future bare call site added without its own gate, or the removal of either gate above, silently
# turns this guard from a clean decline back into the mid-sync abort dir #349 exists to remove — the
# exact shape that bit dir #342/#343's `ensure_ledger` the same week. Whoever adds a fourth call site
# needs to land in one of the two worlds above on purpose, not by accident.
#
# THE SAME "test position suspends set -e" FACT CUTS BOTH WAYS (found live by a fresh /code-review
# pass, on the very draft that added the bullets above): testing this function's return value at the
# bin/keel site doesn't just exempt the non-regular-dest `return 1` from `set -e` — it suspends
# errexit for EVERY command in this function's body for that invocation, including the `cp` below. A
# function relying on ambient `set -e` to catch ITS OWN internal failures is only safe when every
# caller invokes it as a bare statement; the moment ANY caller tests its return value, the function
# must check its own risky commands explicitly instead of trusting the shell to abort on their
# failure — which is exactly what the `cp` below now does.
force_backup() {
  local dest="$1" ts
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    echo "  !    $(basename "$dest"): $NON_REGULAR_MSG"
    return 1
  fi
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  # Explicit check, not ambient `set -e` (dir #349, found live by a fresh /code-review pass): the
  # bin/keel call site below tests this function's own return value (`elif force_backup ...; then`),
  # and bash suspends errexit for the WHOLE body of a command invoked in test position — not just its
  # final exit status. Without this check, a real `cp` failure (permission denied, disk full, a
  # transient I/O error) would silently fall through to the success echo below and return 0: the
  # caller would then believe the backup happened and proceed to overwrite the adopter's real file
  # with nothing actually backed up — reproduced live. Checking explicitly makes the failure mode the
  # same regardless of how the caller invokes this function: a bare-statement caller (sync_product's
  # two call sites) still aborts under `set -e` on a `return 1` here, same as before, but now with a
  # clear message first instead of a bare `cp` stderr line.
  if ! cp "$dest" "$dest.$ts.bak"; then
    echo "  !    $(basename "$dest"): backup failed — left untouched" >&2
    return 1
  fi
  echo "  ~    $(basename "$dest") backed up → $(basename "$dest").$ts.bak (--force)"
}

# 1. Durable core.
# atomic_write DEST — stdin lands via a temp sibling + rename, so a dest is never left half-written.
# The ONE spelling of the atomicity protocol; every file write below routes through it (or make_link).
atomic_write() {
  cat > "$1.keeltmp.$$" && mv -f "$1.keeltmp.$$" "$1"
}
atomic_copy() {
  atomic_write "$2" < "$1"
}

# _keel_test_checkpoint NAME — test-only crash-simulation checkpoint (dir #235): exits immediately
# when KEEL_TEST_CRASH_AFTER equals NAME, letting the test suite prove the ordering of two
# non-atomic writes deterministically instead of racing a real interrupt (both writes are near-instant
# renames). A no-op in every real run. One generic mechanism, parameterized by checkpoint name, rather
# than a bespoke `exit` line grown per write pair that ever needs this.
# The explicit `return 0` matters under `set -e`: unlike a bare `[ cond ] && exit N` inlined at the
# call site (exempt from errexit because it's the non-final command of its own && list), a FUNCTION's
# own return status is what the caller sees — without this, a false `[ cond ]` here would make the
# whole function return 1 and abort the script even when no crash was requested.
_keel_test_checkpoint() {
  [ "${KEEL_TEST_CRASH_AFTER:-}" = "$1" ] && exit 99
  return 0
}

# make_link — same temp-sibling + rename discipline for a symlink, so a dest is replaced, never
# left dangling mid-write.
make_link() {
  ln -s "$1" "$2.keeltmp.$$" && mv -f "$2.keeltmp.$$" "$2"
}

# manifest_artifacts — every Keel-owned artifact CONFIRMED in place this run (dir #125), one
# "REL<TAB>KIND<TAB>EXTRA" element per record_artifact call below. Merged over the prior manifest's
# own records near the end of the script (state, not action: an artifact this run left untouched —
# up to date, or a declined drift prompt — must still appear, with its PRIOR recorded extra, not a
# blind re-derive from possibly-user-edited disk bytes). Only sites that CONFIRM Keel content is
# correctly at dest call this — a "left untouched, differs, kept as yours" branch never does, so a
# foreign/edited file is never claimed as ours.
manifest_artifacts=()
record_artifact() { manifest_artifacts+=("$1	$2	$3"); }   # rel kind extra
# CKSUM_UNREADABLE/artifact_cksum — sourced from tools/lib/artifact-cksum.sh above (dir #362).
# record_placed DEST — DEST is confirmed Keel content as of right now; classify symlink vs file and
# record it relative to $HOME_DIR. The one call every write/up-to-date site below routes through.
#
# dir #369: a symlink's EXTRA is now `readlink DEST` — the target THIS run actually wired, always an
# absolute path into $root (every make_link call site passes one) — not the literal `-` placeholder
# record_placed used to write. uninstall.sh reads this back and compares it against the live link's
# current target, instead of hand-mirroring install.sh's own wiring in a table to re-derive what the
# target SHOULD be. No manifest version bump: the field's position/format is unchanged (still a plain
# `artifact=symlink\t<rel>\t<extra>` line, same arity), and neither script's parser cared what a
# symlink record's third field held before this — a manifest written by an OLDER install.sh (extra=`-`)
# stays fully readable, just uninformative for this one refinement (uninstall.sh's own comment at its
# call site names how it degrades).
record_placed() {
  local dest="$1" rel
  rel="${dest#"$HOME_DIR"/}"
  if [ -L "$dest" ]; then record_artifact "$rel" symlink "$(readlink "$dest")"
  elif [ -f "$dest" ]; then record_artifact "$rel" file "$(artifact_cksum "$dest")"
  fi
}

# keel_own_untouched SRC DEST (dir #323) — true only when DEST's CONTENT currently differs from SRC's
# (the `cmp -s` exclusion below — content already matching means there's nothing to refresh: an exact
# in-sync DEST falls to in_sync's own branch, and a right-content-wrong-form DEST in linked mode falls
# to the copy→symlink migration branch; neither is this predicate's job) AND the bytes at DEST are
# what a PRIOR install run placed there: on-disk cksum equals the cksum that run's manifest recorded
# for it. That distinguishes "your own unedited older Keel release" (safe to refresh with no prompt)
# from "you edited it, or Keel never placed it" (never-clobber territory — including a foreign file
# like an adopter's own /go, which the predicate also correctly rejects: no prior record exists for it
# at all).
#
# WHAT THE PREDICATE CAN AND CANNOT OBSERVE. It compares BYTES, and only bytes. It does NOT establish
# that "nobody has touched DEST since" — an earlier wording of this docstring claimed exactly that, and
# it is false for every change that leaves content identical. Re-forming DEST as a SYMLINK is the
# case that matters (an adopter moving a Keel-placed command into a dotfiles repo and linking it back
# produces byte-identical content by construction): `cksum` reads straight THROUGH the link, so the
# digest still matches, while record_placed classified the original as a regular `file`. The kind check
# below is what closes that gap — the predicate cannot see the re-forming, so it refuses to answer for
# a dest whose CURRENT form disagrees with the recorded one. Same for mode/ownership/xattr changes: not
# observed, and not claimed. A HARD link IS observed, by the nlink clause below — and it had to be:
# a hard link is a regular file, so `[ ! -L ]` passes it, its cksum matches, and `atomic_copy`'s
# `mv -f` breaks the link exactly as the symlink case severs one. Same never-clobber harm, reached
# through `ln` instead of `ln -s`, and NOT pre-existing: v0.8.0 has no keel_own_untouched at all (the
# whole dir #323 machinery is unreleased), and there the hard link survives — measured link count
# 2 -> 2 with the alias fork, against 2 -> 1 and "refreshed (Keel's own copy, unedited)" before this
# clause. It was the unreleased twin of the symlink regression, and it is closed here for the same
# reason and by the same rejection.
#
# That check is UNCONDITIONAL, not gated on $LINK, and the reason is worth stating because the obvious
# reading says otherwise. The copy→linked migration below legitimately drives this branch (see the
# first non-behaviour), so it looks like linked mode needs an exemption — it does not: that migration's
# dest is a regular FILE (a copy an earlier copy-mode run placed), which `[ ! -L ]` passes on its own.
# The only dest an exemption would additionally admit is one that is ALREADY a symlink in linked mode,
# and there it does exactly the harm this whole check exists to stop: `place` would re-point an
# adopter's dotfiles link at the checkout, silently, with no backup, under the same "unedited" message
# — the resulting form being a symlink is not the same thing as no wiring having been destroyed. With
# the check unconditional, such a dest falls instead to the linked-mode symlink branch further down,
# which declines it by name and prints a re-point hint — NON-TTY only: that branch sits after both
# `[ -t 0 ]` branches, so an interactive run gets the generic overwrite prompt instead, which never
# mentions that the dest is a link. (Reproduced both ways before this was written.)
#
# What that does NOT reach, stated because the sentence above invites the wrong inference: a symlinked
# dest whose content is byte-IDENTICAL to the source is rejected here too (by the same clause), and
# then sync_product routes it by MODE, neither route being this predicate's doing:
#   - linked mode -> the `cmp -s` migration branch, which converges it to a checkout link and so
#     re-points the very dotfiles wiring this predicate protects in the drifted case;
#   - copy mode -> in_sync, which prints "up to date" and leaves the link ON DISK untouched — but
#     calls record_placed, which classifies by CURRENT form and so rewrites the manifest record from
#     `file <cksum>` to `symlink -`. uninstall.sh treats a `symlink` record as unconditionally owned,
#     so the adopter's link is then swept on uninstall, with no release drift needed at all. "The link
#     is untouched" is true of this run and false of the next uninstall; an earlier draft of this
#     comment called that outcome "correct", which it is not.
# Both are pre-existing, unchanged since v0.8.0 (reproduced there: identical outcomes) and outside this
# batch's findings — so do not read this predicate as closing the symlinked-dest case in general. It
# closes the path that runs THROUGH it, not every path a symlinked dest can take.
#
# Two deliberate non-behaviours:
#   - A dest a LINKED run recorded is unaffected: record_placed writes `symlink -` there, never a
#     `cksum:` string, so the artifact=file lookup below cannot match it — that dest is already handled
#     by in_sync/the migration branch. This is a statement about the RECORD, not about the mode of the
#     run reading it: `commands/<name>.md` has the same home-relative key in both modes and both modes
#     read the same manifest file (manifest_mode keys on $CODEX, not on $LINK), so a `file` + `cksum:`
#     record written by an earlier COPY-mode run IS visible to a later `--link` run, and does drive
#     this branch. That is intended and load-bearing: it is the copy→linked migration of a DRIFTED
#     command (v0.8.0 left a stale copy shadowing the link forever), and it survives the kind check
#     above for the reason given there — its dest is a regular file, not a link.
#   - A manifest-less home (pre-0.7, or an unreadable/unversioned manifest) makes manifest_usable false
#     and the predicate false — falls through to today's behaviour (plus --force), never a crash. The
#     branch it falls through to always prints something actionable, so the decline is never silent.
# Ordered by COST, not by narrative, except where termination requires otherwise. Every clause is an
# independent rejection returning 1 on its own, so the order is free for CORRECTNESS: any permutation
# gives the same final answer. It is NOT free for TERMINATION: `cmp` on a non-regular `$dest` can block
# forever — reproduced live: a FIFO at `$dest` hangs `cmp -s` indefinitely, the same failure this batch
# already had to fix once for the manifest snapshot's own `cp` (see its `[ -f ]` guard above). The
# three cheap, non-forking builtins come first because they settle the whole predicate, WITHOUT EVER
# CALLING `cmp`, on every manifest-less home (a fresh install, a pre-0.7 adopter) and on every symlinked
# dest; moving `cmp` ahead of either would make those calls attempt it too, widening exposure to the
# same hang rather than merely shifting a cost. `cmp` comes next, and the two forking clauses LAST, so
# an up-to-date dest never pays for a `stat` or a `cksum`. That pair is NOT interchangeable either:
# `stat_portable_nlink`'s rejection gates the `cksum` lookup below it behind an early `return 1`, so
# swapping them would make every hard-linked dest pay for a `cksum` fork it currently never reaches —
# and `cksum` isn't non-blocking at all: `artifact_cksum` runs `cksum` with no
# `[ -f ]` guard, so it can hang on a non-regular dest exactly as `cmp` does, unreached today only
# because `cmp` blocks first. Cost orders everything else here.
keel_own_untouched() {
  local src="$1" dest="$2" rel prior_extra dest_nlink
  [ "$prior_manifest_usable" = 1 ] || return 1
  # A dest that is now a SYMLINK is not the regular file a `file` record describes, whatever its bytes
  # say — see the docstring's own symlink case above. Unconditional, in BOTH modes, and deliberately
  # not a `$LINK` special case: see the docstring for why the copy→linked migration doesn't need one.
  [ ! -L "$dest" ] || return 1
  # A FIFO/char-device/block-device/socket/directory at $dest blocks `cmp` forever, reproduced live
  # (dir #351) — reject by type before the call, same idiom as the clause above. Explicit `|| return 1`,
  # not a bare `[ -f ] &&` prefix on the `cmp` line, for the same set -e reason the clause above uses
  # one: this function's own return status is what the caller sees, and an explicit return doesn't
  # depend on the call site staying an exempt `elif` test forever.
  [ -f "$dest" ] || return 1
  cmp -s "$src" "$dest" 2>/dev/null && return 1
  # …and neither is a HARD link, which `[ ! -L ]` cannot see: it IS a regular file, so its bytes match
  # and `atomic_copy`'s `mv -f` would sever it just as silently. Same rejection, same reason. An empty
  # count means the probe could not answer (no tools/lib, an unstattable dest) and is treated as
  # UNKNOWN, not as 1 — fail closed on the rail whose job is to fail closed.
  # LAST because it is the only remaining clause that forks: every up-to-date dest is already rejected
  # by `cmp` above, so the `stat` is paid only for a dest that actually drifted. NOT free to swap with
  # the cksum lookup below: this rejection gates it, via the early `return 1` — a hard-linked dest is
  # rejected right here and never reaches `rel`/`prior_extra`/the cksum fork at all.
  dest_nlink="$(stat_portable_nlink "$dest")"
  [ "$dest_nlink" = 1 ] || return 1
  rel="${dest#"$HOME_DIR"/}"
  # dir #356 (absorbed here): $prior_manifest can vanish mid-run under dir #350's own sibling-sweep
  # race — a REGULAR file's continued existence is in question, not its type (contrast the `[ -f ]`
  # guards above/below, which reject by type). Degrade silently on a missing/unreadable snapshot,
  # exactly like every other manifest-less-home path this predicate already falls through for
  # (`prior_manifest_usable=0` above) — losing this read only narrows what the predicate can
  # OPTIMISTICALLY refresh with no prompt, it never threatens anything this run is about to WRITE
  # (contrast dir #350's own merge-scratch guard, which is loud because losing ITS file would risk
  # this run overwriting the manifest with un-trustworthy state). `2>/dev/null` suppresses the actual
  # leak (a raw `awk: can't open file` on stderr); `|| true` matches manifest_field's own convention
  # (tools/lib/manifest.sh) and is defensive rather than load-bearing — this statement is already
  # set -e-safe at its one call site today (the `elif keel_own_untouched ...; then` exemption
  # propagates into the function body), but `|| true` keeps it correct independent of that exemption
  # ever holding at some future, non-exempt call site.
  prior_extra="$(awk -F'\t' -v rel="$rel" '$1 == "artifact=file" && $2 == rel { print $3; exit }' "$prior_manifest" 2>/dev/null)" || true
  # Rejecting $CKSUM_UNREADABLE on the PRIOR side is what closes the self-equal case, and it closes it
  # on both: an unreadable DEST yields the sentinel too, and the sentinel can only ever compare equal
  # to itself — so a guard here alone is enough, and it keeps artifact_cksum's fork behind the `&&`
  # where a dest with no prior record never pays for it.
  [ -n "$prior_extra" ] && [ "$prior_extra" != "$CKSUM_UNREADABLE" ] && [ "$prior_extra" = "$(artifact_cksum "$dest")" ]
}

# place / in_sync / FIX — the one seam between copy mode and linked mode: how Keel-owned content
# lands at dest, when dest already matches the shipped source, and the one-liner we print for
# fixing drift by hand. Everything else (never-clobber, collision aliases, tty/non-tty behavior)
# is shared, so the two modes can't drift apart in semantics.
place() {
  if [ "$LINK" = 1 ]; then make_link "$1" "$2"; else atomic_copy "$1" "$2"; fi
  record_placed "$2"
}
in_sync() {
  if [ "$LINK" = 1 ]; then
    # -ef, not a readlink string compare: the same checkout is reachable through different path
    # spellings (/tmp vs /private/tmp on macOS, a symlinked parent) — a link to the same physical
    # file is in sync however it's spelled. A link to a DIFFERENT checkout stays out of sync.
    [ -L "$2" ] && [ "$2" -ef "$1" ]
  else
    # `[ -f "$2" ]` first (dir #351): a FIFO/char-device/etc. at $2 blocks `cmp` forever, and this is
    # reachable independently of keel_own_untouched's own guard — a fresh install (no prior manifest)
    # routes straight here without ever attempting `cmp` inside that predicate.
    [ -f "$2" ] && cmp -s "$1" "$2"
  fi
}
if [ "$LINK" = 1 ]; then FIX="ln -sf"; else FIX="cp"; fi

# Linked-mode helpers (used by the --link branch below AND its Verify section; $import_line is set
# by the --link branch before any call).
# strip_core_block FILE [REPLACEMENT] → stdout, with the KEEL-CORE block replaced by REPLACEMENT
# (default: the import line; "" = block removed). The ONE definition of the marker transform;
# callers own the destination (in-place migration or a pipe).
strip_core_block() {
  awk -v imp="${2-$import_line}" '
    /KEEL-CORE-BEGIN/ {if (imp != "") print imp; skip=1; next}
    /KEEL-CORE-END/   {skip=0; next}
    !skip
  ' "$1"
}
# resolve_file FILE — follow symlinks (≤10 hops) to the real file, so an in-place rewrite lands in
# the file's true home instead of severing the link (a dotfiles-managed CLAUDE.md is a symlink).
resolve_file() {
  local f="$1" t i=0
  while [ -L "$f" ] && [ "$i" -lt 10 ]; do
    t="$(readlink "$f")"
    case "$t" in /*) f="$t" ;; *) f="$(dirname "$f")/$t" ;; esac
    i=$((i + 1))
  done
  printf '%s' "$f"
}
replace_core_block() {  # $1=file, optional $2 forwarded to strip_core_block
  local real; real="$(resolve_file "$1")"
  strip_core_block "$1" ${2+"$2"} > "$real.keeltmp.$$" && mv -f "$real.keeltmp.$$" "$real"
}
# core_block FILE → the lines strictly between the markers (markers excluded — their comment text
# legitimately differs). Mirror of block_of() in tests/test_core_wrapper_sync.sh — keep in sync.
core_block() { sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$1" | sed '1d;$d'; }
# refresh_core_block FILE — replace FILE's embedded KEEL-CORE block (markers included) with the
# CURRENT shipped block from CORE.md — the same source the caller's own drift check (core_block
# "$root/CORE.md") already compares against, so there is exactly one file this "is it stale"/"refresh
# it" pair depends on, not two kept in sync only by test_core_wrapper_sync.sh's byte-equality pin.
# The copy-mode analog of replace_core_block: that one migrates an embedded block to an @import line
# (linked mode); this one keeps the block embedded, just refreshed (--codex currency — see header).
# resolve_file first, same as replace_core_block: a dotfiles-managed FILE is a symlink, and writing
# straight to it (atomic_write's mv would replace the link itself) would sever it instead of updating
# the real target through the link.
# ENVIRON, not -v: a -v value goes through awk's own escape processing, which would mangle a
# multi-line block containing backslashes (same reason strip_git_blocks uses ENVIRON below).
refresh_core_block() {
  local file="$1" real fresh
  real="$(resolve_file "$file")"
  fresh="$(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$root/CORE.md")"
  KEEL_FRESH_BLOCK="$fresh" awk '
    /KEEL-CORE-BEGIN/ { print ENVIRON["KEEL_FRESH_BLOCK"]; skip=1; next }
    /KEEL-CORE-END/   { skip=0; next }
    !skip
  ' "$file" | atomic_write "$real"
}
# strip_template_prose — stdin → stdout, with the copy-path-only header prose removed: the
# " (TEMPLATE)" tag suffix and the "> Copy this to your harness" line. Shared by both wrapper
# generators below (linked mode's CLAUDE.md, --codex's AGENTS.md) — tests/test_install_link.sh pins
# the exact source strings this targets, so a template reword fails loudly instead of no-oping here.
strip_template_prose() {
  sed -e 's/ (TEMPLATE)$//' -e '/^> Copy this to your harness/d'
}
# has_core_import FILE — THE definition of "the import line is wired". Claude Code treats an @path
# anywhere in prose as an import, so the token may sit mid-line with text around it — an anchored
# ^@…$ would call a working import unwired (and then append a duplicate). Verify uses this too, and
# tools/doctor.sh --install carries a mirrored copy (cross-referenced there) — keep them in sync.
has_core_import() { grep -qE '(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)' "$1" 2>/dev/null; }
# --no-git (linked mode): CORE.md's KEEL-GIT markers fence the code/git rails. strip_git_blocks removes
# every marked block, replacing the FIRST with the constant breadcrumb below — always-on text that
# (a) tells the assistant the git rails are deliberately absent and to restore them BEFORE the first
# git command (the assistant is present at the exact moment git enters the workflow — the strongest
# detector of the no-git → git transition), and (b) carries the KEEL-NOGIT token install/doctor read
# as "this trim is deliberate". Keep this a PURE marker transform — any smarter rewriting here would
# fork the generated core from the shipped rails and break the equivalence doctor's staleness check
# relies on (it compares crumb-insensitively by dropping KEEL-NOGIT-BEGIN..END — keep the two in sync).
nogit_crumb='<!-- KEEL-NOGIT-BEGIN — generated by install.sh --link --no-git; not hand-edited (a re-run refreshes it) -->
**Git rails not installed on this machine** (`--no-git` install: the code/git rails are trimmed from
this always-on core). If git enters the workflow — STOP before the first git command and restore the
safety rails first: re-run `install.sh --link --with-git` in the Keel checkout.
<!-- KEEL-NOGIT-END -->'
strip_git_blocks() {
  KEEL_NOGIT_CRUMB="$nogit_crumb" awk '
    /KEEL-GIT-BEGIN/ { if (!seen) { seen=1; print ENVIRON["KEEL_NOGIT_CRUMB"] } skip=1; next }
    /KEEL-GIT-END/   { skip=0; next }
    !skip
  ' "$1"
}

# copy_gap — for USER-owned files (CLAUDE.md, INSTANCE.md, LEARNINGS.md, IDEAS.md): copy only if the destination is
# absent, never clobber. The user edits these (placeholders, private data), so a re-run must preserve them.
copy_gap() {
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "  =    $(basename "$dest") exists (left untouched)"
  elif [ -f "$src" ]; then
    atomic_copy "$src" "$dest"
    echo "  +    $(basename "$dest")"
  else
    echo "  !    source missing: $src" >&2
    return 1
  fi
}

# sync_product — for KEEL-owned core (FRAMEWORK, PRINCIPLES, commands/*): these are canonical Keel content,
# so a re-run after `git pull` SHOULD deliver the newer version. A drifted copy that provably is Keel's
# own older release (keel_own_untouched, dir #323) is refreshed automatically — that isn't adopter data,
# so never-clobber was never the right frame for it. Otherwise we still never clobber silently: if the
# installed copy might be yours we ask before overwriting — interactively when a terminal is attached
# (default no, so your copy is never lost without a yes), else a WARN naming --force. Non-interactive
# (curl|sh, CI) never blocks on input: no TTY → WARN path, not a hang. --force skips every prompt/WARN
# outright (an explicit answer already) and takes the file over, backed up first (dir #323 Part 2) —
# EXCEPT a still-virgin alias-eligible collision (see ALIAS_DEST below): there, --force is scoped OUT
# on purpose (found by this ticket's own /code-review high pass), so it never overrides the alias fork's
# already-safe, non-destructive default with a destructive one on a file Keel has never touched before.
#
# Optional ALIAS_DEST (commands only): on a name collision with the adopter's OWN command (a pre-existing
# /go is likely), Keel's version goes alongside as keel-<name> instead of overwrite-or-nothing — the
# collision fallback of the naming rule in ADAPTING.md. Once the alias exists, the unprefixed name is the
# user's for good: re-runs never touch or re-create it, and the drift check routes to the alias — unless
# keel_own_untouched proves $dest was never the adopter's to begin with, or --force says take it anyway
# (only once the collision is ALREADY resolved — see the exception above for a virgin one).
sync_product() {
  local src="$1" dest="$2" alias_dest="${3:-}" name reply=""; name="$(basename "$dest")"
  # alias_exists — computed once rather than re-testing the same three clauses at each of the two
  # sites below that ask it (dir #323 /simplify pass): does an alias file, or even a dangling alias
  # symlink (the checkout moved), already sit at $alias_dest?
  local alias_exists=0
  [ -n "$alias_dest" ] && { [ -e "$alias_dest" ] || [ -L "$alias_dest" ]; } && alias_exists=1
  # dest_nonregular (dir #351) — computed once, same reasoning as $alias_exists above, for the two
  # sites below that both need to recognize and decline a non-regular $dest (a code-review high pass on
  # this ticket found the condition duplicated verbatim between them). The two echo sites reference the
  # shared top-level $NON_REGULAR_MSG (dir #349) directly rather than through a local alias — a local
  # that only ever forwarded the constant's value added a name to chase with nothing of its own to say.
  # DELIBERATELY no `[ ! -L "$dest" ]` clause: `-e`/`-f` both follow a symlink to its target, so this
  # is true for a BARE FIFO/char-device/directory at $dest (a symlink can never itself report as one of
  # those — `-L` and that shape are mutually exclusive at the dentry level, so dropping `! -L` changes
  # nothing for that case) AND for a symlink whose TARGET is one of those (found by this same review
  # pass: every earlier guard in this diff explicitly excluded symlinks, so a dest that reaches Keel via
  # `~/.claude/commands/wrap.md -> /some/fifo` fell through every check and reached `place()`'s `mv -f`,
  # which replaces whatever dentry sits at $dest — symlink or not — silently destroying the adopter's
  # link with none of this same predicate's own decline message). A dangling symlink (a moved/reaped
  # checkout) and a symlink-to-regular-file (dir #323's own, unrelated, already-settled territory) are
  # both still correctly excluded: `-e`/`-f` are false for the former (nothing to follow to) and true
  # for the latter, so neither trips this flag.
  local dest_nonregular=0
  [ -e "$dest" ] && [ ! -f "$dest" ] && dest_nonregular=1
  if [ ! -f "$src" ]; then
    echo "  !    source missing: $src" >&2
    return 1
  elif keel_own_untouched "$src" "$dest"; then
    place "$src" "$dest"
    echo "  ^    $name refreshed (Keel's own copy, unedited)"
    if [ "$alias_exists" = 1 ]; then
      echo "       $(basename "$alias_dest") is now redundant ($name is Keel's own place again) — remove it: rm \"$alias_dest\""
      sync_product "$src" "$alias_dest"
    fi
  elif [ "$alias_exists" = 1 ]; then
    # resolved collision: Keel's copy lives at the alias; $dest — present, absent, or even identical to
    # the shipped file — is the user's space now. Route the drift check to the alias, always — unless
    # --force says otherwise: an adopter stuck here can reclaim $dest for Keel explicitly, backed up
    # first. The alias is never deleted either way (only the adopter's own hand removes it).
    local dest_differs=0
    [ -f "$dest" ] && ! cmp -s "$src" "$dest" && dest_differs=1
    if [ "$FORCE" = 1 ] && [ "$dest_differs" = 1 ]; then
      force_backup "$dest"
      place "$src" "$dest"
      echo "  +    $name updated (--force); $(basename "$alias_dest") is now redundant — remove it: rm \"$alias_dest\""
      # Same reasoning as the keel_own_untouched branch above: the alias is Keel's own file too, so it
      # still gets its own drift check this run instead of waiting for the next one (found missing by
      # this ticket's own /code-review high pass — it had silently diverged from that sibling branch).
      sync_product "$src" "$alias_dest"
    else
      # Printed whenever $dest exists, matching the ORIGINAL (pre-dir-#323) unconditional behavior —
      # even byte-identical content is "yours" here, since $dest is the adopter's space once the
      # collision resolves to the alias (found by this ticket's own /code-review high pass: an earlier
      # draft gated this on $dest_differs too, which silently dropped the line for that edge case).
      if [ -f "$dest" ]; then
        echo "  =    $name left untouched (yours; Keel's version lives at $(basename "$alias_dest")). Reclaim it: $advise_refresh_force"
      elif [ "$dest_nonregular" = 1 ]; then
        # dir #351 (found by the release-manager's own validation pass on this ticket, after the
        # done-criterion's decline branch below was already written): reachable here too — a non-regular
        # $dest can equally exist once a collision has already resolved to an alias, and $dest_differs
        # above stays 0 for it (gated on `[ -f "$dest" ]` too), which correctly keeps --force from ever
        # touching it — but that same gating also skipped this branch's own "left untouched" message, so
        # the adopter got silence instead of the decline this ticket's own done-criterion promises. Same
        # $NON_REGULAR_MSG as the dedicated decline branch further down (the one this collision-resolved
        # path would otherwise never reach), so the two read as one contract rather than two.
        echo "  !    $name: $NON_REGULAR_MSG"
      fi
      sync_product "$src" "$alias_dest"
    fi
  elif in_sync "$src" "$dest"; then
    echo "  =    $name (up to date)"
    record_placed "$dest"
  elif [ "$dest_nonregular" = 1 ]; then
    # dest exists as, or resolves through a symlink to, a non-regular file (FIFO, char/block device,
    # socket, directory) — never silently placed over. Unconditional decline, --force included:
    # force_backup (above) is a plain `cp "$dest" ...`, which hangs on a FIFO exactly the way `cmp` did
    # (dir #351) — extending --force here would trade one hang for another, not remove one. Left as
    # explicitly out of scope; an adopter who genuinely wants this dest reclaimed removes it by hand.
    echo "  !    $name: $NON_REGULAR_MSG"
  elif [ ! -f "$dest" ]; then
    # absent — or a dangling symlink (a moved/reaped checkout): place() replaces it atomically either way.
    place "$src" "$dest"
    echo "  +    $name"
  elif cmp -s "$src" "$dest"; then
    # content equals the shipped version but isn't in the mode's canonical form. In copy mode the
    # canonical form IS identical content (absorbed by in_sync above), so this only fires in linked
    # mode — for a real file (the copy→linked migration) or a same-content symlink into another
    # checkout (a re-link after a move or re-clone): converge to the canonical link either way.
    place "$src" "$dest"
    echo "  ^    $name — identical copy upgraded to a symlink (now updates with git pull)"
  elif [ "$FORCE" = 1 ] && [ -z "$alias_dest" ]; then
    # Every remaining branch below is a decline (a prompt defaulting to no, or a flat refusal) —
    # --force overrides all of them the same way: back up, take it, done (dir #323 Part 2). Scoped OUT
    # when $alias_dest is set (found by this ticket's own /code-review high pass, reproduced live): an
    # alias-eligible file with NO alias yet is a VIRGIN collision, not a decline — the branches below
    # already resolve it safely (fork a keel-<name> alias, non-destructive) rather than refuse, so
    # --force has nothing here to override yet. Letting it intercept anyway would silently replace an
    # adopter's own same-named command (e.g. their own /go) with Keel's version on the very first run
    # that happens to combine --force with a name it had never seen before — a materially different,
    # riskier act than every other --force use in this diff, all of which override an actual refusal.
    # Once the collision genuinely resolves (the alias exists), the branch above handles --force instead.
    force_backup "$dest"
    place "$src" "$dest"
    echo "  +    $name updated (--force)"
  elif [ -t 0 ] && [ -n "$alias_dest" ]; then
    echo "  ~    $name exists and differs — an older Keel copy, or your own /${name%.md} command."
    printf "       [u]pdate it with Keel's version / [a] keep yours + add Keel's as %s / [N]either: " "$(basename "$alias_dest")"
    read -r reply || reply=""
    case "$reply" in
      [uU]) place "$src" "$dest"; echo "  +    $name updated" ;;
      [aA]) sync_product "$src" "$alias_dest" ;;
      *)    echo "  =    $name left untouched (add Keel's alongside later:  $FIX \"$src\" \"$alias_dest\")" ;;
    esac
  elif [ -t 0 ]; then
    echo "  ~    $name differs from Keel's shipped version — an older release, or you edited it."
    printf "       Overwrite your copy with the shipped version? [y/N] "
    read -r reply || reply=""
    case "$reply" in
      [yY]|[yY][eE][sS]) place "$src" "$dest"; echo "  +    $name updated" ;;
      *)                 echo "  =    $name left untouched (update later:  $FIX \"$src\" \"$dest\", or: $advise_refresh_force)" ;;
    esac
  elif [ "$LINK" = 1 ] && [ -L "$dest" ]; then
    # non-tty, and dest is a symlink resolving to a different target with different content: far
    # more likely a stale link into an old/moved keel checkout than the user's own wiring. Never
    # fork it into a keel-<name> alias here — that would cede the real name to the stale link
    # forever (resolved-state semantics). Flag it and let a human decide (a tty re-run offers [u]).
    echo "  !    $name is a symlink to a different target — an old Keel checkout, or your own wiring. Left untouched."
    echo "       If it's a stale Keel link, re-point it:  $FIX \"$src\" \"$dest\""
  elif [ -n "$alias_dest" ]; then
    # no TTY to ask which way to resolve the collision — but creating the alias is non-destructive (a
    # brand-new file; the user's $name is untouched), so converge to the resolved state instead of
    # re-warning on every re-run: the curl|sh path would otherwise never get Keel's command at all
    # (its cp hints point into a temp clone that bootstrap reaps on exit). Reclaim the name later:
    # $advise_refresh_force (dir #323 — the re-run is the real remedy here, not a cp into a reaped clone).
    echo "  ~    $name is your own command — installing Keel's version alongside it (reclaim the name later: $advise_refresh_force):"
    sync_product "$src" "$alias_dest"
  elif [ "$EPHEMERAL" = 1 ]; then
    # $FIX's cp/ln hint points into a temp clone bootstrap reaps on exit — actively wrong here, so
    # suppress it in favour of the one remedy that actually reaches this install again (dir #323).
    echo "  !    $name differs from Keel's shipped version — left untouched. Update: $advise_refresh_force"
  else
    echo "  !    $name differs from Keel's shipped version — left untouched."
    echo "       Update when ready:  $FIX \"$src\" \"$dest\", or take over: $advise_refresh_force"
  fi
}

# Detect a pre-existing context file that ISN'T Keel's core: we never clobber it, so the always-loaded
# rails won't be merged in. Flag that in Verify instead of leaving it silent. Keel's core (and any file
# derived from it) carries this heading; a foreign file won't.
# (Copy mode only — linked mode has no such gap: the import line delivers the rails into any file.)
# Also foreign if the heading is present but the KEEL-CORE-BEGIN marker isn't (hand-stripped, or a
# foreign file that happens to reuse the phrase): a heading with no actual block is not Keel-managed
# either — mode-agnostic, not just --codex, since codex_wrapper's drift check is the only caller that
# currently acts on this (a heading-but-no-block CLAUDE.md would otherwise pass silently), but the
# Verify WARN below should say so regardless of mode.
foreign_core=0
if [ "$LINK" = 0 ] && [ -f "$HOME_DIR/$CONTEXT_FILE" ]; then
  if ! grep -q 'always-loaded core' "$HOME_DIR/$CONTEXT_FILE" 2>/dev/null; then
    foreign_core=1
  elif ! grep -q 'KEEL-CORE-BEGIN' "$HOME_DIR/$CONTEXT_FILE" 2>/dev/null; then
    foreign_core=1
  fi
fi

if [ "$LINK" = 1 ]; then
  # Linked mode: everything Keel-owned lives under ONE consumption point ($HOME_DIR/keel/) as
  # symlinks into this checkout — enumerable (traceable), refreshed by `git pull`, removable by
  # deleting the dir + the one import line. User-owned files stay real files, never symlinks into
  # a public checkout (INSTANCE.md carries personal data).
  # link_dir/the self-link guard are set/checked earlier now (dir #323) — before anything sources
  # tools/lib/manifest.sh, so the refusal below still fires from a checkout that hasn't got a tools/
  # dir yet. $link_dir is already set.
  import_line="@$link_dir/CORE.md"
  # Prefer the ~-form when the home sits under $HOME — shorter, and survives a username-preserving
  # home move. (${HOME:-} guard: --home/KEEL_HOME callers may legitimately run without $HOME.)
  if [ -n "${HOME:-}" ]; then
    case "$link_dir" in "$HOME"/*) import_line="@~${link_dir#"$HOME"}/CORE.md" ;; esac
  fi
  mkdir -p "$link_dir"

  core_dest="$link_dir/CORE.md"
  if [ "$NOGIT" = 1 ]; then
    # A generated trimmed copy instead of the symlink. keel/ is Keel-owned and the KEEL-NOGIT token
    # marks the file as generated — regenerate without asking: a re-run after `git pull` is exactly
    # how a stale trim heals (doctor --install carries the matching staleness check).
    trimmed="$(strip_git_blocks "$root/CORE.md")"
    if [ ! -L "$core_dest" ] && [ -f "$core_dest" ] && [ "$trimmed" = "$(cat "$core_dest")" ]; then
      echo "  =    CORE.md (up to date — trimmed --no-git copy)"
      record_placed "$core_dest"
    else
      if [ -L "$core_dest" ]; then was_link=1; else was_link=0; fi
      printf '%s\n' "$trimmed" | atomic_write "$core_dest"
      record_placed "$core_dest"
      if [ "$was_link" = 1 ]; then
        echo "  ^    CORE.md — linked full rails replaced by a trimmed copy (--no-git: code/git rails removed)"
      else
        echo "  +    CORE.md (trimmed --no-git copy — code/git rails removed)"
      fi
    fi
  elif keel_core_is_nogit_trim "$core_dest"; then
    # --with-git: the generated trimmed copy goes back to the canonical symlink (full rails restored).
    make_link "$root/CORE.md" "$core_dest"
    record_placed "$core_dest"
    echo "  ^    CORE.md — trimmed --no-git copy replaced by the full linked rails (git rails restored)"
  else
    sync_product "$root/CORE.md"     "$core_dest"
  fi
  sync_product "$root/FRAMEWORK.md"  "$link_dir/FRAMEWORK.md"
  sync_product "$root/PRINCIPLES.md" "$link_dir/PRINCIPLES.md"

  # A short README so the dir explains itself later (written once; yours to edit after).
  # Path-neutral on purpose: a baked-in checkout path would silently go stale if the checkout ever
  # moves — the symlinks themselves are the live pointer (readlink shows where).
  if [ ! -f "$link_dir/README.md" ]; then
    atomic_write "$link_dir/README.md" <<EOF
# keel/ — the Keel consumption point (linked install)

Everything here is a symlink into the Keel checkout — \`readlink CORE.md\` shows where that is.
\`git pull\` in the checkout refreshes them all; a running session keeps what it loaded at start.
After a pull, re-run \`install.sh --link$home_flag\` once — a pull refreshes content, not composition
(a newly shipped file doesn't wire itself).

- \`CORE.md\` — the always-on rails, @imported by the global \`CLAUDE.md\` one level up
  (a \`--no-git\` install generates a trimmed copy here instead of the symlink — re-runs refresh it)
- \`FRAMEWORK.md\`, \`PRINCIPLES.md\` — read on demand via the map in that \`CLAUDE.md\`

To remove Keel: delete this dir, the one \`@\` import line in the global \`CLAUDE.md\`, and any
\`commands/\` symlinks (one level up) into the checkout. Health check: \`tools/doctor.sh --install$doctor_arg\`
(run from the checkout).
EOF
    echo "  +    keel/README.md"
  fi
  # record_placed OUTSIDE the guard above — the file is written once, but a manifest re-derives
  # state EVERY run: a home that already had keel/README.md before its first manifest (a pre-dir-125
  # install upgrading straight into this version) must still get it listed, not permanently miss it
  # because the write-once guard skipped the record too (found by an independent /code-review high
  # pass). By this point the file exists either way.
  record_placed "$link_dir/README.md"

  # The global CLAUDE.md — exactly ONE @import line delivers the rails, whatever was there before:
  #   absent            → generate a thin wrapper: the template minus the embedded core, import line instead
  #   already imports   → up to date (never append twice)
  #   copy-mode wrapper → migrate: swap the embedded KEEL-CORE block for the import line — automatic
  #                       when the block is byte-identical to the shipped core (pure duplication,
  #                       zero information loss), asked/flagged when it drifted (your edits may live there)
  #   your own file     → append the one line (non-destructive, announced; delete it to unlink)
  gclaude="$HOME_DIR/CLAUDE.md"
  if [ ! -f "$gclaude" ]; then
    # tests/test_install_link.sh pins the exact source strings strip_template_prose targets, so a
    # reword in templates/CLAUDE.md fails loudly instead of no-oping here.
    strip_core_block "$root/templates/CLAUDE.md" \
      | strip_template_prose \
      | sed -e 's|\*\*`FRAMEWORK\.md`\*\*|**`keel/FRAMEWORK.md`**|' \
            -e 's|\*\*`PRINCIPLES\.md`\*\*|**`keel/PRINCIPLES.md`**|' \
      | atomic_write "$gclaude"
    echo "  +    CLAUDE.md (thin wrapper — rails arrive via the import line, fresh on every git pull)"
  elif has_core_import "$gclaude"; then
    if grep -q 'KEEL-CORE-BEGIN' "$gclaude"; then
      # half-done manual migration: the import line AND a leftover embedded block — the rails load
      # TWICE every session. Identical block = pure duplication, remove it; edited block = human call.
      if [ "$(core_block "$gclaude")" = "$(core_block "$root/CORE.md")" ]; then
        replace_core_block "$gclaude" ""
        echo "  ^    CLAUDE.md — removed the embedded rails block (the import line already delivers it; it was loading twice)"
      else
        echo "  !    CLAUDE.md has BOTH the import line and an embedded KEEL-CORE block that differs from the shipped core."
        echo "       The rails load twice each session — remove the block (or the import line) by hand."
      fi
    else
      echo "  =    CLAUDE.md already imports the linked core"
    fi
  elif grep -q 'KEEL-CORE-BEGIN' "$gclaude"; then
    if [ "$(core_block "$gclaude")" = "$(core_block "$root/CORE.md")" ]; then
      replace_core_block "$gclaude"
      echo "  ^    CLAUDE.md — embedded rails swapped for the import line (identical text; now updates with git pull)"
    elif [ -t 0 ]; then
      echo "  ~    CLAUDE.md embeds rails that differ from the shipped core — an older release, or your edits inside the block."
      printf "       Replace the embedded block with the import line (adopts the CURRENT shipped rails)? [y/N] "
      read -r reply || reply=""
      case "$reply" in
        [yY]|[yY][eE][sS]) replace_core_block "$gclaude"; echo "  +    CLAUDE.md now imports the linked core" ;;
        *) echo "  =    CLAUDE.md left untouched (embedded rails kept; the verify below flags the missing import)" ;;
      esac
    else
      echo "  !    CLAUDE.md embeds rails that differ from the shipped core — left untouched (your edits may live in the block)."
      echo "       Compare, then migrate by hand: replace the KEEL-CORE block with the line  $import_line"
    fi
  else
    printf '\n%s\n' "$import_line" >> "$gclaude"
    echo "  +    CLAUDE.md: appended the Keel core import line (one line, at the end — remove it to unlink)"
  fi

  # Root-level copies from an earlier copy-mode install would now shadow the linked versions and
  # silently go stale — flag them (the map in YOUR CLAUDE.md may still point at them, so we never
  # delete; you re-point the map, then remove the copies).
  for stale in FRAMEWORK.md PRINCIPLES.md; do
    if [ -e "$HOME_DIR/$stale" ] && [ ! -L "$HOME_DIR/$stale" ]; then
      echo "  !    $stale root copy remains from a copy-mode install — linked mode reads keel/$stale."
      echo "       Point your CLAUDE.md map at keel/$stale, then remove the copy:  rm \"$HOME_DIR/$stale\""
    fi
  done
else
  if [ "$CODEX" = 1 ]; then
    # --codex: generate an AGENTS.md wrapper instead of a plain copy_gap of templates/CLAUDE.md — the
    # (TEMPLATE) tag and "copy this" line are Claude-Code-copy-path prose that make no sense on a
    # file install.sh itself generated (same strip_template_prose the linked-mode wrapper uses; no
    # path-repoint needed here, FRAMEWORK.md/PRINCIPLES.md land at the same root-relative spot the
    # template's map already names). User-owned outside the block (never clobbered past first
    # install); the KEEL-CORE block itself gets a currency check on re-run — strictly better than
    # copy-mode Claude gets today, but never a silent auto-refresh.
    dest="$HOME_DIR/$CONTEXT_FILE"
    if [ ! -f "$dest" ]; then
      strip_template_prose < "$root/templates/CLAUDE.md" | atomic_write "$dest"
      echo "  +    $CONTEXT_FILE (generated — embedded core, refreshed on drift)"
    elif [ "$foreign_core" = 1 ]; then
      echo "  =    $CONTEXT_FILE exists (left untouched — predates Keel, see Verify below)"
    elif [ "$(core_block "$dest")" = "$(core_block "$root/CORE.md")" ]; then
      echo "  =    $CONTEXT_FILE (up to date)"
    elif [ -t 0 ]; then
      echo "  ~    $CONTEXT_FILE embeds rails that differ from the shipped core — an older release, or your edits inside the block."
      printf "       Replace just the block with the current shipped rails? [y/N] "
      read -r reply || reply=""
      case "$reply" in
        [yY]|[yY][eE][sS]) refresh_core_block "$dest"; echo "  +    $CONTEXT_FILE core block refreshed" ;;
        *)                 echo "  =    $CONTEXT_FILE left untouched (your edits may live in the block)" ;;
      esac
    else
      echo "  !    $CONTEXT_FILE embeds rails that differ from the shipped core — left untouched (non-interactive)."
      echo "       Refresh by hand: replace the KEEL-CORE block using $root/CORE.md as the source."
    fi
  else
    # User-owned (never clobber) …
    copy_gap "$root/templates/CLAUDE.md"  "$HOME_DIR/CLAUDE.md"
  fi
  # … Keel-owned (offered for update on a drifted re-run).
  sync_product "$root/FRAMEWORK.md"       "$HOME_DIR/FRAMEWORK.md"
  sync_product "$root/PRINCIPLES.md"      "$HOME_DIR/PRINCIPLES.md"
fi

# User-owned seeds — identical in both modes (real files, never clobbered, never symlinks into a
# public checkout: INSTANCE.md carries personal data).
copy_gap "$root/templates/INSTANCE.md"  "$HOME_DIR/INSTANCE.md"
copy_gap "$root/templates/LEARNINGS.md" "$HOME_DIR/LEARNINGS.md"
copy_gap "$root/templates/IDEAS.md"     "$HOME_DIR/IDEAS.md"

# Lifecycle commands — Claude Code reads them from <home>/commands/, so wire them too (never clobber).
# This is what makes /wrap, /go, /init-project, … real slash commands without a manual copy.
# Skipped under --codex: commands/ is Claude-format files in a dir Codex never reads (its skills live
# at ~/.codex/skills/<name>/SKILL.md and convert per ADAPTING.md's note — not mechanized here).
if [ "$CODEX" = 0 ] && [ -d "$root/commands" ]; then
  mkdir -p "$HOME_DIR/commands"
  for cmd in "$root"/commands/*.md; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"; alias_dest="$HOME_DIR/commands/keel-$name"
    case "$name" in
      # keel-* commands never get an alias (a keel-keel-* name would be noise) — plain drift handling.
      keel-*)    alias_dest="" ;;
    esac
    # a genuinely shipped keel-<name> owns that slot — never repurpose it as a collision alias.
    if [ -n "$alias_dest" ] && [ -f "$root/commands/keel-$name" ]; then alias_dest=""; fi
    sync_product "$cmd" "$HOME_DIR/commands/$name" "$alias_dest"
  done
fi

# The `keel` CLI on PATH — one entry point (keel install|sync|doctor|audit|init|check|uninstall) so
# the lifecycle tools work from any cwd, not just the checkout. ALWAYS a symlink into the checkout in
# BOTH modes: the dispatcher resolves its siblings (install.sh, tools/*) relative to its real path, so
# a copy severed from the checkout couldn't dispatch. Refuse-to-clobber, with an explicit opt-out
# (dir #324): a real FILE you put at bin/keel is left untouched by a plain run — the refusal below
# names the remedy — and --force takes it over, backing the file up first. A SYMLINK is replaced either
# way, and the branch does not ask whose it is: a stale one, a dangling one, and an ADOPTER'S OWN live
# link all get re-pointed with no backup and no --force (verified live; the backup arm runs only for
# `[ ! -L ] && [ -e ]`). Keel's own correctly-wired link is the exception, and only because the branch
# above catches it first on `-ef` and returns without writing. That is pre-existing and outside this
# batch, but it is what the code does, so it is what this comment says.
# $HOME_DIR/bin keeps Keel's whole footprint under one
# root (clean uninstall) at the cost of a PATH line the summary prints if the dir isn't already on PATH.
# Ephemeral bootstrap run (see header): $root is reaped right after — a symlink would dangle.
if [ "$EPHEMERAL" = 1 ]; then
  echo "  =    keel CLI skipped (temporary bootstrap clone — the summary below has the --link alternative)"
elif [ -f "$root/keel" ]; then
  mkdir -p "$HOME_DIR/bin"
  keel_link="$HOME_DIR/bin/keel"
  if [ -L "$keel_link" ] && [ "$keel_link" -ef "$root/keel" ]; then
    echo "  =    bin/keel already wired"
    record_placed "$keel_link"
  elif [ -L "$keel_link" ] || [ ! -e "$keel_link" ]; then
    # Absent, or a dangling/stale symlink — nothing of the adopter's to preserve.
    make_link "$root/keel" "$keel_link"
    record_placed "$keel_link"
    echo "  +    bin/keel → $root/keel  (run 'keel help')"
  elif [ "$FORCE" != 1 ]; then
    # A real file, no --force. $advise_install, matching the Verify WARN below and tools/doctor.sh's
    # own W-CLI-UNWIRED, and NOT $advise_refresh_force: its linked form is `keel sync`, which
    # dispatches through the bin/keel this very line reports is occupied by something that is not
    # Keel's symlink — so it is command-not-found at best, and runs the ADOPTER'S OWN program at worst
    # (reproduced live by this batch's own /code-review max pass, on two independent legs). dir #324
    # gave this line --force but kept the unreachable command; making the two lines one run prints
    # AGREE is the point, and agreeing on a command that cannot run is not a fix. --force is
    # CONDITIONAL here for the same reason: a DIRECTORY at that path takes the elif below instead (dir
    # #349), so the wording stays accurate — --force helps for a real file, never for a directory.
    echo "  !    $keel_link exists and is not a Keel symlink — left it untouched (remove it, or re-run '$advise_install' with --force if a real file, not a symlink or a directory, sits there — it gets backed up first)."
  elif force_backup "$keel_link"; then
    # $FORCE=1 from here on. force_backup is the only thing that can still say no: its own internal
    # guard (dir #349) declines and returns 1 for a non-regular $keel_link — a DIRECTORY/FIFO/
    # device/socket satisfies `[ ! -L ] && [ -e ]` too, and a plain `cp` cannot copy one (verified live:
    # it used to abort the whole run mid-sync under `set -euo pipefail`). A decline here falls through
    # this `elif` with NOTHING further to print — force_backup already explained why (its own
    # $NON_REGULAR_MSG line), and printing the FORCE=0 branch's message too would just be a second,
    # differently-worded line about the same refusal (an earlier draft did exactly that; a fresh
    # /code-review pass on this ticket caught the double message live and this split is the fix). So
    # --force never reaches a non-regular file, mirroring sync_product's own $dest_nonregular guard
    # (dir #351): unconditional decline, --force included — and there is exactly one message either way.
    make_link "$root/keel" "$keel_link"
    record_placed "$keel_link"
    echo "  +    bin/keel → $root/keel  (run 'keel help') — real file backed up first (--force)"
  fi
  # else: $FORCE=1 and force_backup declined (non-regular $keel_link) — its own message above already
  # said why; nothing more to print here.
fi

# 2. Secret-guard — machine-global, but never clobber an existing global hooksPath.
# keel_hooks must match the path install-secret-guard.sh --global writes to. Derived ONCE, here, and
# read by both the wiring block below and the Verify block further down — dir #85's finding 22 first
# re-derived the same literal a second time near Verify, which is the very "consumer re-derives the
# producer's path" shape finding 4 of the same audit was fixing elsewhere. Empty when HOME is unset:
# --no-hooks must never need $HOME, and Verify reports that as unknown state rather than guessing.
keel_hooks="${HOME:+$HOME/.config/git/keel-hooks}"
if [ "$DO_HOOKS" = 1 ]; then
  # Plain-language heads-up first: felt (first fresh-adopter install, 2026-07-11) — when an AI tool
  # drives this install, its permission dialog for the git config change reads as "a bug" to a novice
  # unless the step announces itself in human terms right before.
  echo "Next: wiring secret-guard — a git safety check that blocks key-shaped secrets (and, opt-in,"
  echo "      your personal data) from ever being committed. If an AI tool is running this install,"
  echo "      it may ask your permission for the git config change — expected, and safe to allow."
  # Now an ASSERTION, not the derivation: wiring genuinely needs HOME, and a clear message here beats
  # a bare "unbound variable" (or, worse, a hooks dir silently rooted at "/.config/git/keel-hooks").
  : "${HOME:?install: wiring hooks needs HOME set (or pass --no-hooks)}"
  existing="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ -z "$existing" ] || [ "$existing" = "$keel_hooks" ]; then
    # Non-fatal: a wiring failure must still fall through to the verify summary below
    # (which reports the hook state), not abort the whole bootstrap under `set -e`.
    if ! "$root/tools/install-secret-guard.sh" --global | sed 's/^/  /'; then
      echo "  !    secret-guard wiring failed — the verify step below will flag it" >&2
    fi
  else
    echo "  !    global core.hooksPath already set to '$existing' — not clobbering it."
    echo "       To protect a repo, vendor instead: tools/install-secret-guard.sh <repo>"
  fi
else
  echo "  =    secret-guard skipped (--no-hooks)"
fi

# 3. Verify the result — fail loudly if a core file or the hook wiring is missing.
echo "Verify:"
missing=0
if [ "$LINK" = 1 ]; then
  vfiles=(CLAUDE.md INSTANCE.md LEARNINGS.md IDEAS.md keel/CORE.md keel/FRAMEWORK.md keel/PRINCIPLES.md)
else
  vfiles=("$CONTEXT_FILE" INSTANCE.md LEARNINGS.md IDEAS.md FRAMEWORK.md PRINCIPLES.md)
fi
for f in "${vfiles[@]}"; do
  if [ -f "$HOME_DIR/$f" ]; then
    echo "  OK   $f"
  elif [ -L "$HOME_DIR/$f" ]; then
    echo "  MISS $f (dangling symlink — did the checkout move? re-run install.sh --link$home_flag from its new home)" >&2; missing=1
  else
    echo "  MISS $f" >&2; missing=1
  fi
done

# (Rails trichotomy: parallel to tools/doctor.sh --install's core-rails check — keep the two in
# sync. Severities differ on purpose: in a --link run an embedded block means "un-migrated" (WARN);
# to doctor it's legitimate copy mode (OK).)
if [ "$LINK" = 1 ]; then
  if has_core_import "$HOME_DIR/CLAUDE.md"; then
    if grep -q 'KEEL-CORE-BEGIN' "$HOME_DIR/CLAUDE.md" 2>/dev/null; then
      echo "  WARN CLAUDE.md imports the core AND still embeds a KEEL-CORE block — the rails load twice."
      echo "       Remove the block (or the import line) by hand."
    else
      echo "  OK   CLAUDE.md imports keel/CORE.md"
    fi
  elif grep -q 'KEEL-CORE-BEGIN' "$HOME_DIR/CLAUDE.md" 2>/dev/null; then
    echo "  WARN CLAUDE.md still embeds the rails as a copy (loads fine, but won't update on git pull)."
    echo "       Migrate when ready: replace the KEEL-CORE block with the line  $import_line"
  else
    echo "  WARN CLAUDE.md does not import the linked core — the always-on rails will NOT load."
    echo "       Add the line:  $import_line"
  fi
  if [ "$NOGIT" = 1 ]; then
    echo "  OK   keel/CORE.md is the trimmed --no-git core — code/git rails NOT installed"
    echo "       (if git enters this machine's workflow, restore them first:  install.sh --link$home_flag --with-git)"
  fi
fi

# dir #85 (code audit, finding 22): the guard's REAL state is inspected on every run, not only when
# this run was the one asked to wire it. Before, `--no-hooks` skipped the whole block, left guard_ok=0,
# and the closing summary then told an already-protected user "secret-guard is NOT wired (see Verify
# above)" — false, and pointing at a Verify section that had said nothing about the guard. The reverse
# of the sentence this block's own comment guards against, and just as dishonest. Reading global git
# config + a selftest is read-only, so it costs a re-run nothing; only the remediation advice below is
# still gated on DO_HOOKS, since "run install-secret-guard.sh" is not the right next step for someone
# who just explicitly asked this run not to touch hooks. $keel_hooks is empty only when HOME is unset,
# in which case there is nothing to compare against and the branches below say so instead of guessing.
guard_ok=0
hp="$(git config --global core.hooksPath 2>/dev/null || true)"
if [ -n "$keel_hooks" ] && [ "$hp" = "$keel_hooks" ] && [ -x "$hp/pre-commit" ] && grep -q 'Keel secret-guard' "$hp/pre-commit" 2>/dev/null; then
  # Presence is not function: also run the installed scanner's selftest, so a wired-but-broken
  # gate (e.g. a regressed copy on a re-run) is flagged here instead of degrading silently.
  if [ -x "$hp/secret-scan.sh" ] && "$hp/secret-scan.sh" --selftest >/dev/null 2>&1; then
    echo "  OK   secret-guard ($hp; selftest passed)"
    guard_ok=1
  else
    echo "  WARN secret-guard is wired but its selftest FAILS — the gate may not catch what it claims."
    echo "       Inspect:  $hp/secret-scan.sh --selftest"
  fi
elif [ -n "$hp" ] && [ -n "$keel_hooks" ] && [ "$hp" != "$keel_hooks" ]; then
  # A foreign global hooksPath is set — we did NOT wire Keel's guard (and didn't clobber theirs).
  # Reported BEFORE the --no-hooks arm below, and regardless of DO_HOOKS: this is the reason the guard
  # is not wired on ANY run, including one that does try to wire it (install.sh refuses to clobber).
  # Ordered the other way round, a --no-hooks run blamed the flag and implied that re-running without
  # it would fix things — it would not, and the user paid a full re-install to find that out.
  # The `!=` guard matters too: $hp EQUAL to $keel_hooks but failing the marker check above is a broken
  # or half-installed Keel hooks dir, not someone else's — it belongs in the generic arm below, whose
  # "run install-secret-guard.sh --global" is the actually-correct advice for it.
  echo "  WARN secret-guard NOT wired — a foreign global core.hooksPath ('$hp') is set."
  echo "       Vendor per-repo instead: tools/install-secret-guard.sh <repo>"
elif [ "$DO_HOOKS" = 0 ]; then
  echo "  --   secret-guard not wired (--no-hooks: this run did not touch git hooks)"
else
  echo "  WARN secret-guard not wired — run tools/install-secret-guard.sh --global"
fi

# The keel CLI: wired iff bin/keel resolves back into this checkout. Not graded in an ephemeral
# run — the CLI is deliberately not wired there (see header).
if [ "$EPHEMERAL" != 1 ] && [ -f "$root/keel" ]; then
  if [ -L "$HOME_DIR/bin/keel" ] && [ "$HOME_DIR/bin/keel" -ef "$root/keel" ]; then
    echo "  OK   keel CLI (bin/keel)"
  else
    # What was wrong here was the silence about --force, not the command: a BARE re-run reproduces
    # this identical WARN, so the two lines one run prints about the SAME file contradicted each other.
    # This matches tools/doctor.sh's own W-CLI-UNWIRED wording (dir #349 brought all four sites — this
    # line, the refusal above, tools/doctor.sh's W-CLI-UNWIRED, and keel:88 — into agreement) — the
    # conditional form, not a flat `--force`, because the wiring branch above used to fire for a
    # DIRECTORY at that path too and hand it to force_backup's plain `cp`, which cannot copy one. Fixed
    # structurally (dir #349): force_backup itself now declines a non-regular $keel_link — see that
    # branch's own comment for the mechanics. Same $advise_install-not-$advise_refresh_force reasoning
    # as the refusal above (bin/keel wiring block) applies to this WARN too — see there for why.
    # EPHEMERAL never reaches this block, so $advise_install is always reachable here.
    echo "  WARN keel CLI not wired at $HOME_DIR/bin/keel — re-run '$advise_install' (add --force if a real file, not a symlink or a directory, sits there already — it gets backed up first), or add an alias by hand."
  fi
fi

# keel-setup.md: the closing summary below tells the adopter to run /keel-setup as the very first
# next step (S8, backlog dir #4) — assert it actually landed instead of only doctor.sh --install
# catching a silently-skipped wiring bug. WARN, not a hard fail: like doctor's own command-coverage
# check (tools/doctor.sh, "missing commands are advisory"), a declined interactive drift prompt is a
# legitimate reason the file might be an older copy, not a broken install.
if [ "$CODEX" = 0 ]; then
  if [ -f "$HOME_DIR/commands/keel-setup.md" ] || [ -L "$HOME_DIR/commands/keel-setup.md" ]; then
    echo "  OK   commands/keel-setup.md (the onboarding command the summary below tells you to run)"
  else
    echo "  WARN commands/keel-setup.md is missing — the 'run /keel-setup' step below won't work."
  fi
fi

if [ "$foreign_core" = 1 ]; then
  echo "  WARN $HOME_DIR/$CONTEXT_FILE predates Keel — its always-loaded rails were NOT merged in (your file is untouched)."
  echo "       Merge the rails you want by hand:  diff $HOME_DIR/$CONTEXT_FILE $root/templates/CLAUDE.md"
fi

[ "$missing" = 0 ] || { echo "install: verification FAILED — core file(s) missing" >&2; exit 1; }

# 4. Install manifest (dir #125) — records what THIS install owns, so uninstall/doctor read ONE
# recorded state instead of re-deriving it heuristically at every site. `artifact=` lines are
# TAB-separated with no empty middle field (the IFS=$'\t' read collapse trap). dir #150 (0.7): the
# manifest is now REQUIRED by every consumer — a home with no manifest (a pre-0.7 install that hasn't
# re-run this script) gets a clear, actionable error from uninstall.sh/tools/doctor.sh naming this
# script as the fix, never a silent heuristic fallback.
# manifest_mode/manifest_dir/manifest_file/the manifest_dir mkdir are hoisted above the sync block now
# (dir #323) — only manifest_layout is still derived here, since it depends on $LINK/$NOGIT and nothing
# above the sync block needs it.
manifest_layout="copy"
[ "$LINK" = 1 ] && manifest_layout="link"
[ "$LINK" = 1 ] && [ "$NOGIT" = 1 ] && manifest_layout="link-nogit"
home_resolved="$(cd "$HOME_DIR" && pwd)"
keel_version="$(git -C "$root" describe --tags 2>/dev/null || echo unknown)"
installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

rm -f "$prior_manifest"

# dir #190's foreign-core sentinel, written/cleared BEFORE the manifest below (dir #235) — the two
# writes are independent, non-atomic operations, so a kill/crash between them is possible; ordering
# the sentinel first means the only reachable partial state is "sentinel fresh, manifest stale",
# never "manifest fresh, sentinel stale". That matters because artifact_shared_with_other's
# no-usable-other-manifest fallback (uninstall.sh) only trusts the sentinel once the manifest itself
# is unusable — a fresh-looking manifest paired with a stale sentinel is exactly the combination that
# could misjudge a live foreign-core install as unconfirmed. A stale manifest paired with a fresh
# sentinel carries no such risk: the manifest reflects an earlier, still-valid run, and the sentinel
# already tells the truth for whichever mode/state this run ended in.
foreign_core_marker="$manifest_dir/foreign-core.$manifest_mode"
if [ "$foreign_core" = 1 ]; then
  printf '' | atomic_write "$foreign_core_marker"
else
  rm -f "$foreign_core_marker"
fi
_keel_test_checkpoint foreign-core-sentinel

# context_created / the rails "edit" artifact — re-derived from the FINAL context-file state rather
# than threaded through every wrapper/migration branch above: there's no cksum-precision to lose here
# (extra is a fixed "import-line"/"core-block" tag, not a byte fingerprint), so re-inspecting the
# result is just as correct and far simpler. `foreign_core=1` → context_created=0, no edit artifact.
# NAMING NOTE for PR2's uninstall consumer (raised by an independent /code-review high pass): in
# linked mode, context_created=1 covers BOTH "Keel generated a brand-new CLAUDE.md" AND "Keel appended
# one @import line to your pre-existing global CLAUDE.md" — foreign_core is a copy-mode-only concept
# (install.sh:~385), so linked mode has no separate signal for the second case. This is intentional
# per the field's own definition ("0 = pre-existing/foreign — install never wrote rails into it"; here
# it DID), but it means context_created=1 must NEVER be read as "safe to delete the whole file" — only
# the `edit` artifact (a single import line or core block) is ever a removal candidate, never the file
# itself. The manifest already reflects this: there is no `file`-kind artifact for CLAUDE.md/AGENTS.md
# anywhere in this script, by design.
context_created=0
edit_kind="" edit_extra=""
if [ "$foreign_core" != 1 ]; then
  if [ "$LINK" = 1 ]; then
    if has_core_import "$gclaude" 2>/dev/null; then
      context_created=1; edit_kind=edit; edit_extra=import-line
    fi
  elif [ -f "$HOME_DIR/$CONTEXT_FILE" ] && grep -q 'KEEL-CORE-BEGIN' "$HOME_DIR/$CONTEXT_FILE" 2>/dev/null; then
    context_created=1; edit_kind=edit; edit_extra=core-block
  fi
fi

# Merge this run's confirmed placements over the prior manifest's own artifact records (state, not
# action): a re-run whose files are all `=` or whose drift prompt was declined must still list every
# Keel-owned artifact currently in place — the prior record wins unless THIS run confirmed a fresh
# one, and any record whose file is gone from disk is dropped. (Old-manifest lines re-shaped from
# `artifact=<kind>\t<rel>\t<extra>` to `<rel>\t<kind>\t<extra>` to match record_artifact's own order;
# awk's `a[$1]=$0` keeps the LAST line per key, so the appended this-run records win on conflict.)
merge_tmp="$manifest_dir/.artifacts.$$"
{
  if [ -f "$manifest_file" ]; then
    # edit-kind lines are excluded here — they're re-derived fresh above and printed separately
    # below, never carried forward, or a stale prior-manifest copy would duplicate the fresh one.
    awk -F'\t' '/^artifact=/ { k = $1; sub(/^artifact=/, "", k); if (k != "edit") print $2"\t"k"\t"$3 }' "$manifest_file"
  fi
  if [ "${#manifest_artifacts[@]}" -gt 0 ]; then
    printf '%s\n' "${manifest_artifacts[@]}"
  fi
} | awk -F'\t' '{a[$1] = $0} END {for (k in a) print a[k]}' | sort > "$merge_tmp"

manifest_artifact_lines=()
# Fail LOUD if the merge temp vanished between the write above and this read. Whether bash errexits on
# a failed `done < file` redirection is VERSION-DEPENDENT, measured on the snippet itself: bash 3.2.57
# (macOS's own, the macos-14 leg) prints AFTER and exits 0, while bash 5.2 (ubuntu-24.04's, and the
# alpine leg's apk bash) aborts. So on macOS the loop would simply never run and the manifest would be
# written with zero artifact records while the files sit on disk — an exit-0 success summary over an
# install uninstall can no longer see. This guard normalizes all three legs and names the cause instead
# of leaving a bare "No such file or directory"; do NOT delete it after reproducing the one-liner on a
# Linux box and concluding it is dead weight — that is precisely the leg it does not speak for.
# The check is EXISTENCE only: a temp that exists but cannot be read still takes the read path below.
# Newly reachable because this
# batch widened the stale-scratch sweep above to `.artifacts.*`: a concurrent install into the SAME
# home can now delete this run's temp. Microseconds wide and rare, but it must not fail silently —
# the sibling .prior-manifest race degrades provenance, which is recoverable; this one would not say
# anything at all.
if [ ! -f "$merge_tmp" ]; then
  echo "install: manifest merge scratch vanished ($merge_tmp) — another install into this home?" >&2
  exit 1   # merge-scratch guard: abort, never fall through and write an artifact-less manifest
fi
while IFS=$'\t' read -r rel kind extra; do
  [ -n "$rel" ] || continue
  if [ -e "$HOME_DIR/$rel" ] || [ -L "$HOME_DIR/$rel" ]; then
    manifest_artifact_lines+=("artifact=$kind	$rel	$extra")
  fi
done < "$merge_tmp"
rm -f "$merge_tmp"

{
  echo "keel_manifest_version=1"
  echo "mode=$manifest_mode"
  echo "layout=$manifest_layout"
  echo "home=$home_resolved"
  echo "context_file=$CONTEXT_FILE"
  echo "context_created=$context_created"
  echo "checkout=$root"
  echo "ephemeral=$EPHEMERAL"
  echo "keel_version=$keel_version"
  echo "installed_at=$installed_at"
  [ -n "$edit_kind" ] && printf 'artifact=%s\t%s\t%s\n' "$edit_kind" "$CONTEXT_FILE" "$edit_extra"
  if [ "${#manifest_artifact_lines[@]}" -gt 0 ]; then
    printf '%s\n' "${manifest_artifact_lines[@]}"
  fi
} | atomic_write "$manifest_file"
echo "  +    install manifest ($manifest_file)"

# Checkout-side ledger — the discovery index consumers use to find every recorded home from the
# checkout side; deduped on append (tools/lib/ledger.sh — shared with install-pre-pr-gate.sh's own
# ledger write, dir #125). Skipped when EPHEMERAL: the checkout is a temp clone about to be reaped, so
# a ledger entry pointing back at it would be pointing at nothing.
# KEEL_LEDGER_FILE overrides the path — same escape hatch as KEEL_IMPACT_LOG/LEDGER/EVIDENCE
# (tools/keel-impact.sh) for a script that would otherwise always write into $root/.keel regardless
# of the caller's own HOME sandbox; the test harness points this at a throwaway file so a test run
# never pollutes the real checkout's ledger with stale sandbox homes.
if [ "$EPHEMERAL" != 1 ]; then
  # shellcheck source=tools/lib/ledger.sh
  . "$root/tools/lib/ledger.sh"
  # Non-fatal, like the secret-guard wiring above: the home install above already fully succeeded,
  # so a checkout that happens to be read-only (a different write target than $HOME_DIR — every
  # other write in this script lands there, not here) must not abort the run and swallow the Verify
  # summary below (found by an independent /code-review high pass).
  ledger_append "${KEEL_LEDGER_FILE:-$root/.keel/installed-homes}" "$home_resolved" \
    || echo "  !    ledger write failed (non-fatal) — $root/.keel not writable?" >&2
fi

# Shared opening — the mode-specific middle differs below (clone handling, update, removal).
# The guard sentence must match reality: after --no-hooks, a refused foreign hooksPath, or a wiring
# failure, claiming "already guards your commits" tells an unprotected user they are protected.
if [ "$CODEX" = 1 ]; then mode_tag=" (codex preset)"; elif [ "$LINK" = 1 ]; then mode_tag=" (linked mode)"; else mode_tag=""; fi
if [ "$guard_ok" = 1 ]; then
  guard_note="secret-guard already guards your commits."
else
  guard_note="NOTE: secret-guard is NOT wired (see Verify above)."
fi
cat <<EOF

Done$mode_tag. $guard_note Next:
EOF
if [ "$CODEX" = 1 ]; then
  echo "  - $CONTEXT_FILE is read by Codex verbatim — nothing else to wire, no restart needed."
else
  cat <<EOF
  - EASIEST — restart Claude Code (commands load only at session start), then run  /keel-setup
    Machine setup works from ANYWHERE — no projects needed yet: it fills your machine details and
    the always-on ground rules. Later, run /keel-setup again INSIDE each project you want Keel on —
    that part drafts the project's CLAUDE.md from its code (you review).
EOF
fi
if [ "$EPHEMERAL" != 1 ] && [ -f "$root/keel" ]; then
  echo "  - the  keel  CLI is on  $HOME_DIR/bin  →  keel help  (install · sync · doctor · audit · init · check · uninstall)"
  case ":${PATH:-}:" in
    *":$HOME_DIR/bin:"*) : ;;
    *) echo "    (add it to PATH:  export PATH=\"$HOME_DIR/bin:\$PATH\"  — or keep using the tools by path)" ;;
  esac
fi
if [ "$CODEX" = 0 ] && [ "$EPHEMERAL" != 1 ] && [ -f "$root/tools/install-pre-pr-gate.sh" ]; then
  echo "  - /polish shipped, its gate did NOT — opt in per project:  tools/install-pre-pr-gate.sh <repo>"
  echo "    (blocks the agent's own gh pr create until /polish runs clean; your own terminal is never gated)"
  # dir #98: --home/KEEL_HOME retargets THIS install, but the gate installer is a separate run with its
  # own default home — say the matching flag here, at the one moment the retargeted path is on screen,
  # rather than letting the two installers quietly describe different machines.
  if [ "$HOME_DIR" != "${HOME:-}/.claude" ]; then
    echo "    This install is retargeted to $HOME_DIR — machine-global gate wiring needs the same home:"
    echo "      tools/install-pre-pr-gate.sh --home \"$HOME_DIR\"     (per-repo wiring is unaffected)"
  fi
fi
if [ "$CODEX" = 1 ]; then
  cat <<EOF
  - $CONTEXT_FILE is a real file, edited in place — Codex reads it with no import mechanism (that's a
    Claude Code thing). Update later: re-run the install (the one-liner, or  git pull && ./$advise_install
    from a kept checkout) — refreshes FRAMEWORK.md/PRINCIPLES.md and offers
    to refresh the KEEL-CORE block if it drifted from a newer release; your edits outside the block are
    always kept.
  - commands/ was NOT wired — Codex reads skills from  ~/.codex/skills/<name>/SKILL.md  instead; see
    ADAPTING.md for the (manual, 1:1) conversion note.
  - edit  $HOME_DIR/$CONTEXT_FILE  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md  private.
EOF
elif [ "$LINK" = 1 ]; then
  cat <<EOF
  - This clone IS the installation — everything points into it, so never delete it, and park it
    somewhere permanent BEFORE re-running (moving it later dangles every link).
    Update:  git pull  — rails/docs/commands refresh in place; then  ./install.sh --link$home_flag  once, to
    wire anything a release ADDED (a pull refreshes content, not composition).
    A pull changes your next session's rails without review — pull deliberately, or pin a tag.
  - health check:  tools/doctor.sh --install$doctor_arg     (everything shipped is wired, nothing dangles)
  - remove Keel:  $advise_uninstall  (reverses this, backing up what it removes) — or by hand: delete
    $HOME_DIR/keel/ , the @import line in  $HOME_DIR/CLAUDE.md , the  $HOME_DIR/commands/  symlinks,
    and  $HOME_DIR/bin/keel .
  - edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md  private.
EOF
elif [ "$EPHEMERAL" = 1 ]; then
  # Ephemeral bootstrap run: every promise here must hold WITHOUT a checkout on disk (no CLI, no
  # uninstall.sh, no tools/ for the commands that shell out) — point checkout-backed verbs elsewhere.
  cat <<EOF
  - installed by the one-line bootstrap: the temporary clone it ran from is removed as it exits, so
    the files above stand alone. The  keel  CLI,  keel uninstall , tools/install-pre-pr-gate.sh (the
    /polish gate), and the commands that shell out to Keel's tools/ (/keel-setup project drafting,
    /init-project) need a KEPT checkout — either re-run the one-liner with  --link  (keeps a checkout
    at ~/keel and wires everything to it), or git clone the keel repo and run  ./$advise_install  from it
    (re-runs never clobber your files).
  - lifecycle commands are in  $HOME_DIR/commands/  → on Claude Code: /wrap, /go, …
  - to update later: re-run the same one-liner.
  - remove Keel later by hand: delete Keel's files in  $HOME_DIR  (FRAMEWORK.md, PRINCIPLES.md, the
    commands/ entries) — CLAUDE.md and INSTANCE.md are yours; or get a checkout and run  $advise_uninstall .
EOF
else
  cat <<EOF
  - KEEP this keel clone — /keel-setup and /init-project run its tools/. Park it anywhere out of the
    way (e.g. ~/keel); it's Keel itself, not one of your projects, so don't register it. To update
    later:  git pull && ./$advise_install
  - lifecycle commands are in  $HOME_DIR/commands/  → on Claude Code: /wrap, /go, /init-project, …
  - prefer to do it by hand? edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md
    private, and scaffold/audit a project:  tools/init-project.sh <dir>  ;  tools/doctor.sh <dir>
  - measure Keel's impact: new projects (init-project) are tracked by default; for an existing repo run
    tools/keel-impact.sh enable <dir>  then score a session with  /keel-score
  - remove Keel later:  $advise_uninstall  (reverses this install, backing up what it removes)
EOF
fi
