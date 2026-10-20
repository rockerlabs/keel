#!/usr/bin/env bash
# test_doctor_alwayson.sh — dir #253 slice S2 (docs/specs/253-always-on-delivery-contract.md B4-B9, B7b, B10a):
# doctor resolves what each entrypoint actually loads — its whole import chain, Claude Code's import grammar
# (B5) — and checks it: an on-demand Keel file in the chain is a GAP (B6), the footprint follows the chain
# (B7), the global chain has its own budget (B7b), dangling and too-deep imports are named and the count line
# fails closed (B8), a project file also in the global chain is named (B9), and the manifest's edit record is
# compared with the file (B4). Every check drives the doctor CLI in a tests/lib.sh sandbox, never the real home.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# A12's scratch checkout is a git repository the doctor's ls-files reads (Linux trap 1).
git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
doctor="$REPO_ROOT/tools/doctor.sh"
nomem="$SANDBOX/no-memory-dir"          # KEEL_MEMORY_DIR pointing at nothing: the memory checks stay silent
core_txt="$(sed -n '/^<!-- KEEL-CORE-BEGIN/,/^<!-- KEEL-CORE-END/p' "$REPO_ROOT/CORE.md")"

# inst NAME MODE — a fresh install (MODE: link | copy | codex) into $SANDBOX/NAME; prints the home.
inst() {
  local h="$SANDBOX/$1" flags=()
  mkdir -p "$h"
  case "$2" in link) flags=(--link) ;; codex) flags=(--codex) ;; esac
  "$install" ${flags[@]+"${flags[@]}"} --home "$h" --no-hooks >"$SANDBOX/$1.install.log" 2>&1 </dev/null \
    || echo "FATAL: install $2 into $h failed (see $SANDBOX/$1.install.log)" >&2
  printf '%s' "$h"
}
# dinst HOME [--codex] — doctor --install on HOME → OUT, STATUS
dinst() { local h="$1"; shift; run "$doctor" --install "$@" "$h"; }
# dproj PROJECT HOME [ENV…] — the per-project run with HOME as the global home → OUT, STATUS
dproj() { local p="$1" h="$2"; shift 2; run env "KEEL_HOME=$h" "KEEL_MEMORY_DIR=$nomem" "$@" "$doctor" "$p"; }
# proj [TEXT] — a clean project (git, ignored context) whose CLAUDE.md holds TEXT; prints its path
proj() {
  local d; d="$(new_repo)"
  printf '%s\n' "${1:-# a project}" > "$d/CLAUDE.md"
  printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
  printf '%s' "$d"
}
# fill FILE BYTES — FILE holds exactly BYTES bytes of plain text (no `@`)
fill() { mkdir -p "$(dirname "$1")"; head -c "$2" /dev/zero | tr '\0' 'x' > "$1"; }
# gen_file FILE [block] — a generator-owned entrypoint (B1's line-1 marker), with CORE.md's KEEL-CORE block when asked
gen_file() {
  {
    printf '%s\n' '<!-- KEEL-GENERATED — do NOT hand-edit: a regeneration overwrites this file.' \
      '     A stand-in generator header. -->' ''
    [ "${2:-}" = block ] && printf '%s\n' "$core_txt"
    printf '\npersonal layer text\n'
  } > "$1"
}
# idline ID — the lines of OUT carrying [ID] (empty when none)
idline() { match "$OUT" -F "[$1]" || true; }
# idcount ID — how many lines of OUT carry [ID]
idcount() { local l; l="$(idline "$1")"; if [ -z "$l" ]; then echo 0; else printf '%s\n' "$l" | wc -l | tr -d ' '; fi; }
# out_num SED_EXPR — the first capture SED_EXPR prints from OUT (empty when none)
out_num() { local v; v="$(sed -n "$1" <<<"$OUT")"; printf '%s' "${v%%$'\n'*}"; }
# chain_n / chain_bytes — N and M of B8's count line `always-on chain: N file(s), M bytes` (empty when absent)
chain_n()     { out_num 's/.*always-on chain: \([0-9][0-9]*\) file(s), [0-9][0-9]* bytes.*/\1/p'; }
chain_bytes() { out_num 's/.*always-on chain: [0-9][0-9]* file(s), \([0-9][0-9]*\) bytes.*/\1/p'; }
# fp_field NAME — the ~N figure H-FOOTPRINT prints for NAME (global | project), empty when absent
fp_field()    { out_num "s/.*$1 ~\\([0-9][0-9]*\\).*/\\1/p"; }
ge() { if [ -n "$2" ] && [ "$2" -ge "$3" ]; then pass "$1"; else fail "$1" "expected ≥ $3, got '${2}'"; fi; }
bytes_of() { wc -c < "$1" | tr -d ' '; }
no_alwayson() {  # no_alwayson LABEL — OUT carries no G-ALWAYSON-* and no W-ALWAYSON-* finding
  check_absent "$1: no G-ALWAYSON-*" "$OUT" "[G-ALWAYSON-"
  check_absent "$1: no W-ALWAYSON-*" "$OUT" "[W-ALWAYSON-"
}

