# shellcheck shell=bash
# tools/lib/project-slug.sh — adopter-usable (dir #916): the ONE string-only encoder for Claude Code's project-directory
# names, the `~/.claude/projects/<slug>/` an absolute path maps to. Claude Code writes every character outside
# [A-Za-z0-9] as `-` (`replace(/[^a-zA-Z0-9]/g, "-")`): `/`, `.`, a space, `_` and a non-ASCII character alike.
# Four encoders had grown (cloud-brief.sh's two forms, tools/lib/transcript-usage.sh's `/` and `.` only, tools/doctor.sh's
# `/` and `.` only) and disagreed on `_`, a space and everything non-ASCII.
#
# Dependency-free on purpose: no other lib sourced, no git, no filesystem. It encodes the text it is given and never
# resolves a directory (tu_project_slug in transcript-usage.sh does the `cd`/`pwd` and then calls this), so it also
# serves a path that no longer exists, and a path that only appears as text in a document.
# Sourced, not executed — no shebang, no set -e (inherits the caller's).
#
# keel_project_slug TEXT — prints TEXT with every byte outside [A-Za-z0-9] replaced by `-`, no trailing newline.
#   Byte-wise (LC_ALL=C): a multi-byte character becomes one `-` per byte, where the CLI writes one per UTF-16 unit, so
#   the two agree on ASCII and on BMP characters of one byte only. A known limit; the callers that match the encoded
#   name against a real directory treat a non-ASCII path as unverified (tools/doctor.sh's H-MEMORY-DIR-UNRESOLVED).
keel_project_slug() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9' '-'
}
