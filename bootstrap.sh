#!/bin/sh
# Keel bootstrap — one-line install. Fetches Keel (git clone, or a source tarball when git is absent),
# runs install.sh, cleans up.
#
#   curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh
#
# Pass install.sh flags after `--`, e.g.  … | sh -s -- --no-hooks   (or --home DIR).
# Version: no flag installs the latest main; pin a release with KEEL_REF=<tag> (a tag/branch). Point
# elsewhere with KEEL_REPO; force/offline a source tarball with KEEL_TARBALL (a .tar.gz URL or local file).
#
# Release-pinned copy: `releases/latest/download/bootstrap.sh` serves a copy stamped at release time
# (KEEL_DEFAULT_REF below, set by tools/stamp-release-bootstrap.sh) so that asset installs ITS OWN tag
# by default instead of main — KEEL_REF still overrides it. The copy tracked in git always ships
# KEEL_DEFAULT_REF="" (tracks main) — never hand-edit that line; it's stamped into the release asset only.
#
# Linked mode (--link, Claude Code): the linked install wires by REFERENCE (symlinks into a checkout +
# one import line), so it needs a checkout that OUTLIVES this script — the temp clone below would leave
# every symlink dangling. So --link clones into a PERMANENT dir (KEEL_DIR, default ~/keel) and never
# reaps it; re-running the one-liner over that checkout updates it in place (git pull) instead. --link
# requires git.
#
# No git? Copy mode falls back to downloading a source tarball — that installs the prose rails + commands
# only; secret-guard is a git hook, so without git it's skipped (announced, and --no-hooks forced).
#
# POSIX sh (it's piped to `sh`); install.sh itself needs bash, checked below. Prefer reading this
# before piping a remote script to a shell — or use the clone path in the README if you'd rather.
set -eu

REPO="${KEEL_REPO:-https://github.com/rockerlabs/keel.git}"
KEEL_DEFAULT_REF=""
REF="${KEEL_REF:-$KEEL_DEFAULT_REF}"

have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || { echo "keel: '$1' is required but not found" >&2; exit 1; }; }
need bash   # install.sh and the git hooks have a bash shebang; git is checked contextually below

# fetch URL DEST — download with whatever's on hand (curl, then wget).
fetch() {
  if   have curl; then curl -fsSL "$1" -o "$2"
  elif have wget; then wget -qO "$2" "$1"
  else echo "keel: need git, or curl/wget, to fetch Keel" >&2; exit 1
  fi
}

LINK=0
case " $* " in *" --link "*) LINK=1 ;; esac

if [ "$LINK" = 1 ]; then
  have git || { echo "keel: --link needs git (it clones a checkout and updates it with git pull). Install git, or drop --link for a copy install." >&2; exit 1; }
  # Linked mode: clone into a PERMANENT dir the symlinks can point into (not the reaped temp clone).
  # A full clone (no --depth) so the kept checkout supports `git pull` cleanly later.
  dest="${KEEL_DIR:-$HOME/keel}"
  if [ -e "$dest" ]; then
    # Re-running the one-liner over an existing Keel checkout = update it in place. Anything else that
    # already occupies the path is user data — refuse rather than clobber it.
    if [ -d "$dest/.git" ] && [ -f "$dest/install.sh" ] && [ -f "$dest/CORE.md" ]; then
      echo "keel: updating the existing checkout at $dest …"
      if [ -n "$REF" ]; then
        # A re-run that names a ref moves the checkout to it (a tag/branch/SHA) — otherwise a bare
        # `git pull` would ignore KEEL_REF and silently keep the old version.
        git -C "$dest" fetch -q --tags origin && git -C "$dest" checkout -q "$REF" \
          || echo "keel: could not update $dest to $REF — linking the checkout as-is" >&2
      else
        git -C "$dest" pull --ff-only -q \
          || echo "keel: could not fast-forward $dest — linking the checkout as-is" >&2
      fi
    else
      echo "keel: '$dest' already exists and is not a Keel checkout — refusing to overwrite it." >&2
      echo "      Point KEEL_DIR at an empty path (KEEL_DIR=~/some/dir), or remove '$dest' first." >&2
      exit 2
    fi
  else
    echo "keel: cloning $REPO${REF:+ @ $REF} into $dest …"
    if [ -n "$REF" ]; then
      git clone -q --branch "$REF" "$REPO" "$dest"
    else
      git clone -q "$REPO" "$dest"
    fi
  fi
  echo "keel: running install.sh --link …"
  ( cd "$dest" && ./install.sh "$@" )
else
  # Copy mode (default): a temp clone/extract is enough — install.sh copies the files out, then we reap it.
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT INT TERM
  src="$tmp/keel"

  if have git && [ -z "${KEEL_TARBALL:-}" ]; then
    echo "keel: cloning $REPO${REF:+ @ $REF} …"
    if [ -n "$REF" ]; then
      git clone -q --depth 1 --branch "$REF" "$REPO" "$src"
    else
      git clone -q --depth 1 "$REPO" "$src"
    fi
  else
    # No git (or an explicit KEEL_TARBALL): fetch a source tarball instead of cloning. Without git this
    # installs the prose rails + commands only — secret-guard is a git hook, so it's skipped.
    if ! have git; then
      echo "keel: git not found — installing the prose rails + commands only (secret-guard needs git; skipping it)."
      case " $* " in *" --no-hooks "*) ;; *) set -- "$@" --no-hooks ;; esac
    fi
    need tar
    # Resolve the source in priority order: KEEL_TARBALL as a local file, then as a URL, then derive one
    # from the (GitHub) repo. The repo shape only matters when KEEL_TARBALL is unset.
    tarball="$tmp/keel.tar.gz"
    if [ -n "${KEEL_TARBALL:-}" ] && [ -f "$KEEL_TARBALL" ]; then
      cp "$KEEL_TARBALL" "$tarball"
    elif [ -n "${KEEL_TARBALL:-}" ]; then
      echo "keel: downloading $KEEL_TARBALL …"; fetch "$KEEL_TARBALL" "$tarball"
    else
      case "$REPO" in
        *github.com*) url="${REPO%.git}/archive/${REF:-main}.tar.gz" ;;
        *) echo "keel: can't derive a tarball URL from '$REPO' — install git, or set KEEL_TARBALL to a .tar.gz URL/path." >&2; exit 1 ;;
      esac
      echo "keel: downloading $url …"; fetch "$url" "$tarball"
    fi
    mkdir -p "$src"
    tar -xzf "$tarball" -C "$src"
    # GitHub archives (and our `git archive --prefix=`) wrap everything in a single top dir; descend into
    # it so $src is the repo root. If install.sh is already at top, the tarball was flat — leave it.
    if [ ! -f "$src/install.sh" ]; then
      inner="$(find "$src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
      [ -n "$inner" ] && src="$inner"
    fi
  fi

  echo "keel: running install.sh …"
  # This clone/extract is reaped when the trap fires — tell install.sh, so it skips everything that
  # must point into a KEPT checkout (the bin/keel symlink, the CLI/uninstall promises in the
  # summary). Otherwise the run would ship a symlink that dangles the moment this script exits.
  ( cd "$src" && KEEL_EPHEMERAL=1 ./install.sh "$@" )
fi
