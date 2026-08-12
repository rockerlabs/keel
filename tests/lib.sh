# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO_ROOT/OUT/STATUS are read by the sourcing test files, not here
# shellcheck disable=SC2154  # $gate (pre-pr-gate.sh receipt fixtures) is set by the sourcing test file
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

# pin LABEL FILE PATTERN HINT — assert FILE contains PATTERN as a fixed string (grep -F), reporting
# under LABEL with HINT on failure. Promoted here (dir #143) once a second test file
# (test_release_audit_doc.sh) needed the exact same prose-citation-pin idiom
# test_rails_honesty.sh had defined for itself — the "second use = promote" signal this file's own
# earlier comments already apply to run()/fresh_home_env()/etc.
pin() {
  if grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "$4"
  fi
}

# run CMD...  → capture combined stdout+stderr in OUT, exit status in STATUS
#
# dir #85 (code audit, finding 19): stdin is redirected from /dev/null for EVERY run. CI is always
# non-interactive so this changes nothing there, but a developer running `bash tests/test_install.sh`
# by hand from a terminal inherits that terminal as stdin — and install.sh's `[ -t 0 ]` interactive
# branches (the drift re-run prompt) then genuinely block on `read`, hanging the suite with no
# indication why. test_uninstall.sh had already been patched case-by-case with a `</dev/null` and a
# comment explaining it; doing it once here covers the other three install-touching test files too.
# The redirect is applied INSIDE the capture, so it wins over anything redirected onto the `run` call
# itself: a test that must FEED stdin builds its own two-line capture instead (`gate()` in
# test_pre_pr_gate.sh and test_keel_check_gate.sh already do exactly that, for exactly that reason).
run() {
  OUT="$("$@" 2>&1 </dev/null)"
  STATUS=$?
}

# An isolated HOME *plus* its own global git config, for tools that must not see the shared sandbox
# state. lib.sh pins GIT_CONFIG_GLOBAL to one sandbox-wide config (above), so a fresh HOME ALONE does
# not isolate `git config --global` — a non-obvious invariant three separate dir #85 tests each had to
# re-derive. Sets the ARRAY $FRESH_HOME_ENV rather than printing a string: callers expand it quoted, so
# a sandbox path containing a space stays one argument (an earlier printf version relied on the caller
# word-splitting it, which silently mangled `env`'s arguments on such a path — found by the
# operator-run /code-review high pass on dir #85).
# $FRESH_HOME_ENV is OVERWRITTEN by the next call, so expand it right away. If the value has to survive
# later calls — a helper function that closes over it, say — copy it into your own array at the point
# you set it (`fresh_home_env "$h"; my_env=("${FRESH_HOME_ENV[@]}")`); expanding $FRESH_HOME_ENV inside
# a function body re-reads it at CALL time, silently following whatever home was set last.
# Usage:  h="$SANDBOX/x"; mkdir -p "$h"; fresh_home_env "$h"; run env "${FRESH_HOME_ENV[@]}" some-tool
fresh_home_env() { FRESH_HOME_ENV=("HOME=$1" "GIT_CONFIG_GLOBAL=$1/.gitconfig"); }

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

# --- pre-pr-gate.sh receipt fixtures -------------------------------------------------------------
# Shared by test_pre_pr_gate.sh and test_pipeline_canary.sh (dir #64) — both drive the SAME gate CLI
# subcommands to build a complete, matching receipt. Expects the CALLER to have already set a $gate
# variable (the path to tools/pre-pr-gate.sh) before calling these.
ALL_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"

