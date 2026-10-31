#!/usr/bin/env bash
# cloud-brief.sh — adopter-usable: build the self-contained brief that runs one backlog ticket in a Claude Code
# cloud session, check that the ticket may go there, and (on the operator's yes) dispatch it (dir #900). The
# rules — the opt-in line, the eligibility rows G1–G9, the verdict line, who may dispatch — live in
# docs/cloud.md; this tool runs the mechanical half of them. tools/cloud-land.sh is the landing check after.
#
#   cloud-brief.sh <repo> <ticket-id> [--check | --eligible | --dispatch] [--credit-before <amount>]
#                  [--redispatch] [--out FILE]
#   cloud-brief.sh <repo> --sweep
#
# <repo> is any path inside the project (a worktree too); the tool works on its main checkout, the first entry
# of `git worktree list`. <ticket-id> is spelled as its backlog heading spells it (`dir #801`, `KB.34`) — quote it.
#   (no mode)    build: write the brief and a `built` ledger row.
#   --check      every row the tool can run (G9 aside), the brief assembled, sized and scanned in a temporary
#                directory; writes nothing. Its last stdout line is `cloud-check: <exit> <ticket> <main HEAD>`
#                (`?` for no ticket or one holding a tab or a newline, `none` for no HEAD) — on every exit once
#                `--check` was read, a usage error's too.
#   --eligible   build a ticket that has no verdict yet, the judged rows confirmed; prints the `yes` line to
#                write into the ticket.
#   --dispatch   build, check G9, write the row as `dispatched`, run `claude --cloud` from the main checkout
#                under a pseudo-terminal (the CLI refuses to run without one), print the claim to write.
#   --sweep      read-only: every open R3/R4/📐 ticket with its verdict, and this repository's dispatched and
#                landed ledger rows with their pull requests.
#   --out FILE   write the brief to FILE, a regular file (a FIFO or /dev/stdout is refused), not the brief dir.
# The tool never writes the backlog and never pushes.
#
# Exit: 0 done · 1 the secret scan refused the brief · 2 usage, not found, a gh/git failure, the ledger lock ·
# 3 a mechanical row, the model mapping or the ledger refused · 4 judged rows unconfirmed (no verdict) ·
# 5 the dispatch itself failed (the row goes back to `built`). Every refusal comes before the brief is written
# but one: the ledger row's re-check under the lock (another run changed the row meanwhile) comes after it.
#
# Env (relative values — these, TMPDIR and HOME — are made absolute against the start directory): CLOUD_LEDGER
# ($(keel_store_root cloud)/ledger.tsv) · CLOUD_BRIEF_DIR ($(keel_store_root cloud)/briefs) · CLOUD_TEMPLATE
# (<engine>/templates/cloud-protocol.md) · CLOUD_BRIEF_MAX_BYTES (130000 — Linux caps one argument at 131071
# bytes) · CLOUD_KEEL_ORIGIN (https://github.com/rockerlabs/keel — what the VM clones) · SECRET_SCAN_PERSONAL_FILE
# (the scanner's default; a path that is not a regular file refuses, /dev/null opts out) · CLOUD_BACKLOG (unset:
# <main>/BACKLOG.md, else CLAUDE.md's inline section; set: the backlog file itself — a mirror of an adopter's
# tickets in the heading canon — which must be a readable regular file, else exit 2).
set -uo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

START_DIR="$PWD"
abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$START_DIR" "$1" ;; esac; }
die() { local code="$1"; shift; printf 'cloud-brief: %s\n' "$*" >&2; exit "$code"; }

ENGINE="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
for lib in fence-blank backlog-blocks state-root repo-top nonneg-int safe-write leak-gate cloud; do
  [ -s "$ENGINE/tools/lib/$lib.sh" ] && bash -n "$ENGINE/tools/lib/$lib.sh" 2>/dev/null \
    || die 2 "$ENGINE/tools/lib/$lib.sh is missing or corrupted — re-clone or re-download Keel"
  # shellcheck source=/dev/null
  . "$ENGINE/tools/lib/$lib.sh"
done
cloud_absolutize_env || die 2 "cannot make the path variables absolute"

usage() {
  die 2 "usage: cloud-brief.sh <repo> <ticket-id> [--check | --eligible | --dispatch] [--credit-before <amount>] [--redispatch] [--out FILE]
       cloud-brief.sh <repo> --sweep"
}
REPO_ARG="" TICKET="" MODE=build REDISPATCH="" CREDIT="?" OUT="" RECEIPT=""
WORK="" MAIN=""
# --check's receipt comes on every exit once `--check` was read, a usage error's too, on fd 3 — the caller's stdout,
# opened when `--check` is read (before any redirect), so an exit from inside a redirected group (the brief's
# assembly) reaches it; no other mode opens fd 3, so no child of theirs (--dispatch's CLI) holds the caller's stdout.
# Never with a ticket id that could print a line of its own.
on_exit() {
  local rc=$? head=none ticket="${TICKET:-?}"
  [ -z "$WORK" ] || rm -rf "$WORK"
  if [ -n "$RECEIPT" ]; then
    [ -z "$MAIN" ] || head="$(git -C "$MAIN" rev-parse HEAD 2>/dev/null)" || head=none
    cloud_cell_ok "$ticket" || ticket="?"
    printf 'cloud-check: %s %s %s\n' "$rc" "$ticket" "$head" >&3
  fi
  exit "$rc"
}
trap on_exit EXIT
set_mode() { [ "$MODE" = build ] || usage; MODE="$1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check) exec 3>&1; RECEIPT=1; set_mode check ;;
    --eligible) set_mode eligible ;;
    --dispatch) set_mode dispatch ;;
    --sweep) set_mode sweep ;;
    --redispatch) REDISPATCH=1 ;;
    --credit-before) [ $# -ge 2 ] || usage; CREDIT="$2"; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT="$(abs "$2")"; shift ;;
    -*) usage ;;
    *) if [ -z "$REPO_ARG" ]; then REPO_ARG="$1"; elif [ -z "$TICKET" ]; then TICKET="$1"; else usage; fi ;;
  esac
  shift
done

[ -n "$REPO_ARG" ] || usage
if [ "$MODE" = sweep ]; then
  [ -z "$TICKET" ] || usage
else
  [ -n "$TICKET" ] || usage
fi
cloud_cell_ok "$TICKET" || die 2 "a ticket id holds no tab or newline"
[ -n "$CREDIT" ] && cloud_cell_ok "$CREDIT" || die 2 "--credit-before takes a plain amount"

