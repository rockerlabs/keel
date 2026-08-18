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
#      part of each `$ <tool>` command line) is replaced with `.`, matching how the README shows
#      `./tools/doctor.sh ...` rather than a machine-specific absolute path.
#   3. Key masking — the real planted AWS-shaped key tour.sh commits is replaced with the README's
#      disclosed masked form (`AKIA…REDACTED…`); secret-guard's own BLOCKED output has no masking of
#      its own — the masking is an editorial choice on the README's part, not a claim about what
#      secret-guard prints.
#   4. Fence-capture trim (mechanical, not a content rule) — a single leading blank line is dropped.
#      tour.sh's step() helper prints a blank line before EVERY heading, including the first; a Markdown
#      code fence pasted from a terminal naturally starts at the first real line of output, not a
#      blank one, so this drops only that one leading artifact and nothing else.
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

# Rule 1: the tour's own mktemp sandbox, resolved or not, -> /tmp/demo.
sandbox_re='(/private)?(/var/folders/[^ ]*/T/tmp\.[A-Za-z0-9]+|/tmp/tmp\.[A-Za-z0-9]+)'
live="$(printf '%s\n' "$OUT" | sed -E "s#${sandbox_re}#/tmp/demo#g")"
# Rule 2: this checkout's absolute root -> '.' (matches the README's relative `./tools/...` form).
live="$(printf '%s\n' "$live" | sed "s#${REPO_ROOT}#.#g")"
# Rule 3: the real planted key -> the README's disclosed masked form. Built from parts (like
# tour.sh's own fake_key) so this file's source never holds a whole key-shaped token.
planted_key="$(key 'AKIA' 'IOSFODNN7EXAMPLE')"
live="$(printf '%s\n' "$live" | sed "s/${planted_key}/AKIA…REDACTED…/")"
# Rule 4: drop exactly one leading blank line.
live="$(printf '%s\n' "$live" | awk 'NR==1 && $0==""{next}{print}')"

# The README's own fenced transcript (the ```console block under "What it looks like").
expected="$(awk '/^```console$/{f=1;next} /^```$/{if(f){f=0}} f' "$readme")"

if [ "$live" = "$expected" ]; then
  pass "normalized tour.sh output matches examples/README.md's transcript"
else
  fail "normalized tour.sh output matches examples/README.md's transcript" \
       "transcript is stale — diff below (< live, > README)"
  diff <(printf '%s\n' "$live") <(printf '%s\n' "$expected") || true
fi

summary
