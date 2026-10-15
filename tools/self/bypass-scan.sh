#!/usr/bin/env bash
# tools/self/bypass-scan.sh — keel-self-maintenance (dir #842 B11; dir #68: never installed by install.sh): the sensor of
# the guards' known-bypass registers. A register entry counts as a sighting only when a real session wrote the shape, and
# nothing else reads session transcripts for it. This tool reads Claude Code's transcripts, matches each Bash command
# against the shape table tools/self/known-bypass-shapes.tsv, and lists the CANDIDATES per class and per parent session
# into a scratch file. It adds nothing to the accumulator: a pattern cannot tell a construction from real work, so every
# candidate is adjudicated by the session running the scan (docs/grooming.md G0) — a probe, an audit, a fixture, a sandbox
# setup or a scratch target is dropped, and a real session that wrote the guarded action against its real target, by the
# right actor, becomes one `accumulate.sh add`.
#
# PERSONAL DATA: the candidate file holds commands from the operator's sessions. It is written outside every repository
# (the tool refuses a path inside a git work tree or inside this checkout) and is deleted after adjudication; nothing from
# it goes into a tracked file, a PR body or a ticket — counts only. The tool's stdout carries counts, never command text.
#
# Sessions: a transcript is <projects>/<project>/<session-uuid>.jsonl; a subagent's is
# <projects>/<project>/<parent-uuid>/subagents/agent-<id>.jsonl, its lines carrying isSidechain true and the PARENT's
# sessionId. A candidate is keyed by the line's sessionId (the file's own name when a line has none), so one parent and its
# subagents are ONE session, as the accumulator counts them (a source is `session:<parent-uuid>`).
#
# Usage:
#   bypass-scan.sh scan [--transcripts DIR] [--shapes FILE] [--since D | --days N] [--as-of D] [--out FILE]
#       lists candidates for every class of the shape table; --since/--days bound the lines by date (default: the 90-day
#       window up to --as-of, today by default); a re-scan is harmless, the accumulator ignores a duplicate (class,
#       session, consumer). --out defaults to a fresh file under ${TMPDIR:-/tmp}. Exit 0 ok, 2 a usage or I/O error.
#   bypass-scan.sh classes [--shapes FILE]
#       prints one `accumulate.sh --dir <data dir> new-class …` command per class (owner guards, threshold 2, window 90,
#       counts felt) — the operator-machine half of dir #842 slice 4; it runs nothing.
#   bypass-scan.sh data-dir        prints the guards' accumulator data dir ($KEEL_GUARDS_ACCUM_DIR, else
#                                  $HOME/.keel/guards-accumulator — outside every repository, never committed).
#   bypass-scan.sh -h | --help
# Environment: KEEL_TRANSCRIPTS_DIR (default $HOME/.claude/projects), KEEL_GUARDS_ACCUM_DIR. Needs jq.
set -u
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$self_dir/../.." && pwd -P)"
DEFAULT_SHAPES="$self_dir/known-bypass-shapes.tsv"
WINDOW_DAYS=90          # B11: the guards' window; the scan's default look-back
THRESHOLD=2
EXAMPLES_PER_SESSION=5  # candidate lines kept per (class, session); the rest are counted
COMMAND_CAP=400         # characters of a command kept in a candidate line

# The macros a pattern may use. {PUSH}: a `git … push`; {PR}: a `gh pr create`; {ACT}: either; {ACTAT}: either at a
# command position.
M_PUSH='git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*push'
M_PR='gh[[:space:]]+pr[[:space:]]+create'
M_ACT="($M_PUSH|$M_PR)"
M_ACTAT="(^|[;&|(])[[:space:]]*$M_ACT"

die() { printf 'bypass-scan: %s\n' "$*" >&2; exit 2; }

usage() { sed -n '/^# Usage:/,/^# Environment:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

valid_date() {
  LC_ALL=C awk -v d="$1" 'BEGIN {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    dim = substr("312831303130313130313031", (m - 1) * 2 + 1, 2) + 0
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) dim = 29
    exit !(m >= 1 && m <= 12 && dd >= 1 && dd <= dim) }'
}

# date_minus D N — the ISO date N days before D (days-from-civil arithmetic; no `date` flavour involved).
date_minus() {
  LC_ALL=C awk -v d="$1" -v n="$2" 'BEGIN {
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m <= 2) y -= 1
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
    z = era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - n
    era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153); dd = doy - int((153 * mp + 2) / 5) + 1
    m = mp < 10 ? mp + 3 : mp - 9; if (m <= 2) y += 1
    printf "%04d-%02d-%02d\n", y, m, dd }'
}

data_dir() { printf '%s\n' "${KEEL_GUARDS_ACCUM_DIR:-$HOME/.keel/guards-accumulator}"; }

