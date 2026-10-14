#!/usr/bin/env bash
# test_known_bypass_registers.sh — dir #842 slice 1 (docs/specs/842-guard-threat-model-1a-1b.md, A6): the
# per-guard known-bypass registers exist where SECURITY.md's "Threat model by guard" table says they do.
#
# Pinned: (a) the section is there exactly once; (b) every table row names a register file that exists and a
# heading phrase that file holds OUTSIDE the new section, and an "In doubt" cell reading 1a or 1b; (c) the eight
# guard rows, each in its doubt family, and the "In doubt column is the doubt class only" sentence; (d) the
# register entries dir #842's slice 1 wrote (one phrase each, where it must sit); (e) SECURITY.md's "Scope"
# carries the 1b clause. The checker is one function over a root directory, so the same rules read a scratch
# copy: deliberately broken copies must each turn it red, or a green real run would prove nothing.
#
# Keel-self-maintenance: it reads keel's own register files (tools/pre-pr-gate.sh, tests/lib.sh,
# tools/lib/safe-write.sh), which an adopter does not carry.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# The eight guard rows: the first words of the guard cell, then the doubt class the row must read (B3).
EXPECTED_ROWS='secret guard|1a
public-audit|1a
installer / uninstaller|1a
pre-PR gate — the push-bypass rule|1a
pre-PR gate — the PR rule|1b
subagent git floor|1a
test sandbox — outside writes|1a
test sandbox — false green|1b'

# cell ROW F — awk field F of a table row (`|`-separated, field 1 is the empty text before the first bar), trimmed:
# 2 the guard, 5 the In doubt cell, 7 the register cell.
cell() { awk -F'|' -v n="$2" '{ c = $n; gsub(/^ +| +$/, "", c); print c }' <<<"$1"; }

# regcheck ROOT — print one `fail:<rule>:<detail>` line per rule that does not hold under ROOT; nothing = all hold.
regcheck() {
  local root="$1" sec gate
  sec="$root/SECURITY.md"; gate="$root/tools/pre-pr-gate.sh"
  local n section outside rows row reg path phrase doubt exp guard want got line block

  n="$(grep -c -x '## Threat model by guard' "$sec")"
  [ "$n" = 1 ] || echo "fail:a:heading found $n times"
  section="$(section_body '## Threat model by guard' "$sec")"
  outside="$(awk '$0 == "## Threat model by guard" { f = 1; next } /^## / { f = 0 } !f' "$sec")"

  # (b) every row: register file exists, its heading phrase is held outside the section, the doubt cell is 1a or 1b.
  rows="$(grep '^|' <<<"$section" | grep -v '^|[-| ]*$' | sed 1d)"
  [ -n "$rows" ] || echo "fail:b:the section has no table rows"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    reg="$(cell "$row" 7)"
    guard="$(cell "$row" 2)"
    path="$(sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p' <<<"$reg")"
    phrase="$(sed -n 's/^[^"]*"\([^"]*\)".*/\1/p' <<<"$reg")"
    doubt="$(cell "$row" 5)"
    if [ -z "$path" ] || [ ! -f "$root/$path" ]; then
      echo "fail:b:[$guard] register file '$path' does not exist"
    elif [ -z "$phrase" ]; then
      echo "fail:b:[$guard] the register cell names no heading phrase"
    elif [ "$path" = SECURITY.md ]; then
      grep -q -E '^Known limits \(by design' <<<"$outside" || echo "fail:b:[$guard] SECURITY.md has no Known limits block outside the section"
    else
      grep -qF -- "$phrase" "$root/$path" || echo "fail:b:[$guard] $path holds no '$phrase'"
    fi
    case "$doubt" in 1a|1b) ;; *) echo "fail:b:[$guard] In doubt cell reads '$doubt'" ;; esac
  done <<<"$rows"

  # (c) the eight rows, each in its family; the column-is-the-doubt-class sentence.
  while IFS='|' read -r exp want; do
    row=""
    while IFS= read -r line; do
      guard="$(cell "$line" 2)"; guard="${guard//\`/}"
      case "$guard" in "$exp"*) row="$line"; break ;; esac
    done <<<"$rows"
    if [ -z "$row" ]; then echo "fail:c:no row for [$exp]"; continue; fi
    got="$(cell "$row" 5)"
    [ "$got" = "$want" ] || echo "fail:c:[$exp] In doubt reads '$got', want $want"
  done <<<"$EXPECTED_ROWS"
  grep -qF -- 'is 1b in every row' <<<"$section" || echo "fail:c:the 'is 1b in every row' sentence is missing"

  # (d) the register entries slice 1 wrote.
  block="$(sed -n '1,/^# CLI subcommands/p' "$gate")"
  for phrase in 'a heredoc- or pipe-fed shell' 'an upper-case command word' 'group inside a' 'a hook started with stdin closed'; do
    grep -qF -- "$phrase" <<<"$block" || echo "fail:d:Named residuals lacks '$phrase'"
  done
  block="$(awk '/Allowed by design:/ { f = 1 } f && !/^#/ { exit } f && /^#$/ { exit } f' "$gate")"
  grep -qF -- 'an upper-case command word' <<<"$block" || echo "fail:d:the floor's Allowed by design block lacks 'an upper-case command word'"
  grep -qF -- 'traps TERM' "$root/tests/lib.sh" || echo "fail:d:tests/lib.sh lacks 'traps TERM'"
  grep -qF -- 'planted at the claimed temp path' "$root/tools/lib/safe-write.sh" || echo "fail:d:tools/lib/safe-write.sh lacks 'planted at the claimed temp path'"

  # (e) the Scope clause.
  line="$(section_body '## Scope — what counts' "$sec")"
  grep -qF -- 'holds only for a constructed input' <<<"$line" || echo "fail:e:SECURITY.md Scope lacks the 1b clause"
}

# --- the real tree --------------------------------------------------------------------------------------------------
check_eq "the real tree: every register rule holds" "" "$(regcheck "$REPO_ROOT")"

# --- three broken copies, each must turn its own rule red -------------------------------------------------------------
copy="$SANDBOX/registers-copy"
mkdir -p "$copy/tools/lib" "$copy/tests"
fresh_copy() {
  local f
  for f in SECURITY.md tools/pre-pr-gate.sh tools/lib/safe-write.sh tests/lib.sh; do cp "$REPO_ROOT/$f" "$copy/$f"; done
}

fresh_copy; delete_line_containing "$copy/tests/lib.sh" 'Known bypasses (1b'
check_contains "mutant: tests/lib.sh loses its Known bypasses (1b line → (b) fails" "$(regcheck "$copy")" 'fail:b:'

fresh_copy; replace_in_line_containing "$copy/SECURITY.md" 'pre-PR gate — the PR rule' ' | 1b | ' ' | 1a | '
check_contains "mutant: the PR-rule row's doubt cell swapped to 1a → (c) fails" "$(regcheck "$copy")" 'fail:c:[pre-PR gate — the PR rule]'

fresh_copy; delete_line_containing "$copy/SECURITY.md" 'holds only for a constructed input'
check_contains "mutant: the Scope clause deleted → (e) fails" "$(regcheck "$copy")" 'fail:e:'

fresh_copy; delete_line_containing "$copy/tools/lib/safe-write.sh" 'planted at the claimed temp path'
check_contains "mutant: safe-write.sh loses its test-gap entry → (d) fails" "$(regcheck "$copy")" 'fail:d:tools/lib/safe-write.sh'

summary