# --- A11 (B4): the manifest's edit record vs the file -------------------------------------------------------
h="$(inst a11-link link)"
printf '# my own notes, no rails, no import\n' > "$h/CLAUDE.md"
dinst "$h"
check_contains "A11: import-line recorded, file has no import → W-MANIFEST-DRIFT" "$OUT" "[W-MANIFEST-DRIFT]"
check_contains "A11: the drift line names import-line" "$(idline W-MANIFEST-DRIFT)" "import-line"

h="$(inst a11-gen link)"
gen_file "$h/CLAUDE.md" block                       # this machine's state [E7]: a generated file, an import-line record
dinst "$h"
check_contains "A11: an edit record on a generated file → W-MANIFEST-DRIFT" "$OUT" "[W-MANIFEST-DRIFT]"
check_contains "A11: the drift line names the generated file" "$(idline W-MANIFEST-DRIFT)" "generated"
"$install" --link --home "$h" --no-hooks >/dev/null 2>&1 </dev/null    # S1: the re-run drops the record
dinst "$h"
check_absent "A11 negative: after the S1 re-run over a generated file, no W-MANIFEST-DRIFT" "$OUT" "[W-MANIFEST-DRIFT]"

h="$(inst a11-codex codex)"
gen_file "$h/AGENTS.md" block                       # ~/.codex's state [E25]: core-block recorded, the block still there
dinst "$h" --codex
check_contains "A11: --codex core-block record over a generated AGENTS.md with its block → W-MANIFEST-DRIFT (the third clause alone)" "$OUT" "[W-MANIFEST-DRIFT]"

h="$(inst a11-copy copy)"
awk '/^<!-- KEEL-CORE-BEGIN/{skip=1} !skip{print} /^<!-- KEEL-CORE-END/{skip=0}' "$h/CLAUDE.md" > "$h/CLAUDE.md.new" && mv "$h/CLAUDE.md.new" "$h/CLAUDE.md"
dinst "$h"
check_contains "A11: core-block recorded, block deleted by hand → W-MANIFEST-DRIFT" "$OUT" "[W-MANIFEST-DRIFT]"
check_contains "A11: the drift line names core-block" "$(idline W-MANIFEST-DRIFT)" "core-block"

# --- A12 (B6): an on-demand Keel file in the chain is a GAP ------------------------------------------------
h_ok="$(inst a12-healthy link)"
dinst "$h_ok"
check_absent "A12: the healthy linked home (keel/CORE.md import only) raises no G-ALWAYSON-*" "$OUT" "[G-ALWAYSON-"

