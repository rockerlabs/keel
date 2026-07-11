#!/usr/bin/env bash
# install — one-command bootstrap for Keel into your harness home.
#
# Copies the durable core into the harness home. Your own files (CLAUDE.md, INSTANCE.md, LEARNINGS.md)
# are never clobbered; Keel's own core (FRAMEWORK, PRINCIPLES, the commands) is offered for update on a
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
#   install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
#   install.sh -h | --help
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"          # repo root (this script lives at the top level)

usage() {
  cat <<'EOF'
install — one-command bootstrap for Keel into your harness home.

Copies the durable core into the harness home. Your own files (CLAUDE.md, INSTANCE.md,
LEARNINGS.md) are never clobbered; Keel's own core (FRAMEWORK, PRINCIPLES, commands) is
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
  install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
  install.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"          # --home overrides; the $HOME default is resolved AFTER parsing
DO_HOOKS=1
LINK=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --no-hooks) DO_HOOKS=0 ;;
    --link) LINK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Default to $HOME/.claude only if neither KEEL_HOME nor --home was given — so those callers never
# need $HOME (and `set -u` won't abort when it's unset). Require $HOME only when we actually fall back.
: "${HOME_DIR:=${HOME:?install: set HOME, or pass --home DIR}/.claude}"

echo "Keel → $HOME_DIR"
mkdir -p "$HOME_DIR"

# 1. Durable core.
# atomic_copy — write via a temp sibling + rename, so a dest is never left half-written.
atomic_copy() {
  cp "$1" "$2.keeltmp.$$" && mv -f "$2.keeltmp.$$" "$2"
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
    [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]
  else
    cmp -s "$1" "$2"
  fi
}
if [ "$LINK" = 1 ]; then FIX="ln -sf"; else FIX="cp"; fi

