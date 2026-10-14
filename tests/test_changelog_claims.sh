#!/usr/bin/env bash
# tools/self/changelog-claims.sh (dir #810, slice S1): the numeric-claim lint over changelog text.
# Fixture repos are built in the sandbox (every one `git init`s, so none clones $REPO_ROOT and none needs the
# safe.directory guard of CLAUDE.md's Linux-leg trap 1). Covers the four 0.16.0 claims replayed as written
# (A1) and bound the way their author would have (A2), one correct bound claim per kind (A3), the exclusion
# rules (A4), what is not a claim or a marker (A5), every BADMARK (A6), marker text never executed (A7),
# spelled numbers (A8), sections and arguments (A9, A9a), binding order (A10), a live leg over keel's own
# text (A11) and the wiring pins of the docs this tool is named in (A12).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

ccl="$REPO_ROOT/tools/self/changelog-claims.sh"
scratch_cwd="$(mktemp -d "$SANDBOX/cwd.XXXXXX")"
# The label the tool prints for the changelog's own lines — held in a variable so no `name:LINE` citation
# shape sits in this file's text (tools/self/line-citations.sh would flag it).
cl="CHANGELOG.md"

check_file "tools/self/changelog-claims.sh exists" "$ccl"

# put DIR PATH TEXT — a file (parents made); frag DIR NAME TEXT — a TRACKED fragment (the reader lists tracked
# files); chg DIR TEXT — CHANGELOG.md. words_n N — a file body of exactly N awk fields.
put() { mkdir -p "$(dirname "$1/$2")"; printf '%s' "$3" > "$1/$2"; }
frag() { put "$1" "changelog.d/$2" "$3"; git -C "$1" add -f "changelog.d/$2"; }
chg() { put "$1" CHANGELOG.md "$2"; }
words_n() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "w%d%s", i, (i % 10 ? " " : "\n"); printf "\n" }'; }
count_of() { local n; n="$(grep -c -- "$2" <<< "$1" || true)"; printf '%s' "$n"; }
one_frag() { local d; d="$(new_repo)"; frag "$d" a.md "$1"; printf '%s' "$d"; }

# --- --help / bad arguments (A9 half) ----------------------------------------------------------------------
run "$ccl" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
check_contains "the header says keel-self-maintenance (dir #810)" "$(head -n 3 "$ccl" 2>/dev/null)" "keel-self-maintenance (dir #810)"
run "$ccl" --bogus
check_status "A9: an unknown flag -> exit 2" 2 "$STATUS"
run "$ccl" --repo /nonexistent
check_status "A9: --repo /nonexistent -> exit 2" 2 "$STATUS"
run "$ccl" --repo
check_status "A9: --repo without a value -> exit 2" 2 "$STATUS"

# --- A1: the four 0.16.0 claims, replayed as written (lines from `git show` at the E1 commits) -----------------
d="$(one_frag "$(printf '%s\n' \
  '- keeping `commands/polish.md` at 2,985 words. dir #673 (b), the delta-audit verifier'\''s default mutation mandate,' \
  '- `tests/mutants/pre-pr-gate.tsv` lists the gate reader'\''s single-clause mutants (46 of the bypassed-push deny at PR-1, rewritten against the lexer in PR-2: 269 rows); the dir #731 A18 block moved to' \
  '- start-marker waits keep a literal 5–20 s bound.' \
  '- survives (only `PATH` and `TMPDIR` are exempt, with reasons); `tests/lib.sh` neutralizes every one it found (26 unset; `HOME` and `GIT_CONFIG_GLOBAL` redirected). A')")"
run "$ccl" --repo "$d" --strict
check_status "A1: --strict over the four unbound claims -> exit 1" 1 "$STATUS"
check_contains "A1: 2,985 is UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:1: 2,985"
check_contains "A1: 46 is UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:2: 46"
check_contains "A1: 269 is UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:2: 269"
check_contains "A1: 5–20 (the en-dash as written) is UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:3: 5–20"
check_contains "A1: 26 is UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:4: 26"
check_eq "A1: exactly five UNBOUND lines" "5" "$(count_of "$OUT" '^UNBOUND')"
check_contains "A1: the summary line" "$OUT" "changelog-claims: 5 claim(s): 0 ok, 0 mismatched, 0 hand, 5 unbound, 0 word, 0 bad marker(s)"
run "$ccl" --repo "$d"
check_status "A1: without --strict -> exit 0" 0 "$STATUS"
check_eq "A1: without --strict, the same five UNBOUND lines" "5" "$(count_of "$OUT" '^UNBOUND')"

# --- A2: the same four, bound the way their author would have ------------------------------------------------
d="$(one_frag $'- 2,985 words <!-- claim: words commands/polish.md -->\n')"
put "$d" commands/polish.md "$(words_n 2983)"
run "$ccl" --repo "$d"
check_status "A2(a): a stale words claim -> exit 1 without --strict" 1 "$STATUS"
check_contains "A2(a): MISMATCH names the derived value" "$OUT" "MISMATCH changelog.d/a.md:1: 2,985 — words commands/polish.md gives 2983"

