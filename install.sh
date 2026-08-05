#!/usr/bin/env bash
# install — one-command bootstrap for Keel into your harness home.
#
# Copies the durable core into the harness home. Your own files (CLAUDE.md, INSTANCE.md, LEARNINGS.md,
# IDEAS.md) are never clobbered; Keel's own core (FRAMEWORK, PRINCIPLES, the commands) is offered for update on a
# re-run when the installed copy has drifted — interactively (y/N, default no) when run from a terminal,
# else a WARN with the exact cp to run. On a command-name collision with your OWN command (a pre-existing
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
offered for update on a re-run when it has drifted — interactively (y/N, default no) from
a terminal, else a WARN with the cp to run. If a command name is already taken by your OWN
command (say, /go), Keel's version goes alongside as keel-<name> instead — offered on a
terminal, automatic when non-interactive. Wires the secret-guard git hook machine-global
(never over an existing hooksPath), seeds a private INSTANCE.md, and verifies the result.

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
  install.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"          # --home overrides; the $HOME default is resolved AFTER parsing
DO_HOOKS=1
LINK=0
NOGIT=0
WITHGIT=0
CODEX=0
EPHEMERAL="${KEEL_EPHEMERAL:-0}"   # env, not a flag: an internal bootstrap→install signal (see header)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --no-hooks) DO_HOOKS=0 ;;
    --link) LINK=1 ;;
    --no-git) NOGIT=1 ;;
    --with-git) WITHGIT=1 ;;
    --codex) CODEX=1 ;;
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

# Default to $HOME/.claude only if neither KEEL_HOME nor --home was given — so those callers never
# need $HOME (and `set -u` won't abort when it's unset). Require $HOME only when we actually fall back.
# --codex's home is Codex's own global config dir instead — an explicit --home/KEEL_HOME still wins.
if [ "$CODEX" = 1 ]; then
  : "${HOME_DIR:=${HOME:?install: set HOME, or pass --home DIR}/.codex}"
else
  : "${HOME_DIR:=${HOME:?install: set HOME, or pass --home DIR}/.claude}"
fi

# CONTEXT_FILE — the harness's global always-loaded file name. Everywhere copy mode below writes or
# mentions "the global context file", it routes through this instead of a hardcoded CLAUDE.md.
CONTEXT_FILE="CLAUDE.md"
[ "$CODEX" = 1 ] && CONTEXT_FILE="AGENTS.md"

# Mode is sticky: a plain re-run over a LINKED home must not quietly copy root FRAMEWORK/PRINCIPLES
# back in as stale shadows — "git pull && ./install.sh" is exactly the muscle-memory the copy-mode
# docs teach, so detect the linked layout and stay in linked mode. (-L, not -f: even a dangling
# CORE.md link marks the home as linked — the re-run then heals it.)
if [ "$CODEX" = 0 ] && [ "$LINK" = 0 ] && [ -L "$HOME_DIR/keel/CORE.md" ]; then
  LINK=1
  echo "install: this home is a LINKED install — continuing in linked mode (as if --link was passed)"
fi

# A --no-git home is linked too, but its keel/CORE.md is a generated REGULAR file (carrying the
# KEEL-NOGIT token), which the -L stickiness above can't see — recognize it here, and make the trim
# itself sticky: a plain re-run KEEPS the trim and refreshes it from the current CORE.md, so the
# muscle-memory "git pull && install.sh --link" heals a stale trim instead of silently restoring the
# git rails. Restoring is explicit: --with-git.
if [ "$CODEX" = 0 ] && [ -f "$HOME_DIR/keel/CORE.md" ] && [ ! -L "$HOME_DIR/keel/CORE.md" ] \
   && grep -q 'KEEL-NOGIT' "$HOME_DIR/keel/CORE.md" 2>/dev/null; then
  [ "$LINK" = 1 ] || echo "install: this home is a LINKED install — continuing in linked mode (as if --link was passed)"
  LINK=1
  if [ "$NOGIT" = 0 ] && [ "$WITHGIT" = 0 ]; then
    NOGIT=1
    echo "install: this home is a --no-git install — keeping the trim (restore the git rails: install.sh --link --with-git)"
  fi
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