# copy_gap — for USER-owned files (CLAUDE.md, INSTANCE.md, LEARNINGS.md): copy only if the destination is
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
  elif [ "$LINK" = 1 ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
    # linked mode over an identical copy-mode file: pure duplication, zero information loss — upgrade
    # it to a symlink so it starts tracking `git pull` (this IS the copy→linked migration path).
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

# Detect a pre-existing CLAUDE.md that ISN'T Keel's core: we never clobber it, so the always-loaded
# rails won't be merged in. Flag that in Verify instead of leaving it silent. Keel's core (and any file
# derived from it) carries this heading; a foreign file won't.
foreign_core=0
if [ -f "$HOME_DIR/CLAUDE.md" ] && ! grep -q 'always-loaded core' "$HOME_DIR/CLAUDE.md" 2>/dev/null; then
  foreign_core=1
fi

if [ "$LINK" = 1 ]; then
  # Linked mode: everything Keel-owned lives under ONE consumption point ($HOME_DIR/keel/) as
  # symlinks into this checkout — enumerable (traceable), refreshed by `git pull`, removable by
  # deleting the dir + the one import line. User-owned files stay real files, never symlinks into
  # a public checkout (INSTANCE.md carries personal data).
  link_dir="$HOME_DIR/keel"
  import_line="@$link_dir/CORE.md"
  # Prefer the ~-form when the home sits under $HOME — shorter, and survives a username-preserving
  # home move. (${HOME:-} guard: --home/KEEL_HOME callers may legitimately run without $HOME.)
  if [ -n "${HOME:-}" ]; then
    case "$link_dir" in "$HOME"/*) import_line="@~${link_dir#"$HOME"}/CORE.md" ;; esac
  fi
  mkdir -p "$link_dir"

  sync_product "$root/CORE.md"       "$link_dir/CORE.md"
  sync_product "$root/FRAMEWORK.md"  "$link_dir/FRAMEWORK.md"
  sync_product "$root/PRINCIPLES.md" "$link_dir/PRINCIPLES.md"

  # A short README so the dir explains itself later (written once; yours to edit after).
  if [ ! -f "$link_dir/README.md" ]; then
    cat > "$link_dir/README.md.keeltmp.$$" <<EOF
# keel/ — the Keel consumption point (linked install)

Symlinks into the Keel checkout at: $root
\`git pull\` there refreshes them all; a running session keeps what it loaded at start.
After a pull, re-run \`install.sh --link\` once — a pull refreshes content, not composition
(a newly shipped file doesn't wire itself).

- \`CORE.md\` — the always-on rails, @imported by \`$HOME_DIR/CLAUDE.md\`
- \`FRAMEWORK.md\`, \`PRINCIPLES.md\` — read on demand via the map in your CLAUDE.md

To remove Keel: delete this dir, the one \`@\` import line in \`$HOME_DIR/CLAUDE.md\`, and any
\`$HOME_DIR/commands/\` symlinks into the checkout. Health check: \`tools/doctor.sh --install\`.
EOF
    mv -f "$link_dir/README.md.keeltmp.$$" "$link_dir/README.md"
    echo "  +    keel/README.md"
  fi

  # The global CLAUDE.md — exactly ONE @import line delivers the rails, whatever was there before:
  #   absent            → generate a thin wrapper: the template minus the embedded core, import line instead
  #   already imports   → up to date (never append twice)
  #   copy-mode wrapper → migrate: swap the embedded KEEL-CORE block for the import line — automatic
  #                       when the block is byte-identical to the shipped core (pure duplication,
  #                       zero information loss), asked/flagged when it drifted (your edits may live there)
  #   your own file     → append the one line (non-destructive, announced; delete it to unlink)
  replace_core_block() {
    awk -v imp="$import_line" '
      /KEEL-CORE-BEGIN/ {print imp; skip=1; next}
      /KEEL-CORE-END/   {skip=0; next}
      !skip
    ' "$1" > "$1.keeltmp.$$" && mv -f "$1.keeltmp.$$" "$1"
  }
  gclaude="$HOME_DIR/CLAUDE.md"
  if [ ! -f "$gclaude" ]; then
    awk -v imp="$import_line" '
      /KEEL-CORE-BEGIN/ {print imp; skip=1; next}
      /KEEL-CORE-END/   {skip=0; next}
      !skip
    ' "$root/templates/CLAUDE.md" \
      | sed -e 's/ (TEMPLATE)$//' \
            -e '/^> Copy this to your harness/d' \
            -e 's|\*\*`FRAMEWORK\.md`\*\*|**`keel/FRAMEWORK.md`**|' \
            -e 's|\*\*`PRINCIPLES\.md`\*\*|**`keel/PRINCIPLES.md`**|' \
      > "$gclaude.keeltmp.$$" && mv -f "$gclaude.keeltmp.$$" "$gclaude"
    echo "  +    CLAUDE.md (thin wrapper — rails arrive via the import line, fresh on every git pull)"
  elif grep -qE '^@.*keel/CORE\.md[[:space:]]*$' "$gclaude"; then
    echo "  =    CLAUDE.md already imports the linked core"
  elif grep -q 'KEEL-CORE-BEGIN' "$gclaude"; then
    embedded="$(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$gclaude" | sed '1d;$d')"
    shipped="$(sed -n '/KEEL-CORE-BEGIN/,/KEEL-CORE-END/p' "$root/CORE.md" | sed '1d;$d')"
    if [ "$embedded" = "$shipped" ]; then
      replace_core_block "$gclaude"
      echo "  ^    CLAUDE.md — embedded rails swapped for the import line (identical text; now updates with git pull)"
    elif [ -t 0 ]; then
      reply=""
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

  # User-owned seeds (real files, never clobbered).
  copy_gap "$root/templates/INSTANCE.md"  "$HOME_DIR/INSTANCE.md"
  copy_gap "$root/templates/LEARNINGS.md" "$HOME_DIR/LEARNINGS.md"

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
  # User-owned (never clobber) …
  copy_gap "$root/templates/CLAUDE.md"    "$HOME_DIR/CLAUDE.md"
  copy_gap "$root/templates/INSTANCE.md"  "$HOME_DIR/INSTANCE.md"
  copy_gap "$root/templates/LEARNINGS.md" "$HOME_DIR/LEARNINGS.md"
  # … Keel-owned (offered for update on a drifted re-run).
  sync_product "$root/FRAMEWORK.md"       "$HOME_DIR/FRAMEWORK.md"
  sync_product "$root/PRINCIPLES.md"      "$HOME_DIR/PRINCIPLES.md"
fi

# Lifecycle commands — Claude Code reads them from <home>/commands/, so wire them too (never clobber).
# This is what makes /wrap, /go, /init-project, … real slash commands without a manual copy.
if [ -d "$root/commands" ]; then
  mkdir -p "$HOME_DIR/commands"
  for cmd in "$root"/commands/*.md; do
    [ -f "$cmd" ] || continue
    name="$(basename "$cmd")"; alias_dest="$HOME_DIR/commands/keel-$name"
    case "$name" in
      # polish.md is maintainer dev-tooling: a Claude-Code-specific pre-PR flow that pairs with
      # tools/pre-pr-gate.sh, which install.sh deliberately does NOT wire. Shipping the command without
      # its gate would hand adopters an inert feature, so skip it — it stays in the repo for the
      # maintainer + downstream consumers. (Intentional; a future audit should read this as scoped, not
      # half-shipped.)
      polish.md) continue ;;
      # keel-* commands never get an alias (a keel-keel-* name would be noise) — plain drift handling.
      keel-*)    alias_dest="" ;;
    esac
    # a genuinely shipped keel-<name> owns that slot — never repurpose it as a collision alias.
    if [ -n "$alias_dest" ] && [ -f "$root/commands/keel-$name" ]; then alias_dest=""; fi
    sync_product "$cmd" "$HOME_DIR/commands/$name" "$alias_dest"
  done
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
  vfiles=(CLAUDE.md INSTANCE.md LEARNINGS.md keel/CORE.md keel/FRAMEWORK.md keel/PRINCIPLES.md)
else
  vfiles=(CLAUDE.md INSTANCE.md LEARNINGS.md FRAMEWORK.md PRINCIPLES.md)
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

if [ "$LINK" = 1 ]; then
  if grep -qE '^@.*keel/CORE\.md[[:space:]]*$' "$HOME_DIR/CLAUDE.md" 2>/dev/null; then
    echo "  OK   CLAUDE.md imports keel/CORE.md"
  elif grep -q 'KEEL-CORE-BEGIN' "$HOME_DIR/CLAUDE.md" 2>/dev/null; then
    echo "  WARN CLAUDE.md still embeds the rails as a copy (loads fine, but won't update on git pull)."
    echo "       Migrate when ready: replace the KEEL-CORE block with the line  $import_line"
  else
    echo "  WARN CLAUDE.md does not import the linked core — the always-on rails will NOT load."
    echo "       Add the line:  $import_line"
  fi
fi

if [ "$DO_HOOKS" = 1 ]; then
  hp="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = "$keel_hooks" ] && [ -x "$hp/pre-commit" ] && grep -q 'Keel secret-guard' "$hp/pre-commit" 2>/dev/null; then
    # Presence is not function: also run the installed scanner's selftest, so a wired-but-broken
    # gate (e.g. a regressed copy on a re-run) is flagged here instead of degrading silently.
    if [ -x "$hp/secret-scan.sh" ] && "$hp/secret-scan.sh" --selftest >/dev/null 2>&1; then
      echo "  OK   secret-guard ($hp; selftest passed)"
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

if [ "$foreign_core" = 1 ] && [ "$LINK" = 0 ]; then
  # (linked mode has no such gap: the import line delivers the rails into any pre-existing file.)
  echo "  WARN $HOME_DIR/CLAUDE.md predates Keel — its always-loaded rails were NOT merged in (your file is untouched)."
  echo "       Merge the rails you want by hand:  diff $HOME_DIR/CLAUDE.md $root/templates/CLAUDE.md"
fi

[ "$missing" = 0 ] || { echo "install: verification FAILED — core file(s) missing" >&2; exit 1; }

if [ "$LINK" = 1 ]; then
  cat <<EOF

Done (linked mode). secret-guard already guards your commits. Next:
  - EASIEST — restart Claude Code (commands load only at session start), then run  /keel-setup
    Machine setup works from ANYWHERE — no projects needed yet. Later, run /keel-setup again INSIDE
    each project you want Keel on.
  - This clone IS the installation — everything points into it, so never delete it, and park it
    somewhere permanent BEFORE re-running (moving it later dangles every link).
    Update:  git pull  — rails/docs/commands refresh in place; then  ./install.sh --link  once, to
    wire anything a release ADDED (a pull refreshes content, not composition).
    A pull changes your next session's rails without review — pull deliberately, or pin a tag.
  - health check:  tools/doctor.sh --install     (everything shipped is wired, nothing dangles)
  - remove Keel:  delete  $HOME_DIR/keel/ , the one @import line in  $HOME_DIR/CLAUDE.md ,
    and the  $HOME_DIR/commands/  symlinks into this checkout.
  - edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md  private.
EOF
else
  cat <<EOF

Done. secret-guard already guards your commits. Next:
  - EASIEST — restart Claude Code (commands load only at session start), then run  /keel-setup
    Machine setup works from ANYWHERE — no projects needed yet: it fills your machine details and
    the always-on ground rules. Later, run /keel-setup again INSIDE each project you want Keel on —
    that part drafts the project's CLAUDE.md from its code (you review).
  - KEEP this keel clone — /keel-setup and /init-project run its tools/. Park it anywhere out of the
    way (e.g. ~/keel); it's Keel itself, not one of your projects, so don't register it. To update
    later:  git pull && ./install.sh
  - lifecycle commands are in  $HOME_DIR/commands/  → on Claude Code: /wrap, /go, /init-project, …
  - prefer to do it by hand? edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>), keep  $HOME_DIR/INSTANCE.md
    private, and scaffold/audit a project:  tools/init-project.sh <dir>  ;  tools/doctor.sh <dir>
  - measure Keel's impact: new projects (init-project) are tracked by default; for an existing repo run
    tools/keel-impact.sh enable <dir>  then score a session with  /keel-score
EOF
fi
