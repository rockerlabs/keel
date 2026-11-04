- `tools/keel-check-gate.sh`, the opt-in hard veto, now finds a `git commit` or `gh pr create` in any simple
  command (after `&&`, `;`, `|`, in a subshell, behind `VAR=val` or a wrapper, with `git -C`/`-c` options)
  instead of only as the literal start of the command, so those spellings no longer bypass it while a
  declared check is red. A command that only mentions the words, such as a `git log --grep` search or an
  `echo`, stays allowed. The header now states the residual (a verb built at run time, or a command substitution inside double quotes, is not recognised). The shell-aware walk runs only when the veto is on and a check is red, so a wired hook with the veto off pays nothing for it (dir #511).
