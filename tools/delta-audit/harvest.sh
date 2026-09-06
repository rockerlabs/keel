#!/usr/bin/env bash
# tools/delta-audit/harvest.sh — fill run-record.md's mechanically-derivable fields from a run's own
# artifacts (dir #267).
#
# Adopter-facing: `derive.sh` emits `run-record.md` as a stub — a human fills every row by hand today.
# This script fills the THREE rows that are genuinely mechanical and re-writes the rest unchanged, so
# a human still owns the narrative rows (method, coverage, findings, behavioural defects, diversity
# result, new classes vs instances, upstream gate) that `docs/verification-economics.md` §9 defines as
# judgement calls, not facts a script can read off a file.
#
# Why only three rows, not all eleven (the ticket's own gate, re-read at implementation time):
#   - `scope`        already mechanical — `derive.sh` fills it at emission time from
#                     delta-files.txt/file-pr-map.tsv. Nothing here to add.
#   - `records`      a directory listing. Mechanical, filled here.
#   - `cost, per leg`  §9 field 5: "record per leg... token spend where the harness reports it, with
#                     an explicit `unmeasured` value permitted and expected". Harvested here from
#                     `orchestrator-notes.md`'s own cost table(s) — see below.
#   - `induced defects (induced / total)`  §9 field 6: "the run record carries only the DERIVED RATE
#                     (induced/total), never the per-finding marks" — the marks themselves are a human
#                     judgement call written into each report (§9: "a finding is `induced` when...the
#                     triaging session can state the causal path in one sentence"). This script is a
#                     COLLECTOR of that judgement, never an inferencer of it, per the ticket's own rule.
#   - everything else  no artifact in a run directory states these as fact; a script that guessed at
#                     them would be exactly the fabrication doctrine forbids for cost (§9's "never a
#                     fabricated zero"), generalised to prose.
#
# Two hard constraints, both load-bearing, both checked live in tests/test_delta_audit_harvest.sh:
#   1. NEVER emit `0` (or any measured-looking figure) for a cost this script could not find — the
#      value is the literal string `unmeasured`. A leg absent from the cost table is `unmeasured` for
#      THAT LEG; it never becomes 0 and it never gets folded into another leg's figure.
#   2. NEVER compute a run-level or cross-leg cost aggregate. Each leg's figure is printed on its own;
#      this script contains no `+` across legs, and the induced rate is a COUNT of marks, not a cost.
#
# The induced-defects convention this script recognises is now the prescribed syntax in
# docs/delta-audit.md's Protocol rule 6 and docs/verification-economics.md's field 6 definition —
# not invented here in isolation. It postdates this repo's own report corpus, which uses free-text
# phrasing this script deliberately does NOT try to parse; see "Known limitation" below. A report
# marks each triaged finding with a line containing the literal substring `Mark:` (case-insensitive,
# backticks/bold markup ignored) followed by `induced` or `original`, e.g.:
#   **Mark:** `induced` — one-sentence causal path to the prior round's fix
#   **Mark:** `original`
# A report using any other phrasing for the same judgement is silently undercounted, which this
# script discloses (via `unmeasured` when zero marks are found at all) rather than guessing at.
#
# Known limitation (found auditing this run's real report corpus, not invented): every run in
# private/audit/ that predates this script uses free-text phrasing for both the cost table and the
# induced mark ("S1 169k · S2 468k...", "induced/original: **induced**", "**Mark:** `original`" among
# several other shapes for the same fact). This script recognises exactly ONE convention for each —
# the `orchestrator-notes.md` cost table shape already used by the two runs that have one
# (private/audit/delta-0.7.*/orchestrator-notes.md), and the `Mark:` line above — and reports
# `unmeasured` rather than guess at the others. Widening the recognised shapes is future work, not a
# defect in this pass: guessing at free text is exactly the overfit-to-one-run's-shape risk dir #267
# was gated on.
#
# Exit codes: 0 harvested (fields updated in place) · 2 bad arguments · 3 refused (not a directory /
# run-record.md absent — nothing to fill).
set -uo pipefail

