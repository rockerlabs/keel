#!/usr/bin/env bash
# Records the README demo GIF (docs/demo.gif) — a REAL, sandboxed secret-guard run:
# machine-global install → a key-shaped commit blocked → the owner's name blocked
# inside a UTF-16 binary fixture. Nothing is mocked: the outputs on screen are the
# hook's actual outputs.
#
# Sandboxed like examples/tour.sh: HOME and the global git config are redirected into
# a temp dir; the repo's tools are copied there so no local path leaks into the frames;
# nothing on the recording machine is touched, and the sandbox is removed on exit.
#
#   docs/demo/record-demo.sh            # record + render (needs: brew install asciinema agg)
#   docs/demo/record-demo.sh --scenes   # inner mode: just play the scenes (what gets recorded)
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"

if [ "${1:-}" != "--scenes" ]; then
  command -v asciinema >/dev/null 2>&1 || { echo "missing asciinema (brew install asciinema)"; exit 1; }
  command -v agg       >/dev/null 2>&1 || { echo "missing agg (brew install agg)"; exit 1; }
  castdir="$(mktemp -d)"
  trap 'rm -rf "$castdir"' EXIT
  asciinema rec --quiet --cols 100 --rows 24 \
    --command "bash '$root/docs/demo/record-demo.sh' --scenes" "$castdir/demo.cast"
  agg --font-size 16 "$castdir/demo.cast" "$root/docs/demo.gif"
  echo "wrote docs/demo.gif ($(du -h "$root/docs/demo.gif" | cut -f1 | tr -d ' '))"
  exit 0
fi

# ---- inner mode: the scenes ---------------------------------------------------------

sandbox="$(mktemp -d /tmp/keel-demo.XXXX)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"; mkdir -p "$HOME/.claude"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
git config --global user.email you@example.com
git config --global user.name "You"
git config --global init.defaultBranch main

# a neutral copy of the tools, so the recording shows no machine-specific paths
cp -R "$root/tools" "$sandbox/keel-tools"
proj="$sandbox/my-project"
mkdir -p "$proj"
git -C "$proj" init -q

say() { printf '\033[2m%s\033[0m\n' "$*"; sleep 1.4; }

# print a prompt, "type" the command char by char, then actually run it
type_cmd() {
  printf '\033[1;32m$\033[0m '
  local s="$1" i
  for ((i = 0; i < ${#s}; i++)); do
    printf '%s' "${s:i:1}"
    sleep 0.035
  done
  printf '\n'
  sleep 0.2
  eval "$1"
  sleep "${2:-1.6}"
}

cd "$sandbox" || exit 1
say "# keel secret-guard — a real run (sandboxed: HOME + git config redirected)"
type_cmd "keel-tools/install-secret-guard.sh --global" 2.2

cd "$proj" || exit 1
say "# an API key sneaks into a config file..."
# built from parts so this script's own source never holds a whole key
fake_key="$(printf '%s%s' 'ghp_' 'abcdefghijklmnopqrstuvwxyz0123456789')"
type_cmd "echo 'token = \"$fake_key\"' > config.py" 0.4
type_cmd "git add config.py && git commit -m 'add config'" 3.0
git reset -q && rm -f config.py   # silent cleanup so scene 3 shows only its own hit

say "# opt-in: list YOUR OWN literals (name, emails, drives) in a local, never-committed file"
type_cmd "echo 'Jane Doe' > ~/.claude/secret-scan-personal" 0.6

say "# a binary fixture generated from a real device carries its owner's name, UTF-16 encoded"
type_cmd "printf 'device owner: Jane Doe' | iconv -t UTF-16LE > fixture.bin" 0.6
type_cmd "git add fixture.bin && git commit -m 'add test fixture'" 3.2

say "# text advises — hooks enforce.   github.com/rockerlabs/keel"
sleep 2
