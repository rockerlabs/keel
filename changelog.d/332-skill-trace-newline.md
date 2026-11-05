- The pre-PR gate's skill-trace hook no longer cuts a review call's arguments at their first newline (dir #332).
  The hook read its fields through a shell `read`, which stops at a newline, so an argument string such as
  `bogus` + newline + `high --fix` was traced as plain `bogus`, a leading newline before `high` was traced as
  unparsed, and the field after the arguments (the agent type that the subagent-stop leg checks) was lost with
  it. The flattening step that was meant to prevent this sat after the read and could never see a newline; it
  is replaced by a newline-to-space substitution in the jq expression, before the fields are joined. A newline
  is now an ordinary separator, and an unresolved argument string is traced whole, on one line. The gate
  suite's embedded-newline check, which passed with or without the fix, now has three fixtures that fail
  without it.