usage() {
  cat <<'EOF'
usage: harvest.sh <run-dir>

Fill run-record.md's mechanical rows (records, cost per leg, induced defects) from a delta-audit
run directory's own artifacts, in place. Every other row is copied through unchanged — method,
coverage, findings, behavioural defects, diversity result, new-classes and upstream-gate stay a
human's call, per docs/verification-economics.md §9.

  <run-dir>     a directory already carrying run-record.md (as emitted by derive.sh --out <dir>).

Reads, if present, from <run-dir>:
  run-record.md          required — the stub (or a partially hand-filled record) to update
  orchestrator-notes.md  optional — one or more markdown tables headed by a "leg" column and a
                         column whose name contains "token"; each row becomes one leg's cost figure
  reports/*.md           optional — lines containing `Mark:` (case-insensitive) followed by
                         `induced` or `original`; tallied into the induced/total rate

Exit codes: 0 harvested · 2 bad arguments · 3 refused (not a directory, or run-record.md missing).
EOF
}

err()      { printf 'harvest.sh: %s\n' "$1" >&2; exit "$2"; }
die_args() { err "$1" 2; }
refuse()   { err "$1" 3; }

run_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*)        die_args "unknown option '$1' (see --help)" ;;
    *)
      if [ -z "$run_dir" ]; then run_dir="$1"
      else die_args "unexpected argument '$1' — harvest.sh takes exactly one run directory"
      fi
      shift ;;
  esac
done
[ -n "$run_dir" ] || die_args "missing <run-dir> (see --help)"

[ -d "$run_dir" ] || refuse "not a directory: '$run_dir'"
record_file="$run_dir/run-record.md"
[ -f "$record_file" ] || refuse "no run-record.md in '$run_dir' — run derive.sh --out first"
[ -w "$record_file" ] || refuse "run-record.md in '$run_dir' is not writable"
run_dir="$(cd "$run_dir" && pwd)"
record_file="$run_dir/run-record.md"

# --- records: a sorted directory listing, excluding run-record.md itself (the row being filled, not
# an input artifact) ---------------------------------------------------------------------------------
records_value=""
entries="$(cd "$run_dir" && LC_ALL=C ls -A 2>/dev/null | LC_ALL=C sort)"
if [ -n "$entries" ]; then
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "$entry" = "run-record.md" ] && continue
    if [ -d "$run_dir/$entry" ]; then entry="$entry/"; fi
    if [ -z "$records_value" ]; then records_value="\`$entry\`"
    else records_value="$records_value, \`$entry\`"
    fi
  done <<EOF
$entries
EOF
fi
[ -n "$records_value" ] || records_value="(empty run directory)"

# --- cost, per leg: parse orchestrator-notes.md's own cost table(s) ---------------------------------
# One tab-separated "leg<TAB>tokens" pair per data row found, in file order, across every table whose
# header carries a "leg" column and a column with "token" in its name. Portable POSIX awk only — no
# gawk-only builtins, no arrays keyed by anything but small integers, so this runs unmodified under
# BusyBox awk and macOS's shipped awk (this project's fifth Alpine trap and the fourth-trap lesson
# both apply to shell, not awk, but the same "verify the actual interpreter" discipline held here).
cost_notes="$run_dir/orchestrator-notes.md"
cost_pairs=""
if [ -f "$cost_notes" ]; then
  cost_pairs="$(awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      is_row = ($0 ~ /^\|.*\|[ \t]*$/)
      if (!is_row) { state = 0; next }
      # split() on a well-formed "| a | b | c |" row yields a leading AND a trailing empty field
      # (indices 1 and n) either side of the real cells — every loop below runs 2..n-1, not 2..n, or
      # the trailing empty field reads as a blank separator cell and falsely fails the sepok check.
      n = split($0, cell, "|")
      if (state == 0) {
        c1 = tolower(trim(cell[2]))
        if (c1 == "leg") {
          legcol = 2; tokcol = 0
          for (i = 2; i <= n - 1; i++) {
            c = tolower(trim(cell[i]))
            if (index(c, "token") > 0) { tokcol = i }
          }
          if (tokcol > 0) { state = 1 }
        }
        next
      }
      if (state == 1) {
        sepok = 1
        for (i = 2; i <= n - 1; i++) {
          c = trim(cell[i])
          if (c !~ /^:?-+:?$/) { sepok = 0 }
        }
        state = sepok ? 2 : 0
        next
      }
      if (state == 2) {
        leg = trim(cell[legcol]); tok = trim(cell[tokcol])
        if (leg != "") { gsub(/,/, "", tok); printf "%s\t%s\n", leg, tok }
        next
      }
    }
  ' "$cost_notes" 2>/dev/null || true)"
fi

cost_value=""
if [ -n "$cost_pairs" ]; then
  while IFS="$(printf '\t')" read -r leg tok; do
    [ -n "$leg" ] || continue
    case "$tok" in
      ''|*[!0-9]*) tok_disp="unmeasured" ;;   # empty, or not a plain digit string -> not a measured figure
      *)           tok_disp="${tok} tokens" ;;
    esac
    if [ -z "$cost_value" ]; then cost_value="$leg: $tok_disp"
    else cost_value="$cost_value · $leg: $tok_disp"
    fi
  done <<EOF
$cost_pairs
EOF
fi
[ -n "$cost_value" ] || cost_value="unmeasured (no cost table found in orchestrator-notes.md)"

# --- induced defects: tally explicit "Mark: induced|original" lines under reports/ ------------------
induced_count=0
total_count=0
if [ -d "$run_dir/reports" ]; then
  for f in "$run_dir"/reports/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      clean="$(printf '%s' "$line" | tr -d '`*' | tr '[:upper:]' '[:lower:]')"
      case "$clean" in
        *mark:*induced*)  induced_count=$((induced_count + 1)); total_count=$((total_count + 1)) ;;
        *mark:*original*) total_count=$((total_count + 1)) ;;
      esac
    done < "$f"
  done
fi
if [ "$total_count" -eq 0 ]; then
  induced_value="unmeasured (no \`Mark:\` markers found in reports/)"
else
  induced_value="$induced_count induced / $total_count marked"
fi

# --- rewrite run-record.md, replacing only the three rows above by field-name prefix, everything
# else copied through byte-for-byte -------------------------------------------------------------------
tmp_file="$(mktemp "${TMPDIR:-/tmp}/harvest-record.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

awk -v records="$records_value" -v cost="$cost_value" -v induced="$induced_value" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  {
    if ($0 ~ /^\|[^|]*\|[^|]*\|[ \t]*$/) {
      n = split($0, cell, "|")
      field = trim(cell[2])
      lf = tolower(field)
      if (lf == "records") { printf "| %s | %s |\n", field, records; next }
      if (index(lf, "cost, per leg") == 1) { printf "| %s | %s |\n", field, cost; next }
      if (index(lf, "induced defects") == 1) { printf "| %s | %s |\n", field, induced; next }
    }
    print
  }
' "$record_file" > "$tmp_file"

mv "$tmp_file" "$record_file"
trap - EXIT
exit 0