h_gap="$(inst a12-link link)"
printf '\n@%s/keel/FRAMEWORK.md\n' "$h_gap" >> "$h_gap/CLAUDE.md"
dinst "$h_gap"
check_contains "A12: a linked home importing keel/FRAMEWORK.md → GAP G-ALWAYSON-ONDEMAND" "$OUT" "GAP  [G-ALWAYSON-ONDEMAND]"
check_status "A12: the GAP fails the audit" 1 "$STATUS"
check_contains "A12: the GAP names the file" "$(idline G-ALWAYSON-ONDEMAND)" "FRAMEWORK.md"

h="$(inst a12-copy copy)"
printf '\n@FRAMEWORK.md\n' >> "$h/CLAUDE.md"
dinst "$h"
check_contains "A12: a copy home importing @FRAMEWORK.md (a real file at the home root) → GAP (B6 (i))" "$OUT" "[G-ALWAYSON-ONDEMAND]"

mkdir -p "$SANDBOX/a12-realhome"; ln -s "$SANDBOX/a12-realhome" "$SANDBOX/a12-linkhome"
inst a12-linkhome copy >/dev/null
printf '\n@%s/FRAMEWORK.md\n' "$SANDBOX/a12-linkhome" >> "$SANDBOX/a12-linkhome/CLAUDE.md"
dinst "$SANDBOX/a12-linkhome"
check_contains "A12: the same copy home installed through a symlinked path → GAP (canonical roots)" "$OUT" "[G-ALWAYSON-ONDEMAND]"

# a hand-wired linked home, NO manifest, whose keel/ links point into another tree: only B6 (ii)'s parent-real path sees it
ta="$SANDBOX/a12-treeA-min"; mkdir -p "$ta"; cp "$REPO_ROOT/CORE.md" "$REPO_ROOT/FRAMEWORK.md" "$ta/"
h="$SANDBOX/a12-handwired"; mkdir -p "$h/keel"
ln -s "$ta/CORE.md" "$h/keel/CORE.md"; ln -s "$ta/FRAMEWORK.md" "$h/keel/FRAMEWORK.md"
printf '# hand-wired\n@%s/keel/CORE.md\n@%s/keel/FRAMEWORK.md\n' "$h" "$h" > "$h/CLAUDE.md"
dinst "$h"
check_contains "A12: a hand-wired no-manifest linked home importing keel/FRAMEWORK.md → GAP (B6 (ii))" "$OUT" "[G-ALWAYSON-ONDEMAND]"

# the per-project run beside a home whose GLOBAL chain has the GAP never repeats it
p="$(proj)"
dproj "$p" "$h_gap"
check_absent "A12: the per-project run does not repeat the global chain's GAP" "$OUT" "[G-ALWAYSON-"
p="$(proj "# a project
@$h_gap/CLAUDE.md")"
dproj "$p" "$h_gap"
check_absent "A12: a project importing the global context file stops at the global chain — its GAP is not repeated" "$OUT" "[G-ALWAYSON-"

# a linked home installed from scratch tree A (a git repository), its CLAUDE.md importing a shipped doc of A directly:
# audited by THIS checkout's doctor, so only B6 (iii) through the manifest's checkout= can see it
treeA="$SANDBOX/a12-treeA"
tracked_tree_copy "$treeA" || exit 1
git -C "$treeA" init -q && git -C "$treeA" add -A \
  && git -C "$treeA" -c user.name=t -c user.email=t@example.com commit -qm tree-a
h="$SANDBOX/a12-fromA"; mkdir -p "$h"
"$treeA/install.sh" --link --home "$h" --no-hooks >/dev/null 2>&1 </dev/null
printf '\n@%s/docs/loading-and-cost.md\n' "$treeA" >> "$h/CLAUDE.md"
dinst "$h"
check_contains "A12: a doc of the install's own checkout (checkout=), imported directly → GAP (B6 (iii))" "$OUT" "[G-ALWAYSON-ONDEMAND]"
pp="$(proj)"
for pv in GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS; do    # the caller's pathspec mode is not doctor's
  run env "$pv=1" "$doctor" --install "$h"
  check_contains "A12: … still a GAP under an exported $pv=1" "$OUT" "[G-ALWAYSON-ONDEMAND]"
  dproj "$pp" "$h" "$pv=1"
  check_absent "A12: … and a project's gitignored CLAUDE.md still reads as ignored under $pv=1" "$OUT" "[G-GITIGNORE-CONTEXT]"
