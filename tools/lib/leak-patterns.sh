# shellcheck shell=bash
# tools/lib/leak-patterns.sh — the ONE definition of the two content patterns detectable at all for a
# leaked personal identifier (a home-directory path, a real-looking email), shared by public-audit.sh
# (its tracked-tree + history scan) and self/doctor.sh (the narrower GAP over FRAMEWORK.md/PRINCIPLES.md,
# dir #114). Sibling of safe-emails.sh's SAFE_EMAILS list (dir #106) — same shape, same reason: one
# definition instead of hand-copies behind "keep in sync" comments nothing enforces.
#
# Sourced, not executed — no shebang, no set -e (inherits the caller's).

# Both consumed only by callers that source this file — shellcheck can't see across that boundary.
# shellcheck disable=SC2034
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# shellcheck disable=SC2034
HOME_RE='/(Users|home)/[A-Za-z0-9._-]+'
