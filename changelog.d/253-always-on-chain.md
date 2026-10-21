- `doctor` now resolves what each entrypoint actually loads, its whole import chain, and checks it (dir #253,
  slice 2). It reads imports with a line-based approximation of Claude Code's import grammar (four hops, each file once; no
  import inside a code span, fenced or indented code, an HTML comment or a quoted path), which can differ from what
  the harness loads: it can miss an import (one after a fence opened on a list-marker line, or one in inline formatting),
  read `@path#fragment` as a different path, flag an on-demand `@path` the harness would not import (inside an HTML
  block, a link reference definition or a blockquote), and over-count a file near the fourth hop. A clean `always-on
  chain` line is evidence, not proof, and a `G-ALWAYSON-ONDEMAND` on one of those constructs cannot be suppressed. `doctor --install` prints the global chain
  as one line (`always-on chain: N file(s), M bytes`) and fails closed: a context file it cannot read is a GAP,
  `G-ALWAYSON-UNREAD`. A Keel on-demand file imported into a chain is a GAP, `G-ALWAYSON-ONDEMAND` (the global
  chain under `--install`, the project's own chain in the per-project run). The WARNs are `W-ALWAYSON-DANGLING`
  (an import that resolves to nothing), `W-ALWAYSON-DEPTH` (a file past the fourth hop) and `W-ALWAYSON-TWICE`
  (a project `CLAUDE.md` the global entrypoint also imports). `W-ALWAYSON-BUDGET` warns when the global chain
  alone passes `KEEL_ALWAYS_ON_WARN_TOKENS` (default 8,000 tokens <!-- claim: hand the KEEL_ALWAYS_ON_WARN_TOKENS default in tools/doctor.sh, 2026-10-20 -->). `H-FOOTPRINT` now sums both chains, no
  longer only the `keel/CORE.md` import.
- `W-MANIFEST-DRIFT` now compares the install manifest's edit record with the context file (dir #253). It fires
  when the recorded import line or embedded KEEL-CORE block is gone from the file, and when any edit is recorded
  on a generator-owned file.
- [`docs/loading-and-cost.md`](/docs/loading-and-cost.md) gains "The always-on layers" (dir #253). It names the
  core, personal, project and on-demand layers and the one-file-one-slot rule, and lists what `doctor` checks.
- `doctor` no longer misreads a project under an exported `GIT_LITERAL_PATHSPECS`, `GIT_GLOB_PATHSPECS`,
  `GIT_NOGLOB_PATHSPECS` or `GIT_ICASE_PATHSPECS` (found in dir #253's review). It unsets all four before its
  first git call, the way it drops an inherited `GIT_DIR`. Before, any one of them made `git check-ignore` fail,
  so a gitignored `CLAUDE.md` raised a false `G-GITIGNORE-CONTEXT`.