done

h="$SANDBOX/a12-fromA-untracked"; mkdir -p "$h"
"$treeA/install.sh" --link --home "$h" --no-hooks >/dev/null 2>&1 </dev/null
printf 'my private notes\n' > "$treeA/my-untracked-notes.md"
printf 'a glob-shaped name\n' > "$treeA/CHANGELO[G].md"      # as a pathspec it would match the tracked CHANGELOG.md
printf '\n@%s/my-untracked-notes.md\n@%s/CHANGELO[G].md\n' "$treeA" "$treeA" >> "$h/CLAUDE.md"
dinst "$h"
check_absent "A12: an UNTRACKED file in the install's checkout is the adopter's → no G-ALWAYSON-*" "$OUT" "[G-ALWAYSON-"
check_eq "A12: the untracked files (one glob-shaped, read literally) are loaded and counted (4 files)" 4 "$(chain_n)"

p="$(proj "# a project
@$h_ok/CLAUDE.md")"
dproj "$p" "$h_ok"
check_absent "A12: a project importing the home's own context file (an edit record, not Keel-shipped) → no G-ALWAYSON-*" "$OUT" "[G-ALWAYSON-"

# --- A13 (B7): the footprint follows the chain ------------------------------------------------------------
h="$SANDBOX/a13-home"; mkdir -p "$h"
printf 'global\n@hop1.md\n' > "$h/CLAUDE.md"; printf 'hop one\n@hop2.md\n' > "$h/hop1.md"; fill "$h/hop2.md" 70000
p="$(proj)"
dproj "$p" "$h"
ge "A13: a 70,000-byte file two hops down is in the global figure" "$(fp_field global)" 17500
p="$(proj "# a project
@notes/big.md")"
fill "$p/notes/big.md" 70000
dproj "$p" "$SANDBOX/a13-empty-home"
ge "A13: a 70,000-byte note the project file imports is in the project figure" "$(fp_field project)" 17500

# --- A14 (B8): dangling, too deep, cycles ------------------------------------------------------------------
h="$(inst a14-cycle link)"
printf '\n@a.md\n@notes/missing.md\n' >> "$h/CLAUDE.md"
printf 'a\n@b.md\n' > "$h/a.md"; printf 'b\n@a.md\n' > "$h/b.md"
dinst "$h"
check_eq "A14: CLAUDE.md + keel/CORE.md + a.md ↔ b.md (a cycle) count each once: 4 files" 4 "$(chain_n)"
check_contains "A14: a missing path-shaped import → W-ALWAYSON-DANGLING (--install)" "$OUT" "[W-ALWAYSON-DANGLING]"
check_contains "A14: the dangling line names the import" "$(idline W-ALWAYSON-DANGLING)" "notes/missing.md"

h="$(inst a14-deep link)"
printf '\n@h1.md\n' >> "$h/CLAUDE.md"
for i in 1 2 3 4; do printf 'hop %s\n@h%s.md\n' "$i" "$((i + 1))" > "$h/h$i.md"; done
fill "$h/h5.md" 70000
dinst "$h"
check_eq "A14: CLAUDE.md → h1 → … → h5 plus keel/CORE.md: h5 is past hop 4, 6 files" 6 "$(chain_n)"
check_contains "A14: the hop-5 file → W-ALWAYSON-DEPTH" "$OUT" "[W-ALWAYSON-DEPTH]"
check_contains "A14: the depth line names h5.md" "$(idline W-ALWAYSON-DEPTH)" "h5.md"
expected=$(( $(bytes_of "$h/CLAUDE.md") + $(bytes_of "$REPO_ROOT/CORE.md") ))
for i in 1 2 3 4; do expected=$(( expected + $(bytes_of "$h/h$i.md") )); done
check_eq "A14: the hop-5 file's bytes are absent from the chain total" "$expected" "$(chain_bytes)"