d="$(one_frag $'- 269 rows <!-- claim: matches \'^[A-Z][0-9]\' tests/mutants/pre-pr-gate.tsv -->\n')"
put "$d" tests/mutants/pre-pr-gate.tsv "$({ printf '# header\n# more\n'; for i in $(seq 1 285); do printf 'A%d\trow\n' "$i"; done; })"$'\n'
run "$ccl" --repo "$d"
check_status "A2(b): a stale matches claim -> exit 1" 1 "$STATUS"
check_contains "A2(b): MISMATCH 'gives 285'" "$OUT" "gives 285"

d="$(one_frag $'- 5–20 s <!-- claim: words x.md -->\n')"
put "$d" x.md $'a b c\n'
run "$ccl" --repo "$d"
check_status "A2(c): a re-derived kind on a range -> exit 1" 1 "$STATUS"
check_contains "A2(c): BADMARK names the non-integer claim" "$OUT" "BADMARK changelog.d/a.md:1: 5–20 — words on a non-integer claim"
d="$(one_frag $'- 5–20 s <!-- claim: hand install.sh waits 30 s, as of 2026-10-12 -->\n')"
run "$ccl" --repo "$d" --strict
check_status "A2(c): hand on a range, --strict -> exit 0 (no claim from the marker's own 30 or date)" 0 "$STATUS"
check_contains "A2(c): HAND" "$OUT" "HAND changelog.d/a.md:1: 5–20 — install.sh waits 30 s, as of 2026-10-12"
check_contains "A2(c): one claim, one hand" "$OUT" "changelog-claims: 1 claim(s): 0 ok, 0 mismatched, 1 hand, 0 unbound, 0 word, 0 bad marker(s)"

d="$(one_frag $'- 26 <!-- claim: matches \'^  [A-Z_]+$\' tests/lib.sh -->\n')"
put "$d" tests/lib.sh "$({ for i in $(seq 1 26); do printf '  VAR_%s\n' "$(printf '%s' "$i" | tr 0-9 A-J)"; done; printf '  lower\nother\n'; })"$'\n'
run "$ccl" --repo "$d" --strict
check_status "A2(d): a too-narrow definition that counts 26 -> exit 0" 0 "$STATUS"
check_contains "A2(d): the OK line carries the ERE" "$OUT" "OK changelog.d/a.md:1: 26 — matches '^  [A-Z_]+\$' tests/lib.sh = 26"

# --- A3: the must-pass samples --------------------------------------------------------------------------------
d="$(new_repo)"
put "$d" f.md "$(words_n 2983)"$'\n'
put "$d" l.md $'one\ntwo\nthree\n'
put "$d" m1.md $'ab\nab\ncd\n'
put "$d" m2.md $'ab\nxx\n'
put "$d" w.md $'one — two → three four\n'
frag "$d" a.md $'- 2,983 <!-- claim: words f.md -->\n- 3 lines <!-- claim: lines l.md -->\n- 3 <!-- claim: matches ab m1.md m2.md -->\n- 6 <!-- claim: words w.md -->\n'
run "$ccl" --repo "$d" --strict
check_status "A3: one correct bound claim per kind, --strict -> exit 0" 0 "$STATUS"
check_contains "A3: words 2,983 -> OK" "$OUT" "OK changelog.d/a.md:1: 2,983 — words f.md = 2983"
check_contains "A3: lines -> OK" "$OUT" "OK changelog.d/a.md:2: 3 — lines l.md = 3"
check_contains "A3: matches over two paths sums -> OK" "$OUT" "OK changelog.d/a.md:3: 3 — matches ab m1.md m2.md = 3"
check_contains "A3: the awk field count of ' — ' and ' → ' tokens (portable, unlike wc -w)" "$OUT" "OK changelog.d/a.md:4: 6 — words w.md = 6"
check_contains "A3: 4 ok" "$OUT" "changelog-claims: 4 claim(s): 4 ok, 0 mismatched, 0 hand, 0 unbound, 0 word, 0 bad marker(s)"

# --- A4: exclusions ---------------------------------------------------------------------------------------------
d="$(one_frag "$(printf '%s\n' \
  '- dir #810 and PR #622 at v0.16.0 on 2026-10-12 08:45Z: A13, S2-9, R1-4 exit 2, exits 0, step 5, steps 1, 2 and 4, slice 3, PR-1 of 3, UTF-8, bash 3.2, umask 022, mode 755, 755/644, (1) item, §10, sha 3b8b41c, line 56' \
  '- it kills 29 of the 46 and `sed -n 224,256p` stays code')")"