# 1. Durable core.
# atomic_write DEST — stdin lands via a temp sibling + rename, so a dest is never left half-written.
# The ONE spelling of the atomicity protocol; every file write below routes through it (or make_link).
atomic_write() {
  cat > "$1.keeltmp.$$" && mv -f "$1.keeltmp.$$" "$1"
}
atomic_copy() {
  atomic_write "$2" < "$1"
}

# make_link — same temp-sibling + rename discipline for a symlink, so a dest is replaced, never
# left dangling mid-write.
make_link() {
  ln -s "$1" "$2.keeltmp.$$" && mv -f "$2.keeltmp.$$" "$2"
}

# place / in_sync / FIX — the one seam between copy mode and linked mode: how Keel-owned content
# lands at dest, when dest already matches the shipped source, and the one-liner we print for
# fixing drift by hand. Everything else (never-clobber, collision aliases, tty/non-tty behavior)
# is shared, so the two modes can't drift apart in semantics.
place() {
  if [ "$LINK" = 1 ]; then make_link "$1" "$2"; else atomic_copy "$1" "$2"; fi
}
in_sync() {
  if [ "$LINK" = 1 ]; then
    # -ef, not a readlink string compare: the same checkout is reachable through different path
    # spellings (/tmp vs /private/tmp on macOS, a symlinked parent) — a link to the same physical
    # file is in sync however it's spelled. A link to a DIFFERENT checkout stays out of sync.
    [ -L "$2" ] && [ "$2" -ef "$1" ]
  else
    cmp -s "$1" "$2"
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
# CURRENT shipped block from templates/CLAUDE.md, leaving everything outside it untouched. The
# copy-mode analog of replace_core_block: that one migrates an embedded block to an @import line
# (linked mode); this one keeps the block embedded, just refreshed (--codex currency — see header).
# ENVIRON, not -v: a -v value goes through awk's own escape processing, which would mangle a
# multi-line block containing backslashes (same reason strip_git_blocks uses ENVIRON below).
refresh_core_block() {
  local file="$1" fresh
  fresh="$(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$root/templates/CLAUDE.md")"
  KEEL_FRESH_BLOCK="$fresh" awk '
    /KEEL-CORE-BEGIN/ { print ENVIRON["KEEL_FRESH_BLOCK"]; skip=1; next }
    /KEEL-CORE-END/   { skip=0; next }
    !skip
  ' "$file" > "$file.keeltmp.$$" && mv -f "$file.keeltmp.$$" "$file"
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
# so a re-run after `git pull` SHOULD deliver the newer version. We still never clobber silently: if the
# installed copy has drifted (an older release, or you edited it) we ask before overwriting — interactively
# when a terminal is attached (default no, so your copy is never lost without a yes), else a WARN with the
# exact cp to run. Non-interactive (curl|sh, CI) never blocks on input: no TTY → WARN path, not a hang.
#
# Optional ALIAS_DEST (commands only): on a name collision with the adopter's OWN command (a pre-existing
# /go is likely), Keel's version goes alongside as keel-<name> instead of overwrite-or-nothing — the
# collision fallback of the naming rule in ADAPTING.md. Once the alias exists, the unprefixed name is the
# user's for good: re-runs never touch or re-create it, and the drift check routes to the alias.
sync_product() {
  local src="$1" dest="$2" alias_dest="${3:-}" name reply=""; name="$(basename "$dest")"
  if [ ! -f "$src" ]; then
    echo "  !    source missing: $src" >&2
    return 1
  elif [ -n "$alias_dest" ] && { [ -e "$alias_dest" ] || [ -L "$alias_dest" ]; }; then
    # resolved collision: Keel's copy lives at the alias; $dest — present, absent, or even identical to
    # the shipped file — is the user's space now. Route the drift check to the alias, always.
    # (-e OR -L: a dangling alias symlink — e.g. the checkout moved — still marks the resolved state.)
    if [ -f "$dest" ]; then
      echo "  =    $name left untouched (yours; Keel's version lives at $(basename "$alias_dest"))"
    fi
    sync_product "$src" "$alias_dest"
  elif in_sync "$src" "$dest"; then
    echo "  =    $name (up to date)"
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
      *)                 echo "  =    $name left untouched (update later:  $FIX \"$src\" \"$dest\")" ;;
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
    # (its cp hints point into a temp clone that bootstrap reaps on exit).
    echo "  ~    $name is your own command — installing Keel's version alongside it:"
    sync_product "$src" "$alias_dest"
  else
    echo "  !    $name differs from Keel's shipped version — left untouched."
    echo "       Update when ready:  $FIX \"$src\" \"$dest\""
  fi
}

