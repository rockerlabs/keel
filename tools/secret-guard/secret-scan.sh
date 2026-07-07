#!/usr/bin/env bash
# secret-scan — backstop scanner for key-shaped secrets and personal data.
#
# TWO detector classes:
#   1. key-SHAPED secrets — length-anchored patterns (a known prefix + a long body), case-SENSITIVE:
#      exactly what bots scrape repos for. Length anchoring means a bare prefix or this pattern list
#      itself never trips.
#   2. personal data — operator-specific literals (real name, device serials, personal drive labels,
#      personal emails) loaded as EREs, matched case-INSENSITIVELY, from a LOCAL file that is never
#      committed:
#        default path: ~/.claude/secret-scan-personal   (override with $SECRET_SCAN_PERSONAL_FILE)
#        one ERE per line; blank lines and `# comments` ignored; absent file → only class 1 runs.
#      Put ONLY literals that must never appear in ANY repo. Do NOT list your bare home username —
#      it is a legitimate path component in a private knowledge base and would flag every home-path
#      reference. Starter: tools/secret-guard/secret-scan-personal.example
#
# Both classes are scanned over text AND over BINARY content: binary files/blobs are decoded via a
# NUL-strip pass (catches ASCII-range UTF-16 with no dependencies) plus iconv UTF-16LE/BE when iconv
# is available (needed for non-ASCII literals, e.g. a Cyrillic name) plus a raw-printable pass — a
# real name inside a UTF-16 binary fixture is invisible to a plain-text grep.
#
# It does NOT catch passwords, opaque/custom tokens, or base64 blobs: it is a backstop to .gitignore +
# env vars, NOT a complete DLP. Mark that boundary honestly (P1).
#
# Usage:
#   secret-scan.sh                 scan staged changes (added/modified), for a pre-commit hook
#   secret-scan.sh --range A..B    scan the diff of a commit range, for a pre-push hook
#   secret-scan.sh FILE...         scan specific files
#
# Allowlist (for legit fixtures/example keys — be deliberate, real keys hide in tests too):
#   a repo-root .secret-scan-allow file:
#     <ERE>          drop any matched line from results
#     path:<glob>    exclude a path
#   or an inline  secret-scan:allow  comment on the offending line.
#
# Exit 0 = clean; 1 = a secret-shaped string or personal data found; 2 = usage/config error.

set -euo pipefail

# Length-anchored patterns: a bare prefix or this pattern list itself never trips them.
PATTERNS=(
  'ghp_[A-Za-z0-9]{36}'                 # GitHub personal access token
  'github_pat_[A-Za-z0-9_]{60,}'        # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                    # AWS access key id
  'AIza[0-9A-Za-z_-]{35}'              # Google API key
  'sk-ant-[A-Za-z0-9_-]{20,}'          # Anthropic API key
  'sk-proj-[A-Za-z0-9_-]{20,}'         # OpenAI project key (the hyphen breaks the generic sk- rule)
  'sk-svcacct-[A-Za-z0-9_-]{20,}'      # OpenAI service-account key
  'sk-[A-Za-z0-9]{32,}'                # generic "sk-" secret key
  'sk_(live|test)_[A-Za-z0-9]{16,}'    # Stripe secret key (underscore form)
  'glpat-[A-Za-z0-9_-]{20,}'           # GitLab personal access token
  'xox[baprs]-[A-Za-z0-9-]{10,}'       # Slack token
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key
)

ALLOW_FILE=".secret-scan-allow"
PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"

# All temp files live in one scratch dir, removed on ANY exit (set -e failures, Ctrl-C, TERM) —
# a hook that runs on every commit must not litter $TMPDIR with orphans.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Build a combined regex (class 1, case-sensitive).
joined=""
for p in "${PATTERNS[@]}"; do
  joined="${joined:+$joined|}$p"
done

# Class 2: operator literals from the local personal file (case-insensitive).
personal=""
if [ -f "$PERSONAL_FILE" ]; then
  while IFS= read -r _t || [ -n "$_t" ]; do
    _t="${_t%$'\r'}"                                              # tolerate CRLF
    # BRE on purpose — the repo's sed usage stays POSIX-portable (busybox included), no -E
    _t="$(printf '%s' "$_t" | sed 's/[[:space:]][[:space:]]*#.*$//; s/^[[:space:]][[:space:]]*//; s/[[:space:]][[:space:]]*$//')"
    case "$_t" in
      ''|\#*) ;;
      *)      personal="${personal:+$personal|}$_t" ;;
    esac
  done < "$PERSONAL_FILE"