run "$ccl" --repo "$d"
check_eq "A4: exactly two claims over the whole input" "2" "$(count_of "$OUT" '^UNBOUND')"
check_contains "A4: 29 is a claim" "$OUT" "UNBOUND changelog.d/a.md:2: 29"
check_contains "A4: 46 is a claim" "$OUT" "UNBOUND changelog.d/a.md:2: 46"
check_contains "A4: nothing else was listed" "$OUT" "changelog-claims: 2 claim(s)"
d="$(one_frag "$(printf '%s\n' \
  '- X1 PR-1 of 3, PR-22' \
  '- X2 dir #12, #13, KB.34, H.5, https://example.com/a/b/12 end' \
  '- X3 v1.2.3, 1.2.3, git 2.39 and 2.40, zsh 5.9' \
  '- X4 2026-10-12T08:45:01Z, 8:45, the 3rd, 2nd, 21st' \
  '- X5 L232, B4a, deadbeef1, 3b8b41c9' \
  '- X6 Steps 1-4, Slices 2 to 5, phase 3, rounds 2 and 3, spec 810, lines 5, 6, turn 1, fd 3, items 2 or 3, legs 1, passes 2, part 4' \
  '- X7 exits 1, exit code 2, Return 3, status 4, exiting 5, exited 6' \
  '- X8 (2) (13) mode 644, umask 77, 644/755' \
  '1. item' \
  '- 2. dash item' \
  '  0. wrapped sentence')")"
run "$ccl" --repo "$d"
check_status "A4: the exclusion samples run clean" 0 "$STATUS"
check_contains "A4: the indented '0.' stays a claim (a wrapped sentence)" "$OUT" "UNBOUND changelog.d/a.md:11: 0"
check_eq "A4: one sample per X1-X8 leaves only that one claim" "1" "$(count_of "$OUT" '^UNBOUND')"
check_contains "A4: one claim in the summary" "$OUT" "changelog-claims: 1 claim(s)"
# A real claim in an excluded shape is missed — the recorded limit; a plain number is not.
d="$(one_frag $'- the lint reads 30 rows at 12% and ~3,000 of 1.5 k, 5ms, 3MB, 5k, 3,000-word and 45-second\n')"
run "$ccl" --repo "$d"
check_contains "A4: 30 is a claim" "$OUT" "UNBOUND changelog.d/a.md:1: 30 —"
check_contains "A4: 12% is a claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 12% —"
check_contains "A4: ~3,000 is a claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: ~3,000 —"
check_contains "A4: 1.5 is a claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 1.5 —"
check_contains "A4: 5ms is a claim with a suffix" "$OUT" "UNBOUND changelog.d/a.md:1: 5ms —"
check_contains "A4: 3MB is a claim with a suffix" "$OUT" "UNBOUND changelog.d/a.md:1: 3MB —"
check_contains "A4: 3,000-word is the integer claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 3,000-word —"
check_contains "A4: 45-second is the integer claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 45-second —"

# --- A5: not claims, not markers ----------------------------------------------------------------------------------
d="$(one_frag "$(printf '%s\n' \
  '- a `12 code files` span, and <!-- note 12 --> a comment, and [a link](docs/x-99.md) here' \
  '  ```' \
  '  34 inside a fence' \
  '  ```' \
  '- after the fence' )")"
run "$ccl" --repo "$d" --strict
check_status "A5: numbers in a code span, a comment, a link target and a fence -> exit 0" 0 "$STATUS"
check_contains "A5: no claims" "$OUT" "changelog-claims: 0 claim(s)"
d="$(one_frag $'- 5 files `<!-- claim: words a.md -->` here\n')"
run "$ccl" --repo "$d"
check_contains "A5: a marker in backticks is not a marker — the number stays UNBOUND" "$OUT" "UNBOUND changelog.d/a.md:1: 5"
d="$(one_frag $'- 7 <!-- claim: hand counted 7 of 9 on 2026-10-12 -->\n- 285 <!-- claim: matches \'^[A-Z][0-9]{2}\' t.tsv -->\n')"
put "$d" t.tsv "$({ for i in $(seq 1 285); do printf 'A%02d\n' $((i % 100)); done; })"$'\n'
run "$ccl" --repo "$d" --strict
check_status "A5: a hand as-of and an ERE's {2} are not claims — --strict -> exit 0" 0 "$STATUS"
check_contains "A5: exactly the two bound claims" "$OUT" "changelog-claims: 2 claim(s): 1 ok, 0 mismatched, 1 hand, 0 unbound, 0 word, 0 bad marker(s)"
d="$(one_frag $'- see `a b and 17 files and `c` here\n')"
run "$ccl" --repo "$d"
check_contains "A5: an odd-backtick line is not code-blanked — its number lists" "$OUT" "UNBOUND changelog.d/a.md:1: 17"
check_contains "A5: ...and the context shows the text that was not deleted" "$OUT" "17 files and"

