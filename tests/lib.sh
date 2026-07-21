# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO_ROOT/OUT/STATUS are read by the sourcing test files, not here
# Keel test harness — zero-dependency bash. Sourced by each tests/test_*.sh.
#
# Provides: an isolated sandbox HOME (so global git config / hooks never touch the real
# environment or the CI runner), small assertion helpers, key-shaped fixture builders, and a
# pass/fail summary. NOT `set -e`: the tests deliberately run commands expected to fail and
# inspect the status.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# --- isolated environment -----------------------------------------------------------------------
# Redirect HOME and the global git config into a throwaway dir. secret-guard --global and
# install.sh both write there; this keeps them off the real machine and the CI runner.
SANDBOX="$(mktemp -d)"
export HOME="$SANDBOX/home"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
unset XDG_CONFIG_HOME 2>/dev/null || true
mkdir -p "$HOME"
git config --global user.email test@keel.invalid
git config --global user.name "Keel Test"
git config --global init.defaultBranch main
git config --global commit.gpgsign false

# Redirect impact writes into the sandbox by default, so a guardrail firing (or a stray `add`) during a
# test never records into a real .keel/ log or into Keel's own docs/keel-impact.md. Tests that assert on
# these override with their own path; tests of the .keel/-marker default path unset them and run inside a
# fresh repo. Removed with the sandbox on exit.
export KEEL_IMPACT_LOG="$SANDBOX/harness-impact.log"
export KEEL_IMPACT_LEDGER="$SANDBOX/harness-ledger.md"
export KEEL_IMPACT_EVIDENCE="$SANDBOX/harness-evidence.md"

trap 'rm -rf "$SANDBOX"' EXIT

# --- assertions ---------------------------------------------------------------------------------
_pass=0
_fail=0

pass() { _pass=$((_pass + 1)); printf '  ok    %s\n' "$1"; }
fail() { _fail=$((_fail + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

# run CMD...  → capture combined stdout+stderr in OUT, exit status in STATUS
run() {
  OUT="$("$@" 2>&1)"
  STATUS=$?
}

# Like run, but execute in DIR (restoring cwd) — for tools that read a cwd-relative file.
run_in() {
  local dir="$1"; shift
  local prev="$PWD"
  cd "$dir" || { OUT="cannot cd $dir"; STATUS=99; return; }
  run "$@"
  cd "$prev" || true
}

check_status()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi; }
check_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "output missing: $3" ;; esac; }
check_absent()   { case "$2" in *"$3"*) fail "$1" "output should not contain: $3" ;; *) pass "$1" ;; esac; }
check_file()     { if [ -f "$2" ]; then pass "$1"; else fail "$1" "missing file: $2"; fi; }
check_dir()      { if [ -d "$2" ]; then pass "$1"; else fail "$1" "missing dir: $2"; fi; }
check_nofile()   { if [ -f "$2" ]; then fail "$1" "file should not exist: $2"; else pass "$1"; fi; }
check_link()     { if [ -L "$2" ]; then pass "$1"; else fail "$1" "not a symlink: $2"; fi; }
check_nolink()   { if [ -L "$2" ]; then fail "$1" "should not be a symlink: $2"; else pass "$1"; fi; }

# --- fixtures -----------------------------------------------------------------------------------
# Join a prefix and body so the *source* of a test file never holds a whole key-shaped token —
# the repo's own secret-guard (and GitHub push protection) would otherwise block committing it.
key() { printf '%s%s' "$1" "$2"; }
# Repeat CHAR ($1) N ($2) times — e.g. a key body of the length the pattern requires.
rep() { printf "%*s" "$2" '' | tr ' ' "$1"; }
# ASCII string -> UTF-16LE bytes (NUL-interleaved), no iconv needed — for binary-fixture tests
utf16le() { local s="$1" i; for ((i=0; i<${#s}; i++)); do printf '%s\000' "${s:i:1}"; done; }

# A throwaway git repo under the sandbox; prints its path.
new_repo() {
  local d
  d="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
  git -C "$d" init -q
  printf '%s' "$d"
}

# A PATH dir ($1) symlinking every executable currently on $PATH EXCEPT the names in $2.. — for
# testing a script's dependency check when one or more tools are missing.
path_farm() {
  local dest="$1" d f n hide hidden=0
  shift
  mkdir -p "$dest"
  IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      n=${f##*/}
      hidden=0
      for hide in "$@"; do [ "$n" = "$hide" ] && { hidden=1; break; }; done
      [ "$hidden" = 1 ] && continue
      [ -e "$dest/$n" ] || ln -s "$f" "$dest/$n"
    done
  done
  unset IFS
}

summary() {
  printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_pass" "$_fail"
  [ "$_fail" -eq 0 ]
}