# Shared repo-key derivation (mirrors the production file's own _repo_key) — the trace/rollout-state
# files (still repo-only keyed, dir #80) key off this one function instead of each caller inlining
# `basename "$1"` separately. NAIVE on purpose (plain basename, no worktree redirection) — for any $1
# that is not itself a worktree, main_top_for($1) == $1, so this already matches production's
# `_repo_key`; the dir #61 worktree tests below rely on this naive/redirected DIVERGENCE (a worktree's
# own basename vs its main checkout's) to prove the redirection actually happens.
repo_key_for() { basename "$1"; }
# dir #80: sanitized current-branch slug, mirroring the production file's own `_sanitize_branch`
# byte-for-byte (kept in sync manually, not via a subcommand round-trip, so these
# fixtures work standalone the same way repo_key_for's naive basename does — see the same comment).
# The branch name is captured into a variable FIRST (command substitution strips the trailing
# newline `git branch --show-current` prints) before piping through `tr` — piping git's raw output
# straight into `tr -c` would translate that trailing newline into a trailing '-' too, same bug
# `_sanitize_branch` in production avoids the same way.
branch_key_for() {
  local branch
  branch="$(git -C "$1" branch --show-current 2>/dev/null)"
  printf '%s' "$branch" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-'
}
# dir #80: the RAW (unsanitized) current branch of dir $1 — mirrors the production file's own
# `_branch_raw_for`. Needed separately from branch_key_for's sanitized slug because the hash below
# must hash the RAW branch, not the (lossy) slug — see receipt_hash_for's own comment.
branch_raw_for() { git -C "$1" branch --show-current 2>/dev/null; }
# dir #80 (this ticket's own /code-review high finding): mirrors the production file's own
# `_receipt_key_hash` byte-for-byte — a plain "$repo-$branch" string join is ambiguous (both halves
# routinely contain '-'), and the sanitized branch slug alone is lossy (`branch_key_for`'s tr-to-'-'
# collapses distinct branches like "feature/foo" and "feature-foo" to the same string) — hashing the
# RAW (repo-key, branch) pair sidesteps both. Kept in sync manually with production, same rationale
# as branch_key_for's own comment (these fixtures build the EXPECTED path independently of the code
# under test, not by invoking it).
receipt_hash_for() { printf '%s\x1f%s' "$1" "$2" | cksum | tr -cd '0-9'; }
# dir #80: sentinel/prev-sentinel/hand-off are now keyed by (repo, branch), not repo alone — every
# caller below keys off THIS pairing (`<repo>-<hash>-<slug>`, matching production's `$RECEIPT_KEY`
# format). For the dir #61 worktree tests, where the correct key mixes the MAIN checkout's repo
# component with the WORKTREE's own branch component, use `real_key_for` instead (below) —
# sentinel_for/prev_sentinel_for/handoff_for, called on a single dir, only ever combine that SAME
# dir's own repo+branch, which is right for every non-worktree fixture but wrong for a worktree one
# (see the dir #61 test section's own comments for why).
combined_key_for() {
  local rk; rk="$(repo_key_for "$1")"
  printf '%s-%s-%s' "$rk" "$(receipt_hash_for "$rk" "$(branch_raw_for "$1")")" "$(branch_key_for "$1")"
}
sentinel_for() { printf '/tmp/pre-pr-gate-%s' "$(combined_key_for "$1")"; }
# dir #72: the single-slot backup `retire_sentinel()`/`init` write on every sentinel invalidation —
# `receipt --recover` reads it.
prev_sentinel_for() { printf '/tmp/pre-pr-gate-prev-%s' "$(combined_key_for "$1")"; }
# dir #80: the REAL (repo, branch) key as production resolves it when the two halves come from
# DIFFERENT checkouts of the same repo — $1 = the repo dir (pass the MAIN checkout when it differs
# from where the branch was read), $2 = the dir whose OWN current branch is the branch component (a
# worktree's own branch, not its main checkout's — each worktree has an independent checked-out
# branch by git's own design, so _repo_key's worktree-redirection has no equivalent on the branch
# side to undo).
real_key_for() {
  local rk; rk="$(repo_key_for "$1")"
  printf '%s-%s-%s' "$rk" "$(receipt_hash_for "$rk" "$(branch_raw_for "$2")")" "$(branch_key_for "$2")"
}
# dir #80: the real sentinel path for a (repo dir, branch-source dir) pair — wraps real_key_for the
# same way sentinel_for wraps the single-dir key, so the dir #61 worktree tests build the path once
# instead of re-typing the `/tmp/pre-pr-gate-` prefix at every call site.
real_sentinel_for() { printf '/tmp/pre-pr-gate-%s' "$(real_key_for "$1" "$2")"; }
# dir #63/#80: the hand-off note's own file, keyed the same way as the sentinel. Lives here next to
# sentinel_for/real_sentinel_for (this ticket's own /code-review found the naive handoff_for had
# drifted into test_pre_pr_gate.sh instead, duplicating this same composition a third time).
handoff_for() { printf '/tmp/pre-pr-gate-handoff-%s' "$(combined_key_for "$1")"; }
real_handoff_for() { printf '/tmp/pre-pr-gate-handoff-%s' "$(real_key_for "$1" "$2")"; }
# dir #63: the code-review skill-trace file, keyed by repo only (not repo+branch, unlike the
# sentinel/handoff above — see pre-pr-gate.sh's own trace_path_for). Shared by test_pre_pr_gate.sh and
# test_pipeline_canary.sh, same rationale as repo_key_for/sentinel_for above.
trace_for() { printf '/tmp/pre-pr-gate-trace-%s' "$(repo_key_for "$1")"; }

