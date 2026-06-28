#!/usr/bin/env bash
# public-audit — is this repo safe to publish? Scan tracked content AND git history for personal /
# instance-specific leakage before a private->public flip. The audit you run once, on demand — NOT a
# per-commit hook (scanning full history every commit is the wrong altitude).
#
#   GAP  (fails, exit 1): a declared-private token, or a commit/tag identity email that isn't
#        public-safe — high-confidence leaks that are painful to scrub after publishing.
#   WARN (advisory):      heuristic hits — absolute home paths, other emails in content, Cyrillic —
#        a human decides.
#
# Usage:
#   public-audit.sh [DIR]            audit DIR (default: .); reads DIR/.public-audit if present
#   public-audit.sh --token ERE ...  add a private token to hunt (repeatable; CLI, not committed)
#   public-audit.sh --no-history ... tree only (skip the git-history scan)
#   public-audit.sh --config FILE    use a specific config file
#   public-audit.sh --quiet ...      print only GAP/WARN lines
#
# Config (.public-audit) — ERE values, '#' comments:
#   token: <ERE>         a private string to flag in tree + history (an internal name, host, ...)
#   allow-email: <ERE>   an email/domain OK in history & content (added to the built-in noreply set)
#   allow-path: <glob>   a tracked path to skip in content scanning
#
# Note: a committed `.public-audit` literally contains its token strings. For a truly-secret token,
# pass it with --token (ephemeral) or keep the config gitignored, rather than committing it.
# Note: tokens are unanchored regexes — a short token also matches inside unrelated strings such as
# a commit hash. Prefer a specific token to avoid false positives.
set -uo pipefail

QUIET=0
NO_HISTORY=0
CONFIG=""
DIR=""
cli_tokens=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)      QUIET=1 ;;
    --no-history) NO_HISTORY=1 ;;
    --config)     shift; CONFIG="${1:?--config needs a FILE}" ;;
    --token)      shift; cli_tokens+=("${1:?--token needs an ERE}") ;;
    -*)           echo "public-audit: unknown option '$1'" >&2; exit 2 ;;
    *)            DIR="$1" ;;
  esac
  shift
done
DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "public-audit: not a directory: $DIR" >&2; exit 2; }

# Built-in public-safe email patterns (ERE). Real personal/corporate emails are deliberately absent.
SAFE_EMAILS=(
  '@users\.noreply\.github\.com'
  'noreply@anthropic\.com'
  'noreply@github\.com'
  '@example\.(com|org|net)'
  '@[A-Za-z0-9.-]*\.invalid'
)
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
HOME_RE='/(Users|home)/[A-Za-z0-9._-]+'

# --- gather config -------------------------------------------------------------------------------
tokens=()
[ "${#cli_tokens[@]}" -gt 0 ] && tokens+=("${cli_tokens[@]}")
allow_emails=()
allow_paths=()

cfg="${CONFIG:-$DIR/.public-audit}"
if [ -f "$cfg" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    val="$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$line" in
      ''|\#*)         ;;
      token:*)        tokens+=("$val") ;;
      allow-email:*)  allow_emails+=("$val") ;;
      allow-path:*)   allow_paths+=("$val") ;;
    esac
  done < "$cfg"
fi

# combined safe-email regex (built-ins + configured allow-email)
safe_re=""
for e in "${SAFE_EMAILS[@]}"; do safe_re="${safe_re:+$safe_re|}$e"; done
if [ "${#allow_emails[@]}" -gt 0 ]; then
  for e in "${allow_emails[@]}"; do [ -n "$e" ] && safe_re="${safe_re:+$safe_re|}$e"; done
fi

# pathspec exclusions for content scans (the config file always; plus any allow-path globs)
excludes=( ":(exclude).public-audit" )
if [ "${#allow_paths[@]}" -gt 0 ]; then
  for g in "${allow_paths[@]}"; do [ -n "$g" ] && excludes+=( ":(exclude)$g" ); done
fi

# --- reporting -----------------------------------------------------------------------------------
exit_code=0
say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

is_git=0
git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 && is_git=1

# Temp refs from the host-PR-ref scan (section 6) must never outlive the run. Clean them on EXIT/INT/TERM
# so a Ctrl-C mid-fetch — or a run against a repo with no GitHub remote — leaves nothing behind, and any
# orphan a prior interrupted run left is reaped on the next run's exit.
cleanup_pr_refs() {
  [ "$is_git" = 1 ] || return 0
  git -C "$DIR" for-each-ref --format='%(refname)' 'refs/keel-pr-audit/*' 2>/dev/null \
    | while IFS= read -r r; do [ -n "$r" ] && git -C "$DIR" update-ref -d "$r" 2>/dev/null || true; done
}
trap cleanup_pr_refs EXIT INT TERM