# Review round 1: the code-span blanking never rewrites a marker's own text, a number glued to letters or
# digits is one token (not a stray head), a leading-dot decimal is not an integer, and the context keeps
# glued text glued.
d="$(one_frag $'- 2 <!-- claim: matches \'^`[a-z]`$\' t.txt -->\n')"
put "$d" t.txt $'`a`\n`b`\nzz\n'
run "$ccl" --repo "$d" --strict
check_status "R1: backticks inside a marker's ERE are data -> OK, exit 0" 0 "$STATUS"
check_contains "R1: ...and the OK line prints the ERE as written" "$OUT" "matches '^\`[a-z]\`\$' t.txt = 2"
d="$(one_frag $'- 2 <!-- claim: matches \'^`\' t.txt --> and `x`\n')"
put "$d" t.txt $'`a\n`b\nzz\n'
run "$ccl" --repo "$d"
check_contains "R2: an odd backtick count in a marker is a BADMARK, not a mangled end" "$OUT" "odd number of backticks"
d="$(one_frag $'- wait...5 more and `<!-- claim: words a.md -->` in code\n- see v1.2 and v10.4.1.7 here\n- 3 files `<!-- claim: words a.md -->` and a stray ` tick\n')"
run "$ccl" --repo "$d"
check_absent "R2: an ellipsis is not a leading-dot decimal" "$OUT" ".5 —"
check_contains "R2: a marker wholly inside a code span is no marker" "$OUT" "UNBOUND changelog.d/a.md:1: 5"
check_eq "R2: v1.2 and a four-part version are versions — no claim on that line" "" "$(grep ':2: ' <<< "$OUT" || true)"
check_contains "R2: a marker on an odd-backtick line is a BADMARK, never a silent bind" "$OUT" "BADMARK changelog.d/a.md:3: 3 — a marker on a line with an odd number of backticks"
d="$(one_frag $'- rev3.5 and 2v1.5 here\n')"
run "$ccl" --repo "$d"
check_contains "R2: 2v1.5 is one claim as written (not swallowed as a version, no stray tail)" "$OUT" "UNBOUND changelog.d/a.md:1: 2v1.5 —"
check_eq "R2: ...and rev3.5 is an identifier: that line has exactly one claim" "1" "$(count_of "$OUT" '^UNBOUND')"
d="$(one_frag $'- 1e5 and 12h30m and .5 and see a.sh:12 and 5/6 here\n')"
run "$ccl" --repo "$d"
check_contains "R1: 1e5 is one claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 1e5 —"
check_contains "R1: 12h30m is one claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: 12h30m —"
check_contains "R1: .5 is a decimal claim as written" "$OUT" "UNBOUND changelog.d/a.md:1: .5 —"
check_contains "R1: the context keeps a.sh:12 glued" "$OUT" "see a.sh:12"
check_contains "R1: the context keeps 5/6 glued" "$OUT" "5/6 here"
check_eq "R1: six claims (1e5, 12h30m, .5, 12, 5, 6), no stray head or tail" "6" "$(count_of "$OUT" '^UNBOUND')"
d="$(one_frag $'- 3 <!-- claim: hand it was defaced here -->\n')"
run "$ccl" --repo "$d"
check_contains "R1: an English hex-letter word is not a sha as-of" "$OUT" "without an as-of"
d="$(one_frag $'- 3 <!-- claim: hand see commit 3b8b41c for it -->\n')"
run "$ccl" --repo "$d" --strict
check_status "R1: a real commit sha is an as-of" 0 "$STATUS"
d="$(one_frag $'- 3 files\n')"
run "$ccl" --repo "$d" --section ''
check_status "R1: an empty --section -> exit 2" 2 "$STATUS"