STORE=""
if [ -z "${CLOUD_LEDGER:-}" ] || [ -z "${CLOUD_BRIEF_DIR:-}" ]; then
  STORE="$(keel_store_root cloud)" || die 2 "no state root: HOME is unset"
fi
CLOUD_LEDGER="$(abs "${CLOUD_LEDGER:-$STORE/ledger.tsv}")"
CLOUD_BRIEF_DIR="$(abs "${CLOUD_BRIEF_DIR:-$STORE/briefs}")"
CLOUD_TEMPLATE="$(abs "${CLOUD_TEMPLATE:-$ENGINE/templates/cloud-protocol.md}")"
MAX_BYTES="${CLOUD_BRIEF_MAX_BYTES:-130000}"
KEEL_ORIGIN="${CLOUD_KEEL_ORIGIN:-https://github.com/rockerlabs/keel}"
SCANNER="$ENGINE/tools/secret-guard/secret-scan.sh"
_nonneg_int_valid "$MAX_BYTES" 19 || die 2 "CLOUD_BRIEF_MAX_BYTES must be a number"
case "$KEEL_ORIGIN" in ''|*[[:space:]\'\"\`\$\\]*) die 2 "CLOUD_KEEL_ORIGIN must be a plain URL" ;; esac
case "$KEEL_ORIGIN" in *://*|*@*:*) ;; *) KEEL_ORIGIN="$(abs "$KEEL_ORIGIN")" ;; esac

# --- the project: its main checkout, the opt-in line, the GitHub repository ---------------------------------
cloud_resolve_main "$REPO_ARG" || die 2 "$CLOUD_ERR"

today() { date +%F; }
ORIGIN_URL="$(git -C "$MAIN" config --get remote.origin.url 2>/dev/null || true)"
OR="$(cloud_github_slug "$ORIGIN_URL" || true)"
OWNER="${OR%%/*}"

# Every `### ` ticket heading bounds a block, whatever its id shape (`dir #801`, `KB.34`, `34.`).
TICKET_ERE='[^[:space:]]+( #[0-9]+)?'
# The backlog, the /backlog way: <main>/BACKLOG.md, else CLAUDE.md's inline section.
BACKLOG=""
if [ -n "${CLOUD_BACKLOG+x}" ]; then
  BACKLOG="$(abs "$CLOUD_BACKLOG")"
  [ -f "$BACKLOG" ] && [ -r "$BACKLOG" ] || die 2 "CLOUD_BACKLOG is not a readable regular file: $BACKLOG"
elif [ -f "$MAIN/BACKLOG.md" ]; then
  BACKLOG="$MAIN/BACKLOG.md"
elif [ -f "$MAIN/CLAUDE.md" ] && grep -qE "^### ($TICKET_ERE) — " "$MAIN/CLAUDE.md"; then
  BACKLOG="$MAIN/CLAUDE.md"
fi

# slug_of ID — lowercased, every run outside [a-z0-9] one `-`, trimmed.
slug_of() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

# verdict_of BLANKED_BLOCK — prints `none`, `yes`, `no <row> <reason>`, or `malformed <why>` for the B2 line(s).
verdict_of() {
  local lines n line
  lines="$(grep -E '^\*\*Cloud:\*\*' <<< "$1" || true)"
  n=0; [ -z "$lines" ] || n="$(grep -c '' <<< "$lines")"
  if [ "$n" -eq 0 ]; then echo none; return; fi
  if [ "$n" -gt 1 ]; then echo "malformed $n **Cloud:** lines"; return; fi
  line="$(tr -d '\r' <<< "$lines")"
  local date_who='\([0-9]{4}-[0-9]{2}-[0-9]{2}, [^)]+\)[[:space:]]*$'
  if [[ "$line" =~ ^\*\*Cloud:\*\*\ yes\ $date_who ]]; then echo yes; return; fi
  if [[ "$line" =~ ^\*\*Cloud:\*\*\ no\ —\ (G3|G3b|G4|G5|G8):\ (.+)\ $date_who ]]; then
    echo "no ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; return
  fi
  echo "malformed '$line'"
}

# grade_of HEADING — the LAST `— R<d>` token's grade, or nothing.
grade_of() { grep -oE '— R[0-9]([^a-zA-Z0-9]|$)' <<< "$1" | tail -1 | grep -oE 'R[0-9]' || true; }

# --- --sweep: read-only listing ------------------------------------------------------------------------------
# pr_of BRANCH [PR] → "<number> <head sha>" of PR when the row records one (a failed `cloud-land.sh --ticket` run
# records the PR but leaves the branch cell), else of the newest PR from BRANCH, or nothing; rc 1 when gh failed
# (its stderr kept).
pr_of() {
  [ -n "$OR" ] || return 0
  if [ -n "${2:-}" ]; then
    cloud_gh_api "repos/$OR/pulls/$2" --jq '"\(.number) \(.head.sha)"' || return 1
    return 0
  fi
  cloud_gh_api "repos/$OR/pulls?head=$OWNER:$1&state=all" --jq '.[0] // empty | "\(.number) \(.head.sha)"' || return 1
}
noon_epoch() { # YYYY-MM-DD → the epoch second of local noon that day (GNU/busybox date, else BSD)
  date -d "$1 12:00:00" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$1 12:00:00" +%s 2>/dev/null
}
# days_since YYYY-MM-DD — whole days from it to today (NOON_TODAY, set once by the sweep); both read at local noon
# and rounded half away from zero, so no zone or DST shifts it and a date one day ahead reads -1, not 0.
NOON_TODAY=""
days_since() {
  local s d
  [ -n "$NOON_TODAY" ] && s="$(noon_epoch "$1")" || { echo "?"; return; }
  d=$((NOON_TODAY - s))
  if [ "$d" -ge 0 ]; then echo $(( (d + 43200) / 86400 )); else echo $(( -((43200 - d) / 86400) )); fi
}
if [ "$MODE" = sweep ]; then
  printf 'cloud sweep: %s (%s)\n' "$MAIN" "${OR:-origin is not a github.com repository}"
  printf 'tickets (open, R3/R4 or 📐):\n'
  if [ -n "$BACKLOG" ]; then
    blanked_all="$(blank_fenced_blocks "$BACKLOG")"
    while IFS=$'\t' read -r b_start b_end _ b_heading; do
      case "$b_heading" in "### "*" — "*) ;; *) continue ;; esac
      grep -qE '✅|❌|SUPERSEDED|RETRACTED' <<< "$b_heading" && continue
      g="$(grade_of "$b_heading")"
      case "$g" in R3|R4) ;; '') grep -q '📐' <<< "$b_heading" || continue ;; *) continue ;; esac
      id="${b_heading#\#\#\# }"; id="${id%% — *}"
      v="$(verdict_of "$(sed -n "${b_start},${b_end}p" <<< "$blanked_all")")"
      case "$v" in none) v="—" ;; yes) ;; no\ *) v="no — $(cut -d' ' -f2 <<< "$v")" ;; malformed*) v="malformed" ;; esac
      printf '  %s\t%s\t%s\n' "$id" "${g:-📐}" "$v"
    done < <(backlog_ticket_blocks "$BACKLOG" "$TICKET_ERE")
  fi
  printf 'dispatches (ledger %s):\n' "$CLOUD_LEDGER"
  gh_failed=""
  if [ -f "$CLOUD_LEDGER" ] && [ -n "$OR" ]; then
    NOON_TODAY="$(noon_epoch "$(today)")" || NOON_TODAY=""
    # Cells may be empty, and `read` collapses runs of a whitespace IFS: re-join on a unit separator first.
    while IFS=$'\037' read -r r_built r_repo r_ticket r_branch r_status r_exit r_head r_pr; do
      [ "$r_repo" = "$OR" ] || continue
      case "$r_status" in dispatched|landed) ;; *) continue ;; esac
      if pr="$(pr_of "$r_branch" "$r_pr")"; then
        label="no PR"; [ -z "$pr" ] || label="PR #${pr%% *}"
      else
        gh_failed=1 pr="?" label="PR unknown (gh failed)" # `?`: no "<number> <sha>" pair is ever one word
      fi
      case "$r_status" in
        dispatched)
          printf '  dispatched\t%s\t%s\tsince %s (%s days)\t%s\n' "$r_ticket" "$r_branch" "$r_built" \
            "$(days_since "$r_built")" "$label" ;;
        landed)
          # A failed re-run records its head but leaves the row landed: its exit cell flags it.
          if [ -n "$r_exit" ] && [ "$r_exit" != 0 ]; then state="STALE: the last landing check exited $r_exit"
          elif [ "$pr" = "?" ]; then state="unknown"
          elif [ -n "$pr" ] && [ "${pr#* }" != "$r_head" ]; then state="STALE: the PR head is ${pr#* }, landed at $r_head"
          else state="current"; fi
          printf '  landed\t%s\t%s\t%s\t%s\n' "$r_ticket" "$r_branch" "$label" "$state" ;;
      esac
    done < <(awk -F'\t' -v OFS='\037' 'NR > 1 { print $1, $2, $3, $4, $8, $12, $13, $14 }' "$CLOUD_LEDGER")
  fi
  [ -z "$gh_failed" ] || die 2 "gh failed: the PR columns above marked unknown are not known (network, auth or gh itself)"
  exit 0
