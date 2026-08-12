#!/usr/bin/env bash
# public-audit — is this repo safe to publish? Scan tracked content AND git history for personal /
# instance-specific leakage before a private->public flip. The audit you run once, on demand — NOT a
# per-commit hook (scanning full history every commit is the wrong altitude).
#
#   GAP  (fails, exit 1): a declared-private token, a personal literal from the local
#        secret-scan-personal file, or a commit/tag identity email that isn't public-safe —
#        high-confidence leaks that are painful to scrub after publishing.
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
# If the secret-guard's local personal file exists (~/.claude/secret-scan-personal, override with
# $SECRET_SCAN_PERSONAL_FILE — one ERE per line, never committed), its literals are hunted as
# case-insensitive private tokens in the tree, git history, and binary blobs: they are precisely
# what must not ship when a repo goes public.
#
# Env: KEEL_AUDIT_BLOB_MAX (bytes, default 10485760) — per-blob cap for the binary decode pass;
#      oversized blobs are skipped but SURFACED as un-audited.
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
usage() {
  cat <<'EOF'
public-audit — is this repo safe to publish? Scan the tree AND git history (and host PR refs)
for personal / instance-specific leakage before a private->public flip.

Usage:
  public-audit.sh [DIR]            audit DIR (default: .); reads DIR/.public-audit if present
  public-audit.sh --token ERE ...  add a private token to hunt (repeatable; CLI, not committed)
  public-audit.sh --no-history     tree only (skip the git-history + PR-ref scan)
  public-audit.sh --config FILE    use a specific config file
  public-audit.sh --quiet          print only GAP/WARN lines
  public-audit.sh -h | --help

If ~/.claude/secret-scan-personal exists (override with $SECRET_SCAN_PERSONAL_FILE), its literals
are hunted as case-insensitive private tokens in the tree, git history, and binary blobs.

Env: KEEL_AUDIT_BLOB_MAX (bytes, default 10485760) caps the binary-blob decode pass;
     oversized blobs are skipped but surfaced as un-audited.
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)      QUIET=1 ;;
    --no-history) NO_HISTORY=1 ;;
    --config)     shift; CONFIG="${1:?--config needs a FILE}" ;;
    --token)      shift; cli_tokens+=("${1:?--token needs an ERE}") ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "public-audit: unknown option '$1' (try --help)" >&2; exit 2 ;;
    *)            DIR="$1" ;;
  esac
  shift
done
DIR="${DIR:-.}"
[ -d "$DIR" ] || { echo "public-audit: not a directory: $DIR" >&2; exit 2; }

# Built-in public-safe email patterns (ERE). Real personal/corporate emails are deliberately absent.
# dir #106: the set lives in tools/lib/safe-emails.sh — doctor.sh sources the same file for its
# advisory commit-email nudge, so the two can't silently re-diverge.
_pa_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/safe-emails.sh
. "$_pa_dir/lib/safe-emails.sh"
# EMAIL_RE / HOME_RE: the leaked-identifier content patterns, shared with self/doctor.sh's narrower
# GAP over FRAMEWORK.md/PRINCIPLES.md (dir #114) — same reuse reason as safe-emails.sh above.
# shellcheck source=tools/lib/leak-patterns.sh
. "$_pa_dir/lib/leak-patterns.sh"
unset _pa_dir

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

# Bad ERE? Detect by stderr, not exit code: a valid pattern on empty input exits 1 (no match) with no
# stderr; a broken one prints an error. (busybox grep doesn't use exit 2 for a bad regex, so an
# exit-code check would pass a broken regex through.) Shared by the allow-email and personal-literal
# validation below — same idiom, only the case-sensitivity flag differs.
valid_ere() { local flag="$1" pat="$2"; [ -z "$(printf '' | grep "$flag" -- "$pat" 2>&1 >/dev/null)" ]; }