h="$SANDBOX/a14-shapes"; mkdir -p "$h"
printf 'global\n@missing.md\n@notes/missing\n@missing.md\nAsk @Model, or check @main.\n' > "$h/CLAUDE.md"
dinst "$h"
check_eq "A14: @missing.md and @notes/missing each raise one W-ALWAYSON-DANGLING (a repeated import once); @Model / @main raise none" 2 "$(idcount W-ALWAYSON-DANGLING)"

h="$(inst a14-core-broken link)"
rm "$h/keel/CORE.md"
dinst "$h"
check_contains "A14: the context file's own broken core import is the rails check's GAP" "$OUT" "[G-RAILS-IMPORT-BROKEN]"
check_absent "A14: … and is not repeated as a W-ALWAYSON-DANGLING" "$OUT" "[W-ALWAYSON-DANGLING]"

h="$(inst a14-codex codex)"
printf '\n@extra.md\n@notes/missing.md\n' >> "$h/AGENTS.md"; fill "$h/extra.md" 70000
dinst "$h" --codex
check_eq "A14: an AGENTS.md entrypoint is a one-file chain — its imports are not followed (N = 1)" 1 "$(chain_n)"
check_absent "A14: … nor reported dangling" "$OUT" "[W-ALWAYSON-DANGLING]"

p="$(proj "# a project
@notes/missing.md")"
dproj "$p" "$h_ok"
check_contains "A14: a missing import in the project chain → W-ALWAYSON-DANGLING (per-project run)" "$OUT" "[W-ALWAYSON-DANGLING]"
check_absent "A14: the per-project run prints no count line" "$OUT" "always-on chain:"

# --- A15 (B5): the import grammar --------------------------------------------------------------------------
# One home holds every NEGATIVE sample: none may add a file to the chain or raise DANGLING. x.md, notes/x.md and a
# file literally named `x.md.` are 70,000 bytes each, so following any of them would show in N.
h="$SANDBOX/a15-neg"; mkdir -p "$h/notes"
fill "$h/x.md" 70000; fill "$h/notes/x.md" 70000; fill "$h/x.md." 70000
cat > "$h/CLAUDE.md" <<'EOF'
# negative samples — nothing here is an import
A code span: `@x.md` and a double one: `` @x.md ``.

```
@x.md
```

~~~
@x.md
~~~

Quoted: @"x.md" and @"dir name/x.md" and @"notes/x.md"
<!-- a multi-line header
@x.md
-->
Inline <!-- @x.md --> comment.
A bare @ alone.
Path-shaped with trailing punctuation: @notes/x.md, and @notes/x.md)
Trailing: @x.md. @x.md, @x.md; @x.md: @x.md) @x.md! @x.md] @x.md" @x.md'
Path-shaped trailing: @notes/x.md] @notes/x.md" @notes/x.md'
Not at a boundary: (@x.md) and name@x.md

    @x.md