fi

# --- from here on, one ticket ----------------------------------------------------------------------------------
SLUG="$(slug_of "$TICKET")"
[ -n "$SLUG" ] || die 2 "the ticket id '$TICKET' has no letter or digit"
BRANCH="claude/cloud-$SLUG"
refuse() { die 3 "$TICKET refused: $1 — $2"; }

cloud_personal_file || die 2 "$CLOUD_ERR"
[ -f "$SCANNER" ] || die 2 "no scanner at $SCANNER"
[ -f "$CLOUD_TEMPLATE" ] || die 2 "no protocol template at $CLOUD_TEMPLATE"

# G1 (local half): the opt-in is a line of its own in the main checkout's CLAUDE.md, read from fence-blanked text
# like every other field (dir #913): a line inside a fenced example opts nothing in, and the refusal names it.
OPTIN="" UNPROTECTED_OK="" NEAR=""
if [ -f "$MAIN/CLAUDE.md" ]; then
  claude_blanked="$(blank_fenced_blocks "$MAIN/CLAUDE.md")"
  while IFS= read -r hit; do
    n="${hit%%:*}" text="${hit#*:}"
    if grep -qi 'keel-cloud' <<< "$(sed -n "${n}p" <<< "$claude_blanked")"; then
      if [[ "$text" =~ ^KEEL-CLOUD(\ unprotected-ok)?[[:space:]]*$ ]]; then
        OPTIN=1
        [ -z "${BASH_REMATCH[1]}" ] || UNPROTECTED_OK=1
      else
        NEAR="${NEAR}  CLAUDE.md line $n: $text"$'\n'
      fi
    else
      NEAR="${NEAR}  CLAUDE.md line $n (inside a fenced block): $text"$'\n'
    fi
  done < <(grep -n -i 'keel-cloud' "$MAIN/CLAUDE.md" || true)
fi
# An odd number of fence markers leaves a fence open to the file's end, blanking a real opt-in below it.
if [ -f "$MAIN/CLAUDE.md" ] && [ $(( $(fence_marker_lines "$MAIN/CLAUDE.md" | grep -c '') % 2 )) -eq 1 ]; then
  NEAR="${NEAR}  CLAUDE.md has an odd number of fence markers: an unclosed fence blanks everything after it, an opt-in line included"$'\n'
fi
[ -z "$NEAR" ] || printf 'cloud-brief: not the opt-in (the opt-in is a line of its own, outside any fenced block: KEEL-CLOUD, or KEEL-CLOUD unprotected-ok):\n%s' "$NEAR" >&2
[ -n "$OPTIN" ] || refuse G1 "$MAIN/CLAUDE.md has no KEEL-CLOUD line of its own outside a fenced block (docs/cloud.md)"
[ -n "$OR" ] || refuse G1 "origin (${ORIGIN_URL:-none}) is not a github.com repository"

# --- the ticket block --------------------------------------------------------------------------------------------
[ -n "$BACKLOG" ] || die 2 "no backlog in $MAIN (no BACKLOG.md, no inline ticket section in CLAUDE.md) — spec-mode tickets are not dispatched"
# The lookup mode of the scanner: this one heading's row, none of the others walked or closure-tested.
START="" END="" HEADING=""
IFS=$'\t' read -r START END _ HEADING < <(backlog_ticket_blocks "$BACKLOG" "$TICKET_ERE" "$TICKET") || true
[ -n "$START" ] || die 2 "no heading '### $TICKET — …' in $BACKLOG"
# The scanner's END runs a last ticket to the file's last line, a fenced tail included. An odd fence-marker count after
# its heading leaves a fence open that hides the tickets and sections after it: bb_last_block_fence_end cuts the block
# there, or refuses when a cut would drop text the blanking reads as the ticket's own (a G8 phrase, say).
if ! CUT="$(bb_last_block_fence_end "$BACKLOG" "$START" "$END" "$TICKET_ERE")"; then
  die 2 "$TICKET: the fence markers after its heading do not pair up, and the heading at line $CUT of $BACKLOG" \
    "lies inside the ticket's text — close the unclosed fence inside the ticket, before line $CUT"
