#!/usr/bin/env bash
# doctor — structural self-audit of a project's knowledge-base baseline.
#
# The baseline is the durable convention; this script is its current instance. It reports drift, it does
# not fix it. Three tiers, printed ordered GAP → WARN → HINT per audit unit (dir #45 — a brownfield
# first run is a triaged report, not a wall in check order):
#   GAP   fails the audit (exit 1) — the baseline is structurally broken
#   WARN  advisory, safety/integrity — something that leaks, or a rail that looks wired but isn't
#   HINT  advisory, engineering convention — a nudge, exactly the tier a quiet run wants gone
# Every finding carries a stable ID ([G-*]/[W-*]/[H-*]) — referenceable in docs and issues, and the key
# the accept file matches on: .keel/doctor-accept (at the MAIN checkout's .keel/, one ID per line,
# `#` comments) suppresses that WARN/HINT class; suppressed findings are counted in the tail summary,
# `--all` shows them. doctor only READS the file. A GAP is never suppressed — accepting a hard failure
# would fake a green exit. The tail summary (`doctor: X gap, Y warn, Z hint`) prints on every run.
#
# Usage:
#   doctor.sh [PROJECT_DIR ...]     audit each dir (default: current dir)
#   doctor.sh --registry FILE       audit every project in an INSTANCE.md Projects table (the Path column)
#   doctor.sh --quiet ...           print only GAP/WARN lines (+ the tail summary)
#   doctor.sh --all ...             also show findings suppressed by .keel/doctor-accept
#
# Checks per project:
#   GAP   G-DIR-MISSING        the project directory itself does not exist
#   GAP   G-GIT-MISSING        not a git repo
#   GAP   G-CLAUDEMD-MISSING   no project CLAUDE.md
#   GAP   G-GITIGNORE-CONTEXT  .gitignore does not ignore the private AI context — unless public fork
#   GAP   G-AGENTSMD-CONTEXT  AGENTS.md exists but .gitignore does not ignore it — unless public fork
#   GAP   G-AGENTSMD-INHERIT  AGENTS.md's tracked/ignored status does not match CLAUDE.md's (dir #75:
#                             AGENTS.md always inherits CLAUDE.md's git status)
#   WARN  W-CLAUDEMD-GITIGNORED  CLAUDE.md absent but gitignored (private/mechanism repo — create it locally)
#   WARN  W-AGENTSMD-DRIFT     AGENTS.md is a regular-file copy that has drifted from CLAUDE.md, or a
#                             symlink pointing somewhere other than CLAUDE.md
#   WARN  W-EVENTLOG-TRACKED   a .keel/ marker exists but its event log isn't gitignored (leak risk)
#   WARN  W-KEEL-SPLIT         a worktree-local .keel/ marker coexists with the main checkout's —
#                             either a linked worktree carrying its own stray marker, or the main
#                             checkout with one or more linked worktrees carrying their own
#   WARN  W-GUARD-UNWIRED      secret-guard not wired: no usable core.hooksPath (unset, or set to a dir
#                              carrying no executable pre-commit) and no local hook. Sensitive to a
#                              redirected global git config, so it names its source (dir #97)
#   WARN  W-GUARD-BYPASSED     a local core.hooksPath override carries no executable pre-commit — this
#                              repo's commits run nothing, and any global guard is bypassed (dir #97)
#   WARN  W-GUARD-STALE        a wired per-repo secret-guard copy differs from the engine this checkout
#                              ships — vendored, or reached through a RELATIVE global core.hooksPath,
#                              which names a different dir in every repo (dir #97). An ABSOLUTE
#                              machine-global copy is W-GUARD-GLOBAL-STALE instead, checked once
#   WARN  W-EMAIL-PUBLIC       publication-bound project committing with a non-noreply email
#   WARN  W-WT-BRIDGE          a private-fork linked worktree missing the CLAUDE.md bridge (blind session)
#   WARN  W-GATE-PARTIAL       project-scope /polish gate: some hook references it but the load-bearing
#                              PreToolUse/Bash one is missing (plain absence isn't flagged — opt-in)
#   HINT  H-FOOTPRINT          session startup footprint (project CLAUDE.md + resolved global
#                              CLAUDE.md/keel/CORE.md) over budget (KEEL_STARTUP_WARN_TOKENS, 10000)
#   HINT  H-MAP-DRIFT          CLAUDE.md map may be stale — a backtick-spanned path no longer on disk
#                              (path-granular accept stays .keel/map-drift-baseline)
#   HINT  H-DEP-FLOATING       floating dependency version (image :latest / Action @vN)
#   HINT  H-LINT-*             a detected stack missing its lint gate (JAVA/PY/SWIFT/BASH);
#                              H-JAVA-WILDCARD — a Java file uses a wildcard import
# (--install mode audits the install instead; its findings are GAP/WARN only, IDs in the code below.)
set -euo pipefail

QUIET=0
REGISTRY=""
DIRS=()
usage() {
  cat <<'EOF'
doctor — audit a project's Keel knowledge-base baseline.
Findings print ordered GAP (fails, exit 1) → WARN (safety/integrity advisory) → HINT (convention
nudge), each with a stable ID. List WARN/HINT IDs in .keel/doctor-accept (main checkout, one ID per
line, # comments) to suppress that class — suppressed findings are counted in the tail summary.

Usage:
  doctor.sh [DIR ...]          audit DIR(s) for the baseline (default: .)
  doctor.sh --registry FILE    audit every project in an INSTANCE.md Projects table
  doctor.sh --install [HOME]   audit the Keel INSTALL instead: everything this checkout ships
                               is wired (or deliberately declined), nothing dangles
                               (default HOME: \$KEEL_HOME, else ~/.claude)
  doctor.sh --install --codex [HOME]
                               audit a  install.sh --codex  install instead (AGENTS.md is the
                               rails carrier, commands/ is never wired — default HOME: ~/.codex)
  doctor.sh --quiet            print only GAP/WARN lines (+ the tail summary)
  doctor.sh --all              also show findings suppressed by .keel/doctor-accept
  doctor.sh -h | --help

Example:  doctor.sh ~/code/my-project
EOF
}
INSTALL_MODE=0
SHOW_ALL=0
CODEX_MODE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    --all) SHOW_ALL=1 ;;
    --registry) shift; REGISTRY="${1:?--registry needs a FILE}" ;;
    --install) INSTALL_MODE=1 ;;
    --codex) CODEX_MODE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "doctor: unknown option '$1' (try --help)" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

# --codex only makes sense against --install: it is install.sh's own mode flag (dir #134, mirroring
# uninstall.sh's dir #109), not a per-project audit concept — a project's CLAUDE.md/AGENTS.md pairing
# is already covered by the AGENTS.md drift checks in the per-project loop below.
if [ "$CODEX_MODE" = 1 ] && [ "$INSTALL_MODE" = 0 ]; then
  echo "doctor: --codex only applies to --install" >&2; exit 2
fi

# Pull project paths from the Path column of an INSTANCE.md Projects table.
# Skips the header, the separator, and unfilled placeholder rows; expands a leading ~.
if [ -n "$REGISTRY" ]; then
  [ -f "$REGISTRY" ] || { echo "doctor: registry not found: $REGISTRY" >&2; exit 2; }
  while IFS='|' read -r _lead _col1 col_path _rest; do
    path="$(printf '%s' "$col_path" | tr -d '`' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$path" in
      ""|Path|*"<"*) continue ;;        # header / blank / placeholder
    esac
    path="${path/#\~/$HOME}"
    DIRS+=("$path")
  done < <(awk 'BEGIN{f=0} /^[[:space:]]*(```|~~~)/{f=!f;next} !f' "$REGISTRY" \
            | grep -E '^[[:space:]]*\|' | grep -vE '^[[:space:]]*\|[-:| ]+\|?[[:space:]]*$')
fi

# In install mode a positional arg is the harness HOME, not a project dir — don't default it to ".".
if [ "$INSTALL_MODE" = 0 ]; then
  [ "${#DIRS[@]}" -gt 0 ] || DIRS=(".")
fi

WARN_TOKENS="${KEEL_STARTUP_WARN_TOKENS:-10000}"
case "$WARN_TOKENS" in ''|*[!0-9]*) WARN_TOKENS=10000 ;; esac   # non-numeric → default (no `[: integer expected`)
exit_code=0

# The @import line's own detection regex — mirror of install.sh's has_core_import() — used twice
# below (H-FOOTPRINT's global-core resolution, and the --install rails check further down): one
# definition instead of two hand-copies of the same literal in this file (keep the two in sync with
# install.sh's own copy).
core_import_re='(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)'

# Byte-count-or-0: `wc -c` an existing file, degrading to 0 on any read failure instead of aborting
# the whole run under `set -euo pipefail` (an unreadable CLAUDE.md must not take down findings already
# buffered for this unit — dir #45). Used 3x below (the global core's own size, its resolved @import
# target, and each project's own CLAUDE.md) — one definition instead of three hand-copies.
_char_count() {
  local n
  n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')" || n=0
  [ -n "$n" ] || n=0
  printf '%s' "$n"
}

# manifest_field FILE KEY — the value of a top-level `key=value` line in an install manifest (dir
# #125), first match, "" on any read failure. Used below to read both install-manifest.<mode> and
# install-manifest.gate — one definition instead of hand-copied sed pipelines. `|| true` at the end: an
# EXISTING but unreadable manifest (permission-denied) makes `sed` exit non-zero even with stderr silenced, and
# under this file's own `set -euo pipefail` an unguarded pipeline failure here would abort the WHOLE
# run mid-unit — losing every finding already buffered in $NOTES and printing no summary line at all
# (found by an independent /code-review high pass). The manifest-versioning contract says exactly
# this case degrades to "treated as absent", never a crash — same `|| true` degradation the file's
# own load_token_set() already uses for the identical unreadable-file risk.
manifest_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1 || true
}

# dir #114 (M4-2): H-FOOTPRINT used to measure only the project's own CLAUDE.md, so the number it
# printed was a floor on real startup cost, not the whole of it — the global core is the OTHER half
# of every session's always-loaded set. Resolved once here (machine-invariant across every $d in the
# loop below) — same default-home expression --install mode's own $ihome/$ihome_flag/$gate_flag
# comparisons already hand-copied twice further down; those now reuse $ghome too instead of a third
# copy, so a plain `doctor.sh` run (no --install) finds the SAME global CLAUDE.md that install audits.
#
# _rails_file DIR — which of CLAUDE.md/AGENTS.md actually carries the rails at DIR, so a --codex
# adopter's real startup cost (AGENTS.md, not CLAUDE.md — dir #134) is summed instead of silently
# read as "no global install" (a --codex home has no CLAUDE.md at all). CLAUDE.md wins when a home
# holds both (dir #124's shape): this is a plain per-project audit with no --codex context of its
# own to disambiguate with, so it defaults to the harness doctor otherwise assumes throughout. Prints
# "CLAUDE.md" when NEITHER exists too — the caller's own -f check then simply finds nothing, same as
# before this existed.
_rails_file() {
  if   [ -f "$1/CLAUDE.md" ]; then printf 'CLAUDE.md'
  elif [ -f "$1/AGENTS.md" ]; then printf 'AGENTS.md'
  else                             printf 'CLAUDE.md'
  fi
}
ghome="${KEEL_HOME:-${HOME:-}/.claude}"
ghome_context="$(_rails_file "$ghome")"
# footprint_home/footprint_context — where H-FOOTPRINT actually looks. Same as $ghome UNLESS
# $KEEL_HOME is unset AND nothing lives at the Claude default — then also try the codex default
# (~/.codex): a bare `doctor.sh <project>` on a machine with ONLY a default-leaf codex install (no
# KEEL_HOME override at all) otherwise still summed a footprint of 0, since $ghome itself never
# resolves anywhere near ~/.codex (found by a second operator-run /code-review pass; the first version
# of this fix only auto-detected BETWEEN CLAUDE.md/AGENTS.md AT $ghome's own path, not across the two
# possible default homes). Kept separate from $ghome itself — used elsewhere (the --install mode's own
# gate_flag comparison) for a DIFFERENT purpose that must keep meaning "the Claude default" specifically
# — so this fallback doesn't change what THAT comparison means. With KEEL_HOME set, precedence stops
# here deliberately: it names ONE harness location the same way install.sh's own precedence does, and
# guessing past an explicit override is not this HINT's business.
footprint_home="$ghome"; footprint_context="$ghome_context"
if [ ! -f "$footprint_home/$footprint_context" ] && [ -z "${KEEL_HOME:-}" ] \
   && [ -f "${HOME:-}/.codex/AGENTS.md" ]; then
  footprint_home="${HOME:-}/.codex"; footprint_context="AGENTS.md"
