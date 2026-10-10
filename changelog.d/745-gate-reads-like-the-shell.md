- **The pre-PR gate reads a command the way the shell will.** dir #745 (PR-2 of 3): one lexer reads the whole
  command — quotes glued to their words, `$(…)` and backticks (inside double quotes and expanding heredoc bodies
  too), heredocs owned by the context they were read in, arithmetic, redirections, comments, backslash-newline —
  and both rules share one skip set. Now caught: a partly quoted prefix assignment, the heredoc-commit closing
  line `)" && git push --no-verify`, a stray `<<`, a redirection or backslash-newline before the bypass, a quoted
  bypass argument, and `if`/`time`/`nohup`/`!`/`{`/`env -u` before `gh pr create`; multi-line quoted text that
  mentions a push is no longer denied. Where bash, zsh and busybox read a part differently and it mentions git or
  gh, the gate refuses the command and says why; if the reader itself fails it denies git/gh commands instead of
  allowing everything. `pre-pr-gate.sh lex` shows how a command was read; the header lists what stays unseen.
