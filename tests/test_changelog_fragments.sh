#!/usr/bin/env bash
# tools/self/changelog-fragments.sh (dir #744 slice 1, B1-B4a): the one reader/linter of `changelog.d/`.
# Covers the reader (filename order, README skipped, one blank line between fragments, empty output
# without fragments), the --check lint (a good sample and a bad sample per rule, A2) and a live leg that
# lints keel's OWN fragments, so a malformed fragment fails `tests/run.sh` locally instead of at the cut.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

cf="$REPO_ROOT/tools/self/changelog-fragments.sh"
frag_dir_real="$REPO_ROOT/changelog.d"

# --- A1: the README exists and its FIRST line names the file and keel-self-maintenance (dir #68) -------
check_file "A1: changelog.d/README.md exists" "$frag_dir_real/README.md"
readme_first="$(head -n 1 "$frag_dir_real/README.md" 2>/dev/null || true)"
check_contains "A1: README's first line names the file" "$readme_first" "changelog.d/README.md"
check_contains "A1: README's first line carries keel-self-maintenance (dir #68)" "$readme_first" "keel-self-maintenance (dir #68)"

# --- --help / bad arguments ---------------------------------------------------------------------
run "$cf" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$cf" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$cf" --repo
check_status "--repo without a value -> exit 2" 2 "$STATUS"
run "$cf" --repo /no/such/dir
check_status "--repo naming a missing directory -> exit 2" 2 "$STATUS"

# mk_frags — a fresh git repo with an empty changelog.d/ (the reader lists TRACKED files, CI's view);
# callers add a tracked file with frag DIR NAME TEXT. mk_plain is the non-git case (a plain directory).
mk_frags() { local d; d="$(new_repo)"; mkdir -p "$d/changelog.d"; printf '%s' "$d"; }
frag() { printf '%s' "$3" > "$1/changelog.d/$2"; git -C "$1" add -f "changelog.d/$2"; }
mk_plain() { local d; d="$(mktemp -d "$SANDBOX/plain.XXXXXX")"; mkdir -p "$d/changelog.d"; printf '%s' "$d"; }

# --- the reader ---------------------------------------------------------------------------------
d="$(mktemp -d "$SANDBOX/nofrags.XXXXXX")"
run "$cf" --repo "$d"
check_status "no changelog.d/ -> exit 0" 0 "$STATUS"
check_eq "no changelog.d/ -> empty output" "" "$OUT"
run "$cf" --repo "$d" --check
check_status "no changelog.d/, --check -> exit 0" 0 "$STATUS"

d="$(mk_frags)"
run "$cf" --repo "$d"
check_status "empty changelog.d/ -> exit 0" 0 "$STATUS"
check_eq "empty changelog.d/ -> empty output" "" "$OUT"

d="$(mk_frags)"
# Created in REVERSE name order, so mtime order (z first) differs from filename order (a first).
frag "$d" 20-z.md $'- dir #20: zed\n'
sleep 1
frag "$d" 3-b.md $'- dir #3: bee\n  continued\n\n\n'
frag "$d" 100-a.md $'- dir #100: ay\n'
frag "$d" README.md $'readme text that is not a fragment\n'
run "$cf" --repo "$d"
check_status "reader -> exit 0" 0 "$STATUS"
want=$'- dir #100: ay\n\n- dir #20: zed\n\n- dir #3: bee\n  continued'
check_eq "reader: LC_ALL=C filename order, README skipped, exactly one blank line between fragments" "$want" "$OUT"

run "$cf" --repo "$d" --list
check_eq "--list: the same files, same order, README skipped" $'changelog.d/100-a.md\nchangelog.d/20-z.md\nchangelog.d/3-b.md' "$OUT"
run "$cf" --repo "$d" --check --list
check_status "--check with --list -> exit 2" 2 "$STATUS"

# Only TRACKED files count (CI's view): an untracked WIP file and a Finder .DS_Store are ignored.
printf -- '- untracked wip\n' > "$d/changelog.d/999-wip.md"
: > "$d/changelog.d/.DS_Store"
run "$cf" --repo "$d"
check_absent "an untracked fragment is not read" "$OUT" "untracked wip"
run "$cf" --repo "$d" --check
check_status "an untracked .DS_Store and WIP file do not fail the lint" 0 "$STATUS"
git -C "$d" add changelog.d/999-wip.md
run "$cf" --repo "$d"
check_contains "the same file once tracked IS read" "$OUT" "untracked wip"

