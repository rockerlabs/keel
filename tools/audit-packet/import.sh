#!/usr/bin/env bash
# tools/audit-packet/import.sh — dir #495 PR1: import an external auditor's replies into drydock's
# ordinary file contract. Full procedure: docs/drydock.md, "The external leg".
#
# Adopter-facing. Usage:
#   import.sh <reply-dir> <audit-dir>
#
#   <reply-dir>   the packet directory export.sh wrote (holds MANIFEST.txt and chunks/), with the
#                 operator's reply-NN.md files copied back into it. NOT a separate directory of just
#                 the replies — MANIFEST.txt's chunk/file map lives here too, and this script needs it
#                 to tell a mapped path from an unmapped one.
#   <audit-dir>   the run's drydock audit directory (created if missing) — the SAME directory phase 1
#                 writes <slug>-audit.md into, so phase 2 verifies both sets in one file.
#
# Exit codes: 0 every reply chunk imported cleanly · 1 at least one chunk FAILED (truncated/off-format
# — other chunks still imported; see stderr for which) · 2 bad arguments · 3 refused (reply-dir has no
# MANIFEST.txt, or audit-dir is unusable).
#
# What happens to each reply-NN.md: tolerates one wrapping code-fence line and chatter before the
# first `## <path>` heading. Refuses (FAILED, not a crash) a chunk whose first ~15 non-blank lines
# don't quote its own `CHUNK-END NN` line — the per-chunk truncation detector PROMPT.md's own rail
# asks the model to honor; a genuinely truncated or off-format reply never got far enough to include
# it, wherever the model puts it. Every `## <repo-relative path>` section splits into per-`### F<n>`
# finding blocks (claim:/evidence:/confidence:/verdict:); `verdict:` is FORCED empty regardless of
# what the model wrote there — verdicts are a phase-2 verifier's call, never the external model's own,
# same rule the in-house auditor prompts already carry. A path IN MANIFEST.txt's chunk map writes (or
# appends, numbering continued, under `## external findings`) into `<audit-dir>/<slug>-audit.md` in
# drydock's ordinary shape, `## claims` present with drydock's own dead-agent-marker line (honest:
# this leg has no tool access, so no claims were measured). A path NOT in MANIFEST.txt never gets a
# fabricated slug — it lands in `<audit-dir>/EXTERNAL-UNMAPPED.md` instead.
#
# `reply-value.md` (the independent project-value assessment, PR1's --value-prompt) is IGNORED
# entirely by this script — it is opinion, not a finding; drydock phase 2 has no verdict to issue on
# it. Read it yourself; nothing here touches it.
set -euo pipefail

usage() { sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

err()      { printf 'import.sh: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

reply_dir=""
audit_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*)        die_args "unknown option '$1' (see --help)" ;;
    *)
      if [ -z "$reply_dir" ]; then reply_dir="$1"
      elif [ -z "$audit_dir" ]; then audit_dir="$1"
      else die_args "unexpected argument '$1' — import.sh takes exactly two positional arguments"
      fi
      shift ;;
  esac
done
[ -n "$reply_dir" ] || die_args "missing <reply-dir> (see --help)"
[ -n "$audit_dir" ] || die_args "missing <audit-dir> (see --help)"

[ -d "$reply_dir" ] || refuse "'$reply_dir' is not a directory"
manifest="$reply_dir/MANIFEST.txt"
[ -r "$manifest" ] || refuse "'$manifest' not found — <reply-dir> must be the packet directory
  export.sh wrote (MANIFEST.txt + chunks/), with the operator's reply-*.md files copied back into it,
  not a bare directory of just the replies."

mkdir -p "$audit_dir" 2>/dev/null || refuse "cannot create '$audit_dir'"
[ -w "$audit_dir" ] || refuse "'$audit_dir' is not writable"
audit_dir="$(cd "$audit_dir" && pwd)"

