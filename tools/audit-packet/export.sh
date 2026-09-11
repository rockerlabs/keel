#!/usr/bin/env bash
# tools/audit-packet/export.sh — dir #495 PR1: build a leak-gated audit packet for a human-driven,
# unscriptable vendor UI (first target: "Astra", an OpenAI-family corporate UI a colleague drives —
# no API, no CLI, this machine cannot reach it). Full procedure: docs/drydock.md, "The external leg".
#
# Adopter-facing: procedure-NEUTRAL by design — this tool never decides WHICH files are audited. The
# caller supplies the file list (one repo-relative path per line, from stdin or --files FILE):
# tools/drydock/inventory.sh's --paths mode for a whole-tree drydock run, or
# tools/delta-audit/derive.sh's delta-files.txt for a release-range delta. Both are plain path lists
# by design so this tool stays foreign to neither tools/drydock/ nor tools/delta-audit/.
#
# Usage:
#   inventory.sh --paths | export.sh --vendor astra [--files -] [options...]
#   cat delta-files.txt  | export.sh --vendor astra --known KNOWN.md
#
#   --vendor <name>        required. Names the packet dir and the imported audit files'
#                           `auditor: external/<vendor>` line.
#   --files <FILE>         repo-relative paths, one per line ('-' or omitted = stdin).
#   --baseline <rev>       the commit this packet audits (default: origin/main). HEAD must equal it.
#   --out <dir>            where to write the packet dir (default: private/audit/external/).
#   --chunk-bytes <n>      max content bytes per non-historical chunk (default: 400000 — a
#                           placeholder until PROBE.md's reply answers the real window).
#   --probe-bytes <n>      PROBE.md's filler size (default: 1000000).
#   --known <FILE>         copied into the packet as KNOWN.md (the standing accepted-findings list);
#                           absent -> PROMPT.md says "no known list".
#   --disclosure-ack <txt> required for a non-keel repo (recorded verbatim into MANIFEST.txt) — a
#                           per-project human decision made visible, never a flag that flips. For
#                           keel itself (detected via the 'origin' remote) this defaults to
#                           "keel: public repository" and does not need to be passed.
#   --historical <path>    a file that gets its OWN trailing chunk, never packed with others
#                           (repeatable; default: CHANGELOG.md). Pass --historical '' once to disable
#                           the default and treat CHANGELOG.md as ordinary content.
#   --value-prompt          emit PROMPT-value.md (the second ask: an independent value assessment,
#   --no-value-prompt        applied to the prose chunk(s) — see the ticket's 2026-09-11 amendment).
#                           Default: on for keel (the same remote detection as --disclosure-ack),
#                           off otherwise — pass one of these two flags explicitly to override.
#   -h, --help              this message.
#
# Exit codes: 0 written · 2 bad arguments / a listed file does not resolve at the baseline ·
# 3 refused (not a repo / dirty tree / wrong HEAD / packet dir exists / the leak gate found a hit).
#
# The leak gate is not optional and has no bypass — there is no --force and no --skip-scan. Before a
# single chunk byte is written, every listed file is scanned by tools/secret-guard/secret-scan.sh's
# FILE-list mode (its usage line 33: `secret-scan.sh FILE...` — already shipped, exercised by its own
# selftest; TO VERIFY 2 resolved: no new scanner mode or public-audit.sh fallback needed). HEAD equals
# baseline and the tree is clean (enforced by the guard below), so the working-tree bytes ARE the
# baseline's tracked bytes — scanning the files on disk is scanning exactly what will be embedded. On
# any hit, this refuses (exit 3) and prints ONLY the offending paths, never the matched content —
# stricter than secret-scan.sh's own terminal output (which prints the matched line, meant for a
# human at their own keyboard): a packet-export's stderr can end up in a session transcript or a CI
# log, a wider exposure than a local pre-commit hook's.
#
# PROMPT.md's role-prompt BODY is read from docs/drydock/external-auditor.md (PR2, a later worker's
# ticket — absent until PR2 merges, refused with a clear message meanwhile) and is NOT expected to
# carry export.sh-specific placeholder tokens: this script prepends its own dynamically generated
# context block (baseline SHA, repo, chunk id, the known-list note) ahead of that doc's static content,
# the same "context block + copy-pasted role prompt" shape the four in-house role prompts already use
# for a human copying them by hand (docs/drydock/auditor.md's `<baseline-sha>`-style placeholders) —
# except here the SUBSTITUTION is mechanical, since the recipient is a third party, not an agent
# session. If docs/drydock/external-auditor.md DOES contain `<baseline-sha>`, `<repo-name>`, or
# `<chunk-id>` literally, those three tokens are substituted too, matching auditor.md's own convention
# — harmless no-ops otherwise.
#
# Chunking: markdown files (scope A, minus --historical) first, whole-files-first-fit up to
# --chunk-bytes; then the remaining (non-md) files the same way; then each --historical file gets its
# OWN trailing chunk, never packed with anything else, regardless of size. "First-fit" here means:
# try the currently open chunk; if the next file doesn't fit, close it and open a new one — never
# re-visit an earlier closed chunk. True first-fit-with-backtracking (checking every earlier open
# chunk for room) was considered and rejected: it could place a later file into an earlier,
# already-mostly-full chunk out of order, silently breaking the "*.md before code, chunks in read
# order" guarantee for a marginal packing-density gain this tool doesn't need. A file bigger than
# --chunk-bytes on its own becomes a solo OVERSIZE chunk (MANIFEST.txt says so) rather than being
# refused or truncated — the file still has to reach the vendor somehow.
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