# --- A6: BADMARK (exit 1 without --strict), each case separately --------------------------------------------------------
badmark() {   # badmark LABEL MARKER-TEXT [REASON-FRAGMENT]  (fixture: x.md, a.md present; 'sub' a symlink out)
  local label="$1" mk="$2" want="${3:-}" b
  b="$(new_repo)"
  put "$b" x.md $'a b c\n'
  put "$b" a.md $'a\n'
  ln -s "$scratch_cwd" "$b/sub"
  ln -s x.md "$b/link.md"
  frag "$b" a.md "$mk"
  run "$ccl" --repo "$b"
  check_status "A6: $label -> exit 1 without --strict" 1 "$STATUS"
  check_contains "A6: $label -> a BADMARK line" "$OUT" "BADMARK changelog.d/a.md:1:"
  [ -z "$want" ] || check_contains "A6: $label -> reason '$want'" "$OUT" "$want"
}
badmark "an unknown kind" $'- 3 <!-- claim: bogus x.md -->\n' "unknown kind"
badmark "an absolute path" $'- 3 <!-- claim: lines /etc/passwd -->\n'
badmark "a .. path" $'- 3 <!-- claim: lines ../x -->\n'
badmark "a missing file" $'- 3 <!-- claim: lines nope.md -->\n'
badmark "a symlink" $'- 3 <!-- claim: lines link.md -->\n'
badmark "a bad ERE" $'- 3 <!-- claim: matches \'([\' x.md -->\n'
badmark "an empty hand" $'- 3 <!-- claim: hand -->\n' "empty hand"
badmark "a hand without an as-of" $'- 3 <!-- claim: hand from a grep -->\n' "without an as-of"
badmark "a path through a symlinked directory outside the repo" $'- 3 <!-- claim: lines sub/x.md -->\n'
badmark "a re-derived kind on ~3,000" $'- ~3,000 <!-- claim: words x.md -->\n' "non-integer claim"
badmark "a re-derived kind on 12%" $'- 12% <!-- claim: lines x.md -->\n' "non-integer claim"
badmark "a marker before any number" $'- <!-- claim: words x.md --> then 5\n' "no unbound claim"
badmark "a second marker with nothing left to bind" $'- 4 <!-- claim: lines x.md --> <!-- claim: lines x.md -->\n' "no unbound claim"
badmark "a missing argument" $'- 3 <!-- claim: words -->\n' "missing argument"
badmark "an extra argument" $'- 3 <!-- claim: words x.md a.md -->\n' "extra argument"
badmark "an unclosed quote" $'- 3 <!-- claim: matches \'ab x.md -->\n' "unclosed quote"
badmark "no closing -->" $'- 3 <!-- claim: words x.md\n'
badmark "no colon after claim" $'- 3 <!-- claim words x.md -->\n'
badmark "a lookalike kind's case" $'- 3 <!-- claim: Words x.md -->\n' "unknown kind"
d="$(one_frag $'- 3 <!-- claim: bogus x.md -->\n')"
run "$ccl" --repo "$d" --strict
check_absent "A6: a claim whose marker is a BADMARK is not also UNBOUND" "$OUT" "UNBOUND"
d="$(one_frag $'- <!-- claim: words x.md -->\n')"
run "$ccl" --repo "$d"
check_contains "A6: a marker with no claim prints '-' as its claim" "$OUT" "BADMARK changelog.d/a.md:1: - — "
# A comment that merely mentions the word is not a marker (case-exact).
d="$(one_frag $'- 8 files <!-- Claim: it is a note -->\n')"
run "$ccl" --repo "$d"
check_status "A6: '<!-- Claim' (other case) is an ordinary comment" 0 "$STATUS"

# --- A7: marker text is never executed -------------------------------------------------------------------------------
d="$(new_repo)"
put "$d" a.md $'x\n'
frag "$d" a.md $'- 3 <!-- claim: matches \'$(touch PWNED)\' a.md -->\n- 4 <!-- claim: words $(touch PWNED) -->\n- 5 <!-- claim: hand `touch PWNED` on 2026-10-12 -->\n'
git -C "$d" add -A
git -C "$d" -c user.name=Test -c user.email=test@example.com commit -q -m fixture
run_in "$scratch_cwd" "$ccl" --repo "$d"
check_nofile "A7: no PWNED file in the fixture repo" "$d/PWNED"
check_nofile "A7: no PWNED file in the cwd" "$scratch_cwd/PWNED"
check_eq "A7: git status --porcelain is empty after the run" "" "$(git -C "$d" status --porcelain)"
check_contains "A7: the hostile ERE ran as an ERE (a clean mismatch, not a crash)" "$OUT" "MISMATCH changelog.d/a.md:1: 3"

# --- A8: spelled numbers ------------------------------------------------------------------------------------------------
d="$(one_frag $'- Four Fixer sessions ran, and Sixteen mutants survived; twenty-one too, but one is not listed\n')"
run "$ccl" --repo "$d" --strict
check_status "A8: only WORD lines, --strict -> exit 0" 0 "$STATUS"
check_contains "A8: Four is a WORD" "$OUT" "WORD changelog.d/a.md:1: Four —"
check_contains "A8: Sixteen is a WORD" "$OUT" "WORD changelog.d/a.md:1: Sixteen —"
check_contains "A8: 'twenty-one' gives one WORD (twenty)" "$OUT" "WORD changelog.d/a.md:1: twenty —"
check_eq "A8: three WORD lines in all ('one' is not listed)" "3" "$(count_of "$OUT" '^WORD')"
check_contains "A8: the summary counts them in the word field" "$OUT" "changelog-claims: 0 claim(s): 0 ok, 0 mismatched, 0 hand, 0 unbound, 3 word, 0 bad marker(s)"
d="$(one_frag $'- Four <!-- claim: hand x 2026-10-12 --> sessions\n')"
run "$ccl" --repo "$d"
check_status "A8: a marker after a spelled number -> exit 1" 1 "$STATUS"
check_contains "A8: ...it is a BADMARK (no claim to bind)" "$OUT" "BADMARK changelog.d/a.md:1: - — "