EOF
dinst "$h"
check_eq "A15: no negative sample is followed (N = 1)" 1 "$(chain_n)"
check_absent "A15: no negative sample is reported dangling" "$OUT" "[W-ALWAYSON-DANGLING]"
# a15_neg LABEL LINE… — a home of its own whose CLAUDE.md is `global`, a blank line, then the LINEs: a sample that
# could leave a block open (a fence, a list) gets one, so a broken rule cannot hide the samples after it
a15_n=0
a15_neg() {
  local label="$1"; shift
  a15_n=$((a15_n + 1)); h="$SANDBOX/a15-neg-$a15_n"; mkdir -p "$h/notes"; fill "$h/x.md" 70000; fill "$h/notes/x.md" 70000
  printf '%s\n' global '' "$@" > "$h/CLAUDE.md"
  dinst "$h"
  check_eq "A15: $label (N = 1)" 1 "$(chain_n)"
  check_absent "A15: $label (nothing dangling)" "$OUT" "[W-ALWAYSON-DANGLING]"
}
a15_neg 'a heading, then an indented code block' '# A heading' '    @notes/x.md'
a15_neg 'a fence close, then an indented code block' '```' x '```' '    @notes/x.md'
a15_neg 'a closer indented 4 does not close a top-level fence' '```' x '    ```' '@x.md' '```'
a15_neg 'a closer at 6 does not close a fence opened at 3' '   ```' x '      ```' '@x.md' '   ```'
a15_neg 'a thematic break, then an indented code block' text '***' '    @notes/x.md'
a15_neg 'a setext = underline, then an indented code block' Title '=====' '    @notes/x.md'
a15_neg 'a setext -- underline, then an indented code block' Title '--' '    @notes/x.md'
a15_neg 'an HTML comment block, then an indented code block' '<!--' ' a comment block' '-->' '    @notes/x.md'
a15_neg 'an unindented thematic break ends a list' '- a list item' '***' '' '    @notes/x.md'
a15_neg 'an unindented fence ends a list' '- a list item' '```' x '```' '' '    @notes/x.md'

a15_pos() {  # a15_pos LABEL HOME EXPECTED_N — the home's chain counts EXPECTED_N files and ≥ 70,000 bytes, nothing dangling
  dinst "$2"
  check_eq "A15: $1 (N)" "$3" "$(chain_n)"
  ge "A15: $1 (its 70,000 bytes are counted)" "$(chain_bytes)" 70000
  check_absent "A15: $1 (nothing dangling)" "$OUT" "[W-ALWAYSON-DANGLING]"
}
h="$SANDBOX/a15-esc"; mkdir -p "$h"; fill "$h/dir name/y.md" 70000
printf 'global\n@dir\\ name/y.md\n' > "$h/CLAUDE.md"
a15_pos 'an escaped space (@dir\ name/y.md) is followed' "$h" 2
h="$SANDBOX/a15-tilde"; mkdir -p "$h"; fill "$HOME/a15-z.md" 70000
printf 'global\n@~/a15-z.md\n' > "$h/CLAUDE.md"
a15_pos '@~/ resolves under $HOME' "$h" 2
h="$SANDBOX/a15-nested"; mkdir -p "$h/sub"; printf 'nested\n@b.md\n' > "$h/sub/a.md"; fill "$h/sub/b.md" 70000
printf 'global\n@sub/a.md\n' > "$h/CLAUDE.md"
a15_pos 'a relative import inside a nested file resolves against that file (sub/b.md)' "$h" 3
h="$SANDBOX/a15-fence-mixed"; mkdir -p "$h"; fill "$h/y.md" 70000
printf 'global\n```\n~~~\n@notes/inside.md\n```\n@y.md\n' > "$h/CLAUDE.md"
a15_pos 'a ~~~ line inside a ``` fence neither closes it nor hides the import after it' "$h" 2
h="$SANDBOX/a15-indented-fence"; mkdir -p "$h"; fill "$h/y.md" 70000
printf 'global\n\n    ```\n@y.md\n' > "$h/CLAUDE.md"
a15_pos 'a ``` line in an indented code block opens no fence' "$h" 2
# a15_one LABEL LINE… — a home of its own whose CLAUDE.md is `global`, a blank line, then the LINEs, which import
# y.md (70,000 bytes) once: the sample decides N = 2 and the figure alone
a15_k=0
a15_one() {
  local label="$1"; shift
  a15_k=$((a15_k + 1)); h="$SANDBOX/a15-one-$a15_k"; mkdir -p "$h"; fill "$h/y.md" 70000
  printf '%s\n' global '' "$@" > "$h/CLAUDE.md"
  a15_pos "$label" "$h" 2
}
a15_one 'a longer closer closes a fence' '```' code '````' '@y.md'
a15_one 'a backtick in a backtick fence info string makes the line prose' '``` a`b' '@y.md'
a15_one 'a tab-indented ``` continues a paragraph, opening no fence' paragraph $'\t```' '@y.md'
a15_one 'seven # is no heading: a 4-space line continues it' '####### seven' '    @y.md'
a15_one '"= =" is no setext underline: a 4-space line continues the paragraph' Title '= =' '    @y.md'
a15_one 'a fence opened inside a list closes 3 past its own indent' '- item' '' '  ```' '  x' '    ```' '@y.md'
a15_one 'under a list item a bare - is an item, so a 4-space line continues it' '- item' - '    @y.md'
h="$SANDBOX/a15-symlinked"; mkdir -p "$h/real"
printf 'target\nRelative: @a.md\n' > "$h/real/target.md"; fill "$h/real/a.md" 70000
ln -s "$h/real/target.md" "$h/CLAUDE.md"
a15_pos 'a symlinked CLAUDE.md resolves @a.md against its TARGET directory (real/a.md)' "$h" 2