err()      { printf 'audit-packet export: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/lib/nonneg-int.sh
. "$script_dir/../lib/nonneg-int.sh"

vendor=""
files_arg=""
baseline_rev="origin/main"
out_dir="private/audit/external/"
chunk_bytes="400000"
probe_bytes="1000000"
known_file=""
disclosure_ack=""
disclosure_ack_set=0
historical=(CHANGELOG.md)
historical_set=0
value_prompt=""   # "" = unset (decide from remote), "1" = on, "0" = off

while [ $# -gt 0 ]; do
  case "$1" in
    --vendor)         [ $# -ge 2 ] || die_args "--vendor needs a name"; vendor="$2"; shift 2 ;;
    --files)          [ $# -ge 2 ] || die_args "--files needs a path"; files_arg="$2"; shift 2 ;;
    --baseline)       [ $# -ge 2 ] || die_args "--baseline needs a rev"; baseline_rev="$2"; shift 2 ;;
    --out)            [ $# -ge 2 ] || die_args "--out needs a directory"; out_dir="$2"; shift 2 ;;
    --chunk-bytes)    [ $# -ge 2 ] || die_args "--chunk-bytes needs a number"; chunk_bytes="$2"; shift 2 ;;
    --probe-bytes)    [ $# -ge 2 ] || die_args "--probe-bytes needs a number"; probe_bytes="$2"; shift 2 ;;
    --known)          [ $# -ge 2 ] || die_args "--known needs a path"; known_file="$2"; shift 2 ;;
    --disclosure-ack) [ $# -ge 2 ] || die_args "--disclosure-ack needs text"; disclosure_ack="$2"; disclosure_ack_set=1; shift 2 ;;
    --historical)
      [ $# -ge 2 ] || die_args "--historical needs a path"
      # Clear the CHANGELOG.md default only on the FIRST call, and only when its value is the
      # empty-string disable idiom (`--historical ''`) — never merely because it's the first call.
      # The earlier shape cleared on any first call regardless of value, so `--historical
      # BACKLOG.md` (meant to ADD a second historical file, per --help's own "repeatable" contract)
      # silently dropped CHANGELOG.md instead of keeping it — found live, code review high, Angle A.
      if [ "$historical_set" = 0 ] && [ -z "$2" ]; then historical=(); fi
      [ -z "$2" ] || historical+=("$2")
      historical_set=1
      shift 2 ;;
    --value-prompt)    value_prompt=1; shift ;;
    --no-value-prompt) value_prompt=0; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                die_args "unknown option '$1' (see --help)" ;;
    *)                 die_args "unexpected argument '$1' (see --help)" ;;
  esac
done

