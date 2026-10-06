#!/usr/bin/env bash
# go-handoff — dir #401: the ticket-level handoff note an interrupted `/go` session leaves behind and the
# next `/go` on the same ticket reads before it reconciles. State that exists only in a session's context
# (what is done and proven, where work stopped, what lives outside the commit) is lost when the session
# ends; this keeps it in ONE small keyed file in keel's state root, never in the repo, never committed.
# An aid, never a gate: the note is a dated hint, a live file that disagrees wins.
#
# Usage (run from inside the repo being worked on, as `/polish` runs its tool; QUOTE the ticket — an
# unquoted `dir #401` reaches the tool as `dir`, `#401` being a shell comment):
#   tools/go-handoff.sh write "<ticket>"   stdin = the three fields below; replaces the note atomically
#   tools/go-handoff.sh read  "<ticket>"   prints the note, then one last line `verdict: <v>`; exit 1 and
#                                          no output when there is no note (or it belongs to another ticket)
#   tools/go-handoff.sh clear "<ticket>"   removes the note; an absent note is exit 0
#
# The note is `$HOME/.keel/tmp/go-handoff/<repo-key>/<ticket-key>` (under tools/lib/gate-paths.sh's
# gate_state_root). <repo-key> is `tools/pre-pr-gate.sh repo-key` — worktree-aware, so identical from every
# worktree of one repo; <ticket-key> is the ticket with every byte outside [A-Za-z0-9._-] turned into `-`,
# runs of `-` collapsed, leading and trailing `-`/`.` stripped. The ticket is the CANONICAL id of the
# heading `/go` resolved (`dir #401`, `KB.34`, `34`), never the argument as typed. A bare alphabetic word
# (`dir`: what an unquoted `dir #401` delivers) and an empty key are refused, so two tickets never share
# a key by accident; the stored `ticket:` line is compared on `read`, so a genuine key collision
# (`dir #401` vs `dir-401`) reads as "no note".
#
# Note format — five header lines the tool writes, then the three fields from stdin:
#   ticket: <ticket verbatim>          branch: <current branch | none>     worktree: <toplevel | none>
#   head: <HEAD sha | none>            written: <UTC YYYY-MM-DDTHH:MM:SSZ>
#   done: <items finished AND verified, each with its proof | none>
#   next: <the open items in order — the first is the next action — and why the session stopped>
#   carry: <what exists only outside the commit: uncommitted files, scratch paths, red tests | none>
# stdin rules: the keys done:/next:/carry: each appear exactly once, at a line start, in that order, each
# with non-empty text; a line that starts a key the tool owns (ticket: branch: worktree: head: written:
# verdict:) is refused, so a caller cannot spoof a header or `read`'s last line.
#
# `read`'s verdict compares the note's `head` with the reader's HEAD: `fresh` (equal), `behind <n>` (the
# note's head is an ancestor, n commits behind), `ahead <n>` (HEAD is an ancestor of the note's head — the
# predecessor committed beyond the reader), `unrelated` (neither: rebased, diverged, object gone, or not a
# sha), `unknown` (`head: none`, or the reader is not in git).
#
# Exit codes: 0 ok · 1 `read` found no note · 2 bad usage or input (a stdin rule, a bad or bare-word key,
# an unknown verb, a bad config value) with any previous note untouched · 3 `$HOME` cannot back the root,
# or the root cannot be written.
#
# Config (environment; a value that is not a positive integer is exit 2 naming the key, never a silent
# fallback — a silent fallback on PRUNE_DAYS could prune everything):
#   KEEL_GO_HANDOFF_PRUNE_DAYS   age in days past which notes (and .tmp. residue) under go-handoff/ are
#                                deleted by mtime — after a `read` has answered, and after a `write` (30)
#   KEEL_GO_HANDOFF_MAX_BYTES    the most stdin bytes a `write` accepts; exactly the bound is accepted (4096)
# No override for the root: tests redirect $HOME (tests/lib.sh), as gate-paths.sh documents.
#
# Adopter note: like every tools/ script this lives in the Keel checkout, not in the project being worked
# on. A copy-mode install (`KEEL_EPHEMERAL`) has no kept checkout and so no note — a named non-goal.
set -euo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
LC_ALL=C; export LC_ALL
umask 077

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/gate-paths.sh
. "$SELF_DIR/lib/gate-paths.sh"
# shellcheck source=tools/lib/nonneg-int.sh
. "$SELF_DIR/lib/nonneg-int.sh"