# Detect a pre-existing context file that ISN'T Keel's core: we never clobber it, so the always-loaded
# rails won't be merged in. Flag that in Verify instead of leaving it silent. Keel's core (and any file
# derived from it) carries this heading; a foreign file won't.
# (Copy mode only — linked mode has no such gap: the import line delivers the rails into any file.)
foreign_core=0
if [ "$LINK" = 0 ] && [ -f "$HOME_DIR/$CONTEXT_FILE" ] && ! grep -q 'always-loaded core' "$HOME_DIR/$CONTEXT_FILE" 2>/dev/null; then
  foreign_core=1
fi

if [ "$LINK" = 1 ]; then
  # Linked mode: everything Keel-owned lives under ONE consumption point ($HOME_DIR/keel/) as
  # symlinks into this checkout — enumerable (traceable), refreshed by `git pull`, removable by
  # deleting the dir + the one import line. User-owned files stay real files, never symlinks into
  # a public checkout (INSTANCE.md carries personal data).
  link_dir="$HOME_DIR/keel"
  # Self-link guard: if the consumption dir IS this checkout (e.g. --home "$HOME" while the checkout
  # sits at $HOME/keel, bootstrap's default), sync_product would see src -ef dest and "upgrade" the
  # checkout's own CORE/FRAMEWORK/PRINCIPLES into symlinks pointing at themselves — corrupting every
  # file the links resolve to. -ef (not a string compare): different spellings of the same dir still
  # collide. Refuse rather than no-op — the invocation is nonsensical (home is ~/.claude, not the checkout).
  if [ "$link_dir" -ef "$root" ] 2>/dev/null; then
    echo "install: --link consumption dir ($link_dir) is the Keel checkout itself — refusing (it would" >&2
    echo "         replace the checkout's own core files with self-referential symlinks). Point --home at" >&2
    echo "         your Claude home (e.g. ~/.claude), not the checkout." >&2
    exit 2
  fi
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
    else
      if [ -L "$core_dest" ]; then was_link=1; else was_link=0; fi
      printf '%s\n' "$trimmed" | atomic_write "$core_dest"
      if [ "$was_link" = 1 ]; then
        echo "  ^    CORE.md — linked full rails replaced by a trimmed copy (--no-git: code/git rails removed)"
      else
        echo "  +    CORE.md (trimmed --no-git copy — code/git rails removed)"
      fi
    fi
  elif [ -f "$core_dest" ] && [ ! -L "$core_dest" ] && grep -q 'KEEL-NOGIT' "$core_dest" 2>/dev/null; then
    # --with-git: the generated trimmed copy goes back to the canonical symlink (full rails restored).
    make_link "$root/CORE.md" "$core_dest"
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
    atomic_write "$link_dir/README.md" <<'EOF'
# keel/ — the Keel consumption point (linked install)

