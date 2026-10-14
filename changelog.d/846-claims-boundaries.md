- **Changelog claim lint: three more kinds of count are no longer excluded as references (dir #846).**
  `tools/self/changelog-claims.sh` now keeps a number that follows a structure or status word when a count
  unit or a change verb comes next (`passes 12 tests`, `lines 120 changed`), and a hyphenated count such as
  `top-10` or `over-100`; a glued unit (`2x`, `40KB`) leaves an integer claim that a marker can bind.
  `--fragment` accepts `./` and absolute paths under the repository, and `--section` refuses a duplicated
  version heading. `docs/release-audit.md` Phase 7 now says what to do with a number whose source is
  gitignored or moves after the cut: `claim: hand` with its as-of. Over the released sections the change adds
  one real claim and no noise.