fi
# Fail CLOSED on a broken personal regex: a malformed ERE would make every personal grep exit 2,
# which reads as "no match" and would silently disable personal-data detection — a security gate
# must never fail open on its own config. grep exits >=2 only on a bad pattern; 1 (no match) is fine.
if [ -n "$personal" ]; then
  rc=0; printf '' | grep -iE "$personal" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ge 2 ]; then
    echo "secret-scan: invalid regex in $PERSONAL_FILE — personal-data detection would be" >&2
    echo "silently disabled. Fix the offending line (each line is an ERE)." >&2
    exit 2
  fi
fi

# --- gather the lines to scan as "path:line" records ---------------------------------------------------
records=""

# a file (or blob) is binary if it contains a NUL byte
is_binary_file() { ! LC_ALL=C tr -d '\000' < "$1" 2>/dev/null | cmp -s - "$1"; }

# match a text FILE against both classes; optional extra grep flag (e.g. -n) via $1
match_text() {  # $1 = extra grep flags ('' for none), $2 = file to scan
  local flags="$1" f="$2"
  {
    # shellcheck disable=SC2086  # $flags intentionally word-split ('' → no extra flag)
    grep -aE $flags "$joined" "$f" 2>/dev/null || true
    if [ -n "$personal" ]; then
      # shellcheck disable=SC2086
      grep -aiE $flags "$personal" "$f" 2>/dev/null || true
    fi
  } | LC_ALL=C sort -u
}

# decode binary bytes on stdin (NUL-strip + optional iconv UTF-16LE/BE + raw-printable), match both
# classes, and emit "label:(binary) MATCH" records
emit_blob() {  # $1 = record label (path)
  local label="$1" tmp dec hits
  tmp="$(mktemp "$SCRATCH/blob.XXXXXX")"; dec="$(mktemp "$SCRATCH/blob.XXXXXX")"
  cat > "$tmp"
  {
    LC_ALL=C tr -d '\000' < "$tmp"; echo                          # ASCII-range UTF-16, no deps
    if command -v iconv >/dev/null 2>&1; then                     # non-ASCII UTF-16 (e.g. a Cyrillic name)
      iconv -f UTF-16LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      iconv -f UTF-16BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
    fi
    LC_ALL=C tr -c '[:print:]\t\n' '\n' < "$tmp"; echo            # raw printable runs
  } > "$dec"
  hits="$( { grep -aoE "$joined" "$dec" 2>/dev/null || true
             if [ -n "$personal" ]; then grep -aoiE "$personal" "$dec" 2>/dev/null || true; fi
           } | LC_ALL=C sort -u )"
  rm -f "$tmp" "$dec"
  [ -z "$hits" ] && return 0
  while IFS= read -r hit; do
    [ -n "$hit" ] && records+="$label:(binary) $hit"$'\n'
  done <<< "$hits"
}

# route one unit of content (stdin) by type: binary → the decode pass, text → line matching with
# line numbers. Spools stdin to a temp file; callers must feed it via redirection or process
# substitution (NOT a pipe) so the records+= appends run in this shell.
emit_stream() {  # $1 = record label (path)
  local label="$1" stmp
  stmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
  cat > "$stmp"
  if is_binary_file "$stmp"; then
    emit_blob "$label" < "$stmp"
  else
    while IFS= read -r line; do
      records+="$label:$line"$'\n'
    done < <(match_text -n "$stmp")
  fi
  rm -f "$stmp"
}

# scan the added lines of one file's diff, emitting path-aware "path:content" records. No line number:
# the diff has already been reduced to a bare added-lines stream, so `grep -n` would number that stream,
# not the file — a misleading figure. The path + matched content is what's actionable.
emit_diff() {
  local path="$1"; shift   # remaining args = git diff args
  local dtmp
  dtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
  git diff "$@" --unified=0 --no-color -- "$path" 2>/dev/null \
    | grep -E '^\+' | grep -vE '^\+\+\+' \
    | sed 's/^\+//' > "$dtmp" || true
  while IFS= read -r hit; do
    records+="$path:$hit"$'\n'
  done < <(match_text '' "$dtmp")
  rm -f "$dtmp"
}