Everything here is a symlink into the Keel checkout — `readlink CORE.md` shows where that is.
`git pull` in the checkout refreshes them all; a running session keeps what it loaded at start.
After a pull, re-run `install.sh --link` once — a pull refreshes content, not composition
(a newly shipped file doesn't wire itself).

- `CORE.md` — the always-on rails, @imported by the global `CLAUDE.md` one level up
  (a `--no-git` install generates a trimmed copy here instead of the symlink — re-runs refresh it)
- `FRAMEWORK.md`, `PRINCIPLES.md` — read on demand via the map in that `CLAUDE.md`

To remove Keel: delete this dir, the one `@` import line in the global `CLAUDE.md`, and any
`commands/` symlinks (one level up) into the checkout. Health check: `tools/doctor.sh --install`
(run from the checkout).
EOF
    echo "  +    keel/README.md"
  fi

  # The global CLAUDE.md — exactly ONE @import line delivers the rails, whatever was there before:
  #   absent            → generate a thin wrapper: the template minus the embedded core, import line instead
  #   already imports   → up to date (never append twice)
  #   copy-mode wrapper → migrate: swap the embedded KEEL-CORE block for the import line — automatic
  #                       when the block is byte-identical to the shipped core (pure duplication,
  #                       zero information loss), asked/flagged when it drifted (your edits may live there)
  #   your own file     → append the one line (non-destructive, announced; delete it to unlink)
  gclaude="$HOME_DIR/CLAUDE.md"
  if [ ! -f "$gclaude" ]; then
    # The sed strips/re-points TEMPLATE-only prose; tests/test_install_link.sh pins these exact
    # strings in templates/CLAUDE.md, so a reword there fails loudly instead of no-oping here.
    strip_core_block "$root/templates/CLAUDE.md" \
      | sed -e 's/ (TEMPLATE)$//' \
            -e '/^> Copy this to your harness/d' \
            -e 's|\*\*`FRAMEWORK\.md`\*\*|**`keel/FRAMEWORK.md`**|' \
            -e 's|\*\*`PRINCIPLES\.md`\*\*|**`keel/PRINCIPLES.md`**|' \
      > "$gclaude.keeltmp.$$" && mv -f "$gclaude.keeltmp.$$" "$gclaude"
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
    # file install.sh itself generated (same two sed edits the linked-mode wrapper already makes;
    # see header — no path-repoint needed here, FRAMEWORK.md/PRINCIPLES.md land at the same
    # root-relative spot the template's map already names). User-owned outside the block (never
    # clobbered past first install); the KEEL-CORE block itself gets a currency check on re-run —
    # strictly better than copy-mode Claude gets today, but never a silent auto-refresh.
    dest="$HOME_DIR/$CONTEXT_FILE"
    if [ ! -f "$dest" ]; then
      sed -e 's/ (TEMPLATE)$//' -e '/^> Copy this to your harness/d' "$root/templates/CLAUDE.md" \
        > "$dest.keeltmp.$$" && mv -f "$dest.keeltmp.$$" "$dest"
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
# a copy severed from the checkout couldn't dispatch. Refuse-to-clobber: only ever replace our own
# symlink, never a real file you put at bin/keel. $HOME_DIR/bin keeps Keel's whole footprint under one
# root (clean uninstall) at the cost of a PATH line the summary prints if the dir isn't already on PATH.
# Ephemeral bootstrap run (see header): $root is reaped right after — a symlink would dangle.
if [ "$EPHEMERAL" = 1 ]; then
  echo "  =    keel CLI skipped (temporary bootstrap clone — the summary below has the --link alternative)"
elif [ -f "$root/keel" ]; then
  mkdir -p "$HOME_DIR/bin"
  keel_link="$HOME_DIR/bin/keel"
  if [ -L "$keel_link" ] || [ ! -e "$keel_link" ]; then
    if [ -L "$keel_link" ] && [ "$keel_link" -ef "$root/keel" ]; then
      echo "  =    bin/keel already wired"
    else
      make_link "$root/keel" "$keel_link"
      echo "  +    bin/keel → $root/keel  (run 'keel help')"
    fi
  else
    echo "  !    $keel_link exists and is not a Keel symlink — left it untouched (remove it to let Keel wire the CLI)."
  fi
fi

# 2. Secret-guard — machine-global, but never clobber an existing global hooksPath.
# keel_hooks must match the path install-secret-guard.sh --global writes to (re-used by Verify below).
# Resolved only when hooks are in play, so --no-hooks never needs $HOME; a clear message (not a bare
# "unbound variable") if $HOME is unset while wiring hooks.
keel_hooks=""
if [ "$DO_HOOKS" = 1 ]; then
  # Plain-language heads-up first: felt (first fresh-adopter install, 2026-07-11) — when an AI tool
  # drives this install, its permission dialog for the git config change reads as "a bug" to a novice
  # unless the step announces itself in human terms right before.
  echo "Next: wiring secret-guard — a git safety check that blocks key-shaped secrets (and, opt-in,"
  echo "      your personal data) from ever being committed. If an AI tool is running this install,"
  echo "      it may ask your permission for the git config change — expected, and safe to allow."
  keel_hooks="${HOME:?install: wiring hooks needs HOME set (or pass --no-hooks)}/.config/git/keel-hooks"
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
    echo "  MISS $f (dangling symlink — did the checkout move? re-run install.sh --link from its new home)" >&2; missing=1
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
    echo "       (if git enters this machine's workflow, restore them first:  install.sh --link --with-git)"
  fi
fi

guard_ok=0
if [ "$DO_HOOKS" = 1 ]; then
  hp="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = "$keel_hooks" ] && [ -x "$hp/pre-commit" ] && grep -q 'Keel secret-guard' "$hp/pre-commit" 2>/dev/null; then
    # Presence is not function: also run the installed scanner's selftest, so a wired-but-broken
    # gate (e.g. a regressed copy on a re-run) is flagged here instead of degrading silently.
    if [ -x "$hp/secret-scan.sh" ] && "$hp/secret-scan.sh" --selftest >/dev/null 2>&1; then
      echo "  OK   secret-guard ($hp; selftest passed)"
      guard_ok=1
    else
      echo "  WARN secret-guard is wired but its selftest FAILS — the gate may not catch what it claims."
      echo "       Inspect:  $hp/secret-scan.sh --selftest"
    fi
  elif [ -n "$hp" ]; then
    # A foreign global hooksPath is set — we did NOT wire Keel's guard (and didn't clobber theirs).
    echo "  WARN secret-guard NOT wired — a foreign global core.hooksPath ('$hp') is set."
    echo "       Vendor per-repo instead: tools/install-secret-guard.sh <repo>"
  else
    echo "  WARN secret-guard not wired — run tools/install-secret-guard.sh --global"
  fi
fi

# The keel CLI: wired iff bin/keel resolves back into this checkout. Not graded in an ephemeral
# run — the CLI is deliberately not wired there (see header).
if [ "$EPHEMERAL" != 1 ] && [ -f "$root/keel" ]; then
  if [ -L "$HOME_DIR/bin/keel" ] && [ "$HOME_DIR/bin/keel" -ef "$root/keel" ]; then
    echo "  OK   keel CLI (bin/keel)"
  else
    echo "  WARN keel CLI not wired at $HOME_DIR/bin/keel — run 'install.sh' again, or add an alias by hand."
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
fi
if [ "$CODEX" = 1 ]; then
  cat <<EOF
  - $CONTEXT_FILE is a real file, edited in place — Codex reads it with no import mechanism (that's a
    Claude Code thing). Update later: re-run the install (the one-liner, or  git pull && ./install.sh
    --codex --home "$HOME_DIR"  from a kept checkout) — refreshes FRAMEWORK.md/PRINCIPLES.md and offers
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
    Update:  git pull  — rails/docs/commands refresh in place; then  ./install.sh --link  once, to
    wire anything a release ADDED (a pull refreshes content, not composition).
    A pull changes your next session's rails without review — pull deliberately, or pin a tag.
  - health check:  tools/doctor.sh --install     (everything shipped is wired, nothing dangles)
  - remove Keel:  keel uninstall  (reverses this, backing up what it removes) — or by hand: delete
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
    at ~/keel and wires everything to it), or git clone the keel repo and run  ./install.sh  from it
    (re-runs never clobber your files).
  - lifecycle commands are in  $HOME_DIR/commands/  → on Claude Code: /wrap, /go, …
  - to update later: re-run the same one-liner.
  - remove Keel later by hand: delete Keel's files in  $HOME_DIR  (FRAMEWORK.md, PRINCIPLES.md, the
    commands/ entries) — CLAUDE.md and INSTANCE.md are yours; or get a checkout and run  keel uninstall .
EOF
else
  cat <<EOF
  - KEEP this keel clone — /keel-setup and /init-project run its tools/. Park it anywhere out of the
    way (e.g. ~/keel); it's Keel itself, not one of your projects, so don't register it. To update
    later:  git pull && ./install.sh
  - lifecycle commands are in  $HOME_DIR/commands/  → on Claude Code: /wrap, /go, /init-project, …
  - prefer to do it by hand? edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md
    private, and scaffold/audit a project:  tools/init-project.sh <dir>  ;  tools/doctor.sh <dir>
  - measure Keel's impact: new projects (init-project) are tracked by default; for an existing repo run
    tools/keel-impact.sh enable <dir>  then score a session with  /keel-score
  - remove Keel later:  keel uninstall  (reverses this install, backing up what it removes)
EOF
fi
