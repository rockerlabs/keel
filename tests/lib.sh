# shellcheck shell=bash
# shellcheck disable=SC2034  # REPO_ROOT/OUT/STATUS are read by the sourcing test files, not here
# shellcheck disable=SC2154  # $gate (pre-pr-gate.sh receipt fixtures) is set by the sourcing test file
# Keel test harness — zero-dependency bash. Sourced by each tests/test_*.sh.
#
# Provides: an isolated sandbox HOME (so global git config / hooks never touch the real
# environment or the CI runner), small assertion helpers, key-shaped fixture builders, and a
# pass/fail summary. NOT `set -e`: the tests deliberately run commands expected to fail and
# inspect the status.
#
# The ref-namespace rule (dir #318): a test never writes refs (branch, tag, commit, fetch,
# `update-ref`, `worktree add`) in $REPO_ROOT; reading it is fine. For a repo to write in, use
# new_repo() / new_repo_with_origin() below. For this repo's own content or history,
# git clone "$REPO_ROOT" into $SANDBOX and write in the clone. The guard armed below (ref_guard_arm)
# refuses the rest and fails the file.
set -uo pipefail

# dir #644 (closes dir #318 residual N8): a foreign GIT_DIR + a GIT_COMMON_DIR that happens to equal
# REPO_ROOT's own real common dir is NOT bound by ref_guard_arm's includeIf.gitdir pattern below —
# that pattern matches GIT_DIR, not GIT_COMMON_DIR (measured live, docs/specs/318-test-ref-isolation.md
# E19(c)) — so that combination bypasses the guard entirely and a git write from this process lands in
# the real repo even though REPO_ROOT below is computed correctly. Unsetting all four ambient
# repo-selector vars before this file's first git call — including ref_guard_arm's own
# `rev-parse --git-common-dir` on $REPO_ROOT further down — closes the vector: once unset, `-C` is the
# only thing left that can select a repo for the rest of this process and everything it spawns (unset
# removes the var from the exported environment table, not just this shell's view of it). A test that
# deliberately EXERCISES an inherited GIT_DIR (test_lib_ref_guard.sh's T12(a)) is unaffected — it sets
# the var only for one subprocess via `env VAR=... cmd`, which this shell-level unset does not touch.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# --- isolated environment -----------------------------------------------------------------------
# Redirect HOME and the global git config into a throwaway dir. secret-guard --global and
# install.sh both write there; this keeps them off the real machine and the CI runner.
SANDBOX="$(mktemp -d)"
# dir #627: `mktemp -d` can fail silently under this file's `set -uo pipefail` (no `-e`, see the file
# banner) — a failed mktemp leaves SANDBOX empty, and deriving HOME from it below would then produce
# HOME=/home, pointing every fixture (git config --global, install.sh, secret-guard, …) at the real
# machine's root-level /home instead of a throwaway dir. This is the ONE place the sandbox is
# created, so checking it here — BEFORE HOME is derived from it — protects every caller, including
# one whose own `. lib.sh` source line forgot its `|| exit` (the felt incident this ticket exists
# for: a missing lib.sh ran fixtures against the real machine and deleted a live `~/.claude` harness
# home).
if [ -z "$SANDBOX" ] || [ "$SANDBOX" = / ] || [ ! -d "$SANDBOX" ]; then
  printf 'FATAL: mktemp -d did not return a usable sandbox dir (got %s) — refusing to run outside an isolated HOME (dir #627).\n' "$SANDBOX" >&2
  exit 1
fi
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
# dir #251: the impact-score triple's external store root, redirected the same way — a test of the
# store-based path (enable/migrate/rollup --registry) unsets the three explicit overrides above and
# relies on this instead, so it must never resolve into the real $HOME/.claude/.keel/impact/.
export KEEL_IMPACT_STORE="$SANDBOX/harness-impact-store"
# dir #317 S3c: no harness default for KEEL_HOME — a test that needs one sets it itself
# (`env KEEL_HOME=...`, per V1's grep of every read in tests/) — and unset explicitly in case the
# operator's own shell happens to export one, so no tool this harness spawns can resolve through an
# inherited KEEL_HOME by accident.
unset KEEL_HOME
# Same reasoning as KEEL_IMPACT_STORE above, for the read-trace store's own external root (dir #317).
export KEEL_READ_TRACE_STORE="$SANDBOX/harness-read-trace-store"

# Same reasoning, for install.sh/install-pre-pr-gate.sh's checkout-side install ledger (dir #125):
# both always resolve their OWN checkout root from $0/dirname, which for every test in this suite IS
# the real $REPO_ROOT — without this override every install.sh/install-pre-pr-gate.sh call across the
# whole suite would append this run's throwaway sandbox homes into the real, tracked-by-nothing but
# still-real $REPO_ROOT/.keel/installed-homes (found by an independent /code-review high pass, which
# reproduced hundreds of stale entries left behind by exactly this).
export KEEL_LEDGER_FILE="$SANDBOX/harness-installed-homes"

trap 'rm -rf "$SANDBOX"' EXIT