fi
END="$CUT"
blanked_all="$(blank_fenced_blocks "$BACKLOG")"
BLOCK="$(sed -n "${START},${END}p" "$BACKLOG")"
BLANKED="$(sed -n "${START},${END}p" <<< "$blanked_all")"

# heading_walk — backlog_ticket_blocks' wrapped-heading rule, walked again over the block's blanked text: sets
# WALK_N (the continuation lines it takes after the first) and WALK_TEXT (the heading as walked, lines joined by
# newlines). The walk is trusted only when it rebuilds the flattened HEADING exactly (walk_ok).
WALK_N=0 WALK_TEXT=""
heading_walk() {
  local so_far ln
  WALK_N=0
  {
    IFS= read -r so_far
    so_far="$(sed -E 's/`[^`]*`//g' <<< "$so_far")"
    while [ "$WALK_N" -lt 50 ] && IFS= read -r ln; do
      ln="$(sed -E 's/`[^`]*`//g' <<< "$ln")"
      [ -n "$ln" ] && bb_heading_continues "$so_far" "$ln" || break
      so_far+=$'\n'"$ln"; WALK_N=$((WALK_N + 1))
    done
  } <<< "$BLANKED"
  WALK_TEXT="$so_far"
}
walk_ok() { [ "$(tr '\n\t' '  ' <<< "$WALK_TEXT")" = "$HEADING" ]; }
heading_walk

# G2 (glued line, dir #913): the lib folds a body line written directly under a heading into the heading while the
# heading has no recognized tail (BB_HEADING_TAIL_PATTERN), so G2 below could read a 📐 or a ✅ out of body text. The
# lib documents that residual for keel's own backlog and stays unchanged; an adopter's backlog is not ours to
# assume, and the wrapped-heading grammar (a tail that lands on a later physical line) cannot tell the two apart —
# so a block that took continuation lines and still has no tail is refused, fail-closed, naming the line.
walk_ok || refuse G2 "cannot tell where the heading at line $START of $BACKLOG ends — leave a blank line after it, and check that no tab or odd character splits it"
if [ "$WALK_N" -ge 1 ] && ! [[ "$WALK_TEXT" =~ $BB_HEADING_TAIL_PATTERN ]]; then
  glued="$(sed -n "$((START + 1))p" "$BACKLOG" | tr -d '\r')"
  refuse G2 "line $((START + 1)) of $BACKLOG ('$glued') sits directly under a heading that has no readiness tail (— R<d>, → pool, a status glyph), so the backlog reads it as part of the heading — leave a blank line after the heading"
fi

# G2: open, R3/R4 or 📐 — the LAST `— R<d>` token decides; markers count on the heading only.
if grep -qE '✅|❌|SUPERSEDED|RETRACTED|⏳|⛔' <<< "$HEADING"; then
  refuse G2 "the heading carries a closed, superseded, retracted, in-flight or blocked marker"
fi
GRADE="$(grade_of "$HEADING")"
case "$GRADE" in
  R3|R4) ;;
  '') grep -q '📐' <<< "$HEADING" || refuse G2 "no readiness grade on the heading, needs R3, R4 or 📐 SPEC-READY" ;;
  *) refuse G2 "readiness $GRADE, needs R3, R4 or 📐 SPEC-READY (📐 beside R0–R2 is a contradiction)" ;;
esac

# G2b: the verdict line, read from the fence-blanked block.
VERDICT="$(verdict_of "$BLANKED")"
case "$VERDICT" in
  none|yes) ;;
  no\ *) v="${VERDICT#no }"; refuse G2b "its verdict is no — ${v%% *}: ${v#* }" ;;
  malformed*) refuse G2b "a malformed verdict: ${VERDICT#malformed } (docs/cloud.md: one line, yes or no — <row>)" ;;
esac