say "● public-audit ($DIR)"
[ "$is_git" = 1 ] || say "       (not a git repo — git-history checks skipped)"

# helper: first matching line of a tracked-tree grep, or empty
tree_grep() { git -C "$DIR" grep -nIE "$1" -- . "${excludes[@]}" 2>/dev/null; }

# --- 1. identities in git history (GAP) ----------------------------------------------------------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # A shallow clone only carries part of history, so every scan below sees an incomplete picture and a
  # clean result is not trustworthy. Warn loudly (visible even under --quiet, via the WARN stream).
  if [ "$(git -C "$DIR" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    warn "shallow clone — git-history scans are INCOMPLETE; run 'git fetch --unshallow' before trusting a clean result"
  fi
  ids="$( { git -C "$DIR" log --all --format='%ae%n%ce' 2>/dev/null;
            git -C "$DIR" for-each-ref --format='%(taggeremail)' refs/tags 2>/dev/null | tr -d '<>'; } \
          | sed '/^$/d' | sort -u )"
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    printf '%s' "$e" | grep -qE "$safe_re" && continue
    gap "non-public-safe identity in git history: $e"
  done <<EOF
$ids
EOF
fi

# --- 2. declared-private tokens, in tree AND history (GAP) ---------------------------------------
if [ "${#tokens[@]}" -gt 0 ]; then
  for t in "${tokens[@]}"; do
    [ -z "$t" ] && continue
    hit="$(tree_grep "$t" | head -1 || true)"
    [ -n "$hit" ] && gap "private token /$t/ in tracked tree — e.g. $hit"
    if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
      c="$(git -C "$DIR" log --all --oneline -G"$t" 2>/dev/null | head -1 || true)"
      m="$(git -C "$DIR" log --all --oneline --grep="$t" -E 2>/dev/null | head -1 || true)"
      [ -n "$c$m" ] && gap "private token /$t/ in git history — e.g. ${c:-$m}"
    fi
  done
fi

# --- 3. heuristic content scans (WARN) -----------------------------------------------------------
home="$(tree_grep "$HOME_RE" | head -1 || true)"
[ -n "$home" ] && warn "absolute home path in tracked tree — e.g. $home"

emails="$(tree_grep "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
[ -n "$emails" ] && warn "email in tracked content — e.g. $emails"

# Cyrillic via UTF-8 lead bytes (0xD0-0xD3) + a continuation byte — portable across grep flavors,
# unlike `git grep -P '\x{0400}'` which isn't supported on every git build.
cyr_pat=$'[\xd0-\xd3][\x80-\xbf]'
# Subshell cd so ls-files' repo-relative paths resolve for grep (which runs in the current cwd).
cyr="$( cd "$DIR" && git ls-files -z -- . "${excludes[@]}" 2>/dev/null \
        | LC_ALL=C xargs -0 grep -lI "$cyr_pat" 2>/dev/null | head -1 || true)"
[ -n "$cyr" ] && warn "Cyrillic text in tracked file — e.g. $cyr"

# --- 4. agent tooling / session metadata (WARN) --------------------------------------------------
# The per-session trailers a coding agent appends to commits (and the same shape in tracked files).
# We hit this leak class ourselves and the audit missed it — so surface it on purpose.
session_re='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'
sess_tree="$(tree_grep "$session_re" | head -1 || true)"
[ -n "$sess_tree" ] && warn "agent/session metadata in tracked tree — e.g. $sess_tree"
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  sess_msg="$(git -C "$DIR" log --all --format='%B' 2>/dev/null | grep -aE "$session_re" | head -1 || true)"
  [ -n "$sess_msg" ] && warn "agent/session metadata in a commit message — e.g. $sess_msg"
fi

# --- 5. history content heuristics (WARN) --------------------------------------------------------
# Section 3 scans the working tree only — so personal data in a commit-message body or a historical
# diff (an added-then-removed blob) would pass clean. Scan history content (messages + diffs in one
# `git log -p` pass) with the SAME regexes; reuse EMAIL_RE/HOME_RE/safe_re/cyr_pat. WARN, not GAP.
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # message bodies + diffs, AND annotated-tag message bodies (which `git log -p` omits).
  hist="$( { git -C "$DIR" log --all -p 2>/dev/null;
             git -C "$DIR" for-each-ref --format='%(contents)' refs/tags 2>/dev/null; } || true)"
  h="$(printf '%s\n' "$hist" | grep -nE "$HOME_RE" | head -1 || true)"
  [ -n "$h" ] && warn "absolute home path in git history — e.g. $h"
  h="$(printf '%s\n' "$hist" | grep -nIE "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
  [ -n "$h" ] && warn "email in git history content — e.g. $h"
  h="$(printf '%s\n' "$hist" | LC_ALL=C grep -n "$cyr_pat" | head -1 || true)"
  [ -n "$h" ] && warn "Cyrillic text in git history — e.g. $h"