fi
global_chars=0
if [ -f "$footprint_home/$footprint_context" ]; then
  global_chars="$(_char_count "$footprint_home/$footprint_context")"
  # Linked mode: the global CLAUDE.md carries one `@…/keel/CORE.md` line, and Claude Code loads that
  # target's own bytes at session start — so an honest sum must resolve it and add its size in too.
  # Copy mode (or --no-git) embeds the core's content directly inside CLAUDE.md instead (no @import
  # line), so its bytes are already counted by the read above — nothing extra to add there. AGENTS.md
  # (--codex, copy-mode only) never carries an @import line either, so this never fires for it.
  if grep -qE "$core_import_re" "$footprint_home/$footprint_context" 2>/dev/null \
     && [ -f "$footprint_home/keel/CORE.md" ]; then
    global_chars=$(( global_chars + $(_char_count "$footprint_home/keel/CORE.md") ))
  fi
fi
global_est=$(( global_chars / 4 ))

say()  { [ "$QUIET" = 1 ] || echo "$@"; }

# Findings are BUFFERED per audit unit (a project dir, or the install) and flushed ordered
# GAP → WARN → HINT (dir #45): the checks run in code order, the reader sees severity order.
# Record shape: TIER<TAB>ID<TAB>message (no message ever contains a tab). gap() sets the exit
# code at RECORD time, so a GAP fails the run even if its ID is (mistakenly) listed in the
# accept file — accepting a hard failure must not fake a green exit.
NOTES=()
n_gap=0; n_warn=0; n_hint=0; n_hidden=0
gap()  { NOTES+=("GAP	$1	$2"); exit_code=1; }
warn() { NOTES+=("WARN	$1	$2"); }
hint() { NOTES+=("HINT	$1	$2"); }

# Shared newline-framed token-set idiom (also used below by the map-drift baseline): load_token_set
# FILE prints one token per line (a bare `$(...)` — the caller frames it, since command substitution
# strips ALL trailing newlines and a naive "frame inside the function" would silently lose the closing
# frame). STRIP_COMMENTS=1 drops a trailing `# ...`; the map-drift baseline passes 0 — its file
# predates comment support and a bare `#`-led path mention there is a real (if unlikely) token, not
# an annotation, so silently swallowing it would be a behavior change, not a cleanup.
# `|| true`: an existing-but-unreadable file (permission-denied, an odd .keel/ sync state) must
# degrade to an empty set, not take down the whole run — under set -euo pipefail a failed read here
# (this isn't a `local` assignment) would kill the script mid-unit, losing every finding already
# buffered for it, the same trap the CLAUDE.md footprint read below guards against.
load_token_set() {
  local file="$1" strip_comments="${2:-0}"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  if [ "$strip_comments" = 1 ]; then sed 's/#.*//' "$file" 2>/dev/null | awk 'NF{print $1}' || true
  else cat "$file" 2>/dev/null || true
  fi
}
in_token_set() { case "$1" in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac }

# The accept set for the current unit. One ID per line; `#` starts a comment (whole-line or
# trailing); blank lines ignored.
ACCEPT_SET=$'\n'
load_accept() { ACCEPT_SET=$'\n'"$(load_token_set "${1:-}" 1)"$'\n'; }
is_accepted() { in_token_set "$ACCEPT_SET" "$1"; }

# flush_notes ACCEPT_FILE — print the unit's buffered findings in tier order and tally the global
# counters. n_gap/n_warn/n_hint count only findings still ACTIVE (unaccepted) in that tier — an
# accepted WARN/HINT is excluded from its tier's count and instead tallied once in n_hidden, unless
# --all, which prints it with an "(accepted)" suffix and DOES count it in its tier (nothing is
# hidden under --all, so there is nothing left for n_hidden to track). This is deliberately different
# from --quiet, which hides HINTs from the printed listing but leaves them counted in n_hint — quiet
# only changes what's DISPLAYED, accept changes what's ACTIVE. "doctor: 0 hint (2 accepted hidden)"
# means exactly what it says: zero unaddressed hints, two waived ones on record.
flush_notes() {
  local tier line t rest id msg suffix
  load_accept "${1:-}"
  for tier in GAP WARN HINT; do
    for line in ${NOTES[@]+"${NOTES[@]}"}; do
      t="${line%%	*}"; rest="${line#*	}"; id="${rest%%	*}"; msg="${rest#*	}"
      [ "$t" = "$tier" ] || continue
      suffix=""
      if [ "$t" != "GAP" ] && is_accepted "$id"; then
        if [ "$SHOW_ALL" = 1 ]; then suffix=" (accepted)"; else n_hidden=$((n_hidden + 1)); continue; fi
      fi
      case "$t" in
        GAP)  n_gap=$((n_gap + 1));   echo "  GAP  [$id] $msg$suffix" ;;
        WARN) n_warn=$((n_warn + 1)); echo "  WARN [$id] $msg$suffix" ;;
        HINT) n_hint=$((n_hint + 1)); [ "$QUIET" = 1 ] || echo "  HINT [$id] $msg$suffix" ;;
      esac
    done
  done
  NOTES=()
}

# The tail summary prints on EVERY run (dir #45 item 4) — quiet included: one line, and the only
# place a hidden accepted finding is still visible as a count.
finish() {
  local s="doctor: $n_gap gap, $n_warn warn, $n_hint hint"
  if [ "$n_hidden" -gt 0 ]; then s="$s ($n_hidden accepted hidden)"; fi
  echo "$s"
  exit "$exit_code"
}

# First-party find: prune build-output / vendored-dependency dirs so a dependency's sources or lint
# configs never trip a per-stack gate. find only (busybox/Alpine has no `grep --include`). Usage:
# fp_find DIR  EXPR...   e.g. fp_find "$d" -name '*.java' -print
fp_find() {
  find "$1" \( -name .git -o -name .claude -o -name target -o -name build -o -name .build \
               -o -name .gradle -o -name node_modules -o -name vendor -o -name dist -o -name out \) -prune \
            -o "${@:2}" 2>/dev/null
}

# fp_any DIR EXPR...   true iff fp_find yields ≥1 line. The result comes from the CAPTURED first line,
# never the pipeline's exit status — so a producer killed by SIGPIPE when `head` closes the pipe early
# (under `set -o pipefail`, on a large tree) can't flip a real match into a false negative. Do NOT
# rewrite this as `fp_find … | grep -q .`: that gates on the pipeline status and reintroduces the bug.
fp_any() {
  [ -n "$(fp_find "$@" | head -n1)" ]
}

# gate_hook_wired SETTINGS_JSON — true iff the /polish pre-PR gate's load-bearing hook (PreToolUse
# matcher "Bash" running pre-pr-gate.sh) is wired in SETTINGS_JSON. Shared by the --install-mode check
# (machine-global scope) and the per-project loop (project scope) below, so the two structural checks
# can never drift apart. jq gives a structural check — a bare substring grep would call it wired from
# an unrelated mention (a comment, some other value) — falling back to the grep when jq isn't on PATH
# (same fail-open posture the gate's own hook mode takes: it needs jq to function at all, so a missing
# jq means "wired but inert" either way, not a doctor false negative worth hard-failing over).
gate_hook_wired() {
  local settings="$1"
  [ -f "$settings" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e '.hooks.PreToolUse // [] | any(.matcher == "Bash" and (.hooks // [] | any(.command // "" | contains("pre-pr-gate.sh"))))' \
      "$settings" >/dev/null 2>&1
  else
    grep -q 'pre-pr-gate.sh' "$settings" 2>/dev/null
  fi
}

# gate_any_reference SETTINGS_JSON — true iff pre-pr-gate.sh is referenced ANYWHERE in SETTINGS_JSON
# (any hook, any event), not just the load-bearing one. Used to tell "never wired" (silence — the gate
# is opt-in, most projects legitimately skip it) apart from "partially wired" (a real finding — see the
# per-project loop). Without jq this collapses to the same grep as gate_hook_wired, so the "partial"
# distinction only exists when jq is available — consistent with the fail-open posture above.
gate_any_reference() {
  local settings="$1"
  [ -f "$settings" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e '[.hooks // {} | to_entries[] | .value[]? | .hooks[]? | .command // ""] | any(contains("pre-pr-gate.sh"))' \
      "$settings" >/dev/null 2>&1
  else
    grep -q 'pre-pr-gate.sh' "$settings" 2>/dev/null
  fi
}

# _expand_hookspath_tilde VALUE — a LITERAL leading `~/` a user wrote into git config, which git
# returns verbatim rather than expanding itself. Shared by every core.hooksPath read below ($global_hooks
# here, $global_hooks_eff further down) — one definition instead of two hand-copies of a git-version-
# sensitive rule (found by an independent /code-review high pass: the duplication is exactly what its
# own comment warned against).
# shellcheck disable=SC2088  # matching a LITERAL ~ a user wrote into git config (git returns it verbatim)
_expand_hookspath_tilde() {
  case "$1" in "~/"*) printf '%s' "${HOME:-}/${1#\~/}" ;; *) printf '%s' "$1" ;; esac
}
global_hooks="$(git config --global core.hooksPath 2>/dev/null || true)"
global_hooks="$(_expand_hookspath_tilde "$global_hooks")"