die() { printf 'go-handoff: %s\n' "$1" >&2; exit "${2:-2}"; }

# positive_int KEY DEFAULT — prints the env value of KEY (or DEFAULT), exit 2 naming KEY if it is not a
# positive integer (zero excluded).
positive_int() {
  local key="$1" val
  val="${!key:-$2}"
  if _nonneg_int_valid "$val" && [ "$val" -gt 0 ]; then
    printf '%s' "$val"
  else
    die "$key must be a positive integer (got '$val')"
  fi
}

verb="${1:-}"
case "$verb" in
  write|read|clear) ;;
  -h|--help) sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
  *) die "usage: go-handoff.sh write|read|clear \"<ticket>\"  (see --help)" ;;
esac
[ "$#" -eq 2 ] || die "usage: go-handoff.sh $verb \"<ticket>\" — exactly one ticket argument, quoted"
ticket="$2"

# --- the ticket and its key (B1) ----------------------------------------------------------------------
case "$ticket" in
  *$'\n'*|*$'\r'*) die "the ticket must be one line" ;;
esac
[ "${#ticket}" -le 200 ] || die "the ticket is longer than 200 bytes"
case "$ticket" in
  ''|*[!A-Za-z]*) ;;   # empty or not a bare alphabetic word → fall through to the key check below
  *) die "'$ticket' is a bare word — quote the full ticket id, e.g. \"dir #401\" (an unquoted #401 is a shell comment)" ;;
esac
tkey="$(printf '%s' "$ticket" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-' | sed -e 's/^[-.]*//' -e 's/[-.]*$//')"
[ -n "$tkey" ] || die "the ticket '$ticket' leaves an empty key — quote the full ticket id"

prune_days=""; max_bytes=""
case "$verb" in
  write) prune_days="$(positive_int KEEL_GO_HANDOFF_PRUNE_DAYS 30)"; max_bytes="$(positive_int KEEL_GO_HANDOFF_MAX_BYTES 4096)" ;;
  read)  prune_days="$(positive_int KEEL_GO_HANDOFF_PRUNE_DAYS 30)" ;;
esac

# --- the root (B1) -----------------------------------------------------------------------------------
state_root="$(gate_state_root)" || die "\$HOME $(gate_home_diagnosis) — cannot place the handoff root" 3
hroot="$state_root/go-handoff"
repo_key="$(bash "$SELF_DIR/pre-pr-gate.sh" repo-key "$PWD" 2>/dev/null)" || repo_key=""
[ -n "$repo_key" ] || die "cannot derive the repo key from $PWD" 3
ndir="$hroot/$repo_key"
note="$ndir/$tkey"

# prune — delete files older than prune_days under go-handoff/ only (files, never a symlink target,
# never anything outside hroot).
prune() {
  [ -d "$hroot" ] || return 0
  find "$hroot" -type f -mtime "+$prune_days" -exec rm -f {} + 2>/dev/null || true
}

# in_git — 0 when the cwd is inside a git work tree.
in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

case "$verb" in
# --- clear -------------------------------------------------------------------------------------------
clear)
  rm -f "$note" 2>/dev/null || die "cannot remove $note" 3
  exit 0
  ;;

