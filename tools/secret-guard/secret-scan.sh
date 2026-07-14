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
# NUL-strip pass (catches ASCII-range UTF-16/UTF-32 with no dependencies) plus iconv UTF-16 and UTF-32
# LE/BE when iconv is available (needed for non-ASCII literals, e.g. a Cyrillic name) plus a
# raw-printable pass — a real name inside a UTF-16/UTF-32 binary fixture is invisible to a plain-text grep.
#
# It does NOT catch passwords, opaque/custom tokens, or base64 blobs: it is a backstop to .gitignore +
# env vars, NOT a complete DLP. Mark that boundary honestly (P1).
#
# Usage:
#   secret-scan.sh                 scan staged changes (added/modified), for a pre-commit hook
#   secret-scan.sh --staged        same as the default, spelled out (for callers outside the hook)
#   secret-scan.sh --range A..B    scan a commit range — introduced blobs, the commits' messages
#                                  (agent/session-metadata trailers), and annotated-tag message
#                                  bodies, for a pre-push hook
#   secret-scan.sh --tracked       detective audit: scan ALL tracked content (doctor / periodic review)
#   secret-scan.sh --selftest      verify the scanner catches what it claims (end-to-end child runs)
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
  'gh[oprsu]_[A-Za-z0-9]{36}'           # GitHub token — PAT ghp_, OAuth gho_, user ghu_, server ghs_, refresh ghr_
  'github_pat_[A-Za-z0-9_]{60,}'        # GitHub fine-grained PAT
  'AKIA[0-9A-Z]{16}'                    # AWS access key id
  'AIza[0-9A-Za-z_-]{35}'              # Google API key
  'sk-ant-[A-Za-z0-9_-]{20,}'          # Anthropic API key
  'sk-proj-[A-Za-z0-9_-]{20,}'         # OpenAI project key (the hyphen breaks the generic sk- rule)
  'sk-svcacct-[A-Za-z0-9_-]{20,}'      # OpenAI service-account key
  'sk-[A-Za-z0-9]{32,}'                # generic "sk-" secret key
  'sk_(live|test)_[A-Za-z0-9]{16,}'    # Stripe secret key (underscore form)
  'glpat-[A-Za-z0-9_-]{20,}'           # GitLab personal access token
  'npm_[A-Za-z0-9]{36}'                # npm access token
  'hf_[A-Za-z0-9]{34,}'                # Hugging Face user access token
  'xox[baprs]-[A-Za-z0-9-]{10,}'       # Slack token
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'  # PEM private key
)

# Agent/session metadata in COMMIT and annotated-TAG MESSAGES — the per-session trailer an agent
# harness appends (a `Claude-Session` line with its session URL). Scanned by --range only: a
# message is not a blob, so no content pass above can see it, and the push is where it becomes
# effectively unpurgeable (a protected public history needs a rewrite). Mirrors public-audit.sh
# session_re — keep the two in sync.
SESSION_META='([A-Za-z][A-Za-z0-9-]*-Session:|claude\.ai/code/session)'

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

# fast-path hit count for one spooled scan FILE — the shared shape of every --range pre-check (blob
# stream, commit messages, tag bodies). ONE case-sensitive grep over class 1 (key shapes, optionally
# OR'd with an extra ERE like $SESSION_META for messages); only if that is clean, ONE case-insensitive
# grep over class 2 (personal literals). `grep -c` (count), NEVER `-q`: -q exits on the first match and
# SIGPIPEs the still-writing producer, which under `pipefail` reads as failure and drops the hit — a
# real intermittent scanner hole (flaked on macOS CI). -c consumes the whole stream → deterministic.
# Prints the count on stdout.
count_matches() {  # $1 = file, $2 = extra case-sensitive ERE OR'd into class 1 ('' for none)
  local f="$1" extra="${2:-}" n
  n="$(grep -acE "${extra:+$extra|}$joined" "$f" || true)"
  if [ "${n:-0}" -eq 0 ] && [ -n "$personal" ]; then
    n="$(grep -aciE "$personal" "$f" || true)"
  fi
  printf '%s' "${n:-0}"
}

