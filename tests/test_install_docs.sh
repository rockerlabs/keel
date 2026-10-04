#!/usr/bin/env bash
# install.sh / uninstall.sh ship Keel's procedure docs (dir #650): every `docs/*.md` and
# `docs/drydock/*.md` lands beside the installed FRAMEWORK.md — `<home>/docs/` in copy and --codex
# mode, `<home>/keel/docs/` in linked mode — so the `docs/<x>.md` paths the rails, FRAMEWORK.md and
# the commands name resolve on an adopter's machine. Covers: placement per mode and its manifest
# records (A2–A4), the uninstall round trip incl. the manifest-less dry-run listing (A5/A5b), the
# ship set (A6), the class guard — every installed `docs/…` reference resolves, per mode, with a
# mutation proof (A7), never-clobber and the copy→linked stale line (A9), and the footprint prose
# (A12). Doctor (A8) lives in test_doctor_docs.sh; block currency (A13/A14) in
# test_core_block_currency.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# The alpine CI leg mounts the repo under another uid; install.sh runs git against it (CLAUDE.md
# "Linux-leg traps", trap 1).
git config --global --add safe.directory '*'

install="$REPO_ROOT/install.sh"
uninstall="$REPO_ROOT/uninstall.sh"

# The ship set as home-relative names under docs/: every docs/*.md plus docs/drydock/*.md (D1) —
# derived here from the live tree with the same two globs, never from a hard-coded list.
doc_rels=()
for f in "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/docs/drydock/*.md; do
  [ -f "$f" ] || continue
  doc_rels+=("${f#"$REPO_ROOT"/docs/}")
done
check_ne "the live tree ships a non-empty docs set (fixture sanity)" "${#doc_rels[@]}" 0
# The one doc every referenced-by-command class guard below mutates; chosen because the rails, the
# commands and FRAMEWORK.md all name it.
mut_doc="grooming.md"
case " ${doc_rels[*]} " in *" $mut_doc "*) pass "mutation target $mut_doc is in the ship set" ;; *) fail "mutation target $mut_doc is in the ship set" "not in docs/" ;; esac

# --- per-mode homes -----------------------------------------------------------------------------
c_home="$SANDBOX/copy-home";      mkdir -p "$c_home/docs"
printf 'my own doc, not Keel\n' > "$c_home/docs/mine.md"          # A5: planted BEFORE install
run "$install" --home "$c_home" --no-hooks
check_status "A2: copy install exits 0" 0 "$STATUS"
l_home="$SANDBOX/link-home"
run "$install" --link --home "$l_home" --no-hooks
check_status "A3: linked install exits 0" 0 "$STATUS"
n_home="$SANDBOX/nogit-home"
run "$install" --link --no-git --home "$n_home" --no-hooks
check_status "A3: linked --no-git install exits 0" 0 "$STATUS"
x_home="$SANDBOX/codex-home"
run "$install" --codex --home "$x_home" --no-hooks
check_status "A4: --codex install exits 0" 0 "$STATUS"

# --- A2 copy ------------------------------------------------------------------------------------
c_manifest="$c_home/.keel/install-manifest.claude"
for rel in "${doc_rels[@]}"; do
  dest="$c_home/docs/$rel"
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$REPO_ROOT/docs/$rel" "$dest"; then
    pass "A2: copy home has docs/$rel (regular file, cmp-identical)"
  else
    fail "A2: copy home has docs/$rel (regular file, cmp-identical)" "missing, a symlink, or differs: $dest"
  fi
  if grep -q "^artifact=file	docs/$rel	cksum:" "$c_manifest" 2>/dev/null; then
    pass "A2: manifest records artifact=file docs/$rel"
  else
    fail "A2: manifest records artifact=file docs/$rel" "no such line in $c_manifest"
  fi
done

