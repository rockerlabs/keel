- **`secret-scan.sh` allow decisions read the right field, and `--tracked` reads every tracked file.** A hit is now
  a record whose label and content are kept apart: the inline `secret-scan:allow` marker and every ERE allowlist
  entry match the matched line only, so a file named `notes-secret-scan:allow.txt`, or `README.md:x.txt` under
  `path:README.md`, no longer exempts its own key, and a `path:` glob never exempts a commit or tag message
  (dir #741). Under `--range`, a `path:` glob exempts a blob only when every path the push introduces it at is
  exempt: the same key added at `fixtures/key.txt` and `src/real.txt` — in one commit, on two merged branches, or
  by an evil merge — is reported under the path that is not exempt (dir #742).
  A tracked file `--tracked` could not read from the working tree used to be skipped — with a WARN when it was
  unreadable, silently when it was deleted, replaced by a directory or hidden — and the run reported clean. It now
  scans that file's index copy, with a WARN naming why: unreadable, missing, not a regular file, or hidden by a
  directory that cannot be searched. A tracked file replaced by a symlink has its target string scanned, as
  before, and now its index copy too. An absent sparse-checkout (skip-worktree) entry is scanned from its index
  copy, counted in one summary line. A mid-merge (unmerged) file is read from its working file or symlink, if
  any, and from each of its stages' index copies; a hit they share prints once, and one WARN names the path.
  New causes of exit 2: git cannot read an index copy, or the working file or symlink of an unmerged path cannot
  be read — it is unreadable, or a directory that cannot be searched hides whether it exists (dir #746).
  Hit lines print in the same form as before. Upgrading: an ERE allowlist entry now matches the line's content
  only; use `path:` for a path.