# --- A16 (B8): healthy homes, the false-GAP guard; an unreadable context file ------------------------------
for mode in link copy codex; do
  h="$(inst "a16-$mode" "$mode")"
  if [ "$mode" = codex ]; then dinst "$h" --codex; else dinst "$h"; fi
  check_status "A16: a fresh $mode home → doctor --install exits 0" 0 "$STATUS"
  no_alwayson "A16: fresh $mode home (--install)"
  check_absent "A16: fresh $mode home: no W-MANIFEST-DRIFT" "$OUT" "[W-MANIFEST-DRIFT]"
  ge "A16: fresh $mode home: the count line names N ≥ 1" "$(chain_n)" 1
  p="$(proj)"
  dproj "$p" "$h"
  check_status "A16: a project beside the fresh $mode home → the per-project run exits 0" 0 "$STATUS"
  no_alwayson "A16: project beside the fresh $mode home"
done
h="$h_ok"                                           # restored below, before A17 reads it again
chmod 000 "$h/CLAUDE.md"
dinst "$h"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "A16: an unreadable context file → GAP G-ALWAYSON-UNREAD" "$OUT" "GAP  [G-ALWAYSON-UNREAD]"
  check_absent "A16: an unreadable context file prints no count line" "$OUT" "always-on chain:"
fi
check_absent "A16: an unreadable context file never crashes doctor" "$OUT" "unbound variable"
chmod 644 "$h/CLAUDE.md"

# --- A17 (B9, B6 per project): one file, one slot ------------------------------------------------------------
p="$(proj)"
h="$SANDBOX/a17-home"; mkdir -p "$h"; printf 'global\n@%s/CLAUDE.md\n' "$p" > "$h/CLAUDE.md"
dproj "$p" "$h"
check_contains "A17: a project CLAUDE.md the global file imports → W-ALWAYSON-TWICE" "$OUT" "[W-ALWAYSON-TWICE]"
ln -s "$p" "$SANDBOX/a17-plink"
h="$SANDBOX/a17-home-link"; mkdir -p "$h"; printf 'global\n@%s/CLAUDE.md\n' "$SANDBOX/a17-plink" > "$h/CLAUDE.md"
dproj "$p" "$h"
check_contains "A17: the same project reached through a symlinked path → W-ALWAYSON-TWICE (real paths)" "$OUT" "[W-ALWAYSON-TWICE]"
p="$(proj "# a project
@$REPO_ROOT/FRAMEWORK.md")"
dproj "$p" "$h_ok"
check_contains "A17: a project file importing the checkout's FRAMEWORK.md → GAP G-ALWAYSON-ONDEMAND (per-project run)" "$OUT" "[G-ALWAYSON-ONDEMAND]"