# --- A3 linked (and --no-git) -------------------------------------------------------------------
for variant in link nogit; do
  if [ "$variant" = link ]; then h="$l_home"; else h="$n_home"; fi
  m="$h/.keel/install-manifest.claude"
  for rel in "${doc_rels[@]}"; do
    dest="$h/keel/docs/$rel"
    if [ -L "$dest" ] && [ "$dest" -ef "$REPO_ROOT/docs/$rel" ]; then
      pass "A3 ($variant): keel/docs/$rel is a symlink to the source"
    else
      fail "A3 ($variant): keel/docs/$rel is a symlink to the source" "missing, not a link, or wrong target: $dest"
    fi
    if grep -q "^artifact=symlink	keel/docs/$rel	" "$m" 2>/dev/null; then
      pass "A3 ($variant): manifest records artifact=symlink keel/docs/$rel"
    else
      fail "A3 ($variant): manifest records artifact=symlink keel/docs/$rel" "no such line in $m"
    fi
  done
done
check_nodir "A3: a linked home puts no docs/ at the root" "$l_home/docs"

# --- A4 codex -----------------------------------------------------------------------------------
for rel in "${doc_rels[@]}"; do
  dest="$x_home/docs/$rel"
  if [ -f "$dest" ] && cmp -s "$REPO_ROOT/docs/$rel" "$dest"; then
    pass "A4: codex home has docs/$rel"
  else
    fail "A4: codex home has docs/$rel" "missing or differs: $dest"
  fi
done
check_nodir "A4: --codex puts no docs under keel/" "$x_home/keel"

# --- A6 ship set --------------------------------------------------------------------------------
# (a) every tracked docs/*.md (git's pathspec `*` crosses `/`, so docs/drydock/ is included) is placed
# by A2. The not-shipped list is explicit and empty today; a new tracked doc subdir fails here until
# the ship set (or this list, with a reason) learns it.
not_shipped=" "
while IFS= read -r tracked; do
  [ -n "$tracked" ] || continue
  rel="${tracked#docs/}"
  case "$not_shipped" in *" $rel "*) continue ;; esac
  if [ -f "$c_home/docs/$rel" ]; then pass "A6a: tracked $tracked is placed"
  else fail "A6a: tracked $tracked is placed" "not at $c_home/docs/$rel — add it to the ship set or list it as not-shipped with why"; fi
done < <(git -C "$REPO_ROOT" ls-files -- 'docs/*.md')
# (b) an untracked docs/specs/zz.md and docs/zzsub/zz.md in the SOURCE root are not placed. Built in a
# scratch copy of the tree (never by writing into $REPO_ROOT); tar, not cp, for BSD/GNU portability.
src_copy="$SANDBOX/source-copy"
mkdir -p "$src_copy"
tar -C "$REPO_ROOT" --exclude=.git --exclude=.claude --exclude=private -cf - . | tar -C "$src_copy" -xf -
mkdir -p "$src_copy/docs/specs" "$src_copy/docs/zzsub"
printf 'maintainer-only design spec\n' > "$src_copy/docs/specs/zz.md"
printf 'an unlisted docs subdir\n'    > "$src_copy/docs/zzsub/zz.md"
b_home="$SANDBOX/shipset-home"
run "$src_copy/install.sh" --home "$b_home" --no-hooks
check_status "A6b: install from the extended source copy exits 0" 0 "$STATUS"
check_file   "A6b: the extended copy's real docs still land" "$b_home/docs/grooming.md"
check_nofile "A6b: docs/specs/zz.md is NOT placed" "$b_home/docs/specs/zz.md"
check_nofile "A6b: docs/zzsub/zz.md is NOT placed" "$b_home/docs/zzsub/zz.md"
check_nodir  "A6b: no docs/specs dir is created" "$b_home/docs/specs"
check_nodir  "A6b: no docs/zzsub dir is created" "$b_home/docs/zzsub"

