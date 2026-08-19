#!/usr/bin/env bash
# examples/README.md ships a "real output from a run" transcript of examples/tour.sh. Drydock run 1
# found that transcript silently drifting stale against the live tools 5 separate times in one pass
# (missing gitignore lines, selftest output, an AGENTS.md line, doctor preamble) — each one caught
# only by a human diffing by eye. This test mechanizes that diff: run tour.sh for real, normalize its
# output, and byte-compare it against the README's own fenced code block. Any future change to a
# tool's console output that isn't also pasted into the README reds this test.
#
# Normalization rules applied to the LIVE run's output before comparing — every one of them mirrors a
# rule the README itself discloses in the prose directly above the transcript ("paths abbreviated, and
# the planted key masked — a live run prints it in full"), plus one purely mechanical fence-capture
# trim:
#   1. Path abbreviation — tour.sh's own throwaway `mktemp -d` sandbox (e.g.
#      /var/folders/xx/.../T/tmp.AbC123, or its macOS /private-resolved form) is replaced with the
#      README's literal stand-in path `/tmp/demo`, wherever it appears (as the project dir, the HOME
#      dir, or inside a nested message like the keel-impact gitignore note).
#   2. Path abbreviation — this repo's own absolute checkout root (which tour.sh's `show()` prints as
#      part of each `$ <tool>` command line), followed by a path separator, is replaced with `./`,
#      matching how the README shows `./tools/doctor.sh ...` rather than a machine-specific absolute
#      path. The trailing `/` is load-bearing, not cosmetic: a bare `${REPO_ROOT}` match would also
#      hit `$REPO_ROOT` as a plain substring prefix of an unrelated string that merely starts the same
#      way — confirmed live on the Alpine leg, where `$REPO_ROOT` is `/keel` and doctor.sh's own
#      "run /keel-score to score" hint collapsed into "run .-score to score" without this anchor.
#      `$REPO_ROOT` is escaped (`sed_escape`, below) before going into the sed pattern: it's an
#      arbitrary filesystem path, not a literal this file controls, and interpolating it into a BRE
#      unescaped is a real, reproducible bug on a checkout whose path contains a sed/regex
#      metacharacter (`.`, `*`, `[`, or the `#` delimiter itself) — confirmed live: a `#` in the path
#      breaks the sed script outright, and an unescaped `.` silently mismatches an unrelated string,
#      which would mask real staleness rather than report it.
#   3. Key masking — the real planted AWS-shaped key tour.sh commits is replaced with the README's
#      disclosed masked form (`AKIA…REDACTED…`); secret-guard's own BLOCKED output has no masking of
#      its own — the masking is an editorial choice on the README's part, not a claim about what
#      secret-guard prints.
#   4. Fence-capture trim (mechanical, not a content rule) — a single leading blank line is dropped.
#      tour.sh's step() helper prints a blank line before EVERY heading, including the first; a Markdown
#      code fence pasted from a terminal naturally starts at the first real line of output, not a
#      blank one, so this drops only that one leading artifact and nothing else.
#   5. Host-grep-capability variance in install-secret-guard.sh's own selftest (confirmed live on
#      Alpine/BusyBox, the CI matrix's third leg): secret-scan.sh's selftest() probes whether this
#      host's `grep -E` flags a malformed ERE (see its own comment there) — GNU/BSD grep does, so the
#      probe prints an indented "OK — malformed personal regex fails CLOSED" line; BusyBox grep
#      doesn't, so it prints an unindented "WARN — this grep does not flag a malformed ERE..." line
#      to stderr INSTEAD, which — because it's unbuffered stderr racing a buffered stdout pipe
#      (`| sed 's/^/  /'` in install-secret-guard.sh) — lands at a different position in the captured
#      transcript entirely. This is the tool honestly reporting a host capability, not the tool's
#      output changing meaning, so both known forms are dropped from BOTH sides before comparing
#      (position-independent — see the note above about why position can't be preserved). Matched as
#      two EXACT fixed strings, not a wildcard: the same probe also has a genuine "FAIL — ... (exit N,
#      want 2)" shape when the fail-closed guard is actually broken (secret-scan.sh's own probe()), and
#      that FAIL text must NOT be swallowed by this rule — a loose `.*` pattern here would silently hide
#      a real regression in the guard this test exists to protect, by dropping the mismatch from both
#      sides instead of surfacing it.
#
# No other content difference is normalized away — an actual output change (a new step, a reworded
# line, a different WARN/HINT count) survives the pipeline below and fails the diff.
#
# Neither Alpine CI trap named in the project CLAUDE.md applies here: this test doesn't `git clone`
# $REPO_ROOT (tour.sh only `git init`s its own disposable sandbox project), and it makes no
# `chmod 000` content assertion.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

tour="$REPO_ROOT/examples/tour.sh"
readme="$REPO_ROOT/examples/README.md"

run bash "$tour"
check_status "tour.sh runs end-to-end -> exit 0" 0 "$STATUS"

# Escape every non-alnum/underscore/hyphen byte with a backslash, so an arbitrary string is safe to
# interpolate as a literal (not a pattern) into a BRE, regardless of which delimiter the caller picks.
sed_escape() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9_-]/\\&/g'; }

# Rule 1: the tour's own mktemp sandbox, resolved or not, -> /tmp/demo.
sandbox_re='(/private)?(/var/folders/[^ ]*/T/tmp\.[A-Za-z0-9]+|/tmp/tmp\.[A-Za-z0-9]+)'
repo_root_esc="$(sed_escape "$REPO_ROOT")"
# Rule 3's replacement is built from parts (like tour.sh's own fake_key) so this file's source
# never holds a whole key-shaped token.
planted_key="$(key 'AKIA' 'IOSFODNN7EXAMPLE')"

# Rule 5: drop both known-GOOD forms of the host-grep-capability selftest line, on both sides —
# fixed strings, not a wildcard, so a genuine FAIL for this same probe is never swallowed.
drop_ok() { grep -v -F -e 'selftest: OK   — malformed personal regex fails CLOSED' \
                        -e 'selftest: WARN — this grep does not flag a malformed ERE'; }

live="$(printf '%s\n' "$OUT" \
  | sed -E "s#${sandbox_re}#/tmp/demo#g" \
  | sed -e "s#${repo_root_esc}/#./#g" -e "s/${planted_key}/AKIA…REDACTED…/" \
  | awk 'NR==1 && $0==""{next}{print}' \
  | drop_ok)"  # rule 2, rule 3, rule 4, rule 5

# The README's own fenced transcript (the ```console block under "What it looks like").
expected="$(awk '/^```console$/{f=1;next} /^```$/{if(f){f=0}} f' "$readme" | drop_ok)"

if [ "$live" = "$expected" ]; then
  pass "normalized tour.sh output matches examples/README.md's transcript"
else
  fail "normalized tour.sh output matches examples/README.md's transcript" \
       "transcript is stale — diff below (< live, > README)"
  diff <(printf '%s\n' "$live") <(printf '%s\n' "$expected") || true
fi

summary