# Personal literals from the secret-guard's local file double as private tokens for this audit —
# they are precisely what must not ship when a repo goes public. Case-INSENSITIVE (unlike tokens).
# Invalid lines are counted and warned about (without echoing them — the file's whole point is that
# its content stays off any pasteable output).
PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"
personal_re=""
bad_personal=0
if [ -f "$PERSONAL_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(printf '%s' "$line" | sed 's/[[:space:]][[:space:]]*#.*$//; s/^[[:space:]][[:space:]]*//; s/[[:space:]][[:space:]]*$//')"
    case "$line" in ''|\#*) continue ;; esac
    if valid_ere -iE "$line"; then
      personal_re="${personal_re:+$personal_re|}$line"
    else
      bad_personal=$((bad_personal + 1))
    fi
  done < "$PERSONAL_FILE"
fi

# combined safe-email regex (built-ins + configured allow-email). Seed from the lib's own pre-joined
# safe_email_re instead of re-deriving the SAFE_EMAILS join here too — dir #106 shared the pattern
# LIST; re-deriving the joiner would leave that half still duplicated by eyeball.
safe_re="$safe_email_re"
# A configured allow-email is user input — a broken ERE would make every later `grep -E "$safe_re"`
# spew "bad regex" and silently drop the content-leak WARNs. Validate each before trusting it; collect
# the bad ones to report once the WARN helper is defined below.
bad_allow_emails=()
if [ "${#allow_emails[@]}" -gt 0 ]; then
  for e in "${allow_emails[@]}"; do
    [ -n "$e" ] || continue
    if valid_ere -E "$e"; then
      safe_re="${safe_re:+$safe_re|}$e"
    else
      bad_allow_emails+=("$e")
    fi
  done
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
audit_tmp="$(mktemp -d)"
# dir #85 (code audit, finding 11): the INT/TERM handler must EXIT. Bash runs a trap handler for a
# caught signal and then RESUMES the script — so Ctrl-C used to tear down the fetched PR refs and the
# tmpdir and then keep auditing against the state it had just deleted, while the operator believed the
# run was cancelled. `exit 130` is the conventional 128+SIGINT status; the EXIT trap still fires after
# it (that is what actually performs cleanup), so the teardown is written once, not per-signal.
trap 'cleanup_pr_refs; rm -rf "$audit_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- binary-blob decode scan (shared by sections 5b and 6) ----------------------------------------
# The text passes cannot see INSIDE a binary: tree_grep's -I skips binary files, and `git log -p`
# renders a binary change as "Binary files … differ" — so personal data encoded in a binary blob (the
# felt leak class: a real name UTF-16-encoded inside a fixture) passes every text check above. This
# decodes each binary blob reachable from the given revs (NUL-strip + iconv UTF-16/UTF-32 LE/BE when
# available + raw-printable) and re-runs the same regex set: declared tokens + personal literals =
# GAP, heuristics = WARN — one example per category per pass, like the text sections. KEEL_AUDIT_BLOB_MAX (bytes, default 10MB)
# bounds the per-blob cost; oversized blobs are counted and SURFACED, never silently trusted.
scan_binary_blobs() {  # $1 = label for messages; the rest = rev-list args (e.g. --all)
  local label="$1"; shift
  local max="${KEEL_AUDIT_BLOB_MAX:-10485760}"
  case "$max" in ''|*[!0-9]*) max=10485760 ;; esac
  local tmp="$audit_tmp/blob" dec="$audit_tmp/blob.dec"
  local otype osha osize opath h t skipped=0 reported_toks="" reported_personal=""
  local hit_home="" hit_email="" hit_cyr=""
  # A failed mktemp (full/unwritable TMPDIR) must not silently no-op the whole pass — the tool's job
  # is never to trust unscanned content. Surface it and bail.
  if [ ! -d "$audit_tmp" ]; then
    warn "binary-blob scan of $label SKIPPED — no usable temp dir (mktemp failed); result is INCOMPLETE"
    return 0
  fi
  while IFS='|' read -r otype osha osize opath; do
    [ "$otype" = "blob" ] && [ -n "$osha" ] || continue
    if [ "${osize:-0}" -gt "$max" ]; then skipped=$((skipped + 1)); continue; fi
    git -C "$DIR" cat-file blob "$osha" > "$tmp" 2>/dev/null || continue
    # binary = contains a NUL byte; text blobs are already covered by the text passes
    LC_ALL=C tr -d '\000' < "$tmp" | cmp -s - "$tmp" && continue
    # Decode recipe: keep IN SYNC with secret-guard/secret-scan.sh emit_blob() — deliberately
    # duplicated (each tool stands alone), so an encoding gap fixed there must be fixed here too.
    {
      LC_ALL=C tr -d '\000' < "$tmp"; echo                        # ASCII-range UTF-16/UTF-32, no deps
      if command -v iconv >/dev/null 2>&1; then                   # non-ASCII UTF-16/UTF-32 (e.g. a Cyrillic name)
        iconv -f UTF-16LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
        iconv -f UTF-16BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
        iconv -f UTF-32LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
        iconv -f UTF-32BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      fi
      LC_ALL=C tr -c '[:print:]\t\n' '\n' < "$tmp"; echo          # raw printable runs
    } > "$dec"
    if [ "${#tokens[@]}" -gt 0 ]; then
      for t in "${tokens[@]}"; do
        [ -z "$t" ] && continue
        case "$reported_toks" in *"|$t|"*) continue ;; esac       # one GAP per token per pass
        if [ -n "$(grep -aE "$t" "$dec" 2>/dev/null | head -n1 || true)" ]; then
          gap "private token /$t/ in a binary blob in $label — ${opath:-$osha}"
          reported_toks="$reported_toks|$t|"
        fi
      done
    fi
    if [ -n "$personal_re" ] && [ -z "$reported_personal" ]; then
      h="$(grep -aoiE -- "$personal_re" "$dec" 2>/dev/null | head -1 || true)"
      if [ -n "$h" ]; then
        gap "personal literal (secret-scan-personal) in a binary blob in $label — ${opath:-$osha}: $h"
        reported_personal=1
      fi
    fi
    if [ -z "$hit_home" ]; then
      h="$(grep -aoE "$HOME_RE" "$dec" 2>/dev/null | head -1 || true)"
      [ -n "$h" ] && hit_home="$h (${opath:-$osha})"
    fi
    if [ -z "$hit_email" ]; then
      h="$(grep -aoE "$EMAIL_RE" "$dec" 2>/dev/null | grep -vE "$safe_re" | head -1 || true)"
      [ -n "$h" ] && hit_email="$h (${opath:-$osha})"
    fi
    if [ -z "$hit_cyr" ]; then
      # Require ≥4 CONSECUTIVE Cyrillic chars, unlike the single-pair text heuristic: the NUL-strip
      # and raw-printable views of compressed data (a gif, a zip) match an isolated
      # [\xd0-\xd3][\x80-\xbf] pair by chance hundreds of times per MB — a real name is a run.
      h="$(LC_ALL=C grep -acE "(${cyr_pat}){4}" "$dec" 2>/dev/null || true)"
      [ "${h:-0}" -gt 0 ] && hit_cyr="${opath:-$osha}"
    fi
  done < <(git -C "$DIR" rev-list --objects "$@" 2>/dev/null \
           | git -C "$DIR" cat-file --batch-check='%(objecttype)|%(objectname)|%(objectsize)|%(rest)' 2>/dev/null)
  [ -n "$hit_home" ]  && warn "absolute home path in a binary blob in $label — e.g. $hit_home"
  [ -n "$hit_email" ] && warn "email in a binary blob in $label — e.g. $hit_email"
  [ -n "$hit_cyr" ]   && warn "Cyrillic text in a binary blob in $label — e.g. $hit_cyr"
  [ "$skipped" -gt 0 ] && warn "$skipped binary blob(s) over KEEL_AUDIT_BLOB_MAX (${max}B) skipped in $label — UN-audited; raise the cap to cover them"
  return 0
}