[ -n "$vendor" ] || die_args "--vendor is required (see --help)"
case "$vendor" in */*|.|..) die_args "--vendor '$vendor' must be a plain name, not a path" ;; esac
_nonneg_int_valid "$chunk_bytes" || die_args "--chunk-bytes must be a non-negative integer"
[ "$chunk_bytes" -gt 0 ] || die_args "--chunk-bytes must be greater than zero"
_nonneg_int_valid "$probe_bytes" || die_args "--probe-bytes must be a non-negative integer"

# --- the guard --------------------------------------------------------------------------------
# Reuses tools/drydock/inventory.sh's refusal semantics (same messages' intent, same exit code): HEAD
# must equal --baseline, the tree must be clean, there is no --force. Not literally sourced from
# inventory.sh — its guard block is written against ITS OWN variable names as inline top-level script
# code, not exposed as a callable function, and refactoring a shipped, heavily-tested guard into a
# shared lib is a bigger, separate change this ticket does not need to make (flagged in the PR1
# checkpoint report as a possible follow-up, not done here).
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || refuse "not a git repository (run this inside the tree you are exporting from)"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

baseline="$(git rev-parse --verify --quiet "${baseline_rev}^{commit}" || true)"
[ -n "$baseline" ] || die_args "cannot resolve baseline '$baseline_rev' — fetch first (git fetch
  --prune), or name the commit yourself with --baseline <rev>."
baseline7="${baseline:0:7}"

head_sha="$(git rev-parse --verify --quiet HEAD || true)"
[ -n "$head_sha" ] || refuse "this repository has no commits yet (unborn HEAD) — nothing to export."
if [ "$head_sha" != "$baseline" ]; then
  refuse "refusing to export — HEAD is not the baseline.
  HEAD     $head_sha ($(git rev-parse --abbrev-ref HEAD))
  baseline $baseline ($baseline_rev)
A packet exported off the baseline would ship content nobody chose. Check out the baseline, or name
this tree's own HEAD explicitly:
  --baseline $head_sha"
fi

dirty="$(git status --porcelain)"
if [ -n "$dirty" ]; then
  refuse "refusing to export a dirty working tree — the packet would not describe any one commit.
$(head -10 <<< "$dirty" | sed 's/^/  /')
Commit, stash, or discard the above (ignored files are not dirt and are already excluded)."
fi

remote_url="$(git remote get-url origin 2>/dev/null || true)"
is_keel=0
case "$remote_url" in
  *github.com*rockerlabs/keel|*github.com*rockerlabs/keel.git) is_keel=1 ;;
esac

if [ "$disclosure_ack_set" = 0 ]; then
  if [ "$is_keel" = 1 ]; then
    disclosure_ack="keel: public repository"
  else
    die_args "--disclosure-ack \"<project>: <one-line reason it may leave>\" is required for a
  non-keel repo — a per-project human decision recorded into MANIFEST.txt, not a flag that flips.
  ('origin' resolved to '${remote_url:-<no remote>}', not rockerlabs/keel.)"
  fi
fi

# Default --value-prompt from the same remote detection as --disclosure-ack, per --help's own
# documented contract ("Default: on for keel ... off otherwise") — dropped during an earlier edit
# pass and caught live by code-review high's cleanup-pass agent (reproduced: a fresh keel-remote
# export with no --value-prompt flag wrote "value-prompt: skipped" instead of emitting
# PROMPT-value.md). Only fires when the flag wasn't passed explicitly (value_prompt is still "").
if [ -z "$value_prompt" ]; then
  if [ "$is_keel" = 1 ]; then value_prompt=1; else value_prompt=0; fi
fi

# One scratch dir for every intermediate file below, cleaned unconditionally on exit — including a
# refusal partway through (tools/drydock/inventory.sh's own established pattern). Created here,
# before the file-list read below, since that read now spools through it too.
scratch="$(mktemp -d)"
ok=""
on_exit() {
  st=$?
  [ -n "$ok" ] || [ "$st" -ne 0 ] || st=1
  rm -rf "$scratch"
  exit "$st"
}
trap on_exit EXIT

# --- the file list ------------------------------------------------------------------------------
# One repo-relative path per line, from --files FILE or stdin ('-' means stdin explicitly). Blank
# lines skipped; a trailing CR tolerated (a list pasted from a Windows editor), same as
# secret-scan.sh's own allowlist reader.
filelist_raw="$scratch/filelist.raw"
if [ -n "$files_arg" ] && [ "$files_arg" != "-" ]; then
  cat "$files_arg" > "$filelist_raw" 2>/dev/null || die_args "cannot read --files '$files_arg'"
else
  cat > "$filelist_raw"
fi

files=()
TAB="$(printf '\t')"
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [ -n "$line" ] || continue
  case "$line" in
    *"$TAB"*) die_args "path '$line' contains a tab — cannot be represented in the chunk header or
  MANIFEST.txt" ;;
  esac
  files+=("$line")
done < "$filelist_raw"

[ "${#files[@]}" -gt 0 ] || die_args "the file list is empty — nothing to export. Pipe a caller's
  path list in (inventory.sh --paths, or delta-audit's delta-files.txt), or pass --files FILE."

# Every listed path must be a real blob at the baseline — a bad caller-supplied list is a refusal,
# never a silent omission (the same discipline tools/drydock/inventory.sh's readability check uses).
for f in "${files[@]}"; do
  git cat-file -e "$baseline:$f" 2>/dev/null \
    || die_args "'$f' is not a tracked file at $baseline7 — the caller's file list disagrees with
  the tree. Re-derive it (inventory.sh --paths / delta-audit's delta-files.txt) against this exact
  baseline."
done

# --- the leak gate — before a single chunk byte is written -----------------------------------------
# Resolved relative to THIS script's own install location, not the audited repo's root: the scanner
# ships alongside export.sh in the same tools/ tree (matching tools/drydock/inventory.sh's own
# convention for tools/self/shellcheck-targets.sh) — a non-keel adopter's repo being audited has no
# reason to carry its own copy, vendored or not, and must not silently lose the gate if it doesn't.
scan_script="$script_dir/../secret-guard/secret-scan.sh"
[ -x "$scan_script" ] || refuse "tools/secret-guard/secret-scan.sh is missing or not executable next
  to this script ($scan_script) — refusing to export without a working leak gate. There is no
  --skip-scan."

gate_err="$scratch/gate.err"
gate_status=0
# The listed FILES are not the only operator/caller-supplied text that ends up in the packet —
# --disclosure-ack and --vendor both land verbatim in MANIFEST.txt (and vendor also names the
# packet directory and the imported audit files' `auditor:` line). "The would-be packet content"
# means these too, not just the file list (dir #495 manager amendment W2-A1, after re-verifying TO
# VERIFY 2's premise was wrong — secret-scan.sh's FILE... mode already existed, no new scanner mode
# needed, but these two free-text fields were still unscanned). Spooled into scratch files and added
# to the SAME gate call rather than a second invocation, so one BLOCKED/clean verdict covers
# everything that ships.
ack_file="$scratch/gate-disclosure-ack.txt"
printf '%s\n' "$disclosure_ack" > "$ack_file"
vendor_file="$scratch/gate-vendor.txt"
printf '%s\n' "$vendor" > "$vendor_file"
# `--` is load-bearing, not decoration: secret-scan.sh dispatches its MODE off a bare $1, so without
# it a caller-supplied file list (this repo-agnostic exporter's whole point — the list is never fully
# ours to control) whose first entry happens to literally read "staged" (or start with "-") silently
# re-dispatches to a different mode instead of being scanned, reporting clean with the real content
# never inspected — reproduced live with a real key-shaped secret in a file named `staged`, code
# review high, Angle C. `--` forces every remaining argument to be treated as a literal filename.
"$scan_script" -- "${files[@]}" "$ack_file" "$vendor_file" >/dev/null 2>"$gate_err" || gate_status=$?

if [ "$gate_status" = 1 ]; then
  # BLOCKED — extract ONLY the leading path off each "  path:line:content" / "  path:(binary) match"
  # detail line (secret-scan.sh's own format, see its emit_stream/emit_blob). Splitting on the FIRST
  # colon (`cut -d: -f1`, equivalent to secret-scan.sh's own allowlist idiom `recpath="${rec%%:*}"`)
  # is deliberate, not a from-the-end sed: the matched CONTENT after the line number can itself
  # contain colons, and a from-the-end strip (tried first, caught live: a fixture line "leaked
  # token: ghp_..." left "path:3:leaked token" in the message — the word before its own colon
  # survived) leaks a fragment of the very text this gate exists to keep off this script's stderr.
  # Never the rest of the line, in any case: that portion carries the matched secret text, which
  # must not reach a session transcript or a CI log — a wider exposure than a human's own local
  # terminal, which is what secret-scan.sh's own output is written for.
  # A hit against $ack_file/$vendor_file would otherwise print a raw scratch-dir absolute path,
  # meaningless once $scratch is cleaned up on exit — relabel those two specifically.
  hit_paths="$(sed -n 's/^  //p' "$gate_err" | cut -d: -f1 \
    | sed -e "s#^$ack_file\$#--disclosure-ack text#" -e "s#^$vendor_file\$#--vendor text#" \
    | LC_ALL=C sort -u)"
  [ -n "$hit_paths" ] || hit_paths="(the gate reported a hit but its path could not be parsed — see
  tools/secret-guard/secret-scan.sh's own output by re-running it directly on the file list)"
  refuse "leak gate BLOCKED — secret-shaped string(s) or personal data found in:
$(printf '%s\n' "$hit_paths" | sed 's/^/  /')
Nothing was written. Remove the finding (or, for a genuine test fixture, an operator-approved
.secret-scan-allow entry — a human, out-of-band decision, never an agent's own workaround) and
re-export. There is no --force and no --skip-scan."
elif [ "$gate_status" != 0 ]; then
  refuse "leak gate failed to run (tools/secret-guard/secret-scan.sh exited $gate_status) — refusing
  to export without a clean gate. Its stderr:
$(sed 's/^/  /' "$gate_err")"
fi
gate_files_count="${#files[@]}"

# --- classify: markdown (minus historical) / code / historical -------------------------------------
# Exact-match array membership — same shape as tools/drydock/inventory.sh's own array_contains(),
# not shared with it (the two files don't currently source a common lib; see the guard block above
# for the same "not worth a cross-file extraction in this PR" call).
array_contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}
is_historical() { [ "${#historical[@]}" -gt 0 ] && array_contains "$1" "${historical[@]}"; }

md_files=()
code_files=()
hist_files=()
for f in "${files[@]}"; do
  if is_historical "$f"; then
    hist_files+=("$f")
  elif case "$f" in *.md) true ;; *) false ;; esac; then
    md_files+=("$f")
  else
    code_files+=("$f")
  fi
done

# --- pack into chunks --------------------------------------------------------------------------
NL=$'\n'
CHUNK_PATHS=()   # index i -> NL-joined repo-relative paths in chunk i+1
CHUNK_BYTES=()   # index i -> sum of tracked blob sizes in that chunk
CHUNK_OVERSIZE=()

pack_ordered() {  # $1 = cap, $@ = paths, in the order to pack them; each call starts a fresh chunk
  local cap="$1"; shift
  local path size idx cur_open=0
  for path in "$@"; do
    size="$(git cat-file -s "$baseline:$path" 2>/dev/null)" \
      || refuse "cannot read the tracked size of '$path' at $baseline7 — was it removed between the
  file-list read and this scan? Re-derive the list and re-export."
    if [ "$cur_open" = 1 ]; then
      idx=$(( ${#CHUNK_PATHS[@]} - 1 ))
      if [ $(( CHUNK_BYTES[idx] + size )) -le "$cap" ]; then
        CHUNK_PATHS[idx]="${CHUNK_PATHS[idx]}${path}${NL}"
        CHUNK_BYTES[idx]=$(( CHUNK_BYTES[idx] + size ))
        continue
      fi
      cur_open=0
    fi
    CHUNK_PATHS+=("${path}${NL}")
    CHUNK_BYTES+=("$size")
    CHUNK_OVERSIZE+=(0)
    idx=$(( ${#CHUNK_PATHS[@]} - 1 ))
    [ "$size" -gt "$cap" ] && CHUNK_OVERSIZE[idx]=1
    cur_open=1
  done
}

[ "${#md_files[@]}" -gt 0 ]   && pack_ordered "$chunk_bytes" "${md_files[@]}"
[ "${#code_files[@]}" -gt 0 ] && pack_ordered "$chunk_bytes" "${code_files[@]}"
# each historical file gets its OWN trailing chunk — one pack_ordered call per file, never batched
if [ "${#hist_files[@]}" -gt 0 ]; then
  for f in "${hist_files[@]}"; do
    pack_ordered "$chunk_bytes" "$f"
  done
fi

total_chunks="${#CHUNK_PATHS[@]}"
[ "$total_chunks" -gt 0 ] || refuse "packing produced zero chunks — this should be unreachable given
  a non-empty file list; please report this as a bug."
[ "$total_chunks" -le 99 ] || refuse "packing produced $total_chunks chunks — more than this tool's
  two-digit chunk numbering supports. Raise --chunk-bytes and re-export."

# --- write the packet ----------------------------------------------------------------------------
packet_date="$(date -u +%Y-%m-%d)"
packet_name="packet-${vendor}-${packet_date}-${baseline7}"
packet_dir="$out_dir/$packet_name"

[ ! -e "$packet_dir" ] || refuse "'$packet_dir' already exists — refusing to overwrite a prior
  packet. Remove it yourself if it is stale, or wait a day (the packet name includes the date)."
mkdir -p "$packet_dir/chunks" \
  || refuse "cannot create '$packet_dir' — check that '$out_dir' is writable."

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else printf 'sha256-unavailable'
  fi
}

# chunks/NN.txt — the run-audit.sh bundle format (private/audit-harness/run-audit.sh), plus the
# baseline stamp and the closing CHUNK-END line the importer and the external-auditor prompt both key
# on (the per-chunk truncation detector).
manifest_chunks=""
for i in $(seq 0 $((total_chunks - 1))); do
  chunk_num=$((i + 1))
  chunk_file="$packet_dir/chunks/$(printf '%02d' "$chunk_num").txt"
  : > "$chunk_file"
  n_files=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '===== FILE: %s @ %s =====\n' "$path" "$baseline7" >> "$chunk_file"
    git cat-file -p "$baseline:$path" >> "$chunk_file"
    printf '\n' >> "$chunk_file"
    n_files=$((n_files + 1))
  done <<< "${CHUNK_PATHS[i]}"
  printf 'CHUNK-END %02d files=%d bytes=%d\n' "$chunk_num" "$n_files" "${CHUNK_BYTES[i]}" >> "$chunk_file"
  sum="$(sha256_of "$chunk_file")"
  oversize_flag=""; [ "${CHUNK_OVERSIZE[i]}" = 1 ] && oversize_flag=" OVERSIZE"
  manifest_chunks="${manifest_chunks}chunk $(printf '%02d' "$chunk_num"): files=$n_files bytes=${CHUNK_BYTES[i]} sha256=$sum$oversize_flag${NL}"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    manifest_chunks="${manifest_chunks}  $path${NL}"
  done <<< "${CHUNK_PATHS[i]}"
done

# README-operator.md — the OTHER operator's procedure. English, <=40 lines, no judgment asked of them.
{
  printf '# Audit packet — operator instructions\n\n'
  printf 'This packet holds %d chunk(s) plus a window probe. Please follow these steps exactly.\n\n' "$total_chunks"
  printf '1. Upload (or paste) `PROBE.md` to the model FIRST, as its own message. This measures how\n'
  printf '   much it can actually hold — do this before anything else, even if you already know the\n'
  printf '   product'"'"'s advertised context size.\n\n'
  printf '2. For each chunk, in order (`chunks/01.txt`, `chunks/02.txt`, ...): upload or paste the\n'
  printf '   chunk, then paste `PROMPT.md` verbatim as your message. Save the model'"'"'s reply,\n'
  printf '   **completely unedited**, as `reply-01.md`, `reply-02.md`, and so on (matching the chunk\n'
  printf '   number). Please do not summarize, reformat, or correct anything in the reply.\n\n'
  if [ "$value_prompt" = 1 ]; then
    printf '3. Optional, and only after the audit chunks above: paste `PROMPT-value.md` (a different\n'
    printf '   kind of question — the project as a whole, not a defect hunt) to the same chat, and\n'
    printf '   save the reply unedited as `reply-value.md`. Skip this step if your time runs out —\n'
    printf '   the audit chunks come first.\n\n'
  fi
  printf 'When done, please zip and return every `reply-*.md` file. Thank you — no judgment call is\n'
  printf 'asked of you anywhere in this; just upload, paste, and save.\n'
} > "$packet_dir/README-operator.md"

# PROBE.md — packet 0, the cheapest possible first hand-off (never the full audit). A marker every
# 25 KB up to --probe-bytes, ending in PROBE-END; the reply sets --chunk-bytes for the real packet.
{
  printf 'This is a window probe, not an audit. Read to the end if you can, then reply with: the\n'
  printf 'LAST "PROBE-MARK" number you saw, and whether you reached "PROBE-END". Nothing else.\n\n'
  k=0
  emitted=0
  filler="the quick brown fox jumps over the lazy dog. "
  while [ "$emitted" -lt "$probe_bytes" ]; do
    if [ $(( emitted % 25000 )) -lt ${#filler} ]; then
      k=$((k + 1))
      mark="PROBE-MARK $k at ~$((k * 25))KB"
      printf '%s\n' "$mark"
      emitted=$((emitted + ${#mark} + 1))
    fi
    printf '%s\n' "$filler"
    emitted=$((emitted + ${#filler} + 1))
  done
  printf 'PROBE-END\n'
} > "$packet_dir/PROBE.md"

# PROMPT.md — the external-auditor role prompt: this script's own dynamic context block, then
# docs/drydock/external-auditor.md's static body (PR2 — absent until it merges).
auditor_doc="$repo_root/docs/drydock/external-auditor.md"
if [ ! -r "$auditor_doc" ]; then
  refuse "docs/drydock/external-auditor.md does not exist yet (dir #495 PR2, a separate ticket) —
  cannot build PROMPT.md without it. This tool works once both PR1 and PR2 have merged."
fi
known_note="No known list for this run — report everything you find."
[ -z "$known_file" ] || known_note="A KNOWN.md file accompanies this packet: previously accepted
findings, listed so you don't have to re-report closed ground."
{
  printf 'baseline: %s (%s)\n' "$baseline" "$baseline7"
  printf 'repo: %s\n' "${remote_url:-$repo_root}"
  printf 'vendor: %s\n' "$vendor"
  printf 'chunk: <fill in the chunk number you are pasting this alongside, e.g. 01>\n'
  printf '%s\n\n---\n\n' "$known_note"
  sed -e "s#<baseline-sha>#$baseline#g" -e "s#<repo-name>#${remote_url:-$repo_root}#g" \
      -e "s#<chunk-id>#<the chunk number you are pasting this alongside>#g" \
      "$auditor_doc"
} > "$packet_dir/PROMPT.md"

# KNOWN.md — optional, copied verbatim.
if [ -n "$known_file" ]; then
  cp "$known_file" "$packet_dir/KNOWN.md" || die_args "cannot read --known '$known_file'"
fi

# PROMPT-value.md — the second ask (2026-09-11 amendment): fixed, so replies are comparable across
# runs and vendors. Applied to the prose chunk(s) only, by the operator's own judgment of which
# chunk(s) hold PRINCIPLES.md/README.md/etc — this tool does not identify "the prose chunk" itself.
if [ "$value_prompt" = 1 ]; then
  {
    printf 'An independent assessment of this project as a whole — not a defect audit. Apply this to\n'
    printf 'the prose chunk(s) you were given (the ones holding PRINCIPLES.md, README.md, and similar\n'
    printf 'first-read documents), not the code chunks.\n\n'
    printf 'Answer, in <= 1500 words total, with confidence: high/medium/low per judgment:\n\n'
    printf '1. What problem does this solve, and for whom?\n'
    printf '2. What here is genuinely novel, versus a restatement of common practice?\n'
    printf '3. The three strongest and three weakest ideas — each with the quoted line that carries it\n'
    printf '   (a verbatim quote, never a line number — this reply will be read outside the repo).\n'
    printf '4. What would a first-time adopter fail to understand?\n'
    printf '5. Would you adopt it, and what would have to change first?\n'
  } > "$packet_dir/PROMPT-value.md"
fi

# MANIFEST.txt
{
  printf '# audit-packet MANIFEST — %s\n' "$packet_name"
  printf 'remote: %s\n' "${remote_url:-(no remote)}"
  printf 'baseline: %s (%s)\n' "$baseline" "$baseline_rev"
  printf 'exporter: tools/audit-packet/export.sh | files scanned: %d\n' "$gate_files_count"
  printf 'vendor: %s\n' "$vendor"
  printf 'disclosure-ack: %s\n' "$disclosure_ack"
  printf 'value-prompt: %s\n' "$([ "$value_prompt" = 1 ] && echo emitted || echo skipped)"
  printf 'generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'leak gate: clean (tools/secret-guard/secret-scan.sh, %d file(s) scanned)\n\n' "$gate_files_count"
  printf '## chunks\n'
  printf '%s' "$manifest_chunks"
} > "$packet_dir/MANIFEST.txt"

printf 'audit-packet export: wrote %s (%d chunks, leak gate clean)\n' "$packet_dir" "$total_chunks"
ok=1