mode="${1:-staged}"
case "$mode" in
  --range)
    shift
    rng="${1:?--range needs A..B}"
    # Scan every blob the push would INTRODUCE (objects reachable in the range), not the net endpoint
    # diff: a secret added in one pushed commit and removed in a later one is absent from both endpoint
    # trees yet its blob still ships and stays recoverable — `git diff A..B` would miss it. rng is a
    # commit range (A..B) or rev-list args (a first push passes "<tip> --not --remotes"), so the
    # word-split is intentional. Blobs already on the far side are excluded → only what's being pushed.
    #
    # Fast path (the common case — a clean push): stream ALL introduced blob contents through ONE grep
    # per class. If nothing matches we stop here, paying O(1) processes regardless of blob count. Only
    # on a hit do we re-scan per blob for the exact path/line. The stream is NUL-stripped so a literal
    # inside an ASCII-range UTF-16 binary is visible to the fast check too.
    #
    # `grep -c` (count), NOT `grep -q`: -q exits on the first match, the still-writing `git cat-file`
    # takes SIGPIPE (141), and under `pipefail` the whole pipeline reads as failed — the hit is thrown
    # away and the push scans CLEAN. That was a real intermittent scanner hole (flaked on macOS CI,
    # buffer/timing-dependent). -c consumes the whole stream, so the status is deterministic.
    # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
    blobs="$(git rev-list --objects $rng 2>/dev/null \
              | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' 2>/dev/null \
              | awk '$1=="blob"' || true)"
    range_hits=1                                    # default: run the detailed scan
    if [ -z "$blobs" ]; then
      range_hits=0
    else
      case "$personal" in
        *[![:ascii:]]*) ;;  # a non-ASCII personal literal (e.g. a Cyrillic name) is invisible to
                            # the NUL-strip fast view of UTF-16 bytes — skip the fast path and let
                            # the detailed scan's iconv pass see it
        *)
          rtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
          printf '%s\n' "$blobs" | awk '{print $2}' \
            | git cat-file --batch 2>/dev/null | LC_ALL=C tr -d '\000' > "$rtmp"
          range_hits="$(grep -acE "$joined" "$rtmp" || true)"
          if [ "${range_hits:-0}" -eq 0 ] && [ -n "$personal" ]; then
            range_hits="$(grep -aciE "$personal" "$rtmp" || true)"
          fi
          rm -f "$rtmp"
          ;;
      esac
    fi
    if [ "${range_hits:-0}" -gt 0 ]; then
      while IFS=' ' read -r _otype osha opath; do
        [ -n "$osha" ] || continue
        emit_stream "$opath" < <(git cat-file blob "$osha" 2>/dev/null)
      done <<< "$blobs"
    fi
    ;;
  staged|"")
    while IFS= read -r f; do
      [ -n "$f" ] && emit_diff "$f" --cached
    done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
    # binary staged files have no text diff (numstat shows "- -") — decode and scan their staged blobs
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      emit_stream "$f" < <(git show ":$f" 2>/dev/null)
    done < <(git -c core.quotePath=false diff --cached --numstat --diff-filter=ACM 2>/dev/null \
             | awk -F'\t' '$1=="-" && $2=="-"{print $3}')
    ;;
  -*)
    echo "secret-scan: unknown option '$mode'" >&2; exit 2
    ;;
  *)
    for f in "$@"; do
      [ -f "$f" ] || { echo "secret-scan: no such file: $f" >&2; exit 2; }
      emit_stream "$f" < "$f"
    done
    ;;
esac

[ -n "$records" ] || { echo "secret-scan: clean"; exit 0; }

# --- apply the allowlist ------------------------------------------------------------------------------
drop_res=()
path_globs=()
if [ -f "$ALLOW_FILE" ]; then
  while IFS= read -r entry; do
    entry="${entry%$'\r'}"                 # tolerate a CRLF-saved allowlist (strip trailing CR)
    [ -z "$entry" ] && continue
    case "$entry" in
      \#*) ;;                              # comment
      path:*) path_globs+=("${entry#path:}") ;;
      *) drop_res+=("$entry") ;;
    esac
  done < "$ALLOW_FILE"
fi

found=0
while IFS= read -r rec; do
  [ -z "$rec" ] && continue
  # inline allow
  case "$rec" in *secret-scan:allow*) continue ;; esac
  # ERE allowlist
  skip=0
  for re in "${drop_res[@]:-}"; do
    [ -z "$re" ] && continue
    if printf '%s' "$rec" | grep -qE "$re"; then skip=1; break; fi
  done
  [ "$skip" = 1 ] && continue
  # path-glob allowlist (only meaningful for "path:line" records)
  recpath="${rec%%:*}"
  for g in "${path_globs[@]:-}"; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2053
    if [[ "$recpath" == $g ]]; then skip=1; break; fi
  done
  [ "$skip" = 1 ] && continue

  if [ "$found" = 0 ]; then
    echo "secret-scan: BLOCKED — secret-shaped string(s) or personal data detected:" >&2
    found=1
  fi
  echo "  $rec" >&2
done <<< "$records"

if [ "$found" = 1 ]; then
  echo "" >&2
  echo "If this is a legit fixture, add it to $ALLOW_FILE or an inline 'secret-scan:allow' — don't weaken the scanner." >&2
  echo "Operator-specific literals live in the local, never-committed \$SECRET_SCAN_PERSONAL_FILE." >&2
  exit 1
fi

echo "secret-scan: clean"
exit 0