# `|| true` OUTSIDE the $(...), not inside it: under this file's own `pipefail`, `head -1` can
# SIGPIPE the still-writing `sed` after it has already emitted its one line — the pipeline's exit
# status then lies (nonzero on a genuine match), but the captured value is unaffected (head read a
# line before it closed the pipe). `|| true` guards the ASSIGNMENT statement against that spurious
# status tripping `set -e`; putting it inside the substitution instead (`"$(cmd | head -1 ||
# true)"`) would leave the line ending in `)"`, not literally in `|| true` — tried first, and
# tests/test_no_pipe_sigpipe_race.sh's dir #280 static guard (a plain textual "ends with '|| true'"
# check, by design) does not recognize that shape as the safe idiom it otherwise is. The same idiom
# tools/lib/manifest.sh's manifest_field() uses, adapted for a captured value rather than a bare
# pipeline. `[ -n ... ] || refuse` right after each line is what actually checks success, never `$?`.
vendor="$(sed -n 's/^vendor: //p' "$manifest" | head -1)" || true
[ -n "$vendor" ] || refuse "'$manifest' has no 'vendor:' line — is this really an export.sh packet?"
baseline="$(sed -n 's/^baseline: \([^ ]*\).*/\1/p' "$manifest" | head -1)" || true
[ -n "$baseline" ] || refuse "'$manifest' has no 'baseline:' line"

# --- the known-path map, from MANIFEST.txt's "## chunks" section --------------------------------
# Every "  <path>" line (two leading spaces, distinguishing it from a "chunk NN: ..." header line)
# after "## chunks" is a path this packet actually shipped. NL-bracketed for the same substring-safe
# membership test used throughout this repo's other tools (tools/drydock/inventory.sh's is_changed).
NL=$'\n'
TAB="$(printf '\t')"
known_paths="$NL"
in_chunks=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    '## chunks') in_chunks=1; continue ;;
  esac
  [ "$in_chunks" = 1 ] || continue
  case "$line" in
    '  '*) known_paths="$known_paths${line#??}$NL" ;;
  esac
done < "$manifest"

scratch="$(mktemp -d)"
ok=""
on_exit() {
  st=$?
  [ -n "$ok" ] || [ "$st" -ne 0 ] || st=1
  rm -rf "$scratch"
  exit "$st"
}
trap on_exit EXIT

today="$(date -u +%Y-%m-%d)"

# next_finding_number FILE — 1 if FILE doesn't exist yet, else one past the highest existing "### F<n>"
# in it (findings already there from a same-family auditor's own phase-1 pass, or an earlier external
# import into this same file) — "numbering continued", per the ticket. `sort -n | tail -1` is safe
# under this file's own pipefail despite `tail`'s early exit: `sort` cannot write anything until it
# has read ALL of stdin, so there is no still-writing producer for `tail` to SIGPIPE (unlike a
# streaming producer — printf/grep -n — piped into `head`/`grep -q`, this file's own leak-gate-path
# extraction avoids exactly that class, see the manifest-field reads above). `|| true`: an empty
# match (no "### F" in FILE, or FILE absent) makes `grep` exit 1, which `set -e` would otherwise
# trip on this captured pipeline.
next_finding_number() {
  local f="$1" max
  max="$(grep -oE '^### F[0-9]+' "$f" 2>/dev/null | sed -E 's/^### F//' | sort -n | tail -1)" || true
  printf '%d' "$(( ${max:-0} + 1 ))"
}

# render_findings START_N SECFILE — SECFILE is one "## <path>" section's body (everything between
# that heading and the next one, or EOF). Emits each "### F<n> ..." block found in it, renumbered
# sequentially from START_N, keeping only claim:/evidence:/confidence: as the model wrote them and
# FORCING verdict: empty regardless of what the model put there — the external auditor never gets to
# rule on its own finding, the same rule the in-house role prompts already carry (docs/drydock.md's
# "empty verdict:" rail). Anything else inside a finding block (stray prose, a line matching none of
# the four field prefixes) is dropped rather than guessed at.
render_findings() {
  # `local start="$1" ... n="$start"` (one statement, n self-referencing a local just declared on
  # the same line) is NOT reliable on bash <4.0 under `set -u` — reproduced live on this machine's
  # bash 3.2.57: "start: unbound variable", even though $1 was non-empty (memory:
  # reference_bash_local_unset_boundary_is_4_0_not_4_4 documents the same class). Split into two
  # statements so `start` is a fully-established local before anything reads it.
  local start="$1" file="$2" in_finding=0 tail line
  local n="$start"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      '### F'[0-9]*)
        [ "$in_finding" = 1 ] && printf '\n'
        tail="$(printf '%s' "$line" | sed -E 's/^### F[0-9]+//')"
        printf '### F%d%s\n' "$n" "$tail"
        n=$((n + 1))
        in_finding=1
        continue
        ;;
    esac
    [ "$in_finding" = 1 ] || continue
    case "$line" in
      claim:*|evidence:*|confidence:*) printf '%s\n' "$line" ;;
      verdict:*) printf 'verdict:\n' ;;
    esac
  done < "$file"
}

