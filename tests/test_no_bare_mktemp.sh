#!/usr/bin/env bash
# test_no_bare_mktemp.sh — the census that keeps test scratch inside the suite's sandbox (dir #437, caught
# by the 0.13.0 delta audit). A bare `mktemp` / `mktemp -d` in a test file lands in the REAL temp dir, and
# on macOS it ignores $TMPDIR, so no redirect can catch it: three install tests left PATH farms (one
# symlink per command on PATH, thousands of them) and a scratch checkout there on every run. tests/lib.sh's
# $SANDBOX is removed when a test file exits, so a scratch path minted under it —
# `mktemp -d "$SANDBOX/name.XXXXXX"` — cannot outlive the run.
#
# Axis, named: this detects the `$(mktemp …)` call shape on a non-comment line of a tests/test_*.sh file.
# It does not see a backtick call, a `mktemp` outside a command substitution, or a template held in a
# variable; tests/lib.sh itself (which creates $SANDBOX with the one deliberate bare call) is not a test_*
# file. This file is skipped too: its allow-list below is literal text of the shape it hunts.
#
# The census is a function over a directory: it runs once on tests/ and once on a sandbox tree this file
# builds, so the detector's own non-vacuity is asserted.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "no bare mktemp in test files (dir #437)"

# The allow-list — one entry per kept call, keyed by file AND the exact (indent-trimmed) line, never by line
# number, each with its reason.
allowed() {
  case "$1|$2" in
    # the case asserts the installer's refusal to run from a bootstrap-shaped temp clone, so the clone must
    # sit in the real temp dir; the case removes it with `rm -rf "$btmp"`
    'test_install_pre_pr_gate.sh|btmp="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"') return 0 ;;
    # removed by the same case's `rm -rf "$archive_dir"` (out of the dir #437 fix's scope; it leaves nothing)
    'test_self_citation_resolvability.sh|archive_dir="$(mktemp -d)"') return 0 ;;
    # fixture TEXT: a copy of tools/drydock/inventory.sh's own shape, whose extracted EXIT trap removes it
    "test_drydock_inventory.sh|'scratch=\"\$(mktemp -d)\"' \\") return 0 ;;
  esac
  return 1
}

# census DIR — prints `file:line: text` for every offending call in DIR/test_*.sh.
census() {
  local dir="$1" f base n text trimmed rest stripped
  local sandboxed='\$\(mktemp( +-[A-Za-z]+)* +"\$\{?SANDBOX[/}]'
  for f in "$dir"/test_*.sh; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    [ "$base" = test_no_bare_mktemp.sh ] && continue
    while IFS= read -r n; do
      text="${n#*:}"; n="${n%%:*}"
      trimmed="${text#"${text%%[![:space:]]*}"}"
      case "$trimmed" in '#'*) continue ;; esac
      # drop each sandboxed call, then judge what is left: one sandboxed call must not hide a bare one
      # sharing its line. A substitution that removes nothing ends the loop (and the line is flagged),
      # never spins.
      rest="$trimmed"
      while [[ "$rest" =~ $sandboxed ]]; do
        stripped="${rest/"${BASH_REMATCH[0]}"/}"
        [ "$stripped" = "$rest" ] && break
        rest="$stripped"
      done
      case "$rest" in *'$(mktemp'*) ;; *) continue ;; esac
      allowed "$base" "$trimmed" && continue
      printf '%s:%s: %s\n' "$base" "$n" "$trimmed"
    done < <(grep -nF '$(mktemp' "$f" || true)
  done
}

# --- non-vacuity: the detector flags what it should, and only that, on a planted tree -------------------
plant="$(mktemp -d "$SANDBOX/plant.XXXXXX")"
{
  printf '%s\n' 'a="$(mktemp -d)"'
  printf '%s\n' 'b="$(mktemp)"'
  printf '%s\n' 'c="$(mktemp -d "$TMPDIR/c.XXXXXX")"'
  printf '%s\n' 'd="$(mktemp -d "$SANDBOX/d.XXXXXX")"'
  printf '%s\n' 'e="$(mktemp "${SANDBOX}/e.XXXXXX")"'
  printf '%s\n' '  # a comment naming "$(mktemp -d)"'
  printf '%s\n' 'archive_dir="$(mktemp -d)"'
  printf '%s\n' 'f="$(mktemp -d "$SANDBOX/f.XXXXXX")" g="$(mktemp -d)"'
} > "$plant/test_planted.sh"
out="$(census "$plant")"
check_contains "a bare \`mktemp -d\` is flagged" "$out" 'test_planted.sh:1:'
check_contains "a bare \`mktemp\` is flagged" "$out" 'test_planted.sh:2:'
check_contains "a template outside \$SANDBOX is flagged" "$out" 'test_planted.sh:3:'
check_absent "a \$SANDBOX template is not flagged" "$out" 'test_planted.sh:4:'
check_absent "a \${SANDBOX} template is not flagged" "$out" 'test_planted.sh:5:'
check_absent "a comment line is not flagged" "$out" 'test_planted.sh:6:'
check_contains "an allow-listed line in ANOTHER file is still flagged (the allow-list is per file)" "$out" 'test_planted.sh:7:'
check_contains "a bare call sharing a line with a sandboxed one is flagged" "$out" 'test_planted.sh:8:'
check_eq "exactly the five offending lines are reported" 5 "$(printf '%s\n' "$out" | grep -c 'test_planted.sh:')"

# --- the real census ---------------------------------------------------------------------------------
out="$(census "$TESTS_DIR")"
if [ -z "$out" ]; then
  pass "no tests/test_*.sh mints scratch with a bare mktemp outside the allow-list"
else
  fail "no tests/test_*.sh mints scratch with a bare mktemp outside the allow-list" \
    "mint it under the sandbox instead (mktemp -d \"\$SANDBOX/name.XXXXXX\"):
$out"
fi

summary