# --- A18 (B10a, the registry, B10b's S2 clause): the contract in prose ----------------------------------------
lac="$REPO_ROOT/docs/loading-and-cost.md"
check_contains "A18: docs/loading-and-cost.md has '## The always-on layers'" "$(cat "$lac")" $'\n## The always-on layers\n'
layers="$(section_body '## The always-on layers' "$lac")"
for w in core personal project on-demand MEMORY.md '## Three tiers'; do
  check_contains "A18: the always-on layers section names '$w'" "$layers" "$w"
done
lnames="$(match "$layers" -nE '(^|[^A-Za-z0-9])L[0-2]p?([^A-Za-z0-9]|$)' || true)"
check_eq "A18: the section uses no L0/L1/L1p/L2 names" "" "$lnames"
registry="$(sed -n '1,/^set -euo pipefail/p' "$doctor")"
for id in G-ALWAYSON-ONDEMAND G-ALWAYSON-UNREAD W-ALWAYSON-DANGLING W-ALWAYSON-DEPTH W-ALWAYSON-TWICE W-ALWAYSON-BUDGET; do
  check_contains "A18: doctor's header registry lists $id" "$registry" "$id"
done
fp_entry="$(awk '/H-FOOTPRINT/{p=1} p{print} p&&/^#   [A-Z]+ /&&!/H-FOOTPRINT/{exit}' <<<"$registry" | flatten_ws)"
check_contains "A18: the registry's H-FOOTPRINT entry says the import chain is followed" "$fp_entry" "import chain"
adapting="$(section_body '## Generating your entrypoints yourself' "$REPO_ROOT/ADAPTING.md")"
check_contains "A18: ADAPTING.md's generator section names the W-ALWAYSON checks" "$adapting" "W-ALWAYSON"

# --- A18a (B7b): the always-on budget ---------------------------------------------------------------------
h="$(inst a18a link)"
fill "$SANDBOX/a18a-personal" 36000; { printf '\n'; cat "$SANDBOX/a18a-personal"; printf '\n'; } >> "$h/CLAUDE.md"
fig=$(( ($(bytes_of "$h/CLAUDE.md") + $(bytes_of "$REPO_ROOT/CORE.md")) / 4 ))
dinst "$h"
bl="$(idline W-ALWAYSON-BUDGET)"
check_contains "A18a: a global chain over 8,000 tokens → W-ALWAYSON-BUDGET" "$OUT" "WARN [W-ALWAYSON-BUDGET]"
check_contains "A18a: the budget line names the figure (the chain's bytes / 4)" "$bl" "~$fig tokens"
check_contains "A18a: the budget line names the 8000 budget" "$bl" "budget 8000"
largest="${bl#*largest: }"
if match "$largest" -q 'CLAUDE\.md.*keel/CORE\.md'; then pass "A18a: the largest files are CLAUDE.md, then keel/CORE.md"
else fail "A18a: the largest files are CLAUDE.md, then keel/CORE.md" "got: $largest"; fi
run env KEEL_ALWAYS_ON_WARN_TOKENS=20000 "$doctor" --install "$h"
check_absent "A18a: KEEL_ALWAYS_ON_WARN_TOKENS=20000 → no W-ALWAYSON-BUDGET" "$OUT" "[W-ALWAYSON-BUDGET]"
for bad in abc 99999999999999999999; do    # both sanitize paths (A18a)
  run env "KEEL_ALWAYS_ON_WARN_TOKENS=$bad" "$doctor" --install "$h"
  check_contains "A18a: KEEL_ALWAYS_ON_WARN_TOKENS=$bad falls back to the 8000 default" "$(idline W-ALWAYSON-BUDGET)" "budget 8000"
done
p="$(proj)"
dproj "$p" "$h"
check_absent "A18a: the per-project run beside that home raises no W-ALWAYSON-BUDGET (--install only)" "$OUT" "[W-ALWAYSON-BUDGET]"

summary
