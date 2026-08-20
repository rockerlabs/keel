# shellcheck shell=bash
# tools/lib/nonneg-int.sh (dir #196) — the ONE non-negative-integer sanitizer, shared by every tool
# that clamps a numeric env-var/arg override. dir #156 first fixed this class in self/doctor.sh's
# `pending_max_commits`: a digit-SHAPE-only guard (`case ... in ''|*[!0-9]*) ...`) accepts an
# arbitrarily long all-digit string, which can overflow the shell's native integer range (bash's own
# signed range holds ~19 digits) and make a later `-gt`/`-lt`/`-ge` comparison fail with "integer
# expression expected" instead of comparing — evaluating false and silently defeating the very bound
# it was guarding. The same bare idiom, unfixed, was then found duplicated across 6 more files
# (dir #196) — each hand-copying the same case arm and the same explanatory comment, exactly the
# "second file re-deriving it from scratch is the same drift one file over" class
# tools/lib/fence-blank.sh's own header already names. Consolidated here instead of swept 6 more times.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# `_nonneg_int_valid VALUE [MAX_DIGITS]` — returns 0 (valid) or 1 (invalid: empty, non-digit-shaped, or
# MAX_DIGITS digits or longer). MAX_DIGITS defaults to 10 (dir #156's own original choice — "far above
# any sane bound, comfortably inside every shell's integer range"), NOT the actual ~19-digit overflow
# boundary: it's a deliberately conservative sanity bound, so a caller whose value is a real magnitude
# that can legitimately reach 10 digits (e.g. a raw unix epoch — already 10 digits today) must pass a
# larger cap explicitly, or every legitimate value would be rejected.
_nonneg_int_valid() {
  local val="$1" n="${2:-10}" pattern
  pattern="$(printf '%*s' "$n" '')"
  pattern="${pattern// /?}*"
  # shellcheck disable=SC2254  # intentional: $pattern's ?/* must match as a glob (N digits or more),
  # not literally — that's the whole point of building it dynamically from $n.
  case "$val" in
    '') return 1 ;;
    *[!0-9]*) return 1 ;;
    $pattern) return 1 ;;
    *) return 0 ;;
  esac
}

# `sanitize_nonneg_int VALUE DEFAULT [MAX_DIGITS]` — prints VALUE if `_nonneg_int_valid` accepts it,
# else prints DEFAULT. The common "fall back to a default" shape; a caller that instead needs to
# REJECT (exit with an error) or SKIP (continue a loop) on an invalid value calls `_nonneg_int_valid`
# directly instead — same validity check, different action on failure.
sanitize_nonneg_int() {
  local val="$1" default="$2" n="${3:-10}"
  if _nonneg_int_valid "$val" "$n"; then
    printf '%s' "$val"
  else
    printf '%s' "$default"
  fi
}