say "● public-audit ($DIR)"
[ "$is_git" = 1 ] || say "       (not a git repo — git-history checks skipped)"

for e in "${bad_allow_emails[@]:-}"; do
  [ -n "$e" ] && warn "ignoring invalid allow-email regex in .public-audit: $e"
done
[ "$bad_personal" -gt 0 ] && warn "ignoring $bad_personal invalid regex line(s) in $PERSONAL_FILE"
[ -n "$personal_re" ] && say "       (hunting the local secret-scan-personal literals as private tokens)"

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

# --- 2b. personal literals (local secret-scan-personal), in tree text (GAP) ----------------------
if [ -n "$personal_re" ]; then
  hit="$(git -C "$DIR" grep -inIE -- "$personal_re" -- . "${excludes[@]}" 2>/dev/null | head -1 || true)"
  [ -n "$hit" ] && gap "personal literal (secret-scan-personal) in tracked tree — e.g. $hit"
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
# Mirrored by secret-guard/secret-scan.sh SESSION_META (the preventive pre-push block) — keep in sync.
session_re='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'
sess_tree="$(tree_grep "$session_re" | head -1 || true)"
[ -n "$sess_tree" ] && warn "agent/session metadata in tracked tree — e.g. $sess_tree"
tag_msgs=""
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # annotated-tag message bodies, captured once for sections 4 and 5 — a tag's message is neither
  # a commit message nor a diff, so `git log` (any format) never shows it
  tag_msgs="$(git -C "$DIR" for-each-ref --format='%(contents)' refs/tags 2>/dev/null || true)"
  sess_msg="$( { git -C "$DIR" log --all --format='%B' 2>/dev/null;
                 printf '%s\n' "$tag_msgs"; } | grep -aE "$session_re" | head -1 || true)"
  [ -n "$sess_msg" ] && warn "agent/session metadata in a commit or tag message — e.g. $sess_msg"