# import_findings_into_contract SECFILE PATH AUDIT_FILE — new file: full drydock contract shape,
# `## claims` present with the honest dead-agent-marker line (this leg measured no claims — no tool
# access). Existing file (a same-family auditor already ran on this path): appended at the end under
# "## external findings", leaving whatever "## claims" that file already has exactly where it is —
# phase 3 reads claims sections wherever they occur, and appending at the end is the one placement
# that can never disturb an existing file's own completeness marker.
import_findings_into_contract() {
  local secfile="$1" path="$2" audit_file="$3" start rendered
  start="$(next_finding_number "$audit_file")"
  rendered="$(render_findings "$start" "$secfile")"
  [ -n "$rendered" ] || return 0
  if [ -r "$audit_file" ]; then
    {
      printf '\n## external findings\n'
      printf 'auditor: external/%s | %s\n\n' "$vendor" "$today"
      printf '%s\n' "$rendered"
    } >> "$audit_file"
  else
    {
      printf '# drydock audit — %s @ %s\n' "$path" "$baseline"
      printf 'auditor: external/%s | %s\n\n' "$vendor" "$today"
      printf '## findings\n'
      printf '%s\n\n' "$rendered"
      printf '## claims\n'
      printf -- '- (external leg — claims not collected; no tool access)\n'
    } > "$audit_file"
  fi
}

append_unmapped() {  # SECFILE PATH REPLY_BASENAME
  local secfile="$1" path="$2" replyname="$3" rendered out="$audit_dir/EXTERNAL-UNMAPPED.md"
  rendered="$(render_findings 1 "$secfile")"
  [ -n "$rendered" ] || return 0
  {
    printf '\n## %s (from %s, not in MANIFEST.txt — never given a fabricated slug)\n\n' "$path" "$replyname"
    printf '%s\n' "$rendered"
  } >> "$out"
}

# secfile_for PADDED IDX — the scratch file a "## <path>" section's body is spooled to: the Nth
# section encountered in chunk PADDED, by pure sequential index. NOT derived from the path itself —
# an earlier version sanitized the path via `tr -c ... '_'`, which maps every unsafe byte (including
# `/`) to the same `_`, so two genuinely different paths (e.g. `docs/sub.md` and `docs_sub.md`) could
# sanitize to the identical filename; the second section's `: > "$cur_file"` truncation would then
# silently overwrite the first's already-collected content before either was ever read back — no
# error, no warning, exit 0, one finding just gone (reproduced live: code review high, Angle A/C). An
# index can never collide by construction, so this fix removes the class rather than papering over
# one instance of it.
secfile_for() { printf '%s/sec-%s-%s' "$scratch" "$1" "$2"; }

failed_chunks=""
imported_files=0
unmapped_count=0
replies_seen=0