# --- A9: sections and arguments ---------------------------------------------------------------------------------------------
d="$(new_repo)"
chg "$d" $'# Changelog\n\n## [Unreleased]\n\n- unrel 111 thing\n\n## [1.0.0] — 2026-01-01\n\n- one section 222 thing\n\n  ```\n  444 fenced\n  ```\n\n### Sub\n\n- sub 555 thing\n\n## [0.9.0] — 2025-12-01\n\n- old 333 thing\n'
frag "$d" a.md $'- frag a 777\n'
frag "$d" b.md $'- frag b 888\n'
run "$ccl" --repo "$d" --section 1.0.0
check_status "A9: --section 1.0.0 -> exit 0" 0 "$STATUS"
check_contains "A9: --section reads its own body" "$OUT" "${cl}:9: 222"
check_contains "A9: ...including a ### sub-heading's text" "$OUT" "${cl}:17: 555"
check_absent "A9: ...a fenced number is not read" "$OUT" ": 444"
check_absent "A9: ...[Unreleased] is absent" "$OUT" ": 111"
check_absent "A9: ...an older section is absent" "$OUT" ": 333"
check_absent "A9: ...fragments are absent" "$OUT" "changelog.d/"
run "$ccl" --repo "$d"
check_contains "A9: the default reads fragment a" "$OUT" "changelog.d/a.md:1: 777"
check_contains "A9: ...fragment b" "$OUT" "changelog.d/b.md:1: 888"
check_contains "A9: ...and [Unreleased]'s body" "$OUT" "${cl}:5: 111"
check_absent "A9: ...not a released section" "$OUT" ": 222"
check_eq "A9: fragments come before [Unreleased] (file order)" "changelog.d/a.md:1:changelog.d/b.md:1:${cl}:5:" \
  "$(sed -E -n 's/^[A-Z]+ ([^ ]+:[0-9]+:) .*/\1/p' <<< "$OUT" | tr -d '\n')"
run "$ccl" --repo "$d" --fragment changelog.d/a.md
check_status "A9: --fragment reads one fragment -> exit 0" 0 "$STATUS"
check_contains "A9: --fragment: the named fragment" "$OUT" ": 777"
check_absent "A9: --fragment: another fragment's number is absent" "$OUT" ": 888"
check_absent "A9: --fragment: [Unreleased]'s number is absent" "$OUT" ": 111"
run "$ccl" --repo "$d" --fragment changelog.d/a.md --fragment changelog.d/b.md
check_contains "A9: --fragment is repeatable" "$OUT" ": 888"
for bad in "--section 9.9.9" "--section 1.2" "--section 1.0.0 --fragment changelog.d/a.md" "--fragment changelog.d/absent.md" "--fragment a.md" "--section"; do
  # shellcheck disable=SC2086  # the word list is the point
  run "$ccl" --repo "$d" $bad
  check_status "A9: '$bad' -> exit 2" 2 "$STATUS"
done
run_in "$scratch_cwd" "$ccl" --repo "$d" --section 1.0.0
from_scratch="$OUT"
run_in "$d" "$ccl" --repo "$d" --section 1.0.0
check_eq "A9: a run from a scratch cwd gives the same output as cwd = DIR" "$OUT" "$from_scratch"
OUT="$("$ccl" --repo "$d" --section 1.0.0 2>&1 <&-)"
check_eq "A9: with stdin closed the output is the same" "$from_scratch" "$OUT"
# CHANGELOG.md refusals, copied from the cut: an odd fence count, and an [Unreleased] count other than 1.
d="$(new_repo)"; chg "$d" $'## [Unreleased]\n\n- a 1\n\n  ```\n  x\n'
run "$ccl" --repo "$d"
check_status "A9: an odd number of fence markers in CHANGELOG.md -> exit 2" 2 "$STATUS"
d="$(new_repo)"; chg "$d" $'## [1.0.0] — 2026-01-01\n\n- a 1\n'
run "$ccl" --repo "$d"
check_status "A9: no ## [Unreleased] -> exit 2" 2 "$STATUS"
run "$ccl" --repo "$d" --section 1.0.0
check_status "A9: ...also in --section mode -> exit 2" 2 "$STATUS"
d="$(new_repo)"; chg "$d" $'## [Unreleased]\n\n## [Unreleased]\n\n- a 1\n'
run "$ccl" --repo "$d"
check_status "A9: two ## [Unreleased] -> exit 2" 2 "$STATUS"
d="$(new_repo)"; frag "$d" a.md $'- a 1\n\n  ```\n  x\n'
run "$ccl" --repo "$d"
check_status "A9: an odd fence count in a fragment -> exit 2" 2 "$STATUS"