# Build a complete, matching receipt at $1 (repo dir) via the CLI subcommands (run_in so $PWD == $1, since
# both `init` and `receipt` key the sentinel off basename "$PWD"). $2 = optional step to omit (for the
# incomplete-receipt tests); $3 = optional step whose line should be re-tagged with a foreign nonce instead
# of being written at all (for the replay tests). polish.5-review defaults to a TRUSTED outcome
# (`medium-operator-run`) — dir #63's trace cross-check only applies to a bare level, and these fixtures
# are about the OTHER completeness/replay/worktree mechanics, not that check; a real caller can still
# override via write_full_receipt_review() when it needs a bare level. polish.4-depth is derived to carry
# the SAME base level as the review outcome (dir #63's depth-mismatch check requires this on every real
# receipt, trusted outcomes included).
write_full_receipt() { write_full_receipt_review "$1" "medium-operator-run" "${2:-}" "${3:-}"; }
write_full_receipt_review() {
  local d="$1" review_outcome="$2" omit="${3:-}" replay_step="${4:-}" s depth_level
  depth_level="${review_outcome%-operator-run}"; depth_level="${depth_level%-waived}"
  # dir #81: the combined `agent:<level>+operator-run` outcome records step 4's depth as the bare level
  # too — strip this suffix the same way `-operator-run`/`-waived` are stripped above (order relative to
  # the `agent:` prefix strip below doesn't matter — prefix and suffix never overlap — but stripping it
  # here keeps every suffix-strip grouped together), so a caller can pass "agent:high+operator-run" and
  # still get a matching polish.4-depth of "high".
  depth_level="${depth_level%+operator-run}"
  # dir #70: an `agent:<level>` outcome (the independent-subagent-review leg) records step 4's depth as
  # the bare level too — strip the prefix the same way the `-operator-run`/`-waived` suffixes are stripped
  # above, so a caller can pass "agent:high" and still get a matching polish.4-depth of "high".
  depth_level="${depth_level#agent:}"
  run_in "$d" bash "$gate" init
  # Hoisted: nothing in the loop commits, so HEAD is invariant across it — one fork instead of three.
  local head_sha; head_sha="$(git -C "$d" rev-parse HEAD)"
  for s in $ALL_STEPS; do
    [ "$s" = "$omit" ] && continue
    if [ "$s" = "$replay_step" ]; then
      printf 'stale-nonce-from-a-previous-run\t%s\tdone\n' "$s" >> "$(sentinel_for "$d")"
      continue
    fi
    if [ "$s" = "polish.8-unlock" ] || [ "$s" = "polish.6-retest" ] || [ "$s" = "polish.3-tests" ]; then
      # dir #72 finding #1: polish.6-retest's outcome is now sha-checked the same way polish.8-unlock's
      # is — a bare "done" would no longer pass the gate. dir #96 added polish.3-tests to the same set:
      # some test run must be bound to the shipped commit, and step 3 is where that normally comes from.
      run_in "$d" bash "$gate" receipt "$s" "$head_sha"
    elif [ "$s" = "polish.5-review" ]; then
      run_in "$d" bash "$gate" receipt "$s" "$review_outcome"
    elif [ "$s" = "polish.4-depth" ]; then
      run_in "$d" bash "$gate" receipt "$s" "$depth_level:test-fixture"
    else
      run_in "$d" bash "$gate" receipt "$s"
    fi
  done
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
