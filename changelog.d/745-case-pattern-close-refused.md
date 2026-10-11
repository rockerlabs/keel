- **The pre-PR gate no longer lets a `case` pattern's `)` hide a bypassed push (dir #745, 0.16.0 audit S2-5).** The
  lexer read the first `)` of `${v:-$(case x in x) ;; esac; git push --no-verify)}` as the end of the `$(…)`, so the
  rest of the substitution was read in the enclosing context — as data inside the `${…}`, or as more arguments of the
  enclosing command (`echo $(case x in a) git push --no-verify;; esac)`) — and a push v0.15.0 denied was allowed. A
  `)` that closes a `$(…)` while a `case` is open in it (any pattern form: `a|b`, a newline before `in`, a nested
  `case`, a prefix such as `env` or `coproc` before the `case`), in any context, is now an unread part: if the text
  from there to the end mentions git or gh, the command is refused with the reason, as for the other parts the reader
  cannot settle. A push the reader still finds as a command of its own is denied as a push. The cost is a refusal for
  a harmless `$(case …)`, or a `$(…)` holding the words `case … in`, followed by a later git command in the same call
  (a rewrite in two Bash calls clears it). The double-quoted and heredoc-body shapes, which v0.15.0 also allowed, are
  covered by the same rule. Sixteen mutants of the new clauses join the reader's mutation list.