# dir #97: the machine-global half above resolves through whatever global git config the environment
# points at. Under a REDIRECTED one — an audit probe isolating itself, a test harness, a container — a
# guarded machine reads as unguarded, turning W-GUARD-UNWIRED, doctor's highest-stakes finding, into a
# systematic false negative; dir #85's drift audit nearly filed one as real drift. The resolution stays
# as it is: reading a global git config is read-only and cannot damage the machine, so isolation rules
# were never meant to cover it (docs/rollout-audit.md now carves that out explicitly). What is added is
# provenance — the finding names the source it was resolved through, the same way --install mode's
# findings name their $ihome.
#
# Name the source ACTUALLY consulted, not $HOME flatly. What the check above reads is `git config
# --global`, a SCOPE SELECTOR that collapses to exactly one file — verified against git 2.52:
# $GIT_CONFIG_GLOBAL when that variable is SET (even to the empty string, which silences the global
# config entirely); else ~/.gitconfig when it is READABLE (git falls through on access(R_OK), not merely
# on absence); else $XDG_CONFIG_HOME/git/config. Each of those can be redirected without touching the
# others — `GIT_CONFIG_GLOBAL=/dev/null` is a standard hermetic-CI idiom — and a note pointing at an
# unredirected ~/.gitconfig where core.hooksPath *is* set reads as a doctor bug: the very confusion this
# exists to remove, displaced one variable over. Hence set-ness (`+x`) rather than non-emptiness on BOTH
# variables, and an XDG branch narrowed to the case where that file is the one `--global` actually lands
# on. HOME UNSET is not that case — `git config --global` then fails outright ($HOME not set) whatever
# XDG_CONFIG_HOME says — but HOME set-to-EMPTY is: git builds "/.gitconfig", can't read it, and falls
# through to XDG exactly as the branch below does. That branch names the FILE, not a variable, because
# the XDG location exists whether or not XDG_CONFIG_HOME is set (unset → ~/.config/git/config, the
# ordinary case): keying it on the variable sent every default-layout machine to the `HOME=` arm and so
# pointed the reader at a ~/.gitconfig that isn't there.
# The two fall-through tests are deliberately asymmetric — `-r` for ~/.gitconfig, `-f` for the XDG file —
# because git's behaviour is: unreadable ~/.gitconfig means it moves ON to XDG (so naming HOME would name
# a file git rejected), while an unreadable XDG file has nothing after it (git warns, returns empty, and
# that file is still the last one it touched — naming it is the useful answer).
# This selector is NOT git's effective config resolution: git's own lookup merges
# $XDG_CONFIG_HOME/git/config (default ~/.config/git/config) BEHIND an existing ~/.gitconfig, so a
# hooksPath set only in the XDG file genuinely governs commits while `--global` cannot see it. The
# project audit below survives that by falling through to `git rev-parse --git-path hooks/pre-commit`,
# which does use git's own resolution — so it still finds such a guard. --install mode has no equivalent
# fallback and would report it unwired; that gap predates this note and is filed as dir #121.
#
# Unconditional on purpose. The tempting narrower trigger — "no global git config readable here" — is a
# proxy for a question that cannot be answered from inside: any sandbox that ran `git config --global
# user.email` in order to commit has one (this repo's own tests/lib.sh and examples/tour.sh both do), so
# that predicate stays silent on the commonest sandbox shape while appending an excuse to a perfectly
# correct finding on a bare real machine — wrong in both directions. Naming the source is decidable, and
# lets the reader judge. Residual: the SILENT halves of the same resolution carry no message to append
# to — W-GUARD-GLOBAL-STALE simply never runs under a redirected config, and its absence reads as
# "fresh" (dir #120).
if [ -n "${GIT_CONFIG_GLOBAL+x}" ]; then
  guard_cfg_src="GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL:-<empty>}"
elif [ -n "${HOME+x}" ] && [ ! -r "$HOME/.gitconfig" ] && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" ]; then
  guard_cfg_src="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
else
  guard_cfg_src="HOME=${HOME-<unset>}"   # `-`, not `:-`: an EMPTY HOME is set, and git did read /.gitconfig
fi
guard_home_note=" [global config read via $guard_cfg_src — a redirected one reports a guarded machine as unwired]"