# --- ref guard (dir #318) ------------------------------------------------------------------------
# ref_guard_arm REPO — arm a git-level guard, keyed on REPO's own git common dir, so no git process a
# test spawns (this test's own calls, any tool it runs, any binary on any PATH) can write a ref —
# branch, tag, commit, fetch, update-ref, worktree add — into REPO or any of its worktrees. Reading
# REPO is unaffected; an unrelated repo, or a clone of REPO, is unaffected. Mechanism: two
# command-scope `includeIf.gitdir` entries (via GIT_CONFIG_COUNT/KEY/VALUE, so they reach every git
# process this test spawns, not just ones invoked through this shell) pointing `core.hooksPath` at a
# sandboxed `reference-transaction` hook that aborts every transaction in state "prepared". Command
# scope is required, not optional: it outranks a repo-local or worktree-scope `core.hooksPath`, which
# this project's own worktrees carry (measured; a config-file-based guard would silently lose to it).
#
# If REPO is not a git repository, this is a silent no-op (return 0) — there is nothing to protect.
# This is load-bearing for test_lib_sandbox_guard.sh's copied lib.sh (its REPO_ROOT resolves to the
# copy's parent, not a git repo) and for any other copied-tree fixture.
#
# Never overwrites an existing GIT_CONFIG_KEY_*/VALUE_* entry: it starts at the current
# GIT_CONFIG_COUNT and only appends, so calling this twice (e.g. a child script that sources its own
# copy of this file) keeps the parent's entries intact.
ref_guard_arm() {
  local repo="$1" raw cd_path n hooks_dir escaped i c hook_src seen

  # `rev-parse --git-common-dir` alone answers "is this a repo" too (it fails identically to
  # `--git-dir`, same message and exit code, when $repo isn't one — verified live) — a separate
  # `--git-dir` probe first would just be a second git fork to learn what this call's own failure
  # already tells us.
  #
  # Resolve the common dir. `rev-parse --git-common-dir` may print a path relative to $repo, so
  # resolve it from there with `cd`, then take the physical path with `pwd -P` (not
  # --path-format=absolute: that needs git >= 2.31, and the self-check below already reports an old
  # git some other way). An empty or non-absolute result is refused, never armed: an empty <cd> would
  # turn the second includeIf pattern into `/**`, which matches EVERY repository (measured by
  # accident during this ticket's design: every fixture write was refused when this happened).
  raw="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 0
  cd_path="$(cd "$repo" 2>/dev/null && cd "$raw" 2>/dev/null && pwd -P 2>/dev/null)"
  case "$cd_path" in
    /*) ;;
    *)
      printf 'NOTE: dir #318 ref guard: could not resolve a usable git common dir for %s (got %s) — arming nothing; this test file runs unguarded.\n' "$repo" "$cd_path" >&2
      return 0
      ;;
  esac

  # `${GIT_CONFIG_COUNT:-0}` already substitutes 0 for unset OR empty, so this only needs to reject
  # non-digit content — and, mirroring tools/lib/nonneg-int.sh's own conservative default bound (dir
  # #196: an all-digit string long enough overflows bash's native integer range and silently defeats a
  # later arithmetic comparison), a run of 10 or more digits, which this env var should never
  # legitimately reach (this file is its only writer; E12 found nothing else touches it). Checked here,
  # before anything is written, and refused the same way an unresolvable common dir is refused above
  # (a NOTE, arm nothing) rather than falling back to index 0 — silently defaulting to 0 here would
  # itself violate this function's own "never overwrite an existing entry" rule (item 3) whenever a
  # nested arm call is the one that hits this branch. Kept inline rather than sourcing nonneg-int.sh:
  # tests/lib.sh has no `tools/lib/*.sh` dependency today, and the claude-kb adopter symlinks only this
  # file in (spec E13) — every new dependency here stays optional.
  n="${GIT_CONFIG_COUNT:-0}"
  case "$n" in
    (*[!0-9]*|??????????*)
      printf 'NOTE: dir #318 ref guard: GIT_CONFIG_COUNT is not a small non-negative integer (got %s) for %s — arming nothing rather than risk overwriting an existing entry.\n' "$n" "$repo" >&2
      return 0
      ;;
  esac
  # Normalize to a clean base-10 value now that the shape is known-safe: a leading zero (e.g. "008",
  # "017") would otherwise make bash's own `$((n + 1))` arithmetic below read $n as OCTAL, not decimal
  # — "008" contains an invalid octal digit and crashes arithmetic evaluation outright ("value too
  # great for base"), silently skipping every line after it, including the step-6 self-check that
  # exists specifically so this function never fails open silently; "017" would silently compute the
  # WRONG (smaller) index instead. `10#$n` forces decimal reading of the digit string regardless of
  # leading zeros. Found live (reproduced with `bash -c 'n="008"; echo $((n+1))'`).
  n=$((10#$n))

  # TO VERIFY V1: escape wildmatch metacharacters so includeIf.gitdir never matches an unrelated
  # repository whose path happens to contain one. Not load-bearing either way — the self-check below
  # (step 6) reports an unmatched pattern the same way it reports every other inert-guard cause. Runs
  # unconditionally rather than gating on a separate "does it need escaping" pre-check: the loop
  # already produces the identical, unescaped output on a path with no metacharacters, so a pre-check
  # would only be a second copy of the same four-character class to keep in sync.
  escaped=""
  for ((i = 0; i < ${#cd_path}; i++)); do
    c="${cd_path:i:1}"
    case "$c" in
      '*'|'?'|'['|'\') escaped="${escaped}\\${c}" ;;
      *) escaped="${escaped}${c}" ;;
    esac
  done

  hooks_dir="$SANDBOX/ref-guard/hooks"
  mkdir -p "$hooks_dir"
  # Create the refused-log ONLY if it doesn't already exist — never truncate it. This function can be
  # called more than once in the same process (nested arming, or a test file that arms a second
  # fixture directly), and a later call unconditionally truncating this file would silently erase an
  # earlier refusal's record before summary() ever inspects it, which is precisely the "every refusal
  # fails its test file" guarantee (G2) this file exists to provide. Found live: two sequential arm
  # calls with a refusal in between left the log empty by the time of a simulated summary() check.
  [ -e "$SANDBOX/ref-guard/refused" ] || : > "$SANDBOX/ref-guard/refused"

  # A POSIX sh reference-transaction hook (CLAUDE.md Linux trap 5: not bash). Built via bash
  # parameter substitution, not sed -i or an unquoted heredoc, so the baked-in $SANDBOX path can
  # contain no shell metacharacters that would need escaping either way.
  hook_src='#!/bin/sh
# dir #318 -- refuses every ref write in the repository tests/lib.sh guards; see its header for the
# remedy this refusal points back to.
state="$1"
if [ "$state" = "prepared" ]; then
  cat >> "__REFUSED__"
  echo "dir #318: a test tried to write a ref in the real repository this suite guards -- refused. Use new_repo()/new_repo_with_origin(), or clone \$REPO_ROOT into \$SANDBOX and write there instead." >&2
  exit 1
fi
exit 0
'
  hook_src="${hook_src//__REFUSED__/$SANDBOX/ref-guard/refused}"
  printf '%s' "$hook_src" > "$hooks_dir/reference-transaction"
  chmod +x "$hooks_dir/reference-transaction"

  printf '[core]\n\thooksPath = %s\n' "$hooks_dir" > "$SANDBOX/ref-guard/guard.cfg"

  export "GIT_CONFIG_KEY_$n=includeIf.gitdir:$escaped.path"
  export "GIT_CONFIG_VALUE_$n=$SANDBOX/ref-guard/guard.cfg"
  export "GIT_CONFIG_KEY_$((n + 1))=includeIf.gitdir:$escaped/**.path"
  export "GIT_CONFIG_VALUE_$((n + 1))=$SANDBOX/ref-guard/guard.cfg"
  export GIT_CONFIG_COUNT=$((n + 2))

  # Step 6 self-check, so the guard never fails open silently: git older than 2.31 ignores
  # GIT_CONFIG_COUNT (dir #318 residual N7), an escaped pattern may not have matched, or something in
  # the environment may have overridden the entries. Also checks the hook file itself is present and
  # executable, not just that core.hooksPath resolves to the right directory: a hook git can't execute
  # is silently ignored (git prints only an advisory hint and lets the write through), which
  # core.hooksPath alone reading correctly would never catch (found live: an unexecutable hook let a
  # branch write through with exit 0 despite hooksPath resolving exactly as expected). The test file
  # still runs, unguarded but not silently so.
  seen="$(git -C "$repo" config --get core.hooksPath 2>/dev/null)"
  if [ "$seen" != "$hooks_dir" ]; then
    printf 'NOTE: dir #318 ref guard did not arm for %s (core.hooksPath reads [%s], expected [%s]) — an old git, an unmatched escaped pattern, or the environment overrode it. This test file runs unguarded.\n' "$repo" "$seen" "$hooks_dir" >&2
  elif [ ! -x "$hooks_dir/reference-transaction" ]; then
    printf 'NOTE: dir #318 ref guard did not arm for %s (core.hooksPath is correct, but %s/reference-transaction is missing or not executable) — this test file runs unguarded.\n' "$repo" "$hooks_dir" >&2
  fi
}

ref_guard_arm "$REPO_ROOT"

# dir #627, second fail-open: a test file calling an assertion this library does not define (e.g.
# `check_eq` when only `check_ne` exists) loses that assertion SILENTLY — bash prints its own
# "command not found" to stderr and, under this file's `set -uo pipefail` (no `-e`), the test file
# keeps running with fewer checks than it meant to have. Felt live: four equality assertions vanished
# from a new test file and the suite stayed green; the miscount (30 expected, 26 reported) was what
# gave it away, not any failure. command_not_found_handle is a bash >= 4.0 feature — this project's
# own dev machine ships /bin/bash 3.2.57, where an unknown command just prints bash's own message and
# returns 127 without ever invoking this handler, so it is LINUX-ONLY protection here, closing the
# hole on CI's bash 5 legs and any adopter running bash >= 4 locally. The portable backstop that also
# covers bash 3.2 is tests/run.sh's own "command not found" scan of each test file's captured log
# (dir #627) — but that only fires for a run THROUGH run.sh; a single test file run directly
# (`./tests/test_x.sh`) on bash < 4 is the one case neither mechanism reaches (named residual, see
# BACKLOG.md dir #627). A bare `exit` does NOT work here — verified live on this project's
# alpine/bash-5 CI image (dir #627): bash dispatches command_not_found_handle in a SEPARATE forked
# execution environment (its own $BASHPID, confirmed live), the exact same shape
# require_sandbox_path() above documents for its own `$(...)`-subshell callers — an `exit` inside it
# only ends that fork, and the calling script continues right past the undefined call as if it had
# simply returned nonzero. `kill -TERM $$` reaches the top-level pid the same way it does there
# (`$$` stays the top-level script's pid even inside the fork — verified live), so it actually stops
# the whole test file; the trailing `exit 90` is the same belt-and-suspenders fallback
# require_sandbox_path() uses, in case the signal is not yet delivered by the time this function
# would otherwise return.
command_not_found_handle() {
  printf 'FATAL: %s: unknown command/assertion "%s" — lib.sh does not define it (dir #627: an unknown assertion must fail loudly, not vanish silently).\n' "$(basename "$0")" "$1" >&2
  kill -TERM $$
  exit 90
}

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

# extract_rails_block FILE [strip_indent] — the delegation-doctrine "Worker rails" block a file
# carries (docs/delegation.md's canonical text, or a verbatim copy elsewhere), start-to-end-marker
# inclusive. Promoted here (dir #375) once a THIRD test file (test_polish_review_rails.sh) needed the
# exact same awk range test_drydock_doc.sh and test_delta_audit_doc.sh had each already defined
# independently — this file's own "second use = promote" convention (see pin()'s comment above), overdue
# at three. Pass strip_indent=1 when the copy sits inside a nested list item and needs its leading
# whitespace normalized before a byte-identity comparison; the two pre-existing call sites stay
# flush-left and don't need it. The range markers tolerate leading whitespace unconditionally (zero
# spaces satisfies `[[:space:]]*` too), so one awk program covers both modes — stripping is then just
# whether awk's own `sub()` runs on each matched line, never a second `sed` process.
extract_rails_block() {
  local file="$1" strip="${2:-}"
  awk -v strip="$strip" '
    /^[[:space:]]*- You are read-only:/,/^[[:space:]]*- DELEGATION RUN:/ {
      if (strip == "1") sub(/^[[:space:]]*/, "")
      print
    }
  ' "$file"
}