for reply in "$reply_dir"/reply-*.md; do
  [ -e "$reply" ] || continue
  base="$(basename "$reply")"
  [ "$base" = "reply-value.md" ] && continue   # opinion, not a finding — never imported
  num="$(printf '%s' "$base" | sed -n 's/^reply-\([0-9][0-9]*\)\.md$/\1/p')"
  if [ -z "$num" ]; then
    printf 'import.sh: skipping %s — not a reply-NN.md filename\n' "$base" >&2
    continue
  fi
  replies_seen=$((replies_seen + 1))
  padded="$(printf '%02d' "$((10#$num))")"

  body="$scratch/body-$padded.md"
  # Tolerate one wrapping code-fence line (```, ```markdown, ...) at the very first or very last
  # line. Deliberately NOT `sed -e '1{/^```/d}'`: that GNU-style address-block needs a trailing `;`
  # before the `}` on BSD sed (macOS's own /bin/sed) — "extra characters at the end of d command",
  # caught live on this machine. A plain `sed -n 'N,Mp'` range is portable across GNU/BSD/busybox.
  # `awk 'END{print NR}'`, not `wc -l`: this repo's own established caveat (see
  # tools/drydock/inventory.sh's header) — wc -l counts newlines and undercounts a reply whose last
  # line has none.
  total_lines="$(awk 'END{print NR}' "$reply" 2>/dev/null || echo 0)"
  first_line="$(head -n 1 "$reply" 2>/dev/null || true)"
  last_line="$(tail -n 1 "$reply" 2>/dev/null || true)"
  body_start=1
  body_end="$total_lines"
  case "$first_line" in '```'*) body_start=2 ;; esac
  case "$last_line" in '```') body_end=$((body_end - 1)) ;; esac
  if [ "$body_start" -le "$body_end" ] 2>/dev/null; then
    sed -n "${body_start},${body_end}p" "$reply" > "$body"
  else
    : > "$body"
  fi

  needle="CHUNK-END $padded"
  # Materialize the bounded head into a variable FIRST, then grep the variable via a here-string —
  # not `grep -v ... | head -15 | grep -qF ...` piped straight through. A body long enough to
  # overflow the pipe buffer before `head -15` reads its quota gets `head` closing the pipe on
  # `grep -v` mid-write; under this file's own pipefail, the pipeline's reported status scans
  # right-to-left for the first NONZERO stage, so `grep -v`'s SIGPIPE (141) can win even though
  # `head` read cleanly and the trailing `grep -qF` genuinely found the needle (0) — a real,
  # reproduced FAILED-chunk false positive on an otherwise valid chunk (code review high, Angle A).
  # A here-string has bash buffer the content up front, so there is no live writer left for the
  # final match check to interrupt (the same reasoning tests/lib.sh's own match() comment gives).
  head15="$(grep -v '^[[:space:]]*$' "$body" | head -15)" || true
  if ! grep -qF "$needle" <<< "$head15"; then
    printf 'import.sh: FAILED chunk %s — truncated or off-format (no "%s" quoted near the start of %s)\n' \
      "$padded" "$needle" "$base" >&2
    failed_chunks="$failed_chunks $padded"
    continue
  fi

  # --- split into per-"## <path>" sections, chatter before the first heading discarded ---
  # section_paths carries "IDX<TAB>path" records, not bare paths — IDX is the section's own
  # sequential position (1, 2, 3, ...), read back below to re-derive the EXACT SAME scratch file
  # secfile_for() wrote it to. Two sections sharing a path (unusual, but the model could repeat a
  # heading) are handled correctly too: each gets its own index, so neither collides with or
  # overwrites the other's content.
  cur_file=""
  section_paths=""
  section_idx=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      '## '*)
        path="${line#??}"
        path="${path# }"
        [ -n "$path" ] || continue
        section_idx=$((section_idx + 1))
        cur_file="$(secfile_for "$padded" "$section_idx")"
        section_paths="$section_paths$section_idx$TAB$path$NL"
        : > "$cur_file"
        continue
        ;;
    esac
    [ -n "$cur_file" ] && printf '%s\n' "$line" >> "$cur_file"
  done < "$body"

  # IFS="$TAB" read -r idx path — this codebase's own established TAB-record convention
  # (tools/drydock/inventory.sh, tools/delta-audit/derive.sh both already read TAB-delimited
  # records this way), reused here instead of hand-rolling the split via parameter expansion.
  while IFS="$TAB" read -r idx path; do
    [ -n "$idx" ] || continue
    secfile="$(secfile_for "$padded" "$idx")"
    [ -r "$secfile" ] || continue
    case "$known_paths" in
      *"$NL$path$NL"*)
        slug="$(printf '%s' "$path" | tr '/' '-')"
        import_findings_into_contract "$secfile" "$path" "$audit_dir/$slug-audit.md"
        imported_files=$((imported_files + 1))
        ;;
      *)
        append_unmapped "$secfile" "$path" "$base"
        unmapped_count=$((unmapped_count + 1))
        ;;
    esac
  done <<< "$section_paths"
done

[ "$replies_seen" -gt 0 ] || refuse "no reply-NN.md files found in '$reply_dir' — nothing to import.
  (reply-value.md, if present, is deliberately never imported here.)"

if [ -n "$failed_chunks" ]; then
  printf 'import.sh: %d section(s) imported, %d unmapped — FAILED chunk(s):%s\n' \
    "$imported_files" "$unmapped_count" "$failed_chunks" >&2
  exit 1
fi
printf 'import.sh: %d section(s) imported into %s, %d unmapped\n' "$imported_files" "$audit_dir" "$unmapped_count"
ok=1