# The engine THIS checkout ships — the drift reference for every installed secret-guard copy. An
# installed copy that differs runs old (or unknown) detection while looking wired; presence is not
# freshness. Machine-global is checked ONCE here (not per project — it covers the whole machine);
# per-repo vendored copies are checked inside the loop.
# BASH_SOURCE, not $0: resolves this script's real location even when invoked as `bash doctor.sh`
# from another cwd — a drift check that can't find its own reference would silently never fire.
# ABSOLUTE hooksPath only (dir #97). A RELATIVE core.hooksPath names a different directory in every
# repo, so it is not a machine-wide install and this check has no business claiming it: resolving it
# here would silently compare whatever happens to sit under doctor's own cwd, and the finding's
# remediation (`install-secret-guard.sh --global`) exits 3 refusing to clobber that very setting — a
# dead end. The per-repo loop owns that shape instead, with the fix that actually works. The two
# domains are disjoint by construction, so one drift is still never reported twice. ~/ was already
# expanded above, so a tilde spelling counts as absolute here.
tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# dir #106: sourced once here, not per-project below — the allowlist is invariant across every
# scanned project, so re-sourcing it inside the loop would just rebuild the same regex N times.
# shellcheck source=tools/lib/safe-emails.sh
. "$tools_dir/lib/safe-emails.sh"
shipped_scan="$tools_dir/secret-guard/secret-scan.sh"
case "$global_hooks" in /*) global_hooks_abs=1 ;; *) global_hooks_abs=0 ;; esac

# dir #121: `git config --global` is a SCOPE SELECTOR (see the note above $guard_cfg_src) that
# collapses to exactly ONE file — it cannot see a hooksPath set only in the XDG git config behind an
# existing ~/.gitconfig, even though git's own EFFECTIVE resolution merges that file in and every
# commit on the machine genuinely runs through it. Resolved ONCE here (not per project — same
# machine-invariant reasoning as $global_hooks itself), by reading core.hooksPath (no --global
# restriction) from a guaranteed non-repo scratch dir, so nothing at LOCAL scope — a repo doctor
# happens to be invoked from — can leak into what must be a machine-wide read (verified against git
# 2.52 in the same session as dir #97). Shared by the machine-wide staleness check right below, the
# dir #120 disclosure in its elif, and --install mode's own secret-guard section further down — all
# three are the same question ("what does this machine's effective config say"), asked three times;
# one probe, one variable, answered once. `-d`-gated: if the probe dir turns out to sit inside a real
# repo (an odd TMPDIR), fall back to $global_hooks rather than risk reading THAT repo's local scope —
# disclosed when it happens (found by an independent /code-review high pass: a silent fallback here
# would reintroduce dir #121's own false negative, invisibly, on exactly the machines it exists to fix).
global_hooks_eff="$global_hooks"; global_hooks_eff_abs="$global_hooks_abs"; global_hooks_eff_degraded=0
ieff_probe="$(mktemp -d 2>/dev/null || true)"
if [ -n "$ieff_probe" ] && ! git -C "$ieff_probe" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  global_hooks_eff="$(_expand_hookspath_tilde "$(git -C "$ieff_probe" config core.hooksPath 2>/dev/null || true)")"
  case "$global_hooks_eff" in /*) global_hooks_eff_abs=1 ;; *) global_hooks_eff_abs=0 ;; esac
else
  global_hooks_eff_degraded=1
fi
[ -n "$ieff_probe" ] && rmdir "$ieff_probe" 2>/dev/null
if [ "$global_hooks_eff_degraded" = 1 ]; then
  say "  (effective core.hooksPath probe unavailable this run — falling back to the narrower --global-only read; a hooksPath set only behind an existing ~/.gitconfig would go undetected)"
fi

# guard_eff_note — the $guard_home_note-style provenance clause, but honest about WHICH resolution
# actually produced a value that differs from what a plain `git config --global` read would give:
# $guard_cfg_src (and $guard_home_note, built from it) name the ONE file `--global` collapses to, but
# $global_hooks_eff can additionally merge in $XDG_CONFIG_HOME/git/config behind an existing
# ~/.gitconfig — attaching $guard_home_note's file-specific claim to a value that came from THAT merge
# names a file that was never the one actually consulted (found by an independent /code-review high
# pass, reproduced for the XDG-behind-~/.gitconfig case). Falls back to $guard_home_note verbatim
# whenever the two resolutions agree (the common case) or the probe degraded above (nothing more
# precise to say than the --global-selector note already gives).
guard_eff_note="$guard_home_note"
if [ "$global_hooks_eff_degraded" = 0 ] \
   && { [ "$global_hooks_eff" != "$global_hooks" ] || [ "$global_hooks_eff_abs" != "$global_hooks_abs" ]; }; then
  guard_eff_note=" [resolved via git's effective config, which additionally merges \$XDG_CONFIG_HOME/git/config behind an existing ~/.gitconfig — narrower than that, a plain \`git config --global\` read would have missed this]"
fi

if [ "$global_hooks_eff_abs" = 1 ] && [ -f "$global_hooks_eff/secret-scan.sh" ] && [ -f "$shipped_scan" ] \
   && ! cmp -s "$global_hooks_eff/secret-scan.sh" "$shipped_scan"; then
  warn W-GUARD-GLOBAL-STALE "machine-global secret-guard ($global_hooks_eff/secret-scan.sh) differs from the engine this Keel checkout ships — an older install, or a stale checkout; update the repo, then re-run install-secret-guard.sh --global (or re-copy the hooks)"
elif [ -z "$global_hooks_eff" ]; then
  # dir #120: the drift check above is GATED on core.hooksPath resolving to anything at all, so with
  # nothing configured (redirected OR genuinely bare — doctor cannot tell those apart) it never runs,
  # and its absence would otherwise read as "the machine-global guard is fresh" (residual noted in dir
  # #97's own comment above $guard_home_note). Unlike a WARN/GAP this has no message of its own to
  # append the provenance clause to, so disclose here instead — same source, same wording family as
  # $guard_home_note.
  say "  (machine-global secret-guard staleness check: no core.hooksPath resolved via $guard_cfg_src — a redirected config looks identical to a genuinely bare machine)"
fi
# This machine-wide finding belongs to no audit unit — flush it now, against the accept file of the
# repo the CWD sits in (so `cd project && keel doctor …` can still accept it there). Deliberately NOT
# $ihome/.keel/doctor-accept even under --install: this check runs before the --install branch below,
# and the finding is about the MACHINE's global guard, not the install at $ihome — the two can differ
# (e.g. auditing a --install HOME while sitting in an unrelated repo). An --install run that wants to
# accept this specific finding does so via the CWD's accept file, same as any other invocation.
#
# Resolved to the MAIN checkout, same fallback chain as unit_top below — NOT the raw CWD toplevel: a
# CWD sitting inside a linked worktree would otherwise point this at the worktree's own .keel/, which
# is exactly the split-brain condition W-KEEL-SPLIT flags (an accept file only that worktree ever sees).
cwd_d_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
cwd_main_top="$(git worktree list --porcelain 2>/dev/null \
  | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
flush_notes "${cwd_main_top:-${cwd_d_top:-.}}/.keel/doctor-accept"

# --install: audit the INSTALL itself (wired-vs-shipped completeness), not a project. The linked-mode
# contract this closes: `git pull` refreshes CONTENT, never COMPOSITION — a release that ADDS a command
# wires itself nowhere, and only this check notices. Also the reverse of the liveness check: dead
# symlinks/imports (a moved or deleted checkout) are HARD failures, missing commands are advisory
# (declining a command is a legitimate choice).
if [ "$INSTALL_MODE" = 1 ]; then
  # Reject nonsense combinations up front: the registry fills DIRS with PROJECT paths, and install
  # mode reads DIRS[0] as the harness HOME — composing them would audit a random project as a home.
  if [ -n "$REGISTRY" ]; then
    echo "doctor: --install and --registry don't combine (audit the install and the projects separately)" >&2; exit 2
  fi
  if [ "${#DIRS[@]}" -gt 1 ]; then
    echo "doctor: --install takes at most one HOME dir" >&2; exit 2
  fi
  # Mode is EXPLICIT (--codex), never auto-detected — same reason uninstall.sh's dir #109 flag is
  # explicit: a home holding BOTH context files (dir #124's shape) has no content-based answer, and
  # auto-detecting on "which file happens to be there" is exactly what produced the false GAP this
  # ticket closes (a codex-only home has no CLAUDE.md at all, so guessing from CLAUDE.md's absence
  # alone can't tell "not installed" from "installed the other mode").
  if [ "$CODEX_MODE" = 1 ]; then idefault_leaf=".codex"; iother_leaf=".claude"; icontext="AGENTS.md"; imode_flag=" --codex"; iother_context="CLAUDE.md"
  else                            idefault_leaf=".claude"; iother_leaf=".codex"; icontext="CLAUDE.md"; imode_flag="";        iother_context="AGENTS.md"
  fi
  ihome="${DIRS[0]:-${KEEL_HOME:-${HOME:?doctor --install: pass a HOME dir, or set HOME/KEEL_HOME}/$idefault_leaf}}"
  # ihome_flag — the ` --home "DIR"` every command this mode ADVISES must carry when $ihome is not
  # where a bare re-run would land. Same rule, and the same reason, as install.sh's home_flag: an
  # instruction that re-resolves the home from scratch cannot fix the install this audit is about, so
  # the finding would never clear however faithfully it was followed (dir #98, found to be a class).
  # Compared against THIS mode's own default (not $ghome unconditionally, which is always the Claude
  # default) — a bare `doctor.sh --install --codex` at the default ~/.codex must get the short, friendly
  # advice too, the same way a bare `doctor.sh --install` does at ~/.claude. $idefault_leaf already
  # encodes which mode this is, so one formula covers both — no branch needed here.
  idefault="${KEEL_HOME:-${HOME:-}/$idefault_leaf}"
  if [ "$ihome" = "$idefault" ]; then ihome_flag=""
  else                                 ihome_flag=" --home \"$ihome\""; fi
  # iother_home_flag — the SAME home-reaching suffix, but computed against the OTHER mode's default
  # (via $iother_leaf, the mirror of $idefault_leaf), for the one advice site (the mode-mismatch
  # redirect below) that recommends switching modes. Using plain $ihome_flag there was a real bug
  # (operator-run /code-review, step 5 of /polish): $ihome_flag is relative to THIS mode's default, so
  # on a home placed at the OTHER mode's default leaf via an explicit `--home` (e.g. a Claude-mode
  # install put at ~/.codex with `install.sh --home ~/.codex`), $ihome_flag comes out empty even though
  # the redirect's advised command switches modes and therefore needs an explicit --home to still reach
  # $ihome — reproducing exactly the dir #98 class this file's own ihome_flag comment says it closes,
  # just for the redirect branch specifically.
  iother_default="${KEEL_HOME:-${HOME:-}/$iother_leaf}"
  if [ "$ihome" = "$iother_default" ]; then iother_home_flag=""
  else                                        iother_home_flag=" --home \"$ihome\""; fi
  # irelink_mode — the re-wiring MODE for a dangling/foreign symlink (bin/keel is wired in BOTH modes,
  # so this is reachable under --codex too, code-review found live): under Claude mode that's `--link`
  # (recreates the linked layout); under --codex it's just $imode_flag itself, a bare re-run of --codex
  # (copy mode has no --link equivalent, and `install.sh --codex --link` is a hard usage error) — never
  # `--link`, which would wire a full second, Claude-mode install into the same codex home. $imode_flag
  # is non-empty exactly when CODEX_MODE=1, so `${imode_flag:- --link}` picks it out without a branch:
  # falls to the literal `--link` default only when $imode_flag is empty (non-codex). Kept as ITS OWN
  # variable rather than folded into $ihome_flag (appended at each print site below) so
  # tools/self/doctor.sh's check 1c — which greps advice lines for the LITERAL substring `ihome_flag`,
  # not just its expanded value — still recognizes these as home-aware (dir #98).
  irelink_mode="${imode_flag:- --link}"
  repo_root="$(cd "$tools_dir/.." && pwd)"
  say "● keel install ($ihome)"
  if [ ! -d "$ihome" ]; then
    gap G-INSTALL-MISSING "no install found at $ihome (run install.sh$imode_flag$ihome_flag)"
    flush_notes ""
    finish
  fi

  # Liveness: every symlink Keel wires must resolve — including a hand-migrated top-level
  # FRAMEWORK/PRINCIPLES layout. ([ -L ] skips the literal glob when a dir is empty.) A link that
  # RESOLVES but into a different checkout than this one looks healthy while running stale content —
  # -ef (same physical file) catches that; advisory, since a second checkout can be deliberate.
  for l in "$ihome"/*.md "$ihome/keel"/* "$ihome/commands"/* "$ihome/bin"/*; do
    [ -L "$l" ] || continue
    # this_relink — the re-wiring mode that can actually restore THIS SPECIFIC slot (found by a second
    # independent code-review pass): bin/keel is the ONLY slot wired in BOTH modes, so $irelink_mode's
    # --codex-awareness only makes sense there. Every other slot (commands/*, keel/*, top-level
    # FRAMEWORK/PRINCIPLES) is Claude/linked-mode-only by construction — `install.sh --codex` never
    # creates any of them — so one dangling under a --codex audit is a leftover from an UNRELATED
    # Claude-mode install sharing this home (dir #124's shape), not something a --codex re-run could
    # ever fix; it keeps advising `--link` unconditionally, same as before --codex existed.
    if [ "$l" = "$ihome/bin/keel" ]; then this_relink="$irelink_mode"
    else                                    this_relink=" --link"
    fi
    if [ ! -e "$l" ]; then
      gap G-LINK-DANGLING "dangling symlink: $l → $(readlink "$l") (checkout moved/deleted? re-run install.sh$this_relink$ihome_flag from its home)"
      continue
    fi
    b="$(basename "$l")"
    case "$l" in
      "$ihome/commands/"*)
        tgt="$repo_root/commands/${b#keel-}"
        if [ -f "$repo_root/commands/$b" ]; then tgt="$repo_root/commands/$b"; fi ;;
      "$ihome/bin/keel")
        tgt="$repo_root/keel" ;;
      "$ihome/keel/"*)
        tgt="$repo_root/$b" ;;
      *)
        # top level: only FRAMEWORK/PRINCIPLES are ever Keel-wired there (a hand-migrated layout);
        # CLAUDE/INSTANCE/LEARNINGS are user-owned — a dotfiles symlink is their business, not drift.
        case "$b" in FRAMEWORK.md|PRINCIPLES.md) tgt="$repo_root/$b" ;; *) tgt="" ;; esac ;;
    esac
    if [ -n "$tgt" ] && [ -f "$tgt" ] && [ ! "$l" -ef "$tgt" ]; then
      warn W-LINK-FOREIGN "$b resolves outside this checkout (an older keel clone?) — it will not refresh when THIS checkout pulls; re-run install.sh$this_relink$ihome_flag from here if this is the live one"
    fi
  done

  # Always-on rails: delivered by the @import line (linked) or the embedded block (copy mode).
  # (Trichotomy parallel to install.sh's linked-mode Verify — keep in sync. Severities differ on
  # purpose: an embedded block is legitimate copy mode here, an un-migrated WARN there.)
  gclaude="$ihome/$icontext"
  if [ ! -f "$gclaude" ]; then
    # dir #134: before falling to the generic "not installed" advice, check whether the OTHER mode's
    # context file is sitting right there — the exact shape of the false GAP this ticket closes. The
    # generic advice ("run install.sh$imode_flag$ihome_flag") is safe on a genuinely empty/foreign dir,
    # but on an other-mode home it would wire the missing context file ALONGSIDE the one already there,
    # producing dir #124's both-modes-in-one-home rather than fixing anything — so redirect to the
    # correctly-moded re-run instead. is_accepted() flow untouched: this still records a real GAP (the
    # mode this audit was asked about genuinely isn't installed here), just with advice that leads
    # somewhere useful.
    if [ -f "$ihome/$iother_context" ]; then
      # Stop here, the same way the "no install found" branch above does (flush + finish): every check
      # below this point is written for THIS mode and would cascade wrong-mode noise on top of the one
      # real finding (dir #134 code-review: W-CMDS-MISSING's own "re-run install.sh$ihome_flag" advice
      # is exactly as dangerous as this GAP's used to be, and it fires unless the audit stops here).
      if [ "$CODEX_MODE" = 1 ]; then
        gap G-RAILS-MISSING "no $icontext at $ihome — but $iother_context is there: this looks like a Claude Code install, not --codex. Re-run without --codex: doctor.sh --install$iother_home_flag (running install.sh$imode_flag$ihome_flag here would create a second mode in the same home)"
      else
        gap G-RAILS-MISSING "no $icontext at $ihome — but $iother_context is there: this looks like a --codex install. Re-run: doctor.sh --install --codex$iother_home_flag (running install.sh$imode_flag$ihome_flag here would create a second mode in the same home)"
      fi
      flush_notes "$ihome/.keel/doctor-accept"
      finish
    else
      gap G-RAILS-MISSING "no global $icontext at $ihome — the always-on rails are not wired (run install.sh$imode_flag$ihome_flag)"
    fi
  elif grep -qE "$core_import_re" "$gclaude"; then
    if [ ! -f "$ihome/keel/CORE.md" ]; then
      gap G-RAILS-IMPORT-BROKEN "$icontext imports keel/CORE.md but the target does not resolve (re-run install.sh$irelink_mode$ihome_flag)"
    elif grep -q 'KEEL-CORE-BEGIN' "$gclaude"; then
      warn W-RAILS-DOUBLE "$icontext imports the core AND still embeds a KEEL-CORE block — the rails load twice each session; remove the block (or the import line)"
    elif [ ! -L "$ihome/keel/CORE.md" ] && grep -q 'KEEL-NOGIT' "$ihome/keel/CORE.md"; then
      # A --no-git install: keel/CORE.md is a GENERATED trimmed copy, not a symlink — `git pull`
      # refreshes the checkout but never this file. Two risks only this check notices:
      #   staleness — the copy was generated from an older CORE.md. Compare crumb-insensitively
      #   (drop the KEEL-NOGIT-BEGIN..END breadcrumb from the installed side, the KEEL-GIT blocks
      #   from the shipped side): the breadcrumb wording may legitimately change across releases,
      #   the rails content must not. (Mirror of install.sh's strip_git_blocks — keep in sync.)
      #   git evidence — a registered project lives in git while the always-on git rails are absent:
      #   exactly the user the rails exist for, in the window where they're missing.
      ref_trim="$(awk '/KEEL-GIT-BEGIN/{skip=1;next} /KEEL-GIT-END/{skip=0;next} !skip' "$repo_root/CORE.md")"
      inst_trim="$(sed '/KEEL-NOGIT-BEGIN/,/KEEL-NOGIT-END/d' "$ihome/keel/CORE.md")"
      if [ "$ref_trim" = "$inst_trim" ]; then
        say "  OK   core rails: linked, trimmed (--no-git — code/git rails not installed)"
      else
        warn W-NOGIT-STALE "trimmed (--no-git) core is stale against this checkout's CORE.md — re-run install.sh$irelink_mode$ihome_flag (a re-run keeps the trim and refreshes it)"
      fi
      git_projects=0
      if [ -f "$ihome/INSTANCE.md" ]; then
        # Path column of the INSTANCE.md Projects table — same parse as --registry above; keep in sync.
        while IFS='|' read -r _lead _col1 col_path _rest; do
          p="$(printf '%s' "$col_path" | tr -d '`' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          case "$p" in ""|Path|*"<"*) continue ;; esac
          p="${p/#\~/${HOME:-}}"
          if [ -e "$p/.git" ]; then git_projects=$((git_projects + 1)); fi
        done < <(awk 'BEGIN{f=0} /^[[:space:]]*(```|~~~)/{f=!f;next} !f' "$ihome/INSTANCE.md" \
                  | grep -E '^[[:space:]]*\|' | grep -vE '^[[:space:]]*\|[-:| ]+\|?[[:space:]]*$')
      fi
      if [ "$git_projects" -gt 0 ]; then
        warn W-NOGIT-GIT-PROJECTS "core is trimmed (--no-git) but $git_projects registered project(s) live in git — the always-on git safety rails are NOT loaded; restore them before git work: install.sh$irelink_mode$ihome_flag --with-git"
      fi
    elif [ ! -L "$ihome/keel/CORE.md" ]; then
      warn W-CORE-UNLINKED "keel/CORE.md is a regular file without the KEEL-NOGIT marker — not a live link into the checkout (it won't refresh on git pull); re-run install.sh$irelink_mode$ihome_flag"
    else
      say "  OK   core rails: linked (@import → keel/CORE.md)"
    fi
  elif grep -q 'KEEL-CORE-BEGIN' "$gclaude"; then
    say "  OK   core rails: embedded copy (copy mode; a re-run checks for drift)"
  else
    warn W-RAILS-UNWIRED "$icontext carries neither the @import line nor the embedded KEEL-CORE block — the rails are not wired (re-run install.sh$imode_flag$ihome_flag$([ "$CODEX_MODE" = 1 ] || echo ", or migrate: install.sh --link"))"
  fi

  # On-demand tier reachable in either layout — and not shadowed: a root COPY beside a linked
  # keel/ version is a stale shadow (a leftover of the copy→linked migration) that a map still
  # pointing at the root name would silently keep reading.
  for f in FRAMEWORK.md PRINCIPLES.md; do
    if [ ! -f "$ihome/keel/$f" ] && [ ! -f "$ihome/$f" ]; then
      warn W-TIER-MISSING "$f is reachable neither at keel/$f nor at $f — the on-demand tier is missing (re-run install.sh$imode_flag$ihome_flag)"
    elif [ -f "$ihome/keel/$f" ] && [ -e "$ihome/$f" ] && [ ! -L "$ihome/$f" ]; then
      warn W-TIER-SHADOW "$f exists both at keel/$f (linked, fresh) and as a root copy (stale shadow) — re-point your $icontext map at keel/$f, then remove the copy"
    fi
  done

  # Commands: X of Y shipped are wired (under their own name, or as a keel-<name> collision alias).
  # dir #134: install.sh --codex never wires commands/ at all — it's a Claude-format dir a codex home
  # never reads (Codex's own skills live at ~/.codex/skills/<name>/SKILL.md instead, per ADAPTING.md) —
  # so counting "0 of N wired" here would be a permanent, un-clearable W-CMDS-MISSING on every healthy
  # codex install, not a real gap.
  if [ "$CODEX_MODE" = 1 ]; then
    say "  =    commands: not applicable under --codex (Codex reads skills, not commands — see ADAPTING.md)"
  else
    wired=0; total=0; missing_cmds=""
    for cmd in "$repo_root"/commands/*.md; do
      [ -f "$cmd" ] || continue
      cname="$(basename "$cmd")"
      total=$((total + 1))
      if [ -f "$ihome/commands/$cname" ] || [ -f "$ihome/commands/keel-$cname" ]; then
        wired=$((wired + 1))
      else
        missing_cmds="$missing_cmds $cname"
      fi
    done
    if [ "$wired" = "$total" ]; then
      say "  OK   commands: $wired of $total shipped are wired"
    else
      warn W-CMDS-MISSING "commands: only $wired of $total shipped are wired — missing:$missing_cmds (a pull refreshes content, not composition: re-run install.sh$ihome_flag; or ignore this if declined deliberately)"
    fi
  fi

  # The keel CLI: install wires bin/keel as a symlink into the checkout. Only flag it when this
  # checkout actually ships a `keel` (older checkouts predate it) — and a resolved-but-foreign link
  # is the same stale-clone smell as the command links above (advisory, a second checkout can be
  # deliberate). Missing entirely is advisory too: the CLI is a convenience, not a rail.
  if [ -f "$repo_root/keel" ]; then
    kl="$ihome/bin/keel"
    if [ -L "$kl" ] && [ -e "$kl" ]; then
      if [ "$kl" -ef "$repo_root/keel" ]; then
        say "  OK   keel CLI: wired ($kl)"
      else
        warn W-CLI-FOREIGN "keel CLI ($kl) resolves outside this checkout (an older keel clone?) — re-run install.sh$imode_flag$ihome_flag from here if this is the live one"
      fi
    else
      warn W-CLI-UNWIRED "keel CLI not wired at $ihome/bin/keel — re-run install.sh$imode_flag$ihome_flag (or add an alias by hand)"
    fi
  fi

  # Install manifest (dir #125): read-only here — doctor only reports on it, never acts on it. Both
  # findings below are advisory. A missing (or corrupt/unversioned, same versioning contract: an
  # unknown/unparsable manifest is treated as absent, never a crash) manifest just means this audit
  # can't run the layout/home drift checks below install.sh$imode_flag$ihome_flag would let it
  # (dir #150 removed the pre-manifest heuristic that used to stand in). A present, well-formed
  # manifest that CONTRADICTS the filesystem names both sides rather than trusting either —
  # install.sh's own $manifest_mode/$manifest_layout naming, mirrored here.
  imanifest_mode="claude"; [ "$CODEX_MODE" = 1 ] && imanifest_mode="codex"
  imanifest="$ihome/.keel/install-manifest.$imanifest_mode"
  if [ ! -f "$imanifest" ]; then
    warn W-MANIFEST-MISSING "no install manifest recorded at $imanifest — this install predates Keel's install manifest or hasn't been re-run since; record one: install.sh$imode_flag$ihome_flag"
  else
    iman_version="$(manifest_field "$imanifest" keel_manifest_version)"
    if [ "$iman_version" != "1" ]; then
      warn W-MANIFEST-MISSING "install manifest at $imanifest has an unreadable or unsupported keel_manifest_version ('${iman_version:-none}') — treated as absent, same as no manifest; re-run install.sh$imode_flag$ihome_flag to record a fresh one"
    else
      iman_layout="$(manifest_field "$imanifest" layout)"
      iman_home="$(manifest_field "$imanifest" home)"
      iman_drift=""
      case "$iman_layout" in
        link)
          if [ -e "$ihome/keel/CORE.md" ] && [ ! -L "$ihome/keel/CORE.md" ]; then
            iman_drift="manifest says layout=link but $ihome/keel/CORE.md is a regular file, not a symlink"
          fi ;;
        link-nogit)
          if [ -L "$ihome/keel/CORE.md" ]; then
            iman_drift="manifest says layout=link-nogit but $ihome/keel/CORE.md is a symlink (the --no-git trim looks restored)"
          fi ;;
      esac
      # Canonicalize $ihome for this ONE comparison only (never reassign the shared $ihome — every
      # other advice line in this mode still names the home the way the operator typed it): the
      # manifest's own home= is always resolved absolute (install.sh's home_resolved), so a
      # cosmetic difference — a trailing slash, a relative path — would otherwise false-fire this
      # WARN on a perfectly healthy install (found by an independent /code-review high pass).
      ihome_canon="$(cd "$ihome" 2>/dev/null && pwd || printf '%s' "$ihome")"
      if [ -z "$iman_drift" ] && [ -n "$iman_home" ] && [ "$iman_home" != "$ihome_canon" ]; then
        iman_drift="manifest recorded home=$iman_home, but this audit is auditing $ihome"
      fi
      if [ -n "$iman_drift" ]; then
        warn W-MANIFEST-DRIFT "$iman_drift — re-run install.sh$imode_flag$ihome_flag to refresh the manifest, or uninstall first if the layout changed on purpose: keel uninstall$imode_flag$ihome_flag"
      fi
    fi
  fi

  # dir #68 pairing check: /polish ships unconditionally now, but its gate is a separate, opt-in step
  # (a hook changes what a session can do without asking each time, so install.sh never auto-wires it) —
  # flag the shipped-but-inert state instead of letting an adopter discover it only when gh pr create
  # doesn't unlock. This mode only sees the INSTALL's own machine-global settings.json; project-scope
  # wiring (tools/install-pre-pr-gate.sh <repo>, the documented default) lives in each project's own
  # .claude/settings.json and is invisible from here — expected, not a gap, so the message says so.
  if [ -f "$ihome/commands/polish.md" ] || [ -L "$ihome/commands/polish.md" ]; then
    # The advised flag must be able to reach the home this finding just NAMED, so the test is
    # literally "does --global resolve to $ihome" — i.e. compare against $ghome (the same
    # ${KEEL_HOME:-$HOME/.claude} expression install-pre-pr-gate.sh's own --global evaluates,
    # resolved once near the top of this file). Comparing against $HOME/.claude alone is the same
    # defect mirrored: with KEEL_HOME set elsewhere and doctor pointed at $HOME/.claude, --global
    # would wire $KEEL_HOME and the warning would never clear (reproduced by the operator's fifth
    # /code-review pass). install.sh --home retargets WITHOUT exporting KEEL_HOME — dir #98's whole
    # premise — so both halves of this really happen. Computed up front now (dir #125): more than one
    # branch below names it.
    if [ "$ihome" = "$ghome" ]; then gate_flag="--global"; else gate_flag="--home \"$ihome\""; fi

    # dir #125: agree with the gate manifest instead of assuming $ihome/settings.json. A usable
    # manifest's own settings= is ground truth from the wire itself (mirrors uninstall.sh's
    # gate_hooks_hint, dir #136) — for a global/home install the two always name the same file today,
    # but resolving through the manifest catches a future retargeting bug the same way W-MANIFEST-DRIFT
    # catches one for the install manifest, instead of silently trusting a re-derived guess.
    igate_manifest="$ihome/.keel/install-manifest.gate"
    igate_manifest_usable=0
    if [ -f "$igate_manifest" ] && [ "$(manifest_field "$igate_manifest" keel_manifest_version)" = "1" ]; then
      igate_manifest_usable=1
      igate_settings="$(manifest_field "$igate_manifest" settings)"
      [ -n "$igate_settings" ] || igate_settings="$ihome/settings.json"
    else
      # dir #150 audit (kept, not a no-manifest heuristic): without a usable manifest there is still
      # only one possible settings path for a global/home-scope gate install — install-pre-pr-gate.sh
      # itself always writes to exactly $ihome/settings.json for this scope (never project scope, which
      # this loop doesn't reach — see the pairing-check comment above). Nothing here is guessed among
      # several candidates the way the removed pre-manifest fallbacks in uninstall.sh/install.sh were.
      igate_settings="$ihome/settings.json"
    fi

    # The load-bearing hook is PreToolUse/Bash (it's the one that actually blocks gh pr create); the
    # other 5 (SessionStart/PostToolUse x2/UserPromptExpansion/SubagentStop — the newest, PostToolUse's
    # AskUserQuestion matcher, added dir #88) are enhancements. gate_hook_wired (shared with the
    # per-project loop's own half of this check, below) does the structural jq-else-grep test.
    if gate_hook_wired "$igate_settings"; then
      if [ "$igate_manifest_usable" = 1 ]; then
        say "  OK   /polish gate: wired machine-global ($igate_settings; manifest confirms)"
      else
        say "  OK   /polish gate: wired machine-global ($igate_settings)"
        warn W-GATE-MANIFEST-MISSING "gate hooks are wired at $igate_settings but no gate manifest is recorded — re-run install-pre-pr-gate.sh $gate_flag to record one (the B2 ledger-based dialog-arming check in tools/pre-pr-gate.sh relies on it for a retargeted --home)"
      fi
    elif [ "$igate_manifest_usable" = 1 ]; then
      # A DISTINCT id from the install-manifest drift check above (W-MANIFEST-DRIFT), not a reuse: found
      # by an operator-run /code-review high pass — .keel/doctor-accept matches by bare id, so an
      # adopter who accepted the install-manifest drift finding once (a deliberate re-home, say) would
      # silently swallow this unrelated gate-manifest drift too, collapsing "hooks removed by hand" into
      # the same anonymous accepted-hidden count. Paired with W-GATE-MANIFEST-MISSING above.
      warn W-GATE-MANIFEST-DRIFT "gate manifest at $igate_manifest recorded settings=$igate_settings, but no load-bearing hook is present there — hooks removed by hand? re-run install-pre-pr-gate.sh $gate_flag to rewire, or remove the stale manifest if this was deliberate"
    else
      warn W-GATE-UNWIRED "commands/polish.md is shipped but no machine-global gate is wired at $igate_settings — expected if you wired it per-project instead (tools/install-pre-pr-gate.sh <repo>, the default); run $gate_flag there for every repo, or confirm project scope with tools/doctor.sh <repo> instead (look for its own '/polish gate: wired' OK line)"
    fi
  fi

  # Secret-guard: machine-global wiring (per-repo vendoring is checked by the project audit).
  # Absolute hooksPath only, same ownership split as the drift check above: this mode audits the MACHINE
  # and has no repo to resolve against, so testing a relative path here would answer from whatever
  # happens to sit under doctor's own cwd — the verdict then flips between "OK machine-global" and
  # W-GUARD-UNWIRED depending on where the operator stood, on one unchanged machine (reproduced). A
  # relative core.hooksPath names a different dir in every repo and is not a machine-global install at
  # all; the project audit is where it can be judged.
  #
  # dir #121: `$global_hooks_eff`/`$global_hooks_eff_abs` (resolved once, machine-wide, above — same
  # values the top-level W-GUARD-GLOBAL-STALE staleness check now uses) already close the gap this mode
  # used to have on its own: `git config --global` cannot see a hooksPath set only in the XDG git config
  # behind an existing ~/.gitconfig, even though it genuinely governs every commit on the machine. The
  # per-project loop below survives that a different way (falling through to `git rev-parse --git-path
  # hooks/pre-commit`, git's own resolution, when nothing at repo/global scope explains the guard) —
  # --install mode has no repo to run that from, so it shares the machine-wide probe instead.
  if [ "$global_hooks_eff_abs" = 1 ] && [ -x "$global_hooks_eff/pre-commit" ]; then
    say "  OK   secret-guard: machine-global ($global_hooks_eff)"
  elif [ "$global_hooks_eff_abs" = 0 ] && [ -n "$global_hooks_eff" ]; then
    warn W-GUARD-UNWIRED "secret-guard is not wired machine-global: core.hooksPath is set to the RELATIVE path '$global_hooks_eff', which names a different directory in every repo — that is per-repo wiring, not a machine-global install (install-secret-guard.sh --global for a machine-wide one; tools/doctor.sh <repo> judges the relative one)$guard_eff_note"
  elif [ -n "$global_hooks_eff" ]; then
    # A DIFFERENT shape from the else below: core.hooksPath is set, it just points somewhere with no
    # executable pre-commit. Say that, rather than the generic "not wired" — the two need different
    # fixes (dir #97, operator's own /code-review pass). The provenance clause still rides along: a
    # successful read proves *a* config was read, not the RIGHT one, and a redirected GIT_CONFIG_GLOBAL
    # whose config points at a hookless dir lands exactly here while the real machine is guarded — the
    # systematic false negative this whole clause exists to signal. The project-scope half below now
    # names the same shape in its own branch (it used to swallow it as "covered by global").
    warn W-GUARD-UNWIRED "secret-guard is not wired machine-global: core.hooksPath is set to $global_hooks_eff but that dir carries no executable pre-commit (install-secret-guard.sh --global; or vendor per repo)$guard_eff_note"
  else
    warn W-GUARD-UNWIRED "secret-guard is not wired machine-global (install-secret-guard.sh --global; or vendor per repo)$guard_eff_note"
  fi

  flush_notes "$ihome/.keel/doctor-accept"
  if [ "$exit_code" = 0 ]; then say "doctor: install is complete — everything shipped is wired or declined"; fi
  finish
fi

for d in "${DIRS[@]}"; do
  name="$(basename "$(cd "$d" 2>/dev/null && pwd || echo "$d")")"
  say "● $name ($d)"

  if [ ! -d "$d" ]; then gap G-DIR-MISSING "directory not found"; flush_notes ""; continue; fi

  if ! git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gap G-GIT-MISSING "not a git repo (git init + a feature-branch flow — see FRAMEWORK.md)"
  fi

  if [ ! -f "$d/CLAUDE.md" ]; then
    if git -C "$d" check-ignore -q CLAUDE.md 2>/dev/null; then
      # CLAUDE.md is gitignored (a private-fork or a "mechanism" repo like Keel itself), so a fresh
      # clone legitimately has none — advise, don't fail.
      warn W-CLAUDEMD-GITIGNORED "no project CLAUDE.md in this checkout — it's gitignored (private/mechanism repo); create it locally"
    else
      gap G-CLAUDEMD-MISSING "no project CLAUDE.md (copy templates/project-CLAUDE.md, or run init-project)"
    fi
  else
    # _char_count degrades to 0 on an unreadable file instead of aborting under set -e (dir #45):
    # findings are buffered until this unit's flush_notes, so a read failure here must not take down
    # anything already recorded for this unit — including a GAP — before it ever prints.
    proj_est=$(( $(_char_count "$d/CLAUDE.md") / 4 ))
    est=$(( proj_est + global_est ))
    if [ "$est" -gt "$WARN_TOKENS" ]; then
      hint H-FOOTPRINT "session startup footprint ~${est} tokens (project ~${proj_est} + global ~${global_est}) > budget ${WARN_TOKENS} — move project detail to the on-demand tier (P2/P3)"
    fi
  fi

  gi="$d/.gitignore"
  claude_tracked=0
  git -C "$d" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1 && claude_tracked=1
  if [ -f "$gi" ] && grep -qE '(^|/)(\.claude/?|CLAUDE\.md)' "$gi"; then
    :  # private AI context ignored — good
  elif [ -f "$d/CLAUDE.md" ] && [ "$claude_tracked" = 1 ]; then
    say "       (CLAUDE.md is tracked — treating as a deliberate public fork; ensure no secrets/PII)"
  else
    gap G-GITIGNORE-CONTEXT ".gitignore does not ignore the private AI context (.claude/ or CLAUDE.md)"
  fi

  # AGENTS.md — the vendor sibling of CLAUDE.md for Codex/Cursor (dir #75). It takes its CLAUDE.md's git
  # status (status inheritance, not a fixed status): the check only fires when AGENTS.md actually exists
  # (its absence is advice ADAPTING.md gives, not a nag — same philosophy as the .keel/ checks).
  if [ -e "$d/AGENTS.md" ] || [ -L "$d/AGENTS.md" ]; then
    agents_tracked=0
    git -C "$d" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1 && agents_tracked=1
    agents_ignored=0
    git -C "$d" check-ignore -q AGENTS.md 2>/dev/null && agents_ignored=1

    if [ "$agents_ignored" = 0 ] && [ "$agents_tracked" = 0 ]; then
      gap G-AGENTSMD-CONTEXT ".gitignore does not ignore AGENTS.md (vendor sibling of CLAUDE.md — private AI context)"
    elif [ -f "$d/CLAUDE.md" ]; then
      if [ "$agents_tracked" != "$claude_tracked" ]; then
        gap G-AGENTSMD-INHERIT "AGENTS.md's tracked/ignored status does not match CLAUDE.md's — it should always inherit CLAUDE.md's git status"
      elif [ "$agents_tracked" = 1 ]; then
        say "       (AGENTS.md is tracked — treating as a deliberate public fork; ensure no secrets/PII)"
      fi
    fi

    # Drift check: for a SYMLINK, verify it actually points at CLAUDE.md — a symlink to something
    # else entirely (wrong copy-paste, stale backup) can't "drift" by content-compare, but it's just
    # as wrong, so check the target name instead. For a REGULAR-FILE copy, compare content —
    # skipped if either side isn't readable (a permission-denied CLAUDE.md would otherwise make
    # `cmp`'s read-error exit look identical to a real content diff).
    if [ -L "$d/AGENTS.md" ]; then
      agents_target="$(readlink "$d/AGENTS.md")"
      if [ "$agents_target" != "CLAUDE.md" ]; then
        warn W-AGENTSMD-DRIFT "AGENTS.md is a symlink but does not point at CLAUDE.md (points at '$agents_target') — relink it"
      fi
    elif [ -f "$d/CLAUDE.md" ] && [ -r "$d/CLAUDE.md" ] && [ -f "$d/AGENTS.md" ] && [ -r "$d/AGENTS.md" ] \
         && ! cmp -s "$d/AGENTS.md" "$d/CLAUDE.md"; then
      warn W-AGENTSMD-DRIFT "AGENTS.md is a regular-file copy that has drifted from CLAUDE.md — replace with a symlink, or re-sync"
    fi
  fi

  # Impact-tracking hygiene: a repo opted into impact tracking carries a .keel/ marker. Its event log is
  # ephemeral and must stay out of git (the ledger.md beside it is durable and MAY be committed — so we
  # check the log specifically, not the whole dir). Fires ONLY when .keel/ exists AND the log isn't ignored;
  # it never nags a project to enable tracking (optional).
  if [ -d "$d/.keel" ] && ! git -C "$d" check-ignore -q .keel/impact-events.log 2>/dev/null; then
    warn W-EVENTLOG-TRACKED "impact event log (.keel/impact-events.log) is not gitignored — it can leak into history (run keel-impact.sh enable, or add /.keel/impact-events.log to .gitignore)"
  fi

  # Impact-tracking split-brain (dir #10 residue (b)): a pre-#67 `enable`/init-project run could have
  # planted the .keel/ marker at a linked worktree's own top (untracked, so it's invisible to other
  # worktrees). PR #67's resolvers try the CURRENT top first, so a leftover worktree-local marker
  # silently diverts that worktree's events into its own ledger while the main-top ledger undercounts —
  # a split it's easy not to notice without this check. Covers both directions: $d itself carrying a
  # stray local marker next to the main one, and $d (as the main checkout) having linked worktrees that
  # each carry their own.
  # `|| true`: outside a repo (e.g. the "bare dir" GAP case above, which doesn't `continue`) git exits
  # 128 and pipefail would trip `set -e` here, aborting the whole audit instead of just skipping this
  # check — same guard as keel-impact.sh's `_keel_main_top`. Both paths come from git (not `cd && pwd`)
  # so they're canonicalized the same way — on macOS /tmp is a symlink to /private/tmp, and comparing a
  # shell-resolved path against git's own realpath'd worktree list would otherwise false-positive.
  d_top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  wt_list="$(git -C "$d" worktree list --porcelain 2>/dev/null || true)"  # one snapshot, read below for both main_top and the stray-worktree scan
  main_top="$(printf '%s\n' "$wt_list" | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
  # The MAIN checkout's top, never a worktree-local one — a single fallback chain reused below by
  # both the map-drift baseline and the doctor-accept file: a worktree-local .keel/ is exactly what
  # the split-brain check above flags, so neither lookup should tempt anyone into creating one.
  unit_top="${main_top:-${d_top:-$d}}"
  if [ -n "$d_top" ] && [ -n "$main_top" ] && [ -d "$main_top/.keel" ]; then
    if [ "$main_top" != "$d_top" ] && [ -d "$d/.keel" ]; then
      warn W-KEEL-SPLIT "worktree-local .keel/ marker coexists with the main checkout's ($main_top/.keel/) — events split across two ledgers (this worktree wins locally); remove this worktree's .keel/ so events land in the shared one"
    elif [ "$main_top" = "$d_top" ]; then
      stray_wt=0
      while IFS= read -r wline; do
        case "$wline" in "worktree "*) wt="${wline#worktree }" ;; *) continue ;; esac
        if [ "$wt" = "$d_top" ]; then continue; fi          # the main checkout itself
        if [ -d "$wt/.keel" ]; then stray_wt=$((stray_wt + 1)); fi
      done <<EOF
$wt_list
EOF
      if [ "$stray_wt" -gt 0 ]; then
        warn W-KEEL-SPLIT "$stray_wt linked worktree(s) carry their own .keel/ marker alongside the main checkout's — events split across ledgers; remove the worktree-local .keel/ dirs so events land in the shared one"
      fi
    fi
  fi

  # Map-drift (dir #39 T1): a backtick-spanned path/filename in the LIVE map that no longer exists on
  # disk — code moves, the map doesn't, and the agent confidently follows a dead path. Backtick-spans
  # ONLY (never bare prose): a backtick is the author's own "literal identifier" marker, the strongest
  # precision filter available. NEVER check CLAUDE-archive.md/BACKLOG.md — historical files legitimately
  # name dead paths; every hit there would be false by definition. A span may carry trailing args/flags
  # (`` `tools/doctor.sh --quiet` ``) — only its first whitespace token is a path candidate. Narrower
  # scope than tools/self/doctor.sh's "dead internal references" check on purpose: that one audits the
  # Keel repo's OWN tools/commands/templates references; this one audits an arbitrary CONSUMER project's
  # CLAUDE.md against that project's own tree — different corpus, different skip rules, not a duplicate.
  if [ -f "$d/CLAUDE.md" ]; then
    # unit_top (computed above) resolves this at the main checkout, never a worktree-local one.
    baseline="$unit_top/.keel/map-drift-baseline"
    # Read once, not once-per-missing-token: a grep-per-candidate against the baseline would re-open and
    # re-scan the same small file for every drift hit on a doc with many accepted mentions. No comment
    # support here (unlike doctor-accept, see load_token_set above) — this file predates it, and a bare
    # `#`-led path mention would be a real token, not an annotation to strip.
    baseline_set=$'\n'"$(load_token_set "$baseline" 0)"$'\n'
    drift_list=""
    drift_count=0
    max_show=5
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case "$tok" in
        # URL (scheme://…), placeholder, glob, env-var, ~-path, or absolute path (incl. the KB's neutral
        # stand-ins like /Users/x/…) — unverifiable by design, skip rather than false-positive. $ matches
        # ANYWHERE (an env-var mid-path, e.g. `output/$BUILD_ID/report.md`, is exactly as unverifiable as
        # one at the start); ~ stays prefix-anchored — a trailing ~ is a real, checkable editor-backup
        # name (`file.sh~`), not a placeholder, so a mid-token ~ must not be swept up with it.
        *'://'*|*'<'*|*'>'*|*'$'*|*'*'*|*'?'*|'~'*|/*) continue ;;
      esac
      # strip a trailing `:LINE` decoration (`tools/doctor.sh:42`, this file's own doc-link convention)
      # before judging path-shape or checking existence — the decoration isn't part of the path.
      case "$tok" in
        *:[0-9]*)
          suffix="${tok##*:}"
          case "$suffix" in ''|*[!0-9]*) ;; *) tok="${tok%:*}" ;; esac
          ;;
      esac
      if [[ "$tok" != */* ]]; then
        if [[ "$tok" =~ ^\.[A-Za-z][A-Za-z0-9]*$ ]]; then
          # single-dot-led, no further dots: a SHORT one names a file TYPE in prose (`` `.sh` ``,
          # `` `.json` ``) — no basename to check for existence. A LONGER one is a real dotfile's whole
          # name (`.gitignore`, `.editorconfig`) — keep those as candidates unconditionally.
          [ "${#tok}" -le 5 ] && continue
        else
          # normal name.ext shape (or a multi-dot dotfile like .swiftlint.yml) — needs an extension-
          # looking ending, capped length, to count as a path signal at all.
          [[ "$tok" =~ \.[A-Za-z][A-Za-z0-9]{0,5}$ ]] || continue
        fi
      fi
      [ -e "$d/$tok" ] && continue
      # A worktree legitimately lacks paths that live only at the main checkout by this project's own
      # convention (BACKLOG.md, private/ — see this project's CLAUDE.md). unit_top already resolves to
      # the main checkout (never worktree-local), so re-check there before flagging drift (dir #113).
      [ "$unit_top" != "$d" ] && [ -e "$unit_top/$tok" ] && continue
      in_token_set "$baseline_set" "$tok" && continue
      drift_count=$((drift_count + 1))
      [ "$drift_count" -le "$max_show" ] && drift_list="${drift_list}${drift_list:+, }$tok"
    done < <(awk 'BEGIN{f=0} /^[[:space:]]*(```|~~~)/{f=!f;next} !f' "$d/CLAUDE.md" 2>/dev/null \
               | grep -oE '`[^`[:space:]][^`]*`' \
               | sed -e 's/^`//' -e 's/`$//' \
               | awk '{print $1}' \
               | sort -u)
    if [ "$drift_count" -gt 0 ]; then
      more=""
      [ "$drift_count" -gt "$max_show" ] && more=" and $((drift_count - max_show)) more"
      hint H-MAP-DRIFT "CLAUDE.md map may be stale — not found on disk: ${drift_list}${more} (fix the mention, or accept it in .keel/map-drift-baseline)"
    fi
  fi

  # A machine-global core.hooksPath covers this repo — UNLESS the repo sets its own LOCAL core.hooksPath,
  # which silently overrides the global one (git runs the local path, so the global guard never fires here).
  # So when a local override exists, verify it actually carries the guard before trusting it.
  local_hooks="$(git -C "$d" config --local core.hooksPath 2>/dev/null || true)"
  if [ -n "$local_hooks" ]; then
    case "$local_hooks" in /*) lhd="$local_hooks" ;; *) lhd="$d/$local_hooks" ;; esac
    # An EXECUTABLE pre-commit is the whole test, same bar as the global branch below (dir #97). The
    # older `secret-scan.sh OR pre-commit OR pre-push` reading counted an engine file, or a push-only
    # hook, as cover: a dir holding just secret-scan.sh — a pre-commit deleted, or one that lost its +x
    # bit — left every commit running nothing while doctor printed a clean 0/0/0 (reproduced: a planted
    # key committed straight through). Presence of parts is not a wired guard.
    if [ -x "$lhd/pre-commit" ]; then
      # carries the guard — but a WIRED copy that drifted from the shipped engine runs old detection.
      # dir #122: a LOCAL hooksPath pinned to the very same absolute dir the machine-global one names
      # (-ef, same physical file) is one drifted file, not two — the machine-wide W-GUARD-GLOBAL-STALE
      # check above already reports it, with the remediation that actually fixes both (this repo's
      # override just points at the same shared dir; re-vendoring per-repo here would either write a
      # second, unshared copy or clobber the shared one, neither of which is what "re-vendor: <this
      # repo>" promises). Only the RELATIVE case is this branch's to own — an absolute local path that
      # happens to differ from the global one is a genuine separate vendored copy, still reported here.
      # Compared against $global_hooks_eff/_eff_abs, NOT the plain $global_hooks/_abs — the machine-wide
      # check above (dir #121's hoist) fires on the EFFECTIVE value, so deduping against the narrower
      # --global-only one would miss the dup on exactly the XDG-behind-~/.gitconfig machines dir #121
      # exists for (found by an independent /code-review high pass, reproduced against a live sandbox).
      local_is_global_dup=0
      [ "$global_hooks_eff_abs" = 1 ] && [ -d "$lhd" ] && [ -d "$global_hooks_eff" ] && [ "$lhd" -ef "$global_hooks_eff" ] \
        && local_is_global_dup=1
      if [ "$local_is_global_dup" = 0 ] && [ -f "$lhd/secret-scan.sh" ] && [ -f "$shipped_scan" ] \
         && ! cmp -s "$lhd/secret-scan.sh" "$shipped_scan"; then
        warn W-GUARD-STALE "vendored secret-guard (core.hooksPath '$local_hooks') differs from the engine this Keel checkout ships — re-vendor: install-secret-guard.sh <this repo>"
      fi
    else
      warn W-GUARD-BYPASSED "local core.hooksPath ('$local_hooks') takes over this repo's hooks but carries no executable pre-commit, so commits here run nothing — and any machine-global guard is silently bypassed (vendor the guard into the override dir, or unset it)"
    fi
  elif [ -n "$global_hooks" ]; then
    # A machine-global core.hooksPath is only cover if the dir it names actually carries an executable
    # pre-commit — until dir #97 this branch trusted the setting alone and swallowed the hookless case
    # as "covered by global": a hooksPath pointing at an empty dir left commits guarded by nothing while
    # the audit printed a clean 0/0/0. Found by the operator's own /code-review pass on dir #97 and
    # reproduced (a planted key committed through). The dir is resolved PER REPO, the same way the
    # local_hooks branch above does it: a relative core.hooksPath (`.githooks`) is resolved by git
    # against the repo, so testing it from doctor's own cwd would both miss real guards and invent
    # absent ones — the `~/` form is already expanded where $global_hooks is read.
    case "$global_hooks" in /*) ghd="$global_hooks" ;; *) ghd="$d/$global_hooks" ;; esac
    if [ -x "$ghd/pre-commit" ]; then
      # Covered. Engine drift for an ABSOLUTE hooksPath was checked once, machine-wide, above; a
      # RELATIVE one is per-repo by construction, so that pass deliberately skips it and this branch
      # owns it — with the remediation that actually works here (the machine one exits 3 rather than
      # touch a hooksPath it didn't set). The two domains are disjoint, so one drift is reported once,
      # by whichever check can fix it. Phrased like the local_hooks branch above.
      if [ "$global_hooks_abs" = 0 ] && [ -f "$ghd/secret-scan.sh" ] && [ -f "$shipped_scan" ] \
         && ! cmp -s "$ghd/secret-scan.sh" "$shipped_scan"; then
        warn W-GUARD-STALE "secret-guard at the global core.hooksPath '$global_hooks' ($ghd) differs from the engine this Keel checkout ships — re-vendor: install-secret-guard.sh $d"
      fi
    else
      ghd_note=""
      [ "$ghd" = "$global_hooks" ] || ghd_note=" (relative — resolves to $ghd for this repo)"
      warn W-GUARD-UNWIRED "secret-guard is not wired: core.hooksPath is set to $global_hooks$ghd_note but that dir carries no executable pre-commit, so commits here are guarded by nothing (install-secret-guard.sh --global, or vendor into this repo)$guard_home_note"
    fi
  elif ( cd "$d" 2>/dev/null && p="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null)" && [ -x "$p" ] ); then
    # vendored into the real hooks dir (a worktree/submodule isn't .git/hooks) — same drift check
    vh="$(git -C "$d" rev-parse --git-path hooks 2>/dev/null)"
    case "$vh" in /*) ;; *) vh="$d/$vh" ;; esac
    if [ -f "$vh/secret-scan.sh" ] && [ -f "$shipped_scan" ] && ! cmp -s "$vh/secret-scan.sh" "$shipped_scan"; then
      warn W-GUARD-STALE "vendored secret-guard ($vh) differs from the engine this Keel checkout ships — re-vendor: install-secret-guard.sh <this repo>"
    fi
  else
    warn W-GUARD-UNWIRED "secret-guard not wired (install-secret-guard.sh --global, or vendor into this repo)$guard_home_note"
  fi

  # dir #68 pairing check, project-scope half — mirrors the --install-mode check above, which only
  # ever sees the machine-global settings.json and structurally cannot see this. The gate is opt-in
  # per project (tools/install-pre-pr-gate.sh <repo>, the documented default), so plain absence is not
  # a finding at any tier — most projects legitimately never wire it, same posture as the .keel/ marker
  # checks (an unadopted optional feature isn't a gap). The one state worth flagging is the
  # secret-guard-shaped one: SOME hook here already references pre-pr-gate.sh (this repo clearly ran
  # the installer, or hand-wired part of it) but the load-bearing PreToolUse/Bash hook specifically is
  # missing — a rail that looks engaged but doesn't actually enforce anything, same "looks wired but
  # isn't" shape as W-GUARD-BYPASSED.
  proj_settings="$d/.claude/settings.json"
  if gate_hook_wired "$proj_settings"; then
    say "  OK   /polish gate: wired (project scope, $proj_settings)"
  elif gate_any_reference "$proj_settings"; then
    warn W-GATE-PARTIAL "$proj_settings references pre-pr-gate.sh but the load-bearing PreToolUse/Bash hook isn't wired — gh pr create is NOT actually gated here; re-run tools/install-pre-pr-gate.sh $d (--force to replace a stale hook)"
  fi

  # Publication-bound projects (those with a .public-audit config) shouldn't commit with a real
  # personal/corporate email — it ends up in public history. Nudge toward a noreply address.
  # Public-safe set: $safe_email_re, sourced once above from tools/lib/safe-emails.sh — public-audit.sh
  # (the GAP gate) sources the same file, so this advisory mirror can't silently disagree with it.
  if [ -f "$d/.public-audit" ]; then
    email="$(git -C "$d" config user.email 2>/dev/null || true)"
    # dir #120: the effective read above falls through to whatever global config is in scope when this
    # repo sets no LOCAL user.email — under a redirected HOME it can go silent (no email anywhere) or
    # read a container's baked-in address, either of which looks like a clean verdict without saying so.
    # Detectable: compare against the LOCAL-only read — a mismatch means the verdict just given (WARN or
    # silence) rode on config this repo doesn't own.
    email_local="$(git -C "$d" config --local user.email 2>/dev/null || true)"
    # Disclose whenever this repo's OWN config didn't settle the verdict — including the "no email
    # anywhere" case (found by an independent /code-review high pass: the prior `$email != $email_local`
    # test stayed silent exactly when BOTH are empty, the precise silent-under-a-sandbox case this
    # comment above already claims to cover). Not "$guard_cfg_src" in the note text: that names the ONE
    # file a plain `git config --global` read collapses to, but the read above is user.email's own
    # EFFECTIVE resolution (system/global/XDG, same merge core.hooksPath gets) — naming a specific file
    # here risks pointing at one that was never actually consulted (same mislabeling the guard-side
    # $guard_eff_note exists to avoid).
    if [ -n "$email" ] && ! printf '%s' "$email" | grep -qE "$safe_email_re"; then
      email_note=""
      [ "$email" = "$email_local" ] || email_note=" (read via git's global/system config, not this repo's own)"
      warn W-EMAIL-PUBLIC "git commit email '$email' is not a noreply address — it lands in public history (run public-audit.sh)$email_note"
    elif [ -z "$email_local" ]; then
      say "       (commit email for this publication-bound project not set locally — the verdict above rode on git's global/system config, or found nothing at all; a redirected HOME looks identical to a genuinely safe repo)"
    fi
  fi

  # Dependency pinning (FRAMEWORK "Dependency versioning") — WARN on a floating version of a pinnable dep:
  # a Docker/compose image :latest tag, or a major-only GitHub Action @vN tag. A *-latest CI runner label
  # is NOT flagged — a managed alias, not a pinnable artifact.
  # find+grep, not `grep -r --include=…`: busybox grep (Alpine) has no --include, so the option errored
  # and this check silently never fired there. find's -name globs are portable across GNU/BSD/busybox.
  # dir #85 (code audit, finding 12): fp_find, not a bare find — every per-stack check around this one
  # prunes build-output/vendored trees (see fp_find's own comment) and this one silently didn't, so a
  # vendored dependency shipping its own example Dockerfile flagged the adopter for code they don't own.
  dep="$(fp_find "$d" -type f \( -name 'Dockerfile*' -o -name '*compose*.yml' -o -name '*compose*.yaml' \) \
           -exec grep -InE '^[^#]*(FROM|image:)[[:space:]]+[^[:space:]]+:latest' {} + | head -1 || true)"
  if [ -z "$dep" ] && [ -d "$d/.github/workflows" ]; then
    dep="$(grep -rInE 'uses:[[:space:]]+[^[:space:]]+@v[0-9]+([[:space:]]|$)' "$d/.github/workflows" 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$dep" ]; then
    hint H-DEP-FLOATING "floating dependency version — pin it (no image :latest / Action @vN; FRAMEWORK 'Dependency versioning')"
  fi

  # Per-stack lint gate (FRAMEWORK "Code conventions"): each stack enforces its native linter, run in CI.
  # doctor flags a project whose stack is detected but its lint config is absent. Detection prunes build /
  # vendored-dependency trees, so a dependency's sources or configs never flip the gate or count as ours.
  # Java — Checkstyle present, and no wildcard imports.
  if fp_any "$d" \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) -print \
     || fp_any "$d" -name '*.java' -print; then
    if fp_any "$d" -name '*.java' -exec grep -lE '^import[[:space:]]+(static[[:space:]]+)?[A-Za-z0-9_.]+\.\*;' {} +; then
      hint H-JAVA-WILDCARD "Java wildcard imports present — list each import individually (FRAMEWORK 'Code conventions')"
    fi
    fp_any "$d" -name 'checkstyle*.xml' -print \
      || hint H-LINT-JAVA "Java stack but no checkstyle config present — add one and wire it into CI (FRAMEWORK 'Code conventions')"
  fi
  # Python — Ruff config ([tool.ruff] in a pyproject.toml, or a ruff.toml / .ruff.toml).
  if fp_any "$d" \( -name pyproject.toml -o -name setup.py -o -name setup.cfg \) -print \
     || [ -f "$d/requirements.txt" ]; then
    if ! { fp_any "$d" -name pyproject.toml -exec grep -lE '\[tool\.ruff' {} + \
           || fp_any "$d" \( -name ruff.toml -o -name .ruff.toml \) -print; }; then
      hint H-LINT-PY "Python stack but no Ruff config ([tool.ruff] / ruff.toml) — add one and run it in CI (FRAMEWORK 'Code conventions')"
    fi
  fi
  # Swift — a first-party SwiftLint config.
  if fp_any "$d" \( -name Package.swift -o -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print \
     || fp_any "$d" -name '*.swift' -print; then
    fp_any "$d" \( -name .swiftlint.yml -o -name .swiftlint.yaml \) -print \
      || hint H-LINT-SWIFT "Swift stack but no SwiftLint config — add a first-party .swiftlint.yml and run it in CI (FRAMEWORK 'Code conventions')"
  fi
  # Bash — either a first-party .shellcheckrc, or shellcheck actually invoked in CI (unlike
  # Checkstyle/Ruff/SwiftLint, shellcheck runs fine with zero config, so a config file alone isn't a
  # reliable signal — a repo that wires `shellcheck` straight into its workflow with no rc file, e.g.
  # this Keel checkout itself, must not be flagged).
  if fp_any "$d" -name '*.sh' -print; then
    if ! fp_any "$d" -name '.shellcheckrc' -print \
       && ! { [ -d "$d/.github/workflows" ] \
              && grep -rlE '(^|[^A-Za-z0-9_-])shellcheck([^A-Za-z0-9_-]|$)' "$d/.github/workflows" >/dev/null 2>&1; }; then
      hint H-LINT-BASH "Bash stack but no ShellCheck config (.shellcheckrc) and no shellcheck invocation in CI — wire one (FRAMEWORK 'Code conventions')"
    fi
  fi

  # Worktree CLAUDE.md bridge (FRAMEWORK "Worktree discipline"): a private-fork project gitignores CLAUDE.md,
  # so `git worktree add` checks it out WITHOUT one and that worktree's session starts blind to the project
  # context. Each live linked worktree should carry a CLAUDE.md (a bridge symlink). Public-fork (committed
  # CLAUDE.md) is exempt — a worktree checks it out normally.
  if [ -f "$d/CLAUDE.md" ] && git -C "$d" check-ignore -q CLAUDE.md 2>/dev/null; then
    wt_missing=0
    while IFS= read -r wline; do
      case "$wline" in "worktree "*) wt="${wline#worktree }" ;; *) continue ;; esac
      if [ "$wt" = "$d" ]; then continue; fi                                  # the main checkout, not a worktree
      if [ ! -d "$wt" ]; then continue; fi                                    # gone/prunable
      if [ -e "$wt/CLAUDE.md" ] || [ -L "$wt/CLAUDE.md" ]; then continue; fi  # already bridged
      wt_missing=$((wt_missing + 1))
    done <<EOF
$wt_list
EOF
    if [ "$wt_missing" -gt 0 ]; then
      warn W-WT-BRIDGE "$wt_missing linked worktree(s) missing the CLAUDE.md bridge — the session starts blind there (FRAMEWORK 'Worktree discipline')"
    fi
  fi

  # unit_top: same fallback chain as the map-drift baseline above (a worktree-local .keel/ would
  # itself be a finding, so neither lookup should tempt anyone into creating one).
  flush_notes "$unit_top/.keel/doctor-accept"
done

if [ "$exit_code" = 0 ]; then say "doctor: structural baseline OK"; fi
finish
