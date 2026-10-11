- **The pre-PR gate no longer lets a `case` pattern's `)` hide a bypassed push (dir #745, 0.16.0 audit S2-5).** The
  lexer read the first `)` of `${v:-$(case x in x) ;; esac; git push --no-verify)}` as the end of the `$(…)` and the
  rest as data inside the `${…}`, so a push v0.15.0 denied was allowed. A `)` that closes a `$(…)` while a `case` is
  open in it (any pattern form: `a|b`, a newline before `in`, a nested `case`), inside double quotes, a `${…}` or an
  expanding heredoc body, is now an unread part: if the text from there to the end mentions git or gh, the command is
  refused with the reason, as for the other parts the reader cannot settle, so a harmless `"$(case …)"` followed by a
  later git command is refused too (a rewrite in two Bash calls clears it). The same fix covers the double-quoted and
  heredoc-body shapes, which v0.15.0 also allowed. A `case` in a `$(…)` at the top level of a command is read as
  before. Thirteen mutants of the new clauses join the reader's mutation list.