# A directory that is not a git work tree is read directly, dotfiles ignored.
p="$(mk_plain)"
printf -- '- plain dir fragment\n' > "$p/changelog.d/1-p.md"
: > "$p/changelog.d/.DS_Store"
run "$cf" --repo "$p"
check_eq "non-git directory: read from the directory" "- plain dir fragment" "$OUT"
run "$cf" --repo "$p" --check
check_status "non-git directory: dotfiles are ignored by the lint -> exit 0" 0 "$STATUS"
mkdir "$p/changelog.d/sub.md"
run "$cf" --repo "$p" --check
check_contains "non-git directory: a subdirectory is named" "$OUT" "changelog.d/sub.md:1: not a regular file"

# A scratch copy of keel's tree inside another repo's work tree must not borrow the OUTER repo's listing.
outer="$(new_repo)"
mkdir -p "$outer/inner/changelog.d"
printf -- '- inner fragment\n' > "$outer/inner/changelog.d/1-i.md"
run "$cf" --repo "$outer/inner"
check_eq "a non-toplevel directory inside a repo is read as a plain directory" "- inner fragment" "$OUT"

# --- --check: a good sample and a bad sample per rule (A2) -------------------------------------
# lint NAME TEXT — a fresh dir holding one fragment; sets OUT/STATUS from --check.
lint() { local d; d="$(mk_frags)"; frag "$d" "$1" "$2"; run "$cf" --repo "$d" --check; }

lint 1-x.md $'- dir #1: x\n'
check_status "good: '- dir #1: x' passes" 0 "$STATUS"
check_eq "good: nothing printed" "" "$OUT"
lint 2-x.md $'- see [x](/docs/x.md)\n'
check_status "good: a root-anchored link passes" 0 "$STATUS"
lint 3-x.md $'- see [x](https://example.com/a) and [y](mailto:a@example.com)\n'
check_status "good: absolute URLs pass" 0 "$STATUS"
lint 4-x.md $'- first\n  indented continuation\n\n- second\n'
check_status "good: indented continuation lines and several bullets pass" 0 "$STATUS"
lint 5-x.md $'- a `[x](docs/x.md)` quoted in a code span is an example, not a link\n'
check_status "good: a file-relative link inside an inline code span passes" 0 "$STATUS"
lint 6-x.md $'- block:\n  ```\n  # a comment line\n  [x](docs/x.md)\n  ```\n'
check_status "good: an indented fenced block with '#' and a relative link passes" 0 "$STATUS"
lint just-a-slug.md $'- no ticket\n'
check_status "good: <slug>.md without a ticket passes" 0 "$STATUS"
lint 16-x.md $'- a regex `]([^a-z]|$)` in a code span is not a link\n'
check_status "good: a backticked regex like ]([^a-z]|\$) passes" 0 "$STATUS"

lint 7-x.md $'### Added\n- x\n'
check_status "bad: a heading line -> exit 1" 1 "$STATUS"
check_contains "bad: heading names file:line and the reason" "$OUT" "changelog.d/7-x.md:1:"
lint 8-x.md $'- ok\n### Added\n'
check_contains "bad: a '#' line later in the file is named at its line" "$OUT" "changelog.d/8-x.md:2: line starts with '#'"
lint 9-x.md $'- see [x](docs/x.md)\n'
check_status "bad: a file-relative link -> exit 1" 1 "$STATUS"
check_contains "bad: names the link target" "$OUT" "changelog.d/9-x.md:1: link target 'docs/x.md' is file-relative"
lint 17-x.md $'- see [x](#top)\n'
check_status "bad: a bare #anchor link -> exit 1" 1 "$STATUS"
check_contains "bad: the #anchor target named" "$OUT" "changelog.d/17-x.md:1: link target '#top'"
lint 18-x.md $'- see [x](ftp://h/x)\n'
check_status "bad: an ftp:// link -> exit 1" 1 "$STATUS"
lint 19-x.md $'- cites `dir #5` in backticks\n'
check_status "bad: a backtick-wrapped dir #N -> exit 1" 1 "$STATUS"
check_contains "bad: the backtick-wrapped dir #N is named" "$OUT" "changelog.d/19-x.md:1: dir #N inside backticks"
lint 10-x.md ''
check_status "bad: an empty file -> exit 1" 1 "$STATUS"
check_contains "bad: empty file named" "$OUT" "changelog.d/10-x.md:1: empty file"
lint 11-x.md $'\n  \n'
check_contains "bad: a whitespace-only file counts as empty" "$OUT" "empty file"
lint note.txt $'- x\n'
check_status "bad: changelog.d/note.txt -> exit 1" 1 "$STATUS"
check_contains "bad: a non-.md file named" "$OUT" "changelog.d/note.txt:1: not a .md file"
lint Bad_Name.md $'- x\n'
check_status "bad: changelog.d/Bad_Name.md -> exit 1" 1 "$STATUS"
check_contains "bad: a non-kebab name named" "$OUT" "changelog.d/Bad_Name.md:1: name is not kebab-case"
lint 12-x.md $'no bullet here\n'
check_contains "bad: first non-blank line is not a bullet" "$OUT" "changelog.d/12-x.md:1: first non-blank line must start with '- '"
lint 13-x.md $'- a\nunindented continuation\n'
check_contains "bad: an unindented continuation line" "$OUT" "changelog.d/13-x.md:2: continuation line must be indented"