# check_block_equal LABEL A B — assert two block-extracted strings are identical and non-empty,
# printing a diff on mismatch rather than a bare presence check (dir #209's own finding: a substring
# pin can survive a drift that deletes or reorders a contract line, since "the text is somewhere in the
# file" says nothing about whether it is INTACT). Promoted here (dir #375) alongside
# extract_rails_block above, same convention — test_drydock_doc.sh defined this first,
# test_polish_review_rails.sh needed the exact same idiom for a third file.
check_block_equal() {
  local label="$1" a="$2" b="$3"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    pass "$label"
  else
    fail "$label" "block-extracted text differs or is empty — diff:
$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"
  fi
}

# snapshot_tree_cksum DIR — every regular file under DIR, path + content hash, sorted for order-
# independence: a byte-identical-before/after proof strong enough to catch a CONTENT change to an
# existing file of the same size/mtime-minute, which `ls -la` (the dir #617(a) block's own snapshot)
# would miss. `cksum`, not `shasum`: POSIX, present on every CI leg including alpine's busybox —
# `shasum` is a macOS/perl tool alpine does not have (found live, dir #644: every check silently read
# as "identical" against empty `find` output on both sides there). Promoted here at its second use
# (lib.sh's own convention, pin()'s comment: "one caller; promote... only at a second use") —
# tests/test_install.sh's own T12b inlines the same idiom with one extra exclusion
# (`! -path '*/.keel/install-manifest.*'`), left as its own inline copy rather than folded onto this
# general form: its excluded path is specific to what install.sh itself writes, not a general
# snapshot need. Pair with check_block_equal, same as the dir #617(a) block's `ls -la` pairing. Every
# call site today passes an absolute mktemp-derived path, but this is a shared helper now — a future
# caller passing a relative path whose first component starts with `-` would make `find` parse it as
# a flag instead of a path and fail loud, unrelated to whatever the caller is actually testing (found
# by /code-review max's own line-by-line pass). A leading `--` does NOT fix this (tried first,
# corrected by a later /code-review max round, reproduced live on all three `find`s this project's own
# CLAUDE.md documents — macOS BSD find, alpine busybox, ubuntu GNU findutils: none treats `--` as a
# strict end-of-options marker for `find`'s own path/predicate grammar, so a bare relative
# dash-leading argument still misparses with or without it). The actual fix is the standard technique
# for this class of pitfall (the same one `rm ./-file` uses): prefix a non-absolute `$1` with `./` so
# its first character is never `-`, portable across all three.
snapshot_tree_cksum() {
  local d="$1"
  case "$d" in /*) ;; *) d="./$d" ;; esac
  find "$d" -type f -exec cksum {} + | sort
}

# check_count LABEL FILE PATTERN EXPECTED — assert PATTERN (a grep BRE, as-is — callers already anchor
# their own patterns with `^` where that's the point, same as their pre-promotion call sites did)
# occurs exactly EXPECTED times in FILE, reporting under LABEL with the actual count on failure.
# Promoted here (dir #371) once a 4th test file (test_core_capability_index.sh) needed the exact same
# "grep -c, compare to an expected count, pass/fail" idiom test_core_wrapper_sync.sh,
# test_parallel_sessions_doc.sh, and test_release_audit_doc.sh had each defined independently — the
# same "second use = promote" convention pin() above and release_tag_versions() below already follow
# for their own idioms. The three pre-existing call sites are left as their own inline checks (each
# has its own local variable name and failure wording already tuned and tested); only new call sites
# are expected to reach for this helper going forward.
check_count() {
  local label="$1" file="$2" pattern="$3" expected="$4" n
  n="$(grep -c "$pattern" "$file")"
  if [ "$n" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "found $n occurrence(s), expected $expected"
  fi
}

# section_body HEADING FILE — print the lines strictly between HEADING (matched by exact string
# equality, never regex) and the next "## " heading in FILE. Promoted here (dir #371) once a 2nd call
# site (test_core_capability_index.sh) needed the same "flag-based section slicer, stop at the next
# top-level heading" idiom tests/test_doc_figures.sh's own "What just got set up" section extraction
# already used ad hoc — same "second use = promote" convention as check_count() above. That 1st call
# site is left un-retrofitted, same reasoning as check_count()'s 3 pre-existing sites: its own
# extraction pipes straight into a further filter (`&& /^\|/`) tuned to its one caller, and a shared
# helper's job here is only the SLICE — a caller needing more filters its own way, same as it always did.
section_body() {
  local heading="$1" file="$2"
  awk -v h="$heading" '$0 == h { f = 1; next } /^## / { f = 0 } f { print }' "$file"
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

# The one real UTF-8 locale this HOST actually has, preferring C.UTF-8 (musl/Alpine ships only that,
# not en_US.UTF-8/ru_RU.UTF-8) — for a test that must exercise a genuine non-C locale axis, since
# every test in this suite otherwise runs under this file's ambient C locale (dir #250: a locale-
# dependent miss went uncaught for exactly that reason). Prints the locale name and returns 0, or
# prints nothing and returns 1 when the host has none. `locale -a`'s output is captured into a
# variable first, not piped straight into `grep -q`: under a `set -o pipefail` file, `-q`'s
# first-match exit would SIGPIPE the still-writing `locale -a` and read as failure (the same hazard
# `count_matches()` in secret-scan.sh documents for `git cat-file --batch`).
# dir #627 (found live by an independent /code-review high pass on this ticket's own diff, reproduced
# on the project's alpine CI image): the explicit `command -v locale` guard below is now load-bearing,
# not decoration — CI's alpine leg ships no `locale` binary at all (`command -v locale` there is exit
# 127), and this file's own new command_not_found_handle() now catches exactly that lookup failure and
# kills the WHOLE test-file process with SIGTERM before this function ever gets to its documented
# graceful "return 1" — defeating the two real callers' `utf8_locale="$(pick_utf8_locale)" ||
# utf8_locale=""` fallback and turning a legitimately-passing file red. A `2>/dev/null` on the call
# does NOT protect against this: command_not_found_handle fires on the shell's COMMAND LOOKUP itself,
# before anything resembling `locale`'s own stderr exists to redirect.
# Usage:  utf8_locale="$(pick_utf8_locale)" || utf8_locale=""
pick_utf8_locale() {
  local avail cand
  command -v locale >/dev/null 2>&1 || return 1
  avail="$(locale -a 2>/dev/null)"
  # Both namings per non-C locale too (dir #250 code review): glibc's `locale -a` spells these
  # lowercase/no-hyphen (`en_US.utf8`) on Debian/Ubuntu, not just the hyphenated form macOS/BSD use.
  for cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8 ru_RU.UTF-8 ru_RU.utf8; do
    case "$avail" in *"$cand"*) printf '%s' "$cand"; return 0 ;; esac
  done
  return 1
}

# Like run, but execute in DIR (restoring cwd) — for tools that read a cwd-relative file.
run_in() {
  local dir="$1"; shift
  local prev="$PWD"
  # dir #478: `cd ""` is a silent bash no-op (returns 0, $PWD unchanged) — an empty $dir never trips
  # the `cd ... || {...}` guard below, so it must be rejected explicitly before the cd is attempted.
  [ -n "$dir" ] || { OUT="run_in: empty dir argument"; STATUS=99; return; }
  cd "$dir" || { OUT="cannot cd $dir"; STATUS=99; return; }
  run "$@"
  cd "$prev" || true
}

check_status()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi; }
check_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "output missing: $3" ;; esac; }
check_absent()   { case "$2" in *"$3"*) fail "$1" "output should not contain: $3" ;; *) pass "$1" ;; esac; }
# dir #481 (found by this ticket's own /code-review high pass, two independent delta-round agents):
# `check_absent "$a" "$b"` is a SUBSTRING check, not an equality check — it fails when $b is anywhere
# inside $a, which is a strictly weaker test than "$a" != "$b" and can spuriously fail two genuinely
# DISTINCT values where one happens to be a substring of the other (e.g. two digit-only hash suffixes
# sharing a common prefix). A caller asserting plain inequality wants this, not check_absent.
check_ne()       { if [ "$2" != "$3" ]; then pass "$1"; else fail "$1" "expected different values, both were '$2'"; fi; }
check_file()     { if [ -f "$2" ]; then pass "$1"; else fail "$1" "missing file: $2"; fi; }
check_dir()      { if [ -d "$2" ]; then pass "$1"; else fail "$1" "missing dir: $2"; fi; }
check_nofile()   { if [ -f "$2" ]; then fail "$1" "file should not exist: $2"; else pass "$1"; fi; }
check_nodir()    { if [ -d "$2" ]; then fail "$1" "dir should not exist: $2"; else pass "$1"; fi; }
check_link()     { if [ -L "$2" ]; then pass "$1"; else fail "$1" "not a symlink: $2"; fi; }
check_nolink()   { if [ -L "$2" ]; then fail "$1" "should not be a symlink: $2"; else pass "$1"; fi; }

# match HAYSTACK GREP_ARGS... — grep against an in-memory string via a `<<<` here-string, not a
# `printf HAYSTACK | grep ...` pipe (dir #280, promoted here once a sixth test file needed the exact
# same idiom — this file's own established "second use = promote" convention, see release_tag_versions
# below). Under load, grep's own early exit on a match (`-q`/`-m`) can close the read end of a pipe
# before printf finishes writing; this file's `pipefail` then reports printf's broken-pipe failure
# instead of grep's real (successful) match, silently flipping a real hit into "missing" (reproduced
# live: a genuine v0.3.0 release-history heading was reported missing this exact way). A here-string
# has bash buffer the content up front, so there's no live writer process for grep's early exit to
# signal — pass grep's own flags (including -q) straight through, e.g. `match "$s" -qw "$v"`.
match() { local h="$1"; shift; grep "$@" <<< "$h"; }

# STRICT_SEMVER_TAG_RE — a v-prefixed strict-semver tag name (`v<x.y.z>`, the `v` kept), anchored.
# Exposed as its own variable (dir #318) so a second data source for the same tag SHAPE —
# all_release_tag_versions()'s own `ls-remote` leg below, which release_tag_versions() can't cover
# since it always reads local `git tag -l`, never arbitrary ref-listing text — filters through the
# identical pattern instead of hand-copying it a fourth time.
STRICT_SEMVER_TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

# release_tag_versions REPO_ROOT — echoes every v-prefixed strict-semver release tag (`v<x.y.z>`, the
# `v` kept), one per line, `git tag -l`'s own order. Third independent copy of this exact regex found
# by /code-review medium on dir #232's own diff (tools/self/doctor.sh's `_release_tag_versions()` — not
# sourceable, doctor.sh runs its own audit on load — plus test_changelog_section.sh and
# test_release_history.sh, both of which DO already source this file): promoted here so the two test
# files share one copy instead of three total. doctor.sh keeps its own private copy (bare version, `v`
# stripped) since it isn't a consumer of this file.
release_tag_versions() {
  git -C "$1" tag -l 'v*' | grep -E "$STRICT_SEMVER_TAG_RE" || true
}

# all_release_tag_versions REPO_ROOT — the union of release_tag_versions() (local `git tag -l`) and a
# read-only `git ls-remote` of origin, deduplicated, v kept, one per line (dir #318, found live during
# this ticket's own /code-review). A CI checkout starts shallow AND tagless (actions/checkout's default
# depth carries no tags), so before this ticket every test in this suite that needed real tags was
# quietly riding on test_changelog_section.sh's OWN now-removed `fetch --prune --tags` against
# $REPO_ROOT — an undocumented cross-test dependency the ticket's own design missed: removing that
# fetch (G3) took test_release_history.sh's tag source down with it, reproduced live on a tagless
# clone. Every consumer that needs real tags on a shallow/tagless checkout calls this instead of
# release_tag_versions() alone. Marks REPO_ROOT safe first — the alpine CI leg mounts the checkout
# under a different uid, so git would otherwise refuse to even read it ("dubious ownership"); safe to
# call from more than one test file, since each runs in its own sandboxed HOME/GIT_CONFIG_GLOBAL (dir
# #64) and this only ever writes `safe.directory = *`, not a path-specific entry. `ls-remote`'s own
# lines are `<sha><TAB>refs/tags/<name>`, so `cut -f2` before stripping the `refs/tags/` prefix (a bare
# `sed` strip alone would leave the sha glued to the name — E1b). Falls back to the local list alone on
# failure (no network, no `origin`) — the same fail-open the removed fetch's own `|| true` had.
all_release_tag_versions() {
  local repo="$1" remote remote_raw
  git config --global --add safe.directory '*'
  remote=""
  if remote_raw="$(git -C "$repo" ls-remote --tags --refs origin 'v*' 2>/dev/null)"; then
    remote="$(printf '%s\n' "$remote_raw" | cut -f2 | sed 's#^refs/tags/##' | grep -E "$STRICT_SEMVER_TAG_RE" || true)"
  fi
  printf '%s\n%s\n' "$(release_tag_versions "$repo")" "$remote" | sed '/^$/d' | LC_ALL=C sort -u
}

# --- fixtures -----------------------------------------------------------------------------------
# Join a prefix and body so the *source* of a test file never holds a whole key-shaped token —
# the repo's own secret-guard (and GitHub push protection) would otherwise block committing it.
key() { printf '%s%s' "$1" "$2"; }
# Repeat CHAR ($1) N ($2) times — e.g. a key body of the length the pattern requires.
rep() { printf "%*s" "$2" '' | tr ' ' "$1"; }
# ASCII string -> UTF-16LE bytes (NUL-interleaved), no iconv needed — for binary-fixture tests
utf16le() { local s="$1" i; for ((i=0; i<${#s}; i++)); do printf '%s\000' "${s:i:1}"; done; }

# dir #318: guards a freshly-mktemp'd fixture dir before the first `git -C` call touches it. A path
# that resolves to empty, ".", or anything outside $SANDBOX (mktemp failing silently under `set -uo
# pipefail` — no `-e` here, so a failed mktemp's empty stdout would otherwise flow straight into an
# unguarded `git -C "" init`/`git -C "$d" commit`) is the one way new_repo()/new_bare_origin() could
# point real git mutations at the caller's actual cwd instead of a throwaway dir. Not reproduced live
# (see BACKLOG.md), but the fixture branch/commit shapes this suite deliberately creates
# (crossfork-feature, "substantial follow-up commit", etc.) would corrupt a real checkout's history
# if it ever did. $2 names the caller in the error message.
#
# Every real caller invokes new_repo()/new_bare_origin() via command substitution
# (`d="$(new_repo)"`), which forks a subshell — a plain `exit` here would only kill THAT subshell, not
# the test file, leaving the caller's `d` empty and STILL free to run the next `git -C "$d" ...` call
# against its own cwd (reproduced live: a bare `exit 90` in this position is a silent no-op on the
# exact path it exists to close, found by /code-review high on this ticket's own diff). `kill -TERM
# $$` reaches past the subshell — bash keeps `$$` equal to the top-level script's pid even inside a
# `$(...)` subshell (verified on both GNU bash 5 and the bash 3.2 this suite must also run under) — so
# it terminates the whole test file's process, not just this call. `exit 90` right after is a fallback
# in case the signal is not yet delivered by the time this function would otherwise return.
require_sandbox_path() {
  case "$1" in
    "$SANDBOX"/*) ;;
    *)
      printf '%s: mktemp did not return a sandbox-scoped path (got %s) — refusing to touch it\n' "$2" "$1" >&2
      kill -TERM $$
      exit 90
      ;;
  esac
}

# A throwaway git repo under the sandbox; prints its path.
new_repo() {
  local d
  d="$(mktemp -d "$SANDBOX/repo.XXXXXX")"
  require_sandbox_path "$d" new_repo
  git -C "$d" init -q
  printf '%s' "$d"
}

# A fresh bare origin, wired to work tree $1's "origin" remote (mktemp -d + git init --bare + remote
# add origin — the two of new_repo_with_origin()'s five lines that don't presume a commit already
# exists). Split out so a caller that must commit real content BEFORE its first push
# (tests/test_drydock_inventory.sh's mk_repo()) can wire the remote without paying for the throwaway
# commit+push
# new_repo_with_origin() bakes in for its own no-content callers. Prints the bare's path.
new_bare_origin() {
  local bare
  bare="$(mktemp -d "$SANDBOX/origin.XXXXXX")"
  require_sandbox_path "$bare" new_bare_origin
  git init -q --bare "$bare"
  git -C "$1" remote add origin "$bare"
  printf '%s' "$bare"
}

# dir #173: new_repo() plus a fresh bare "origin" — pushed, so `origin/<branch>` is a real ref to be at
# (or off). This exact idiom (a bare origin, wired, and pushed to) was hand-rolled in five test files
# before this promotion, two of them matching it closely enough to migrate here (`pin()`'s own comment
# states the promotion rule — "once a SECOND test file needed the exact same idiom" — this was one past
# it); the other three push specific refspecs or deliberately diverge local from origin/<branch> and were
# left as their own fixtures — and both migrated files (test_drydock_inventory.sh's own "a repository with
# no commits at all" case, test_pre_pr_gate.sh's `push_named_remote()`) still keep a hand-rolled site of
# their own alongside using this helper.
# Makes one empty "init" commit first, since a bare new_repo() has no
# commits to push (unborn HEAD). No explicit fetch: a successful push already updates the local
# origin/<branch> tracking ref (git's own default since 1.8.4), so a fetch right after would just
# re-derive a ref git already set. Prints the work tree's path, like new_repo() — callers that also need
# the bare origin's own path (a second work tree pointed at the same origin, say) recover it with
# `git -C "$d" remote get-url origin` rather than a second return channel: this is called via `$(...)`
# (a subshell), so a plain variable set inside it never reaches the caller.
new_repo_with_origin() {
  local d
  d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m init
  new_bare_origin "$d" >/dev/null
  git -C "$d" push -q origin "$(branch_raw_for "$d")"
  printf '%s' "$d"
}

# --- pre-pr-gate.sh receipt fixtures -------------------------------------------------------------
# Shared by test_pre_pr_gate.sh and test_pipeline_canary.sh (dir #64) — both drive the SAME gate CLI
# subcommands to build a complete, matching receipt. Expects the CALLER to have already set a $gate
# variable (the path to tools/pre-pr-gate.sh) before calling these.
ALL_STEPS="polish.1-diff polish.2-simplify polish.3-tests polish.4-depth polish.5-review polish.6-retest polish.7-selfcheck polish.8-unlock"

# Shared repo-key derivation (mirrors the production file's own _repo_key) — the trace/rollout-state
# files (still repo-only keyed, dir #80) key off this one function instead of each caller inlining the
# algorithm separately. NAIVE on purpose (no worktree redirection) — for any $1 that is not itself a
# worktree, main_top_for($1) == $1, so this already matches production's `_repo_key`; the dir #61
# worktree tests below rely on this naive/redirected DIVERGENCE (a worktree's own key vs its main
# checkout's) to prove the redirection actually happens. dir #481: production now hashes the FULL path
# (basename kept only as a cosmetic prefix — see `_repo_key_from_path`'s own comment) instead of
# basename alone, so this mirror must hash the SAME full path production would — `git rev-parse
# --show-toplevel` first, not $1 verbatim: macOS's mktemp -d returns a path under the symlink `/var`,
# and git's own toplevel resolution canonicalizes it to `/private/var/...` before `main_top_for` (via
# `git worktree list --porcelain`) ever sees it, so hashing $1 raw silently diverged from production's
# hash of the resolved path — caught live via test_pipeline_canary.sh's trace-file check, which reads
# the trace this fixture writes back through production's own `_repo_key_of`, and found no file there
# once the two hashes stopped agreeing. Falls back to $1 verbatim when it isn't a repo at all (mirrors
# production's own main_top_for fallback). Kept in sync manually with production, same rationale as
# branch_key_for/receipt_hash_for below (these fixtures build the EXPECTED path independently of the
# code under test, not by invoking it).
repo_key_for() {
  local top resolved
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)"
  resolved="${top:-$1}"
  printf '%s-%s' "$(basename "$resolved")" "$(receipt_hash_for "$resolved" '')"
}
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
# dir #398/#399/#637: the gate's state root, mirroring production's gate_state_root()/
# gate_pre_pr_gate_root() (tools/lib/gate-paths.sh) — $HOME/.keel/tmp/pre-pr-gate.
# $HOME is already this file's own sandbox (line ~31 above), so every fixture below lands inside
# $SANDBOX automatically, same as production would resolve it in a real session. Kept in sync
# manually with production, same rationale as repo_key_for/branch_key_for above.
gate_tmp_root_for_tests() { printf '%s/.keel/tmp/pre-pr-gate' "$HOME"; }
# dir #398: every purpose now lives in its OWN subdirectory (sentinel/, trace/, …) rather than a flat
# filename, and production only `mkdir -p`s one right before its first real write (never on a plain
# read, dir #398's own hook-cost concern). A test fixture has no such hot-path cost to protect, and
# several fixtures below write DIRECTLY through the path this returns (no real gate subcommand in
# between to do that mkdir for them) — so this ensures the directory eagerly, every call, read or
# write. Found live: a bare `: > "$(sentinel_for "$d")"` fixture failed with "No such file or
# directory" the first time a repo's sentinel/ subdirectory didn't exist yet.
gate_tmp_purpose_dir() {
  local d; d="$(gate_tmp_root_for_tests)/$1"
  mkdir -p "$d" 2>/dev/null
  printf '%s' "$d"
}
combined_key_for() {
  local rk; rk="$(repo_key_for "$1")"
  printf '%s-%s-%s' "$rk" "$(receipt_hash_for "$rk" "$(branch_raw_for "$1")")" "$(branch_key_for "$1")"
}
sentinel_for() { printf '%s/%s' "$(gate_tmp_purpose_dir sentinel)" "$(combined_key_for "$1")"; }
# dir #72: the single-slot backup `retire_sentinel()`/`init` write on every sentinel invalidation —
# `receipt --recover` reads it.
prev_sentinel_for() { printf '%s/%s' "$(gate_tmp_purpose_dir prev-sentinel)" "$(combined_key_for "$1")"; }
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
# instead of re-typing the state-root prefix at every call site.
real_sentinel_for() { printf '%s/%s' "$(gate_tmp_purpose_dir sentinel)" "$(real_key_for "$1" "$2")"; }
# dir #63/#80: the hand-off note's own file, keyed the same way as the sentinel. Lives here next to
# sentinel_for/real_sentinel_for (this ticket's own /code-review found the naive handoff_for had
# drifted into test_pre_pr_gate.sh instead, duplicating this same composition a third time).
handoff_for() { printf '%s/%s' "$(gate_tmp_purpose_dir handoff)" "$(combined_key_for "$1")"; }
real_handoff_for() { printf '%s/%s' "$(gate_tmp_purpose_dir handoff)" "$(real_key_for "$1" "$2")"; }
# dir #63: the code-review skill-trace file, keyed by repo only (not repo+branch, unlike the
# sentinel/handoff above — see pre-pr-gate.sh's own trace_path_for). Shared by test_pre_pr_gate.sh and
# test_pipeline_canary.sh, same rationale as repo_key_for/sentinel_for above.
trace_for() { printf '%s/%s' "$(gate_tmp_purpose_dir trace)" "$(repo_key_for "$1")"; }

# Build a complete, matching receipt at $1 (repo dir) via the CLI subcommands (run_in so $PWD == $1, since
# both `init` and `receipt` key the sentinel off basename "$PWD"). $2 = optional step to omit (for the
# incomplete-receipt tests); $3 = optional step whose line should be re-tagged with a foreign nonce instead
# of being written at all (for the replay tests). polish.5-review defaults to a TRUSTED outcome
# (`medium-operator-run`) — dir #63's trace cross-check only applies to a bare level, and these fixtures
# are about the OTHER completeness/replay/worktree mechanics, not that check; a real caller can still
# override via write_full_receipt_review() when it needs a bare level. polish.4-depth is derived to carry
# the SAME base level as the review outcome (dir #63's depth-mismatch check requires this on every real
# receipt, trusted outcomes included).
# $5 = optional polish.4-depth level OVERRIDE, for the deliberate depth-MISMATCH fixtures (dir #158).
# Without it, the depth is derived from the review outcome and always agrees with it by construction, so
# there was no way to ask this helper for a disagreeing pair — every such test had to open-code the whole
# 9-line init+receipt sequence by hand instead, and there are now several near-identical copies of it
# (found by /simplify's reuse AND simplification passes, independently). New mismatch fixtures should
# pass this rather than add a copy. **dir #183 migrated test 50h onto it** — not drive-by tidying, but
# because dir #183 deleted the override's only other caller and a helper parameter with zero callers is
# dead by accident rather than by decision. **dir #163 migrated the remaining four (18b, 18c, 49, 50d)**,
# so every deliberate-depth-mismatch fixture now goes through this one idiom.
write_full_receipt() { write_full_receipt_review "$1" "medium-operator-run" "${2:-}" "${3:-}"; }
write_full_receipt_review() {
  local d="$1" review_outcome="$2" omit="${3:-}" replay_step="${4:-}" depth_override="${5:-}" s depth_level
  # dir #366: strip the longer `-waived:trace-broken` suffix before the plain `-waived` one — the two
  # don't overlap (a string ending in `-waived:trace-broken` does not end in bare `-waived`, so the
  # plain strip below is a no-op for it regardless of order), but a caller passing
  # `medium-waived:trace-broken` with no explicit depth_override needs this to derive `medium`, not
  # the un-stripped literal (which would fail the gate's own depth-level allowlist as an invented
  # value — a latent trap the dir #366 tests below dodge by always passing an explicit override).
  depth_level="${review_outcome%-waived:trace-broken}"
  depth_level="${depth_level%-operator-run}"; depth_level="${depth_level%-waived}"
  # dir #81/#141/#183: a combined `agent:<level>+<addon>` outcome records step 4's depth as the bare
  # level too, so strip the add-on the same way `-operator-run`/`-waived` are stripped above (order
  # relative to the `agent:` prefix strip below doesn't matter — prefix and suffix never overlap — but
  # keeping every suffix-strip grouped here is deliberate). `%%+*` (strip from the FIRST `+` onward),
  # not a list of per-addon `%+operator-run` / `%+second-opinion` strips: an enumerated strip would
  # have to be extended for every new add-on, and — the property that actually matters here — it would
  # NOT strip an INVALID add-on at all, which is exactly what the deny-path fixtures pass. A fixture
  # writing `agent:high+bogus-addon` needs `polish.4-depth high` so the test denies for the reason it
  # is about (the unknown token) rather than for a depth mismatch the fixture accidentally built in.
  # The greedy form handles valid and invalid suffixes identically; no real review level contains `+`,
  # so it cannot over-strip. (Written against dir #158's comma SET, where the enumerated form also
  # mis-derived multi-addon outcomes; dir #183 removed the set, and the greedy strip's logic needs no
  # change — only this reasoning did, since the multi-addon example it cited can no longer exist.)
  depth_level="${depth_level%%+*}"
  # dir #70: an `agent:<level>` outcome (the independent-subagent-review leg) records step 4's depth as
  # the bare level too — strip the prefix the same way the `-operator-run`/`-waived` suffixes are stripped
  # above, so a caller can pass "agent:high" and still get a matching polish.4-depth of "high".
  depth_level="${depth_level#agent:}"
  # Applied AFTER the derivation above so the override is the last word, whatever shape came in.
  [ -n "$depth_override" ] && depth_level="$depth_override"
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

# apostrophe_fixture_checkout LABEL — a disposable copy of just tools/ (never $REPO_ROOT itself) under
# an apostrophe-bearing dir name ("$SANDBOX/Alex's LABEL/keel"), for a dir #514-shaped regression: an
# installer that resolves its own repo_root as `tools/..` needs only that subtree, so this is scoped
# down from a whole-checkout copy (found by /simplify — a whole-checkout `cp -r` was pure I/O waste for
# a test that only ever exercises tools/). Sets $APOSTROPHE_CKDIR to the checkout root (the parent of
# tools/, matching what the installer's own $repo_root computation expects). Shared by
# tests/test_install_pre_pr_gate.sh and tests/test_install_read_trace.sh, which otherwise hand-copied
# this identically (the SAME "keep two copies in sync by hand" shape dir #514's own fix closed for the
# installers' escaping logic).
apostrophe_fixture_checkout() {
  APOSTROPHE_CKDIR="$SANDBOX/Alex's $1/keel"
  mkdir -p "$APOSTROPHE_CKDIR"
  cp -r "$REPO_ROOT/tools" "$APOSTROPHE_CKDIR/tools"
}

# apostrophe_cmd_argv COMMAND — evals COMMAND (a hook command string extracted from a generated
# settings.json or snippet, e.g. `bash '/path/with'\''s an apostrophe' rollout-check`) into the array
# $APOSTROPHE_ARGV the same way Claude Code's own hook runner would parse it — the real proof that an
# escaped path round-trips, not a hand-rolled unescaper (which would just re-encode the same
# assumption the fix is supposed to verify).
apostrophe_cmd_argv() {
  APOSTROPHE_ARGV=()
  eval "APOSTROPHE_ARGV=($1)"
}

# dir #318, G2: a refused ref write fails the file even when the refused command's own failure was
# swallowed (`|| true`, `2>/dev/null` — test_changelog_section.sh's old `fetch` had exactly this
# shape). Checked here, once, right before the totals line, rather than at every call site.
#
# NAMED RESIDUAL, alongside tools/lib/ref-guard.sh's own N1-N9 (dir #333): a ref-mutating git call
# that turns out to be a no-op (E7 — a `fetch` with nothing new to pull, a `branch` that already
# exists at the same tip) never reaches the reference-transaction hook's "prepared" state at all, so
# it produces no transaction for the hook to refuse and G2 has nothing to catch. This is a structural
# property of the reference-transaction mechanism, not specific to any one test file — measured, not
# closed: G3 (the same PR) fixes the one shipped instance this class had (test_changelog_section.sh's
# old fetch, which only ever wrote something on a genuine origin move), but a future ref-mutating call
# that happens to no-op on the day it's written is not caught here, or anywhere else in the suite.
summary() {
  if [ -s "$SANDBOX/ref-guard/refused" ]; then
    fail "no test wrote the real repository's refs (dir #318)" "$(cat "$SANDBOX/ref-guard/refused")"
  fi
  printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_pass" "$_fail"
  [ "$_fail" -eq 0 ]
}