# --- A9a: empty and missing inputs ----------------------------------------------------------------------------------------------
d="$(new_repo)"; chg "$d" $'# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2026-01-01\n\n- a thing\n'
run "$ccl" --repo "$d" --strict
check_status "A9a: no changelog.d/ and an empty [Unreleased] -> exit 0" 0 "$STATUS"
check_contains "A9a: ...0 claims" "$OUT" "changelog-claims: 0 claim(s)"
d="$(new_repo)"; frag "$d" a.md $'- only 12 here\n'
run "$ccl" --repo "$d"
check_status "A9a: no CHANGELOG.md, default mode -> exit 0" 0 "$STATUS"
check_contains "A9a: ...the fragments are read" "$OUT" "changelog.d/a.md:1: 12"
run "$ccl" --repo "$d" --section 1.0.0
check_status "A9a: no CHANGELOG.md, --section -> exit 2" 2 "$STATUS"
d="$(new_repo)"; frag "$d" a.md $'- gone 12\n'; frag "$d" b.md $'- kept 13\n'; rm "$d/changelog.d/a.md"
run "$ccl" --repo "$d"
check_status "A9a: a tracked fragment deleted from the working tree is skipped -> exit 0" 0 "$STATUS"
check_contains "A9a: ...the other fragment is read" "$OUT" ": 13"
check_absent "A9a: ...the deleted one is not" "$OUT" ": 12"
d="$(new_repo)"; frag "$d" a.md $'- 5 apples <!-- claim: hand counted on 2026-10-12 -->\n- 6 pears\n'
chg "$d" $'## [Unreleased]\n\n- 9 more\n'
before_status="$(git -C "$d" status --porcelain)"
run "$ccl" --repo "$d"; first="$OUT"
run "$ccl" --repo "$d"
check_eq "A9a: two runs on the same tree are byte-identical" "$first" "$OUT"
check_eq "A9a: the runs wrote nothing" "$before_status" "$(git -C "$d" status --porcelain)"

# --- A10: binding order ---------------------------------------------------------------------------------------------------------
d="$(new_repo)"; put "$d" x.md $'a b c\n'
frag "$d" a.md $'- 3 <!-- claim: words x.md --> of the 3 <!-- claim: words x.md -->\n- 3 of the 3 <!-- claim: words x.md -->\n'
run "$ccl" --repo "$d"
check_contains "A10: both markers bind both numbers" "$OUT" "changelog-claims: 4 claim(s): 3 ok, 0 mismatched, 0 hand, 1 unbound, 0 word, 0 bad marker(s)"
check_eq "A10: with one marker the nearer number (the second) is bound, the first stays UNBOUND" "UNBOUND OK" \
  "$(awk '/^[A-Z]+ changelog.d\/a.md:2: /{printf "%s%s", sep, $1; sep=" "}' <<< "$OUT")"