# G7: the first token after `Spec:` names a file in the main checkout, which the brief carries to the VM — so never
# an absolute path, a file whose PHYSICAL directory lies outside $MAIN (a `..` that climbs out, a directory symlinked
# out), a file that is itself a symlink, or git data (a config, its auth), in any case — a case-insensitive file
# system (macOS) reads `.GIT` as `.git`: no `.git` component as written (a gitfile too), no `.git` or `*.git`
# component in the physical directory (a bare repository inside the checkout is `<name>.git`), and, whatever its
# name, no directory git itself reads as a git directory (a bare clone `vendor/upstream`, a --separate-git-dir) —
# one git cannot answer for (a bare repository under safe.bareRepository=explicit) refuses too.
# A `..` that stays inside is no refusal: the physical directory decides.
SPEC_REL="" SPEC_FILE=""
SPEC_LINE="$(grep -m1 -E '^(\*\*)?Spec:(\*\*)?[[:space:]]' <<< "$BLANKED" | tr -d '\r' || true)"
if [ -n "$SPEC_LINE" ]; then
  SPEC_REL="$(sed -E 's/^(\*\*)?Spec:(\*\*)?[[:space:]]+//' <<< "$SPEC_LINE" | awk '{print $1}' | tr -d '`')"
  SPEC_FILE="$MAIN/$SPEC_REL"
  case "$SPEC_REL" in /*) refuse G7 "Spec: $SPEC_REL is outside $MAIN" ;; esac
  case "/$SPEC_REL/" in */.[Gg][Ii][Tt]/*) refuse G7 "Spec: $SPEC_REL has a .git component (the repository's git data)" ;; esac
  [ -n "$SPEC_REL" ] && [ -f "$SPEC_FILE" ] || refuse G7 "Spec: ${SPEC_REL:-?} is not a file in $MAIN"
  [ ! -L "$SPEC_FILE" ] || refuse G7 "Spec: $SPEC_REL is a symlink"
  spec_dir="$(CDPATH='' cd -P -- "$(dirname -- "$SPEC_FILE")" && pwd -P)" || refuse G7 "Spec: $SPEC_REL — its directory cannot be entered"
  case "$spec_dir/" in "${MAIN%/}/"*) ;; *) refuse G7 "Spec: $SPEC_REL is outside $MAIN (its directory is $spec_dir)" ;; esac
  case "${spec_dir#"${MAIN%/}"}/" in *.[Gg][Ii][Tt]/*) refuse G7 "Spec: $SPEC_REL is inside a git directory (its directory is $spec_dir)" ;; esac
  # git's own stderr goes into the refusal (dir #913): a spec directory on another file system inside the checkout
  # (GIT_DISCOVERY_ACROSS_FILESYSTEM), a bare repository under safe.bareRepository=explicit, ... each say why.
  g7_err="$(mktemp "${TMPDIR:-/tmp}/cloud-brief-g7.XXXXXX")" || die 2 "mktemp failed"
  if in_git="$(git -C "$spec_dir" rev-parse --is-inside-git-dir 2>"$g7_err")"; then
    rm -f "$g7_err"
  else
    g7_msg="$(tr '\n' ' ' < "$g7_err" | sed -E 's/[[:space:]]+$//')"; rm -f "$g7_err"
    refuse G7 "Spec: $SPEC_REL — git cannot tell whether its directory ($spec_dir) is a git directory: ${g7_msg:-no message from git}"
  fi
  [ "$in_git" = false ] || refuse G7 "Spec: $SPEC_REL is inside a git directory (git reads $spec_dir as one)"
fi

# G8 (its two mechanical phrases), then the model mapping.
MODEL_LINE="$(grep -m1 -F '**Model rec:**' <<< "$BLANKED" || true)"
grep -qF 'Question for a /design pass' <<< "$BLANKED" && refuse G8 "the ticket asks for a /design pass first"
grep -qiF 'for the design' <<< "$MODEL_LINE" && refuse G8 "its Model rec is for the design, not the build"
WARN=""
if [ -z "$MODEL_LINE" ]; then
  MODEL=sonnet EFFORT=medium WARN="no **Model rec:** line — sonnet + medium, the default"
else
  rec="$(tr '[:upper:]' '[:lower:]' <<< "${MODEL_LINE#*\*\*Model rec:\*\*}")"
  tier="$(grep -oE '[a-z]+[ -]tier' <<< "$rec" | head -1 || true)"
  case "$tier" in
    "top tier"|"top-tier") MODEL=opus ;;
    "mid tier"|"mid-tier") MODEL=sonnet ;;
    "light tier"|"light-tier") MODEL=haiku ;;
    *) refuse model "the Model rec names no mapped tier (${tier:-none}): top, mid or light" ;;
  esac
  EFFORT="$(grep -oE '(^|[^a-z0-9])(low|medium|high|xhigh|max)([^a-z0-9]|$)' <<< "$rec" | head -1 \
    | grep -oE 'low|medium|xhigh|high|max' || true)"
  [ -n "$EFFORT" ] || { EFFORT=medium; WARN="no effort word on the Model rec line — medium"; }
fi

# The ledger: a dispatched or abandoned row needs --redispatch; a landed row always refuses.
ledger_refusal() { # prints the refusal reason, or nothing
  local row status
  row="$(cloud_ledger_row "$CLOUD_LEDGER" "$OR" "$TICKET")" || return 0
  status="$(cloud_ledger_cell "$row" 8)"
  case "$status" in
    built) ;;
    dispatched|abandoned) [ -n "$REDISPATCH" ] || echo "its ledger row is $status — re-run with --redispatch to dispatch it again (the operator's yes covers one dispatch)" ;;
    landed) echo "its ledger row is landed — set it to abandoned by hand if its PR closed unmerged" ;;
    *) echo "its ledger row has an unknown status '$status'" ;;
  esac
}
reason="$(ledger_refusal)"
[ -z "$reason" ] || refuse ledger "$reason"

# --- G1 (remote half), G1b, G1c — GitHub, through gh ---------------------------------------------------------
gh_or_refuse() { # ROW WHAT ARGS... — gh api's stdout; 404/403 refuses ROW, anything else is exit 2
  local row="$1" what="$2" out rc=0
  shift 2
  out="$(cloud_gh_api "$@")" || rc=$?
  case "$rc" in
    0) printf '%s' "$out" ;;
    4) refuse "$row" "gh api cannot read $what" ;;
    *) die 2 "gh api failed reading $what (a rate limit, network, auth or gh itself — see gh's message above)" ;;
  esac
}
DEFAULT="$(gh_or_refuse G1 "repos/$OR" "repos/$OR" --jq .default_branch)" || exit $?
[ -n "$DEFAULT" ] || die 2 "gh api gave no default branch for $OR"
# The name goes unquoted into the VM's shell commands (the protocol's <default>): ref characters a shell passes as
# they are, spelled out — a bracket range follows the locale's collation in bash 3.2 — and no leading `+` or `-`,
# which `git fetch origin <default>` would read as a forced refspec or an option.
case "$DEFAULT" in
  [+-]*)
    refuse G1 "the default branch name '$DEFAULT' starts with a + or a -, which the cloud protocol's git commands would read as a refspec flag or an option" ;;
  *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/+-]*)
    refuse G1 "the default branch name '$DEFAULT' has a character the cloud protocol cannot pass to a shell" ;;
esac
LEVEL="$(gh_or_refuse G1b "the protection of $OR:$DEFAULT" "repos/$OR/branches/$DEFAULT" \
  --jq '.protection.required_status_checks.enforcement_level // ""')" || exit $?
if [ "$LEVEL" != everyone ] && [ -z "$UNPROTECTED_OK" ]; then
  refuse G1b "$OR's $DEFAULT does not refuse an unchecked direct push (required status checks for everyone: '${LEVEL:-none}') — protect it, or opt in with the line KEEL-CLOUD unprotected-ok"
fi
WORKFLOWS="$(gh_or_refuse G1c "the workflows of $OR" "repos/$OR/actions/workflows" \
  --jq '[(.workflows // [])[] | select(.state == "active")] | length')" || exit $?
case "$WORKFLOWS" in ''|0|*[!0-9]*) refuse G1c "$OR has no active CI workflow — the landing check needs a green check rollup" ;; esac

# --- the judged rows ---------------------------------------------------------------------------------------------
if [ "$VERDICT" = none ] && [ "$MODE" != eligible ]; then
  cat <<ROWS
$TICKET has no **Cloud:** verdict. The mechanical rows pass. Judge these rows (docs/cloud.md):
  G3  every file the work WRITES is tracked in the project — never a gitignored or untracked file, the backlog,
      the rails file when it is gitignored, anything outside the repository
  G3b every file the work must READ is tracked, or travels in the brief (the ticket, its spec, the rails)
  G4  every check that decides the work runs on an Ubuntu VM with no key, device or live account; a final live
      check alone is done locally at landing
  G5  the ticket is not itself a managed-release role (manager, train worker, auditor)
  G8  the ticket does not ask for a design pass first, in any words
Then write one line into the ticket body, beside **Model rec:**:
  **Cloud:** yes ($(today), <who>)
  **Cloud:** no — <G3|G3b|G4|G5|G8>: <reason> ($(today), <who>)
Hints (each line that may bear on a judged row):
ROWS
  hint_re='private/|\.evidence/|~/|BACKLOG|RELEASES\.md|gitignored|live|API key|docker|Docker|simulator|device'
  grep -nE "$hint_re" <<< "$BLOCK" | sed 's/^/  ticket:/'
  [ -z "$SPEC_FILE" ] || grep -nE "$hint_re" "$SPEC_FILE" | sed "s|^|  spec $SPEC_REL:|"
  exit 4
fi

# --- the keel commit the VM clones -------------------------------------------------------------------------------
same_origin() {
  local a b
  if a="$(cloud_github_slug "$1")" && b="$(cloud_github_slug "$2")"; then
    [ "$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$a")" = "$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$b")" ]
    return
  fi
  a="${1%/}"; a="${a%.git}"; b="${2%/}"; b="${b%.git}"
  [ "$a" = "$b" ]
}
no_keel() { die 2 "no published keel commit to hand the VM: $*"; }
[ "$(git -C "$ENGINE" rev-parse --show-toplevel 2>/dev/null)" = "$ENGINE" ] || no_keel "$ENGINE is no git checkout"
ENGINE_ORIGIN="$(git -C "$ENGINE" config --get remote.origin.url 2>/dev/null || true)"
same_origin "$ENGINE_ORIGIN" "$KEEL_ORIGIN" \
  || no_keel "the engine's origin (${ENGINE_ORIGIN:-none}) is not CLOUD_KEEL_ORIGIN ($KEEL_ORIGIN)"
git -C "$ENGINE" fetch -q origin main 2>/dev/null || no_keel "git fetch origin main failed in $ENGINE"
KEEL_SHA="$(git -C "$ENGINE" merge-base HEAD origin/main 2>/dev/null)" || no_keel "no merge-base of HEAD and origin/main in $ENGINE"

# --- assemble, rewrite, size, scan — in a temporary directory ----------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloud-brief.XXXXXX")" || die 2 "mktemp failed"
protocol="$(cat "$CLOUD_TEMPLATE")"
protocol=${protocol//"<repo>"/"$OR"}
protocol=${protocol//"<ticket>"/"$TICKET"}
protocol=${protocol//"<branch>"/"$BRANCH"}
protocol=${protocol//"<default>"/"$DEFAULT"}
protocol=${protocol//"<keel-sha>"/"$KEEL_SHA"}
protocol=${protocol//"<keel-origin>"/"$KEEL_ORIGIN"}
part() { cat "$1" && { [ -z "$(tail -c 1 "$1")" ] || echo; }; } # FILE, then a newline when it lacks a final one
{
  echo "=== protocol ==="
  printf '%s\n' "$protocol"
  echo "=== ticket ==="
  printf '%s\n' "$BLOCK"
  # A part that cannot be read stops the build (the group runs in this shell: `die` exits the tool).
  if [ -n "$SPEC_FILE" ]; then echo "=== spec ==="; part "$SPEC_FILE" || die 2 "cannot read $SPEC_FILE"; fi
  echo "=== rails ==="
  [ ! -f "$MAIN/CLAUDE.md" ] || part "$MAIN/CLAUDE.md" || die 2 "cannot read $MAIN/CLAUDE.md"
  echo "=== end of brief ==="
} > "$WORK/raw" || die 2 "cannot assemble the brief"

# The home path in each form a brief carries it (the scanner does not catch a bare username, by design). The homes:
# $HOME and the passwd entry's home (HOME may be unset, or `/`), each with its physical path, every one without its
# trailing `/`, `/` itself and duplicates dropped, all of them longer first (one may hold another). For each:
#   - the path itself → `~`, wherever it occurs (privacy first: HOME=/root also turns `/rootfs` into `~fs`, and
#     a sibling `/Users/alice2` becomes `~2` — the login never survives as a prefix);
#   - its project-directory names → `-Users-x`: Claude Code's (the CLI's encoder turns every character outside
#     [A-Za-z0-9] into `-`, `replace(/[^a-zA-Z0-9]/g, "-")`) and tools/lib/transcript-usage.sh's tu_project_slug
#     form (only `/` and `.` → `-`, so a home holding `_` keeps it). Both work per byte here, so a non-ASCII home
#     comes out longer than the CLI's (one `-` per UTF-16 unit there) and goes unrewritten — a known limit. A name
#     is matched only where it starts a token (the byte before it is not one of [A-Za-z0-9]), so `-Users-alice/…`,
#     `-Users-alice-proj`, a sibling's `-Users-alice2-…` (→ `-Users-x2-…`) and a name nested in another project
#     directory's (`-private-tmp-claude-501--Users-alice-…`) are rewritten, while HOME=/root's `-root` never hits
#     `state-root-migrate`, `non-root-user` or `claude/cloud-root-12`. A known cost of catching the nested name: an
#     option spelled like one, HOME=/root's `git log --root`, becomes `--Users-x` too (dir #908).
# Then the session scratch roots → `<tmp>/`, the longer first.
# rewrite MODE FROM TO [MODE FROM TO]... — stdin → stdout with each non-empty FROM replaced by its TO, in order;
# MODE `p` replaces every occurrence, `a` only one that starts a token (above). One byte-wise awk pass: bash's own
# `${text//…}` on a brief holding multibyte text costs time quadratic in its size (minutes near the byte cap on
# macOS). A subshell, so the pairs never reach the CLI's environment.
rewrite() (
  i=0
  while [ $# -ge 3 ]; do
    [ -z "$2" ] || { i=$((i + 1)); export "CL_MODE_$i=$1" "CL_FROM_$i=$2" "CL_TO_$i=$3"; }
    shift 3
  done
  CL_PAIRS="$i" LC_ALL=C awk '
    function rep(s, from, to, alone,   out, i, n, prev, b) {
      out = ""; n = length(from); prev = ""
      while ((i = index(s, from)) > 0) {
        if (alone) {
          b = (i > 1) ? substr(s, i - 1, 1) : prev
          if (b ~ /[A-Za-z0-9]/) {
            out = out substr(s, 1, i); prev = substr(s, i, 1); s = substr(s, i + 1); continue
          }
        }
        out = out substr(s, 1, i - 1) to; prev = substr(from, n, 1); s = substr(s, i + n)
      }
      return out s
    }
    BEGIN { n = ENVIRON["CL_PAIRS"] + 0; mp = "CL_MODE_"; fp = "CL_FROM_"; tp = "CL_TO_" }
    { for (k = 1; k <= n; k++) $0 = rep($0, ENVIRON[fp k], ENVIRON[tp k], ENVIRON[mp k] == "a"); print }'
)
# passwd_home — the passwd entry's home: `~` with HOME unset (bash then reads the entry), when absolute.
passwd_home() ( unset HOME; h=~; case "$h" in /*) printf '%s' "$h" ;; esac )
homes=""
add_home() { # PATH — add PATH, trailing slashes dropped, to the newline-separated list $homes; `/` and repeats skipped
  local h="$1"
  while [ "${h%/}" != "$h" ]; do h="${h%/}"; done
  [ -n "$h" ] || return 0
  case $'\n'"$homes" in *$'\n'"$h"$'\n'*) return 0 ;; esac
  homes="$homes$h"$'\n'
}
for h in "${HOME:-}" "$(passwd_home)"; do
  add_home "$h"
  [ -z "$h" ] || add_home "$(CDPATH='' cd -P -- "$h" 2>/dev/null && pwd -P)"
done
pairs=()
while IFS= read -r h; do
  [ -z "$h" ] || pairs+=(p "$h" '~')
done < <(printf '%s' "$homes" | LC_ALL=C awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
# Both encodings keep every byte's place, so the names come in the paths' own longer-first order.
n_paths="${#pairs[@]}" k=1
while [ "$k" -lt "$n_paths" ]; do
  pairs+=(a "$(printf '%s' "${pairs[$k]}" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')" -Users-x)
  pairs+=(a "$(printf '%s' "${pairs[$k]}" | LC_ALL=C tr '/.' '--')" -Users-x)
  k=$((k + 3))
done
uid="$(id -u)"
rewrite ${pairs[@]+"${pairs[@]}"} p "/private/tmp/claude-$uid/" '<tmp>/' p "/tmp/claude-$uid/" '<tmp>/' \
  < "$WORK/raw" > "$WORK/brief" || die 2 "the home-path rewrite failed"

BYTES="$(wc -c < "$WORK/brief" | tr -d ' ')"
[ "$BYTES" -le "$MAX_BYTES" ] || refuse G6 "the brief is $BYTES bytes, over CLOUD_BRIEF_MAX_BYTES=$MAX_BYTES"

scan_rc=0
scan_out="$(cloud_scan_file "$SCANNER" "$WORK/brief" "$WORK")" || scan_rc=$?
if [ "$scan_rc" -ne 0 ]; then
  printf '%s\n' "$scan_out" >&2
  die 1 "$TICKET refused: the secret scan exited $scan_rc — nothing written"
fi

if [ "$MODE" = check ]; then
  printf 'brief would be %s bytes, model %s/%s, branch %s; nothing written\n' "$BYTES" "$MODEL" "$EFFORT" "$BRANCH"
  [ -z "$WARN" ] || printf 'cloud-brief: warning: %s\n' "$WARN" >&2
  exit 0
fi

# --- G9, dispatch only -------------------------------------------------------------------------------------------
if [ "$MODE" = dispatch ]; then
  current="$(git -C "$MAIN" branch --show-current 2>/dev/null || true)"
  [ "$current" = "$DEFAULT" ] || refuse G9 "$MAIN is on '${current:-a detached HEAD}', not $DEFAULT — the CLI clones the main checkout's current branch"
  remote="$(git -C "$MAIN" ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null)" \
    || die 2 "git ls-remote origin failed in $MAIN"
  [ -z "$remote" ] || refuse G9 "origin already has $BRANCH — an abandoned run not cleaned; delete it (docs/cloud.md, Abandoning)"
fi

# --- write the brief, then the ledger row under the lock -------------------------------------------------------
DEST="${OUT:-$CLOUD_BRIEF_DIR/$(slug_of "$OR")--$SLUG.md}"
mkdir -p "$(dirname "$DEST")" || die 2 "cannot create $(dirname "$DEST")"
# Temp + rename: a CLI still reading an earlier brief at this path keeps its own file.
keel_write_state "$DEST" cat "$WORK/brief" || die 2 "cannot write $DEST"
DEST="$(CDPATH='' cd -- "$(dirname -- "$DEST")" && pwd -P)/$(basename -- "$DEST")"
printf 'brief: %s (%s bytes)\n' "$DEST" "$BYTES"
[ -z "$WARN" ] || printf 'cloud-brief: warning: %s\n' "$WARN" >&2

STATUS=built
[ "$MODE" = dispatch ] && STATUS=dispatched
ROW="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\t\t\t\t\t\t' "$(today)" "$OR" "$TICKET" "$BRANCH" "$MODEL/$EFFORT" "$BYTES" "$CREDIT" "$STATUS")"
cloud_ledger_init "$CLOUD_LEDGER" || die 2 "cannot create the ledger $CLOUD_LEDGER"
cloud_ledger_lock "$CLOUD_LEDGER" || die 2 "the ledger is locked"
reason="$(ledger_refusal)"
if [ -n "$reason" ]; then cloud_ledger_unlock "$CLOUD_LEDGER"; refuse ledger "$reason"; fi
cloud_ledger_put "$CLOUD_LEDGER" "$OR" "$TICKET" "$ROW" || { cloud_ledger_unlock "$CLOUD_LEDGER"; die 2 "cannot write $CLOUD_LEDGER"; }
cloud_ledger_unlock "$CLOUD_LEDGER"

Q_ENGINE="$(printf '%q' "$ENGINE")" Q_MAIN="$(printf '%q' "$MAIN")" Q_TICKET="$(printf '%q' "$TICKET")"
LAND="$Q_ENGINE/tools/cloud-land.sh $Q_MAIN <PR#> --ticket $Q_TICKET"
SWEEP="$Q_ENGINE/tools/cloud-brief.sh $Q_MAIN --sweep"

if [ "$MODE" != dispatch ]; then
  if [ "$MODE" = eligible ] && [ "$VERDICT" = none ]; then
    printf '\nWrite this line into the ticket body, beside **Model rec:**:\n  **Cloud:** yes (%s, <who>)\n' "$(today)"
  fi
  cat <<NEXT

Dispatch, on the operator's yes (docs/cloud.md):
  $Q_ENGINE/tools/cloud-brief.sh $Q_MAIN $Q_TICKET --dispatch
Land, once the session's draft PR exists:
  $LAND
NEXT
  exit 0
fi

# --- dispatch: the CLI, from the main checkout, on a pseudo-terminal ---------------------------------------------
back_to_built() {
  cloud_ledger_lock "$CLOUD_LEDGER" || { echo "cloud-brief: the row stays dispatched — set it to built by hand" >&2; return; }
  cloud_ledger_set "$CLOUD_LEDGER" "$OR" "$TICKET" 8=built || echo "cloud-brief: cannot set the row back to built" >&2
  cloud_ledger_unlock "$CLOUD_LEDGER"
}
CLI_CMD="claude --cloud \"\$(cat $(printf '%q' "$DEST"))\" --model $MODEL --effort $EFFORT"
# The CLI records its pid first, so a stuck run can be killed: `exec` keeps the pid, `script` ends with its child.
printf 'cd %q || exit 1\necho $$ > %q\nexec %s\n' "$MAIN" "$WORK/cli.pid" "$CLI_CMD" > "$WORK/run-cli.sh"
cli_rc=0
if ! command -v script >/dev/null 2>&1; then
  back_to_built
  die 5 "no \`script\` to give the CLI the terminal it requires — run this in a terminal, from $MAIN:
  $CLI_CMD"
fi
# cli_clean FILE — the CLI's output with terminal escapes, carriage returns and backspaces removed.
cli_clean() {
  local esc
  esc="$(printf '\033')"
  LC_ALL=C sed -e "s/${esc}\[[0-9;?<>=]*[A-Za-z]//g" -e "s/${esc}[()][A-Za-z0-9]//g" -e "s/${esc}[0-9=>]//g" \
    -e 's/\^D//g' "$1" 2>/dev/null | LC_ALL=C tr -d '\r\010'
}
# The CLI runs in the background and is watched: it stops on an interactive prompt nobody answers (dir #926), so a
# folder-trust prompt in its output, or CLOUD_DISPATCH_TIMEOUT seconds (default 300) without an exit, ends it.
case "$(uname -s)" in
  Darwin) script -q "$WORK/cli.out" bash "$WORK/run-cli.sh" < /dev/null > /dev/null 2>&1 & ;;
  *) script -qefc "bash $(printf '%q' "$WORK/run-cli.sh")" "$WORK/cli.out" < /dev/null > /dev/null 2>&1 & ;;
esac
script_pid=$!
dispatch_timeout="${CLOUD_DISPATCH_TIMEOUT:-300}"
case "$dispatch_timeout" in '' | *[!0-9]*) dispatch_timeout=300 ;; esac
stuck="" waited=0
while kill -0 "$script_pid" 2>/dev/null; do
  # A captured variable, not `cli_clean | grep -q`: grep's early exit would fail the pipeline under pipefail.
  seen="$(cli_clean "$WORK/cli.out")"
  if grep -qE 'Is this a project you created or one you trust|Yes, I trust this folder' <<< "$seen"; then
    stuck=trust; break
  fi
  if [ "$waited" -ge "$dispatch_timeout" ]; then stuck=timeout; break; fi
  sleep 1
  waited=$((waited + 1))
done
if [ -n "$stuck" ]; then
  cli_pid="$(cat "$WORK/cli.pid" 2>/dev/null || true)"
  if [ -n "$cli_pid" ]; then kill "$cli_pid" 2>/dev/null || true; sleep 1; kill -9 "$cli_pid" 2>/dev/null || true; fi
  kill "$script_pid" 2>/dev/null || true
fi
wait "$script_pid" 2>/dev/null || cli_rc=$?
CLI_OUT="$(cli_clean "$WORK/cli.out")"
printf '%s\n' "$CLI_OUT"
# util-linux `script` may answer with its own status, so success also needs the CLI's own line.
if [ "$stuck" = trust ]; then
  back_to_built
  die 5 "the CLI stopped on its folder-trust prompt — the row is back to built; nothing was claimed. The CLI has never trusted $MAIN: run \`claude\` once in $MAIN, answer 'Yes, I trust this folder', exit, then dispatch again (this tool never answers the prompt for you)"
fi
if [ "$stuck" = timeout ]; then
  back_to_built
  die 5 "the CLI did not finish within ${dispatch_timeout}s (an interactive prompt may be waiting) — killed; the row is back to built; nothing was claimed. Run it by hand, from $MAIN:
  $CLI_CMD"
fi
if [ "$cli_rc" -ne 0 ] || ! grep -q 'Created cloud session' <<< "$CLI_OUT"; then
  back_to_built
  die 5 "the dispatch failed (exit $cli_rc) — the row is back to built; nothing was claimed"
fi

SESSION="$(grep -oE 'session_[A-Za-z0-9]+' <<< "$CLI_OUT" | head -1 || true)"
CLAIM="⏳ IN FLIGHT ($(today), branch $BRANCH, cloud)"
# The claim goes after the heading's LAST physical line: re-walk backlog_ticket_blocks' wrapped-heading rule over
# the block, and trust the walk only when it rebuilds the flattened HEADING exactly.
claim_at=""
heading_walk
[ -z "$HEADING" ] || ! walk_ok || claim_at="$(sed -n "$((START + WALK_N))p" "$BACKLOG" | tr -d '\r') — $CLAIM"
[ -n "$claim_at" ] || claim_at="(append \` — $CLAIM\` to the end of the heading — its last line)"
# The session id is never written into the ticket (dir #913): the Log line carries none, a gitignored backlog's
# included — no scan reads a bare `session_<id>` there. It lives only in the local ledger row, set here.
LOG="Log: $(today) — dispatched to a cloud session on $BRANCH ($MODEL/$EFFORT)"
if [ -n "$SESSION" ]; then
  if cloud_ledger_lock "$CLOUD_LEDGER"; then
    cloud_ledger_set "$CLOUD_LEDGER" "$OR" "$TICKET" "15=$SESSION" || echo "cloud-brief: cannot record the session id $SESSION on the ledger row — keep it for \`claude --cloud <session id>\`" >&2
    cloud_ledger_unlock "$CLOUD_LEDGER"
  else
    echo "cloud-brief: the session id $SESSION was not recorded on the ledger row — keep it for \`claude --cloud <session id>\`" >&2
  fi
fi
cat <<NEXT

Claim — append to the heading with an edit tool, then add the Log line to the body:
  $CLAIM
  $claim_at
  $LOG
The PR will appear on $BRANCH. Land it (the operator, or a local session the operator asks):
  $LAND
Find it, or a dispatch that never produced one:
  $SWEEP
NEXT
exit 0