fi

# --- 5. history content heuristics (WARN) --------------------------------------------------------
# Section 3 scans the working tree only — so personal data in a commit-message body or a historical
# diff (an added-then-removed blob) would pass clean. Scan history content (messages + diffs in one
# `git log -p` pass) with the SAME regexes; reuse EMAIL_RE/HOME_RE/safe_re/cyr_pat. WARN, not GAP.
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  # message bodies + diffs, AND annotated-tag message bodies (which `git log -p` omits).
  hist="$( { git -C "$DIR" log --all -p 2>/dev/null;
             printf '%s\n' "$tag_msgs"; } )"
  h="$(printf '%s\n' "$hist" | grep -nE "$HOME_RE" | head -1 || true)"
  [ -n "$h" ] && warn "absolute home path in git history — e.g. $h"
  h="$(printf '%s\n' "$hist" | grep -nIE "$EMAIL_RE" | grep -vE "$safe_re" | head -1 || true)"
  [ -n "$h" ] && warn "email in git history content — e.g. $h"
  h="$(printf '%s\n' "$hist" | LC_ALL=C grep -n "$cyr_pat" | head -1 || true)"
  [ -n "$h" ] && warn "Cyrillic text in git history — e.g. $h"
fi

# --- 5a. personal literals (local secret-scan-personal), in git history text (GAP) ----------------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ] && [ -n "$personal_re" ]; then
  h="$(printf '%s\n' "$hist" | grep -aniE -- "$personal_re" | head -1 || true)"
  [ -n "$h" ] && gap "personal literal (secret-scan-personal) in git history — e.g. $h"
fi