# --- write -------------------------------------------------------------------------------------------
write)
  # stdin: at most max_bytes+1 bytes are read, so an endless stream cannot hang or fill memory. The
  # trailing `x` keeps the final newlines through the command substitution.
  body="$(head -c "$((max_bytes + 1))"; printf x)"; body="${body%x}"
  [ "${#body}" -le "$max_bytes" ] || die "stdin is over KEEL_GO_HANDOFF_MAX_BYTES ($max_bytes bytes) — a note is a note, not a transcript"
  case "$body" in *$'\n') ;; *) body="$body"$'\n' ;; esac

  want="done"; seen_text=0; ndone=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ticket:*|branch:*|worktree:*|head:*|written:*|verdict:*)
        die "stdin has a line starting '${line%%:*}:' — that key is the tool's own" ;;
      done:*|next:*|carry:*)
        key="${line%%:*}"
        [ "$key" = "$want" ] || die "stdin key '$key:' is duplicated or out of order (the order is done:, next:, carry:, each once)"
        if [ "$ndone" -gt 0 ] && [ "$seen_text" -eq 0 ]; then die "the field before '$key:' is empty — say 'none' when there is nothing"; fi
        ndone=$((ndone + 1)); seen_text=0
        case "$key" in done) want=next ;; next) want=carry ;; carry) want=end ;; esac
        rest="${line#*:}"
        case "$rest" in *[![:space:]]*) seen_text=1 ;; esac
        ;;
      *)
        if [ "$ndone" -eq 0 ]; then
          case "$line" in *[![:space:]]*) die "stdin text before 'done:' — the three fields are all there is" ;; esac
        else
          case "$line" in *[![:space:]]*) seen_text=1 ;; esac
        fi
        ;;
    esac
  done <<EOF
$body
EOF
  [ "$ndone" -eq 3 ] || die "stdin needs the three fields done:, next:, carry: (found $ndone)"
  [ "$seen_text" -eq 1 ] || die "the last field is empty — say 'none' when there is nothing"

  b="none"; w="none"; h="none"
  if in_git; then
    b="$(git branch --show-current 2>/dev/null || true)"; [ -n "$b" ] || b="none"
    w="$(git rev-parse --show-toplevel 2>/dev/null || true)"; [ -n "$w" ] || w="none"
    h="$(git rev-parse HEAD 2>/dev/null || true)"; [ -n "$h" ] || h="none"
  fi

  gate_ensure_owner_dir "$hroot"
  gate_ensure_owner_dir "$ndir"
  [ -d "$ndir" ] || die "cannot create $ndir" 3
  tmp="$ndir/$tkey.tmp.$$"
  if ! { printf 'ticket: %s\nbranch: %s\nworktree: %s\nhead: %s\nwritten: %s\n' \
           "$ticket" "$b" "$w" "$h" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
         printf '%s' "$body"; } > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; die "cannot write $tmp" 3
  fi
  if ! mv -f "$tmp" "$note" 2>/dev/null; then
    rm -f "$tmp"; die "cannot replace $note" 3
  fi
  prune
  exit 0
  ;;

# --- read --------------------------------------------------------------------------------------------
read)
  # No note, or a note of another ticket (a key collision) → nothing on stdout, exit 1; prune either way.
  if [ ! -f "$note" ] || [ "$(head -n 1 "$note" 2>/dev/null)" != "ticket: $ticket" ]; then
    prune
    exit 1
  fi
  nhead="$(sed -n -e '/^head: /{s///p;q;}' "$note")"
  verdict=unknown
  if [ "$nhead" != none ] && in_git && cur="$(git rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"; then
    case "$nhead" in
      *[!0-9a-f]*|'') verdict=unrelated ;;
      *)
        if [ "$nhead" = "$cur" ]; then
          verdict=fresh
        else
          rc=0; git merge-base --is-ancestor "$nhead" "$cur" 2>/dev/null || rc=$?
          if [ "$rc" -eq 0 ]; then
            verdict="behind $(git rev-list --count "$nhead..$cur" 2>/dev/null || echo '?')"
          else
            rc=0; git merge-base --is-ancestor "$cur" "$nhead" 2>/dev/null || rc=$?
            if [ "$rc" -eq 0 ]; then
              verdict="ahead $(git rev-list --count "$cur..$nhead" 2>/dev/null || echo '?')"
            else
              verdict=unrelated
            fi
          fi
        fi
        ;;
    esac
  fi
  cat "$note"
  printf 'verdict: %s\n' "$verdict"
  prune
  exit 0
  ;;
esac