# --- dir #846: right boundaries on the exclusions, the --fragment path forms, a duplicated heading, glued units -----------------
# 846-1/3: a structure or status word followed by a number and then a COUNT unit or a change verb is a count,
# not a reference ("passes 12 tests"); a reference followed by a verb or punctuation stays excluded ("step 5 runs").
d="$(one_frag "$(printf '%s\n' '- the suite passes 12 tests' '- it returns 3 values' '- lines 120 changed' '- exit 2 files')")"
run "$ccl" --repo "$d"
check_contains "846-1: 'passes 12 tests' keeps the claim" "$OUT" "UNBOUND changelog.d/a.md:1: 12 —"
check_contains "846-1: 'returns 3 values' keeps the claim" "$OUT" "UNBOUND changelog.d/a.md:2: 3 —"
check_contains "846-3: 'lines 120 changed' keeps the claim" "$OUT" "UNBOUND changelog.d/a.md:3: 120 —"
check_contains "846-1: 'exit 2 files' keeps the claim" "$OUT" "UNBOUND changelog.d/a.md:4: 2 —"
check_eq "846-1: ...one claim per line, nothing else" "4" "$(count_of "$OUT" '^UNBOUND')"
d="$(one_frag $'- step 5 runs the gate; exit 0 with output; exits 2 on failure; phase 7 said so; line 56 now; steps 1, 2 and 4 are done; status 4 means no\n- item 3, round 2: and lines 5-9 in a.sh\n')"
run "$ccl" --repo "$d"
check_contains "846-1: references followed by a verb, a connective or punctuation stay excluded" "$OUT" "changelog-claims: 0 claim(s)"
d="$(one_frag $'- step 3 added a check\n- phase 2 changed\n- round 2 findings\n- step 5 times out\n- step 2 session\n- see step 4 line 56 of a.sh\n- slice 2 file x.sh\n- round 3 error path\n')"
run "$ccl" --repo "$d"
check_contains "846-1: ambiguous nouns and a change verb after a non-lines reference stay references" "$OUT" "changelog-claims: 0 claim(s)"
# 846-2: "top-10" / "over-100" carry a count (a count qualifier before the hyphen); other word-number shapes stay identifiers.
d="$(one_frag $'- A top-10 list, over-100 files, UTF-8 and PR-22 and SHA-256 and x86-64 and S2-9 and round-3 and exit-0 and Latin-1 and check-10\n')"
run "$ccl" --repo "$d"
check_contains "846-2: top-10 keeps its number" "$OUT" "UNBOUND changelog.d/a.md:1: 10 —"
check_contains "846-2: over-100 keeps its number" "$OUT" "UNBOUND changelog.d/a.md:1: 100 —"
check_eq "846-2: UTF-8, PR-22, SHA-256, x86-64, S2-9, round-3, exit-0, Latin-1 and check-10 stay identifiers" "2" "$(count_of "$OUT" '^UNBOUND')"
# 846-4: --fragment takes ./ and absolute paths under the repo; a path outside it or an unlisted one still exits 2.
d="$(new_repo)"; frag "$d" a.md $'- frag a 777\n'; frag "$d" b.md $'- frag b 888\n'
run "$ccl" --repo "$d" --fragment ./changelog.d/a.md
check_status "846-4: --fragment ./changelog.d/a.md -> exit 0" 0 "$STATUS"
check_contains "846-4: ...and reads that fragment" "$OUT" "changelog.d/a.md:1: 777"
run "$ccl" --repo "$d" --fragment "$d/changelog.d/a.md"
check_status "846-4: --fragment <absolute path under the repo> -> exit 0" 0 "$STATUS"
check_contains "846-4: ...and reads that fragment (labelled repo-relative)" "$OUT" "changelog.d/a.md:1: 777"
run "$ccl" --repo "$d" --fragment "$scratch_cwd/a.md"
check_status "846-4: an absolute path outside the repo -> exit 2" 2 "$STATUS"
run "$ccl" --repo "$d" --fragment ./changelog.d/../changelog.d/a.md
check_status "846-4: a path with a .. segment -> exit 2" 2 "$STATUS"
run "$ccl" --repo "$d" --fragment ./changelog.d/absent.md
check_status "846-4: a normalised path the reader does not list -> exit 2" 2 "$STATUS"
# 846-5: a duplicated version heading is refused, not half-scanned.
d="$(new_repo)"; chg "$d" $'## [Unreleased]\n\n## [1.0.0] — 2026-01-01\n\n- one 11\n\n## [1.0.0] — 2026-01-02\n\n- two 22\n'
run "$ccl" --repo "$d" --section 1.0.0
check_status "846-5: two '## [1.0.0]' headings -> exit 2" 2 "$STATUS"
check_contains "846-5: ...naming the duplicate" "$OUT" "2 '## [1.0.0]' headings"
# 846-6: a unit glued to a number is an integer claim a marker may bind; scale suffixes, %, ~, decimals and ranges stay non-integer.
d="$(new_repo)"; put "$d" f.md $'a\nb\n'
frag "$d" a.md $'- 2x faster <!-- claim: lines f.md -->\n- 40KB cap <!-- claim: lines f.md -->\n- 2ms <!-- claim: lines f.md -->\n- 5k <!-- claim: lines f.md -->\n- 12% <!-- claim: lines f.md -->\n'
run "$ccl" --repo "$d"
check_contains "846-6: '2x' binds as the integer 2 (OK)" "$OUT" "OK changelog.d/a.md:1: 2x — lines f.md = 2"
check_contains "846-6: '40KB' binds as the integer 40 (MISMATCH, not BADMARK)" "$OUT" "MISMATCH changelog.d/a.md:2: 40KB — lines f.md gives 2"
check_contains "846-6: '2ms' binds as the integer 2 (OK)" "$OUT" "OK changelog.d/a.md:3: 2ms — lines f.md = 2"
check_contains "846-6: '5k' (a scale suffix) stays a BADMARK" "$OUT" "BADMARK changelog.d/a.md:4: 5k — lines on a non-integer claim"
check_contains "846-6: '12%' stays a BADMARK" "$OUT" "BADMARK changelog.d/a.md:5: 12% — lines on a non-integer claim"
d="$(new_repo)"; put "$d" f.md $'a\n'
frag "$d" a.md $'- 0xff <!-- claim: lines f.md -->\n- 3D <!-- claim: lines f.md -->\n- 2FA <!-- claim: lines f.md -->\n'
run "$ccl" --repo "$d"
check_eq "846-6: letters that are not a known unit (0xff, 3D, 2FA) stay non-integer — three BADMARKs" "3" "$(count_of "$OUT" '^BADMARK')"
d="$(new_repo)"; frag "$d" a.md $'- three apples\n'
run "$ccl" --repo "$d" --fragment changelog.d/a.md --fragment ./changelog.d/a.md --fragment "$d/changelog.d/a.md"
check_contains "846-4: the same fragment named three ways is read once" "$OUT" "0 unbound, 1 word,"

# --- A11: the live leg — keel's own changelog text ---------------------------------------------------------------------------------
run "$ccl" --repo "$REPO_ROOT"
check_status "A11: the default mode over keel's own text exits 0 (no re-derived claim is stale)" 0 "$STATUS"
check_contains "A11: ...and prints a summary" "$OUT" "changelog-claims: "

# --- A12 (the tool's half): the reader's header names this tool -------------------------------------------------------------------
pin "A12: changelog-fragments.sh's header names changelog-claims.sh" \
  "$REPO_ROOT/tools/self/changelog-fragments.sh" 'changelog-claims.sh' \
  "expected the reader's header to name every reader of changelog.d/ (dir #810)"

summary
