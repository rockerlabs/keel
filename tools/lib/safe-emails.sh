# shellcheck shell=bash
# tools/lib/safe-emails.sh — the ONE list of public-safe email patterns (ERE), shared by
# public-audit.sh (the GAP gate: a non-safe commit/tag email fails a publish audit) and doctor.sh
# (its advisory nudge mirror). dir #106: these were two hand-maintained copies behind "keep in sync"
# comments that nothing enforced, and had already re-diverged once before (PR #43 consolidated them,
# then they drifted apart again). One array, sourced by both, so a new safe pattern can't land in one
# copy and not the other.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

SAFE_EMAILS=(
  '@users\.noreply\.github\.com'
  'noreply@anthropic\.com'
  'noreply@github\.com'
  '@example\.(com|org|net)'
  '@[A-Za-z0-9.-]*\.invalid'
)

# Pre-joined ERE alternation — callers that don't need to merge in their own extra patterns (doctor.sh)
# can use this directly instead of looping the array themselves.
safe_email_re=""
for _sge_e in "${SAFE_EMAILS[@]}"; do safe_email_re="${safe_email_re:+$safe_email_re|}$_sge_e"; done
unset _sge_e