# shape_rows FILE — the data rows (class, register, pattern, actor), the comment lines and the header dropped; each
# pattern's macros expanded. Prints US-free tab rows; exits 2 on a malformed row.
shape_rows() {
  local file="$1" cls reg pat actor header=1 line
  [ -f "$file" ] || die "shape table $file does not exist"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    if [ "$header" = 1 ]; then header=0; continue; fi
    IFS=$'\t' read -r cls reg pat actor <<<"$line"
    [[ "$cls" =~ ^[a-z0-9:-]+$ ]] || die "shape table: bad class id '$cls'"
    [ -n "$reg" ] && [ -n "$pat" ] || die "shape table: class $cls has an empty column"
    case "$actor" in any|subagent) ;; *) die "shape table: class $cls has actor '$actor' (any|subagent)" ;; esac
    pat="${pat//\{ACTAT\}/$M_ACTAT}"; pat="${pat//\{ACT\}/$M_ACT}"; pat="${pat//\{PUSH\}/$M_PUSH}"; pat="${pat//\{PR\}/$M_PR}"
    # busybox awk accepts an unbalanced pattern silently, so the syntax is also checked by the shell's own ERE (regcomp
    # status 2 = a syntax error); an awk that does reject it is caught by the second check.
    [[ "" =~ $pat ]]; [ $? -le 1 ] || die "shape table: class $cls pattern does not compile"
    P="$pat" LC_ALL=C awk 'BEGIN { x = ("" ~ ENVIRON["P"]) }' 2>/dev/null || die "shape table: class $cls pattern does not compile"
    printf '%s\t%s\t%s\n' "$cls" "$pat" "$actor"
  done <"$file"
}

cmd_classes() {
  local shapes="$DEFAULT_SHAPES" dd acc cls reg pat actor line
  while [ $# -gt 0 ]; do
    case "$1" in
      --shapes) [ $# -ge 2 ] || die "--shapes needs a file"; shapes="$2"; shift 2 ;;
      *) die "classes: unknown argument '$1'" ;;
    esac
  done
  dd="$(data_dir)"; acc="$self_dir/accumulate.sh"
  shape_rows "$shapes" >/dev/null || exit 2
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    IFS=$'\t' read -r cls reg pat actor <<<"$line"
    [ "$cls" = class ] && continue
    printf "'%s' --dir '%s' new-class '%s' 'a known-bypass register entry: %s' 'the guard %s: fix the reader for this shape, then delete the register entry and its pins (dir #842)' guards %s %s felt\n" \
      "$acc" "$dd" "$cls" "${cls#*:}" "$reg" "$THRESHOLD" "$WINDOW_DAYS"
  done <"$shapes"
}

