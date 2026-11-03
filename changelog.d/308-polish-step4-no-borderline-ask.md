- `/polish` step 4 no longer opens a depth dialog on a "borderline" diff (dir #308). The clause had no
  measurable predicate, so it silently re-opened the ask threshold dir #254 raised to `max`, `ultra` and `skip`:
  two `/polish` runs at the same level `high` on the same day, one asked and one did not, and both were correct
  under the text. The bullet is deleted from the core and the guide's § Step 4: `low`, `medium` and `high` always
  run automatically once sized, and only `max`, `ultra` and `skip` ask. An unclear bucket is still biased up one
  notch by the sizing step, so a diff near the `high`/`max` boundary can still reach `max` and ask through that
  existing rule; the release train's always-ask carve-out is unchanged. Text only: the gate's checks are
  untouched. A COPIED `polish.md` or `polish-guide.md` keeps the old clause until the adopter copies the shipped
  files over their own.