fi

# --- 6. host-side PR refs (GitHub refs/pull/*) ---------------------------------------------------
# These are served by the host but are NOT reachable from `git log --all`, so a leak in a closed PR's
# commits passes the local scan (a force-push of `main` does not purge them). When a remote is set
# (and not --no-history), fetch them and run the SAME checks: identity/token = GAP, heuristic = WARN.
# Offline / no PR refs / non-GitHub remote → a prominent NOTE (out of local scope — the only fix is
# delete-and-recreate; see docs/going-public.md). The network call is gated so the tool still runs offline.
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # Probe EVERY remote, not just the first: `git remote | head -1` could pick a non-GitHub mirror that
  # sorts ahead of the real GitHub remote and silently skip the PR-ref scan. Scan each remote that
  # exposes refs/pull/*; emit the OUT-OF-SCOPE note only if a remote exists but none did.
  any_remote=0; scanned_pr=0
  while IFS= read -r remote; do
    [ -n "$remote" ] || continue
    any_remote=1
    git -C "$DIR" ls-remote --quiet "$remote" 'refs/pull/*' 2>/dev/null | grep -q . || continue
    scanned_pr=1
    # Fetch both the PR tip (…/head) AND GitHub's synthetic merge (…/merge) — neither is reachable
    # from `git log --all`. Flat dest names keep them in one namespace for the scans below.
    git -C "$DIR" fetch -q "$remote" 'refs/pull/*/head:refs/keel-pr-audit/head-*' \
      'refs/pull/*/merge:refs/keel-pr-audit/merge-*' 2>/dev/null || true
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      printf '%s' "$e" | grep -qE "$safe_re" && continue
      gap "non-public-safe identity in a host PR ref (refs/pull/*): $e — purge via delete-and-recreate (going-public.md)"
    done <<EOF
$(git -C "$DIR" log --glob='refs/keel-pr-audit/*' --format='%ae%n%ce' 2>/dev/null | sed '/^$/d' | sort -u)
EOF
    pr_hist="$(git -C "$DIR" log --glob='refs/keel-pr-audit/*' -p 2>/dev/null || true)"
    if [ "${#tokens[@]}" -gt 0 ]; then
      for t in "${tokens[@]}"; do
        [ -z "$t" ] && continue
        printf '%s' "$pr_hist" | grep -qE "$t" && \
          gap "private token /$t/ in a host PR ref (refs/pull/*) — purge via delete-and-recreate"
      done
    fi
    # Same heuristic set the local-history pass (sections 4-5) applies, over PR-ref content. WARN.
    ph="$(printf '%s\n' "$pr_hist" | grep -nIE "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
    [ -n "$ph" ] && warn "email in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | grep -nE "$HOME_RE" | head -1 || true)"
    [ -n "$ph" ] && warn "absolute home path in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | LC_ALL=C grep -n "$cyr_pat" | head -1 || true)"
    [ -n "$ph" ] && warn "Cyrillic text in a host PR ref (refs/pull/*) — e.g. $ph"
    ph="$(printf '%s\n' "$pr_hist" | grep -naE "$session_re" | head -1 || true)"
    [ -n "$ph" ] && warn "agent/session metadata in a host PR ref (refs/pull/*) — e.g. $ph"
    cleanup_pr_refs   # reap this remote's temp refs before the next iteration (also runs on EXIT)
  done <<EOF_REMOTES
$(git -C "$DIR" remote 2>/dev/null)
EOF_REMOTES
  if [ "$any_remote" = 1 ] && [ "$scanned_pr" = 0 ]; then
    say "       NOTE: host PR refs (refs/pull/*) are OUT OF SCOPE of this local scan (offline, none,"
    say "       or a non-GitHub remote). A repo with closed PRs must purge them via delete-and-recreate"
    say "       before going public — git log --all does NOT cover them. See docs/going-public.md."
  fi
fi

# --- verdict -------------------------------------------------------------------------------------
[ "$exit_code" = 0 ] && say "public-audit: no publication blockers found"
exit "$exit_code"