# in_git_tree PATH — true when PATH (or its nearest existing ancestor) is inside a git work tree or this checkout.
in_git_tree() {
  local p="$1" d
  d="$(dirname "$p")"
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do d="$(dirname "$d")"; done
  d="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
  case "$d/" in "$repo_root"/*) return 0 ;; esac
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

cmd_scan() {
  local tdir="${KEEL_TRANSCRIPTS_DIR:-$HOME/.claude/projects}" shapes="$DEFAULT_SHAPES" since="" days="" asof="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --transcripts) [ $# -ge 2 ] || die "--transcripts needs a directory"; tdir="$2"; shift 2 ;;
      --shapes) [ $# -ge 2 ] || die "--shapes needs a file"; shapes="$2"; shift 2 ;;
      --since) [ $# -ge 2 ] || die "--since needs a date"; since="$2"; shift 2 ;;
      --days) [ $# -ge 2 ] || die "--days needs a number"; days="$2"; shift 2 ;;
      --as-of) [ $# -ge 2 ] || die "--as-of needs a date"; asof="$2"; shift 2 ;;
      --out) [ $# -ge 2 ] || die "--out needs a file"; out="$2"; shift 2 ;;
      *) die "scan: unknown argument '$1'" ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ -d "$tdir" ] || die "transcripts dir $tdir does not exist"
  [ -n "$asof" ] || asof="$(date +%F)"
  valid_date "$asof" || die "--as-of '$asof' is not an ISO date"
  if [ -n "$since" ] && [ -n "$days" ]; then die "give --since or --days, not both"; fi
  if [ -n "$days" ]; then
    [[ "$days" =~ ^[1-9][0-9]*$ ]] || die "--days '$days' is not a positive number"
    since="$(date_minus "$asof" "$days")"
  fi
  [ -n "$since" ] || since="$(date_minus "$asof" "$WINDOW_DAYS")"
  valid_date "$since" || die "--since '$since' is not an ISO date"

  local scratch rows_file
  if [ -n "$out" ]; then
    in_git_tree "$out" && die "refusing --out $out: it is inside a git work tree (the candidates are personal data)"
    : >"$out" 2>/dev/null || die "cannot write $out"
  else
    out="$(mktemp "${TMPDIR:-/tmp}/bypass-scan.XXXXXX")" || die "cannot create a scratch file"
    if in_git_tree "$out"; then rm -f "$out"; die "the scratch dir ${TMPDIR:-/tmp} is inside a git work tree; pass --out elsewhere"; fi
  fi
  scratch="$(mktemp "${TMPDIR:-/tmp}/bypass-scan-shapes.XXXXXX")" || die "cannot create a scratch file"
  rows_file="$scratch"
  shape_rows "$shapes" >"$rows_file" || { rm -f "$rows_file"; exit 2; }

  # `$tdir/.` so a symlinked transcripts root (the KB links ~/.claude/projects) is walked, not listed as one link.
  # Stage 1 (jq): one line per Bash tool call — session, sidechain, timestamp, file, command (newlines -> " ; ").
  # Stage 2 (awk): the shape table against each command; per (class, session) a few example lines and a count.
  # `fromjson?` skips a malformed (truncated) transcript line instead of failing the whole file; one jq per file (`-n 1`),
  # because jq -R joins a file's last line, when it has no newline, to the next file's first.
  find "$tdir/." -type f -name '*.jsonl' -print0 2>/dev/null \
    | xargs -0 -n 1 jq -R -r '
        fromjson? | . as $l
        | (.message.content? // empty) | select(type == "array") | .[]
        | select(type == "object" and .type == "tool_use" and .name == "Bash")
        | [ ($l.sessionId // ""), (($l.isSidechain // false) | tostring), ($l.timestamp // ""), input_filename,
            ((.input.command // "") | tostring | gsub("[\t\r]"; " ") | gsub("\n"; " ; ")) ]
        | join("\t")' 2>/dev/null \
    | LC_ALL=C awk -F'\t' -v since="$since" -v asof="$asof" -v maxex="$EXAMPLES_PER_SESSION" -v cap="$COMMAND_CAP" -v rows="$rows_file" -v out="$out" '
        BEGIN {
          while ((getline line < rows) > 0) { n++; split(line, f, "\t"); cls[n] = f[1]; pat[n] = f[2]; act[n] = f[3] }
          close(rows)
        }
        {
          sid = $1; side = $2; d = substr($3, 1, 10); file = $4; cmd = $5
          if (d == "" || d < since || d > asof) next
          scanned++
          if (sid == "") {            # a line with no sessionId: the parent is named by the path
            if (file ~ /\/subagents\/[^\/]*$/) { p = file; sub(/\/subagents\/[^\/]*$/, "", p); sub(/.*\//, "", p); sid = p }
            else { p = file; sub(/.*\//, "", p); sub(/\.jsonl$/, "", p); sid = p }
          }
          for (i = 1; i <= n; i++) {
            if (act[i] == "subagent" && side != "true") continue
            if (cmd !~ pat[i]) continue
            key = cls[i] "\t" sid
            total[key]++; hits++
            if (!(key in first) || d < first[key]) first[key] = d
            if (total[key] <= maxex) {
              c = (length(cmd) > cap) ? substr(cmd, 1, cap) "..." : cmd
              exl[key, total[key]] = d "\t" (side == "true" ? "subagent" : "main") "\t" c
            }
            if (!(key in seen)) { seen[key] = 1; per[cls[i]]++; ns++; order[ns] = key }
          }
        }
        END {
          printf "# bypass-scan candidates, as-of %s, since %s — PERSONAL DATA: adjudicate, then delete this file\n", asof, since > out
          printf "# class\tsession\tdate\tactor\tcommand (first %d per class and session)\n", maxex > out
          for (k = 1; k <= ns; k++) {
            key = order[k]; split(key, kp, "\t")
            for (j = 1; j <= total[key] && j <= maxex; j++) printf "%s\t%s\t%s\n", kp[1], kp[2], exl[key, j] > out
            if (total[key] > maxex) printf "%s\t%s\t%s\t-\t(+%d more)\n", kp[1], kp[2], first[key], total[key] - maxex > out
          }
          printf "bypass-scan: %d command(s) scanned, %d candidate(s) in %d (class, session) pair(s)\n", scanned + 0, hits + 0, ns + 0
          for (i = 1; i <= n; i++) if (per[cls[i]] > 0) printf "  %s: %d session(s)\n", cls[i], per[cls[i]]
        }'
  local rc=$?
  rm -f "$rows_file"
  [ "$rc" -eq 0 ] || die "scan failed"
  printf 'bypass-scan: candidates written to %s (since %s, as-of %s)\n' "$out" "$since" "$asof"
}

case "${1:-}" in
  scan) shift; cmd_scan "$@" ;;
  classes) shift; cmd_classes "$@" ;;
  data-dir) data_dir ;;
  -h|--help|help) usage ;;
  '') usage >&2; exit 2 ;;
  *) die "unknown subcommand '$1' (scan | classes | data-dir)" ;;
esac