# --- A7 class guard -----------------------------------------------------------------------------
# guard_home DOCS_DIR FRAMEWORK RAILS... — print one line per unresolved reference found in the
# installed Keel texts of a home: every `docs/<path>.md` token (anchored so `something/docs/x.md` is
# not read as a Keel doc, E12) in the rails, the installed FRAMEWORK.md, every installed command and
# every installed doc must exist at DOCS_DIR/<path>; and every relative `](x.md)` link inside an
# installed doc whose SOURCE target is a shipped doc, FRAMEWORK.md or PRINCIPLES.md must resolve from
# that doc's own installed dir (links to other repo files are E12's named gap, not checked).
# The command glob is `<home>/commands/*.md` — every shipped command, so a hidden companion command a
# later ticket adds (dir #670's polish-guide.md) is guarded the day it lands.
guard_home() {
  local docs_dir="$1" fw="$2" f tok rel d dd t base srcdir cand
  shift 2
  local texts=("$@" "$fw")
  for f in "$(dirname "$docs_dir")"/commands/*.md; do [ -f "$f" ] && texts+=("$f"); done
  for f in "$docs_dir"/*.md "$docs_dir"/drydock/*.md; do [ -f "$f" ] && texts+=("$f"); done
  for f in "${texts[@]}"; do
    [ -f "$f" ] || continue
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      [ -f "$docs_dir/${tok#docs/}" ] || echo "token docs/${tok#docs/} (in ${f#"$SANDBOX"/}) does not resolve at $docs_dir/${tok#docs/}"
    done < <(grep -o -E '(^|[^A-Za-z0-9_./-])(\.\./)?docs/[A-Za-z0-9_/-]+\.md' "$f" 2>/dev/null \
               | sed -E 's|^.*docs/|docs/|' | sort -u)
  done
  for f in "$docs_dir"/*.md "$docs_dir"/drydock/*.md; do
    [ -f "$f" ] || continue
    rel="${f#"$docs_dir"/}"; dd="$(dirname "$rel")"      # "." for a top-level doc, "drydock" below
    d="$(dirname "$f")"
    while IFS= read -r t; do
      case "$t" in *://*|"") continue ;; esac
      t="${t%%#*}"; [ -n "$t" ] || continue
      # Where does this link point IN THE SOURCE tree (one `../` at most — anything deeper is not a doc link)?
      case "$t" in
        ../../*) continue ;;
        ../*)  if [ "$dd" = . ]; then srcdir="$REPO_ROOT"; else srcdir="$REPO_ROOT/docs"; fi; base="${t#../}" ;;
        *)     if [ "$dd" = . ]; then srcdir="$REPO_ROOT/docs"; else srcdir="$REPO_ROOT/docs/$dd"; fi; base="$t" ;;
      esac
      cand="$srcdir/$base"
      # Only links whose source target is a shipped doc, FRAMEWORK.md or PRINCIPLES.md are in scope.
      case "$cand" in
        "$REPO_ROOT/FRAMEWORK.md"|"$REPO_ROOT/PRINCIPLES.md") ;;
        "$REPO_ROOT"/docs/*.md|"$REPO_ROOT"/docs/drydock/*.md) [ -f "$cand" ] || continue ;;
        *) continue ;;
      esac
      [ -e "$d/$t" ] || echo "link ]($t) in ${rel} does not resolve from $d"
    done < <(grep -o -E '\]\([^) ]+\.md[^) ]*\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
  done
}

guard_c="$(guard_home "$c_home/docs" "$c_home/FRAMEWORK.md" "$c_home/CLAUDE.md")"
check_eq "A7 copy: every installed docs/… reference resolves" "" "$guard_c"
guard_l="$(guard_home "$l_home/keel/docs" "$l_home/keel/FRAMEWORK.md" "$l_home/CLAUDE.md" "$l_home/keel/CORE.md")"
check_eq "A7 linked: every installed docs/… reference resolves" "" "$guard_l"
guard_n="$(guard_home "$n_home/keel/docs" "$n_home/keel/FRAMEWORK.md" "$n_home/CLAUDE.md" "$n_home/keel/CORE.md")"
check_eq "A7 linked --no-git: every installed docs/… reference resolves" "" "$guard_n"
guard_x="$(guard_home "$x_home/docs" "$x_home/FRAMEWORK.md" "$x_home/AGENTS.md")"
check_eq "A7 codex: every installed docs/… reference resolves" "" "$guard_x"
# The guard must have actually read something (a vacuous pass proves nothing): the copy home's rails
# name docs/ and the commands link ../docs/.
check_contains "A7 sanity: the copy home's rails name a docs/ path" "$(cat "$c_home/CLAUDE.md")" 'docs/'
check_contains "A7 sanity: an installed command carries a ../docs/ link" "$(cat "$c_home/commands/groom.md")" '../docs/'

# Mutation proof: delete one placed doc → the guard names it, in every mode.
mv "$c_home/docs/$mut_doc" "$c_home/docs/$mut_doc.held"
check_contains "A7 mutation (copy): a missing doc is named" "$(guard_home "$c_home/docs" "$c_home/FRAMEWORK.md" "$c_home/CLAUDE.md")" "docs/$mut_doc"
mv "$c_home/docs/$mut_doc.held" "$c_home/docs/$mut_doc"
rm "$l_home/keel/docs/$mut_doc"
check_contains "A7 mutation (linked): a missing doc is named" "$(guard_home "$l_home/keel/docs" "$l_home/keel/FRAMEWORK.md" "$l_home/CLAUDE.md" "$l_home/keel/CORE.md")" "docs/$mut_doc"
ln -s "$REPO_ROOT/docs/$mut_doc" "$l_home/keel/docs/$mut_doc"
mv "$x_home/docs/$mut_doc" "$x_home/docs/$mut_doc.held"
check_contains "A7 mutation (codex): a missing doc is named" "$(guard_home "$x_home/docs" "$x_home/FRAMEWORK.md" "$x_home/AGENTS.md")" "docs/$mut_doc"
mv "$x_home/docs/$mut_doc.held" "$x_home/docs/$mut_doc"
# A broken intra-doc link is named too (the link clause): drydock.md → drydock/auditor.md.
mv "$c_home/docs/drydock/auditor.md" "$c_home/docs/drydock/auditor.md.held"
check_contains "A7 mutation (link clause): a broken relative doc link is named" "$(guard_home "$c_home/docs" "$c_home/FRAMEWORK.md" "$c_home/CLAUDE.md")" "auditor.md"
mv "$c_home/docs/drydock/auditor.md.held" "$c_home/docs/drydock/auditor.md"

# --- A9 never-clobber + copy→linked migration ----------------------------------------------------
nc_home="$SANDBOX/noclobber-home"; mkdir -p "$nc_home/docs"
printf 'FOREIGN grooming content\n' > "$nc_home/docs/grooming.md"
run "$install" --home "$nc_home" --no-hooks
check_status "A9: install over a foreign docs/grooming.md exits 0" 0 "$STATUS"
check_eq "A9: the foreign docs/grooming.md survives byte-for-byte" "FOREIGN grooming content" "$(cat "$nc_home/docs/grooming.md")"
check_contains "A9: the refusal is reported, not silent" "$OUT" "grooming.md"
check_file "A9: the other docs still land" "$nc_home/docs/delegation.md"

# A copy home re-run with --link prints D6's stale-docs line and deletes nothing.
mig_home="$SANDBOX/migrate-home"
run "$install" --home "$mig_home" --no-hooks
check_status "A9: copy install for the migration fixture exits 0" 0 "$STATUS"
printf 'ADOPTER own doc\n' > "$mig_home/docs/reference-mine.md"
run "$install" --link --home "$mig_home" --no-hooks
check_status "A9: copy → --link re-run exits 0" 0 "$STATUS"
check_contains "A9: names the stale root docs/ left by the copy install" "$OUT" "docs/ copies remain from a copy-mode install"
check_contains "A9: carries the map re-point advice" "$OUT" "keel/FRAMEWORK.md"
check_file "A9: nothing deleted — a Keel doc copy is still there" "$mig_home/docs/grooming.md"
check_file "A9: nothing deleted — the adopter's own doc is still there" "$mig_home/docs/reference-mine.md"
check_link "A9: the linked docs landed beside it" "$mig_home/keel/docs/grooming.md"
# An adopter's OWN same-named file is not Keel's: a root docs/ holding only a foreign-content
# reference.md (not cmp-identical to the shipped one, never recorded) triggers NO stale line.
own_home="$SANDBOX/own-docs-home"; mkdir -p "$own_home/docs"
printf 'my project reference\n' > "$own_home/docs/reference.md"
run "$install" --link --home "$own_home" --no-hooks
check_status "A9: linked install over an adopter's own docs/reference.md exits 0" 0 "$STATUS"
check_absent "A9: a bare name match is not read as Keel's copy" "$OUT" "docs/ copies remain"

# --- A5 uninstall -------------------------------------------------------------------------------
# Copy home: Keel's docs go, the adopter's planted docs/mine.md and its dir stay.
check_file "A5 precondition: the copy home's docs are placed before uninstall" "$c_home/docs/grooming.md"
check_file "A5 precondition: so is a drydock doc" "$c_home/docs/drydock/auditor.md"
run "$uninstall" --home "$c_home" --yes
check_status "A5: copy uninstall exits 0" 0 "$STATUS"
check_nofile "A5: Keel's docs/grooming.md removed" "$c_home/docs/grooming.md"
check_nodir  "A5: Keel's docs/drydock/ pruned" "$c_home/docs/drydock"
check_file   "A5: the adopter's docs/mine.md survives" "$c_home/docs/mine.md"
check_dir    "A5: docs/ itself survives while it holds an adopter file" "$c_home/docs"
# Linked home: nothing left under keel/docs, keel/ itself gone.
check_link "A5 precondition: the linked home's docs are placed before uninstall" "$l_home/keel/docs/drydock/auditor.md"
run "$uninstall" --home "$l_home" --yes
check_status "A5: linked uninstall exits 0" 0 "$STATUS"
check_nodir "A5: linked keel/docs removed" "$l_home/keel/docs"
check_nodir "A5: linked keel/ removed" "$l_home/keel"
run "$uninstall" --home "$n_home" --yes
check_status "A5: linked --no-git uninstall exits 0" 0 "$STATUS"
check_nodir "A5: --no-git keel/docs removed" "$n_home/keel/docs"
check_file "A5 precondition: the codex home's docs are placed before uninstall" "$x_home/docs/grooming.md"
run "$uninstall" --codex --home "$x_home" --yes
check_status "A5: codex uninstall exits 0" 0 "$STATUS"
check_nodir "A5: codex docs/ removed (nothing of the adopter's in it)" "$x_home/docs"
# A copy home with no adopter file: the whole docs/ dir is pruned.
e_home="$SANDBOX/empty-prune-home"
run "$install" --home "$e_home" --no-hooks
run "$uninstall" --home "$e_home" --yes
check_nodir "A5: a copy home's docs/ is pruned when nothing of the adopter's is in it" "$e_home/docs"

# A5b — the manifest-less --dry-run heuristic listing (D7's second half): a copy home with its
# manifest removed lists each shipped doc the way it lists commands/<name>; a linked home's docs are
# covered by its `would remove  keel` line.
m_home="$SANDBOX/manifestless-home"
run "$install" --home "$m_home" --no-hooks
rm -f "$m_home/.keel/install-manifest.claude"
run "$uninstall" --home "$m_home" --dry-run
check_status "A5b: manifest-less dry-run exits 0" 0 "$STATUS"
check_contains "A5b: the listing is the heuristic one" "$OUT" "heuristic"
check_contains "A5b: names commands the known way (control)" "$OUT" "would remove  commands/groom.md"
for rel in "${doc_rels[@]}"; do
  check_contains "A5b: dry-run lists would remove docs/$rel" "$OUT" "would remove  docs/$rel"
done
ml_home="$SANDBOX/manifestless-link-home"
run "$install" --link --home "$ml_home" --no-hooks
rm -f "$ml_home/.keel/install-manifest.claude"
run "$uninstall" --home "$ml_home" --dry-run
check_contains "A5b: a linked home's docs are covered by its keel line" "$OUT" "would remove  keel"

# --- A12 footprint prose (D8) -------------------------------------------------------------------
gs="$(cat "$REPO_ROOT/docs/getting-started.md")"
check_contains "A12: getting-started §2 table has a docs/ row" "$gs" '`docs/`'
check_contains "A12: getting-started's core enumeration names the docs" "$gs" 'the commands, `docs/`'
ih="$(cat "$install")"
check_contains "A12: install.sh's header names the shipped docs" "$ih" "(FRAMEWORK, PRINCIPLES, the docs, the commands)"
run "$install" --help
check_contains "A12: --help names the docs in the footprint" "$OUT" "FRAMEWORK, PRINCIPLES, docs, commands"
check_contains "A12: --help states the one CLAUDE.md exception" "$OUT" "refresh only the rails block"
check_contains "A12: the linked keel/README.md heredoc lists docs/" "$(cat "$mig_home/keel/README.md")" '`docs/`'
check_contains "A12: the ephemeral summary's by-hand removal names docs/" "$ih" "(FRAMEWORK.md, PRINCIPLES.md, docs/, the"

summary