# decode binary bytes on stdin (NUL-strip + optional iconv UTF-16LE/BE + raw-printable), match both
# classes, and emit "label:(binary) MATCH" records. The decode recipe is deliberately duplicated in
# public-audit.sh scan_binary_blobs() (each tool stands alone) — keep the two in sync.
emit_blob() {  # $1 = record label (path)
  local label="$1" tmp dec hits
  tmp="$(mktemp "$SCRATCH/blob.XXXXXX")"; dec="$(mktemp "$SCRATCH/blob.XXXXXX")"
  cat > "$tmp"
  {
    LC_ALL=C tr -d '\000' < "$tmp"; echo                          # ASCII-range UTF-16, no deps
    if command -v iconv >/dev/null 2>&1; then                     # non-ASCII UTF-16/UTF-32 (e.g. a Cyrillic name)
      iconv -f UTF-16LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      iconv -f UTF-16BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      # UTF-32: an ASCII literal survives the NUL-strip pass above (3-of-4 bytes are NUL), but a
      # NON-ASCII one (multi-byte code point) does not — decode it explicitly, symmetric with UTF-16.
      iconv -f UTF-32LE -t UTF-8 "$tmp" 2>/dev/null || true; echo
      iconv -f UTF-32BE -t UTF-8 "$tmp" 2>/dev/null || true; echo
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

# an annotated tag's message body — everything after the first blank line of the raw tag object
tag_body() { git cat-file tag "$1" 2>/dev/null | sed '1,/^$/d'; }

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

# selftest — end-to-end verification via child runs of this same script in FILE mode, from a neutral
# cwd (so a repo's .secret-scan-allow can't mask a probe) with a fixture personal file. A guard you
# can't verify degrades silently — this is the check install/bootstrap scripts run after wiring.
selftest() {
  local script dir rc=0 fake greprc trailer mrepo trepo
  # BASH_SOURCE, not $0: resolves the script's real location even when invoked as `bash secret-scan.sh`
  # from another cwd — a selftest that can't find itself would fail for the wrong reason.
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  dir="$SCRATCH/selftest"; mkdir -p "$dir"
  # %.0s prints zero chars of each of the 36 args → 'a' repeated 36 times, built at runtime so the
  # literal token body never sits in this file (the scanner must not trip on its own source).
  fake="ghp_$(printf 'a%.0s' {1..36})"
  printf 'SeekritPersonName\n' > "$dir/personal"

  probe() {  # $1 = expected exit, $2 = label, $3 = personal file, $4 = fixture path
    local want="$1" label="$2" pfile="$3" fixture="$4" got=0
    (cd "$dir" && KEEL_IMPACT_LOG='' SECRET_SCAN_PERSONAL_FILE="$pfile" "$script" "$fixture" >/dev/null 2>&1) || got=$?
    if [ "$got" -eq "$want" ]; then
      echo "selftest: OK   — $label"
    else
      echo "selftest: FAIL — $label (exit $got, want $want)" >&2; rc=1
    fi
  }

  printf '%s\n' "$fake" > "$dir/key.txt"
  probe 1 "caught a key-shaped string" /dev/null "$dir/key.txt"
  printf 'docs reference ghp_[A-Za-z0-9]{36} and sk-ant-[A-Za-z0-9_-]{20,}\n' > "$dir/doc.txt"
  probe 0 "ignored the anchored pattern doc (no self-match)" /dev/null "$dir/doc.txt"
  printf '%s secret-scan:allow\n' "$fake" > "$dir/allowed.txt"
  probe 0 "honored the inline allow pragma" /dev/null "$dir/allowed.txt"
  printf 'author: seekritpersonname\n' > "$dir/pers.txt"
  probe 1 "caught a personal literal in text (case-insensitive)" "$dir/personal" "$dir/pers.txt"
  # The fail-closed probe holds only where grep itself signals a malformed ERE (exit >= 2); a
  # lenient minimal grep (busybox) can't distinguish "bad pattern" from "no match" — WARN honestly
  # there instead of failing the whole selftest on an otherwise-working host.
  greprc=0; printf '' | grep -iE 'unbalanced(paren' >/dev/null 2>&1 || greprc=$?
  if [ "$greprc" -ge 2 ]; then
    printf 'unbalanced(paren\n' > "$dir/badre"
    printf 'anything\n' > "$dir/any.txt"
    probe 2 "malformed personal regex fails CLOSED (config error, not a silent pass)" "$dir/badre" "$dir/any.txt"
  else
    echo "selftest: WARN — this grep does not flag a malformed ERE; the fail-closed guard is a no-op on this host" >&2
  fi
  if command -v iconv >/dev/null 2>&1; then
    printf 'lead-in SeekritPersonName trail' | iconv -f UTF-8 -t UTF-16LE > "$dir/fixture.bin"
    probe 1 "caught a personal literal inside a UTF-16LE blob" "$dir/personal" "$dir/fixture.bin"
    # UTF-32 with a NON-ASCII literal: a Cyrillic name (built from bytes so this source stays ASCII)
    # survives ONLY via the iconv UTF-32 pass — its multi-byte code points are garbage after NUL-strip.
    cyr="$(printf '\320\230\320\262\320\260\320\275')"           # "Ivan" (Cyrillic) in UTF-8
    # Guard on the UTF-32 converter specifically (some minimal iconv builds have UTF-16 but not
    # UTF-32) — otherwise the encode silently yields an empty fixture and the probe FAILs falsely.
    if printf '%s' "$cyr" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
      printf '%s\n' "$cyr" > "$dir/personal32"
      printf 'lead %s trail' "$cyr" | iconv -f UTF-8 -t UTF-32LE > "$dir/fixture32.bin"
      probe 1 "caught a non-ASCII personal literal inside a UTF-32LE blob" "$dir/personal32" "$dir/fixture32.bin"
    else
      echo "selftest: WARN — iconv lacks a UTF-32 converter; the UTF-32 pass is degraded on this host" >&2
    fi
  else
    echo "selftest: WARN — iconv absent; the non-ASCII UTF-16/UTF-32 passes are degraded on this host" >&2
  fi
  # a session trailer in a pushed commit MESSAGE and in an annotated TAG message (neither is a
  # blob — only the --range message/tag passes see them). The trailer is built by printf so this
  # source never holds the literal. --template= + --no-verify + explicit -c identity: a probe repo
  # must not depend on host hooks/config (--no-verify alone leaves a template-installed
  # prepare-commit-msg hook running) — the recipe lives once, shared by both probes.
  trailer="$(printf 'Claude-%s: https://claude.ai/code/%s_selftest' Session session)"
  probe_repo() {  # $1 = dir, $2 = optional second -m paragraph for the probe commit
    git init -q --template= "$1" 2>/dev/null || return 1
    if [ -n "${2:-}" ]; then
      git -C "$1" -c user.name=keel -c user.email=keel@keel.invalid -c commit.gpgsign=false \
        commit -q --no-verify --allow-empty -m probe -m "$2" 2>/dev/null
    else
      git -C "$1" -c user.name=keel -c user.email=keel@keel.invalid -c commit.gpgsign=false \
        commit -q --no-verify --allow-empty -m probe 2>/dev/null
    fi
  }
  range_probe() {  # $1 = repo, $2 = rev to push-scan, $3 = label — expects the scan to BLOCK
    local got=0
    (cd "$1" && KEEL_IMPACT_LOG='' SECRET_SCAN_PERSONAL_FILE=/dev/null \
       "$script" --range "$2 --not --remotes" >/dev/null 2>&1) || got=$?
    if [ "$got" -eq 1 ]; then
      echo "selftest: OK   — $3"
    else
      echo "selftest: FAIL — $3 (exit $got, want 1)" >&2; rc=1
    fi
  }
  mrepo="$dir/msgrepo"
  if probe_repo "$mrepo" "$trailer"; then
    range_probe "$mrepo" HEAD "caught a session trailer in a pushed commit message"
  else
    echo "selftest: WARN — could not create the message-probe repo; the commit-message pass is unverified on this host" >&2
  fi
  # the tag probe's commit is CLEAN, so a hit can only come from the tag body
  trepo="$dir/tagrepo"
  if probe_repo "$trepo" \
     && git -C "$trepo" -c user.name=keel -c user.email=keel@keel.invalid -c tag.gpgsign=false \
          tag -a probe-tag -m "$(printf 'release\n\n%s' "$trailer")" 2>/dev/null; then
    range_probe "$trepo" probe-tag "caught a session trailer in a pushed annotated-tag message"
  else
    echo "selftest: WARN — could not create the tag-probe repo; the tag-message pass is unverified on this host" >&2
  fi
  return $rc
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
    objs="$(git rev-list --objects $rng 2>/dev/null \
              | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' 2>/dev/null || true)"
    blobs="$(printf '%s\n' "$objs" | awk '$1=="blob"')"
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
          range_hits="$(count_matches "$rtmp")"
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
    # The push also introduces the commits' MESSAGES, which no blob pass sees. Felt (2026-07-10
    # audit): seven harness-appended session trailers reached the public main through merged PRs,
    # visible afterwards only as a post-hoc audit WARN. Scan the messages against ALL THREE classes
    # (key shapes + personal literals + session metadata) — a key or a personal literal pasted into
    # a commit message ships to the remote just as unpurgeably as a session trailer, and the tag
    # pass below already scans all three; a commit message must not be the weaker sibling. Same
    # fast-path shape as the blob/tag scans (`count_matches`, `-c` not `-q`), then re-walk per
    # commit on a hit to attribute the exact sha.
    # shellcheck disable=SC2086  # rng intentionally word-split into rev-list args
    msgtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
    git log --format=%B $rng > "$msgtmp" 2>/dev/null || true
    if [ "$(count_matches "$msgtmp" "$SESSION_META")" -gt 0 ]; then
      while IFS= read -r csha; do
        [ -n "$csha" ] || continue
        ctmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
        git log -1 --format=%B "$csha" > "$ctmp" 2>/dev/null || true
        while IFS= read -r hit; do
          [ -n "$hit" ] && records+="commit ${csha:0:7} message:$hit"$'\n'
        done < <({ match_text '' "$ctmp"
                   grep -aE "$SESSION_META" "$ctmp" 2>/dev/null || true; } | LC_ALL=C sort -u)
        rm -f "$ctmp"
      done < <(git rev-list $rng 2>/dev/null || true)
    fi
    rm -f "$msgtmp"
    # An annotated TAG's own message is neither a blob nor a commit message, so both passes above
    # are blind to it — a pushed tag (pre-push passes "<tagsha> --not --remotes") would carry a
    # key, a personal literal, or a session trailer to the remote unscanned. The tag objects are
    # already in the batch-check stream captured above; scan each tag's message body against all
    # three matchers via the same `count_matches` fast-path shared with the blob/commit passes.
    tagshas="$(printf '%s\n' "$objs" | awk '$1=="tag"{print $2}')"
    if [ -n "$tagshas" ]; then
      tagtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
      while IFS= read -r tsha; do
        [ -n "$tsha" ] || continue
        tag_body "$tsha"
      done <<< "$tagshas" > "$tagtmp"
      tag_hits="$(count_matches "$tagtmp" "$SESSION_META")"
      rm -f "$tagtmp"
      if [ "${tag_hits:-0}" -gt 0 ]; then
        while IFS= read -r tsha; do
          [ -n "$tsha" ] || continue
          tagtmp="$(mktemp "$SCRATCH/blob.XXXXXX")"
          tag_body "$tsha" > "$tagtmp"
          while IFS= read -r hit; do
            [ -n "$hit" ] && records+="tag ${tsha:0:7} message:$hit"$'\n'
          done < <({ match_text '' "$tagtmp"
                     grep -aE "$SESSION_META" "$tagtmp" 2>/dev/null || true; } | LC_ALL=C sort -u)
          rm -f "$tagtmp"
        done <<< "$tagshas"
      fi
    fi
    ;;
  staged|--staged|"")
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
  --tracked)
    # Detective audit: scan ALL tracked content as it sits in the working tree — text with line
    # numbers, binaries through the decode pass. For a periodic review / doctor run, not a hook
    # (it is O(repo), not O(change)). Anchored to the repo root so a subdirectory invocation can
    # never silently audit only that subtree; the allowlist is the root one for the same reason.
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "secret-scan: --tracked needs a git repo" >&2; exit 2; }
    ALLOW_FILE="$top/.secret-scan-allow"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -L "$top/$f" ]; then
        # a tracked symlink's committed content IS its target string — scan that (it can carry a
        # personal path); the target file itself, if tracked, is scanned as its own entry
        emit_stream "$f" < <(readlink "$top/$f")
      elif [ -f "$top/$f" ]; then
        if [ -r "$top/$f" ]; then
          emit_stream "$f" < "$top/$f"
        else
          # skip-and-warn, never abort: one unreadable file must not void the rest of the audit
          echo "secret-scan: WARN unreadable, skipped: $f" >&2
        fi
      fi
    done < <(git -C "$top" -c core.quotePath=false ls-files 2>/dev/null)
    ;;
  --selftest)
    selftest; exit $?
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
  # Impact instrumentation (metadata only, opt-in per repo): record that a guardrail fired so keel-impact
  # can auto-ingest it — a deterministic, zero-token signal. NEVER the matched secret; only the fact of a
  # block. Enabled either explicitly ($KEEL_IMPACT_LOG) or per repo by a .keel/ marker at its top level
  # (in a linked worktree: the MAIN checkout's top — the untracked marker isn't shared, so fall back to
  # the first `git worktree list` entry, skipped when bare; awk reads its whole input on purpose — no early exit, no
  # SIGPIPE); with neither, nothing is written and the hook's behaviour is unchanged.
  _klog="${KEEL_IMPACT_LOG:-}"
  if [ -z "$_klog" ]; then
    _ktop="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$_ktop" ] && [ ! -d "$_ktop/.keel" ]; then
      _kmain="$(git worktree list --porcelain 2>/dev/null |
        awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
      if [ -n "$_kmain" ] && [ -d "$_kmain/.keel" ]; then _ktop="$_kmain"; fi
    fi
    if [ -n "$_ktop" ] && [ -d "$_ktop/.keel" ]; then _klog="$_ktop/.keel/impact-events.log"; fi
  fi
  if [ -n "$_klog" ]; then
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" guard secret-guard blocked \
      >> "$_klog" 2>/dev/null || true
  fi
  echo "" >&2
  # Say WHAT to do (remove the secret), not HOW to bypass the check: the exact allowlist syntax is
  # deliberately kept OUT of this block message so an agent optimizing to get unblocked can't follow it as
  # a recipe (an agent under test on Cursor did exactly that). A genuine fixture is a human, out-of-band
  # decision — the mechanism is documented in this script's header. See FRAMEWORK.md "Enforcement mechanics".
  echo "This looks like a real secret — remove it (use an env var or a secret manager), then re-commit." >&2
  echo "A genuine test fixture is a rare exception a human allowlists deliberately (see this script's header); an agent must NOT add an allowlist entry just to get a commit through." >&2
  echo "Operator-specific literals live in the local, never-committed \$SECRET_SCAN_PERSONAL_FILE." >&2
  exit 1
fi

echo "secret-scan: clean"
exit 0