# --- 5b. binary blobs — the decoded scan of what sections 3/5 cannot see (tree + history) ---------
if [ "$is_git" = 1 ] && [ "$NO_HISTORY" = 0 ]; then
  scan_binary_blobs "git history" --all
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
    # Capture the first ref, don't gate on the pipeline status: under `pipefail`, `… | grep -q .`
    # makes ls-remote die with SIGPIPE on a busy remote (1000+ refs/pull/*), and the 141 would skip
    # the whole PR-ref scan for that remote. The captured-non-empty test can't be flipped by SIGPIPE.
    [ -n "$(git -C "$DIR" ls-remote --quiet "$remote" 'refs/pull/*' 2>/dev/null | head -n1)" ] || continue
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
        # Capture-then-test, not `grep -qE … && gap`: with a token that matches EARLY in a large
        # pr_hist, `printf | grep -q` SIGPIPEs printf, and `pipefail` makes the pipeline 141 — so the
        # `&& gap` never fires and a real leak passes clean. The captured hit can't be lost to SIGPIPE.
        if [ -n "$(printf '%s\n' "$pr_hist" | grep -E "$t" | head -n1 || true)" ]; then
          gap "private token /$t/ in a host PR ref (refs/pull/*) — purge via delete-and-recreate"
        fi
      done
    fi
    if [ -n "$personal_re" ]; then
      ph="$(printf '%s\n' "$pr_hist" | grep -aniE -- "$personal_re" | head -1 || true)"
      [ -n "$ph" ] && gap "personal literal (secret-scan-personal) in a host PR ref (refs/pull/*) — e.g. $ph"
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
    # Binary blobs a PR ref carries that local history does not. The exclusion must NOT be a bare
    # `--not --all`: --all includes the refs/keel-pr-audit/* temp refs themselves (fetched above), so
    # the include-set would be a subset of the exclude-set and the scan a silent no-op — --exclude
    # carves the temp namespace out of the --all that follows it. A leak in a closed PR's binary
    # fixture is exactly as recoverable as a text one.
    scan_binary_blobs "a host PR ref (refs/pull/*)" \
      --glob='refs/keel-pr-audit/*' --not --exclude='refs/keel-pr-audit/*' --all
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

# Impact instrumentation (metadata only, opt-in per repo): a GAP is a real publication blocker caught —
# record the guardrail fire so keel-impact can auto-ingest it (deterministic, zero-token). Only on GAP
# (exit 1), never on a clean run or advisory WARNs. Enabled via $KEEL_IMPACT_LOG or a .keel/ marker at the
# audited repo's top level (in a linked worktree: the MAIN checkout's top — the untracked marker isn't
# shared, so fall back to the first `git worktree list` entry, skipped when bare; awk reads its whole input on purpose — no
# early exit, no SIGPIPE); with neither, nothing is written.
if [ "$exit_code" != 0 ]; then
  _klog="${KEEL_IMPACT_LOG:-}"
  _kclaim=""
  if [ -z "$_klog" ]; then
    _ktop="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    # dir #74: the claim key is THIS site's own toplevel, captured here before the main-checkout fallback
    # below can overwrite $_ktop — that fallback only decides where the log FILE lives, not who fired the
    # event. Saving it now (instead of re-deriving it at the write site) avoids a second identical
    # `git rev-parse` subprocess for the same value.
    _kclaim="$_ktop"
    if [ -n "$_ktop" ] && [ ! -d "$_ktop/.keel" ]; then
      _kmain="$(git -C "$DIR" worktree list --porcelain 2>/dev/null |
        awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
      if [ -n "$_kmain" ] && [ -d "$_kmain/.keel" ]; then _ktop="$_kmain"; fi
    fi
    if [ -n "$_ktop" ] && [ -d "$_ktop/.keel" ]; then _klog="$_ktop/.keel/impact-events.log"; fi
  fi
  if [ -n "$_klog" ]; then
    # $KEEL_IMPACT_LOG was set explicitly, so the resolution block above (and $_kclaim with it) never ran
    # — compute it fresh here, the only remaining case that needs a subprocess for it.
    [ -n "$_kclaim" ] || _kclaim="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard public-audit blocked "$_kclaim" \
      >> "$_klog" 2>/dev/null || true
  fi
fi
exit "$exit_code"