# A tracked subdirectory file and a tracked dotfile inside changelog.d/ are named, never silently skipped.
d="$(mk_frags)"
mkdir -p "$d/changelog.d/sub"
printf -- '- nested\n' > "$d/changelog.d/sub/1-n.md"
: > "$d/changelog.d/.keep"
git -C "$d" add -f changelog.d/sub/1-n.md changelog.d/.keep
run "$cf" --repo "$d" --check
check_status "a tracked subdirectory file and dotfile in changelog.d/ -> exit 1" 1 "$STATUS"
check_contains "the subdirectory file named" "$OUT" "changelog.d/sub/1-n.md:1: file in a subdirectory"
check_contains "the dotfile named" "$OUT" "changelog.d/.keep:1: dotfile"

# README.md is never linted as a fragment (it may carry headings and relative-looking prose).
d="$(mk_frags)"
frag "$d" README.md $'# changelog.d\n\nNot a bullet.\n'
frag "$d" 14-x.md $'- ok\n'
run "$cf" --repo "$d" --check
check_status "README.md is exempt from the lint" 0 "$STATUS"

# Several failures in one run are all reported, one line each.
d="$(mk_frags)"
frag "$d" 15-x.md $'# h\n'
frag "$d" note.txt $'- x\n'
run "$cf" --repo "$d" --check
check_contains "failure in one file reported" "$OUT" "changelog.d/15-x.md:1:"
check_contains "failure in another file reported in the same run" "$OUT" "changelog.d/note.txt:1:"

# --- the live leg: keel's own fragments lint clean ----------------------------------------------
run "$cf" --repo "$REPO_ROOT" --check
check_status "keel's own changelog.d/ passes the lint" 0 "$STATUS"
check_eq "keel's own changelog.d/ lint prints nothing" "" "$OUT"


# --- A19 (static half): every test that pins a cite in the real changelog reads the fragments too --------
# The behavioural proof is a scratch-copy mutation (move the pinned line into changelog.d/, the pin stays
# green; move it nowhere, it goes red) run at review time; this guard keeps a sixth pin, or a regression of
# one of the five, from reading CHANGELOG.md alone. A new test that reads the real changelog for a cite
# belongs in this list.
for t in test_go_handoff test_secrets_doc test_vendor_review_doc test_rails_honesty test_drydock_doc; do
  if grep -qF 'changelog-fragments.sh' "$REPO_ROOT/tests/$t.sh"; then
    pass "A19: $t.sh reads CHANGELOG.md plus the fragment reader's output"
  else
    fail "A19: $t.sh reads CHANGELOG.md plus the fragment reader's output" "no changelog-fragments.sh in tests/$t.sh"
  fi
done


# --- B33 prose: the shipped polish guide states the exemption's changelog.d/ exception -------------------
pin "polish-guide Step 3: a changelog.d/ path is never exempt" "$REPO_ROOT/commands/polish-guide.md" \
  'under `changelog.d/` is never exempt either' "expected the one-sentence exception beside the basename-exemption rule (dir #744)"
pin "polish-guide Step 3: a changelog.d/ path takes the full-run branch" "$REPO_ROOT/commands/polish-guide.md" \
  'A `changelog.d/` path takes the full-run branch too' "expected the full-run sentence beside the dir #427 scoping rule (dir #744)"

summary
