- **`/polish` gains a mutation pass for a diff that adds or changes a filter, threshold, guard or exclusion rule.**
  dir #673 (a), slice 3 of spec 739: step 3 of `commands/polish.md` points at the guide's § Step 3, which mutates
  one clause of the changed rule at a time in a scratch clone, runs only the tests that pin it, and treats a
  survivor as a finding to fix or record, disclosed in step 10 and with no receipt of its own. A rule written
  only in prose never triggers it. The same slice dedupes the guide pointers of steps 8 and 9 to the short form,
  keeping `commands/polish.md` at 2,985 words. dir #673 (b), the delta-audit verifier's default mutation mandate,
  is not part of this change.
